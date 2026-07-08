"""
07_pyg_graph_construction.py

Converts the labeled RCA dataset into a PyTorch Geometric (PyG) Data object
ready for GNN training.

This is the bridge between raw telecom data and the GNN model.

Usage:
    pip install torch torch-geometric pandas
    python 07_pyg_graph_construction.py
"""

import json
import pandas as pd
import numpy as np
from pathlib import Path

# ============================================================
# If PyG is available, use real classes; otherwise mock for demo
# ============================================================
try:
    import torch
    from torch_geometric.data import HeteroData, Data
    HAS_PYG = True
except ImportError:
    HAS_PYG = False
    print("PyTorch Geometric not installed. Running in demo mode (prints structure only).")
    print("Install with: pip install torch torch-geometric\n")


def load_topology(path: str) -> dict:
    """Load network topology (graph structure)."""
    with open(path) as f:
        return json.load(f)


def load_node_features(path: str, timestamp: str) -> dict:
    """Load node features for a specific timestamp snapshot."""
    df = pd.read_csv(path, comment='#')
    df = df[df['timestamp'] == timestamp]
    features = {}
    for _, row in df.iterrows():
        features[row['node_id']] = [
            row['cpu_util'],
            row['memory_util'],
            row['connected_ues'],
            row['dl_throughput_mbps'],
            row['ul_throughput_mbps'],
            row['prb_util_dl'],
            row['prb_util_ul'],
            row['rrc_conn_success_rate'],
            row['erab_setup_success_rate'],
            row['handover_success_rate'],
            row['cqi_avg'],
            row['rsrp_avg_dbm'],
            row['packet_loss_rate'],
            row['latency_ms'],
            row['active_alarms'],
            row['interface_errors'],
            row['interface_discards'],
            row['temperature_c'],
            row['power_draw_w'],
        ]
    return features


def load_edge_features(path: str, timestamp: str) -> dict:
    """Load edge features for a specific timestamp snapshot."""
    df = pd.read_csv(path, comment='#')
    df = df[df['timestamp'] == timestamp]
    features = {}
    for _, row in df.iterrows():
        features[row['edge_id']] = [
            row['utilization'],
            row['latency_ms'],
            row['packet_loss_rate'],
            row['bandwidth_gbps'],
            row['crc_errors'],
            row['input_errors'],
            row['output_drops'],
            row['link_flaps'],
            1.0 if row['oper_status'] == 'up' else 0.0,
        ]
    return features


def load_labels(path: str) -> dict:
    """Load RCA ground truth labels."""
    with open(path) as f:
        return json.load(f)


def build_node_type_encoding(node_type: str) -> list:
    """One-hot encode node type."""
    types = ['gnodeb', 'enodeb', 'cell_site_gateway',
             'aggregation_router', 'core_router', 'upf', 'amf']
    encoding = [0.0] * len(types)
    if node_type in types:
        encoding[types.index(node_type)] = 1.0
    return encoding


def build_pyg_data(topology: dict, node_features: dict,
                   edge_features: dict, labels: dict,
                   fault_timestamp: str) -> dict:
    """
    Build a PyTorch Geometric Data object from telecom network data.

    Returns dict with all tensors (or builds actual PyG Data if available).
    """
    # === Step 1: Create node index mapping ===
    node_ids = [n['node_id'] for n in topology['nodes']]
    node_to_idx = {nid: i for i, nid in enumerate(node_ids)}
    num_nodes = len(node_ids)

    print(f"Building graph with {num_nodes} nodes, {len(topology['edges'])} edges")
    print(f"Fault timestamp: {fault_timestamp}\n")

    # === Step 2: Build node feature matrix X [num_nodes × num_features] ===
    # Features = [KPIs (19) + node_type_onehot (7) + domain_onehot (3)] = 29 features
    node_feature_list = []
    for node in topology['nodes']:
        nid = node['node_id']

        # KPI features (from PM counters / telemetry)
        kpi_features = node_features.get(nid, [0.0] * 19)

        # Structural features (from inventory)
        type_encoding = build_node_type_encoding(node['node_type'])

        # Domain encoding
        domain_map = {'RAN': [1, 0, 0], 'transport': [0, 1, 0], 'core': [0, 0, 1]}
        domain_encoding = domain_map.get(node.get('domain', ''), [0, 0, 0])

        # Combined feature vector
        combined = kpi_features + type_encoding + domain_encoding
        node_feature_list.append(combined)

    X = np.array(node_feature_list, dtype=np.float32)
    print(f"Node feature matrix X: shape {X.shape}")
    print(f"  Features: 19 KPIs + 7 node_type_onehot + 3 domain_onehot = {X.shape[1]}")

    # === Step 3: Build edge index [2 × num_edges] (undirected) ===
    edge_sources = []
    edge_targets = []
    edge_feature_list = []
    edge_type_list = []

    edge_type_map = {
        'fronthaul': 0, 'backhaul': 1, 'inter_agg': 2,
        'transport_core': 3, 'n3_interface': 4, 'n2_interface': 5,
        'xn_interface': 6
    }

    for edge in topology['edges']:
        src_idx = node_to_idx[edge['source']]
        tgt_idx = node_to_idx[edge['target']]

        # Add both directions (undirected graph)
        edge_sources.extend([src_idx, tgt_idx])
        edge_targets.extend([tgt_idx, src_idx])

        # Edge features
        eid = edge['edge_id']
        e_feat = edge_features.get(eid, [0.0] * 9)

        # Add edge type as additional feature
        etype = edge_type_map.get(edge.get('edge_type', ''), 0)
        e_feat_with_type = e_feat + [float(etype)]

        # Duplicate for both directions
        edge_feature_list.extend([e_feat_with_type, e_feat_with_type])
        edge_type_list.extend([etype, etype])

    edge_index = np.array([edge_sources, edge_targets], dtype=np.int64)
    E = np.array(edge_feature_list, dtype=np.float32)

    print(f"Edge index: shape {edge_index.shape} ({len(edge_sources)} directed edges)")
    print(f"Edge feature matrix E: shape {E.shape}")
    print(f"  Features: 9 KPIs + 1 edge_type = {E.shape[1]}")

    # === Step 4: Build label vectors ===
    node_labels = labels['node_labels']

    # Multi-class labels (5 classes)
    y_multiclass = []
    for nid in node_ids:
        if nid in node_labels:
            y_multiclass.append(node_labels[nid]['label_id'])
        else:
            y_multiclass.append(4)  # unaffected
    y_multiclass = np.array(y_multiclass, dtype=np.int64)

    # Binary root cause labels
    y_binary = np.array([1 if y == 0 else 0 for y in y_multiclass], dtype=np.int64)

    # Root cause ranking scores (regression)
    ranking_scores = labels['training_target_formats']['root_cause_ranking']['scores']
    y_ranking = np.array(
        [ranking_scores.get(nid, 0.0) for nid in node_ids],
        dtype=np.float32
    )

    print(f"\nLabels:")
    print(f"  Multi-class (5 classes): {y_multiclass}")
    print(f"  Binary (root cause):     {y_binary}")
    print(f"  Ranking scores:          {np.round(y_ranking, 2)}")

    print(f"\nNode label distribution:")
    label_names = ['root_cause', 'primary_symptom', 'secondary_symptom',
                   'collateral', 'unaffected']
    for i, name in enumerate(label_names):
        count = np.sum(y_multiclass == i)
        nodes_in_class = [nid for nid, lbl in zip(node_ids, y_multiclass) if lbl == i]
        print(f"  {i} ({name:20s}): {count} nodes → {nodes_in_class}")

    # === Step 5: Build PyG Data object (if available) ===
    if HAS_PYG:
        data = Data(
            x=torch.FloatTensor(X),
            edge_index=torch.LongTensor(edge_index),
            edge_attr=torch.FloatTensor(E),
            y=torch.LongTensor(y_multiclass),           # multi-class labels
            y_binary=torch.LongTensor(y_binary),         # binary root cause
            y_ranking=torch.FloatTensor(y_ranking),       # ranking scores
            num_nodes=num_nodes,
        )

        # Add metadata
        data.node_ids = node_ids
        data.incident_id = labels['incident_id']
        data.fault_timestamp = fault_timestamp

        print(f"\nPyG Data object created:")
        print(f"  {data}")
        print(f"  Is undirected: {data.is_undirected()}")
        print(f"  Has self-loops: {data.has_self_loops()}")
        print(f"  Avg degree: {data.num_edges / data.num_nodes:.1f}")

        return data
    else:
        result = {
            'x': X,
            'edge_index': edge_index,
            'edge_attr': E,
            'y_multiclass': y_multiclass,
            'y_binary': y_binary,
            'y_ranking': y_ranking,
            'node_ids': node_ids,
            'num_nodes': num_nodes,
            'num_edges': len(edge_sources),
            'incident_id': labels['incident_id'],
        }
        print(f"\nGraph dict created (install PyG for full Data object)")
        return result


def normalize_features(X: np.ndarray) -> np.ndarray:
    """Z-score normalization per feature (column-wise)."""
    mean = X.mean(axis=0)
    std = X.std(axis=0)
    std[std == 0] = 1.0  # avoid division by zero
    return (X - mean) / std


def main():
    base_dir = Path(__file__).parent.parent / 'samples'

    print("=" * 70)
    print("TELECOM GNN RCA — GRAPH CONSTRUCTION FROM LABELED DATASET")
    print("=" * 70)
    print()

    # Load all data
    topology = load_topology(base_dir / '01_topology.json')
    labels = load_labels(base_dir / '05_rca_labels.json')

    # Use fault-onset timestamp (when the cascading failure is happening)
    fault_timestamp = '2025-03-14T02:17:00Z'

    node_features = load_node_features(
        base_dir / '02_node_features_timeseries.csv', fault_timestamp
    )
    edge_features = load_edge_features(
        base_dir / '03_edge_features_timeseries.csv', fault_timestamp
    )

    # Build the graph
    data = build_pyg_data(topology, node_features, edge_features,
                          labels, fault_timestamp)

    print()
    print("=" * 70)
    print("GRAPH READY FOR GNN TRAINING")
    print("=" * 70)
    print()
    print("Next steps:")
    print("  1. Build a training set of 500-5000 such labeled incidents")
    print("  2. Create temporal snapshots (multiple timestamps per incident)")
    print("  3. Apply z-score normalization across the dataset")
    print("  4. Split into train/val/test (by incident, not by node)")
    print("  5. Train GCN/GAT/GraphSAGE for node classification")
    print("  6. Evaluate: Precision/Recall for root_cause class (class 0)")
    print()

    # === Demo: Show what a simple GCN forward pass looks like ===
    if HAS_PYG:
        print("=" * 70)
        print("DEMO: Simple GCN Forward Pass")
        print("=" * 70)

        import torch.nn.functional as F
        from torch_geometric.nn import GCNConv

        class SimpleRCAGNN(torch.nn.Module):
            """Minimal GCN for root cause classification."""
            def __init__(self, num_features, num_classes):
                super().__init__()
                self.conv1 = GCNConv(num_features, 64)
                self.conv2 = GCNConv(64, 32)
                self.classifier = torch.nn.Linear(32, num_classes)

            def forward(self, x, edge_index):
                # Message passing layer 1
                h = self.conv1(x, edge_index)
                h = F.relu(h)
                h = F.dropout(h, p=0.3, training=self.training)

                # Message passing layer 2
                h = self.conv2(h, edge_index)
                h = F.relu(h)

                # Node-level classification
                out = self.classifier(h)
                return out

        model = SimpleRCAGNN(
            num_features=data.x.shape[1],
            num_classes=5
        )

        print(f"\nModel architecture:")
        print(model)
        print(f"\nTotal parameters: {sum(p.numel() for p in model.parameters()):,}")

        # Forward pass (random weights — not trained)
        model.eval()
        with torch.no_grad():
            logits = model(data.x, data.edge_index)
            predictions = logits.argmax(dim=1)

        print(f"\nPredictions (untrained): {predictions.numpy()}")
        print(f"Ground truth:            {data.y.numpy()}")
        print(f"\n(Predictions are random — model needs training on 500+ incidents)")


if __name__ == '__main__':
    main()

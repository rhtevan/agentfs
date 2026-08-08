---
type: Postmortem
title: "Skills Inventory: Updates, Renames, and New Knowledge"
description: "Complete inventory of all skills created, updated, or renamed during this session"
tags: [agentfs, skills, inventory, changelog]
timestamp: 2026-08-08T12:09:00-04:00
---

# Skills Inventory: Updates, Renames, and New Knowledge

## Skills Updated

| Skill | Version Change | Key Updates |
|-------|:--------------:|-------------|
| `hosted-model-ctl` | 2.3 → **4.0** | Added rhel-ai host profile (4× L4); g30b-96k and g8b-128k models; InstructLab container support; port 8000→10000 for rhtevan-work; port 9000 for rhel-ai |
| `skupper-model-provider` | 1.0 → **4.0** | Complete rewrite: edge→interior mode; linux→podman platform; official container image; dual routing keys; inter-router links |
| `goose-skupper-provider` | 1.0 → **3.1** | Multi-port routing; defensive JSON template with warning; port 10000/9000 |
| `skill-index` | 2.3 → **2.4** | Fixed signals extraction bug (regex→state machine); 44/48→48/48 skills with signals |
| `agentfs-setup` | 3.8 → **3.9** | "Never improvise" routing rule; "Backup untracked files" guardrail; log.md comment removal |
| `skill-gen` | 1.5 → **1.6** | "Defensive file templates" writing guidance; `writes-files` schema field |

## Skills Renamed

| Old Name | New Name | Reason |
|----------|----------|--------|
| `local-model-ctl` | `hosted-model-ctl` | Reflects "self-hosted" models, not "local" — models run on remote GPU hosts |

## SSH Profile Created

| Profile | Host | User | Purpose |
|---------|------|------|---------|
| `rhel-ai` | `bastion.g7cpg.sandbox600.opentlc.com` | `cloud-user` | 4× NVIDIA L4 cloud instance for large model serving |

## AgentFS Guardrail Changes (Template v3.9)

| Guardrail | Change |
|-----------|--------|
| Signal Routing Rules | Added: "Never improvise when a skill exists" |
| #9 Checkpoints | Added: "Backup untracked files" for non-git-tracked files |
| #5 Filesystem Integrity | Changed log.md insertion anchor from HTML comment to heading |

## Model Registry (Final State)

### rhtevan-work (RTX A500, 4 GB VRAM)

| Alias | Model | Engine | Port |
|:-----:|-------|:------:|:----:|
| `g350m` | Granite 4.0 350M | vLLM FP16 | 10000 |
| `g1b` | Granite 4.0 1B | vLLM INT4 | 10000 |
| `g8b` | Granite 4.1 8B | llama.cpp Q4_K_M | 10000 |

### rhel-ai (4× NVIDIA L4, 92 GB VRAM)

| Alias | Model | Engine | TP | Port | Context |
|:-----:|-------|:------:|:--:|:----:|:-------:|
| `g30b-96k` | Granite 4.1 30B | vLLM BF16 | 4 | 9000 | 96K |
| `g8b-128k` | Granite 4.1 8B | vLLM BF16 | 2 | 9000 | 128K |

## Final Skupper VAN Architecture

```
localhost (interior, outbound only, podman, skrouterd 3.5.2)
  ├── 3× inter-router → 192.168.1.177:55671 (rhtevan-work)
  │     Listener :10000 ← model-api-rhtevan-work
  │
  └── 3× inter-router → 3.23.208.217:8000 (rhel-ai)
        Listener :9000  ← model-api-rhel-ai

Port 8000 unoccupied on localhost
```

## Candidate Knowledge for Future Extraction

| Topic | Type | Scope |
|-------|------|-------|
| Skupper V2 podman platform operational guide | Knowledge bundle | Cross-project |
| vLLM tensor parallelism VRAM calculator | Skill or reference doc | Cross-project |
| InstructLab container as vLLM runtime | Knowledge concept | Cross-project |
| Goose custom provider JSON schema | Reference doc | Cross-project |
| AWS security group port workarounds | Knowledge concept | Cross-project |

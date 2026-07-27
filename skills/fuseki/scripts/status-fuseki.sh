#!/usr/bin/env bash
# status-fuseki.sh — Check Fuseki installation and service status
# Usage: bash status-fuseki.sh
set -euo pipefail

JENA_LINK="${HOME}/.local/share/apache-jena"
FUSEKI_LINK="${HOME}/.local/share/apache-jena-fuseki"
DATA_DIR="${HOME}/.local/share/fuseki-data"
SERVICE="fuseki.service"
PORT=3030

echo "══════════════════════════════════════════════════════"
echo "  Fuseki Status"
echo "══════════════════════════════════════════════════════"
echo ""

# ── Installation ─────────────────────────────────────
echo "── Installation ──────────────────────────────────────"

if [[ -d "$JENA_LINK" ]]; then
    JENA_VER=$("${JENA_LINK}/bin/riot" --version 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || echo 'unknown')
    echo "  ✅ Jena CLI tools: ${JENA_VER} (${JENA_LINK})"
else
    echo "  ❌ Jena CLI tools: NOT INSTALLED"
fi

if [[ -d "$FUSEKI_LINK" ]]; then
    FUSEKI_VER=$("${FUSEKI_LINK}/fuseki-server" --version 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo 'unknown')
    echo "  ✅ Fuseki server:  ${FUSEKI_VER} (${FUSEKI_LINK})"
else
    echo "  ❌ Fuseki server:  NOT INSTALLED"
fi

if [[ -d "$DATA_DIR" ]]; then
    echo "  ✅ Data directory:  ${DATA_DIR}"
else
    echo "  ❌ Data directory:  NOT FOUND"
fi

echo ""

# ── Systemd Service ──────────────────────────────────
echo "── Systemd Service ───────────────────────────────────"

if ! systemctl --user cat "${SERVICE}" &>/dev/null; then
    echo "  ❌ Service unit not installed"
    echo "     Run 'fuseki setup' to install."
    echo ""
    echo "══════════════════════════════════════════════════════"
    exit 0
fi

SVC_STATE=$(systemctl --user is-active "${SERVICE}" 2>/dev/null || echo 'inactive')
SVC_ENABLED=$(systemctl --user is-enabled "${SERVICE}" 2>/dev/null || echo 'disabled')

if [[ "$SVC_STATE" == "active" ]]; then
    echo "  ✅ Service state:   ${SVC_STATE}"
else
    echo "  ⏹  Service state:   ${SVC_STATE}"
fi
echo "  📌 Service enabled: ${SVC_ENABLED}"

echo ""

# ── Endpoint Health ──────────────────────────────────
echo "── Endpoint Health ───────────────────────────────────"

if [[ "$SVC_STATE" != "active" ]]; then
    echo "  ⏹  Fuseki is not running"
    echo "     Run 'fuseki start' to start."
else
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 \
        "http://localhost:${PORT}/\$/ping" 2>/dev/null || echo "000")

    if [[ "$HTTP_CODE" == "200" ]]; then
        echo "  ✅ Endpoint:  http://localhost:${PORT} (HTTP ${HTTP_CODE})"
        echo "  ✅ Web UI:    http://localhost:${PORT}/#/"
    else
        echo "  ⚠️  Endpoint:  http://localhost:${PORT} (HTTP ${HTTP_CODE})"
    fi

    # List datasets
    echo ""
    echo "── Datasets ──────────────────────────────────────────"
    DATASETS_JSON=$(curl -s "http://localhost:${PORT}/\$/datasets" 2>/dev/null || echo '{}')
    DATASET_COUNT=$(echo "$DATASETS_JSON" | jq '.datasets | length' 2>/dev/null || echo '0')

    if [[ "$DATASET_COUNT" -gt 0 ]]; then
        echo "$DATASETS_JSON" | jq -r '.datasets[] | "  \(.\"ds.name\")  (state: \(.\"ds.state\"))"' 2>/dev/null
    else
        echo "  (none)"
    fi
fi

echo ""

# ── CLI Tools ────────────────────────────────────────
echo "── CLI Tools ─────────────────────────────────────────"

export PATH="${JENA_LINK}/bin:${FUSEKI_LINK}:${PATH}"

for tool in riot shacl arq rdfparse; do
    if command -v "$tool" &>/dev/null; then
        VER=$("$tool" --version 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo '?')
        printf '  ✅ %-12s %s\n' "$tool" "$VER"
    else
        printf '  ❌ %-12s NOT FOUND\n' "$tool"
    fi
done

echo ""
echo "══════════════════════════════════════════════════════"

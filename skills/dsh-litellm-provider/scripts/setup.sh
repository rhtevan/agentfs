#!/usr/bin/env bash
# setup.sh — Configure DSH with local LiteLLM proxy provider
# Usage: bash setup.sh
set -euo pipefail

DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
SETTINGS="$DSH_HOME/settings.yaml"
LITELLM_URL="http://127.0.0.1:4000"
PROVIDER_ID="litellm-vertex-ai"

# --- Preflight: check LiteLLM proxy ---
echo "🔍 Checking LiteLLM proxy at $LITELLM_URL..."
if ! curl -s --connect-timeout 3 "$LITELLM_URL/health" >/dev/null 2>&1; then
  echo "❌ LiteLLM proxy not reachable at $LITELLM_URL" >&2
  echo "   Start it first (see skill: litellm-vertex-ai-proxy)" >&2
  exit 1
fi
echo "✅ LiteLLM proxy is healthy"

# --- Discover models from LiteLLM ---
echo "🔍 Discovering models from LiteLLM..."
MODELS_JSON=$(curl -s "$LITELLM_URL/v1/models" 2>/dev/null)
if [[ -z "$MODELS_JSON" ]]; then
  echo "❌ Failed to query models from LiteLLM" >&2
  exit 1
fi

MODEL_IDS=$(echo "$MODELS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data.get('data', []):
    print(m['id'])
" 2>/dev/null)

if [[ -z "$MODEL_IDS" ]]; then
  echo "❌ No models found in LiteLLM response" >&2
  exit 1
fi

echo "   Found models:"
while IFS= read -r mid; do
  echo "     - $mid"
done <<< "$MODEL_IDS"

# --- Ensure DSH home exists ---
mkdir -p "$DSH_HOME"

# --- Backup existing settings ---
if [[ -f "$SETTINGS" ]]; then
  cp "$SETTINGS" "$SETTINGS.bak"
  echo "📋 Backed up existing settings to $SETTINGS.bak"
fi

# --- Build models YAML block ---
MODELS_YAML=""
while IFS= read -r mid; do
  MODELS_YAML+="        - id: $mid
          input: [text, image]
"
done <<< "$MODEL_IDS"

# --- Provider YAML block ---
# DSH requires a non-empty apiKeyEnv even for unauthenticated proxies.
# Set a dummy env var so DSH doesn't reject the provider.
export LITELLM_VERTEX_AI_API_KEY="sk-litellm-local-no-auth"

PROVIDER_BLOCK="    $PROVIDER_ID:
      apiKeyEnv: LITELLM_VERTEX_AI_API_KEY
      api: openai-completions
      baseURL: $LITELLM_URL/v1
      compat:
        supportsDeveloperRole: false
        maxTokensField: max_tokens
      models:
$MODELS_YAML"

# --- Write or merge into settings.yaml ---
if [[ ! -f "$SETTINGS" ]]; then
  # Fresh settings file
  cat > "$SETTINGS" << EOF
llm-pi-ai:
  providers:
$PROVIDER_BLOCK
EOF
  echo "✅ Created $SETTINGS with $PROVIDER_ID provider"

elif grep -q "$PROVIDER_ID:" "$SETTINGS" 2>/dev/null; then
  # Provider already exists — replace the block
  # Use Python for reliable YAML manipulation
  python3 << PYEOF
import sys

settings_path = "$SETTINGS"
provider_id = "$PROVIDER_ID"

# Read current file
with open(settings_path, 'r') as f:
    lines = f.readlines()

# Find and replace the provider block
new_lines = []
i = 0
skipping = False
while i < len(lines):
    line = lines[i]
    stripped = line.rstrip()
    # Detect start of our provider
    if stripped == f'    {provider_id}:':
        skipping = True
        i += 1
        continue
    # If skipping, continue until we hit another provider or end of providers
    if skipping:
        # Another provider at same indent level or section end
        if stripped and not stripped.startswith('      ') and not stripped.startswith('        '):
            skipping = False
            # Don't skip this line — fall through
        else:
            i += 1
            continue
    new_lines.append(line)
    i += 1

# Insert new provider block before the end of providers section
# Find where providers: is and insert after its children
provider_yaml = """$PROVIDER_BLOCK"""

# Find insertion point (after 'providers:' line)
insert_idx = None
for idx, line in enumerate(new_lines):
    if line.strip() == 'providers:':
        insert_idx = idx + 1
        break

if insert_idx is not None:
    for pline in provider_yaml.strip().split('\n'):
        new_lines.insert(insert_idx, pline + '\n')
        insert_idx += 1

with open(settings_path, 'w') as f:
    f.writelines(new_lines)

print(f'✅ Updated {provider_id} provider in {settings_path}')
PYEOF

else
  # settings.yaml exists but no provider — append
  if grep -q 'llm-pi-ai:' "$SETTINGS" 2>/dev/null; then
    if grep -q '  providers:' "$SETTINGS" 2>/dev/null; then
      # Append provider under existing providers:
      python3 << PYEOF
settings_path = "$SETTINGS"
provider_yaml = """$PROVIDER_BLOCK"""

with open(settings_path, 'r') as f:
    content = f.read()

# Find 'providers:' and insert after it
idx = content.find('  providers:\n')
if idx >= 0:
    insert_at = idx + len('  providers:\n')
    content = content[:insert_at] + provider_yaml + '\n' + content[insert_at:]

with open(settings_path, 'w') as f:
    f.write(content)

print(f'✅ Added provider to existing settings')
PYEOF
    else
      # llm-pi-ai exists but no providers section
      cat >> "$SETTINGS" << EOF
  providers:
$PROVIDER_BLOCK
EOF
      echo "✅ Added providers section to $SETTINGS"
    fi
  else
    # No llm-pi-ai section at all
    cat >> "$SETTINGS" << EOF

llm-pi-ai:
  providers:
$PROVIDER_BLOCK
EOF
    echo "✅ Added llm-pi-ai section to $SETTINGS"
  fi
fi

echo ""
echo "🎉 DSH configured with LiteLLM provider ($PROVIDER_ID)"
echo "   Models: $(echo "$MODEL_IDS" | tr '\n' ', ' | sed 's/,$//')"
echo "   Settings: $SETTINGS"
echo "   Next: launch DSH and check Settings → Models"

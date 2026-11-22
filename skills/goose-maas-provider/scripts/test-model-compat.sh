#!/usr/bin/env bash
# test-model-compat.sh — Test whether MaaS models can drive Goose tool calls
#
# Runs a real 2-step tool chain over STREAMING (as Goose does):
#   "run `echo one` with shell, then read /etc/hostname with read_file,
#    then answer with both results" — tool results are simulated locally.
# Nothing is executed on this machine.
#
# Usage: test-model-compat.sh [--url URL] [--key KEY] [--model MODEL | --all] [--runs N]
#
#   --url    default: base_url of custom_maas.json, else the RHDP MaaS URL
#   --key    discouraged (visible in ps/history). Without it the key is read
#            from GNOME Keyring (CUSTOM_MAAS_API_KEY) and handed over via a
#            0600 header file. The key is never printed.
#   --model  default: providers.custom_maas.model, else llama-scout-17b
#   --all    test every model from <url>/v1/models
#   --runs   attempts per model (default 1); verdict = worst run
# Env: GOOSE_CONFIG_DIR (default ~/.config/goose)
#
# Output: human table plus one machine line per model:
#   RESULT <model> <PASS|NO_TOOLS|FLAKY|ERROR>
#     PASS     — real tool_calls for both steps, final answer uses both results
#     NO_TOOLS — model never emits tool_calls (cannot drive Goose)
#     FLAKY    — some tool calls, but stopped early or wrote a tool call as text
#     ERROR    — HTTP/API error
#
# Exit codes (worst model wins): 0 all PASS · 1 any NO_TOOLS · 5 any FLAKY
#                                2 error/no key/usage · 3 keyring locked
#
# Note: reasoning_content alone is NOT a failure on goose >= 1.60 (the
# v1.41 "tool calls dropped after reasoning" behaviour is gone).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-keyring.sh"

GOOSE_CONFIG_DIR="${GOOSE_CONFIG_DIR:-$HOME/.config/goose}"
MAAS_URL=""; MAAS_KEY=""; MODEL=""; ALL=false; RUNS=1

usage() { echo "Usage: test-model-compat.sh [--url URL] [--key KEY] [--model MODEL | --all] [--runs N]" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)   MAAS_URL="${2:?--url needs a value}"; shift 2 ;;
    --key)   MAAS_KEY="${2:?--key needs a value}"; shift 2 ;;
    --model) MODEL="${2:?--model needs a value}"; shift 2 ;;
    --all)   ALL=true; shift ;;
    --runs)  RUNS="${2:?--runs needs a value}"; shift 2 ;;
    *) usage ;;
  esac
done
[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || usage
$ALL && [[ -n "$MODEL" ]] && usage

if [[ -z "$MAAS_URL" ]]; then
  MAAS_URL=$(jq -r '.base_url // empty' "$GOOSE_CONFIG_DIR/custom_providers/custom_maas.json" 2>/dev/null || true)
  MAAS_URL="${MAAS_URL:-https://maas-rhdp.apps.maas.redhatworkshops.io}"
fi
MAAS_URL="${MAAS_URL%/}"

if ! $ALL && [[ -z "$MODEL" ]]; then
  MODEL=$(CFG="$GOOSE_CONFIG_DIR/config.yaml" python3 -c '
import os, yaml
try:
    c = yaml.safe_load(open(os.environ["CFG"])) or {}
    print(((c.get("providers") or {}).get("custom_maas") or {}).get("model") or "")
except Exception:
    print("")' 2>/dev/null || true)
  MODEL="${MODEL:-llama-scout-17b}"
fi

if [[ -z "$MAAS_KEY" ]]; then
  rc=0; MAAS_KEY=$(keyring_get CUSTOM_MAAS_API_KEY) || rc=$?
  if [[ $rc -ne 0 ]]; then
    keyring_explain "$rc" CUSTOM_MAAS_API_KEY
    [[ $rc -eq 3 ]] && exit 3
    exit 2
  fi
fi
HDR=$(auth_header_file "$MAAS_KEY"); trap 'rm -f "$HDR"' EXIT
unset MAAS_KEY

echo "Model Tool-Call Test"
echo "════════════════════"
echo "Endpoint: $MAAS_URL"
echo "Runs:     $RUNS per model"
echo ""

rc=0
HDR="$HDR" URL="$MAAS_URL" MODEL="$MODEL" ALL="$ALL" RUNS="$RUNS" python3 - <<'PYEOF' || rc=$?
import json, os, sys, urllib.request, urllib.error

auth = open(os.environ["HDR"]).read().split(":", 1)[1].strip()
H = {"Authorization": auth, "Content-Type": "application/json"}
B = os.environ["URL"]; RUNS = int(os.environ["RUNS"])

def req(path, body=None, timeout=30):
    data = json.dumps(body).encode() if body is not None else None
    return urllib.request.urlopen(urllib.request.Request(B + path, data=data, headers=H), timeout=timeout)

if os.environ["ALL"] == "true":
    try:
        models = sorted(x["id"] for x in json.load(req("/v1/models"))["data"])
    except Exception as e:
        print(f"❌ Cannot list models: {e}"); sys.exit(2)
else:
    models = [os.environ["MODEL"]]

TOOLS = [
    {"type": "function", "function": {"name": "shell", "description": "Run a shell command",
     "parameters": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}}},
    {"type": "function", "function": {"name": "read_file", "description": "Read a file",
     "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
]
SIM = {"shell": "one", "read_file": "fedora-test-host"}

def turn(model, msgs):
    body = {"model": model, "messages": msgs, "tools": TOOLS, "max_tokens": 1000, "stream": True}
    content = reason = ""; tcs = {}
    for raw in req("/v1/chat/completions", body, timeout=180):
        line = raw.decode(errors="replace").strip()
        if not line.startswith("data:") or line == "data: [DONE]":
            continue
        ch = json.loads(line[5:])
        if not ch.get("choices"):
            continue
        d = ch["choices"][0].get("delta") or {}
        content += d.get("content") or ""
        reason += d.get("reasoning_content") or d.get("reasoning") or ""
        for t in d.get("tool_calls") or []:
            e = tcs.setdefault(t.get("index", 0), {"id": "", "name": "", "args": ""})
            f = t.get("function") or {}
            e["id"] = t.get("id") or e["id"]; e["name"] += f.get("name") or ""; e["args"] += f.get("arguments") or ""
    return content, reason, list(tcs.values())

def run_once(model):
    msgs = [{"role": "system", "content": "You are an agent. Use tools to act; never invent tool output."},
            {"role": "user", "content": "First run `echo one` with the shell tool. After you get its output, "
             "read the file /etc/hostname with read_file. Then answer with both results."}]
    calls = []
    try:
        for step in range(4):
            content, reason, tcs = turn(model, msgs)
            if not tcs:
                if not calls:
                    return "NO_TOOLS"
                ok = "one" in content and SIM["read_file"] in content and {"shell", "read_file"} <= set(calls)
                return "PASS" if ok else "FLAKY"
            calls += [t["name"] for t in tcs]
            ids = [t["id"] or f"call_{step}_{i}" for i, t in enumerate(tcs)]
            msgs.append({"role": "assistant", "content": None, "tool_calls": [
                {"id": ids[i], "type": "function", "function": {"name": t["name"], "arguments": t["args"]}}
                for i, t in enumerate(tcs)]})
            for i, t in enumerate(tcs):
                msgs.append({"role": "tool", "tool_call_id": ids[i], "content": SIM.get(t["name"], "ok")})
        return "FLAKY"
    except urllib.error.HTTPError as e:
        print(f"   {model}: HTTP {e.code} {e.read()[:160]!r}"); return "ERROR"
    except Exception as e:
        print(f"   {model}: {type(e).__name__}: {str(e)[:160]}"); return "ERROR"

SEV = {"PASS": 0, "ERROR": 1, "FLAKY": 2, "NO_TOOLS": 3}
ICON = {"PASS": "✅", "FLAKY": "⚠️ ", "NO_TOOLS": "❌", "ERROR": "❓"}
worst = "PASS"; lines = []
for m in models:
    runs = [run_once(m) for _ in range(RUNS)]
    v = max(runs, key=SEV.get)
    if SEV[v] > SEV[worst]:
        worst = v
    print(f"{ICON[v]} {m:34s} {' '.join(runs)}")
    lines.append(f"RESULT {m} {v}")
print()
print("\n".join(lines))
print()
print({"PASS": "✅ All tested models drive tool calls",
       "FLAKY": "⚠️  Some models are flaky with tool calls (usable; may stop mid-task)",
       "NO_TOOLS": "❌ Some models never emit tool calls — do not use them with Goose",
       "ERROR": "❓ Some tests errored — re-run"}[worst])
sys.exit({"PASS": 0, "NO_TOOLS": 1, "FLAKY": 5, "ERROR": 2}[worst])
PYEOF
exit "$rc"

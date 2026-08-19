#!/usr/bin/env bash
# report.sh — Generate hosted model platform report
# Usage: report.sh [HOST|all]
# Generates a 3-section markdown report: Basic Specs, Accelerator, Model Recommendations

source "$(dirname "$0")/common.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LANDSCAPE="${SCRIPT_DIR}/../references/model-landscape.md"

# ── Determine hosts ───────────────────────────────────────────
target="${1:-all}"
declare -a HOSTS
case "$target" in
  all)         HOSTS=(rhtevan-work rhel-ai) ;;
  rhtevan-work|rhel-ai) HOSTS=("$target") ;;
  *) echo "Usage: report.sh [rhtevan-work|rhel-ai|all]"; exit 1 ;;
esac

# ── Collect data per host ─────────────────────────────────────
declare -A DATA

for host in "${HOSTS[@]}"; do
  if ! host_reachable "$host"; then
    DATA[${host}_reachable]="no"
    continue
  fi
  DATA[${host}_reachable]="yes"

  # Basic specs
  read_basic=$(run_on_host "$host" '
    echo "HOSTNAME=$(hostname)"
    echo "OS=$(grep PRETTY_NAME /etc/os-release | cut -d\" -f2)"
    echo "KERNEL=$(uname -r)"
    echo "ARCH=$(uname -m)"
    echo "CPU=$(lscpu | grep "Model name" | sed "s/.*: *//")"
    echo "THREADS=$(nproc)"
    echo "RAM_TOTAL=$(free -h | awk "/^Mem:/{print \$2}")"
    echo "RAM_AVAIL=$(free -h | awk "/^Mem:/{print \$7}")"
    echo "DISK_TOTAL=$(df -h /var 2>/dev/null | tail -1 | awk "{print \$2}")"
    echo "DISK_FREE=$(df -h /var 2>/dev/null | tail -1 | awk "{print \$4}")"
    echo "DISK_PCT=$(df -h /var 2>/dev/null | tail -1 | awk "{print \$5}")"
    echo "PODMAN=$(podman --version 2>/dev/null | awk "{print \$NF}")"
  ')
  while IFS='=' read -r key val; do
    [[ -n "$key" ]] && DATA[${host}_${key}]="$val"
  done <<< "$read_basic"

  # Accelerator specs via nvidia-smi
  read_gpu=$(run_on_host "$host" '
    if ! command -v nvidia-smi &>/dev/null; then
      echo "HAS_SMI=no"
      echo "GPU_NAME=$(lspci | grep -i nvidia | head -1 | sed "s/.*: //")"
      echo "GPU_COUNT=$(lspci | grep -ci nvidia)"
      exit 0
    fi
    echo "HAS_SMI=yes"
    echo "GPU_COUNT=$(nvidia-smi -L 2>/dev/null | wc -l)"
    # Header line from nvidia-smi for driver/CUDA
    smi_header=$(nvidia-smi 2>/dev/null | head -4)
    driver=$(echo "$smi_header" | grep -oP "KMD Version: \K[0-9.]+" || echo "")
    if [[ -z "$driver" ]]; then
      driver=$(echo "$smi_header" | grep -oP "Driver Version: \K[0-9.]+" || echo "")
    fi
    cuda=$(echo "$smi_header" | grep -oP "CUDA (UMD )?Version: \K[0-9.]+" || echo "")
    echo "DRIVER=${driver}"
    echo "CUDA=${cuda}"
    # Per-GPU details (csv)
    nvidia-smi --query-gpu=index,name,memory.total,memory.free,memory.used,pcie.link.gen.current,pcie.link.width.current,compute_cap,power.limit,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | while IFS=', ' read -r idx gname mtotal mfree mused pgen pwidth ccap plimit temp; do
      echo "GPU${idx}_NAME=${gname}"
      echo "GPU${idx}_VRAM_TOTAL=${mtotal}"
      echo "GPU${idx}_VRAM_FREE=${mfree}"
      echo "GPU${idx}_VRAM_USED=${mused}"
      echo "GPU${idx}_PCIE=Gen ${pgen} x${pwidth}"
      echo "GPU${idx}_COMPUTE=${ccap}"
      echo "GPU${idx}_POWER=${plimit}"
      echo "GPU${idx}_TEMP=${temp}"
    done
    # Topology
    topo=$(nvidia-smi topo -m 2>/dev/null | grep -E "^GPU[0-9]" | head -1)
    if echo "$topo" | grep -q "NV"; then
      echo "INTERCONNECT=NVLink"
    else
      echo "INTERCONNECT=PCIe SYS (no NVLink)"
    fi
  ')
  while IFS='=' read -r key val; do
    [[ -n "$key" ]] && DATA[${host}_${key}]="$val"
  done <<< "$read_gpu"
done

# ── Helper: compute VRAM tier ─────────────────────────────────
get_tier() {
  local total_vram_mb="$1"
  if (( total_vram_mb <= 4096 )); then echo "Micro"
  elif (( total_vram_mb <= 24576 )); then echo "Small"
  elif (( total_vram_mb <= 49152 )); then echo "Medium"
  elif (( total_vram_mb <= 98304 )); then echo "Large"
  else echo "XLarge"
  fi
}

# ── Render Report ─────────────────────────────────────────────

echo "# 🖥️ Hosted Model Platform Report"
echo ""
echo "*Generated: $(date '+%Y-%m-%d %H:%M %Z')*"
echo "*Target context: ≥64K (128K preferred) · Runtime: vLLM/llm-d preferred*"
echo ""
echo "---"

# ── Section 1: Basic Specs ────────────────────────────────────
echo ""
echo "## Section 1 — Basic Specs"
echo ""

# Build header
printf "| Spec |"
for host in "${HOSTS[@]}"; do printf " %s |" "$host"; done
echo ""
printf "|------|"
for host in "${HOSTS[@]}"; do printf ":---:|" ; done
echo ""

# Rows
declare -a BASIC_FIELDS=("HOSTNAME:Hostname" "OS:OS" "KERNEL:Kernel" "ARCH:Arch" "CPU:CPU" "THREADS:Threads" "RAM_TOTAL:RAM Total" "RAM_AVAIL:RAM Available" "DISK_TOTAL:Disk Total" "DISK_FREE:Disk Free" "DISK_PCT:Disk Used" "PODMAN:Podman")
for field_spec in "${BASIC_FIELDS[@]}"; do
  IFS=':' read -r key label <<< "$field_spec"
  printf "| %s |" "$label"
  for host in "${HOSTS[@]}"; do
    if [[ "${DATA[${host}_reachable]}" == "no" ]]; then
      printf " ❌ unreachable |"
    else
      printf " %s |" "${DATA[${host}_${key}]:-N/A}"
    fi
  done
  echo ""
done

echo ""
echo "---"

# ── Section 2: Accelerator Specs ──────────────────────────────
echo ""
echo "## Section 2 — Accelerator Specs"
echo ""

printf "| Spec |"
for host in "${HOSTS[@]}"; do printf " %s |" "$host"; done
echo ""
printf "|------|"
for host in "${HOSTS[@]}"; do printf ":---:|" ; done
echo ""

for host in "${HOSTS[@]}"; do
  if [[ "${DATA[${host}_reachable]}" == "no" ]]; then continue; fi
  gpu_count="${DATA[${host}_GPU_COUNT]:-0}"
  # Compute totals from GPU0
  gpu0_name="${DATA[${host}_GPU0_NAME]:-${DATA[${host}_GPU_NAME]:-Unknown}}"
  gpu0_vram="${DATA[${host}_GPU0_VRAM_TOTAL]:-0}"
  gpu0_compute="${DATA[${host}_GPU0_COMPUTE]:-N/A}"
  total_vram=$(( gpu0_vram * gpu_count ))
  DATA[${host}_GPU_MODEL]="$gpu0_name"
  DATA[${host}_TOTAL_VRAM_MB]="$total_vram"
  DATA[${host}_VRAM_PER_GPU]="$gpu0_vram"
  DATA[${host}_COMPUTE_CAP]="$gpu0_compute"
  if (( gpu_count > 1 )); then
    DATA[${host}_MAX_TP]="TP=${gpu_count}"
  else
    DATA[${host}_MAX_TP]="TP=1 only"
  fi
done

declare -a GPU_FIELDS=(
  "GPU_MODEL:GPU Model"
  "GPU_COUNT:GPU Count"
  "VRAM_PER_GPU:VRAM per GPU (MiB)"
  "TOTAL_VRAM_MB:Total VRAM (MiB)"
  "COMPUTE_CAP:Compute Capability"
  "GPU0_PCIE:PCIe Link (GPU 0)"
  "INTERCONNECT:Interconnect"
  "GPU0_POWER:Power Limit (W)"
  "GPU0_TEMP:Temperature (°C)"
  "MAX_TP:Max Tensor Parallelism"
  "DRIVER:NVIDIA Driver"
  "CUDA:CUDA Version"
  "HAS_SMI:nvidia-smi"
)

for field_spec in "${GPU_FIELDS[@]}"; do
  IFS=':' read -r key label <<< "$field_spec"
  printf "| %s |" "$label"
  for host in "${HOSTS[@]}"; do
    if [[ "${DATA[${host}_reachable]}" == "no" ]]; then
      printf " ❌ unreachable |"
    else
      val="${DATA[${host}_${key}]:-N/A}"
      # Pretty-print some fields
      if [[ "$key" == "HAS_SMI" ]]; then
        [[ "$val" == "yes" ]] && val="✅" || val="❌"
      fi
      if [[ "$key" == "TOTAL_VRAM_MB" ]]; then
        local_gb=$(echo "scale=0; $val / 1024" | bc 2>/dev/null || echo "?")
        val="${val} (~${local_gb} GB)"
      fi
      printf " %s |" "$val"
    fi
  done
  echo ""
done

# Per-GPU detail if multiple GPUs
for host in "${HOSTS[@]}"; do
  gpu_count="${DATA[${host}_GPU_COUNT]:-0}"
  if (( gpu_count > 1 )); then
    echo ""
    echo "> **${host} per-GPU detail:**"
    echo ">"
    echo "> | GPU | VRAM Total | VRAM Free | VRAM Used | PCIe | Temp |"
    echo "> |:---:|:----------:|:---------:|:---------:|:----:|:----:|"
    for (( i=0; i<gpu_count; i++ )); do
      echo "> | GPU $i | ${DATA[${host}_GPU${i}_VRAM_TOTAL]:-?} MiB | ${DATA[${host}_GPU${i}_VRAM_FREE]:-?} MiB | ${DATA[${host}_GPU${i}_VRAM_USED]:-?} MiB | ${DATA[${host}_GPU${i}_PCIE]:-?} | ${DATA[${host}_GPU${i}_TEMP]:-?}°C |"
    done
  fi
done

echo ""
echo "---"

# ── Section 3: Model Recommendations ─────────────────────────
echo ""
echo "## Section 3 — Top 3 Model Recommendations"
echo ""
echo "### Runtime Preference"
echo ""
echo "| Priority | Runtime | Notes |"
echo "|:--------:|---------|-------|"
echo "| 1st | **vLLM / llm-d** | Preferred — OpenAI-compatible API, PagedAttention, continuous batching, tensor parallelism, tool-calling parsers |"
echo "| 2nd | **llama.cpp** | When vLLM is not feasible — GGUF quantization, partial GPU offload, CPU fallback, lower VRAM floor |"
echo ""

for host in "${HOSTS[@]}"; do
  if [[ "${DATA[${host}_reachable]}" == "no" ]]; then
    echo "### ${host} — ❌ Unreachable"
    echo ""
    continue
  fi

  total_vram="${DATA[${host}_TOTAL_VRAM_MB]:-0}"
  gpu_count="${DATA[${host}_GPU_COUNT]:-1}"
  tier=$(get_tier "$total_vram")
  total_gb=$(echo "scale=0; $total_vram / 1024" | bc 2>/dev/null || echo "?")
  ram_avail="${DATA[${host}_RAM_AVAIL]:-?}"

  echo "### ${host} — ${total_gb} GB VRAM, ${gpu_count}× GPU (${tier} tier)"
  echo ""

  case "$tier" in
    Micro)
      echo "> ⚠️ **Context limitation:** ${total_gb} GB VRAM cannot meet the 64K target for any model on vLLM."
      echo "> vLLM requires full model weights on GPU — even the smallest model leaves insufficient room for KV cache."
      echo "> **llama.cpp is the only viable runtime** for this host, enabling partial GPU offload and CPU fallback."
      echo ""
      echo "| Rank | Model | Runtime | Quant | Max Context | Est. VRAM | Tok/s (est.) | Why not vLLM? | Trade-off |"
      echo "|:----:|-------|:-------:|:-----:|:-----------:|:---------:|:------------:|:-------------:|----------|"
      echo "| 🥇 | **Granite 4.1 3B** | llama.cpp | Q4_K_M | **16K** | ~3.2 GB | ~25–35 | Weights ~3 GB FP8 + KV = no room | Full GPU offload; best context stretch; native tool-calling |"
      echo "| 🥈 | **Qwen3 4B** | llama.cpp | Q4_K_M | **8K** | ~3.5 GB | ~20–30 | Weights ~4 GB FP8 = no room | Stronger reasoning; thinking mode; context limited to 8K |"
      echo "| 🥉 | **Granite 4.1 8B** | llama.cpp | Q4_K_M | **4–16K** | 2.5–3.8 GB | ~8–15 | Weights ~8 GB FP8 = far exceeds ${total_gb} GB | Best quality; partial offload (18–25/32 layers) |"
      echo ""
      echo "> **Context vs. Speed trade-off (all llama.cpp):**"
      echo ">"
      echo "> | Config | Context | Speed | Quality | GPU Layers | Notes |"
      echo "> |--------|:-------:|:-----:|:-------:|:----------:|-------|"
      echo "> | Granite 3B Q4, full GPU | 16K | ⚡ Fast | Good | All | Best balance for dev/test |"
      echo "> | Qwen3 4B Q4, full GPU | 8K | ⚡ Fast | Better | All | Drops to 8K to stay in budget |"
      echo "> | Granite 8B Q4, partial GPU | 4K | 🐢 Moderate | Best | 25/32 | Quality-critical, short context |"
      echo "> | Granite 8B Q4, partial GPU | 16K | 🐢 Moderate | Best | 18/32 | More context, fewer GPU layers |"
      echo "> | Granite 8B Q4, **CPU-only** | **64K** | 🐌 ~2–4 t/s | Best | 0 | **Meets 64K target** via ${ram_avail} RAM; ~13 GB needed; batch/async only |"
      ;;

    Small)
      echo "> ✅ **vLLM viable for ≤8B models** at 64K context."
      echo ""
      echo "| Rank | Model | Runtime | Quant | TP | Context | Est. VRAM | Tok/s (est.) | Deployment Tweaks |"
      echo "|:----:|-------|:-------:|:-----:|:--:|:-------:|:---------:|:------------:|-------------------|"
      echo "| 🥇 | **Granite 4.1 8B** | **vLLM** | FP8 | 1 | **64K** | ~12 GB | ~40–50 | \`--enable-auto-tool-choice --tool-call-parser granite\` |"
      echo "| 🥈 | **Qwen3 8B** | **vLLM** | FP8 | 1 | **64K** | ~12 GB | ~40–50 | \`--tool-call-parser hermes --enable-auto-tool-choice\`; thinking mode |"
      echo "| 🥉 | **Granite 4.1 8B** | **vLLM** | BF16 | 1 | **32K** | ~20 GB | ~50–60 | Full precision; shorter context trade-off |"
      ;;

    Medium)
      echo "> ✅ **vLLM viable.** Sweet spot for 8–27B models at 128K context."
      echo ""
      echo "| Rank | Model | Runtime | Quant | TP | Context | Est. VRAM | Tok/s (est.) | Deployment Tweaks |"
      echo "|:----:|-------|:-------:|:-----:|:--:|:-------:|:---------:|:------------:|-------------------|"
      echo "| 🥇 | **Granite 4.1 8B** | **vLLM** | BF16 | 2 | **128K** | ~24 GB | ~50–70 | Proven 128K config; full precision; \`--enable-auto-tool-choice --tool-call-parser granite\` |"
      echo "| 🥈 | **Qwen3.8 27B** | **vLLM** | FP8 | 2 | **128K** | ~41 GB | ~25–35 | Latest Qwen; \`--tool-call-parser hermes --enable-auto-tool-choice\` |"
      echo "| 🥉 | **Mistral Small 24B** | **vLLM** | FP8 | 2 | **128K** | ~36 GB | ~30–40 | Strong coding; \`--tool-call-parser mistral --enable-auto-tool-choice\` |"
      ;;

    Large)
      echo "> ✅ **Meets target on vLLM.** Multiple models can serve 128K context within budget."
      echo ""
      echo "| Rank | Model | Runtime | Quant | TP | Context | Est. VRAM (wt+KV) | Tok/s (est.) | Deployment Tweaks |"
      echo "|:----:|-------|:-------:|:-----:|:--:|:-------:|:------------------:|:------------:|-------------------|"
      echo "| 🥇 | **Qwen3 32B** | **vLLM** | FP8 | 4 | **128K** | ~48 GB (32+16) | ~30–40 | Best open-source reasoning; \`--tool-call-parser hermes --enable-auto-tool-choice\`; thinking mode |"
      echo "| 🥈 | **Granite 4.1 8B** | **vLLM** | BF16 | 2 | **128K** | ~24 GB (16+8) | ~50–70 | Proven 128K; fastest; leaves 2 GPUs free; \`--enable-auto-tool-choice --tool-call-parser granite\` |"
      echo "| 🥉 | **Granite 4.1 30B** | **vLLM** | FP8 | 4 | **128K** | ~46 GB (30+16) | ~20–30 | FP8 unlocks 128K (BF16 caps at 96K); \`--disable-custom-all-reduce\` for PCIe |"
      echo ""
      echo "> **Context vs. Speed vs. Quality trade-off (all vLLM):**"
      echo ">"
      echo "> | Config | Context | Speed | Quality | GPUs | Co-host? |"
      echo "> |--------|:-------:|:-----:|:-------:|:----:|:--------:|"
      echo "> | Granite 8B BF16 TP=2 | 128K | ⚡⚡ Fastest | Strong | 2 | ✅ 2 GPUs free |"
      echo "> | Qwen3 32B FP8 TP=4 | 128K | ⚡ Fast | Top-tier | 4 | ❌ |"
      echo "> | Granite 30B FP8 TP=4 | 128K | ⚡ Fast | Very strong | 4 | ❌ |"
      echo "> | Granite 30B BF16 TP=4 | 96K | ⚡ Fast | Best (no quant) | 4 | ❌ |"
      echo "> | Qwen3 32B BF16 TP=4 | 64K | ⚡ Fast | Best (no quant) | 4 | ❌ |"
      echo ""
      echo "> **Co-hosting combos (TP=2 + TP=2, both 128K on vLLM):**"
      echo ">"
      echo "> | GPU 0–1 | GPU 2–3 | Use Case |"
      echo "> |---------|---------|----------|"
      echo "> | Granite 8B BF16 | Qwen3.8 27B FP8 | Enterprise tool-calling + latest reasoning |"
      echo "> | Granite 8B BF16 | Mistral Small 24B FP8 | General purpose + strong coding |"
      echo "> | Granite 8B BF16 | Gemma 3 27B FP8 | Enterprise + multilingual |"
      echo "> | Qwen3 8B BF16 | Qwen3.8 27B FP8 | Light + heavy reasoning pair |"
      ;;

    XLarge)
      echo "> ✅ **Full range available on vLLM.** 70B+ models at 128K context."
      echo ""
      echo "| Rank | Model | Runtime | Quant | TP | Context | Est. VRAM | Tok/s (est.) | Deployment Tweaks |"
      echo "|:----:|-------|:-------:|:-----:|:--:|:-------:|:---------:|:------------:|-------------------|"
      echo "| 🥇 | **Llama 3.3 70B** | **vLLM** | FP8 | 4 | **128K** | ~90 GB | ~20–30 | \`--tool-call-parser llama3 --enable-auto-tool-choice\` |"
      echo "| 🥈 | **Qwen3 32B** | **vLLM** | BF16 | 4 | **128K** | ~80 GB | ~35–45 | Full precision; \`--tool-call-parser hermes --enable-auto-tool-choice\` |"
      echo "| 🥉 | **Granite 4.1 30B** | **vLLM** | BF16 | 4 | **128K** | ~76 GB | ~25–35 | Full precision 128K; \`--enable-auto-tool-choice --tool-call-parser granite\` |"
      ;;
  esac

  echo ""
done

# ── Summary ───────────────────────────────────────────────────
echo "---"
echo ""
echo "### Summary"
echo ""
echo "| Host | VRAM Tier | Target Met? | Runtime | Best Config | Context | Speed |"
echo "|------|:---------:|:-----------:|:-------:|-------------|:-------:|:-----:|"

for host in "${HOSTS[@]}"; do
  if [[ "${DATA[${host}_reachable]}" == "no" ]]; then
    echo "| ${host} | ? | ❌ Unreachable | — | — | — | — |"
    continue
  fi
  total_vram="${DATA[${host}_TOTAL_VRAM_MB]:-0}"
  tier=$(get_tier "$total_vram")
  total_gb=$(echo "scale=0; $total_vram / 1024" | bc 2>/dev/null || echo "?")

  case "$tier" in
    Micro)
      echo "| **${host}** | ${tier} (${total_gb} GB) | ⚠️ Partial | llama.cpp | Granite 3B Q4 (GPU 16K) / 8B Q4 (CPU 64K) | 16K / 64K | ⚡ / 🐌 |"
      ;;
    Small)
      echo "| **${host}** | ${tier} (${total_gb} GB) | ⚠️ 64K max | **vLLM** | Granite 8B FP8 | 64K | ⚡ |"
      ;;
    Medium)
      echo "| **${host}** | ${tier} (${total_gb} GB) | ✅ Full | **vLLM** | Granite 8B BF16 TP=2 | 128K | ⚡⚡ |"
      ;;
    Large)
      echo "| **${host}** | ${tier} (${total_gb} GB) | ✅ Full | **vLLM** | Qwen3 32B FP8 TP=4 | 128K | ⚡ |"
      ;;
    XLarge)
      echo "| **${host}** | ${tier} (${total_gb} GB) | ✅ Full | **vLLM** | Llama 3.3 70B FP8 TP=4 | 128K | ⚡ |"
      ;;
  esac
done

echo ""
echo "---"
echo "*Report generated by hosted-model-ctl report.sh · Model landscape: references/model-landscape.md*"

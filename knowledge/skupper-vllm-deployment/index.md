# Skupper + vLLM Deployment Postmortem

Knowledge bundle capturing lessons learned from deploying IBM Granite
models on multi-GPU cloud instances via Skupper V2 Virtual Application
Networks, August 2026.

## Concepts

* [Skupper Platform Migration](./skupper-platform-migration.md) - Why custom-built skrouterd on linux/systemd failed and how the official container image on podman platform solved it; 13+ build iterations; octets=0 mystery; podman gotchas
* [Network Architecture](./network-architecture.md) - Edge vs interior mode limitation (source code proof); AWS port constraints; routing key design; multi-hub connectivity; link token gotchas; CLI status reporting bug
* [vLLM Model Deployment](./vllm-model-deployment.md) - 128K context VRAM calculations; Granite 4.1 30B/8B tensor parallelism; InstructLab container as vLLM runtime; model selection mistakes (Qwen3 40K, Granite "14B"); cold start times
* [AgentFS Process Lessons](./agentfs-process-lessons.md) - Custom provider JSON schema incident; three-layer defensive fix; backup guardrail; skill-index signals bug; context window degradation in long sessions
* [Skills Inventory](./skills-inventory.md) - Complete inventory of skills updated/renamed; AgentFS guardrail changes; final model registry and Skupper VAN architecture

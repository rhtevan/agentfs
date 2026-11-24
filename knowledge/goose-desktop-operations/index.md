# Goose Desktop Operations

Knowledge bundle for Goose-specific configuration, troubleshooting,
and runtime behavior — Desktop UI, custom providers, config.yaml
settings, and agent operational patterns.

## Concepts

* [Toolshim & Tool Call Providers](./toolshim-and-tool-calls.md) - When GOOSE_TOOLSHIM is needed vs harmful; native tool call detection; Desktop hang diagnostic pattern
* [Custom Provider JSON Schema](./custom-provider-schema.md) - Goose Desktop custom provider JSON requirements; poison-JSON safeguard; field inventory
* [Reasoning Effort Gotcha](./reasoning-effort.md) - Custom (OpenAI-engine) providers drop GOOSE_THINKING_EFFORT → server default; native providers honour it; effort changes rule adherence (R2 medium 0/8 vs high 8/8)
* [Plugin Registration Teardown](./plugin-registration-teardown.md) - goose records project plugins in global config.yaml `plugins:`; deleting the directory leaves the entry enabled; hook-test teardown must remove both

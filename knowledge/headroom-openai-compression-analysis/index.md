# Headroom OpenAI-Endpoint Compression Analysis

Why LLM compression proxies achieve zero savings through OpenAI-compatible
endpoints, which proxy flags provide value regardless, and when to
keep vs remove a passthrough proxy.

* [OpenAI-Compatible Endpoints Block LLM Proxy Compression](problem-analysis.md) - Architectural mismatch between OpenAI chat format and Anthropic-native compression routing
* [Headroom Proxy Flag Reference](configuration-history.md) - Which flags provide value and which are blocked by the content router
* [LLM Proxy Architecture Decision](options-assessment.md) - Decision framework for keeping vs removing a non-compressing proxy

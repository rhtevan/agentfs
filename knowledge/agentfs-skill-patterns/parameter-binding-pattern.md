---
type: Pattern
title: Skill Parameter Binding Pattern
description: >
  A reusable pattern for defining structured parameters in AgentFS skills
  with semantic binding-cues, CLI-style usage hints, confirmation flow,
  and explicit script argument mapping. Use for any skill with more than
  two parameters to ensure reliable and accurate argument resolution.
tags: [agentfs, skills, parameters, binding, patterns, design]
timestamp: 2026-07-22T21:21:00-04:00
---

# Skill Parameter Binding Pattern

## Problem

Skills accept arguments as a single freeform string. When a skill has
multiple parameters, the agent must semantically map user intent to
named parameters. Without guidance, the agent may:

- Confuse similar parameters (e.g., `REMOTE_SITE_NAME` vs `REMOTE_SSH_HOST`)
- Silently assume values for missing required parameters
- Skip optional parameters the user intended to set
- Pass arguments to scripts in the wrong positional order

## When to Use

Apply this pattern when a skill has **three or more parameters**, or
when two parameters could be semantically confused.

## Solution: Four-Layer Binding

### Layer 1: `parameters:` Block in YAML Frontmatter

Define each parameter with structured metadata directly in the
SKILL.md frontmatter:

```yaml
parameters:
  PARAM_NAME:
    description: What this parameter controls
    required: true|false
    default: "value"           # omit for required params
    binding-cues: ["phrase1", "phrase2", "phrase3"]
    example: concrete-value
```

**`binding-cues`** are the key innovation — a list of natural-language
phrases the agent should match against user input. They disambiguate
parameters that might otherwise be confused.

Guidelines for binding-cues:
- Include 2–4 phrases per parameter
- Cover synonyms and common variations
- Make cues **mutually exclusive** across parameters — avoid the same
  phrase appearing in two parameters' cue lists
- Include the formal name as a cue (e.g., `"namespace"` for `NAMESPACE`)

### Layer 2: `argument-hint` with CLI-Style Usage

Provide a familiar CLI usage string in the frontmatter:

```yaml
argument-hint: >
  Usage: skill-name --param1 <value> --param2 <value>
    [--optional-param <value>]
  Example: skill-name --param1 foo --param2 bar
```

This serves two purposes:
1. **Agent prompt** — when required parameters are missing, the agent
   presents this usage string instead of guessing
2. **User invocation** — users can provide arguments in CLI-style
   format for unambiguous binding:
   ```
   load_skill(name: "my-skill", args: "--param1 foo --param2 bar")
   ```

### Layer 3: Agent Binding Rules in SKILL.md Body

Define explicit rules for the agent to follow. Include these five
rules in a section titled `### Agent Binding Rules`:

| Rule | Description |
|------|-------------|
| **1. Match binding-cues** | Scan user input for phrases matching each parameter's `binding-cues`. Bind the adjacent value to that parameter. |
| **2. Prompt for missing required** | If any `required: true` parameter cannot be resolved, present the `argument-hint` usage string and list the missing parameters with descriptions and examples. |
| **3. Apply defaults silently** | For `required: false` parameters not mentioned by the user, apply the `default` value without prompting. |
| **4. Confirm before executing** | Present a resolved parameter table showing all bindings (including defaults) and wait for user confirmation. |
| **5. Script argument mapping** | Map named parameters to positional script arguments using an explicit mapping table. |

### Layer 4: Script Argument Mapping Table

Explicitly document how named parameters map to positional `$1`, `$2`,
etc. for each script:

```markdown
| Script | Args |
|--------|------|
| `setup.sh` | `$1=NAME $2=NAMESPACE $3=HOST` |
| `test.sh`  | `$1=NAMESPACE $2=HOST $3=PORT` |
```

This eliminates guesswork — the agent knows exactly which value goes
where without reading script source code.

## Complete Example

### Frontmatter

```yaml
---
name: my-two-host-skill
description: >
  Deploy a service across two hosts with connectivity testing.
argument-hint: >
  Usage: my-two-host-skill --local-name <name> --remote-name <name>
    --remote-host <ssh-host> --namespace <ns> [--port <port>]
  Example: my-two-host-skill --local-name hub --remote-name edge
    --remote-host worker-1 --namespace prod
parameters:
  LOCAL_NAME:
    description: Name for the local service instance
    required: true
    binding-cues: ["local name", "this host", "hub name"]
    example: hub
  REMOTE_NAME:
    description: Name for the remote service instance
    required: true
    binding-cues: ["remote name", "other host", "edge name"]
    example: edge
  REMOTE_HOST:
    description: SSH target for the remote host
    required: true
    binding-cues: ["ssh host", "remote host", "connect to"]
    example: worker-1
  NAMESPACE:
    description: Logical namespace for isolation
    required: true
    binding-cues: ["namespace", "ns"]
    example: prod
  PORT:
    description: Port number for connectivity test
    required: false
    default: "8080"
    binding-cues: ["port", "test port"]
    example: "8080"
metadata:
  tags: [deployment, two-host, networking]
---
```

### Agent Invocation Flow

```
User: "Deploy the service to worker-1, call it hub locally
       and edge remotely, namespace prod"

Agent resolves:
  LOCAL_NAME   = hub        (matched "locally" → "this host")
  REMOTE_NAME  = edge       (matched "remotely" → "other host")
  REMOTE_HOST  = worker-1   (matched "to worker-1" → "remote host")
  NAMESPACE    = prod       (matched "namespace prod" → "namespace")
  PORT         = 8080       (default applied)

Agent confirms:
  Resolved parameters:
    LOCAL_NAME:   hub
    REMOTE_NAME:  edge
    REMOTE_HOST:  worker-1
    NAMESPACE:    prod
    PORT:         8080 (default)
  Proceed? [y/n]

User: y

Agent executes:
  bash scripts/setup.sh hub prod worker-1
  bash scripts/test.sh prod worker-1 8080
```

## Anti-Patterns

| Anti-Pattern | Why It Fails | Fix |
|-------------|-------------|-----|
| No binding-cues, rely on parameter names alone | `REMOTE_SITE_NAME` vs `REMOTE_SSH_HOST` — agent can't distinguish | Add unique binding-cues per parameter |
| Overlapping binding-cues | "remote" matches both `REMOTE_NAME` and `REMOTE_HOST` | Make cues mutually exclusive: "remote name" vs "ssh host" |
| No confirmation step | Agent silently misassigns a value, user discovers too late | Always confirm resolved bindings |
| Implicit script arg ordering | Agent infers wrong positional order | Explicit mapping table |
| Prompting for optional params | Slows down the common case | Apply defaults silently, prompt only for required |

## Integration with skill-gen

When `skill-gen` creates a new skill with 3+ parameters, it SHOULD:

1. Generate the `parameters:` block with binding-cues
2. Generate an `argument-hint` with CLI-style usage
3. Include the Agent Binding Rules section
4. Include a Script Argument Mapping table
5. Add a concise Invocation Example section

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-22 21:21 | v1.0 — Initial pattern, extracted from skupper-linux-two-site skill development session |

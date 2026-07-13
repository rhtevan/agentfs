---
name: bash-completion-gen
description: >-
  Generate a bash completion script for any CLI command by systematically
  discovering its subcommands and options. Uses a multi-step process:
  check for built-in completion generators, recursively walk the subcommand
  tree via --help/-h, build the completion script, then validate every
  subcommand and option against actual command output.
argument-hint: "<command-name> — the CLI command to generate bash completion for"
compatibility: "Any agent with shell access on a system with bash-completion installed"
metadata:
  author: agentfs
  version: "1.0"
  tags: [bash, completion, cli, shell, automation]
user-invocable: true
disable-model-invocation: false
---

# Bash Completion Generator

Generate a bash completion script for any CLI command by discovering its
full subcommand tree and options, then building and validating a completion
script.

## Input

The user provides a command name. The agent must be able to locate and
execute the command.

## Step 1 — Locate the Command

Find the command binary:

```bash
which <command> || find /usr /home -name '<command>' -type f 2>/dev/null | head -10
```

If the command is not in PATH, use the full path for all subsequent steps.
If the command cannot be found at all, stop and inform the user.

## Step 2 — Check for Built-in Completion Generator

Many modern CLI tools can generate their own completion scripts. Try these
variants in order — if any succeeds, follow its output/instructions and
skip to Step 6 (Install):

```bash
<command> completion bash
<command> completions bash
<command> --completion bash
<command> --completions bash
<command> generate-completion bash
```

If none of these work, proceed to manual discovery.

## Step 3 — Discover Subcommands and Options

This is a recursive process. Start with the top-level command and work
down the subcommand tree.

### 3a — Top-level Help

Run the command's help:

```bash
<command> --help 2>&1
<command> -h 2>&1
```

From the output, extract:

1. **Global options** — flags and options that apply to the command itself
   (e.g., `--verbose`, `--version`, `-h`)
2. **Subcommands** — named sub-commands listed in the help output
3. **Option arguments** — which options take values vs. are boolean flags
4. **Enum values** — options with a fixed set of allowed values
   (e.g., `--format table|json|yaml`)

### 3b — Recurse into Each Subcommand

For each discovered subcommand, run:

```bash
<command> <subcommand> --help 2>&1
<command> <subcommand> -h 2>&1
```

Extract the same information: sub-subcommands, options, option arguments,
and enum values.

Continue recursing until there are no deeper subcommands. Most CLIs are
2–3 levels deep.

**Efficiency tip:** Batch multiple subcommand help calls into a single
shell invocation to reduce round-trips:

```bash
for cmd in sub1 sub2 sub3; do
    echo "========== $cmd =========="
    <command> $cmd --help 2>&1
    echo
done
```

### 3c — Record the Full Command Tree

Build a mental model of the complete tree:

```
<command>
├── global options: --opt1, --opt2 <value>, --flag
├── subcommand1
│   ├── options: --foo, --bar <value>
│   └── sub-subcommand1a
│       └── options: --baz
├── subcommand2
│   └── options: --qux <enum: a|b|c>
└── ...
```

## Step 4 — Build the Completion Script

Create the bash completion script following these conventions:

### Structure Template

```bash
# bash completion for <command>                -*- shell-script -*-
# Auto-generated from '<command> --help' and subcommand discovery (<command> <version>)

_<command>() {
    local cur prev words cword
    _init_completion || return

    # 1. Find the subcommand position (skip global options and their args)
    local subcmd="" subcmd_idx=0
    local i
    for (( i=1; i < cword; i++ )); do
        case "${words[i]}" in
            <options-that-take-arguments>)
                (( i++ ))  # skip the argument value
                ;;
            <boolean-flags>)
                ;;
            -*)
                ;;
            *)
                subcmd="${words[i]}"
                subcmd_idx=$i
                break
                ;;
        esac
    done

    # 2. If no subcommand yet, complete top-level
    if [[ -z "$subcmd" ]]; then
        # Handle options that take specific values
        case "$prev" in
            <option-with-enum>)
                COMPREPLY=( $(compgen -W '<enum-values>' -- "$cur") )
                return
                ;;
            <option-with-path>)
                _filedir       # or _filedir -d for directories
                return
                ;;
        esac

        if [[ "$cur" == -* ]]; then
            COMPREPLY=( $(compgen -W '<all-global-options>' -- "$cur") )
        else
            COMPREPLY=( $(compgen -W '<all-subcommands>' -- "$cur") )
        fi
        return
    fi

    # 3. Find sub-subcommand if the subcommand has its own subcommands
    local subsub="" subsub_idx=0
    # ... (same pattern as above, starting from subcmd_idx+1)

    # 4. Dispatch per subcommand
    case "$subcmd" in
        <subcommand1>)
            # Handle sub-subcommands if any, else options
            ;;
        <subcommand2>)
            ;;
    esac
} &&
complete -F _<command> <command>

# vim: ft=bash
```

### Key Patterns

| Pattern | When to Use |
|---------|-------------|
| `compgen -W 'opt1 opt2'` | Fixed set of completions (subcommands, enum values) |
| `_filedir` | Option expects a file path |
| `_filedir -d` | Option expects a directory path |
| `_filedir yaml` | Option expects files with a specific extension |
| `return` (no COMPREPLY) | Option expects a free-form value (number, name, ID) |
| `[[ "$cur" == -* ]]` | Distinguish between completing options vs. positional args |

### Rules

- **Function name:** `_<command>` (underscore prefix, hyphens in command
  name converted to underscores in function name)
- **Helper functions:** prefix with `_<command>_` (e.g., `_herdr_integration_targets`)
- **Enum values:** always provide completions via `compgen -W` when a
  `case` on `$prev` matches the option
- **Boolean flags vs. value options:** boolean flags need no argument
  skipping; value options need `(( i++ ))` in the subcommand finder loop
- **Sub-subcommand depth:** support at least 2 levels (command → subcommand
  → sub-subcommand). Use the same `for` loop pattern for each level.
- **Path arguments:** use `_filedir` or `_filedir -d` as appropriate
- **Guard the registration:** use `&& complete -F ...` pattern so
  completion is only registered if the function definition succeeds

## Step 5 — Validate

Validation has two parts. Both MUST pass before the skill is complete.

### 5a — Syntax Validation

Source the script and verify the function loads:

```bash
bash -c 'source <completion-file> && type _<command> >/dev/null 2>&1 && echo "✓ OK" || echo "✗ FAIL"'
```

### 5b — Content Validation

Validate every subcommand and option against actual command output:

```bash
# Validate each top-level subcommand exists
for cmd in <all-subcommands>; do
    <command> $cmd --help >/dev/null 2>&1 || <command> $cmd -h >/dev/null 2>&1
    echo "  $cmd: exit $?"
done

# Validate each sub-subcommand exists
for sub in <sub-subcommands>; do
    result=$(<command> <subcommand> $sub 2>&1 | head -1)
    echo "  <subcommand> $sub: $result"
done
```

Check the validation output for:

- **Unknown subcommand errors** → remove from completion script
- **Missing options** in the validation usage output that are not in
  the completion script → add them
- **Extra options** in the completion script not present in usage → remove
- **Enum mismatches** (e.g., completion says `--raw` but usage doesn't
  list it) → fix

If any discrepancies are found, edit the completion script and re-run
validation until clean.

## Step 6 — Install

Install the completion script to the user's bash-completion directory:

```bash
mkdir -p ~/.local/share/bash-completion/completions
cp <generated-file> ~/.local/share/bash-completion/completions/<command>
```

Or if the script was written directly to that location, confirm it exists.

The completion will auto-load in new bash sessions (bash-completion
lazy-loads from `~/.local/share/bash-completion/completions/`).

## Step 7 — Report

Summarize to the user:

1. Where the completion script was installed
2. How many subcommands and sub-subcommands are covered
3. Notable completions (enum values, path completions, etc.)
4. Any subcommands or options that couldn't be discovered
   (e.g., dynamic values like IDs that can't be completed statically)

## Notes

- **Existing completion:** Before starting, check if a completion already
  exists at `~/.local/share/bash-completion/completions/<command>` or
  `/etc/bash_completion.d/`. If so, ask the user whether to replace it.
- **Dynamic completions:** Some arguments (IDs, names) can only be
  completed dynamically by querying the running command. If the command
  provides a `list` subcommand, consider adding a helper function that
  calls it for dynamic completion. Only do this if the list command is
  fast and doesn't require a running server.
- **Version pinning:** Include the command version in the script header
  comment so the user knows when it may need regeneration.
- **Hyphenated command names:** Replace hyphens with underscores in bash
  function names (e.g., `my-tool` → `_my_tool`).

## Verification

- [ ] Completion script sources without errors
- [ ] All subcommands validated against actual `--help` output
- [ ] All options validated against actual usage output
- [ ] Enum values match actual allowed values
- [ ] Script installed to `~/.local/share/bash-completion/completions/<command>`
- [ ] New bash shell shows completions when pressing TAB

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-13 10:48 | v1.0 — Initial skill created from herdr completion workflow |

# Agent Prompts

Three prompt instruction files are loaded by opencode, configured in `default/opencode.jsonc:20-24`:

## General (`default/prompts/general.md`)

Baseline agent behavior:
- Answer directly when no tools are needed
- Prefer the smallest set of reads, searches, and commands
- Use gitnexus when available for codebase exploration
- Escalate to planning only for non-trivial work
- Follow least privilege; ask before destructive/networked actions

## GitNexus (`default/prompts/gitnexus.md`)

Code intelligence rules:
- MUST run `gitnexus_impact` before editing any symbol and report blast radius
- MUST run `gitnexus_detect_changes` before committing
- MUST warn user on HIGH/CRITICAL risk
- NEVER edit a function/class/method without impact analysis first
- NEVER rename symbols with find-and-replace -- use `gitnexus_rename`

## Karpathy (`default/prompts/karpathy.md`)

Behavioral guidelines to reduce LLM coding mistakes:
- Think before coding: surface tradeoffs, ask when unclear
- Simplicity first: minimum code, no speculative features
- Surgical changes: touch only what's needed, match existing style
- Goal-driven execution: define verifiable success criteria, loop until verified

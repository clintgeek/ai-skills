---
name: ai-list
description: List all known AI CLI tools and report whether each is installed and configured (hotwired) to ~/.ai.
---

# /ai-list — AI CLI Inventory

Use this skill when the user wants to see which tracked AI CLI tools are installed and how they are currently configured.

## 1. Run the shared inventory

```bash
~/.ai/skills/ai-setup/scripts/ai-setup inventory
```

This prints a table with one row per tracked tool:

| column      | meaning |
| :---------- | :------ |
| `tool`      | short binary name |
| `installed` | `yes` if the binary is on `PATH`, otherwise `no` |
| `known`     | `yes` if the skill/laws paths are vetted, otherwise `no` |
| `skills`    | `yes` if symlinked to `~/.ai/skills`, `dir` if a real directory, else `no` |
| `laws`      | `yes` if symlinked to `~/.ai/laws/global_rules.md`, `file` if a real file, else `no` |

## 2. (Optional) Show the roster with paths

```bash
~/.ai/skills/ai-battle/scripts/ai-battle --list-tools
```

This lists installed and missing tools with their `command -v` path or install command.

## 3. Report to the human

Present the table in a clean, scannable format. Explain any tool that is:

- **installed but not hotwired** (`skills` or `laws` is not `yes`): it is not sharing `~/.ai` yet; point the user at `/ai-setup` if they want to fix it.
- **missing** (`installed: no`): the tool is not on `PATH`.
- **unknown path map** (`known: no`): its skill/laws roots have not been vetted; use `ai-setup hotwire-generic` with explicit paths.

Do not install, hotwire, or modify anything unless the user explicitly asks.

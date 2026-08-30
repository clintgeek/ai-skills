---
name: ai-setup
description: One-shot and re-runnable bootstrap for a new machine. Clones the shared skills repo, detects installed AI CLI tools from the ai-battle registry, hotwires their skill and laws roots to ~/.ai/skills and ~/.ai/laws, and can install missing tools.
---

# /ai-setup — Shared AI Environment Bootstrap

Use this skill when the user wants to:

- Set up a new machine with all their AI tools.
- Re-run `ai-setup` after adding a new tool or skill.
- Install a new AI CLI and hotwire it to the shared folders.
- Sync skills and laws across Claude, Devin, Windsurf, Copilot, etc.

## 1. Bootstrap

1. If `~/.ai/skills` is missing, clone `git@github.com:clintgeek/ai-skills.git` into `~/.ai/skills`.
2. If `~/.ai/laws` is missing, create it and ensure `~/.ai/laws/global_rules.md` exists.
3. Report the state of both directories.

## 2. Inventory

Run `~/.ai/skills/ai-setup/scripts/ai-setup.sh inventory` to see which of the 12 ai-battle CLI tools are installed and which are already hotwired.

The registry is:

| binary | tool | family |
| :--- | :--- | :--- |
| `devin` | Cognition Devin CLI | cognition |
| `claude` | Anthropic Claude Code | anthropic |
| `agy` | Google Antigravity CLI | google |
| `gemini` | Google Gemini CLI (older) | google |
| `copilot` | GitHub Copilot CLI | github |
| `codex` | OpenAI Codex CLI | openai |
| `opencode` | opencode | opencode |
| `goose` | Block goose | goose |
| `aider` | aider | aider |
| `cursor-agent` | Cursor CLI agent | cursor |
| `amp` | Sourcegraph Amp CLI | sourcegraph |
| `qwen` | Qwen Code CLI | alibaba |

## 3. Hotwire installed tools

For each installed tool:

1. Back up any existing skill root to `<root>.bak-<timestamp>`.
2. Replace it with a symlink to `~/.ai/skills`.
3. Back up any existing laws file/root to `<path>.bak-<timestamp>`.
4. Replace it with a symlink to `~/.ai/laws/global_rules.md`.

Use `~/.ai/skills/ai-setup/scripts/ai-setup.sh hotwire <tool>` for each known tool. Use `hotwire-generic <tool> <skills-path> <laws-path>` for tools not in the built-in map.

Always prefer the built-in map for the 12 above. Ask the user before running `hotwire-generic`.

## 4. Install missing tools

If the user wants a missing tool, the install command menu is the same one `ai-battle` already has:

```bash
~/.ai/skills/ai-battle/scripts/battle_runner.sh --connect <tool>
```

Do not auto-install without the user confirming the exact command. After a successful install, immediately hotwire that tool.

## 5. Re-run behavior

`ai-setup` is idempotent:

- Already-correct symlinks are skipped.
- Broken symlinks are removed and recreated.
- New skills added to `~/.ai/skills` are picked up by all linked tools.
- Backups are timestamped, so repeated runs never overwrite the same `.bak`.

## 6. Safety rules

- Never `rm -rf` an existing directory; always rename it to `.bak-<timestamp>`.
- Never run a tool installer unprompted.
- Report every change made and every tool left unlinked.

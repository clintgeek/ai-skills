---
name: ai-setup
description: One-shot and re-runnable bootstrap for a new machine. Clones the shared skills repo, detects installed AI CLI tools from the ai-battle registry, hotwires their skill and laws roots to ~/.ai and ~/.ai/laws, and can install missing tools.
---

# /ai-setup — Shared AI Environment Bootstrap

Use this skill when the user wants to:

- Set up a new machine with all their AI tools.
- Re-run `ai-setup` after adding a new tool or skill.
- Install a new AI CLI and hotwire it to the shared folders.
- Sync skills and laws across Claude, Devin, Copilot, etc.

## 1. Bootstrap

1. Verify this repo is at `~/.ai`.
   This repo is expected to live at `~/.ai`. If it is checked out somewhere else, ask the user whether to move it to `~/.ai`. If they do not want to move it, use the actual checkout path in place of every `~/.ai` reference below; `ai-setup` also honors `AI_SKILLS` and `AI_LAWS` if you prefer to export those instead.
   If `~/.ai` is still missing, clone `git@github.com:clintgeek/ai-skills.git` into it.
2. If `~/.ai/laws` is missing, create it and ensure `~/.ai/laws/global_rules.md` exists.
3. Report the state of both directories.

## 2. Inventory

Run `~/.ai/skills/ai-setup/scripts/ai-setup inventory` to see which of the 6 tracked AI CLIs are installed and which are already hotwired.

The registry is:

| binary | tool | family |
| :--- | :--- | :--- |
| `devin` | Cognition Devin CLI | cognition |
| `claude` | Anthropic Claude Code | anthropic |
| `agy` | Google Antigravity CLI | google |
| `copilot` | GitHub Copilot CLI | github |
| `codex` | OpenAI Codex CLI | openai |
| `opencode` | opencode | opencode |

## 3. Hotwire installed tools

The repo must be checked out first: `hotwire` refuses to link a tool at a
missing `~/.ai/skills`. Linking into nothing would leave the tool on dangling
symlinks and cause a starter `global_rules.md` to be written, which makes
`~/.ai` exist, non-empty, and not a git checkout — after which `machine-setup`
will not clone over it and the laws stay a placeholder.

For each installed tool:

1. Back up any existing skill root to `<root>.bak-<timestamp>`.
2. Replace it with a symlink to `~/.ai/skills` (the skills *subdirectory* — a tool's skills root must contain `<skill>/SKILL.md` directly, so linking it at the repo root hides every skill).
3. Back up any existing laws file/root to `<path>.bak-<timestamp>`.
4. Replace it with a symlink to `~/.ai/laws/global_rules.md`.

Use `~/.ai/skills/ai-setup/scripts/ai-setup hotwire <tool>` for each known tool. Use `hotwire-generic <tool> <skills-path> <laws-path>` for tools not in the built-in map.

Always prefer the built-in map for the 11 above. Ask the user before running `hotwire-generic`.

## 4. Install missing tools

If the user wants a missing tool, get the install command from the shared registry:

```bash
~/.ai/skills/ai-setup/scripts/ai-setup install <tool>
```

Add `--yes` to run the install command automatically:

```bash
~/.ai/skills/ai-setup/scripts/ai-setup install <tool> --yes
```

The tool binary/family/install metadata lives in `~/.ai/skills/ai-setup/lib/ai-tools.sh`; both `ai-setup` and `ai-battle --connect` use the same source, so nothing is duplicated. Do not auto-install without the user confirming the exact command. After a successful install, immediately hotwire that tool.

## 5. Re-run behavior

`ai-setup` is idempotent:

- Already-correct symlinks are skipped.
- Dangling symlinks are removed and recreated (a broken link holds no content
  worth preserving).
- A symlink already pointing inside `~/.ai` is one of ours from an earlier run,
  so it is replaced rather than backed up — otherwise every re-run left another
  `.bak-<timestamp>` symlink behind.
- Everything else — real files, real directories, and symlinks pointing
  somewhere we do not own — is always moved to `.bak-<timestamp>`, never
  deleted.
- New skills added to `~/.ai` are picked up by all linked tools.
- Backups are timestamped, so repeated runs never overwrite the same `.bak`.

## 6. Safety rules

- Never `rm -rf` an existing directory; always rename it to `.bak-<timestamp>`.
- Never run a tool installer unprompted.
- Report every change made and every tool left unlinked.

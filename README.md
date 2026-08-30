# ai-skills

A single, shared skill repo for every AI tool I use. Each tool's global skills directory is symlinked here so they all see the same set.

## Currently wired up

- `~/.claude/skills` -> `~/.ai/skills`
- `~/.codeium/windsurf/skills` -> `~/.ai/skills`
- `~/.copilot/skills` -> `~/.ai/skills`
- Devin also picks these up through its `claude` and `windsurf` config imports.

## Adding a skill

1. Create a new folder under `~/.ai/skills/`.
2. Add a `SKILL.md` with YAML frontmatter:

```markdown
---
name: my-skill
description: What it does and when to use it.
---

# my-skill

Instructions go here.
```

3. Restart or reload the target tool. For Devin, `devin skills list` should show it.

## Syncing to a new machine

```bash
git clone git@github.com:clintgeek/ai-skills.git ~/.ai/skills
ln -s ~/.ai/skills ~/.claude/skills
ln -s ~/.ai/skills ~/.codeium/windsurf/skills
ln -s ~/.ai/skills ~/.copilot/skills
```

Then reinstall the `.agents` skills through your normal plugin/workflow setup.

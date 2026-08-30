# ai-skills

A single, shared home for every AI skill I care about. `~/.ai/skills` is the repo. `~/.ai/laws` is the shared rules directory. Every installed AI CLI is hotwired to both so they all see the same skills and the same global rules, and any new machine can be bootstrapped from this README.

## For the AI assistant running on a new machine

If you are reading this, the human wants the environment set up. Do the following, stopping for confirmation on anything that mutates the system.

### 1. Ensure this repo is at `~/.ai/skills`

If `~/.ai/skills` is not a git repo, clone it:

```bash
mkdir -p ~/.ai
if [[ ! -d ~/.ai/skills/.git ]]; then
  git clone git@github.com:clintgeek/ai-skills.git ~/.ai/skills
fi
```

### 2. Run the inventory

```bash
~/.ai/skills/ai-setup/scripts/ai-setup.sh inventory
```

This shows which of the 12 tracked AI CLIs are installed and which are already hotwired.

### 3. Hotwire every installed tool

For each tool that shows `installed: yes`, run:

```bash
~/.ai/skills/ai-setup/scripts/ai-setup.sh hotwire <tool>
```

Valid names: `devin`, `claude`, `agy`, `gemini`, `copilot`, `codex`, `opencode`, `goose`, `aider`, `cursor-agent`, `amp`, `qwen`.

If a tool is installed but has no built-in path map, use `hotwire-generic` with paths the user provides, or ask before touching it:

```bash
~/.ai/skills/ai-setup/scripts/ai-setup.sh hotwire-generic <tool> <skills-path> <laws-path>
```

`hotwire` and `hotwire-generic` make timestamped `.bak` backups before replacing any existing skill/laws directories or files.

### 4. Offer to install missing tools

For any tool the user wants that is not installed:

```bash
~/.ai/skills/ai-setup/scripts/ai-setup.sh install <tool>
```

This prints the install command and notes. Only run it without confirming if the user explicitly told you to use the `--yes` flag:

```bash
~/.ai/skills/ai-setup/scripts/ai-setup.sh install <tool> --yes
```

After a successful install, immediately run `hotwire <tool>`.

### 5. Verify the setup

```bash
devin skills list
```

You should see `ai-battle`, `ai-setup`, and `ui-design` from this repo, plus whatever `.agents` skills are present on the system.

### 6. Leave the human a report

List what was linked, what was already linked, what was backed up, and which tools are still missing. Point them at `~/.ai/skills/ai-setup/SKILL.md` if they want the full skill prompt.

---

## For a human doing this manually

### Quickstart

1. Install one AI CLI — `devin` is the easiest:

   ```bash
   curl -fsSL https://cli.devin.ai/install.sh | bash
   ```

2. Clone the repo:

   ```bash
   git clone git@github.com:clintgeek/ai-skills.git ~/.ai/skills
   ```

3. Run the bootstrap:

   ```bash
   ~/.ai/skills/ai-setup/scripts/ai-setup.sh inventory
   ~/.ai/skills/ai-setup/scripts/ai-setup.sh hotwire <tool>
   ```

4. Verify:

   ```bash
   devin skills list
   ```

### What the wiring actually looks like

`ai-setup` replaces each tool's global skills and laws paths with symlinks to the shared locations:

- `~/.claude/skills` -> `~/.ai/skills`
- `~/.codeium/windsurf/skills` -> `~/.ai/skills`
- `~/.copilot/skills` -> `~/.ai/skills`
- `~/.config/devin/skills` -> `~/.ai/skills`
- `~/.claude/CLAUDE.md` -> `~/.ai/laws/global_rules.md`
- `~/.config/devin/global_rules.md` -> `~/.ai/laws/global_rules.md`
- `~/.copilot/copilot-instructions.md` -> `~/.ai/laws/global_rules.md`

`~/.ai/laws` is outside this repo by default. It is the single place for always-on rules that every tool reads.

### Re-run on an existing machine

`ai-setup` is idempotent. Just run:

```bash
~/.ai/skills/ai-setup/scripts/ai-setup.sh inventory
```

and `hotwire` anything that is not yet linked. Backups are timestamped, so repeated runs never clobber the same `.bak`.

---

## Repo layout

- `ai-setup/` — the setup skill and shared tool registry.
  - `SKILL.md` — the full prompt for an AI assistant.
  - `scripts/ai-setup.sh` — the setup runner.
  - `lib/ai-tools.sh` — the 12-tool registry (binary, family, install commands, skill/laws paths). Both `ai-setup` and `ai-battle` source this.
- `ai-battle/` — adversarial cross-model code review skill.
  - `SKILL.md` — the battle prompt.
  - `scripts/battle_runner.sh` — the battle dispatcher.
- `ui-design/` — frontend/UI design skill.
- `LICENSE` — MIT.
- `.gitignore` — ignores `.env`, `*.key`, backups, and local noise.

## Adding a new skill

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

3. Commit and push.
4. Linked tools will pick it up the next time they reload skills. In Devin, `devin skills list` should show it.

## Adding a new AI CLI to the registry

Edit `ai-setup/lib/ai-tools.sh` and add the binary, display name, family, install commands per OS, and best-guess skill/laws paths. Both `ai-setup` and `ai-battle --connect` will use it automatically.

## .agents skills

Some tools (Devin especially) may also have packaged skills under `~/.agents/skills` or `~/.config/devin/skills.bak`. `ai-setup` does not put these in the shared repo; it backs up any existing tool directories before replacing them with symlinks. Reinstall packaged skills through the normal plugin manager, or restore from the `.bak` directory if needed.

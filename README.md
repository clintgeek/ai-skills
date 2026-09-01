# ai-skills

A single, shared home for every AI skill I care about. `~/.ai` is the repo. `~/.ai/laws` is the shared rules directory. Every installed AI CLI is hotwired to both so they all see the same skills and the same global rules, and any new machine can be bootstrapped from this README.

For the full design specification, see [`DOCS/THE_SPEC.md`](DOCS/THE_SPEC.md).

## For the AI assistant running on a new machine

If you are reading this, the human wants the environment set up. Do the following, stopping for confirmation on anything that mutates the system.

### 1. Verify this repo is at `~/.ai`

This repo is expected to live at `~/.ai`. If it was checked out somewhere else, ask the user whether to move it to `~/.ai`. If they do not want to move it, use the actual checkout path in place of every `~/.ai` reference in the commands below; the `ai-setup` script also honors `AI_SKILLS` and `AI_LAWS` if you prefer to export those instead.

If `~/.ai` is not a git repo, clone it:

```bash
mkdir -p ~/.ai
if [[ ! -d ~/.ai/.git ]]; then
  git clone git@github.com:clintgeek/ai-skills.git ~/.ai
fi
```

### 2. Run the inventory

```bash
~/.ai/skills/ai-setup/scripts/ai-setup inventory
```

This shows which of the 6 tracked AI CLIs are installed and which are already hotwired.

### 3. Hotwire every installed tool

For each tool that shows `installed: yes`, run:

```bash
~/.ai/skills/ai-setup/scripts/ai-setup hotwire <tool>
```

Valid names: `devin`, `claude`, `agy`, `copilot`, `codex`, `opencode`.

Anything else wires with `hotwire-generic <tool> <skills-path> <laws-path>` — the registry is a convenience for tools whose paths are vetted, not a limit on what can be hotwired.

If a tool is installed but has no built-in path map, use `hotwire-generic` with paths the user provides, or ask before touching it:

```bash
~/.ai/skills/ai-setup/scripts/ai-setup hotwire-generic <tool> <skills-path> <laws-path>
```

`hotwire` and `hotwire-generic` make timestamped `.bak` backups before replacing any existing skill/laws directories or files.

### 4. Offer to install missing tools

For any tool the user wants that is not installed:

```bash
~/.ai/skills/ai-setup/scripts/ai-setup install <tool>
```

This prints the install command and notes. Only run it without confirming if the user explicitly told you to use the `--yes` flag:

```bash
~/.ai/skills/ai-setup/scripts/ai-setup install <tool> --yes
```

After a successful install, immediately run `hotwire <tool>`.

### 5. Verify the setup

```bash
devin skills list
```

You should see `ai-battle`, `ai-setup`, `machine-setup`, `spec-builder`, and `ui-design` from this repo, plus whatever `.agents` skills are present on the system.

### 6. Leave the human a report

List what was linked, what was already linked, what was backed up, and which tools are still missing. Point them at `~/.ai/skills/ai-setup/SKILL.md` if they want the full skill prompt.

---

## For a human doing this manually

### Quickstart

Two commands on a bare machine. **`git` is the only prerequisite** — and you
need it to clone this anyway.

1. Clone the repo:

   ```bash
   git clone git@github.com:clintgeek/ai-skills.git ~/.ai
   ```

2. Run the bootstrap:

   ```bash
   ~/.ai/skills/machine-setup/scripts/machine-setup
   ```

   It installs Homebrew (macOS), zsh + a modern bash, makes zsh your login
   shell, clones the repos in `skills/machine-setup/repos.conf`, then shows you
   a roster of AI CLIs and installs and hotwires the ones you pick.

   Unattended: `machine-setup --clis claude,devin --yes`
   Preview only: `machine-setup --dry-run`

3. Verify:

   ```bash
   devin skills list      # or: claude, and check /machine-setup is listed
   ```

**Apps are not installed by the bootstrap, on purpose.** There is no app
catalog — a committed list of `brew install` commands goes stale, and "is this
already installed?" is something an agent can just check. Once bootstrapped,
ask your agent to set the machine up; `skills/machine-setup/SKILL.md` tells it
how (look first, propose a concrete plan, confirm before mutating).

### What the wiring actually looks like

`ai-setup` replaces each tool's global skills and laws paths with symlinks to the shared locations. Note the skills link targets `~/.ai/skills`, not the repo root: a tool's skills root must contain `<skill>/SKILL.md` directly, so pointing it at `~/.ai` hides every skill without any error:

- `~/.claude/skills` -> `~/.ai/skills`
- `~/.copilot/skills` -> `~/.ai/skills`
- `~/.config/devin/skills` -> `~/.ai/skills`
- `~/.claude/CLAUDE.md` -> `~/.ai/laws/global_rules.md`
- `~/.config/devin/global_rules.md` -> `~/.ai/laws/global_rules.md`
- `~/.copilot/copilot-instructions.md` -> `~/.ai/laws/global_rules.md`

`~/.ai/laws` is part of this repo. It contains `THE_SAGE_LAWS.md` and a `global_rules.md` symlink that every tool reads.

### Re-run on an existing machine

`ai-setup` is idempotent. Just run:

```bash
~/.ai/skills/ai-setup/scripts/ai-setup inventory
```

and `hotwire` anything that is not yet linked. Backups are timestamped, so repeated runs never clobber the same `.bak`.

---

## Bootstrapping a bare machine

Every entry point is a `#!/bin/sh` wrapper over `lib/bootstrap.sh`, so a machine
with nothing but `sh` and `git` can run them. In dependency order, the
bootstrapper guarantees:

1. **Homebrew** (macOS) — Apple ships no package manager and every mac install
   command in the catalog is a `brew install`, so this is a hard prerequisite,
   not a nicety. Added to `PATH` for the current process *and* persisted to
   `~/.zprofile`.
2. **zsh** — installed via the detected package manager if missing.
3. **bash 4+** — `skills/ai-setup/lib/ai-tools.sh` uses associative arrays, and
   macOS ships bash 3.2 permanently for licensing reasons. `lib/spec_builder.sh`
   is deliberately bash-3.2-clean and needs none of this.
4. **zsh as the login shell** — via `chsh`, adding it to `/etc/shells` first.

It mutates nothing without consent: pass `--yes` (the wrappers forward it as
`BS_ASSUME_YES`) or answer the prompt. Knobs:

| Variable | Effect |
| :--- | :--- |
| `BS_ASSUME_YES=1` | Install without prompting |
| `BS_DRY_RUN=1` | Print every mutation, change nothing |
| `BS_NO_CHSH=1` | Install zsh but never touch the login shell |
| `BS_ZSH_PREFER=newest` | Use the newest zsh as login shell instead of the system one |

By default the login shell is set to the **system** zsh (`/bin/zsh` on macOS)
rather than Homebrew's. A login shell living under `/opt/homebrew` locks you out
if that install is ever removed or the volume is unmounted; `BS_ZSH_PREFER=newest`
opts into it anyway. If your login shell is already some zsh, it is left alone.

Preview what it would do to the machine you are on:

```bash
BS_DRY_RUN=1 /bin/sh -c '. ~/.ai/lib/bootstrap.sh; bs_bootstrap'
```

## Repo layout

- `lib/bootstrap.sh` — POSIX `sh` machine bootstrapper (brew, zsh, bash 4+, login shell). Sourced by every wrapper.
- `skills/ai-setup/` — the setup skill and shared tool registry.
  - `SKILL.md` — the full prompt for an AI assistant.
  - `scripts/ai-setup` — `sh` wrapper: bootstrap, then re-exec under bash 4+.
  - `scripts/ai-setup.sh` — the setup runner.
  - `lib/ai-tools.sh` — the 6-tool registry (binary, family, install commands, skill/laws paths). Both `ai-setup` and `ai-battle` source this.
- `skills/ai-battle/` — adversarial cross-model code review skill.
  - `SKILL.md` — the battle prompt.
  - `scripts/ai-battle` — `sh` wrapper: bootstrap, then re-exec under bash 4+.
  - `scripts/battle_runner.sh` — the battle dispatcher.
- `skills/machine-setup/` — bare-machine bootstrap.
  - `SKILL.md` — the bootstrap contract, plus how to do app setup conversationally.
  - `scripts/machine-setup` — POSIX `sh` bootstrapper (brew, zsh, bash, repos, CLIs).
  - `repos.conf` — the repos to clone on a new machine. Committed, so it travels.
- `skills/spec-builder/` — find or build a human-owned spec.
- `skills/ui-design/` — frontend/UI design skill.
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

Edit `skills/ai-setup/lib/ai-tools.sh` and add the binary, display name, family, install commands per OS, and best-guess skill/laws paths. Both `ai-setup` and `ai-battle --connect` will use it automatically.

## .agents skills

Some tools (Devin especially) may also have packaged skills under `~/.agents/skills` or `~/.config/devin/skills.bak`. `ai-setup` does not put these in the shared repo; it backs up any existing tool directories before replacing them with symlinks. Reinstall packaged skills through the normal plugin manager, or restore from the `.bak` directory if needed.

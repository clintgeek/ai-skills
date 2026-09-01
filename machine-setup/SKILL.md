---
name: machine-setup
description: Bootstrap a new PC by interviewing the user about its role, suggesting common apps from a shared catalog, and letting them choose what to install. Also clones and initializes the user's personal config repos (~/.ai, ~/dotfiles) from a committed repos.conf. Use when the user says "set up a new machine", "what should I install on this computer", or "bootstrap my Mac/PC".
---

# /machine-setup — New-Machine Bootstrap Wizard

Use this skill when the user wants to set up a new computer and get suggestions for common apps, or when they want to run the machine-setup wizard.

## 1. Trigger phrases

- "set up this new machine"
- "what should I install on this computer?"
- "bootstrap my Mac/PC"
- "install my dotfiles and apps on a new machine"
- "run machine-setup"

## 2. What it does

The wizard at `machine-setup/scripts/machine-wizard`:

1. **Personal repos first** — clones or pulls the repos listed in `machine-setup/repos.conf` (e.g. `~/.ai`, `~/dotfiles`). Runs any configured post-clone script (e.g. `dotfiles/install.sh`) after a fresh clone.
2. **Interview** — asks the user what the machine is for and which categories of apps they want.
3. **Recommends** — pre-selects a default checklist from `lib/app-catalog.sh` based on role + categories.
4. **Lets the user edit** — they can remove, add, or confirm the list.
5. **Installs** — runs the OS-appropriate install command for each selected app.
6. **Reports** — prints what was installed, skipped, or failed.

## 3. How to run it

Interactive mode (best in a terminal):

```bash
~/.ai/machine-setup/scripts/machine-wizard
```

Non-interactive / repeatable mode:

```bash
~/.ai/machine-setup/scripts/machine-wizard \
  --role dev \
  --categories terminal,productivity,security \
  --extras zoom,notion \
  --yes
```

For a headless VPS (CLI-only) and also hotwire already-installed AI CLIs:

```bash
~/.ai/machine-setup/scripts/machine-wizard \
  --role admin \
  --categories cli \
  --ai \
  --yes
```

Preview only:

```bash
~/.ai/machine-setup/scripts/machine-wizard --dry-run
```

Set up repos only:

```bash
~/.ai/machine-setup/scripts/machine-wizard --repos-only --yes
```

## 4. Constraints

- Never run the install step without an explicit `--yes` flag or a manual `y` confirmation in interactive mode.
- If the user is not in a terminal and has not provided `--yes`, print the plan and tell them to run with `--yes` themselves.
- The wizard uses the native package manager per OS (`brew`, `apt-get`, `winget`, etc.). It does not download binaries on its own.
- If `~/.ai` or `~/dotfiles` already exists and is a git repo, the wizard pulls instead of re-cloning.
- After the wizard finishes, you may offer to run `ai-setup` to install and hotwire the AI CLI tools.

## 5. Customizing the catalog

- Add new apps in `lib/app-catalog.sh`.
- Add or change personal repos in `machine-setup/repos.conf`.
- Both files are committed, so the same catalog travels to new machines.

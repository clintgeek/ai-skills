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

The wizard at `skills/machine-setup/scripts/machine-wizard`:

1. **Personal repos first** — clones or pulls the repos listed in `skills/machine-setup/repos.conf` (e.g. `~/.ai`, `~/dotfiles`). Runs any configured post-clone script (e.g. `dotfiles/install.sh`) after a fresh clone.
2. **Interview** — asks the user what the machine is for and which categories of apps they want.
3. **Recommends** — pre-selects a default checklist from `lib/app-catalog.zsh` based on role + categories.
4. **Lets the user edit** — an interactive checklist where they can toggle
   items on *and off* by number (so a mistaken removal is recoverable), add an
   app id, a package name, or a raw install command with `+<text>`, `all` /
   `none`, `list`, `help`, and `done`.
5. **Installs** — runs the OS-appropriate install command for each selected app.
6. **Reports** — prints what was installed, skipped, or failed.

## 3. How to run it

Interactive mode (best in a terminal):

```bash
~/.ai/skills/machine-setup/scripts/machine-wizard
```

Non-interactive / repeatable mode:

```bash
~/.ai/skills/machine-setup/scripts/machine-wizard \
  --role dev,design \
  --categories terminal,productivity,security \
  --extras zoom,notion,neovim \
  --extra-cmd 'brew tap foo/bar && brew install baz' \
  --yes
```

**Roles** (`--role`, comma-separated, union): `dev`, `design`, `data`,
`writing`, `gaming`, `admin`, `general`. Roles and categories are separate axes
— a role is what the machine is *for*, a category is what *kind* of app it is —
so `--role dev` and `--categories dev-tools` select different things.

**Categories** (`--categories`, comma-separated): `cli`, `terminal`, `browser`,
`productivity`, `security`, `media`, `dev-tools`, `cloud`, `communication`.

**Extras** — two flags, because names and commands need different parsing:

| Flag | For | Splitting |
| :--- | :--- | :--- |
| `--extras` | app ids and package names | comma-separated; repeatable |
| `--extra-cmd` | one raw install command | never split; repeatable |

An `--extras` entry that is not a catalog id is installed as a **package** via
the local package manager, so custom app names are never silently dropped. An
entry containing shell syntax or whitespace is run verbatim. Because `--extras`
is comma-delimited, a command containing a comma is ambiguous and is **refused**
with a pointer to `--extra-cmd` rather than being split into fragments.

For a headless VPS (CLI-only) and also hotwire already-installed AI CLIs:

```bash
~/.ai/skills/machine-setup/scripts/machine-wizard \
  --role admin \
  --categories cli \
  --ai \
  --yes
```

`--ai` only **hotwires CLIs that are already installed**. Running a vendor's
installer is a separate opt-in, because `ai-setup`'s own rule is "never run a
tool installer unprompted":

```bash
~/.ai/skills/machine-setup/scripts/machine-wizard --role admin --categories cli --ai-install --yes
```

Preview only:

```bash
~/.ai/skills/machine-setup/scripts/machine-wizard --dry-run
```

Set up repos only:

```bash
~/.ai/skills/machine-setup/scripts/machine-wizard --repos-only --yes
```

## 4. Constraints

- Never run the install step without an explicit `--yes` flag or a manual `y` confirmation in interactive mode.
- If the user is not in a terminal and has not provided `--yes`, print the plan and tell them to run with `--yes` themselves.
- The wizard uses the native package manager per OS (`brew`, `apt-get`, `winget`, etc.). It does not download binaries on its own.
- On macOS there is no native package manager, so the `scripts/machine-wizard` wrapper bootstraps Homebrew first via `lib/bootstrap.sh` — without it every mac install command would fail. The same wrapper guarantees zsh, a bash 4+, and zsh as the login shell. It honors the wizard's `--yes` and `--dry-run`, so it never installs anything the wizard itself would have paused for.
- Always invoke `scripts/machine-wizard` (the `sh` wrapper), not `machine-wizard.zsh` directly — the `.zsh` script assumes the bootstrapper has already run.
- If `~/.ai` or `~/dotfiles` already exists and is a git repo, the wizard pulls instead of re-cloning.
- After the wizard finishes, you may offer to run `ai-setup` to install and hotwire the AI CLI tools.
- `--ai` hotwires only already-installed CLIs; `--ai-install` additionally runs each missing tool's installer. Never substitute one for the other — the second runs vendor scripts the user did not name.

## 5. Customizing the catalog

- Add new apps in `lib/app-catalog.zsh`. Each app needs `APP_NAME`, `APP_TAGS`
  (categories, plus the special `base` tag for always-install), and usually
  `APP_ROLES`. Every role in `VALID_ROLES` must appear on at least one app or it
  silently selects nothing beyond `base` — `lib/tests/machine_setup_test.zsh`
  asserts this, and the wizard warns at runtime.
- Add or change personal repos in `skills/machine-setup/repos.conf`.
- Both files are committed, so the same catalog travels to new machines.

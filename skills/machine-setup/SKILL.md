---
name: machine-setup
description: >-
  Bootstrap a bare machine to the point where an AI agent can work — Homebrew
  on macOS, zsh as the login shell, a modern bash, the user's repos, and their
  chosen AI CLIs installed and hotwired to ~/.ai. Then set the machine up
  conversationally: work out what is already installed and install what the
  user actually wants, rather than reading it from a catalog. Use when the user
  says "set up a new machine", "bootstrap my Mac/PC", or "what should I install
  on this computer".
---

# /machine-setup — New-Machine Bootstrap, then Conversational Setup

This skill has two halves, and the split matters.

**The bootstrap is a script**, because it must run before zsh, before a modern
bash, and before any agent exists. **The app setup is a conversation**, because
you can look at the machine and reason about it, which beats any list this repo
could freeze in a file.

## 1. Trigger phrases

- "set up this new machine" / "bootstrap my Mac"
- "what should I install on this computer?"
- "install my dotfiles and apps on a new machine"
- "run machine-setup"

## 2. The bootstrap script

```bash
~/.ai/skills/machine-setup/scripts/machine-setup
```

POSIX `sh`. Four steps, in dependency order:

1. **Homebrew** (macOS) — Apple ships no package manager and everything
   downstream needs one, so this is a hard prerequisite, not a nicety.
2. **zsh + a modern bash**, and zsh set as the **login shell**. The login shell
   defaults to the *system* zsh (`/bin/zsh`), not Homebrew's: a login shell under
   `/opt/homebrew` locks the user out if that install disappears.
   `BS_ZSH_PREFER=path` opts into whatever `command -v zsh` finds instead.
3. **Repos** from `repos.conf` — pulls a checkout, clones into a free path, and
   **refuses to touch anything else**. It will not move a real directory aside to
   clone over it.
4. **AI CLIs** — shows a roster, takes a selection, installs and hotwires them
   via `ai-setup select`.

Options:

| Flag | Effect |
| :--- | :--- |
| `--clis <list>` | CLIs to install non-interactively: numbers and/or names, or `all` |
| `--no-clis` | Skip the AI CLI step |
| `--no-repos` | Skip the repo step |
| `--yes` | Do not prompt |
| `--dry-run` | Print every mutation, change nothing |

```bash
# Interactive: roster + prompt for the CLIs
~/.ai/skills/machine-setup/scripts/machine-setup

# Unattended
~/.ai/skills/machine-setup/scripts/machine-setup --clis claude,devin --yes

# Preview, touching nothing
~/.ai/skills/machine-setup/scripts/machine-setup --dry-run
```

**Prerequisites**

- **`git`** — you cloned this repo, so you have it.
- **A non-root user with sudo.** This is never run as root, and it refuses to be.
  Everything it does configures the *invoking user's* account: `~/.ai`, the tool
  symlinks under `$HOME`, the login shell, `~/.zprofile`. As root all of that
  lands on root's account instead, silently and plausibly.

  If a provider hands you a box where root is the only account, setting it up
  properly is **the operator's job, done by hand, before running this**: create a
  non-root user with key-only access and no password, grant it sudo, disable root
  login. The tool does not do that for you and should not — closing off root
  login is a decision about a machine's security posture, not a side effect of
  installing zsh.

  `FS_ALLOW_ROOT=1` overrides, for a container or image build where root really
  is the only user that will ever exist.

## 3. After the bootstrap: set the machine up by talking

The script installs **no apps on purpose**. There is no catalog, no role
taxonomy, and no checklist, because all three were worse than just looking:

- A committed `brew install` list goes stale. You can check what a package is
  called *today*.
- "Which apps does a design machine want?" is a judgment call that belongs to the
  user, not to a tag in a file.
- "Is it already installed?" is `command -v`, `brew list`, `ls /Applications` —
  discovery, which is what you are for.

So when the user wants apps installed:

1. **Ask what the machine is for**, in their words. Do not offer a fixed menu of
   roles; ask what they will do with it and what they miss from their last setup.
2. **Look before proposing.** Check what is already present — package manager
   lists, `command -v`, `/Applications`, existing dotfiles. Never propose
   installing something that is already there.
3. **Propose a concrete plan** with the exact command per app, grouped so it is
   skimmable. Say which are already installed and being skipped.
4. **Get explicit confirmation before mutating anything.** One `y` for the whole
   plan is fine; silence is not. This is the same contract the bootstrap script
   enforces, and it does not lapse because a human is talking to you instead.
5. **Install, then report** what succeeded, what was already present, what
   failed, and what you skipped.
6. **Offer to record durable choices.** A repo the user always wants belongs in
   `repos.conf`, which is committed and travels to the next machine. An app list
   does not — next time, look again.

## 4. Constraints

- Never install anything without an explicit `--yes` or a clear confirmation.
- Never run a vendor's installer the user did not ask for. Installing an AI CLI
  is the bootstrap's job *because the user picked it from the roster*.
- Never move or delete an existing directory to make room. Report it and let the
  user decide.
- The login shell belongs to `lib/bootstrap.sh`. Do not let a third-party
  installer change it (`oh-my-zsh`, for one, defaults to doing exactly that —
  pass `CHSH=no`).
- Prefer the package manager over `curl | sh`. When a project only ships a shell
  installer, say so plainly before running it.

## 5. What lives where

- `scripts/machine-setup` — the bootstrap (POSIX `sh`).
- `repos.conf` — the user's repos. Committed, so it travels. Edit this when they
  name a repo they always want.
- `lib/bootstrap.sh` — brew / zsh / bash / login-shell logic, shared with the
  other skills' wrappers.
- `lib/fs-helpers.sh` — backup-before-replace, shared with `ai-setup`.

# ai-skills — Product Specification

**Version:** 1.0  
**Status:** Living document. Update this file whenever the repo structure, CLI, or supported tool set changes.

---

## 1. Purpose

`ai-skills` is a single source of truth for every AI skill and global rule ("laws") I want all my AI coding assistants to share. It lives at `~/.ai`, is backed by Git, and is designed so that a fresh laptop with nothing but `git` and one AI CLI (usually Devin) can be hotwired to the same skill set in minutes.

The system has three goals:

1. **One place to edit.** Add a skill here; all tools see it.
2. **One place for rules.** Keep always-on constraints in `~/.ai/laws`; every hotwired tool reads the same `global_rules.md`.
3. **One command to bootstrap.** `ai-setup` clones, inventories, installs missing tools, and hotwires skill and laws paths.

---

## 2. Core Concepts

### 2.1 Skill

A skill is a folder containing at minimum a `SKILL.md` file with YAML frontmatter.

```markdown
---
name: my-skill
description: What it does and when to use it.
---

# my-skill

Instructions for the assistant.
```

Skills may also ship helper scripts in a `scripts/` subdirectory. The loader is responsible for finding `SKILL.md`; the content is opaque to the repo.

### 2.2 Laws

"Laws" are always-on rules that apply to every hotwired AI tool. They live in `~/.ai/laws/global_rules.md`, which is a symlink to `~/.ai/laws/THE_SAGE_LAWS.md` in this repo. Each tool's global rules path is replaced with a symlink to that one file.

Laws are for constraints that should survive across all tools: identity, tone, file-access rules, security policies, human-in-the-loop requirements, etc.

### 2.3 Tool Registry

`skills/ai-setup/lib/ai-tools.sh` is the canonical registry of the 11 AI CLIs the system knows about. It stores:

- Binary name
- Display name
- Model family
- Install commands per OS
- Install notes
- Best-guess skill root
- Best-guess laws root
- Whether the path map is known to be correct

Both `ai-setup` and `ai-battle` source this file. It is the only place these values should be maintained.

### 2.4 Shared tools (`lib/`)

Repo-root `lib/` holds helper scripts shared across skills (as opposed to `skills/ai-setup/lib/ai-tools.sh`, which predates it and stays put for compatibility). Each is written to work both as a CLI and as a sourceable bash library. Current entries:

- `lib/fs-helpers.sh` — `backup_path` and `ensure_dir`, in POSIX `sh` so the bash side (`ai-setup.sh`) and the zsh side (machine-setup) share ONE implementation instead of a copy each. `backup_path` moves anything real aside to `.bak-<timestamp>`, but removes a dangling symlink or a symlink already pointing inside `$AI_ROOT` — those hold no content, and backing them up left a new stale link on every re-run. Targets are resolved to absolute paths before comparison (via `cd` in a subshell, since `readlink -f` and `realpath` are GNU-only and absent on macOS), so a hand-made *relative* link is recognised as ours too.
- `lib/report-check.sh` — validates that an ai-battle challenger actually produced a review. Exit 4 for empty, trivial, findings-free, or permission-blocked output; a loud warning for a report truncated short of its own claimed finding count. Exists because the runner twice reported success over a report containing nothing.
- `lib/tests/` — `spec_builder_test.sh`, `bootstrap_test.sh`, `machine_setup_test.sh`, `report_check_test.sh`, and `fs_helpers_test.sh`. All five run in CI.
- `lib/bootstrap.sh` — the shared machine bootstrapper, and the only file in the repo that is deliberately POSIX `sh`: it runs *before* the shells it installs are known to exist, so it cannot use them. Guarantees, in dependency order, Homebrew on macOS (Apple ships no package manager), zsh, a bash 4+ (for `ai-tools.sh`'s associative arrays), and zsh as the login shell. Consumers: `skills/machine-setup/scripts/machine-setup` (which IS the bootstrapper's product), plus thin `#!/bin/sh` wrappers that re-exec a bash script — `skills/ai-setup/scripts/ai-setup`, `skills/ai-battle/scripts/ai-battle`. Honors `BS_ASSUME_YES` (the caller's `--yes`), `BS_DRY_RUN`, `BS_NO_CHSH`, and `BS_ZSH_PREFER`. Mutates nothing without consent; tested by `lib/tests/bootstrap_test.sh`. Under `BS_DRY_RUN` the `BS_ZSH`/`BS_BASH` paths stay **empty** rather than being guessed — nothing was installed, so there is no path — and `bs_exec_bash` refuses instead of `exec`ing something absent. Escalation goes through `BS_SUDO`, which is `sudo -n` when there is no terminal, so an unattended run on a password-required box fails fast instead of hanging on an unanswerable prompt; `bs_check_sudo` warns about that up front rather than mid-install. Note `--dry-run` on a *skill* is deliberately NOT mapped to `BS_DRY_RUN`: those are different scopes, and an inner flag should not gain the power to change what gets installed.
- `lib/spec_builder.sh` — spec discovery (`find`), scaffolding (`build`), and find-or-scaffold (`ensure`). Scaffolds a DRAFT `TICKET-SPEC.md` pre-filled with neutral git evidence (branch, commits, diffstat, ticket IDs) and TODO requirement sections that must be filled from the original ticket/request — never reverse-engineered from the code. `--interactive` interviews the human at the terminal for the four sections and writes a banner-free spec when Intent and Requirements are answered. Consumers: `ai-battle`, and the `spec-builder` skill — a thin wrapper that makes the find→interview→write flow directly invocable as `/spec-builder` (any skill needing a spec should source the lib rather than copying the logic).
- `lib/SPEC_INTERVIEW.md` — the spec interview protocol for AI agents, which have no TTY for `--interactive`. The agent interrogates the human section by section (proposing candidates only from the ticket/request/conversation, never the diff), writes the confirmed answers into the spec, deletes the DRAFT banner, and gets sign-off. Covers ticket-less repos, where the requesting conversation is the ticket: quote the original ask, confirm builder inferences explicitly, and capture the spec when the ask lands rather than at review time.

### 2.5 Hotwiring

"Hotwiring" means replacing a tool's global skill directory and laws file with symlinks to the shared `~/.ai` and `~/.ai/laws/global_rules.md`.

Before replacing anything, `ai-setup` moves the existing path to `<path>.bak-<timestamp>`. This is non-negotiable.

---

## 3. Directory & File Layout

### 3.1 This repo (`~/.ai`)

```
~/.ai
├── .gitignore
├── LICENSE
├── README.md
├── DOCS/
│   ├── THE_SPEC.md
│   └── TICKET-SPEC.md
├── laws/
│   ├── THE_SAGE_LAWS.md
│   └── global_rules.md -> THE_SAGE_LAWS.md
├── lib/
│   ├── bootstrap.sh
│   ├── fs-helpers.sh
│   ├── spec_builder.sh
│   ├── SPEC_INTERVIEW.md
│   └── tests/
│       ├── bootstrap_test.sh
│       ├── machine_setup_test.sh
│       └── spec_builder_test.sh
├── skills/
│   ├── spec-builder/
│   │   └── SKILL.md
│   ├── ai-battle/
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       ├── ai-battle          (sh wrapper: bootstrap + re-exec)
│   │       └── battle_runner.sh
│   ├── ai-setup/
│   │   ├── SKILL.md
│   │   ├── lib/ai-tools.sh
│   │   └── scripts/
│   │       ├── ai-setup           (sh wrapper: bootstrap + re-exec)
│   │       └── ai-setup.sh
│   ├── machine-setup/
│   │   ├── SKILL.md
│   │   ├── repos.conf
│   │   └── scripts/
│   │       └── machine-setup      (POSIX sh bootstrapper)
│   └── ui-design/
│       └── SKILL.md
```

### 3.2 Laws inside this repo

`~/.ai` is this git repo. The `laws/` directory lives inside it:

```
~/.ai/
├── .gitignore
├── LICENSE
├── README.md
├── DOCS/
│   ├── THE_SPEC.md
│   └── TICKET-SPEC.md
├── laws/
│   ├── THE_SAGE_LAWS.md
│   └── global_rules.md -> THE_SAGE_LAWS.md
├── lib/
│   ├── bootstrap.sh
│   ├── fs-helpers.sh
│   ├── spec_builder.sh
│   ├── SPEC_INTERVIEW.md
│   └── tests/
│       ├── bootstrap_test.sh
│       ├── machine_setup_test.sh
│       └── spec_builder_test.sh
├── skills/
│   ├── spec-builder/
│   │   └── SKILL.md
│   ├── ai-battle/
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       ├── ai-battle          (sh wrapper: bootstrap + re-exec)
│   │       └── battle_runner.sh
│   ├── ai-setup/
│   │   ├── SKILL.md
│   │   ├── lib/ai-tools.sh
│   │   └── scripts/
│   │       ├── ai-setup           (sh wrapper: bootstrap + re-exec)
│   │       └── ai-setup.sh
│   ├── machine-setup/
│   │   ├── SKILL.md
│   │   ├── repos.conf
│   │   └── scripts/
│   │       └── machine-setup      (POSIX sh bootstrapper)
│   └── ui-design/
│       └── SKILL.md
```

`~/.ai/laws/global_rules.md` is a symlink to `THE_SAGE_LAWS.md` so every tool's rules path resolves to the same file. Edit `laws/THE_SAGE_LAWS.md` to change the rules.

### 3.3 Tool root symlinks after setup

```
~/.claude/skills -> ~/.ai/skills
~/.copilot/skills -> ~/.ai/skills
~/.config/devin/skills -> ~/.ai/skills
~/.claude/CLAUDE.md -> ~/.ai/laws/global_rules.md
~/.config/devin/global_rules.md -> ~/.ai/laws/global_rules.md
~/.copilot/copilot-instructions.md -> ~/.ai/laws/global_rules.md
```

Tools with unverified path maps (`codex`, `opencode`, `goose`, `aider`, `cursor-agent`, `amp`, `qwen`) must be hotwired with explicit paths via `hotwire-generic` until their registry entries are promoted to `KNOWN=1`. `agy` is vetted (`TOOL_KNOWN[agy]=1`) and hotwires normally; this list and the registry must agree.

---

## 4. User Flows

### 4.1 First-time setup on a new machine

1. Install one AI CLI, preferably Devin:

   ```bash
   curl -fsSL https://cli.devin.ai/install.sh | bash
   ```

2. Clone the repo:

   ```bash
   git clone git@github.com:clintgeek/ai-skills.git ~/.ai
   ```

3. Run `ai-setup` inventory:

   ```bash
   ~/.ai/skills/ai-setup/scripts/ai-setup inventory
   ```

4. Hotwire each installed tool:

   ```bash
   ~/.ai/skills/ai-setup/scripts/ai-setup hotwire <tool>
   ```

5. Install missing tools (optional, with confirmation):

   ```bash
   ~/.ai/skills/ai-setup/scripts/ai-setup install <tool>
   ~/.ai/skills/ai-setup/scripts/ai-setup install <tool> --yes
   ~/.ai/skills/ai-setup/scripts/ai-setup hotwire <tool>
   ```

6. Verify:

   ```bash
   devin skills list
   ```

### 4.2 Adding a new skill

1. Create `~/.ai/<skill-name>/SKILL.md` with proper frontmatter.
2. Test that `devin skills list` shows it.
3. `git add`, `git commit`, `git push`.
4. On other machines, `git pull` inside `~/.ai`.

### 4.3 Adding a new AI CLI to the registry

1. Edit `skills/ai-setup/lib/ai-tools.sh`.
2. Add binary, family, install commands per OS, skill/laws paths, and `KNOWN` flag.
3. If the paths are verified, set `KNOWN=1`.
4. Commit and push.

`ai-battle --connect` and `ai-setup install <tool>` will immediately use the new entry.

### 4.4 Re-running ai-setup

`ai-setup` is idempotent:

- Correct symlinks are left alone.
- Broken symlinks are recreated.
- Existing real directories are timestamped-backupped before replacement.
- New skills in `~/.ai` are picked up by all linked tools on their next skill reload.

### 4.5 Running ai-battle

`ai-battle` is an adversarial red-team review that uses this same tool registry to pick a challenger.

```bash
~/.ai/skills/ai-battle/scripts/ai-battle --diff <range>
```

When a spec exists (e.g. this file or a feature-specific spec), pass it with `--spec`:

```bash
~/.ai/skills/ai-battle/scripts/ai-battle --spec DOCS/THE_SPEC.md --diff main...HEAD
```

If no spec is passed or found (`TICKET-SPEC.md`, `SPEC.md`, `*SPEC.md`, `*spec.md`), the runner scaffolds a DRAFT `TICKET-SPEC.md` via `lib/spec_builder.sh` and exits with code 3. The builder agent then interviews the human for the requirements (protocol: `lib/SPEC_INTERVIEW.md` — proposals may come from the ticket/request, never from the diff), writes the answers into the spec, deletes the DRAFT banner, and re-runs; a human at a terminal can run `spec_builder.sh ensure --interactive` instead. Specs with an intact DRAFT banner are refused; `--no-spec` is the explicit opt-out for battling without spec grounding.

The human must approve findings before any fixes are made.

---

## 5. Tool Integration Details

| Binary | Family | Skills root | Laws root | Known |
| :--- | :--- | :--- | :--- | :--- |
| `devin` | cognition | `~/.config/devin/skills` | `~/.config/devin/global_rules.md` | yes |
| `claude` | anthropic | `~/.claude/skills` | `~/.claude/CLAUDE.md` | yes |
| `copilot` | github | `~/.copilot/skills` | `~/.copilot/copilot-instructions.md` | yes |
| `agy` | google | `~/.antigravity/skills` | `~/.antigravity/global_rules.md` | yes |

| `codex` | openai | `~/.codex/skills` | `~/.codex/global_rules.md` | no |
| `opencode` | opencode | `~/.opencode/skills` | `~/.opencode/global_rules.md` | no |
| `goose` | goose | `~/.goose/skills` | `~/.goose/global_rules.md` | no |
| `aider` | aider | `~/.aider/skills` | `~/.aider/global_rules.md` | no |
| `cursor-agent` | cursor | `~/.cursor/skills` | `~/.cursor/global_rules.md` | no |
| `amp` | sourcegraph | `~/.amp/skills` | `~/.amp/global_rules.md` | no |
| `qwen` | alibaba | `~/.qwen/skills` | `~/.qwen/global_rules.md` | no |

A "no" in `Known` means the path has not been verified on a real install. Use `hotwire-generic` or promote it after confirming the layout.

---

## 6. Safety & Idempotency Rules

1. **No destructive deletes.** Existing directories and files are always moved to `.<path>.bak-<timestamp>` before a symlink is created.
2. **No silent self-battles.** `ai-battle` refuses to match a challenger in the same model family as the caller.
3. **No auto-install without explicit consent.** `install <tool>` prints the command. `--yes` is required to run it.
4. **No secrets in this repo.** `.gitignore` covers `.env`, `*.key`, `*.pem`, `secrets/`, `.ssh/`, and backup directories.
5. **Prompt size guards.** `ai-battle` refuses to pass >100KB prompts via argv to tools that cannot accept stdin or files.
6. **Challengers run read-only.** Devin `normal`, Claude `plan`, Codex `sandbox read-only`, aider `--dry-run`, etc.
7. **No battles against empty specs.** A missing spec is scaffolded as a DRAFT and the battle exits for the builder to fill in real requirements — before challenger selection, so the scaffold happens even with no eligible opponent installed; unfilled DRAFT scaffolds are refused, spec-less `--dry-run` included; `--no-spec` is the only opt-out and warns loudly.

---

## 7. CLI Reference

### `ai-setup.sh`

| Command | Description |
| :--- | :--- |
| `clone` | Clone `~/.ai` if missing, create `~/.ai/laws` and starter `global_rules.md` |
| `inventory` | Show installed state, known/unknown, skill and laws link status |
| `hotwire <tool>` | Hotwire a known tool's skills and laws roots |
| `hotwire-generic <tool> <skills> <laws>` | Hotwire a tool with explicit paths |
| `install <tool>` | Print install command and notes |
| `install <tool> --yes` | Print and run the install command |

### `battle_runner.sh`

| Flag | Description |
| :--- | :--- |
| `--diff <range>` | Git diff or revision range to review |
| `--spec <file>` | Specification file for the reviewer (auto-found, else a DRAFT is scaffolded and the run exits 3) |
| `--no-spec` | Battle without spec grounding (explicit opt-out, loud warning) |
| `--opponent <tool>` | Force a specific challenger |
| `--report <file>` | Where to write the raw challenger report |
| `--timeout <s>` | Kill the challenger after this many seconds |
| `--connect [tool]` | Show install menu for a tool |
| `--yes` | With `--connect`, pre-confirm install |
| `--list-tools` | List installed and missing AI CLIs |

### `spec_builder.sh` (shared, `lib/`)

| Command | Description |
| :--- | :--- |
| `find [--dir <path>]` | Print the path of an existing spec file; exit 1 if none |
| `build [--out <file>] [--diff <range>] [--title <text>] [--force] [--interactive]` | Scaffold a DRAFT spec with auto-collected git evidence; `--interactive` interviews the human first (TTY only) |
| `ensure [--dir] [--out] [--diff] [--title] [--interactive]` | `find`, else `build`; exit 3 means the spec found or written is still a DRAFT needing filling (a stale draft never exits 0) |

Also sourceable as a library: `find_spec_file`, `spec_is_draft`, `run_spec_interview`, `build_spec_scaffold` (which consumes the `SPEC_INTENT` / `SPEC_REQUIREMENTS` / `SPEC_OUT_OF_SCOPE` / `SPEC_INVARIANTS` variables). Agents conduct the interview in conversation per `lib/SPEC_INTERVIEW.md`.

---

## 8. Design Rationale

### Why one `~/.ai` git repo instead of per-tool plugin installs?

Skills are mostly markdown and small scripts. Keeping them in one repo means one `git pull` syncs every tool. The per-tool skill loaders only care about file paths; symlinks let the repo stay single while each tool sees its own expected layout.

### Why are laws in the same repo?

The canonical `laws/THE_SAGE_LAWS.md` is versioned with the skills so a fresh clone includes the rules and `ai-setup` has a known good `global_rules.md` to link. The `global_rules.md` symlink is the stable path every tool reads; if you need machine-specific overrides, keep a separate `~/.env` or `~/.ai/laws/local_rules.md` and source it from `THE_SAGE_LAWS.md` without committing.

### Why is the tool registry in a shared bash library?

`ai-battle` needs the registry to pick a challenger. `ai-setup` needs the same registry to hotwire and install. One source of truth (`skills/ai-setup/lib/ai-tools.sh`) eliminates drift.

### Why does `ai-battle` not run in the same process?

The challenger must be a different model family to catch the builder's blind spots. Running it in a separate CLI process enforces that boundary.

---

## 9. Future Work

- Promote more tools from `KNOWN=0` to `KNOWN=1` after real install tests.
- Add CI that validates every `SKILL.md` has required frontmatter.
- Add `ai-setup.sh sync` to pull the repo and re-hotwire in one command.
- Consider a `~/.ai/laws` repo separate from skills for users who want versioned rules.
- ~~Add `TICKET-SPEC.md` template for battles that target a single feature.~~ Done: `lib/spec_builder.sh`.

---

## 10. How This Document Is Used

- **For humans:** The source of truth for what the repo is trying to do.
- **For AI assistants:** A specification to derive expected behavior from before touching code.
- **For `ai-battle`:** Pass this file as `--spec` so the challenger can independently evaluate whether the implementation matches the spec.

When the spec changes, commit the change immediately. A spec that drifts from the code is worse than no spec.

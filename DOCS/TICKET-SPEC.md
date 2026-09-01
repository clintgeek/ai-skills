# Specification: Add machine-setup skill

> **SUPERSEDED (2026-09-01).** Requirements 1, 2, 5, 6, 10 and 11 below describe
> an app catalog, a role/category taxonomy and an interactive checklist. All of
> that has been deliberately **removed**. It encoded knowledge a model can look
> up (install commands, package names, which apps suit which machine) and froze
> it in a file that goes stale — and every self-inflicted bug in that subsystem
> lived in it.
>
> `machine-setup` now does one job: bring a bare machine to the point where an
> agent can work (Homebrew, zsh as login shell, a modern bash, repos, AI CLIs).
> App installation is conversational, per `skills/machine-setup/SKILL.md`.
>
> Requirements 3, 4, 7, 8, 9 and 12 (committed repo list, post-clone script,
> non-interactive mode, no-install-without-consent, reuse ai-setup's backup
> pattern, final report) still hold and are still met.
>
> Kept as the historical record of why the code looked the way it did.

## 1. Intent
Add a `machine-setup` skill that bootstraps a new PC by interviewing the user about what the machine is for, suggesting common apps, and letting them choose which to install (plus add custom ones). It must also clone and initialize the user's personal config repos (`~/.ai` and `~/dotfiles`) from a committed, versioned repo list so the same setup is repeatable on any new machine.

## 2. Requirements / Acceptance Criteria
1. Detect the OS/package manager (macOS `brew`, Linux `apt`/`dnf`/etc., Windows `winget`/`choco`) and pick the correct install command for each app.
2. Store the app catalog and any reusable setup logic in shared `lib/` files (e.g. `lib/app-catalog.sh`) with fields: id, name, description, tags/categories, and per-OS install commands. Main skill scripts must source these shared utilities and remain thin orchestration.
3. Keep a committed `machine-setup/repos.conf` file in the repo that lists personal git repos to clone, their target paths, and optional post-clone commands. The skill reads this file by default and clones/maintains each repo before installing apps.
4. For the `dotfiles` entry, after cloning to its target path, run the configured install script (e.g. `dotfiles/install`) if it exists.
5. Start with an interview that asks for:
   - primary role(s) of the machine (dev, design, data, writing, gaming, admin, general, etc.)
   - categories the user cares about (cli, terminal, browser, productivity, security, media, dev-tools, cloud, communication)
6. Pre-select a sensible default set from the role + categories, then present a checklist the user can:
   - toggle items on/off
   - add custom app names or raw install commands
   - preview the plan, or run it with explicit confirmation
7. Support a non-interactive mode: `--role <role> --categories <list> --extras <list>` plus `--yes` so the setup is repeatable on a clean machine.
8. Never run an installer by default in interactive mode; require a `--yes` flag or a manual "run it now" confirmation.
9. Re-use the same backup-before-overwrite pattern as `ai-setup` if any existing tool config paths are touched.
10. Provide an `--ai` flag that installs and hotwires the known AI CLIs (devin, claude, copilot) after the app install step by calling `ai-setup.sh`, reusing the existing `lib/ai-tools.sh` registry.
11. The catalog must support `cli` and `base` tags for headless/VPS-style setups (tmux, zsh, oh-my-zsh, btop, htop, ripgrep, etc.).
12. Produce a final report of what was installed, skipped, and failed.

## 3. Out of Scope
- Migrating dotfiles, SSH keys, or cloud account config from an old machine.
- Changing system settings (wallpaper, system preferences, window managers, user accounts).
- Installing/hotwiring the AI CLI tools themselves (that stays in `ai-setup`, but `machine-setup` can call it).
- Uninstalling or downgrading already-installed apps.
- Handling license keys, paid activations, or GUI-only installers that can't be scripted.
- Replacing package-manager lock-in; the skill uses the native package manager, not its own binary downloads.

## 4. Invariants That Must Not Break
- Existing `ai-setup`, `ai-battle`, `ui-design`, and other skills must remain discoverable and hotwired.
- `lib/ai-tools.sh` stays the canonical source for AI CLI tool metadata; the new catalog must not conflict.
- Reusable logic must live in shared `lib/` files and be sourced by main skill scripts. Skill scripts must not duplicate catalog parsing, OS detection, repo cloning, or AI CLI hotwiring logic.
- The user must always be able to preview before an install runs.
- Shared `~/.ai` paths must not be moved or broken for existing tools.
- The committed `repos.conf` must be safe to push to a public repo: no secrets, only public repo URLs and non-secret paths.

## 5. Evidence From the Working Tree (auto-collected — context, not requirements)

* **Branch:** `main`
* **Diff target:** `HEAD`

### Commit messages in range

* Move canonical repo path from ~/.ai/skills to ~/.ai and commit THE_SAGE_LAWS.md.
  - Repo root is now ~/.ai (not ~/.ai/skills) across README, THE_SPEC,
  SKILL.md files, scripts, and tests
  - ai-setup.sh defaults to AI_SKILLS=$HOME/.ai
  - laws/ is now part of the repo with THE_SAGE_LAWS.md and a
  global_rules.md symlink
  - DOCS/THE_SPEC.md now explains that laws are committed and that
  global_rules.md links to THE_SAGE_LAWS.md
  - Verified with ai-setup inventory that all installed tools see the skills
  and laws paths

  Generated with [Devin](https://devin.ai)

  Co-Authored-By: Devin
  <158243242+devin-ai-integration[bot]@users.noreply.github.com>

* Add THE_SAGE_LAWS.md to the repo and remove laws/ from gitignore.
  - Keeps the canonical prompt as laws/THE_SAGE_LAWS.md
  - laws/global_rules.md is a symlink to it so the hotwired tool paths
  resolve
  - No need to keep laws outside the repo

  Generated with [Devin](https://devin.ai)

  Co-Authored-By: Devin
  <158243242+devin-ai-integration[bot]@users.noreply.github.com>

* Ignore local laws directory from the shared skills repo.
  Generated with [Devin](https://devin.ai)

  Co-Authored-By: Devin
  <158243242+devin-ai-integration[bot]@users.noreply.github.com>

* Tighten docs and skill prompts to match the current tool registry.
  The README and DOCS still referenced a Windsurf path that the tool 
  registry no longer maps, and the setup instructions assumed a hardcoded
  ~/.ai/skills location. This brings the docs into line with the actual 
  scripts and tells the AI to ask before moving a non-default checkout.

  Generated with [Devin](https://devin.ai)

  Co-Authored-By: Devin
  <158243242+devin-ai-integration[bot]@users.noreply.github.com>

* Add shared spec builder with human interview flow; harden ai-battle spec gating
  New shared tooling (repo-root lib/ for cross-skill helpers):
  - lib/spec_builder.sh: spec discovery (find), scaffolding (build), and
   find-or-scaffold (ensure), CLI + sourceable library. Scaffolds a DRAFT
   TICKET-SPEC.md from neutral git evidence with TODO requirement sections;
   --interactive interviews the human at a TTY and writes a banner-free,
   battle-ready spec when Intent and Requirements are answered.
  - lib/SPEC_INTERVIEW.md: interview protocol for AI agents (no TTY) —
   requirements come from the human/ticket/requesting conversation, never
   reverse-engineered from the code; covers ticket-less repos where the
   conversation is the ticket.
  - spec-builder/SKILL.md: /spec-builder skill, a thin wrapper over the lib.

  ai-battle integration: a missing spec scaffolds a DRAFT and exits 3
  (scaffold-then-stop, before challenger selection); unfilled DRAFT specs
  are refused; --no-spec is the explicit, loudly-warned opt-out.

  Cross-model battle (Codex challenger) found 3 P1s, all fixed with
  regression tests in lib/tests/spec_builder_test.sh: 1. ensure treated a
  stale unfilled DRAFT as a completed spec (exit 0) 2. spec-less --dry-run
  previewed an ungrounded prompt without --no-spec 3. tool discovery ran
  before spec scaffolding, skipping the scaffold when
    no eligible challenger was installed

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>

* Retire gemini-cli in favor of Antigravity (agy).
  Google has deprecated the gemini-cli client for individual accounts, so 
  remove it from the shared AI tool registry and promote agy as the 
  supported Google CLI. Update ai-setup, ai-battle, README, and the spec to
  reflect the change. Uninstall gemini globally and install + hotwire agy.

  Generated with [Devin](https://devin.ai)

  Co-Authored-By: Devin
  <158243242+devin-ai-integration[bot]@users.noreply.github.com>

* Add DOCS/THE_SPEC.md

* Rewrite README as a self-contained new-machine setup guide

* Centralize AI tool registry in ai-setup/lib/ai-tools.sh and have ai-battle source it

* Add ai-setup skill and bootstrap script

* Add README, LICENSE, and paranoid .gitignore

* Initial commit: central AI skills repo

### Diffstat

```text
 ai-setup/lib/ai-tools.sh     | 18 +++++++++---------
 ai-setup/scripts/ai-setup.sh | 13 +++++++++----
 2 files changed, 18 insertions(+), 13 deletions(-)
```

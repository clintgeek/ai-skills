# Specification: Shell bootstrap + repo hardening (branch fix/reorg-wiring-and-ci)

> Scaffolded by spec_builder.sh on 2026-09-01 (branch `fix/reorg-wiring-and-ci`, diff `main...HEAD`).

## 1. Intent
This branch has two distinct origins, and they carry very different
authority:

**(a) Requirements stated by the human (Chef).** Verbatim, from the conversation
that requested the work:

> "There is a small wrapper: machine-wizard in skills/machine-setup/scripts/machine-wizard
> that checks for zsh and installs it if missing. Could we extract that to lib and have
> each skill that needs zsh or newer bash [...] install zsh? Also what about brew on macOS?
> I dont think thats getting handled, right?"

> "I know this: Id like every machine I touch to be using zsh as the default shell. Im a
> strong proponent of zsh. If we can also update bash and use it where appropriate, Im
> fine with that. Having both hurts nothing as long as zsh ends up the default. So the
> bootstrapper needs to probably install both and make zsh the default. Brew NEEDS to be
> installed on every macOS machine [...] so brew is non-negotiable, we need to install it
> in the bootstrapper."

> "and this works even if the user isnt clintcrocker, right?"

**(b) Defect fixes originating from a report the BUILDER wrote.** Chef asked for
"a report around issues that you see", then approved batches of it with "yes,
please" / "Yes" / "lets commit and keep going". The human authorized the work,
but the DEFECT DEFINITIONS are builder-authored. Any review that grounds itself
in (b) is checking the builder against the builder. The challenger should treat
every requirement in section 2.2 as an unverified claim and confirm the
underlying defect independently from the code, not accept that it existed.

## 2. Requirements / Acceptance Criteria
### 2.1 Stated by the human (authoritative)

1. zsh must end up as the **default login shell** on every machine the tooling touches.
2. A modern bash must also be installed where appropriate. Both shells coexisting is
   explicitly acceptable; the only hard constraint is that zsh is the default.
3. Homebrew must be **installed by the bootstrapper** on every macOS machine — not
   detected, not warned about. Non-negotiable per the human.
4. The zsh-install logic must be **extracted out of** `skills/machine-setup/scripts/machine-wizard`
   into a shared `lib/` location, usable by **every** skill that needs zsh or a newer bash.
5. The tooling must work under **any username and home layout**. There is one human;
   the account name differs per machine (`ccrocker` on the work Mac, `crocker` on the
   home server, `rallycenter` on the VPS, others elsewhere) and so does the home
   directory root (`/Users/x` on macOS, `/home/x` on Linux). Nothing may assume a
   username or a home path.

   *(Builder note: I originally read this as "portable to a different person" and
   answered that instead. Corrected by the owner. The right reading found a real
   defect the wrong one could not: running under `sudo` silently configures root's
   account -- $HOME, login shell, .zprofile, symlinks -- and reports success.)*

### 2.2 Builder-authored defect claims (treat as UNVERIFIED)

Each of these asserts a defect existed and is now fixed. The challenger must
independently establish (i) that the defect was real, and (ii) that the fix is
correct and complete — from the code, not from these statements.

6. Hotwired tools must actually load the skills in this repo (claim: the skills root
   was linked one level too high after the `skills/` reorg).
7. `ai-battle` must run at all (claim: its `spec_builder.sh` source path was wrong).
8. The test suites must pass, and CI must run them (claim: 6/16 failing, never run).
9. `hotwire <unknown-tool>` must print a usable message (claim: aborted on `set -u`).
10. `--role admin` / `--role general` must select more than the base app set, and the
    roles named in `DOCS/TICKET-SPEC.md` Req 5 must be accepted (claim: both broken).
11. `--extras <single-token>` must not be silently dropped; a raw command must not be
    split into separately-eval`d fragments (claim: both happened).
12. The interactive checklist must support toggling on **and** off, plus adding names
    and raw commands (claim: remove-only).
13. `hotwire` must not be able to create a state that permanently blocks the repo clone
    (claim: a starter `global_rules.md` wedged it).
14. `backup_path`/`ensure_dir` must exist once, not once per language.
15. `spec_builder build` must honor its own documented exit codes.
16. Nothing may mutate the machine without consent (`--yes` / an interactive `y`).

> **Attribution.** Section 2.1 is the owner's words. Section 2.2 is builder-authored
> defect claims, to be verified independently. Sections 3 and 4 were builder inferences,
> reviewed by the owner on 2026-09-01: requirement 5 was corrected, the `repos.conf`
> scope entry struck, and invariants 2 and 7 are marked BUILDER-PROPOSED where the rule
> did not originate with them.

## 3. Out of Scope
- Porting `battle_runner.sh` or `ai-setup.sh` from bash to zsh. The human accepted
  "install both" instead; those two remain bash and require bash 4+.
- Making `skills/machine-setup/repos.conf` "portable to other users". Struck: there are
  no other users. `clintgeek/ai-skills` and `clintgeek/dotfiles` are the owner's repos on
  every machine and are correct as committed, permanently. This entry existed because the
  builder misread requirement 5 as being about a different person.
- Direct tests for `execute_plan` / `report`. Known and stated gap: exercising them means
  real package installs or real clones. No stub harness was built.
- Fixing spec discovery so it searches `DOCS/` (identified as P1-2 in the builder report,
  never actioned — this very battle had to be handed its spec explicitly because of it).
- Verification on Linux or Intel macOS. Those code paths exist and CI covers Ubuntu, but
  nothing in this branch was executed on either by the builder.

## 4. Invariants That Must Not Break
1. **Nothing mutates the machine without consent.** The bootstrapper must install
   nothing when non-interactive without `--yes`, and `BS_DRY_RUN=1` must perform zero
   mutations. Installing Homebrew, running `chsh`, and appending to `/etc/shells` all
   fall under this.
2. **The login shell must never be left broken.** A `chsh` target must be present in
   `/etc/shells` first, and an existing zsh login shell must not be swapped merely to
   chase a newer build. Preferring the *system* zsh over Homebrew's is
   BUILDER-PROPOSED and owner-ratified: a login shell under `/opt/homebrew` locks the
   user out if that install is removed. `BS_ZSH_PREFER=newest` opts out.
3. **`lib/bootstrap.sh` must remain POSIX `sh`.** It runs before zsh or bash 4 is known
   to exist. Any `[[ ]]`, array, or zsh-ism in it is a defect regardless of whether it
   happens to work on the authors machine.
4. **backup_path must never destroy user data.** Real files and directories are moved to
   `.bak-<timestamp>`, never deleted. (The branch newly makes an exception for symlinks —
   verify that exception is actually safe.)
5. **The challenger in ai-battle stays read-only.** No change may loosen a tools
   permission mode, sandbox, or dry-run flag.
6. **No username or home-layout assumptions.** No hardcoded `/Users/<name>`; `$HOME`
   and `id -un` throughout.
7. **Never run as root.** OWNER POLICY, stated emphatically: not via `sudo`, not logged
   in as root. Both become root's `$HOME` and `id -un`, so the repo, symlinks, login
   shell and `.zprofile` all land on the wrong account -- silently, and reporting
   success. Where root is the only account, creating a non-root user with key-only
   access and disabling root login is the OPERATOR's first step, by hand; the tool must
   not attempt it. `FS_ALLOW_ROOT=1` is the container escape hatch.
   *(An earlier draft allowed "genuinely root" as legitimate. That was the builder's
   inference and it was wrong.)*
8. **Tests must fail when the code is wrong.** Any test that cannot fail is a defect.
   *(BUILDER-PROPOSED, accepted by the owner -- not something they asked for. Added after
   the builder caught itself writing unfalsifiable assertions, then did it three more
   times: a `$?` captured after a command substitution, a grep matching its own
   explanatory comment, and a guard unreachable on the author's machine. Where practical,
   pair a guard with a control proving it can still fail.)*

## 5. Evidence From the Working Tree (auto-collected — context, not requirements)

* **Branch:** `fix/reorg-wiring-and-ci`
* **Diff target:** `main...HEAD`
* **Ticket references detected:** P1-3,P1-4 P1-5,P1-6 P1-8

### Commit messages in range

* Converge backup_path, harden hotwire, and fix a zsh PATH clobber
  P1-8 -- backup_path/ensure_dir existed twice, once in bash (ai-setup.sh)
  and once in zsh (lib/setup-helpers.zsh), with different timestamp
  variables. The zsh copy used `(( $+functions[log] ))`, so the bash side
  could not have converged on it even deliberately. Both now source
  lib/fs-helpers.sh, written in POSIX sh precisely so one copy can serve
  both callers. THE_SPEC forbade the duplication and TICKET-SPEC Req 9 asked
  for reuse rather than a retype; CI now asserts exactly one definition of
  each.

  While unifying them, two behaviours changed on purpose. A dangling symlink
  is removed rather than backed up (a broken link holds no content), and a
  symlink already pointing inside $AI_ROOT is replaced rather than backed up
  -- it is one of ours from an earlier run, and preserving it left another
  stale
  .bak-<timestamp> symlink on every single re-run. Real files, real
  directories, and symlinks pointing anywhere we do not own are still always
  moved, never deleted. ai-setup's SKILL.md claimed "broken symlinks are
  removed and recreated", which was simply untrue before; now it is, and the
  doc spells out all three cases.

  P1-6 -- hotwire could wedge its own recovery path. link_laws helpfully
  creates a starter global_rules.md when one is missing, so hotwiring
  against a missing repo made $AI_ROOT exist, non-empty, and not a git
  checkout. machine-setup's setup_repos then refused to clone over it
  permanently, leaving placeholder laws in place of THE_SAGE_LAWS with no
  way back. hotwire and hotwire-generic now require the repo to be present
  and say how to get it, creating nothing.

  A zsh PATH clobber found while testing the above, and worse than the
  finding that led me to it: `path` is tied to PATH in zsh, and both
  setup_repos and print_plan did `local id path` then `path=/some/dir`. That
  replaces PATH with a single directory for the rest of the function -- so
  setup_repos destroyed PATH before every `git clone`/`git pull`, and
  print_plan's new `command -v` checks reported every installed AI CLI as
  missing. `local` scopes the damage to the function body, which is exactly
  why it stayed invisible: the only affected code is between the assignment
  and the end of the function, and that is where the git calls live. Renamed
  to repo_path at both sites.

  The test for it reports from INSIDE the function, since PATH is restored
  on return and an after-the-fact check cannot see the bug. A control
  asserts the old spelling still fails that probe, so the guard cannot
  quietly rot. A lint bans
  path/fpath/cdpath/manpath/module_path/mailpath/infopath as local scalars.

  P2 -- --ai ran `install <tool> --yes` for all four known CLIs,
  contradicting ai-setup's "never run a tool installer unprompted" and
  installing vendor scripts the user never picked. Split: --ai hotwires what
  is already installed,
  --ai-install additionally installs the missing ones. The plan output now
  names which is which.

  P2 -- `spec_builder build` returned 0 for a DRAFT unless --interactive,
  against its own documented "3 = still a DRAFT". A caller could treat a
  TODO-only placeholder as a finished spec. Now 3 whenever what was written
  is a draft, 0 only for a battle-ready one. All four documented exit codes
  verified.

  P2 -- .gitignore listed *.bak, which never matched the .bak-<timestamp>
  form every writer actually produces. Added *.bak-*.

  P2 -- THE_SPEC listed agy among tools needing hotwire-generic while the 
  registry has TOOL_KNOWN[agy]=1. The registry is right; the doc was stale.

  Also fixes a bug in the new fs-helpers: `command -v log` matches macOS's
  /usr/bin/log, so with no caller-supplied log() every message went to the
  system logging binary as a bogus subcommand. Matches on "function"
  instead, which bash, zsh and dash all report.

  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>

* Fix role selection, extras handling, and the checklist; add machine-setup tests
  Three review findings, one data path.

  P1-3 -- roles selected nothing. APP_TAGS conflated two axes: what a
  machine is FOR and what KIND an app is. Both were matched against one tag
  list, so
  `--role dev` and `--categories dev` were identical while `--role admin`
  and
  `--role general` matched no tag at all and fell through to the `base` set
  -- measurably 10/10/10 apps for dev/admin/general. The spec's design,
  data, writing and gaming roles were hard-rejected outright.

  Split into APP_ROLES (dev, design, data, writing, gaming, admin, general)
  and APP_TAGS (the category list from the spec, plus `base`), tagged every
  app on both axes, and added the entries the empty roles needed. --role now
  takes a comma-separated union, and roles/categories are validated
  separately with the valid set printed on error. A role carrying no apps
  warns at runtime instead of silently contributing nothing. Selection is
  now 25/17/23 for dev/admin/general and every spec role is accepted.

  P1-4 -- extras were dropped or shredded. Items were bare app ids and "does
  it contain a space?" decided app vs. raw command, so `--extras neovim`
  printed
  "skip neovim (no mac installer)" and vanished, while a comma inside a raw 
  command split it into two separately-eval'd fragments.

  Items are now typed -- app:<id>, pkg:<name>, cmd:<raw> -- so nothing is 
  inferred from shape. An unknown name becomes a package installed via the
  local package manager rather than being discarded. --extras is documented
  and enforced as a comma-delimited NAME list and is repeatable; --extra-cmd
  takes one command verbatim and is never split. A value that both contains
  a comma and looks like a command is genuinely ambiguous, so it is refused
  with a pointer to
  --extra-cmd rather than silently split -- that ambiguity was the original
  bug, and documenting it away would not have fixed it.

  P1-5 -- the checklist could only remove, by number, once. Now a real
  editor: toggle on AND off (a mistaken removal is recoverable), `+<name>`
  to add an app id or package, `+<command>` to add a raw command,
  all/none/list/help/done. Unrecognized input is distinguished from an
  out-of-range item number -- saying
  "no item zzz" for a non-numeric token was misleading.

  Also fixes a bug introduced while writing this: `(( n++ ))` evaluates to
  the PRE-increment value, so the first increment from 0 returns 0, which
  `set -e` reads as failure. It aborted the wizard mid-checklist and, worse,
  made two tests pass for the wrong reason -- the plan never printed, so the
  item under test was legitimately absent. Both occurrences are now plain
  assignment, and the suite lints for the form.

  New lib/tests/machine_setup_test.zsh (65 tests): catalog integrity,
  per-role selection floors, role/category overlap, multi-role union, extras 
  classification and the refusal path, typed-item commands, and the
  interactive loop driven over a pipe through a documented seam (a pty via
  script(1) dropped input lines nondeterministically, making the tests flaky
  rather than useful).

  Known gap: execute_plan and report are still untested -- exercising them
  means real installs or real clones. Everything they depend on
  (item_install_cmd, item_label) is unit-tested, and the plan path is
  covered end to end.

  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>

* Add a shared POSIX-sh machine bootstrapper (brew, zsh, bash 4+, login shell)
  The inline zsh installer in scripts/machine-wizard only helped
  machine-setup, and only for zsh. Extract it to lib/bootstrap.sh and give
  every entry point a thin sh wrapper over it, so a machine with nothing but
  sh and git can run any of them.

  lib/bootstrap.sh is deliberately POSIX sh -- it runs before the shells it 
  installs are known to exist, so it cannot use them. Enforced by CI (dash
  -n plus a grep for bash/zsh-only constructs) and by bootstrap_test.sh.

  Guarantees, in dependency order:

    1. Homebrew on macOS. Apple ships no package manager, and every
      APP_INSTALL_MAC entry in the catalog is a `brew install`, so a fresh
  Mac
      previously failed every single app install (Installed: 0, Failed: 12).
      brew is a hard prerequisite, not a nicety. Handles both /opt/homebrew
  and
      /usr/local, adds it to PATH for the current process (the installer
  only
      edits profiles, so a bootstrap-then-install run in one invocation
  could
      not otherwise see it), and persists it to ~/.zprofile idempotently.
   2. zsh, via the detected package manager.
   3. A bash >= 4, for ai-tools.sh's associative arrays. macOS ships bash
  3.2
      permanently, so brew has to come first. lib/spec_builder.sh is
      bash-3.2-clean and deliberately not covered.
   4. zsh as the login shell, adding it to /etc/shells first.

  The login shell defaults to the SYSTEM zsh (/bin/zsh on macOS) rather than 
  Homebrew's: a login shell under /opt/homebrew locks you out if that
  install is removed or the volume unmounted. BS_ZSH_PREFER=newest opts in
  anyway, and an already-zsh login shell is left alone rather than switched
  to chase a version.

  Consent is inherited, not invented: the wrappers forward --yes as 
  BS_ASSUME_YES and --dry-run as BS_DRY_RUN, so the bootstrapper never
  installs anything the calling skill would itself have paused for.
  Non-interactive without --yes declines and says why. BS_DRY_RUN prints
  every mutation and performs none; BS_NO_CHSH keeps the login shell
  untouched.

  Also teaches lib/machine-setup.zsh that brew is the macOS package manager
  -- detect_pkg_mgr was gated behind OS_KIND == linux, so on a Mac PKG_MGR
  was always empty and install_cmd handed back `brew install ...` on faith.
  And routes setup_ai_clis through the new ai-setup wrapper, since
  ai-setup.sh needs a bash 4+ that a fresh Mac does not have yet.

  New: lib/tests/bootstrap_test.sh (30 tests) covering POSIX purity,
  detection, bash-4 discovery (including refusing 3.2 when it is the only
  candidate), consent, dry-run, idempotency, login-shell handling, and the
  re-exec helpers. CI gains the suite, a no-op-on-provisioned-machine check,
  a nothing-without-consent check, and wrapper smoke tests.

  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>

* Add CI, a bash 4+ guard, and unconfound the F3 test
  The spec_builder suite was failing 6/16 on HEAD and had not been run since
  the reorg -- it would have caught the battle_runner source path 
  immediately. Nothing ran it automatically, so add a workflow.

  Three of those failures were not the path bug. F3 stripped AI CLIs by 
  narrowing PATH to /usr/bin:/bin, which also demoted bash 5 to macOS's bash
  3.2; ai-tools.sh needs associative arrays, so the runner died with
  "declare: -A: invalid option" and rc 2. F3 was measuring the interpreter 
  rather than the empty roster. It now exposes only the bash running the 
  suite, via a dir containing nothing else -- re-adding the real bash 
  directory would reintroduce an AI CLI (agy lives in /opt/homebrew/bin).

  ai-tools.sh now says so plainly instead of spraying declare errors. This 
  is a diagnostic, not a fix: the bash 3.2 portability gap is still open, 
  and a stock Mac still cannot run ai-setup. The guard stays quiet under 
  zsh, which sources this file via lib/machine-setup.zsh.

  CI runs syntax checks over every tracked .sh/.zsh, the regression suite, 
  smoke tests for battle_runner/ai-setup/machine-wizard, an assertion that 
  hotwire never regresses to "unbound variable", and a SKILL.md frontmatter 
  check. Ubuntu only: macOS runners ship bash 3.2, which the guard refuses.

  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>

* Finish the skills/ reorg: fix skill-root wiring and ai-battle source path
  The 212a0ff reorg moved everything under skills/, but only some path 
  references followed. Two skills were broken on disk as a result.

  ai-setup was linking each tool's skills root at the repo root, so the 
  resolved lookup path became <root>/skills/skills/<name>/SKILL.md and no 
  skill in this repo loaded for any hotwired tool. AI_SKILLS had been doing 
  double duty as both "repo checkout" and "skills root"; split those apart 
  so cmd_clone still clones the repo root rather than nesting it inside 
  skills/:

    AI_ROOT   -> the checkout      (clone target)
   AI_SKILLS -> $AI_ROOT/skills   (symlink target)
   AI_LAWS   -> $AI_ROOT/laws

  battle_runner.sh sourced ../../lib/spec_builder.sh, which lands in 
  skills/, not the repo root -- every invocation of ai-battle died on the 
  source line. Line 7 (ai-tools.sh) resolved correctly, which is why this 
  one slipped through the reorg fixups.

  cmd_hotwire indexed TOOL_SKILLS/TOOL_LAWS before validating the tool name,
  so under `set -u` an unknown tool aborted with "unbound variable" instead
  of printing the hotwire-generic hint sitting two lines below. Index
  through :- defaults instead; same guard in cmd_inventory.

  Docs updated to match, with a note on why the target is skills/ and not 
  the repo root: getting it wrong hides every skill without erroring, which 
  is exactly how this went unnoticed. Also adds machine-setup to the README
  verify list.

  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>

### Diffstat

```text
 .github/workflows/tests.yml                     | 106 ++++++
 .gitignore                                      |   2 +
 DOCS/THE_SPEC.md                                | 121 ++++---
 README.md                                       |  82 +++--
 lib/app-catalog.zsh                             | 229 +++++++------
 lib/bootstrap.sh                                | 416 +++++++++++++++++++++++
 lib/fs-helpers.sh                               |  86 +++++
 lib/machine-setup.zsh                           | 237 ++++++++++---
 lib/setup-helpers.zsh                           |  42 +--
 lib/spec_builder.sh                             |  14 +-
 lib/tests/bootstrap_test.sh                     | 135 ++++++++
 lib/tests/machine_setup_test.zsh                | 316 ++++++++++++++++++
 lib/tests/spec_builder_test.sh                  |  27 +-
 skills/ai-battle/SKILL.md                       |  18 +-
 skills/ai-battle/scripts/ai-battle              |  19 ++
 skills/ai-battle/scripts/battle_runner.sh       |   2 +-
 skills/ai-setup/SKILL.md                        |  29 +-
 skills/ai-setup/lib/ai-tools.sh                 |  11 +
 skills/ai-setup/scripts/ai-setup                |  19 ++
 skills/ai-setup/scripts/ai-setup.sh             |  74 +++--
 skills/machine-setup/SKILL.md                   |  66 +++-
 skills/machine-setup/scripts/machine-wizard     |  43 ++-
 skills/machine-setup/scripts/machine-wizard.zsh | 420 +++++++++++++++++-------
 23 files changed, 2081 insertions(+), 433 deletions(-)
```

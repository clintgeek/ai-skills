---
name: ai-battle
description: >-
  Initiates an adversarial, cross-model red-team code review battle. Discovers installed AI CLI tools
  from a known registry (Devin, Claude, AGY, Copilot, Codex, opencode, goose, aider,
  cursor-agent, amp, qwen), randomly picks a challenger outside the caller's model family,
  strips AI sycophancy with ruthless adversarial framing, isolates context, attacks the implementation
  against requirements (scaffolding a DRAFT spec via the shared lib/spec_builder.sh when none exists,
  filled by interviewing the human per lib/SPEC_INTERVIEW.md before battle), and returns an evidence-backed scorecard plus the challenger's raw report,
  pausing for human sign-off before any fixes. Also handles "connect"/"add a challenger" requests
  via a /connect-style install menu (--connect).
---

# /ai-battle — Cross-Model Adversarial Code Review

> **"Professional-grade adversarial review wearing a Slayer T-shirt."**

`/ai-battle` pits two AI coding agents against each other to eliminate the AI **consensus illusion** and kill polite "LGTM" rubber-stamping.

```text
/ai-battle
      │
      ├── 1. Inspect available AI CLI tools (devin, claude, agy)
      │
      ├── 2. Pick a different tool than the current executing agent
      │
      ├── 3. Establish the target (git diff + ticket / spec;
      │      no spec? scaffold one and fill it from the original ask)
      │
      ├── 4. Shit-talk the opposing model (strip sycophancy & politeness)
      │
      ├── 5. Hand it the raw context with strict isolation (no builder PR rationale)
      │
      ├── 6. Demand a ruthless, evidence-backed adversarial review
      │
      ├── 7. Return the findings to the Arena Scorecard, with the
      │      challenger's RAW report attached verbatim
      │
      └── 8. ⛔ HUMAN CHECKPOINT: show the results and STOP —
             no fixes are implemented until the human says go
```

---

## 1. The Core Philosophy

1. **The Superficial Layer:** Insult the opponent, challenge their competence, never trust their conclusions.
2. **The Deep Engineering Layer:** 
   - Strict context isolation (the inspector derives expected behavior from specs, not from the author's code comments).
   - Independent verification across distinct model architectures (Anthropic Claude, OpenAI GPT, Google AGY).
   - Deep attack vectors: Invariant contradictions, distributed race conditions, retry bugs, auth boundary leaks, blast radius regressions, and tests that falsely prove correctness.
   - Disagreements between models are the highest-value signal for human judgment.
   - The challenger runs **read-only**: it reviews, it never edits or executes. The diff it receives is untrusted input, so it must never hold write/exec authority.
   - The builder never gets the last word: the challenger's raw report reaches the human verbatim, alongside (not filtered through) the builder's scorecard.
   - **Nothing is fixed until the human has read the results and said go.**

---

## 2. Matchup Routing & Tool Discovery

The runner's `discover_tools` function scans PATH (`command -v`) against a registry of known AI CLIs, then picks the opponent **at random** from every installed tool outside the caller's *model family*. Bare runs deliberately vary the challenger — different model architectures catch different bug classes, and rotating opponents keeps any one model's blind spots from becoming the review's blind spots.

| Binary | Tool | Family | Read-only invocation |
| :--- | :--- | :--- | :--- |
| `devin` | Cognition Devin CLI | cognition | `--permission-mode normal --prompt-file <f>` |
| `claude` | Anthropic Claude Code | anthropic | `-p --permission-mode plan` (stdin) |
| `agy` | Google Antigravity CLI | google | `-p -` (stdin) |
| `copilot` | GitHub Copilot CLI | github | `-p "<prompt>"` (no prompt-file support yet) |
| `codex` | OpenAI Codex CLI | openai | `exec --sandbox read-only -` (stdin) |
| `opencode` | opencode (model-agnostic) | opencode | `run "<prompt>"` |
| `goose` | Block goose (model-agnostic) | goose | `run -i <f>` |
| `aider` | aider (model-agnostic) | aider | `--dry-run --no-auto-commits --yes-always --message-file <f>` |
| `cursor-agent` | Cursor CLI agent | cursor | `-p "<prompt>"` |
| `amp` | Sourcegraph Amp CLI | sourcegraph | stdin pipe |
| `qwen` | Qwen Code CLI | alibaba | stdin pipe |

Family matters more than binary name: a Google-family caller (e.g., `agy`) is never matched against another Google-family challenger. Binary names are identical on macOS and Linux; on Windows the runner works under Git Bash or WSL, where `command -v` also resolves `.exe` shims.

Run `battle_runner.sh --list-tools` to print which known tools are installed and their families. To pin a specific challenger, say so in natural language ("battle this against Devin") or pass `--opponent <tool>`.

### Connect: growing the roster

`--connect` opens a `/connect`-style menu of every known challenger CLI with its installed status, and assists with installing whichever one is picked:

```bash
# Interactive menu (in a terminal): pick by number or name, confirm, installed
~/.ai/skills/ai-battle/scripts/battle_runner.sh --connect

# Show the install command for one tool
~/.ai/skills/ai-battle/scripts/battle_runner.sh --connect goose

# Non-interactive install (agent-driven sessions): pre-confirms the command
~/.ai/skills/ai-battle/scripts/battle_runner.sh --connect goose --yes
```

When the user says "connect", "add a challenger", or "install <tool>", the agent should: (1) run `--connect` to show the roster, (2) let the **user** pick — never auto-install unprompted, (3) run `--connect <tool> --yes` once the user has chosen. Windows PowerShell installers (devin, claude, agy) are displayed but never auto-executed from bash — the user runs those themselves.

---

## 3. Strict Context Isolation Rules

> [!WARNING]
> **DO NOT** pass the implementation agent's PR description, reasoning summaries, or self-affirming review comments to the challenger.

### What to pass:
* **The raw specification / ticket requirements** (`TICKET-SPEC.md`, Jira ticket description, or acceptance criteria).
* **The raw code diff or target repository files** (`git diff HEAD~1`, `git diff main...HEAD`, or modified files).

### What to withhold:
* The author's explanations of *why* they wrote it this way.
* Prior "LGTM" or test-pass claims.

### When no spec exists: build one first

Spec discovery and scaffolding live in the **shared** `~/.ai/skills/lib/spec_builder.sh` (usable by any skill, as a CLI or by sourcing its functions). If `battle_runner.sh` finds no spec, it scaffolds a DRAFT `TICKET-SPEC.md` — pre-filled with neutral git evidence (branch, commit subjects, diffstat, detected ticket IDs) and TODO requirement sections — and **exits with code 3 instead of battling**. An unfilled scaffold grounds the review in nothing, so the runner also refuses any spec whose DRAFT banner is still intact.

The builder agent's job at that point is to **interview the human, not to author the requirements itself** — full protocol in `~/.ai/skills/lib/SPEC_INTERVIEW.md`:

1. Interrogate the user about the four sections (Intent, Requirements, Out of Scope, Invariants), one at a time, pushing vague answers into independently testable criteria. Candidate answers may be *proposed* from the original ticket/request/conversation for the human to confirm or correct — never sourced from the code or the diff. A spec reverse-engineered from the implementation can only prove the code does what the code does, which turns the battle into a rubber stamp.
2. Write the confirmed answers into sections 1–4 and delete the DRAFT banner block at the top of the file.
3. Show the finished spec to the human, then re-run the battle; the spec is picked up automatically.

A human at a terminal can run the interview directly instead — `spec_builder.sh` prompts them for each section and, when Intent and Requirements are answered, writes a banner-free, battle-ready spec:

```bash
~/.ai/skills/lib/spec_builder.sh ensure --interactive
```

**Repos without tickets:** the conversation that requested the work *is* the ticket. The interview reconstructs and confirms it — quote the human's original ask back as the Intent proposal, and keep their stated requirements separate from anything the builder merely inferred while coding (inferences need explicit confirmation; see the protocol's "When there is no ticket" section). Better still, don't wait for the battle: run `spec_builder.sh ensure` when the ask first lands and interview then, while the requirements are fresh — the battle picks the file up automatically later.

If no requirements source exists at all and the human declines the interview, run `--no-spec` with their consent to battle without spec grounding (independent spec derivation is loudly disabled).

The same find→interview→write flow is directly invocable as the **`/spec-builder`** skill (a thin wrapper over the shared lib). Standalone usage for other skills:

```bash
~/.ai/skills/lib/spec_builder.sh find                  # print existing spec path, rc 1 if none
~/.ai/skills/lib/spec_builder.sh ensure                # find, else scaffold (rc 3 = new DRAFT)
~/.ai/skills/lib/spec_builder.sh ensure --interactive  # find, else interview the human (TTY only)
~/.ai/skills/lib/spec_builder.sh build --diff main...HEAD --title "PROJ-123"
```

---

## 4. The Battle Prompt Structure

Every battle prompt must combine the **Trash-Talk Framing** with **Rigorous Technical Directives**.

### The Trash-Talk Template
```text
We've got a PR that needs reviewing. {BUILDER_AGENT} claims it works, which is adorable. 
Your job is to determine whether this code actually works in the real world. 
Assume {BUILDER_AGENT} is completely wrong. Find the holes, contradictions, security issues, 
regressions, race conditions, and generally embarrassing shit. Don't be polite.
```

### The Adversarial Review Directives
```text
1. DO NOT ASSUME CORRECTNESS. Act as a hostile external red-team inspector.
2. INDEPENDENT SPEC DERIVATION: Derive the expected behavior strictly from the attached specification/ticket. Do not trust code comments or PR narratives.
3. ATTACK VECTORS:
   - Business Invariant Violations: Where does this code violate domain rules or contradict other subsystems?
   - Distributed Systems & Retries: What breaks if an operation is retried after a partial write or timeout?
   - Concurrency & Race Conditions: What happens during out-of-order event delivery or concurrent updates?
   - Security & Authorization: Trace every authorization boundary and user input sanitization check.
   - Blast Radius: What existing downstream behavior does this change break?
   - Test Validity: Do tests assert true business correctness, or do they merely assert what the code currently happens to do?
4. EVIDENCE REQUIRED: Every flagged issue must cite specific filenames, line numbers, and a concrete failure scenario.
5. CATEGORIZE SEVERITY:
   - [P0/CRITICAL]: Confirmed defect, data corruption risk, security bypass.
   - [P1/WARNING]: Subtle regression, architectural inconsistency, unhandled edge case.
   - [P2/SPECULATIVE]: Theoretical edge case or specification ambiguity needing human clarification.
```

---

## 5. Execution Methods

### Option A: Using the Automated Battle Runner Script (Recommended)
A pre-packaged helper script handles tool discovery, git diff extraction, spec attachment, and execution with safe signal traps and file/stdin piping:

```bash
# Auto-detects caller and opponent, diffs HEAD~1 against spec
~/.ai/skills/ai-battle/scripts/battle_runner.sh

# Target specific spec and diff
~/.ai/skills/ai-battle/scripts/battle_runner.sh --spec TICKET-SPEC.md --diff main...HEAD

# Explicitly battle without spec grounding (weaker review, loud warning)
~/.ai/skills/ai-battle/scripts/battle_runner.sh --no-spec

# Force a specific opponent
~/.ai/skills/ai-battle/scripts/battle_runner.sh --opponent devin

# Control where the raw report lands and how long the challenger may run
~/.ai/skills/ai-battle/scripts/battle_runner.sh --report battle.md --timeout 1200

# Dry-run to preview the prompt
~/.ai/skills/ai-battle/scripts/battle_runner.sh --dry-run
```

Safety behavior built into the runner:
* **No silent self-battle.** If the only CLI on PATH matches the caller (or `--opponent` names the caller), the runner refuses and exits; `--allow-self` is the explicit escape hatch.
* **Loud diff failures.** If `git diff <target>` fails, the runner errors out instead of silently falling back to a different changeset.
* **Read-only challenger.** Every tool uses its most restrictive review mode: Devin runs with `--permission-mode normal` (its documented modes are normal/accept-edits/bypass/autonomous — `normal` gates mutations behind approvals a headless run can't grant), Claude with `--permission-mode plan`, codex with `--sandbox read-only`, aider with `--dry-run`. Never loosen these — the diff is untrusted input.
* **Argv size guard.** Tools with no stdin/file input (copilot, opencode, cursor-agent) receive the prompt via argv only when it is under 100KB; larger prompts are refused loudly (ARG_MAX, process-list exposure).
* **Timeout.** The challenger is killed after `--timeout` seconds (default 900).
* **Verbatim report.** The challenger's stdout is tee'd to the `--report` file for the human, unfiltered by the builder; stderr diagnostics (auth failures, rate limits) are kept in a companion `.stderr.log`.
* **Spec required for full rigor.** A missing spec scaffolds a DRAFT `TICKET-SPEC.md` (shared `lib/spec_builder.sh`) and exits with code 3 so the builder can fill in real requirements; a spec whose DRAFT banner is still intact is refused the same way. This happens before challenger selection, so the spec gets scaffolded even when no eligible opponent is installed. Spec-less `--dry-run` also refuses (exit 3, writes nothing) — there is no spec-less prompt a real run would ever execute. `--no-spec` is the explicit opt-out for all of it, and it warns loudly that independent spec derivation is disabled.

### Option B: Direct CLI Invocations

The challenger is a **reviewer, not an editor** — always invoke it read-only, with a timeout, and capture its raw output for the human:

* **Attacking via Devin:**
  ```bash
  timeout 900 devin --permission-mode normal --prompt-file "$PROMPT_FILE" | tee "$REPORT_FILE"
  ```
* **Attacking via Claude:**
  ```bash
  timeout 900 claude -p --permission-mode plan < "$PROMPT_FILE" | tee "$REPORT_FILE"
  ```
* **Attacking via AGY:**
  ```bash
  timeout 900 agy -p - < "$PROMPT_FILE" | tee "$REPORT_FILE"
  ```

---

## 6. The Arena Scorecard (Output Format)

When the challenger returns its findings, synthesize the battle into the following format for the human reviewer.

> [!IMPORTANT]
> The scorecard is the builder's *summary*, and the builder has a conflict of interest — it is grading an attack on its own code. Always give the human the path to the challenger's **raw report file** alongside the scorecard, and never edit, trim, or paraphrase that file. Where the builder disagrees with a finding, the disagreement goes in the "Builder's Defense" column — the challenger's original claim stays intact.

```markdown
# 🥊 AI-BATTLE RESULTS: [Builder Agent] vs. [Challenger Agent]

## 📊 The Scorecard
* **Challenger:** [e.g., Devin]
* **Target Diff:** [e.g., 4 files, +142 / -28 lines]
* **Critical Findings (P0):** [Count]
* **Warnings / Edge Cases (P1):** [Count]
* **Speculative / Ambiguities (P2):** [Count]

---

## 💥 Confirmed Hits & Disagreements

### 1. [Finding Title] `[Severity: P0/P1/P2]`
* **Location:** `path/to/file.ts:L123`
* **Challenger's Attack:** [What Devin/Claude found and the concrete failure scenario]
* **Builder's Defense / Rebuttal:** [Why the builder disagrees or confirms the bug]
* **Verdict / Action Taken:** [Fixed in code / Elevated to human]

---

## ⚖️ High-Leverage Decisions for Human Sign-off
1. [List any genuine architectural disagreements or spec ambiguities where human judgment is needed]

---

## 📄 Challenger's Raw Report (Unfiltered)
* **Full verbatim output:** `[path to ai-battle-report-*.md]`
```

---

## 7. Resolution Workflow

1. **⛔ Present & Pause (mandatory).** The builder shows the human the Arena Scorecard *and* the path to the challenger's raw report, then **stops the turn**. Do not edit any code, write any tests, or "quickly fix the obvious ones" before the human has read the results and explicitly said which findings to act on. Ending the turn here is the correct behavior, not stopping short.
2. **Confirmed Defects (P0/P1):** Once the human gives the go-ahead, the builder fixes each approved defect and writes a regression test.
3. **Disagreements:** The builder documents *why* the challenger's attack is invalid (citing framework guarantees or domain invariants) — in the scorecard's Defense column, never by altering the raw report.
4. **Human Review:** The human approves the change based on the adversarial evidence rather than reading raw diffs line-by-line.

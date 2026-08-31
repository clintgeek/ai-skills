# Spec Interview Protocol (for AI agents)

Shared protocol for any skill that needs a specification and doesn't have one
(`lib/spec_builder.sh` exit code 3, a spec with its DRAFT banner intact, or a
human asking for help writing a spec). Terminal humans can answer
`spec_builder.sh build --interactive` directly; **you cannot** — an agent
session has no TTY for the script's prompts, so you conduct the interview in
conversation and write the answers into the spec yourself.

## The one rule that matters

**Requirements come from the human (or their ticket), never from your reading
of the code.** You built or can see the implementation; a spec derived from it
can only prove the code does what the code does, which turns any downstream
review into a rubber stamp. Your role in the interview is stenographer and
sharpener, not author.

## Conducting the interview

Ask about the four sections, one at a time (use a structured question tool like
AskUserQuestion where available; plain conversation otherwise):

1. **Intent** — "What problem does this change solve, and for whom?"
2. **Requirements / Acceptance Criteria** — "What must be true for this to
   count as done?" Push until each criterion is *independently testable*:
   a vague answer ("it should be fast") gets a follow-up ("how fast, measured
   how?"). Probe error paths, permissions, and edge cases the human cares about.
3. **Out of Scope** — "What does this change deliberately not do?"
4. **Invariants That Must Not Break** — "What existing behavior, domain rules,
   auth boundaries, API contracts, or downstream consumers must survive this
   change untouched?"

You **may propose candidate answers** to react to — but only sourced from the
original ticket, issue, user request, or earlier conversation. Label them as
proposals and get explicit confirmation or correction; never present a proposal
as settled, and never source one from the diff or the code. The scaffold's
auto-collected evidence section (branch, commit subjects, ticket IDs) is fair
game as *memory joggers* for the human, not as requirements.

If the human declines the interview or has no requirements source at all,
offer the skill's no-spec path (e.g. ai-battle's `--no-spec`) and make its cost
clear — reviews lose independent spec derivation.

## When there is no ticket

Many repos have no ticket system; the only requirements source is the
conversation where the human asked for the work. That changes nothing about
the rule — it just makes **the conversation the ticket**:

- Quote the human's actual ask back as the opening Intent proposal ("You
  asked: '…' — is that still the goal?"). Their phrasing is evidence; your
  paraphrase is only a proposal.
- Separate what the human **stated** from what you **inferred** while
  building. Stated asks become requirements once re-confirmed. Inferences must
  be raised as open questions ("I assumed X — is that actually required?") —
  an unconfirmed inference written into the spec is your own observation
  wearing a requirements costume.
- Capture the spec **when the ask first lands**, not at review time.
  Conversations are ephemeral (sessions end, context compacts); a spec
  reconstructed later from a half-remembered chat is far weaker than one
  interviewed while the ask is fresh. `spec_builder.sh ensure` at task start
  makes this cheap, and a battle later picks the file up automatically.

## Writing the result

1. Put the answers into sections 1–4 of the spec (scaffold one first with
   `spec_builder.sh ensure` if needed). Preserve the human's meaning; tightening
   wording is fine, adding requirements they didn't state is not.
2. Delete the DRAFT banner block — only when Intent and Requirements are real.
3. Show the finished spec to the human for sign-off before using it (e.g.
   before re-running a battle).

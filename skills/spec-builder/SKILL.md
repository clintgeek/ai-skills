---
name: spec-builder
description: >-
  Establishes what the work is supposed to do, in conversation with the human.
  Searches the project (., DOCS/, docs/, doc/) for an existing spec; if one
  exists, reads it and discusses it with them against the work at hand; if none
  does — new, greenfield, or unstarted work — builds one by asking them.
  Requirements come from the human, the ticket, or the conversation that
  requested the work, and NEVER from reading the code: a builder writing its own
  spec is asking the bank robber how much he took. Backed by
  ~/.ai/lib/spec_builder.sh for discovery and an empty skeleton. Use when the
  user says "write a spec", "spec this out", when starting new work, or before a
  review that needs requirements.
---

# /spec-builder — Establish the Spec, By Talking to the Human

**This skill is always a conversation.** There is no non-interactive mode and no
`--interactive` flag; the shell library only finds files and writes an empty
skeleton. Everything that makes a spec a spec comes from the human.

## The rule that makes this worth doing

A spec you wrote from reading the diff can only prove the code does what the
code does. Grounding a review in it is a rubber stamp — asking the bank robber
how much he took. So:

- Requirements come from **the human**, the ticket, or the conversation that
  requested the work.
- You may *propose* candidates from a ticket or from what they told you earlier,
  for them to confirm or correct.
- You may **never** source a requirement from the implementation, the commit
  messages, or the branch name. Those are the builder's account of its own work.

## 1. Look first

```bash
~/.ai/lib/spec_builder.sh list      # every spec-shaped file in the project
```

Searches `.`, `DOCS/`, `docs/`, `doc/` for `TICKET-SPEC.md`, `SPEC.md`,
`*SPEC*.md`, `*spec*.md`. A project may have several and only the human knows
which one governs the work at hand — so show them what you found rather than
picking.

## 2a. A spec exists → read it and discuss it

Do not just report that it exists. **Read it, then have a conversation about it**:

- Summarise what it says the work must do, in your words, so they can catch a
  misreading immediately.
- Ask whether it still describes what they want — specs go stale, and the one in
  the repo may predate the change they are asking for.
- Ask what it does **not** cover about the work at hand. This is usually where
  the real requirements surface.
- Check whether its invariants are still true, and whether the current task
  threatens any of them.
- If it needs changes, make them **with the human**, section by section, and show
  the result for sign-off.

If the file still carries its DRAFT banner, treat it as if no spec exists and go
to 2b — an unfilled skeleton is not a spec.

## 2b. No spec → build one by asking

```bash
~/.ai/lib/spec_builder.sh ensure    # writes an EMPTY skeleton, exit 3
```

It lands in `DOCS/` when the project has one, otherwise the repo root, and it is
deliberately blank — no git evidence, no commit messages, nothing pre-filled from
the code.

Then interview them, one section at a time, following
`~/.ai/lib/SPEC_INTERVIEW.md`:

1. **Intent** — what problem, for whom? Push vague answers ("make it better")
   toward something observable.
2. **Requirements** — numbered and independently testable. "Fast" is not a
   requirement; "responds within 200ms at p95" is.
3. **Out of scope** — what this deliberately does not do. Cheap to ask, and it
   prevents the review inventing work later.
4. **Invariants** — what must not break. Domain rules, auth boundaries, API
   contracts, downstream consumers.

For **greenfield work** this is the whole job and there is nothing else to draw
on: no commits, no diff, no ticket. Ask what they are building and why, and write
down what they say.

In a repo without tickets, **the conversation that requested the work IS the
ticket**. Quote their original ask back as the Intent proposal. Keep anything you
merely inferred while working separate, and get it confirmed explicitly.

## 3. Write it and get sign-off

Put the confirmed answers into sections 1–4, delete the DRAFT banner block, and
show the finished spec to the human for sign-off. Mark anything you proposed
rather than they stated, so the provenance is visible later.

## Notes

- **Best run when the ask lands**, not at review time. Requirements are fresh
  then, and downstream skills (`ai-battle`) pick the file up automatically.
- **Never overwrite an existing spec** without the human saying so (`--force`).
- The DRAFT banner is load-bearing: `ai-battle` refuses to review against a spec
  that still has it, which is what stops a review grading itself.

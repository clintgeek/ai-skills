---
name: spec-builder
description: >-
  Finds or builds a specification for the work at hand. Locates an existing spec
  (TICKET-SPEC.md, SPEC.md, *spec.md); when none exists, scaffolds a DRAFT from
  neutral git evidence (branch, commits, diffstat, ticket IDs) and perfects it by
  interviewing the human — Intent, Requirements, Out of Scope, Invariants — per
  the shared lib/SPEC_INTERVIEW.md protocol. Requirements come from the human,
  ticket, or requesting conversation, never reverse-engineered from the code.
  Backed by the shared ~/.ai/lib/spec_builder.sh, which other skills
  (e.g. ai-battle) also use. Use when the user says "write a spec", "build a
  spec", "spec this out", or before a review/battle that needs requirements.
---

# /spec-builder — Find or Build a Human-Owned Spec

Thin skill wrapper around the shared spec tooling. All logic lives in
`~/.ai/lib/spec_builder.sh` (CLI + sourceable library) and
`~/.ai/lib/SPEC_INTERVIEW.md` (the interview protocol) — never
duplicate it here or elsewhere.

## Flow

1. **Find or scaffold:**

   ```bash
   ~/.ai/lib/spec_builder.sh ensure --diff <range>
   ```

   - Exit 0 with a path: a **completed** spec already exists (a stale unfilled
     draft never exits 0). Show it to the user and ask whether it needs
     updating (interview any section they want changed). Done.
   - Exit 3: a DRAFT `TICKET-SPEC.md` was scaffolded, or an existing one is
     still unfilled — proceed to the interview.

   Default `--diff` is `HEAD~1..HEAD`; pass what matches the work (e.g.
   `main...HEAD`, or `HEAD` for uncommitted changes).

2. **Interview the human** following `~/.ai/lib/SPEC_INTERVIEW.md`:
   one section at a time (Intent → Requirements → Out of Scope → Invariants),
   pushing vague answers into independently testable criteria. Propose
   candidates only from the ticket, issue, or the conversation that requested
   the work — never from the code or the diff. In ticket-less repos the
   requesting conversation *is* the ticket: quote the user's actual ask back,
   and get explicit confirmation for anything the builder merely inferred.

3. **Write and confirm:** put the confirmed answers into sections 1–4, delete
   the DRAFT banner block, and show the finished spec to the human for
   sign-off.

A human at a terminal can skip the agent entirely:

```bash
~/.ai/lib/spec_builder.sh ensure --interactive
```

## Notes

- Best run when the ask first lands — conversations are ephemeral, and a spec
  interviewed while requirements are fresh beats one reconstructed at review
  time. Downstream skills (ai-battle) pick the file up automatically.
- The scaffold's auto-collected evidence section is context for the human,
  not requirements — never promote it into sections 1–4 unconfirmed.
- Never overwrite an existing spec without the user's say-so (`--force` exists
  for when they give it).

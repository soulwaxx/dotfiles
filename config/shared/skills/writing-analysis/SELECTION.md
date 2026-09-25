# Selection branch sections

Slot 4 of the skeleton in [SKILL.md](SKILL.md), in this order. Verdicts, option blocks and the table rule come from SKILL.md.

## Candidates

Give the long list first: every product considered, including the ones dropped early. Then give the shortlist. Name the hard constraint that excludes each early elimination, with its source. Include an option block for each excluded candidate under Verdict per candidate.

## Trade-off matrix

One table. Rows are dimensions, columns are shortlisted candidates. Each column header carries the candidate and its verdict, for example `Istio Ambient (chosen)`.

- Every hard constraint is a row.
- Each cell holds a marker plus at most a few words:
  - `Yes`: meets the requirement.
  - `Partial`: meets it under a condition. Name the condition in a few words, or explain it in the candidate's option block.
  - `No`: fails the requirement.
  - `Unknown`: evidence does not yet establish whether it meets the requirement. Put the proof gate in Open items when the chosen verdict depends on it.
  - `n/a`: the row does not apply to this candidate.
- A cost row carries verified licence and infrastructure cost as numbers; use `Unknown` for unverified costs. When any candidate is not free, add a 12-month TCO row per candidate: licence, infrastructure, and operations effort in T-shirt sizes (S, M, L, XL). Cite each figure in its option block; mark unverified figures `Unknown`.

## Verdict per candidate

One option block per candidate, chosen first, including candidates excluded before the shortlist. Use the verdict-first paragraph format in SKILL.md.

- **chosen**: show how it clears each hard constraint, or name an unverified constraint and its proof gate. State its costs in the paragraph when they matter.
- **alternative** or **discarded**: explain the verdict (with the hard constraint when one applies), then give a revisit trigger. Example: "Revisit if security-groups-for-pods gives way to a different data-tier authorization model."

## Adoption approach

How the chosen candidate enters production: phases, coexistence with what runs today, and rollback. State what the PoC must prove. The PoC checks live in Open items; link to them with an anchor.

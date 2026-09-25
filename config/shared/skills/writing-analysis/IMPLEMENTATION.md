# Implementation branch sections

Slot 4 of the skeleton in [SKILL.md](SKILL.md), in this order. Verdicts, option blocks and the table rule come from SKILL.md.

## Current state

How the system works today, verified against code and configuration. One numbered list, one step per item: the actor in bold, the step, and the evidence path in parentheses.

```md
1. **Pipeline**: Terraform creates the DB with a `random_password` master password (`wrappers/service/eks/main.tf`).
```

Close with **defects found**: the bugs, gaps and inconsistencies you saw while reading, stated as facts with their paths. When nothing exists yet, write "None: greenfield".

## Invariants

Numbered rules the design must keep, `INV-1` onward. Each one is checkable: a reviewer can say whether a design breaks it. Technical limits (versions, quotas, service limits) belong in Constraints.

## Decision areas

One subsection per decision. Its heading names the decision, for example "Where credentials live". Under it:

- One option block per option, chosen first, in the verdict-first paragraph format in SKILL.md.
- Every alternative and discarded option carries a revisit trigger.
- Each option whose trade-off needs sign-off carries its approver, for example *(Security)*.

## Target design

- **Components and locations**: a table of component and the repo or account it lives in, both as names.
- **Contracts**: the request and response shapes other systems depend on, as code blocks.
- **Workflow**: a numbered list of steps, each with its idempotency and resume behaviour.
- **IAM**: one bullet per principal with its least-privilege permissions.
- **Diagram**: Mermaid, when the design has more than three components.

## Security analysis

Required when the work touches credentials, IAM or network boundaries. Otherwise write "None" with the reason.

- One bullet per secret: where it exists, and who can read it.
- The audit trail: which logs and histories record what, and for how long.
- Residual risks go to Risks and approvals.

## Feasibility

- **Verdict**: feasible with the current toolchain, or the blocking unknowns that stop it.
- **Effort**: a table of work items with T-shirt sizes (S, M, L, XL).
- **Running cost**: numbers per service, with sources.
- **Fit with the final goal**: what later work can reuse unchanged.

## Prerequisites

A numbered list of actions needed before the build, grouped by repo or system. Each action names what changes and where.

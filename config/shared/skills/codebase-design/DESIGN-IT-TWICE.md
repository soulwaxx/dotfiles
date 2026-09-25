# Design It Twice

Use this process when the user wants alternative interfaces for a chosen deepening candidate. The first idea is rarely the best.

Use the vocabulary in [SKILL.md](SKILL.md): **module**, **interface**, **seam**, **adapter**, and **leverage**.

## Process

### 1. Frame the problem space

Explain:

- the constraints every interface must satisfy;
- the dependencies each design must handle and their categories from [DEEPENING.md](DEEPENING.md);
- a small code sketch that makes the constraints concrete without proposing a solution.

### 2. Draft distinct designs

Draft at least three interfaces in sequence. Apply one constraint at a time, and finish each draft before evaluating it:

1. Minimize the interface. Aim for one to three entry points and high leverage per entry point.
2. Support the required variation without speculative extension points.
3. Optimize the common caller so the default case is trivial.
4. When cross-seam dependencies justify it, use ports and adapters.

For each design, provide:

1. The interface, including types, methods, parameters, invariants, ordering, and error modes.
2. A usage example.
3. The implementation details hidden behind the seam.
4. The dependency and adapter strategy from [DEEPENING.md](DEEPENING.md).
5. The trade-offs, including where leverage is high and where it is thin.

Keep each draft materially different. Do not converge on the first design by renaming its methods.

### 3. Compare

Present the designs separately, then compare depth, locality, and seam placement.

Recommend the strongest design and explain why it wins. Propose a hybrid only when specific elements combine without increasing the caller's required knowledge.

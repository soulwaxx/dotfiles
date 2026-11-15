---
name: perspectives
disable-model-invocation: true
description: Put a decision before a panel of independent lenses, each run as a separate subagent that commits to a stance, then synthesize one recommendation.
argument-hint: "[decision or trade-off] [optional: lenses to add or swap]"
---

Convene a **panel** on the decision supplied, or on the decision currently under discussion. Each panelist judges the same question in isolation, so any disagreement is real rather than staged.

1. **Frame.** Restate the decision in one sentence, naming the options, including keeping things as they are when credible. Gather the facts every panelist needs (files, configuration, the user's numbers) once, here. If no decision is identifiable, ask what to evaluate and stop. Done when the framing and shared facts fit in one brief.

2. **Seat the panel.** Use these lenses unless the user adds, drops, or swaps any:

   | Lens | Question it owns |
   | --- | --- |
   | Operator | Can this be run, debugged, and recovered at 3 a.m.? Where does operational load land? |
   | Security | What does this expose, trust, or make harder to audit? |
   | Cost | What does it cost to adopt and run, and what does it displace? |
   | Maintainer | What is the simplest option that works, and what will be painful to change in a year? |
   | Skeptic | What is the strongest case for the opposite choice, and what fails if the framing is wrong? |

   Done when every lens has a one-line mandate tied to this decision.

3. **Dispatch.** Launch one read-only subagent per lens in parallel (`researcher` when public facts matter, otherwise `scout`), each with the same brief and only its own lens. Each must return: a verdict (`For`, `Against`, or `Conditional: <condition>` — or the option it picks), two to four sentences of reasoning tied to evidence, and the one fact that would flip its verdict. Have each panelist label its own estimates as estimates. Done when every lens has returned a verdict; a lens that failed is reported as missing, never filled in by you.

4. **Synthesize.** Weigh the verdicts by evidence, not by headcount, and emit:

   ```
   ## Panel: <decision in one sentence>

   **Recommendation:** <one decisive sentence>
   **Vote:** <tally by option>
   **Decisive lens:** <which lens carries most weight here, and why>
   **Fault line:** <the core assumption on which lenses actually clash, or "Unanimous — possible shared blind spot: <X>">
   **Key condition:** <what must hold for the recommendation to work; the cheapest check that confirms it>

   | Lens | Verdict | Reasoning | Would flip if |
   | --- | --- | --- | --- |
   ```

   Done when every lens appears in the table and the recommendation names one option.

This is an assessment only. Leave files untouched. Offer once to add a specialist lens or to have the two clashing lenses argue the fault line further.

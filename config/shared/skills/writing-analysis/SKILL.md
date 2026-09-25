---
name: writing-analysis
description: Write a cloud engineering analysis (software selection or implementation) to a fixed standard, with optional Notion publishing.
disable-model-invocation: true
---

# Writing an analysis

An analysis answers one decision question with a **verdict** a reviewer can check. Every run follows the steps below in order. It produces one document, `ANALYSIS.md`, in the output folder, plus the local evidence log `ANALYSIS_RESOURCES.md` when the research step runs.

The skill has two branches:

- **Selection**: pick a product or tool among candidates. Branch sections: [SELECTION.md](SELECTION.md).
- **Implementation**: design how to build or change a system. Branch sections: [IMPLEMENTATION.md](IMPLEMENTATION.md).

## Steps

### 1. Intake

Read any earlier output on the topic first: the conversation, a grilling session, an existing analysis, `CONTEXT.md`, ADRs, notes the user points to. Pre-fill the fields from it and from the environment. Ask the user only for the gaps.

| # | Field | Content |
|---|---|---|
| 1 | Question | The decision, in one sentence |
| 2 | Branch | Selection or implementation |
| 3 | Ticket or parent | Issue link, parent analysis, or none |
| 4 | Constraints | **Hard constraints** (a failure disqualifies an option), listed apart from **preferences** (they weigh, they never disqualify) |
| 5 | Candidates | The products or options already on the table |
| 6 | Scope | What is in, what is out |
| 7 | Approvers | Who signs off, and on which items, for example *(Security)* |
| 8 | Output folder | Where the files go. Always ask: there is no default |

Done when every field holds a value or reads "unknown", and the user has confirmed the list.

### 2. Research

Run this step for every selection. Run it for an implementation only when the verdict rests on facts outside the repositories: vendor limits, pricing, versions, API behaviour. A repo fact takes its repo path as the source.

Read [RESEARCH.md](RESEARCH.md) and follow it. It writes `ANALYSIS_RESOURCES.md` in the output folder.

Done when `ANALYSIS_RESOURCES.md` records a sourced finding or explicit unknown for each candidate–hard-constraint pair, plus the other targets in RESEARCH.md.

### 3. Verdict checkpoint

Present to the user the shortlist, the option you would choose with its one or two reasons, every option a hard constraint eliminates, and every unverified hard constraint. Mark a choice that depends on an unverified constraint as conditional and name the proof gate. Wait for the answer.

Done when the user confirms the verdict, including any pending proof gates, or gives a new one. A new verdict that needs new facts sends you back to step 2.

### 4. Draft

Read [WRITING-STYLE.md](WRITING-STYLE.md) and the branch file before you write the first sentence. Write `ANALYSIS.md` with the skeleton below, and put the branch sections in slot 4.

Done when every skeleton section and every branch section is present, in order, and each evaluated option uses the option block format below.

### 5. Style gates

Run the grep gate from WRITING-STYLE.md on every file you wrote, and rewrite each sentence it flags. Then run the read-through gate: re-read each section against the structure and sentence rules in WRITING-STYLE.md, and rewrite each sentence that fails.

Done when the grep gate returns no hits outside its allowed exceptions and every section has had its read-through.

### 6. Self-check

Check the draft against every item:

- [ ] Every skeleton section and every branch section is present, in order. An empty section reads "None" with the reason.
- [ ] **Relevance gate**: every paragraph, bullet and table row supports the verdict, a decision, a risk or an open item. Delete each one that supports none.
- [ ] Every selection candidate has a sourced finding or explicit unknown for each hard constraint in `ANALYSIS_RESOURCES.md`.
- [ ] Every sentence that supports the verdict cites a primary source or a repo path, or carries *(assumed)*.
- [ ] Every number (cost, limit, version, count) cites a source.
- [ ] Every *(assumed)* claim appears in Open items with how to confirm it. Every unverified hard constraint stays unknown in the matrix and makes the chosen verdict conditional until its proof gate passes.
- [ ] Every option block opens with its bold verdict, then states what the option is, what it gains and what decides it, in at most three sentences plus bullets for three or more parallel points. Every non-chosen option ends with a revisit trigger.
- [ ] Every item that needs sign-off appears in Risks and approvals with its approver.
- [ ] Every table cell is a marker, a number, a name or a few words.
- [ ] Headings carry no numbers, the text carries no `§` references, and every anchor link resolves to a heading.
- [ ] The grep gate returns no hits.

Fix each failing item and run the check again. Done when every item passes.

### 7. Publish

Ask the user whether to publish to Notion. If the answer is yes, ask for the URL of the page to fill, then read [PUBLISH.md](PUBLISH.md) and follow it.

Done when the user declines, or when the completion condition in PUBLISH.md holds.

### 8. Report

List every file written with its path, the Notion page URL when published, and every open item.

## Skeleton

The sections of `ANALYSIS.md`, in order. The document builds through the evidence to the Recommendation, then records the risks and remaining work. An empty section reads "None" with the reason, so a reader can tell empty from forgotten.

1. **Header block.** `# <Topic>: analysis`, then one line each for ticket or parent and status (`analysis, not implementation`).
2. **Problem and goal.** The current pain (in numbers where they exist), the target, and the scope of this document.
3. **Constraints.** Two lists, **Hard constraints** and **Preferences**. Every item cites its source.
4. **Branch sections.** From SELECTION.md or IMPLEMENTATION.md.
5. **Recommendation.**
   - The verdict in one sentence. A verdict can be conditional ("chosen, pending the cost check"); name the unverified hard constraint and put its proof gate in Open items.
   - The one or two reasons it wins.
   - The strongest counter-argument, and why it loses here.
   - One line per other option, with its verdict.
   - A Mermaid diagram when the chosen design has more than three components.
6. **Risks and approvals.**
   - Residual risks, one bullet each.
   - Then one bullet per item that needs sign-off: **approver**, the item, and an anchor link to where the body discusses it.
   - In the body, each such item carries its approver in italics, for example *(Security)*.
7. **Open items.** A `- [ ]` checklist. Each line names the assumption, the fact to gather or the PoC check, then how to close it and who closes it.
8. **Out of scope.** Adjacent gaps, each with one line on why it stays out.
9. **References.** The primary sources cited in the body, grouped by topic.

## Rules for the whole document

### One document

Everything the reader needs lives in `ANALYSIS.md`. Content that passes the relevance gate stays in the body; content that fails it is deleted. The skill writes no ADR files, no glossary file and no side documents.

`ANALYSIS_RESOURCES.md` is the local evidence log: `ANALYSIS.md` links it once, under References, and cites primary sources directly.

### Evidence

Every claim belongs to one of three classes:

- **Fact.** Cites a primary source inline: official documentation, source code, a specification, release notes, a vendor pricing page, or a repo path (`file` or `file:symbol`). A secondary source (blog, news) counts only when it reports a vendor decision, and the sentence names it as secondary.
- **Assumption.** Carries *(assumed)* inline and appears again in Open items.
- **Open item.** A question the analysis could not answer, listed in Open items.

Copy each primary source from `ANALYSIS_RESOURCES.md` into the sentence it supports, so a reviewer checks a claim in one click.

### Verdicts

One vocabulary for options, in both branches:

- **chosen**: the option this analysis recommends. If a hard constraint remains unverified, say `chosen, pending <check>` and put the proof gate in Open items.
- **alternative**: viable, kept for later or for an approver's trade-off.
- **discarded**: rejected. State the reason, and name the hard constraint when one eliminates the option.

Every alternative and discarded option carries a **revisit trigger**: the condition that would change its verdict, or "none" with the reason.

Write each evaluated option as an **option block**, chosen first: a heading that names the option, then one paragraph of at most three sentences.

1. The verdict in bold as the first words (`**Chosen.**`, `**Chosen, pending <check>.**`, `**Alternative.**`, `**Discarded.**`), then what the option is.
2. What it gains. When it gains nothing material, say so in a clause instead of inventing an advantage.
3. What decides it: for the chosen option, why it wins and what it costs; for the others, why it loses, naming the hard constraint when one applies.

Cite facts inline. When the gains or the costs run to three or more parallel points, list them as bullets after the sentence that introduces them. Close each alternative and discarded option with its revisit trigger on its own line, `Revisit if: <condition>.`

```md
### Step Functions behind a waiting starter

**Chosen.** A waiting starter begins the state machine for each request. It retries individual steps and resumes from the failed one ([docs](...)). It costs a state machine definition and its IAM permissions.

### Single Lambda

**Discarded.** One function runs all steps for a request, with fewer parts to deploy. It loses because a retry reruns every step and leaves partial state across four systems (`path/to/handler`).

Revisit if: none; the resume requirement is structural.
```

### Tables

A table earns its place only when every cell is a marker (`Yes`, `Partial`, `No`, `n/a`), a number, a name or a few words: a trade-off matrix, a role-per-environment grid, an effort list. Content that needs a sentence goes in prose, bullets or an option block.

### Headings and cross-references

Headings carry no numbers. A cross-reference is a Markdown anchor to the heading, for example `[Aurora readiness](#aurora-readiness)`. Add one only where the reader needs to jump; repeat a single fact instead of pointing at a whole section for it.

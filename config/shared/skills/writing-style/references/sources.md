# Writing-style: Sources and Provenance

This file traces every rule in `SKILL.md` to its origin. It exists so the skill can be honest about what it inherits from a documented standard and what it invents. The sibling `asd-ste100` skill makes the same split between rules it can verify against a real standard and rules it only recommends; this skill borrows that discipline.

## The honest caveat first

The skill's name and the user's intent tie it to "Amazon/AWS technical documentation style." That lineage is real but partial:

- **Amazon's writing culture** (narrative six-page memos, weasel-word elimination, sub-30-word sentences, data over adjectives, verdict-first thinking) is well documented in public secondary sources and is the strongest external anchor for this skill.
- **AWS documentation conventions** (active voice, present tense, second person, imperative procedures, sentence-case headings, one term per concept) are widely corroborated, but **AWS's complete official style guide has limited public availability.** There is no single canonical public page to quote for all of them. Where this file cites AWS conventions, it relies on AWS contribution guides, secondary write-ups, and the strong agreement of sibling tech style guides (Google, Microsoft) that document the identical conventions in the open.
- **The anti-AI-tell rules** (em-dash ban, negative-parallelism ban, tricolon-padding ban, the banned-word list) are the skill author's own house style. They are not AWS rules. AWS does not ban the em dash. Attributing them to AWS would be false, so they are marked as house rules below.

Treat the AWS-sourced rules as "direction of travel corroborated across major style guides," not "quoted from a certified standard." When exact AWS wording matters (e.g. contributing to AWS-owned docs), check the target repo's own style guide.

## Part 1. AWS / Amazon-sourced rules

| Rule in SKILL.md | Origin | Notes |
|---|---|---|
| Active voice | AWS docs convention; Strunk; Google/Microsoft style guides | Universal across tech style guides. AWS states active voice clarifies who performs the action. |
| Present tense | AWS docs convention; Google/Microsoft style guides | "The function returns," not "will return." Describes system behavior as timeless. |
| Second person + imperative procedures | AWS docs convention; Google developer style guide (Procedures); Cloudflare style guide | Address the reader as "you"; write steps as commands. Applies to docs/procedures, not chat. |
| One term per concept | AWS terminology consistency; `asd-ste100` (one word, one meaning) | The one rule this skill and `asd-ste100` enforce identically. |
| Sentence-case headings | AWS docs convention; Google style guide | First word + proper nouns only. |
| Weasel-word / hedge elimination | Amazon writing culture (six-pager discipline) | "Eliminate weasel words"; replace vague qualifiers with data. Directly sourced to Amazon narrative-memo practice. |
| Numbers beat adjectives | Amazon writing culture | "Cut p99 from 850ms to 120ms" over "significantly faster." Amazon memos favor concrete data over adjectives. |
| Sentence length discipline | Amazon writing culture (<30-word target) | The skill enforces this indirectly via "one idea per sentence" and 3-sentence paragraphs. |
| Verdict-first / no balanced pro-con lists | Amazon narrative-memo culture; Working Backwards | Memos argue to a recommendation, not to a shrug. The skill's trade-off framing encodes this. |
| Omit needless words; positive form; parallel construction | Strunk, *The Elements of Style* | Predates and underlies both AWS and Google style guides. |

## Part 2. Anti-AI-tell rules (house style, not AWS)

| Rule in SKILL.md | Status | Why it's here anyway |
|---|---|---|
| Em-dash total ban | House rule. **AWS does not ban the em dash.** | The em dash is a strong AI-tell and the author overuses it as a rhythm crutch. Banning it outright is a deliberate overcorrection, not a style-guide citation. |
| Negative-parallelism ban ("not just X, it's Y") | House rule | A recognizable LLM cadence. No style guide bans it; the skill does because it reads as machine-generated. |
| Tricolon-padding ban ("fast, reliable, and scalable") | House rule | Rule of three used for rhythm rather than content. A stylistic tell, not a documented AWS rule. |
| The specific banned-word list (delve, leverage, tapestry, etc.) | House rule, community-sourced | Assembled from widely circulated lists of AI-tell vocabulary, not from AWS. |
| Abstract-metaphor-noun ban (substrate, wedge, vector, flywheel, etc.) | House rule, community-sourced | Words that read technical but hide a plainer concrete term. |
| "Don't over-sterilize" counter-check | House rule | Stripping tells can flatten prose into voiceless uniformity, itself a machine tell. |
| Formulaic-opener ban ("Whether you're X or Y…") | House rule | Marketing-copy cadence flagged as an AI-tell. |

These rules are defensible on their own merits. They are simply not what "AWS style" means, and this file says so rather than laundering personal preference through a brand name.

## Where AWS and this skill disagree with `asd-ste100`

`asd-ste100` targets machine-parsed strings and **preserves hedges** ("may", "might") because a hedge is content for a downstream parser. This skill targets human-facing prose and **bans bare hedges**, because in an ADR a hedge usually signals the author skipped the measurement. Same words, opposite rulings, different readers. Route by reader. `asd-ste100`'s own header note documents this split from its side.

## Sources

- [Amazon's writing culture: six-page memos and weasel words](https://www.thebottleneck.io/p/write-like-an-amazonian)
- [The Amazon Way of Writing](https://networkcapital.substack.com/p/the-amazon-way-of-writing)
- [Amazon Working Backwards and narrative memos (About Amazon)](https://www.aboutamazon.com/news/workplace/an-insider-look-at-amazons-culture-and-processes)
- [Amazon tone-of-voice analysis](https://www.copystyleguide.com/amazon-tone-of-voice)
- [AWS-oriented documentation style guidelines (Rackspace docs-aws)](https://github.com/rackerlabs/docs-aws/blob/master/docs/style-guidelines.md)
- [Google developer documentation style guide](https://developers.google.com/style)
- [Google developer style guide: Procedures](https://developers.google.com/style/procedures)
- [Cloudflare style guide: steps, tasks, procedures](https://developers.cloudflare.com/style-guide/documentation-content-strategy/component-attributes/steps-tasks-procedures/)
- Strunk & White, *The Elements of Style*: active voice, omit needless words, positive form, parallel construction.

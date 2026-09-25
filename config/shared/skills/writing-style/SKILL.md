---
name: writing-style
disable-model-invocation: true
description: Apply Andrea's prose style rules before drafting or revising any prose deliverable (ADRs, technical analyses, PR descriptions, Slack drafts, commit messages, release notes, documentation). Bans AI-tell vocabulary and constructions, sets structure limits and trade-off framing. Invoke BEFORE writing the draft, and re-check the finished draft against it. Not for code comments or direct conversational replies.
---

# Writing style

Applies to all prose I produce for Andrea: ADRs, technical analyses, PR descriptions, Slack drafts, commit messages, docs. Does **not** apply to code comments (which follow the no-comment default in CLAUDE.md) or to direct chat replies in this CLI.

> **Provenance (honest split).** Two kinds of rule live in this file. **AWS/Amazon-sourced rules** come from documented Amazon writing practice and AWS documentation conventions: active voice, present tense, second person, imperative procedures, one term per concept, weasel-word elimination, numbers over adjectives, verdict-first structure. **Anti-AI-tell rules** are mine: the em-dash ban, negative-parallelism ban, tricolon-padding ban, and the specific banned-word list. Both earn their place, but only the first set can claim an external standard. `references/sources.md` traces each rule to its origin; `examples/before-after.md` shows the rules applied. This mirrors how the sibling `asd-ste100` skill separates what it can verify from what it only recommends. AWS's complete official style guide has limited public availability, so the AWS conventions here are corroborated across secondary sources and sibling tech style guides (Google, Microsoft), not quoted from one canonical page.

## Banned words and phrases

Strike these on sight. Use a concrete verb or noun instead.

- **Filler verbs**: delve, leverage, utilize, unlock, foster, harness, navigate, streamline, facilitate, empower, enable (when it just means "let"), drive (when it means "cause"), underscore, showcase, embark
- **Buzz-nouns**: tapestry, landscape, journey, ecosystem, paradigm, synergy, framework (when used loosely, not in the technical sense), realm, world (e.g. "the world of cloud"), testament (as in "a testament to")
- **Abstract metaphor nouns**: substrate, wedge, vector, locus, vantage, nexus, primitive (as noun), harness (as metaphor), surface (as in "API surface"), bedrock, scaffolding (as metaphor), modality, flywheel, north star, endgame, ratchet (as metaphor). These read technical but hide a plainer concrete word: substrate → base, wedge in → add, vector → way / method, evacuate (for moving code) → move out, endgame → the last phase, ratchet → the mechanism's real name or "a limit that only tightens". Pick the concrete word.
- **Hedged superlatives**: cutting-edge, state-of-the-art, robust, seamless, best-in-class, world-class, next-generation, holistic, comprehensive, intricate, pivotal, meticulous, commendable, vibrant
- **Hedges and intensifiers**: very, quite, somewhat, fairly, rather, arguably, "significantly" without a number, possibly, probably, and bare "might"/"may" used to soften a claim. Commit to the claim or attach a number: "may reduce cost" becomes "cuts the bill ~18%" or gets dropped. Hedging signals you haven't done the measurement.
- **Vague authority**: "experts say", "studies show", "research indicates", "it is widely believed", "some argue". Cite the specific source or own the claim yourself. The passive cop-out ("it is believed", "mistakes were made") hides the actor; name them.
- **Bridge phrases**: "It's worth noting that", "It's important to remember", "In today's fast-paced world", "In the realm of", "When it comes to", "At the end of the day", "Moving forward", "a testament to", "navigating the complexities of", "cannot be overstated", "paving the way"
- **Transition tics**: moreover, furthermore, notably, indeed, crucially. Start the sentence with its content, not a throat-clearing connector.
- **AI-tells**: "I hope this helps", "Certainly!", "Absolutely!", "Great question", "Let's dive in"

## Banned constructions

- **Negative parallelism**: "It's not just X, it's Y." / "This isn't about A — it's about B." Pick one side and say it.
- **Em dash (—), any use.** Never use one. It is the loudest AI tell and you overuse it as a rhythm trick. Replace it: a period or colon for a break in thought, a comma for a light aside, parentheses for a true aside, or split into two sentences. This includes the ` — aside — ` parenthetical wrap — use commas or parentheses there instead. (The en dash `–` in numeric ranges like `2–4` is fine; this rule is about the em dash as prose punctuation.)
- **Tricolons for padding**: "fast, reliable, and scalable" when only one of those is actually load-bearing in context.
- **Vacuous openers**: "In conclusion", "Overall", "To summarize" at the start of a final paragraph. Just write the conclusion.
- **Formulaic openers**: "Whether you're X or Y…" and "By [doing something], you can…". Both commit to nothing and scream machine. State the specific case directly.

## Say this instead

Banning a word without a replacement just makes the model guess. Default swaps:

| Instead of | Write |
| --- | --- |
| utilize / leverage / harness | use |
| facilitate a discussion | run the meeting |
| ` — aside — ` (em-dash parenthetical) | `, aside,` or `(aside)` or two sentences |
| a testament to | name what it actually proves |
| navigating the complexities of | the specific hard part |

**Before:** "Our robust, cutting-edge platform leverages Karpenter to seamlessly navigate the complexities of scaling — a testament to the team's expertise."

**After:** "Karpenter scales the cluster. It cut our p99 node-provisioning time from 90s to 12s."

## Structure

- **Paragraphs cap at 3 sentences.** Break longer ones.
- **Lead with the claim, then evidence.** Not the reverse. ADR readers skim. Bury the conclusion and they miss it.
- **One idea per sentence.** If you used "and" or "which" to join two clauses, ask whether they should be two sentences.
- **Bullets for ≥3 parallel items.** Otherwise prose.
- **Numbers beat adjectives.** "Cut p99 from 850ms to 120ms" beats "significantly faster".
- **The "So what?" test.** A sentence that doesn't change the reader's understanding or decision is padding. Cut it. This is the paragraph-level companion to omitting needless words: the word rule trims phrases, this one deletes whole sentences.
- **Spell out non-obvious acronyms on first use**: judgment, not reflex. Expand a term a non-specialist reader of *this* doc wouldn't know (IRSA, KEDA, PDB); leave house-standard infra vocabulary alone (AWS, EKS, VPC, IAM). Jargon that excludes the actual audience is a defect, not precision.

## Sentence-level rules

Strunk, applied. These cut at the sentence level after the structure above is right.

- **Active voice.** "Karpenter scaled the nodes," not "the nodes were scaled by Karpenter." Reserve the passive for when the actor is unknown or genuinely irrelevant.
- **Omit needless words.** Cut padding that carries no information: "the fact that" → "that" or delete; "due to the fact that" → "because"; "in order to" / "for the purpose of" → "to" / "for"; "until such time as" → "until"; "there is X that" → "X"; "is able to" → "can"; "a number of" → a count. Delete "who is"/"which was" where the sentence survives without them.
- **Positive form.** Say what is, not what is not. "did not remember" → "forgot"; "not honest" → "dishonest"; "not many" → "few". Reserve "not" for genuine denial or antithesis.
- **Parallel construction.** Co-ordinate ideas take the same grammatical form. In a series, repeat the article/preposition before every term or only the first, not some. Match correlatives: "either grant the request or incur his ill will," not "you must either grant his request or incur his ill will" misaligned.

## AWS documentation conventions

AWS-sourced rules for **docs and procedures** (READMEs, runbooks, ADRs, PR bodies). They do not govern chat replies. Where a rule reads oddly for a given genre (a commit message has no reader to address as "you"), apply judgment.

- **Present tense.** Describe what the system does, not what it will do. "The function returns a token," not "the function will return a token." Reserve the future for events genuinely later than the action being described.
- **Second person, imperative for steps.** Address the reader as "you"; write procedure steps as commands. "Choose **Save**," not "the user should click the Save button" and not "one can save by clicking." One actor, one instruction, one step.
- **One term per concept.** Pick a single name for a thing and reuse it every time. Do not rotate "user" / "customer" / "client" or "job" / "task" / "run" for the same referent. Synonym variety is a virtue in an essay and a defect in a spec: the reader cannot tell whether two names mean one thing or two. (This is the one rule `asd-ste100` and this skill enforce identically.)
- **Sentence-case headings.** Capitalize headings like sentences: first word and proper nouns only. "Configure the cache," not "Configure The Cache."

## Trade-off framing

When recommending an option in an ADR or analysis:

1. State the recommendation in one sentence.
2. List the specific reason it wins (1–2 lines).
3. Name the strongest counter-argument and why it loses here.
4. Name the rejected alternatives with one-line dismissals.

Do not present "balanced" lists of pros and cons without a verdict. The point of the doc is the verdict.

## After any draft

Before handing back prose work, re-read it once against this file. If any banned word or construction slipped in, rewrite that sentence. Do not announce the audit, just produce the corrected output. Aim for density, not a brittle zero: one stray banned word in otherwise concrete prose is cheap to fix, but it's the cluster (vague verbs plus balanced rhythm plus throat-clearing transitions) that reads as machine. Fix the cluster.

**Don't over-sterilize.** Stripping tells is half the job. Prose that is voiceless and perfectly uniform reads as machine too. After the cuts, check that a human voice survives: commit to an opinion instead of listing balanced pros and cons, vary sentence length instead of flattening every line to the same clip, and keep "I" where it fits. The target is concrete and human, not neutral and empty.

## Additional resources

- **`references/sources.md`**: every rule traced to its origin, split into AWS/Amazon-sourced and anti-AI-tell, with citations.
- **`examples/before-after.md`**: worked before/after rewrites per rule cluster.

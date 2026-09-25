# Writing style for analyses

Every file this skill writes follows these rules: `ANALYSIS.md` and `ANALYSIS_RESOURCES.md`. This is the analysis-specific copy of Andrea's `writing-style` principles. Keep the applicable rules aligned with `../writing-style/SKILL.md` when changing either skill.

## Banned words and phrases

Replace each with a concrete verb or noun.

- **Filler verbs**: delve, leverage, utilize, unlock, foster, harness, navigate, streamline, facilitate, empower, enable (when it means "let"), drive (when it means "cause"), underscore, showcase, embark.
- **Buzz-nouns**: tapestry, landscape, journey, ecosystem, paradigm, synergy, framework (in the loose sense), realm, world ("the world of cloud"), testament.
- **Abstract metaphor nouns**: substrate, wedge, vector, locus, vantage, nexus, primitive (as a noun), surface ("API surface"), bedrock, scaffolding (as a metaphor), modality, flywheel, north star, endgame, ratchet (as a metaphor). Use the plain word: substrate becomes base, vector becomes way, endgame becomes the last phase.
- **Hedged superlatives**: cutting-edge, state-of-the-art, robust, seamless, best-in-class, world-class, next-generation, holistic, comprehensive, intricate, pivotal, meticulous, commendable, vibrant.
- **Hedges and intensifiers**: very, quite, somewhat, fairly, rather, arguably, possibly, probably, "significantly" without a number, and bare "might" or "may" that soften a claim. Commit to the claim or attach a number; an unmeasured claim goes to Open items.
- **Vague authority**: "experts say", "studies show", "research indicates", "it is widely believed", "some argue". Cite the source or own the claim, and name the actor instead of hiding it in the passive.
- **Bridge phrases**: "it's worth noting that", "it's important to remember", "in today's fast-paced world", "in the realm of", "when it comes to", "at the end of the day", "moving forward", "navigating the complexities of", "cannot be overstated", "paving the way".
- **Transition tics**: moreover, furthermore, notably, indeed, crucially. Start the sentence with its content.
- **AI-tell replies**: "I hope this helps", "Certainly!", "Absolutely!", "Great question", "Let's dive in". State the substance instead.

## Banned constructions

- **Em dash (U+2014), any use.** Use a period or colon for a break, a comma for a light aside, parentheses for a true aside, or two sentences. The en dash in numeric ranges (`2–4`) is fine.
- **Negative parallelism**: "It's not just X, it's Y." Pick one side and say it.
- **Tricolons for padding**: three adjectives where one carries the meaning.
- **Vacuous openers**: "In conclusion", "Overall", "To summarize". Write the conclusion.
- **Formulaic openers**: "Whether you're X or Y" and "By doing X, you can". State the specific case.

## Say this instead

| Instead of | Write |
|---|---|
| utilize, leverage, harness | use |
| an em-dash aside | `, aside,` or `(aside)` or two sentences |
| a testament to | what it proves |
| navigating the complexities of | the specific hard part |
| may reduce cost | cuts the bill ~18% (with a source), or drop it |

## Structure

- **Claim first, then evidence, at section and paragraph level.** Each section and paragraph opens with its claim. The analysis is evidence-first at document level: the Recommendation follows the branch sections and precedes Risks and approvals. Its verdict remains explicit.
- **Paragraphs cap at 3 sentences.**
- **One idea per sentence.** A sentence joined by "and" or "which" is often two sentences.
- **Bullets for 3 or more parallel items.** Two items stay in prose.
- **Numbers beat adjectives.** "p99 from 850 ms to 120 ms", not "faster".
- **The "So what?" test.** Delete each sentence that changes neither the reader's understanding nor the decision.
- **Acronyms.** Spell out on first use any term the approvers of this document would not know (IRSA, KEDA, PDB). House vocabulary (AWS, EKS, VPC, IAM) stays short.

## Sentence rules

- **Active voice.** Name the actor. Use the passive only when the actor is unknown or irrelevant.
- **Omit needless words.** "due to the fact that" becomes "because", "in order to" becomes "to", "is able to" becomes "can", "a number of" becomes a count.
- **Positive form.** "forgot", not "did not remember"; "few", not "not many".
- **Parallel construction.** Items in a list or series share one grammatical form.
- **Present tense.** "The Lambda returns a token." Use the future only for events that come later than the thing described.
- **Second person, imperative for procedures.** When the analysis gives adoption or prerequisite steps to a reader, address that reader as "you" and write each step as a command with one actor and one action. This does not apply to descriptions of the system workflow.
- **One term per concept.** Pick one name per thing and reuse it everywhere.
- **Sentence-case headings.** "Trade-off matrix", not "Trade-Off Matrix".

## Trade-off framing

Every recommendation, in the document and in each decision area:

1. State the verdict in one sentence before its reasons.
2. Give the one or two reasons it wins.
3. Name the strongest counter-argument and why it loses here.
4. Name the other options with one-line verdicts.

Each option block opens with its verdict, then names what the option gains and what decides it. An option described without a verdict is unfinished.

## Voice

After removing formulaic prose, check that a human voice survives. Commit to an opinion instead of a neutral pros-and-cons inventory, vary sentence length, and keep "I" or "we" where it fits. The target is concrete and human.

## Grep gate

Run from the output folder, on every file the skill wrote. It skips fenced code blocks and prints `file:line: text` for each hit.

```sh
awk 'FNR==1{f=0} /^[[:space:]]*```/{f=!f; next} !f {print FILENAME":"FNR": "$0}' ANALYSIS.md ANALYSIS_RESOURCES.md 2>/dev/null \
  | grep -i -E \
    -e '—' \
    -e '\b(delve[sd]?|delving|leverag(e|es|ed|ing)|utiliz(e|es|ed|ing)|unlock(s|ed|ing)?|foster(s|ed|ing)?|harness(es|ed|ing)?|navigat(e|es|ed|ing)|streamlin(e|es|ed|ing)|facilitat(e|es|ed|ing)|empower(s|ed|ing)?|underscor(e|es|ed|ing)|showcas(e|es|ed|ing)|embark(s|ed|ing)?)\b' \
    -e '\b(tapestry|landscape|journey|ecosystems?|paradigms?|synergy|realm|testament|substrate|locus|vantage|nexus|bedrock|modality|flywheel|north star|endgame)\b' \
    -e '\b(cutting-edge|state-of-the-art|robust|seamless(ly)?|best-in-class|world-class|next-generation|holistic|comprehensive|intricate|pivotal|meticulous(ly)?|commendable|vibrant)\b' \
    -e '\b(very|quite|somewhat|fairly|arguably|possibly|probably|moreover|furthermore|notably|indeed|crucially)\b' \
    -e "(it'?s|it is) (worth noting|important to)|when it comes to|at the end of the day|moving forward|cannot be overstated|paving the way|in today's|experts say|studies show|research indicates|widely believed|some argue|whether you're|by doing [^,]+, you can|i hope this helps|certainly!|absolutely!|great question|let'?s dive in" \
    -e ':[0-9]+: (#+ )?(Overall|In conclusion|To summarize)\b'
```

Rewrite each flagged sentence. Two hits are clean and stay: a word inside a URL, and a word inside a quoted source title. Every other hit is a fix.

The gate covers only unambiguous tokens. The read-through gate checks the rest: enable, drive, framework, world, wedge, vector, primitive, surface, scaffolding, ratchet, rather, may, might, "significantly", negative parallelism, tricolons, paragraph length, heading case, and imperative wording in reader-facing procedures.

# Before / After Examples

Worked rewrites, one cluster per section. Each shows the *cluster* failing together, because a single stray banned word is cheap to fix; the tell is the pile-up (vague verb + balanced rhythm + throat-clearing transition). These are illustrations built for this skill, not quotes from any real document.

Every "After" here has been re-read against `SKILL.md`, including its own em-dash and hedge bans.

## 1. Banned vocabulary + hedged superlatives

**Before:**
> Our robust, cutting-edge platform leverages Karpenter to seamlessly navigate the complexities of scaling, a testament to the team's expertise.

Flagged: `robust`, `cutting-edge`, `leverages`, `seamlessly`, `navigate the complexities of`, `a testament to`. Six tells in one sentence. It asserts quality instead of showing it.

**After:**
> Karpenter scales the cluster. It cut our p99 node-provisioning time from 90s to 12s.

The number does the work the six adjectives were faking.

## 2. Hedge stacking (the weasel-word cluster)

**Before:**
> This change may possibly help to significantly reduce costs, and it's worth noting that it could arguably improve latency as well.

Flagged: `may`, `possibly`, `help to`, `significantly` (no number), `it's worth noting that`, `could`, `arguably`. The sentence asserts nothing. Per Amazon's weasel-word rule, either attach a number or drop the claim.

**After:**
> This change cuts the monthly bill ~18% and drops p99 latency from 240ms to 180ms.

If you can't measure it, say "I haven't measured latency yet" instead of hedging it into fog.

## 3. Em dash as a rhythm crutch (house rule)

**Before:**
> The migration is done — mostly — and the last few tables — the big ones — will follow next week.

Flagged: four em dashes used as a cadence trick. AWS wouldn't ban these; this skill does, because they read as machine rhythm.

**After:**
> The migration is done except for the large tables. Those follow next week.

Replace with a period for a break, a comma for a light aside, or parentheses for a true aside. Here two sentences carry it.

## 4. Negative parallelism (house rule)

**Before:**
> This isn't about saving money, it's about reliability. It's not a rewrite, it's a re-architecture.

Flagged: the "not X, it's Y" cadence, twice. Pick one side and state it.

**After:**
> The goal is reliability; the cost saving is a side effect. This is a re-architecture, not a patch.

The second sentence keeps one "not" for genuine antithesis. The ban is on the padding cadence, not on the word "not."

## 5. Passive voice + nominalization + transition tic

**Before:**
> Furthermore, an analysis of the failed requests was performed by the on-call engineer, and it was determined that a retry storm had been triggered by the client.

Flagged: `Furthermore` (throat-clearing opener), `an analysis ... was performed` (nominalization + passive), `it was determined` (passive cop-out hiding the actor), `had been triggered` (passive + compound tense).

**After:**
> The on-call engineer analyzed the failed requests. The client's retries caused a storm.

Active voice names the actor. The verb "analyzed" replaces "performed an analysis of."

## 6. AWS present tense + second person + imperative (procedure)

**Before:**
> The user will need to first navigate to the console, and then the Save button should be clicked in order to persist the changes that have been made.

Flagged: `will need to` (future for a timeless step), `navigate` (banned verb + not imperative), `should be clicked` (passive), `in order to` (padding), `have been made` (compound tense), third-person "the user."

**After:**
> Go to the console. Choose **Save** to persist your changes.

Present tense, second person, one imperative per step. This is the AWS-sourced cluster working together.

## 7. One term per concept

**Before:**
> The user submits a job. Once the customer's task is queued, the client polls until the run finishes.

Flagged: `user` / `customer` / `client` for one actor; `job` / `task` / `run` for one thing. The reader can't tell if these are one referent or several.

**After:**
> The user submits a job. Once the job is queued, the user polls until the job finishes.

Repetition reads as flat prose and parses as unambiguous spec. In a spec, that trade is correct.

## 8. Structure: bury-the-verdict + balanced pros/cons (Amazon memo rule)

**Before:**
> There are several factors to weigh. Karpenter offers flexibility but adds operational surface. Cluster Autoscaler is simpler but less responsive. Both have merits, and the right choice depends on many considerations.

Flagged: no verdict. Amazon narrative memos argue *to* a recommendation. A balanced shrug wastes the reader's time.

**After:**
> Use Karpenter. It provisions right-sized nodes in ~12s versus Cluster Autoscaler's ~90s, which matters for our bursty workloads. The cost is a larger operational surface; we accept it because the team already runs Karpenter in staging. Cluster Autoscaler stays the fallback if provisioning proves unstable.

Recommendation first, the reason it wins, the strongest counter-argument and why it loses, the rejected alternative in one line. That's the trade-off framing from `SKILL.md`.

## How to read these

Each "After" is not merely shorter. It removes an ambiguity or asserts a claim the "Before" dodged. Compression is a side effect of that, not the goal. When cutting a word would delete a real qualifier (a scope condition, a number, an honest "not yet measured"), keep the word.

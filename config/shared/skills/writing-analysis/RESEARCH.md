# Research procedure

Output: `ANALYSIS_RESOURCES.md` in the output folder, the evidence log for `ANALYSIS.md`.

1. **List the targets.** For a selection, make one target for each candidate–hard-constraint pair, including candidates eliminated before the shortlist. Also list every number the verdict will rest on: price, limit, version, licence. For an implementation, list the outside-repo facts the verdict depends on.
2. **Trace each target to a primary source**: official documentation, source code, a specification, release notes, a first-party API, a vendor pricing page, or a repo path.
   - A secondary source (blog, news) counts only when it reports a vendor decision; label it `secondary`.
   - Record the check date for prices and versions, because they drift.
3. **Write each finding** into `ANALYSIS_RESOURCES.md` using the layout below. In a selection, give each candidate a row for every hard constraint: a sourced result (`meets` or `fails`) or `unknown` with what was searched. Put other findings in the same candidate section or under the relevant constraint.
4. **Re-read the file.** Copy every `unknown` target to "Not found" with what you searched. A source that turned out wrong or outdated goes under "Dead ends", so the next reader skips it.

Done when every candidate–hard-constraint pair and every other target has a sourced finding or an explicit unknown, and every unknown appears under "Not found".

## Layout

```md
# <Topic>: analysis resources

Evidence log for [ANALYSIS.md](ANALYSIS.md). Checked on YYYY-MM-DD.

## <Candidate or constraint>

| Finding | Source | Type |
|---|---|---|
| Seven-day retention: meets constraint | <URL or repo path> | primary |
| Monthly cost below $500: unknown at stated workload | Searched <pricing page>; need quote | not found |

## Not found

- <Candidate, constraint or other target>: searched <where>; confirm by <check>.

## Dead ends

- <Source>: <why it is wrong or outdated>.
```

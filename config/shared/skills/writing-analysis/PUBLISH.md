# Publishing to Notion

The local `ANALYSIS.md` stays the source of truth; the Notion page holds a copy of it as one page. `ANALYSIS_RESOURCES.md` stays local.

Use the Notion tools available in the current session. When the session has none, tell the user and end this step: the local files are the deliverable.

1. **Learn the page syntax.** When the Notion tools expose a specification of Notion's own Markdown dialect, read it first, so tables, code blocks and the table of contents use syntax the page accepts.
2. **Read the target page** at the URL the user gave. Record its title, its properties and its existing child pages.
3. **Check that the body is empty.**
   - An empty body with no child pages goes to step 4.
   - A page with content gets a short summary for the user (headings, length, child pages) and one question: replace the body, or abort. Abort ends this step with nothing written.
   - When the page has child pages, ask about each group as well: keep them, or remove them.
4. **Convert `ANALYSIS.md`.**
   - The body starts with a table-of-contents block, then the content after the first heading of `ANALYSIS.md`.
   - Anchor links to headings leave no trace, because the table of contents carries the navigation. A link that fills a whole parenthesis, such as `([Aurora readiness](#aurora-readiness))`, is dropped with its parentheses. A link inside a sentence, such as `step 7 of [Current state](#current-state)`, keeps its words as plain text.
   - The link to `ANALYSIS_RESOURCES.md` is dropped; primary sources stay as links.
   - Mermaid stays a `mermaid` code block.
   - Headings, tables, text markers and wording keep their content. Their syntax follows the Notion specification from step 1.
   - The page title and every page property stay as they are.
5. **Write the body** into the target page, replacing any existing body.
   - Child pages the user chose to keep go at the end of the body as child-page blocks: the replace removes every child page the body leaves out.
   - Child pages the user chose to remove stay out of the body.
6. **Verify.** Read the page again and confirm:
   - the table of contents opens the body;
   - every heading of `ANALYSIS.md` appears, in order;
   - the body holds no `§`, no link to a local file, and no leftover of an anchor link;
   - the child pages match the user's keep or remove answers;
   - the title and properties match what step 2 read.

Done when every check in step 6 passes, or when the user aborted at step 3.

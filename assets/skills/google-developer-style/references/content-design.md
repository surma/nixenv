# Content design

Use this reference for information order, headings, paragraphs, lists, procedures, tables, links, notices, and images.

## Information order

Start with the reader's goal, required context, and critical constraints. Do not delay information that affects safety or success.

Put prerequisites before the first procedure. Put a warning immediately before the risky action.

Present information in the order that readers use it. Keep supporting detail near the statement that it supports.

Choose one recommended path for a task. Add alternatives only when they serve distinct reader needs.

Do not repeat a procedure. Link to one maintained procedure and provide enough context for the transition.

## Paragraphs

Cover one main idea in each paragraph. Put the most important sentence first.

Use the fewest sentences that explain the idea completely. Split a paragraph when it contains unrelated ideas.

A paragraph with more than five or six sentences often needs revision. Preserve a longer paragraph when every sentence supports one idea.

Avoid walls of text. Use meaningful headings, short paragraphs, and appropriate lists.

Left-align paragraphs. Do not center, right-align, or fully justify them.

Do not insert forced line breaks inside prose paragraphs.

## Headings and titles

Use a unique `h1` for the page title. Use only one `h1` on a page.

Use sentence case. Do not put a period at the end.

Make each title describe the document's primary purpose. Make each heading identify the section's content.

For a task title, start with a base-form verb:

- Recommended: *Create an instance*
- Avoid: *Creating an instance*

For a concept title, use a noun phrase that does not start with an `-ing` verb:

- Recommended: *Migration to Google Cloud*
- Avoid: *Migrating to Google Cloud*

Use `Optional:` at the start of an optional section title. Do not put *optional* in parentheses.

Use task and concept headings in the same document when their sections require different forms.

Avoid an `-ing` form as the first word. Preserve established nouns such as *Billing* when no clearer form exists.

Do not repeat the page title as an internal heading.

Use a logical hierarchy without skipped levels. Do not use heading levels to control visual size.

Put content between a parent heading and its first child heading. Do not create empty headings.

Use *the following sections* when you introduce several subsections. Do not call the group *this section*.

Keep heading punctuation simple. Rewrite a heading that requires complicated punctuation.

Use an abbreviation in a heading only when readers know it better than its long form. Define it in the first following paragraph.

Do not number headings to express sequence. Use page order and heading hierarchy.

Avoid code in a heading. When code is necessary, add a descriptive common noun.

Do not put links in headings.

## Stable heading targets

Use custom anchors for frequently linked sections, short stable links, or headings that can change.

Use lowercase words separated by hyphens in a custom anchor.

When you revise an automatically anchored heading, preserve the old generated anchor as a custom anchor.

Do not change an existing custom anchor without checking inbound links. Change it when retaining a harmful term creates greater harm.

## Lists

Except for a one-step procedure, do not create a list with one item. Use a sentence, paragraph, or notice instead.

Choose the list type by meaning:

- Use a numbered list when order, phase, priority, or sequence matters.
- Use a bulleted list when order does not matter.
- Use a description list for terms paired with definitions or explanations.
- Use bold run-in headings in bullets for compact concept-and-description pairs.

Make it clear whether every unordered item is required, optional, or an example.

Introduce most lists with a complete sentence. Use a colon when the list follows immediately.

Do not end an incomplete introduction with a colon and complete it through list items.

Omit an introduction only when the immediately preceding heading supplies all necessary context.

Use parallel grammar and syntax for every item in one list.

Start each ordinary list item with a capital letter.

Use end punctuation when an item contains a verb or a complete thought.

Omit end punctuation for a single word, a noun phrase without a verb, code-only text, link-only text, or a title.

If punctuation becomes inconsistent, rewrite the items in parallel form. Otherwise, punctuate every item for consistency.

For a description list, capitalize the term and omit a period after it. End a complete description with a period.

For bold run-in headings, use a colon or period consistently. Do not use a dash between the heading and description.

Use the serial comma in an inline list.

Do not end a list with *etc.*, *and so on*, or a similar phrase. Introduce the list as nonexhaustive.

## Procedures

Use a numbered list for a sequence with two or more steps.

Write a one-step procedure as one bulleted sentence. Do not create a numbered list with one item.

Introduce a procedure when readers need context beyond the heading. Do not repeat the heading.

Use a complete introductory sentence. A colon can follow *Follow these steps*, *Do the following*, or a direct imperative.

Make the first sentence of every step start with, or contain, an imperative verb.

Put one primary reader decision or action in each step. Combine only small inseparable actions.

Keep steps short. Split a step when readers must track several independent actions.

Use lowercase letters for substeps. Use lowercase Roman numerals for a third nested level when the format supports it.

End a step with a colon when its substeps follow immediately.

For a step that contains a command, use this order:

1. State the action.
2. Show the command.
3. Explain the placeholders.
4. Explain the command when necessary.
5. Show useful output when necessary.
6. Explain the result in a separate paragraph when necessary.

Use `Optional:` as the first word of an optional step.

State the tool, application, or field before the action:

- Recommended: In the console, click **Create**.
- Avoid: Click **Create** in the console.

State a useful goal before the action:

- Recommended: To create the file, click **New**.
- Avoid: Click **New** to create the file.

If a goal-first sentence makes a required step appear optional, use a colon. For example, write *Create the file: click **New***.

State an action before its result or justification. Keep a short result in the same step paragraph.

Do not repeat a dialog name in consecutive steps when the result already establishes the dialog.

Tell readers to press `Enter` in the same step as the text entry.

Do not include keyboard shortcuts as the primary procedure. Prefer an accessible interface path.

Do not use *please* in a step.

Do not orient readers with *above*, *below*, *left*, or *right*. Use a label, accessible name, context, or screenshot.

Do not write *run the following command*. Introduce the command by its purpose.

Provide all preparation information before the task. Limit interruptions along the successful path.

## Tables

Use a list for items with one field. Use a description list for items with two related fields.

Use a table for items with three or more related fields that readers compare across rows or columns.

Do not use a table for page layout, code layout, a one-column list, or a long one-dimensional list.

Avoid a table in the middle of a numbered procedure.

Introduce every table with a complete sentence that explains its purpose. This introduction supports screen reader users.

Place a table next to the text that introduces it. Do not put a table inside a sentence.

A single nearby table does not need a caption. Give nearby multiple tables numbered captions.

Format a caption as **Table N.** followed by a sentence-case description without final punctuation.

Refer to a numbered table by number. Use lowercase *table* unless it starts a sentence.

Use semantic header cells for the first row and first column. Add appropriate `scope` attributes.

Do not merge cells or use `colspan` and `rowspan`.

Use sentence case and concise text for column headings. Do not add end punctuation.

Sort rows logically. Use alphabetical order when no domain order exists.

Split a long or complex table into simpler tables. Use responsive table styles.

Do not communicate new information only through a symbol, image, or color in a table.

Avoid links that target a table directly. Link to its containing section when practical.

## Cross-references and links

Use links selectively. Every link adds a reader decision and a possible exit from the task.

Provide short essential context on the current page. Link for deeper information or authoritative third-party detail.

Avoid duplicate links to the same destination on one page. Repeat a link only across distant or independent entry points.

Link to the most relevant page and heading. Do not offer several links that serve the same purpose.

Use either the exact destination title or a short descriptive phrase as link text.

Put important words near the start of descriptive link text.

Make link text understandable outside its sentence. Do not use *click here*, *this article*, *this document*, or *learn more* alone.

Do not use the same link text for different destinations in one document.

Do not expose a URL as link text unless a legal or technical context requires it.

When a linked name includes a newly introduced abbreviation, include both forms inside the link.

When linking a code item, include its descriptive noun when that wording remains natural. For example, link the full phrase *`--name` flag*.

Use this sentence pattern for a standalone cross-reference:

> For more information about TOPIC, see LINK.

Use *about*, not *on*, in this pattern. Use *see* for links and cross-references.

Explain why a link matters when the destination is not clear from its text.

Explain unexpected behavior in the link text. Examples include a file download, email action, same-page jump, or new tab.

Do not force a link into a new tab. If a required exception opens a new tab, state that behavior.

Put punctuation and quotation marks outside the link unless they belong to the linked title.

## Images and figures

Use an image when a visual explanation communicates information that prose cannot communicate efficiently.

Use screenshots only for important and difficult interface details. Crop each screenshot to the relevant region.

Do not include personally identifiable information in a screenshot.

Cover sensitive information with a fully opaque solid shape. Flatten layered files before distribution.

Do not use an image of text, code, or terminal output.

Prefer SVG for diagrams. Use PNG when SVG is unavailable. Avoid transparent backgrounds when the site can change themes.

Use MP4 or another efficient video format instead of an animated GIF.

Use one operating system and visual treatment consistently across related screenshots.

Give image files descriptive names.

Introduce most images with a complete sentence. A procedure can introduce a screenshot through its immediately preceding step.

Distinguish these elements:

- **Alt text:** a concise contextual replacement for the image
- **Figure caption:** an optional visible summary
- **Figure description:** a detailed text equivalent for complex information

Give every `img` element an `alt` attribute.

Use `alt=""` for a decorative image or an image whose information already appears in nearby text.

Do not start alt text with *Image of* or *Photo of*.

Use punctuation in alt text. Use a sentence or noun phrase that fits the surrounding context.

Keep alt text within about 155 characters. Add a nearby figure description when the information requires more text.

Do not use a caption as a substitute for alt text.

When a figure needs a number, format its caption as **Figure N.** followed by a complete summary sentence.

Use end punctuation in figure captions. Refer to a numbered figure by number without spatial language.

Provide a figure description when the caption and alt text cannot convey all useful information.

Do not embed explanations or captions inside an image. Repeat unavoidable embedded information in accessible text.

Use sentence case for labels and callouts inside an image. Use full product names.

Provide high-resolution assets when practical. Do not enlarge a low-resolution source to simulate higher resolution.

Use the site's standard image layout. Do not manually position or center images with inline styles.

## Notices

Use a notice only for information outside the main flow. Readers often skip notices.

Do not place several notices together. Reorganize the content when notices lose their distinct purpose.

Choose the least severe accurate type:

- **Note:** useful information that readers can skip and still succeed
- **Caution:** a reason to proceed carefully
- **Warning:** an irreversible, financial, data-loss, or security risk
- **Success:** a dynamic confirmation in interactive content

Do not use a note for a prerequisite, required step, expected result, cross-reference, or necessary success information.

Put required information in the main flow. Put a warning immediately before the associated risk.

Use the site's standard notice markup and visual treatment.

## Footnotes

Avoid footnotes because they interrupt navigation, accessibility, and localization.

Use an inline explanation, cross-reference, note, or short parenthetical instead.

When no alternative works, use a superscript number and place the footnote near the relevant content.

# Foundations

Read this reference for every task that uses the Google developer documentation style.

## Authority and judgment

Apply the project style before this guide. Use this guide before general third-party references.

Use established project terminology when it helps the intended readers. Do not replace a useful domain convention only to satisfy this guide.

Make a deliberate exception when the exception improves clarity, accuracy, accessibility, or reader success. Apply the exception consistently.

Use an authoritative technical source for definitions. Use Merriam-Webster for unresolved US English spelling questions.

This guide does not replace legal advice. Consult qualified counsel for legal, trademark, launch, or policy questions.

## Reader, purpose, and path

Identify the intended reader before drafting. State required knowledge near the document start when it affects success.

Define one primary reader goal for each document. Organize the document around that goal.

Give the reader necessary context before a decision or action. Omit background that does not support the current goal.

Prefer prescriptive documentation for complex tasks. Recommend one suitable path for the most common case.

Document alternatives only when readers need them. Separate materially different alternatives into pages, sections, or tabs.

Include prerequisites before the procedure. Do not hide a prerequisite in a note or later step.

## Voice and tone

Use a conversational, friendly, respectful voice. Sound like a knowledgeable person who understands the reader's goal.

Use natural language without copying spoken language. Spoken language often contains unnecessary words, slang, and incomplete thoughts.

Use familiar two-word contractions. Avoid invented or three-word contractions.

Use transitions when they clarify a relationship. Remove transitions that make the prose formal or slow.

Do not optimize for entertainment. The reader often needs information quickly.

Avoid these tone problems:

- A formal, academic, or legalistic register
- A pushy or patronizing register
- Cuteness, zaniness, or forced personality
- Slang and internet abbreviations
- Pop-culture references
- Humor that depends on culture or language
- Buzzwords and unexplained jargon
- Exclamation points
- Repeated sentence openings
- Placeholder phrases such as *please note* or *at this time*

Do not use *easy*, *easily*, *simple*, *simply*, *quick*, or *quickly* to judge a task.

Do not use *please* in ordinary instructions. Use it for a real request, inconvenience, permission, or apology.

Do not use a contraction of *let us* to lead the reader through a task. Address the reader directly or use an imperative.

## Clear language for a global audience

Write for readers who use English as an additional language. Write for translation and localization systems.

Use the simplest accurate word. Prefer *start* to *commence*, *use* to *utilize*, and *so* to *consequently*.

Use one word instead of a phrase when both express the same meaning. Keep all required technical precision.

Keep most sentences below 26 words. Split a long sentence before it contains several independent ideas.

Use standard subject-verb-object order. Keep the main subject and verb near the sentence start.

Avoid phrasal verbs when a direct verb exists. Some established terms, such as *set up* and *sign in*, remain acceptable.

Limit noun modifiers. Do not normally place more than two modifying nouns before another noun.

Place a modifier next to the word that it modifies. Put *only* immediately before its intended scope.

Use each important word in its primary sense. Do not use one word as both a noun and verb nearby.

Use helper words when they improve comprehension. Helpful words include *that*, *then*, *of*, and repeated prepositions.

Repeat a noun when a pronoun would create ambiguity. Repeat shared sentence elements when omission could change the meaning.

Include relative pronouns such as *that* and *which* when they improve clarity.

Include articles. Do not remove *a*, *an*, or *the* from headings or instructions to save space.

Avoid these elements:

- Idioms, colloquialisms, and slang
- Metaphors and other figurative language
- Culture-specific holidays, sports, and practices
- Seasons as global date references
- Geographic assumptions
- Humor
- Unexplained abbreviations
- Directional page or interface references

Use a consistent term, capitalization, and format for each concept. Consistency helps readers and translation systems.

## Inclusive language

Use literal and precise language. Many exclusionary terms also create technical ambiguity.

Use the singular *they* for an unspecified person. Do not use *he/she*, *(s)he*, or a generic gendered pronoun.

Use non-gendered role terms. For example, use *person-hours*, *staffed*, and *workforce*.

Avoid ableist language and mental-health metaphors. Replace them with the exact technical condition.

Avoid unnecessarily violent, graphic, or militarized metaphors. Describe the operation or incident directly.

Avoid socially charged labels for technical concepts. Prefer specific terms such as *allowlist*, *denylist*, *primary*, *replica*, or *controller*.

Do not apply a one-word replacement blindly. Confirm that the replacement describes the actual relationship.

When a discouraged term appears in code, format the literal as code. Explain the preferred concept outside the code.

When an established term aids recognition, introduce a preferred term first. Put the established term in parentheses once when necessary.

Use diverse, internationally plausible examples. Avoid stereotypes in names, roles, ages, locations, and relationships.

Do not describe people without disabilities as *normal* or *healthy*. Use a precise and neutral description.

Avoid language that defines people only by a disability. Research whether the relevant community prefers person-first or identity-first language.

Avoid judgmental phrases such as *suffers from*, *victim of*, or *wheelchair-bound*. Use neutral factual descriptions.

Do not use euphemisms such as *differently abled* or *special*.

## Accessibility

Write content that remains understandable without color, sound, images, pointer movement, visual position, or punctuation cues.

Use semantic elements for their intended purpose. Prefer native HTML elements over custom controls.

Make all controls reachable with a keyboard. Test interactive documentation with a keyboard and a screen reader.

Use a logical heading hierarchy. Use one `h1`, do not skip levels, and do not use headings only for visual styling.

Use concise, unique headings. Each heading must describe its section when a reader scans it independently.

Use link text that identifies the destination or action. Do not use *click here*, *this document*, or a bare URL.

Separate adjacent links with ordinary text or punctuation.

Use lists to separate steps and related items. Use parallel structures within a list.

Introduce tables in preceding text. Mark row and column headings semantically, and avoid merged cells.

Avoid tables when a list communicates the same information. Tables create additional work for screen reader users.

Give every image an `alt` attribute. Use concise alt text for informative images and `alt=""` for decorative images.

Do not put essential information only in an image. Provide an equivalent explanation in nearby text.

Do not use screenshots of text, code, or terminal output. Use real text instead.

Provide captions, transcripts, or descriptions for audio and video. Do not use flickering or flashing media.

Label every form field. Place the label outside the field and associate it semantically.

Write validation errors that identify the problem and the correction.

Do not rely on color, size, shape, or position as the only state indicator. Add a text label or another nonvisual cue.

Refer to a control by its accessible label. Do not describe an unlabeled control only by its shape or location.

Do not force line breaks inside paragraphs. Left-align text and preserve the document's natural reading order.

Check the document in these conditions:

- Without sound
- With only sound
- Without images or animation
- Without color
- With a keyboard
- With screen magnification
- Without punctuation cues

## Claims, requirements, and recommendations

Write factual and objective statements. Limit claims to information that readers can verify during the document's useful life.

Avoid unsupported claims about performance, cost, scale, security, quality, and competing products.

Do not use superlatives such as *best*, *fastest*, or *simplest* without verifiable evidence.

Use *ensure* and *guarantee* only for outcomes that the described process controls completely.

Cite a source for specific performance, cost, storage, or scale claims.

Describe a security feature as risk reduction or design intent. Do not promise that the feature prevents every incident.

Describe competing products accurately and neutrally. Avoid comparisons that can become false after a product change.

Use explicit modal language:

- Use *must* for a required action or state.
- Use an imperative for a direct required instruction.
- Use *can* for permission, ability, an option, or a possible outcome.
- Use *might* for an uncertain outcome.
- Use *We recommend* for an explicit recommendation from the authoring organization.
- Reserve *may* for policy or legal language.
- Avoid *could*, *would*, *will*, *shall*, and ambiguous *should*.

Describe an expected outcome in the present tense. Describe a possible outcome with *can* or *might*.

When a state matters, identify who sets it. Do not write that a value *should be true*.

## Timeless documentation

Document the current product state. Do not assume that readers know an earlier version.

Avoid words that anchor ordinary product documentation to publication time:

- *as of this writing*
- *currently*
- *does not yet*
- *eventually*
- *existing*
- *future*
- *latest*
- *new* or *newer*
- *now*
- *old* or *older*
- *presently*
- *soon*

Use a version number or date when a time comparison is necessary.

Use time-dependent language in release notes, announcements, and dated procedures when time is part of the content.

Do not describe unreleased features or plans. Obtain the required legal and product approval before a preannouncement.

## Third-party material

Do not copy third-party prose, images, code, logos, audio, or other material without confirmed rights.

Paraphrase necessary context and link to the source. Provide enough context to prevent an unnecessary link traversal.

Do not assume that open source material or repository content permits reuse. Check the applicable license.

## Product names and trademarks

Use the official spelling and capitalization for every product, brand, company, feature, and community term.

Use a lowercase official name at a sentence start when necessary. Prefer a rewrite that avoids that position.

Treat feature names as lowercase unless the owner officially capitalizes them.

Use a full product name unless the owner approves a shorter form. Use a general noun after the full context becomes clear.

Do not use *the* before a product name. Use *the* before a named tool, API, console, or CLI.

Do not use a product name, trademark, or abbreviation as a verb.

Use a trademark as a modifier for a generic noun. Do not make a trademark plural or possessive.

Follow the trademark owner's marking and attribution requirements.

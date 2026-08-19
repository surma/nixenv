# Technical content

Use this reference for APIs, code, commands, placeholders, interfaces, markup, files, examples, product names, and trademarks.

## Code in prose

Use code font for text that readers enter verbatim and for named code entities.

Use code font for these items:

- Attributes, values, classes, methods, functions, constants, enums, and language keywords
- Commands, command-line tools, flags, input, output, and environment variables
- Data types, database elements, package names, ports, and query parameters
- Filenames, filename extensions, directories, paths, and placeholders
- HTTP methods, content types, and status codes
- HTML and XML element names without angle brackets
- URLs, domains, IP addresses, and email addresses when they are input, output, or literals

Use ordinary font for products, organizations, conceptual domain names, and URLs that readers follow. Prefer a descriptive link instead of an exposed URL.

Use both bold and code font when a named UI element contains a code value. For example, use **`my-instance`**.

Do not add quotation marks around code unless the quotation marks belong to the literal.

Do not use a code item as an English verb. Do not make a code item plural or possessive.

Add a common noun after the code item. Write *send a `POST` request* and *`Intent` objects*.

Omit a class qualifier from a method name unless the qualifier prevents ambiguity.

Call an HTTP result a *status code*. Write *an HTTP `400 Bad Request` status code* or *an HTTP `2xx` status code*.

## API reference comments

Document every public type, constant, field, enum, typedef, and method. Document every parameter, return value, and exception.

Follow the language-specific documentation format and code style. Add a focused sample near the top of each unique reference page when useful.

Format API names as code and link them to their reference entries. Follow the generator's rules for repeated links.

Make the first sentence short, unique, and suitable for an index. Put the most important information in that sentence.

For a type, state its purpose without repeating its name. Then explain its use, key behavior, requirements, pitfalls, and related APIs.

For a method, use present tense and start with its action:

- Use *Checks whether* for a Boolean getter.
- Use *Gets* for another getter.
- Use *Creates* for a convenience constructor.
- Use *Sets*, *Updates*, *Deletes*, or *Registers* for those actions.
- Use *Called by ACTOR* for a callback.

State prerequisites and missing-dependency behavior. Include relevant exceptions and related APIs.

Capitalize a parameter description and end it with a period. Start a non-Boolean description with *The* or *A* when practical.

For a Boolean control parameter, describe both the true and false behavior. For a Boolean state, write *True if CONDITION; false otherwise*.

Do not format *true* or *false* as code in these parameter and return descriptions.

For a default, describe all relevant values or ranges. Then introduce the default with *Default:*

Start a non-Boolean return description with *The*. Keep the return description brief.

If the generator supplies *Throws*, start an exception description with *If*. Otherwise, start it with *Thrown when*.

Start a deprecation notice with *Deprecated.* Name the replacement and the required migration. Include the first deprecated version when the API tracks versions.

## Code samples

Follow the project or language code style. Preserve valid syntax and use the language's required indentation.

Keep lines within 80 characters when a safe break exists. Never change code behavior only to satisfy the limit.

Introduce most samples with a complete sentence. Use a colon when the sample immediately completes that sentence.

Use `pre` for a source-code sample in HTML. In Markdown, indent every code line by four spaces.

Represent an omission with a comment in the sample language. Do not use an ellipsis for omitted source code.

Do not offer click-to-copy for an incomplete sample.

Test samples when practical. Confirm imports, prerequisites, versions, output, and cleanup behavior.

## Commands and output

Link the first useful command mention to its complete reference. Show only the arguments required for the recommended task.

Prefer a runnable click-to-copy command. Keep syntax notation and explanatory comments outside that command.

Use a code block for a command. Wrap a long command near 80 characters at a safe boundary.

Indent each continuation line by four spaces. End every nonfinal line with the platform's continuation character.

Use a backslash for Linux and common shells. Use a caret for Windows command syntax.

When a block contains multiple input lines, show a prompt for each line. Do not include the current directory in the prompt.

Use a consistent prompt style throughout one document. Distinguish local and remote prompts when the context changes.

Separate input from output. Show output only when readers need a value or a verification signal.

Introduce exact output with *The output is the following:*. Introduce variable output with *The output is similar to the following:*.

Use `...` on its own line for omitted command output. Do not use the single ellipsis character.

Use these syntax conventions only in reference syntax:

- `[ARGUMENT]` for one optional argument
- `[ARGUMENT_1] [ARGUMENT_2]` for separate optional arguments
- `{CHOICE_1|CHOICE_2}` for exactly one required choice
- `[ARGUMENT ...]` for a repeatable argument

Do not put these metacharacters in click-to-copy commands. Remove optional arguments, show separate runnable variants, or explain the syntax outside the block.

Use the product's command terminology. Describe the complete command when specialized names for its parts do not help the reader.

Preserve exact process-control terms for Linux signals. Do not replace a signal's documented action with a friendlier but inaccurate verb.

## Placeholders

Use a descriptive uppercase name with underscores, such as `PROJECT_ID`. Do not use `x`, `MY_`, or `YOUR_` as a generic placeholder.

Use another convention only when the surrounding syntax requires it. Apply that convention consistently.

In HTML prose, nest a `var` element in a `code` element. In HTML code blocks, mark each placeholder with `var` inside `pre`.

In Markdown prose, format a placeholder as *`PROJECT_ID`*. Markdown code fences cannot add separate placeholder styling.

Do not include optional brackets, choice braces, or repetition marks inside the placeholder markup.

Explain each placeholder at its first occurrence. Repeat the explanation when distance or separate entry paths make repetition useful.

For one placeholder, write *Replace `PLACEHOLDER` with DESCRIPTION.*

For multiple placeholders, write *Replace the following:* and add a list of descriptions in occurrence order. Start each description with lowercase text.

After sample output, write *This output includes the following values:* and explain each variable value in occurrence order.

## UI instructions

Describe the reader's goal instead of a widget gesture when the interface path is clear. Add interface detail when readers need help.

Use the exact visible label and make it bold. Do not add quotation marks or code font unless the label contains a code value.

Match the label's capitalization. Use sentence case when all labels use capitals or related labels use inconsistent capitalization.

Do not use a UI label as a verb. Name the control and the action.

Identify a control by its accessible label or tooltip. Do not identify it only by color, shape, icon, or location.

Omit a trailing ellipsis from a UI label unless its omission causes confusion.

Use accurate element names:

- Use *window* for a desktop application window.
- Use *page* for a web page or console subpage.
- Use *dialog* for a smaller detached window.
- Use *pane* or *panel* for a distinct region in a larger window.
- Use *section* for a labeled group of controls.
- Use *navigation menu* for a control that links to pages.
- Use *tab*, *toolbar*, *menu*, *button*, *field*, *list*, *checkbox*, and *toggle* as their interfaces define them.

Use *box* for a generic text box. Use *field* for Google Cloud, Google Workspace, or an interface that uses that term.

Use *in* with dialogs, fields, lists, menus, panes, and windows. Use *on* with pages, tabs, and toolbars.

Use these interaction verbs precisely:

- Use *click* for a mouse action. Do not write *click on*.
- Use *tap* for a touchscreen action.
- Use *press* for a physical button or keyboard key.
- Use *enter* or *type* for text input.
- Use *select* and *clear* for checkbox actions.
- Use *drag*, not *click and drag* or *drag and drop*.
- Use *turn on* or *turn off* for a toggle state. Do not use *toggle* as a verb.

Prefer an accessible interface path over a keyboard shortcut. When a shortcut helps, use `kbd` in HTML or code font elsewhere.

Spell out modifier names. Write `Control+S` and `Command+S`, not abbreviated names or symbols.

Put the macOS shortcut after the Windows and Linux shortcut. For example, write `Control+C` (`Command+C` on macOS).

For menu paths, prefer prose such as *In the **File** menu, select **Open***.

If the site uses angle brackets, expose *and then* to assistive technology. Do not use menu-path notation across unrelated control types.

## Semantic HTML

Use each HTML element for its defined meaning. Prefer native controls and document structure over custom visual equivalents.

Do not use tables or frames for page layout. Do not use heading elements only to change text size.

Use `em` for semantic emphasis. Use `i` for non-emphasis italics, such as a term discussed as a term.

Use `strong` for strong importance. Use `b` for visual attention without added importance, including named UI elements.

Use `br` only when a line break forms part of the content. Use paragraphs and CSS for ordinary spacing.

Use `cite` for a standalone work's title. Use semantic lists, tables, labels, keyboard markup, and landmarks where applicable.

## HTML and Markdown source

Follow the repository's source format and formatter before these defaults.

For HTML and similar source files:

- Use spaces instead of tabs.
- Indent by two spaces per level.
- Use lowercase element and attribute names.
- Remove trailing spaces unless Markdown requires them.
- Keep ordinary lines within 80 characters.
- Keep an unbreakable URL or required single-line metadata intact.
- Include optional HTML elements instead of omitting them.

For a small edit, preserve a file's consistent line-length convention. Do not reformat unrelated content.

Use Markdown when its readable source expresses the required structure. Use HTML when the content needs semantics or behavior that Markdown cannot express.

Follow the existing project choice when a project standard exists.

## Filenames and file types

Use lowercase ASCII alphanumeric characters and hyphens in new file and directory names. Choose a descriptive name.

Follow an established local naming convention when changing it is not feasible. Preserve names that a generator or API controls.

In prose, use the exact filename in code font and add the noun *file*. For example, write *the `build.sh` file*.

Use the formal file type name instead of an extension for a generic type. Write *a PNG file*, *a Bash file*, and *a YAML file*.

Do not use a file type as a verb. Write *extract the zip file*, not a verb formed from *zip*.

## Safe example data

Never expose real personal data, credentials, project names, addresses, email addresses, domains, or phone numbers in examples.

Use reserved data where a standard provides it:

- Domains: `example.com`, `example.org`, and `example.net`
- IPv4: `192.0.2.0/24`, `198.51.100.0/24`, and `203.0.113.0/24`
- IPv6: values in `2001:db8::/32`
- US phone numbers: `800-555-0100` through `800-555-0199`
- Company: Example Organization
- Service account numeric ID: `123456789012345678901`

Use a nonbreaking hyphen in a displayed phone number. Prefix an international number with `+` and its country code.

Use a meaningful fictional project name. Do not use `foo`, `bar`, or `baz` when a descriptive name can teach the concept.

For person names, use varied names without stereotypes. The source list includes Alex, Amal, Ariel, Bola, Charlie, Cruz, and Dana.

The complete approved list also includes Dani, Hao, Ira, Izumi, Jie, Kai, Kalani, Kim, Kiran, Lee, and Lucian.

It also includes Luka, Mahan, Noam, Nur, Quinn, Raha, Rosario, Sasha, Tal, Taylor, Tristan, and Yuri.

Use an initial for a surname, such as *Quinn N.* Use singular *they* unless gender is necessary to the example.

Use the Alice and Bob cast only when a referenced technical specification uses that convention.

Use fictitious street addresses. Use a reserved domain and an approved name for email, such as `dana@example.com`.

## Product names and trademarks

Use the owner's official spelling and capitalization for brands, companies, products, services, features, and community terms.

Treat a feature name as lowercase unless the owner officially capitalizes it. Match exact UI capitalization when you refer to a label.

Use the full product name. After you establish context, use a generic noun instead of an unapproved shortened name.

Do not put *the* before a product name. Use *the* before a named API, CLI, console, or tool.

Do not use a product name, feature name, trademark, or abbreviation as a verb.

Follow each trademark owner's marking and attribution rules. Use a trademark as a modifier for a generic noun.

Do not pluralize, possess, abbreviate, or otherwise alter a trademark.

# Word usage

Use this reference for modality, connectors, interface verbs, technical spelling, jargon, and inclusive alternatives.

This reference distills high-value entries. It does not replace the complete and frequently updated word list.

## Exact-term lookup protocol

Use this order for a disputed, sensitive, branded, unfamiliar, or omitted term:

1. Follow the user's requirements and the project's glossary.
2. Check the exact term in the live [Google word list](https://developers.google.com/style/word-list).
3. Confirm whether the entry applies only to Android, Google Cloud, or Google Workspace.
4. Treat *avoid* or *use with caution* as contextual guidance.
5. Treat *do not use* as the default prohibition outside exact literals.
6. Check an authoritative technical source when the live list has no entry.
7. Use the first Merriam-Webster spelling for an unresolved US English choice.
8. Use the Chicago Manual of Style for another unresolved editorial choice.

Do not guess an exact spelling or replacement when a live lookup is possible.

When a term must match code, a command, an API, or a UI label, preserve the literal. Format code literals as code and explain the preferred term nearby.

When the live guide differs from this distillation, follow the live guide unless a higher authority overrides it.

## Requirements, options, and possibility

Choose a modal that states the intended force:

- Use *must* for a requirement.
- Use an imperative for a direct required action.
- Use *can* for permission, ability, an option, or a possible outcome.
- Use *might* for an uncertain outcome.
- Use *may* only for policy or legal language.
- Use *We recommend* only for a recommendation from the authoring organization.

Avoid *should*. It can mean a requirement, recommendation, expectation, or prediction.

Avoid *could* and *would*. Use *can* for ability or possibility, and use *might* for uncertainty.

Avoid *will* for ordinary product behavior. Use present tense.

Avoid *shall* unless legal counsel requires it.

Do not state that a value *should be true*. Name the actor, requirement, default, or expected result.

## Logic and connectors

Use the connector that states the exact relationship:

- Use *because* for causation. Do not use ambiguous *as* or *since* for this meaning.
- Use *while* only for a time relationship. Use *although* or *whereas* for contrast.
- Use *after* instead of *once* when sequence is the meaning.
- Use *if* for a condition. Use *whether* for alternatives or an indirect yes-or-no question.
- Include *then* when it makes an `if` condition easier to parse.
- Use *either* for two choices and keep both choices grammatically parallel.
- Write *neither A nor B*.
- Use *between* for distinct items. Use *among* for members of a group.
- Use *each* for individual items. Use *all* for the group collectively.
- Use *about*, not *on*, after *information* in a cross-reference.

Avoid *and/or*. State whether one choice, both choices, or any combination is valid.

Do not use *via*. Choose *through*, *by*, or another word that names the relationship.

Use *per* for a rate. Use *for each*, *according to*, or *in response to* for other meanings.

When *using* can attach to two sentence elements, write *by using* or revise the sentence.

Do not use *with* for unclear ownership or method. Write *that has* for ownership or *by using* for method.

Use *to* instead of *in order to*. Use *lets you* instead of *allows you to* or *enables you to*.

Put a clear noun after *this*, *that*, *these*, or *those* when the reference can be ambiguous.

Avoid *e.g.* and *i.e.* Use *for example* and *that is*.

## Timeless terms

Describe the product state directly. Remove publication-time commentary that the reader cannot act on.

Avoid these terms in ordinary product documentation:

- *as of this writing*
- *currently* and *presently*
- *does not yet*
- *eventually*
- *future*
- *latest*
- *new* and *newer*
- *now*
- *old* and *older*
- *soon*

Use an exact version, release, date, or comparison point when time affects the instruction.

Use *earlier* and *later* with a version number. Follow a product-specific convention when it requires *lower* or *higher*.

Use *new* only when the contrast with another recently created item matters. Write *Create a project* unless the distinction matters.

Use *latest* only when an ongoing instruction intentionally means the latest available release. Add a reference point when the document depends on one release.

Use *legacy* only with a neutral, precise definition. Do not use it as a negative judgment.

Time-dependent words are suitable in dated announcements, release notes, and migration schedules when time is part of the content.

## Interface and action verbs

Use these verbs consistently:

- Use *click* for a desktop pointer action. Do not write *click on*.
- Use *tap* for an on-screen action on a touch device.
- Use *press* for a mechanical button or keyboard key.
- Use *select* for an interface choice, selected text, or a checkbox.
- Use *choose* only for a generic choice outside an exact UI action.
- Use *clear* to remove a checkbox mark. Do not use *uncheck* or *deselect* for this action.
- Use *deselect* for a selected item that is not a checkbox.
- Use *enter* for text input. Use *type* only when the physical input method matters.
- Use *drag*, not *click and drag* or *drag and drop*.
- Use *point to* for pointer placement. Use *hold the pointer over* when duration or a delayed response matters.
- Use *go to* instead of *scroll to* when implementation does not matter.
- Use *turn on* or *enable* consistently for activation.
- Use *turn off*, *deactivate*, *unavailable*, or another precise state instead of a vague *disable*.
- Use *extract* instead of *unzip*, *untar*, *unarchive*, or *uncompress*.

Do not call a link a button. Do not use *toggle* as a verb.

Do not use *email* or a file type as a verb. Write *send email* and *extract a zip file*.

Use *sign-in* and *sign-out* as nouns or modifiers. Use *sign in* and *sign out* as verbs.

Write *sign in to*, not *sign into*. Use *sign-on* only in *single sign-on*.

## Preferred technical forms

Use the project's established form when it intentionally differs. Otherwise, use these forms:

- *backend*, not *back end* or *back-end*
- *codebase*, not *code base*
- *data center*, *data source*, and *data type*
- *datastore*, when that single concept is intended
- *ecommerce*, not *e-commerce*
- *email*, not *e-mail*
- *endpoint*, not *end point*
- *filename*, but *file system*
- *hardcode* and *hardcoded*, without a hyphen
- *hostname*, not *host name*
- *inline* as an adjective
- *internet* and *web* in lowercase
- *lifecycle*, not *life cycle*
- *microservices*, not *micro-services*
- *on-premises*, not *on-premise* or *on prem*
- *runtime* for an execution environment
- *run time* for a time during program execution
- *setup* as a noun or modifier, and *set up* as a verb
- *startup* as a noun or modifier, and *start up* as a verb
- *web server*, not *webserver*
- *whitepaper* and *whitespace*
- *wildcard*, not *wild card*

Use *WebAssembly* and *Wasm* with specification capitalization.

Use *data* as a singular mass noun. Write *the data is* and *less data*.

Use *API* for a web or language API, not for one class or method.

Name a specific command-line interface. Do not use *CLI* as a generic substitute when the actual tool name is available.

Name a specific page, console, or web interface. Do not use *UI* as a generic location.

Write `curl` for the command and curl for the project. Do not write *cURL*.

Use SSH for the protocol and `ssh` for the utility. Do not use either form as a verb.

Use *a SQL* because the standard pronunciation begins with a consonant sound.

Use *media type* in general. Use *content type* when the `Content-Type` header or another specific context requires it.

Use lowercase *boolean* for the abstract type. Preserve the exact spelling of a programming language's Boolean type or literal.

## Plain alternatives to jargon

First, decide whether the intended readers know and search for the term. Then use this sequence:

1. Replace unnecessary jargon with a direct description.
2. Use a more precise term when one exists.
3. Define necessary jargon at first use or link to an authoritative definition.
4. Use one term consistently after its introduction.

Apply these common replacements:

- Use *see*, *edit*, *find*, *use*, or *view* instead of vague *access*.
- Use *useful* or *that you can act on* instead of *actionable*.
- Use *platform-independent* or another exact property instead of *agnostic*.
- Describe the error or harmful practice instead of calling it an *anti-pattern*.
- Describe the actual behavior before using *best effort*.
- Use *configuration* outside exact code instead of *config*.
- Use *run* instead of *execute* when both mean the same action.
- Use *affect* as a verb. Use *impact* only as a noun.
- Use *import*, *load*, or *copy* for simple data movement. Reserve *ingest* for movement with significant processing.
- Use *use*, *build on*, or *take advantage of* instead of *leverage*.
- Use *built-in* or another exact property instead of ambiguous *native*.
- State the measured quality instead of calling something *performant*.
- Use *repository* instead of *repo*.
- State direction or magnitude with *scale*.
- Use *create* or *start* instead of *spin up*.
- Name the app, service, resources, data, infrastructure, or components instead of vague *workload*.

Define necessary terms such as *canary*, *cold standby*, *hot failover*, and *warm spare* at first use.

Avoid filler and reader judgments. Remove *just*, *easy*, *simple*, *quick*, and related adverbs unless they convey necessary facts.

## Inclusive and precise alternatives

Do not replace a sensitive term mechanically. Choose a term that states the real technical relationship.

Use these patterns where they fit:

- Replace *blacklist*, *whitelist*, and *graylist* with precise nouns such as *denylist*, *allowlist*, or *provisional list*.
- Do not use *allowlist* or *denylist* as verbs. Describe the actual action.
- Replace *master/slave* with a contextual pair such as *primary/replica*, *controller/worker*, or *leader/follower*.
- Replace *black-box testing* with *opaque-box testing* and *white-box testing* with *clear-box testing*.
- Describe mixed testing directly. Use *translucent-box testing* only after a definition.
- Replace *black-box monitoring* with *synthetic monitoring* and *white-box monitoring* with *introspective monitoring*.
- Replace *blast radius* with *affected area* or *spatial impact*.
- Replace *break-glass* with *emergency access*, *manual fallback*, or *preplanned procedure*.
- Replace *demilitarized zone* with *perimeter network* when that term is accurate.
- Replace *sanity check* with *confidence check*, *preliminary check*, or *coherence check*.
- Replace figurative *blind* with *ignore*, *unaware of*, or an exact operation.
- Replace *grandfathered* with *exempt* or explain the date-based exception.
- Replace *man-hours* with *person-hours*, *manned* with *staffed*, and *manpower* with *staff* or *workforce*.
- Replace *man-in-the-middle* with *on-path attacker* or *person-in-the-middle* when the domain permits it.
- Replace *female adapter* and *male adapter* with exact connector terms such as *socket* and *plug*.
- Replace *war room* with *incident-management team*, *situation room*, or another exact function.
- Replace *tribal knowledge* with *undocumented team knowledge* or another literal description.
- Replace *guys* with *everyone* or another non-gendered address.
- Replace role metaphors such as *guru*, *ninja*, and *sherpa* with *expert*, *teacher*, or *guide*.
- Replace *brown bag* with *learning session* or *informal training*.

Do not use disability, mental-health, body, ethnicity, religion, violence, or sexuality as a metaphor for technical quality.

Terms that require a precise rewrite include *crazy*, *cripple*, *fat*, *ghetto*, *lame*, *retarded*, *sexy*, *voodoo*, and similar labels.

Describe a person with the terms that the relevant community prefers. Do not use *visually challenged* or describe a person without disabilities as *normal*.

Use *person who is blind*, *screen reader user*, *person with low vision*, or another accurate community term when relevant.

Use *stop*, *exit*, *cancel*, or *end* instead of *abort*, *kill*, or *terminate* in general prose.

Preserve exact Linux signal terminology and other required technical literals. Explain their meaning without extending the literal into ordinary prose.

# goosemarklint

goosemarklint is an opinionated Markdown linter and formatter, written in Goose, that checks Markdown for ASD-STE100 and for the marks of LLM text.

The parser reads CommonMark, GitHub Flavored Markdown, YAML front matter and GitHub alerts.

## Run

Build the tool with the Goose compiler, then check the Markdown files of a repo.
`fmt --check` fails when `fmt` would change a file:

```sh
goose build src/main.goose -o goosemarklint
./goosemarklint check .
./goosemarklint fmt --check .
```

`check` takes files and folders.
In a folder, it reads each `.md` file and skips `node_modules` and each folder whose name starts with a dot.
Each finding is one line: `file:line:col: rule: message`.
A warning has the word `warning:` before its message.
The exit status is 0 for no finding or only warnings, and 1 for an error.
It is 2 for a file or a config that the tool cannot read.

`./goosemarklint rules` prints the rule IDs.
`./goosemarklint --version` prints the version.
`./goosemarklint tree FILE` prints the parse tree of a file.

## Format

`./goosemarklint fmt .` writes each Markdown file again in one layout:

- Each sentence of a paragraph goes on its own line.
  A sentence ends at `.`, `!` or `?` before a space and a capital letter or a digit.
  The line does not break after a word from the `abbreviation` list, or in a code span, a URL or inline HTML.
- One blank line goes between two blocks, except in a tight list.
- Headings start with `#`.
  Bullets use `-`, with an indent of 2 spaces for each level.
  The numbers of an ordered list count up from the first number.
- Code fences use backticks.
  Each table pipe has 1 space on each side.
- Front matter, code, HTML blocks and link reference definitions do not change.
- A paragraph after a suppression directive keeps its lines, so the directive stays on the line before its target.
- A paragraph in a raw HTML `<pre>` element keeps its lines, because the browser shows each line break of a `pre` element.

`fmt` parses its output again and compares the two parse trees.
The comparison ignores soft line breaks.
When the trees differ, `fmt` does not write the file, and the exit status is 2.
`./goosemarklint fmt --check .` writes nothing.
It prints each file that `fmt` would change, and then its exit status is 1.

## Rules

The STE, LLM and file rules check prose only.
They skip code blocks, code spans, front matter, URLs and raw HTML.
The rules for `SKILL.md`, `AGENTS.md`, `CLAUDE.md` and `README.md` apply by file name.
Each other Markdown file, such as a blog post, gets all of the other rules.

| Rule | Finds |
| --- | --- |
| `ste-word` | A word or a phrase from a `ban` list, with the STE word to use. It skips a word with a capital letter after the start of a sentence, because that word is part of a name or a title. |
| `ste-sentence-length` | A sentence of more than 25 words, or an instruction of more than 20 words. An instruction starts with a verb, or has a verb after its first comma. |
| `ste-contraction` | A contraction, such as `don't`. |
| `ste-semicolon` | A semicolon. |
| `ste-ing` | A warning for an -ing verb form. This is a word that ends in -ing and is not in an `allow` list. It comes after a form of "be" or after a word such as `without`, `of`, `for` or `to`. It also comes after a verb such as `prefer`, `avoid` or `stop`, which takes an -ing object. One adverb can come between them. It also comes after `and` or `or` when the sentence has a found -ing word before it. It skips a word with a capital letter that does not start a sentence. Thus the rule skips most nouns, adjectives, titles and names. |
| `ste-passive` | A form of "be" and then a past participle, such as `is used`. |
| `llm-stock` | A stock word or a stock phrase of LLM text, such as `delve` or `seamless`. It skips a name or a title, as `ste-word` does. |
| `llm-hedge` | A hedge or a filler word, such as `basically` or `very`. |
| `llm-em-dash` | An em dash. It skips a table cell that holds only an em dash, because that dash is a placeholder. |
| `llm-contrast` | The forms `not just X, but Y` and `it is not X, it is Y`. |
| `llm-rule-of-three` | A list of 3 adjectives, such as `fast, simple and safe`. |
| `llm-heading-emoji` | An emoji in a heading. |
| `llm-bold-label` | A list of 3 or more items where each item starts with bold text. |
| `llm-heavy-bold` | A paragraph with 3 or more bold spans. |
| `llm-summary-heading` | A summary heading, such as "Summary" or "Conclusion", as the last heading. |
| `html-comment` | An HTML comment. Only the suppression directive and a marker can stay. A marker has one lowercase word immediately after `<!--`, such as `<!--curve NAME-->`, so that a script can find it. The word can start with `/`, such as `<!--/hand-check-->`. Each argument after this word has a character that is not a lowercase letter. A marker has no colon and no sentence punctuation. Thus `<!--todo fix this-->` is not a marker. |
| `suppression` | A directive with no reason, with an unknown rule or `repeated-fact`, or with no finding on the next line. |
| `skill-front-matter` | In `SKILL.md`: front matter with no `name`, no `description`, or a description without the word "when". |
| `agents-imperative` | In `AGENTS.md` and `CLAUDE.md`: a list item that gives an instruction with "must", "should" or "shall" and does not start with the verb. A fact or a list of files passes. |
| `readme-purpose` | In `README.md`: a first paragraph that is not 1 sentence. The tool skips the title, HTML and badge images before it. |
| `readme-run-block` | In `README.md`: no fenced code block. |
| `repeated-fact` | A warning. The same sentence or list in 2 places, or the same commit hash or version string in 2 files, in one run. |

`repeated-fact` reads all files of one run together, so run `check` on the whole repo.
It skips each file under a `generated` path of the config, because a script copies text into these files.
It also skips each file under a `pass` folder that has a sibling `fail` folder, because a pass fixture can repeat a fail fixture.
It folds case, white space and punctuation, and it skips sentences of fewer than 8 words, sentences with code, headings and table cells.
A pinned value is a commit hash of 7 to 40 hex characters or a version such as `1.4.2` or `v1.4.2`, outside front matter.
A short hash and a longer hash that starts with it are one pinned value.
A list is 3 or more items with commas, "and" or "or" between them, or a Markdown list.
An inline list ends at the first "and" or "or" after a comma.
The rule reads lists in paragraphs, in list items and in the `description` of front matter.
It folds case, punctuation and code marks in each item, and it compares the items as a set.
In a sentence, the words before the first item and after the last item can be part of these items.
Thus for a list that is not in parentheses or after a colon, the rule compares only the interior items.
A list of 5 or more items matches a list that has at most 1 different item and at most 1 more or fewer items.
If a list has 1 more item, the rule can also skip its second or second-last item as part of the sentence.
The warning then names the items that differ, so that you can see the drift.
A list of fewer than 5 items must have the same set of items.
A list that is in a repeated sentence gets only the warning for the sentence.
The warning names each `file:line`, so you can keep one owner and point to it from the other places.
A suppression directive cannot stop this warning.

`data/ste.tsv` and `data/llm.tsv` hold the word lists.
Each line has a category, a tab and a word or a phrase.
A `ban`, `contraction` or `stock` line can then have a tab and the replacement.
The other categories are `allow`, `be`, `adverb`, `participle`, `verb`, `abbreviation`, `hedge`, `summary`, `adjective` and `suffix`.

## markdownlint rules

The `MD` rules have the IDs and the default settings of markdownlint 0.42.0.
They check the Markdown syntax, so they also read the lines that the prose rules skip, as markdownlint does.

| Rule | Finds |
| --- | --- |
| `MD001` | A heading level that goes up by more than 1. |
| `MD003` | A heading style (ATX, closed ATX or setext) that is not the style of the first heading. |
| `MD004` | A list marker (`-`, `*` or `+`) that is not the marker of the first list. |
| `MD005` | List items at one level with different indents. |
| `MD007` | A bulleted list with an indent that is not 2 spaces for each level. |
| `MD009` | Spaces at the end of a line, other than the 2 spaces of a line break. |
| `MD010` | A hard tab. |
| `MD011` | A link in the reversed form `(text)[url]`. |
| `MD012` | More than 1 blank line in a row. |
| `MD014` | A code block where each line starts with `$` and no line shows output. |
| `MD018` | No space after the `#` of a heading. |
| `MD019` | More than 1 space after the `#` of a heading. |
| `MD020` | No space inside the `#` marks of a closed heading. |
| `MD021` | More than 1 space inside the `#` marks of a closed heading. |
| `MD022` | A heading with no blank line above or below it. |
| `MD023` | A heading with an indent. |
| `MD024` | Two headings with the same text. |
| `MD025` | More than 1 level 1 heading, or a level 1 heading and a `title` in the front matter. |
| `MD026` | A heading that ends with `.`, `,`, `;`, `:` or `!`. |
| `MD027` | More than 1 space after the `>` of a block quote. |
| `MD028` | A blank line between two block quotes. |
| `MD029` | An ordered list with numbers that are not all 1 and do not count up by 1. |
| `MD030` | More than 1 space after a list marker. |
| `MD031` | A fenced code block with no blank line above or below it. |
| `MD032` | A list with no blank line above or below it. |
| `MD033` | An HTML element. |
| `MD034` | A bare URL. |
| `MD035` | A thematic break that is not in the style of the first one. |
| `MD036` | A paragraph of only bold or italic text, in the place of a heading. |
| `MD037` | A space inside an emphasis marker, such as `* text *`. A marker after a letter or a digit, such as the star of `E* = E / 2`, does not open emphasis. |
| `MD038` | A space inside a code span. |
| `MD039` | A space inside the text of a link. |
| `MD040` | A fenced code block with no language. |
| `MD041` | A first line that is not a level 1 heading. A `title` in the front matter is also a title. |
| `MD042` | A link with no URL, or with only `#`. |
| `MD045` | An image with no alternative text. |
| `MD046` | A code block style (fenced or indented) that is not the style of the first code block. |
| `MD047` | A file that does not end with a newline. |
| `MD048` | A code fence (backtick or tilde) that is not the fence of the first code block. |
| `MD049` | An emphasis marker (`*` or `_`) that is not the marker of the first emphasis. |
| `MD050` | A strong marker (`**` or `__`) that is not the marker of the first strong text. |
| `MD051` | A link to a `#` fragment with no heading or HTML anchor of that name. |
| `MD052` | A reference link with a label that has no definition. |
| `MD053` | A reference definition that no link uses. |
| `MD055` | A table row that does not start and end with a pipe as the first row does. |
| `MD056` | A table row with more or fewer cells than the header. |
| `MD058` | A table with no blank line above or below it. |
| `MD059` | A link text that does not tell where the link goes, such as "here" or "more". |
| `MD060` | A table with pipes that do not line up, and that is not in the compact or the tight style. The rule does not check the delimiter row, so `\|---\|` is correct in each style. |

The tool does not have these markdownlint rules:

- `MD013`, the line length: a decision of the tool is one sentence on each line, so a long sentence makes a long line.
- `MD043`, `MD044` and `MD054`: with the default settings of markdownlint, they find nothing.

## Suppression

To stop a finding, put this directive on the line before it:

```markdown
<!-- goosemarklint-disable-next-line ste-ing: the name of a product -->
```

The directive names one or more rule IDs, then a colon and a reason.
The reason is necessary.

## Config

A `.goosemarklint` file in the current folder adds words to the lists.
Each line is one of these:

- `allow`, a tab and a word.
- `ban`, a tab, a word or a phrase, a tab and the replacement.
- `generated`, a tab and a path from the current folder.
- `exclude`, a tab and a path from the current folder.
- `disable`, a tab and a rule ID.

This command makes a config with 1 line of 4 types:

```sh
printf 'allow\tHugging\nban\twhitelist\tallow-list\ngenerated\tvalidation/reports/\nexclude\tvendor/\ndisable\tste-ing\n' > .goosemarklint
```

An `allow` word passes each word rule.
A `ban` word gives a `ste-word` finding.
`repeated-fact` skips each file whose path is a `generated` path or is in a `generated` folder.
`check` and `fmt` skip each file under an `exclude` path.
`fmt` also skips each file under a `generated` path.
Thus a vendored file or a test fixture gets no finding.
A `disable` rule gives no finding in the project, and an unknown rule ID is a config error.

## Checks

Run all checks: the spec tests, the rule tests, the saved lint and `fmt` output, and the parse tree replay:

```sh
scripts/check.sh
```

Each rule has a `pass` folder and a `fail` folder in `test/rules`.
`test/rules.expect` and `test/corpus.expect` hold the lint output of the rule tests and of the real Markdown files in `test/corpus`.
`test/fmt.expect` holds the `fmt` output of `test/corpus` and `test/fmt`.
The spec tests also format each spec example two times.
The parse tree must stay the same, and the second `fmt` must change nothing.
When a change must change an output, read the diff, then accept it:

```sh
scripts/check.sh --accept
```

## Sources

`data/sources.tsv` gives the source, version, licence and hash of each vendored file.

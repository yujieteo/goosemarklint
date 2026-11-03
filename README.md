# goosemarklint

goosemarklint is an opinionated Markdown linter and formatter, written in Goose, that checks Markdown for ASD-STE100 and common style rules.

The parser for CommonMark and GitHub Flavored Markdown is done.
It also reads YAML front matter and GitHub alerts.
The `check` and `fmt` commands and the profiles for README.md, SKILL.md, AGENTS.md and CLAUDE.md come in later steps.

## Run

Build the tool with the Goose compiler, then print the parse tree of a Markdown file:

```sh
goose build src/main.goose -o goosemarklint
./goosemarklint tree README.md
```

Run all checks, which include the CommonMark and GFM spec tests and the output replay:

```sh
scripts/check.sh
```

When a change must change the parse tree, read the replay diff, then accept it:

```sh
scripts/check.sh --accept
```

## Sources

`data/sources.tsv` gives the source, version, licence and hash of each vendored file.

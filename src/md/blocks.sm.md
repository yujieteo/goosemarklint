# Block parser: the open leaf block of a container

Source: src/md/blocks.goose and src/md/block_start.goose on the branch fm/goosemarklint-parser.
The state is the kind of the open leaf block at the tip of one container. The code keeps it in `d.nodes[b.tip].kind`, `html_type` and `fenced`.
Each event is one line of the container. `start` means that `try_starts` found a block start on the line. `text` is each other non-blank line.
The lines that continue an enclosing block quote or list item, and lazy paragraph lines, are not in this machine.

## Requirements

- R1: A sequence of non-blank lines that no other block takes is a paragraph. A blank line ends it. — test/spec/commonmark-0.31.2.txt:3516
- R2: Blank lines between blocks are ignored. — test/spec/commonmark-0.31.2.txt:3624
- R3: A fenced code block holds each line up to a closing fence, or to the end of the containing block. A fence can interrupt a paragraph. — test/spec/commonmark-0.31.2.txt:1959
- R4: An indented code block holds indented chunks separated by blank lines. It cannot interrupt a paragraph. — test/spec/commonmark-0.31.2.txt:1737
- R5: An HTML block ends at the first line that meets the end condition of its type. Types 6 and 7 end at a blank line. — test/spec/commonmark-0.31.2.txt:2366
- R6: An HTML block of types 1 to 6 can interrupt a paragraph. Type 7 cannot. — test/spec/commonmark-0.31.2.txt:2992
- R7: A setext underline after a paragraph makes the paragraph a heading. — test/spec/commonmark-0.31.2.txt:1318
- R8: Block quotes, list items, ATX headings and thematic breaks can interrupt a paragraph. — test/spec/commonmark-0.31.2.txt:1034
- R9: A header row and a delimiter row start a table. A blank line or the start of another block ends it. — test/spec/gfm-0.29.txt:3397
- R10: The end of the document closes each open block. — test/spec/commonmark-0.31.2.txt:2068
- R11: A line in a code block or an HTML block is content. It starts no block. — test/spec/commonmark-0.31.2.txt:1959

## Machine leaf

initial: container
final: done

| state | event | guard | next | req | source |
|---|---|---|---|---|---|
| container | blank | | - | R2 | src/md/blocks.goose:139 |
| container | text | | paragraph | R1 | src/md/blocks.goose:140 |
| container | start | fence | fenced_code | R3 | src/md/block_start.goose:65 |
| container | start | indent | indented_code | R4 | src/md/block_start.goose:198 |
| container | start | html 1 to 5 | html_until_end | R5 | src/md/block_start.goose:82 |
| container | start | html 6 or 7 | html_until_blank | R5 | src/md/block_start.goose:82 |
| container | start | else | container | R8 | src/md/block_start.goose:244 |
| paragraph | blank | | container | R1 | src/md/blocks.goose:76 |
| paragraph | text | | paragraph | R1 R4 R6 | src/md/blocks.goose:126 |
| paragraph | start | underline | container | R7 | src/md/block_start.goose:103 |
| paragraph | start | delimiter row | table | R9 | src/md/table.goose:138 |
| paragraph | start | fence | fenced_code | R3 | src/md/block_start.goose:65 |
| paragraph | start | html 1 to 5 | html_until_end | R6 | src/md/block_start.goose:87 |
| paragraph | start | html 6 | html_until_blank | R6 | src/md/block_start.goose:87 |
| paragraph | start | else | container | R8 | src/md/block_start.goose:244 |
| fenced_code | text | closing fence | container | R3 | src/md/blocks.goose:35 |
| fenced_code | text | else | fenced_code | R3 | src/md/blocks.goose:41 |
| fenced_code | blank | | fenced_code | R3 | src/md/blocks.goose:41 |
| indented_code | text | indent | indented_code | R4 | src/md/blocks.goose:23 |
| indented_code | text | else | container | R4 | src/md/blocks.goose:28 |
| indented_code | blank | | indented_code | R4 | src/md/blocks.goose:25 |
| html_until_end | text | end condition | container | R5 | src/md/blocks.goose:135 |
| html_until_end | text | else | html_until_end | R5 | src/md/blocks.goose:133 |
| html_until_end | blank | | html_until_end | R5 | src/md/blocks.goose:75 |
| html_until_blank | text | | html_until_blank | R5 | src/md/blocks.goose:133 |
| html_until_blank | blank | | container | R5 | src/md/blocks.goose:75 |
| table | text | row | table | R9 | src/md/table.goose:167 |
| table | text | else | container | R9 | src/md/blocks.goose:77 |
| table | blank | | container | R9 | src/md/table.goose:162 |
| table | start | fence | fenced_code | R9 R3 | src/md/block_start.goose:65 |
| table | start | indent | indented_code | R9 R4 | src/md/block_start.goose:198 |
| table | start | html 1 to 5 | html_until_end | R9 R5 | src/md/block_start.goose:82 |
| table | start | html 6 or 7 | html_until_blank | R9 R5 | src/md/block_start.goose:82 |
| table | start | else | container | R9 | src/md/block_start.goose:244 |
| * | start | | - | R11 | src/md/blocks.goose:105 |
| * | eof | | done | R10 | src/md/blocks.goose:189 |

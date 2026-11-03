# Block parser: the open leaf block of a container

Source: src/md/blocks.goose, src/md/block_start.goose and src/md/table.goose. The source column names the Goose function.
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
| container | blank | | - | R2 | add_text_line |
| container | text | | paragraph | R1 | add_text_line |
| container | start | fence | fenced_code | R3 | try_fence |
| container | start | indent | indented_code | R4 | try_indented_code |
| container | start | html 1 to 5 | html_until_end | R5 | try_html |
| container | start | html 6 or 7 | html_until_blank | R5 | try_html |
| container | start | else | container | R8 | try_starts |
| paragraph | blank | | container | R1 | continue_block |
| paragraph | text | | paragraph | R1 R4 R6 | add_text_line |
| paragraph | start | underline | container | R7 | try_setext |
| paragraph | start | delimiter row | table | R9 | try_table_header |
| paragraph | start | fence | fenced_code | R3 | try_fence |
| paragraph | start | html 1 to 5 | html_until_end | R6 | try_html |
| paragraph | start | html 6 | html_until_blank | R6 | try_html |
| paragraph | start | else | container | R8 | try_starts |
| fenced_code | text | closing fence | container | R3 | continue_code |
| fenced_code | text | else | fenced_code | R3 | continue_code |
| fenced_code | blank | | fenced_code | R3 | continue_code |
| indented_code | text | indent | indented_code | R4 | continue_code |
| indented_code | text | else | container | R4 | continue_code |
| indented_code | blank | | indented_code | R4 | continue_code |
| html_until_end | text | end condition | container | R5 | add_text_line |
| html_until_end | text | else | html_until_end | R5 | add_text_line |
| html_until_end | blank | | html_until_end | R5 | continue_block |
| html_until_blank | text | | html_until_blank | R5 | add_text_line |
| html_until_blank | blank | | container | R5 | continue_block |
| table | text | row | table | R9 | try_table_row |
| table | text | else | container | R9 | continue_block |
| table | blank | | container | R9 | row_continues |
| table | start | fence | fenced_code | R9 R3 | try_fence |
| table | start | indent | indented_code | R9 R4 | try_indented_code |
| table | start | html 1 to 5 | html_until_end | R9 R5 | try_html |
| table | start | html 6 or 7 | html_until_blank | R9 R5 | try_html |
| table | start | else | container | R9 | try_starts |
| * | start | | - | R11 | open_new_blocks |
| * | eof | | done | R10 | parse_lines |

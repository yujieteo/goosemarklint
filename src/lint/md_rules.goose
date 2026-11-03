import std;
import lint.context;
import lint.prose;
import lint.md_base;
import lint.md_lines;
import lint.md_headings;
import lint.md_lists;
import lint.md_blocks;
import lint.md_spans;
import lint.md_tables;

fn check_markdown(L: Lint&, p: Prose&) {
    check_lines(L);
    check_headings(L, p);
    check_lists(L);
    check_blocks(L);
    check_inlines(L, p);
    check_tables(L);
}

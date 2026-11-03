import std;
import md.node;
import lint.context;
import lint.md_base;
import lint.md_lists;

struct BlockStyles { code: i64 = -1, fence: u8 = 0, rule: i64 = -1 }

fn is_dollar_line(t: const u8[:]) -> bool {
    let s = trim_start(t);
    return s.len >= 2 && s[0] == '$' && (s[1] == ' ' || s[1] == '\t');
}

fn check_dollar_commands(L: Lint&, n: i64) {
    let node = L.d.nodes[n];
    let first = if node.fenced { node.line + 1 } else { node.line };
    let lines = split(text_of(L.d, node.content), '\n');
    let values = count(lines) { trim(it).len > 0 };
    let dollars = count(lines) { trim(it).len > 0 && is_dollar_line(it) };
    guard values > 0 && values == dollars;
    for t, i in lines {
        guard trim(t).len > 0 && first + i <= last_line(L);
        let src = line_text(L, first + i);
        report(L, L.lines[first + i] + max(position(src, '$'), 0), "MD014", "\"$\" before a command that shows no output: delete the \"$\"");
    }
}

fn check_fence_blanks(L: Lint&, n: i64) {
    let node = L.d.nodes[n];
    if !blank_at(L, node.line - 1) { report_line(L, node.line, "MD031", "fenced code block has no blank line above it: add one"); }
    if !blank_at(L, node.end_line + 1) && !blank_at(L, node.end_line) {
        report_line(L, node.end_line, "MD031", "fenced code block has no blank line below it: add one");
    }
}

fn check_code_block(L: Lint&, n: i64, st: BlockStyles&) {
    let node = L.d.nodes[n];
    check_dollar_commands(L, n);
    let style = if node.fenced { 1 } else { 0 };
    if st.code < 0 { st.code = style; }
    if style != st.code {
        report_line(L, node.line, "MD046", str("code block style ", if node.fenced { "fenced" } else { "indented" }, ": use ", if st.code == 1 { "fenced" } else { "indented" }, ", as the first code block"));
    }
    guard node.fenced;
    check_fence_blanks(L, n);
    if trim(text_of(L.d, node.info)).len == 0 { report_line(L, node.line, "MD040", "fenced code block has no language: add one after the fence"); }
    if st.fence == 0 { st.fence = node.fence_char; }
    if node.fence_char != st.fence { report_line(L, node.line, "MD048", str("code fence \"", [node.fence_char], "\": use \"", [st.fence], "\", as the first code fence")); }
}

fn rule_text(L: Lint&, n: i64) -> const u8[:] { trim(line_text(L, L.d.nodes[n].line)[max(L.d.nodes[n].col, 1) - 1..]) }

fn check_rule_style(L: Lint&, n: i64, st: BlockStyles&) {
    if st.rule < 0 { st.rule = n; }
    let t = rule_text(L, n);
    let want = rule_text(L, st.rule);
    guard t != want;
    report_node(L, n, "MD035", str("thematic break \"", t, "\": use \"", want, "\", as the first one"));
}

fn check_quote_gap(L: Lint&, n: i64) {
    let next = L.d.nodes[n].next;
    guard next >= 0 && (L.d.nodes[next].kind == Kind.BlockQuote || L.d.nodes[next].kind == Kind.Alert);
    for ln in L.d.nodes[n].end_line + 1..L.d.nodes[next].line {
        report_at(L, ln, 1, "MD028", "blank line between two block quotes: delete it, or put text between them");
    }
}

fn in_item_indent(L: Lint&, q: i64, ln: i64, col: i64) -> bool {
    var n = q;
    while n >= 0 {
        let node = L.d.nodes[n];
        if node.kind == Kind.Item && ln > node.line && ln <= node.end_line && col >= node.col + node.list.padding { return true; }
        n = next_in(L.d, n, q);
    }
    return false;
}

fn check_quote_spaces(L: Lint&, q: i64) {
    let node = L.d.nodes[q];
    for ln in node.line..node.end_line + 1 {
        guard is_markdown_line(L, ln);
        let t = line_text(L, ln);
        let at = quote_prefix(t);
        guard at > 0 && at < t.len && (t[at] == ' ' || t[at] == '\t');
        var e = at;
        while e < t.len && (t[e] == ' ' || t[e] == '\t') { e++; }
        guard e < t.len && !in_item_indent(L, q, ln, e + 1);
        report(L, L.lines[ln] + at, "MD027", "more than 1 space after the block quote marker: use 1 space");
    }
}

fn check_table_blanks(L: Lint&, n: i64) {
    let node = L.d.nodes[n];
    if !blank_at(L, node.line - 1) { report_line(L, node.line, "MD058", "table has no blank line above it: add one"); }
    if !blank_at(L, node.end_line + 1) { report_line(L, node.end_line, "MD058", "table has no blank line below it: add one"); }
}

fn check_blocks(L: Lint&) {
    var st = BlockStyles {};
    var n = 0;
    while n >= 0 {
        let k = L.d.nodes[n].kind;
        match k {
            CodeBlock => check_code_block(L, n, st),
            ThematicBreak => check_rule_style(L, n, st),
            Table => check_table_blanks(L, n),
            BlockQuote, Alert => {
                check_quote_gap(L, n);
                if !in_quote(L, n) { check_quote_spaces(L, n); }
            },
            _ => {},
        }
        n = next_in(L.d, n, 0);
    }
}

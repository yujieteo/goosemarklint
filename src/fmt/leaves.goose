import std;
import md.node;
import md.table;
import lint.suppress;
import fmt.emit;
import fmt.flow;

let DELIMITERS = ["---", ":---", "---:", ":---:"];

fn longest_run(s: const u8[:], c: u8) -> i64 {
    var best = 0;
    var run = 0;
    for x in s {
        run = if x == c { run + 1 } else { 0 };
        best = max(best, run);
    }
    return best;
}

fn put_fenced(f: Fmt&, n: i64) {
    let info = text_of(f.d, f.d.nodes[n].title);
    let content = text_of(f.d, f.d.nodes[n].content);
    let ch: u8 = if position(info, '`') >= 0 { '~' } else { '`' };
    let len = max(3, longest_run(content, ch) + 1);
    var fence: u8[>..] = [];
    push_n(fence, ch, len);
    put_line(f, str(fence, info));
    put_lines(f, content);
    put_line(f, fence);
}

fn put_indented(f: Fmt&, n: i64) {
    let content = text_of(f.d, f.d.nodes[n].content);
    var at = 0;
    while at < content.len {
        let nl = position(content[at..], '\n');
        let end = if nl < 0 { content.len } else { at + nl };
        let line: u8[>..] = if end > at { str("    ", content[at..end]) } else { "" };
        put_line(f, line);
        at = end + 1;
    }
}

fn put_front_matter(f: Fmt&, n: i64) { for ln in 1..f.d.nodes[n].end_line + 1 { put_line(f, source_line(f, ln)); } }

fn delimiter_of(a: u8) -> const u8[:] {
    match a {
        'l' => DELIMITERS[1],
        'r' => DELIMITERS[2],
        'c' => DELIMITERS[3],
        _ => DELIMITERS[0],
    }
}

fn put_row(f: Fmt&, raw: const u8[:], cols: i64) {
    var cells: Cell[>..] = [];
    var row: u8[>..] = [];
    guard parse_row(raw, cells) >= 0 else {
        put_line(f, raw);
        return;
    }
    for i in cols {
        let cell = if i < cells.len { trim(raw[cells[i].start..cells[i].end]) } else { "" };
        row.append("| ");
        if cell.len > 0 { format(row, cell, " "); }
    }
    row.push('|');
    put_line(f, row);
}

fn put_table(f: Fmt&, n: i64) {
    let aligns = text_of(f.d, f.d.nodes[n].info);
    var row = f.d.nodes[n].first;
    while row >= 0 {
        put_row(f, trim(leaf_line(f, f.d.nodes[row].line)), aligns.len);
        if f.d.nodes[row].header {
            var delims: u8[>..] = [];
            for a in aligns { format(delims, "| ", delimiter_of(a), " "); }
            delims.push('|');
            put_line(f, delims);
        }
        row = f.d.nodes[row].next;
    }
}

fn is_target(f: Fmt&, ln: i64) -> bool { position(f.targets, ln) >= 0 }

fn has_directive(d: Doc&, para: i64) -> bool {
    var n = d.nodes[para].first;
    while n >= 0 {
        if d.nodes[n].kind == Kind.HtmlInline && is_directive(text_of(d, d.nodes[n].content)) { return true; }
        n = d.nodes[n].next;
    }
    return false;
}

fn tag_at(t: const u8[:], i: i64, tag: const u8[:]) -> bool {
    let end = i + tag.len;
    guard end <= t.len && lower_equal(t[i..end], tag) else { return false; }
    return end == t.len || position(" \t\n>", t[end]) >= 0;
}

fn pre_tags(t: const u8[:]) -> i64, i64 {
    var opens = 0;
    var closes = 0;
    for c, i in t {
        guard c == '<';
        if tag_at(t, i, "<pre") { opens++; }
        if tag_at(t, i, "</pre") { closes++; }
    }
    return opens, closes;
}

fn track_pre(f: Fmt&, t: const u8[:]) -> bool {
    let opens, closes = pre_tags(t);
    f.pre = max(f.pre + opens - closes, 0);
    return opens + closes > 0;
}

fn put_raw_paragraph(f: Fmt&, n: i64) {
    var keep = f.pre > 0 || is_target(f, first_line(f.d, n)) || has_directive(f.d, n);
    var k = f.d.nodes[n].first;
    while k >= 0 {
        if f.d.nodes[k].kind == Kind.HtmlInline && track_pre(f, text_of(f.d, f.d.nodes[k].content)) { keep = true; }
        k = f.d.nodes[k].next;
    }
    put_paragraph(f, n, keep);
}

fn after_list(d: Doc&, n: i64) -> bool { d.nodes[n].prev >= 0 && d.nodes[d.nodes[n].prev].kind == Kind.List }

fn first_line(d: Doc&, n: i64) -> i64 {
    guard d.nodes[n].kind == Kind.Paragraph else { return d.nodes[n].line; }
    let c = text_of(d, d.nodes[n].content);
    let tail = if ends_with(c, "\n") { 0 } else { 1 };
    let lines = count(c) { it == '\n' } + tail;
    return max(d.nodes[n].line, d.nodes[n].end_line - lines + 1);
}

fn put_leaf(f: Fmt&, n: i64) {
    let node = f.d.nodes[n];
    match node.kind {
        FrontMatter => put_front_matter(f, n),
        Paragraph => put_raw_paragraph(f, n),
        Heading => put_heading(f, n),
        CodeBlock => if node.fenced || after_list(f.d, n) { put_fenced(f, n); } else { put_indented(f, n); },
        HtmlBlock => {
            put_lines(f, text_of(f.d, node.content));
            track_pre(f, text_of(f.d, node.content));
        },
        Table => put_table(f, n),
        _ => {},
    }
}

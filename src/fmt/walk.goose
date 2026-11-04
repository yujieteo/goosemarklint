import std;
import md.node;
import fmt.emit;
import fmt.leaves;

let ALERT_NAMES = ["note", "tip", "important", "warning", "caution"];

fn is_tight(d: Doc&, parent: i64) -> bool {
    match d.nodes[parent].kind {
        List => d.nodes[parent].list.tight,
        Item => d.nodes[d.nodes[parent].parent].list.tight,
        _ => false,
    }
}

fn put_separator(f: Fmt&, prev: i64, parent: i64, joined: bool) {
    guard !(joined && is_directive_block(f.d, prev)) && !is_tight(f.d, parent);
    put_blank(f);
}

fn def_line(f: Fmt&, ln: i64) -> const u8[:] {
    guard ln < f.d.line_cols.len && f.d.line_cols[ln] > 0 else { return ""; }
    return trim(leaf_line(f, ln));
}

fn has_defs(f: Fmt&, from: i64, to: i64) -> bool {
    for ln in max(from, 1)..to + 1 { if def_line(f, ln).len > 0 { return true; } }
    return false;
}

fn put_defs(f: Fmt&, from: i64, to: i64) {
    for ln in max(from, 1)..to + 1 {
        let t = def_line(f, ln);
        if t.len > 0 { put_line(f, t); }
    }
}

fn put_tail(f: Fmt&, parent: i64, to: i64) -> bool {
    let last = f.d.nodes[parent].last;
    let from = if last >= 0 { f.d.nodes[last].end_line + 1 } else { content_line(f.d, parent) };
    guard has_defs(f, from, to) else { return false; }
    if last >= 0 { put_separator(f, last, parent, def_line(f, from).len > 0); }
    put_defs(f, from, to);
    return true;
}

fn content_line(d: Doc&, n: i64) -> i64 { if d.nodes[n].kind == Kind.Alert { d.nodes[n].line + 1 } else { d.nodes[n].line } }

fn put_before(f: Fmt&, n: i64) {
    let prev = f.d.nodes[n].prev;
    let parent = f.d.nodes[n].parent;
    let from = if prev >= 0 { f.d.nodes[prev].end_line + 1 } else { content_line(f.d, parent) };
    let to = first_line(f.d, n) - 1;
    if prev >= 0 { put_separator(f, prev, parent, from > to || def_line(f, from).len > 0); }
    guard has_defs(f, from, to);
    put_defs(f, from, to);
    put_separator(f, -1, parent, false);
}

fn first_line(d: Doc&, n: i64) -> i64 {
    guard d.nodes[n].kind == Kind.Paragraph else { return d.nodes[n].line; }
    let c = text_of(d, d.nodes[n].content);
    let tail = if ends_with(c, "\n") { 0 } else { 1 };
    let lines = count(c) { it == '\n' } + tail;
    return max(d.nodes[n].line, d.nodes[n].end_line - lines + 1);
}

fn bullet_of(d: Doc&, list: i64) -> u8 {
    var flips = 0;
    var p = d.nodes[list].prev;
    while p >= 0 && d.nodes[p].kind == Kind.List && !d.nodes[p].list.ordered {
        flips++;
        p = d.nodes[p].prev;
    }
    return if flips % 2 == 0 { '-' } else { '*' };
}

fn item_number(d: Doc&, item: i64) -> i64 {
    let list = d.nodes[item].parent;
    let first = d.nodes[list].first;
    let second = d.nodes[first].next;
    let start = d.nodes[list].list.start;
    guard second < 0 || d.nodes[second].list.start != d.nodes[first].list.start else { return start; }
    var index = 0;
    var k = first;
    while k != item {
        index++;
        k = d.nodes[k].next;
    }
    return start + index;
}

fn push_marker(f: Fmt&, item: i64) {
    let list = f.d.nodes[f.d.nodes[item].parent].list;
    var marker: u8[>..] = [];
    if list.ordered {
        format(marker, item_number(f.d, item));
        marker.push(list.delim);
    } else {
        marker.push(bullet_of(f.d, f.d.nodes[item].parent));
    }
    let width = marker.len + 1;
    let task = f.d.nodes[item].task;
    if task > 0 { marker.append(if task == 2 { " [x]" } else { " [ ]" }); }
    push_item(f, marker, width);
}

fn break_text(d: Doc&, n: i64) -> const u8[:] {
    let parent = d.nodes[n].parent;
    let prev = d.nodes[n].prev;
    if prev < 0 && d.nodes[parent].kind == Kind.Item && !d.nodes[d.nodes[parent].parent].list.ordered {
        return if bullet_of(d, d.nodes[parent].parent) == '-' { "***" } else { "---" };
    }
    let after_paragraph = prev >= 0 && d.nodes[prev].kind == Kind.Paragraph && is_tight(d, parent);
    return if after_paragraph { "***" } else { "---" };
}

fn put_alert_line(f: Fmt&, n: i64) {
    var line: u8[>..] = [];
    line.append("[!");
    for c in text_of(f.d, f.d.nodes[n].info) { line.push(if c >= 'a' && c <= 'z' { c - 32 } else { c }); }
    line.push(']');
    put_line(f, line);
}

fn open_container(f: Fmt&, n: i64) -> bool {
    match f.d.nodes[n].kind {
        BlockQuote => push_quote(f),
        Alert => {
            push_quote(f);
            put_alert_line(f, n);
        },
        Item => push_marker(f, n),
        List => {},
        _ => { return false; },
    }
    return true;
}

fn close_container(f: Fmt&, n: i64) {
    let node = f.d.nodes[n];
    let defs = put_tail(f, n, node.end_line);
    if node.last < 0 && !defs && (node.kind == Kind.Item || node.kind == Kind.BlockQuote) { put_line(f, ""); }
    if node.kind != Kind.List { pop_level(f); }
}

fn enter(f: Fmt&, n: i64) -> bool {
    put_before(f, n);
    guard open_container(f, n) else {
        if f.d.nodes[n].kind == Kind.ThematicBreak { put_line(f, break_text(f.d, n)); } else { put_leaf(f, n); }
        return false;
    }
    guard f.d.nodes[n].first >= 0 else {
        close_container(f, n);
        return false;
    }
    return true;
}

fn put_document(f: Fmt&) {
    var n = f.d.nodes[0].first;
    while n >= 0 {
        if enter(f, n) {
            n = f.d.nodes[n].first;
            continue;
        }
        while n != 0 && f.d.nodes[n].next < 0 {
            n = f.d.nodes[n].parent;
            if n != 0 { close_container(f, n); }
        }
        n = if n == 0 { -1 } else { f.d.nodes[n].next };
    }
    put_tail(f, 0, f.starts.len - 1);
}

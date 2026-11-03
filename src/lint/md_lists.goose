import std;
import md.node;
import md.chars;
import lint.context;
import lint.md_base;

let LIST_INDENT = 2;

fn marker_at(L: Lint&, item: i64) -> const u8[:] {
    let node = L.d.nodes[item];
    let t = line_text(L, node.line)[max(node.col, 1) - 1..];
    var n = 0;
    while n < t.len && is_digit(t[n]) { n++; }
    return t[..min(n + 1, t.len)];
}

fn check_bullets(L: Lint&, list: i64, want: u8&) {
    var item = L.d.nodes[list].first;
    while item >= 0 {
        let m = marker_at(L, item);
        if want == 0 { want = m[0]; }
        if m[0] != want { report_node(L, item, "MD004", str("list marker \"", m, "\": use \"", [want], "\", as the first list")); }
        item = L.d.nodes[item].next;
    }
}

fn check_indent(L: Lint&, list: i64) {
    let want = L.d.nodes[list].col;
    var want_end = 0;
    var by_end = false;
    var item = L.d.nodes[list].first;
    while item >= 0 {
        let col = L.d.nodes[item].col;
        if !L.d.nodes[list].list.ordered {
            if col != want { report_node(L, item, "MD005", str("list item indent ", col - 1, ": use ", want - 1, ", as the other items")); }
        } else {
            let end = col + marker_at(L, item).len - 1;
            if want_end == 0 { want_end = end; }
            if col != want || by_end {
                if end == want_end { by_end = true; } else { report_node(L, item, "MD005", "list item indent is not the same as the other items: align the markers"); }
            }
        }
        item = L.d.nodes[item].next;
    }
}

fn unordered_depth(L: Lint&, list: i64) -> i64 {
    var depth = 0;
    var n = L.d.nodes[list].parent;
    while n >= 0 {
        if L.d.nodes[n].kind == Kind.List {
            guard !L.d.nodes[n].list.ordered else { return -1; }
            depth++;
        }
        n = L.d.nodes[n].parent;
    }
    return depth;
}

fn in_quote(L: Lint&, n: i64) -> bool {
    var k = L.d.nodes[n].parent;
    while k >= 0 {
        if L.d.nodes[k].kind == Kind.BlockQuote || L.d.nodes[k].kind == Kind.Alert { return true; }
        k = L.d.nodes[k].parent;
    }
    return false;
}

fn quote_prefix(t: const u8[:]) -> i64 {
    var i = 0;
    var end = 0;
    loop {
        var j = i;
        while j < t.len && t[j] == ' ' { j++; }
        guard j < t.len && t[j] == '>' else { return end; }
        j++;
        if j < t.len && t[j] == ' ' { j++; }
        end = j;
        i = j;
    }
}

fn check_ul_indent(L: Lint&, list: i64) {
    let depth = unordered_depth(L, list);
    guard depth >= 0 && !L.d.nodes[list].list.ordered;
    let quoted = in_quote(L, list);
    var item = L.d.nodes[list].first;
    while item >= 0 {
        let node = L.d.nodes[item];
        let shift = if quoted { quote_prefix(line_text(L, node.line)) } else { 0 };
        let actual = node.col - 1 - shift;
        if actual != depth * LIST_INDENT { report_node(L, item, "MD007", str("list indent ", actual, ": use ", depth * LIST_INDENT)); }
        item = node.next;
    }
}

fn item_number(m: const u8[:]) -> i64 {
    var v = 0;
    for c in m[..m.len - 1] { v = v * 10 + (c - '0'); }
    return v;
}

fn check_ol_prefix(L: Lint&, list: i64) {
    let first = L.d.nodes[list].first;
    guard first >= 0;
    let second = L.d.nodes[first].next;
    let a = item_number(marker_at(L, first));
    let counting = second >= 0 && (item_number(marker_at(L, second)) != 1 || a == 0);
    var want = if counting && a == 0 { 0 } else { 1 };
    var item = first;
    while item >= 0 {
        let v = item_number(marker_at(L, item));
        if v != want { report_node(L, item, "MD029", str("list number ", v, ": use ", want, if counting { ", and count up by 1" } else { " for each item" })); }
        if counting { want++; }
        item = L.d.nodes[item].next;
    }
}

fn check_marker_space(L: Lint&, list: i64) {
    var item = L.d.nodes[list].first;
    while item >= 0 {
        let node = L.d.nodes[item];
        let t = line_text(L, node.line)[max(node.col, 1) - 1..];
        let m = if node.list.ordered || L.d.nodes[list].list.ordered { marker_at(L, item).len } else { 1 };
        var n = 0;
        while m + n < t.len && t[m + n] == ' ' { n++; }
        if n > 1 && n < 5 && m + n < t.len { report(L, node_offset(L, item) + m, "MD030", str(n, " spaces after the list marker: use 1")); }
        item = node.next;
    }
}

fn check_list_blanks(L: Lint&, list: i64) {
    let node = L.d.nodes[list];
    if !blank_at(L, node.line - 1) { report_node(L, list, "MD032", "list has no blank line above it: add one"); }
    if !blank_at(L, node.end_line + 1) { report_line(L, node.end_line, "MD032", "list has no blank line below it: add one"); }
}

fn has_list_parent(L: Lint&, n: i64) -> bool {
    var k = L.d.nodes[n].parent;
    while k >= 0 {
        if L.d.nodes[k].kind == Kind.List { return true; }
        k = L.d.nodes[k].parent;
    }
    return false;
}

fn check_lists(L: Lint&) {
    var bullet: u8 = 0;
    var n = 0;
    while n >= 0 {
        if L.d.nodes[n].kind == Kind.List {
            if L.d.nodes[n].list.ordered { check_ol_prefix(L, n); } else { check_bullets(L, n, bullet); }
            check_indent(L, n);
            check_ul_indent(L, n);
            check_marker_space(L, n);
            if !has_list_parent(L, n) { check_list_blanks(L, n); }
        }
        n = next_in(L.d, n, 0);
    }
}

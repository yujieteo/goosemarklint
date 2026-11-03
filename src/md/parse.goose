import std;
import md.node;
import md.chars;
import md.html_scan;
import md.line;
import md.blocks;
import md.reference;
import md.inl_state;
import md.inline;
import md.email;

let ALERT_TYPES = ["note", "tip", "important", "warning", "caution"];

fn next_in_order(d: Doc&, n: i64, root: i64) -> i64 {
    if d.nodes[n].first >= 0 { return d.nodes[n].first; }
    var k = n;
    while k != root {
        if d.nodes[k].next >= 0 { return d.nodes[k].next; }
        k = d.nodes[k].parent;
    }
    return -1;
}

fn is_marker_line(s: const u8[:], marker: const u8[:]) -> bool {
    guard starts_with(s, marker) else { return false; }
    for c in s[marker.len..] { if !is_space_or_tab(c) { return false; } }
    return true;
}

fn front_matter_close(s: const u8[:]) -> i64 {
    let first = line_end(s, 0);
    guard is_marker_line(s[..first], "---") else { return -1; }
    var i = next_line(s, first);
    while i < s.len {
        let end = line_end(s, i);
        if is_marker_line(s[i..end], "---") || is_marker_line(s[i..end], "...") { return i; }
        i = next_line(s, end);
    }
    return -1;
}

fn count_lines(s: const u8[:]) -> i64 {
    var n = 0;
    var i = 0;
    while i < s.len {
        n++;
        i = next_line(s, line_end(s, i));
    }
    return n;
}

fn add_front_matter(d: Doc&, b: LineState&, src: Span) -> i64 {
    guard d.opts.front_matter else { return 0; }
    let s = d.text[src.at..src.at + src.len];
    let close = front_matter_close(s);
    guard close >= 0 else { return 0; }
    let body = min(next_line(s, line_end(s, 0)), close);
    let resume = next_line(s, line_end(s, close));
    let n = new_node(d, Kind.FrontMatter, 1, 1);
    d.nodes[n].open = false;
    d.nodes[n].content = Span { at: src.at + body, len: close - body };
    b.number = count_lines(s[..min(resume, s.len)]);
    d.nodes[n].end_line = b.number;
    d.nodes[n].end_col = 3;
    append_child(d, 0, n);
    return resume;
}

fn remove_references(d: Doc&) {
    var empty: i64[>..] = [];
    var n = 0;
    while n >= 0 {
        if d.nodes[n].kind == Kind.Paragraph {
            let before = d.nodes[n].content.len;
            let removed = strip_references(d, n);
            d.nodes[n].line += removed;
            let c = d.nodes[n].content;
            if c.len != before && is_blank_text(d.text[c.at..c.at + c.len]) { empty.push(n); }
        }
        n = next_in_order(d, n, 0);
    }
    for e in empty { unlink(d, e); }
}

fn alert_type(s: const u8[:]) -> i64 {
    let end = position(s, '\n');
    let line = if end >= 0 { s[..end] } else { s };
    guard line.len > 4 && line[0] == '[' && line[1] == '!' else { return -1; }
    for t in ALERT_TYPES.len {
        let name = ALERT_TYPES[t];
        if line.len >= name.len + 3 && line[name.len + 2] == ']' && lower_equal(line[2..name.len + 2], name) {
            if is_marker_line(line[name.len + 3..], "") { return t; }
        }
    }
    return -1;
}

fn make_alert(d: Doc&, quote: i64) {
    let para = d.nodes[quote].first;
    guard para >= 0 && d.nodes[para].kind == Kind.Paragraph;
    let c = d.nodes[para].content;
    let t = alert_type(d.text[c.at..c.at + c.len]);
    guard t >= 0;
    d.nodes[quote].kind = Kind.Alert;
    d.nodes[quote].info = put_text(d, ALERT_TYPES[t]);
    let body = d.text[c.at..c.at + c.len];
    let nl = position(body, '\n');
    let cut = if nl >= 0 { nl + 1 } else { c.len };
    d.nodes[para].content = Span { at: c.at + cut, len: c.len - cut };
    d.nodes[para].line++;
    if is_blank_text(d.text[c.at + cut..c.at + c.len]) { unlink(d, para); }
}

fn make_alerts(d: Doc&) {
    guard d.opts.alerts;
    var n = d.nodes[0].first;
    while n >= 0 {
        if d.nodes[n].kind == Kind.BlockQuote { make_alert(d, n); }
        n = d.nodes[n].next;
    }
}

fn has_inlines(k: Kind) -> bool { k == Kind.Paragraph || k == Kind.Heading || k == Kind.TableCell }

fn process_inlines(d: Doc&) {
    var delims: Delim[>..] = [];
    var brackets: Bracket[>..] = [];
    let count = d.nodes.len;
    var n = 0;
    while n >= 0 {
        if n < count && has_inlines(d.nodes[n].kind) { parse_inlines(d, n, delims, brackets); }
        n = next_in_order(d, n, 0);
    }
}

fn merge_text(d: Doc&, a: i64, b: i64) {
    let x = d.nodes[a].content;
    let y = d.nodes[b].content;
    if x.at + x.len == y.at {
        d.nodes[a].content.len += y.len;
    } else {
        let at = d.text.len;
        d.text.append(d.text[x.at..x.at + x.len]);
        d.text.append(d.text[y.at..y.at + y.len]);
        d.nodes[a].content = Span { at: at, len: d.text.len - at };
    }
    unlink(d, b);
}

fn consolidate_text(d: Doc&) {
    var n = 0;
    while n >= 0 {
        if d.nodes[n].kind == Kind.Text {
            while d.nodes[n].next >= 0 && d.nodes[d.nodes[n].next].kind == Kind.Text { merge_text(d, n, d.nodes[n].next); }
        }
        n = next_in_order(d, n, 0);
    }
}

fn parse_markdown(d: Doc&, input: const u8[:]) {
    let root = new_node(d, Kind.Document, 1, 1);
    let src = put_source(d, input);
    var b = LineState { tip: root, oldtip: root, last_matched: root, .. };
    let from = add_front_matter(d, b, src);
    parse_lines(d, b, src, from);
    remove_references(d);
    make_alerts(d);
    process_inlines(d);
    consolidate_text(d);
    if d.opts.autolink { link_emails(d); }
}

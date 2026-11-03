import std;
import md.node;
import md.chars;
import md.entity;

let CODE_INDENT = 4;

enum Start { None, Container, Leaf }

struct LineState {
    at: i64 = 0,
    len: i64 = 0,
    number: i64 = 0,
    offset: i64 = 0,
    column: i64 = 0,
    next_nonspace: i64 = 0,
    next_nonspace_column: i64 = 0,
    indent: i64 = 0,
    indented: bool = false,
    blank: bool = false,
    partial_tab: bool = false,
    all_closed: bool = true,
    tip: i64 = 0,
    oldtip: i64 = 0,
    last_matched: i64 = 0,
    last_line_length: i64 = 0,
}

fn line_of(d: Doc&, b: LineState&) -> const u8[:] { d.text[b.at..b.at + b.len] }

fn peek(d: Doc&, b: LineState&, pos: i64) -> i64 { if pos < b.len { d.text[b.at + pos] } else { -1 } }

fn rest_of_line(d: Doc&, b: LineState&, pos: i64) -> const u8[:] { d.text[b.at + min(pos, b.len)..b.at + b.len] }

fn find_next_nonspace(d: Doc&, b: LineState&) {
    var i = b.offset;
    var cols = b.column;
    var c = peek(d, b, i);
    while c == ' ' || c == '\t' {
        if c == ' ' { cols++; } else { cols += 4 - cols % 4; }
        i++;
        c = peek(d, b, i);
    }
    b.blank = c == -1;
    b.next_nonspace = i;
    b.next_nonspace_column = cols;
    b.indent = cols - b.column;
    b.indented = b.indent >= CODE_INDENT;
}

fn advance_offset(d: Doc&, b: LineState&, count: i64, columns: bool) {
    var n = count;
    while n > 0 && b.offset < b.len {
        if peek(d, b, b.offset) == '\t' {
            let to_tab = 4 - b.column % 4;
            if columns {
                b.partial_tab = to_tab > n;
                let step = min(to_tab, n);
                b.column += step;
                if !b.partial_tab { b.offset++; }
                n -= step;
            } else {
                b.partial_tab = false;
                b.column += to_tab;
                b.offset++;
                n--;
            }
        } else {
            b.partial_tab = false;
            b.offset++;
            b.column++;
            n--;
        }
    }
}

fn advance_next_nonspace(b: LineState&) {
    b.offset = b.next_nonspace;
    b.column = b.next_nonspace_column;
    b.partial_tab = false;
}

fn add_line(d: Doc&, b: LineState&) {
    let tip = b.tip;
    if d.nodes[tip].content.len == 0 { d.nodes[tip].content.at = d.text.len; }
    let start = d.nodes[tip].content.at;
    assert(start + d.nodes[tip].content.len == d.text.len);
    if b.partial_tab {
        b.offset++;
        push_n(d.text, ' ', 4 - b.column % 4);
    }
    d.text.append(rest_of_line(d, b, b.offset));
    d.text.push('\n');
    d.nodes[tip].content.len = d.text.len - start;
}

fn can_contain(parent: Kind, child: Kind) -> bool {
    match parent {
        Document, BlockQuote, Alert, Item => child != Kind.Item,
        List => child == Kind.Item,
        Table => child == Kind.TableRow,
        TableRow => child == Kind.TableCell,
        _ => false,
    }
}

fn accepts_lines(k: Kind) -> bool { k == Kind.Paragraph || k == Kind.CodeBlock || k == Kind.HtmlBlock }

fn add_child(d: Doc&, b: LineState&, kind: Kind, offset: i64) -> i64 {
    while !can_contain(d.nodes[b.tip].kind, kind) { finalize(d, b, b.tip, b.number - 1); }
    let n = new_node(d, kind, b.number, offset + 1);
    append_child(d, b.tip, n);
    b.tip = n;
    return n;
}

fn close_unmatched(d: Doc&, b: LineState&) {
    guard !b.all_closed;
    while b.oldtip != b.last_matched {
        let parent = d.nodes[b.oldtip].parent;
        finalize(d, b, b.oldtip, b.number - 1);
        b.oldtip = parent;
    }
    b.all_closed = true;
}

fn ends_with_blank_line(d: Doc&, n: i64) -> bool {
    let next = d.nodes[n].next;
    next >= 0 && d.nodes[n].end_line != d.nodes[next].line - 1
}

fn finalize_list(d: Doc&, list: i64) {
    var item = d.nodes[list].first;
    while item >= 0 {
        if d.nodes[item].next >= 0 && ends_with_blank_line(d, item) {
            d.nodes[list].list.tight = false;
            break;
        }
        var sub = d.nodes[item].first;
        while sub >= 0 {
            if d.nodes[sub].next >= 0 && ends_with_blank_line(d, sub) {
                d.nodes[list].list.tight = false;
                break;
            }
            sub = d.nodes[sub].next;
        }
        item = d.nodes[item].next;
    }
    copy_end(d, list, d.nodes[list].last);
}

fn copy_end(d: Doc&, to: i64, from: i64) {
    d.nodes[to].end_line = d.nodes[from].end_line;
    d.nodes[to].end_col = d.nodes[from].end_col;
}

fn finalize_item(d: Doc&, item: i64) {
    let last = d.nodes[item].last;
    if last >= 0 {
        copy_end(d, item, last);
    } else {
        d.nodes[item].end_line = d.nodes[item].line;
        d.nodes[item].end_col = d.nodes[item].list.marker_offset + d.nodes[item].list.padding;
    }
}

fn is_blank_text(s: const u8[:]) -> bool {
    for c in s { if c != ' ' && c != '\t' && c != '\n' && c != '\r' && c != 11 && c != 12 { return false; } }
    return true;
}

fn finalize_fenced(d: Doc&, n: i64) {
    let c = d.nodes[n].content;
    let body = d.text[c.at..c.at + c.len];
    let nl = position(body, '\n');
    let info_at = d.text.len;
    unescape_into(d.text, trim_ascii(body[..nl]));
    d.nodes[n].info = Span { at: info_at, len: d.text.len - info_at };
    d.nodes[n].content = Span { at: c.at + nl + 1, len: c.len - nl - 1 };
}

fn finalize_indented(d: Doc&, n: i64) {
    let c = d.nodes[n].content;
    var end = c.len;
    var lines = 0;
    let body = d.text[c.at..c.at + c.len];
    for ch in body { if ch == '\n' { lines++; } }
    loop {
        let prev = if end > 0 { rfind(body[..end - 1], "\n") } else { -1 };
        guard is_blank_text(body[prev + 1..end]) else { break; }
        guard end > 0 else { break; }
        end = prev + 1;
        lines--;
    }
    d.nodes[n].content.len = end;
    let last_start = if end > 0 { rfind(body[..end - 1], "\n") + 1 } else { 0 };
    d.nodes[n].end_line = d.nodes[n].line + lines - 1;
    d.nodes[n].end_col = d.nodes[n].col + max(end - 1 - last_start, 0) - 1;
}

fn trim_ascii(s: const u8[:]) -> const u8[:] {
    var a = 0;
    var z = s.len;
    while a < z && is_ascii_space(s[a]) { a++; }
    while z > a && is_ascii_space(s[z - 1]) { z--; }
    return s[a..z];
}

fn finalize(d: Doc&, b: LineState&, n: i64, line_number: i64) {
    let above = d.nodes[n].parent;
    d.nodes[n].open = false;
    d.nodes[n].end_line = line_number;
    d.nodes[n].end_col = b.last_line_length;
    match d.nodes[n].kind {
        List => finalize_list(d, n),
        Item => finalize_item(d, n),
        CodeBlock => if d.nodes[n].fenced { finalize_fenced(d, n); } else { finalize_indented(d, n); },
        HtmlBlock => {
            let c = d.nodes[n].content;
            if c.len > 0 && d.text[c.at + c.len - 1] == '\n' { d.nodes[n].content.len--; }
        },
        _ => {},
    }
    b.tip = above;
}

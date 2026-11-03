import std;
import md.node;
import md.chars;
import md.line;
import md.html_scan;
import md.table;
import md.reference;
import md.block_start;

enum Continue { Matched, Failed, LineDone }

fn closing_fence_length(s: const u8[:], fence_char: u8) -> i64 {
    var n = 0;
    while n < s.len && s[n] == fence_char { n++; }
    guard n >= 3 else { return 0; }
    var k = n;
    while k < s.len && is_space_or_tab(s[k]) { k++; }
    return if k == s.len { n } else { 0 };
}

fn continue_code(d: Doc&, b: LineState&, n: i64) -> Continue {
    if !d.nodes[n].fenced {
        if b.indent >= CODE_INDENT {
            advance_offset(d, b, CODE_INDENT, true);
        } else if b.blank {
            advance_next_nonspace(b);
        } else {
            return Continue.Failed;
        }
        return Continue.Matched;
    }
    let fence = d.nodes[n].fence_char;
    if b.indent <= 3 && peek(d, b, b.next_nonspace) == fence {
        let len = closing_fence_length(rest_of_line(d, b, b.next_nonspace), fence);
        if len >= d.nodes[n].fence_len {
            b.last_line_length = b.offset + b.indent + len;
            finalize(d, b, n, b.number);
            return Continue.LineDone;
        }
    }
    var i = d.nodes[n].fence_offset;
    while i > 0 && is_space_or_tab(peek(d, b, b.offset)) {
        advance_offset(d, b, 1, true);
        i--;
    }
    return Continue.Matched;
}

fn continue_item(d: Doc&, b: LineState&, n: i64) -> Continue {
    let need = d.nodes[n].list.marker_offset + d.nodes[n].list.padding;
    if b.blank {
        guard d.nodes[n].first >= 0 else { return Continue.Failed; }
        advance_next_nonspace(b);
    } else if b.indent >= need {
        advance_offset(d, b, need, true);
    } else {
        return Continue.Failed;
    }
    return Continue.Matched;
}

fn continue_quote(d: Doc&, b: LineState&) -> Continue {
    guard !b.indented && peek(d, b, b.next_nonspace) == '>' else { return Continue.Failed; }
    advance_next_nonspace(b);
    advance_offset(d, b, 1, false);
    if is_space_or_tab(peek(d, b, b.offset)) { advance_offset(d, b, 1, true); }
    return Continue.Matched;
}

fn continue_block(d: Doc&, b: LineState&, n: i64) -> Continue {
    match d.nodes[n].kind {
        BlockQuote => continue_quote(d, b),
        Item => continue_item(d, b, n),
        CodeBlock => continue_code(d, b, n),
        HtmlBlock => if b.blank && d.nodes[n].html_type >= 6 { Continue.Failed } else { Continue.Matched },
        Paragraph => if b.blank { Continue.Failed } else { Continue.Matched },
        Table => if row_continues(d, b) { Continue.Matched } else { Continue.Failed },
        List => Continue.Matched,
        _ => Continue.Failed,
    }
}

fn maybe_special(c: i64) -> bool { c >= 0 && position("#`~*+_=<>0123456789-", c as! u8) >= 0 }

fn match_containers(d: Doc&, b: LineState&) -> i64 {
    var container = 0;
    loop {
        let last = d.nodes[container].last;
        guard last >= 0 && d.nodes[last].open else { break; }
        container = last;
        find_next_nonspace(d, b);
        let r = continue_block(d, b, container);
        if r == Continue.LineDone { return -1; }
        if r == Continue.Failed {
            container = d.nodes[container].parent;
            break;
        }
    }
    return container;
}

fn open_new_blocks(d: Doc&, b: LineState&, start: i64) -> i64 {
    var container = start;
    let kind = d.nodes[container].kind;
    var leaf = kind != Kind.Paragraph && accepts_lines(kind);
    let shortcut = !d.opts.table && !d.opts.tasklist;
    while !leaf {
        find_next_nonspace(d, b);
        if shortcut && !b.indented && !maybe_special(peek(d, b, b.next_nonspace)) {
            advance_next_nonspace(b);
            break;
        }
        let r = try_starts(d, b, container);
        if r == Start.None {
            advance_next_nonspace(b);
            break;
        }
        container = b.tip;
        leaf = r == Start.Leaf;
    }
    return container;
}

fn add_text_line(d: Doc&, b: LineState&, start: i64) {
    var container = start;
    if !b.all_closed && !b.blank && d.nodes[b.tip].kind == Kind.Paragraph {
        add_line(d, b);
        return;
    }
    close_unmatched(d, b);
    let kind = d.nodes[container].kind;
    if accepts_lines(kind) {
        add_line(d, b);
        let t = d.nodes[container].html_type;
        if kind == Kind.HtmlBlock && t >= 1 && t <= 5 && html_block_ends(t, rest_of_line(d, b, b.offset)) {
            b.last_line_length = b.len;
            finalize(d, b, container, b.number);
        }
    } else if b.offset < b.len && !b.blank {
        container = add_child(d, b, Kind.Paragraph, b.offset);
        advance_next_nonspace(b);
        add_line(d, b);
    }
}

fn incorporate_line(d: Doc&, b: LineState&) {
    b.oldtip = b.tip;
    b.offset = 0;
    b.column = 0;
    b.blank = false;
    b.partial_tab = false;
    b.number++;
    let matched = match_containers(d, b);
    guard matched >= 0;
    b.all_closed = matched == b.oldtip;
    b.last_matched = matched;
    let container = open_new_blocks(d, b, matched);
    add_text_line(d, b, container);
    b.last_line_length = b.len;
}

fn line_end(s: const u8[:], i: i64) -> i64 {
    var j = i;
    while j < s.len && s[j] != '\n' && s[j] != '\r' { j++; }
    return j;
}

fn next_line(s: const u8[:], end: i64) -> i64 {
    if end < s.len && s[end] == '\r' && end + 1 < s.len && s[end + 1] == '\n' { return end + 2; }
    return end + 1;
}

fn put_source(d: Doc&, input: const u8[:]) -> Span {
    let at = d.text.len;
    for c in input { if c == 0 { d.text.append("\xEF\xBF\xBD"); } else { d.text.push(c); } }
    return Span { at: at, len: d.text.len - at };
}

fn parse_lines(d: Doc&, b: LineState&, src: Span, from: i64) {
    let s = d.text[src.at..src.at + src.len];
    var i = from;
    while i < s.len {
        let end = line_end(s, i);
        b.at = src.at + i;
        b.len = end - i;
        incorporate_line(d, b);
        i = next_line(s, end);
    }
    while b.tip >= 0 { finalize(d, b, b.tip, b.number); }
}

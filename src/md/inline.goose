import std;
import md.node;
import md.chars;
import md.entity;
import md.html_scan;
import md.reference;
import md.inl_state;
import md.emph;
import md.inline_link;
import md.autolink;

fn is_blank_spaces(s: const u8[:]) -> bool {
    for c in s { if c != ' ' { return false; } }
    return true;
}

fn parse_backticks(d: Doc&, p: Inl&, parent: i64) {
    let s = subject(d, p);
    let start = p.pos;
    var i = start;
    while i < s.len && s[i] == '`' { i++; }
    let ticks = i - start;
    let after_open = i;
    while i < s.len {
        if s[i] != '`' {
            i++;
            continue;
        }
        let run_start = i;
        while i < s.len && s[i] == '`' { i++; }
        guard i - run_start == ticks;
        let at = d.text.len;
        for k in after_open..run_start {
            let c = d.text[p.at + k];
            d.text.push(if c == '\n' { ' ' } else { c });
        }
        var span = Span { at: at, len: d.text.len - at };
        let body = d.text[span.at..span.at + span.len];
        if body.len > 1 && body[0] == ' ' && body[body.len - 1] == ' ' && !is_blank_spaces(body) {
            span = Span { at: span.at + 1, len: span.len - 2 };
        }
        let code = add_leaf(d, parent, Kind.Code, span);
        d.nodes[code].src = p.at + start;
        p.pos = i;
        return;
    }
    add_text(d, p, parent, start, after_open);
    p.pos = after_open;
}

fn parse_backslash(d: Doc&, p: Inl&, parent: i64) {
    p.pos++;
    let c = peek_at(d, p, p.pos);
    if c == '\n' {
        add_leaf(d, parent, Kind.LineBreak, Span { at: p.at + p.pos, len: 0 });
        p.pos++;
    } else if c >= 0 && is_ascii_punct(c) {
        add_text(d, p, parent, p.pos, p.pos + 1);
        p.pos++;
    } else {
        add_text(d, p, parent, p.pos - 1, p.pos);
    }
}

fn parse_entity(d: Doc&, p: Inl&, parent: i64) -> bool {
    let at = d.text.len;
    let n = decode_entity(d.text, subject(d, p), p.pos);
    guard n > 0 else { return false; }
    let t = add_leaf(d, parent, Kind.Text, Span { at: at, len: d.text.len - at });
    d.nodes[t].src = p.at + p.pos;
    p.pos += n;
    return true;
}

fn parse_html_inline(d: Doc&, p: Inl&, parent: i64) -> bool {
    let end = scan_html_tag(subject(d, p), p.pos);
    guard end > 0 else { return false; }
    add_leaf(d, parent, Kind.HtmlInline, Span { at: p.at + p.pos, len: end - p.pos });
    p.pos = end;
    return true;
}

fn parse_newline(d: Doc&, p: Inl&, parent: i64) {
    let at = p.at + p.pos;
    p.pos++;
    let last = d.nodes[parent].last;
    var hard = false;
    if last >= 0 && d.nodes[last].kind == Kind.Text {
        let c = d.nodes[last].content;
        if c.len > 0 && d.text[c.at + c.len - 1] == ' ' {
            hard = c.len > 1 && d.text[c.at + c.len - 2] == ' ';
            var n = c.len;
            while n > 0 && d.text[c.at + n - 1] == ' ' { n--; }
            d.nodes[last].content.len = n;
        }
    }
    add_leaf(d, parent, if hard { Kind.LineBreak } else { Kind.SoftBreak }, Span { at: at, len: 0 });
    while peek_at(d, p, p.pos) == ' ' { p.pos++; }
}

fn is_special(c: u8, gfm: bool) -> bool {
    match c {
        '\n', '`', '[', ']', '\\', '!', '<', '&', '*', '_' => true,
        '~', ':', 'w' => gfm,
        _ => false,
    }
}

fn parse_string(d: Doc&, p: Inl&, parent: i64) {
    let s = subject(d, p);
    let gfm = d.opts.strike || d.opts.autolink;
    var i = p.pos + 1;
    while i < s.len && !is_special(s[i], gfm) { i++; }
    add_text(d, p, parent, p.pos, i);
    p.pos = i;
}

fn parse_one(d: Doc&, p: Inl&, parent: i64) {
    let c = d.text[p.at + p.pos];
    let done = match c {
        '\n' => {
            parse_newline(d, p, parent);
            true
        },
        '\\' => {
            parse_backslash(d, p, parent);
            true
        },
        '`' => {
            parse_backticks(d, p, parent);
            true
        },
        '*', '_' => handle_delim(d, p, parent, c),
        '~' => d.opts.strike && handle_delim(d, p, parent, c),
        '[' => {
            parse_open_bracket(d, p, parent);
            true
        },
        '!' => {
            parse_bang(d, p, parent);
            true
        },
        ']' => {
            parse_close_bracket(d, p, parent);
            true
        },
        '<' => parse_pointy_autolink(d, p, parent) || parse_html_inline(d, p, parent),
        '&' => parse_entity(d, p, parent),
        ':', 'w' => d.opts.autolink && p.bracket_top < 0 && match_autolink(d, p, parent, c),
        _ => false,
    };
    if !done { parse_string(d, p, parent); }
}

fn trim_subject(d: Doc&, c: Span) -> Span {
    var a = c.at;
    var z = c.at + c.len;
    while a < z && is_ascii_space(d.text[a]) { a++; }
    while z > a && is_ascii_space(d.text[z - 1]) { z--; }
    return Span { at: a, len: z - a };
}

fn parse_inlines(d: Doc&, parent: i64, delims: Delim[>..]&, brackets: Bracket[>..]&) {
    let s = trim_subject(d, d.nodes[parent].content);
    delims.clear();
    brackets.clear();
    var p = Inl { at: s.at, len: s.len, delims: delims, brackets: brackets, .. };
    while p.pos < p.len { parse_one(d, p, parent); }
    process_emphasis(d, p, -1);
}

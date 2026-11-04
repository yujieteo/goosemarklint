import std;
import md.node;
import md.chars;
import md.parse;
import lint.lists;
import fmt.emit;

let CLOSERS = ")]\"'*_";
let OPENERS = "\"'([*_`!";

struct Flow { s: u8[>..]&, map: i64[>..]&, nl: bool[>..]&, safe: Span[>..]&, breaks: i64[>..]&, keep: bool, from: i64 = 0 }

fn is_blank_char(c: u8) -> bool { c == ' ' || c == '\t' }

fn collect_safe(d: Doc&, flow: Flow&, para: i64) {
    let c = d.nodes[para].content;
    var n = next_in_order(d, para, para);
    while n >= 0 {
        let t = d.nodes[n].content;
        let k = d.nodes[n].kind;
        if k == Kind.Text && t.at >= c.at && t.at + t.len <= c.at + c.len { flow.safe.push(t); }
        if k == Kind.SoftBreak || k == Kind.LineBreak { flow.breaks.push(t.at); }
        n = next_in_order(d, n, para);
    }
}

fn in_safe(flow: Flow&, at: i64) -> bool { any(flow.safe) { at >= it.at && at < it.at + it.len } }

fn starts_block(t: const u8[:]) -> bool {
    if (t[0] == '*' || t[0] == '_') && (t.len == 1 || is_blank_char(t[1])) { return true; }
    if starts_with(t, "```") { return true; }
    var i = 0;
    while i < t.len && is_digit(t[i]) { i++; }
    return i > 0 && i < t.len && (t[i] == '.' || t[i] == ')') && (i + 1 == t.len || is_blank_char(t[i + 1]));
}

fn starts_sentence(t: const u8[:]) -> bool {
    let c = t[0];
    guard (c >= 'A' && c <= 'Z') || is_digit(c) || c >= 0x80 || position(OPENERS, c) >= 0 else { return false; }
    return !starts_block(t);
}

fn is_abbreviation(before: const u8[:]) -> bool {
    var a = before.len;
    while a > 0 && (is_alnum(before[a - 1]) || before[a - 1] == '.') { a--; }
    return a < before.len && in_list(ABBREVIATION, before[a..]);
}

fn boundary(flow: Flow&, k: i64) -> i64 {
    let s = flow.s;
    guard position(".!?", s[k]) >= 0 else { return -1; }
    var j = k + 1;
    while j < s.len && position(CLOSERS, s[j]) >= 0 { j++; }
    guard j < s.len && is_blank_char(s[j]) else { return -1; }
    var w = j;
    while w < s.len && is_blank_char(s[w]) { w++; }
    guard w < s.len && starts_sentence(s[w..]) && !is_abbreviation(s[..k]) else { return -1; }
    let joined = any(flow.nl[j..w]) { it };
    guard joined || (in_safe(flow, flow.map[j]) && in_safe(flow, flow.map[w - 1])) else { return -1; }
    return w;
}

fn put_flow(f: Fmt&, flow: Flow&, suffix: const u8[:]) {
    var start = flow.from;
    var k = if flow.keep { flow.s.len } else { flow.from };
    while k < flow.s.len {
        let w = boundary(flow, k);
        if w >= 0 {
            put_line(f, trim_space_end(flow.s[start..w]));
            start = w;
            k = w;
        } else {
            k++;
        }
    }
    put_line(f, str(flow.s[start..], suffix));
    flow.from = flow.s.len;
}

fn add_text(flow: Flow&, s: const u8[:], at: i64) {
    for c, i in s {
        flow.s.push(c);
        flow.map.push(at + i);
        flow.nl.push(false);
    }
}

fn odd_backslashes(s: const u8[:]) -> bool {
    var n = 0;
    while n < s.len && s[s.len - 1 - n] == '\\' { n++; }
    return n % 2 == 1;
}

fn trailing_spaces(s: const u8[:]) -> i64 {
    var n = 0;
    while n < s.len && s[s.len - 1 - n] == ' ' { n++; }
    return n;
}

fn flow_line(f: Fmt&, flow: Flow&, line: const u8[:], at: i64, lead: bool, last: bool) -> bool {
    var a = 0;
    while lead && a < line.len && is_blank_char(line[a]) { a++; }
    let text_break = !last && position(flow.breaks, at + line.len) >= 0;
    guard text_break else {
        add_text(flow, if last { trim_space_end(line[a..]) } else { line[a..] }, at + a);
        put_flow(f, flow, "");
        return false;
    }
    let spaces = trailing_spaces(line) >= 2;
    let body = trim_space_end(line[a..]);
    add_text(flow, body, at + a);
    if flow.keep || spaces || odd_backslashes(body) {
        put_flow(f, flow, if spaces { "  " } else { "" });
    } else {
        flow.s.push(' ');
        flow.map.push(at + line.len);
        flow.nl.push(true);
    }
    return true;
}

fn put_paragraph(f: Fmt&, para: i64, keep: bool) {
    var s: u8[>..] = [];
    var map: i64[>..] = [];
    var nl: bool[>..] = [];
    var safe: Span[>..] = [];
    var breaks: i64[>..] = [];
    var flow = Flow { s: s, map: map, nl: nl, safe: safe, breaks: breaks, keep: keep };
    collect_safe(f.d, flow, para);
    let c = f.d.nodes[para].content;
    let all = f.d.text[c.at..c.at + c.len];
    let text = if ends_with(all, "\n") { all[..all.len - 1] } else { all };
    var at = 0;
    var lead = true;
    while at <= text.len {
        let nl_at = position(text[at..], '\n');
        let end = if nl_at < 0 { text.len } else { at + nl_at };
        lead = flow_line(f, flow, text[at..end], c.at + at, lead, end == text.len);
        at = end + 1;
    }
}

fn heading_text(d: Doc&, n: i64, out: u8[>..]&) {
    let c = d.nodes[n].content;
    each_split(d.text[c.at..c.at + c.len], '\n') {
        let t = trim(it);
        if t.len > 0 && out.len > 0 { out.push(' '); }
        out.append(t);
    };
}

fn put_heading(f: Fmt&, n: i64) {
    var t: u8[>..] = [];
    heading_text(f.d, n, t);
    var r = t.len;
    while r > 0 && t[r - 1] == '#' { r--; }
    var line: u8[>..] = [];
    push_n(line, '#', f.d.nodes[n].level);
    if t.len > 0 { line.push(' '); }
    line.append(t[..r]);
    if r < t.len && (r == 0 || is_blank_char(t[r - 1])) { line.push('\\'); }
    line.append(t[r..]);
    put_line(f, line);
}

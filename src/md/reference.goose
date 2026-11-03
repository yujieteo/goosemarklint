import std;
import dictionary;
import md.node;
import md.chars;
import md.entity;

fn skip_spnl(s: const u8[:], i: i64) -> i64 {
    var j = i;
    while j < s.len && s[j] == ' ' { j++; }
    if j < s.len && s[j] == '\n' {
        j++;
        while j < s.len && s[j] == ' ' { j++; }
    }
    return j;
}

fn link_label_length(s: const u8[:], i: i64) -> i64 {
    guard i < s.len && s[i] == '[' else { return 0; }
    var j = i + 1;
    var chars = 0;
    while j < s.len {
        let c = s[j];
        if c == ']' { return if chars <= 999 { j + 1 - i } else { 0 }; }
        if c == '[' { return 0; }
        if c == '\\' && j + 1 < s.len {
            j++;
            chars++;
        }
        if (s[j] & 0xC0) != 0x80 { chars++; }
        j++;
        if chars > 1000 { return 0; }
    }
    return 0;
}

fn put_destination(d: Doc&, raw: const u8[:]) -> Span {
    var plain: u8[>..] = [];
    unescape_into(plain, raw);
    let at = d.text.len;
    normalize_uri_into(d.text, plain);
    return Span { at: at, len: d.text.len - at };
}

fn put_unescaped(d: Doc&, raw: const u8[:]) -> Span {
    let at = d.text.len;
    unescape_into(d.text, raw);
    return Span { at: at, len: d.text.len - at };
}

fn scan_braced_destination(s: const u8[:], i: i64) -> i64 {
    var j = i + 1;
    while j < s.len {
        let c = s[j];
        if c == '>' { return j + 1; }
        if c == '<' || c == '\n' { return -1; }
        if c == '\\' && j + 1 < s.len && s[j + 1] != '\n' { j++; }
        j++;
    }
    return -1;
}

fn scan_plain_destination(s: const u8[:], i: i64) -> i64 {
    var j = i;
    var parens = 0;
    while j < s.len {
        let c = s[j];
        if c == '\\' && j + 1 < s.len && is_ascii_punct(s[j + 1]) {
            j += 2;
        } else if c == '(' {
            parens++;
            if parens > 32 { return -1; }
            j++;
        } else if c == ')' {
            if parens < 1 { break; }
            parens--;
            j++;
        } else if is_ascii_space(c) {
            break;
        } else {
            j++;
        }
    }
    if j == i && (j >= s.len || s[j] != ')') { return -1; }
    if parens != 0 { return -1; }
    return j;
}

fn parse_destination(d: Doc&, s: const u8[:], i: i64, dest: Span&) -> i64 {
    if i < s.len && s[i] == '<' {
        let end = scan_braced_destination(s, i);
        guard end >= 0 else { return -1; }
        dest = put_destination(d, s[i + 1..end - 1]);
        return end;
    }
    let end = scan_plain_destination(s, i);
    guard end >= 0 else { return -1; }
    dest = put_destination(d, s[i..end]);
    return end;
}

fn scan_title(s: const u8[:], i: i64) -> i64 {
    guard i < s.len else { return -1; }
    let open = s[i];
    guard open == '"' || open == '\'' || open == '(' else { return -1; }
    let close = if open == '(' { ')' } else { open };
    var j = i + 1;
    while j < s.len {
        let c = s[j];
        if c == '\\' {
            guard j + 1 < s.len else { return -1; }
            j += 2;
            continue;
        }
        if c == close { return j + 1; }
        if open == '(' && c == '(' { return -1; }
        if c == 0 { return -1; }
        j++;
    }
    return -1;
}

fn space_to_line_end(s: const u8[:], i: i64) -> i64 {
    var j = i;
    while j < s.len && s[j] == ' ' { j++; }
    if j == s.len { return j; }
    if s[j] == '\n' { return j + 1; }
    return -1;
}

fn find_ref(d: Doc&, key: const u8[:]) -> i64 {
    let first = d.ref_index.get(hash(key));
    guard first else { return -1; }
    var r = first;
    while r >= 0 {
        let label = d.refs[r].label;
        if d.text[label.at..label.at + label.len] == key { return r; }
        r = d.refs[r].chain;
    }
    return -1;
}

fn lookup_ref(d: Doc&, raw: const u8[:]) -> i64 {
    var key: u8[>..] = [];
    normalize_label(key, raw[1..raw.len - 1]);
    guard key.len > 0 else { return -1; }
    return find_ref(d, key);
}

fn add_ref(d: Doc&, key: const u8[:], dest: Span, title: Span, line: i64) {
    guard find_ref(d, key) < 0;
    let id = d.refs.len;
    let label = put_text(d, key);
    let head = d.ref_index.get(hash(key));
    let chain = if head { head } else { -1 };
    d.refs.push(Ref { label: label, dest: dest, title: title, chain: chain, line: line });
    d.ref_index.insert(hash(key), id);
}

fn parse_reference(d: Doc&, s: const u8[:], line: i64) -> i64 {
    let label_len = link_label_length(s, 0);
    guard label_len > 0 && label_len < s.len && s[label_len] == ':' else { return 0; }
    let dest_at = skip_spnl(s, label_len + 1);
    var dest = Span {};
    let dest_end = parse_destination(d, s, dest_at, dest);
    guard dest_end >= 0 else { return 0; }
    let before_title = dest_end;
    let title_at = skip_spnl(s, before_title);
    var title = Span {};
    var end = -1;
    if title_at != before_title {
        let title_end = scan_title(s, title_at);
        if title_end >= 0 {
            end = space_to_line_end(s, title_end);
            if end >= 0 { title = put_unescaped(d, s[title_at + 1..title_end - 1]); }
        }
    }
    if end < 0 { end = space_to_line_end(s, before_title); }
    guard end >= 0 else { return 0; }
    var key: u8[>..] = [];
    normalize_label(key, s[1..label_len - 1]);
    guard key.len > 0 else { return 0; }
    add_ref(d, key, dest, title, line);
    return end;
}

fn strip_references(d: Doc&, para: i64) {
    var removed_lines = 0;
    loop {
        let c = d.nodes[para].content;
        guard c.len > 0 && d.text[c.at] == '[' else { break; }
        let n = parse_reference(d, d.text[c.at..c.at + c.len], d.nodes[para].line + removed_lines);
        guard n > 0 else { break; }
        for k in n { if d.text[c.at + k] == '\n' { removed_lines++; } }
        d.nodes[para].content = Span { at: c.at + n, len: c.len - n };
    }
    guard removed_lines > 0 && d.nodes[para].content.len > 0;
    d.nodes[para].line += removed_lines;
    d.nodes[para].col = d.line_cols[d.nodes[para].line];
}

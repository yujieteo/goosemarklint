import std;
import md.node;
import md.chars;
import md.entity;
import md.inl_state;

fn is_c_space(c: i64) -> bool { c == ' ' || c == '\t' || c == '\n' || c == 11 || c == 12 || c == '\r' }

fn is_valid_hostchar(s: const u8[:], i: i64) -> bool {
    guard s[i] < 0x80 || s[i] >= 0xC0 else { return false; }
    let cp, n = decode_at(s, i);
    return !is_unicode_space(cp) && !is_c_space(cp) && !is_unicode_punct(cp);
}

fn autolink_delim(s: const u8[:], end_in: i64) -> i64 {
    var end = end_in;
    var opening = 0;
    var closing = 0;
    for i in end_in {
        let c = s[i];
        if c == '<' {
            end = i;
            break;
        }
        if c == '(' { opening++; } else if c == ')' { closing++; }
    }
    while end > 0 {
        let c = s[end - 1];
        if c == ')' {
            if closing <= opening { return end; }
            closing--;
            end--;
        } else if position("?!.,:*_~'\"", c) >= 0 {
            end--;
        } else if c == ';' {
            var k = end - 2;
            while k > 0 && is_alpha(s[k]) { k--; }
            if k < end - 2 && s[k] == '&' { end = k; } else { end--; }
        } else {
            return end;
        }
    }
    return end;
}

fn check_domain(s: const u8[:], allow_short: bool) -> i64 {
    var np = 0;
    var us1 = 0;
    var us2 = 0;
    var i = 1;
    while i < s.len - 1 {
        if s[i] == '\\' && i < s.len - 2 { i++; }
        if s[i] == '_' {
            us2++;
        } else if s[i] == '.' {
            us1 = us2;
            us2 = 0;
            np++;
        } else if !is_valid_hostchar(s, i) && s[i] != '-' {
            break;
        }
        i++;
    }
    if (us1 > 0 || us2 > 0) && np <= 10 { return 0; }
    if allow_short || np > 0 { return i; }
    return 0;
}

fn extend_link(s: const u8[:], from: i64) -> i64 {
    var end = from;
    while end < s.len && !is_c_space(s[end]) && s[end] != '<' { end++; }
    return autolink_delim(s, end);
}

fn add_autolink(d: Doc&, parent: i64, prefix: const u8[:], text: Span) {
    let link = new_node(d, Kind.Link, 0, 0);
    var raw: u8[>..] = [];
    raw.append(prefix);
    raw.append(d.text[text.at..text.at + text.len]);
    let at = d.text.len;
    normalize_uri_into(d.text, raw);
    d.nodes[link].info = Span { at: at, len: d.text.len - at };
    let child = new_node(d, Kind.Text, 0, 0);
    d.nodes[child].content = text;
    append_child(d, link, child);
    append_child(d, parent, link);
}

fn match_www(d: Doc&, p: Inl&, parent: i64) -> bool {
    let s = subject(d, p);
    let pos = p.pos;
    guard pos == 0 || position("*_~(", s[pos - 1]) >= 0 || is_c_space(s[pos - 1]) else { return false; }
    guard starts_with(s[pos..], "www.") else { return false; }
    let data = s[pos..];
    let domain = check_domain(data, false);
    guard domain > 0 else { return false; }
    let end = extend_link(data, domain);
    guard end > 0 else { return false; }
    add_autolink(d, parent, "http://", Span { at: p.at + pos, len: end });
    p.pos = pos + end;
    return true;
}

fn lower_starts(s: const u8[:], word: const u8[:]) -> bool {
    guard s.len >= word.len else { return false; }
    for k in word.len { if lower_ascii(s[k]) != word[k] { return false; } }
    return true;
}

fn is_safe_scheme(s: const u8[:]) -> bool {
    for scheme in ["http://", "https://", "ftp://"] {
        if s.len > scheme.len && lower_starts(s, scheme) && is_valid_hostchar(s, scheme.len) { return true; }
    }
    return false;
}

fn unput(d: Doc&, parent: i64, count: i64) {
    var n = count;
    var node = d.nodes[parent].last;
    while n > 0 && node >= 0 && d.nodes[node].kind == Kind.Text {
        let len = d.nodes[node].content.len;
        let take = min(len, n);
        d.nodes[node].content.len = len - take;
        n -= take;
        node = d.nodes[node].prev;
    }
}

fn match_url(d: Doc&, p: Inl&, parent: i64) -> bool {
    let s = subject(d, p);
    let pos = p.pos;
    let data = s[pos..];
    guard data.len >= 4 && data[1] == '/' && data[2] == '/' else { return false; }
    var rewind = 0;
    while rewind < pos && is_alpha(s[pos - rewind - 1]) { rewind++; }
    guard is_safe_scheme(s[pos - rewind..]) else { return false; }
    let domain = check_domain(data[3..], true);
    guard domain > 0 else { return false; }
    let end = extend_link(data, 3 + domain);
    guard end > 0 else { return false; }
    unput(d, parent, rewind);
    add_autolink(d, parent, "", Span { at: p.at + pos - rewind, len: end + rewind });
    p.pos = pos + end;
    return true;
}

fn match_autolink(d: Doc&, p: Inl&, parent: i64, c: u8) -> bool {
    if c == ':' { return match_url(d, p, parent); }
    return match_www(d, p, parent);
}

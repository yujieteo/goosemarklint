import std;
import md.node;
import md.chars;
import md.entity;
import md.reference;
import md.inl_state;
import md.emph;

fn add_bracket(p: Inl&, node: i64, index: i64, image: bool) {
    if p.bracket_top >= 0 { p.brackets[p.bracket_top].bracket_after = true; }
    let id = p.brackets.len;
    p.brackets.push(Bracket { node: node, prev: p.bracket_top, prev_delim: p.delim_top, index: index, image: image, .. });
    p.bracket_top = id;
}

fn parse_open_bracket(d: Doc&, p: Inl&, parent: i64) {
    let node = add_text(d, p, parent, p.pos, p.pos + 1);
    add_bracket(p, node, p.pos, false);
    p.pos++;
}

fn parse_bang(d: Doc&, p: Inl&, parent: i64) {
    if peek_at(d, p, p.pos + 1) == '[' {
        let node = add_text(d, p, parent, p.pos, p.pos + 2);
        add_bracket(p, node, p.pos + 1, true);
        p.pos += 2;
    } else {
        add_text(d, p, parent, p.pos, p.pos + 1);
        p.pos++;
    }
}

struct Target { dest: Span, title: Span }

fn parse_inline_target(d: Doc&, p: Inl&, t: Target&) -> bool {
    let s = subject(d, p);
    let open = p.pos;
    guard open < s.len && s[open] == '(' else { return false; }
    let dest_end = parse_destination(d, s, skip_spnl(s, open + 1), t.dest);
    guard dest_end >= 0 else { return false; }
    var j = skip_spnl(s, dest_end);
    if is_ascii_space(s[j - 1]) {
        let title_end = scan_title(s, j);
        if title_end >= 0 {
            t.title = put_unescaped(d, s[j + 1..title_end - 1]);
            j = title_end;
        }
    }
    j = skip_spnl(s, j);
    guard j < s.len && s[j] == ')' else { return false; }
    p.pos = j + 1;
    return true;
}

fn parse_ref_target(d: Doc&, p: Inl&, opener: Bracket, start: i64, t: Target&) -> bool {
    let s = subject(d, p);
    let before = p.pos;
    let n = link_label_length(s, before);
    var r = -1;
    if n > 2 {
        r = lookup_ref(d, s[before..before + n]);
    } else if !opener.bracket_after {
        r = lookup_ref(d, s[opener.index..start]);
    }
    if n == 0 { p.pos = start; } else { p.pos = before + n; }
    guard r >= 0 else { return false; }
    d.refs[r].used = true;
    t.dest = d.refs[r].dest;
    t.title = d.refs[r].title;
    return true;
}

fn deactivate_links(p: Inl&) {
    var b = p.bracket_top;
    while b >= 0 {
        if !p.brackets[b].image { p.brackets[b].active = false; }
        b = p.brackets[b].prev;
    }
}

fn parse_close_bracket(d: Doc&, p: Inl&, parent: i64) {
    p.pos++;
    let start = p.pos;
    let top = p.bracket_top;
    if top < 0 || !p.brackets[top].active {
        add_text(d, p, parent, start - 1, start);
        if top >= 0 { p.bracket_top = p.brackets[top].prev; }
        return;
    }
    let opener = p.brackets[top];
    var t = Target { dest: Span {}, title: Span {} };
    var matched = parse_inline_target(d, p, t);
    if !matched { matched = parse_ref_target(d, p, opener, start, t); }
    p.bracket_top = opener.prev;
    if !matched {
        p.pos = start;
        add_text(d, p, parent, start - 1, start);
        return;
    }
    let link = new_node(d, if opener.image { Kind.Image } else { Kind.Link }, 0, 0);
    d.nodes[link].src = d.nodes[opener.node].content.at;
    d.nodes[link].info = t.dest;
    d.nodes[link].title = t.title;
    var n = d.nodes[opener.node].next;
    while n >= 0 {
        let next = d.nodes[n].next;
        unlink(d, n);
        append_child(d, link, n);
        n = next;
    }
    append_child(d, parent, link);
    process_emphasis(d, p, opener.prev_delim);
    unlink(d, opener.node);
    if !opener.image { deactivate_links(p); }
}

fn is_email_local(c: u8) -> bool { is_alnum(c) || position(".!#$%&'*+/=?^_`{|}~-", c) >= 0 }

fn scan_email(s: const u8[:], i: i64) -> i64 {
    var j = i + 1;
    while j < s.len && is_email_local(s[j]) { j++; }
    guard j > i + 1 && j < s.len && s[j] == '@' else { return -1; }
    j++;
    loop {
        let label = j;
        while j < s.len && (is_alnum(s[j]) || s[j] == '-') { j++; }
        let n = j - label;
        guard n >= 1 && n <= 63 && is_alnum(s[label]) && is_alnum(s[j - 1]) else { return -1; }
        guard j < s.len else { return -1; }
        if s[j] == '>' { return j + 1; }
        guard s[j] == '.' else { return -1; }
        j++;
    }
}

fn scan_uri(s: const u8[:], i: i64) -> i64 {
    var j = i + 1;
    guard j < s.len && is_alpha(s[j]) else { return -1; }
    j++;
    while j < s.len && (is_alnum(s[j]) || s[j] == '.' || s[j] == '+' || s[j] == '-') { j++; }
    let scheme = j - i - 1;
    guard scheme >= 2 && scheme <= 32 && j < s.len && s[j] == ':' else { return -1; }
    j++;
    while j < s.len && s[j] > 0x20 && s[j] != '<' && s[j] != '>' { j++; }
    guard j < s.len && s[j] == '>' else { return -1; }
    return j + 1;
}

fn parse_pointy_autolink(d: Doc&, p: Inl&, parent: i64) -> bool {
    let s = subject(d, p);
    var end = scan_email(s, p.pos);
    let email = end >= 0;
    if !email { end = scan_uri(s, p.pos); }
    guard end >= 0 else { return false; }
    let link = new_node(d, Kind.Link, 0, 0);
    d.nodes[link].src = p.at + p.pos;
    var raw: u8[>..] = [];
    if email { raw.append("mailto:"); }
    raw.append(s[p.pos + 1..end - 1]);
    let at = d.text.len;
    normalize_uri_into(d.text, raw);
    d.nodes[link].info = Span { at: at, len: d.text.len - at };
    let text = new_node(d, Kind.Text, 0, 0);
    d.nodes[text].content = Span { at: p.at + p.pos + 1, len: end - p.pos - 2 };
    append_child(d, link, text);
    append_child(d, parent, link);
    p.pos = end;
    return true;
}

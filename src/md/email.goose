import std;
import md.node;
import md.chars;
import md.entity;
import md.autolink;

struct EmailHit { from: i64 = 0, to: i64 = 0, mailto: bool = true }

fn protocol_before(s: const u8[:], at: i64, rewind: i64, max_rewind: i64, protocol: const u8[:]) -> bool {
    let len = protocol.len;
    guard len <= max_rewind - rewind else { return false; }
    let start = at - rewind - len;
    guard s[start..start + len] == protocol else { return false; }
    guard len != max_rewind - rewind else { return true; }
    return !is_alnum(s[start - 1]);
}

struct EmailScan { mailto: bool = true, xmpp: bool = false, dots: i64 = 0 }

fn rewind_local(s: const u8[:], at: i64, max_rewind: i64, e: EmailScan&) -> i64 {
    var rewind = 0;
    while rewind < max_rewind {
        let c = s[at - rewind - 1];
        if !is_alnum(c) && position(".+-_", c) < 0 {
            guard c == ':' else { break; }
            if protocol_before(s, at, rewind, max_rewind, "mailto:") {
                e.mailto = false;
            } else if protocol_before(s, at, rewind, max_rewind, "xmpp:") {
                e.mailto = false;
                e.xmpp = true;
            } else {
                break;
            }
        }
        rewind++;
    }
    return rewind;
}

fn domain_length(s: const u8[:], at: i64, e: EmailScan&) -> i64, bool {
    let room = s.len - at;
    var end = 1;
    while end < room {
        let c = s[at + end];
        if c == '@' { return end, true; }
        if c == '.' && end < room - 1 && is_alnum(s[at + end + 1]) {
            e.dots++;
        } else if !is_alnum(c) && !(c == '/' && e.xmpp) && c != '-' && c != '_' {
            break;
        }
        end++;
    }
    return end, false;
}

fn find_email(s: const u8[:], hit: EmailHit&) -> bool {
    var offset = 0;
    while offset < s.len {
        let found = position(s[offset..], '@');
        guard found >= 0 else { return false; }
        var max_rewind = found;
        var e = EmailScan {};
        loop {
            let at = offset + max_rewind;
            let rewind = rewind_local(s, at, max_rewind, e);
            if rewind == 0 {
                offset += max_rewind + 1;
                break;
            }
            let end, another = domain_length(s, at, e);
            if another {
                offset += max_rewind + 1;
                max_rewind = end - 1;
                continue;
            }
            let last = s[at + end - 1];
            if end < 2 || e.dots == 0 || (!is_alpha(last) && last != '.') {
                offset += max_rewind + end;
                break;
            }
            let link_end = autolink_delim(s[at..], end);
            if link_end == 0 {
                offset += max_rewind + 1;
                break;
            }
            hit = EmailHit { from: at - rewind, to: at + link_end, mailto: e.mailto };
            return true;
        }
    }
    return false;
}

fn split_email(d: Doc&, text: i64) -> i64 {
    let c = d.nodes[text].content;
    var hit = EmailHit {};
    guard find_email(d.text[c.at..c.at + c.len], hit) else { return -1; }
    let link = new_node(d, Kind.Link, 0, 0);
    var raw: u8[>..] = [];
    if hit.mailto { raw.append("mailto:"); }
    raw.append(d.text[c.at + hit.from..c.at + hit.to]);
    let at = d.text.len;
    normalize_uri_into(d.text, raw);
    d.nodes[link].info = Span { at: at, len: d.text.len - at };
    let label = new_node(d, Kind.Text, 0, 0);
    d.nodes[label].content = Span { at: c.at + hit.from, len: hit.to - hit.from };
    append_child(d, link, label);
    insert_after(d, text, link);
    d.nodes[text].content.len = hit.from;
    guard hit.to < c.len else { return -1; }
    let post = new_node(d, Kind.Text, 0, 0);
    d.nodes[post].content = Span { at: c.at + hit.to, len: c.len - hit.to };
    insert_after(d, link, post);
    return post;
}

fn link_emails(d: Doc&) {
    var n = 0;
    loop {
        let k = d.nodes[n].kind;
        var skip = false;
        if k == Kind.Link {
            skip = true;
        } else if k == Kind.Text {
            var t = n;
            while t >= 0 {
                n = t;
                t = split_email(d, t);
            }
        }
        var next = if skip { -1 } else { d.nodes[n].first };
        if next < 0 {
            var up = n;
            while up != 0 && d.nodes[up].next < 0 { up = d.nodes[up].parent; }
            if up == 0 { break; }
            next = d.nodes[up].next;
        }
        n = next;
    }
}

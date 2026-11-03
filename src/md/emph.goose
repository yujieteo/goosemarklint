import std;
import md.node;
import md.chars;
import md.inl_state;

fn remove_delimiter(p: Inl&, i: i64) {
    let prev = p.delims[i].prev;
    let next = p.delims[i].next;
    if prev >= 0 { p.delims[prev].next = next; }
    if next < 0 { p.delim_top = prev; } else { p.delims[next].prev = prev; }
}

fn handle_delim(d: Doc&, p: Inl&, parent: i64, cc: u8) -> bool {
    let s = subject(d, p);
    let start = p.pos;
    var end = start;
    while end < s.len && s[end] == cc { end++; }
    let before = if start == 0 { 10 } else { decode_before(s, start) };
    var after = 10;
    if end < s.len {
        let cp, n = decode_at(s, end);
        after = cp;
    }
    let after_space = is_unicode_space(after);
    let after_punct = is_unicode_punct(after);
    let before_space = is_unicode_space(before);
    let before_punct = is_unicode_punct(before);
    let left = !after_space && (!after_punct || before_space || before_punct);
    let right = !before_space && (!before_punct || after_space || after_punct);
    var can_open = left;
    var can_close = right;
    if cc == '_' {
        can_open = left && (!right || before_punct);
        can_close = right && (!left || after_punct);
    }
    let num = end - start;
    let node = add_text(d, p, parent, start, end);
    p.pos = end;
    guard can_open || can_close else { return true; }
    guard cc != '~' || num <= 2 else { return true; }
    let id = p.delims.len;
    p.delims.push(Delim { cc: cc, num: num, orig: num, node: node, prev: p.delim_top, can_open: can_open, can_close: can_close });
    if p.delim_top >= 0 { p.delims[p.delim_top].next = id; }
    p.delim_top = id;
    return true;
}

fn bottom_index(c: Delim) -> i64 {
    let base = if c.cc == '_' { 0 } else if c.cc == '*' { 6 } else { 12 };
    return base + (if c.can_open { 3 } else { 0 }) + c.orig % 3;
}

fn move_between(d: Doc&, from: i64, to: i64, into: i64) {
    var n = d.nodes[from].next;
    while n >= 0 && n != to {
        let next = d.nodes[n].next;
        unlink(d, n);
        append_child(d, into, n);
        n = next;
    }
}

fn insert_strike(d: Doc&, p: Inl&, opener: i64, closer: i64) -> i64 {
    let next = p.delims[closer].next;
    let o = p.delims[opener].node;
    let c = p.delims[closer].node;
    if d.nodes[o].content.len == d.nodes[c].content.len {
        let strike = new_node(d, Kind.Strike, 0, 0);
        move_between(d, o, c, strike);
        insert_after(d, o, strike);
        unlink(d, o);
        unlink(d, c);
    }
    var k = closer;
    while k >= 0 && k != opener {
        let prev = p.delims[k].prev;
        remove_delimiter(p, k);
        k = prev;
    }
    remove_delimiter(p, opener);
    return next;
}

fn insert_emph(d: Doc&, p: Inl&, opener: i64, closer: i64) -> i64 {
    let use_delims = if p.delims[closer].num >= 2 && p.delims[opener].num >= 2 { 2 } else { 1 };
    let o = p.delims[opener].node;
    let c = p.delims[closer].node;
    p.delims[opener].num -= use_delims;
    p.delims[closer].num -= use_delims;
    d.nodes[o].content.len -= use_delims;
    d.nodes[c].content.len -= use_delims;
    let emph = new_node(d, if use_delims == 1 { Kind.Emph } else { Kind.Strong }, 0, 0);
    move_between(d, o, c, emph);
    insert_after(d, o, emph);
    if p.delims[opener].next != closer {
        p.delims[opener].next = closer;
        p.delims[closer].prev = opener;
    }
    if p.delims[opener].num == 0 {
        unlink(d, o);
        remove_delimiter(p, opener);
    }
    guard p.delims[closer].num == 0 else { return closer; }
    unlink(d, c);
    let next = p.delims[closer].next;
    remove_delimiter(p, closer);
    return next;
}

fn find_opener(p: Inl&, closer: i64, bottom: i64, stack_bottom: i64) -> i64 {
    let c = p.delims[closer];
    var o = c.prev;
    while o >= 0 && o != stack_bottom && o != bottom {
        let od = p.delims[o];
        let odd = (c.can_open || od.can_close) && c.orig % 3 != 0 && (od.orig + c.orig) % 3 == 0;
        if od.cc == c.cc && od.can_open && !odd { return o; }
        o = od.prev;
    }
    return -1;
}

fn process_emphasis(d: Doc&, p: Inl&, stack_bottom: i64) {
    var bottoms = [stack_bottom; 18];
    var closer = p.delim_top;
    while closer >= 0 && p.delims[closer].prev != stack_bottom { closer = p.delims[closer].prev; }
    while closer >= 0 {
        guard p.delims[closer].can_close else {
            closer = p.delims[closer].next;
            continue;
        }
        let slot = bottom_index(p.delims[closer]);
        let opener = find_opener(p, closer, bottoms[slot], stack_bottom);
        let old = closer;
        if opener < 0 {
            closer = p.delims[closer].next;
            bottoms[slot] = p.delims[old].prev;
            if !p.delims[old].can_open { remove_delimiter(p, old); }
        } else if p.delims[closer].cc == '~' {
            closer = insert_strike(d, p, opener, closer);
        } else {
            closer = insert_emph(d, p, opener, closer);
        }
    }
    while p.delim_top >= 0 && p.delim_top != stack_bottom { remove_delimiter(p, p.delim_top); }
}

import std;
import md.node;

struct Delim {
    cc: u8 = 0,
    num: i64 = 0,
    orig: i64 = 0,
    node: i64 = -1,
    prev: i64 = -1,
    next: i64 = -1,
    can_open: bool = false,
    can_close: bool = false,
}

struct Bracket {
    node: i64 = -1,
    prev: i64 = -1,
    prev_delim: i64 = -1,
    index: i64 = 0,
    image: bool = false,
    active: bool = true,
    bracket_after: bool = false,
}

struct Inl {
    at: i64 = 0,
    len: i64 = 0,
    pos: i64 = 0,
    delim_top: i64 = -1,
    bracket_top: i64 = -1,
    delims: Delim[>..]&,
    brackets: Bracket[>..]&,
}

fn subject(d: Doc&, p: Inl&) -> const u8[:] { d.text[p.at..p.at + p.len] }

fn peek_at(d: Doc&, p: Inl&, i: i64) -> i64 { if i < p.len { d.text[p.at + i] } else { -1 } }

fn add_text(d: Doc&, p: Inl&, parent: i64, from: i64, to: i64) -> i64 {
    let n = new_node(d, Kind.Text, 0, 0);
    d.nodes[n].content = Span { at: p.at + from, len: to - from };
    append_child(d, parent, n);
    return n;
}

fn add_leaf(d: Doc&, parent: i64, kind: Kind, content: Span) -> i64 {
    let n = new_node(d, kind, 0, 0);
    d.nodes[n].content = content;
    append_child(d, parent, n);
    return n;
}

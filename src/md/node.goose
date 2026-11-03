import std;
import dictionary;

enum Kind {
    Document,
    FrontMatter,
    BlockQuote,
    Alert,
    List,
    Item,
    Paragraph,
    Heading,
    ThematicBreak,
    CodeBlock,
    HtmlBlock,
    Table,
    TableRow,
    TableCell,
    Text,
    SoftBreak,
    LineBreak,
    Code,
    Emph,
    Strong,
    Strike,
    Link,
    Image,
    HtmlInline,
}

struct Span { at: i64 = 0, len: i64 = 0 }

struct ListData {
    ordered: bool = false,
    bullet: u8 = 0,
    delim: u8 = 0,
    start: i64 = 0,
    tight: bool = true,
    marker_offset: i64 = 0,
    padding: i64 = 0,
}

struct Node {
    kind: Kind,
    parent: i64 = -1,
    first: i64 = -1,
    last: i64 = -1,
    prev: i64 = -1,
    next: i64 = -1,
    open: bool = true,
    line: i64 = 0,
    col: i64 = 0,
    end_line: i64 = 0,
    end_col: i64 = 0,
    content: Span,
    info: Span,
    title: Span,
    level: i64 = 0,
    list: ListData,
    fenced: bool = false,
    fence_char: u8 = 0,
    fence_len: i64 = 0,
    fence_offset: i64 = 0,
    html_type: i64 = 0,
    task: i64 = 0,
    align: u8 = 0,
    header: bool = false,
    visited: bool = false,
    src: i64 = -1,
}

struct Opts {
    table: bool = false,
    strike: bool = false,
    autolink: bool = false,
    tagfilter: bool = false,
    tasklist: bool = false,
    gfm_html: bool = false,
    front_matter: bool = false,
    alerts: bool = false,
}

fn gfm_opts() -> Opts {
    Opts {
        table: true,
        strike: true,
        autolink: true,
        tagfilter: true,
        tasklist: true,
        gfm_html: true,
        front_matter: true,
        alerts: true,
    }
}

struct Ref { label: Span, dest: Span, title: Span, chain: i64 = -1, line: i64 = 0, used: bool = false }

struct Doc {
    nodes: Node[>..]&,
    text: u8[>..]&,
    refs: Ref[>..]&,
    ref_index: dictionary<u64, i64>&,
    line_cols: i64[>..]&,
    opts: Opts,
}

fn new_node(d: Doc&, kind: Kind, line: i64, col: i64) -> i64 {
    let id = d.nodes.len;
    d.nodes.push(Node { kind: kind, line: line, col: col, .. });
    return id;
}

fn append_child(d: Doc&, parent: i64, child: i64) {
    let last = d.nodes[parent].last;
    d.nodes[child].parent = parent;
    d.nodes[child].prev = last;
    d.nodes[child].next = -1;
    if last >= 0 { d.nodes[last].next = child; } else { d.nodes[parent].first = child; }
    d.nodes[parent].last = child;
}

fn unlink(d: Doc&, n: i64) {
    let parent = d.nodes[n].parent;
    let prev = d.nodes[n].prev;
    let next = d.nodes[n].next;
    if prev >= 0 { d.nodes[prev].next = next; } else if parent >= 0 { d.nodes[parent].first = next; }
    if next >= 0 { d.nodes[next].prev = prev; } else if parent >= 0 { d.nodes[parent].last = prev; }
    d.nodes[n].parent = -1;
    d.nodes[n].prev = -1;
    d.nodes[n].next = -1;
}

fn insert_after(d: Doc&, at: i64, n: i64) {
    unlink(d, n);
    let parent = d.nodes[at].parent;
    let next = d.nodes[at].next;
    d.nodes[n].parent = parent;
    d.nodes[n].prev = at;
    d.nodes[n].next = next;
    d.nodes[at].next = n;
    if next >= 0 { d.nodes[next].prev = n; } else if parent >= 0 { d.nodes[parent].last = n; }
}

fn insert_before(d: Doc&, at: i64, n: i64) {
    unlink(d, n);
    let parent = d.nodes[at].parent;
    let prev = d.nodes[at].prev;
    d.nodes[n].parent = parent;
    d.nodes[n].prev = prev;
    d.nodes[n].next = at;
    d.nodes[at].prev = n;
    if prev >= 0 { d.nodes[prev].next = n; } else if parent >= 0 { d.nodes[parent].first = n; }
}

fn put_text(d: Doc&, s: const u8[:]) -> Span {
    let at = d.text.len;
    d.text.append(s);
    return Span { at: at, len: s.len };
}

fn text_of(d: Doc&, s: Span) -> const u8[:] { d.text[s.at..s.at + s.len] }

fn is_container(k: Kind) -> bool {
    match k {
        Document, BlockQuote, Alert, List, Item, Paragraph, Heading, Table, TableRow, TableCell, Emph, Strong,
        Strike, Link, Image => true,
        _ => false,
    }
}

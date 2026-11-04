import std;
import md.node;
import md.tree;

fn is_flow(k: Kind) -> bool { k == Kind.Text || k == Kind.SoftBreak }

fn put_collapsed(out: u8[>..]&, d: Doc&, first: i64, last: i64, depth: i64) {
    var s: u8[>..] = [];
    var k = first;
    loop {
        if d.nodes[k].kind == Kind.Text { s.append(text_of(d, d.nodes[k].content)); } else { s.push(' '); }
        if k == last { break; }
        k = d.nodes[k].next;
    }
    var flat: u8[>..] = [];
    for c in s {
        let blank = c == ' ' || c == '\t' || c == '\n';
        guard !blank || flat.len == 0 || flat[flat.len - 1] != ' ';
        flat.push(if blank { ' ' } else { c });
    }
    guard flat.len > 0;
    push_n(out, ' ', depth * 2);
    out.append("text ");
    quote(out, flat);
    out.push('\n');
}

fn flow_end(d: Doc&, n: i64) -> i64 {
    var k = n;
    while d.nodes[k].next >= 0 && is_flow(d.nodes[d.nodes[k].next].kind) { k = d.nodes[k].next; }
    return k;
}

fn canon_attrs(out: u8[>..]&, d: Doc&, n: i64) {
    let node = d.nodes[n];
    if node.kind == Kind.List && !node.list.ordered {
        out.append(if node.list.tight { " bullet tight" } else { " bullet loose" });
    } else if node.kind == Kind.CodeBlock {
        if node.info.len > 0 { attr(out, d, "info", node.info); }
        out.push(' ');
        quote(out, text_of(d, node.content));
    } else {
        node_attrs(out, d, n);
    }
}

fn canon_node(out: u8[>..]&, d: Doc&, n: i64, depth: i64) -> i64 {
    guard !is_flow(d.nodes[n].kind) else {
        let last = flow_end(d, n);
        put_collapsed(out, d, n, last, depth);
        return last;
    }
    push_n(out, ' ', depth * 2);
    out.append(kind_name(d.nodes[n].kind));
    canon_attrs(out, d, n);
    out.push('\n');
    return n;
}

fn canon_tree(d: Doc&, out: u8[>..]&) {
    var n = 0;
    var depth = 0;
    loop {
        n = canon_node(out, d, n, depth);
        if d.nodes[n].first >= 0 {
            n = d.nodes[n].first;
            depth++;
            continue;
        }
        while n != 0 && d.nodes[n].next < 0 {
            n = d.nodes[n].parent;
            depth--;
        }
        if n == 0 { break; }
        n = d.nodes[n].next;
    }
}

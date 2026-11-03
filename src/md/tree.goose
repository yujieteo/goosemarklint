import std;
import md.node;

fn kind_name(k: Kind) -> const u8[:] {
    match k {
        Document => "document",
        FrontMatter => "front_matter",
        BlockQuote => "block_quote",
        Alert => "alert",
        List => "list",
        Item => "item",
        Paragraph => "paragraph",
        Heading => "heading",
        ThematicBreak => "thematic_break",
        CodeBlock => "code_block",
        HtmlBlock => "html_block",
        Table => "table",
        TableRow => "table_row",
        TableCell => "table_cell",
        Text => "text",
        SoftBreak => "softbreak",
        LineBreak => "linebreak",
        Code => "code",
        Emph => "emph",
        Strong => "strong",
        Strike => "strikethrough",
        Link => "link",
        Image => "image",
        HtmlInline => "html_inline",
    }
}

fn is_block(k: Kind) -> bool {
    match k {
        Document, FrontMatter, BlockQuote, Alert, List, Item, Paragraph, Heading, ThematicBreak, CodeBlock, HtmlBlock,
        Table, TableRow, TableCell => true,
        _ => false,
    }
}

fn quote(out: u8[>..]&, s: const u8[:]) {
    let hex = "0123456789abcdef";
    out.push('"');
    for c in s {
        if c == '"' || c == '\\' {
            out.push('\\');
            out.push(c);
        } else if c == '\n' {
            out.append("\\n");
        } else if c == '\t' {
            out.append("\\t");
        } else if c < 0x20 || c == 0x7F {
            out.append("\\x");
            out.push(hex[c >> 4]);
            out.push(hex[c & 15]);
        } else {
            out.push(c);
        }
    }
    out.push('"');
}

fn attr(out: u8[>..]&, d: Doc&, name: const u8[:], s: Span) {
    format(out, " ", name, "=");
    quote(out, text_of(d, s));
}

fn list_attrs(out: u8[>..]&, l: ListData) {
    if l.ordered {
        format(out, " ordered start=", l.start, " delim=");
        out.push(l.delim);
    } else {
        out.append(" bullet=");
        out.push(l.bullet);
    }
    out.append(if l.tight { " tight" } else { " loose" });
}

fn align_name(a: u8) -> const u8[:] {
    match a {
        'l' => " align=left",
        'c' => " align=center",
        'r' => " align=right",
        _ => "",
    }
}

fn node_attrs(out: u8[>..]&, d: Doc&, n: i64) {
    let node = d.nodes[n];
    match node.kind {
        Heading => format(out, " level=", node.level),
        List => list_attrs(out, node.list),
        Item => if node.task > 0 { out.append(if node.task == 2 { " task=done" } else { " task=open" }); },
        Alert => attr(out, d, "type", node.info),
        CodeBlock => if node.fenced { attr(out, d, "info", node.info); },
        HtmlBlock => format(out, " type=", node.html_type),
        TableRow => if node.header { out.append(" header"); },
        TableCell => out.append(align_name(node.align)),
        Link, Image => {
            attr(out, d, "dest", node.info);
            if node.title.len > 0 { attr(out, d, "title", node.title); }
        },
        _ => {},
    }
    match node.kind {
        FrontMatter, CodeBlock, HtmlBlock, Text, Code, HtmlInline => {
            out.push(' ');
            quote(out, text_of(d, node.content));
        },
        _ => {},
    }
}

fn print_node(out: u8[>..]&, d: Doc&, n: i64, depth: i64) {
    let node = d.nodes[n];
    guard node.kind != Kind.Text || node.content.len > 0;
    push_n(out, ' ', depth * 2);
    out.append(kind_name(node.kind));
    if is_block(node.kind) { format(out, " [", node.line, ":", node.col, "-", node.end_line, ":", node.end_col, "]"); }
    node_attrs(out, d, n);
    out.push('\n');
}

fn print_tree(d: Doc&, out: u8[>..]&) {
    var n = 0;
    var depth = 0;
    loop {
        print_node(out, d, n, depth);
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

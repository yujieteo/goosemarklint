import std;
import md.node;
import md.chars;
import md.entity;
import md.html_scan;

struct Html {
    out: u8[>..]&,
    disable: i64 = 0,
    in_header: bool = false,
    need_tbody: bool = false,
}

let FILTERED_TAGS = ["title", "textarea", "style", "xmp", "iframe", "noembed", "noframes", "script", "plaintext"];

fn cr(h: Html&) { if h.out.len > 0 && h.out[h.out.len - 1] != '\n' { h.out.push('\n'); } }

fn tag(h: Html&, s: const u8[:]) { if h.disable == 0 { h.out.append(s); } }

fn esc(h: Html&, d: Doc&, s: Span) { escape_html_into(h.out, d.text[s.at..s.at + s.len]); }

fn is_filtered_tag(s: const u8[:]) -> bool {
    guard s.len >= 3 && s[0] == '<' else { return false; }
    let at = if s[1] == '/' { 2 } else { 1 };
    for name in FILTERED_TAGS {
        guard starts_lower(s, at, name);
        let end = at + name.len;
        guard end < s.len;
        if is_ascii_space(s[end]) || s[end] == '>' { return true; }
        if s[end] == '/' && end + 1 < s.len && s[end + 1] == '>' { return true; }
    }
    return false;
}

fn raw_html(h: Html&, d: Doc&, s: Span) {
    let text = d.text[s.at..s.at + s.len];
    guard d.opts.tagfilter else {
        h.out.append(text);
        return;
    }
    for i in text.len {
        if text[i] == '<' && is_filtered_tag(text[i..]) { h.out.append("&lt;"); } else { h.out.push(text[i]); }
    }
}

fn in_tight_list(d: Doc&, n: i64) -> bool {
    let parent = d.nodes[n].parent;
    guard parent >= 0 else { return false; }
    let grand = d.nodes[parent].parent;
    grand >= 0 && d.nodes[grand].kind == Kind.List && d.nodes[grand].list.tight
}

fn code_block(h: Html&, d: Doc&, n: i64) {
    let info = d.nodes[n].info;
    let words = d.text[info.at..info.at + info.len];
    var end = 0;
    while end < words.len && !is_ascii_space(words[end]) { end++; }
    cr(h);
    h.out.append("<pre><code");
    if end > 0 {
        h.out.append(" class=\"language-");
        escape_html_into(h.out, words[..end]);
        h.out.append("\"");
    }
    h.out.append(">");
    esc(h, d, d.nodes[n].content);
    h.out.append("</code></pre>");
    cr(h);
}

fn list_open(h: Html&, d: Doc&, n: i64) {
    cr(h);
    let l = d.nodes[n].list;
    if !l.ordered {
        h.out.append("<ul>");
    } else if l.start != 1 {
        format(h.out, "<ol start=\"", l.start, "\">");
    } else {
        h.out.append("<ol>");
    }
    cr(h);
}

fn item_open(h: Html&, d: Doc&, n: i64) {
    cr(h);
    h.out.append("<li>");
    let task = d.nodes[n].task;
    if task == 1 { h.out.append("<input disabled=\"\" type=\"checkbox\"> "); }
    if task == 2 { h.out.append("<input checked=\"\" disabled=\"\" type=\"checkbox\"> "); }
}

fn alert_open(h: Html&, d: Doc&, n: i64) {
    let info = d.nodes[n].info;
    let name = d.text[info.at..info.at + info.len];
    cr(h);
    h.out.append("<div class=\"markdown-alert markdown-alert-");
    h.out.append(name);
    h.out.append("\">\n<p class=\"markdown-alert-title\">");
    h.out.push(name[0] - 32);
    h.out.append(name[1..]);
    h.out.append("</p>\n");
}

fn link_open(h: Html&, d: Doc&, n: i64) {
    guard h.disable == 0;
    h.out.append("<a href=\"");
    esc(h, d, d.nodes[n].info);
    h.out.append("\"");
    if d.nodes[n].title.len > 0 {
        h.out.append(" title=\"");
        esc(h, d, d.nodes[n].title);
        h.out.append("\"");
    }
    h.out.append(">");
}

fn image(h: Html&, d: Doc&, n: i64, entering: bool) {
    if entering {
        if h.disable == 0 {
            h.out.append("<img src=\"");
            esc(h, d, d.nodes[n].info);
            h.out.append("\" alt=\"");
        }
        h.disable++;
        return;
    }
    h.disable--;
    guard h.disable == 0;
    if d.nodes[n].title.len > 0 {
        h.out.append("\" title=\"");
        esc(h, d, d.nodes[n].title);
    }
    h.out.append("\" />");
}

fn table_row(h: Html&, d: Doc&, n: i64, entering: bool) {
    let header = d.nodes[n].header;
    if entering {
        cr(h);
        if header {
            h.in_header = true;
            h.out.append("<thead>\n");
        } else if !h.need_tbody {
            h.out.append("<tbody>\n");
            h.need_tbody = true;
        }
        h.out.append("<tr>");
        return;
    }
    cr(h);
    h.out.append("</tr>");
    if header {
        h.out.append("\n</thead>");
        h.in_header = false;
    }
}

fn table_cell(h: Html&, d: Doc&, n: i64, entering: bool) {
    let name = if h.in_header { "th" } else { "td" };
    if !entering {
        format(h.out, "</", name, ">");
        return;
    }
    cr(h);
    format(h.out, "<", name);
    match d.nodes[n].align {
        'l' => h.out.append(" align=\"left\""),
        'c' => h.out.append(" align=\"center\""),
        'r' => h.out.append(" align=\"right\""),
        _ => {},
    }
    h.out.append(">");
}

fn table(h: Html&, entering: bool) {
    cr(h);
    if entering {
        h.out.append("<table>");
        h.need_tbody = false;
        return;
    }
    if h.need_tbody { h.out.append("</tbody>\n"); }
    h.need_tbody = false;
    h.out.append("</table>");
    cr(h);
}

fn wrap(h: Html&, entering: bool, open: const u8[:], close: const u8[:]) { tag(h, if entering { open } else { close }); }

fn block_wrap(h: Html&, entering: bool, open: const u8[:], close: const u8[:]) {
    cr(h);
    h.out.append(if entering { open } else { close });
    cr(h);
}

fn paragraph(h: Html&, d: Doc&, n: i64, entering: bool) {
    guard !in_tight_list(d, n);
    if entering { cr(h); }
    h.out.append(if entering { "<p>" } else { "</p>" });
    if !entering { cr(h); }
}

fn heading(h: Html&, d: Doc&, n: i64, entering: bool) {
    if entering {
        cr(h);
        format(h.out, "<h", d.nodes[n].level, ">");
    } else {
        format(h.out, "</h", d.nodes[n].level, ">");
        cr(h);
    }
}

fn render_node(h: Html&, d: Doc&, n: i64, entering: bool) {
    match d.nodes[n].kind {
        Document, FrontMatter => {},
        BlockQuote => block_wrap(h, entering, "<blockquote>", "</blockquote>"),
        Alert => if entering { alert_open(h, d, n); } else { block_wrap(h, false, "", "</div>"); },
        List => if entering { list_open(h, d, n); } else { block_wrap(h, false, "", if d.nodes[n].list.ordered { "</ol>" } else { "</ul>" }); },
        Item => if entering { item_open(h, d, n); } else { h.out.append("</li>"); cr(h); },
        Paragraph => paragraph(h, d, n, entering),
        Heading => heading(h, d, n, entering),
        ThematicBreak => block_wrap(h, true, "<hr />", ""),
        CodeBlock => code_block(h, d, n),
        HtmlBlock => { cr(h); raw_html(h, d, d.nodes[n].content); cr(h); },
        Table => table(h, entering),
        TableRow => table_row(h, d, n, entering),
        TableCell => table_cell(h, d, n, entering),
        Text => esc(h, d, d.nodes[n].content),
        SoftBreak => h.out.push('\n'),
        LineBreak => { tag(h, "<br />"); cr(h); },
        Code => { tag(h, "<code>"); esc(h, d, d.nodes[n].content); tag(h, "</code>"); },
        Emph => wrap(h, entering, "<em>", "</em>"),
        Strong => if !(d.opts.gfm_html && d.nodes[d.nodes[n].parent].kind == Kind.Strong) { wrap(h, entering, "<strong>", "</strong>"); },
        Strike => wrap(h, entering, "<del>", "</del>"),
        Link => if entering { link_open(h, d, n); } else { tag(h, "</a>"); },
        Image => image(h, d, n, entering),
        HtmlInline => if h.disable == 0 { raw_html(h, d, d.nodes[n].content); },
    }
}

fn render_html(d: Doc&, out: u8[>..]&) {
    var h = Html { out: out, .. };
    var n = 0;
    var entering = true;
    loop {
        render_node(h, d, n, entering);
        if entering && is_container(d.nodes[n].kind) {
            let first = d.nodes[n].first;
            if first >= 0 {
                n = first;
                continue;
            }
            render_node(h, d, n, false);
        }
        if n == 0 { break; }
        let next = d.nodes[n].next;
        if next >= 0 {
            n = next;
            entering = true;
        } else {
            n = d.nodes[n].parent;
            entering = false;
        }
    }
}

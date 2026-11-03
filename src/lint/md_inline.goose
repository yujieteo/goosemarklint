import std;
import md.node;
import md.chars;
import lint.context;
import lint.prose;
import lint.md_base;
import lint.md_links;

let VAGUE_LINK_TEXTS = ["click here", "here", "link", "more"];
let EMPHASIS_MARKERS = ["*", "**", "***", "_", "__", "___"];

struct InlineStyles { emph: u8 = 0, strong: u8 = 0 }

fn node_pos(L: Lint&, p: Prose&, n: i64) -> i64 {
    var k = n;
    while L.d.nodes[k].src < 0 && L.d.nodes[k].first >= 0 { k = L.d.nodes[k].first; }
    let node = L.d.nodes[k];
    return content_pos(p, if node.src >= 0 { node.src } else { node.content.at });
}

fn is_ws(c: u8) -> bool { c == ' ' || c == '\t' || c == '\n' || c == '\r' }

fn tag_end(t: const u8[:]) -> i64 {
    let e = position(t, '>');
    return if e < 0 { t.len } else { e + 1 };
}

fn check_img_alt(L: Lint&, tag: const u8[:], at: i64) {
    let alt, has_alt = attr_value(tag, "alt");
    let hidden, has_hidden = attr_value(tag, "aria-hidden");
    guard !has_alt && !(has_hidden && lower_equal(hidden, "true"));
    report(L, at, "MD045", "image has no alternative text: add an alt attribute");
}

fn check_html_text(L: Lint&, p: Prose&, t: const u8[:], at: i64) {
    var tags: i64[>..] = [];
    each_open_tag(t, tags);
    for i in tags {
        let tag = t[i..i + tag_end(t[i..])];
        let name = open_tag_name(tag);
        let pos = content_pos(p, at + i);
        report(L, pos, "MD033", str("HTML element <", name, ">: use Markdown"));
        if lower_equal(name, "img") { check_img_alt(L, tag, pos); }
    }
}

fn close_name(t: const u8[:]) -> const u8[:] { if starts_with(t, "</") { open_tag_name(t[1..]) } else { "" } }

fn inside_html_pair(L: Lint&, n: i64) -> bool {
    var k = L.d.nodes[n].prev;
    while k >= 0 {
        let name = open_tag_name(text_of(L.d, L.d.nodes[k].content));
        if L.d.nodes[k].kind == Kind.HtmlInline && name.len > 0 {
            var j = L.d.nodes[n].next;
            while j >= 0 {
                if L.d.nodes[j].kind == Kind.HtmlInline && lower_equal(close_name(text_of(L.d, L.d.nodes[j].content)), name) { return true; }
                j = L.d.nodes[j].next;
            }
        }
        k = L.d.nodes[k].prev;
    }
    return false;
}

fn text_edge(L: Lint&, n: i64, end: bool) -> bool {
    guard n >= 0 else { return false; }
    let node = L.d.nodes[n];
    guard node.kind != Kind.SoftBreak && node.kind != Kind.LineBreak else { return true; }
    guard node.kind == Kind.Text && node.content.len > 0 else { return false; }
    let t = text_of(L.d, node.content);
    return is_ws(if end { t[t.len - 1] } else { t[0] });
}

fn link_words(L: Lint&, link: i64, out: u8[>..]&) -> bool {
    var n = L.d.nodes[link].first;
    while n >= 0 {
        let k = L.d.nodes[n].kind;
        guard k != Kind.Code && k != Kind.HtmlInline else { return false; }
        if k == Kind.Text {
            var space = true;
            for c in text_of(L.d, L.d.nodes[n].content) {
                let word = is_alnum(c);
                if word && space && out.len > 0 { out.push(' '); }
                if word { out.push(lower_ascii(c)); }
                space = !word;
            }
            out.push(' ');
        }
        n = next_in(L.d, n, link);
    }
    return true;
}

fn check_link_text(L: Lint&, n: i64, at: i64) {
    let node = L.d.nodes[n];
    if text_edge(L, node.first, false) { report(L, at, "MD039", "space at the start of the link text: delete it"); }
    if text_edge(L, node.last, true) { report(L, at, "MD039", "space at the end of the link text: delete it"); }
    let dest = text_of(L.d, node.info);
    if dest.len == 0 || dest == "#" { report(L, at, "MD042", "link has no destination: add a URL"); }
    var words: u8[>..] = [];
    guard link_words(L, n, words);
    let t = trim(words);
    guard position(VAGUE_LINK_TEXTS, t) >= 0;
    report(L, at, "MD059", str("link text \"", t, "\" does not say where the link goes: describe the target"));
}

fn check_link(L: Lint&, p: Prose&, a: Anchors&, n: i64) {
    let node = L.d.nodes[n];
    let at = node_pos(L, p, n);
    guard node.src >= 0 else {
        if !inside_html_pair(L, n) { report(L, at, "MD034", "bare URL: put it in <> or in a link"); }
        return;
    };
    guard L.d.text[node.src] == '[';
    check_link_text(L, n, at);
    check_fragment(L, a, at, text_of(L.d, node.info));
}

fn check_image(L: Lint&, p: Prose&, n: i64) {
    let empty = all_text_empty(L, n);
    guard empty;
    report(L, node_pos(L, p, n), "MD045", "image has no alternative text: add it in the brackets");
}

fn all_text_empty(L: Lint&, n: i64) -> bool {
    var k = L.d.nodes[n].first;
    while k >= 0 {
        guard L.d.nodes[k].kind == Kind.Text && L.d.nodes[k].content.len == 0 else { return false; }
        k = next_in(L.d, k, n);
    }
    return true;
}

fn code_raw(L: Lint&, n: i64) -> const u8[:] {
    let s = L.d.text;
    let at = L.d.nodes[n].src;
    var ticks = 0;
    while at + ticks < s.len && s[at + ticks] == '`' { ticks++; }
    var i = at + ticks;
    while i < s.len {
        var j = i;
        while j < s.len && s[j] == '`' { j++; }
        if j - i == ticks { return s[at + ticks..i]; }
        i = max(j, i + 1);
    }
    return s[at + ticks..at + ticks];
}

fn check_code_space(L: Lint&, p: Prose&, n: i64) {
    let raw = code_raw(L, n);
    let solid = any(raw) { !is_ws(it) };
    guard solid;
    let padded = raw.len >= 2 && is_ws(raw[0]) && is_ws(raw[raw.len - 1]);
    let data = if padded { raw[1..raw.len - 1] } else { raw };
    var lead = 0;
    while lead < data.len && is_ws(data[lead]) { lead++; }
    var trail = 0;
    while trail < data.len - lead && is_ws(data[data.len - 1 - trail]) { trail++; }
    let start = lead - (if lead > 0 && data[lead] == '`' && !padded { 1 } else { 0 });
    let end = trail - (if trail > 0 && data[data.len - 1 - trail] == '`' && !padded { 1 } else { 0 });
    if start > 0 { report(L, node_pos(L, p, n), "MD038", "space at the start of the code span: delete it"); }
    if end > 0 { report(L, node_pos(L, p, n), "MD038", "space at the end of the code span: delete it"); }
}

fn end_pos(L: Lint&, p: Prose&, n: i64) -> i64 {
    var k = n;
    while L.d.nodes[k].last >= 0 { k = L.d.nodes[k].last; }
    let c = L.d.nodes[k].content;
    guard L.d.nodes[k].kind == Kind.Text && c.len > 0 else { return node_pos(L, p, n); }
    return content_pos(p, c.at + c.len - 1) + 1;
}

fn check_emphasis_style(L: Lint&, p: Prose&, n: i64, want: u8&, rule: const u8[:]) {
    let c = L.d.text[L.d.nodes[n].src];
    if want == 0 { want = c; }
    guard c != want;
    let at = node_pos(L, p, n);
    let s = source_of(L);
    guard !(want == '_' && at > 0 && (is_alnum(s[at - 1]) || s[at - 1] == '_'));
    let name = if rule == "MD049" { "emphasis" } else { "strong" };
    let msg = str(name, " marker \"", [c], "\": use \"", [want], "\", as the first ", name);
    report(L, at, rule, msg);
    report(L, end_pos(L, p, n), rule, msg);
}

import std;
import md.node;
import lint.context;
import lint.prose;
import lint.md_base;
import lint.md_lines;

let STYLE_NAMES = ["atx", "atx_closed", "setext"];
let ATX = 0;
let ATX_CLOSED = 1;
let SETEXT = 2;
let HEADING_PUNCT = [".", ",", ";", ":", "!", "\xE3\x80\x82", "\xEF\xBC\x8C", "\xEF\xBC\x9B", "\xEF\xBC\x9A", "\xEF\xBC\x81"];
let EMPHASIS_PUNCT = [".", ",", ";", ":", "!", "?", "\xE3\x80\x82", "\xEF\xBC\x8C", "\xEF\xBC\x9B", "\xEF\xBC\x9A", "\xEF\xBC\x81", "\xEF\xBC\x9F"];

fn heading_line(L: Lint&, h: i64) -> const u8[:] { line_text(L, L.d.nodes[h].line)[max(L.d.nodes[h].col, 1) - 1..] }

fn heading_style(L: Lint&, h: i64) -> i64 {
    guard L.d.nodes[h].end_line == L.d.nodes[h].line else { return SETEXT; }
    let t = trim_end(heading_line(L, h));
    let o = hash_run(t);
    var e = t.len;
    while e > o && t[e - 1] == '#' { e--; }
    return if e < t.len && e > o && (t[e - 1] == ' ' || t[e - 1] == '\t') { ATX_CLOSED } else { ATX };
}

fn check_increment(L: Lint&, hs: const i64[:]) {
    var prev = if has_front_matter_title(L) { 1 } else { 99 };
    for h in hs {
        let level = L.d.nodes[h].level;
        if level > prev + 1 { report_node(L, h, "MD001", str("heading level ", level, " after level ", prev, ": use level ", prev + 1)); }
        prev = level;
    }
}

fn check_style(L: Lint&, hs: const i64[:]) {
    var want = -1;
    for h in hs {
        let style = heading_style(L, h);
        if want < 0 { want = style; }
        if style != want {
            report_node(L, h, "MD003", str("heading style ", STYLE_NAMES[style], ": use ", STYLE_NAMES[want], ", as the first heading"));
        }
    }
}

fn space_run(t: const u8[:], i: i64) -> i64 {
    var j = i;
    while j < t.len && (t[j] == ' ' || t[j] == '\t') { j++; }
    return j - i;
}

fn check_atx_spaces(L: Lint&, h: i64, style: i64) {
    let t = trim_end(heading_line(L, h));
    let o = hash_run(t);
    let left = space_run(t, o);
    guard o + left < t.len;
    let at = node_offset(L, h);
    let rule = if style == ATX { "MD019" } else { "MD021" };
    if left > 1 { report(L, at + o + 1, rule, str(left, " spaces after the opening hashes: use 1 space")); }
    guard style == ATX_CLOSED;
    var e = t.len;
    while e > o && t[e - 1] == '#' { e--; }
    var k = e;
    while k > o && (t[k - 1] == ' ' || t[k - 1] == '\t') { k--; }
    if e - k > 1 { report(L, at + k + 1, rule, str(e - k, " spaces before the closing hashes: use 1 space")); }
}

fn check_blank_around(L: Lint&, h: i64) {
    let node = L.d.nodes[h];
    if !blank_at(L, node.line - 1) { report_node(L, h, "MD022", "heading has no blank line above it: add one"); }
    if !blank_at(L, node.end_line + 1) { report_node(L, h, "MD022", "heading has no blank line below it: add one"); }
}

fn check_start_left(L: Lint&, h: i64) {
    let node = L.d.nodes[h];
    let parent = L.d.nodes[node.parent].kind;
    let before = line_text(L, node.line)[..max(node.col, 1) - 1];
    let indent = if parent == Kind.Document {
        before.len
    } else if parent == Kind.BlockQuote || parent == Kind.Alert {
        max(before.len - rfind(before, ">") - 2, 0)
    } else {
        0
    };
    guard indent > 0;
    report_at(L, node.line, 1, "MD023", "heading does not start at the left edge: delete the indent");
}

fn heading_text(L: Lint&, h: i64) -> u8[>..] {
    var out: u8[>..] = [];
    for c in text_of(L.d, L.d.nodes[h].content) { out.push(if c == '\n' { ' ' } else { c }); }
    let t = trim(out);
    return str(t);
}

fn check_duplicates(L: Lint&, hs: const i64[:]) {
    for h, i in hs {
        let t = heading_text(L, h);
        let copy = any(hs[..i]) { heading_text(L, it) == t };
        if copy { report_node(L, h, "MD024", str("heading \"", t, "\" is a copy of an earlier heading: change the text")); }
    }
}

fn is_comment_block(L: Lint&, n: i64) -> bool {
    let node = L.d.nodes[n];
    return node.kind == Kind.HtmlBlock && starts_with(trim(text_of(L.d, node.content)), "<!--");
}

fn first_block(L: Lint&) -> i64 {
    var n = L.d.nodes[0].first;
    while n >= 0 && (L.d.nodes[n].kind == Kind.FrontMatter || is_comment_block(L, n)) { n = L.d.nodes[n].next; }
    return n;
}

fn check_single_title(L: Lint&, hs: const i64[:]) {
    let titled = has_front_matter_title(L);
    var top: i64[>..] = [];
    for h in hs { if L.d.nodes[h].level == 1 { top.push(h); } }
    guard top.len > 0 && (titled || first_block(L) == top[0]);
    for h, i in top {
        if titled || i > 0 { report_node(L, h, "MD025", "more than one level 1 heading: keep one title"); }
    }
}

fn html_heading_level(L: Lint&, n: i64) -> i64 {
    let t = trim(text_of(L.d, L.d.nodes[n].content));
    guard t.len >= 3 && t[0] == '<' && (t[1] == 'h' || t[1] == 'H') && t[2] >= '1' && t[2] <= '6' else { return 0; }
    guard t.len == 3 || position(" \t\n>/", t[3]) >= 0 else { return 0; }
    return t[2] - '0';
}

fn check_first_line(L: Lint&) {
    guard !has_front_matter_title(L);
    let n = first_block(L);
    guard n >= 0;
    let node = L.d.nodes[n];
    let level = if node.kind == Kind.Heading { node.level } else if node.kind == Kind.HtmlBlock { html_heading_level(L, n) } else { 0 };
    guard level != 1;
    report_line(L, node.line, "MD041", "first line is not a level 1 heading: start the file with a title");
}

fn trailing_punct(t: const u8[:], set: const u8[:][:]) -> i64 {
    var e = t.len;
    loop {
        let hit = find(set) { ends_with(t[..e], it) };
        guard hit else { break; }
        e -= hit.len;
    }
    return t.len - e;
}

fn is_entity_or_emoji_end(t: const u8[:]) -> bool {
    guard ends_with(t, ";") || ends_with(t, ":") else { return false; }
    let open = if ends_with(t, ";") { rfind(t, "&") } else { rfind(t[..t.len - 1], ":") };
    guard open >= 0 && open + 2 < t.len else { return false; }
    return all(t[open + 1..t.len - 1]) { (it >= 'a' && it <= 'z') || (it >= 'A' && it <= 'Z') || (it >= '0' && it <= '9') || it == '#' || it == '_' || it == '-' };
}

fn check_trailing_punct(L: Lint&, p: Prose&, h: i64) {
    let c = L.d.nodes[h].content;
    let t = trim_end(text_of(L.d, c));
    let n = trailing_punct(t, HEADING_PUNCT);
    guard n > 0 && !is_entity_or_emoji_end(t);
    map_block(L, p, h);
    report(L, content_pos(p, c.at + t.len - n), "MD026", str("heading ends with \"", t[t.len - n..], "\": delete the punctuation"));
}

fn check_emphasis_heading(L: Lint&, b: i64) {
    let para = L.d.nodes[b];
    guard para.parent == 0 && para.first >= 0 && para.first == para.last;
    let e = L.d.nodes[para.first];
    guard e.kind == Kind.Emph || e.kind == Kind.Strong;
    guard e.first >= 0 && e.first == e.last && L.d.nodes[e.first].kind == Kind.Text;
    let t = text_of(L.d, L.d.nodes[e.first].content);
    guard trailing_punct(t, EMPHASIS_PUNCT) == 0;
    report_node(L, b, "MD036", str("emphasis \"", t, "\" is used as a heading: use a heading"));
}

fn check_headings(L: Lint&, p: Prose&) {
    var hs: i64[>..] = [];
    var n = 0;
    while n >= 0 {
        let k = L.d.nodes[n].kind;
        if k == Kind.Heading { hs.push(n); }
        if k == Kind.Paragraph { check_emphasis_heading(L, n); }
        n = next_in(L.d, n, 0);
    }
    check_increment(L, hs);
    check_style(L, hs);
    check_duplicates(L, hs);
    check_single_title(L, hs);
    check_first_line(L);
    for h in hs {
        let style = heading_style(L, h);
        if style != SETEXT { check_atx_spaces(L, h, style); }
        check_blank_around(L, h);
        check_start_left(L, h);
        check_trailing_punct(L, p, h);
    }
}

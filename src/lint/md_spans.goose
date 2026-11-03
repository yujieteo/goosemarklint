import std;
import md.node;
import lint.context;
import lint.prose;
import lint.md_base;
import lint.md_links;
import lint.md_inline;

struct Run { marker: i64, at: i64 }

fn add_runs(L: Lint&, p: Prose&, n: i64, runs: Run[>..]&) {
    let c = L.d.nodes[n].content;
    let t = text_of(L.d, c);
    let s = source_of(L);
    var i = 0;
    while i < t.len {
        let ch = t[i];
        var j = i + 1;
        if ch == '*' || ch == '_' {
            while j < t.len && t[j] == ch { j++; }
            let at = content_pos(p, c.at + i);
            let m = position(EMPHASIS_MARKERS, t[i..j]);
            if m >= 0 && at < s.len && s[at] == ch && (at == 0 || s[at - 1] != '\\') { runs.push(Run { marker: m, at: at }); }
        }
        i = j;
    }
}

fn space_after(s: const u8[:], at: i64) -> bool {
    guard at < s.len && (s[at] == ' ' || s[at] == '\t') else { return false; }
    var j = at;
    while j < s.len && (s[j] == ' ' || s[j] == '\t') { j++; }
    return j < s.len && s[j] != '\n' && s[j] != '\r';
}

fn space_before(s: const u8[:], at: i64) -> i64 {
    guard at > 0 && (s[at - 1] == ' ' || s[at - 1] == '\t') else { return -1; }
    var j = at - 1;
    while j > 0 && (s[j - 1] == ' ' || s[j - 1] == '\t') { j--; }
    return if j > 0 && s[j - 1] != '\n' && s[j - 1] != '\r' { j } else { -1 };
}

fn check_emphasis_spaces(L: Lint&, p: Prose&, parent: i64) {
    var runs: Run[>..] = [];
    var k = L.d.nodes[parent].first;
    while k >= 0 {
        if L.d.nodes[k].kind == Kind.Text { add_runs(L, p, k, runs); }
        k = L.d.nodes[k].next;
    }
    let s = source_of(L);
    for m in EMPHASIS_MARKERS.len {
        var open = -1;
        for r in runs {
            guard r.marker == m;
            if open < 0 {
                open = r.at;
                continue;
            }
            let msg = str("space inside the emphasis marker \"", EMPHASIS_MARKERS[m], "\": delete it");
            if space_after(s, open + EMPHASIS_MARKERS[m].len) { report(L, open + EMPHASIS_MARKERS[m].len, "MD037", msg); }
            let before = space_before(s, r.at);
            if before >= 0 { report(L, before, "MD037", msg); }
            open = -1;
        }
    }
}

fn check_inline_block(L: Lint&, p: Prose&, a: Anchors&, st: InlineStyles&, b: i64) {
    map_block(L, p, b);
    check_emphasis_spaces(L, p, b);
    var n = L.d.nodes[b].first;
    while n >= 0 {
        let node = L.d.nodes[n];
        match node.kind {
            Emph => check_emphasis_style(L, p, n, st.emph, "MD049"),
            Strong => check_emphasis_style(L, p, n, st.strong, "MD050"),
            Code => check_code_space(L, p, n),
            Link => check_link(L, p, a, n),
            Image => check_image(L, p, n),
            HtmlInline => check_html_text(L, p, text_of(L.d, node.content), node.content.at),
            Text => check_reference_text(L, p, n),
            _ => {},
        }
        if node.kind == Kind.Emph || node.kind == Kind.Strong || node.kind == Kind.Strike || node.kind == Kind.Link { check_emphasis_spaces(L, p, n); }
        n = next_in(L.d, n, b);
    }
}

fn check_inlines(L: Lint&, p: Prose&) {
    var names: u8[>..] = [];
    var a = Anchors { names: names, .. };
    collect_anchors(L, a);
    var st = InlineStyles {};
    var n = 0;
    while n >= 0 {
        let node = L.d.nodes[n];
        let inline = node.kind == Kind.Paragraph || node.kind == Kind.Heading || node.kind == Kind.TableCell;
        if inline { check_inline_block(L, p, a, st, n); }
        if node.kind == Kind.HtmlBlock {
            map_block(L, p, n);
            check_html_text(L, p, text_of(L.d, node.content), node.content.at);
        }
        n = if inline { next_skip(L.d, n, 0) } else { next_in(L.d, n, 0) };
    }
    check_definitions(L);
}

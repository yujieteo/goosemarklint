import std;
import md.node;
import lint.context;
import lint.prose;

let LINE_TEXT = 0;
let LINE_FENCE = 1;
let LINE_CODE = 2;
let LINE_HTML = 3;
let LINE_FRONT = 4;

fn last_line(L: Lint&) -> i64 { L.lines.len - 1 }

fn line_text(L: Lint&, ln: i64) -> const u8[:] {
    let s = source_of(L);
    let at = L.lines[ln];
    var end = if ln + 1 < L.lines.len { L.lines[ln + 1] } else { s.len };
    while end > at && (s[end - 1] == '\n' || s[end - 1] == '\r') { end--; }
    return s[at..end];
}

fn mark_lines(L: Lint&, from: i64, to: i64, kind: i64) {
    for ln in max(from, 1)..min(to, last_line(L)) + 1 { L.kinds[ln] = kind; }
}

fn strip_prefix(s: const u8[:]) -> const u8[:] {
    var i = 0;
    while i < s.len && (s[i] == ' ' || s[i] == '\t' || s[i] == '>') { i++; }
    return s[i..];
}

fn is_closing_fence(L: Lint&, n: i64) -> bool {
    let node = L.d.nodes[n];
    guard node.end_line > node.line else { return false; }
    let t = strip_prefix(line_text(L, node.end_line));
    guard t.len >= node.fence_len else { return false; }
    return all(t[..node.fence_len]) { it == node.fence_char };
}

fn mark_code(L: Lint&, n: i64) {
    let node = L.d.nodes[n];
    mark_lines(L, node.line, node.end_line, LINE_CODE);
    guard node.fenced;
    L.kinds[node.line] = LINE_FENCE;
    if is_closing_fence(L, n) { L.kinds[node.end_line] = LINE_FENCE; }
}

fn index_kinds(L: Lint&) {
    for i in L.lines.len { L.kinds.push(LINE_TEXT); }
    var n = 0;
    while n >= 0 {
        let node = L.d.nodes[n];
        match node.kind {
            FrontMatter => mark_lines(L, node.line, node.end_line, LINE_FRONT),
            HtmlBlock => mark_lines(L, node.line, node.end_line, LINE_HTML),
            CodeBlock => mark_code(L, n),
            _ => {},
        }
        n = next_in(L.d, n, 0);
    }
}

fn is_code_line(L: Lint&, ln: i64) -> bool { L.kinds[ln] == LINE_FENCE || L.kinds[ln] == LINE_CODE }

fn is_markdown_line(L: Lint&, ln: i64) -> bool { L.kinds[ln] == LINE_TEXT }

fn without_comments(s: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    var t = s;
    loop {
        let start = find(t, "<!--");
        let end = find(t, "-->");
        if end >= 0 && (start < 0 || end < start) {
            t = t[end + 3..];
        } else if start >= 0 {
            out.append(t[..start]);
            guard end >= 0 else { return out; }
            t = t[end + 3..];
        } else {
            out.append(t);
            return out;
        }
    }
}

fn is_blank_md(s: const u8[:]) -> bool {
    let quiet = without_comments(s);
    return all(quiet) { it == ' ' || it == '\t' || it == '>' };
}

fn blank_at(L: Lint&, ln: i64) -> bool {
    guard ln >= 1 && ln <= last_line(L) && L.kinds[ln] != LINE_FRONT else { return true; }
    return is_blank_md(line_text(L, ln));
}

fn front_matter(L: Lint&) -> const u8[:] {
    let fm = L.d.nodes[0].first;
    guard fm >= 0 && L.d.nodes[fm].kind == Kind.FrontMatter else { return ""; }
    return text_of(L.d, L.d.nodes[fm].content);
}

fn is_title_line(line: const u8[:]) -> bool {
    var t = trim(line);
    if starts_with(t, "\"") { t = t[1..]; }
    guard t.len >= 5 && lower_equal(t[..5], "title") else { return false; }
    t = t[5..];
    if starts_with(t, "\"") { t = t[1..]; }
    t = trim(t);
    return starts_with(t, ":") || starts_with(t, "=");
}

fn has_front_matter_title(L: Lint&) -> bool { any(split(front_matter(L), '\n')) { is_title_line(it) } }

fn report_line(L: Lint&, ln: i64, rule: const u8[:], msg: const u8[:]) {
    let t = line_text(L, ln);
    var col = 0;
    while col < t.len && (t[col] == ' ' || t[col] == '\t') { col++; }
    report(L, L.lines[ln] + min(col, t.len), rule, msg);
}

import std;
import md.node;

let RULE_IDS = [
    "ste-word",
    "ste-sentence-length",
    "ste-contraction",
    "ste-semicolon",
    "ste-ing",
    "ste-passive",
    "llm-stock",
    "llm-hedge",
    "llm-em-dash",
    "llm-contrast",
    "llm-rule-of-three",
    "llm-heading-emoji",
    "llm-bold-label",
    "llm-heavy-bold",
    "llm-summary-heading",
    "html-comment",
    "suppression",
    "skill-front-matter",
    "agents-imperative",
    "readme-purpose",
    "readme-run-block",
];

enum Profile { Docs, Readme, Skill, Agents }

struct Finding { line: i64, col: i64, rule: i64, msg: Span }

struct Directive { line: i64, col: i64, target: i64, rules: Span, used: bool = false }

struct Lint {
    d: Doc&,
    profile: Profile,
    lines: i64[>..]&,
    found: Finding[>..]&,
    msgs: u8[>..]&,
    directives: Directive[>..]&,
}

fn source_of(L: Lint&) -> const u8[:] {
    let s = L.d.nodes[0].content;
    return L.d.text[s.at..s.at + s.len];
}

fn index_lines(L: Lint&) {
    let s = source_of(L);
    L.lines.push(0);
    L.lines.push(0);
    for c, i in s {
        if c == '\n' || (c == '\r' && (i + 1 >= s.len || s[i + 1] != '\n')) { L.lines.push(i + 1); }
    }
}

fn line_at(L: Lint&, off: i64) -> i64 {
    var lo = 1;
    var hi = L.lines.len - 1;
    while lo < hi {
        let mid = (lo + hi + 1) / 2;
        if L.lines[mid] <= off { lo = mid; } else { hi = mid - 1; }
    }
    return lo;
}

fn col_at(L: Lint&, line: i64, off: i64) -> i64 {
    let s = source_of(L);
    var col = 1;
    for c in s[L.lines[line]..min(off, s.len)] { if (c & 0xC0) != 0x80 { col++; } }
    return col;
}

fn rule_index(rule: const u8[:]) -> i64 {
    let r = position(RULE_IDS, rule);
    assert(r >= 0);
    return r;
}

fn report_at(L: Lint&, line: i64, col: i64, rule: const u8[:], msg: const u8[:]) {
    let at = L.msgs.len;
    L.msgs.append(msg);
    L.found.push(Finding { line: line, col: col, rule: rule_index(rule), msg: Span { at: at, len: msg.len } });
}

fn report(L: Lint&, off: i64, rule: const u8[:], msg: const u8[:]) {
    let line = line_at(L, off);
    report_at(L, line, col_at(L, line, off), rule, msg);
}

fn node_offset(L: Lint&, n: i64) -> i64 { L.lines[L.d.nodes[n].line] + max(L.d.nodes[n].col, 1) - 1 }

fn report_node(L: Lint&, n: i64, rule: const u8[:], msg: const u8[:]) { report(L, node_offset(L, n), rule, msg); }

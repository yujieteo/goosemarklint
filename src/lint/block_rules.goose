import std;
import md.node;
import md.chars;
import lint.lists;
import lint.context;
import lint.prose;
import lint.tokens;

let BOLD_LABEL_ITEMS = 3;
let HEAVY_BOLD_SPANS = 3;

struct Range2 { lo: i64, hi: i64 }

let EMOJI = [
    Range2 { lo: 0x26A0, hi: 0x26A0 },
    Range2 { lo: 0x26A1, hi: 0x26A1 },
    Range2 { lo: 0x2705, hi: 0x2705 },
    Range2 { lo: 0x2728, hi: 0x2728 },
    Range2 { lo: 0x274C, hi: 0x274C },
    Range2 { lo: 0x2B50, hi: 0x2B50 },
    Range2 { lo: 0x1F300, hi: 0x1FAFF },
];

fn is_emoji(cp: i64) -> bool { any(EMOJI) { cp >= it.lo && cp <= it.hi } }

fn check_heading_emoji(L: Lint&, p: Prose&) {
    var i = 0;
    while i < p.text.len {
        let cp, n = decode_at(p.text, i);
        if is_emoji(cp) {
            report(L, p.pos[i], "llm-heading-emoji", "emoji in a heading: delete it");
            return;
        }
        i += n;
    }
}

fn count_strong(d: Doc&, b: i64) -> i64 {
    var total = 0;
    var n = d.nodes[b].first;
    while n >= 0 {
        if d.nodes[n].kind == Kind.Strong { total++; }
        n = next_in(d, n, b);
    }
    return total;
}

fn check_heavy_bold(L: Lint&, b: i64) {
    let n = count_strong(L.d, b);
    guard n >= HEAVY_BOLD_SPANS;
    report_node(L, b, "llm-heavy-bold", str("paragraph has ", n, " bold spans: keep bold for one key term"));
}

fn starts_bold(d: Doc&, item: i64) -> bool {
    let para = d.nodes[item].first;
    guard para >= 0 && d.nodes[para].kind == Kind.Paragraph else { return false; }
    let first = d.nodes[para].first;
    return first >= 0 && d.nodes[first].kind == Kind.Strong;
}

fn check_bold_labels(L: Lint&, list: i64) {
    var items = 0;
    var n = L.d.nodes[list].first;
    while n >= 0 {
        guard starts_bold(L.d, n) else { return; }
        items++;
        n = L.d.nodes[n].next;
    }
    guard items >= BOLD_LABEL_ITEMS;
    report_node(L, list, "llm-bold-label", "each list item starts with a bold label: delete the labels or use a table");
}

fn normalize_heading(out: u8[>..]&, p: Prose&) {
    var space = false;
    for c in p.text {
        if is_alnum(c) {
            if space && out.len > 0 { out.push(' '); }
            out.push(lower_ascii(c));
            space = false;
        } else {
            space = true;
        }
    }
}

fn check_summary_heading(L: Lint&, p: Prose&) {
    var last = -1;
    for node, i in L.d.nodes {
        if node.kind == Kind.Heading && node.parent >= 0 && (last < 0 || node.line > L.d.nodes[last].line) { last = i; }
    }
    guard last >= 0;
    build_prose(L, p, last);
    var name: u8[>..] = [];
    normalize_heading(name, p);
    guard in_list(SUMMARY, name);
    report_node(L, last, "llm-summary-heading", str("summary heading \"", name, "\" at the end: delete the summary"));
}

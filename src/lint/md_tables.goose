import std;
import md.node;
import md.chars;
import lint.context;
import lint.md_base;

struct Hit { line: i64, at: i64 }

struct PipeStyle { set: bool = false, lead: bool = false, trail: bool = false }

struct Wide { lo: i64, hi: i64 }

let WIDE = [
    Wide { lo: 0x1100, hi: 0x115F },
    Wide { lo: 0x2705, hi: 0x2705 },
    Wide { lo: 0x274C, hi: 0x274E },
    Wide { lo: 0x2E80, hi: 0xA4CF },
    Wide { lo: 0xAC00, hi: 0xD7A3 },
    Wide { lo: 0xF900, hi: 0xFAFF },
    Wide { lo: 0xFE30, hi: 0xFE4F },
    Wide { lo: 0xFF00, hi: 0xFF60 },
    Wide { lo: 0xFFE0, hi: 0xFFE6 },
    Wide { lo: 0x1F300, hi: 0x1F64F },
    Wide { lo: 0x1F900, hi: 0x1F9FF },
    Wide { lo: 0x20000, hi: 0x3FFFD },
];

fn char_width(cp: i64) -> i64 {
    guard cp != 0xFE0F && cp != 0x200D && !(cp >= 0x300 && cp <= 0x36F) else { return 0; }
    let wide = any(WIDE) { cp >= it.lo && cp <= it.hi };
    return if wide { 2 } else { 1 };
}

fn text_width(s: const u8[:]) -> i64 {
    var w = 0;
    var i = 0;
    while i < s.len {
        let cp, n = decode_at(s, i);
        w += char_width(cp);
        i += n;
    }
    return w;
}

fn pipes(t: const u8[:], from: i64) -> i64[>..] {
    var out: i64[>..] = [];
    for c, i in t {
        if i >= from && c == '|' && (i == 0 || t[i - 1] != '\\') { out.push(i); }
    }
    return out;
}

fn check_pipe_style(L: Lint&, ln: i64, t: const u8[:], from: i64, ps: PipeStyle&) {
    let body = trim(t[from..]);
    let lead = starts_with(body, "|");
    let trail = body.len > 1 && ends_with(body, "|") && !ends_with(body, "\\|");
    if !ps.set {
        ps.set = true;
        ps.lead = lead;
        ps.trail = trail;
    }
    if lead != ps.lead { report_line(L, ln, "MD055", if ps.lead { "table row has no leading pipe: add one, as the first row" } else { "table row has a leading pipe: delete it, as the first row" }); }
    if trail != ps.trail { report(L, L.lines[ln] + trim_end(t).len - 1, "MD055", if ps.trail { "table row has no trailing pipe: add one, as the first row" } else { "table row has a trailing pipe: delete it, as the first row" }); }
}

fn cell_count(t: const u8[:], from: i64) -> i64 {
    let body = trim(t[from..]);
    var n = pipes(body, 0).len + 1;
    if starts_with(body, "|") { n--; }
    if body.len > 1 && ends_with(body, "|") && !ends_with(body, "\\|") { n--; }
    return n;
}

fn aligned_hits(L: Lint&, t0: const u8[:], ln: i64, t: const u8[:], from: i64, hits: Hit[>..]&) {
    var want: i64[>..] = [];
    for i in pipes(t0, from) { want.push(text_width(t0[..i])); }
    var left = want.len;
    for i in pipes(t, from) {
        guard left > 0;
        let k = position(want, text_width(t[..i]));
        if k < 0 {
            hits.push(Hit { line: ln, at: i });
        } else {
            want[k] = -1;
            left--;
        }
    }
}

fn spaced_hits(ln: i64, t: const u8[:], from: i64, compact: Hit[>..]&, tight: Hit[>..]&) {
    let end = trim_end(t).len;
    var first = from;
    while first < t.len && is_space(t[first]) { first++; }
    for i in pipes(t, from) {
        if i > first {
            var j = i;
            while j > first && is_space(t[j - 1]) { j--; }
            if i - j != 1 { compact.push(Hit { line: ln, at: i }); }
            if i - j > 0 { tight.push(Hit { line: ln, at: i }); }
        }
        if i + 1 < end {
            var j = i + 1;
            while j < end && is_space(t[j]) { j++; }
            if j - i - 1 != 1 { compact.push(Hit { line: ln, at: i }); }
            if j - i - 1 > 0 { tight.push(Hit { line: ln, at: i }); }
        }
    }
}

fn report_hits(L: Lint&, hits: const Hit[:], msg: const u8[:]) {
    for h in hits { report(L, L.lines[h.line] + h.at, "MD060", msg); }
}

fn check_column_style(L: Lint&, n: i64) {
    let node = L.d.nodes[n];
    let from = max(node.col, 1) - 1;
    var aligned: Hit[>..] = [];
    var compact: Hit[>..] = [];
    var tight: Hit[>..] = [];
    for ln in node.line..node.end_line + 1 {
        let t = line_text(L, ln);
        if ln > node.line { aligned_hits(L, line_text(L, node.line), ln, t, from, aligned); }
        spaced_hits(ln, t, from, compact, tight);
    }
    guard aligned.len > 0;
    var pick = 0;
    var best = aligned.len;
    if compact.len < best {
        pick = 1;
        best = compact.len;
    }
    if tight.len < best { pick = 2; }
    match pick {
        0 => report_hits(L, aligned, "table pipe is not in line with the header pipe: align the columns"),
        1 => report_hits(L, compact, "table pipe does not have 1 space on each side: align the columns or use 1 space"),
        _ => report_hits(L, tight, "table pipe has a space next to it: delete the space or align the columns"),
    }
}

fn check_table(L: Lint&, n: i64, ps: PipeStyle&) {
    let node = L.d.nodes[n];
    let from = max(node.col, 1) - 1;
    let want = cell_count(line_text(L, node.line), from);
    for ln in node.line..node.end_line + 1 {
        let t = line_text(L, ln);
        check_pipe_style(L, ln, t, from, ps);
        let cells = cell_count(t, from);
        if cells != want { report_line(L, ln, "MD056", str("table row has ", cells, " cells, the header has ", want, ": make them the same")); }
    }
    check_column_style(L, n);
}

fn check_tables(L: Lint&) {
    var ps = PipeStyle {};
    var n = 0;
    while n >= 0 {
        if L.d.nodes[n].kind == Kind.Table { check_table(L, n, ps); }
        n = next_in(L.d, n, 0);
    }
}

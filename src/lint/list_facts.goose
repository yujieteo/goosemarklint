import std;
import dictionary;
import md.chars;
import md.node;
import lint.facts;
import lint.context;
import lint.prose;
import lint.profiles;

let MIN_LIST = 3;
let FUZZY_LIST = 5;
let LOOKUPS = 4;

struct Side { miss: i64, matched: i64 }

struct Link { list: i64, next: i64 }

fn fold_item(t: const u8[:], from: i64, to: i64, out: u8[>..]&) {
    let start = out.len;
    var depth = 0;
    var gap = false;
    for c in t[from..to] {
        if c == '(' {
            depth++;
        } else if c == ')' {
            if depth > 0 { depth--; }
        } else if depth == 0 {
            if is_alnum(c) || c >= 0x80 {
                if gap && out.len > start { out.push(' '); }
                gap = false;
                out.push(lower_ascii(c));
            } else {
                gap = true;
            }
        }
    }
}

fn add_list(L: Lint&, buf: const u8[:], items: Span[>..]&, bounded: bool, line: i64, col: i64) {
    guard items.len >= MIN_LIST;
    var ends: u8[>..] = [];
    if !bounded {
        for k, at in [0, 1, items.len - 2, items.len - 1] {
            if at > 0 { ends.push('\n'); }
            ends.append(buf[items[k].at..items[k].at + items[k].len]);
        }
    }
    let first = buf[items[0].at..items[0].at + items[0].len];
    let last = buf[items[items.len - 1].at..items[items.len - 1].at + items[items.len - 1].len];
    sort(items) { a, b => compare(buf[a.at..a.at + a.len], buf[b.at..b.at + b.len]) < 0 };
    var key: u8[>..] = [];
    var core = 0;
    for it, k in items {
        let x = buf[it.at..it.at + it.len];
        guard k == 0 || x != buf[items[k - 1].at..items[k - 1].at + items[k - 1].len];
        if key.len > 0 { key.push('\n'); }
        key.append(x);
        if bounded || (x != first && x != last) { core++; }
    }
    guard core >= MIN_LIST;
    add_fact(L.facts, FactKind.List, line, col, key, ends);
}

fn conj_len(t: const u8[:], i: i64) -> i64 {
    if starts_with(t[i..], " and ") { return 5; }
    if starts_with(t[i..], " or ") { return 4; }
    return 0;
}

fn add_items(L: Lint&, t: const u8[:], at: i64, from: i64, to: i64, bounded: bool, pos: const i64[:], line: i64) {
    var segs: Span[>..] = [];
    var start = from;
    var depth = 0;
    var i = from;
    while i < to {
        if t[i] == '(' {
            depth++;
        } else if t[i] == ')' {
            if depth > 0 { depth--; }
        } else if t[i] == ',' && depth == 0 {
            segs.push(Span { at: start, len: i - start });
            start = i + 1;
        } else if depth == 0 && segs.len > 0 && conj_len(t[..to], i) > 0 {
            segs.push(Span { at: start, len: i - start });
            start = i + conj_len(t[..to], i);
            i = to;
        }
        i++;
    }
    segs.push(Span { at: start, len: to - start });
    var buf: u8[>..] = [];
    var items: Span[>..] = [];
    for seg in segs {
        let at = buf.len;
        fold_item(t, seg.at, seg.at + seg.len, buf);
        if buf.len > at { items.push(Span { at: at, len: buf.len - at }); }
    }
    var first = at;
    while first < to && is_space(t[first]) { first++; }
    guard first < to;
    guard pos.len > 0 else {
        add_list(L, buf, items, bounded, line, 1);
        return;
    }
    let ln = line_at(L, pos[first]);
    add_list(L, buf, items, bounded, ln, col_at(L, ln, pos[first]));
}

fn add_sentence_lists(L: Lint&, t: const u8[:], start: i64, end: i64, colon: i64, pos: const i64[:], line: i64) {
    if colon >= 0 { add_items(L, t, start, colon + 1, end, true, pos, line); } else { add_items(L, t, start, start, end, false, pos, line); }
}

fn scan_lists(L: Lint&, t: const u8[:], pos: const i64[:], line: i64) {
    var depth = 0;
    var open = 0;
    var start = 0;
    var colon = -1;
    for c, i in t {
        let spaced = i + 1 >= t.len || is_space(t[i + 1]);
        if c == '(' {
            if depth == 0 { open = i + 1; }
            depth++;
        } else if c == ')' {
            if depth == 1 { add_items(L, t, start, open, i, true, pos, line); }
            if depth > 0 { depth--; }
        } else if depth == 0 && c == ':' && spaced {
            colon = i;
        } else if depth == 0 && position(".!?;", c) >= 0 && spaced {
            add_sentence_lists(L, t, start, i, colon, pos, line);
            start = i + 1;
            colon = -1;
        }
    }
    add_sentence_lists(L, t, start, t.len, colon, pos, line);
}

fn collect_lists(L: Lint&, p: Prose&, b: i64) {
    p.code = true;
    build_prose(L, p, b);
    p.code = false;
    scan_lists(L, p.text, p.pos, 0);
}

fn collect_bullets(L: Lint&, p: Prose&, list: i64) {
    var buf: u8[>..] = [];
    var items: Span[>..] = [];
    var item = L.d.nodes[list].first;
    while item >= 0 {
        let para = L.d.nodes[item].first;
        if para >= 0 && L.d.nodes[para].kind == Kind.Paragraph {
            p.code = true;
            build_prose(L, p, para);
            p.code = false;
            let at = buf.len;
            fold_item(p.text, 0, p.text.len, buf);
            if buf.len > at { items.push(Span { at: at, len: buf.len - at }); }
        }
        item = L.d.nodes[item].next;
    }
    let off = node_offset(L, list);
    let line = line_at(L, off);
    add_list(L, buf, items, true, line, col_at(L, line, off));
}

fn collect_description(L: Lint&) {
    let fm = L.d.nodes[0].first;
    guard fm >= 0 && L.d.nodes[fm].kind == Kind.FrontMatter;
    let desc, at = key_value(text_of(L.d, L.d.nodes[fm].content), "description");
    guard desc.len > 0;
    let none: i64[>..] = [];
    scan_lists(L, desc, none, at + 2);
}

fn item_count(F: Facts&, f: Fact) -> i64 { split(fact_key(F, f), '\n').len }

fn edges(F: Facts&, f: Fact) -> const u8[:][>..] {
    var out: const u8[:][>..] = [];
    if f.ends.len > 0 { out = split(fact_ends(F, f), '\n'); }
    return out;
}

fn add_diff(diffs: u8[>..]&, x: const u8[:]) {
    guard position(split(diffs, '\n'), x) < 0;
    if diffs.len > 0 { diffs.push('\n'); }
    diffs.append(x);
}

fn compare_side(F: Facts&, a: Fact, b: Fact, diffs: u8[>..]&) -> Side {
    let full = split(fact_key(F, b), '\n');
    let items = split(fact_key(F, a), '\n');
    let ends = edges(F, a);
    let other = edges(F, b);
    var surplus = max(item_count(F, a) - item_count(F, b), 0);
    var s = Side { miss: 0, matched: 0 };
    for x in items {
        let k = position(ends, x);
        let inside = position(full, x) >= 0;
        let extra = (k == 1 || k == 2) && !inside && surplus > 0;
        if extra { surplus--; }
        if inside && k != 0 && k != 3 && !extra {
            s.matched++;
        } else if !inside && k != 0 && k != 3 && !extra {
            let glued = any(other) { position(items, it) < 0 && find(it, x) >= 0 };
            if ends.len > 0 || !glued {
                s.miss++;
                add_diff(diffs, x);
            }
        }
    }
    return s;
}

fn fits(s: Side, tol: i64) -> bool { s.matched >= MIN_LIST && s.miss <= tol }

fn list_diffs(F: Facts&, a: Fact, b: Fact, diffs: u8[>..]&) -> bool {
    let tol = if item_count(F, a) >= FUZZY_LIST && item_count(F, b) >= FUZZY_LIST { 1 } else { 0 };
    guard abs(item_count(F, a) - item_count(F, b)) <= tol else { return false; }
    let sa = compare_side(F, a, b, diffs);
    let sb = compare_side(F, b, a, diffs);
    return fits(sa, tol) && fits(sb, tol);
}

fn same_list(F: Facts&, a: Fact, b: Fact) -> bool {
    var diffs: u8[>..] = [];
    return list_diffs(F, a, b, diffs);
}

fn group_diffs(F: Facts&, group: i64[:]) -> u8[>..] {
    var out: u8[>..] = [];
    for i, at in group {
        for j in group[at + 1..] {
            var d: u8[>..] = [];
            guard list_diffs(F, F.items[i], F.items[j], d);
            for x in split(d, '\n') { if x.len > 0 { add_diff(out, x); } }
        }
    }
    return out;
}

fn lookups(F: Facts&, f: Fact) -> const u8[:][>..] {
    let ends = edges(F, f);
    var out: const u8[:][>..] = [];
    for x in split(fact_key(F, f), '\n') {
        let k = position(ends, x);
        if k != 0 && k != 3 && out.len < LOOKUPS { out.push(x); }
    }
    return out;
}

fn join_lists(F: Facts&, up: i64[>..]&) {
    var heads = dictionary<u64, i64> {};
    var links: Link[>..] = [];
    for f, i in F.items {
        guard f.kind == FactKind.List;
        for x in split(fact_key(F, f), '\n') {
            let prev = heads.get(hash(x));
            links.push(Link { list: i, next: if prev { prev } else { -1 } });
            heads.insert(hash(x), links.len - 1);
        }
    }
    for f, i in F.items {
        guard f.kind == FactKind.List;
        for x in lookups(F, f) {
            let h = heads.get(hash(x));
            var k = if h { h } else { -1 };
            while k >= 0 {
                let j = links[k].list;
                if j != i && same_list(F, f, F.items[j]) { join(up, i, j); }
                k = links[k].next;
            }
        }
    }
}

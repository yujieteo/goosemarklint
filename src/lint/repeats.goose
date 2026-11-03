import std;
import md.chars;
import md.node;
import lint.facts;
import lint.context;
import lint.prose;
import lint.tokens;
import lint.list_facts;

let MIN_FACT_WORDS = 8;
let MAX_HASH = 40;
let MIN_HASH = 7;

fn sentence_key(p: Prose&, w: Words&, s: Sent, key: u8[>..]&) -> bool {
    key.clear();
    guard word_count(w, s) >= MIN_FACT_WORDS else { return false; }
    for i in s.first..s.end {
        let t = w.toks[i];
        guard t.kind != Tk.Opaque else { return false; }
        guard t.kind != Tk.Punct;
        if key.len > 0 { key.push(' '); }
        for c in tok_text(p, t) { key.push(lower_ascii(c)); }
    }
    return true;
}

fn collect_sentences(L: Lint&, p: Prose&, w: Words&) {
    var key: u8[>..] = [];
    for s in w.sents {
        guard sentence_key(p, w, s, key);
        let off = p.pos[w.toks[s.first].at];
        let line = line_at(L, off);
        add_fact(L.facts, FactKind.Sentence, line, col_at(L, line, off), key, "");
    }
}

fn is_digit(c: u8) -> bool { c >= '0' && c <= '9' }

fn is_hex(c: u8) -> bool { is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F') }

fn digits_end(s: const u8[:], from: i64) -> i64 {
    var j = from;
    while j < s.len && is_digit(s[j]) { j++; }
    return j;
}

fn version_end(s: const u8[:], from: i64) -> i64 {
    var j = from;
    for part in 3 {
        let e = digits_end(s, j);
        guard e > j else { return -1; }
        j = e;
        if part < 2 {
            guard j < s.len && s[j] == '.' else { return -1; }
            j++;
        }
    }
    let more = j + 1 < s.len && s[j] == '.' && is_digit(s[j + 1]);
    guard j >= s.len || (!is_alnum(s[j]) && !more) else { return -1; }
    return j;
}

fn hash_end(s: const u8[:], from: i64) -> i64 {
    var j = from;
    var digit = false;
    while j < s.len && is_hex(s[j]) {
        if is_digit(s[j]) { digit = true; }
        j++;
    }
    let n = j - from;
    guard n >= MIN_HASH && n <= MAX_HASH && digit && (j >= s.len || !is_alnum(s[j])) else { return -1; }
    let letter = any(s[from..j]) { !is_digit(it) };
    guard letter else { return -1; }
    return j;
}

fn pin_start(L: Lint&) -> i64 {
    let fm = L.d.nodes[0].first;
    guard fm >= 0 && L.d.nodes[fm].kind == Kind.FrontMatter else { return 0; }
    let next = L.d.nodes[fm].end_line + 1;
    return if next < L.lines.len { L.lines[next] } else { source_of(L).len };
}

fn add_pin(L: Lint&, kind: FactKind, at: i64, key: const u8[:]) {
    let line = line_at(L, at);
    add_fact(L.facts, kind, line, col_at(L, line, at), key, "");
}

fn collect_pins(L: Lint&) {
    let s = source_of(L);
    var key: u8[>..] = [];
    var i = pin_start(L);
    while i < s.len {
        let boundary = i == 0 || (!is_alnum(s[i - 1]) && s[i - 1] != '.');
        var end = -1;
        if boundary {
            let prefixed = (s[i] == 'v' || s[i] == 'V') && i + 1 < s.len;
            let from = if prefixed { i + 1 } else { i };
            end = version_end(s, from);
            if end >= 0 {
                add_pin(L, FactKind.Version, i, s[from..end]);
            } else {
                end = hash_end(s, i);
                if end >= 0 {
                    key.clear();
                    for c in s[i..end] { key.push(lower_ascii(c)); }
                    add_pin(L, FactKind.Hash, i, key);
                }
            }
        }
        i = if end >= 0 { end } else { i + 1 };
    }
}

fn kind_rank(k: FactKind) -> i64 {
    match k {
        Sentence => 0,
        Version => 1,
        Hash => 2,
        List => 3,
    }
}

fn same_key(F: Facts&, head: Fact, f: Fact) -> bool {
    guard head.kind == f.kind else { return false; }
    let a = fact_key(F, head);
    let b = fact_key(F, f);
    return a == b || (f.kind == FactKind.Hash && starts_with(b, a));
}

fn join_keys(F: Facts&, up: i64[>..]&) {
    var order: i64[>..] = [];
    for f, i in F.items { if f.kind != FactKind.List { order.push(i); } }
    sort(order) { a, b =>
        let fa = F.items[a];
        let fb = F.items[b];
        let c = compare(fact_key(F, fa), fact_key(F, fb));
        kind_rank(fa.kind) < kind_rank(fb.kind) || (fa.kind == fb.kind && c < 0)
    };
    var head = 0;
    for k in 1..order.len {
        if same_key(F, F.items[order[head]], F.items[order[k]]) { join(up, order[head], order[k]); } else { head = k; }
    }
}

fn file_count(F: Facts&, group: i64[:]) -> i64 {
    var n = 0;
    for k, at in group {
        var seen = false;
        for j in at { if fact_path(F, F.items[group[j]]) == fact_path(F, F.items[k]) { seen = true; } }
        if !seen { n++; }
    }
    return n;
}

fn place(F: Facts&, f: Fact) -> u8[>..] { str(fact_path(F, f), ":", f.line) }

fn places_of(F: Facts&, group: i64[:]) -> u8[>..] {
    var out: u8[>..] = [];
    for k, at in group {
        if at > 0 { out.append(", "); }
        out.append(place(F, F.items[k]));
    }
    return out;
}

fn shown_key(F: Facts&, group: i64[:]) -> u8[>..] {
    var best = group[0];
    for k in group {
        let f = F.items[k];
        let b = F.items[best];
        let cleaner = f.ends.len == 0 && b.ends.len > 0;
        if cleaner || ((f.ends.len == 0) == (b.ends.len == 0) && fact_key(F, f).len > fact_key(F, b).len) { best = k; }
    }
    var out: u8[>..] = [];
    for c in fact_key(F, F.items[best]) { if c == '\n' { out.append(", "); } else { out.push(c); } }
    return out;
}

fn report_group(out: u8[>..]&, F: Facts&, group: i64[:], sentence_places: const u8[:]) {
    let first = F.items[group[0]];
    let what = match first.kind {
        Sentence => "sentence",
        List => "list",
        _ => "pinned value",
    };
    let pin = first.kind == FactKind.Version || first.kind == FactKind.Hash;
    let enough = if pin { file_count(F, group) >= 2 } else { group.len >= 2 };
    guard enough;
    let places = places_of(F, group);
    guard first.kind != FactKind.List || position(split(sentence_places, '\0'), places) < 0;
    format(out, fact_path(F, first), ":", first.line, ":", first.col, ": repeated-fact: warning: ", what, " \"", shown_key(F, group), "\" is in ", group.len, " places: ", places);
    if first.kind == FactKind.List {
        let diffs = group_diffs(F, group);
        if diffs.len > 0 {
            out.append(", and these items differ: ");
            for x, at in split(diffs, '\n') { format(out, if at > 0 { ", " } else { "" }, "\"", x, "\""); }
        }
    }
    out.append(": keep one owner and point to it from the others\n");
}

fn report_repeats(out: u8[>..]&, F: Facts&) {
    var up: i64[>..] = [];
    for i in F.items.len { up.push(i); }
    join_keys(F, up);
    join_lists(F, up);
    var root: i64[>..] = [];
    for i in F.items.len { root.push(find_root(up, i)); }
    var order: i64[>..] = [];
    for i in F.items.len { order.push(i); }
    stable_sort(order) { a, b => root[a] < root[b] };
    var groups: Span[>..] = [];
    var start = 0;
    for k in 1..order.len + 1 {
        if k == order.len || root[order[k]] != root[order[start]] {
            groups.push(Span { at: start, len: k - start });
            start = k;
        }
    }
    var sentence_places: u8[>..] = [];
    for g in groups {
        guard g.len >= 2 && F.items[order[g.at]].kind == FactKind.Sentence;
        sentence_places.append(places_of(F, order[g.at..g.at + g.len]));
        sentence_places.push('\0');
    }
    for g in groups { report_group(out, F, order[g.at..g.at + g.len], sentence_places); }
}

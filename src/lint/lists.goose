import std;
import os;
import dictionary;
import md.node;
import md.chars;
import md.html_scan;

let STE_DATA = embed_file("../../data/ste.tsv");
let LLM_DATA = embed_file("../../data/llm.tsv");
let CATEGORIES = [
    "ban",
    "contraction",
    "allow",
    "be",
    "adverb",
    "participle",
    "verb",
    "abbreviation",
    "stock",
    "hedge",
    "summary",
    "adjective",
    "suffix",
    "generated",
    "exclude",
    "disable",
];
let BAN = 0;
let CONTRACTION = 1;
let ALLOW = 2;
let BE = 3;
let ADVERB = 4;
let PARTICIPLE = 5;
let VERB = 6;
let ABBREVIATION = 7;
let STOCK = 8;
let HEDGE = 9;
let SUMMARY = 10;
let ADJECTIVE = 11;
let SUFFIX = 12;
let GENERATED = 13;
let EXCLUDE = 14;
let DISABLE = 15;
let CONFIG_CATEGORIES = [BAN, ALLOW, GENERATED, EXCLUDE, DISABLE];

struct Entry { cat: i64, phrase: Span, repl: Span, next: i64 = -1 }

var list_text: u8[>..] = [];
var entries: Entry[>..] = [];
var entry_index = dictionary<u64, i64> {};
var loaded = load_shipped();

fn entry_key(cat: i64, word: const u8[:]) -> u64 {
    var low: u8[..64] = [];
    for c in word[..min(word.len, 64)] { low.push(lower_ascii(c)); }
    return hash_combine(hash(cat), hash(low));
}

fn first_word(s: const u8[:]) -> const u8[:] {
    let sp = position(s, ' ');
    return if sp < 0 { s } else { s[..sp] };
}

fn put_lower(s: const u8[:]) -> Span {
    let at = list_text.len;
    for c in s { list_text.push(lower_ascii(c)); }
    return Span { at: at, len: s.len };
}

fn add_entry(cat: i64, phrase: const u8[:], repl: const u8[:]) {
    let key = entry_key(cat, first_word(phrase));
    let p = put_lower(phrase);
    let at = list_text.len;
    list_text.append(repl);
    let prev = entry_index.get(key);
    let next = if prev { prev } else { -1 };
    entry_index.insert(key, entries.len);
    entries.push(Entry { cat: cat, phrase: p, repl: Span { at: at, len: repl.len }, next: next });
}

fn add_list_line(line: const u8[:], allowed: const i64[:]) -> bool {
    let f = split(line, '\t');
    guard f.len == 2 || f.len == 3 else { return false; }
    let cat = position(CATEGORIES, f[0]);
    guard cat >= 0 && (allowed.len == 0 || position(allowed, cat) >= 0) && f[1].len > 0 else { return false; }
    let phrase = if cat == EXCLUDE || cat == GENERATED { strip_dot(f[1]) } else { f[1] };
    add_entry(cat, phrase, if f.len == 3 { f[2] } else { "" });
    return true;
}

fn add_lists(data: const u8[:], allowed: const i64[:]) -> i64 {
    var line_no = 0;
    var bad = 0;
    each_split(data, '\n') {
        line_no++;
        let line = trim_end(it);
        if line.len > 0 && bad == 0 && !add_list_line(line, allowed) { bad = line_no; }
    };
    return bad;
}

fn load_shipped() -> bool {
    let none: i64[>..] = [];
    assert(add_lists(STE_DATA, none) == 0);
    assert(add_lists(LLM_DATA, none) == 0);
    return true;
}

fn phrase_of(e: Entry) -> const u8[:] { list_text[e.phrase.at..e.phrase.at + e.phrase.len] }

fn repl_of(e: Entry) -> const u8[:] { list_text[e.repl.at..e.repl.at + e.repl.len] }

fn find_entry(cat: i64, word: const u8[:]) -> i64 {
    var e = entry_index.get(entry_key(cat, first_word(word)));
    var i = if e { e } else { -1 };
    while i >= 0 {
        if entries[i].cat == cat && lower_equal(word, phrase_of(entries[i])) { return i; }
        i = entries[i].next;
    }
    return -1;
}

fn in_list(cat: i64, word: const u8[:]) -> bool { find_entry(cat, word) >= 0 }

fn is_allowed(word: const u8[:]) -> bool { in_list(ALLOW, word) }

fn strip_dot(path: const u8[:]) -> const u8[:] { if starts_with(path, "./") { path[2..] } else { path } }

fn is_under(cat: i64, path: const u8[:]) -> bool {
    let rel = strip_dot(path);
    return any(entries) { it.cat == cat && rel.len >= it.phrase.len && lower_equal(rel[..it.phrase.len], phrase_of(it)) && (rel.len == it.phrase.len || rel[it.phrase.len] == '/' || ends_with(phrase_of(it), "/")) };
}

fn is_generated(path: const u8[:]) -> bool { is_under(GENERATED, path) }

fn is_excluded(path: const u8[:]) -> bool { is_under(EXCLUDE, path) }

fn is_disabled(rule: const u8[:]) -> bool { in_list(DISABLE, rule) }

fn fixture_base(root: const u8[:]) -> i64 {
    var end = root.len;
    while end > 0 && root[end - 1] == '/' { end -= 1; }
    var at = end;
    while at > 0 && root[at - 1] != '/' { at -= 1; }
    return at;
}

fn in_pass_fixture(path: const u8[:], from: i64) -> bool {
    var found = false;
    var parent: u8[>..] = [];
    each_split(path, '/') {
        if it == "pass" && parent.len >= from && is_dir(str(parent, "fail")) { found = true; }
        format(parent, it, "/");
    };
    return found;
}

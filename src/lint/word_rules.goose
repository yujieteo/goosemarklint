import std;
import md.node;
import md.html_scan;
import lint.lists;
import lint.context;
import lint.prose;
import lint.tokens;

let PHRASE_RULES = [BAN, CONTRACTION, STOCK, HEDGE];
let ING_AFTER = ["without", "before", "after", "by", "while", "when", "than", "upon"];

fn lower_ends_with(w: const u8[:], suffix: const u8[:]) -> bool {
    w.len >= suffix.len && lower_equal(w[w.len - suffix.len..], suffix)
}

fn phrase_matches(p: Prose&, w: Words&, i: i64, phrase: const u8[:]) -> i64 {
    var k = i;
    var ok = true;
    each_split(phrase, ' ') {
        if ok && k < w.toks.len && w.toks[k].kind == Tk.Plain && lower_equal(tok_text(p, w.toks[k]), it) {
            k++;
        } else {
            ok = false;
        }
    };
    return if ok { k } else { -1 };
}

fn match_phrase(p: Prose&, w: Words&, i: i64, cat: i64) -> i64, i64 {
    var e = entry_index.get(entry_key(cat, tok_text(p, w.toks[i])));
    var k = if e { e } else { -1 };
    while k >= 0 {
        if entries[k].cat == cat {
            let end = phrase_matches(p, w, i, phrase_of(entries[k]));
            if end >= 0 { return k, end; }
        }
        k = entries[k].next;
    }
    return -1, -1;
}

fn phrase_message(out: u8[>..]&, cat: i64, words: const u8[:], repl: const u8[:]) {
    format(out, "\"", words, "\"");
    match cat {
        BAN => format(out, " is not STE: use \"", repl, "\""),
        CONTRACTION => format(out, " is a contraction: write \"", repl, "\""),
        STOCK => if repl.len > 0 { format(out, " is an LLM stock word: use \"", repl, "\""); } else { out.append(" is an LLM stock phrase: rewrite it"); },
        _ => out.append(" is filler: delete it"),
    }
}

fn phrase_rule(cat: i64) -> const u8[:] {
    match cat {
        BAN => "ste-word",
        CONTRACTION => "ste-contraction",
        STOCK => "llm-stock",
        _ => "llm-hedge",
    }
}

fn is_capital(p: Prose&, t: Tok) -> bool { p.text[t.at] >= 'A' && p.text[t.at] <= 'Z' }

fn check_phrases_at(L: Lint&, p: Prose&, w: Words&, i: i64, starts: bool) {
    let in_name = !starts && is_capital(p, w.toks[i]);
    for cat in PHRASE_RULES {
        guard !(in_name && (cat == BAN || cat == STOCK));
        let e, end = match_phrase(p, w, i, cat);
        guard e >= 0;
        let words = p.text[w.toks[i].at..w.toks[end - 1].at + w.toks[end - 1].len];
        guard end > i + 1 || !is_allowed(words);
        var msg: u8[>..] = [];
        phrase_message(msg, cat, words, repl_of(entries[e]));
        report(L, p.pos[w.toks[i].at], phrase_rule(cat), msg);
    }
}

fn is_verb_slot(p: Prose&, w: Words&, i: i64) -> bool {
    guard i > 0 && w.toks[i - 1].kind == Tk.Plain else { return false; }
    let prev = tok_text(p, w.toks[i - 1]);
    return in_list(BE, prev) || any(ING_AFTER) { lower_equal(prev, it) };
}

fn check_ing(L: Lint&, p: Prose&, w: Words&, i: i64) {
    guard is_verb_slot(p, w, i);
    let t = w.toks[i];
    let word = tok_text(p, t);
    var at = 0;
    each_split(word, '-') {
        if it.len >= 4 && lower_ends_with(it, "ing") && !is_allowed(it) {
            report_warning(L, p.pos[t.at + at], "ste-ing", str("\"", it, "\" is an -ing verb form: use another verb form"));
        }
        at += it.len + 1;
    };
}

fn is_participle(word: const u8[:]) -> bool {
    guard !is_allowed(word) else { return false; }
    return in_list(PARTICIPLE, word) || (word.len >= 4 && lower_ends_with(word, "ed"));
}

fn is_plain(w: Words&, i: i64) -> bool { i < w.toks.len && w.toks[i].kind == Tk.Plain }

fn check_passive(L: Lint&, p: Prose&, w: Words&, i: i64) {
    guard in_list(BE, tok_text(p, w.toks[i]));
    var j = i + 1;
    guard is_plain(w, j);
    let between = tok_text(p, w.toks[j]);
    if in_list(ADVERB, between) || (between.len > 3 && lower_ends_with(between, "ly")) { j++; }
    guard is_plain(w, j) && is_participle(tok_text(p, w.toks[j]));
    let words = p.text[w.toks[i].at..w.toks[j].at + w.toks[j].len];
    report(L, p.pos[w.toks[i].at], "ste-passive", str("\"", words, "\" is passive voice: name who does the action"));
}

fn is_em_dash(s: const u8[:], i: i64) -> bool { s[i] == 0xE2 && i + 2 < s.len && s[i + 1] == 0x80 && s[i + 2] == 0x94 }

fn check_marks(L: Lint&, p: Prose&) {
    let alone = trim(p.text);
    let placeholder = alone.len == 3 && is_em_dash(alone, 0);
    for c, i in p.text {
        if c == ';' { report(L, p.pos[i], "ste-semicolon", "semicolon: write two sentences"); }
        if is_em_dash(p.text, i) && !placeholder {
            report(L, p.pos[i], "llm-em-dash", "em dash: write two sentences or use a comma");
        }
    }
}

fn check_words(L: Lint&, p: Prose&, w: Words&) {
    check_marks(L, p);
    var starts: bool[>..] = [];
    for t in w.toks { starts.push(false); }
    for s in w.sents {
        var k = s.first;
        while k < s.end && !is_word(w.toks[k]) { k++; }
        if k < s.end { starts[k] = true; }
    }
    for t, i in w.toks {
        guard t.kind == Tk.Plain;
        check_phrases_at(L, p, w, i, starts[i]);
        check_ing(L, p, w, i);
        check_passive(L, p, w, i);
    }
}

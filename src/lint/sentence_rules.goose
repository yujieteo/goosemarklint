import std;
import md.html_scan;
import lint.lists;
import lint.context;
import lint.prose;
import lint.tokens;
import lint.word_rules;

let DESCRIPTION_LIMIT = 25;
let INSTRUCTION_LIMIT = 20;
let SUBJECTS = ["it", "it's", "this", "that", "that's", "they", "they're", "these", "those"];
let NOT_JUST = ["just", "only", "merely"];

fn word_at(p: Prose&, w: Words&, i: i64) -> const u8[:] { if is_plain(w, i) { tok_text(p, w.toks[i]) } else { "" } }

fn is_verb(p: Prose&, w: Words&, i: i64) -> bool { is_plain(w, i) && in_list(VERB, tok_text(p, w.toks[i])) }

fn is_instruction(p: Prose&, w: Words&, s: Sent) -> bool {
    guard s.first < s.end else { return false; }
    if is_verb(p, w, s.first) { return true; }
    for i in s.first..s.end {
        if w.toks[i].kind == Tk.Punct && p.text[w.toks[i].at] == ',' { return is_verb(p, w, i + 1); }
    }
    return false;
}

fn check_length(L: Lint&, p: Prose&, w: Words&, s: Sent) {
    let n = word_count(w, s);
    let instruction = is_instruction(p, w, s);
    let limit = if instruction { INSTRUCTION_LIMIT } else { DESCRIPTION_LIMIT };
    guard n > limit;
    let kind = if instruction { "instruction" } else { "sentence" };
    report(L, p.pos[w.toks[s.first].at], "ste-sentence-length", str(kind, " has ", n, " words, limit ", limit));
}

fn in_words(word: const u8[:], set: const u8[:][:]) -> bool { any(set) { lower_equal(word, it) } }

fn is_comma(p: Prose&, w: Words&, i: i64) -> bool { i >= 0 && i < w.toks.len && w.toks[i].kind == Tk.Punct && p.text[w.toks[i].at] == ',' }

fn is_negation(word: const u8[:]) -> bool { lower_equal(word, "not") || lower_ends_with(word, "n't") }

fn reframes_at(p: Prose&, w: Words&, i: i64) -> bool {
    let a = word_at(p, w, i);
    guard in_words(a, SUBJECTS) else { return false; }
    return position(a, '\'') >= 0 || in_list(BE, word_at(p, w, i + 1));
}

fn contrast_at(p: Prose&, w: Words&, s: Sent) -> i64 {
    var negation = -1;
    for i in s.first..s.end {
        let word = word_at(p, w, i);
        if negation < 0 && lower_equal(word, "not") && in_words(word_at(p, w, i + 1), NOT_JUST) { negation = i; }
        if negation >= 0 && i > negation + 1 && lower_equal(word, "but") { return negation; }
    }
    guard in_words(word_at(p, w, s.first), SUBJECTS) else { return -1; }
    negation = -1;
    for i in s.first..s.end {
        if negation < 0 && is_negation(word_at(p, w, i)) { negation = i; }
        if negation >= 0 && is_comma(p, w, i) && reframes_at(p, w, i + 1) { return s.first; }
    }
    return -1;
}

fn check_contrast(L: Lint&, p: Prose&, w: Words&, s: Sent) {
    let at = contrast_at(p, w, s);
    guard at >= 0;
    report(L, p.pos[w.toks[at].at], "llm-contrast", "\"not X, but Y\" contrast: state Y");
}

fn is_adjective(word: const u8[:]) -> bool {
    guard word.len > 0 && word[0] >= 'a' && word[0] <= 'z' else { return false; }
    if in_list(ADJECTIVE, word) { return true; }
    for k in 3..min(word.len - 1, 5) { if in_list(SUFFIX, word[word.len - k..]) { return true; } }
    return false;
}

fn triple_end(p: Prose&, w: Words&, i: i64) -> i64 {
    guard !is_comma(p, w, i - 1) && is_adjective(word_at(p, w, i)) && is_comma(p, w, i + 1) else { return -1; }
    guard is_adjective(word_at(p, w, i + 2)) else { return -1; }
    var j = i + 3;
    if is_comma(p, w, j) { j++; }
    let joiner = word_at(p, w, j);
    guard lower_equal(joiner, "and") || lower_equal(joiner, "or") else { return -1; }
    guard is_adjective(word_at(p, w, j + 1)) && !is_comma(p, w, j + 2) else { return -1; }
    return j + 2;
}

fn check_triples(L: Lint&, p: Prose&, w: Words&, s: Sent) {
    for i in s.first..s.end {
        let end = triple_end(p, w, i);
        guard end >= 0 && end <= s.end;
        let words = p.text[w.toks[i].at..w.toks[end - 1].at + w.toks[end - 1].len];
        report(L, p.pos[w.toks[i].at], "llm-rule-of-three", str("\"", words, "\" is a rule-of-three adjective list: keep the one that matters"));
    }
}

fn check_sentences(L: Lint&, p: Prose&, w: Words&) {
    for s in w.sents {
        check_length(L, p, w, s);
        check_contrast(L, p, w, s);
        check_triples(L, p, w, s);
    }
}

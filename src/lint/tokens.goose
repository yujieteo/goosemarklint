import std;
import md.chars;
import lint.lists;
import lint.context;
import lint.prose;

enum Tk { Plain, Other, Opaque, Punct }

struct Tok { at: i64, len: i64, kind: Tk }

struct Sent { first: i64, end: i64 }

struct Words { toks: Tok[>..]&, sents: Sent[>..]& }

fn is_word_char(s: const u8[:], i: i64) -> bool {
    let c = s[i];
    guard c >= 0x80 else { return is_alnum(c) || c == '_'; }
    let cp, n = decode_at(s, i);
    return !is_unicode_punct(cp) && !is_unicode_space(cp);
}

fn is_joiner(s: const u8[:], i: i64) -> bool {
    guard i > 0 && i + 1 < s.len && position("'-./", s[i]) >= 0 else { return false; }
    return is_word_char(s, i - 1) && is_word_char(s, i + 1);
}

fn char_len(s: const u8[:], i: i64) -> i64 {
    let cp, n = decode_at(s, i);
    return n;
}

fn word_kind(w: const u8[:]) -> Tk {
    for c in w { if !is_alpha(c) && c != '\'' && c != '-' { return Tk.Other; } }
    return Tk.Plain;
}

fn tokenize(p: Prose&, w: Words&) {
    let s = p.text;
    w.toks.clear();
    var i = 0;
    while i < s.len {
        let c = s[i];
        if c == ' ' || c == '\t' || c == '\n' {
            i++;
        } else if c == OPAQUE {
            w.toks.push(Tok { at: i, len: 1, kind: Tk.Opaque });
            i++;
        } else if is_word_char(s, i) {
            var j = i + char_len(s, i);
            while j < s.len && (is_word_char(s, j) || is_joiner(s, j)) { j += char_len(s, j); }
            w.toks.push(Tok { at: i, len: j - i, kind: word_kind(s[i..j]) });
            i = j;
        } else {
            let n = char_len(s, i);
            w.toks.push(Tok { at: i, len: n, kind: Tk.Punct });
            i += n;
        }
    }
}

fn tok_text(p: Prose&, t: Tok) -> const u8[:] { p.text[t.at..t.at + t.len] }

fn is_closer(c: u8) -> bool { position(")]\"'*_", c) >= 0 }

fn is_terminal(p: Prose&, w: Words&, i: i64) -> bool {
    let t = w.toks[i];
    guard t.len == 1 && position(".!?", p.text[t.at]) >= 0 else { return false; }
    if p.text[t.at] == '.' && i > 0 {
        let prev = w.toks[i - 1];
        if prev.at + prev.len == t.at && in_list(ABBREVIATION, tok_text(p, prev)) { return false; }
    }
    var j = t.at + 1;
    while j < p.text.len && is_closer(p.text[j]) { j++; }
    return j >= p.text.len || p.text[j] == ' ' || p.text[j] == '\t' || p.text[j] == '\n';
}

fn split_sentences(p: Prose&, w: Words&) {
    w.sents.clear();
    var first = 0;
    for i in w.toks.len {
        if is_terminal(p, w, i) {
            w.sents.push(Sent { first: first, end: i + 1 });
            first = i + 1;
        }
    }
    if first < w.toks.len { w.sents.push(Sent { first: first, end: w.toks.len }); }
}

fn is_word(t: Tok) -> bool { t.kind != Tk.Punct }

fn word_count(w: Words&, s: Sent) -> i64 { count(w.toks[s.first..s.end]) { is_word(it) } }

fn read_words(L: Lint&, p: Prose&, w: Words&, b: i64) {
    build_prose(L, p, b);
    tokenize(p, w);
    split_sentences(p, w);
}

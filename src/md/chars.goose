import std;
import dictionary;
import md.node;

struct Range { lo: i64, hi: i64 }

let UNICODE_DATA = embed_file("../../data/unicode.txt");

var punct_ranges: Range[>..] = load_ranges('p');
var space_ranges: Range[>..] = load_ranges('z');
var fold_text: u8[>..] = [];
var fold_index = load_map('f');
var lower_index = load_map('l');

fn hex_value(s: const u8[:]) -> i64 {
    let v, ok = parse_int(s, 16);
    assert(ok);
    return v;
}

fn load_ranges(tag: u8) -> Range[>..] {
    var out: Range[>..] = [];
    each_split(UNICODE_DATA, '\n') {
        guard it.len > 2 && it[0] == tag && it[1] == ' ';
        let parts = words(it[2..]);
        out.push(Range { lo: hex_value(parts[0]), hi: hex_value(parts[1]) });
    };
    return out;
}

fn load_map(tag: u8) -> dictionary<i64, Span> {
    var index = dictionary<i64, Span> {};
    each_split(UNICODE_DATA, '\n') {
        guard it.len > 2 && it[0] == tag && it[1] == ' ';
        let parts = words(it[2..]);
        let at = fold_text.len;
        for p in parts[1..] { push_utf8(fold_text, hex_value(p)); }
        index.insert(hex_value(parts[0]), Span { at: at, len: fold_text.len - at });
    };
    return index;
}

fn in_ranges(rs: const Range[:], cp: i64) -> bool {
    var lo = 0;
    var hi = rs.len;
    while lo < hi {
        let mid = (lo + hi) / 2;
        if cp < rs[mid].lo { hi = mid; } else if cp > rs[mid].hi { lo = mid + 1; } else { return true; }
    }
    return false;
}

fn is_space_or_tab(c: i64) -> bool { c == ' ' || c == '\t' }

fn is_ascii_space(c: i64) -> bool { c == ' ' || c == '\t' || c == '\n' || c == 11 || c == 12 || c == '\r' }

fn is_digit(c: i64) -> bool { c >= '0' && c <= '9' }

fn is_alpha(c: i64) -> bool { (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') }

fn is_alnum(c: i64) -> bool { is_alpha(c) || is_digit(c) }

fn is_hex(c: i64) -> bool { is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F') }

fn is_ascii_punct(c: i64) -> bool {
    (c >= 33 && c <= 47) || (c >= 58 && c <= 64) || (c >= 91 && c <= 96) || (c >= 123 && c <= 126)
}

fn is_unicode_space(cp: i64) -> bool {
    cp == '\t' || cp == '\n' || cp == 12 || cp == '\r' || in_ranges(space_ranges, cp)
}

fn is_unicode_punct(cp: i64) -> bool { (cp < 128 && is_ascii_punct(cp)) || (cp >= 128 && in_ranges(punct_ranges, cp)) }

fn lower_ascii(c: u8) -> u8 { if c >= 'A' && c <= 'Z' { c + 32 } else { c } }

fn utf8_len(lead: u8) -> i64 {
    if lead < 0x80 { 1 } else if lead >= 0xF0 { 4 } else if lead >= 0xE0 { 3 } else if lead >= 0xC0 { 2 } else { 1 }
}

fn decode_at(s: const u8[:], i: i64) -> i64, i64 {
    let lead = s[i];
    let n = utf8_len(lead);
    guard n > 1 && i + n <= s.len else { return lead, 1; }
    var cp: i64 = if n == 2 { lead & 0x1F } else if n == 3 { lead & 0x0F } else { lead & 0x07 };
    for k in 1..n {
        let b = s[i + k];
        guard (b & 0xC0) == 0x80 else { return 0xFFFD, 1; }
        cp = cp * 64 + (b & 0x3F);
    }
    return cp, n;
}

fn decode_before(s: const u8[:], i: i64) -> i64 {
    var start = i - 1;
    while start > 0 && i - start < 4 && (s[start] & 0xC0) == 0x80 { start--; }
    let cp, n = decode_at(s, start);
    if start + n == i { cp } else { s[i - 1] }
}

fn fold_into(out: u8[>..]&, cp: i64) { map_into(out, fold_index, cp); }

fn lower_into(out: u8[>..]&, cp: i64) { map_into(out, lower_index, cp); }

fn map_into(out: u8[>..]&, index: dictionary<i64, Span>&, cp: i64) {
    let f = index.get(cp);
    if f {
        out.append(fold_text[f.at..f.at + f.len]);
    } else {
        push_utf8(out, cp);
    }
}

fn normalize_label(out: u8[>..]&, label: const u8[:]) {
    let start = out.len;
    var i = 0;
    var pending_space = false;
    while i < label.len {
        let c = label[i];
        if is_ascii_space(c) && c != 11 && c != 12 {
            pending_space = out.len > start;
            i++;
            continue;
        }
        if pending_space { out.push(' '); }
        pending_space = false;
        let cp, n = decode_at(label, i);
        fold_into(out, cp);
        i += n;
    }
}

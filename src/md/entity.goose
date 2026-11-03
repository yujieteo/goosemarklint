import std;
import dictionary;
import md.node;
import md.chars;

let ENTITY_DATA = embed_file("../../data/entities.json");

struct Entity { name: Span, chars: Span }

var entity_text: u8[>..] = [];
var entity_list: Entity[>..] = [];
var entity_index = load_entities();

fn load_entities() -> dictionary<u64, i64> {
    var index = dictionary<u64, i64> {};
    each_split(ENTITY_DATA, '\n') {
        let q = find(it, "\"&");
        guard q >= 0;
        let rest = it[q + 2..];
        let end = find(rest, "\"");
        guard end > 1 && rest[end - 1] == ';';
        let name_at = entity_text.len;
        entity_text.append(rest[..end - 1]);
        let chars_at = entity_text.len;
        let open = find(rest, "[");
        let close = find(rest, "]");
        assert(open > 0 && close > open);
        each_split(rest[open + 1..close], ',') {
            let v, ok = parse_int(trim(it));
            assert(ok);
            push_utf8(entity_text, v);
        };
        let e = Entity { name: Span { at: name_at, len: end - 1 }, chars: Span { at: chars_at, len: entity_text.len - chars_at } };
        index.insert(hash(entity_text[name_at..name_at + end - 1]), entity_list.len);
        entity_list.push(e);
    };
    return index;
}

fn lookup_entity(out: u8[>..]&, name: const u8[:]) -> bool {
    let idx = entity_index.get(hash(name));
    guard idx else { return false; }
    let e = entity_list[idx];
    guard entity_text[e.name.at..e.name.at + e.name.len] == name else { return false; }
    out.append(entity_text[e.chars.at..e.chars.at + e.chars.len]);
    return true;
}

fn push_codepoint(out: u8[>..]&, cp: i64) {
    if cp == 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) { push_utf8(out, 0xFFFD); } else { push_utf8(out, cp); }
}

fn numeric_entity(out: u8[>..]&, s: const u8[:], i: i64) -> i64 {
    var j = i + 2;
    let hexa = j < s.len && (s[j] == 'x' || s[j] == 'X');
    if hexa { j++; }
    let start = j;
    let limit = if hexa { 6 } else { 7 };
    while j < s.len && j - start < limit && (if hexa { is_hex(s[j]) } else { is_digit(s[j]) }) { j++; }
    guard j > start && j < s.len && s[j] == ';' else { return 0; }
    let v, ok = parse_int(s[start..j], if hexa { 16 } else { 10 });
    assert(ok);
    push_codepoint(out, v);
    return j + 1 - i;
}

fn decode_entity(out: u8[>..]&, s: const u8[:], i: i64) -> i64 {
    guard i + 2 < s.len && s[i] == '&' else { return 0; }
    if s[i + 1] == '#' { return numeric_entity(out, s, i); }
    guard is_alpha(s[i + 1]) else { return 0; }
    var j = i + 2;
    while j < s.len && j - i - 1 < 32 && is_alnum(s[j]) { j++; }
    guard j < s.len && s[j] == ';' && j - i - 1 >= 2 else { return 0; }
    guard lookup_entity(out, s[i + 1..j]) else { return 0; }
    return j + 1 - i;
}

fn unescape_into(out: u8[>..]&, s: const u8[:]) {
    var i = 0;
    while i < s.len {
        let c = s[i];
        if c == '\\' && i + 1 < s.len && is_ascii_punct(s[i + 1]) {
            out.push(s[i + 1]);
            i += 2;
            continue;
        }
        if c == '&' {
            let n = decode_entity(out, s, i);
            if n > 0 {
                i += n;
                continue;
            }
        }
        out.push(c);
        i++;
    }
}

fn is_uri_safe(c: u8) -> bool {
    if is_alnum(c) { return true; }
    for k in ";/?:@&=+$,-_.!~*'()#" { if k == c { return true; } }
    return false;
}

fn normalize_uri_into(out: u8[>..]&, s: const u8[:]) {
    let hex = "0123456789ABCDEF";
    var i = 0;
    while i < s.len {
        let c = s[i];
        if c == '%' && i + 2 < s.len && is_hex(s[i + 1]) && is_hex(s[i + 2]) {
            out.append(s[i..i + 3]);
            i += 3;
            continue;
        }
        if is_uri_safe(c) {
            out.push(c);
        } else {
            out.push('%');
            out.push(hex[(c >> 4) as i64]);
            out.push(hex[(c & 15) as i64]);
        }
        i++;
    }
}

fn escape_html_into(out: u8[>..]&, s: const u8[:]) {
    for c in s {
        if c == '&' { out.append("&amp;"); } else if c == '<' { out.append("&lt;"); } else if c == '>' {
            out.append("&gt;");
        } else if c == '"' { out.append("&quot;"); } else { out.push(c); }
    }
}

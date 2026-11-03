import std;
import md.chars;

let BLOCK_TAGS = "address article aside base basefont blockquote body caption center col colgroup dd details dialog dir div dl dt fieldset figcaption figure footer form frame frameset h1 h2 h3 h4 h5 h6 head header hr html iframe legend li link main menu menuitem nav noframes ol optgroup option p param section search summary table tbody td tfoot th thead title tr track ul";

fn at(s: const u8[:], i: i64) -> i64 { if i < s.len { s[i] } else { -1 } }

fn skip_spaces(s: const u8[:], i: i64) -> i64 {
    var j = i;
    while j < s.len && is_ascii_space(s[j]) { j++; }
    return j;
}

fn lower_equal(s: const u8[:], word: const u8[:]) -> bool {
    guard s.len == word.len else { return false; }
    for k in s.len { if lower_ascii(s[k]) != word[k] { return false; } }
    return true;
}

fn starts_lower(s: const u8[:], i: i64, word: const u8[:]) -> bool {
    i + word.len <= s.len && lower_equal(s[i..i + word.len], word)
}

fn scan_tag_name(s: const u8[:], i: i64) -> i64 {
    guard i < s.len && is_alpha(s[i]) else { return -1; }
    var j = i + 1;
    while j < s.len && (is_alnum(s[j]) || s[j] == '-') { j++; }
    return j;
}

fn is_attr_name_start(c: i64) -> bool { is_alpha(c) || c == '_' || c == ':' }

fn is_attr_name_char(c: i64) -> bool { is_alnum(c) || c == '_' || c == ':' || c == '.' || c == '-' }

fn is_unquoted_char(c: u8) -> bool {
    c > 0x20 && c != '"' && c != '\'' && c != '=' && c != '<' && c != '>' && c != '`'
}

fn scan_attr_value(s: const u8[:], i: i64) -> i64 {
    let c = at(s, i);
    if c == '"' || c == '\'' {
        var j = i + 1;
        while j < s.len && s[j] != c { j++; }
        return if j < s.len { j + 1 } else { -1 };
    }
    var j = i;
    while j < s.len && is_unquoted_char(s[j]) { j++; }
    return if j > i { j } else { -1 };
}

fn scan_attribute(s: const u8[:], i: i64) -> i64 {
    let name = skip_spaces(s, i);
    guard name > i && is_attr_name_start(at(s, name)) else { return -1; }
    var j = name + 1;
    while j < s.len && is_attr_name_char(s[j]) { j++; }
    let eq = skip_spaces(s, j);
    guard at(s, eq) == '=' else { return j; }
    let v = scan_attr_value(s, skip_spaces(s, eq + 1));
    return if v >= 0 { v } else { j };
}

fn scan_open_tag(s: const u8[:], i: i64) -> i64 {
    guard at(s, i) == '<' else { return -1; }
    var j = scan_tag_name(s, i + 1);
    guard j >= 0 else { return -1; }
    loop {
        let a = scan_attribute(s, j);
        if a < 0 { break; }
        j = a;
    }
    j = skip_spaces(s, j);
    if at(s, j) == '/' { j++; }
    return if at(s, j) == '>' { j + 1 } else { -1 };
}

fn scan_close_tag(s: const u8[:], i: i64) -> i64 {
    guard at(s, i) == '<' && at(s, i + 1) == '/' else { return -1; }
    let name = scan_tag_name(s, i + 2);
    guard name >= 0 else { return -1; }
    let j = skip_spaces(s, name);
    return if at(s, j) == '>' { j + 1 } else { -1 };
}

fn scan_until(s: const u8[:], i: i64, close: const u8[:]) -> i64 {
    let k = find(s[i..], close);
    return if k >= 0 { i + k + close.len } else { -1 };
}

fn scan_comment(s: const u8[:], i: i64) -> i64 {
    guard starts_with(s[i..], "<!--") else { return -1; }
    if starts_with(s[i..], "<!-->") { return i + 5; }
    if starts_with(s[i..], "<!--->") { return i + 6; }
    return scan_until(s, i + 4, "-->");
}

fn scan_declaration(s: const u8[:], i: i64) -> i64 {
    guard at(s, i + 1) == '!' && is_alpha(at(s, i + 2)) else { return -1; }
    var j = i + 3;
    while j < s.len && is_alpha(s[j]) { j++; }
    while j < s.len && s[j] != '>' { j++; }
    return if j < s.len { j + 1 } else { -1 };
}

fn scan_html_tag(s: const u8[:], i: i64) -> i64 {
    guard at(s, i) == '<' else { return -1; }
    let c = at(s, i + 1);
    if c == '/' { return scan_close_tag(s, i); }
    if c == '?' { return scan_until(s, i + 2, "?>"); }
    if c == '!' {
        if starts_with(s[i..], "<!--") { return scan_comment(s, i); }
        if starts_with(s[i..], "<![CDATA[") { return scan_until(s, i + 9, "]]>"); }
        return scan_declaration(s, i);
    }
    return scan_open_tag(s, i);
}

fn tag_ends_here(s: const u8[:], j: i64) -> bool {
    let c = at(s, j);
    c == -1 || is_ascii_space(c) || c == '>' || (c == '/' && at(s, j + 1) == '>')
}

fn is_block_tag(name: const u8[:]) -> bool {
    var hit = false;
    each_split(BLOCK_TAGS, ' ') { if lower_equal(name, it) { hit = true; } };
    return hit;
}

fn html_block_type_raw(s: const u8[:]) -> i64 {
    for name in ["script", "pre", "textarea", "style"] {
        if starts_lower(s, 1, name) {
            let c = at(s, 1 + name.len);
            if c == -1 || is_ascii_space(c) || c == '>' { return 1; }
        }
    }
    return 0;
}

fn html_block_start(s: const u8[:]) -> i64 {
    guard at(s, 0) == '<' else { return 0; }
    if html_block_type_raw(s) > 0 { return 1; }
    if starts_with(s, "<!--") { return 2; }
    if starts_with(s, "<?") { return 3; }
    if at(s, 1) == '!' && is_alpha(at(s, 2)) { return 4; }
    if starts_with(s, "<![CDATA[") { return 5; }
    let name_at = if at(s, 1) == '/' { 2 } else { 1 };
    let name_end = scan_tag_name(s, name_at);
    if name_end >= 0 && is_block_tag(s[name_at..name_end]) && tag_ends_here(s, name_end) { return 6; }
    let end = if name_at == 2 { scan_close_tag(s, 0) } else { scan_open_tag(s, 0) };
    if end >= 0 && skip_spaces(s, end) == s.len { return 7; }
    return 0;
}

fn contains_lower(s: const u8[:], word: const u8[:]) -> bool {
    guard s.len >= word.len else { return false; }
    for i in s.len - word.len + 1 { if starts_lower(s, i, word) { return true; } }
    return false;
}

fn html_block_ends(kind: i64, s: const u8[:]) -> bool {
    match kind {
        1 => contains_lower(s, "</script>") || contains_lower(s, "</pre>") || contains_lower(s, "</textarea>") || contains_lower(s, "</style>"),
        2 => find(s, "-->") >= 0,
        3 => find(s, "?>") >= 0,
        4 => find(s, ">") >= 0,
        5 => find(s, "]]>") >= 0,
        _ => false,
    }
}

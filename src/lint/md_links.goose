import std;
import md.node;
import md.chars;
import lint.context;
import lint.prose;
import lint.md_base;

let IGNORED_LABELS = ["x"];
let IGNORED_DEFINITIONS = ["//"];

struct Anchors { names: u8[>..]& }

fn open_tag_name(t: const u8[:]) -> const u8[:] {
    guard t.len >= 2 && t[0] == '<' && is_alpha(t[1]) else { return ""; }
    var j = 1;
    while j < t.len && (is_alnum(t[j]) || t[j] == '-') { j++; }
    return t[1..j];
}

fn attr_value(t: const u8[:], name: const u8[:]) -> const u8[:], bool {
    var i = 1;
    while i + name.len < t.len {
        let c = t[i - 1];
        if (c == ' ' || c == '\t' || c == '\n') && lower_equal(t[i..i + name.len], name) {
            var j = i + name.len;
            while j < t.len && (t[j] == ' ' || t[j] == '\t') { j++; }
            if j < t.len && t[j] == '=' {
                j++;
                while j < t.len && (t[j] == ' ' || t[j] == '\t') { j++; }
                if j < t.len && (t[j] == '"' || t[j] == '\'') { j++; }
                var e = j;
                while e < t.len && position("'\" \t\n>", t[e]) < 0 { e++; }
                return t[j..e], true;
            }
        }
        i++;
    }
    return "", false;
}

fn each_open_tag(t: const u8[:], at: i64[>..]&) {
    var i = position(t, '<');
    while i >= 0 && i < t.len {
        var from = i + 1;
        if starts_with(t[i..], "<!--") {
            let e = find(t[i..], "-->");
            guard e >= 0 else { return; }
            from = i + e + 3;
        } else if open_tag_name(t[i..]).len > 0 {
            at.push(i);
        }
        let next = position(t[from..], '<');
        i = if next < 0 { -1 } else { from + next };
    }
}

fn add_anchor(a: Anchors&, name: const u8[:]) {
    a.names.append(name);
    a.names.push('\n');
}

fn has_anchor(a: Anchors&, name: const u8[:], fold: bool) -> const u8[:] {
    let names = split(a.names, '\n');
    for it in names { if it.len > 0 && (if fold { lower_equal(it, name) } else { it == name }) { return it; } }
    return "";
}

fn slug_char(out: u8[>..]&, s: const u8[:], i: i64) -> i64 {
    let cp, n = decode_at(s, i);
    if cp < 128 {
        let c = lower_ascii(s[i]);
        if is_alnum(c) || c == '_' || c == '-' { out.push(c); } else if c == ' ' { out.push('-'); }
    } else if !is_unicode_punct(cp) && !is_unicode_space(cp) {
        lower_into(out, cp);
    }
    return n;
}

fn heading_slug(L: Lint&, h: i64) -> u8[>..] {
    var out: u8[>..] = [];
    var n = L.d.nodes[h].first;
    while n >= 0 {
        let node = L.d.nodes[n];
        let skip = node.kind == Kind.Image;
        if node.kind == Kind.Text || node.kind == Kind.Code {
            let t = text_of(L.d, node.content);
            var i = 0;
            while i < t.len { i += slug_char(out, t, i); }
        }
        n = if skip { next_skip(L.d, n, h) } else { next_in(L.d, n, h) };
    }
    return out;
}

fn add_heading_anchor(a: Anchors&, slug: const u8[:]) {
    guard slug.len > 0;
    var copies = 0;
    for name in split(a.names, '\n') { if name == slug { copies++; } }
    if copies > 0 { add_anchor(a, str(slug, "-", copies)); }
    add_anchor(a, slug);
}

fn add_html_anchors(a: Anchors&, t: const u8[:]) {
    var at: i64[>..] = [];
    each_open_tag(t, at);
    for i in at {
        let tag = t[i..];
        let id, has_id = attr_value(tag, "id");
        let name, has_name = attr_value(tag, "name");
        if has_id { add_anchor(a, id); } else if has_name && lower_equal(open_tag_name(tag), "a") { add_anchor(a, name); }
    }
}

fn collect_anchors(L: Lint&, a: Anchors&) {
    add_anchor(a, "top");
    var n = 0;
    while n >= 0 {
        let node = L.d.nodes[n];
        if node.kind == Kind.Heading { add_heading_anchor(a, heading_slug(L, n)); }
        if node.kind == Kind.HtmlBlock || node.kind == Kind.HtmlInline { add_html_anchors(a, text_of(L.d, node.content)); }
        n = next_in(L.d, n, 0);
    }
}

fn percent_decode(s: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    var i = 0;
    while i < s.len {
        if s[i] == '%' && i + 2 < s.len && is_hex(s[i + 1]) && is_hex(s[i + 2]) {
            out.push(hex_value(s[i + 1..i + 3]) as u8);
            i += 3;
        } else {
            out.push(s[i]);
            i++;
        }
    }
    return out;
}

fn is_line_fragment(f: const u8[:]) -> bool {
    guard f.len >= 2 && f[0] == 'L' && is_digit(f[1]) else { return false; }
    return all(f) { is_digit(it) || it == 'L' || it == 'C' || it == '-' };
}

fn check_fragment(L: Lint&, a: Anchors&, at: i64, dest: const u8[:]) {
    guard dest.len > 1 && dest[0] == '#';
    let f = percent_decode(dest[1..]);
    guard !is_line_fragment(f) && has_anchor(a, f, false).len == 0;
    let near = has_anchor(a, f, true);
    let msg = if near.len > 0 { str("link fragment \"#", f, "\" has the wrong case: use \"#", near, "\"") } else { str("link fragment \"#", f, "\" has no heading or anchor: fix the link") };
    report(L, at, "MD051", msg);
}

fn is_plain_bracket(s: const u8[:], at: i64) -> bool { at < s.len && (s[at] == '[' || s[at] == ']') && (at == 0 || s[at - 1] != '\\') }

fn check_reference_text(L: Lint&, p: Prose&, n: i64) {
    let c = L.d.nodes[n].content;
    let t = text_of(L.d, c);
    let s = source_of(L);
    var i = 0;
    while i + 1 < t.len {
        let open = rfind(t[..i], "[");
        let end = position(t[i + 1..], ']');
        guard t[i] == ']' && t[i + 1] == '[' && open >= 0 && end > 0 else {
            i++;
            continue;
        }
        let label = if end == 1 { t[open + 1..i] } else { t[i + 2..i + 1 + end] };
        let at = content_pos(p, c.at + open);
        let plain = is_plain_bracket(s, at) && is_plain_bracket(s, content_pos(p, c.at + i + 1));
        if plain && label.len > 0 && position(IGNORED_LABELS, label) < 0 {
            report(L, at, "MD052", str("reference \"", label, "\" has no definition: add one, or fix the label"));
        }
        i += end + 1;
    }
}

fn check_definitions(L: Lint&) {
    for r in L.d.refs {
        let label = text_of(L.d, r.label);
        guard !r.used && position(IGNORED_DEFINITIONS, label) < 0 && r.line > 0;
        let t = line_text(L, r.line);
        report(L, L.lines[r.line] + max(position(t, '['), 0), "MD053", str("reference definition \"", label, "\" is not used: delete it"));
    }
}

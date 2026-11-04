import std;
import md.node;

struct Level { quote: bool, width: i64 = 0, marker: Span, used: bool = false }

struct Fmt {
    d: Doc&,
    starts: i64[>..]&,
    targets: i64[>..]&,
    out: u8[>..]&,
    levels: Level[>..]&,
    marks: u8[>..]&,
    depth: i64 = 0,
}

fn source(f: Fmt&) -> const u8[:] {
    let s = f.d.nodes[0].content;
    return f.d.text[s.at..s.at + s.len];
}

fn index_starts(f: Fmt&) {
    let s = source(f);
    f.starts.push(0);
    f.starts.push(0);
    for c, i in s {
        if c == '\n' || (c == '\r' && (i + 1 >= s.len || s[i + 1] != '\n')) { f.starts.push(i + 1); }
    }
}

fn source_line(f: Fmt&, n: i64) -> const u8[:] {
    let s = source(f);
    guard n >= 1 && n < f.starts.len else { return ""; }
    var end = if n + 1 < f.starts.len { f.starts[n + 1] } else { s.len };
    while end > f.starts[n] && (s[end - 1] == '\n' || s[end - 1] == '\r') { end--; }
    return s[f.starts[n]..end];
}

fn leaf_line(f: Fmt&, n: i64) -> const u8[:] {
    let t = source_line(f, n);
    let col = if n < f.d.line_cols.len { f.d.line_cols[n] } else { 0 };
    return t[min(max(col, 1) - 1, t.len)..];
}

fn trim_space_end(s: const u8[:]) -> const u8[:] {
    var z = s.len;
    while z > 0 && (s[z - 1] == ' ' || s[z - 1] == '\t') { z--; }
    return s[..z];
}

fn push_level(f: Fmt&, l: Level) {
    if f.depth < f.levels.len { f.levels[f.depth] = l; } else { f.levels.push(l); }
    f.depth++;
}

fn push_quote(f: Fmt&) { push_level(f, Level { quote: true, marker: Span {}, .. }); }

fn push_item(f: Fmt&, marker: const u8[:], width: i64) {
    let at = f.marks.len;
    f.marks.append(marker);
    push_level(f, Level { quote: false, width: width, marker: Span { at: at, len: marker.len }, .. });
}

fn pop_level(f: Fmt&) { f.depth--; }

fn put_spaced(f: Fmt&, pending: i64, s: const u8[:]) {
    push_n(f.out, ' ', pending);
    f.out.append(s);
}

fn put_line(f: Fmt&, s: const u8[:]) {
    var pending = 0;
    for i in f.depth {
        let l = f.levels[i];
        if l.quote {
            put_spaced(f, pending, ">");
            pending = 1;
        } else if l.used {
            pending += l.width;
        } else {
            put_spaced(f, pending, f.marks[l.marker.at..l.marker.at + l.marker.len]);
            pending = 1;
            f.levels[i].used = true;
        }
    }
    if s.len > 0 { put_spaced(f, pending, s); }
    f.out.push('\n');
}

fn put_blank(f: Fmt&) {
    var pending = 0;
    for l in f.levels[..f.depth] {
        if l.quote {
            put_spaced(f, pending, ">");
            pending = 1;
        } else {
            pending += l.width;
        }
    }
    f.out.push('\n');
}

fn put_lines(f: Fmt&, s: const u8[:]) {
    guard s.len > 0;
    let body = if ends_with(s, "\n") { s[..s.len - 1] } else { s };
    each_split(body, '\n') { put_line(f, it); };
}

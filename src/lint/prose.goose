import std;
import md.node;
import md.entity;
import lint.context;

let OPAQUE = 1;

struct Prose { text: u8[>..]&, pos: i64[>..]&, cmap: i64[>..]&, base: i64 = 0 }

fn map_lines(L: Lint&, p: Prose&, c: const u8[:], first_line: i64) {
    var line = first_line;
    var start = 0;
    var j = 0;
    for ch in c {
        if line < L.lines.len && line < L.d.line_cols.len { start = L.lines[line] + max(L.d.line_cols[line], 1) - 1; }
        p.cmap.push(start + j);
        j++;
        if ch == '\n' {
            line++;
            j = 0;
        }
    }
}

fn map_atx(L: Lint&, p: Prose&, c: const u8[:], n: i64) {
    let from = node_offset(L, n);
    let src = source_of(L);
    let end = if n_line_end(L, n) < src.len { n_line_end(L, n) } else { src.len };
    let k = find(src[min(from, end)..end], c);
    let start = if k >= 0 { from + k } else { from };
    for j in c.len { p.cmap.push(start + j); }
}

fn n_line_end(L: Lint&, n: i64) -> i64 {
    let line = L.d.nodes[n].line;
    return if line + 1 < L.lines.len { L.lines[line + 1] } else { source_of(L).len };
}

fn map_cell(L: Lint&, p: Prose&, c: const u8[:], n: i64) {
    let src = source_of(L);
    var s = node_offset(L, n);
    for ch in c {
        if ch == '|' && s + 1 < src.len && src[s] == '\\' && src[s + 1] == '|' { s++; }
        p.cmap.push(s);
        s++;
    }
}

fn map_block(L: Lint&, p: Prose&, b: i64) {
    let node = L.d.nodes[b];
    let c = text_of(L.d, node.content);
    p.cmap.clear();
    p.base = node.content.at;
    if node.kind == Kind.TableCell {
        map_cell(L, p, c, b);
    } else if node.kind == Kind.Heading && node.end_line == node.line && position(c, '\n') < 0 {
        map_atx(L, p, c, b);
    } else {
        map_lines(L, p, c, node.line);
    }
    p.cmap.push(if p.cmap.len > 0 { p.cmap[p.cmap.len - 1] + 1 } else { node_offset(L, b) });
}

fn content_pos(p: Prose&, at: i64) -> i64 {
    let k = at - p.base;
    if k >= 0 && k < p.cmap.len { return p.cmap[k]; }
    return if p.pos.len > 0 { p.pos[p.pos.len - 1] } else { p.cmap[0] };
}

fn emit(p: Prose&, c: u8, pos: i64) {
    p.text.push(c);
    p.pos.push(pos);
}

fn last_pos(p: Prose&) -> i64 { if p.pos.len > 0 { p.pos[p.pos.len - 1] } else { p.cmap[0] } }

fn emit_realigned(L: Lint&, p: Prose&, t: const u8[:], src: i64) {
    let end = p.base + p.cmap.len - 1;
    var s = src;
    var j = 0;
    var decoded: u8[>..] = [];
    while j < t.len {
        let here = content_pos(p, s);
        if s < end && L.d.text[s] == '&' {
            decoded.clear();
            let m = decode_entity(decoded, L.d.text[..end], s);
            if m > 0 && starts_with(t[j..], decoded) {
                for k in decoded.len { emit(p, t[j + k], here); }
                j += decoded.len;
                s += m;
                continue;
            }
        }
        if s < end && L.d.text[s] == '\\' && t[j] != '\\' {
            s++;
            continue;
        }
        emit(p, t[j], here);
        j++;
        s++;
    }
}

fn emit_text(L: Lint&, p: Prose&, n: i64) {
    let c = L.d.nodes[n].content;
    let t = text_of(L.d, c);
    if c.at >= p.base && c.at + c.len < p.base + p.cmap.len {
        for ch, j in t { emit(p, ch, p.cmap[c.at - p.base + j]); }
    } else if L.d.nodes[n].src >= 0 {
        emit_realigned(L, p, t, L.d.nodes[n].src);
    } else {
        let at = last_pos(p);
        for ch in t { emit(p, ch, at); }
    }
}

fn is_url_link(L: Lint&, n: i64) -> bool {
    let first = L.d.nodes[n].first;
    guard first >= 0 && first == L.d.nodes[n].last && L.d.nodes[first].kind == Kind.Text else { return false; }
    let t = text_of(L.d, L.d.nodes[first].content);
    guard position(t, ' ') < 0 else { return false; }
    return find(t, "://") >= 0 || starts_with(t, "www.") || position(t, '@') >= 0;
}

fn next_skip(d: Doc&, n: i64, root: i64) -> i64 {
    var k = n;
    while k != root {
        if d.nodes[k].next >= 0 { return d.nodes[k].next; }
        k = d.nodes[k].parent;
    }
    return -1;
}

fn next_in(d: Doc&, n: i64, root: i64) -> i64 { if d.nodes[n].first >= 0 { d.nodes[n].first } else { next_skip(d, n, root) } }

fn emit_leaf(L: Lint&, p: Prose&, n: i64) -> bool {
    let node = L.d.nodes[n];
    match node.kind {
        Text => emit_text(L, p, n),
        SoftBreak, LineBreak => emit(p, ' ', last_pos(p)),
        Code => emit(p, OPAQUE, if node.src >= 0 { content_pos(p, node.src) } else { last_pos(p) }),
        HtmlInline => emit(p, ' ', content_pos(p, node.content.at)),
        Image => {
            emit(p, ' ', last_pos(p));
            return true;
        },
        Link => if is_url_link(L, n) {
            emit(p, OPAQUE, content_pos(p, L.d.nodes[node.first].content.at));
            return true;
        },
        _ => {},
    }
    return false;
}

fn normalize_quotes(p: Prose&) {
    var w = 0;
    var r = 0;
    while r < p.text.len {
        let curly = r + 2 < p.text.len && p.text[r] == 0xE2 && p.text[r + 1] == 0x80;
        let quote = curly && (p.text[r + 2] == 0x98 || p.text[r + 2] == 0x99);
        p.text[w] = if quote { '\'' } else { p.text[r] };
        p.pos[w] = p.pos[r];
        r += if quote { 3 } else { 1 };
        w++;
    }
    while p.text.len > w {
        p.text.pop();
        p.pos.pop();
    }
}

fn build_prose(L: Lint&, p: Prose&, b: i64) {
    map_block(L, p, b);
    p.text.clear();
    p.pos.clear();
    var n = L.d.nodes[b].first;
    while n >= 0 { n = if emit_leaf(L, p, n) { next_skip(L.d, n, b) } else { next_in(L.d, n, b) }; }
    normalize_quotes(p);
}

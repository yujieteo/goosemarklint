import std;
import md.node;
import md.chars;
import md.line;

struct Cell { start: i64 = 0, end: i64 = 0 }

fn is_table_space(c: i64) -> bool { c == ' ' || c == '\t' || c == 11 || c == 12 }

fn is_trim_space(c: u8) -> bool { is_table_space(c) || c == '\n' || c == '\r' }

fn at_row_end(s: const u8[:], i: i64) -> i64 {
    var j = i;
    while j < s.len && is_table_space(s[j]) { j++; }
    if j == s.len { return j - i; }
    if s[j] == '\n' { return j + 1 - i; }
    if s[j] == '\r' && j + 1 < s.len && s[j + 1] == '\n' { return j + 2 - i; }
    return -1;
}

fn cell_end(s: const u8[:], i: i64) -> i64 {
    guard i < s.len && s[i] == '|' else { return 0; }
    var j = i + 1;
    while j < s.len && is_table_space(s[j]) { j++; }
    return j - i;
}

fn cell_length(s: const u8[:], i: i64) -> i64 {
    var j = i;
    while j < s.len && s[j] != '|' && s[j] != '\n' && s[j] != '\r' {
        if s[j] == '\\' && j + 1 < s.len && is_ascii_punct(s[j + 1]) { j += 2; } else { j++; }
    }
    return j - i;
}

fn parse_row(s: const u8[:], cells: Cell[>..]&) -> i64 {
    cells.clear();
    var paragraph_offset = 0;
    var offset = cell_end(s, 0);
    var more = true;
    while offset < s.len && more {
        let cell = cell_length(s, offset);
        let pipe = cell_end(s, offset + cell);
        if cell > 0 || pipe > 0 { cells.push(Cell { start: offset, end: offset + cell }); }
        offset += cell + pipe;
        if pipe == 0 {
            let row_end = at_row_end(s, offset);
            more = false;
            if row_end > 0 && offset + row_end != s.len {
                offset += row_end;
                paragraph_offset = offset;
                cells.clear();
                offset += cell_end(s, offset);
                more = true;
            } else if row_end >= 0 {
                offset += row_end;
            }
        }
    }
    guard offset == s.len && cells.len > 0 else { return -1; }
    return paragraph_offset;
}

fn is_delimiter_cell(s: const u8[:]) -> bool {
    var i = 0;
    while i < s.len && is_table_space(s[i]) { i++; }
    if i < s.len && s[i] == ':' { i++; }
    let dashes = i;
    while i < s.len && s[i] == '-' { i++; }
    guard i > dashes else { return false; }
    if i < s.len && s[i] == ':' { i++; }
    while i < s.len && is_table_space(s[i]) { i++; }
    return i == s.len;
}

fn is_delimiter_row(s: const u8[:], cells: const Cell[:]) -> bool {
    for c in cells { if !is_delimiter_cell(s[c.start..c.end]) { return false; } }
    return true;
}

fn put_cell_text(d: Doc&, s: const u8[:]) -> Span {
    var a = 0;
    var z = s.len;
    while a < z && is_trim_space(s[a]) { a++; }
    while z > a && is_trim_space(s[z - 1]) { z--; }
    let at = d.text.len;
    var i = a;
    while i < z {
        if s[i] == '\\' && i + 1 < z && s[i + 1] == '|' { i++; }
        d.text.push(s[i]);
        i++;
    }
    return Span { at: at, len: d.text.len - at };
}

fn alignment_of(s: const u8[:]) -> u8 {
    var a = 0;
    var z = s.len;
    while a < z && is_trim_space(s[a]) { a++; }
    while z > a && is_trim_space(s[z - 1]) { z--; }
    let left = s[a] == ':';
    let right = s[z - 1] == ':';
    if left && right { return 'c'; }
    if left { return 'l'; }
    if right { return 'r'; }
    return 'n';
}

fn add_row(d: Doc&, line_no: i64, table: i64, s: const u8[:], base_col: i64, cells: const Cell[:], header: bool) {
    let row = new_node(d, Kind.TableRow, line_no, d.nodes[table].col);
    d.nodes[row].header = header;
    d.nodes[row].open = false;
    d.nodes[row].end_line = line_no;
    append_child(d, table, row);
    let aligns = d.nodes[table].info;
    for i in aligns.len {
        let cell = new_node(d, Kind.TableCell, line_no, base_col);
        d.nodes[cell].open = false;
        d.nodes[cell].end_line = line_no;
        d.nodes[cell].align = d.text[aligns.at + i];
        if i < cells.len {
            d.nodes[cell].col = base_col + cells[i].start;
            d.nodes[cell].end_col = base_col + cells[i].end - 1;
            d.nodes[cell].content = put_cell_text(d, s[cells[i].start..cells[i].end]);
        }
        append_child(d, row, cell);
        d.nodes[row].end_col = max(d.nodes[row].end_col, d.nodes[cell].end_col);
    }
}

fn insert_leading_paragraph(d: Doc&, table: i64, s: const u8[:]) {
    let p = new_node(d, Kind.Paragraph, d.nodes[table].line, d.nodes[table].col);
    d.nodes[p].open = false;
    d.nodes[p].content = put_cell_text(d, s);
    insert_before(d, table, p);
}

fn try_table_header(d: Doc&, b: LineState&, para: i64) -> Start {
    guard !d.nodes[para].visited else { return Start.None; }
    var delims: Cell[>..] = [];
    let line = rest_of_line(d, b, b.next_nonspace);
    guard parse_row(line, delims) == 0 && is_delimiter_row(line, delims) else { return Start.None; }
    var heads: Cell[>..] = [];
    let c = d.nodes[para].content;
    let para_text = d.text[c.at..c.at + c.len];
    let para_offset = parse_row(para_text, heads);
    if para_offset < 0 || heads.len != delims.len {
        d.nodes[para].visited = true;
        return Start.None;
    }
    d.nodes[para].kind = Kind.Table;
    let aligns_at = d.text.len;
    for cell in delims { d.text.push(alignment_of(line[cell.start..cell.end])); }
    d.nodes[para].info = Span { at: aligns_at, len: delims.len };
    if para_offset > 0 { insert_leading_paragraph(d, para, para_text[..para_offset]); }
    add_row(d, b.number - 1, para, para_text, d.nodes[para].col, heads, true);
    advance_offset(d, b, b.len - b.offset, false);
    return Start.Container;
}

fn row_continues(d: Doc&, b: LineState&) -> bool {
    guard !b.blank else { return false; }
    var cells: Cell[>..] = [];
    return parse_row(rest_of_line(d, b, b.next_nonspace), cells) >= 0;
}

fn try_table_row(d: Doc&, b: LineState&, table: i64) -> Start {
    guard !b.blank else { return Start.None; }
    var cells: Cell[>..] = [];
    let line = rest_of_line(d, b, b.next_nonspace);
    guard parse_row(line, cells) >= 0 else { return Start.None; }
    let first = d.nodes[table].col;
    add_row(d, b.number, table, line, first, cells, false);
    d.nodes[table].end_line = b.number;
    advance_offset(d, b, b.len - b.offset, false);
    return Start.Container;
}

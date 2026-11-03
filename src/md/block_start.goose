import std;
import md.node;
import md.chars;
import md.line;
import md.html_scan;
import md.table;
import md.reference;

fn try_block_quote(d: Doc&, b: LineState&) -> Start {
    guard !b.indented && peek(d, b, b.next_nonspace) == '>' else { return Start.None; }
    advance_next_nonspace(b);
    advance_offset(d, b, 1, false);
    if is_space_or_tab(peek(d, b, b.offset)) { advance_offset(d, b, 1, true); }
    close_unmatched(d, b);
    add_child(d, b, Kind.BlockQuote, b.next_nonspace);
    return Start.Container;
}

fn atx_level(s: const u8[:]) -> i64 {
    var n = 0;
    while n < s.len && s[n] == '#' { n++; }
    guard n >= 1 && n <= 6 && (n == s.len || is_space_or_tab(s[n])) else { return 0; }
    return n;
}

fn strip_closing_hashes(s: const u8[:]) -> const u8[:] {
    var z = s.len;
    while z > 0 && is_space_or_tab(s[z - 1]) { z--; }
    var h = z;
    while h > 0 && s[h - 1] == '#' { h--; }
    guard h < z else { return s[..z]; }
    guard h == 0 || is_space_or_tab(s[h - 1]) else { return s[..z]; }
    var a = h;
    while a > 0 && is_space_or_tab(s[a - 1]) { a--; }
    return s[..a];
}

fn try_atx(d: Doc&, b: LineState&) -> Start {
    guard !b.indented else { return Start.None; }
    let rest = rest_of_line(d, b, b.next_nonspace);
    let level = atx_level(rest);
    guard level > 0 else { return Start.None; }
    var marker = level;
    while marker < rest.len && is_space_or_tab(rest[marker]) { marker++; }
    advance_next_nonspace(b);
    advance_offset(d, b, marker, false);
    close_unmatched(d, b);
    let h = add_child(d, b, Kind.Heading, b.next_nonspace);
    d.nodes[h].level = level;
    let text = strip_closing_hashes(rest_of_line(d, b, b.offset));
    d.nodes[h].content = put_text(d, text);
    advance_offset(d, b, b.len - b.offset, false);
    return Start.Leaf;
}

fn fence_length(s: const u8[:]) -> i64 {
    guard s.len >= 3 && (s[0] == '`' || s[0] == '~') else { return 0; }
    var n = 0;
    while n < s.len && s[n] == s[0] { n++; }
    guard n >= 3 else { return 0; }
    if s[0] == '`' && position(s[n..], '`') >= 0 { return 0; }
    return n;
}

fn try_fence(d: Doc&, b: LineState&) -> Start {
    guard !b.indented else { return Start.None; }
    let rest = rest_of_line(d, b, b.next_nonspace);
    let n = fence_length(rest);
    guard n > 0 else { return Start.None; }
    let fence_char = rest[0];
    close_unmatched(d, b);
    let c = add_child(d, b, Kind.CodeBlock, b.next_nonspace);
    d.nodes[c].fenced = true;
    d.nodes[c].fence_len = n;
    d.nodes[c].fence_char = fence_char;
    d.nodes[c].fence_offset = b.indent;
    advance_next_nonspace(b);
    advance_offset(d, b, n, false);
    return Start.Leaf;
}

fn try_html(d: Doc&, b: LineState&, container: i64) -> Start {
    guard !b.indented && peek(d, b, b.next_nonspace) == '<' else { return Start.None; }
    let kind = html_block_start(rest_of_line(d, b, b.next_nonspace));
    guard kind > 0 else { return Start.None; }
    let maybe_lazy = !b.all_closed && !b.blank && d.nodes[b.tip].kind == Kind.Paragraph;
    guard kind < 7 || (d.nodes[container].kind != Kind.Paragraph && !maybe_lazy) else { return Start.None; }
    close_unmatched(d, b);
    let h = add_child(d, b, Kind.HtmlBlock, b.offset);
    d.nodes[h].html_type = kind;
    return Start.Leaf;
}

fn setext_level(s: const u8[:]) -> i64 {
    guard s.len > 0 && (s[0] == '=' || s[0] == '-') else { return 0; }
    var n = 0;
    while n < s.len && s[n] == s[0] { n++; }
    while n < s.len && is_space_or_tab(s[n]) { n++; }
    guard n == s.len else { return 0; }
    return if s[0] == '=' { 1 } else { 2 };
}

fn try_setext(d: Doc&, b: LineState&, container: i64) -> Start {
    guard !b.indented && d.nodes[container].kind == Kind.Paragraph else { return Start.None; }
    let level = setext_level(rest_of_line(d, b, b.next_nonspace));
    guard level > 0 else { return Start.None; }
    close_unmatched(d, b);
    strip_references(d, container);
    guard d.nodes[container].content.len > 0 else { return Start.None; }
    d.nodes[container].kind = Kind.Heading;
    d.nodes[container].level = level;
    advance_offset(d, b, b.len - b.offset, false);
    return Start.Leaf;
}

fn is_thematic_break(s: const u8[:]) -> bool {
    guard s.len > 0 && (s[0] == '*' || s[0] == '_' || s[0] == '-') else { return false; }
    var n = 0;
    for c in s {
        if c == s[0] { n++; } else if !is_space_or_tab(c) { return false; }
    }
    return n >= 3;
}

fn try_thematic_break(d: Doc&, b: LineState&) -> Start {
    guard !b.indented && is_thematic_break(rest_of_line(d, b, b.next_nonspace)) else { return Start.None; }
    close_unmatched(d, b);
    add_child(d, b, Kind.ThematicBreak, b.next_nonspace);
    advance_offset(d, b, b.len - b.offset, false);
    return Start.Leaf;
}

fn list_marker_length(d: Doc&, b: LineState&, container: i64, data: ListData&) -> i64 {
    let rest = rest_of_line(d, b, b.next_nonspace);
    guard rest.len > 0 else { return 0; }
    if rest[0] == '*' || rest[0] == '+' || rest[0] == '-' {
        data.bullet = rest[0];
        return 1;
    }
    var n = 0;
    while n < rest.len && n < 10 && is_digit(rest[n]) { n++; }
    guard n >= 1 && n <= 9 && n < rest.len && (rest[n] == '.' || rest[n] == ')') else { return 0; }
    let start, ok = parse_int(rest[..n]);
    assert(ok);
    guard d.nodes[container].kind != Kind.Paragraph || start == 1 else { return 0; }
    data.ordered = true;
    data.start = start;
    data.delim = rest[n];
    return n + 1;
}

fn parse_list_marker(d: Doc&, b: LineState&, container: i64, data: ListData&) -> bool {
    guard b.indent < 4 else { return false; }
    data.marker_offset = b.indent;
    let n = list_marker_length(d, b, container, data);
    guard n > 0 else { return false; }
    let after = peek(d, b, b.next_nonspace + n);
    guard after == -1 || is_space_or_tab(after) else { return false; }
    let in_para = d.nodes[container].kind == Kind.Paragraph;
    guard !in_para || !is_blank_text(rest_of_line(d, b, b.next_nonspace + n)) else { return false; }
    advance_next_nonspace(b);
    advance_offset(d, b, n, true);
    let start_col = b.column;
    let start_offset = b.offset;
    loop {
        advance_offset(d, b, 1, true);
        guard b.column - start_col < 5 && is_space_or_tab(peek(d, b, b.offset)) else { break; }
    }
    let blank_item = peek(d, b, b.offset) == -1;
    let spaces = b.column - start_col;
    if spaces >= 5 || spaces < 1 || blank_item {
        data.padding = n + 1;
        b.column = start_col;
        b.offset = start_offset;
        if is_space_or_tab(peek(d, b, b.offset)) { advance_offset(d, b, 1, true); }
    } else {
        data.padding = n + spaces;
    }
    return true;
}

fn lists_match(a: ListData, b: ListData) -> bool { a.ordered == b.ordered && a.delim == b.delim && a.bullet == b.bullet }

fn try_list_item(d: Doc&, b: LineState&, container: i64) -> Start {
    guard !b.indented || d.nodes[container].kind == Kind.List else { return Start.None; }
    var data = ListData {};
    guard parse_list_marker(d, b, container, data) else { return Start.None; }
    close_unmatched(d, b);
    if d.nodes[b.tip].kind != Kind.List || !lists_match(d.nodes[container].list, data) {
        let l = add_child(d, b, Kind.List, b.next_nonspace);
        d.nodes[l].list = data;
    }
    let item = add_child(d, b, Kind.Item, b.next_nonspace);
    d.nodes[item].list = data;
    return Start.Container;
}

fn try_indented_code(d: Doc&, b: LineState&) -> Start {
    guard b.indented && d.nodes[b.tip].kind != Kind.Paragraph && !b.blank else { return Start.None; }
    advance_offset(d, b, CODE_INDENT, true);
    close_unmatched(d, b);
    add_child(d, b, Kind.CodeBlock, b.offset);
    return Start.Leaf;
}

fn is_task_line(s: const u8[:]) -> bool {
    var i = 0;
    while i < s.len && is_table_space(s[i]) { i++; }
    guard i < s.len else { return false; }
    if s[i] == '-' || s[i] == '+' || s[i] == '*' {
        i++;
    } else {
        let start = i;
        while i < s.len && is_digit(s[i]) { i++; }
        guard i > start && i < s.len else { return false; }
        i++;
    }
    let spaces = i;
    while i < s.len && is_table_space(s[i]) { i++; }
    guard i > spaces && i + 3 < s.len && s[i] == '[' && s[i + 2] == ']' else { return false; }
    guard s[i + 1] == ' ' || s[i + 1] == 'x' || s[i + 1] == 'X' else { return false; }
    return is_table_space(s[i + 3]);
}

fn try_task(d: Doc&, b: LineState&, container: i64) -> Start {
    guard d.opts.tasklist && d.nodes[container].kind == Kind.Item else { return Start.None; }
    let s = line_of(d, b);
    guard is_task_line(s) else { return Start.None; }
    let box = find(s, "[");
    d.nodes[container].task = if s[box + 1] == ' ' { 1 } else { 2 };
    advance_offset(d, b, 3, false);
    find_next_nonspace(d, b);
    return Start.None;
}

fn try_table(d: Doc&, b: LineState&, container: i64) -> Start {
    guard d.opts.table && !b.indented else { return Start.None; }
    let kind = d.nodes[container].kind;
    if kind == Kind.Paragraph { return try_table_header(d, b, container); }
    if kind == Kind.Table { return try_table_row(d, b, container); }
    return Start.None;
}

fn try_starts(d: Doc&, b: LineState&, container: i64) -> Start {
    var r = try_block_quote(d, b);
    if r == Start.None { r = try_atx(d, b); }
    if r == Start.None { r = try_fence(d, b); }
    if r == Start.None { r = try_html(d, b, container); }
    if r == Start.None { r = try_setext(d, b, container); }
    if r == Start.None { r = try_thematic_break(d, b); }
    if r == Start.None { r = try_list_item(d, b, container); }
    if r == Start.None { r = try_indented_code(d, b); }
    if r == Start.None { r = try_table(d, b, container); }
    if r == Start.None { r = try_task(d, b, container); }
    return r;
}

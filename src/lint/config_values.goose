import std;
import json;
import lint.lists;

fn config_value(cat: i64, node: json::Node?) -> bool {
    guard node else { return false; }
    if cat == BAN {
        match node.val { Arr => {}, _ => { return false; } }
        let a = node.first;
        guard a else { return false; }
        let b = a.next;
        guard b && !b.next else { return false; }
        let word, ok = json::as_string(a);
        let replacement, valid = json::as_string(b);
        guard ok && valid && word.len > 0 && replacement.len > 0 else { return false; }
        add_entry(cat, word, replacement);
        return true;
    }
    let value, ok = json::as_string(node);
    guard ok && value.len > 0 else { return false; }
    add_entry(cat, if cat == EXCLUDE || cat == GENERATED { strip_dot(value) } else { value }, "");
    return true;
}

fn config_array(cat: i64, root: json::Node?) -> bool {
    guard root else { return false; }
    match root.val { Arr => {}, _ => { return false; } }
    var item = root.first;
    while item {
        guard config_value(cat, item) else { return false; }
        item .= item.next;
    }
    return true;
}

fn config_assignment(key: const u8[:], value: u8[:]) -> bool {
    let cat = position(CATEGORIES, trim(key));
    guard cat >= 0 && position(CONFIG_CATEGORIES, cat) >= 0 else { return false; }
    var nodes: json::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, error = json::parse(value, nodes, decoded);
    guard root && error.len == 0 else { return false; }
    return config_array(cat, root);
}

fn config_end(data: const u8[:], start: i64) -> i64 {
    var depth = 0;
    var quoted = false;
    var escaped = false;
    var i = start;
    while i < data.len {
        let c = data[i];
        if quoted {
            if escaped { escaped = false; }
            else if c == '\\' { escaped = true; }
            else if c == '"' { quoted = false; }
        } else if c == '"' { quoted = true; }
        else if c == '[' { depth++; }
        else if c == ']' { depth--; }
        else if c == '\n' && depth <= 0 { return i; }
        i++;
    }
    return i;
}

fn add_config(data: u8[:]) -> i64 {
    var at = 0;
    var line_no = 1;
    while at < data.len {
        let remaining = data[at..];
        let nl = position(remaining, '\n');
        let end = if nl < 0 { data.len } else { at + nl };
        let line = trim_end(data[at..end]);
        if line.len == 0 { at = min(end + 1, data.len); line_no++; continue; }
        let eq = position(line, '=');
        let tab = position(line, '\t');
        if eq < 0 || (tab >= 0 && tab < eq) {
            guard add_list_line(line, CONFIG_CATEGORIES) else { return line_no; }
            at = min(end + 1, data.len);
            line_no++;
            continue;
        }
        let stop = config_end(data, at + eq + 1);
        guard config_assignment(line[..eq], data[at + eq + 1..stop]) else { return line_no; }
        for c in data[at..stop] { if c == '\n' { line_no++; } }
        at = min(stop + 1, data.len);
        line_no++;
    }
    return 0;
}

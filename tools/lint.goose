import std;
import os;

let FILE_BUDGET = 300;
let FUNCTION_BUDGET = 40;
let USAGE = "usage: lint <specs.txt> <file.goose|file.sh>...\n";

fn finding(out: u8[>..]&, path: const u8[:], s: const u8[:], at: i64, rule: const u8[:]) {
    var line = 1;
    for c in s[..at] { if c == '\n' { line++; } }
    format(out, path, ":", line, ": ", rule, "\n");
}

fn line_end(s: const u8[:], i: i64) -> i64 {
    let n = position(s[i..], '\n');
    return if n < 0 { s.len } else { i + n };
}

fn skip_escaped(s: const u8[:], i: i64, quote: u8) -> i64 {
    var j = i + 1;
    while j < s.len && s[j] != quote {
        if s[j] == '\\' { j++; }
        j++;
    }
    return min(j + 1, s.len);
}

fn skip_block_comment(s: const u8[:], i: i64) -> i64 {
    var depth = 0;
    var j = i;
    while j < s.len {
        if starts_with(s[j..], "/*") {
            depth++;
            j += 2;
        } else if starts_with(s[j..], "*/") {
            depth--;
            j += 2;
            if depth == 0 { return j; }
        } else {
            j++;
        }
    }
    return j;
}

fn goose_comments(out: u8[>..]&, path: const u8[:], s: const u8[:]) {
    var i = 0;
    while i < s.len {
        let rest = s[i..];
        if starts_with(rest, "\"\"\"") {
            let end = find(s[i + 3..], "\"\"\"");
            i = if end < 0 { s.len } else { i + end + 6 };
        } else if s[i] == '"' || s[i] == '\'' {
            i = skip_escaped(s, i, s[i]);
        } else if starts_with(rest, "//") {
            finding(out, path, s, i, "comment");
            i = line_end(s, i);
        } else if starts_with(rest, "/*") {
            finding(out, path, s, i, "comment");
            i = skip_block_comment(s, i);
        } else {
            i++;
        }
    }
}

fn is_shell_word_break(c: u8) -> bool { position(" \t\n;&|()", c) >= 0 }

fn shell_comments(out: u8[>..]&, path: const u8[:], s: const u8[:]) {
    var i = if starts_with(s, "#!") { line_end(s, 0) } else { 0 };
    while i < s.len {
        let c = s[i];
        if c == '\'' {
            let end = position(s[i + 1..], '\'');
            i = if end < 0 { s.len } else { i + end + 2 };
        } else if c == '"' {
            i = skip_escaped(s, i, '"');
        } else if c == '\\' {
            i += 2;
        } else if c == '#' && (i == 0 || is_shell_word_break(s[i - 1])) {
            finding(out, path, s, i, "comment");
            i = line_end(s, i);
        } else if starts_with(s[i..], "<<") {
            finding(out, path, s, i, "heredoc (the lexer cannot read it)");
            i += 2;
        } else {
            i++;
        }
    }
}

fn function_name(line: const u8[:]) -> const u8[:] {
    var j = 3;
    while j < line.len && line[j] != '(' && line[j] != '<' { j++; }
    return line[3..j];
}

fn goose_functions(out: u8[>..]&, path: const u8[:], s: const u8[:], live: const u8[:][:]) {
    var at = 0;
    var start = -1;
    var start_at = 0;
    var line_no = 0;
    each_split(s, '\n') {
        line_no++;
        if starts_with(it, "fn ") {
            start = line_no;
            start_at = at;
            if position(live, function_name(it)) < 0 { finding(out, path, s, at, str("dead function ", function_name(it))); }
        }
        let one_line = starts_with(it, "fn ") && ends_with(it, "}");
        if start >= 0 && (one_line || it == "}") {
            let length = line_no - start + 1;
            if length > FUNCTION_BUDGET {
                finding(out, path, s, start_at, str("function has ", length, " lines, budget ", FUNCTION_BUDGET));
            }
            start = -1;
        }
        at += it.len + 1;
    }
}

fn live_functions(specs: const u8[:]) -> const u8[:][>..] {
    var live: const u8[:][>..] = [];
    each_split(specs, '\n') { if starts_with(it, "fn ") { live.push(function_name(it)); } }
    return live;
}

fn lint_file(out: u8[>..]&, path: const u8[:], live: const u8[:][:]) {
    var s: u8[>..] = [];
    guard read_file(path, s) else {
        format(out, path, ": cannot read\n");
        return;
    }
    let lines = count(s) { it == '\n' };
    if lines > FILE_BUDGET { finding(out, path, s, 0, str("file has ", lines, " lines, budget ", FILE_BUDGET)); }
    if ends_with(path, ".goose") {
        goose_comments(out, path, s);
        goose_functions(out, path, s, live);
    } else if ends_with(path, ".sh") {
        shell_comments(out, path, s);
    } else {
        format(out, path, ": no lexer for this file type\n");
    }
}

fn main() {
    let a = args();
    if a.len < 3 {
        write_stderr(USAGE);
        exit(2);
    }
    var specs: u8[>..] = [];
    guard read_file(a[1], specs) else {
        write_stderr(str("lint: cannot read ", a[1], "\n"));
        exit(2);
    }
    let live = live_functions(specs);
    var out: u8[>..] = [];
    for path in a[2..] { lint_file(out, path, live); }
    write_stdout(out);
    if out.len > 0 { exit(1); }
}

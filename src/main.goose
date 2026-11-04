import std;
import os;
import dictionary;
import md.node;
import md.parse;
import md.tree;
import lint.context;
import lint.check;
import fmt.run;

let VERSION = "0.2.0";
let USAGE = "usage: goosemarklint check <path>... | fmt [--check] <path>... | rules | tree <file>... | --version\n";

fn print_file_tree(path: const u8[:]) -> bool {
    var input: u8[>..] = [];
    guard read_file(path, input) else {
        write_stderr(str("goosemarklint: cannot read ", path, "\n"));
        return false;
    }
    var nodes: Node[>..] = [];
    var text: u8[>..] = [];
    var refs: Ref[>..] = [];
    var ref_index = dictionary<u64, i64> {};
    var line_cols: i64[>..] = [];
    var d = Doc { nodes: nodes, text: text, refs: refs, ref_index: ref_index, line_cols: line_cols, opts: gfm_opts() };
    parse_markdown(d, input);
    var out: u8[>..] = [];
    print_tree(d, out);
    write_stdout(out);
    return true;
}

fn print_trees(paths: u8[:][:]) -> i64 {
    var ok = true;
    for path in paths { if !print_file_tree(path) { ok = false; } }
    return if ok { 0 } else { 1 };
}

fn print_rules() -> i64 {
    for id in RULE_IDS { write_stdout(str(id, "\n")); }
    return 0;
}

fn main() {
    let a = args();
    let command = if a.len >= 2 { a[1] } else { "" };
    let fmt_code = if command == "fmt" { run_fmt(a[2..]) } else { -1 };
    let code = if command == "check" && a.len >= 3 {
        run_check(a[2..])
    } else if fmt_code >= 0 {
        fmt_code
    } else if command == "tree" && a.len >= 3 {
        print_trees(a[2..])
    } else if command == "--version" && a.len == 2 {
        write_stdout(str("goosemarklint ", VERSION, "\n"));
        0
    } else if command == "rules" && a.len == 2 {
        print_rules()
    } else {
        write_stderr(USAGE);
        2
    };
    if code != 0 { exit(code); }
}

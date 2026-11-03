import std;
import os;
import dictionary;
import md.node;
import md.parse;
import md.tree;

let USAGE = "usage: goosemarklint tree <file>...\n";

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

fn main() {
    let a = args();
    if a.len < 3 || a[1] != "tree" {
        write_stderr(USAGE);
        exit(2);
    }
    var ok = true;
    for path in a[2..] { if !print_file_tree(path) { ok = false; } }
    if !ok { exit(1); }
}

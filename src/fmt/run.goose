import std;
import os;
import dictionary;
import md.node;
import md.parse;
import lint.check;
import lint.lists;
import fmt.emit;
import fmt.walk;
import fmt.canon;

fn canon_of(input: const u8[:], opts: Opts, out: u8[>..]&) {
    var nodes: Node[>..] = [];
    var text: u8[>..] = [];
    var refs: Ref[>..] = [];
    var ref_index = dictionary<u64, i64> {};
    var line_cols: i64[>..] = [];
    var d = Doc { nodes: nodes, text: text, refs: refs, ref_index: ref_index, line_cols: line_cols, opts: opts };
    parse_markdown(d, input);
    canon_tree(d, out);
}

fn emit_doc(d: Doc&, out: u8[>..]&) {
    var starts: i64[>..] = [];
    var levels: Level[>..] = [];
    var marks: u8[>..] = [];
    var targets: i64[>..] = [];
    directive_targets(d, targets);
    var f = Fmt { d: d, starts: starts, targets: targets, out: out, levels: levels, marks: marks };
    index_starts(f);
    put_document(f);
}

fn format_markdown(input: const u8[:], opts: Opts, out: u8[>..]&) -> bool {
    var nodes: Node[>..] = [];
    var text: u8[>..] = [];
    var refs: Ref[>..] = [];
    var ref_index = dictionary<u64, i64> {};
    var line_cols: i64[>..] = [];
    var d = Doc { nodes: nodes, text: text, refs: refs, ref_index: ref_index, line_cols: line_cols, opts: opts };
    parse_markdown(d, input);
    emit_doc(d, out);
    var before: u8[>..] = [];
    canon_tree(d, before);
    var after: u8[>..] = [];
    canon_of(out, opts, after);
    return before == after;
}

fn format_file(path: const u8[:], check: bool) -> i64 {
    var input: u8[>..] = [];
    guard read_file(path, input) else {
        write_stderr(str("goosemarklint: cannot read ", path, "\n"));
        return 2;
    }
    var out: u8[>..] = [];
    guard format_markdown(input, gfm_opts(), out) else {
        write_stderr(str("goosemarklint: ", path, ": fmt would change the parse tree, so the file stays as it is\n"));
        return 2;
    }
    guard out != input else { return 0; }
    if check {
        write_stdout(str(path, ": not formatted\n"));
        return 1;
    }
    guard write_file_atomic(path, out) else {
        write_stderr(str("goosemarklint: cannot write ", path, "\n"));
        return 2;
    }
    return 0;
}

fn format_paths(paths: u8[:][:], check: bool) -> i64 {
    var files: u8[>..] = [];
    var code = 0;
    for path in paths {
        if is_dir(path) {
            if !collect_files(path, files) { code = 2; }
        } else {
            format(files, path, "\n");
        }
    }
    var list = split(files, '\n');
    sort(list) { a, b => compare(a, b) < 0 };
    for f in list {
        guard f.len > 0 && !is_excluded(f) && !is_generated(f);
        code = max(code, format_file(f, check));
    }
    return code;
}

fn run_fmt(args: u8[:][:]) -> i64 {
    let check = args.len > 0 && args[0] == "--check";
    let paths = if check { args[1..] } else { args };
    guard paths.len > 0 else { return -1; }
    guard load_config() else { return 2; }
    return format_paths(paths, check);
}

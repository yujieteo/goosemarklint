import std;
import os;
import dictionary;
import md.node;
import md.parse;
import lint.lists;
import lint.context;
import lint.prose;
import lint.tokens;
import lint.word_rules;
import lint.sentence_rules;
import lint.block_rules;
import lint.suppress;
import lint.profiles;

let CONFIG = ".goosemarklint";

fn check_inline_comments(L: Lint&, p: Prose&, b: i64) {
    var n = L.d.nodes[b].first;
    while n >= 0 {
        if L.d.nodes[n].kind == Kind.HtmlInline {
            let text = text_of(L.d, L.d.nodes[n].content);
            let off = content_pos(p, L.d.nodes[n].content.at);
            let line = line_at(L, off);
            check_comments(L, text, line, col_at(L, line, off));
        }
        n = next_in(L.d, n, b);
    }
}

fn check_prose_block(L: Lint&, p: Prose&, w: Words&, b: i64) {
    read_words(L, p, w, b);
    check_words(L, p, w);
    check_sentences(L, p, w);
    check_inline_comments(L, p, b);
    if L.d.nodes[b].kind == Kind.Heading { check_heading_emoji(L, p); }
    if L.d.nodes[b].kind == Kind.Paragraph { check_heavy_bold(L, b); }
}

fn check_tree(L: Lint&, p: Prose&, w: Words&) {
    var n = 0;
    while n >= 0 {
        let node = L.d.nodes[n];
        match node.kind {
            Paragraph, Heading, TableCell => check_prose_block(L, p, w, n),
            HtmlBlock => check_comments(L, text_of(L.d, node.content), node.line, max(node.col, 1)),
            List => check_bold_labels(L, n),
            _ => {},
        }
        n = if node.kind == Kind.Paragraph || node.kind == Kind.Heading || node.kind == Kind.TableCell {
            next_skip(L.d, n, 0)
        } else {
            next_in(L.d, n, 0)
        };
    }
    check_summary_heading(L, p);
    check_profile(L, p, w);
}

fn print_findings(out: u8[>..]&, path: const u8[:], L: Lint&) {
    stable_sort(L.found) { a, b => a.line < b.line || (a.line == b.line && (a.col < b.col || (a.col == b.col && a.rule < b.rule))) };
    for f in L.found {
        format(out, path, ":", f.line, ":", f.col, ": ", RULE_IDS[f.rule], ": ");
        out.append(L.msgs[f.msg.at..f.msg.at + f.msg.len]);
        out.push('\n');
    }
}

fn lint_source(out: u8[>..]&, path: const u8[:], input: const u8[:]) -> i64 {
    var nodes: Node[>..] = [];
    var text: u8[>..] = [];
    var refs: Ref[>..] = [];
    var ref_index = dictionary<u64, i64> {};
    var line_cols: i64[>..] = [];
    var d = Doc { nodes: nodes, text: text, refs: refs, ref_index: ref_index, line_cols: line_cols, opts: gfm_opts() };
    parse_markdown(d, input);
    var lines: i64[>..] = [];
    var found: Finding[>..] = [];
    var msgs: u8[>..] = [];
    var directives: Directive[>..] = [];
    var L = Lint { d: d, profile: profile_of(path), lines: lines, found: found, msgs: msgs, directives: directives };
    index_lines(L);
    var ptext: u8[>..] = [];
    var pos: i64[>..] = [];
    var cmap: i64[>..] = [];
    var p = Prose { text: ptext, pos: pos, cmap: cmap, .. };
    var toks: Tok[>..] = [];
    var sents: Sent[>..] = [];
    var w = Words { toks: toks, sents: sents };
    check_tree(L, p, w);
    apply_suppressions(L);
    print_findings(out, path, L);
    return L.found.len;
}

fn lint_file(out: u8[>..]&, path: const u8[:]) -> i64 {
    var input: u8[>..] = [];
    guard read_file(path, input) else {
        write_stderr(str("goosemarklint: cannot read ", path, "\n"));
        return -1;
    }
    return lint_source(out, path, input);
}

fn join_path(dir: const u8[:], name: const u8[:]) -> u8[>..] { str(dir, if ends_with(dir, "/") { "" } else { "/" }, name) }

fn add_dir_entries(dir: const u8[:], names: const u8[:], dirs: u8[>..]&, files: u8[>..]&) {
    each_split(names, '\n') {
        guard it.len > 0 && it[0] != '.' && it != "node_modules";
        let full = join_path(dir, it);
        if is_dir(full) {
            format(dirs, full, "\n");
        } else if ends_with(it, ".md") {
            format(files, full, "\n");
        }
    };
}

fn collect_files(root: const u8[:], files: u8[>..]&) -> bool {
    var dirs: u8[>..] = [];
    format(dirs, root, "\n");
    var at = 0;
    var ok = true;
    while at < dirs.len {
        let end = at + position(dirs[at..], '\n');
        var names: u8[>..] = [];
        if list_dir(dirs[at..end], names) {
            add_dir_entries(dirs[at..end], names, dirs, files);
        } else {
            write_stderr(str("goosemarklint: cannot list ", dirs[at..end], "\n"));
            ok = false;
        }
        at = end + 1;
    }
    return ok;
}

fn lint_dir(out: u8[>..]&, dir: const u8[:]) -> i64 {
    var files: u8[>..] = [];
    let ok = collect_files(dir, files);
    var list = split(files, '\n');
    sort(list) { a, b => compare(a, b) < 0 };
    var total = 0;
    for f in list {
        guard f.len > 0;
        let n = lint_file(out, f);
        if n < 0 { total = -1; } else if total >= 0 { total += n; }
    }
    return if ok { total } else { -1 };
}

fn load_config() -> bool {
    var text: u8[>..] = [];
    guard file_exists(CONFIG) && read_file(CONFIG, text) else { return true; }
    let bad = add_lists(text, CONFIG_CATEGORIES);
    guard bad == 0 else {
        write_stderr(str(CONFIG, ":", bad, ": write allow<TAB>word or ban<TAB>word<TAB>replacement\n"));
        return false;
    }
    return true;
}

fn run_check(paths: u8[:][:]) -> i64 {
    guard load_config() else { return 2; }
    var total = 0;
    var failed = false;
    for path in paths {
        var out: u8[>..] = [];
        let n = if is_dir(path) { lint_dir(out, path) } else { lint_file(out, path) };
        write_stdout(out);
        if n < 0 { failed = true; } else { total += n; }
    }
    return if failed { 2 } else if total > 0 { 1 } else { 0 };
}

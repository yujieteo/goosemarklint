import std;
import os;
import dictionary;
import md.node;
import md.parse;
import md.html;
import md.tree;

let FENCE = "````````````````````````````````";
let TAB_MARK = "\xE2\x86\x92";

struct Example { markdown: Span, expected: Span, section: Span, line: i64, opts: Opts, tree: bool }

enum Part { Prose, Markdown, Expected }

struct Tally { passed: i64 = 0, failed: i64 = 0 }

fn restore_tabs(out: u8[>..]&, s: const u8[:]) { format_replaced(out, s, TAB_MARK, "\t"); }

fn example_opts(profile: const u8[:], words: const u8[:][:]) -> Opts {
    if profile == "ext" { return gfm_opts(); }
    var o = Opts {};
    guard profile == "gfm" else { return o; }
    o.gfm_html = true;
    for w in words {
        if w == "table" { o.table = true; }
        if w == "strikethrough" { o.strike = true; }
        if w == "autolink" { o.autolink = true; }
        if w == "tagfilter" { o.tagfilter = true; }
        if w == "disabled" { o.tasklist = true; }
    }
    return o;
}

fn put(buf: u8[>..]&, s: const u8[:]) -> Span {
    let at = buf.len;
    buf.append(s);
    return Span { at: at, len: s.len };
}

fn collect(profile: const u8[:], spec: const u8[:], buf: u8[>..]&, out: Example[>..]&) {
    var section = Span {};
    var part = Part.Prose;
    var line_no = 0;
    var current = Example { markdown: Span {}, expected: Span {}, section: Span {}, line: 0, opts: Opts {}, tree: false };
    var md_at = 0;
    each_split(spec, '\n') {
        line_no++;
        if part == Part.Prose && starts_with(it, FENCE) && it.len > FENCE.len {
            let words = words(it[FENCE.len..]);
            guard words.len > 0 && words[0] == "example";
            current.opts = example_opts(profile, words[1..]);
            current.tree = position(words, "tree") >= 0;
            current.section = section;
            current.line = line_no;
            md_at = buf.len;
            part = Part.Markdown;
        } else if part == Part.Prose && starts_with(it, "#") {
            section = put(buf, trim(it));
        } else if part == Part.Markdown && it == "." {
            current.markdown = Span { at: md_at, len: buf.len - md_at };
            md_at = buf.len;
            part = Part.Expected;
        } else if part == Part.Expected && it == FENCE {
            current.expected = Span { at: md_at, len: buf.len - md_at };
            out.push(current);
            part = Part.Prose;
        } else if part != Part.Prose {
            restore_tabs(buf, it);
            buf.push('\n');
        }
    };
}

fn report(e: Example, buf: const u8[:], file: const u8[:], got: const u8[:]) {
    var msg: u8[>..] = [];
    format(msg, "FAIL ", file, ":", e.line, " ", buf[e.section.at..e.section.at + e.section.len], "\n");
    format(msg, "--- markdown\n", buf[e.markdown.at..e.markdown.at + e.markdown.len]);
    format(msg, "--- expected\n", buf[e.expected.at..e.expected.at + e.expected.len]);
    format(msg, "--- got\n", got, "\n");
    write_stdout(msg);
}

fn run_example(e: Example, buf: const u8[:], file: const u8[:], t: Tally&) {
    var nodes: Node[>..] = [];
    var text: u8[>..] = [];
    var refs: Ref[>..] = [];
    var ref_index = dictionary<u64, i64> {};
    var line_cols: i64[>..] = [];
    var d = Doc { nodes: nodes, text: text, refs: refs, ref_index: ref_index, line_cols: line_cols, opts: e.opts };
    parse_markdown(d, buf[e.markdown.at..e.markdown.at + e.markdown.len]);
    var got: u8[>..] = [];
    if e.tree { print_tree(d, got); } else { render_html(d, got); }
    if got == buf[e.expected.at..e.expected.at + e.expected.len] {
        t.passed++;
    } else {
        t.failed++;
        report(e, buf, file, got);
    }
}

fn count_openings(spec: const u8[:]) -> i64 {
    var n = 0;
    each_split(spec, '\n') { if starts_with(it, FENCE) && it.len > FENCE.len { n++; } };
    return n;
}

fn run_file(profile: const u8[:], file: const u8[:], t: Tally&) -> bool {
    var spec: u8[>..] = [];
    guard read_file(file, spec) else {
        write_stdout(str("cannot read ", file, "\n"));
        return false;
    }
    var buf: u8[>..] = [];
    var examples: Example[>..] = [];
    collect(profile, spec, buf, examples);
    let before = t.failed;
    for e in examples { run_example(e, buf, file, t); }
    write_stdout(str(file, ": ", examples.len, " examples, ", t.failed - before, " failed\n"));
    let openings = count_openings(spec);
    guard examples.len == openings else {
        write_stdout(str(file, ": ", openings - examples.len, " of ", openings, " examples not collected\n"));
        return false;
    }
    return examples.len > 0;
}

fn main() {
    let a = args();
    var t = Tally {};
    var ok = a.len >= 3 && a.len % 2 == 1;
    var i = 1;
    while i + 1 < a.len {
        if !run_file(a[i], a[i + 1], t) { ok = false; }
        i += 2;
    }
    write_stdout(str(t.passed, " passed, ", t.failed, " failed\n"));
    if !ok || t.failed > 0 { exit(1); }
}

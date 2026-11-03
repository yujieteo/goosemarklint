import std;
import md.node;
import md.html_scan;
import lint.context;
import lint.prose;
import lint.tokens;
import lint.sentence_rules;
import lint.suppress;

fn profile_of(path: const u8[:]) -> Profile {
    let slash = rfind(path, "/");
    let name = path[slash + 1..];
    if lower_equal(name, "readme.md") { return Profile.Readme; }
    if lower_equal(name, "skill.md") { return Profile.Skill; }
    if lower_equal(name, "agents.md") || lower_equal(name, "claude.md") { return Profile.Agents; }
    return Profile.Docs;
}

fn has_word(s: const u8[:], word: const u8[:]) -> bool {
    var found = false;
    var start = 0;
    for c, i in s {
        let letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        if !letter {
            if lower_equal(s[start..i], word) { found = true; }
            start = i + 1;
        }
    }
    return found || lower_equal(s[start..], word);
}

fn indented_end(fm: const u8[:], from: i64) -> i64 {
    var i = from;
    while i < fm.len && (fm[i] == ' ' || fm[i] == '\t' || fm[i] == '\n') {
        let e = position(fm[i..], '\n');
        i = if e < 0 { fm.len } else { i + e + 1 };
    }
    return i;
}

fn key_value(fm: const u8[:], key: const u8[:]) -> const u8[:], i64 {
    var line_no = 0;
    var i = 0;
    while i < fm.len {
        let e = position(fm[i..], '\n');
        let end = if e < 0 { fm.len } else { i + e };
        let line = fm[i..end];
        if starts_with(line, key) && line.len > key.len && line[key.len] == ':' {
            let rest = trim(line[key.len + 1..]);
            guard rest.len == 0 || position("|>", rest[0]) >= 0 else { return rest, line_no; }
            let from = min(end + 1, fm.len);
            return trim(fm[from..indented_end(fm, from)]), line_no;
        }
        i = end + 1;
        line_no++;
    }
    return "", -1;
}

fn is_header(L: Lint&, n: i64) -> bool {
    let k = L.d.nodes[n].kind;
    return k == Kind.FrontMatter || (k == Kind.HtmlBlock && is_directive(trim(text_of(L.d, L.d.nodes[n].content))));
}

fn report_file(L: Lint&, rule: const u8[:], msg: const u8[:]) {
    var n = L.d.nodes[0].first;
    while n >= 0 && is_header(L, n) { n = L.d.nodes[n].next; }
    if n >= 0 { report_node(L, n, rule, msg); } else { report_at(L, 1, 1, rule, msg); }
}

fn check_skill(L: Lint&) {
    let fm = L.d.nodes[0].first;
    guard fm >= 0 && L.d.nodes[fm].kind == Kind.FrontMatter else {
        report_file(L, "skill-front-matter", "SKILL.md has no front matter: add name and description");
        return;
    };
    let text = text_of(L.d, L.d.nodes[fm].content);
    let name, name_at = key_value(text, "name");
    if name.len == 0 { report_file(L, "skill-front-matter", "front matter has no name"); }
    let desc, desc_at = key_value(text, "description");
    if desc.len == 0 {
        report_file(L, "skill-front-matter", "front matter has no description");
    } else if !has_word(desc, "when") {
        report_at(L, desc_at + 2, 1, "skill-front-matter", "description does not say when to load the skill: add \"Use when ...\"");
    }
}

fn check_agents_item(L: Lint&, p: Prose&, w: Words&, item: i64) {
    let para = L.d.nodes[item].first;
    guard para >= 0 && L.d.nodes[para].kind == Kind.Paragraph;
    read_words(L, p, w, para);
    guard w.sents.len > 0 && !is_instruction(p, w, w.sents[0]);
    report(L, p.pos[w.toks[0].at], "agents-imperative", "list item does not start with an imperative verb");
}

fn has_words(L: Lint&, p: Prose&, w: Words&, b: i64) -> bool {
    read_words(L, p, w, b);
    return any(w.toks) { is_word(it) };
}

fn purpose_block(L: Lint&, p: Prose&, w: Words&) -> i64 {
    var n = L.d.nodes[0].first;
    var title = true;
    while n >= 0 {
        let k = L.d.nodes[n].kind;
        let skip = k == Kind.FrontMatter || k == Kind.HtmlBlock || (title && k == Kind.Heading && L.d.nodes[n].level == 1);
        title = title && skip;
        guard skip || (k == Kind.Paragraph && !has_words(L, p, w, n)) else { return n; }
        n = L.d.nodes[n].next;
    }
    return -1;
}

fn check_purpose(L: Lint&, p: Prose&, w: Words&) {
    let b = purpose_block(L, p, w);
    guard b >= 0 && L.d.nodes[b].kind == Kind.Paragraph else {
        if b >= 0 { report_node(L, b, "readme-purpose", "README has no purpose paragraph after the title"); }
        else { report_file(L, "readme-purpose", "README has no purpose paragraph after the title"); }
        return;
    };
    read_words(L, p, w, b);
    let n = count(w.sents) { word_count(w, it) > 0 };
    guard n != 1;
    report_node(L, b, "readme-purpose", str("first paragraph has ", n, " sentences: state the purpose in 1 sentence"));
}

fn check_run_block(L: Lint&) {
    let fenced = any(L.d.nodes) { it.kind == Kind.CodeBlock && it.fenced && it.parent >= 0 };
    guard !fenced;
    report_file(L, "readme-run-block", "README has no fenced code block: show the run steps in one");
}

fn check_profile(L: Lint&, p: Prose&, w: Words&) {
    match L.profile {
        Skill => check_skill(L),
        Readme => {
            check_purpose(L, p, w);
            check_run_block(L);
        },
        Agents => for node, i in L.d.nodes { if node.kind == Kind.Item && node.parent >= 0 { check_agents_item(L, p, w, i); } },
        Docs => {},
    }
}

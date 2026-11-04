import std;
import md.node;
import lint.context;

let DIRECTIVE = "goosemarklint-disable-next-line";
let SYNTAX = "<!-- goosemarklint-disable-next-line RULE: reason -->";

fn comment_body(t: const u8[:]) -> const u8[:] { trim(t[4..if ends_with(t, "-->") && t.len >= 7 { t.len - 3 } else { t.len }]) }

fn is_directive(t: const u8[:]) -> bool { starts_with(t, "<!--") && starts_with(comment_body(t), "goosemarklint-") }

fn is_marker(t: const u8[:]) -> bool { t.len > 4 && ends_with(t, "-->") && ((t[4] >= 'a' && t[4] <= 'z') || t[4] == '/') }

fn check_comment(L: Lint&, t: const u8[:], line: i64, col: i64) {
    guard is_directive(t) && ends_with(t, "-->") else {
        if !is_marker(t) { report_at(L, line, col, "html-comment", "HTML comment: delete it, or move the fact into code or a test"); }
        return;
    }
    let why = read_directive(L, comment_body(t), line, col, line + count(t) { it == '\n' });
    if why.len > 0 { report_at(L, line, col, "suppression", str(why, ": write ", SYNTAX)); }
}

fn check_comments(L: Lint&, text: const u8[:], line: i64, col: i64) {
    var ln = line;
    var ls = 0;
    var seen = 0;
    var at = find(text, "<!--");
    while at >= 0 {
        for c, k in text[seen..at] {
            if c == '\n' {
                ln++;
                ls = seen + k + 1;
            }
        }
        seen = at;
        let e = find(text[at + 2..], "-->");
        let end = if e < 0 { text.len } else { at + e + 5 };
        check_comment(L, text[at..end], ln, col + count(text[ls..at]) { (it & 0xC0) != 0x80 });
        let next = find(text[end..], "<!--");
        at = if next < 0 { -1 } else { end + next };
    }
}

fn read_directive(L: Lint&, body: const u8[:], line: i64, col: i64, end_line: i64) -> const u8[:] {
    guard starts_with(body, DIRECTIVE) && body.len > DIRECTIVE.len && body[DIRECTIVE.len] == ' ' else { return "unknown directive"; }
    let rest = body[DIRECTIVE.len..];
    let colon = position(rest, ':');
    guard colon >= 0 && trim(rest[colon + 1..]).len > 0 else { return "directive has no reason"; }
    let ids = words(rest[..colon]);
    guard ids.len > 0 else { return "directive names no rule"; }
    for id in ids { guard position(RULE_IDS, id) >= 0 && id != "suppression" else { return "directive names an unknown rule"; } }
    for id in ids { guard id != "repeated-fact" else { return "directive names repeated-fact, and a directive cannot stop it"; } }
    let at = L.msgs.len;
    L.msgs.append(rest[..colon]);
    L.directives.push(Directive { line: line, col: col, target: end_line + 1, rules: Span { at: at, len: colon } });
    return "";
}

fn suppresses(L: Lint&, dir: Directive, f: Finding) -> bool {
    guard dir.target == f.line && RULE_IDS[f.rule] != "suppression" else { return false; }
    let ids = words(L.msgs[dir.rules.at..dir.rules.at + dir.rules.len]);
    return position(ids, RULE_IDS[f.rule]) >= 0;
}

fn apply_suppressions(L: Lint&) {
    var kept = 0;
    for i in L.found.len {
        var hit = false;
        for &dir in L.directives {
            if suppresses(L, dir, L.found[i]) {
                dir.used = true;
                hit = true;
            }
        }
        if !hit {
            L.found[kept] = L.found[i];
            kept++;
        }
    }
    while L.found.len > kept { L.found.pop(); }
    for dir in L.directives {
        guard !dir.used;
        report_at(L, dir.line, dir.col, "suppression", str("directive suppresses nothing on line ", dir.target));
    }
}

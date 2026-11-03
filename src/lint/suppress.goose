import std;
import md.node;
import lint.context;

let DIRECTIVE = "goosemarklint-disable-next-line";
let SYNTAX = "<!-- goosemarklint-disable-next-line RULE: reason -->";

fn comment_body(t: const u8[:]) -> const u8[:] { trim(t[4..if ends_with(t, "-->") && t.len >= 7 { t.len - 3 } else { t.len }]) }

fn check_comment(L: Lint&, text: const u8[:], off: i64, end_line: i64) {
    let t = trim(text);
    guard starts_with(t, "<!--");
    let body = comment_body(t);
    if !starts_with(body, "goosemarklint-") || !ends_with(t, "-->") {
        report(L, off, "html-comment", "HTML comment: delete it, or move the fact into code or a test");
        return;
    }
    let why = read_directive(L, body, off, end_line);
    if why.len > 0 { report(L, off, "suppression", str(why, ": write ", SYNTAX)); }
}

fn read_directive(L: Lint&, body: const u8[:], off: i64, end_line: i64) -> const u8[:] {
    guard starts_with(body, DIRECTIVE) && body.len > DIRECTIVE.len && body[DIRECTIVE.len] == ' ' else { return "unknown directive"; }
    let rest = body[DIRECTIVE.len..];
    let colon = position(rest, ':');
    guard colon >= 0 && trim(rest[colon + 1..]).len > 0 else { return "directive has no reason"; }
    let ids = words(rest[..colon]);
    guard ids.len > 0 else { return "directive names no rule"; }
    for id in ids { guard position(RULE_IDS, id) >= 0 && id != "suppression" else { return "directive names an unknown rule"; } }
    let at = L.msgs.len;
    L.msgs.append(rest[..colon]);
    let line = line_at(L, off);
    L.directives.push(Directive { line: line, col: col_at(L, line, off), target: end_line + 1, rules: Span { at: at, len: colon } });
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

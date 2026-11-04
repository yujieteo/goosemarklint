import std;

enum FactKind { Sentence, Version, Hash, List }

struct Fact { kind: FactKind, path: Span, line: i64, col: i64, key: Span, ends: Span }

struct Facts { text: u8[>..]&, items: Fact[>..]&, path: Span, skip: bool = false }

fn put_fact_text(F: Facts&, s: const u8[:]) -> Span {
    let at = F.text.len;
    F.text.append(s);
    return Span { at: at, len: s.len };
}

fn add_fact(F: Facts&, kind: FactKind, line: i64, col: i64, key: const u8[:], ends: const u8[:]) {
    guard !F.skip;
    let k = put_fact_text(F, key);
    let e = put_fact_text(F, ends);
    F.items.push(Fact { kind: kind, path: F.path, line: line, col: col, key: k, ends: e });
}

fn fact_key(F: Facts&, f: Fact) -> const u8[:] { F.text[f.key.at..f.key.at + f.key.len] }

fn fact_ends(F: Facts&, f: Fact) -> const u8[:] { F.text[f.ends.at..f.ends.at + f.ends.len] }

fn fact_path(F: Facts&, f: Fact) -> const u8[:] { F.text[f.path.at..f.path.at + f.path.len] }

fn find_root(up: i64[>..]&, i: i64) -> i64 {
    var k = i;
    while up[k] != k {
        up[k] = up[up[k]];
        k = up[k];
    }
    return k;
}

fn join(up: i64[>..]&, a: i64, b: i64) {
    let ra = find_root(up, a);
    let rb = find_root(up, b);
    if ra < rb { up[rb] = ra; } else { up[ra] = rb; }
}

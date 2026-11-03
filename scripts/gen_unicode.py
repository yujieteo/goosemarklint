import sys
import unicodedata


def ranges(pred):
    out = []
    start = None
    for cp in range(0x110000):
        hit = pred(cp)
        if hit and start is None:
            start = cp
        if not hit and start is not None:
            out.append((start, cp - 1))
            start = None
    return out


def main(path):
    lines = ["unicode " + unicodedata.unidata_version]
    for lo, hi in ranges(lambda cp: unicodedata.category(chr(cp))[0] in "PS"):
        lines.append("p %X %X" % (lo, hi))
    for lo, hi in ranges(lambda cp: unicodedata.category(chr(cp)) == "Zs"):
        lines.append("z %X %X" % (lo, hi))
    for cp in range(0x110000):
        folded = chr(cp).casefold()
        if folded != chr(cp):
            lines.append("f %X " % cp + " ".join("%X" % ord(c) for c in folded))
    with open(path, "w", encoding="ascii") as f:
        f.write("\n".join(lines) + "\n")


main(sys.argv[1])

#!/usr/bin/env python3
"""DEX gate: Glance widget call sites must link against the packaged API.

Why this exists (2026-11-23 launch blocker): pipeline 1125 shipped BOTH store
AABs and the Pro kit whose compiled widget call sites referenced
GlanceAppWidgetKt.provideContent(GlanceAppWidget, Function0, Continuation)
while the packaged glance-appwidget-1.1.1 classes carry only the
(..., Function2 <composable lambda>, ...) signature. Every Glance tile died
with NoSuchMethodError ("Can't show content") on the launcher -- invisible to
kotlinc, D8, R8 and every unit/e2e test, fatal in production.

Gate: open a built .aab/.apk, parse each dex method-id table (stdlib only),
and FAIL if any method reference whose descriptor takes
(GlanceAppWidget, Function0, Continuation) is present, or if the APK/AAB
ships dev.steiner widget classes but no provideContent linkage at all.
Class-name-keyed checks would miss R8-renamed owners, so the linkage key is
the PARAMETER descriptor, not the declaring class or method name.

Usage: widget_dex_gate.py <artifact.aab|artifact.apk> [...]
Exit 0 = ship-clean, 1 = violation, 2 = script/IO/parse error (a probe that
cannot run must never read as clean -- measurement M9).
"""
import struct
import sys
import zipfile

RECEIVER = "Landroidx/glance/appwidget/GlanceAppWidget;"
WIDGET_PKG = "Ldev/steiner/local_budget/widget/"
BAD_PARAMS = (RECEIVER, "Lkotlin/jvm/functions/Function0;",
              "Lkotlin/coroutines/Continuation;")
GOOD_PARAMS = (RECEIVER, "Lkotlin/jvm/functions/Function2;",
               "Lkotlin/coroutines/Continuation;")


def _uleb(b, o):
    r = s = 0
    while True:
        x = b[o]
        o += 1
        r |= (x & 0x7F) << s
        if not x & 0x80:
            return r, o
        s += 7


def _strings(b):
    ssz, soff = struct.unpack_from("<II", b, 56)
    out = []
    for i in range(ssz):
        off, = struct.unpack_from("<I", b, soff + 4 * i)
        ln, o = _uleb(b, off)
        out.append(b[o:o + ln].decode("utf-8", "replace"))
    return out


def scan_dex(b):
    """Return (bad_refs, good_refs, widget_classes) for one dex buffer."""
    if b[:4] != b"dex\n":
        raise ValueError("not a dex file")
    header_size, = struct.unpack_from("<I", b, 0x24)
    if header_size != 0x70:
        raise ValueError(f"unexpected dex header_size {header_size:#x} "
                         "(parser maps the fixed 0x70 header; refuse to "
                         "guess)")
    ss = _strings(b)
    tsz, toff = struct.unpack_from("<II", b, 64)
    types = [ss[struct.unpack_from("<I", b, toff + 4 * i)[0]]
             for i in range(tsz)]
    psz, poff = struct.unpack_from("<II", b, 72)
    protos = []
    for i in range(psz):
        rty, = struct.unpack_from("<I", b, poff + 12 * i + 4)
        prm, = struct.unpack_from("<I", b, poff + 12 * i + 8)
        plist = []
        if prm:
            cnt, = struct.unpack_from("<I", b, prm)
            o = prm + 4
            for _ in range(cnt):
                tidx, = struct.unpack_from("<H", b, o)
                o += 2
                plist.append(types[tidx])
        protos.append((types[rty], tuple(plist)))
    msz, moff = struct.unpack_from("<II", b, 88)
    bad = good = 0
    for i in range(msz):
        cidx, pidx = struct.unpack_from("<HH", b, moff + 8 * i)
        _rty, plist = protos[pidx]
        if plist == BAD_PARAMS:
            bad += 1
        elif plist == GOOD_PARAMS:
            good += 1
    widgets = {t for t in types if t.startswith(WIDGET_PKG)
               and "$" not in t}
    return bad, good, widgets


def scan_artifact(path):
    bad = good = 0
    widgets = set()
    with zipfile.ZipFile(path) as z:
        dexes = [n for n in z.namelist()
                 if n.endswith(".dex") and not n.startswith("__proto")]
        if not dexes:
            raise ValueError(f"{path}: contains no dex entries")
        for name in dexes:
            b, g, w = scan_dex(z.read(name))
            bad += b
            good += g
            widgets |= w
    return bad, good, widgets, len(dexes)


def main(argv):
    if len(argv) < 2:
        print("usage: widget_dex_gate.py <artifact> [...]", file=sys.stderr)
        return 2
    failed = False
    for path in argv[1:]:
        try:
            bad, good, widgets, ndex = scan_artifact(path)
        except Exception as exc:  # noqa: BLE001 - probe must name itself
            print(f"widget_dex_gate: ERROR {path}: {exc}", file=sys.stderr)
            return 2
        if bad:
            print(f"widget_dex_gate: FAIL {path}: {bad} reference(s) to "
                  f"provideContent(GlanceAppWidget, Function0, Continuation)"
                  f" -- compiled against a Glance API that is NOT packaged"
                  f" (widgets crash with NoSuchMethodError at launch).")
            failed = True
        elif widgets and not good:
            print(f"widget_dex_gate: FAIL {path}: widget classes present "
                  f"({sorted(widgets)[:3]}...) but zero "
                  f"provideContent(GlanceAppWidget, Function2, ...) linkage"
                  f" found in {ndex} dex file(s).")
            failed = True
        else:
            print(f"widget_dex_gate: OK {path} ({ndex} dex, "
                  f"{good} good linkage, 0 bad, {len(widgets)} widget "
                  f"class(es))")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

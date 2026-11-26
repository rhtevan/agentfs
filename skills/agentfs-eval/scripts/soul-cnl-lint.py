#!/usr/bin/env python3
"""soul-cnl-lint.py — deterministic CNL lint for SOUL.md principles.

Usage: soul-cnl-lint.py <SOUL.md | variant.md> [--tsv]

Sources (knowledge/context-engineering/cnl-authoring-for-weak-models.md,
evaluation-methodology.md §2 prose types):
  L1 C7  principle form: a situation trigger (When/Before/If/...) or a standing
         imperative                                            FAIL if neither
  L2 C5  counter-behaviour present (Do not / Never / No ...)   WARN
  L3 C2  active imperative: no passive voice, no modal hedging FAIL
         each sentence is an instruction (imperative verb, Do not, No <x>)
                                                               WARN (heuristic)
  L4 C1  one instruction per sentence (no 'and/then/also <verb>', no ';')
                                                               WARN (heuristic)
  L5 C3  single vocabulary across the section (synonym groups) FAIL
  L6 C8  no cross-principle references (heading names, see above/below) FAIL;
         content bigram shared by 2+ principles                WARN
  L7     sentence <= 20 words, principle <= 45 words, <= 8 principles  WARN
Lint predicts adherence; it never claims it (runtime tests decide).
Output: one line per finding, then SOUL_CNL=PASS|WARN|FAIL (exit 1 on FAIL).
--tsv: 'LEVEL<TAB>message' lines plus 'SUMMARY<TAB>sig<TAB>fails<TAB>warns'.
"""
import re, sys

TRIGGER = re.compile(r"^(When|Whenever|Before|After|If|Once|On|Unless|While|Until)\b")
CONNECTOR = re.compile(r"^(Otherwise|Then|Also|Instead|Still|Always|Only),?\s+")
COUNTER = re.compile(r"\b(Do not|Don't|do not|Never|never)\b|^No\s|\bNo\s+\w+")
PASSIVE = re.compile(r"\b(is|are|was|were|be|been|being)\s+(not\s+)?(\w+ed|made|done|kept|met|set|built|shown|told|known|given|taken|found|held|left|put|sent|seen|said|brought|grounded|written|chosen|meant)\b", re.I)
HEDGE = re.compile(r"\b(should|may|might|could|would|ought to|try to|you may want|consider)\b", re.I)
VERBS = set("""act add answer apply ask avoid build call change chase check choose cite confirm copy correct
delete describe diagnose do drop end explain find finish fix flag follow get give guess hold ignore invent keep
lead leave list log make mark measure mention move name note offer open paste pause pick point present prove
push quote read record refuse reject remove repeat replace report request resolve restate retry return reverse
review rewrite run say search send show skip start state stay stop surface take tell test treat trust update
use verify wait warn write""".split())
SYNONYMS = [("task", "request", "job"), ("user", "operator", "human"),
            ("approval", "consent", "permission", "confirmation", "authori"),
            ("fix", "patch", "repair"), ("error", "fault", "failure"), ("risk", "hazard", "danger"),
            ("check", "verify", "confirm", "validate"), ("evidence", "proof"), ("anomal", "inconsisten", "discrepan"),
            ("assum", "presum", "suppos"), ("reply", "response", "message")]
STOP = set("a an the and or of to in on for with from by is are be it its this that you your any each every "
           "not do no as at when before if what which who than then also only so until".split())


def principles(text):
    m = re.search(r"^## Principles\s*$(.*?)(?=^## |^<!--|\Z)", text, re.M | re.S)
    sec = m.group(1) if m else text
    items = re.findall(r"^- \*\*(.+?)\*\*\s*(.*?)(?=^- \*\*|\Z)", sec, re.M | re.S)
    return [(h.rstrip(".").strip(), " ".join(b.split())) for h, b in items]


def sentences(body):
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+(?=[A-Z])", body) if s.strip()]


def head_word(s):
    s = CONNECTOR.sub("", s)
    if TRIGGER.match(s):
        s = s.split(",", 1)[1].strip() if "," in s else ""
    w = re.findall(r"[A-Za-z']+", s)
    return (w[0].lower() if w else ""), s


def lint(text):
    out = []
    add = lambda lvl, code, msg: out.append((lvl, f"{code}: {msg}"))
    ps = principles(text)
    if not ps:
        add("FAIL", "L0", "no '- **Name.** body' principles found")
        return out
    full = " ".join(b for _, b in ps).lower()
    for h, body in ps:
        ss = sentences(body)
        heads = [head_word(s) for s in ss]
        has_trigger = any(TRIGGER.match(CONNECTOR.sub("", s)) for s in ss)
        standing = bool(heads) and heads[0][0] in VERBS | {"do", "never", "no"}
        if not (has_trigger or standing):
            add("FAIL", "L1", f"{h}: no situation trigger and no standing imperative")
        if not COUNTER.search(body):
            add("WARN", "L2", f"{h}: no counter-behaviour (Do not / Never / No ...)")
        for m in PASSIVE.finditer(body):
            add("FAIL", "L3", f"{h}: passive voice '{m.group(0)}'")
        for m in HEDGE.finditer(body):
            add("FAIL", "L3", f"{h}: modal hedging '{m.group(0)}'")
        for (w, rest), s in zip(heads, ss):
            if w and w not in VERBS and w not in ("do", "never", "no", "don't"):
                add("WARN", "L3", f"{h}: not an instruction: '{s[:60]}'")
            if ";" in s or re.search(r"\b(and|then|also)\s+(" + "|".join(VERBS) + r")\b", rest):
                add("WARN", "L4", f"{h}: more than one instruction: '{s[:70]}'")
            if len(s.split()) > 20:
                add("WARN", "L7", f"{h}: sentence of {len(s.split())} words")
        if len(body.split()) > 45:
            add("WARN", "L7", f"{h}: {len(body.split())} words")
        for h2, _ in ps:
            if h2 != h and re.search(r"\b" + re.escape(h2.lower()) + r"\b", body.lower()):
                add("FAIL", "L6", f"{h}: refers to principle '{h2}'")
        if re.search(r"\b(see|as)\s+(above|below)\b", body, re.I):
            add("FAIL", "L6", f"{h}: positional reference (above/below)")
    for grp in SYNONYMS:
        used = sorted({g for g in grp if re.search(r"\b" + g, full)})
        if len(used) > 1:
            add("FAIL", "L5", f"mixed vocabulary for one concept: {used}")
    bigrams = {}
    for h, body in ps:
        w = re.findall(r"[a-z']+", body.lower())
        for a, b in zip(w, w[1:]):
            if a not in STOP and b not in STOP and len(a) > 3 and len(b) > 3:
                bigrams.setdefault(f"{a} {b}", set()).add(h)
    for bg, hs in sorted(bigrams.items()):
        if len(hs) > 1:
            add("WARN", "L6", f"term '{bg}' shared by {sorted(hs)} (defined once, used twice?)")
    if len(ps) > 8:
        add("WARN", "L7", f"{len(ps)} principles (keep as few as possible)")
    return out


def main():
    if len(sys.argv) < 2:
        print(__doc__); return 2
    text = open(sys.argv[1]).read()
    res = lint(text)
    nf, nw = sum(l == "FAIL" for l, _ in res), sum(l == "WARN" for l, _ in res)
    sig = "FAIL" if nf else "WARN" if nw else "PASS"
    if "--tsv" in sys.argv:
        for l, m in res:
            print(f"{l}\t{m}")
        print(f"SUMMARY\t{sig}\t{nf}\t{nw}")
        return 0
    for l, m in res:
        print(f"  [{l}] {m}")
    print(f"{len(principles(text))} principles; {nf} fail, {nw} warn")
    print(f"SOUL_CNL={sig}")
    return 1 if sig == "FAIL" else 0


if __name__ == "__main__":
    sys.exit(main())

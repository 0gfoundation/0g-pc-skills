#!/usr/bin/env python3
"""tests/triggers.py — trigger-phrase exclusivity across the 0G skills (issue #84).

    python3 tests/triggers.py

No key, no network. It checks the descriptions, which is what the router reads to
pick a skill; it does not drive the router itself, so it proves the phrases are
unambiguous rather than that a given model chose correctly.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
# The three Claude skills that must not overlap each other.
UNDER_TEST = ("0g-pc-setup", "0g-pc-switch-model", "0g-pc-uninstall")
# Retired, still on disk until #86; Codex is a different client entirely.
OUT_OF_SCOPE = ("0g-pc-model-config-claude", "0g-pc-model-config-codex")

# Each input must match trigger phrases from exactly one skill.
MATRIX = [
    ("帮我接入 0G",              "0g-pc-setup"),
    ("把 Claude Code 接到 0G",   "0g-pc-setup"),
    ("配置 0G",                  "0g-pc-setup"),
    ("set up 0G PC",             "0g-pc-setup"),
    ("我想换个模型",             "0g-pc-switch-model"),
    ("切到 glm-5.3",             "0g-pc-switch-model"),
    ("换成别的 0G 模型",         "0g-pc-switch-model"),
    ("switch 0G model",          "0g-pc-switch-model"),
    ("不用 0G 了",               "0g-pc-uninstall"),
    ("退回原来的 API",           "0g-pc-uninstall"),
    ("卸载 0G",                  "0g-pc-uninstall"),
    ("go back to Anthropic",     "0g-pc-uninstall"),
]

# Decided in #84: diagnosis routes to no skill. /0g-pc-setup refuses to start once
# a config exists, so sending "it is broken" there dead-ends; letting it accept
# instead would put the mode inference back that this split removed.
UNROUTED = ["0G 配置不工作", "0G 用不了了", "0G is broken"]

# A request naming Codex must not land on a Claude skill. "set up 0G PC" is a
# substring of "set up 0G PC in Codex", so this is settled by specificity, and by
# 0g-pc-setup's description saying in words that Codex is not its client.
CROSS_CLIENT = [
    ("set up 0G PC in Codex",  "0g-pc-model-config-codex"),
    ("在 Codex 接入 0G PC",     "0g-pc-model-config-codex"),
]


def triggers(name):
    text = (ROOT / "skills" / name / "SKILL.md").read_text()
    desc = re.search(r'^description:\s*(.+)$', text.split("---")[1], re.M).group(1)
    return desc, [p for p in re.findall(r'"([^"]+)"', desc)]


def matches(phrases, text):
    low = text.lower()
    return sorted({p for p in phrases if p.lower() in low}, key=len, reverse=True)


def best(skills, text):
    """Longest matching phrase wins.

    Substring matching alone cannot separate "set up 0G PC" from "set up 0G PC in
    Codex" — one contains the other, and no wording of the shorter phrase changes
    that. Specificity is what separates them, and length is how specificity shows
    up here."""
    hits = {n: matches(ps, text) for n, ps in skills.items() if matches(ps, text)}
    if not hits:
        return None, {}
    top = max(len(m[0]) for m in hits.values())
    win = [n for n, m in hits.items() if len(m[0]) == top]
    return (win[0] if len(win) == 1 else None), hits


def main():
    fails = []
    skills = {n: triggers(n)[1] for n in UNDER_TEST}

    print("triggers per skill")
    for n, ps in skills.items():
        print(f"  {n:22} {len(ps):>2} phrases")

    print("\npairwise overlap (a phrase of one inside a phrase of another)")
    for a in UNDER_TEST:
        for b in UNDER_TEST:
            if a >= b:
                continue
            for pa in skills[a]:
                for pb in skills[b]:
                    if pa.lower() in pb.lower() or pb.lower() in pa.lower():
                        fails.append(f"{a} {pa!r} overlaps {b} {pb!r}")
                        print(f"  FAIL  {a} {pa!r}  <->  {b} {pb!r}")
    if not fails:
        print("  none")

    print("\nrouting matrix")
    for text, want in MATRIX:
        hits = {n: matches(ps, text) for n, ps in skills.items()}
        got = [n for n, m in hits.items() if m]
        if got == [want]:
            print(f"  ok    {text:24} -> {want}  via {hits[want][0]!r}")
        else:
            fails.append(f"{text!r} -> {got or 'nothing'}, wanted {want}")
            print(f"  FAIL  {text:24} -> {got or 'nothing'}, wanted {want}")

    print("\ndiagnosis stays unrouted (#84 decision)")
    for text in UNROUTED:
        got = [n for n, ps in skills.items() if matches(ps, text)]
        if got:
            fails.append(f"{text!r} routes to {got}, should route nowhere")
            print(f"  FAIL  {text:24} -> {got}")
        else:
            print(f"  ok    {text:24} -> no skill, as decided")

    print("\ncross-client: a Codex request must not land on a Claude skill")
    allsk = dict(skills)
    allsk["0g-pc-model-config-codex"] = triggers("0g-pc-model-config-codex")[1]
    for text, want in CROSS_CLIENT:
        got, hits = best(allsk, text)
        if got == want:
            print(f"  ok    {text:24} -> {want}  via {hits[want][0]!r}")
        else:
            fails.append(f"{text!r} -> {got or 'ambiguous'}, wanted {want}")
            print(f"  FAIL  {text:24} -> {got or 'ambiguous'}  hits={ {k: v[0] for k, v in hits.items()} }")

    print("\nout of scope, reported not enforced")
    for n in OUT_OF_SCOPE:
        _, ps = triggers(n)
        clash = sorted({p for p in ps
                        for m in UNDER_TEST for q in skills[m]
                        if p.lower() in q.lower() or q.lower() in p.lower()})
        note = "retired, removed in #86" if n.endswith("config-claude") else "different client"
        print(f"  {n:26} {len(clash)} phrase(s) shared with the new three — {note}")
        for p in clash:
            print(f"      {p!r}")

    print(f"\n{'FAILED: ' + str(len(fails)) if fails else 'PASSED'}")
    for f in fails:
        print("  " + f)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())

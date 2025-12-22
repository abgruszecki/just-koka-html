#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
from pathlib import Path
from typing import List

from html5lib_allowlists import (
    AllowlistError,
    DEFAULT_PATH,
    add_indices,
    count_tokenizer_cases,
    count_tree_construction_cases,
    discover_tokenizer_fixtures,
    discover_tree_construction_fixtures,
    format_ranges,
    get_indices,
    load_from_git,
    load,
    parse_ranges,
    repo_root_from_tools_path,
    save,
    total_counts,
)


def _path(p: str) -> Path:
    return Path(p).expanduser().resolve()

def _git_rev_parse(repo_root: Path, rev: str) -> str | None:
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--verify", rev],
            cwd=str(repo_root),
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except subprocess.CalledProcessError:
        return None
    out = (proc.stdout or "").strip()
    return out or None


def cmd_show(args: argparse.Namespace) -> int:
    data = load(args.file)
    kinds = [args.kind] if args.kind else ["tree-doc", "tree-frag", "tokenizer"]
    for kind in kinds:
        if args.fixture:
            fixtures = [args.fixture]
        else:
            if kind == "tree-doc":
                fixtures = sorted(data["tree"]["doc"].keys())
            elif kind == "tree-frag":
                fixtures = sorted(data["tree"]["frag"].keys())
            else:
                fixtures = sorted(data["tokenizer"].keys())

        for fx in fixtures:
            xs = get_indices(data, kind, fx)
            if args.ranges:
                shown = format_ranges(xs)
            else:
                shown = " ".join(str(i) for i in xs)
            print(f"{kind} {fx}  count={len(xs)}")
            print(f"  {shown}")
    return 0


def cmd_stats(args: argparse.Namespace) -> int:
    data = load(args.file)
    repo_root = repo_root_from_tools_path()

    def pct(enabled: int, total: int) -> str:
        if total <= 0:
            return "n/a"
        return f"{(enabled * 100.0 / total):.1f}%"

    # ---- Totals (enabled only) ----
    enabled_totals = total_counts(data)
    print("Enabled totals:")
    for k in ["tree-doc", "tree-frag", "tokenizer"]:
        print(f"  {k}: {enabled_totals[k]}")

    # ---- Totals (enabled vs total available) ----
    tree_paths = discover_tree_construction_fixtures(repo_root)
    tok_paths = discover_tokenizer_fixtures(repo_root)

    # Tree-construction has duplicate basenames under `tree-construction/scripted/`.
    # Our allowlists are keyed by basename (e.g. "webkit01.dat"), so we aggregate totals
    # across all matching paths for the same basename.
    tree_totals_by_fixture = {}
    for p in tree_paths:
        d, f = count_tree_construction_cases(p)
        fx = p.name
        prev_d, prev_f = tree_totals_by_fixture.get(fx, (0, 0))
        tree_totals_by_fixture[fx] = (prev_d + d, prev_f + f)

    tree_doc_total = sum(d for d, _f in tree_totals_by_fixture.values())
    tree_frag_total = sum(f for _d, f in tree_totals_by_fixture.values())
    tok_total = sum(count_tokenizer_cases(p) for p in tok_paths)

    print("")
    print("Coverage totals:")
    print(f"  tree-doc: {enabled_totals['tree-doc']}/{tree_doc_total} ({pct(enabled_totals['tree-doc'], tree_doc_total)})")
    print(f"  tree-frag: {enabled_totals['tree-frag']}/{tree_frag_total} ({pct(enabled_totals['tree-frag'], tree_frag_total)})")
    print(f"  tokenizer: {enabled_totals['tokenizer']}/{tok_total} ({pct(enabled_totals['tokenizer'], tok_total)})")

    print("")
    print("Per fixture:")

    # Tree-construction: show *all* .dat basenames, even if allowlist has no entry yet.
    print("tree-doc:")
    for fx in sorted(tree_totals_by_fixture.keys()):
        total_doc, _total_frag = tree_totals_by_fixture[fx]
        enabled = len(get_indices(data, "tree-doc", fx))
        print(f"  {fx}: {enabled}/{total_doc} ({pct(enabled, total_doc)})")

    print("tree-frag:")
    for fx in sorted(tree_totals_by_fixture.keys()):
        _total_doc, total_frag = tree_totals_by_fixture[fx]
        if total_frag == 0:
            continue
        enabled = len(get_indices(data, "tree-frag", fx))
        print(f"  {fx}: {enabled}/{total_frag} ({pct(enabled, total_frag)})")

    # Tokenizer: show *all* .test files.
    print("tokenizer:")
    for p in tok_paths:
        fx = p.name
        total = count_tokenizer_cases(p)
        enabled = len(get_indices(data, "tokenizer", fx))
        print(f"  {fx}: {enabled}/{total} ({pct(enabled, total)})")
    return 0


def cmd_add(args: argparse.Namespace) -> int:
    data = load(args.file)
    to_add: List[int] = []
    for item in args.add or []:
        # Allow passing either "1,2,5-7" or "12" etc.
        to_add.extend(parse_ranges(item))
    if not to_add:
        raise AllowlistError("Nothing to add: provide --add ...")

    before, after = add_indices(data, args.kind, args.fixture, to_add)
    print(f"{args.kind} {args.fixture}: {before} -> {after} (+{after - before})")

    if args.write:
        save(data, args.file)
        print(f"Wrote {args.file}")
    else:
        print("Dry-run (pass --write to persist).")
    return 0


def cmd_diff_prev(args: argparse.Namespace) -> int:
    repo_root = repo_root_from_tools_path()
    cur = load(args.file)
    try:
        prev = load_from_git(repo_root, rev=args.rev)
    except AllowlistError as e:
        # Common case: first commit in a repo (HEAD~1 doesn't exist) or shallow fetch.
        # Treat "previous" as "current" so the command still produces stable output.
        print(f"warning: {e}")
        print("warning: treating previous allowlists as current (no diff baseline available)")
        prev = cur

    def pct(enabled: int, total: int) -> float | None:
        if total <= 0:
            return None
        return enabled * 100.0 / total

    def fmt_pct(x: float | None) -> str:
        return "n/a" if x is None else f"{x:.1f}%"

    tree_paths = discover_tree_construction_fixtures(repo_root)
    tok_paths = discover_tokenizer_fixtures(repo_root)

    # Aggregate tree totals by basename (see comment in stats).
    tree_totals_by_fixture = {}
    for p in tree_paths:
        d, f = count_tree_construction_cases(p)
        fx = p.name
        prev_d, prev_f = tree_totals_by_fixture.get(fx, (0, 0))
        tree_totals_by_fixture[fx] = (prev_d + d, prev_f + f)

    tree_doc_total = sum(d for d, _f in tree_totals_by_fixture.values())
    tree_frag_total = sum(f for _d, f in tree_totals_by_fixture.values())
    tok_totals_by_fixture = {p.name: count_tokenizer_cases(p) for p in tok_paths}
    tok_total = sum(tok_totals_by_fixture.values())

    def enabled_map(data, kind: str):
        if kind == "tree-doc":
            sec = data["tree"]["doc"]
        elif kind == "tree-frag":
            sec = data["tree"]["frag"]
        elif kind == "tokenizer":
            sec = data["tokenizer"]
        else:
            raise AllowlistError(f"Unknown kind: {kind}")
        # Normalize to basename->count (missing => 0 handled by get_indices elsewhere)
        return sec

    decreased = False

    def print_kind_totals(kind: str, before_enabled: int, after_enabled: int, total: int):
        nonlocal decreased
        delta = after_enabled - before_enabled
        before_p = pct(before_enabled, total)
        after_p = pct(after_enabled, total)
        pp = None if (before_p is None or after_p is None) else (after_p - before_p)
        if delta < 0 or (pp is not None and pp < 0):
            decreased = True
        pp_s = "n/a" if pp is None else f"{pp:+.1f}pp"
        print(f"{kind}: {before_enabled}/{total} ({fmt_pct(before_p)}) -> {after_enabled}/{total} ({fmt_pct(after_p)})  Δ{delta:+d}  {pp_s}")

    resolved = _git_rev_parse(repo_root, args.rev)
    rev_label = resolved or args.rev
    file_path = Path(args.file).resolve()
    try:
        file_label = str(file_path.relative_to(repo_root))
    except ValueError:
        file_label = str(file_path)

    print(f"Comparing allowlists: {rev_label} -> working tree ({file_label})")
    print("")

    before_tot = total_counts(prev)
    after_tot = total_counts(cur)

    print("Totals:")
    print_kind_totals("tree-doc", before_tot["tree-doc"], after_tot["tree-doc"], tree_doc_total)
    print_kind_totals("tree-frag", before_tot["tree-frag"], after_tot["tree-frag"], tree_frag_total)
    print_kind_totals("tokenizer", before_tot["tokenizer"], after_tot["tokenizer"], tok_total)

    # Per fixture diffs (show only changes unless --all).
    def fixture_rows(kind: str):
        if kind == "tree-doc":
            fixtures = sorted(tree_totals_by_fixture.keys())
            totals = {fx: tree_totals_by_fixture[fx][0] for fx in fixtures}
        elif kind == "tree-frag":
            fixtures = sorted([fx for fx, (_d, f) in tree_totals_by_fixture.items() if f > 0])
            totals = {fx: tree_totals_by_fixture[fx][1] for fx in fixtures}
        elif kind == "tokenizer":
            fixtures = sorted(tok_totals_by_fixture.keys())
            totals = tok_totals_by_fixture
        else:
            raise AllowlistError(f"Unknown kind: {kind}")
        return fixtures, totals

    for kind in ["tree-doc", "tree-frag", "tokenizer"]:
        print("")
        print(f"Per fixture ({kind}):")
        fixtures, totals = fixture_rows(kind)
        for fx in fixtures:
            total = totals.get(fx, 0)
            b = len(get_indices(prev, kind, fx))
            a = len(get_indices(cur, kind, fx))
            if not args.all and b == a:
                continue
            delta = a - b
            bp = pct(b, total)
            ap = pct(a, total)
            pp = None if (bp is None or ap is None) else (ap - bp)
            if delta < 0 or (pp is not None and pp < 0):
                decreased = True
            pp_s = "n/a" if pp is None else f"{pp:+.1f}pp"
            print(f"  {fx}: {b}/{total} ({fmt_pct(bp)}) -> {a}/{total} ({fmt_pct(ap)})  Δ{delta:+d}  {pp_s}")

    if args.fail_on_decrease and decreased:
        return 1
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="Manage data/html5lib_allowlists.json")
    p.add_argument("--file", type=_path, default=DEFAULT_PATH, help="Path to allowlists JSON")

    sub = p.add_subparsers(dest="cmd", required=True)

    ps = sub.add_parser("show", help="Show enabled indices (optionally as ranges)")
    ps.add_argument("--kind", choices=["tree-doc", "tree-frag", "tokenizer"], help="Restrict to one kind")
    ps.add_argument("--fixture", help="Restrict to one fixture")
    ps.add_argument("--ranges", action="store_true", help="Show indices as compressed ranges (e.g. 1-5,7)")
    ps.set_defaults(func=cmd_show)

    pst = sub.add_parser("stats", help="Print counts per fixture and totals")
    pst.set_defaults(func=cmd_stats)

    pa = sub.add_parser("add", help="Add indices/ranges to a fixture (dry-run by default)")
    pa.add_argument("--kind", required=True, choices=["tree-doc", "tree-frag", "tokenizer"])
    pa.add_argument("--fixture", required=True)
    pa.add_argument(
        "--add",
        action="append",
        help='Indices/ranges to add, e.g. --add "12" --add "20-30" --add "1,2,5-7"',
    )
    pa.add_argument("--write", action="store_true", help="Persist changes to JSON (otherwise dry-run)")
    pa.set_defaults(func=cmd_add)

    pd = sub.add_parser("diff-prev", help="Compare allowlists vs previous commit (git show) and optionally fail on decreases")
    pd.add_argument("--rev", default="HEAD~1", help='Git revision to compare against (default: "HEAD~1")')
    pd.add_argument("--all", action="store_true", help="Show all fixtures (otherwise only fixtures that changed)")
    pd.add_argument("--fail-on-decrease", action="store_true", help="Exit non-zero if any enabled count/percentage decreases")
    pd.set_defaults(func=cmd_diff_prev)

    args = p.parse_args()
    try:
        return int(args.func(args))
    except AllowlistError as e:
        p.error(str(e))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

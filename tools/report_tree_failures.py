#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

from html5lib_allowlists import _split_tree_construction_blocks, repo_root_from_tools_path
from run_html5lib_tests import build_runner, parse_tree_block, run_tree_cases_batch


ROOT = repo_root_from_tools_path()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fixture", required=True, help="tree-construction .dat filename (e.g. comments01.dat)")
    ap.add_argument("--kind", choices=["doc", "frag"], default="doc")
    ap.add_argument("--limit", type=int, default=20, help="max mismatches to print")
    ap.add_argument(
        "--show",
        help='show details for one case as "<index>" within the chosen kind (e.g. "3")',
    )
    args = ap.parse_args()

    exe = ROOT / ".build" / "html5_runner"
    build_runner(exe)

    tree_dir = ROOT / "html5lib-tests" / "tree-construction"
    fx_path = tree_dir / args.fixture
    raw = fx_path.read_text(encoding="utf-8", errors="replace")
    blocks = _split_tree_construction_blocks(raw)

    show_idx = int(args.show) if args.show is not None else None
    cases: list[dict[str, Any]] = []
    expect: list[tuple[int, str, int]] = []

    doc_i = 0
    frag_i = 0
    for block in blocks:
        parsed = parse_tree_block(block)
        is_frag = parsed["fragment_context"] is not None
        if args.kind == "frag" and is_frag:
            if show_idx is not None and frag_i != show_idx:
                frag_i += 1
                continue
            cases.append(
                {
                    "kind": "frag",
                    "context": parsed["fragment_context"],
                    "scripting": parsed["scripting"],
                    "input": parsed["input"],
                }
            )
            expect.append((frag_i, parsed["expected"], int(parsed["error_count"])))
            frag_i += 1
        elif args.kind == "doc" and not is_frag:
            if show_idx is not None and doc_i != show_idx:
                doc_i += 1
                continue
            cases.append(
                {
                    "kind": "doc",
                    "context": "-",
                    "scripting": parsed["scripting"],
                    "input": parsed["input"],
                }
            )
            expect.append((doc_i, parsed["expected"], int(parsed["error_count"])))
            doc_i += 1
        else:
            if is_frag:
                frag_i += 1
            else:
                doc_i += 1

    got_batch = run_tree_cases_batch(exe, cases)
    mismatches: list[str] = []

    for (orig_idx, exp_tree, exp_errs), out in zip(expect, got_batch, strict=True):
        if not (isinstance(out, list) and len(out) == 2):
            mismatches.append(f"{args.fixture} {args.kind} #{orig_idx}: invalid runner output shape")
            continue
        got_tree, got_errs = out
        if show_idx is not None and orig_idx == show_idx:
            print(f"fixture: {args.fixture}")
            print(f"kind: {args.kind}")
            print(f"index: {orig_idx}")
            print("\ninput:")
            print(cases[0]["input"])
            print("\nexpected tree:")
            print(exp_tree)
            print("\ngot tree:")
            print(got_tree)
            print(f"\nexpected errors: {exp_errs}")
            print(f"got errors: {got_errs}")
            return 1
        if got_tree != exp_tree or int(got_errs) != exp_errs:
            if len(mismatches) < args.limit:
                mismatches.append(f"{args.fixture} {args.kind} #{orig_idx}: mismatch")

    if mismatches:
        for line in mismatches:
            print(line)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

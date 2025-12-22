#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

from html5lib_allowlists import (
    load,
    save,
    repo_root_from_tools_path,
    _split_tree_construction_blocks,
)
from run_html5lib_tests import build_runner, parse_tree_block, run_tree_cases_batch


ROOT = repo_root_from_tools_path()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--allowlists", default=str(ROOT / "data/html5lib_allowlists.json"))
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    allowlists_path = Path(args.allowlists)
    data = load(allowlists_path)

    exe = ROOT / ".build" / "html5_runner"
    build_runner(exe)

    tree_dir = ROOT / "html5lib-tests" / "tree-construction"

    for fx_path in sorted(tree_dir.glob("*.dat")):
        fx = fx_path.name
        blocks = _split_tree_construction_blocks(fx_path.read_text(encoding="utf-8", errors="replace"))

        doc_cases: list[dict[str, Any]] = []
        doc_expect: list[tuple[int, str, int]] = []
        frag_cases: list[dict[str, Any]] = []
        frag_expect: list[tuple[int, str, int]] = []

        doc_i = 0
        frag_i = 0
        for raw in blocks:
            parsed = parse_tree_block(raw)
            is_frag = parsed["fragment_context"] is not None
            if is_frag:
                frag_cases.append(
                    {
                        "kind": "frag",
                        "context": parsed["fragment_context"],
                        "scripting": parsed["scripting"],
                        "input": parsed["input"],
                    }
                )
                frag_expect.append((frag_i, parsed["expected"], int(parsed["error_count"])))
                frag_i += 1
            else:
                doc_cases.append(
                    {
                        "kind": "doc",
                        "context": "-",
                        "scripting": parsed["scripting"],
                        "input": parsed["input"],
                    }
                )
                doc_expect.append((doc_i, parsed["expected"], int(parsed["error_count"])))
                doc_i += 1

        doc_passing: list[int] = []
        if doc_cases:
            got = run_tree_cases_batch(exe, doc_cases)
            for (idx, exp_tree, exp_errs), out in zip(doc_expect, got, strict=True):
                if not (isinstance(out, list) and len(out) == 2):
                    continue
                got_tree, got_errs = out
                if got_tree == exp_tree and int(got_errs) == exp_errs:
                    doc_passing.append(idx)

        frag_passing: list[int] = []
        if frag_cases:
            got = run_tree_cases_batch(exe, frag_cases)
            for (idx, exp_tree, exp_errs), out in zip(frag_expect, got, strict=True):
                if not (isinstance(out, list) and len(out) == 2):
                    continue
                got_tree, got_errs = out
                if got_tree == exp_tree and int(got_errs) == exp_errs:
                    frag_passing.append(idx)

        before_doc = len(data["tree"]["doc"].get(fx, []))
        before_frag = len(data["tree"]["frag"].get(fx, []))
        data["tree"]["doc"][fx] = doc_passing
        data["tree"]["frag"][fx] = frag_passing
        after_doc = len(doc_passing)
        after_frag = len(frag_passing)

        print(f"{fx}: doc Δ{after_doc - before_doc:+d} (now {after_doc})  frag Δ{after_frag - before_frag:+d} (now {after_frag})")

    if args.write:
        save(data, allowlists_path)
        print(f"Wrote {allowlists_path}")
    else:
        print("Dry-run (pass --write to persist).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


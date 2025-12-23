#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from html5lib_allowlists import (
    load,
    save,
    repo_root_from_tools_path,
    add_indices,
    count_tokenizer_cases,
    discover_tokenizer_fixtures,
)
from run_html5lib_tests import _state_arg_from_html5lib, build_runner, normalize_tokenizer_case, run_tokenizer_cases_batch


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

    tok_dir = ROOT / "html5lib-tests" / "tokenizer"
    for p in discover_tokenizer_fixtures(ROOT):
        fx = p.name
        payload = json.loads((tok_dir / fx).read_text(encoding="utf-8"))
        tests = payload.get("tests") or payload.get("xmlViolationTests") or []
        tok_cmd = "tokenizer-batch-xml" if "xmlViolationTests" in payload else "tokenizer-batch"
        assert len(tests) == count_tokenizer_cases(p)

        expanded: list[dict[str, Any]] = []
        mapping: list[tuple[int, list[Any]]] = []
        for idx, case in enumerate(tests):
            input_text, expected_output, last0 = normalize_tokenizer_case(case)
            state_names = case.get("initialStates") or ["Data state"]
            last = last0 or "-"
            try:
                states = [_state_arg_from_html5lib(s) for s in state_names]
            except Exception:
                continue
            for st in states:
                expanded.append({"state": st, "last": last, "input": input_text})
                mapping.append((idx, expected_output))

        # A case "passes" only if it matches expected output for every initialState entry.
        ok = [True] * len(tests)
        if expanded:
            got_batch = run_tokenizer_cases_batch(exe, expanded, cmd=tok_cmd)
            for (idx, expected), got in zip(mapping, got_batch, strict=True):
                if got != expected:
                    ok[idx] = False

        passing = [idx for idx, is_ok in enumerate(ok) if is_ok]

        before = len(data["tokenizer"].get(fx, []))
        data["tokenizer"][fx] = sorted(passing)
        after = len(passing)
        delta = after - before
        print(f"{fx}: Δ{delta:+d} (now {after})")

    if args.write:
        save(data, allowlists_path)
        print(f"Wrote {allowlists_path}")
    else:
        print("Dry-run (pass --write to persist).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

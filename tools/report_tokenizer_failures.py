#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from html5lib_allowlists import count_tokenizer_cases, discover_tokenizer_fixtures, repo_root_from_tools_path
from run_html5lib_tests import _state_arg_from_html5lib, build_runner, normalize_tokenizer_case, run_tokenizer_cases_batch


ROOT = repo_root_from_tools_path()


def iter_cases(payload: dict[str, Any]) -> list[dict[str, Any]]:
    tests = payload.get("tests") or payload.get("xmlViolationTests") or []
    return list(tests)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fixture", help="only check this fixture filename (e.g. test3.test)")
    ap.add_argument("--limit", type=int, default=50, help="max mismatches to print")
    ap.add_argument(
        "--show",
        help='show details for one case as "fixture#index#State" (e.g. "test3.test#12#RCDATA")',
    )
    args = ap.parse_args()

    exe = ROOT / ".build" / "html5_runner"
    build_runner(exe)

    tok_dir = ROOT / "html5lib-tests" / "tokenizer"
    show_req: tuple[str, int, str] | None = None
    if args.show:
        try:
            fx, idx_s, st = args.show.split("#", 2)
            show_req = (fx, int(idx_s), st)
        except Exception as e:  # noqa: BLE001
            raise SystemExit(f"invalid --show value: {args.show!r} ({e})")

    mismatches: list[str] = []

    for p in discover_tokenizer_fixtures(ROOT):
        fx = p.name
        if args.fixture and fx != args.fixture:
            continue

        payload = json.loads((tok_dir / fx).read_text(encoding="utf-8"))
        tests = iter_cases(payload)
        assert len(tests) == count_tokenizer_cases(p)

        expanded: list[dict[str, Any]] = []
        mapping: list[tuple[int, str, list[Any]]] = []
        for idx, case in enumerate(tests):
            input_text, expected_output, last0 = normalize_tokenizer_case(case)
            state_names = case.get("initialStates") or ["Data state"]
            last = last0 or "-"
            try:
                states = [_state_arg_from_html5lib(s) for s in state_names]
            except Exception:
                # Unknown initial state entry; skip for now.
                continue
            for st in states:
                expanded.append({"state": st, "last": last, "input": input_text})
                mapping.append((idx, st, expected_output))

        if not expanded:
            continue

        got_batch = run_tokenizer_cases_batch(exe, expanded)
        ok = [True] * len(tests)
        for (idx, st, expected), got in zip(mapping, got_batch, strict=True):
            if got != expected:
                ok[idx] = False
                if len(mismatches) < args.limit:
                    mismatches.append(f"{fx} #{idx} ({st}): mismatch")
            if show_req and (fx, idx, st) == show_req:
                print(f"fixture: {fx}")
                print(f"index: {idx}")
                print(f"state: {st}")
                print(f"lastStartTag: {last0!r}")
                print("input:")
                print(input_text)
                print("\nexpected:")
                print(json.dumps(expected, ensure_ascii=False))
                print("\ngot:")
                print(json.dumps(got, ensure_ascii=False))
                return 1

        fail_count = sum(1 for is_ok in ok if not is_ok)
        print(f"{fx}: {len(tests) - fail_count}/{len(tests)} passing  ({fail_count} failing)")

    if mismatches:
        print("\nFirst mismatches:")
        for line in mismatches:
            print("  " + line)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

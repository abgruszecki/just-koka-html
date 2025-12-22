#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Iterable

from html5lib_allowlists import load, repo_root_from_tools_path, get_indices


ROOT = repo_root_from_tools_path()


def build_runner(exe: Path) -> None:
    exe.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["koka", "--rebuild", "--include=src", "-O2", "-o", str(exe), "src/cli.kk"],
        cwd=str(ROOT),
        check=True,
    )
    exe.chmod(0o755)


def _iter_enabled(kind: str, fixture: str, indices: list[int]) -> Iterable[tuple[int, Any]]:
    for idx in indices:
        yield idx, idx


def run_tokenizer_case(exe: Path, case: dict[str, Any]) -> list[Any]:
    input_text = case["input"]
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as f:
        f.write(input_text)
        input_path = f.name
    state_names = case.get("initialStates") or ["Data state"]
    # For now: only run Data state; other states will be enabled later.
    if state_names != ["Data state"]:
        raise RuntimeError("non-Data initialStates not supported yet")
    state = "Data"
    last = case.get("lastStartTag") or "-"
    proc = subprocess.run(
        [str(exe), "tokenizer", state, last, input_path],
        cwd=str(ROOT),
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    return json.loads(proc.stdout)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--allowlists", default=str(ROOT / "data/html5lib_allowlists.json"))
    ap.add_argument("--build", action="store_true", help="rebuild runner before running")
    args = ap.parse_args()

    data = load(Path(args.allowlists))
    exe = ROOT / ".build" / "html5_runner"
    if args.build or not exe.exists():
        build_runner(exe)

    failures: list[str] = []

    tok_dir = ROOT / "html5lib-tests" / "tokenizer"
    for fx in sorted(data["tokenizer"].keys()):
        enabled = get_indices(data, "tokenizer", fx)
        if not enabled:
            continue
        payload = json.loads((tok_dir / fx).read_text(encoding="utf-8"))
        tests = payload.get("tests") or payload.get("xmlViolationTests") or []
        for idx in enabled:
            case = tests[idx]
            try:
                got = run_tokenizer_case(exe, case)
            except Exception as e:  # noqa: BLE001
                failures.append(f"tokenizer {fx} #{idx}: runner failed: {e}")
                continue
            expected = case["output"]
            if got != expected:
                failures.append(f"tokenizer {fx} #{idx}: mismatch")

    if failures:
        for line in failures[:50]:
            print(line, file=sys.stderr)
        print(f"{len(failures)} failing cases", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

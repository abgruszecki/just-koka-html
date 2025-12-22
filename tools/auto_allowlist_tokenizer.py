#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
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


ROOT = repo_root_from_tools_path()


def build_runner(exe: Path) -> None:
    exe.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["koka", "--rebuild", "--include=src", "-O2", "-o", str(exe), "src/cli.kk"],
        cwd=str(ROOT),
        check=True,
    )
    exe.chmod(0o755)


def run_tokenizer_case(exe: Path, case: dict[str, Any]) -> list[Any] | None:
    if (case.get("initialStates") or ["Data state"]) != ["Data state"]:
        return None
    if case.get("errors"):
        return None
    input_text = case["input"]
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as f:
        f.write(input_text)
        input_path = f.name
    proc = subprocess.run(
        [str(exe), "tokenizer", "Data", "-", input_path],
        cwd=str(ROOT),
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    return json.loads(proc.stdout)


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
        assert len(tests) == count_tokenizer_cases(p)

        passing: list[int] = []
        for idx, case in enumerate(tests):
            got = run_tokenizer_case(exe, case)
            if got is None:
                continue
            if got == case["output"]:
                passing.append(idx)

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

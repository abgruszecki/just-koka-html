#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

from html5lib_allowlists import load, repo_root_from_tools_path, get_indices


ROOT = repo_root_from_tools_path()


def build_runner(exe: Path) -> None:
    exe.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["koka", "--include=src", "-O2", "-o", str(exe), "src/cli.kk"],
        cwd=str(ROOT),
        check=True,
    )
    exe.chmod(0o755)


def run_tokenizer_cases_batch(exe: Path, cases: list[dict[str, Any]]) -> list[list[Any]]:
    lines: list[str] = [str(len(cases))]
    for case in cases:
        state_names = case.get("initialStates") or ["Data state"]
        if state_names != ["Data state"]:
            raise RuntimeError("non-Data initialStates not supported yet")
        state = "Data"
        last = case.get("lastStartTag") or "-"
        payload = base64.b64encode(case["input"].encode("utf-8", "surrogatepass")).decode("ascii")
        lines.append(f"{state}\t{last}\t{len(payload)}")
        chunk_size = 900  # Koka std/os/readline caps at 1023 chars.
        lines.extend(payload[i : i + chunk_size] for i in range(0, len(payload), chunk_size))

    proc = subprocess.run(
        [str(exe), "tokenizer-batch"],
        cwd=str(ROOT),
        check=True,
        input="\n".join(lines) + "\n",
        stdout=subprocess.PIPE,
        text=True,
    )
    out = json.loads(proc.stdout)
    assert isinstance(out, list)
    return out  # list[case_output]


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
        batch = [tests[idx] for idx in enabled]
        try:
            got_batch = run_tokenizer_cases_batch(exe, batch)
        except Exception as e:  # noqa: BLE001
            failures.append(f"tokenizer {fx}: runner failed: {e}")
            continue

        for idx, got in zip(enabled, got_batch, strict=True):
            expected = tests[idx]["output"]
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

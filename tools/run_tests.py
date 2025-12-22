#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD_DIR = ROOT / ".build"
EXE = BUILD_DIR / "m0_smoke"


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, cwd=ROOT, check=True)


def build_runner() -> None:
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    run(
        [
            "koka",
            "--include=src",
            "-o",
            str(EXE),
            "src/runner.kk",
        ]
    )
    EXE.chmod(0o755)


def smoke_test() -> None:
    expected = "\n".join(
        [
            "| <html>",
            "|   <head>",
            "|   <body>",
            "|     <p>",
            '|       "Hello"',
        ]
    )
    got = subprocess.check_output([str(EXE)], cwd=ROOT, text=True)
    if got != expected:
        sys.stderr.write("Smoke test failed.\n")
        sys.stderr.write("Expected:\n" + expected + "\n")
        sys.stderr.write("Got:\n" + got + "\n")
        raise SystemExit(1)


def main() -> int:
    build_runner()
    smoke_test()
    run(["python3", "tools/run_html5lib_tests.py", "--build"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

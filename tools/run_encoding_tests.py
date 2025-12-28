#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import json
import subprocess
from pathlib import Path

from html5lib_allowlists import repo_root_from_tools_path
from run_html5lib_tests import build_runner


ROOT = repo_root_from_tools_path()


def _split_encoding_blocks(raw: str) -> list[str]:
    # Encoding fixtures are a repeating:
    #   #data\n...\n#encoding\n...\n
    raw = raw.replace("\r\n", "\n")
    parts = raw.split("\n#data\n")
    if parts[0].strip() == "#data":
        # file started with "#data\n"
        parts = ["", *parts[1:]]
    blocks: list[str] = []
    for chunk in parts[1:]:
        blocks.append("#data\n" + chunk)
    return blocks


def _parse_encoding_block(block: str) -> tuple[str, str]:
    lines = block.replace("\r\n", "\n").split("\n")
    if not lines or lines[0] != "#data":
        raise RuntimeError("malformed block: missing #data")
    try:
        i_enc = lines.index("#encoding")
    except ValueError as e:
        raise RuntimeError("malformed block: missing #encoding") from e
    data = "\n".join(lines[1:i_enc])
    enc = "\n".join(lines[i_enc + 1 :]).strip()
    return data, enc


def _norm(label: str) -> str:
    s = label.strip().lower()
    if s in {"utf8", "utf-8"}:
        return "utf-8"
    if s in {"iso-8859-1", "iso8859-1", "latin1", "latin-1"}:
        return "windows-1252"
    if s in {"windows1252", "cp1252", "x-cp1252"}:
        return "windows-1252"
    return s


def run_encoding_cases_batch(exe: Path, cases: list[dict[str, str]]) -> list[str]:
    lines: list[str] = [str(len(cases))]
    for case in cases:
        transport = case["transport"] or "-"
        payload = base64.b64encode(case["bytes"]).decode("ascii")
        lines.append(f"{transport}\t{len(payload)}")
        chunk_size = 900
        lines.extend(payload[i : i + chunk_size] for i in range(0, len(payload), chunk_size))

    proc = subprocess.run(
        [str(exe), "encoding-batch"],
        cwd=str(ROOT),
        check=True,
        input="\n".join(lines) + "\n",
        stdout=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    out = json.loads(proc.stdout)
    if not isinstance(out, list):
        raise RuntimeError("invalid runner output")
    return [str(x) for x in out]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fixture", action="append", help="encoding .dat file name under html5lib-tests/encoding/")
    ap.add_argument("--build", action="store_true")
    args = ap.parse_args()

    exe = ROOT / ".build" / "html5_runner"
    if args.build or not exe.exists():
        build_runner(exe)

    enc_dir = ROOT / "html5lib-tests" / "encoding"
    fixtures = args.fixture or ["tests1.dat", "tests2.dat", "test-yahoo-jp.dat"]

    cases: list[dict[str, str]] = []
    expected: list[str] = []
    for fx in fixtures:
        raw = (enc_dir / fx).read_text(encoding="utf-8", errors="replace")
        for block in _split_encoding_blocks(raw):
            data, exp = _parse_encoding_block(block)
            # The upstream encoding algorithm operates on bytes. We feed UTF-8 bytes here; all fixtures
            # declare charsets using ASCII, so sniffing behavior is stable.
            cases.append({"transport": "-", "bytes": data.encode("utf-8", "surrogatepass")})
            expected.append(exp)

    got = run_encoding_cases_batch(exe, cases)
    mismatches: list[str] = []
    for i, (exp, got_label) in enumerate(zip(expected, got, strict=True)):
        if _norm(exp) != _norm(got_label):
            mismatches.append(f"case #{i}: expected={exp!r} got={got_label!r}")
            if len(mismatches) >= 20:
                break

    if mismatches:
        for m in mismatches:
            print(m)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


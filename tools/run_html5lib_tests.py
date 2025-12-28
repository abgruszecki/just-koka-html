#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import codecs
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

from html5lib_allowlists import load, repo_root_from_tools_path, get_indices, _split_tree_construction_blocks


ROOT = repo_root_from_tools_path()
RUNNER_TIMEOUT_S = float(os.environ.get("HTML5LIB_RUNNER_TIMEOUT_S", "30"))


def build_runner(exe: Path) -> None:
    exe.parent.mkdir(parents=True, exist_ok=True)

    # Avoid rebuilding the runner when nothing changed; koka -O2 can be slow.
    try:
        if exe.exists():
            exe_mtime = exe.stat().st_mtime
            latest_src_mtime = max(p.stat().st_mtime for p in (ROOT / "src").rglob("*.kk"))
            if exe_mtime >= latest_src_mtime:
                return
    except OSError:
        # Fall back to always rebuilding if we can't stat files.
        pass

    subprocess.run(
        ["koka", "--include=src", "-O2", "-o", str(exe), "src/cli.kk"],
        cwd=str(ROOT),
        check=True,
    )
    exe.chmod(0o755)


def _state_arg_from_html5lib(name: str) -> str:
    name = name.strip()
    m = {
        "Data state": "Data",
        "PLAINTEXT state": "PLAINTEXT",
        "RCDATA state": "RCDATA",
        "RAWTEXT state": "RAWTEXT",
        "Script data state": "ScriptData",
        "CDATA section state": "CDATASection",
    }
    if name not in m:
        raise RuntimeError(f"unsupported initialStates entry: {name!r}")
    return m[name]


def _decode_double_escaped_str(s: str) -> str:
    # html5lib tokenizer fixtures sometimes use "doubleEscaped": true, where
    # strings like "\\u0000" should be interpreted as a single escaped layer.
    return codecs.decode(s, "unicode_escape")


def _koka_decode_utf8_forgiving(data: bytes) -> str:
    """
    Mirror Koka's forgiving UTF-8 decoding used by `base64/decode-utf8`, which
    maps invalid bytes to the private-use range U+EE000..U+EE0FF.
    """
    out: list[str] = []
    i = 0
    n = len(data)

    def invalid_byte(byte: int) -> None:
        out.append(chr(0xEE000 + byte))

    while i < n:
        b0 = data[i]
        # 1-byte
        if b0 < 0x80:
            out.append(chr(b0))
            i += 1
            continue

        # 2-byte
        if 0xC2 <= b0 <= 0xDF and i + 1 < n:
            b1 = data[i + 1]
            if 0x80 <= b1 <= 0xBF:
                out.append(chr(((b0 & 0x1F) << 6) | (b1 & 0x3F)))
                i += 2
                continue

        # 3-byte
        if 0xE0 <= b0 <= 0xEF and i + 2 < n:
            b1 = data[i + 1]
            b2 = data[i + 2]
            ok = 0x80 <= b1 <= 0xBF and 0x80 <= b2 <= 0xBF
            if ok:
                if b0 == 0xE0:
                    ok = b1 >= 0xA0
                elif b0 == 0xED:
                    ok = b1 <= 0x9F  # exclude surrogates
            if ok:
                out.append(chr(((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)))
                i += 3
                continue

        # 4-byte
        if 0xF0 <= b0 <= 0xF4 and i + 3 < n:
            b1 = data[i + 1]
            b2 = data[i + 2]
            b3 = data[i + 3]
            ok = 0x80 <= b1 <= 0xBF and 0x80 <= b2 <= 0xBF and 0x80 <= b3 <= 0xBF
            if ok:
                if b0 == 0xF0:
                    ok = b1 >= 0x90
                elif b0 == 0xF4:
                    ok = b1 <= 0x8F
            if ok:
                out.append(
                    chr(((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F))
                )
                i += 4
                continue

        # Invalid leading byte or malformed sequence; consume one byte.
        invalid_byte(b0)
        i += 1

    return "".join(out)


def _koka_utf8_roundtrip(s: str) -> str:
    return _koka_decode_utf8_forgiving(s.encode("utf-8", "surrogatepass"))


def _decode_double_escaped_obj(x: Any) -> Any:
    if isinstance(x, str):
        return _decode_double_escaped_str(x)
    if isinstance(x, list):
        return [_decode_double_escaped_obj(v) for v in x]
    if isinstance(x, dict):
        return {_decode_double_escaped_obj(k): _decode_double_escaped_obj(v) for k, v in x.items()}
    return x


def normalize_tokenizer_case(case: dict[str, Any]) -> tuple[str, Any, str | None]:
    """
    Returns (input, expected_output, lastStartTagOrNone), applying html5lib's
    `doubleEscaped` decoding when present.
    """
    double_escaped = bool(case.get("doubleEscaped"))
    input_text0 = _decode_double_escaped_str(case["input"]) if double_escaped else case["input"]
    expected0 = _decode_double_escaped_obj(case["output"]) if double_escaped else case["output"]
    last0: str | None = case.get("lastStartTag")
    if double_escaped and isinstance(last0, str):
        last0 = _decode_double_escaped_str(last0)

    def roundtrip_obj(x: Any) -> Any:
        if isinstance(x, str):
            return _koka_utf8_roundtrip(x)
        if isinstance(x, list):
            return [roundtrip_obj(v) for v in x]
        if isinstance(x, dict):
            return {roundtrip_obj(k): roundtrip_obj(v) for k, v in x.items()}
        return x

    return _koka_utf8_roundtrip(input_text0), roundtrip_obj(expected0), (_koka_utf8_roundtrip(last0) if last0 else None)


def run_tokenizer_cases_batch(exe: Path, cases: list[dict[str, Any]], *, cmd: str = "tokenizer-batch") -> list[list[Any]]:
    lines: list[str] = [str(len(cases))]
    for case in cases:
        state = case["state"]
        last = case.get("last") or "-"
        payload = base64.b64encode(case["input"].encode("utf-8", "surrogatepass")).decode("ascii")
        lines.append(f"{state}\t{last}\t{len(payload)}")
        chunk_size = 900  # Koka std/os/readline caps at 1023 chars.
        lines.extend(payload[i : i + chunk_size] for i in range(0, len(payload), chunk_size))

    proc = subprocess.run(
        [str(exe), cmd],
        cwd=str(ROOT),
        check=True,
        input="\n".join(lines) + "\n",
        stdout=subprocess.PIPE,
        text=True,
        timeout=RUNNER_TIMEOUT_S,
    )
    out = json.loads(proc.stdout)
    assert isinstance(out, list)
    return out  # list[case_output]


def parse_tree_block(block: str) -> dict[str, Any]:
    """
    Parse one html5lib tree-construction block.
    Returns:
      - input (str)
      - expected (str)   (tree dump)
      - error_count (int)
      - fragment_context (str|None)
      - scripting (str|None)  ("on"|"off"|None)
    """
    lines = block.replace("\r\n", "\n").split("\n")
    if not lines or lines[0] != "#data":
        raise RuntimeError("malformed block: missing #data")

    try:
        i_errors = lines.index("#errors")
    except ValueError as e:  # noqa: PERF203
        raise RuntimeError("malformed block: missing #errors") from e
    data_lines = lines[1:i_errors]
    input_html = "\n".join(data_lines)

    def is_directive(line: str) -> bool:
        return line in {
            "#new-errors",
            "#document-fragment",
            "#document",
            "#script-off",
            "#script-on",
        }

    idx = i_errors + 1
    error_count = 0
    while idx < len(lines) and lines[idx] and not is_directive(lines[idx]):
        error_count += 1
        idx += 1

    if idx < len(lines) and lines[idx] == "#new-errors":
        idx += 1
        while idx < len(lines) and lines[idx] and not is_directive(lines[idx]):
            error_count += 1
            idx += 1

    fragment_context: str | None = None
    if idx < len(lines) and lines[idx] == "#document-fragment":
        idx += 1
        fragment_context = lines[idx] if idx < len(lines) else ""
        idx += 1

    scripting: str | None = None
    if idx < len(lines) and lines[idx] in {"#script-off", "#script-on"}:
        scripting = "off" if lines[idx] == "#script-off" else "on"
        idx += 1

    if idx >= len(lines) or lines[idx] != "#document":
        raise RuntimeError("malformed block: missing #document")
    expected = "\n".join(lines[idx + 1 :]).rstrip("\n")
    return {
        "input": input_html,
        "expected": expected,
        "error_count": error_count,
        "fragment_context": fragment_context,
        "scripting": scripting,
    }


def run_tree_cases_batch(exe: Path, cases: list[dict[str, Any]]) -> list[list[Any]]:
    lines: list[str] = [str(len(cases))]
    for case in cases:
        kind = case["kind"]  # "doc"|"frag"
        ctx = case.get("context") or "-"
        script = case.get("scripting") or "-"
        payload = base64.b64encode(case["input"].encode("utf-8", "surrogatepass")).decode("ascii")
        lines.append(f"{kind}\t{ctx}\t{script}\t{len(payload)}")
        chunk_size = 900
        lines.extend(payload[i : i + chunk_size] for i in range(0, len(payload), chunk_size))

    proc = subprocess.run(
        [str(exe), "tree-batch"],
        cwd=str(ROOT),
        check=True,
        input="\n".join(lines) + "\n",
        stdout=subprocess.PIPE,
        text=True,
        timeout=RUNNER_TIMEOUT_S,
    )
    out = json.loads(proc.stdout)
    assert isinstance(out, list)
    return out  # list[[tree_dump, error_count]]


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
        tok_cmd = "tokenizer-batch-xml" if "xmlViolationTests" in payload else "tokenizer-batch"
        expanded: list[dict[str, Any]] = []
        expect: list[tuple[int, str, list[Any]]] = []
        for idx in enabled:
            case = tests[idx]
            input_text, expected_output, last0 = normalize_tokenizer_case(case)
            state_names = case.get("initialStates") or ["Data state"]
            last = last0 or "-"
            for st_name in state_names:
                st = _state_arg_from_html5lib(st_name)
                expanded.append({"state": st, "last": last, "input": input_text})
                expect.append((idx, st, expected_output))
        try:
            got_batch = run_tokenizer_cases_batch(exe, expanded, cmd=tok_cmd)
        except Exception as e:  # noqa: BLE001
            failures.append(f"tokenizer {fx}: runner failed: {e}")
            continue

        for (idx, st, expected), got in zip(expect, got_batch, strict=True):
            if got != expected:
                failures.append(f"tokenizer {fx} #{idx} ({st}): mismatch")

    tree_dir = ROOT / "html5lib-tests" / "tree-construction"
    for fx in sorted({*data["tree"]["doc"].keys(), *data["tree"]["frag"].keys()}):
        enabled_doc = get_indices(data, "tree-doc", fx)
        enabled_frag = get_indices(data, "tree-frag", fx)
        if not enabled_doc and not enabled_frag:
            continue

        blocks = _split_tree_construction_blocks((tree_dir / fx).read_text(encoding="utf-8", errors="replace"))
        doc_i = 0
        frag_i = 0
        cases: list[dict[str, Any]] = []
        expect: list[tuple[str, int]] = []

        for raw in blocks:
            parsed = parse_tree_block(raw)
            is_frag = parsed["fragment_context"] is not None
            if is_frag:
                if frag_i in enabled_frag:
                    cases.append(
                        {
                            "kind": "frag",
                            "context": parsed["fragment_context"],
                            "scripting": parsed["scripting"],
                            "input": parsed["input"],
                        }
                    )
                    expect.append((parsed["expected"], int(parsed["error_count"])))
                frag_i += 1
            else:
                if doc_i in enabled_doc:
                    cases.append(
                        {
                            "kind": "doc",
                            "context": "-",
                            "scripting": parsed["scripting"],
                            "input": parsed["input"],
                        }
                    )
                    expect.append((parsed["expected"], int(parsed["error_count"])))
                doc_i += 1

        if not cases:
            continue

        try:
            got_batch = run_tree_cases_batch(exe, cases)
        except Exception as e:  # noqa: BLE001
            failures.append(f"tree {fx}: runner failed: {e}")
            continue

        for idx, got in enumerate(got_batch):
            exp_tree, exp_errs = expect[idx]
            if not (isinstance(got, list) and len(got) == 2):
                failures.append(f"tree {fx}: invalid runner output shape")
                break
            got_tree, got_errs = got
            if got_tree != exp_tree:
                failures.append(f"tree {fx}: tree mismatch (case #{idx})")
            if int(got_errs) != exp_errs:
                failures.append(f"tree {fx}: error-count mismatch (case #{idx})")

    if failures:
        for line in failures[:50]:
            print(line, file=sys.stderr)
        print(f"{len(failures)} failing cases", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

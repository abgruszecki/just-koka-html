from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple


DEFAULT_PATH = Path(__file__).resolve().parent.parent / "data" / "html5lib_allowlists.json"


class AllowlistError(RuntimeError):
    pass


def _uniq_sorted_ints(xs: Iterable[int]) -> List[int]:
    out = sorted({int(x) for x in xs})
    return out


def load(path: Path = DEFAULT_PATH) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    validate(data)
    return data


def save(data: Dict[str, Any], path: Path = DEFAULT_PATH) -> None:
    validate(data)
    # stable key order for easy diffs
    out: Dict[str, Any] = {
        "version": int(data.get("version", 1)),
        "tree": data["tree"],
        "tokenizer": data["tokenizer"],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, sort_keys=True)
        f.write("\n")


def validate(data: Dict[str, Any]) -> None:
    if not isinstance(data, dict):
        raise AllowlistError("Top-level JSON must be an object")
    if int(data.get("version", 0)) != 1:
        raise AllowlistError(f"Unsupported allowlists version: {data.get('version')}")
    if "tree" not in data or "tokenizer" not in data:
        raise AllowlistError("Missing required keys: tree/tokenizer")
    tree = data["tree"]
    if not isinstance(tree, dict) or "doc" not in tree or "frag" not in tree:
        raise AllowlistError("tree must be an object with doc/frag keys")
    for section_name in ("doc", "frag"):
        sec = tree[section_name]
        if not isinstance(sec, dict):
            raise AllowlistError(f"tree.{section_name} must be an object")
        for k, v in sec.items():
            if not isinstance(k, str):
                raise AllowlistError("Fixture names must be strings")
            if not isinstance(v, list) or not all(isinstance(i, int) for i in v):
                raise AllowlistError(f"tree.{section_name}.{k} must be a list of ints")
    tok = data["tokenizer"]
    if not isinstance(tok, dict):
        raise AllowlistError("tokenizer must be an object")
    for k, v in tok.items():
        if not isinstance(k, str):
            raise AllowlistError("Fixture names must be strings")
        if not isinstance(v, list) or not all(isinstance(i, int) for i in v):
            raise AllowlistError(f"tokenizer.{k} must be a list of ints")


def get_indices(data: Dict[str, Any], kind: str, fixture: str) -> List[int]:
    """
    kind:
      - tree-doc
      - tree-frag
      - tokenizer
    """
    if kind == "tree-doc":
        xs = data["tree"]["doc"].get(fixture, [])
    elif kind == "tree-frag":
        xs = data["tree"]["frag"].get(fixture, [])
    elif kind == "tokenizer":
        xs = data["tokenizer"].get(fixture, [])
    else:
        raise AllowlistError(f"Unknown kind: {kind}")
    return _uniq_sorted_ints(xs)


def set_indices(data: Dict[str, Any], kind: str, fixture: str, indices: Iterable[int]) -> None:
    xs = _uniq_sorted_ints(indices)
    if kind == "tree-doc":
        data["tree"]["doc"][fixture] = xs
    elif kind == "tree-frag":
        data["tree"]["frag"][fixture] = xs
    elif kind == "tokenizer":
        data["tokenizer"][fixture] = xs
    else:
        raise AllowlistError(f"Unknown kind: {kind}")


def add_indices(data: Dict[str, Any], kind: str, fixture: str, indices: Iterable[int]) -> Tuple[int, int]:
    before = get_indices(data, kind, fixture)
    merged = _uniq_sorted_ints(list(before) + [int(i) for i in indices])
    set_indices(data, kind, fixture, merged)
    return (len(before), len(merged))


def parse_ranges(expr: str) -> List[int]:
    """
    Parse a comma-separated list of ints / ranges:
      "1,2,5-7" -> [1,2,5,6,7]
    """
    expr = expr.strip()
    if not expr:
        return []
    out: List[int] = []
    for part in expr.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            lo_s, hi_s = part.split("-", 1)
            lo = int(lo_s)
            hi = int(hi_s)
            if hi < lo:
                raise AllowlistError(f"Bad range '{part}' (hi < lo)")
            out.extend(range(lo, hi + 1))
        else:
            out.append(int(part))
    return out


def format_ranges(indices: Iterable[int]) -> str:
    xs = _uniq_sorted_ints(indices)
    if not xs:
        return ""
    parts: List[str] = []
    i = 0
    while i < len(xs):
        start = xs[i]
        end = start
        j = i
        while j + 1 < len(xs) and xs[j + 1] == xs[j] + 1:
            j += 1
            end = xs[j]
        if end - start >= 2:
            parts.append(f"{start}-{end}")
        elif end == start:
            parts.append(str(start))
        else:
            parts.append(str(start))
            parts.append(str(end))
        i = j + 1
    return ",".join(parts)


@dataclass(frozen=True)
class Stats:
    fixtures: int
    total_indices: int


def stats(data: Dict[str, Any], kind: str) -> Dict[str, Stats]:
    """
    Returns per-fixture stats for the given kind.
    """
    if kind == "tree-doc":
        sec = data["tree"]["doc"]
    elif kind == "tree-frag":
        sec = data["tree"]["frag"]
    elif kind == "tokenizer":
        sec = data["tokenizer"]
    else:
        raise AllowlistError(f"Unknown kind: {kind}")
    out: Dict[str, Stats] = {}
    for fixture, xs in sec.items():
        norm = _uniq_sorted_ints(xs)
        out[fixture] = Stats(fixtures=1, total_indices=len(norm))
    return out


def total_counts(data: Dict[str, Any]) -> Dict[str, int]:
    return {
        "tree-doc": sum(len(_uniq_sorted_ints(v)) for v in data["tree"]["doc"].values()),
        "tree-frag": sum(len(_uniq_sorted_ints(v)) for v in data["tree"]["frag"].values()),
        "tokenizer": sum(len(_uniq_sorted_ints(v)) for v in data["tokenizer"].values()),
    }


# ---- Fixture discovery + total-case counting (for percentages) ----


def repo_root_from_tools_path() -> Path:
    # tools/ -> repo root
    return Path(__file__).resolve().parents[1]


def discover_tree_construction_fixtures(repo_root: Path) -> List[Path]:
    return sorted((repo_root / "html5lib-tests" / "tree-construction").rglob("*.dat"))


def discover_tokenizer_fixtures(repo_root: Path) -> List[Path]:
    return sorted((repo_root / "html5lib-tests" / "tokenizer").rglob("*.test"))


def _split_tree_construction_blocks(raw: str) -> List[str]:
    # Mirror `test/html5lib_dat.jl` behavior: each test starts with a `#data` line.
    s = raw.replace("\r\n", "\n")
    lines = s.split("\n")
    starts = [i for i, line in enumerate(lines) if line == "#data"]
    if not starts:
        return []
    blocks: List[str] = []
    for idx, lo in enumerate(starts):
        hi = (starts[idx + 1] - 1) if idx + 1 < len(starts) else (len(lines) - 1)
        while hi >= lo and lines[hi] == "":
            hi -= 1
        blocks.append("\n".join(lines[lo : hi + 1]))
    return blocks


def count_tree_construction_cases(path: Path) -> Tuple[int, int]:
    """
    Returns (total_doc_cases, total_fragment_cases) for one `.dat` fixture.
    """
    raw = path.read_text(encoding="utf-8", errors="replace")
    blocks = _split_tree_construction_blocks(raw)
    doc = 0
    frag = 0
    for b in blocks:
        lines = b.replace("\r\n", "\n").split("\n")
        try:
            doc_i = lines.index("#document")
        except ValueError:
            # malformed fixture block; ignore defensively
            continue
        frag_i = None
        try:
            frag_i = lines.index("#document-fragment")
        except ValueError:
            frag_i = None

        # Fragment blocks have `#document-fragment` before `#document`
        if frag_i is not None and frag_i < doc_i:
            frag += 1
        else:
            doc += 1
    return doc, frag


def count_tokenizer_cases(path: Path) -> int:
    raw = path.read_text(encoding="utf-8", errors="replace")
    root = json.loads(raw)
    tests = root.get("tests")
    if tests is None:
        tests = root.get("xmlViolationTests")
    if tests is None:
        raise AllowlistError(f"Unexpected tokenizer test format: {path}")
    return int(len(tests))


def load_from_git(
    repo_root: Path,
    *,
    rev: str = "HEAD~1",
    json_relpath: str = "data/html5lib_allowlists.json",
) -> Dict[str, Any]:
    """
    Load allowlists JSON from git (without checking out a commit).

    Example:
      load_from_git(repo_root, rev="HEAD~1")
    """
    try:
        rev_proc = subprocess.run(
            ["git", "rev-parse", "--verify", rev],
            cwd=str(repo_root),
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        msg = (e.stderr or "").strip()
        raise AllowlistError(f"git rev-parse failed for {rev!r}" + (f": {msg}" if msg else "")) from e

    resolved = (rev_proc.stdout or "").strip()
    if not resolved:
        raise AllowlistError(f"git rev-parse returned empty output for {rev!r}")

    try:
        proc = subprocess.run(
            ["git", "show", f"{resolved}:{json_relpath}"],
            cwd=str(repo_root),
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        msg = (e.stderr or "").strip()
        raise AllowlistError(f"git show failed for {resolved}:{json_relpath}" + (f": {msg}" if msg else "")) from e
    data = json.loads(proc.stdout)
    validate(data)
    return data

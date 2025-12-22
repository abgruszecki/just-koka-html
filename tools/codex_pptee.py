#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from dataclasses import dataclass
from typing import Any, Iterable, List, Optional


ANSI_RESET = "\x1b[0m"
ANSI_BOLD = "\x1b[1m"
ANSI_DIM = "\x1b[2m"
ANSI_RED = "\x1b[31m"
ANSI_GREEN = "\x1b[32m"
ANSI_YELLOW = "\x1b[33m"
ANSI_BLUE = "\x1b[34m"
ANSI_MAGENTA = "\x1b[35m"
ANSI_CYAN = "\x1b[36m"


def _supports_color(disabled_by_flag: bool) -> bool:
    if disabled_by_flag:
        return False
    if os.environ.get("NO_COLOR"):
        return False
    return True


def _c(s: str, code: str, enabled: bool) -> str:
    if not enabled:
        return s
    return f"{code}{s}{ANSI_RESET}"


def _one_line(text: str) -> str:
    return " ".join(text.replace("\r\n", "\n").replace("\r", "\n").split())


def _truncate(text: str, max_chars: int) -> str:
    if max_chars <= 0:
        return text
    if len(text) <= max_chars:
        return text
    return text[: max(0, max_chars - 1)] + "…"


def _indent_lines(lines: Iterable[str], prefix: str) -> List[str]:
    return [prefix + line if line else prefix.rstrip() for line in lines]


def _safe_json_preview(obj: Any, max_chars: int) -> str:
    try:
        s = json.dumps(obj, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    except Exception:
        s = repr(obj)
    return _truncate(s, max_chars)


@dataclass(frozen=True)
class RenderOptions:
    color: bool
    truncate_text: Optional[int]
    truncate_cmd: Optional[int]
    show_cmd_output: str  # never|on-fail|always
    max_json_chars: int
    max_list_items: int


def _render_thread_started(evt: dict[str, Any], opt: RenderOptions) -> List[str]:
    tid = evt.get("thread_id")
    head = _c("thread.started", ANSI_CYAN + ANSI_BOLD, opt.color)
    if tid:
        return [f"{head} {tid}"]
    return [head]


def _render_turn_boundary(evt_type: str, opt: RenderOptions) -> List[str]:
    head = _c(evt_type, ANSI_MAGENTA + ANSI_BOLD, opt.color)
    bar = _c("─" * 18, ANSI_DIM, opt.color)
    return [f"{bar} {head} {bar}"]


def _status_color(status: Optional[str]) -> str:
    if status in ("completed", "success"):
        return ANSI_GREEN + ANSI_BOLD
    if status in ("failed", "error"):
        return ANSI_RED + ANSI_BOLD
    if status in ("in_progress", "running"):
        return ANSI_YELLOW + ANSI_BOLD
    return ANSI_BLUE + ANSI_BOLD


def _render_command_execution(item: dict[str, Any], action: str, opt: RenderOptions) -> List[str]:
    item_id = item.get("id", "?")
    status = item.get("status")
    exit_code = item.get("exit_code", None)
    command = item.get("command", "")
    command_line = (
        _truncate(_one_line(command), opt.truncate_cmd) if opt.truncate_cmd else command
    )

    head = _c(action, ANSI_BLUE + ANSI_BOLD, opt.color)
    st = str(status) if status is not None else "?"
    st_col = _c(st, _status_color(st), opt.color)
    ec = "" if exit_code is None else f" exit={exit_code}"
    lines = [f"{head} command_execution {item_id} {st_col}{ec} ::", f"{command_line}"]

    agg = item.get("aggregated_output") or ""
    if not isinstance(agg, str):
        agg = str(agg)
    if opt.show_cmd_output == "always":
        show = True
    elif opt.show_cmd_output == "never":
        show = False
    else:
        show = st in ("failed", "error") and bool(agg.strip())

    if show and agg:
        body = agg
        if opt.truncate_text:
            body = _truncate(body, max(0, opt.truncate_text * 4))
        body = body.rstrip("\n")
        wrapped = body.splitlines() or [""]
        lines.extend(_indent_lines(wrapped, "  │ "))
    return lines


def _render_reasoning(item: dict[str, Any], action: str, opt: RenderOptions) -> List[str]:
    item_id = item.get("id", "?")
    text = item.get("text", "")
    if not isinstance(text, str):
        text = str(text)
    if opt.truncate_text:
        text = _truncate(_one_line(text), opt.truncate_text)
    head = _c(action, ANSI_BLUE + ANSI_BOLD, opt.color)
    return [f"{head} reasoning {item_id} ::", f"{text}"]


def _render_agent_message(item: dict[str, Any], action: str, opt: RenderOptions) -> List[str]:
    item_id = item.get("id", "?")
    text = item.get("text", "")
    if not isinstance(text, str):
        text = str(text)
    head = _c(action, ANSI_BLUE + ANSI_BOLD, opt.color)
    lines = [f"{head} agent_message {item_id}"]
    body = text
    if opt.truncate_text:
        body = _truncate(body, max(0, opt.truncate_text * 6))
    body = body.rstrip("\n")
    if body:
        lines.extend(_indent_lines(body.splitlines(), "  │ "))
    return lines


def _render_file_change(item: dict[str, Any], action: str, opt: RenderOptions) -> List[str]:
    item_id = item.get("id", "?")
    status = item.get("status")
    st = str(status) if status is not None else "?"
    st_col = _c(st, _status_color(st), opt.color)
    changes = item.get("changes") or []
    head = _c(action, ANSI_BLUE + ANSI_BOLD, opt.color)

    lines = [f"{head} file_change {item_id} {st_col}"]
    if isinstance(changes, list) and changes:
        shown = 0
        for ch in changes:
            if shown >= opt.max_list_items:
                lines.append(f"  │ … (+{len(changes) - shown} more)")
                break
            if isinstance(ch, dict):
                path = ch.get("path", "?")
                kind = ch.get("kind", "?")
                lines.append(f"  │ {kind}: {path}")
            else:
                lines.append(f"  │ {_safe_json_preview(ch, opt.max_json_chars)}")
            shown += 1
    return lines


def _render_todo_list(item: dict[str, Any], action: str, opt: RenderOptions) -> List[str]:
    item_id = item.get("id", "?")
    todos = item.get("items") or []
    head = _c(action, ANSI_BLUE + ANSI_BOLD, opt.color)
    lines = [f"{head} todo_list {item_id}"]
    if isinstance(todos, list):
        shown = 0
        for t in todos:
            if shown >= opt.max_list_items:
                lines.append(f"  │ … (+{len(todos) - shown} more)")
                break
            if isinstance(t, dict):
                text = t.get("text", "")
                completed = bool(t.get("completed"))
                mark = "[x]" if completed else "[ ]"
                line = text if isinstance(text, str) else str(text)
                line = _one_line(line)
                if opt.truncate_text:
                    line = _truncate(line, opt.truncate_text)
                lines.append(f"  │ {mark} {line}")
            else:
                lines.append(f"  │ {_safe_json_preview(t, opt.max_json_chars)}")
            shown += 1
    return lines


def _render_item_event(evt: dict[str, Any], opt: RenderOptions) -> List[str]:
    evt_type = str(evt.get("type", "item.?"))
    action = evt_type.split(".", 1)[-1] if "." in evt_type else evt_type
    item = evt.get("item") or {}
    if not isinstance(item, dict):
        head = _c(evt_type, ANSI_BLUE + ANSI_BOLD, opt.color)
        return [f"{head} :: {_safe_json_preview(evt, opt.max_json_chars)}"]

    item_type = item.get("type", "?")
    if item_type == "command_execution":
        return _render_command_execution(item, action, opt)
    if item_type == "reasoning":
        return _render_reasoning(item, action, opt)
    if item_type == "file_change":
        return _render_file_change(item, action, opt)
    if item_type == "todo_list":
        return _render_todo_list(item, action, opt)
    if item_type == "agent_message":
        return _render_agent_message(item, action, opt)

    item_id = item.get("id", "?")
    head = _c(action, ANSI_BLUE + ANSI_BOLD, opt.color)
    return [
        f"{head} {item_type} {item_id} :: "
        f"{_safe_json_preview(item, opt.max_json_chars)}"
    ]


def _render_invalid_json(line_text: str, opt: RenderOptions) -> List[str]:
    head = _c("invalid-json", ANSI_RED + ANSI_BOLD, opt.color)
    preview = _one_line(line_text)
    if opt.truncate_text:
        preview = _truncate(preview, opt.truncate_text)
    return [f"{head} :: {preview}"]


def render_event(evt: dict[str, Any], opt: RenderOptions) -> List[str]:
    evt_type = evt.get("type")
    if evt_type == "thread.started":
        return _render_thread_started(evt, opt)
    if evt_type in ("turn.started", "turn.completed"):
        return _render_turn_boundary(str(evt_type), opt)
    if isinstance(evt_type, str) and evt_type.startswith("item."):
        return _render_item_event(evt, opt)

    head = _c(str(evt_type or "<no-type>"), ANSI_CYAN + ANSI_BOLD, opt.color)
    keys = []
    if isinstance(evt, dict):
        keys = sorted([k for k in evt.keys() if k != "type"])
    trailer = f" keys={keys}" if keys else ""
    return [f"{head}{trailer} :: {_safe_json_preview(evt, opt.max_json_chars)}"]


def _open_destinations(paths: List[str], append: bool) -> List[Any]:
    mode = "ab" if append else "wb"
    handles = []
    for path in paths:
        handles.append(open(path, mode))
    return handles


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Read JSONL event stream from stdin, tee raw bytes to files, and render events to stdout."
        )
    )
    parser.add_argument("dest", nargs="*", help="Destination paths for raw stdin (written unmodified).")
    parser.add_argument("-a", "--append", action="store_true", help="Append to destinations instead of overwrite.")
    parser.add_argument("--no-color", action="store_true", help="Disable ANSI color.")
    parser.add_argument(
        "--show-cmd-output",
        choices=["never", "on-fail", "always"],
        default="on-fail",
        help="When to show command aggregated output (default: on-fail).",
    )
    parser.add_argument(
        "--truncate-text",
        type=int,
        default=None,
        help="Truncate rendered text fields to N chars (default: no truncation).",
    )
    parser.add_argument(
        "--truncate-cmd",
        type=int,
        default=None,
        help="Truncate rendered command strings to N chars (default: no truncation).",
    )
    args = parser.parse_args(argv)

    opt = RenderOptions(
        color=_supports_color(args.no_color),
        truncate_text=(
            None
            if args.truncate_text is None or args.truncate_text <= 0
            else int(args.truncate_text)
        ),
        truncate_cmd=(
            None
            if args.truncate_cmd is None or args.truncate_cmd <= 0
            else int(args.truncate_cmd)
        ),
        show_cmd_output=str(args.show_cmd_output),
        max_json_chars=800,
        max_list_items=8,
    )

    try:
        out_width = shutil.get_terminal_size((120, 20)).columns
    except Exception:
        out_width = 120

    dest_handles: List[Any] = []
    try:
        if args.dest:
            dest_handles = _open_destinations(args.dest, bool(args.append))

        for raw in sys.stdin.buffer:
            for h in dest_handles:
                h.write(raw)

            try:
                line_text = raw.decode("utf-8")
            except Exception:
                line_text = raw.decode("utf-8", errors="replace")

            stripped = line_text.strip("\n")
            if not stripped:
                continue

            try:
                evt = json.loads(stripped)
            except Exception:
                lines = _render_invalid_json(stripped, opt)
            else:
                if not isinstance(evt, dict):
                    lines = [
                        _c("non-object-json", ANSI_YELLOW + ANSI_BOLD, opt.color)
                        + " :: "
                        + _safe_json_preview(evt, opt.max_json_chars)
                    ]
                else:
                    lines = render_event(evt, opt)

            for line in lines:
                if opt.truncate_text and len(line) > out_width * 6:
                    line = _truncate(line, out_width * 6)
                sys.stdout.write(line + "\n")
            sys.stdout.flush()
    except BrokenPipeError:
        return 0
    finally:
        for h in dest_handles:
            try:
                h.flush()
                h.close()
            except Exception:
                pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

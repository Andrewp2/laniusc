#!/usr/bin/env python3
"""Run a checked daemon request sequence without inter-job host delays."""

import argparse
import json
import select
import subprocess
import sys
import time
from pathlib import Path


TRANSCRIPT_SCHEMA = "lanius.daemon-benchmark-transcript.v1"
SOURCE_EDIT_KEY = "benchmark_source_edit"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--commands", required=True, help="benchmark commands JSON")
    parser.add_argument("--output", required=True, help="transcript JSON output")
    parser.add_argument("--startup-timeout", type=float, default=60.0)
    parser.add_argument("--job-timeout", type=float, default=120.0)
    parser.add_argument(
        "--prequeue-delay",
        type=float,
        default=0.0,
        help="seconds to keep a ready daemon idle before queuing jobs (for profiler attach)",
    )
    parser.add_argument(
        "--postcompile-delay",
        type=float,
        default=0.0,
        help="seconds to keep the daemon alive after compile responses (for profiler export)",
    )
    args = parser.parse_args()
    if (
        args.startup_timeout <= 0
        or args.job_timeout <= 0
        or args.prequeue_delay < 0
        or args.postcompile_delay < 0
    ):
        parser.error(
            "timeouts must be positive and profiler delays must be nonnegative"
        )

    repo = Path(__file__).resolve().parents[1]
    commands_path = resolve_from_repo(repo, args.commands)
    output_path = resolve_from_repo(repo, args.output)
    commands = json.loads(commands_path.read_text())
    daemon = require_string_array(commands, "lanius", "daemon_start")
    requests = commands.get("lanius", {}).get("requests")
    if not isinstance(requests, list) or not requests:
        raise ValueError("commands.lanius.requests must be a nonempty array")
    daemon_requests = [daemon_request(request) for request in requests]
    has_source_edits = any(SOURCE_EDIT_KEY in request for request in requests)
    hold_for_profiler = args.postcompile_delay > 0
    if hold_for_profiler and (
        requests[-1].get("command") != "shutdown"
        or any(request.get("command") == "shutdown" for request in requests[:-1])
    ):
        raise ValueError(
            "--postcompile-delay requires exactly one shutdown request at the end"
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    original_sources: dict[Path, bytes] = {}
    with output_path.with_suffix(output_path.suffix + ".stderr").open("wb") as stderr:
        process = subprocess.Popen(
            daemon,
            cwd=repo,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=stderr,
            text=True,
            bufsize=1,
        )
        assert process.stdin is not None
        assert process.stdout is not None
        try:
            ready = read_json_line(process, args.startup_timeout, "daemon ready event")
            if ready.get("event") != "ready":
                raise RuntimeError(f"first daemon response was not ready: {ready!r}")
            if args.prequeue_delay:
                time.sleep(args.prequeue_delay)

            initially_queued = requests[:-1] if hold_for_profiler else requests
            request_queue_ms = 0.0
            responses = []
            if has_source_edits:
                for index, request in enumerate(initially_queued):
                    apply_source_edit(repo, request, original_sources)
                    request_to_send = daemon_request(request)
                    queue_started = time.monotonic()
                    process.stdin.write(
                        json.dumps(request_to_send, separators=(",", ":")) + "\n"
                    )
                    process.stdin.flush()
                    request_queue_ms += (time.monotonic() - queue_started) * 1000.0
                    responses.append(
                        read_json_line(
                            process, args.job_timeout, f"response {index + 1}"
                        )
                    )
            else:
                queue_started = time.monotonic()
                for request in initially_queued:
                    process.stdin.write(
                        json.dumps(daemon_request(request), separators=(",", ":"))
                        + "\n"
                    )
                process.stdin.flush()
                request_queue_ms = (time.monotonic() - queue_started) * 1000.0
                responses = [
                    read_json_line(process, args.job_timeout, f"response {index + 1}")
                    for index in range(len(initially_queued))
                ]
            if hold_for_profiler:
                time.sleep(args.postcompile_delay)
                shutdown = daemon_request(requests[-1])
                process.stdin.write(json.dumps(shutdown, separators=(",", ":")) + "\n")
                process.stdin.flush()
                responses.append(
                    read_json_line(process, args.job_timeout, "shutdown response")
                )
            process.stdin.close()
            process.wait(timeout=args.job_timeout)
            if process.returncode != 0:
                raise RuntimeError(f"daemon exited with status {process.returncode}")
            validate_response_order(daemon_requests, responses)
        except Exception:
            process.kill()
            process.wait()
            raise
        finally:
            restore_sources(original_sources)

    transcript = {
        "schema": TRANSCRIPT_SCHEMA,
        "daemon_start": daemon,
        "ready": ready,
        "request_queue_ms": request_queue_ms,
        "requests_queued_before_first_response": not hold_for_profiler
        and not has_source_edits,
        "compile_requests_queued_before_first_response": not has_source_edits,
        "source_edits_between_requests": has_source_edits,
        "prequeue_delay_seconds": args.prequeue_delay,
        "postcompile_delay_seconds": args.postcompile_delay,
        "wall_elapsed_ms": (time.monotonic() - started) * 1000.0,
        "requests": requests,
        "responses": responses,
    }
    output_path.write_text(json.dumps(transcript, indent=2, sort_keys=True) + "\n")
    return 0


def daemon_request(request: dict) -> dict:
    if not isinstance(request, dict):
        raise ValueError("commands.lanius.requests entries must be objects")
    return {key: value for key, value in request.items() if key != SOURCE_EDIT_KEY}


def apply_source_edit(repo: Path, request: dict, originals: dict[Path, bytes]) -> None:
    edit = request.get(SOURCE_EDIT_KEY)
    if edit is None:
        return
    if request.get("command") != "compile" or not isinstance(edit, dict):
        raise ValueError(f"{SOURCE_EDIT_KEY} is valid only on compile requests")
    raw_path = edit.get("path")
    old = edit.get("old")
    new = edit.get("new")
    if not all(isinstance(value, str) and value for value in (raw_path, old, new)):
        raise ValueError(
            f"{SOURCE_EDIT_KEY} requires nonempty path, old, and new strings"
        )
    if old == new or len(old.encode()) != len(new.encode()):
        raise ValueError(
            f"{SOURCE_EDIT_KEY} replacements must differ and preserve byte length"
        )
    path = resolve_from_repo(repo, raw_path).resolve()
    try:
        path.relative_to(repo.resolve())
    except ValueError as error:
        raise ValueError(
            f"{SOURCE_EDIT_KEY} path must remain inside the repository"
        ) from error
    original = path.read_bytes()
    originals.setdefault(path, original)
    old_bytes = old.encode()
    if original.count(old_bytes) != 1:
        raise ValueError(
            f"{SOURCE_EDIT_KEY} expected exactly one occurrence of {old!r} in {path}"
        )
    path.write_bytes(original.replace(old_bytes, new.encode(), 1))


def restore_sources(originals: dict[Path, bytes]) -> None:
    for path, contents in originals.items():
        path.write_bytes(contents)


def resolve_from_repo(repo: Path, raw: str) -> Path:
    path = Path(raw)
    return path if path.is_absolute() else repo / path


def require_string_array(document: dict, parent: str, key: str) -> list[str]:
    value = document.get(parent, {}).get(key)
    if (
        not isinstance(value, list)
        or not value
        or not all(isinstance(part, str) and part for part in value)
    ):
        raise ValueError(f"commands.{parent}.{key} must be a nonempty string array")
    return value


def read_json_line(
    process: subprocess.Popen[str], timeout: float, description: str
) -> dict:
    assert process.stdout is not None
    ready, _, _ = select.select([process.stdout], [], [], timeout)
    if not ready:
        raise TimeoutError(f"timed out waiting for {description}")
    line = process.stdout.readline()
    if not line:
        raise RuntimeError(
            f"daemon exited before {description}; status={process.poll()}"
        )
    value = json.loads(line)
    if not isinstance(value, dict):
        raise RuntimeError(f"{description} was not a JSON object")
    return value


def validate_response_order(requests: list[dict], responses: list[dict]) -> None:
    for index, (request, response) in enumerate(zip(requests, responses, strict=True)):
        if response.get("id") != request.get("id"):
            raise RuntimeError(
                f"response {index + 1} id {response.get('id')!r} does not match "
                f"request id {request.get('id')!r}"
            )
        if request.get("command") == "compile" and response.get("ok") is not True:
            raise RuntimeError(
                f"compile request {request.get('id')!r} failed: {response!r}"
            )
        if request.get("command") == "shutdown" and response.get("event") != "shutdown":
            raise RuntimeError(f"shutdown response was malformed: {response!r}")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        OSError,
        ValueError,
        RuntimeError,
        TimeoutError,
        json.JSONDecodeError,
    ) as error:
        print(f"run_daemon_benchmark: {error}", file=sys.stderr)
        raise SystemExit(1)

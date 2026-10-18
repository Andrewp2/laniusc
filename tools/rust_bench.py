#!/usr/bin/env python3
"""Time rustc on the Rust twin of a generated project workload: full and after a one-function edit.

usage: rust_bench.py TWIN_DIR [--reps 3] [--jobs N] [--max-load 2] [--wait-load 180] [--strict-load]

Modes, each with `reps` full runs (target/ removed) and `reps` one-function edits:
  check        cargo check (debug)
  build        cargo build (debug); the binary's stdout is checked after every build
  check-noinc  cargo check with CARGO_INCREMENTAL=0: rustc without its incremental caches,
               the column comparable to Lanius edit mode, which keeps no app caches

Copies nothing: works in TWIN_DIR (its own target/). Edit k rewrites the returns of one module
entry fn (`run_<module>`) to `return ((EXPR) + k) & 4095;`, choosing the fn as
tools/workload_bench.py does on the Lanius side. TWIN_DIR is restored afterwards.

The machine preamble (CPU, governor, EPP, platform profile, mean core MHz, load average) is
printed before and after. The run waits up to --wait-load seconds for the 1-minute load average
to fall below --max-load, then warns, or with --strict-load refuses, if it has not. Run it
inside a quiet job (`heavy --quiet -t 10`) so no build competes.

The w30k gate row (laptop):
  python3 tools/generate_project_workload.py --preset 30k --seed 20 --out W30K --rust-out W30K_RS
  python3 tools/workload_bench.py --laniusc PIN --out OUT --repeat 3 W30K   # Lanius, warm daemon
  python3 tools/rust_bench.py W30K_RS --reps 3 --jobs "$(nproc)"             # rustc baseline
"""
import argparse, json, os, pathlib, re, shutil, subprocess, sys, time

MASK = 4095
ap = argparse.ArgumentParser()
ap.add_argument("twin")
ap.add_argument("--reps", type=int, default=3)
ap.add_argument("--jobs", type=int, default=os.cpu_count())
ap.add_argument("--max-load", type=float, default=2.0, help="1-minute load average to wait for")
ap.add_argument("--wait-load", type=float, default=180.0, help="seconds to wait for --max-load")
ap.add_argument("--strict-load", action="store_true", help="refuse to run above --max-load")
a = ap.parse_args()
twin = pathlib.Path(a.twin).resolve()
env = dict(os.environ, CARGO_TERM_COLOR="never")


def read(path):
    try:
        return pathlib.Path(path).read_text().strip()
    except OSError:
        return None


def machine(stage):
    mhz = [float(l.split(":")[1]) for l in (read("/proc/cpuinfo") or "").splitlines() if l.startswith("cpu MHz")]
    model = next((l.split(":", 1)[1].strip() for l in (read("/proc/cpuinfo") or "").splitlines()
                  if l.startswith("model name")), None)
    info = {"stage": stage, "cpu": model, "nproc": os.cpu_count(),
            "governor": read("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
            "epp": read("/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference"),
            "platform_profile": read("/sys/firmware/acpi/platform_profile"),
            "mean_core_mhz": round(sum(mhz) / len(mhz)) if mhz else None,
            "loadavg": os.getloadavg()}
    print("MACHINE " + json.dumps(info), flush=True)
    return info


machine("start")
waited = 0.0
while os.getloadavg()[0] >= a.max_load and waited < a.wait_load:
    time.sleep(5)
    waited += 5
load = os.getloadavg()[0]
if load >= a.max_load:
    message = f"1-minute load average {load:.2f} is still >= {a.max_load} after {waited:.0f} s"
    if a.strict_load:
        raise SystemExit(f"refusing to time: {message}")
    print(f"WARNING: {message}; timings are not quiet", flush=True)
machine(f"first rep (waited {waited:.0f} s)")


def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, cwd=twin, env=env)


def cargo(sub, extra_env=None):
    s = time.perf_counter()
    r = subprocess.run(["cargo", sub, "--offline", "-j", str(a.jobs), "--quiet"], capture_output=True, text=True,
                       cwd=twin, env=dict(env, **(extra_env or {})))
    ms = (time.perf_counter() - s) * 1000
    if r.returncode != 0:
        print(r.stderr[-3000:])
        raise SystemExit(f"cargo {sub} failed")
    return ms


main_rs = (twin / "src" / "main.rs").read_text()
callees = re.findall(r"part = crate::gen::([a-z_0-9]+)::(run_[a-z_0-9]+)\(", main_rs)
expected_lines = [int(v) for v in (twin / "expected_stdout.txt").read_text().split()]
assert len(callees) + 1 == len(expected_lines), (len(callees), len(expected_lines))


def edit(k):
    n = len(callees)
    stride = 7 if n % 7 else 5
    index = ((k - 1) * stride + n // 2) % n
    module, fn = callees[index]
    path = twin / "src" / "gen" / f"{module}.rs"
    text = path.read_text()
    start = text.index(f"pub fn {fn}(")
    open_at = text.index("{", start)
    depth = 0
    for i in range(open_at, len(text)):
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        if depth == 0:
            end = i + 1
            break
    body = re.sub(r"(?m)^(\s*)return (.*);$", lambda m: f"{m.group(1)}return (({m.group(2)}) + {k}) & {MASK};",
                  text[open_at:end])
    path.write_text(text[:open_at] + body + text[end:])
    parts = list(expected_lines[:-1])
    for j, (mod2, _) in enumerate(callees):
        if mod2 == module:
            parts[j] = (parts[j] + k) & MASK
    return path, text, "".join(f"{v}\n" for v in parts + [sum(parts) & MASK]), f"{module}::{fn}+{k}"


def check_output(expected, label):
    r = subprocess.run([str(twin / "target" / "debug" / "lanius_twin")], capture_output=True, text=True, timeout=60)
    ok = r.stdout == expected
    if not ok:
        print(f"  OUTPUT-MISMATCH {label}")
    return ok


print(json.dumps({"twin": str(twin), "nproc": os.cpu_count(), "cargo_jobs": a.jobs,
                  "cargo": sh(["cargo", "--version"]).stdout.strip(), "rustc": sh(["rustc", "--version"]).stdout.strip(),
                  "sloc": sum(1 for f in (twin / "src").rglob("*.rs") for l in f.read_text().split("\n") if l.strip())}),
      flush=True)
results = {}
expected_full = (twin / "expected_stdout.txt").read_text()
# "check-noinc" is cargo check with CARGO_INCREMENTAL=0: rustc without its incremental
# caches, so an edit re-checks the whole crate, like a compiler that keeps no app caches.
for mode, sub, extra in (("check", "check", None), ("build", "build", None),
                         ("check-noinc", "check", {"CARGO_INCREMENTAL": "0"})):
    full = []
    for rep in range(a.reps):
        shutil.rmtree(twin / "target", ignore_errors=True)
        full.append(cargo(sub, extra))
        print(f"{mode} full rep{rep} {full[-1]:.0f} ms", flush=True)
    if sub == "build":
        check_output(expected_full, "full build")
    edits = []
    for k in range(1, a.reps + 1):
        path, original, expected, label = edit(k)
        try:
            edits.append(cargo(sub, extra))
            ok = check_output(expected, label) if sub == "build" else True
            print(f"{mode} edit {label} {edits[-1]:.0f} ms{'' if ok else ' MISMATCH'}", flush=True)
        finally:
            path.write_text(original)
    # Leave the target dir matching the original sources for the next mode.
    cargo(sub, extra)
    results[mode] = {"full_ms": full, "edit_ms": edits}
med = lambda xs: sorted(xs)[len(xs) // 2]
for sub, r in results.items():
    print(f"SUMMARY cargo {sub}: full median {med(r['full_ms']):.0f} ms {[round(x) for x in r['full_ms']]}, "
          f"one-function edit median {med(r['edit_ms']):.0f} ms {[round(x) for x in r['edit_ms']]}", flush=True)
machine("end")
print(json.dumps(results))

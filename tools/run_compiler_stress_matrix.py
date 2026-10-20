#!/usr/bin/env python3
"""Measure the controlled cross-language synthetic compiler stress matrix."""

import argparse
import hashlib
import json
import os
import platform
import random
import re
import select
import shutil
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

from compiler_stress_model import WORKLOAD_PROFILES


EXTERNAL_COMPILERS = (
    "c", "cpp", "rust", "zig", "tcc", "pareas",
    "d", "ldc", "go", "v", "vx", "tsc", "tsrs",
)
LANES = ("o0", "optimized")
TYPESCRIPT_COMPILERS = ("tsc", "tsrs")
# Compilers that read another compiler's rendering of the workload.
SOURCE_LANGUAGE = {"tcc": "c", "ldc": "d", "tsc": "ts", "tsrs": "ts"}
SOURCE_SUFFIX = {
    "c": "c", "cpp": "cpp", "rust": "rs", "zig": "zig", "lanius": "lani",
    "pareas": "par", "go": "go", "d": "d", "v": "v", "vx": "vx", "ts": "ts",
}
# Compilers added with the toolchains directory run in their per-sample work
# directory (Go would otherwise pick up an enclosing go.mod, dmd and LDC drop
# object files into the working directory). The original five keep the
# repository as their working directory, as in the retained baselines.
WORKDIR_COMPILERS = ("d", "ldc", "go", "v", "vx", "tsc", "tsrs")
DEFAULT_TOOLCHAINS = Path(
    "/home/andrew-peterson/code/laniusc/target/claude-work/toolchains"
)
GO_ROOT = "go/go"
DMD = "dmd/dmd2/linux/bin64/dmd"
LDC2 = "ldc/ldc2-1.43.0-linux-x86_64/bin/ldc2"
V_ROOT = "v"
VX_PREFIX = "vx/vx-v0.0.3-x86_64-unknown-linux-gnu"
TSC_NATIVE = "ts/node_modules/@typescript/typescript-linux-x64/lib/tsc"
TSRS_NATIVE = "ts/node_modules/@tsrs/linux-x64-gnu/tsrs"
TSC_LAUNCHER = "ts/node_modules/typescript/bin/tsc"
TSRS_LAUNCHER = "ts/node_modules/tsrs/bin/tsrs"
# --checkers is passed identically to both TypeScript compilers; 4 is tsgo's
# default, and a one-file program cannot use more than one checker anyway.
TYPESCRIPT_CHECKERS = 4


def parse_external_compilers(value: str) -> tuple[str, ...]:
    if value.strip().lower() == "none":
        return ()
    languages = tuple(part.strip() for part in value.split(",") if part.strip())
    unknown = set(languages) - set(EXTERNAL_COMPILERS)
    if not languages or unknown:
        expected = ",".join(EXTERNAL_COMPILERS)
        raise argparse.ArgumentTypeError(
            f"external compilers must be 'none' or a non-empty subset of {expected}; "
            f"unknown: {sorted(unknown)}"
        )
    return languages


# Opt-in lane (select it with --lanes fastest): each compiler's fastest
# single-file configuration, using whatever parallelism the compiler offers
# for one file. FASTEST_BASIS says what each one is; the probe that chose them
# compiled an unmeasured seed with every candidate.
FASTEST_LANE = "fastest"
FASTEST_BASIS = {
    "c": "o0 lane (gcc -O0); gcc compiles one translation unit on one thread",
    "cpp": "o0 lane (g++ -O0); g++ compiles one translation unit on one thread",
    "tcc": "default lane; single-threaded",
    "rust": "optimized lane (opt-level=3 compiles faster than opt-level=0 here); -Zthreads=16 parallel frontend and rustc's default 16 codegen units",
    "zig": "optimized lane (ReleaseFast is faster than Debug here); zig 0.13 has no option that parallelizes one file",
    "d": "o0 lane (dmd without -O); dmd is single-threaded",
    "ldc": "o0 lane (-O0); LDC codegens one module on one thread",
    "go": "o0 lane plus -c=16 backend concurrency (-gcflags='-N -l -c=16'); measured no faster than the default -c on one file",
    "v": "o0 lane (V development build, bundled TCC); V already threads its transform and cgen by default (-no-parallel was 40% slower) and -parallel-cc was slower with TCC",
    "vx": "o0 lane plus -j 16 (vxc's parallel frontend on 16 threads, about 11% faster than the sequential driver)",
    "tsc": "check_emit lane with --checkers 4; default, 4, and 16 checkers measured within noise on one file, --singleThreaded slower",
    "tsrs": "check_emit lane with --checkers 4; default, 4, 16 checkers and --singleThreaded measured within noise on one file",
}


def lanes_for(language: str) -> tuple[str, ...]:
    if language == "tcc":
        return ("default",)
    if language == "pareas":
        return ("cuda",)
    if language in TYPESCRIPT_COMPILERS:
        return ("check_emit",)
    return LANES


def source_language(compiler: str) -> str:
    return SOURCE_LANGUAGE.get(compiler, compiler)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="target/compiler-stress-matrix")
    parser.add_argument("--size", type=int, default=1_000_000)
    parser.add_argument("--seeds", default=",".join(str(seed) for seed in range(20, 40)))
    parser.add_argument("--warm-seed", type=int, default=19)
    parser.add_argument("--order-seed", type=int, default=0x1A91_05)
    parser.add_argument("--rust-frontend-threads", type=int, default=16)
    parser.add_argument(
        "--external-compilers",
        type=parse_external_compilers,
        default=EXTERNAL_COMPILERS,
    )
    parser.add_argument("--tcc", default="tcc", help="TCC executable")
    parser.add_argument(
        "--pareas",
        default=str(Path.home() / "code/pareas/build-laniusc-cuda-futhark025/pareas"),
        help="Pareas CUDA executable",
    )
    parser.add_argument(
        "--tcc-runtime-path",
        type=Path,
        help="optional TCC runtime directory for an extracted installation",
    )
    parser.add_argument(
        "--tcc-library-path",
        type=Path,
        help="optional TCC library directory (-L) holding libtcc1.a, e.g. V's bundled TCC",
    )
    parser.add_argument(
        "--toolchains",
        type=Path,
        default=DEFAULT_TOOLCHAINS,
        help="directory holding the go, dmd, ldc, v, vx, and ts toolchains",
    )
    parser.add_argument(
        "--lanes",
        help="optional comma-separated lane filter (e.g. optimized), for splitting long matrices",
    )
    parser.add_argument(
        "--skip-lanius",
        action="store_true",
        help="measure external compilers only (Lanius is measured by lanius_perf.py run-lanius)",
    )
    parser.add_argument(
        "--typescript-launcher-samples",
        type=int,
        default=0,
        help="also time the node launchers (npx-style) against the native TypeScript binaries",
    )
    parser.add_argument(
        "--profile",
        choices=tuple(WORKLOAD_PROFILES),
        default="pareas-common-subset",
    )
    args = parser.parse_args()
    seeds = [int(value) for value in args.seeds.split(",")]
    if args.size <= 0 or not seeds or len(set(seeds)) != len(seeds):
        parser.error("--size must be positive and --seeds must be unique")
    if args.warm_seed in seeds:
        parser.error("--warm-seed must not be a measured seed")
    if args.rust_frontend_threads <= 0:
        parser.error("--rust-frontend-threads must be positive")
    if "pareas" in args.external_compilers and args.profile != "pareas-common-subset":
        parser.error("Pareas requires --profile pareas-common-subset")
    if args.skip_lanius and not args.external_compilers:
        parser.error("--skip-lanius needs at least one external compiler")

    repo = Path(__file__).resolve().parents[1]
    out = resolve(repo, args.out)
    source_root = out / "sources"
    bin_root = out / "bin"
    source_root.mkdir(parents=True, exist_ok=True)
    bin_root.mkdir(parents=True, exist_ok=True)
    expected, source_variants = generate_sources(
        repo, source_root, args.size, [args.warm_seed, *seeds], args.profile
    )

    toolchains = args.toolchains.resolve()
    command_templates = compiler_commands(
        repo,
        args.rust_frontend_threads,
        args.tcc,
        args.tcc_runtime_path,
        args.pareas,
        toolchains,
        args.tcc_library_path,
    )
    lane_filter = (
        {part.strip() for part in args.lanes.split(",") if part.strip()}
        if args.lanes
        else None
    )
    selected_lanes = {
        language: tuple(
            lane for lane in lanes_for(language) if lane_filter is None or lane in lane_filter
        ) + (
            (FASTEST_LANE,)
            if lane_filter is not None and FASTEST_LANE in lane_filter and language in FASTEST_BASIS
            else ()
        )
        for language in args.external_compilers
    }
    environments = {
        language: compiler_environment(language, toolchains, out / "caches")
        for language in args.external_compilers
        if language != "pareas"
    }
    provenance = collect_provenance(
        repo,
        command_templates,
        args.external_compilers,
        environments,
        include_lanius=not args.skip_lanius,
    )
    tasks = [
        (language, lane, seed)
        for seed in seeds
        for language in args.external_compilers
        for lane in selected_lanes[language]
    ]
    random.Random(args.order_seed).shuffle(tasks)
    lanius_seeds = list(seeds)
    random.Random(args.order_seed ^ 0x4C41_4E49).shuffle(lanius_seeds)

    pareas_environment, pareas_environment_owner = (
        prepare_pareas_environment()
        if "pareas" in args.external_compilers
        else (None, None)
    )
    if pareas_environment is not None:
        environments["pareas"] = pareas_environment
    daemon, ready = (None, None) if args.skip_lanius else start_daemon(repo)
    samples = []
    warmups = []
    launcher_overhead = None
    try:
        if daemon is not None:
            warm_output = bin_root / f"lanius-warm-{args.warm_seed}"
            compile_lanius(
                daemon,
                source_path(source_root, args.warm_seed, "lanius"),
                warm_output,
                f"warm-{args.warm_seed}",
            )
            validate_executable(warm_output, expected[args.warm_seed])
        # One unmeasured compile of the warm seed per compiler configuration
        # warms the OS file cache and any standard library a toolchain builds
        # lazily (Go compiles its standard library into GOCACHE on first use)
        # without touching a measured source.
        for language in args.external_compilers:
            for lane in selected_lanes[language]:
                sample, _, _ = run_external(
                    language, lane, args.warm_seed, command_templates, source_root,
                    bin_root / "warmup", repo, environments.get(language), expected,
                )
                warmups.append({
                    "language": language,
                    "lane": lane,
                    "seed": args.warm_seed,
                    "wall_ms": sample["wall_ms"],
                    "cache_entries_added": sample["cache_entries_added"],
                })
        for order, (language, lane, seed) in enumerate(tasks):
            sample, stdout, (source, artifact) = run_external(
                language, lane, seed, command_templates, source_root,
                bin_root, repo, environments.get(language), expected,
            )
            samples.append(
                {
                    "order": order,
                    "phase": "external_randomized",
                    "language": language,
                    "lane": lane,
                    "seed": seed,
                    "source_bytes": source.stat().st_size,
                    "source_sha256": sha256_file(source),
                    "output_sha256": sha256_file(artifact),
                    "stdout_sha256": sha256_bytes(stdout.encode()) if stdout is not None else None,
                    **sample,
                }
            )
        if args.typescript_launcher_samples > 0:
            launcher_overhead = measure_typescript_launchers(
                [language for language in args.external_compilers if language in TYPESCRIPT_COMPILERS],
                args.typescript_launcher_samples,
                args.warm_seed,
                command_templates,
                source_root,
                bin_root / "launcher",
                repo,
                environments,
                expected,
            )
        for seed in seeds if daemon is not None else []:
            capacity_output = bin_root / f"lanius-capacity-warm-{seed}"
            compile_lanius(
                daemon,
                source_path(source_root, seed, "lanius"),
                capacity_output,
                f"capacity-warm-{seed}",
            )
            validate_executable(capacity_output, expected[seed])
        # End capacity preparation on a source that is not part of the measured
        # set. Otherwise the first randomized sample can accidentally measure
        # an immediate same-project recompile while every later sample switches
        # projects and rebuilds shape-dependent job resources.
        if daemon is not None:
            variable_project_primer = bin_root / f"lanius-variable-primer-{args.warm_seed}"
            compile_lanius(
                daemon,
                source_path(source_root, args.warm_seed, "lanius"),
                variable_project_primer,
                f"variable-primer-{args.warm_seed}",
            )
            validate_executable(variable_project_primer, expected[args.warm_seed])
        for seed in lanius_seeds if daemon is not None else []:
            output = bin_root / f"lanius-variable-project-{seed}"
            source = source_path(source_root, seed, "lanius")
            sample = compile_lanius(daemon, source, output, f"measure-{seed}")
            stdout = validate_executable(output, expected[seed])
            samples.append({
                "order": len(samples),
                "phase": "lanius_hot_daemon_variable_project",
                "language": "lanius",
                "lane": "hot_daemon_variable_project",
                "seed": seed,
                "source_bytes": source.stat().st_size,
                "source_sha256": sha256_file(source),
                "output_sha256": sha256_file(output),
                "stdout_sha256": sha256_bytes(stdout.encode()),
                **sample,
            })
    finally:
        if daemon is not None:
            stop_daemon(daemon)
        if pareas_environment_owner is not None:
            pareas_environment_owner.cleanup()

    summary = summarize(samples)
    write_json(out / "config.json", {
        "schema": "lanius.compiler-stress-matrix-config.v1",
        "classification": "synthetic_stress",
        "representative_workload": False,
        "size": args.size,
        "seeds": seeds,
        "warm_seed": args.warm_seed,
        "order_seed": args.order_seed,
        "external_compilers": args.external_compilers,
        "lanes": {language: list(lanes) for language, lanes in selected_lanes.items()},
        "lanius_measured": not args.skip_lanius,
        "toolchains": str(toolchains),
        "typescript_checkers": TYPESCRIPT_CHECKERS,
        "fastest_basis": {
            language: FASTEST_BASIS[language]
            for language, lanes in selected_lanes.items()
            if FASTEST_LANE in lanes
        },
        "typescript_launcher_overhead": launcher_overhead,
        "workload_profile": args.profile,
        "timing_policy": "wall clock from request/process start through artifact write (for Vx: vxc object emission plus the link vxc itself performs); Pareas compiler_ms is its synchronized frontend plus backend profile and excludes context initialization",
        "sample_policy": "all samples retained; median is primary, min/max/MAD are reported",
        "warmup_policy": "one unmeasured compile of the warm seed per external compiler configuration before the randomized measured tasks",
        "warmups": warmups,
        "validation_policy": "native artifacts (C, C++, Rust, Zig, TCC, D, Go, V, Vx, Lanius) execute with exact model-derived stdout; tsc/tsrs emit JavaScript that node runs with exact model-derived stdout; Pareas emits raw RISC-V bytes, which must be nonempty, instruction-aligned, and deterministic",
        "cache_policy": "every measured seed is a distinct source compiled once per lane; Go (GOCACHE) and V (VTMP module cache) use caches private to this run, created empty and warmed only by the warm seed (Go standard library, V builtin/closure modules and third-party C objects); a Go or V sample that adds no cache entry (a hit: Go compile action, V whole-program executable) fails the run; cache_entries_added records that growth",
        "daemon_warmup_policy": "one pipeline warmup seed; after CPU trials, one unmeasured capacity warmup per measured seed, then a different-source primer before the contiguous randomized variable-project hot-daemon batch",
        "debug_info": "disabled in every applicable external compiler lane",
    })
    write_json(out / "commands.json", command_templates)
    write_json(out / "source_manifest.json", {
        "schema": "lanius.compiler-stress-source-manifest.v1",
        "generator_path": "tools/generate_compiler_stress.py",
        "model_path": "tools/compiler_stress_model.py",
        "workload_classification": "synthetic_stress",
        "representative_workload": False,
        "workload_profile": args.profile,
        "variants": source_variants,
    })
    outputs = out / "outputs"
    outputs.mkdir(exist_ok=True)
    for seed in seeds:
        (outputs / f"seed-{seed}.stdout").write_text(expected[seed])
    write_json(out / "machine_info.json", machine_info(ready))
    write_json(out / "provenance.json", provenance)
    write_json(out / "samples.json", {"schema": "lanius.compiler-stress-samples.v1", "samples": samples})
    write_json(out / "summary.json", {"schema": "lanius.compiler-stress-summary.v1", "rows": summary})
    write_tsv(out / "results.tsv", samples)
    write_json(out / "manifest.json", manifest(out))
    return 0


def generate_sources(
    repo: Path, out: Path, size: int, seeds: list[int], profile: str
):
    expected = {}
    variants = {}
    for seed in seeds:
        target = out / f"seed-{seed}"
        run = subprocess.run(
            ["python3", "tools/generate_compiler_stress.py", "--out", str(target),
             "--layout", "comparative-single-file", "--sizes", str(size),
             "--seed", str(seed), "--profile", profile],
            cwd=repo, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        if run.returncode != 0:
            raise RuntimeError(f"source generation failed for seed {seed}: {run.stderr}")
        document = json.loads((target / "manifest.json").read_text())
        source_set = document["source_sets"][0]
        expected[seed] = source_set["expected_stdout"]
        variants[str(seed)] = source_set
    return expected, variants


def compiler_commands(
    repo: Path,
    rust_frontend_threads: int = 16,
    tcc: str = "tcc",
    tcc_runtime_path: Path | None = None,
    pareas: str | None = None,
    toolchains: Path = DEFAULT_TOOLCHAINS,
    tcc_library_path: Path | None = None,
) -> dict:
    tcc_command = [tcc]
    if tcc_runtime_path is not None:
        tcc_command.append(f"-B{tcc_runtime_path}")
    if tcc_library_path is not None:
        tcc_command.append(f"-L{tcc_library_path}")
    pareas = pareas or str(
        Path.home() / "code/pareas/build-laniusc-cuda-futhark025/pareas"
    )
    go = str(toolchains / GO_ROOT / "bin/go")
    dmd = str(toolchains / DMD)
    ldc2 = str(toolchains / LDC2)
    v = str(toolchains / V_ROOT / "v")
    return {
        "schema": "lanius.compiler-stress-command-templates.v1",
        "o0": {
            "c": ["gcc", "-O0", "-g0", "{source}", "-o", "{output}"],
            "cpp": ["g++", "-O0", "-g0", "{source}", "-o", "{output}"],
            "rust": ["rustc", "-Awarnings", f"-Zthreads={rust_frontend_threads}", "-C", "opt-level=0", "-C", "debuginfo=0", "-C", "strip=debuginfo", "{source}", "-o", "{output}"],
            "zig": ["zig", "build-exe", "-lc", "-O", "Debug", "-fstrip", "{source}", "-femit-bin={output}"],
            "d": [dmd, "-od={workdir}", "-of={output}", "{source}"],
            "ldc": [ldc2, "-O0", "-od={workdir}", "-of={output}", "{source}"],
            # -gcflags without a package pattern applies to the packages named
            # on the command line only: the main package, not the standard library.
            "go": [go, "build", "-gcflags=-N -l", "-o", "{output}", "{source}"],
            # V's default development build uses its bundled TCC; -w -n silence
            # warnings and notices (V reports a notice for every signed shift).
            "v": [v, "-w", "-n", "-o", "{output}", "{source}"],
            "vx": vx_commands(toolchains, "-O0"),
        },
        "optimized": {
            "c": ["gcc", "-O2", "-g0", "{source}", "-o", "{output}"],
            "cpp": ["g++", "-O2", "-g0", "{source}", "-o", "{output}"],
            "rust": ["rustc", "-Awarnings", f"-Zthreads={rust_frontend_threads}", "-C", "opt-level=3", "-C", "debuginfo=0", "-C", "strip=debuginfo", "{source}", "-o", "{output}"],
            "zig": ["zig", "build-exe", "-lc", "-O", "ReleaseFast", "-fstrip", "{source}", "-femit-bin={output}"],
            "d": [dmd, "-O", "-release", "-inline", "-od={workdir}", "-of={output}", "{source}"],
            # dub's release build type for LDC: -O3 -release (inlining is on at -O3).
            "ldc": [ldc2, "-O3", "-release", "-od={workdir}", "-of={output}", "{source}"],
            "go": [go, "build", "-o", "{output}", "{source}"],
            # -prod compiles the generated C with the system cc at -O3.
            "v": [v, "-w", "-n", "-prod", "-o", "{output}", "{source}"],
            "vx": vx_commands(toolchains, "-O2"),
        },
        "default": {
            "tcc": [*tcc_command, "-std=c11", "{source}", "-o", "{output}"],
        },
        "check_emit": {
            "tsc": [str(toolchains / TSC_NATIVE), "-p", "{workdir}/tsconfig.json", "--checkers", str(TYPESCRIPT_CHECKERS)],
            "tsrs": [str(toolchains / TSRS_NATIVE), "-p", "{workdir}/tsconfig.json", "--checkers", str(TYPESCRIPT_CHECKERS)],
        },
        "typescript_launchers": {
            "tsc": ["node", str(toolchains / TSC_LAUNCHER)],
            "tsrs": ["node", str(toolchains / TSRS_LAUNCHER)],
        },
        FASTEST_LANE: {
            "c": ["gcc", "-O0", "-g0", "{source}", "-o", "{output}"],
            "cpp": ["g++", "-O0", "-g0", "{source}", "-o", "{output}"],
            "tcc": [*tcc_command, "-std=c11", "{source}", "-o", "{output}"],
            "rust": ["rustc", "-Awarnings", f"-Zthreads={rust_frontend_threads}", "-C", "opt-level=3", "-C", "debuginfo=0", "-C", "strip=debuginfo", "{source}", "-o", "{output}"],
            "zig": ["zig", "build-exe", "-lc", "-O", "ReleaseFast", "-fstrip", "{source}", "-femit-bin={output}"],
            "d": [dmd, "-od={workdir}", "-of={output}", "{source}"],
            "ldc": [ldc2, "-O0", "-od={workdir}", "-of={output}", "{source}"],
            "go": [go, "build", "-gcflags=-N -l -c=16", "-o", "{output}", "{source}"],
            "v": [v, "-w", "-n", "-o", "{output}", "{source}"],
            "vx": vx_commands(toolchains, "-O0", jobs=16),
            "tsc": [str(toolchains / TSC_NATIVE), "-p", "{workdir}/tsconfig.json", "--checkers", str(TYPESCRIPT_CHECKERS)],
            "tsrs": [str(toolchains / TSRS_NATIVE), "-p", "{workdir}/tsconfig.json", "--checkers", str(TYPESCRIPT_CHECKERS)],
        },
        "cuda": {
            "pareas": [pareas, "-p", "1", "{source}", "-o", "{output}"],
        },
        "lanius_daemon": ["target/release/laniusc", "daemon", "--stdio", "--backend", "x86_64", "--stdlib-root", "stdlib"],
    }


def vx_commands(toolchains: Path, level: str, jobs: int | None = None) -> list[list[str]]:
    """vxc v0.0.3 has no action that writes a linked executable: its default
    run action compiles, links with the bundled clang, and runs the program.
    Emit the object, then link exactly as that action does."""
    prefix = toolchains / VX_PREFIX
    return [
        [str(prefix / "bin/vxc"), level, *(["-j", str(jobs)] if jobs else []), "-c", "{source}", "-o", "{workdir}/scaling.o"],
        [
            str(prefix / "llvm/bin/clang"),
            f"-Wl,-rpath,{prefix / 'llvm/lib'}",
            f"-Wl,-rpath,{prefix / 'lib'}",
            "{workdir}/scaling.o",
            "-o",
            "{output}",
            str(prefix / "llvm/lib/libmlir_c_runner_utils.so"),
            str(prefix / "llvm/lib/libmlir_runner_utils.so"),
            str(prefix / "lib/libvx_std_core.so"),
            str(prefix / "lib/libvx_mlir_shims.so"),
            str(prefix / "lib/libvx_x86_dispatch.so"),
            "-lffi",
            "-rdynamic",
            "-lm",
        ],
    ]


def compiler_environment(
    language: str, toolchains: Path, cache_root: Path
) -> dict[str, str] | None:
    """Keep every toolchain's settings inside the toolchains directory and its
    build caches inside this run (cache_root), so no run reuses another's."""
    if language == "go":
        environment = os.environ.copy()
        environment.pop("GOBIN", None)
        environment.update({
            "GOROOT": str(toolchains / GO_ROOT),
            "GOTOOLCHAIN": "local",
            "GOENV": "off",
            "GOFLAGS": "",
            "GOPATH": str(toolchains / "go-home/gopath"),
            "GOCACHE": str(cache_root / "go-cache"),
            # Go's local telemetry counters live under the user config directory.
            "XDG_CONFIG_HOME": str(toolchains / "go-home/config"),
        })
        return environment
    if language == "v":
        environment = os.environ.copy()
        environment.update({
            "VMODULES": str(toolchains / "v-home/vmodules"),
            "VCACHE": str(cache_root / "v-cache"),
            # V keeps its module cache (builtin objects, and one whole-program
            # executable per source path) under VTMP.
            "VTMP": str(cache_root / "v-tmp"),
        })
        return environment
    return None


def cache_directory(language: str, environment: dict[str, str] | None) -> Path | None:
    if environment is None:
        return None
    if language == "go":
        return Path(environment["GOCACHE"])
    if language == "v":
        return Path(environment["VTMP"])
    return None


def count_files(root: Path | None, language: str = "") -> int | None:
    """Entries in a compiler cache. For V, the whole-program executable stamps
    its module cache writes on a miss (a hit for an unchanged program writes none)."""
    if root is None:
        return None
    if not root.exists():
        return 0
    if language == "v":
        return sum(1 for path in root.rglob("program_*.exe.stamp") if path.is_file())
    return sum(1 for path in root.rglob("*") if path.is_file())


def write_tsconfig(workdir: Path, source: Path) -> None:
    write_json(workdir / "tsconfig.json", {
        "compilerOptions": {
            "target": "ES2022",
            "strict": True,
            "skipLibCheck": True,
            "noEmitOnError": True,
            "rootDir": str(source.parent),
            "outDir": str(workdir),
        },
        "files": [str(source)],
    })


def run_external(
    language: str,
    lane: str,
    seed: int,
    templates: dict,
    source_root: Path,
    bin_root: Path,
    repo: Path,
    environment: dict[str, str] | None,
    expected: dict[int, str],
) -> tuple[dict, str | None, tuple[Path, Path]]:
    bin_root.mkdir(parents=True, exist_ok=True)
    source = source_path(source_root, seed, language)
    workdir = bin_root / f"{language}-{lane}-{seed}.work"
    shutil.rmtree(workdir, ignore_errors=True)
    workdir.mkdir()
    output = bin_root / f"{language}-{lane}-{seed}"
    artifact = output
    if language in TYPESCRIPT_COMPILERS:
        write_tsconfig(workdir, source)
        artifact = workdir / "scaling.js"
    command = materialize(templates[lane][language], source, output, workdir)
    cache = cache_directory(language, environment)
    before = count_files(cache, language)
    sample = compile_process(
        command,
        workdir if language in WORKDIR_COMPILERS else repo,
        environment=environment,
        parse_pareas_profile=language == "pareas",
    )
    after = count_files(cache, language)
    sample["cache_entries_added"] = None if before is None else after - before
    if language in ("go", "v") and sample["cache_entries_added"] <= 0:
        raise RuntimeError(
            f"{language} build of seed {seed} ({lane}) added no cache entry: a cache hit"
        )
    if language == "pareas":
        validate_pareas_artifact(output)
        stdout = None
    elif language in TYPESCRIPT_COMPILERS:
        stdout = validate_javascript(artifact, expected[seed])
    else:
        stdout = validate_executable(output, expected[seed])
    return sample, stdout, (source, artifact)


def measure_typescript_launchers(
    compilers: list[str],
    sample_count: int,
    seed: int,
    templates: dict,
    source_root: Path,
    bin_root: Path,
    repo: Path,
    environments: dict,
    expected: dict[int, str],
) -> dict:
    """What `npx tsc` adds: the node launcher's wall time against the native binary."""
    result = {"seed": seed, "samples": sample_count, "compilers": {}}
    for compiler in compilers:
        native = templates["check_emit"][compiler][0]
        launcher = templates["typescript_launchers"][compiler]
        version_native = [time_process([native, "--version"], repo) for _ in range(sample_count)]
        version_launcher = [time_process([*launcher, "--version"], repo) for _ in range(sample_count)]
        compile_native = []
        compile_launcher = []
        for index in range(sample_count):
            for kind, prefix, values in (
                ("native", [native], compile_native),
                ("launcher", launcher, compile_launcher),
            ):
                workdir = bin_root / f"{compiler}-{kind}-{index}.work"
                shutil.rmtree(workdir, ignore_errors=True)
                workdir.mkdir(parents=True)
                source = source_path(source_root, seed, compiler)
                write_tsconfig(workdir, source)
                command = [*prefix, *materialize(templates["check_emit"][compiler][1:], source, workdir / "unused", workdir)]
                values.append(compile_process(command, workdir)["wall_ms"])
                validate_javascript(workdir / "scaling.js", expected[seed])
        result["compilers"][compiler] = {
            "native": native,
            "launcher": launcher,
            "version_native_median_ms": statistics.median(version_native),
            "version_launcher_median_ms": statistics.median(version_launcher),
            "compile_native_median_ms": statistics.median(compile_native),
            "compile_launcher_median_ms": statistics.median(compile_launcher),
            "launcher_overhead_ms": statistics.median(compile_launcher) - statistics.median(compile_native),
        }
    return result


def time_process(command: list[str], cwd: Path) -> float:
    started = time.perf_counter_ns()
    run = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    elapsed = (time.perf_counter_ns() - started) / 1_000_000.0
    if run.returncode != 0:
        raise RuntimeError(f"command failed: {command!r}\n{run.stderr}")
    return elapsed


def materialize(template: list, source: Path, output: Path, workdir: Path | None = None) -> list:
    if template and isinstance(template[0], list):
        return [materialize(step, source, output, workdir) for step in template]
    return [
        part.format(source=source, output=output, workdir=workdir if workdir is not None else output.parent)
        for part in template
    ]


def command_steps(command: list) -> list[list[str]]:
    return command if command and isinstance(command[0], list) else [command]


def compile_process(
    command: list,
    cwd: Path,
    environment: dict[str, str] | None = None,
    parse_pareas_profile: bool = False,
) -> dict:
    steps = command_steps(command)
    step_ms = []
    outputs = []
    started = time.perf_counter_ns()
    for step in steps:
        step_started = time.perf_counter_ns()
        run = subprocess.run(
            step,
            cwd=cwd,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        step_ms.append((time.perf_counter_ns() - step_started) / 1_000_000.0)
        if run.returncode != 0:
            raise RuntimeError(f"compile failed: {step!r}\n{run.stderr}")
        outputs.append(run.stdout + "\n" + run.stderr)
    elapsed = (time.perf_counter_ns() - started) / 1_000_000.0
    compiler_ms = None
    context_init_ms = None
    if parse_pareas_profile:
        profile = parse_pareas_timings(outputs[-1])
        compiler_ms = profile["frontend_ms"] + profile["backend_ms"]
        context_init_ms = profile["context_init_ms"]
    return {
        "wall_ms": elapsed,
        "step_wall_ms": step_ms if len(steps) > 1 else None,
        "compiler_ms": compiler_ms,
        "context_init_ms": context_init_ms,
        "daemon_load_ms": None,
        "daemon_compile_ms": None,
        "daemon_write_ms": None,
    }


def parse_pareas_timings(output: str) -> dict[str, float]:
    timings = {
        match.group(1).replace(" ", "_") + "_ms": int(match.group(2)) / 1000.0
        for match in re.finditer(
            r"^(context init|frontend|backend):\s*([0-9]+)(?:µs|us)$",
            output,
            re.MULTILINE,
        )
    }
    required = {"context_init_ms", "frontend_ms", "backend_ms"}
    if timings.keys() != required:
        raise RuntimeError(
            f"Pareas profile did not contain exactly {sorted(required)}: {output!r}"
        )
    return timings


def start_daemon(repo: Path):
    command = compiler_commands(repo)["lanius_daemon"]
    process = subprocess.Popen(command, cwd=repo, text=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=1)
    ready = read_json_line(process, 900.0)
    if ready.get("event") != "ready":
        raise RuntimeError(f"daemon did not become ready: {ready}")
    return process, ready


def compile_lanius(process, source: Path, output: Path, request_id: str) -> dict:
    request = {"id": request_id, "command": "compile", "emit": "x86_64", "input": str(source), "output": str(output)}
    assert process.stdin is not None
    started = time.perf_counter_ns()
    process.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
    process.stdin.flush()
    response = read_json_line(process, 180.0)
    elapsed = (time.perf_counter_ns() - started) / 1_000_000.0
    if response.get("id") != request_id or response.get("ok") is not True:
        raise RuntimeError(f"daemon compile failed: {response}")
    return {"wall_ms": elapsed, "compiler_ms": response.get("compile_ms"), "context_init_ms": None, "daemon_load_ms": response.get("load_ms"), "daemon_compile_ms": response.get("compile_ms"), "daemon_write_ms": response.get("write_ms")}


def stop_daemon(process) -> None:
    if process.poll() is not None:
        return
    assert process.stdin is not None
    process.stdin.write('{"id":"shutdown","command":"shutdown"}\n')
    process.stdin.flush()
    try:
        read_json_line(process, 10.0)
        process.wait(timeout=10.0)
    except Exception:
        process.kill()
        process.wait()


def read_json_line(process, timeout: float) -> dict:
    assert process.stdout is not None
    readable, _, _ = select.select([process.stdout], [], [], timeout)
    if not readable:
        raise TimeoutError(f"daemon response timed out after {timeout}s")
    line = process.stdout.readline()
    if not line:
        stderr = process.stderr.read() if process.stderr else ""
        raise RuntimeError(f"daemon exited early: {process.poll()}\n{stderr}")
    return json.loads(line)


def validate_executable(path: Path, expected: str) -> str:
    run = subprocess.run([str(path)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30.0)
    if run.returncode != 0 or run.stdout != expected:
        raise RuntimeError(f"artifact validation failed for {path}: status={run.returncode}, stdout={run.stdout!r}, expected={expected!r}, stderr={run.stderr}")
    return run.stdout


def validate_javascript(path: Path, expected: str) -> str:
    run = subprocess.run(["node", str(path)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30.0)
    if run.returncode != 0 or run.stdout != expected:
        raise RuntimeError(f"JavaScript validation failed for {path}: status={run.returncode}, stdout={run.stdout!r}, expected={expected!r}, stderr={run.stderr}")
    return run.stdout


def validate_pareas_artifact(path: Path) -> None:
    size = path.stat().st_size
    if size == 0 or size % 4 != 0:
        raise RuntimeError(
            f"Pareas RISC-V artifact must contain whole 32-bit instructions: {path} has {size} bytes"
        )


def summarize(samples: list[dict]) -> list[dict]:
    groups = {}
    for sample in samples:
        groups.setdefault((sample["language"], sample["lane"]), []).append(sample)
    rows = []
    for (language, lane), group in sorted(groups.items()):
        values = [sample["wall_ms"] for sample in group]
        median = statistics.median(values)
        compiler_values = [
            sample["compiler_ms"]
            for sample in group
            if sample.get("compiler_ms") is not None
        ]
        compiler_median = statistics.median(compiler_values) if compiler_values else None
        rows.append({
            "language": language,
            "lane": lane,
            "samples": len(values),
            "median_ms": median,
            "min_ms": min(values),
            "max_ms": max(values),
            "mad_ms": statistics.median(abs(value - median) for value in values),
            "compiler_median_ms": compiler_median,
            "compiler_mad_ms": (
                statistics.median(abs(value - compiler_median) for value in compiler_values)
                if compiler_values
                else None
            ),
        })
    lanius = next((row["median_ms"] for row in rows if row["language"] == "lanius"), None)
    lanius_compiler = next(
        (row["compiler_median_ms"] for row in rows if row["language"] == "lanius"), None
    )
    for row in rows:
        row["speedup_vs_lanius"] = row["median_ms"] / lanius if lanius else None
        row["compiler_speedup_vs_lanius"] = (
            row["compiler_median_ms"] / lanius_compiler
            if row["compiler_median_ms"] is not None and lanius_compiler is not None
            else None
        )
    return rows


def collect_provenance(
    repo: Path,
    commands: dict,
    external_compilers: tuple[str, ...] = EXTERNAL_COMPILERS,
    environments: dict | None = None,
    include_lanius: bool = True,
) -> dict:
    environments = environments or {}
    tools = {}
    for language in external_compilers:
        for lane in lanes_for(language):
            for step in command_steps(commands[lane][language]):
                tools.setdefault(step[0], language)
    if include_lanius:
        tools[str(repo / "target/release/laniusc")] = "lanius"
    rows = {}
    for tool, language in sorted(tools.items()):
        # Version queries go through the name the commands use: resolving
        # symlinks first would ask rustup (not rustc) for its version.
        invoked = Path(shutil.which(tool) or tool)
        path = invoked.resolve()
        rows[tool] = {
            "language": language,
            "path": str(path),
            "sha256": sha256_file(path),
            "version": tool_version(invoked, language, environments.get(language)),
        }
    extras = {}
    if any(language in TYPESCRIPT_COMPILERS for language in external_compilers):
        extras["node"] = command_output(["node", "--version"])
    if "v" in external_compilers:
        extras["cc (V -prod backend)"] = command_output(["cc", "--version"]).splitlines()[0]
        extras["tcc (V development backend)"] = command_output(
            [str(Path(commands["o0"]["v"][0]).parent / "thirdparty/tcc/tcc.exe"), "-v"]
        )
    return {
        "schema": "lanius.compiler-stress-provenance.v1",
        "tools": rows,
        "auxiliary_tools": extras,
        "runner_sha256": sha256_file(repo / "tools/run_compiler_stress_matrix.py"),
        "generator_sha256": sha256_file(repo / "tools/generate_compiler_stress.py"),
        "model_sha256": sha256_file(repo / "tools/compiler_stress_model.py"),
    }


def machine_info(ready: dict | None) -> dict:
    return {
        "schema": "lanius.compiler-stress-machine.v1",
        "system": platform.platform(),
        "cpu": platform.processor(),
        "cpu_model": proc_field("/proc/cpuinfo", "model name"),
        "memory_total": proc_field("/proc/meminfo", "MemTotal"),
        "logical_cpus": os.cpu_count(),
        "gpu": command_output(["nvidia-smi", "--query-gpu=name,driver_version,memory.total", "--format=csv,noheader,nounits"]),
        "daemon_ready": ready,
    }


def proc_field(path: str, key: str) -> str | None:
    try:
        for line in Path(path).read_text().splitlines():
            name, sep, value = line.partition(":")
            if sep and name.strip() == key:
                return value.strip()
    except OSError:
        return None
    return None


def command_output(command: list[str], environment: dict[str, str] | None = None) -> str:
    run = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=environment)
    return run.stdout.strip()


def tool_version(path: Path, language: str, environment: dict[str, str] | None = None) -> str:
    if language == "pareas":
        for parent in path.parents:
            if (parent / ".git").exists():
                commit = command_output(["git", "-C", str(parent), "rev-parse", "HEAD"])
                return f"git {commit}"
        return "Pareas CLI has no version flag; executable hash recorded"
    if (language == "go" and path.name == "go") or language == "zig":
        argv = [str(path), "version"]
    elif path.name.startswith("tcc"):
        argv = [str(path), "-v"]
    else:
        argv = [str(path), "--version"]
    lines = [
        line for line in command_output(argv, environment).splitlines() if line.strip()
    ]
    return lines[0] if lines else "no version output"


def prepare_pareas_environment():
    environment = os.environ.copy()
    cuda_home = environment.get("CUDA_HOME")
    if cuda_home and (Path(cuda_home) / "include/cuda_runtime.h").exists():
        return environment, None

    try:
        import nvidia.cuda_nvcc
        import nvidia.cuda_nvrtc
        import nvidia.cuda_runtime
    except ImportError as error:
        raise RuntimeError(
            "Pareas needs CUDA_HOME or the nvidia-cuda-runtime, nvidia-cuda-nvrtc, and nvidia-cuda-nvcc Python packages"
        ) from error

    runtime = Path(next(iter(nvidia.cuda_runtime.__path__)))
    nvrtc = Path(next(iter(nvidia.cuda_nvrtc.__path__)))
    nvcc = Path(next(iter(nvidia.cuda_nvcc.__path__)))
    owner = tempfile.TemporaryDirectory(prefix="lanius-pareas-cuda-")
    cuda_root = Path(owner.name)
    include = cuda_root / "include"
    include.mkdir()
    for source in (runtime / "include").iterdir():
        (include / source.name).symlink_to(source, target_is_directory=source.is_dir())
    (include / "crt").symlink_to(nvcc / "include/crt", target_is_directory=True)
    environment["CUDA_HOME"] = str(cuda_root)
    library_paths = [str(runtime / "lib"), str(nvrtc / "lib")]
    if environment.get("LD_LIBRARY_PATH"):
        library_paths.append(environment["LD_LIBRARY_PATH"])
    environment["LD_LIBRARY_PATH"] = os.pathsep.join(library_paths)
    return environment, owner


def source_path(root: Path, seed: int, language: str) -> Path:
    suffix = SOURCE_SUFFIX[source_language(language)]
    size_dirs = [path for path in (root / f"seed-{seed}").iterdir() if path.is_dir()]
    if len(size_dirs) != 1:
        raise RuntimeError(f"expected one size directory for seed {seed}")
    return size_dirs[0] / f"scaling.{suffix}"


def write_tsv(path: Path, samples: list[dict]) -> None:
    fields = ("order", "phase", "language", "lane", "seed", "source_bytes", "wall_ms", "compiler_ms", "context_init_ms", "daemon_load_ms", "daemon_compile_ms", "daemon_write_ms", "source_sha256", "output_sha256", "stdout_sha256")
    lines = ["\t".join(fields)]
    for row in samples:
        lines.append("\t".join("" if row.get(field) is None else (f"{row[field]:.3f}" if isinstance(row[field], float) else str(row[field])) for field in fields))
    path.write_text("\n".join(lines) + "\n")


def manifest(out: Path) -> dict:
    files = [{"path": str(path.relative_to(out)), "bytes": path.stat().st_size, "sha256": sha256_file(path)} for path in sorted(out.rglob("*")) if path.is_file() and "bin" not in path.relative_to(out).parts and "sources" not in path.relative_to(out).parts and path.name != "manifest.json"]
    return {"schema": "lanius.compiler-stress-matrix-manifest.v1", "files": files}


def resolve(repo: Path, raw: str) -> Path:
    path = Path(raw)
    return path if path.is_absolute() else repo / path


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


if __name__ == "__main__":
    raise SystemExit(main())

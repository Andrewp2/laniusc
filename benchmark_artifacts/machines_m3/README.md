# M3: `run` against the M0 scanner baseline

`src/scan_run.lani` is M0's scanner (`benchmark_artifacts/machines_m0/src/`)
written as a `machine Scanner on u8` and driven by `m.run(bytes, BYTES)`.
The other three programs are M0's, rebuilt with the same laniusc. Built with

    laniusc --stdlib-root stdlib --emit x86_64 SRC.lani -o bin/NAME

and timed with `../machines_m0/run_bench.py bin 5 scan_input scan_step scan_direct scan_run`
on the laptop (`machine_info.json`). `results.tsv` holds the times; scan time is
a program's minimum minus `scan_input`'s, which only generates the input.

| Program | Scan only (s) |
|---|---|
| `scan_step` (loop around `step`) | 1.341 |
| `scan_run` (`run`) | 0.829 |
| `scan_direct` (nested loops by hand) | 0.498 |

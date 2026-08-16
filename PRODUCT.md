# Lanius Performance Viewer

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

The primary user is Lanius's creator and principal compiler developer. The viewer supports hands-on compiler engineering: comparing revisions and execution modes, finding performance regressions, and deciding what part of the compiler to optimize next.

## Product Purpose

The performance viewer is an internal engineering instrument for understanding Lanius compilation behavior. It turns retained benchmark results and compiler telemetry into a consistent place to compare compilation latency, throughput, variability, GPU memory use, phase timing, CPU and GPU activity, and the executed compiler graph.

Success means a benchmark result can be reproduced, compared fairly with relevant historical and external results, and traced from its headline latency down to the compiler work responsible for that time or memory use.

## Positioning

The viewer combines benchmark reporting with Lanius-specific compiler introspection. It distinguishes process-cold, daemon-with-cold-workspace, and daemon-with-preallocated-workspace compilation; preserves the exact commands and workload facts behind measurements; and connects aggregate performance to phase, memory, Nsight, and compiler-graph telemetry.

## Operating Context

- Benchmark runs are stored as checked JSON artifacts rather than treated as disposable terminal output.
- Lanius measurements change frequently as the compiler evolves. Measurements from C, C++, Rust, Zig, TCC, and Pareas may be frozen and reused when they describe the same explicitly identified workload.
- Workloads include single-file compiler stress and generated typical projects spanning different source sizes and file counts.
- The viewer is served locally from the repository and is used alongside compiler development, profiling, benchmark generation, and performance investigations.
- Comparisons must preserve the source size, source-file count, SLOC, target, compiler configuration, command, machine, timestamp, and sample distribution needed to interpret a result.

## Capabilities and Constraints

- Present compile median, mean, MAD, histograms, median bytes per second, and median SLOC per second.
- Compare Lanius's three cold-to-warm execution modes with matching frozen external compiler results.
- Show source facts, reproduction commands, captured phase timing, tracked GPU memory, CPU/GPU execution timelines, Nsight-derived GPU data, and the topologically layered compiler graph when those data are present.
- Make missing or partial telemetry explicit. Do not invent measurements, dependencies, distributions, or comparison equivalence.
- Match reusable comparison results through an explicit workload identity, not approximate source size or filename heuristics.
- Keep large generated workloads and transient profiler output out of version control while retaining compact, reviewable benchmark evidence.
- The current implementation uses Svelte, TypeScript, Vite, and D3 and builds to a self-contained local HTML viewer.

## Brand Commitments

Use the name “Lanius Performance Viewer” or “Lanius Performance Explorer” only where a product title is useful. Interface language should be concise, technical, and literal. Valuable screen space should not be spent on unexplained qualifiers, redundant labels, marketing language, or implementation history.

## Evidence on Hand

- Canonical benchmark results: `benchmark_artifacts/performance/`
- Generated viewer: `benchmark_artifacts/performance-viewer/index.html`
- Benchmark runner and catalog builder: `tools/lanius_perf.py`
- Canonical performance data model: `tools/perf_model.py`
- Viewer source: `tools/perf-viewer/`
- Compiler phase, memory, Nsight, and execution-graph telemetry are available only for measurements that captured them; their absence must remain visible rather than being filled with fabricated data.

## Product Principles

1. Preserve measurement truth and provenance before improving presentation.
2. Make the next performance decision easier, not merely the dashboard denser.
3. Move progressively from comparison to diagnosis: headline result, distribution, phase and memory attribution, then executed compiler work.
4. Reuse stable external evidence without confusing it with the currently selected Lanius run.
5. Prefer explicit technical meaning over decorative or historical labels.

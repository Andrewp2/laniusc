#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::process::Command;

// Generation and the checksum oracle use the real benchmark generator. The
// result is compiled against the actual stdlib and its complete stdout runs.
// A copied function-name allowlist cannot validate parameter/return contracts.
const GENERATE: &str = r#"
from pathlib import Path
import sys
import generate_stdlib_workload as g
from generate_generic_workload import build_area, Leaf, Step, Workload
mode, entry, expected = sys.argv[1:]
if mode == 'directed':
    kinds = g.kinds_for(True)
    area = build_area(7, 0)
    for i, (kind, (_, _, record)) in enumerate(kinds.items()):
        item = area.records[i % len(area.records)] if record else None
        other = area.records[(i+1) % len(area.records)] if record else None
        steps = tuple(Step(kind, 1000+c, 3000-c, c, item, other)
                      for c in (0, 1, 3, 4, 16, 31, 32, 255, 1024))
        area.leaves.append(Leaf(f'probe_{kind}', 0, i % 7+1, i*17, steps))
        area.salts.append(i*13)
    workload = Workload(7, [area], kinds)
else:
    g.STRING_HELPERS = 2 if mode == 'strings' else 0
    workload = g.build_workload(20, 24, g.kinds_for(False), type_pool=4)
Path(entry).write_text(g.render_single_file(workload))
Path(expected).write_text(g.expected_stdout(workload))
"#;

fn check(mode: &str) {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = common::TempArtifact::new("laniusc_stdlib_workload", mode, Some("lani"));
    let expected = common::TempArtifact::new("laniusc_stdlib_workload", mode, Some("expected"));
    let output = common::short_process_output_with_timeout(
        format!("generate {mode} workload"),
        Command::new("python3")
            .current_dir(&root)
            .env("PYTHONPATH", root.join("tools"))
            .args(["-c", GENERATE, mode])
            .arg(entry.path())
            .arg(expected.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let path = entry.path().to_owned();
    let stdlib = root.join("stdlib");
    let bytes =
        common::run_gpu_codegen_with_timeout(&format!("compile {mode} workload"), move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&path, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("{mode}: {error}"));
    let output = common::run_x86_64_elf_output("stdlib_workload", mode, &bytes);
    assert_eq!(output.status.code(), Some(0), "{mode}: {output:?}");
    assert_eq!(
        output.stdout,
        std::fs::read(expected.path()).unwrap(),
        "{mode}"
    );
    assert!(output.stderr.is_empty(), "{mode}: {output:?}");
}

#[test]
fn default_stdlib_performance_workload_executes_against_its_reference_model() {
    check("default");
}

#[test]
fn string_heavy_stdlib_performance_workload_executes_against_its_reference_model() {
    check("strings");
}

#[test]
fn every_record_container_workload_kind_and_deliberate_error_executes() {
    check("directed");
}

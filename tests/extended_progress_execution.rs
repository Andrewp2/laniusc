mod common;
use std::path::PathBuf;

use laniusc_compiler::compiler::{EntrySourceRoots, compile_entry_to_x86_64_with_source_roots};
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn executable(name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(if name == "csv_table" {
        "sample_programs/library/csv_table.lani".to_owned()
    } else {
        format!("tests/fixtures/extended/{name}.lani")
    });
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_terminal", name, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn progress_is_atomic_bounded_allocation_free_and_matches_u128_fraction_model() {
    let mut cases = Vec::new();
    for width in [0u32, 1, 2, 7, 20, 4096] {
        for (current, total) in [
            (0, None),
            (42, None),
            (0, Some(0)),
            (7, Some(0)),
            (0, Some(100)),
            (1, Some(3)),
            (2, Some(3)),
            (100, Some(100)),
            (101, Some(100)),
            (u64::MAX - 1, Some(u64::MAX)),
            (u64::MAX, Some(u64::MAX)),
            (u64::MAX, Some(1)),
        ] {
            cases.push((current, total, width));
        }
    }
    let mut seed = 0x5a6b_c7d8_192a_u64;
    for index in 0..256 {
        seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
        let total = seed;
        seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
        cases.push((seed, Some(total), (index % 65) as u32));
    }
    let mut payload = Vec::new();
    let mut expected = String::new();
    for &(current, total, width) in &cases {
        payload.extend(current.to_le_bytes());
        payload.extend(total.unwrap_or(0).to_le_bytes());
        payload.extend(width.to_le_bytes());
        payload.extend(u32::from(total.is_some()).to_le_bytes());
        let bar = if let Some(total) = total {
            let filled = if total == 0 {
                width as usize
            } else {
                ((current.min(total) as u128 * width as u128) / total as u128) as usize
            };
            format!(
                "{}{}",
                "#".repeat(filled),
                "-".repeat(width as usize - filled)
            )
        } else {
            "?".repeat(width as usize)
        };
        expected.push_str(&format!(
            "[{bar}] {current}/{}{}\n",
            total
                .map(|x| x.to_string())
                .unwrap_or_else(|| "?".to_owned()),
            if total.is_some_and(|total| current > total) {
                " !"
            } else {
                ""
            }
        ));
    }
    let input = common::TempArtifact::new("laniusc_progress", "cases", None);
    input.write_bytes(&payload);
    let trace = common::TempArtifact::new("laniusc_progress", "noalloc", None);
    let exe = executable("progress_input");
    let output = common::short_process_output_with_timeout(
        "progress fraction model",
        std::process::Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path())
            .stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            )),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(output.stdout, expected.as_bytes());
    assert!(output.stderr.is_empty());
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    let contracts = executable("progress_contracts");
    let output = common::short_process_output_with_timeout(
        "progress buffer bounds",
        &mut std::process::Command::new(contracts.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}

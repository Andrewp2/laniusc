#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};

fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/extended_library/{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_unicode_case", name, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn native_strides_bounds_utf8_atomicity_and_no_allocation() {
    let exe = executable("unicode_case_contracts");
    let trace = common::TempArtifact::new("laniusc_unicode_case", "trace", None);
    let output = common::short_process_output_with_timeout(
        "case contracts with allocation failure",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    let generated = common::short_process_output_with_timeout(
        "case tables regenerate exactly",
        Command::new("python3")
            .args(["tools/unicode17/generate_case.py", "--check"])
            .current_dir(env!("CARGO_MANIFEST_DIR")),
    );
    assert!(generated.status.success(), "{generated:?}");
}

fn reference(mode: &str) {
    let exe = executable("unicode_case_model");
    let vectors = common::process_output_with_timeout(
        "independent Unicode17 casing reference",
        Command::new("python3")
            .args([
                "tests/fixtures/extended_library/unicode_case_reference.py",
                mode,
            ])
            .current_dir(env!("CARGO_MANIFEST_DIR")),
        Duration::from_secs(90),
    );
    assert!(
        vectors.status.success(),
        "{mode}: status {:?}; stderr {}",
        vectors.status,
        String::from_utf8_lossy(&vectors.stderr)
    );
    assert!(vectors.stderr.is_empty());
    let mut input = Vec::new();
    let mut cases = Vec::new();
    let mut position = 0;
    while position < vectors.stdout.len() {
        let header = &vectors.stdout[position..position + 36];
        let word = |at| u32::from_le_bytes(header[at..at + 4].try_into().unwrap());
        let wide = |at| u64::from_le_bytes(header[at..at + 8].try_into().unwrap());
        let length = word(4) as usize;
        let capacity = word(8) as usize;
        let limit = wide(12);
        let code = word(20);
        let detail = wide(24);
        let expected_length = word(32) as usize;
        assert!(length <= 65536 && capacity <= 65536);
        input.extend_from_slice(&header[..20]);
        position += 36;
        input.extend_from_slice(&vectors.stdout[position..position + length]);
        let source = vectors.stdout[position..position + length].to_vec();
        position += length;
        let expected = vectors.stdout[position..position + expected_length].to_vec();
        position += expected_length;
        cases.push((header[0], header[1], source, expected, code, detail, limit));
    }
    assert!(cases.len() > 2000, "{mode}: empty reference?");
    let request = common::TempArtifact::new("laniusc_unicode_case", "request", None);
    request.write_bytes(&input);
    let output = common::process_output_with_timeout(
        "native full string Unicode casing batch",
        Command::new(exe.path()).stdin(std::fs::File::open(request.path()).unwrap()),
        Duration::from_secs(90),
    );
    assert_eq!(
        output.status.code(),
        Some(0),
        "{mode}: status {:?}; stderr {}",
        output.status,
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(output.stderr.is_empty());
    let mut position = 0;
    for (index, (kind, locale, source, expected, code, detail, limit)) in cases.iter().enumerate() {
        let header = output.stdout.get(position..position + 28).unwrap_or_else(|| {
            panic!("{mode} case {index} kind {kind} locale {locale} source {source:?}: missing response")
        });
        let word = |at| u32::from_le_bytes(header[at..at + 4].try_into().unwrap());
        let wide = |at| u64::from_le_bytes(header[at..at + 8].try_into().unwrap());
        let actual_code = word(0);
        let actual_detail = wide(4);
        let bytes = word(12) as usize;
        let scalars = word(16) as usize;
        let work = wide(20);
        position += 28;
        let actual = &output.stdout[position..position + bytes];
        let label = || format!("{mode} case {index} kind {kind} locale {locale} source {source:?}");
        assert_eq!(actual_code, *code, "{}", label());
        if *detail == u64::MAX {
            assert!(actual_detail <= *limit, "{}", label());
        } else {
            assert_eq!(actual_detail, *detail, "{}", label());
        }
        assert_eq!(actual, expected, "{}", label());
        assert_eq!(
            scalars,
            std::str::from_utf8(expected).unwrap().chars().count(),
            "{}",
            label()
        );
        assert!(work <= *limit, "{}", label());
        if *code == 0 {
            assert!(
                work <= 16 * (source.len() + expected.len() + 1) as u64,
                "nonlinear work: {}",
                label()
            );
        }
        position += bytes;
    }
    assert_eq!(position, output.stdout.len());
}

#[test]
fn every_unicode17_scalar_full_lower_upper_title_default_and_turkic_fold() {
    reference("scalars");
}

#[test]
fn special_casing_original_contexts_official_word_boundaries_and_work_limits() {
    reference("contexts");
}

#[test]
fn python_root_casing_differential_on_its_assigned_repertoire() {
    reference("python");
}

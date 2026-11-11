//! Borrowed literal partitions, directional Unicode reference and stride-safe search.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;

use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_text_partitions")
        .join(name)
}

fn compile(name: &str, native: bool) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = fixture(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    common::run_gpu_codegen_with_timeout(name, move || {
        if native {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                    &entry,
                    &roots,
                    &Default::default(),
                ),
            )
        } else {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        }
    })
}

fn execute(name: &str, native: bool, oracle: &str) -> String {
    let bytes = compile(name, native).unwrap_or_else(|error| panic!("{name}: {error}"));
    let executable = common::TempArtifact::new("laniusc_text_partitions", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "text partition executable reference",
        Command::new("python3")
            .args(["-I", "-B"])
            .arg(fixture(oracle))
            .arg(executable.path()),
        Duration::from_secs(45),
    );
    common::assert_command_success(name, &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    String::from_utf8(output.stdout).unwrap()
}

#[test]
fn text_partitions_and_strided_search_execute_without_source_allocation() {
    assert_eq!(
        execute("contracts.lani", true, "noalloc.py"),
        "text-partition-contracts layouts=2 source_allocations=0 source_releases=0\n"
    );
}

#[test]
fn text_partitions_match_independent_unicode_model() {
    let summary = execute("model.lani", false, "oracle.py");
    assert_eq!(
        summary,
        "text-partition-model cases=873 pulls=57204 items=28934 copies=13968 matches=1820 layouts=4 seed=0x7e871a0261117\n"
    );
    eprint!("{summary}");
}

fn rejects_capability(name: &str) {
    let error =
        compile(name, false).expect_err("directional partitions require only forward iteration");
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0008", "{name}: {error}");
    let label = diagnostic
        .primary_label
        .expect("source-local capability requirement");
    assert!(label.path.ends_with(name), "{name}: {label:?}");
    assert!(
        label
            .source_line
            .as_deref()
            .unwrap_or("")
            .contains("rejected_partition_capability"),
        "{name}: {label:?}"
    );
}

macro_rules! negative {
    ($name:ident, $file:literal) => {
        #[test]
        fn $name() {
            rejects_capability($file);
        }
    };
}
negative!(
    rsplit_does_not_claim_double_ended,
    "negative_rsplit_reverse.lani"
);
negative!(
    rsplit_does_not_claim_exact_size,
    "negative_rsplit_exact.lani"
);
negative!(
    splitn_does_not_claim_double_ended,
    "negative_splitn_reverse.lani"
);
negative!(
    splitn_does_not_claim_exact_size,
    "negative_splitn_exact.lani"
);
negative!(
    rsplitn_does_not_claim_double_ended,
    "negative_rsplitn_reverse.lani"
);
negative!(
    rsplitn_does_not_claim_exact_size,
    "negative_rsplitn_exact.lani"
);
negative!(
    rmatch_does_not_claim_double_ended,
    "negative_rmatch_reverse.lani"
);
negative!(
    rmatch_does_not_claim_exact_size,
    "negative_rmatch_exact.lani"
);

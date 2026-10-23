mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile calendar collection fixture")
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let exe = common::TempArtifact::new("laniusc_calendar_keys", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn calendar_comparison_hash_laws_and_collection_contracts_execute() {
    for name in ["calendar_keys_laws", "calendar_keys_collections"] {
        let bytes = compile_fixture(name);
        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            let exe = executable(&bytes, name);
            let output = common::process_output_with_timeout(
                name,
                &mut std::process::Command::new(exe.path()),
                std::time::Duration::from_secs(10),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert!(
                output.stdout.is_empty() && output.stderr.is_empty(),
                "{output:?}"
            );
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
type Civil = (i32, i32, i32, i32, i32, i32, u32);

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn arguments(value: Civil) -> Vec<String> {
    [
        value.0 as i64,
        value.1 as i64,
        value.2 as i64,
        value.3 as i64,
        value.4 as i64,
        value.5 as i64,
        value.6 as i64,
    ]
    .map(|n| n.to_string())
    .to_vec()
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn next(state: &mut u64) -> u32 {
    *state = state.wrapping_mul(6364136223846793005).wrapping_add(1);
    (*state >> 32) as u32
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn civil(state: &mut u64) -> Civil {
    (
        next(state) as i32,
        (next(state) % 12 + 1) as i32,
        (next(state) % 28 + 1) as i32,
        (next(state) % 24) as i32,
        (next(state) % 60) as i32,
        (next(state) % 61) as i32,
        next(state) % 1_000_000_000,
    )
}

#[test]
fn calendar_order_matches_tuple_model_across_native_years() {
    let bytes = compile_fixture("calendar_keys_model");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let exe = executable(&bytes, "calendar_keys_model");
        let edges: [Civil; 12] = [
            (i32::MIN, 1, 1, 0, 0, 0, 0),
            (-400, 2, 29, 23, 59, 60, 999_999_999),
            (-1, 12, 31, 23, 59, 60, 0),
            (0, 1, 1, 0, 0, 0, 0),
            (0, 1, 1, 0, 0, 0, 1),
            (0, 1, 1, 0, 0, 59, 999_999_999),
            (0, 1, 1, 0, 0, 60, 0),
            (0, 1, 1, 0, 0, 60, 999_999_999),
            (0, 1, 1, 0, 1, 0, 0),
            (2000, 2, 29, 0, 0, 0, 0),
            (i32::MAX, 12, 31, 23, 59, 59, 999_999_999),
            (i32::MAX, 12, 31, 23, 59, 60, 999_999_999),
        ];
        let mut cases: Vec<_> = edges
            .iter()
            .flat_map(|a| edges.iter().map(move |b| (*a, *b)))
            .collect();
        let mut state = 0xca1e_0ade_2026_1023;
        for index in 0..512 {
            let a = civil(&mut state);
            let mut b = civil(&mut state);
            if index % 4 == 0 {
                b.0 = a.0;
                b.1 = a.1;
                b.2 = a.2;
            }
            if index % 8 == 0 {
                b = a;
            }
            cases.push((a, b));
        }
        for (a, b) in cases {
            let date_a = (a.0, a.1, a.2);
            let date_b = (b.0, b.1, b.2);
            let time_a = (a.3, a.4, a.5, a.6);
            let time_b = (b.3, b.4, b.5, b.6);
            let expected = [
                date_a.cmp(&date_b) as i32,
                time_a.cmp(&time_b) as i32,
                a.cmp(&b) as i32,
                i32::from(date_a == date_b),
                i32::from(time_a == time_b),
                i32::from(a == b),
            ];
            let mut args = arguments(a);
            args.extend(arguments(b));
            let output = common::short_process_output_with_timeout(
                "calendar tuple comparison",
                std::process::Command::new(exe.path()).args(&args),
            );
            assert_eq!(output.status.code(), Some(0), "{args:?}: {output:?}");
            assert!(output.stderr.is_empty(), "{args:?}: {output:?}");
            let actual: Vec<i32> = String::from_utf8(output.stdout)
                .unwrap()
                .lines()
                .map(|n| n.parse().unwrap())
                .collect();
            assert_eq!(actual, expected, "{args:?}");
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

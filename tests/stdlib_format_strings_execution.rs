#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};
fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_format_strings", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
#[test]
fn runtime_format_contracts_execute() {
    let exe = executable("format_strings_contracts");
    let output = common::process_output_with_timeout(
        "runtime format contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
#[test]
fn owned_format_and_user_display_execute() {
    let exe = executable("format_strings_owned");
    let output = common::process_output_with_timeout(
        "owned format",
        &mut Command::new(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
fn model() -> &'static common::TempArtifact {
    static EXE: std::sync::OnceLock<common::TempArtifact> = std::sync::OnceLock::new();
    EXE.get_or_init(|| executable("format_strings_model"))
}
fn lines(output: std::process::Output) -> Vec<String> {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    String::from_utf8(output.stdout)
        .unwrap()
        .split_terminator('\n')
        .map(str::to_owned)
        .collect()
}
fn invoke(mode: &str, pattern: &str, inputs: &[String]) -> Vec<String> {
    lines(common::process_output_with_timeout(
        "runtime format model",
        Command::new(model().path())
            .args([mode, pattern])
            .args(inputs),
        Duration::from_secs(15),
    ))
}
fn reference(mode: &str, pattern: &str, inputs: &[String]) -> Vec<String> {
    let script = r#"import sys,struct
mode,pattern=sys.argv[1:3]
for source in sys.argv[3:]:
 if mode in ('s','u'): value=int(source)
 elif mode=='d': value=struct.unpack('>d',int(source).to_bytes(8,'big'))[0]
 elif mode=='f': value=struct.unpack('>f',int(source).to_bytes(4,'big'))[0]
 elif mode=='b': value='true' if source=='1' else 'false'
 elif mode=='c': value=chr(int(source))
 else: value=source
 print(pattern.format(value,value=value))
"#;
    lines(common::process_output_with_timeout(
        "Python format reference",
        Command::new("python3")
            .args(["-c", script, mode, pattern])
            .args(inputs),
        Duration::from_secs(10),
    ))
}
fn compare(mode: &str, pattern: &str, inputs: &[String]) {
    assert_eq!(
        invoke(mode, pattern, inputs),
        reference(mode, pattern, inputs),
        "mode={mode}, pattern={pattern:?}, inputs={inputs:?}"
    );
}
fn next(seed: &mut u64) -> u64 {
    *seed ^= *seed << 13;
    *seed ^= *seed >> 7;
    *seed ^= *seed << 17;
    *seed
}
#[test]
fn native_integer_text_scalar_and_repeated_named_fields_match_python() {
    let mut seed = 0x45b1_6af8_2026_1023;
    let mut signed = vec![
        i64::MIN.to_string(),
        i64::MAX.to_string(),
        "0".into(),
        "1".into(),
        "-1".into(),
    ];
    let mut unsigned = vec![u64::MAX.to_string(), "0".into(), "1".into()];
    for _ in 0..64 {
        let value = next(&mut seed);
        signed.push((value as i64).to_string());
        unsigned.push(value.to_string());
    }
    for pattern in [
        "{0}",
        "{0:+08d}",
        "{0: 20d}",
        "{0:-d}",
        "{0:#018x}",
        "{0:#018X}",
        "{0:#070b}",
        "{0:#024o}",
        "{0:*>25d}",
        "{0:🙂^25d}",
        "{{{value}}}:{0}:{value}",
    ] {
        compare("s", pattern, &signed);
        compare("u", pattern, &unsigned);
    }
    let text = vec![
        "".into(),
        "A".into(),
        "é🙂ab".into(),
        "e\u{301}é漢🙂".into(),
        "αβγδεζηθικλμνξοπρστυφχψω".into(),
    ];
    for pattern in [
        "{0}",
        "{value:>12s}",
        "{0:🙂^12.3s}",
        "{0:🌍<8.0s}",
        "{0:.2147483647s}",
        "{value:.3s}:{0:.1s}",
    ] {
        compare("t", pattern, &text);
    }
    compare("b", "{0:🙂^9.4s}", &["1".into(), "0".into()]);
    compare(
        "c",
        "{0:🙂^5s}",
        &[
            "0".into(),
            "65".into(),
            "233".into(),
            "128578".into(),
            "1114111".into(),
        ],
    );
    // A real render beyond the old small scratch size preserves all bytes.
    assert_eq!(
        invoke("t", "{0:5000s}", &["é".into()])[0],
        format!("é{}", " ".repeat(4999))
    );
}
#[test]
fn native_exact_float_precision_signs_padding_and_nonfinite_match_python() {
    let mut seed = 0x9af4_7012_beef_1023;
    let mut wide = vec![
        0_u64,
        1,
        0x8000_0000_0000_0000,
        0x3ff0_0000_0000_0000,
        0x4005_6666_6666_6666,
        0x3fc3_3333_3333_3333,
        0x7fef_ffff_ffff_ffff,
        0x7ff0_0000_0000_0000,
        0xfff0_0000_0000_0000,
        0x7ff8_0000_0000_0001,
    ];
    let mut narrow = vec![
        0_u32,
        1,
        0x8000_0000,
        0x3f80_0000,
        0x7f7f_ffff,
        0x7f80_0000,
        0xff80_0000,
        0x7fc0_0001,
    ];
    for _ in 0..64 {
        let bits = next(&mut seed);
        if !f64::from_bits(bits).is_nan() {
            wide.push(bits);
        }
        let bits = next(&mut seed) as u32;
        if !f32::from_bits(bits).is_nan() {
            narrow.push(bits);
        }
    }
    let wide: Vec<_> = wide.into_iter().map(|v| v.to_string()).collect();
    let narrow: Vec<_> = narrow.into_iter().map(|v| v.to_string()).collect();
    for pattern in [
        "{0:.0f}",
        "{0:+014.2f}",
        "{0: .6e}",
        "{0:#.0E}",
        "{0:.0g}",
        "{0:.1g}",
        "{0:#.8g}",
        "{0:🙂^20.5G}",
        "{value:.17g}:{0:.3f}",
    ] {
        compare("d", pattern, &wide);
        compare("f", pattern, &narrow);
    }
    let boundaries = vec!["1".into(), "9218868437227405311".into()];
    for pattern in ["{0:.768f}", "{0:#.768e}", "{0:#.768g}"] {
        compare("d", pattern, &boundaries);
    }
}
#[test]
fn core_formatting_runs_without_allocating() {
    let exe = executable("format_strings_contracts");
    let trace = common::TempArtifact::new("laniusc_format_strings", "core_trace", None);
    let output = common::process_output_with_timeout(
        "allocation free format",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap,brk,open,openat,socket,connect",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}
#[test]
fn owned_allocation_failures_free_intermediates_and_empty_or_invalid_formats_allocate_nothing() {
    let exe = executable("format_strings_alloc_failure");
    for (mode, when) in [("b", 1), ("s", 1), ("s", 2)] {
        let normal = common::process_output_with_timeout(
            "normal owned format",
            Command::new(exe.path()).arg(mode),
            Duration::from_secs(10),
        );
        assert_eq!(normal.status.code(), Some(1), "{mode}: {normal:?}");
        let trace = common::TempArtifact::new("laniusc_format_strings", "allocation_trace", None);
        let output = common::process_output_with_timeout(
            "failed owned format",
            Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap", "-e"])
                .arg(format!("inject=mmap:error=ENOMEM:when={when}"))
                .arg(exe.path())
                .arg(mode),
            Duration::from_secs(10),
        );
        assert_eq!(
            output.status.code(),
            Some(0),
            "{mode}, when {when}: {output:?}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(
            events.contains("INJECTED") && events.contains("ENOMEM"),
            "{events}"
        );
        let mappings = events
            .lines()
            .filter(|line| line.starts_with("mmap(") && !line.contains("ENOMEM"))
            .count();
        let frees = events
            .lines()
            .filter(|line| line.starts_with("munmap("))
            .count();
        assert_eq!(mappings, frees, "{mode}, when {when}: {events}");
    }
    for mode in ["e", "x"] {
        let trace = common::TempArtifact::new("laniusc_format_strings", "empty_trace", None);
        let output = common::process_output_with_timeout(
            "empty or invalid owned format",
            Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args([
                    "-e",
                    "trace=mmap,munmap,brk",
                    "-e",
                    "inject=mmap:error=ENOMEM:when=1+",
                ])
                .arg(exe.path())
                .arg(mode),
            Duration::from_secs(10),
        );
        assert_eq!(output.status.code(), Some(0), "{mode}: {output:?}");
        assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    }
}

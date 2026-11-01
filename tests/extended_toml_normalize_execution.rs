#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::{ffi::OsStrExt, fs::PermissionsExt},
    process::{Command, Output, Stdio},
    time::{Duration, Instant},
    sync::OnceLock,
};
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/toml_normalize.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("toml-normalize", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("toml-normalize: {e}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes), "TOML normalizer must produce an actual ELF64 x86-64 executable");
    let exe = common::TempArtifact::new("laniusc_toml_normalize", "executable", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
    })
}
fn run(c: &mut Command) -> Output {
    common::process_output_with_timeout("toml-normalize", c, Duration::from_secs(15))
}
fn file(bytes: &[u8]) -> common::TempArtifact {
    let data = common::TempArtifact::new("laniusc_toml_normalize", "data", None);
    data.write_bytes(bytes);
    data
}
fn invoke(exe: &common::TempArtifact, args: &[&str], bytes: &[u8]) -> Output {
    let input = file(bytes);
    run(Command::new(exe.path())
        .args(args)
        .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())))
}
fn success(o: &Output) {
    assert_eq!(
        o.status.code(),
        Some(0),
        "status={} stderr={:?}",
        o.status,
        String::from_utf8_lossy(&o.stderr)
    );
    assert!(o.stderr.is_empty(), "{:?}", o.stderr);
}
fn failure(o: &Output, status: i32, reason: &str) {
    assert_eq!(
        o.status.code(),
        Some(status),
        "status={} stderr={:?}",
        o.status,
        String::from_utf8_lossy(&o.stderr)
    );
    assert!(o.stdout.is_empty(), "stdout bytes={}", o.stdout.len());
    let d = std::str::from_utf8(&o.stderr).unwrap();
    assert!(
        d.starts_with("toml-normalize: ") && d.ends_with('\n') && d.contains(reason),
        "{d}"
    );
}
fn semantic_same(a: &[u8], b: &[u8]) {
    let a = file(a);
    let b = file(b);
    // Python is an independent TOML 1.0 oracle over the shared syntax. Production
    // is TOML1.1 and never calls a host parser. Type tags and float.hex retain
    // integer/float distinction and negative zero; only NaN payloads are ignored.
    let script = r#"import datetime,math,sys,tomllib
def typed(x):
 if isinstance(x,dict): return ('table',sorted((k,typed(v)) for k,v in x.items()))
 if isinstance(x,list): return ('array',[typed(v) for v in x])
 if isinstance(x,float): return ('float','nan' if math.isnan(x) else x.hex())
 return (type(x).__name__,x)
a=tomllib.loads(open(sys.argv[1],'rb').read().decode());b=tomllib.loads(open(sys.argv[2],'rb').read().decode())
assert typed(a)==typed(b),(typed(a),typed(b))
"#;
    let result = run(Command::new("python3")
        .args(["-c", script])
        .arg(a.path())
        .arg(b.path()));
    assert!(
        result.status.success() && result.stderr.is_empty(),
        "oracle: {}",
        String::from_utf8_lossy(&result.stderr)
    );
}
const CONFIG: &str = r###"# application configuration
title = "TOML Example 🙂"
enabled = true
min = -9223372036854775808
max = 9223372036854775807
hex = 0xDEAD_BEEF
neg = -0.0
infinity = +inf
nan = -nan
when = 1979-05-27T07:32:00.123456Z
local = 1979-05-27 07:32:00
time = 07:32:00.123
date = 2000-02-29
message = """
embedded\
   whitespace and \"quotes\"
"""
"" = '\literal'
[server]
host = "localhost"
port = 8080
tags = ["one", "two",]
[[workers]]
name = "one"
settings = { active = true, values = [1, "two", false] }
[[workers]]
name = "two"
"###;

#[test]
fn toml_normalize_executes_real_configs_11_syntax_types_and_idempotence() {
    let exe = executable();
    let output = invoke(&exe, &[], CONFIG.as_bytes());
    success(&output);
    semantic_same(CONFIG.as_bytes(), &output.stdout);
    let again = invoke(&exe, &[], &output.stdout);
    success(&again);
    assert_eq!(again.stdout, output.stdout);
    for input in [
        b"".as_slice(),
        b"# only comment\r\n",
        b"x = 1",
        "\"\"=\"🙂\"\n".as_bytes(),
    ] {
        let out = invoke(&exe, &[], input);
        success(&out);
        semantic_same(input, &out.stdout);
    }
    let new_syntax=b"s=\"\x5ce\x5cxE9\"\nt=12:34\nz=1979-05-27t07:32-00:00\nobject={\n# multiline inline table\na=1,\n}\n";
    let out = invoke(&exe, &[], new_syntax);
    success(&out);
    let encoded = std::str::from_utf8(&out.stdout).unwrap();
    assert!(
        encoded.contains("12:34:00")
            && encoded.contains("1979-05-27T07:32:00-00:00")
            && encoded.contains('é'),
        "{encoded}"
    );
    let again = invoke(&exe, &[], &out.stdout);
    success(&again);
    assert_eq!(again.stdout, out.stdout);
    let checked = invoke(&exe, &["--check", "--max-output-bytes=0"], new_syntax);
    success(&checked);
    assert!(checked.stdout.is_empty());
    let exact = invoke(
        &exe,
        &[
            "--max-input-bytes=3",
            "--max-output-bytes=6",
            "--max-nodes=2",
            "--max-depth=1",
        ],
        b"x=1",
    );
    success(&exact);
    semantic_same(b"x=1", &exact.stdout);
    let full_work = invoke(&exe, &["--max-work=18446744073709551615"], b"ratio=1.25");
    success(&full_work);
    semantic_same(b"ratio=1.25", &full_work.stdout);
}

#[test]
fn toml_normalize_reports_malformed_input_and_resource_failures_before_output() {
    let exe = executable();
    failure(
        &invoke(&exe, &[], b"x=\""),
        2,
        "stage=parse kind=unexpected end byte=3",
    );
    for (input, reason) in [
        (b"x=1\nx=2\n".as_slice(), "duplicate key"),
        (b"x=\"unterminated", "unexpected end"),
        (b"[a]\n[a]\n", "table redefinition"),
        (b"x=9223372036854775808", "number out of range"),
        (b"x=2000-02-30", "invalid date/time"),
        (b"x=1__2", "invalid number"),
        (b"x=\"\x5cq\"", "invalid escape"),
    ] {
        failure(&invoke(&exe, &[], input), 2, reason);
    }
    for (args, input, reason) in [
        (
            vec!["--max-input-bytes=2"],
            b"x=1".as_slice(),
            "resource-limit",
        ),
        (vec!["--max-output-bytes=5"], b"x=1", "output limit"),
        (vec!["--max-nodes=1"], b"x=1", "node limit"),
        (vec!["--max-depth=0"], b"x=1", "depth limit"),
        (vec!["--max-string-bytes=0"], b"x=1", "string limit"),
        (vec!["--max-number-bytes=1"], b"x=12", "number limit"),
        (vec!["--max-work=0"], b"x=1", "work limit"),
    ] {
        failure(&invoke(&exe, &args, input), 2, reason);
    }
    for bad in [
        b"a\xff".as_slice(),
        b"a\xc0\x80",
        b"a\xed\xa0\x80",
        b"a\xf0\x9f",
    ] {
        failure(
            &invoke(&exe, &[], bad),
            2,
            "invalid-utf8 stage=input byte=1",
        );
    }
    let mut bad = vec![b' '; 1023];
    bad.extend_from_slice(b"\xf0\x9f");
    failure(
        &invoke(&exe, &[], &bad),
        2,
        "invalid-utf8 stage=input byte=1023",
    );
    for args in [
        vec!["--bad"],
        vec!["file.toml"],
        vec!["--check=yes"],
        vec!["--max-depth=4097"],
        vec!["--max-nodes=1000001"],
        vec!["--max-input-bytes=-1"],
        vec!["--max-work=+1"],
        vec!["--max-work=18446744073709551616"],
        vec!["--max-number-bytes=67108865"],
        vec!["--max-work"],
    ] {
        failure(&invoke(&exe, &args, b""), 2, "invalid-arguments");
    }
    failure(
        &invoke(&exe, &vec!["--check"; 33], b""),
        2,
        "invalid-arguments",
    );
    failure(
        &invoke(&exe, &[&"x".repeat(8193)], b""),
        2,
        "invalid-arguments",
    );
    failure(
        &run(Command::new(exe.path()).arg(std::ffi::OsStr::from_bytes(b"--max-work=\xff"))),
        2,
        "invalid-arguments",
    );
    let help = invoke(&exe, &["--help"], b"\xff");
    success(&help);
    assert!(help.stdout.starts_with(b"Usage: toml-normalize ") && help.stdout.ends_with(b"\n"));
}

#[test]
fn toml_normalize_scales_to_real_nested_configs_and_matches_python_oracle() {
    let exe = executable();
    let mut source = String::from("title='workers'\nenabled=true\n");
    for index in 0..1200 {
        source.push_str(&format!("[[workers]]\nid={index}\nname='worker {index} 🙂'\noptions={{port={},flags=[true,false,{}]}}\n",1024+index,index%17));
    }
    let start = Instant::now();
    let out = invoke(&exe, &[], source.as_bytes());
    let elapsed = start.elapsed();
    success(&out);
    semantic_same(source.as_bytes(), &out.stdout);
    let again = invoke(&exe, &[], &out.stdout);
    success(&again);
    assert_eq!(again.stdout, out.stdout);
    eprintln!(
        "toml-normalize: {} input bytes / {} output bytes, {:.3}ms native process/file setup and I/O, compilation excluded",
        source.len(),
        out.stdout.len(),
        elapsed.as_secs_f64() * 1000.0
    );
    // The parser conservatively reserves two million units per finite float.
    // A caller can deliberately raise the default budget for numerical files.
    let floats = (0..512).map(|i| format!("x{i}=1.25\n")).collect::<String>();
    failure(&invoke(&exe, &[], floats.as_bytes()), 2, "work limit");
    let raised = invoke(
        &exe,
        &["--max-work=18446744073709551615"],
        floats.as_bytes(),
    );
    success(&raised);
    semantic_same(floats.as_bytes(), &raised.stdout);
}

// Focused streaming consumer evidence replaces the old address-only fault
// helper and its fabricated positive write return. Existing semantic/parser
// selectors above remain available; the migration selects only relevant ones.
fn streaming_oracle(group: &str, expected: Option<usize>) {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        format!("TOML streaming normalizer {group}"),
        Command::new("python3").arg("-B")
            .arg(root.join("tests/fixtures/extended_toml_normalize_streaming/oracle.py"))
            .arg(group).arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("TOML streaming normalizer {group}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    let prefix = match expected {
        Some(n) => format!("toml-normalize-streaming-{group} cases={n} reached_allocations="),
        None => format!("toml-normalize-streaming-{group} cases="),
    };
    assert!(summary.starts_with(&prefix), "{summary}");
    eprint!("{summary}");
}
#[test]
fn toml_normalize_streaming_preserves_exact_wires_without_output_storage() { streaming_oracle("model", Some(14)); }
#[test]
fn toml_normalize_streaming_preflights_limits_and_actual_input_probes() { streaming_oracle("limits", Some(8)); }
#[test]
fn toml_normalize_cleans_up_all_observed_allocation_and_host_io_failures() { streaming_oracle("io", None); }
#[test]
fn toml_normalize_streaming_bounds_attempts_and_reports_confirmed_prefix() { streaming_oracle("budgets", Some(2)); }

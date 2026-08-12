use std::{
    env,
    ffi::OsString,
    io::Read,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};

const DEFAULT_GENERATED_LINES: &str = "5000";
const DEFAULT_CAPACITY_STRESS_SOURCE: &str = "expr-dense";
const DEFAULT_MAX_CAPACITY_STRESS_COMPILE_FLOOR_BYTES: u64 = 12 * 1024 * 1024 * 1024;
const DEFAULT_COMMAND_TIMEOUT_MS: u64 = 120_000;
const MAX_LINES_WITHOUT_OPT_IN: usize = 20_000;
const ALLOW_LARGE_GENERATED_TESTS_ENV: &str = "LANIUS_ALLOW_LARGE_GENERATED_TESTS";

#[test]
#[ignore = "parameterized generated compiler gate; run explicitly after frontend changes"]
fn generated_frontend_suite_passes_supported_phases() {
    let bin = gpu_compile_bench_bin();
    let lines = generated_lines();
    for phase in ["lex", "parse", "typecheck"] {
        run_success(
            &bin,
            &[
                "--phase",
                phase,
                "--source",
                "all",
                "--lines",
                &lines,
                "--warmups",
                "0",
                "--iters",
                "1",
                "--allow-large",
            ],
        );
    }
}

#[test]
#[ignore = "generated capacity gate; estimate-only submits no GPU work"]
fn generated_capacity_stress_x86_has_consistent_bounded_estimate() {
    let bin = gpu_compile_bench_bin();
    let source = env::var("LANIUS_CAPACITY_STRESS_SOURCE")
        .unwrap_or_else(|_| DEFAULT_CAPACITY_STRESS_SOURCE.to_owned());
    let lines = generated_lines_from("LANIUS_CAPACITY_STRESS_LINES");
    let output = run_success(
        &bin,
        &[
            "--phase",
            "x86",
            "--emit",
            "x86_64-elf",
            "--source",
            &source,
            "--lines",
            &lines,
            "--estimate-only",
        ],
    );

    assert_eq!(output.matches("no GPU work was submitted").count(), 1);
    assert!(output.contains("estimate compile_allocation_floor parser_plus_typecheck_plus_x86="));
    assert!(output.contains("estimate x86_dynamic_caps"));
    assert!(output.contains("token_capacity_basis=test_cpu_token_count"));
    assert_x86_capacity_estimate_is_internally_consistent(&output);

    let compile_floors = parse_u64_values(&output, "compile_floor_bytes");
    assert_eq!(compile_floors.len(), 1);
    let compile_floor = compile_floors[0];
    let guardrail = env::var("LANIUS_MAX_CAPACITY_STRESS_COMPILE_FLOOR_BYTES")
        .map(|value| parse_u64_env("LANIUS_MAX_CAPACITY_STRESS_COMPILE_FLOOR_BYTES", &value))
        .unwrap_or(DEFAULT_MAX_CAPACITY_STRESS_COMPILE_FLOOR_BYTES);
    assert!(
        compile_floor <= guardrail,
        "x86 compile allocation floor {compile_floor} for source={source} lines={lines} exceeds guardrail {guardrail}"
    );
}

#[test]
#[ignore = "parameterized generated compiler gate; run explicitly after resident frontend changes"]
fn generated_reused_parse_matches_independent_parse() {
    let bin = gpu_compile_bench_bin();
    let lines = generated_lines();
    let suite = run_success(
        &bin,
        &[
            "--phase",
            "parse",
            "--source",
            "all",
            "--lines",
            &lines,
            "--warmups",
            "0",
            "--iters",
            "1",
            "--allow-large",
        ],
    );
    let independent = run_success(
        &bin,
        &[
            "--phase",
            "parse",
            "--source",
            "varied",
            "--lines",
            &lines,
            "--warmups",
            "0",
            "--iters",
            "1",
            "--allow-large",
        ],
    );

    assert_eq!(
        parse_metrics_for_source(&suite, "varied"),
        parse_metric_line(
            independent
                .lines()
                .find(|line| line.contains("phase=parse token_count="))
                .expect("independent parse output should include parse metrics"),
        ),
    );
}

#[test]
#[ignore = "parameterized generated compiler gate; run explicitly for x86 validation"]
fn generated_reused_x86_output_validates() {
    let bin = gpu_compile_bench_bin();
    let lines = generated_lines();
    run_success(
        &bin,
        &[
            "--phase",
            "x86",
            "--emit",
            "x86_64-elf",
            "--source",
            "simple-lets",
            "--lines",
            &lines,
            "--warmups",
            "1",
            "--iters",
            "1",
            "--allow-large",
            "--validate-output",
        ],
    );
}

fn assert_x86_capacity_estimate_is_internally_consistent(output: &str) {
    const MAX_X86_INSTS: u64 = 2_097_152;
    const X86_INST_CAPACITY_MIN: u64 = 256;
    const X86_INST_CAPACITY_SLACK: u64 = 1_024;
    const X86_INSTS_PER_HIR_NODE_CAPACITY: u64 = 8;

    let estimate_line = line_containing(output, "estimate lines=");
    let parser_line = line_containing(output, "estimate parser_path=");
    let x86_line = line_containing(output, "estimate x86_dynamic_caps");
    let token_capacity = required_u64(estimate_line, "lexer_token_capacity");
    let parser_tree_capacity = required_u64(parser_line, "parser_tree_capacity");
    let inst_basis_words = required_u64(x86_line, "inst_basis_words");
    let requested_inst_capacity = required_u64(x86_line, "requested_inst_capacity");
    let inst_capacity = required_u64(x86_line, "inst_capacity");

    assert_eq!(
        parse_field(x86_line, "hir_basis"),
        Some("parser_tree_capacity")
    );
    assert_eq!(required_u64(x86_line, "hir_words"), parser_tree_capacity);
    assert_eq!(inst_basis_words, parser_tree_capacity);

    let expected_requested = inst_basis_words
        .saturating_mul(X86_INSTS_PER_HIR_NODE_CAPACITY)
        .saturating_add(X86_INST_CAPACITY_SLACK);
    let token_scaled_limit = token_capacity
        .max(1)
        .saturating_add(X86_INST_CAPACITY_SLACK)
        .min(MAX_X86_INSTS);
    let inst_limit = token_scaled_limit.clamp(X86_INST_CAPACITY_MIN, MAX_X86_INSTS);
    let expected_inst = expected_requested.clamp(X86_INST_CAPACITY_MIN, inst_limit);
    assert_eq!(requested_inst_capacity, expected_requested);
    assert_eq!(inst_capacity, expected_inst);
    assert_eq!(
        parse_field(x86_line, "inst_capacity_capped"),
        Some(if expected_requested > expected_inst {
            "true"
        } else {
            "false"
        }),
    );
}

#[derive(Debug, Eq, PartialEq)]
struct ParseMetrics {
    token_count: u64,
    parser_tree_capacity: u64,
    parser_emit_len: u64,
    semantic_hir_count: u64,
}

fn parse_metric_line(line: &str) -> ParseMetrics {
    ParseMetrics {
        token_count: required_u64(line, "token_count"),
        parser_tree_capacity: required_u64(line, "parser_tree_capacity"),
        parser_emit_len: required_u64(line, "parser_emit_len"),
        semantic_hir_count: required_u64(line, "semantic_hir_count"),
    }
}

fn parse_metrics_for_source(output: &str, source: &str) -> ParseMetrics {
    let marker = format!("source={source}");
    let mut previous_metrics = None;
    for line in output.lines() {
        if line.contains("phase=parse token_count=") {
            previous_metrics = Some(parse_metric_line(line));
        } else if line.contains(&marker) {
            return previous_metrics.expect("parse metrics should precede the source marker");
        }
    }
    panic!("suite output should include {marker}");
}

fn run_success(bin: &Path, args: &[&str]) -> String {
    let mut command = Command::new(bin);
    command
        .env("LANIUS_X86_READBACK_TIMEOUT_MS", "60000")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let owned_args = args.iter().map(OsString::from).collect::<Vec<_>>();
    let timeout = command_timeout();
    let start = Instant::now();
    let mut child = command
        .args(&owned_args)
        .spawn()
        .unwrap_or_else(|err| panic!("run {}: {err}", bin.display()));
    let mut stdout = child.stdout.take().expect("capture command stdout");
    let mut stderr = child.stderr.take().expect("capture command stderr");
    let stdout_reader = thread::spawn(move || {
        let mut bytes = Vec::new();
        stdout.read_to_end(&mut bytes).expect("read command stdout");
        bytes
    });
    let stderr_reader = thread::spawn(move || {
        let mut bytes = Vec::new();
        stderr.read_to_end(&mut bytes).expect("read command stderr");
        bytes
    });

    let status = loop {
        if let Some(status) = child.try_wait().expect("poll generated command") {
            break status;
        }
        if start.elapsed() >= timeout {
            let _ = child.kill();
            let _ = child.wait();
            panic!(
                "{} {:?} timed out after {} ms",
                bin.display(),
                args,
                timeout.as_millis()
            );
        }
        thread::sleep(Duration::from_millis(10));
    };
    let stdout = stdout_reader
        .join()
        .expect("stdout reader should not panic");
    let stderr = stderr_reader
        .join()
        .expect("stderr reader should not panic");
    assert!(
        status.success(),
        "{} {:?} failed with status {:?}\nstdout:\n{}\nstderr:\n{}",
        bin.display(),
        args,
        status.code(),
        String::from_utf8_lossy(&stdout),
        String::from_utf8_lossy(&stderr),
    );
    String::from_utf8(stdout).expect("generated command stdout should be UTF-8")
}

fn generated_lines() -> String {
    generated_lines_from("LANIUS_GENERATED_LINES")
}

fn generated_lines_from(name: &str) -> String {
    let value = env::var(name).unwrap_or_else(|_| DEFAULT_GENERATED_LINES.to_owned());
    let count = value
        .parse::<usize>()
        .unwrap_or_else(|_| panic!("{name} must be an integer, got {value:?}"));
    assert!(count > 0, "{name} must be greater than zero");
    assert!(
        count <= MAX_LINES_WITHOUT_OPT_IN || env_truthy(ALLOW_LARGE_GENERATED_TESTS_ENV),
        "{name}={count} exceeds {MAX_LINES_WITHOUT_OPT_IN}; set {ALLOW_LARGE_GENERATED_TESTS_ENV}=1 to opt in",
    );
    count.to_string()
}

fn command_timeout() -> Duration {
    let millis = env::var("LANIUS_GENERATED_GATE_COMMAND_TIMEOUT_MS")
        .map(|value| parse_u64_env("LANIUS_GENERATED_GATE_COMMAND_TIMEOUT_MS", &value))
        .unwrap_or(DEFAULT_COMMAND_TIMEOUT_MS);
    assert!(millis > 0);
    Duration::from_millis(millis)
}

fn gpu_compile_bench_bin() -> PathBuf {
    option_env!("CARGO_BIN_EXE_gpu_compile_bench")
        .map(PathBuf::from)
        .filter(|path| path.exists())
        .or_else(|| {
            let path =
                PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/debug/gpu_compile_bench");
            path.exists().then_some(path)
        })
        .or_else(|| {
            let path =
                PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/release/gpu_compile_bench");
            path.exists().then_some(path)
        })
        .unwrap_or_else(|| PathBuf::from("target/debug/gpu_compile_bench"))
}

fn required_u64(text: &str, name: &str) -> u64 {
    parse_field(text, name)
        .unwrap_or_else(|| panic!("missing {name} in {text:?}"))
        .parse()
        .unwrap_or_else(|_| panic!("{name} should be an integer"))
}

fn parse_u64_values(text: &str, name: &str) -> Vec<u64> {
    text.lines()
        .filter_map(|line| parse_field(line, name)?.parse().ok())
        .collect()
}

fn line_containing<'a>(text: &'a str, marker: &str) -> &'a str {
    text.lines()
        .find(|line| line.contains(marker))
        .unwrap_or_else(|| panic!("output should include {marker:?}"))
}

fn parse_field<'a>(text: &'a str, name: &str) -> Option<&'a str> {
    let prefix = format!("{name}=");
    text.split_ascii_whitespace()
        .find_map(|word| word.strip_prefix(&prefix))
}

fn parse_u64_env(name: &str, value: &str) -> u64 {
    value
        .parse()
        .unwrap_or_else(|_| panic!("{name} must be an integer, got {value:?}"))
}

fn env_truthy(name: &str) -> bool {
    env::var(name).is_ok_and(|value| matches!(value.as_str(), "1" | "true" | "yes" | "on"))
}

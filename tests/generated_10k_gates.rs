use std::{
    env,
    ffi::{OsStr, OsString},
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

const DEFAULT_GENERATED_LINES: &str = "5000";
const DEFAULT_CAPACITY_STRESS_LINES: &str = "5000";
const DEFAULT_CAPACITY_STRESS_SOURCE: &str = "expr-dense";
const DEFAULT_MAX_CAPACITY_STRESS_COMPILE_FLOOR_BYTES: u64 = 12 * 1024 * 1024 * 1024;
const DEFAULT_GENERATED_GATE_COMMAND_TIMEOUT_MS: u64 = 120_000;
const MAX_GENERATED_LINES_WITHOUT_OPT_IN: usize = 20_000;
const MAX_CAPACITY_STRESS_LINES_WITHOUT_OPT_IN: usize = 20_000;
const MAX_PAREAS_COMPARE_ITERS_WITHOUT_OPT_IN: usize = 3;
const ALLOW_LARGE_GENERATED_TESTS_ENV: &str = "LANIUS_ALLOW_LARGE_GENERATED_TESTS";
const GENERATED_X86_READBACK_TIMEOUT_MS: &str = "60000";
const DEFAULT_PAREAS_COMPARE_ITERS: &str = "1";
const CHILD_PROCESS_POLL_INTERVAL_MS: u64 = 10;
const PAREAS_LIMIT_FACTOR: f64 = 1.5;

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
                lines.as_str(),
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
fn generated_capacity_stress_x86_has_capacity_estimate_without_gpu_work() {
    let bin = gpu_compile_bench_bin();
    let source = capacity_stress_source();
    let lines = capacity_stress_lines();
    let output = run_success(
        &bin,
        &[
            "--phase",
            "x86",
            "--emit",
            "x86_64-elf",
            "--source",
            source.as_str(),
            "--lines",
            lines.as_str(),
            "--estimate-only",
        ],
    );
    assert_eq!(
        output.matches("no GPU work was submitted").count(),
        1,
        "estimate-only should report no GPU submission for the stress source"
    );
    assert!(
        output.contains("estimate compile_allocation_floor parser_plus_typecheck_plus_x86="),
        "estimate output should include the full compile allocation floor"
    );
    assert!(
        output.contains("estimate x86_dynamic_caps"),
        "estimate output should include x86 capacity details"
    );
    assert!(
        output.contains("token_capacity_basis=test_cpu_token_count"),
        "estimate output should use the exact no-GPU token count for generated sources"
    );
    let compile_floors = parse_u64_values(&output, "compile_floor_bytes");
    assert_eq!(
        compile_floors.len(),
        1,
        "estimate output should include one raw compile floor for the stress source"
    );
    let max_compile_floor = compile_floors.into_iter().max().expect("compile floors");
    let guardrail = max_capacity_stress_compile_floor_bytes();
    eprintln!("max_capacity_stress_compile_floor_bytes={max_compile_floor}");
    assert!(
        max_compile_floor <= guardrail,
        "x86 compile allocation floor {max_compile_floor} for source={source} lines={lines} exceeds guardrail {guardrail}"
    );
}

#[test]
#[ignore = "parameterized generated compiler gate; run explicitly after resident frontend/backend changes"]
fn generated_reused_parse_matches_independent_varied() {
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
            lines.as_str(),
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
            lines.as_str(),
            "--warmups",
            "0",
            "--iters",
            "1",
            "--allow-large",
        ],
    );

    let suite_varied = parse_metrics_for_source(&suite, "varied");
    let independent_varied = parse_metric_line(
        independent
            .lines()
            .find(|line| line.contains("phase=parse token_count="))
            .expect("independent parse output should include parse metrics"),
    );
    assert_eq!(
        suite_varied, independent_varied,
        "reused compiler parse metrics for varied source diverged from an independent run"
    );
}

#[test]
#[ignore = "parameterized generated compiler gate; run explicitly for x86 backend validation"]
fn generated_reused_x86_suite_validates() {
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
            "all",
            "--lines",
            lines.as_str(),
            "--warmups",
            "1",
            "--iters",
            "1",
            "--allow-large",
            "--validate-output",
        ],
    );
}

#[test]
#[ignore = "requires a Pareas binary; set PAREAS_BIN or LANIUS_REQUIRE_PAREAS=1"]
fn generated_pareas_comparison_when_available() {
    let Some(pareas_bin) = pareas_bin() else {
        if env_truthy("LANIUS_REQUIRE_PAREAS") {
            panic!("Pareas comparison required, but no Pareas binary was found");
        }
        eprintln!("skipping Pareas comparison: set PAREAS_BIN or build ~/code/pareas");
        return;
    };

    let laniusc_bin = release_gpu_compile_bench_bin().unwrap_or_else(gpu_compile_bench_bin);
    let lines = generated_lines();
    let pareas_lines = parse_usize_env_value("LANIUS_GENERATED_LINES", lines.as_str());
    let laniusc_args = [
        "--phase",
        "x86",
        "--emit",
        "x86_64-elf",
        "--source",
        "call-graph",
        "--lines",
        lines.as_str(),
        "--warmups",
        "0",
        "--iters",
        "1",
        "--allow-large",
        "--validate-output",
    ];
    let mut laniusc_inner_best_ms = f64::INFINITY;
    let mut laniusc_wall_best_ms = f64::INFINITY;
    let compare_iters = pareas_compare_iters();
    for _ in 0..compare_iters {
        let run = run_success_timed(&laniusc_bin, &laniusc_args);
        laniusc_wall_best_ms = laniusc_wall_best_ms.min(duration_ms(run.elapsed));
        laniusc_inner_best_ms = laniusc_inner_best_ms
            .min(parse_ms_field(&run.stdout, "best_ms").expect("laniusc best_ms"));
    }

    let pareas_source = pareas_generated_source(pareas_lines);
    let pareas_cuda_path = pareas_runtime_cuda_path();
    let pareas_ld_library_path = pareas_runtime_ld_library_path();
    let source_path = unique_temp_path("pareas_generated", "par");
    let output_path = unique_temp_path("pareas_generated", "out");
    fs::write(&source_path, pareas_source).expect("write Pareas source");
    let mut pareas_wall_best_ms = f64::INFINITY;
    for _ in 0..compare_iters {
        let run = run_pareas_success_timed(
            &pareas_bin,
            &[
                source_path.as_os_str().to_owned(),
                "-o".into(),
                output_path.as_os_str().to_owned(),
            ],
            pareas_cuda_path.as_deref(),
            pareas_ld_library_path.as_deref(),
        );
        pareas_wall_best_ms = pareas_wall_best_ms.min(duration_ms(run.elapsed));
        let _ = fs::remove_file(&output_path);
    }
    let _ = fs::remove_file(&source_path);
    let _ = fs::remove_file(&output_path);

    eprintln!(
        "pareas_bin={} compare_iters={compare_iters} laniusc_wall_best_ms={laniusc_wall_best_ms:.3} laniusc_inner_best_ms={laniusc_inner_best_ms:.3} pareas_wall_best_ms={pareas_wall_best_ms:.3}",
        pareas_bin.display()
    );
    assert!(
        laniusc_wall_best_ms <= pareas_wall_best_ms * PAREAS_LIMIT_FACTOR,
        "laniusc wall best {laniusc_wall_best_ms:.3} exceeded {:.0}% of Pareas wall best {pareas_wall_best_ms:.3}",
        PAREAS_LIMIT_FACTOR * 100.0
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
        token_count: parse_u64_field(line, "token_count").expect("token_count"),
        parser_tree_capacity: parse_u64_field(line, "parser_tree_capacity")
            .expect("parser_tree_capacity"),
        parser_emit_len: parse_u64_field(line, "parser_emit_len").expect("parser_emit_len"),
        semantic_hir_count: parse_u64_field(line, "semantic_hir_count")
            .expect("semantic_hir_count"),
    }
}

fn parse_metrics_for_source(output: &str, source: &str) -> ParseMetrics {
    let marker = format!("source={source}");
    let mut previous_metrics = None;
    for line in output.lines() {
        if line.contains("phase=parse token_count=") {
            previous_metrics = Some(parse_metric_line(line));
        } else if line.contains(&marker) {
            return previous_metrics
                .take()
                .unwrap_or_else(|| panic!("missing parse metrics before {marker}"));
        }
    }
    panic!("suite output should include {marker}");
}

fn run_success(bin: &Path, args: &[&str]) -> String {
    run_success_timed(bin, args).stdout
}

struct TimedOutput {
    stdout: String,
    elapsed: Duration,
}

fn run_success_timed(bin: &Path, args: &[&str]) -> TimedOutput {
    run_success_timed_owned(
        bin,
        &args.iter().map(|arg| (*arg).into()).collect::<Vec<_>>(),
    )
}

fn run_success_timed_owned(bin: &Path, args: &[OsString]) -> TimedOutput {
    let command = Command::new(bin);
    run_command_success_timed(command, bin, args)
}

fn run_pareas_success_timed(
    bin: &Path,
    args: &[OsString],
    cuda_path: Option<&Path>,
    ld_library_path: Option<&OsStr>,
) -> TimedOutput {
    let mut command = Command::new(bin);
    if let Some(cuda_path) = cuda_path {
        command.env("CUDA_PATH", cuda_path);
        command.env("CUDA_ROOT", cuda_path);
    }
    if let Some(ld_library_path) = ld_library_path {
        command.env("LD_LIBRARY_PATH", ld_library_path);
    }
    run_command_success_timed(command, bin, args)
}

fn run_command_success_timed(mut command: Command, bin: &Path, args: &[OsString]) -> TimedOutput {
    if env::var_os("LANIUS_X86_READBACK_TIMEOUT_MS").is_none() {
        command.env(
            "LANIUS_X86_READBACK_TIMEOUT_MS",
            GENERATED_X86_READBACK_TIMEOUT_MS,
        );
    }
    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    let timeout = generated_gate_command_timeout();
    let start = Instant::now();
    let mut child = command
        .args(args)
        .spawn()
        .unwrap_or_else(|err| panic!("run {}: {err}", bin.display()));
    let output = loop {
        match child.try_wait() {
            Ok(Some(_status)) => {
                break child.wait_with_output().unwrap_or_else(|err| {
                    panic!("collect {} output after exit: {err}", bin.display())
                });
            }
            Ok(None) => {}
            Err(err) => panic!("wait for {}: {err}", bin.display()),
        }

        if start.elapsed() >= timeout {
            if let Err(err) = child.kill() {
                eprintln!(
                    "failed to terminate timed-out generated gate command {}: {err}",
                    bin.display()
                );
            }
            let output = child
                .wait_with_output()
                .unwrap_or_else(|err| panic!("collect timed-out {} output: {err}", bin.display()));
            panic!(
                "{} {:?} timed out after {} ms\nstdout:\n{}\nstderr:\n{}",
                bin.display(),
                args,
                timeout.as_millis(),
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
        }

        thread::sleep(Duration::from_millis(CHILD_PROCESS_POLL_INTERVAL_MS));
    };
    let elapsed = start.elapsed();
    assert!(
        output.status.success(),
        "{} {:?} failed with status {:?}\nstdout:\n{}\nstderr:\n{}",
        bin.display(),
        args,
        output.status.code(),
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    TimedOutput {
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        elapsed,
    }
}

fn parse_u64_field(text: &str, name: &str) -> Option<u64> {
    parse_field(text, name)?.parse().ok()
}

fn parse_u64_values(text: &str, name: &str) -> Vec<u64> {
    text.lines()
        .filter_map(|line| parse_u64_field(line, name))
        .collect()
}

fn parse_ms_field(text: &str, name: &str) -> Option<f64> {
    parse_field(text, name)?.parse().ok()
}

fn parse_field<'a>(text: &'a str, name: &str) -> Option<&'a str> {
    let prefix = format!("{name}=");
    text.split_ascii_whitespace()
        .find_map(|word| word.strip_prefix(&prefix))
}

fn generated_lines() -> String {
    bounded_positive_usize_env(
        "LANIUS_GENERATED_LINES",
        DEFAULT_GENERATED_LINES,
        MAX_GENERATED_LINES_WITHOUT_OPT_IN,
    )
    .to_string()
}

fn capacity_stress_lines() -> String {
    bounded_positive_usize_env(
        "LANIUS_CAPACITY_STRESS_LINES",
        DEFAULT_CAPACITY_STRESS_LINES,
        MAX_CAPACITY_STRESS_LINES_WITHOUT_OPT_IN,
    )
    .to_string()
}

fn capacity_stress_source() -> String {
    env::var("LANIUS_CAPACITY_STRESS_SOURCE")
        .unwrap_or_else(|_| DEFAULT_CAPACITY_STRESS_SOURCE.to_string())
}

fn max_capacity_stress_compile_floor_bytes() -> u64 {
    env::var("LANIUS_MAX_CAPACITY_STRESS_COMPILE_FLOOR_BYTES")
        .map(|value| parse_u64_env_value("LANIUS_MAX_CAPACITY_STRESS_COMPILE_FLOOR_BYTES", &value))
        .unwrap_or(DEFAULT_MAX_CAPACITY_STRESS_COMPILE_FLOOR_BYTES)
}

fn generated_gate_command_timeout() -> Duration {
    env::var("LANIUS_GENERATED_GATE_COMMAND_TIMEOUT_MS")
        .map(|value| {
            let milliseconds =
                parse_u64_env_value("LANIUS_GENERATED_GATE_COMMAND_TIMEOUT_MS", &value);
            assert!(
                milliseconds > 0,
                "LANIUS_GENERATED_GATE_COMMAND_TIMEOUT_MS must be greater than zero"
            );
            Duration::from_millis(milliseconds)
        })
        .unwrap_or_else(|_| Duration::from_millis(DEFAULT_GENERATED_GATE_COMMAND_TIMEOUT_MS))
}

fn pareas_compare_iters() -> usize {
    bounded_positive_usize_env(
        "LANIUS_PAREAS_COMPARE_ITERS",
        DEFAULT_PAREAS_COMPARE_ITERS,
        MAX_PAREAS_COMPARE_ITERS_WITHOUT_OPT_IN,
    )
}

fn parse_usize_env_value(name: &str, value: &str) -> usize {
    value
        .parse()
        .unwrap_or_else(|_| panic!("{name} must be an integer, got {value:?}"))
}

fn bounded_positive_usize_env(name: &str, default_value: &str, max_without_opt_in: usize) -> usize {
    let value = env::var(name).unwrap_or_else(|_| default_value.to_string());
    let count = parse_usize_env_value(name, &value);
    assert!(count > 0, "{name} must be greater than zero");
    assert!(
        count <= max_without_opt_in || env_truthy(ALLOW_LARGE_GENERATED_TESTS_ENV),
        "{name}={count} exceeds the default test guardrail {max_without_opt_in}; set {ALLOW_LARGE_GENERATED_TESTS_ENV}=1 to run an intentionally larger generated gate"
    );
    count
}

fn parse_u64_env_value(name: &str, value: &str) -> u64 {
    value
        .parse()
        .unwrap_or_else(|_| panic!("{name} must be an integer, got {value:?}"))
}

fn gpu_compile_bench_bin() -> PathBuf {
    option_env!("CARGO_BIN_EXE_gpu_compile_bench")
        .map(PathBuf::from)
        .or_else(release_gpu_compile_bench_bin)
        .unwrap_or_else(|| PathBuf::from("target/debug/gpu_compile_bench"))
}

fn release_gpu_compile_bench_bin() -> Option<PathBuf> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/release/gpu_compile_bench");
    path.exists().then_some(path)
}

fn pareas_bin() -> Option<PathBuf> {
    if let Ok(path) = env::var("PAREAS_BIN") {
        let path = PathBuf::from(path);
        if path.exists() {
            return Some(path);
        }
    }
    let home = env::var("HOME").ok().map(PathBuf::from)?;
    [
        home.join("code/pareas/build-laniusc-cuda-futhark025/pareas"),
        home.join("code/pareas/build-laniusc-cuda/pareas"),
        home.join("code/pareas/build-laniusc-c/pareas"),
        home.join("code/pareas/build/pareas"),
        home.join("code/pareas/build/src/pareas"),
        home.join("code/pareas/builddir/pareas"),
        home.join("code/pareas/builddir/src/pareas"),
    ]
    .into_iter()
    .find(|path| path.exists())
}

fn pareas_runtime_cuda_path() -> Option<PathBuf> {
    if let Some(path) = env::var_os("PAREAS_CUDA_PATH").or_else(|| env::var_os("CUDA_PATH")) {
        let path = PathBuf::from(path);
        if path.join("include/cuda_fp16.h").is_file() {
            return Some(path);
        }
    }
    if let Ok(home) = env::var("HOME") {
        let path = PathBuf::from(home).join(".cache/laniusc-tools/cuda-12.8-python");
        if path.join("include/cuda_fp16.h").is_file() {
            return Some(path);
        }
    }
    let path = PathBuf::from("/usr/local/cuda");
    path.join("include/cuda_fp16.h").is_file().then_some(path)
}

fn pareas_runtime_ld_library_path() -> Option<OsString> {
    let mut dirs: Vec<PathBuf> = env::var_os("PAREAS_LD_LIBRARY_PATH")
        .map(|value| env::split_paths(&value).collect())
        .unwrap_or_default();

    if let Some(cuda_path) = env::var_os("CUDA_PATH") {
        push_existing_dir(&mut dirs, PathBuf::from(cuda_path).join("lib64"));
    }
    if let Ok(home) = env::var("HOME") {
        let tools = PathBuf::from(home).join(".cache/laniusc-tools");
        push_existing_dir(&mut dirs, tools.join("cuda-12.8-python/lib64"));
        push_existing_dir(&mut dirs, tools.join("cuda-12.9-python/lib64"));
    }
    push_existing_dir(&mut dirs, PathBuf::from("/usr/local/cuda/lib64"));

    if let Some(current) = env::var_os("LD_LIBRARY_PATH") {
        dirs.extend(env::split_paths(&current));
    }

    (!dirs.is_empty()).then(|| env::join_paths(dirs).expect("join LD_LIBRARY_PATH candidates"))
}

fn push_existing_dir(dirs: &mut Vec<PathBuf>, dir: PathBuf) {
    if dir.is_dir() {
        dirs.push(dir);
    }
}

fn pareas_generated_source(lines: usize) -> String {
    let helper_count = lines.saturating_sub(4).max(1) / 5;
    let mut src = String::with_capacity(lines * 28);
    for i in 0..helper_count {
        src.push_str(&format!(
            "fn f{i}[a: int]: int {{\n  var x = a + {i};\n  return x;\n}}\n"
        ));
    }
    src.push_str("fn main[]: int {\n  var acc = 0;\n");
    for i in 0..helper_count {
        src.push_str(&format!("  acc = acc + f{i}[{i}];\n"));
    }
    src.push_str("  return acc;\n}\n");
    src
}

fn unique_temp_path(stem: &str, ext: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0))
        .as_nanos();
    env::temp_dir().join(format!("{stem}_{}_{}.{}", std::process::id(), nanos, ext))
}

fn env_truthy(name: &str) -> bool {
    env::var(name).is_ok_and(|value| {
        matches!(
            value.trim().to_ascii_lowercase().as_str(),
            "1" | "true" | "yes" | "on"
        )
    })
}

fn duration_ms(duration: Duration) -> f64 {
    duration.as_secs_f64() * 1000.0
}

use std::{
    path::PathBuf,
    process::{Command, Stdio},
    rc::Rc,
    time::Instant,
};

#[cfg(test)]
use laniusc::codegen::x86::x86_capacity_estimate_for_hir;
use laniusc::{
    codegen::x86::{
        X86CapacityEstimate,
        x86_capacity_estimate_for_hir_and_tokens,
        x86_node_inst_order_record_words,
    },
    compiler::{
        GpuCompiler,
        GpuLiveCapacityEstimateResult,
        compile_source_to_wasm_with_gpu_codegen_using,
        compile_source_to_x86_64_with_gpu_codegen_using,
    },
    gpu::device,
    parser::tables::PrecomputedParseTables,
};

const RESIDENT_TREE_PRODUCTION_CAPACITY_PER_TOKEN: usize = 4;
const TYPECHECK_CALL_PARAM_CACHE_STRIDE: usize = 16;
const TYPECHECK_TYPE_INSTANCE_ARG_REF_STRIDE: usize = 4;
const TYPECHECK_NAME_RADIX_BUCKETS: usize = 257;
const TYPECHECK_LANGUAGE_SYMBOL_COUNT: usize = 19;
const TYPECHECK_HIR_VISIBLE_DECL_ROW_BLOCK_SIZE: usize = 64;

fn main() {
    if let Err(err) = pollster::block_on(run()) {
        eprintln!("gpu_compile_bench: {err}");
        std::process::exit(1);
    }
}

async fn run() -> Result<(), String> {
    let mut lines = 100_000usize;
    let mut target_bytes: Option<usize> = None;
    let mut iters = 3usize;
    let mut warmups = 1usize;
    let mut validate_output = false;
    let mut source_mode = SourceMode::SimpleLets;
    let mut emit_phase = Phase::Wasm;
    let mut phase = Phase::Wasm;
    let mut seed = 0xc0de_5eed_u64;
    let mut allow_large = false;
    let mut estimate_only = false;
    let mut estimate_live = false;
    let mut dump_source = false;
    let mut run_x86_output = false;

    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--lines" => {
                lines = parse_usize("--lines", args.next())?;
            }
            "--target-bytes" => {
                target_bytes = Some(parse_usize("--target-bytes", args.next())?);
            }
            "--iters" => {
                iters = parse_usize("--iters", args.next())?;
            }
            "--warmups" => {
                warmups = parse_usize("--warmups", args.next())?;
            }
            "--source" | "--mode" => {
                source_mode = parse_source_mode(args.next())?;
            }
            flag if flag.starts_with("--source=") => {
                source_mode =
                    parse_source_mode(Some(flag.trim_start_matches("--source=").to_string()))?
            }
            flag if flag.starts_with("--mode=") => {
                source_mode =
                    parse_source_mode(Some(flag.trim_start_matches("--mode=").to_string()))?
            }
            "--seed" => {
                seed = parse_u64("--seed", args.next())?;
            }
            "--validate-output" => {
                validate_output = true;
            }
            "--run-x86-output" => {
                run_x86_output = true;
                validate_output = true;
            }
            "--allow-large" => {
                allow_large = true;
            }
            "--estimate-only" => {
                estimate_only = true;
            }
            "--estimate-live" => {
                estimate_live = true;
            }
            "--dump-source" => {
                dump_source = true;
            }
            "--phase" => {
                phase = parse_phase(args.next(), emit_phase)?;
            }
            flag if flag.starts_with("--phase=") => {
                phase = parse_phase(
                    Some(flag.trim_start_matches("--phase=").to_string()),
                    emit_phase,
                )?
            }
            "--emit" => {
                emit_phase = parse_emit_phase(args.next())?;
                phase = emit_phase;
            }
            flag if flag.starts_with("--emit=") => {
                emit_phase =
                    parse_emit_phase(Some(flag.trim_start_matches("--emit=").to_string()))?;
                phase = emit_phase;
            }
            "-h" | "--help" => {
                print_help();
                return Ok(());
            }
            flag => return Err(format!("unknown flag {flag}")),
        }
    }

    if estimate_only && estimate_live {
        return Err("--estimate-only and --estimate-live are mutually exclusive".into());
    }
    let parse_tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tables/parse_tables.bin"
    )))
    .ok();
    if source_mode == SourceMode::All {
        if dump_source {
            return Err("--dump-source requires a concrete --source, not --source all".into());
        }
        return run_source_suite(
            phase,
            lines,
            target_bytes,
            seed,
            warmups,
            iters,
            validate_output,
            run_x86_output,
            allow_large,
            estimate_only,
            estimate_live,
            parse_tables.as_ref(),
        )
        .await;
    }

    let generated = make_source_artifact(source_mode, lines, target_bytes, seed);
    let src = generated.source;
    let source_lines = src.lines().count();
    if dump_source {
        print!("{src}");
        return Ok(());
    }
    if estimate_only {
        print_capacity_estimate(source_lines, src.len(), parse_tables.as_ref());
        return Ok(());
    }
    if estimate_live {
        let compiler = GpuCompiler::new_with_device(device::global())
            .await
            .map_err(|err| err.to_string())?;
        let live = compiler
            .benchmark_live_capacity_estimate(&src)
            .await
            .map_err(|err| err.to_string())?;
        print_live_capacity_estimate(source_lines, src.len(), live, parse_tables.as_ref());
        return Ok(());
    }
    reject_large_interactive_run(
        phase,
        source_lines,
        src.len(),
        allow_large,
        parse_tables.as_ref(),
    )?;
    let compiler = GpuCompiler::new_with_device(device::global())
        .await
        .map_err(|err| err.to_string())?;

    for _ in 0..warmups {
        run_phase(
            phase,
            &src,
            &compiler,
            validate_output,
            run_x86_output,
            generated.expected_stdout.as_deref(),
            "warmup",
        )
        .await?;
    }

    let mut best_ms = f64::INFINITY;
    let mut total_ms = 0.0f64;
    let mut output_bytes = 0usize;
    for _ in 0..iters {
        let start = Instant::now();
        let emitted = run_phase(
            phase,
            &src,
            &compiler,
            validate_output,
            run_x86_output,
            generated.expected_stdout.as_deref(),
            "measured",
        )
        .await?;
        let elapsed_ms = start.elapsed().as_secs_f64() * 1000.0;
        best_ms = best_ms.min(elapsed_ms);
        total_ms += elapsed_ms;
        output_bytes = emitted.len();
    }

    let avg_ms = if iters == 0 {
        0.0
    } else {
        total_ms / iters as f64
    };
    println!(
        "phase={} emit={} source={} lines={source_lines} bytes={} output_bytes={output_bytes} warmups={warmups} iters={iters} best_ms={best_ms:.3} avg_ms={avg_ms:.3}",
        phase.name(),
        phase.emit_name(),
        source_mode.name(),
        src.len()
    );
    Ok(())
}

#[allow(clippy::too_many_arguments)]
async fn run_source_suite(
    phase: Phase,
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
    warmups: usize,
    iters: usize,
    validate_output: bool,
    run_x86_output: bool,
    allow_large: bool,
    estimate_only: bool,
    estimate_live: bool,
    parse_tables: Option<&PrecomputedParseTables>,
) -> Result<(), String> {
    let mut compiler = None;
    let mut suite_sources = 0usize;
    let mut suite_lines = 0usize;
    let mut suite_bytes = 0usize;
    let mut suite_output_bytes = 0usize;
    let mut suite_best_ms_total = 0.0f64;
    let mut suite_avg_ms_total = 0.0f64;
    let mut suite_slowest_source = SourceMode::SimpleLets;
    let mut suite_slowest_avg_ms = 0.0f64;
    for source_mode in GENERATED_SOURCE_MODES {
        let generated = make_source_artifact(source_mode, lines, target_bytes, seed);
        let src = generated.source;
        let source_lines = src.lines().count();

        if estimate_only {
            println!("source={}", source_mode.name());
            print_capacity_estimate(source_lines, src.len(), parse_tables);
            continue;
        }

        if estimate_live {
            if compiler.is_none() {
                compiler = Some(
                    GpuCompiler::new_with_device(device::global())
                        .await
                        .map_err(|err| err.to_string())?,
                );
            }
            let compiler = compiler.as_ref().expect("suite compiler initialized");
            let live = compiler
                .benchmark_live_capacity_estimate(&src)
                .await
                .map_err(|err| err.to_string())?;
            println!("source={}", source_mode.name());
            print_live_capacity_estimate(source_lines, src.len(), live, parse_tables);
            continue;
        }

        reject_large_interactive_run(phase, source_lines, src.len(), allow_large, parse_tables)?;
        if compiler.is_none() {
            compiler = Some(
                GpuCompiler::new_with_device(device::global())
                    .await
                    .map_err(|err| err.to_string())?,
            );
        }
        let compiler = compiler.as_ref().expect("suite compiler initialized");

        for _ in 0..warmups {
            run_phase(
                phase,
                &src,
                compiler,
                validate_output,
                run_x86_output,
                generated.expected_stdout.as_deref(),
                "warmup",
            )
            .await?;
        }

        let mut best_ms = f64::INFINITY;
        let mut total_ms = 0.0f64;
        let mut output_bytes = 0usize;
        for _ in 0..iters {
            let start = Instant::now();
            let emitted = run_phase(
                phase,
                &src,
                compiler,
                validate_output,
                run_x86_output,
                generated.expected_stdout.as_deref(),
                "measured",
            )
            .await?;
            let elapsed_ms = start.elapsed().as_secs_f64() * 1000.0;
            best_ms = best_ms.min(elapsed_ms);
            total_ms += elapsed_ms;
            output_bytes = emitted.len();
        }
        let avg_ms = if iters == 0 {
            0.0
        } else {
            total_ms / iters as f64
        };
        println!(
            "phase={} emit={} source={} lines={source_lines} bytes={} output_bytes={output_bytes} warmups={warmups} iters={iters} best_ms={best_ms:.3} avg_ms={avg_ms:.3}",
            phase.name(),
            phase.emit_name(),
            source_mode.name(),
            src.len()
        );
        suite_sources += 1;
        suite_lines += source_lines;
        suite_bytes += src.len();
        suite_output_bytes += output_bytes;
        suite_best_ms_total += best_ms;
        suite_avg_ms_total += avg_ms;
        if avg_ms >= suite_slowest_avg_ms {
            suite_slowest_avg_ms = avg_ms;
            suite_slowest_source = source_mode;
        }
    }
    if suite_sources != 0 && !estimate_only && !estimate_live {
        println!(
            "suite phase={} emit={} sources={suite_sources} total_lines={suite_lines} total_bytes={suite_bytes} total_output_bytes={suite_output_bytes} warmups={warmups} iters={iters} best_ms_sum={suite_best_ms_total:.3} avg_ms_sum={suite_avg_ms_total:.3} slowest_source={} slowest_avg_ms={suite_slowest_avg_ms:.3}",
            phase.name(),
            phase.emit_name(),
            suite_slowest_source.name(),
        );
    }
    Ok(())
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Phase {
    Lex,
    Parse,
    TypeCheck,
    Wasm,
    X86,
}

impl Phase {
    fn name(self) -> &'static str {
        match self {
            Phase::Lex => "lex",
            Phase::Parse => "parse",
            Phase::TypeCheck => "typecheck",
            Phase::Wasm => "wasm",
            Phase::X86 => "x86",
        }
    }

    fn emit_name(self) -> &'static str {
        match self {
            Phase::Wasm => "wasm",
            Phase::X86 => "x86_64-elf",
            Phase::Lex | Phase::Parse | Phase::TypeCheck => "none",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum SourceMode {
    SimpleLets,
    Mixed,
    CallGraph,
    ExprDense,
    AbiCalls,
    Varied,
    LongFunction,
    All,
}

const GENERATED_SOURCE_MODES: [SourceMode; 7] = [
    SourceMode::SimpleLets,
    SourceMode::Mixed,
    SourceMode::CallGraph,
    SourceMode::ExprDense,
    SourceMode::AbiCalls,
    SourceMode::Varied,
    SourceMode::LongFunction,
];

async fn run_phase(
    phase: Phase,
    src: &str,
    compiler: &GpuCompiler<'_>,
    validate_output: bool,
    run_x86_output: bool,
    expected_stdout: Option<&str>,
    phase_name: &str,
) -> Result<Vec<u8>, String> {
    match phase {
        Phase::Lex => {
            compiler
                .benchmark_lex_source(src)
                .await
                .map_err(|err| err.to_string())?;
            Ok(Vec::new())
        }
        Phase::Parse => {
            let result = compiler
                .benchmark_parse_source(src)
                .await
                .map_err(|err| err.to_string())?;
            println!(
                "phase=parse token_count={} parser_tree_capacity={} parser_emit_len={} semantic_hir_count={}",
                result.token_count,
                result.parser_tree_capacity,
                result.ll1.emit_len,
                result.semantic_hir_count
            );
            Ok(Vec::new())
        }
        Phase::TypeCheck => {
            compiler
                .type_check_source(src)
                .await
                .map_err(|err| err.to_string())?;
            Ok(Vec::new())
        }
        Phase::Wasm => {
            let wasm = compile_source_to_wasm_with_gpu_codegen_using(src, compiler)
                .await
                .map_err(|err| err.to_string())?;
            validate_wasm_output(validate_output, &wasm, phase_name)?;
            Ok(wasm)
        }
        Phase::X86 => {
            let elf = compile_source_to_x86_64_with_gpu_codegen_using(src, compiler)
                .await
                .map_err(|err| err.to_string())?;
            validate_x86_output(validate_output, &elf, phase_name)?;
            if run_x86_output {
                run_x86_output_zero_exit(&elf, phase_name, expected_stdout)?;
            }
            Ok(elf)
        }
    }
}

impl SourceMode {
    fn name(self) -> &'static str {
        match self {
            SourceMode::SimpleLets => "simple-lets",
            SourceMode::Mixed => "mixed",
            SourceMode::CallGraph => "call-graph",
            SourceMode::ExprDense => "expr-dense",
            SourceMode::AbiCalls => "abi-calls",
            SourceMode::Varied => "varied",
            SourceMode::LongFunction => "long-function",
            SourceMode::All => "all",
        }
    }
}

fn parse_emit_phase(value: Option<String>) -> Result<Phase, String> {
    match value
        .ok_or_else(|| "--emit requires a value".to_string())?
        .as_str()
    {
        "wasm" => Ok(Phase::Wasm),
        "x86" | "x86_64" | "x86-64" | "elf" | "x86_64-elf" => Ok(Phase::X86),
        other => Err(format!(
            "unsupported --emit {other:?}; expected wasm or x86_64-elf"
        )),
    }
}

fn validate_wasm_output(enabled: bool, wasm: &[u8], phase: &str) -> Result<(), String> {
    if !enabled {
        return Ok(());
    }
    if !is_lanius_wasm_module(wasm) {
        return Err(format!("{phase} output is not the expected WASM module"));
    }
    Ok(())
}

fn is_lanius_wasm_module(bytes: &[u8]) -> bool {
    bytes.len() >= 60
        && bytes[0..8] == [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
        && contains_bytes(bytes, b"\x03env\x09print_i64")
        && contains_bytes(bytes, b"\x04main\x00")
}

fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty()
        && haystack
            .windows(needle.len())
            .any(|window| window == needle)
}

fn parse_usize(flag: &str, value: Option<String>) -> Result<usize, String> {
    value
        .ok_or_else(|| format!("{flag} requires a value"))?
        .parse::<usize>()
        .map_err(|err| format!("parse {flag}: {err}"))
}

fn parse_u64(flag: &str, value: Option<String>) -> Result<u64, String> {
    value
        .ok_or_else(|| format!("{flag} requires a value"))?
        .parse::<u64>()
        .map_err(|err| format!("parse {flag}: {err}"))
}

fn parse_source_mode(value: Option<String>) -> Result<SourceMode, String> {
    match value
        .ok_or_else(|| "--source requires a value".to_string())?
        .as_str()
    {
        "simple" | "simple-let" | "simple-lets" | "lets" => Ok(SourceMode::SimpleLets),
        "mixed" => Ok(SourceMode::Mixed),
        "call-graph" | "callgraph" | "calls" | "functions" => Ok(SourceMode::CallGraph),
        "expr-dense" | "expression-dense" | "dense-expr" | "expressions" => {
            Ok(SourceMode::ExprDense)
        }
        "abi-calls" | "abi" | "call-abi" | "wide-calls" => Ok(SourceMode::AbiCalls),
        "varied" | "stress" | "varied-functions" => Ok(SourceMode::Varied),
        "long-function" | "long-fn" | "single-function" | "single-fn" => {
            Ok(SourceMode::LongFunction)
        }
        "all" | "suite" | "generated-suite" => Ok(SourceMode::All),
        other => Err(format!(
            "unsupported --source {other:?}; expected simple-lets, mixed, call-graph, expr-dense, abi-calls, varied, long-function, or all"
        )),
    }
}

fn parse_phase(value: Option<String>, emit_phase: Phase) -> Result<Phase, String> {
    match value
        .ok_or_else(|| "--phase requires a value".to_string())?
        .as_str()
    {
        "lex" => Ok(Phase::Lex),
        "parse" => Ok(Phase::Parse),
        "typecheck" | "type-check" => Ok(Phase::TypeCheck),
        "compile" => Ok(emit_phase),
        "wasm" => Ok(Phase::Wasm),
        "x86" | "x86_64" | "x86-64" | "elf" | "x86_64-elf" => Ok(Phase::X86),
        other => Err(format!(
            "unsupported --phase {other:?}; expected lex, parse, typecheck, wasm, or x86"
        )),
    }
}

fn validate_x86_output(enabled: bool, elf: &[u8], phase: &str) -> Result<(), String> {
    if !enabled {
        return Ok(());
    }
    if !is_x86_64_elf(elf) {
        return Err(format!("{phase} output is not an x86_64 ELF executable"));
    }
    Ok(())
}

fn is_x86_64_elf(bytes: &[u8]) -> bool {
    bytes.len() >= 20
        && bytes[0..4] == [0x7f, b'E', b'L', b'F']
        && bytes[4] == 2
        && bytes[5] == 1
        && u16::from_le_bytes([bytes[18], bytes[19]]) == 0x3e
}

#[cfg(all(unix, target_arch = "x86_64"))]
fn run_x86_output_zero_exit(
    elf: &[u8],
    phase: &str,
    expected_stdout: Option<&str>,
) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;

    let path = unique_x86_output_path(phase);
    std::fs::write(&path, elf).map_err(|err| format!("write {}: {err}", path.display()))?;
    let mut permissions = std::fs::metadata(&path)
        .map_err(|err| format!("stat {}: {err}", path.display()))?
        .permissions();
    permissions.set_mode(0o755);
    std::fs::set_permissions(&path, permissions)
        .map_err(|err| format!("chmod {}: {err}", path.display()))?;

    let mut command = Command::new(&path);
    command.stdin(Stdio::null()).stderr(Stdio::piped());
    if expected_stdout.is_some() {
        command.stdout(Stdio::piped());
    } else {
        command.stdout(Stdio::null());
    }
    let output = command
        .output()
        .map_err(|err| format!("run {}: {err}", path.display()));
    let _ = std::fs::remove_file(&path);
    let output = output?;
    if !output.status.success() {
        return Err(format!(
            "{phase} x86 output exited with {:?}; stderr={}",
            output.status.code(),
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    if let Some(expected) = expected_stdout
        && output.stdout != expected.as_bytes()
    {
        return Err(format!(
            "{phase} x86 stdout mismatch: expected {} bytes, got {} bytes; expected prefix {:?}, got prefix {:?}",
            expected.len(),
            output.stdout.len(),
            preview_bytes(expected.as_bytes()),
            preview_bytes(&output.stdout)
        ));
    }
    Ok(())
}

#[cfg(not(all(unix, target_arch = "x86_64")))]
fn run_x86_output_zero_exit(
    _elf: &[u8],
    _phase: &str,
    _expected_stdout: Option<&str>,
) -> Result<(), String> {
    Err("--run-x86-output requires a Unix x86_64 host".into())
}

fn preview_bytes(bytes: &[u8]) -> String {
    const LIMIT: usize = 160;
    String::from_utf8_lossy(&bytes[..bytes.len().min(LIMIT)]).into_owned()
}

fn unique_x86_output_path(phase: &str) -> PathBuf {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    std::env::temp_dir().join(format!(
        "laniusc_gpu_compile_bench_{phase}_{}_{}",
        std::process::id(),
        nanos
    ))
}

fn reject_large_interactive_run(
    phase: Phase,
    source_lines: usize,
    source_bytes: usize,
    allow_large: bool,
    tables: Option<&PrecomputedParseTables>,
) -> Result<(), String> {
    const MAX_INTERACTIVE_LINES: usize = 100_000;
    const MAX_INTERACTIVE_BYTES: usize = 2_000_000;
    const MAX_INTERACTIVE_PARSER_TREE_FLOOR_BYTES: usize = 2 * 1024 * 1024 * 1024;
    const MAX_INTERACTIVE_FRONTEND_FLOOR_BYTES: usize = 2 * 1024 * 1024 * 1024;
    const MAX_INTERACTIVE_COMPILE_FLOOR_BYTES: usize = 3 * 1024 * 1024 * 1024;
    if allow_large {
        return Ok(());
    }

    let estimate = parser_capacity_estimate_for_source(source_bytes, tables);
    let floor_bytes = parser_tree_floor_bytes(estimate.tree_capacity);
    let lexer_byte_capacity = source_bytes.div_ceil(4).saturating_mul(4).max(1);
    let parser_floor = parser_allocation_floor_bytes(&estimate);
    let typecheck_floor =
        typecheck_allocation_floor_bytes(lexer_byte_capacity, estimate.tree_capacity, true, 1);
    let frontend_floor = parser_floor.total.saturating_add(typecheck_floor.total);
    if phase == Phase::X86 {
        let x86_capacity =
            x86_capacity_estimate_for_hir_and_tokens(estimate.tree_capacity, lexer_byte_capacity);
        let x86_floor = x86_allocation_floor_bytes(lexer_byte_capacity, &x86_capacity);
        let compile_floor = frontend_floor.saturating_add(x86_floor.total);
        if compile_floor > MAX_INTERACTIVE_COMPILE_FLOOR_BYTES {
            return Err(format!(
                "refusing large interactive GPU benchmark: lines={source_lines} bytes={source_bytes}; estimated compile allocation floor={} (parser={} typecheck={} x86={}) via {}; pass --allow-large to run it intentionally",
                human_bytes(compile_floor),
                human_bytes(parser_floor.total),
                human_bytes(typecheck_floor.total),
                human_bytes(x86_floor.total),
                estimate.path
            ));
        }
    }
    if matches!(phase, Phase::TypeCheck | Phase::Wasm | Phase::X86)
        && frontend_floor > MAX_INTERACTIVE_FRONTEND_FLOOR_BYTES
    {
        return Err(format!(
            "refusing large interactive GPU benchmark: lines={source_lines} bytes={source_bytes}; estimated frontend allocation floor={} (parser={} typecheck={}) via {}; pass --allow-large to run it intentionally",
            human_bytes(frontend_floor),
            human_bytes(parser_floor.total),
            human_bytes(typecheck_floor.total),
            estimate.path
        ));
    }

    if matches!(
        phase,
        Phase::Parse | Phase::TypeCheck | Phase::Wasm | Phase::X86
    ) && floor_bytes > MAX_INTERACTIVE_PARSER_TREE_FLOOR_BYTES
    {
        return Err(format!(
            "refusing large interactive GPU benchmark: lines={source_lines} bytes={source_bytes}; estimated parser tree floor={} via {}; pass --allow-large to run it intentionally",
            human_bytes(floor_bytes),
            estimate.path
        ));
    }

    if source_lines <= MAX_INTERACTIVE_LINES && source_bytes <= MAX_INTERACTIVE_BYTES {
        return Ok(());
    }

    Err(format!(
        "refusing large interactive GPU benchmark: lines={source_lines} bytes={source_bytes}; estimated parser tree floor={} via {}; pass --allow-large to run it intentionally",
        human_bytes(floor_bytes),
        estimate.path
    ))
}

fn print_capacity_estimate(
    source_lines: usize,
    source_bytes: usize,
    tables: Option<&PrecomputedParseTables>,
) {
    let lexer_byte_capacity = source_bytes.div_ceil(4).saturating_mul(4).max(1);
    let parser_token_capacity = lexer_byte_capacity.saturating_add(2);
    let parse_capacity = parser_capacity_estimate_for_source(source_bytes, tables);
    println!(
        "estimate lines={source_lines} source_bytes={source_bytes} lexer_byte_capacity={lexer_byte_capacity} parser_token_capacity={parser_token_capacity}"
    );
    print_capacity_floors(lexer_byte_capacity, &parse_capacity, None);
    println!("estimate ll1_seed_path=inactive note=capacity-derived; no GPU work was submitted");
}

fn print_live_capacity_estimate(
    source_lines: usize,
    source_bytes: usize,
    live: GpuLiveCapacityEstimateResult,
    tables: Option<&PrecomputedParseTables>,
) {
    let token_capacity = (live.token_count as usize).max(1);
    let parse_capacity = parser_capacity_estimate_for_live_token_count(
        token_capacity,
        live.parser_tree_capacity as usize,
        tables,
    );
    println!(
        "estimate_live lines={source_lines} source_bytes={source_bytes} gpu_token_count={} token_capacity={token_capacity} parser_emit_len={} semantic_hir_count={}",
        live.token_count, live.parser_emit_len, live.semantic_hir_count
    );
    let x86_hir_words = (live.parser_emit_len as usize).max(1);
    print_capacity_floors(token_capacity, &parse_capacity, Some(x86_hir_words));
    if x86_hir_words < parse_capacity.tree_capacity {
        let projected_x86_capacity =
            x86_capacity_estimate_for_hir_and_tokens(parse_capacity.tree_capacity, token_capacity);
        let current_x86_capacity =
            x86_capacity_estimate_for_hir_and_tokens(x86_hir_words, token_capacity);
        let projected_x86_floor =
            x86_allocation_floor_bytes(token_capacity, &projected_x86_capacity);
        let current_x86_floor = x86_allocation_floor_bytes(token_capacity, &current_x86_capacity);
        let saved = projected_x86_floor
            .hir_scaled
            .saturating_sub(current_x86_floor.hir_scaled);
        println!(
            "estimate_live x86_parser_emit_capacity current_hir_words={x86_hir_words} projected_tree_hir_words={} projected_x86_hir_scaled={} current_x86_hir_scaled={} hir_scaled_savings={}",
            projected_x86_capacity.hir_words,
            human_bytes(projected_x86_floor.hir_scaled),
            human_bytes(current_x86_floor.hir_scaled),
            human_bytes(saved)
        );
    }
    let semantic_hir_words = (live.semantic_hir_count as usize).max(1);
    if semantic_hir_words < x86_hir_words {
        let current_x86_capacity =
            x86_capacity_estimate_for_hir_and_tokens(x86_hir_words, token_capacity);
        let dense_x86_capacity =
            x86_capacity_estimate_for_hir_and_tokens(semantic_hir_words, token_capacity);
        let current_x86_floor = x86_allocation_floor_bytes(token_capacity, &current_x86_capacity);
        let dense_x86_floor = x86_allocation_floor_bytes(token_capacity, &dense_x86_capacity);
        let saved = current_x86_floor
            .hir_scaled
            .saturating_sub(dense_x86_floor.hir_scaled);
        println!(
            "estimate_live x86_semantic_dense_hypothesis semantic_hir_words={semantic_hir_words} current_hir_words={x86_hir_words} current_x86_hir_scaled={} dense_x86_hir_scaled={} possible_hir_scaled_savings={} note=diagnostic-only-backend-records-are-still-original-hir-keyed",
            human_bytes(current_x86_floor.hir_scaled),
            human_bytes(dense_x86_floor.hir_scaled),
            human_bytes(saved)
        );
    }
    println!(
        "estimate_live ll1_seed_path=inactive note=live GPU lex, parser, and semantic-HIR count"
    );
}

fn print_capacity_floors(
    token_capacity: usize,
    parse_capacity: &ParserCapacityEstimate,
    x86_hir_words_override: Option<usize>,
) {
    let allocation_floor = parser_allocation_floor_bytes(parse_capacity);
    let typecheck_floor =
        typecheck_allocation_floor_bytes(token_capacity, parse_capacity.tree_capacity, true, 1);

    println!(
        "estimate parser_path={} parser_tree_capacity={} one_tree_u32_buffer={} parser_tree_buffer_floor={}",
        parse_capacity.path,
        parse_capacity.tree_capacity,
        human_bytes(parse_capacity.tree_capacity.saturating_mul(4)),
        human_bytes(allocation_floor.tree_hir)
    );
    println!(
        "estimate parser_allocation_floor total={} tree_hir={} brackets={} pack_streams={}",
        human_bytes(allocation_floor.total),
        human_bytes(allocation_floor.tree_hir),
        human_bytes(allocation_floor.brackets),
        human_bytes(allocation_floor.pack_streams)
    );
    println!(
        "estimate typecheck_u32_buffer_floor total={} names_radix={} module_paths={} visible_hir_decls={} calls={} type_metadata={} methods={} control={} core={} empty_hir={}",
        human_bytes(typecheck_floor.total),
        human_bytes(typecheck_floor.names_radix),
        human_bytes(typecheck_floor.module_paths),
        human_bytes(typecheck_floor.visible_hir_decls),
        human_bytes(typecheck_floor.calls),
        human_bytes(typecheck_floor.type_metadata),
        human_bytes(typecheck_floor.methods),
        human_bytes(typecheck_floor.control),
        human_bytes(typecheck_floor.core),
        human_bytes(typecheck_floor.empty_hir),
    );
    println!(
        "estimate frontend_allocation_floor parser_plus_typecheck={}",
        human_bytes(allocation_floor.total.saturating_add(typecheck_floor.total))
    );
    let x86_hir_words = x86_hir_words_override
        .unwrap_or(parse_capacity.tree_capacity)
        .max(1);
    let x86_hir_basis = if x86_hir_words_override.is_some() {
        "parser_emit_len"
    } else {
        "parser_tree_capacity"
    };
    let x86_capacity = x86_capacity_estimate_for_hir_and_tokens(x86_hir_words, token_capacity);
    let x86_dynamic = x86_dynamic_buffer_estimate_bytes(&x86_capacity);
    let x86_floor = x86_allocation_floor_bytes(token_capacity, &x86_capacity);
    println!(
        "estimate x86_dynamic_caps hir_basis={x86_hir_basis} hir_words={} requested_inst_capacity={} inst_capacity={} inst_capacity_capped={} output_capacity={}",
        x86_capacity.hir_words,
        x86_capacity.requested_inst_capacity,
        x86_capacity.inst_capacity,
        x86_capacity.inst_capacity_capped,
        human_bytes(x86_capacity.output_capacity)
    );
    println!(
        "estimate x86_dynamic_buffer_estimate total={} virtual_inst_records={} live_ranges={} selected_text={}",
        human_bytes(x86_dynamic.total),
        human_bytes(x86_dynamic.virtual_inst_records),
        human_bytes(x86_dynamic.live_ranges),
        human_bytes(x86_dynamic.selected_text)
    );
    println!(
        "estimate x86_allocation_floor total={} hir_scaled={} token_scaled={} inst_scaled={} scans={} output_and_readback={} small={}",
        human_bytes(x86_floor.total),
        human_bytes(x86_floor.hir_scaled),
        human_bytes(x86_floor.token_scaled),
        human_bytes(x86_floor.inst_scaled),
        human_bytes(x86_floor.scans),
        human_bytes(x86_floor.output_and_readback),
        human_bytes(x86_floor.small),
    );
    println!(
        "estimate compile_allocation_floor parser_plus_typecheck_plus_x86={}",
        human_bytes(
            allocation_floor
                .total
                .saturating_add(typecheck_floor.total)
                .saturating_add(x86_floor.total)
        )
    );
    if parse_capacity.path.starts_with("llp-") {
        println!(
            "estimate llp_pair_projection max_sc_len={} max_emit_len={} total_sc={} total_emit={}",
            parse_capacity.max_sc_len,
            parse_capacity.max_emit_len,
            parse_capacity.total_sc,
            parse_capacity.total_emit
        );
    }
}

struct X86DynamicBufferEstimate {
    total: usize,
    virtual_inst_records: usize,
    live_ranges: usize,
    selected_text: usize,
}

struct X86AllocationFloor {
    total: usize,
    hir_scaled: usize,
    token_scaled: usize,
    inst_scaled: usize,
    scans: usize,
    output_and_readback: usize,
    small: usize,
}

fn x86_dynamic_buffer_estimate_bytes(capacity: &X86CapacityEstimate) -> X86DynamicBufferEstimate {
    let inst = capacity.inst_capacity;
    let virtual_inst_records = inst
        .saturating_mul(16)
        .saturating_add(inst.saturating_mul(16))
        .saturating_add(inst.saturating_mul(4));
    let live_ranges = inst.saturating_mul(4).saturating_mul(4);
    let selected_text = inst.saturating_mul(4).saturating_mul(3);
    X86DynamicBufferEstimate {
        total: virtual_inst_records
            .saturating_add(live_ranges)
            .saturating_add(selected_text),
        virtual_inst_records,
        live_ranges,
        selected_text,
    }
}

fn x86_allocation_floor_bytes(
    token_capacity: usize,
    capacity: &X86CapacityEstimate,
) -> X86AllocationFloor {
    const X86_NODE_LOCAL_INSTS: usize = 4;
    const STATUS_WORDS: usize = 4;
    const FUNC_META_WORDS: usize = 8;
    const ELF_LAYOUT_WORDS: usize = 8;
    const TRACE_STATUS_WORDS: usize = 84;

    let token_words = token_capacity.max(1);
    let hir_words = capacity.hir_words.max(1);
    let inst = capacity.inst_capacity.max(1);
    let output_words = capacity.output_capacity.div_ceil(4).max(1);
    let func_owner_scan_blocks = hir_words.div_ceil(256).max(1);
    let node_inst_scan_words = hir_words.saturating_add(1);
    let text_scan_blocks = inst.div_ceil(256).max(1);

    let hir_scaled_words_per_node = (
        // Keep this in sync with `record_x86_elf_from_gpu_hir` HIR-sized buffers.
        4 + 4
            + 1
            + 1
            + 1
            + 1
            + 4
            + 4
            + 1
            + 1
            + 1
            + 1
            + 1
            + 1
            + 1
            + 1
            + 4
            + 4
            + 4
            + 4
            + 4
            + 4
            + 1
            + 4
            + 1
            + 4
            + 1
            + 4
            + 1
            + 4
            + 1
            + 4
            + 4
            + 4
            + 4
            + 4
            + 4
            + 4
            + 1
            + 1
            + 4
            + 4
            + X86_NODE_LOCAL_INSTS
            + 4
            + 1
            + 1
            + 1
        // Write-only call-argument eval, call-argument ABI, node-value,
        // terminal-if projection, dead return-projection records, and the
        // dead function-discovery record were removed from the retained x86
        // backend surface. The call-argument lookup record is packed to one
        // word per call/ordinal slot, and the call ABI record stores only the
        // target plus packed argument count/return width. One resolved-expression
        // table was added so backend shaders do not each walk HIR_EXPR_FORWARD
        // chains locally. Node instruction ranges retain only packed
        // start/count/kind data. Enum value records retain only packed
        // kind/payload-count data plus ordinal. Struct/array access rows and
        // declaration layout rows pack their small kind fields into three-word
        // flat records. Node instruction order rows use a compact three-word
        // phase-reused buffer.
        // Enclosing loop owners, virtual parameter masks, node instruction
        // counts, instruction-order rows, subtree slot bounds, node
        // instruction locations, and virtual row bounds reuse existing backend
        // scratch instead of adding HIR-sized buffers. Call type and node
        // instruction count records share one flat three-word row table.
        // Match-result owner pointer-jump rows reuse the later match-pattern
        // owner scratch and same-end link scratch.
        // Function-owner pointer-jump output reuses match-pattern first-use
        // scratch, copying odd-step results back to the stable owner table.
        // Enclosing-let pointer-jump output reuses the later call-callee-root
        // marker table after copyback to the stable owner table.
        // Intrinsic call projection reuses the dead match-pattern owner table.
        // Intrinsic call projection packs the call lookup base and small
        // intrinsic tag into one HIR-keyed word. Call ABI, call-argument lookup,
        // and declaration layouts are token/declaration-token indexed instead
        // of retaining HIR-sized side tables.
        // x86 calls resolve function targets through the token-indexed
        // declaration table rather than a second open-address function table,
        // and const values are token-row sized.
        // Register allocation keeps active-end register state in token-scaled
        // function slots and uses a compact function-slot list for active
        // dispatch.
    )
    .saturating_sub(83usize);
    let hir_scaled_words = hir_words.saturating_mul(hir_scaled_words_per_node);
    let token_scaled_words_per_token = {
        // Token-sized metadata and the token half of compact backend lookup
        // buffers. Virtual function-row bounds reuse dead call lookup/ABI
        // storage, and register-allocation active ends reuse dead node-order
        // scratch when that scratch is large enough.
        let enum_type_record = 1usize;
        let struct_type_record = 1usize;
        let decl_layout_record = 4usize;
        let decl_node_by_token = 1usize;
        let func_slot_by_index = 1usize;
        let const_value_record = 2usize;
        let param_reg_record = 5usize;
        let local_literal_record = 3usize;
        let call_arg_lookup_record = 4usize;
        let call_abi_record = 2usize;
        enum_type_record
            + struct_type_record
            + decl_layout_record
            + decl_node_by_token
            + func_slot_by_index
            + const_value_record
            + param_reg_record
            + local_literal_record
            + call_arg_lookup_record
            + call_abi_record
    };
    let virtual_regalloc_active_end_words = token_words.saturating_mul(10);
    let legacy_node_inst_order_reuse_words = node_inst_scan_words.saturating_mul(3);
    let node_inst_order_reuse_words =
        x86_node_inst_order_record_words(hir_words, inst, token_words);
    let hir_scaled_words = hir_scaled_words.saturating_sub(
        legacy_node_inst_order_reuse_words.saturating_sub(node_inst_order_reuse_words),
    );
    let active_end_extra_words =
        virtual_regalloc_active_end_words.saturating_sub(node_inst_order_reuse_words);
    let token_scaled_words = token_words
        .saturating_mul(token_scaled_words_per_token)
        .saturating_add(active_end_extra_words);
    let inst_scaled_words = inst.saturating_mul(
        // Virtual instruction records plus the inst-sized scratch that remains
        // live after lifetime reuse. Selected instruction fields and
        // instruction sizes reuse dead backend scratch records; byte offsets
        // and text-scan local prefixes are retained as compact inst-sized
        // rows after virtual use-edge materialization was removed.
        4 + 4 + 1 + 1 + 1 + 1 + 1 + 1 + 1,
    );
    let scan_words = func_owner_scan_blocks
        .saturating_mul(3)
        .saturating_add(node_inst_scan_words.saturating_mul(5))
        .saturating_add(text_scan_blocks.saturating_mul(3));
    let output_words_total = output_words.saturating_mul(2).saturating_add(4);
    let small_words = FUNC_META_WORDS
        .saturating_mul(2)
        .saturating_add(ELF_LAYOUT_WORDS)
        .saturating_add(STATUS_WORDS.saturating_mul(37))
        .saturating_add(TRACE_STATUS_WORDS);

    X86AllocationFloor {
        hir_scaled: u32_words_to_bytes(hir_scaled_words),
        token_scaled: u32_words_to_bytes(token_scaled_words),
        inst_scaled: u32_words_to_bytes(inst_scaled_words),
        scans: u32_words_to_bytes(scan_words),
        output_and_readback: u32_words_to_bytes(output_words_total),
        small: u32_words_to_bytes(small_words),
        total: u32_words_to_bytes(
            hir_scaled_words
                .saturating_add(token_scaled_words)
                .saturating_add(inst_scaled_words)
                .saturating_add(scan_words)
                .saturating_add(output_words_total)
                .saturating_add(small_words),
        ),
    }
}

struct TypecheckAllocationFloor {
    total: usize,
    names_radix: usize,
    module_paths: usize,
    visible_hir_decls: usize,
    calls: usize,
    type_metadata: usize,
    methods: usize,
    control: usize,
    core: usize,
    empty_hir: usize,
}

fn typecheck_allocation_floor_bytes(
    token_capacity: usize,
    hir_node_capacity: usize,
    uses_hir_items: bool,
    source_file_capacity: usize,
) -> TypecheckAllocationFloor {
    let token_capacity = token_capacity.max(1);
    let hir_node_capacity = hir_node_capacity.max(1);
    let token_blocks = token_capacity.div_ceil(256).max(1);
    let name_capacity = token_capacity
        .saturating_add(TYPECHECK_LANGUAGE_SYMBOL_COUNT)
        .max(1);
    let name_blocks = name_capacity.div_ceil(256).max(1);
    let name_radix_histogram_len = name_blocks.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS);
    let hir_blocks = hir_node_capacity.div_ceil(256).max(1);
    let record_radix_histogram_len = token_blocks.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS);
    let source_file_capacity = source_file_capacity.max(1);
    let module_capacity = source_file_capacity;
    let import_visible_capacity = if source_file_capacity <= 1 {
        1
    } else {
        token_capacity
    };
    let module_blocks = module_capacity.div_ceil(256).max(1);
    let import_visible_blocks = import_visible_capacity.div_ceil(256).max(1);
    let module_radix_histogram_len = module_blocks.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS);
    let import_visible_radix_histogram_len =
        import_visible_blocks.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS);
    let module_path_key_radix_histogram_len = record_radix_histogram_len
        .max(module_radix_histogram_len)
        .max(import_visible_radix_histogram_len);
    let hir_visible_decl_tree_leaf_count = token_capacity
        .div_ceil(TYPECHECK_HIR_VISIBLE_DECL_ROW_BLOCK_SIZE)
        .max(1);
    let hir_visible_decl_tree_leaf_base = hir_visible_decl_tree_leaf_count.next_power_of_two();
    let hir_visible_decl_radix_histogram_len =
        token_blocks.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS);

    let core_u32 = 12usize
        .saturating_mul(token_capacity)
        .saturating_add(TYPECHECK_LANGUAGE_SYMBOL_COUNT);
    let names_radix_u32 = 4usize
        .saturating_mul(token_capacity)
        .saturating_add(3usize.saturating_mul(token_blocks))
        .saturating_add(2)
        .saturating_add(11usize.saturating_mul(name_capacity))
        .saturating_add(token_capacity)
        .saturating_add(2usize.saturating_mul(name_radix_histogram_len))
        .saturating_add(2usize.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS))
        .saturating_add(3)
        .saturating_add(1);
    let control_u32 = 9usize
        .saturating_mul(token_capacity)
        .saturating_add(8usize.saturating_mul(token_blocks))
        .saturating_add(4);
    let call_param_cache_u32 = TYPECHECK_CALL_PARAM_CACHE_STRIDE.saturating_mul(token_capacity);
    let call_arg_record_u32 = 4usize.saturating_mul(token_capacity);
    let call_arg_node_u32 = TYPECHECK_CALL_PARAM_CACHE_STRIDE.saturating_mul(token_capacity);
    let calls_u32 = 9usize
        .saturating_mul(token_capacity)
        .saturating_add(call_param_cache_u32)
        .saturating_add(call_arg_record_u32)
        .saturating_add(call_arg_node_u32)
        .saturating_add(token_capacity.max(hir_node_capacity));
    let methods_u32 = 17usize
        .saturating_mul(token_capacity)
        .saturating_add(source_file_capacity)
        .saturating_add(2usize.saturating_mul(name_radix_histogram_len))
        .saturating_add(2usize.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS))
        .saturating_add(1);
    let type_metadata_u32 = 26usize.saturating_mul(token_capacity).saturating_add(
        2usize
            .saturating_mul(TYPECHECK_TYPE_INSTANCE_ARG_REF_STRIDE)
            .saturating_mul(token_capacity),
    );
    let empty_hir_u32 = if uses_hir_items {
        4
    } else {
        4usize.saturating_mul(hir_node_capacity)
    };
    let module_paths_u32 = 70usize
        .saturating_mul(token_capacity)
        .saturating_add(source_file_capacity)
        .saturating_add(16usize.saturating_mul(module_capacity))
        .saturating_add(20usize.saturating_mul(import_visible_capacity))
        .saturating_add(2usize.saturating_mul(token_capacity))
        // HIR-indexed module/path scratch: packed family bits, reusable family
        // flag, shared record prefix/local scan, path prefix, and owner map.
        .saturating_add(6usize.saturating_mul(hir_node_capacity))
        .saturating_add(3usize.saturating_mul(hir_blocks))
        .saturating_add(2usize.saturating_mul(module_path_key_radix_histogram_len))
        .saturating_add(2usize.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS))
        .saturating_add(33);
    let visible_hir_decl_scan_scratch_u32 = if uses_hir_items {
        0
    } else {
        3usize
            .saturating_mul(hir_node_capacity)
            .saturating_add(3usize.saturating_mul(hir_blocks))
    };
    let visible_hir_decls_u32 = visible_hir_decl_scan_scratch_u32
        .saturating_add(1)
        .saturating_add(3)
        .saturating_add(6usize.saturating_mul(token_capacity))
        .saturating_add(2usize.saturating_mul(hir_visible_decl_radix_histogram_len))
        .saturating_add(2usize.saturating_mul(TYPECHECK_NAME_RADIX_BUCKETS))
        .saturating_add(hir_visible_decl_tree_leaf_base.saturating_mul(2));

    TypecheckAllocationFloor {
        total: u32_words_to_bytes(
            core_u32
                .saturating_add(names_radix_u32)
                .saturating_add(module_paths_u32)
                .saturating_add(visible_hir_decls_u32)
                .saturating_add(calls_u32)
                .saturating_add(type_metadata_u32)
                .saturating_add(methods_u32)
                .saturating_add(control_u32)
                .saturating_add(empty_hir_u32),
        ),
        names_radix: u32_words_to_bytes(names_radix_u32),
        module_paths: u32_words_to_bytes(module_paths_u32),
        visible_hir_decls: u32_words_to_bytes(visible_hir_decls_u32),
        calls: u32_words_to_bytes(calls_u32),
        type_metadata: u32_words_to_bytes(type_metadata_u32),
        methods: u32_words_to_bytes(methods_u32),
        control: u32_words_to_bytes(control_u32),
        core: u32_words_to_bytes(core_u32),
        empty_hir: u32_words_to_bytes(empty_hir_u32),
    }
}

fn u32_words_to_bytes(words: usize) -> usize {
    words.saturating_mul(4)
}

struct ParserAllocationFloor {
    total: usize,
    tree_hir: usize,
    brackets: usize,
    pack_streams: usize,
}

fn parser_allocation_floor_bytes(estimate: &ParserCapacityEstimate) -> ParserAllocationFloor {
    let tree_hir = parser_tree_floor_bytes(estimate.tree_capacity);
    let brackets = parser_bracket_floor_bytes(estimate.total_sc);
    let pack_streams = parser_pack_stream_floor_bytes(estimate);
    ParserAllocationFloor {
        total: tree_hir
            .saturating_add(brackets)
            .saturating_add(pack_streams),
        tree_hir,
        brackets,
        pack_streams,
    }
}

fn parser_tree_floor_bytes(tree_capacity: usize) -> usize {
    // Resident parser/HIR tree-capacity allocations after shared pointer-jump
    // list scratch. This counts actual allocations, not alias views.
    const PARSER_TREE_SCALAR_U32_BUFFERS: usize = 76;
    const PARSER_TREE_U32X4_RECORD_BUFFERS: usize = 3;
    let parser_tree_scalar_floor_bytes = PARSER_TREE_SCALAR_U32_BUFFERS
        .saturating_mul(tree_capacity)
        .saturating_mul(4);
    let parser_tree_wide_floor_bytes = PARSER_TREE_U32X4_RECORD_BUFFERS
        .saturating_mul(tree_capacity)
        .saturating_mul(16);
    parser_tree_scalar_floor_bytes.saturating_add(parser_tree_wide_floor_bytes)
}

fn parser_bracket_floor_bytes(total_sc: usize) -> usize {
    const U32_SIZE: usize = 4;
    let _ = total_sc;
    // `gpu_compile_bench` uses the resident LLP path. That path never records
    // the legacy bracket passes, so their buffers stay compatibility-sized.
    const RESIDENT_COMPAT_U32S: usize = 7 + 7 + 6 + 3;
    RESIDENT_COMPAT_U32S.saturating_mul(U32_SIZE)
}

fn parser_pack_stream_floor_bytes(estimate: &ParserCapacityEstimate) -> usize {
    const U32_SIZE: usize = 4;
    // Resident parsing consumes the production stream for tree/HIR recovery but
    // does not consume the legacy stack-change stream.
    1usize
        .saturating_add(estimate.tree_capacity.saturating_mul(2))
        .saturating_mul(U32_SIZE)
}

fn parser_capacity_estimate_for_source(
    source_bytes: usize,
    tables: Option<&PrecomputedParseTables>,
) -> ParserCapacityEstimate {
    let lexer_byte_capacity = source_bytes.div_ceil(4).saturating_mul(4).max(1);
    let parser_token_capacity = lexer_byte_capacity.saturating_add(2);
    let parser_pair_capacity = parser_token_capacity.saturating_sub(1);
    tables
        .map(|tables| {
            projected_parser_capacity(tables, parser_token_capacity, parser_pair_capacity)
        })
        .unwrap_or_else(|| ParserCapacityEstimate {
            path: "llp-unavailable",
            tree_capacity: parser_token_capacity.max(1),
            total_sc: 0,
            total_emit: parser_token_capacity.max(1),
            max_sc_len: 0,
            max_emit_len: 0,
        })
}

fn parser_capacity_estimate_for_live_token_count(
    token_capacity: usize,
    parser_tree_capacity: usize,
    tables: Option<&PrecomputedParseTables>,
) -> ParserCapacityEstimate {
    let token_capacity = token_capacity.max(1);
    let parser_pair_capacity = token_capacity.saturating_sub(1);
    tables
        .map(|tables| {
            let max_sc_len = tables.sc_len.iter().copied().max().unwrap_or(0) as usize;
            let max_emit_len = tables.pp_len.iter().copied().max().unwrap_or(0) as usize;
            ParserCapacityEstimate {
                path: "llp-live-gpu-count",
                tree_capacity: parser_tree_capacity.max(1),
                total_sc: parser_pair_capacity.saturating_mul(max_sc_len),
                total_emit: parser_pair_capacity.saturating_mul(max_emit_len),
                max_sc_len,
                max_emit_len,
            }
        })
        .unwrap_or_else(|| ParserCapacityEstimate {
            path: "llp-live-gpu-count-no-tables",
            tree_capacity: parser_tree_capacity.max(1),
            total_sc: 0,
            total_emit: parser_tree_capacity.max(1),
            max_sc_len: 0,
            max_emit_len: 0,
        })
}

struct ParserCapacityEstimate {
    path: &'static str,
    tree_capacity: usize,
    total_sc: usize,
    total_emit: usize,
    max_sc_len: usize,
    max_emit_len: usize,
}

fn projected_parser_capacity(
    tables: &PrecomputedParseTables,
    parser_token_capacity: usize,
    parser_pair_capacity: usize,
) -> ParserCapacityEstimate {
    let max_sc_len = tables.sc_len.iter().copied().max().unwrap_or(0) as usize;
    let max_emit_len = tables.pp_len.iter().copied().max().unwrap_or(0) as usize;
    let total_sc = parser_pair_capacity.saturating_mul(max_sc_len);
    let total_emit = parser_pair_capacity.saturating_mul(max_emit_len);
    ParserCapacityEstimate {
        path: "llp-projected",
        tree_capacity: resident_projected_tree_capacity(parser_token_capacity, total_emit),
        total_sc,
        total_emit,
        max_sc_len,
        max_emit_len,
    }
}

fn resident_projected_tree_capacity(parser_token_capacity: usize, total_emit: usize) -> usize {
    parser_token_capacity
        .saturating_mul(RESIDENT_TREE_PRODUCTION_CAPACITY_PER_TOKEN)
        .max(1)
        .min(total_emit.max(1))
}

fn human_bytes(bytes: usize) -> String {
    const KIB: f64 = 1024.0;
    const MIB: f64 = KIB * 1024.0;
    const GIB: f64 = MIB * 1024.0;
    let bytes_f = bytes as f64;
    if bytes_f >= GIB {
        format!("{:.2} GiB", bytes_f / GIB)
    } else if bytes_f >= MIB {
        format!("{:.1} MiB", bytes_f / MIB)
    } else if bytes_f >= KIB {
        format!("{:.1} KiB", bytes_f / KIB)
    } else {
        format!("{bytes} B")
    }
}

struct SourceArtifact {
    source: String,
    expected_stdout: Option<String>,
}

fn make_source_artifact(
    source_mode: SourceMode,
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> SourceArtifact {
    let (source, expected_stdout) = match source_mode {
        SourceMode::SimpleLets => (
            wrap_body_in_main(&make_simple_let_source(lines, target_bytes)),
            Some(String::new()),
        ),
        SourceMode::Mixed => {
            let SourceArtifact {
                source,
                expected_stdout,
            } = make_mixed_source_artifact(lines, target_bytes, seed);
            (source, expected_stdout)
        }
        SourceMode::CallGraph => {
            let SourceArtifact {
                source,
                expected_stdout,
            } = make_call_graph_source_artifact(lines, target_bytes, seed);
            (source, expected_stdout)
        }
        SourceMode::ExprDense => {
            let SourceArtifact {
                source,
                expected_stdout,
            } = make_expr_dense_source_artifact(lines, target_bytes, seed);
            (source, expected_stdout)
        }
        SourceMode::AbiCalls => {
            let SourceArtifact {
                source,
                expected_stdout,
            } = make_abi_call_source_artifact(lines, target_bytes, seed);
            (source, expected_stdout)
        }
        SourceMode::Varied => {
            let SourceArtifact {
                source,
                expected_stdout,
            } = make_varied_source_artifact(lines, target_bytes, seed);
            (source, expected_stdout)
        }
        SourceMode::LongFunction => {
            let SourceArtifact {
                source,
                expected_stdout,
            } = make_long_function_source_artifact(lines, target_bytes, seed);
            (source, expected_stdout)
        }
        SourceMode::All => unreachable!("suite mode expands before source generation"),
    };
    SourceArtifact {
        source,
        expected_stdout,
    }
}

#[cfg(test)]
fn make_source(
    source_mode: SourceMode,
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> String {
    make_source_artifact(source_mode, lines, target_bytes, seed).source
}

fn wrap_body_in_main(body: &str) -> String {
    let mut src = String::with_capacity(body.len().saturating_add(16));
    src.push_str("fn main() {\n");
    src.push_str(body);
    if !body.ends_with('\n') {
        src.push('\n');
    }
    src.push_str("    return 0;\n");
    src.push_str("}\n");
    src
}

fn make_simple_let_source(lines: usize, target_bytes: Option<usize>) -> String {
    if let Some(target_bytes) = target_bytes {
        let mut src = String::with_capacity(target_bytes.saturating_add(128));
        let mut i = 0usize;
        while src.len() < target_bytes {
            push_simple_let_line(&mut src, i);
            i += 1;
        }
        return src;
    }

    let mut src = String::with_capacity(lines.saturating_mul(18).saturating_add(64));
    for i in 0..lines {
        push_simple_let_line(&mut src, i);
    }
    src
}

fn push_simple_let_line(src: &mut String, i: usize) {
    src.push_str("let x");
    src.push_str(&i.to_string());
    src.push_str(" = ");
    src.push_str(&(i % 1024).to_string());
    src.push_str(";\n");
}

fn make_mixed_source_artifact(
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> SourceArtifact {
    let mut src = String::with_capacity(target_bytes.unwrap_or(lines.saturating_mul(48)));
    let mut rng = DeterministicRng::new(seed);
    let mut expected_stdout = String::new();
    let mut line_count = 0usize;
    let mut chunk = 0usize;
    loop {
        if target_bytes.is_some_and(|target| src.len() >= target)
            || target_bytes.is_none() && line_count >= lines
        {
            break;
        }
        line_count += push_mixed_chunk(&mut src, chunk, &mut rng, &mut expected_stdout);
        chunk += 1;
    }
    SourceArtifact {
        source: wrap_body_in_main(&src),
        expected_stdout: Some(expected_stdout),
    }
}

fn push_mixed_chunk(
    src: &mut String,
    chunk: usize,
    rng: &mut DeterministicRng,
    expected_stdout: &mut String,
) -> usize {
    if chunk >= 3 {
        return push_arithmetic_chunk(src, chunk, rng, expected_stdout);
    }

    match chunk % 4 {
        0 => push_bool_let_chunk(src, chunk, rng, expected_stdout),
        1 => push_if_else_chunk(src, chunk, rng, expected_stdout),
        2 => push_compare_print_chunk(src, chunk, rng, expected_stdout),
        _ => push_logic_chunk(src, chunk, rng, expected_stdout),
    }
}

fn append_expected_print(expected_stdout: &mut String, value: i32) {
    expected_stdout.push_str(&value.to_string());
    expected_stdout.push('\n');
}

struct LongFunctionSimulation {
    acc: i32,
    expected_stdout: String,
}

impl LongFunctionSimulation {
    fn add(&mut self, value: i32) {
        self.acc = self.acc.wrapping_add(value);
    }

    fn sub(&mut self, value: i32) {
        self.acc = self.acc.wrapping_sub(value);
    }

    fn print(&mut self, value: i32) {
        self.expected_stdout.push_str(&value.to_string());
        self.expected_stdout.push('\n');
    }
}

fn make_long_function_source_artifact(
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> SourceArtifact {
    let mut rng = DeterministicRng::new(seed);
    let pair_type = varied_short_ident("t", 0, &mut rng);
    let left_field = varied_short_ident("f", 1, &mut rng);
    let right_field = varied_short_ident("f", 2, &mut rng);
    let helper_fn = varied_short_ident("h", 3, &mut rng);
    let helper_param = varied_short_ident("p", 4, &mut rng);
    let acc_name = varied_short_ident("a", 5, &mut rng);
    let mut src = String::with_capacity(target_bytes.unwrap_or(lines.saturating_mul(48)));
    let mut sim = LongFunctionSimulation {
        acc: 0,
        expected_stdout: String::new(),
    };

    src.push_str("struct ");
    src.push_str(&pair_type);
    src.push_str(" {\n    ");
    src.push_str(&left_field);
    src.push_str(": i32,\n    ");
    src.push_str(&right_field);
    src.push_str(": i32,\n}\nfn ");
    src.push_str(&helper_fn);
    src.push('(');
    src.push_str(&helper_param);
    src.push_str(": i32) -> i32 {\n    return ");
    src.push_str(&helper_param);
    src.push_str(" + 1;\n}\nfn main() {\n    let ");
    src.push_str(&acc_name);
    src.push_str(": i32 = 0;\n");

    let mut line_count = 13usize;
    let mut chunk = 0usize;
    loop {
        if target_bytes.is_some_and(|target| src.len() >= target)
            || target_bytes.is_none() && line_count >= lines
        {
            break;
        }
        line_count += push_long_function_chunk(
            &mut src,
            chunk,
            &pair_type,
            &left_field,
            &right_field,
            &helper_fn,
            &acc_name,
            &mut rng,
            &mut sim,
        );
        chunk += 1;
    }

    src.push_str("    return 0;\n}\n");
    SourceArtifact {
        source: src,
        expected_stdout: Some(sim.expected_stdout),
    }
}

fn push_long_function_chunk(
    src: &mut String,
    chunk: usize,
    pair_type: &str,
    left_field: &str,
    right_field: &str,
    helper_fn: &str,
    acc_name: &str,
    rng: &mut DeterministicRng,
    sim: &mut LongFunctionSimulation,
) -> usize {
    match chunk % 6 {
        0 => push_long_nested_arithmetic(src, chunk, helper_fn, acc_name, rng, sim),
        1 => push_long_branch(src, chunk, acc_name, rng, sim),
        2 => push_long_array_loop(src, chunk, acc_name, rng, sim),
        3 => push_long_struct_use(
            src,
            chunk,
            pair_type,
            left_field,
            right_field,
            acc_name,
            rng,
            sim,
        ),
        4 => push_long_while(src, chunk, acc_name, rng, sim),
        _ => push_long_print(src, acc_name, rng, sim),
    }
}

fn push_long_nested_arithmetic(
    src: &mut String,
    chunk: usize,
    helper_fn: &str,
    acc_name: &str,
    rng: &mut DeterministicRng,
    sim: &mut LongFunctionSimulation,
) -> usize {
    let local = varied_short_ident("l", chunk, rng);
    let a = rng.small_int() % 31;
    let b = rng.small_int() % 17;
    let c = rng.small_int() % 9;
    let d = rng.small_int() % 7;
    let helper_arg = sim
        .acc
        .wrapping_add(a as i32)
        .wrapping_mul((b as i32).wrapping_sub(c as i32))
        .wrapping_add(d as i32);
    sim.add(helper_arg.wrapping_add(1));
    src.push_str("    let ");
    src.push_str(&local);
    src.push_str(": i32 = ");
    src.push_str(helper_fn);
    src.push_str("(((");
    src.push_str(acc_name);
    src.push_str(" + ");
    src.push_str(&a.to_string());
    src.push_str(") * (");
    src.push_str(&b.to_string());
    src.push_str(" - ");
    src.push_str(&c.to_string());
    src.push_str(")) + ");
    src.push_str(&d.to_string());
    src.push_str(");\n    ");
    src.push_str(acc_name);
    src.push_str(" += ");
    src.push_str(&local);
    src.push_str(";\n");
    2
}

fn push_long_branch(
    src: &mut String,
    chunk: usize,
    acc_name: &str,
    rng: &mut DeterministicRng,
    sim: &mut LongFunctionSimulation,
) -> usize {
    let threshold = (chunk % 97 + 1) as i32;
    let then_value = (rng.small_int() % 13 + 1) as i32;
    let else_value = (rng.small_int() % 11 + 1) as i32;
    if (sim.acc & 1) == 0 || sim.acc < threshold {
        sim.add(then_value);
    } else {
        sim.sub(else_value);
    }
    src.push_str("    if ((");
    src.push_str(acc_name);
    src.push_str(" & 1) == 0 || ");
    src.push_str(acc_name);
    src.push_str(" < ");
    src.push_str(&threshold.to_string());
    src.push_str(") {\n        ");
    src.push_str(acc_name);
    src.push_str(" += ");
    src.push_str(&then_value.to_string());
    src.push_str(";\n    } else {\n        ");
    src.push_str(acc_name);
    src.push_str(" -= ");
    src.push_str(&else_value.to_string());
    src.push_str(";\n    }\n");
    5
}

fn push_long_array_loop(
    src: &mut String,
    chunk: usize,
    acc_name: &str,
    rng: &mut DeterministicRng,
    sim: &mut LongFunctionSimulation,
) -> usize {
    let values = varied_short_ident("r", chunk, rng);
    let value = varied_short_ident("v", chunk, rng);
    let old_acc = sim.acc;
    let mut elements_sum = old_acc;
    src.push_str("    let ");
    src.push_str(&values);
    src.push_str(": [i32; 4] = [");
    src.push_str(acc_name);
    src.push_str(", ");
    for item_i in 0..3 {
        if item_i != 0 {
            src.push_str(", ");
        }
        let element = (rng.small_int() % 17) as i32;
        elements_sum = elements_sum.wrapping_add(element);
        src.push_str(&element.to_string());
    }
    sim.add(elements_sum);
    src.push_str("];\n    for ");
    src.push_str(&value);
    src.push_str(" in ");
    src.push_str(&values);
    src.push_str(" {\n        ");
    src.push_str(acc_name);
    src.push_str(" += ");
    src.push_str(&value);
    src.push_str(";\n    }\n");
    5
}

fn push_long_struct_use(
    src: &mut String,
    chunk: usize,
    pair_type: &str,
    left_field: &str,
    right_field: &str,
    acc_name: &str,
    rng: &mut DeterministicRng,
    sim: &mut LongFunctionSimulation,
) -> usize {
    let local = varied_short_ident("s", chunk, rng);
    let right_value = (rng.small_int() % 23) as i32;
    sim.add(sim.acc.wrapping_add(right_value));
    src.push_str("    let ");
    src.push_str(&local);
    src.push_str(": ");
    src.push_str(pair_type);
    src.push_str(" = ");
    src.push_str(pair_type);
    src.push_str(" { ");
    src.push_str(left_field);
    src.push_str(": ");
    src.push_str(acc_name);
    src.push_str(", ");
    src.push_str(right_field);
    src.push_str(": ");
    src.push_str(&right_value.to_string());
    src.push_str(" };\n    ");
    src.push_str(acc_name);
    src.push_str(" += ");
    src.push_str(&local);
    src.push('.');
    src.push_str(left_field);
    src.push_str(" + ");
    src.push_str(&local);
    src.push('.');
    src.push_str(right_field);
    src.push_str(";\n");
    2
}

fn push_long_while(
    src: &mut String,
    chunk: usize,
    acc_name: &str,
    rng: &mut DeterministicRng,
    sim: &mut LongFunctionSimulation,
) -> usize {
    let index = varied_short_ident("i", chunk, rng);
    let limit = (chunk % 3 + 1) as i32;
    let step = (rng.small_int() % 5 + 1) as i32;
    sim.add(limit.wrapping_mul(step));
    src.push_str("    let ");
    src.push_str(&index);
    src.push_str(": i32 = 0;\n    while (");
    src.push_str(&index);
    src.push_str(" < ");
    src.push_str(&limit.to_string());
    src.push_str(") {\n        ");
    src.push_str(acc_name);
    src.push_str(" += ");
    src.push_str(&step.to_string());
    src.push_str(";\n        ");
    src.push_str(&index);
    src.push_str(" += 1;\n    }\n");
    6
}

fn push_long_print(
    src: &mut String,
    acc_name: &str,
    rng: &mut DeterministicRng,
    sim: &mut LongFunctionSimulation,
) -> usize {
    let offset = (rng.small_int() % 7) as i32;
    sim.print(sim.acc.wrapping_add(offset));
    src.push_str("    print(");
    src.push_str(acc_name);
    src.push_str(" + ");
    src.push_str(&offset.to_string());
    src.push_str(");\n");
    1
}

fn push_bool_let_chunk(
    src: &mut String,
    chunk: usize,
    rng: &mut DeterministicRng,
    expected_stdout: &mut String,
) -> usize {
    let a = rng.small_int();
    let b = rng.small_int();
    if chunk % 32 != 0 {
        let c = rng.small_int();
        let d = rng.small_int();
        append_expected_print(expected_stdout, if a < b && c != d { a } else { b } as i32);
        src.push_str(&format!("if (({a} < {b}) && !({c} == {d})) {{\n"));
        src.push_str(&format!("    print({a});\n"));
        src.push_str("} else {\n");
        src.push_str(&format!("    print({b});\n"));
        src.push_str("}\n");
        return 5;
    }

    let c = rng.small_int();
    let d = rng.small_int();
    append_expected_print(expected_stdout, if a < b && c != d { a } else { b } as i32);
    src.push_str(&format!(
        "let flag{chunk}: bool = ({a} < {b}) && !({c} == {d});\n"
    ));
    src.push_str(&format!("if (flag{chunk}) {{\n"));
    src.push_str(&format!("    print({a});\n"));
    src.push_str("} else {\n");
    src.push_str(&format!("    print({b});\n"));
    src.push_str("}\n");
    6
}

fn push_if_else_chunk(
    src: &mut String,
    chunk: usize,
    rng: &mut DeterministicRng,
    expected_stdout: &mut String,
) -> usize {
    let a = rng.small_int();
    let b = rng.small_int();
    append_expected_print(expected_stdout, if a <= b || b == a { a } else { b } as i32);
    src.push_str(&format!("if (({a} <= {b}) || !({b} != {a})) {{\n"));
    src.push_str(&format!("    print({a});\n"));
    src.push_str("} else {\n");
    src.push_str(&format!("    print({b});\n"));
    src.push_str("}\n");
    let _ = chunk;
    5
}

fn push_arithmetic_chunk(
    src: &mut String,
    chunk: usize,
    rng: &mut DeterministicRng,
    expected_stdout: &mut String,
) -> usize {
    let a = rng.small_int();
    let b = rng.small_int();
    let c = rng.small_int();
    let d = rng.small_int();
    match chunk % 3 {
        0 => {
            append_expected_print(
                expected_stdout,
                (a as i32)
                    .wrapping_add(b as i32)
                    .wrapping_mul((c as i32).wrapping_sub(d as i32)),
            );
            src.push_str(&format!(
                "let mix{chunk}: i32 = ({} + {}) * ({} - {});\n",
                a, b, c, d
            ));
            src.push_str(&format!("print(mix{chunk});\n"));
        }
        1 => {
            append_expected_print(expected_stdout, ((a & b) | (c ^ d)) as i32);
            src.push_str(&format!(
                "let mix{chunk}: i32 = ({} & {}) | ({} ^ {});\n",
                a, b, c, d
            ));
            src.push_str(&format!("print(mix{chunk});\n"));
        }
        _ => {
            append_expected_print(
                expected_stdout,
                ((a << 1).wrapping_add(b >> 1).wrapping_add(c)) as i32,
            );
            src.push_str(&format!(
                "let mix{chunk}: i32 = ({} << 1) + ({} >> 1);\n",
                a, b
            ));
            src.push_str(&format!("print(mix{chunk} + {});\n", c));
        }
    }
    2
}

fn push_compare_print_chunk(
    src: &mut String,
    chunk: usize,
    rng: &mut DeterministicRng,
    expected_stdout: &mut String,
) -> usize {
    let a = rng.small_int();
    let b = rng.small_int();
    let c = rng.small_int();
    append_expected_print(expected_stdout, if a >= b || a == c { a } else { c } as i32);
    src.push_str(&format!("if (({a} >= {b}) || ({a} == {c})) {{\n"));
    src.push_str(&format!("    print({a});\n"));
    src.push_str("} else {\n");
    src.push_str(&format!("    print({c});\n"));
    src.push_str("}\n");
    let _ = chunk;
    5
}

fn push_logic_chunk(
    src: &mut String,
    chunk: usize,
    rng: &mut DeterministicRng,
    expected_stdout: &mut String,
) -> usize {
    let a = rng.small_int();
    let b = rng.small_int();
    let c = rng.small_int();
    append_expected_print(expected_stdout, if a <= b || b > c { b } else { c } as i32);
    src.push_str(&format!("if (({a} <= {b}) || ({b} > {c})) {{\n"));
    src.push_str(&format!("    print({b});\n"));
    src.push_str("} else {\n");
    src.push_str(&format!("    print({c});\n"));
    src.push_str("}\n");
    let _ = chunk;
    5
}

#[derive(Clone)]
struct GeneratedFunction {
    name: String,
    arity: usize,
    body: Option<Rc<GeneratedFunctionBody>>,
}

#[derive(Clone)]
enum GeneratedFunctionBody {
    Return(GeneratedExpr),
    LessBranch {
        left: GeneratedExpr,
        right: GeneratedExpr,
        then_expr: GeneratedExpr,
        else_expr: GeneratedExpr,
    },
}

#[derive(Clone)]
enum GeneratedExpr {
    Literal(i32),
    Param(usize),
    Add(Box<GeneratedExpr>, Box<GeneratedExpr>),
    Sub(Box<GeneratedExpr>, Box<GeneratedExpr>),
    Mul(Box<GeneratedExpr>, Box<GeneratedExpr>),
    Shl1(Box<GeneratedExpr>),
    BitAnd(Box<GeneratedExpr>, Box<GeneratedExpr>),
    BitOr(Box<GeneratedExpr>, Box<GeneratedExpr>),
    Call {
        function: GeneratedFunction,
        args: Vec<GeneratedExpr>,
    },
}

impl GeneratedFunction {
    fn source_call(&self, args: &[GeneratedExpr], params: &[String]) -> String {
        let mut out = String::new();
        out.push_str(&self.name);
        out.push('(');
        for (arg_i, arg) in args.iter().enumerate() {
            if arg_i != 0 {
                out.push_str(", ");
            }
            out.push_str(&arg.source(params));
        }
        out.push(')');
        out
    }

    fn eval(&self, args: &[i32]) -> i32 {
        assert_eq!(args.len(), self.arity, "generator oracle arity mismatch");
        match self
            .body
            .as_ref()
            .expect("generator oracle missing generated body")
            .as_ref()
        {
            GeneratedFunctionBody::Return(expr) => expr.eval(args),
            GeneratedFunctionBody::LessBranch {
                left,
                right,
                then_expr,
                else_expr,
            } => {
                if left.eval(args) < right.eval(args) {
                    then_expr.eval(args)
                } else {
                    else_expr.eval(args)
                }
            }
        }
    }
}

impl GeneratedExpr {
    fn binary_source(
        lhs: &GeneratedExpr,
        op: &str,
        rhs: &GeneratedExpr,
        params: &[String],
    ) -> String {
        format!("({} {op} {})", lhs.source(params), rhs.source(params))
    }

    fn source(&self, params: &[String]) -> String {
        match self {
            GeneratedExpr::Literal(value) => value.to_string(),
            GeneratedExpr::Param(index) => params[*index].clone(),
            GeneratedExpr::Add(lhs, rhs) => Self::binary_source(lhs, "+", rhs, params),
            GeneratedExpr::Sub(lhs, rhs) => Self::binary_source(lhs, "-", rhs, params),
            GeneratedExpr::Mul(lhs, rhs) => Self::binary_source(lhs, "*", rhs, params),
            GeneratedExpr::Shl1(expr) => format!("({} << 1)", expr.source(params)),
            GeneratedExpr::BitAnd(lhs, rhs) => Self::binary_source(lhs, "&", rhs, params),
            GeneratedExpr::BitOr(lhs, rhs) => Self::binary_source(lhs, "|", rhs, params),
            GeneratedExpr::Call { function, args } => function.source_call(args, params),
        }
    }

    fn eval(&self, params: &[i32]) -> i32 {
        match self {
            GeneratedExpr::Literal(value) => *value,
            GeneratedExpr::Param(index) => params[*index],
            GeneratedExpr::Add(lhs, rhs) => lhs.eval(params).wrapping_add(rhs.eval(params)),
            GeneratedExpr::Sub(lhs, rhs) => lhs.eval(params).wrapping_sub(rhs.eval(params)),
            GeneratedExpr::Mul(lhs, rhs) => lhs.eval(params).wrapping_mul(rhs.eval(params)),
            GeneratedExpr::Shl1(expr) => expr.eval(params).wrapping_shl(1),
            GeneratedExpr::BitAnd(lhs, rhs) => lhs.eval(params) & rhs.eval(params),
            GeneratedExpr::BitOr(lhs, rhs) => lhs.eval(params) | rhs.eval(params),
            GeneratedExpr::Call { function, args } => {
                let arg_values = args.iter().map(|arg| arg.eval(params)).collect::<Vec<_>>();
                function.eval(&arg_values)
            }
        }
    }
}

fn generated_add(lhs: GeneratedExpr, rhs: GeneratedExpr) -> GeneratedExpr {
    GeneratedExpr::Add(Box::new(lhs), Box::new(rhs))
}

fn generated_mul(lhs: GeneratedExpr, rhs: GeneratedExpr) -> GeneratedExpr {
    GeneratedExpr::Mul(Box::new(lhs), Box::new(rhs))
}

fn generated_sum(mut exprs: Vec<GeneratedExpr>) -> GeneratedExpr {
    let first = exprs.remove(0);
    exprs.into_iter().fold(first, generated_add)
}

fn generated_score_pair(left: GeneratedExpr, right: GeneratedExpr) -> GeneratedExpr {
    generated_add(generated_mul(left, GeneratedExpr::Literal(3)), right)
}

fn make_call_graph_source_artifact(
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> SourceArtifact {
    let mut functions = String::with_capacity(target_bytes.unwrap_or(lines.saturating_mul(64)));
    let mut main_body = String::with_capacity(lines.saturating_mul(24).min(64 * 1024));
    let mut rng = DeterministicRng::new(seed);
    let mut generated: Vec<GeneratedFunction> = Vec::new();
    let mut expected_stdout = String::new();
    let mut line_count = 3usize;
    let mut chunk = 0usize;

    loop {
        let projected_len = functions
            .len()
            .saturating_add(main_body.len())
            .saturating_add(32);
        if target_bytes.is_some_and(|target| projected_len >= target)
            || target_bytes.is_none() && line_count >= lines
        {
            break;
        }

        let prior = (!generated.is_empty()).then(|| {
            let index = rng.index(generated.len());
            generated[index].clone()
        });
        let (function, function_lines) =
            push_call_graph_function(&mut functions, chunk, prior.as_ref(), &mut rng);
        line_count += function_lines;
        let call = generated_call_expr(&function, chunk + 7, &mut rng);
        let expected = call.eval(&[]);
        expected_stdout.push_str(&expected.to_string());
        expected_stdout.push('\n');
        main_body.push_str("    print(");
        main_body.push_str(&call.source(&[]));
        main_body.push_str(");\n");
        line_count += 1;
        generated.push(function);
        chunk += 1;
    }

    let mut src = String::with_capacity(
        functions
            .len()
            .saturating_add(main_body.len())
            .saturating_add(32),
    );
    src.push_str(&functions);
    src.push_str("fn main() {\n");
    src.push_str(&main_body);
    src.push_str("    return 0;\n");
    src.push_str("}\n");
    SourceArtifact {
        source: src,
        expected_stdout: Some(expected_stdout),
    }
}

fn push_call_graph_function(
    src: &mut String,
    chunk: usize,
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunction, usize) {
    let arity = match chunk % 4 {
        0 => 0,
        1 => 1,
        2 => 2,
        _ => 3,
    };
    let name = varied_short_ident("f", chunk, rng);
    let params = call_graph_params(chunk, arity, rng);

    src.push_str("fn ");
    src.push_str(&name);
    src.push('(');
    for param_i in 0..arity {
        if param_i != 0 {
            src.push_str(", ");
        }
        src.push_str(&params[param_i]);
        src.push_str(": i32");
    }
    src.push_str(") -> i32 {\n");
    let (body, body_lines) = push_call_graph_function_body(src, chunk, arity, &params, prior, rng);
    src.push_str("}\n");

    (
        GeneratedFunction {
            name,
            arity,
            body: Some(Rc::new(body)),
        },
        body_lines + 2,
    )
}

fn call_graph_params(chunk: usize, arity: usize, rng: &mut DeterministicRng) -> Vec<String> {
    (0..arity)
        .map(|param_i| {
            varied_short_ident("p", chunk.saturating_mul(4).saturating_add(param_i), rng)
        })
        .collect()
}

fn call_graph_return_generated_expr(
    chunk: usize,
    arity: usize,
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> GeneratedExpr {
    if let Some(prior) = prior
        && chunk % 5 == 4
    {
        let base = generated_call_expr(prior, chunk + 3, rng);
        return if arity == 0 {
            base
        } else {
            GeneratedExpr::Add(Box::new(base), Box::new(GeneratedExpr::Param(0)))
        };
    }

    match arity {
        0 => {
            let a = (rng.small_int() % 64) as i32;
            let b = (rng.small_int() % 64) as i32;
            GeneratedExpr::Add(
                Box::new(GeneratedExpr::Literal(a)),
                Box::new(GeneratedExpr::Literal(b)),
            )
        }
        1 => {
            let a = (rng.small_int() % 64) as i32;
            match chunk % 3 {
                0 => GeneratedExpr::Param(0),
                1 => GeneratedExpr::Add(
                    Box::new(GeneratedExpr::Param(0)),
                    Box::new(GeneratedExpr::Literal(a)),
                ),
                _ => GeneratedExpr::Add(
                    Box::new(GeneratedExpr::Shl1(Box::new(GeneratedExpr::Param(0)))),
                    Box::new(GeneratedExpr::Literal(a)),
                ),
            }
        }
        2 => match chunk % 3 {
            0 => GeneratedExpr::Add(
                Box::new(GeneratedExpr::Param(0)),
                Box::new(GeneratedExpr::Param(1)),
            ),
            1 => GeneratedExpr::Sub(
                Box::new(GeneratedExpr::Param(0)),
                Box::new(GeneratedExpr::Param(1)),
            ),
            _ => GeneratedExpr::Mul(
                Box::new(GeneratedExpr::Param(0)),
                Box::new(GeneratedExpr::Param(1)),
            ),
        },
        _ => match chunk % 3 {
            0 => GeneratedExpr::Sub(
                Box::new(GeneratedExpr::Add(
                    Box::new(GeneratedExpr::Param(0)),
                    Box::new(GeneratedExpr::Param(1)),
                )),
                Box::new(GeneratedExpr::Param(2)),
            ),
            1 => GeneratedExpr::BitOr(
                Box::new(GeneratedExpr::BitAnd(
                    Box::new(GeneratedExpr::Param(0)),
                    Box::new(GeneratedExpr::Param(1)),
                )),
                Box::new(GeneratedExpr::Param(2)),
            ),
            _ => GeneratedExpr::Sub(
                Box::new(GeneratedExpr::Add(
                    Box::new(GeneratedExpr::Param(0)),
                    Box::new(GeneratedExpr::Shl1(Box::new(GeneratedExpr::Param(1)))),
                )),
                Box::new(GeneratedExpr::Param(2)),
            ),
        },
    }
}

fn push_call_graph_function_body(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    if arity >= 2 && chunk % 11 == 5 {
        let then_expr = call_graph_return_generated_expr(chunk + 1, arity, prior, rng);
        let else_expr = call_graph_return_generated_expr(chunk + 2, arity, prior, rng);
        src.push_str("    if (");
        src.push_str(&params[0]);
        src.push_str(" < ");
        src.push_str(&params[1]);
        src.push_str(") {\n        return ");
        src.push_str(&then_expr.source(params));
        src.push_str(";\n    } else {\n        return ");
        src.push_str(&else_expr.source(params));
        src.push_str(";\n    }\n");
        return (
            GeneratedFunctionBody::LessBranch {
                left: GeneratedExpr::Param(0),
                right: GeneratedExpr::Param(1),
                then_expr,
                else_expr,
            },
            5,
        );
    }

    if arity >= 1 && chunk % 7 == 3 {
        let local = varied_short_ident("t", chunk, rng);
        let init = call_graph_return_generated_expr(chunk + 3, arity, prior, rng);
        let bump = (rng.small_int() % 9) as i32;
        src.push_str("    let ");
        src.push_str(&local);
        src.push_str(": i32 = ");
        src.push_str(&init.source(params));
        src.push_str(";\n    return ");
        src.push_str(&local);
        src.push_str(" + ");
        src.push_str(&bump.to_string());
        src.push_str(";\n");
        return (
            GeneratedFunctionBody::Return(GeneratedExpr::Add(
                Box::new(init),
                Box::new(GeneratedExpr::Literal(bump)),
            )),
            2,
        );
    }

    if arity >= 1 && chunk % 13 == 6 {
        let local = varied_short_ident("a", chunk, rng);
        let bump = (rng.small_int() % 7) as i32;
        src.push_str("    let ");
        src.push_str(&local);
        src.push_str(": i32 = ");
        src.push_str(&params[0]);
        src.push_str(";\n    ");
        src.push_str(&local);
        src.push_str(" += ");
        src.push_str(&bump.to_string());
        src.push_str(";\n    return ");
        src.push_str(&local);
        src.push_str(";\n");
        return (
            GeneratedFunctionBody::Return(GeneratedExpr::Add(
                Box::new(GeneratedExpr::Param(0)),
                Box::new(GeneratedExpr::Literal(bump)),
            )),
            3,
        );
    }

    let expr = call_graph_return_generated_expr(chunk, arity, prior, rng);
    src.push_str("    return ");
    src.push_str(&expr.source(params));
    src.push_str(";\n");
    (GeneratedFunctionBody::Return(expr), 1)
}

fn generated_call_expr(
    function: &GeneratedFunction,
    salt: usize,
    rng: &mut DeterministicRng,
) -> GeneratedExpr {
    let mut args = Vec::with_capacity(function.arity);
    for arg_i in 0..function.arity {
        let value = ((salt + arg_i) as u32).wrapping_add(rng.small_int()) % 64;
        let value_expr = GeneratedExpr::Literal(value as i32);
        if arg_i % 3 == 2 {
            let rhs = (rng.small_int() % 8) as i32;
            let factor = (rng.small_int() % 8 + 1) as i32;
            let offset = (rng.small_int() % 4) as i32;
            args.push(GeneratedExpr::Mul(
                Box::new(GeneratedExpr::Add(
                    Box::new(value_expr),
                    Box::new(GeneratedExpr::Literal(rhs)),
                )),
                Box::new(GeneratedExpr::Sub(
                    Box::new(GeneratedExpr::Literal(factor)),
                    Box::new(GeneratedExpr::Literal(offset)),
                )),
            ));
        } else if arg_i % 2 == 0 {
            args.push(value_expr);
        } else {
            let rhs = (rng.small_int() % 8) as i32;
            args.push(GeneratedExpr::Add(
                Box::new(value_expr),
                Box::new(GeneratedExpr::Literal(rhs)),
            ));
        }
    }
    GeneratedExpr::Call {
        function: function.clone(),
        args,
    }
}

fn make_expr_dense_source_artifact(
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> SourceArtifact {
    let mut functions = String::with_capacity(target_bytes.unwrap_or(lines.saturating_mul(96)));
    let mut main_body = String::with_capacity(lines.saturating_mul(32).min(96 * 1024));
    let mut rng = DeterministicRng::new(seed ^ 0x0e95_dede_5eed);
    let mut generated = Vec::<GeneratedFunction>::new();
    let mut expected_stdout = String::new();
    let mut line_count = 3usize;
    let mut chunk = 0usize;

    loop {
        let projected_len = functions
            .len()
            .saturating_add(main_body.len())
            .saturating_add(32);
        if target_bytes.is_some_and(|target| projected_len >= target)
            || target_bytes.is_none() && line_count >= lines
        {
            break;
        }

        let prior = (!generated.is_empty()).then(|| {
            let index = rng.index(generated.len());
            generated[index].clone()
        });
        let (function, function_lines) =
            push_expr_dense_function(&mut functions, chunk, prior.as_ref(), &mut rng);
        line_count += function_lines;

        let call = generated_call_expr(&function, chunk + 97, &mut rng);
        append_expected_print(&mut expected_stdout, call.eval(&[]));
        main_body.push_str("    print(");
        main_body.push_str(&call.source(&[]));
        main_body.push_str(");\n");
        line_count += 1;

        generated.push(function);
        chunk += 1;
    }

    let mut src = String::with_capacity(
        functions
            .len()
            .saturating_add(main_body.len())
            .saturating_add(32),
    );
    src.push_str(&functions);
    src.push_str("fn main() {\n");
    src.push_str(&main_body);
    src.push_str("    return 0;\n");
    src.push_str("}\n");
    SourceArtifact {
        source: src,
        expected_stdout: Some(expected_stdout),
    }
}

fn push_expr_dense_function(
    src: &mut String,
    chunk: usize,
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunction, usize) {
    let arity = 1 + rng.index(4);
    let name = varied_short_ident("xd", chunk, rng);
    let params = (0..arity)
        .map(|param_i| {
            varied_short_ident(
                "xp",
                chunk.saturating_mul(8).saturating_add(param_i),
                rng,
            )
        })
        .collect::<Vec<_>>();

    src.push_str("fn ");
    src.push_str(&name);
    src.push('(');
    for (param_i, param) in params.iter().enumerate() {
        if param_i != 0 {
            src.push_str(", ");
        }
        src.push_str(param);
        src.push_str(": i32");
    }
    src.push_str(") -> i32 {\n");

    let (body, body_lines) = if arity >= 2 && chunk % 5 == 2 {
        push_expr_dense_branch_body(src, chunk, arity, &params, prior, rng)
    } else if chunk % 4 == 1 {
        push_expr_dense_local_body(src, chunk, arity, &params, prior, rng)
    } else {
        let expr = expr_dense_generated_expr(chunk, 4, arity, prior, rng);
        src.push_str("    return ");
        src.push_str(&expr.source(&params));
        src.push_str(";\n");
        (GeneratedFunctionBody::Return(expr), 1)
    };
    src.push_str("}\n");

    (
        GeneratedFunction {
            name,
            arity,
            body: Some(Rc::new(body)),
        },
        body_lines + 2,
    )
}

fn push_expr_dense_branch_body(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let left = expr_dense_generated_expr(chunk + 11, 2, arity, prior, rng);
    let right = expr_dense_generated_expr(chunk + 17, 2, arity, prior, rng);
    let then_expr = expr_dense_generated_expr(chunk + 23, 3, arity, prior, rng);
    let else_expr = expr_dense_generated_expr(chunk + 29, 3, arity, prior, rng);

    src.push_str("    if (");
    src.push_str(&left.source(params));
    src.push_str(" < ");
    src.push_str(&right.source(params));
    src.push_str(") {\n        return ");
    src.push_str(&then_expr.source(params));
    src.push_str(";\n    } else {\n        return ");
    src.push_str(&else_expr.source(params));
    src.push_str(";\n    }\n");

    (
        GeneratedFunctionBody::LessBranch {
            left,
            right,
            then_expr,
            else_expr,
        },
        5,
    )
}

fn push_expr_dense_local_body(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let local = varied_short_ident("xl", chunk, rng);
    let seed_expr = expr_dense_generated_expr(chunk + 31, 3, arity, prior, rng);
    let bump = ((rng.small_int() % 17) as i32) - 8;
    let return_expr = GeneratedExpr::Sub(
        Box::new(GeneratedExpr::Add(
            Box::new(seed_expr.clone()),
            Box::new(GeneratedExpr::Literal(bump)),
        )),
        Box::new(GeneratedExpr::Param(chunk % arity)),
    );

    src.push_str("    let ");
    src.push_str(&local);
    src.push_str(": i32 = ");
    src.push_str(&seed_expr.source(params));
    src.push_str(";\n    return (");
    src.push_str(&local);
    src.push_str(" + ");
    src.push_str(&bump.to_string());
    src.push_str(") - ");
    src.push_str(&params[chunk % arity]);
    src.push_str(";\n");

    (GeneratedFunctionBody::Return(return_expr), 2)
}

fn expr_dense_generated_expr(
    salt: usize,
    depth: usize,
    arity: usize,
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> GeneratedExpr {
    if depth == 0 {
        return expr_dense_leaf(salt, arity, rng);
    }

    if let Some(prior) = prior
        && salt % 7 == 3
    {
        return expr_dense_prior_call(prior, salt, depth, arity, rng);
    }

    match (rng.small_int() as usize + salt + depth) % 7 {
        0 => GeneratedExpr::Add(
            Box::new(expr_dense_generated_expr(salt + 1, depth - 1, arity, prior, rng)),
            Box::new(expr_dense_generated_expr(salt + 9, depth - 1, arity, prior, rng)),
        ),
        1 => GeneratedExpr::Sub(
            Box::new(expr_dense_generated_expr(salt + 1, depth - 1, arity, prior, rng)),
            Box::new(expr_dense_generated_expr(salt + 9, depth - 1, arity, prior, rng)),
        ),
        2 => GeneratedExpr::Mul(
            Box::new(expr_dense_generated_expr(salt + 1, depth - 1, arity, prior, rng)),
            Box::new(expr_dense_generated_expr(salt + 9, depth - 1, arity, prior, rng)),
        ),
        3 => GeneratedExpr::BitAnd(
            Box::new(expr_dense_generated_expr(salt + 1, depth - 1, arity, prior, rng)),
            Box::new(expr_dense_generated_expr(salt + 9, depth - 1, arity, prior, rng)),
        ),
        4 => GeneratedExpr::BitOr(
            Box::new(expr_dense_generated_expr(salt + 1, depth - 1, arity, prior, rng)),
            Box::new(expr_dense_generated_expr(salt + 9, depth - 1, arity, prior, rng)),
        ),
        5 => GeneratedExpr::Shl1(Box::new(expr_dense_generated_expr(
            salt + 1,
            depth - 1,
            arity,
            prior,
            rng,
        ))),
        _ => generated_add(
            expr_dense_generated_expr(salt + 5, depth - 1, arity, prior, rng),
            GeneratedExpr::Literal(((rng.small_int() % 19) as i32) - 9),
        ),
    }
}

fn expr_dense_leaf(salt: usize, arity: usize, rng: &mut DeterministicRng) -> GeneratedExpr {
    if arity != 0 && salt % 3 != 0 {
        GeneratedExpr::Param(salt % arity)
    } else {
        GeneratedExpr::Literal(((rng.small_int() % 31) as i32) - 15)
    }
}

fn expr_dense_prior_call(
    prior: &GeneratedFunction,
    salt: usize,
    depth: usize,
    arity: usize,
    rng: &mut DeterministicRng,
) -> GeneratedExpr {
    let args = (0..prior.arity)
        .map(|arg_i| {
            expr_dense_generated_expr(
                salt.saturating_add(arg_i).saturating_add(37),
                depth.saturating_sub(1).min(2),
                arity,
                None,
                rng,
            )
        })
        .collect::<Vec<_>>();
    GeneratedExpr::Call {
        function: prior.clone(),
        args,
    }
}

fn make_abi_call_source_artifact(
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> SourceArtifact {
    let mut functions = String::with_capacity(target_bytes.unwrap_or(lines.saturating_mul(76)));
    let mut main_body = String::with_capacity(lines.saturating_mul(28).min(96 * 1024));
    let mut rng = DeterministicRng::new(seed ^ 0xaba1_c011_5eed);
    let mut generated: Vec<GeneratedFunction> = Vec::new();
    let mut expected_stdout = String::new();
    let mut line_count = 3usize;
    let mut chunk = 0usize;

    loop {
        let projected_len = functions
            .len()
            .saturating_add(main_body.len())
            .saturating_add(32);
        if target_bytes.is_some_and(|target| projected_len >= target)
            || target_bytes.is_none() && line_count >= lines
        {
            break;
        }

        let prior = (!generated.is_empty()).then(|| {
            let index = rng.index(generated.len());
            generated[index].clone()
        });
        let (function, function_lines) =
            push_abi_call_function(&mut functions, chunk, prior.as_ref(), &mut rng);
        line_count += function_lines;

        let call = generated_call_expr(&function, chunk + 31, &mut rng);
        let printed = if let Some(prior) = prior.as_ref()
            && chunk % 4 == 1
        {
            let prior_call = generated_call_expr(prior, chunk + 37, &mut rng);
            generated_add(call, prior_call)
        } else {
            call
        };
        expected_stdout.push_str(&printed.eval(&[]).to_string());
        expected_stdout.push('\n');
        main_body.push_str("    print(");
        main_body.push_str(&printed.source(&[]));
        main_body.push_str(");\n");
        line_count += 1;
        generated.push(function);
        chunk += 1;
    }

    let mut src = String::with_capacity(
        functions
            .len()
            .saturating_add(main_body.len())
            .saturating_add(32),
    );
    src.push_str(&functions);
    src.push_str("fn main() {\n");
    src.push_str(&main_body);
    src.push_str("    return 0;\n");
    src.push_str("}\n");
    SourceArtifact {
        source: src,
        expected_stdout: Some(expected_stdout),
    }
}

fn push_abi_call_function(
    src: &mut String,
    chunk: usize,
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunction, usize) {
    let arity = chunk % 5;
    let name = varied_short_ident("abi", chunk, rng);
    let params = abi_call_params(chunk, arity, rng);

    src.push_str("fn ");
    src.push_str(&name);
    src.push('(');
    for param_i in 0..arity {
        if param_i != 0 {
            src.push_str(", ");
        }
        src.push_str(&params[param_i]);
        src.push_str(": i32");
    }
    src.push_str(") -> i32 {\n");
    let (body, body_lines) = push_abi_call_function_body(src, chunk, arity, &params, prior, rng);
    src.push_str("}\n");

    (
        GeneratedFunction {
            name,
            arity,
            body: Some(Rc::new(body)),
        },
        body_lines + 2,
    )
}

fn abi_call_params(chunk: usize, arity: usize, rng: &mut DeterministicRng) -> Vec<String> {
    (0..arity)
        .map(|param_i| {
            varied_short_ident("ap", chunk.saturating_mul(5).saturating_add(param_i), rng)
        })
        .collect()
}

fn push_abi_call_function_body(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    if arity >= 2 && chunk % 9 == 4 {
        let then_expr = abi_call_return_expr(chunk + 1, arity, prior, rng);
        let else_expr = abi_call_return_expr(chunk + 2, arity, prior, rng);
        src.push_str("    if (");
        src.push_str(&params[0]);
        src.push_str(" < ");
        src.push_str(&params[1]);
        src.push_str(") {\n        return ");
        src.push_str(&then_expr.source(params));
        src.push_str(";\n    } else {\n        return ");
        src.push_str(&else_expr.source(params));
        src.push_str(";\n    }\n");
        return (
            GeneratedFunctionBody::LessBranch {
                left: GeneratedExpr::Param(0),
                right: GeneratedExpr::Param(1),
                then_expr,
                else_expr,
            },
            5,
        );
    }

    if arity >= 3 && chunk % 7 == 2 {
        let local = varied_short_ident("al", chunk, rng);
        let expr = abi_call_return_expr(chunk + 3, arity, prior, rng);
        let bump = (rng.small_int() % 11) as i32;
        src.push_str("    let ");
        src.push_str(&local);
        src.push_str(": i32 = ");
        src.push_str(&expr.source(params));
        src.push_str(";\n    return ");
        src.push_str(&local);
        src.push_str(" + ");
        src.push_str(&bump.to_string());
        src.push_str(";\n");
        return (
            GeneratedFunctionBody::Return(generated_add(expr, GeneratedExpr::Literal(bump))),
            2,
        );
    }

    let expr = abi_call_return_expr(chunk, arity, prior, rng);
    src.push_str("    return ");
    src.push_str(&expr.source(params));
    src.push_str(";\n");
    (GeneratedFunctionBody::Return(expr), 1)
}

fn abi_call_return_expr(
    chunk: usize,
    arity: usize,
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> GeneratedExpr {
    if let Some(prior) = prior
        && chunk % 4 == 0
    {
        let prior_call = generated_call_expr(prior, chunk + 41, rng);
        return if arity == 0 {
            prior_call
        } else {
            generated_add(prior_call, GeneratedExpr::Param(0))
        };
    }

    match arity {
        0 => GeneratedExpr::Literal((rng.small_int() % 97) as i32),
        1 => generated_add(
            GeneratedExpr::Param(0),
            GeneratedExpr::Literal((chunk % 17) as i32),
        ),
        2 => GeneratedExpr::Sub(
            Box::new(generated_mul(
                GeneratedExpr::Param(0),
                GeneratedExpr::Literal(2),
            )),
            Box::new(GeneratedExpr::Param(1)),
        ),
        3 => generated_add(
            generated_mul(GeneratedExpr::Param(0), GeneratedExpr::Param(1)),
            GeneratedExpr::Param(2),
        ),
        _ => GeneratedExpr::Sub(
            Box::new(generated_add(
                GeneratedExpr::Param(0),
                GeneratedExpr::Param(1),
            )),
            Box::new(generated_mul(
                GeneratedExpr::Param(2),
                GeneratedExpr::Param(3),
            )),
        ),
    }
}

fn make_varied_source_artifact(
    lines: usize,
    target_bytes: Option<usize>,
    seed: u64,
) -> SourceArtifact {
    let mut rng = DeterministicRng::new(seed);
    let names = VariedNames::new(&mut rng);
    let mut functions = String::with_capacity(target_bytes.unwrap_or(lines.saturating_mul(80)));
    let mut main_body = String::with_capacity(lines.saturating_mul(32).min(96 * 1024));
    let mut generated = Vec::<GeneratedFunction>::new();
    let mut expected_stdout = String::new();

    push_varied_prelude(&mut functions, &names);
    let mut line_count = 28usize;
    let mut chunk = 0usize;
    loop {
        let projected_len = functions
            .len()
            .saturating_add(main_body.len())
            .saturating_add(32);
        if target_bytes.is_some_and(|target| projected_len >= target)
            || target_bytes.is_none() && line_count >= lines
        {
            break;
        }

        let prior = (!generated.is_empty()).then(|| {
            let index = rng.index(generated.len());
            generated[index].clone()
        });
        let (function, function_lines) =
            push_varied_function(&mut functions, &names, chunk, prior.as_ref(), &mut rng);
        line_count += function_lines;
        let call = generated_call_expr(&function, chunk + 13, &mut rng);
        let expected = call.eval(&[]);
        expected_stdout.push_str(&expected.to_string());
        expected_stdout.push('\n');
        main_body.push_str("    print(");
        main_body.push_str(&call.source(&[]));
        main_body.push_str(");\n");
        line_count += 1;
        generated.push(function);
        chunk += 1;
    }

    let mut src = String::with_capacity(
        functions
            .len()
            .saturating_add(main_body.len())
            .saturating_add(32),
    );
    src.push_str(&functions);
    src.push_str("fn main() {\n");
    src.push_str(&main_body);
    src.push_str("    return 0;\n");
    src.push_str("}\n");
    SourceArtifact {
        source: src,
        expected_stdout: Some(expected_stdout),
    }
}

struct VariedNames {
    pair_type: String,
    choice_type: String,
    left_field: String,
    right_field: String,
    left_variant: String,
    right_variant: String,
    make_pair_fn: String,
    score_pair_fn: String,
    sum4_fn: String,
    pick_fn: String,
    make_left_param: String,
    make_right_param: String,
    score_param: String,
    sum_param: String,
    pick_values_param: String,
    pick_len_param: String,
    pick_index_param: String,
    pick_fallback_param: String,
}

impl VariedNames {
    fn new(rng: &mut DeterministicRng) -> Self {
        Self {
            pair_type: varied_short_ident("t", 0, rng),
            choice_type: varied_short_ident("e", 15, rng),
            left_field: varied_short_ident("f", 1, rng),
            right_field: varied_short_ident("f", 2, rng),
            left_variant: varied_short_ident("v", 16, rng),
            right_variant: varied_short_ident("v", 17, rng),
            make_pair_fn: varied_short_ident("g", 3, rng),
            score_pair_fn: varied_short_ident("g", 4, rng),
            sum4_fn: varied_short_ident("g", 5, rng),
            pick_fn: varied_short_ident("g", 6, rng),
            make_left_param: varied_short_ident("p", 7, rng),
            make_right_param: varied_short_ident("p", 8, rng),
            score_param: varied_short_ident("p", 9, rng),
            sum_param: varied_short_ident("p", 10, rng),
            pick_values_param: varied_short_ident("p", 11, rng),
            pick_len_param: varied_short_ident("p", 12, rng),
            pick_index_param: varied_short_ident("p", 13, rng),
            pick_fallback_param: varied_short_ident("p", 14, rng),
        }
    }
}

fn varied_short_ident(prefix: &str, salt: usize, rng: &mut DeterministicRng) -> String {
    format!("{prefix}{salt:x}_{:03x}", rng.next_u32() & 0xfff)
}

fn varied_short_params(chunk: usize, arity: usize, rng: &mut DeterministicRng) -> Vec<String> {
    (0..arity)
        .map(|param_i| {
            varied_short_ident("p", chunk.saturating_mul(8).saturating_add(param_i), rng)
        })
        .collect()
}

fn push_varied_prelude(src: &mut String, names: &VariedNames) {
    src.push_str("enum ");
    src.push_str(&names.choice_type);
    src.push_str(" {\n    ");
    src.push_str(&names.left_variant);
    src.push_str(",\n    ");
    src.push_str(&names.right_variant);
    src.push_str(",\n}\n");

    src.push_str("struct ");
    src.push_str(&names.pair_type);
    src.push_str(" {\n    ");
    src.push_str(&names.left_field);
    src.push_str(": i32,\n    ");
    src.push_str(&names.right_field);
    src.push_str(": i32,\n}\n");

    src.push_str("fn ");
    src.push_str(&names.make_pair_fn);
    src.push('(');
    src.push_str(&names.make_left_param);
    src.push_str(": i32, ");
    src.push_str(&names.make_right_param);
    src.push_str(": i32) -> ");
    src.push_str(&names.pair_type);
    src.push_str(" {\n    return ");
    src.push_str(&names.pair_type);
    src.push_str(" { ");
    src.push_str(&names.left_field);
    src.push_str(": ");
    src.push_str(&names.make_left_param);
    src.push_str(", ");
    src.push_str(&names.right_field);
    src.push_str(": ");
    src.push_str(&names.make_right_param);
    src.push_str(" };\n}\n");

    src.push_str("fn ");
    src.push_str(&names.score_pair_fn);
    src.push('(');
    src.push_str(&names.score_param);
    src.push_str(": ");
    src.push_str(&names.pair_type);
    src.push_str(") -> i32 {\n    return ");
    src.push_str(&names.score_param);
    src.push('.');
    src.push_str(&names.left_field);
    src.push_str(" * 3 + ");
    src.push_str(&names.score_param);
    src.push('.');
    src.push_str(&names.right_field);
    src.push_str(";\n}\n");

    src.push_str("fn ");
    src.push_str(&names.sum4_fn);
    src.push('(');
    src.push_str(&names.sum_param);
    src.push_str(": [i32; 4]) -> i32 {\n    return ");
    src.push_str(&names.sum_param);
    src.push_str("[0] + ");
    src.push_str(&names.sum_param);
    src.push_str("[1] + ");
    src.push_str(&names.sum_param);
    src.push_str("[2] + ");
    src.push_str(&names.sum_param);
    src.push_str("[3];\n}\n");

    src.push_str("fn ");
    src.push_str(&names.pick_fn);
    src.push('(');
    src.push_str(&names.pick_values_param);
    src.push_str(": [i32], ");
    src.push_str(&names.pick_len_param);
    src.push_str(": i32, ");
    src.push_str(&names.pick_index_param);
    src.push_str(": i32, ");
    src.push_str(&names.pick_fallback_param);
    src.push_str(": i32) -> i32 {\n    if (");
    src.push_str(&names.pick_index_param);
    src.push_str(" >= ");
    src.push_str(&names.pick_len_param);
    src.push_str(") {\n        return ");
    src.push_str(&names.pick_fallback_param);
    src.push_str(";\n    } else {\n        return ");
    src.push_str(&names.pick_values_param);
    src.push('[');
    src.push_str(&names.pick_index_param);
    src.push_str("];\n    }\n}\n");
}

fn push_varied_function(
    src: &mut String,
    names: &VariedNames,
    chunk: usize,
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunction, usize) {
    let arity = chunk % 5;
    let name = varied_short_ident("h", chunk + 100, rng);
    let params = varied_short_params(chunk + 1000, arity, rng);

    src.push_str("fn ");
    src.push_str(&name);
    src.push('(');
    for param_i in 0..arity {
        if param_i != 0 {
            src.push_str(", ");
        }
        src.push_str(&params[param_i]);
        src.push_str(": i32");
    }
    src.push_str(") -> i32 {\n");
    let (body, body_lines) =
        push_varied_function_body(src, names, chunk, arity, &params, prior, rng);
    src.push_str("}\n");

    (
        GeneratedFunction {
            name,
            arity,
            body: Some(Rc::new(body)),
        },
        body_lines + 2,
    )
}

fn push_varied_function_body(
    src: &mut String,
    names: &VariedNames,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    match chunk % 11 {
        0 => push_varied_scalar_return(src, chunk, arity, params, prior, rng),
        1 => push_varied_branch_return(src, chunk, arity, params, prior, rng),
        2 => push_varied_local_chain(src, names, chunk, arity, params, prior, rng),
        3 => push_varied_array_return(src, names, chunk, arity, params, rng),
        4 => push_varied_struct_return(src, names, chunk, arity, params, rng),
        5 => push_varied_slice_return(src, names, chunk, arity, params, rng),
        6 => push_varied_while_return(src, chunk, arity, params, rng),
        7 => push_varied_for_return(src, chunk, arity, params, rng),
        8 => push_varied_unsigned_branch_return(src, chunk, arity, params, rng),
        9 => push_varied_nested_unsigned_branch_return(src, chunk, arity, params, rng),
        _ => push_varied_enum_match_return(src, names, chunk, arity, params, prior, rng),
    }
}

fn varied_base_generated_expr(
    chunk: usize,
    arity: usize,
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> GeneratedExpr {
    if let Some(prior) = prior
        && chunk % 4 == 0
    {
        let call = generated_call_expr(prior, chunk + 21, rng);
        return if arity == 0 {
            call
        } else {
            GeneratedExpr::Add(Box::new(call), Box::new(GeneratedExpr::Param(0)))
        };
    }
    call_graph_return_generated_expr(chunk, arity, None, rng)
}

fn push_varied_scalar_return(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let expr = varied_base_generated_expr(chunk, arity, prior, rng);
    src.push_str("    return ");
    src.push_str(&expr.source(params));
    src.push_str(";\n");
    (GeneratedFunctionBody::Return(expr), 1)
}

fn push_varied_branch_return(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let left = if arity == 0 {
        GeneratedExpr::Literal((rng.small_int() % 17) as i32)
    } else {
        GeneratedExpr::Param(0)
    };
    let right = GeneratedExpr::Literal((rng.small_int() % 17) as i32);
    let then_expr = varied_base_generated_expr(chunk + 1, arity, prior, rng);
    let else_expr = varied_base_generated_expr(chunk + 2, arity, prior, rng);
    src.push_str("    if (");
    src.push_str(&left.source(params));
    src.push_str(" < ");
    src.push_str(&right.source(params));
    src.push_str(") {\n        return ");
    src.push_str(&then_expr.source(params));
    src.push_str(";\n    } else {\n        return ");
    src.push_str(&else_expr.source(params));
    src.push_str(";\n    }\n");
    (
        GeneratedFunctionBody::LessBranch {
            left,
            right,
            then_expr,
            else_expr,
        },
        5,
    )
}

fn push_varied_local_chain(
    src: &mut String,
    names: &VariedNames,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let local = varied_short_ident("l", chunk, rng);
    let pair = varied_short_ident("q", chunk + 20, rng);
    let base = varied_base_generated_expr(chunk + 3, arity, prior, rng);
    let right = GeneratedExpr::Literal((rng.small_int() % 31) as i32);
    src.push_str("    let ");
    src.push_str(&local);
    src.push_str(": i32 = ");
    src.push_str(&base.source(params));
    src.push_str(";\n    let ");
    src.push_str(&pair);
    src.push_str(": ");
    src.push_str(&names.pair_type);
    src.push_str(" = ");
    src.push_str(&names.make_pair_fn);
    src.push('(');
    src.push_str(&local);
    src.push_str(", ");
    src.push_str(&right.source(params));
    src.push_str(");\n    return ");
    src.push_str(&names.score_pair_fn);
    src.push('(');
    src.push_str(&pair);
    src.push_str(");\n");
    (
        GeneratedFunctionBody::Return(generated_score_pair(base, right)),
        3,
    )
}

fn push_varied_array_return(
    src: &mut String,
    names: &VariedNames,
    chunk: usize,
    arity: usize,
    params: &[String],
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let values = varied_short_ident("a", chunk, rng);
    let head = if arity == 0 {
        GeneratedExpr::Literal((rng.small_int() % 31) as i32)
    } else {
        GeneratedExpr::Param(0)
    };
    let mut elements = vec![head];
    src.push_str("    let ");
    src.push_str(&values);
    src.push_str(": [i32; 4] = [");
    src.push_str(&elements[0].source(params));
    for _ in 1..4 {
        let element = GeneratedExpr::Literal((rng.small_int() % 31) as i32);
        src.push_str(", ");
        src.push_str(&element.source(params));
        elements.push(element);
    }
    src.push_str("];\n    return ");
    src.push_str(&names.sum4_fn);
    src.push('(');
    src.push_str(&values);
    src.push_str(") + ");
    src.push_str(&(chunk % 11).to_string());
    src.push_str(";\n");
    (
        GeneratedFunctionBody::Return(generated_add(
            generated_sum(elements),
            GeneratedExpr::Literal((chunk % 11) as i32),
        )),
        2,
    )
}

fn push_varied_struct_return(
    src: &mut String,
    names: &VariedNames,
    chunk: usize,
    arity: usize,
    params: &[String],
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let pair = varied_short_ident("s", chunk, rng);
    let left = if arity == 0 {
        GeneratedExpr::Literal((rng.small_int() % 23) as i32)
    } else {
        GeneratedExpr::Param(0)
    };
    let right = if arity >= 2 {
        GeneratedExpr::Param(1)
    } else {
        GeneratedExpr::Literal((rng.small_int() % 23) as i32)
    };
    src.push_str("    let ");
    src.push_str(&pair);
    src.push_str(": ");
    src.push_str(&names.pair_type);
    src.push_str(" = ");
    src.push_str(&names.make_pair_fn);
    src.push('(');
    src.push_str(&left.source(params));
    src.push_str(", ");
    src.push_str(&right.source(params));
    src.push_str(");\n    return ");
    src.push_str(&names.score_pair_fn);
    src.push('(');
    src.push_str(&pair);
    src.push_str(");\n");
    (
        GeneratedFunctionBody::Return(generated_score_pair(left, right)),
        2,
    )
}

fn push_varied_slice_return(
    src: &mut String,
    names: &VariedNames,
    chunk: usize,
    arity: usize,
    params: &[String],
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let values = varied_short_ident("q", chunk, rng);
    let fallback = if arity == 0 {
        GeneratedExpr::Literal((rng.small_int() % 29) as i32)
    } else {
        GeneratedExpr::Param(0)
    };
    let mut elements = Vec::with_capacity(4);
    src.push_str("    let ");
    src.push_str(&values);
    src.push_str(": [i32; 4] = [");
    for value_i in 0..4 {
        if value_i != 0 {
            src.push_str(", ");
        }
        let element = GeneratedExpr::Literal((rng.small_int() % 29) as i32);
        src.push_str(&element.source(params));
        elements.push(element);
    }
    src.push_str("];\n    return ");
    src.push_str(&names.pick_fn);
    src.push('(');
    src.push_str(&values);
    src.push_str(", 4, ");
    src.push_str(&(chunk % 6).to_string());
    src.push_str(", ");
    src.push_str(&fallback.source(params));
    src.push_str(");\n");
    let result = elements
        .get(chunk % 6)
        .cloned()
        .unwrap_or_else(|| fallback.clone());
    (GeneratedFunctionBody::Return(result), 2)
}

fn push_varied_while_return(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let index = varied_short_ident("i", chunk, rng);
    let total = varied_short_ident("w", chunk, rng);
    let addend = if arity == 0 {
        GeneratedExpr::Literal((rng.small_int() % 7 + 1) as i32)
    } else {
        GeneratedExpr::Param(0)
    };
    let initial = GeneratedExpr::Literal((rng.small_int() % 11) as i32);
    let limit = (chunk % 5 + 1) as i32;
    src.push_str("    let ");
    src.push_str(&index);
    src.push_str(": i32 = 0;\n    let ");
    src.push_str(&total);
    src.push_str(": i32 = ");
    src.push_str(&initial.source(params));
    src.push_str(";\n    while (");
    src.push_str(&index);
    src.push_str(" < ");
    src.push_str(&limit.to_string());
    src.push_str(") {\n        ");
    src.push_str(&total);
    src.push_str(" += ");
    src.push_str(&addend.source(params));
    src.push_str(";\n        ");
    src.push_str(&index);
    src.push_str(" += 1;\n    }\n    return ");
    src.push_str(&total);
    src.push_str(";\n");
    (
        GeneratedFunctionBody::Return(generated_add(
            initial,
            generated_mul(GeneratedExpr::Literal(limit), addend),
        )),
        7,
    )
}

fn push_varied_for_return(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let values = varied_short_ident("r", chunk, rng);
    let value = varied_short_ident("v", chunk, rng);
    let total = varied_short_ident("u", chunk, rng);
    let head = if arity == 0 {
        GeneratedExpr::Literal((rng.small_int() % 19) as i32)
    } else {
        GeneratedExpr::Param(0)
    };
    let mut elements = vec![head];
    src.push_str("    let ");
    src.push_str(&values);
    src.push_str(": [i32; 4] = [");
    src.push_str(&elements[0].source(params));
    for _ in 1..4 {
        let element = GeneratedExpr::Literal((rng.small_int() % 19) as i32);
        src.push_str(", ");
        src.push_str(&element.source(params));
        elements.push(element);
    }
    src.push_str("];\n    let ");
    src.push_str(&total);
    src.push_str(": i32 = 0;\n    for ");
    src.push_str(&value);
    src.push_str(" in ");
    src.push_str(&values);
    src.push_str(" {\n        ");
    src.push_str(&total);
    src.push_str(" += ");
    src.push_str(&value);
    src.push_str(";\n    }\n    return ");
    src.push_str(&total);
    src.push_str(";\n");
    (GeneratedFunctionBody::Return(generated_sum(elements)), 6)
}

fn push_varied_unsigned_branch_return(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let left = varied_short_ident("u", chunk, rng);
    let right = varied_short_ident("u", chunk + 41, rng);
    let then_expr = if arity == 0 {
        GeneratedExpr::Literal((rng.small_int() % 37) as i32)
    } else {
        GeneratedExpr::Param(0)
    };
    let else_expr = GeneratedExpr::Literal((rng.small_int() % 37) as i32);
    src.push_str("    let ");
    src.push_str(&left);
    src.push_str(": u32 = 4294967295;\n    let ");
    src.push_str(&right);
    src.push_str(": u32 = ");
    src.push_str(&(chunk % 97 + 1).to_string());
    src.push_str(";\n    if (");
    src.push_str(&left);
    src.push_str(" > ");
    src.push_str(&right);
    src.push_str(") {\n        return ");
    src.push_str(&then_expr.source(params));
    src.push_str(";\n    } else {\n        return ");
    src.push_str(&else_expr.source(params));
    src.push_str(";\n    }\n");
    (GeneratedFunctionBody::Return(then_expr), 7)
}

fn push_varied_nested_unsigned_branch_return(
    src: &mut String,
    chunk: usize,
    arity: usize,
    params: &[String],
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let left = varied_short_ident("u", chunk, rng);
    let right = varied_short_ident("u", chunk + 43, rng);
    let depth = 9 + rng.index(8);
    let then_expr = if arity == 0 {
        GeneratedExpr::Literal((rng.small_int() % 37) as i32)
    } else {
        GeneratedExpr::Param(0)
    };
    let else_expr = GeneratedExpr::Literal((rng.small_int() % 37) as i32);
    src.push_str("    let ");
    src.push_str(&left);
    src.push_str(": u32 = 4294967295;\n    let ");
    src.push_str(&right);
    src.push_str(": u32 = ");
    src.push_str(&(chunk % 97 + 1).to_string());
    src.push_str(";\n    if (");
    for _ in 0..depth {
        src.push('(');
    }
    src.push_str(&left);
    for _ in 0..depth {
        src.push_str(" + 0)");
    }
    src.push_str(" > ");
    src.push_str(&right);
    src.push_str(") {\n        return ");
    src.push_str(&then_expr.source(params));
    src.push_str(";\n    } else {\n        return ");
    src.push_str(&else_expr.source(params));
    src.push_str(";\n    }\n");
    (GeneratedFunctionBody::Return(then_expr), 7)
}

fn push_varied_enum_match_return(
    src: &mut String,
    names: &VariedNames,
    chunk: usize,
    arity: usize,
    params: &[String],
    prior: Option<&GeneratedFunction>,
    rng: &mut DeterministicRng,
) -> (GeneratedFunctionBody, usize) {
    let choice = varied_short_ident("m", chunk, rng);
    let variant = if chunk % 2 == 0 {
        &names.left_variant
    } else {
        &names.right_variant
    };
    let left_expr = varied_base_generated_expr(chunk + 5, arity, prior, rng);
    let right_expr = varied_base_generated_expr(chunk + 6, arity, prior, rng);
    src.push_str("    let ");
    src.push_str(&choice);
    src.push_str(": ");
    src.push_str(&names.choice_type);
    src.push_str(" = ");
    src.push_str(variant);
    src.push_str(";\n    return match (");
    src.push_str(&choice);
    src.push_str(") {\n        ");
    src.push_str(&names.left_variant);
    src.push_str(" -> ");
    src.push_str(&left_expr.source(params));
    src.push_str(",\n        ");
    src.push_str(&names.right_variant);
    src.push_str(" -> ");
    src.push_str(&right_expr.source(params));
    src.push_str(",\n    };\n");
    let result = if chunk % 2 == 0 {
        left_expr
    } else {
        right_expr
    };
    (GeneratedFunctionBody::Return(result), 6)
}

struct DeterministicRng {
    state: u64,
}

impl DeterministicRng {
    fn new(seed: u64) -> Self {
        Self { state: seed | 1 }
    }

    fn next_u32(&mut self) -> u32 {
        self.state = self
            .state
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1);
        (self.state >> 32) as u32
    }

    fn small_int(&mut self) -> u32 {
        self.next_u32() % 64
    }

    fn index(&mut self, len: usize) -> usize {
        (self.next_u32() as usize) % len
    }
}

fn print_help() {
    eprintln!(
        "Usage: gpu_compile_bench [--emit wasm|x86_64-elf] [--source simple-lets|mixed|call-graph|expr-dense|abi-calls|varied|long-function|all] [--lines N] [--target-bytes N] [--seed N] [--warmups N] [--iters N] [--validate-output] [--run-x86-output] [--allow-large] [--estimate-only|--estimate-live] [--dump-source]\n\
         Optional phases: --phase lex|parse|typecheck|wasm|x86.\n\
         Measures reused GpuCompiler runtime after construction."
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mixed_source_is_deterministic_and_diverse() {
        let a = make_source(SourceMode::Mixed, 80, None, 123);
        let b = make_source(SourceMode::Mixed, 80, None, 123);
        assert_eq!(a, b);
        assert!(a.contains("if ("));
        assert!(a.contains("&&"));
        assert!(a.contains("||"));
        assert!(a.contains("!("));
        assert!(a.contains(": bool"));
        assert!(a.contains("print("));
        assert!(a.contains("return 0;"));
    }

    #[test]
    fn simple_lets_stdout_oracle_is_empty() {
        let artifact = make_source_artifact(SourceMode::SimpleLets, 80, None, 123);
        assert_eq!(artifact.expected_stdout.as_deref(), Some(""));
        assert!(artifact.source.contains("fn main()"));
        assert!(artifact.source.contains("return 0;"));
    }

    #[test]
    fn mixed_stdout_oracle_is_deterministic_and_nonempty() {
        let a = make_source_artifact(SourceMode::Mixed, 80, None, 123);
        let b = make_source_artifact(SourceMode::Mixed, 80, None, 123);
        assert_eq!(a.source, b.source);
        assert_eq!(a.expected_stdout, b.expected_stdout);
        let expected_stdout = a.expected_stdout.expect("mixed stdout oracle");
        assert!(expected_stdout.lines().count() > 10);
        assert!(expected_stdout.ends_with('\n'));
    }

    #[test]
    fn target_bytes_generates_at_least_requested_size() {
        let src = make_source(SourceMode::Mixed, 0, Some(10_000), 123);
        assert!(src.len() >= 10_000);
    }

    #[test]
    fn call_graph_source_is_deterministic_and_function_heavy() {
        let a = make_source(SourceMode::CallGraph, 80, None, 456);
        let b = make_source(SourceMode::CallGraph, 80, None, 456);
        assert_eq!(a, b);
        assert!(a.matches("fn ").count() > 10);
        assert!(a.contains("fn main()"));
        assert!(a.contains("print(f"));
        assert!(a.contains(") -> i32"));
        assert!(a.contains("return 0;"));
    }

    #[test]
    fn call_graph_stdout_oracle_is_deterministic_and_nonempty() {
        let a = make_source_artifact(SourceMode::CallGraph, 80, None, 456);
        let b = make_source_artifact(SourceMode::CallGraph, 80, None, 456);
        assert_eq!(a.source, b.source);
        assert_eq!(a.expected_stdout, b.expected_stdout);
        let expected_stdout = a.expected_stdout.expect("call graph stdout oracle");
        assert!(expected_stdout.lines().count() > 10);
        assert!(expected_stdout.ends_with('\n'));
    }

    #[test]
    fn expr_dense_source_is_deterministic_and_expression_heavy() {
        let a = make_source(SourceMode::ExprDense, 120, None, 789);
        let b = make_source(SourceMode::ExprDense, 120, None, 789);
        assert_eq!(a, b);
        assert!(a.matches("fn xd").count() > 12);
        assert!(a.contains("fn main()"));
        assert!(a.contains("print(xd"));
        assert!(a.contains(") -> i32"));
        assert!(a.contains("if ("));
        assert!(a.contains("let xl"));
        assert!(a.contains(" << 1"));
        assert!(a.contains(" & "));
        assert!(a.contains(" | "));
        assert!(a.contains(") * (") || a.contains(" * ("));
        assert!(a.contains("return 0;"));
    }

    #[test]
    fn expr_dense_stdout_oracle_is_deterministic_and_nonempty() {
        let a = make_source_artifact(SourceMode::ExprDense, 120, None, 789);
        let b = make_source_artifact(SourceMode::ExprDense, 120, None, 789);
        assert_eq!(a.source, b.source);
        assert_eq!(a.expected_stdout, b.expected_stdout);
        let expected_stdout = a.expected_stdout.expect("expr-dense stdout oracle");
        assert!(expected_stdout.lines().count() > 10);
        assert!(expected_stdout.ends_with('\n'));
    }

    #[test]
    fn abi_calls_source_is_deterministic_and_wide_call_heavy() {
        let a = make_source(SourceMode::AbiCalls, 120, None, 654);
        let b = make_source(SourceMode::AbiCalls, 120, None, 654);
        assert_eq!(a, b);
        assert!(a.matches("fn ").count() > 14);
        assert!(a.contains("fn main()"));
        assert!(a.contains(") -> i32"));
        assert!(a.contains(", "));
        assert!(a.contains("print("));
        assert!(a.contains("return 0;"));
        let mut function_names = std::collections::HashSet::<&str>::new();
        for line in a.lines().filter(|line| line.starts_with("fn abi")) {
            let name = line
                .strip_prefix("fn ")
                .and_then(|rest| rest.split_once('(').map(|(name, _)| name))
                .expect("generated ABI function declaration should have a name");
            assert!(
                function_names.insert(name),
                "abi-calls generator produced duplicate function name {name}"
            );
        }
        assert!(
            a.lines()
                .any(|line| line.starts_with("fn abi") && line.matches(": i32").count() == 4),
            "abi-calls source should include generated four-argument functions"
        );
    }

    #[test]
    fn abi_calls_stdout_oracle_is_deterministic_and_nonempty() {
        let a = make_source_artifact(SourceMode::AbiCalls, 120, None, 654);
        let b = make_source_artifact(SourceMode::AbiCalls, 120, None, 654);
        assert_eq!(a.source, b.source);
        assert_eq!(a.expected_stdout, b.expected_stdout);
        let expected_stdout = a.expected_stdout.expect("abi-calls stdout oracle");
        assert!(expected_stdout.lines().count() > 10);
        assert!(expected_stdout.ends_with('\n'));
    }

    #[test]
    fn varied_source_is_deterministic_and_combines_codegen_shapes() {
        let a = make_source(SourceMode::Varied, 160, None, 789);
        let b = make_source(SourceMode::Varied, 160, None, 789);
        assert_eq!(a, b);
        assert!(a.contains("struct "));
        assert!(a.contains("enum "));
        assert!(a.contains("match ("));
        assert!(a.contains(": [i32; 4]"));
        assert!(a.contains(": [i32]"));
        assert!(a.contains(": u32"));
        assert!(a.contains("4294967295"));
        assert!(a.contains("+ 0) >"));
        assert!(a.contains(") * ("));
        assert!(a.contains("while ("));
        assert!(a.contains("for "));
        assert!(a.contains("if ("));
        assert!(a.matches("fn ").count() > 12);
        assert!(a.contains("fn main()"));
    }

    #[test]
    fn varied_stdout_oracle_is_deterministic_and_nonempty() {
        let a = make_source_artifact(SourceMode::Varied, 160, None, 789);
        let b = make_source_artifact(SourceMode::Varied, 160, None, 789);
        assert_eq!(a.source, b.source);
        assert_eq!(a.expected_stdout, b.expected_stdout);
        let expected_stdout = a.expected_stdout.expect("varied stdout oracle");
        assert!(expected_stdout.lines().count() > 10);
        assert!(expected_stdout.ends_with('\n'));
    }

    #[test]
    fn long_function_source_is_deterministic_and_single_function_heavy() {
        let a = make_source(SourceMode::LongFunction, 180, None, 2468);
        let b = make_source(SourceMode::LongFunction, 180, None, 2468);
        assert_eq!(a, b);
        assert_eq!(a.matches("fn main()").count(), 1);
        assert!(a.matches("fn ").count() >= 2);
        assert!(a.contains("struct "));
        assert!(a.contains(": [i32; 4]"));
        assert!(a.contains("for "));
        assert!(a.contains("while ("));
        assert!(a.contains("if ("));
        assert!(a.contains("print("));
        assert!(a.contains("let a5"));
        assert!(!a.contains("acc += "));
        assert!(a.contains("return 0;"));
    }

    #[test]
    fn emit_x86_selects_elf_codegen_phase() {
        assert_eq!(
            parse_emit_phase(Some("x86_64-elf".to_string())).unwrap(),
            Phase::X86
        );
        assert_eq!(
            parse_phase(Some("x86".to_string()), Phase::Wasm).unwrap(),
            Phase::X86
        );
        assert_eq!(
            parse_phase(Some("compile".to_string()), Phase::X86).unwrap(),
            Phase::X86
        );
    }

    #[test]
    fn source_all_selects_generated_suite() {
        assert_eq!(
            parse_source_mode(Some("all".to_string())).unwrap(),
            SourceMode::All
        );
        assert_eq!(GENERATED_SOURCE_MODES.len(), 7);
        assert!(!GENERATED_SOURCE_MODES.contains(&SourceMode::All));
        let mut names = GENERATED_SOURCE_MODES
            .iter()
            .map(|mode| mode.name())
            .collect::<Vec<_>>();
        names.sort_unstable();
        assert_eq!(
            names,
            vec![
                "abi-calls",
                "call-graph",
                "expr-dense",
                "long-function",
                "mixed",
                "simple-lets",
                "varied"
            ]
        );
    }

    #[test]
    fn interactive_guard_is_phase_aware() {
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../../tables/parse_tables.bin"))
                .expect("parse tables");
        let source_lines = 39_345;
        let source_bytes = 1_300_261;

        reject_large_interactive_run(
            Phase::Parse,
            source_lines,
            source_bytes,
            false,
            Some(&tables),
        )
        .expect("parse benchmark should not be rejected by x86 allocation estimates");

        let err = reject_large_interactive_run(
            Phase::X86,
            source_lines,
            source_bytes,
            false,
            Some(&tables),
        )
        .expect_err("x86 benchmark should still guard large source-capacity estimates");
        assert!(err.contains("compile allocation floor"));
    }

    #[test]
    fn x86_dynamic_estimate_uses_shared_codegen_capacity() {
        let capacity = x86_capacity_estimate_for_hir(1024);
        let dynamic = x86_dynamic_buffer_estimate_bytes(&capacity);
        assert_eq!(capacity.hir_words, 1024);
        assert_eq!(capacity.requested_inst_capacity, 1024 * 8 + 1024);
        assert!(capacity.inst_capacity >= 1024);
        assert!(!capacity.inst_capacity_capped);
        assert!(dynamic.total >= capacity.output_capacity);
    }

    #[test]
    fn x86_dynamic_estimate_reports_instruction_capacity_cap() {
        let capacity = x86_capacity_estimate_for_hir(100_000);
        assert_eq!(capacity.hir_words, 100_000);
        assert!(capacity.requested_inst_capacity > capacity.inst_capacity);
        assert!(capacity.inst_capacity_capped);
    }

    #[test]
    fn x86_dynamic_estimate_uses_live_token_capacity_when_available() {
        let hir_only = x86_capacity_estimate_for_hir(1_000_000);
        let live = x86_capacity_estimate_for_hir_and_tokens(1_000_000, 200_000);
        assert!(hir_only.inst_capacity_capped);
        assert!(live.inst_capacity > hir_only.inst_capacity);
        assert!(live.inst_capacity < live.requested_inst_capacity);
    }

    #[test]
    fn x86_live_token_capacity_does_not_keep_legacy_16k_floor() {
        let live = x86_capacity_estimate_for_hir_and_tokens(31_041, 5_009);
        assert_eq!(live.requested_inst_capacity, 31_041 * 8 + 1_024);
        assert_eq!(live.inst_capacity, 5_009 + 1_024);
        assert!(live.inst_capacity < x86_capacity_estimate_for_hir(31_041).inst_capacity);
        assert!(live.inst_capacity_capped);
    }

    #[test]
    fn x86_order_record_capacity_is_bounded_by_compact_instruction_rows() {
        let hir_words = 687_089;
        let inst_capacity = 93_126;
        let token_capacity = 92_102;
        let compact_words =
            x86_node_inst_order_record_words(hir_words, inst_capacity, token_capacity);
        let legacy_hir_order_words = hir_words.saturating_add(1).saturating_mul(3);

        assert!(compact_words < legacy_hir_order_words);
        assert!(compact_words >= hir_words * 2);
        assert!(compact_words >= token_capacity * 10);
        assert!(compact_words >= (inst_capacity + 1) * 3);
    }

    #[test]
    fn parser_tree_floor_accounts_for_shared_hir_list_scratch() {
        assert_eq!(
            parser_tree_floor_bytes(10),
            77usize
                .saturating_mul(10)
                .saturating_mul(4)
                .saturating_add(3usize.saturating_mul(10).saturating_mul(16))
        );
    }

    #[test]
    fn live_capacity_estimate_uses_gpu_token_count_capacity() {
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../../tables/parse_tables.bin"))
                .expect("parse tables");
        let estimate = parser_capacity_estimate_for_live_token_count(128, 321, Some(&tables));
        let floor = typecheck_allocation_floor_bytes(128, estimate.tree_capacity, true, 1);

        assert_eq!(estimate.path, "llp-live-gpu-count");
        assert_eq!(estimate.tree_capacity, 321);
        assert!(estimate.total_emit >= 127);
        assert!(floor.total < typecheck_allocation_floor_bytes(1024, 321, true, 1).total);
    }
}

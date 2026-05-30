use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{Instant, SystemTime, UNIX_EPOCH},
};

#[path = "gpu_compile_bench/capacity.rs"]
mod capacity;
#[path = "gpu_compile_bench/sources.rs"]
mod sources;

use capacity::{
    print_capacity_estimate,
    print_live_capacity_estimate,
    reject_large_interactive_run,
};
use laniusc::{
    codegen::unit::{
        CodegenUnitLimits,
        SourcePackArtifactTarget,
        SourcePackBuildShardLimits,
        SourcePackJobBatchLimits,
    },
    compiler::{
        ExplicitSourceLibraryPathDependencyStream,
        FilesystemArtifactStore,
        GpuCompiler,
        GpuCompilerBackends,
        PreparedBuild,
        prepare_artifact_build_chunk,
        resume_metadata_chunk_for_target,
    },
    gpu::{device, trace},
    parser::tables::PrecomputedParseTables,
};
use sources::{SourceArtifact, make_source_artifact};

const DEFAULT_BENCH_LINES: usize = 5_000;
const DEFAULT_SOURCE_PACK_DESCRIPTOR_MAX_ITEMS: usize = 1;
const DEFAULT_SOURCE_PACK_DESCRIPTOR_MAX_READY_ITEMS: usize = 64;
const SOURCE_PACK_DESCRIPTOR_MAX_CHUNK_ITEMS: usize = 64;

#[derive(Clone, Debug)]
struct SourcePackDescriptorRunConfig {
    artifact_root: Option<PathBuf>,
    max_items: usize,
    max_ready_items: usize,
}

impl SourcePackDescriptorRunConfig {
    fn new(artifact_root: Option<PathBuf>, max_items: usize, max_ready_items: usize) -> Self {
        Self {
            artifact_root,
            max_items,
            max_ready_items,
        }
    }

    fn bounded_max_items(&self) -> usize {
        self.max_items
            .max(1)
            .min(SOURCE_PACK_DESCRIPTOR_MAX_CHUNK_ITEMS)
    }

    fn bounded_max_ready_items(&self) -> usize {
        self.max_ready_items
            .max(1)
            .min(DEFAULT_SOURCE_PACK_DESCRIPTOR_MAX_READY_ITEMS)
    }
}

fn main() {
    if let Err(err) = pollster::block_on(run()) {
        eprintln!("gpu_compile_bench: {err}");
        std::process::exit(1);
    }
}

async fn run() -> Result<(), String> {
    let mut lines = DEFAULT_BENCH_LINES;
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
    let mut source_pack_descriptors = false;
    let mut source_pack_artifact_root: Option<PathBuf> = None;
    let mut source_pack_max_items = DEFAULT_SOURCE_PACK_DESCRIPTOR_MAX_ITEMS;
    let mut source_pack_max_ready_items = DEFAULT_SOURCE_PACK_DESCRIPTOR_MAX_READY_ITEMS;
    let mut source_pack_legacy_in_memory = false;

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
            "--source-pack-descriptors" => {
                source_pack_descriptors = true;
            }
            "--source-pack-legacy-in-memory" => {
                source_pack_legacy_in_memory = true;
            }
            "--source-pack-artifact-root" => {
                source_pack_descriptors = true;
                source_pack_artifact_root =
                    Some(PathBuf::from(args.next().ok_or_else(|| {
                        "--source-pack-artifact-root requires a value".to_string()
                    })?));
            }
            flag if flag.starts_with("--source-pack-artifact-root=") => {
                source_pack_descriptors = true;
                source_pack_artifact_root = Some(PathBuf::from(
                    flag.trim_start_matches("--source-pack-artifact-root="),
                ));
            }
            "--source-pack-max-items" => {
                source_pack_descriptors = true;
                source_pack_max_items = parse_usize("--source-pack-max-items", args.next())?;
            }
            flag if flag.starts_with("--source-pack-max-items=") => {
                source_pack_descriptors = true;
                source_pack_max_items = parse_usize(
                    "--source-pack-max-items",
                    Some(
                        flag.trim_start_matches("--source-pack-max-items=")
                            .to_string(),
                    ),
                )?;
            }
            "--source-pack-max-ready-items" => {
                source_pack_descriptors = true;
                source_pack_max_ready_items =
                    parse_usize("--source-pack-max-ready-items", args.next())?;
            }
            flag if flag.starts_with("--source-pack-max-ready-items=") => {
                source_pack_descriptors = true;
                source_pack_max_ready_items = parse_usize(
                    "--source-pack-max-ready-items",
                    Some(
                        flag.trim_start_matches("--source-pack-max-ready-items=")
                            .to_string(),
                    ),
                )?;
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
    if source_pack_descriptors && source_pack_legacy_in_memory {
        return Err(
            "--source-pack-descriptors and --source-pack-legacy-in-memory are mutually exclusive"
                .into(),
        );
    }
    if source_pack_descriptors && source_pack_max_ready_items == 0 {
        return Err("--source-pack-max-ready-items must be greater than zero".into());
    }
    let source_pack_descriptor_config = source_pack_descriptors.then(|| {
        SourcePackDescriptorRunConfig::new(
            source_pack_artifact_root,
            source_pack_max_items,
            source_pack_max_ready_items,
        )
    });
    let parse_tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tables/parse_tables.bin"
    )))
    .ok();
    if source_mode == SourceMode::All
        && matches!(phase, Phase::TypeCheck | Phase::Wasm | Phase::X86)
        && !estimate_only
        && !estimate_live
        && source_pack_descriptor_config.is_none()
        && !source_pack_legacy_in_memory
    {
        return Err(source_pack_execution_mode_required_error("--source all"));
    }
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
            source_pack_descriptor_config.as_ref(),
            source_pack_legacy_in_memory,
            parse_tables.as_ref(),
        )
        .await;
    }

    let generated = make_source_artifact(source_mode, lines, target_bytes, seed);
    let src = generated.source.as_str();
    let source_lines = src.lines().count();
    if dump_source {
        print!("{src}");
        return Ok(());
    }
    if estimate_only {
        print_capacity_estimate(
            source_lines,
            src,
            &generated.sources,
            &generated.library_ids,
            &generated.library_dependencies,
            parse_tables.as_ref(),
        );
        return Ok(());
    }
    if estimate_live {
        if generated.sources.len() > 1 {
            print_capacity_estimate(
                source_lines,
                src,
                &generated.sources,
                &generated.library_ids,
                &generated.library_dependencies,
                parse_tables.as_ref(),
            );
            println!(
                "estimate_live source_pack=skipped note=live parse estimate currently reports single-source parser metrics"
            );
            return Ok(());
        }
        let compiler = GpuCompiler::new_with_device_and_backends(
            device::global(),
            GpuCompilerBackends::frontend_only(),
        )
        .await
        .map_err(|err| err.to_string())?;
        device::persist_pipeline_cache();
        let live = compiler
            .benchmark_live_capacity_estimate(&src)
            .await
            .map_err(|err| err.to_string())?;
        print_live_capacity_estimate(source_lines, src.len(), live, parse_tables.as_ref());
        return Ok(());
    }
    if generated.sources.len() > 1
        && source_pack_descriptor_config.is_none()
        && !source_pack_legacy_in_memory
    {
        return Err(source_pack_execution_mode_required_error(
            "--source module-pack",
        ));
    }
    reject_large_interactive_run(
        phase,
        source_lines,
        src,
        generated.sources.len(),
        allow_large,
        parse_tables.as_ref(),
    )?;
    let compiler = GpuCompiler::new_with_device_and_backends(
        device::global(),
        compiler_backends_for_phase(phase),
    )
    .await
    .map_err(|err| err.to_string())?;
    device::persist_pipeline_cache();

    for warmup_i in 0..warmups {
        let start = Instant::now();
        let result = run_phase(
            phase,
            &generated,
            &compiler,
            validate_output,
            run_x86_output,
            generated.expected_stdout.as_deref(),
            "warmup",
            source_pack_descriptor_config.as_ref(),
            source_pack_legacy_in_memory,
        )
        .await;
        trace::record_host_span(
            "host.bench",
            &format!("bench.warmup.{warmup_i}"),
            start,
            Instant::now(),
        );
        result?;
    }

    let mut best_ms = f64::INFINITY;
    let mut total_ms = 0.0f64;
    let mut output_bytes = 0usize;
    for iter_i in 0..iters {
        let start = Instant::now();
        let result = run_phase(
            phase,
            &generated,
            &compiler,
            validate_output,
            run_x86_output,
            generated.expected_stdout.as_deref(),
            "measured",
            source_pack_descriptor_config.as_ref(),
            source_pack_legacy_in_memory,
        )
        .await;
        let end = Instant::now();
        trace::record_host_span(
            "host.bench",
            &format!("bench.measured.{iter_i}"),
            start,
            end,
        );
        let emitted = result?;
        let elapsed_ms = end.duration_since(start).as_secs_f64() * 1000.0;
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
    trace::flush();
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
    source_pack_descriptor_config: Option<&SourcePackDescriptorRunConfig>,
    source_pack_legacy_in_memory: bool,
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
    for source_mode in generated_source_modes_for_phase(phase).iter().copied() {
        let generated = make_source_artifact(source_mode, lines, target_bytes, seed);
        let src = generated.source.as_str();
        let source_lines = src.lines().count();

        if estimate_only {
            println!("source={}", source_mode.name());
            print_capacity_estimate(
                source_lines,
                src,
                &generated.sources,
                &generated.library_ids,
                &generated.library_dependencies,
                parse_tables,
            );
            continue;
        }

        if estimate_live {
            if generated.sources.len() > 1 {
                println!("source={}", source_mode.name());
                print_capacity_estimate(
                    source_lines,
                    src,
                    &generated.sources,
                    &generated.library_ids,
                    &generated.library_dependencies,
                    parse_tables,
                );
                println!(
                    "estimate_live source_pack=skipped note=live parse estimate currently reports single-source parser metrics"
                );
                continue;
            }
            if compiler.is_none() {
                compiler = Some(
                    GpuCompiler::new_with_device_and_backends(
                        device::global(),
                        GpuCompilerBackends::frontend_only(),
                    )
                    .await
                    .map_err(|err| err.to_string())?,
                );
                device::persist_pipeline_cache();
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

        if generated.sources.len() > 1
            && source_pack_descriptor_config.is_none()
            && !source_pack_legacy_in_memory
        {
            return Err(source_pack_execution_mode_required_error(
                source_mode.name(),
            ));
        }
        reject_large_interactive_run(
            phase,
            source_lines,
            src,
            generated.sources.len(),
            allow_large,
            parse_tables,
        )?;
        if compiler.is_none() {
            compiler = Some(
                GpuCompiler::new_with_device_and_backends(
                    device::global(),
                    compiler_backends_for_phase(phase),
                )
                .await
                .map_err(|err| err.to_string())?,
            );
            device::persist_pipeline_cache();
        }
        let compiler_ref = compiler.as_ref().expect("suite compiler initialized");

        for warmup_i in 0..warmups {
            let start = Instant::now();
            let result = run_phase(
                phase,
                &generated,
                compiler_ref,
                validate_output,
                run_x86_output,
                generated.expected_stdout.as_deref(),
                "warmup",
                source_pack_descriptor_config,
                source_pack_legacy_in_memory,
            )
            .await;
            trace::record_host_span(
                "host.bench",
                &format!("bench.{}.warmup.{warmup_i}", source_mode.name()),
                start,
                Instant::now(),
            );
            result?;
        }

        let mut best_ms = f64::INFINITY;
        let mut total_ms = 0.0f64;
        let mut output_bytes = 0usize;
        for iter_i in 0..iters {
            let start = Instant::now();
            let result = run_phase(
                phase,
                &generated,
                compiler_ref,
                validate_output,
                run_x86_output,
                generated.expected_stdout.as_deref(),
                "measured",
                source_pack_descriptor_config,
                source_pack_legacy_in_memory,
            )
            .await;
            let end = Instant::now();
            trace::record_host_span(
                "host.bench",
                &format!("bench.{}.measured.{iter_i}", source_mode.name()),
                start,
                end,
            );
            let emitted = result?;
            let elapsed_ms = end.duration_since(start).as_secs_f64() * 1000.0;
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
        if allow_large {
            compiler = None;
            let _ = device::global()
                .device
                .poll(wgpu::PollType::wait_indefinitely());
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
    trace::flush();
    Ok(())
}

fn generated_source_modes_for_phase(phase: Phase) -> &'static [SourceMode] {
    match phase {
        Phase::Lex | Phase::Parse => &GENERATED_SINGLE_SOURCE_MODES,
        Phase::TypeCheck | Phase::Wasm | Phase::X86 => &GENERATED_COMPILE_SOURCE_MODES,
    }
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

fn compiler_backends_for_phase(phase: Phase) -> GpuCompilerBackends {
    match phase {
        Phase::Wasm => GpuCompilerBackends::wasm_only(),
        Phase::X86 => GpuCompilerBackends::x86_only(),
        Phase::Lex | Phase::Parse | Phase::TypeCheck => GpuCompilerBackends::frontend_only(),
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
    ModulePack,
    All,
}

const GENERATED_SINGLE_SOURCE_MODES: [SourceMode; 7] = [
    SourceMode::SimpleLets,
    SourceMode::Mixed,
    SourceMode::CallGraph,
    SourceMode::ExprDense,
    SourceMode::AbiCalls,
    SourceMode::Varied,
    SourceMode::LongFunction,
];

const GENERATED_COMPILE_SOURCE_MODES: [SourceMode; 8] = [
    SourceMode::SimpleLets,
    SourceMode::Mixed,
    SourceMode::CallGraph,
    SourceMode::ExprDense,
    SourceMode::AbiCalls,
    SourceMode::Varied,
    SourceMode::LongFunction,
    SourceMode::ModulePack,
];

async fn run_phase(
    phase: Phase,
    generated: &SourceArtifact,
    compiler: &GpuCompiler<'_>,
    validate_output: bool,
    run_x86_output: bool,
    expected_stdout: Option<&str>,
    phase_name: &str,
    source_pack_descriptor_config: Option<&SourcePackDescriptorRunConfig>,
    source_pack_legacy_in_memory: bool,
) -> Result<Vec<u8>, String> {
    let src = generated.source.as_str();
    let sources = generated.sources.as_slice();
    if sources.len() > 1 {
        if let Some(config) = source_pack_descriptor_config {
            return run_source_pack_descriptor_phase(
                phase,
                generated,
                compiler,
                validate_output,
                run_x86_output,
                phase_name,
                config,
            )
            .await;
        }
        if !source_pack_legacy_in_memory {
            return Err(source_pack_execution_mode_required_error(
                "--source module-pack",
            ));
        }
        return run_source_pack_phase(
            phase,
            sources,
            compiler,
            validate_output,
            run_x86_output,
            expected_stdout,
            phase_name,
        )
        .await;
    }
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
            let wasm = compiler
                .compile_source_to_wasm(src)
                .await
                .map_err(|err| err.to_string())?;
            validate_wasm_output(validate_output, &wasm, phase_name)?;
            Ok(wasm)
        }
        Phase::X86 => {
            let elf = compiler
                .compile_source_to_x86_64(src)
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

async fn run_source_pack_phase(
    phase: Phase,
    sources: &[String],
    compiler: &GpuCompiler<'_>,
    validate_output: bool,
    run_x86_output: bool,
    expected_stdout: Option<&str>,
    phase_name: &str,
) -> Result<Vec<u8>, String> {
    match phase {
        Phase::Lex | Phase::Parse => Err(format!(
            "--source {} is a source-pack generator; use --phase typecheck, wasm, or x86",
            SourceMode::ModulePack.name()
        )),
        Phase::TypeCheck => {
            compiler
                .type_check_source_pack(sources)
                .await
                .map_err(|err| err.to_string())?;
            Ok(Vec::new())
        }
        Phase::Wasm => {
            let wasm = compiler
                .compile_source_pack_to_wasm(sources)
                .await
                .map_err(|err| err.to_string())?;
            validate_wasm_output(validate_output, &wasm, phase_name)?;
            Ok(wasm)
        }
        Phase::X86 => {
            let elf = compiler
                .compile_source_pack_to_x86_64(sources)
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

async fn run_source_pack_descriptor_phase(
    phase: Phase,
    generated: &SourceArtifact,
    compiler: &GpuCompiler<'_>,
    validate_output: bool,
    run_x86_output: bool,
    phase_name: &str,
    config: &SourcePackDescriptorRunConfig,
) -> Result<Vec<u8>, String> {
    if validate_output || run_x86_output {
        return Err(
            "--source-pack-descriptors writes persisted descriptor artifacts; output validation requires the legacy in-memory source-pack path"
                .to_string(),
        );
    }
    let target = source_pack_artifact_target_for_phase(phase)?;
    let artifact_root = source_pack_descriptor_artifact_root(config, phase, phase_name)?;
    let limits = CodegenUnitLimits::default();
    let batch_limits = SourcePackJobBatchLimits::from_codegen_unit_limits(limits);
    let max_items = config.bounded_max_items();
    let max_ready_items = config.bounded_max_ready_items();
    let store = FilesystemArtifactStore::new(&artifact_root);

    if !store
        .library_partition_index_path_for_target(target)
        .is_file()
    {
        let source_root = artifact_root.join("generated-sources");
        let libraries = materialize_generated_source_pack_paths(generated, &source_root)?;
        let total_library_count = libraries.len();
        let prepared_library_count = if store
            .library_metadata_prepare_progress_path_for_target(target)
            .is_file()
        {
            store
                .load_library_metadata_prepare_progress_for_target(target)
                .map_err(|err| err.to_string())?
                .library_count
        } else {
            0
        };
        if prepared_library_count > total_library_count {
            return Err(format!(
                "source-pack descriptor metadata progress records {prepared_library_count} libraries but generated pack has {total_library_count}"
            ));
        }
        let library_chunk = libraries
            .into_iter()
            .skip(prepared_library_count)
            .take(max_items)
            .collect::<Vec<_>>();
        let manifest_complete_after_input =
            prepared_library_count.saturating_add(library_chunk.len()) >= total_library_count;
        let metadata = resume_metadata_chunk_for_target(
            library_chunk,
            &artifact_root,
            target,
            max_items,
            manifest_complete_after_input,
        )
        .map_err(|err| err.to_string())?;
        println!(
            "source_pack_descriptors phase={} target={target:?} root={} prepare_stage=metadata complete={} libraries={} new_libraries={} source_files={}",
            phase.name(),
            artifact_root.display(),
            metadata.complete,
            metadata.library_count,
            metadata.new_library_count,
            metadata.source_file_count,
        );
        if !metadata.complete {
            return Ok(Vec::new());
        }
    }

    if !store.build_state_path_for_target(target).is_file() {
        let build_step = prepare_artifact_build_chunk(
            &artifact_root,
            limits,
            batch_limits,
            SourcePackBuildShardLimits::default(),
            target,
            max_items,
        )
        .map_err(|err| err.to_string())?;
        println!(
            "source_pack_descriptors phase={} target={target:?} root={} prepare_stage={:?} next_stage={:?} complete={} new_items={}",
            phase.name(),
            artifact_root.display(),
            build_step.stage,
            build_step.next_stage,
            build_step.complete,
            build_step.new_item_count,
        );
        if !build_step.complete {
            return Ok(Vec::new());
        }
    }

    let worker_id = format!("gpu_compile_bench-{phase_name}-{}", std::process::id());
    let prepared = PreparedBuild::new(&artifact_root, target);
    let mut progress = prepared
        .work_queue_progress_snapshot(max_ready_items)
        .map_err(|err| err.to_string())?;
    let mut executed_item_count = 0usize;
    for _ in 0..max_items {
        let step = prepared
            .submit_gpu_descriptor_work_queue_step(
                worker_id.clone(),
                None,
                max_ready_items,
                compiler,
            )
            .await
            .map_err(|err| err.to_string())?;
        if step.executed_item.is_some() {
            executed_item_count += 1;
        }
        let claimed = step.claimed_item_index.is_some();
        progress = step.progress;
        if !claimed || progress.complete {
            break;
        }
    }

    println!(
        "source_pack_descriptors phase={} target={target:?} root={} executed_items={executed_item_count} completed_items={} work_items={} ready_items={} complete={}",
        phase.name(),
        artifact_root.display(),
        progress.completed_item_count,
        progress.work_item_count,
        progress.ready_item_count,
        progress.complete,
    );
    Ok(Vec::new())
}

fn source_pack_artifact_target_for_phase(phase: Phase) -> Result<SourcePackArtifactTarget, String> {
    match phase {
        Phase::TypeCheck => Ok(SourcePackArtifactTarget::Generic),
        Phase::Wasm => Ok(SourcePackArtifactTarget::Wasm),
        Phase::X86 => Ok(SourcePackArtifactTarget::X86_64),
        Phase::Lex | Phase::Parse => Err(format!(
            "--source {} is a source-pack generator; use --phase typecheck, wasm, or x86",
            SourceMode::ModulePack.name()
        )),
    }
}

fn source_pack_execution_mode_required_error(source_name: &str) -> String {
    format!(
        "{source_name} uses source-pack inputs; pass --source-pack-descriptors for the persisted bounded work queue or --source-pack-legacy-in-memory for the old whole-pack path"
    )
}

fn source_pack_descriptor_artifact_root(
    config: &SourcePackDescriptorRunConfig,
    phase: Phase,
    phase_name: &str,
) -> Result<PathBuf, String> {
    if let Some(root) = &config.artifact_root {
        return Ok(root.clone());
    }
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|err| format!("source-pack descriptor artifact clock error: {err}"))?
        .as_nanos();
    Ok(std::env::temp_dir().join(format!(
        "laniusc-source-pack-descriptors-{}-{}-{}-{nanos}",
        phase.name(),
        phase_name,
        std::process::id()
    )))
}

fn materialize_generated_source_pack_paths(
    generated: &SourceArtifact,
    source_root: &Path,
) -> Result<Vec<ExplicitSourceLibraryPathDependencyStream<Vec<PathBuf>, Vec<u32>>>, String> {
    if generated.sources.len() != generated.library_ids.len() {
        return Err(format!(
            "source-pack source count {} does not match library id count {}",
            generated.sources.len(),
            generated.library_ids.len()
        ));
    }

    let mut source_paths_by_library: BTreeMap<u32, Vec<PathBuf>> = BTreeMap::new();
    fs::create_dir_all(source_root).map_err(|err| {
        format!(
            "create generated source-pack source root {}: {err}",
            source_root.display()
        )
    })?;
    for (source_index, (source, library_id)) in generated
        .sources
        .iter()
        .zip(generated.library_ids.iter().copied())
        .enumerate()
    {
        let library_root = source_root.join(format!("library-{library_id}"));
        fs::create_dir_all(&library_root).map_err(|err| {
            format!(
                "create generated source-pack library source root {}: {err}",
                library_root.display()
            )
        })?;
        let path = library_root.join(format!("source-{source_index}.lanius"));
        fs::write(&path, source.as_bytes()).map_err(|err| {
            format!(
                "write generated source-pack source {}: {err}",
                path.display()
            )
        })?;
        source_paths_by_library
            .entry(library_id)
            .or_default()
            .push(path);
    }

    let mut dependencies_by_library: BTreeMap<u32, Vec<u32>> = BTreeMap::new();
    for dependency in &generated.library_dependencies {
        dependencies_by_library
            .entry(dependency.library_id)
            .or_default()
            .push(dependency.depends_on_library_id);
    }

    Ok(source_paths_by_library
        .into_iter()
        .map(|(library_id, paths)| {
            let dependency_library_ids = dependencies_by_library
                .remove(&library_id)
                .unwrap_or_default();
            ExplicitSourceLibraryPathDependencyStream {
                library_id,
                source_file_count: paths.len(),
                paths,
                dependency_library_count: dependency_library_ids.len(),
                dependency_library_ids,
            }
        })
        .collect())
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
            SourceMode::ModulePack => "module-pack",
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
        "module-pack" | "modules" | "source-pack" | "pack" => Ok(SourceMode::ModulePack),
        "all" | "suite" | "generated-suite" => Ok(SourceMode::All),
        other => Err(format!(
            "unsupported --source {other:?}; expected simple-lets, mixed, call-graph, expr-dense, abi-calls, varied, long-function, module-pack, or all"
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

fn print_help() {
    eprintln!(
        "Usage: gpu_compile_bench [--emit wasm|x86_64-elf] [--source simple-lets|mixed|call-graph|expr-dense|abi-calls|varied|long-function|module-pack|all] [--lines N] [--target-bytes N] [--seed N] [--warmups N] [--iters N] [--validate-output] [--run-x86-output] [--allow-large] [--estimate-only|--estimate-live] [--dump-source] [--source-pack-descriptors] [--source-pack-max-items N] [--source-pack-max-ready-items N] [--source-pack-artifact-root PATH] [--source-pack-legacy-in-memory]\n\
         Optional phases: --phase lex|parse|typecheck|wasm|x86.\n\
         Defaults to --lines 5000; use --allow-large for intentional large live runs.\n\
         --source-pack-descriptors prepares module-pack filesystem artifacts and advances the persisted queue with bounded one-item submits; --source-pack-legacy-in-memory is required for the old whole-pack module-pack path.\n\
         Set LANIUS_PERFETTO_TRACE=path.json to write Perfetto-compatible trace-event JSON.\n\
         Measures reused GpuCompiler runtime after construction."
    );
}

#[cfg(test)]
#[path = "gpu_compile_bench/tests.rs"]
mod tests;

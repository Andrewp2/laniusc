// build.rs — compile Slang entrypoints (no duplicate module sources).

use std::{
    collections::{HashSet, VecDeque},
    env,
    fs,
    io,
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    sync::{Arc, Mutex, mpsc},
    thread,
    time::{Duration, Instant, SystemTime},
};

use anyhow::{Context, Result, anyhow};

fn main() -> Result<()> {
    const DEFAULT_SHADER_COMPILE_TIMEOUT_MS: u64 = 120_000;

    println!("cargo:rerun-if-env-changed=SLANGC");
    println!("cargo:rerun-if-env-changed=LANIUS_SHADER_DEBUG");
    println!("cargo:rerun-if-env-changed=LANIUS_SHADER_OPT_LEVEL");
    println!("cargo:rerun-if-env-changed=LANIUS_SHADER_MINIMUM_SLANG_OPT");
    println!("cargo:rerun-if-env-changed=LANIUS_SHADER_DISABLE_NON_ESSENTIAL_VALIDATIONS");
    println!("cargo:rerun-if-env-changed=LANIUS_SHADER_SKIP_SPIRV_VALIDATION");
    println!("cargo:rerun-if-env-changed=LANIUS_SHADER_REPORT_DOWNSTREAM_TIME");
    println!("cargo:rerun-if-env-changed=LANIUS_SHADER_REPORT_PERF");
    println!("cargo:rerun-if-env-changed=LANIUS_SHADER_REPORT_DETAILED_PERF");
    println!("cargo:rerun-if-env-changed=LANIUS_SHADER_MAX_SPV_BYTES");
    println!("cargo:rerun-if-env-changed=LANIUS_SHADER_COMPILE_TIMEOUT_MS");
    println!("cargo:rerun-if-env-changed=LANIUS_SHADER_BUILD_JOBS");
    println!("cargo:rerun-if-env-changed=SLANGC_EXTRA_FLAGS");

    let workspace_root = workspace_root()?;
    let shader_root = workspace_root.join("shaders");
    track_dir_recursively(&shader_root);
    let slangc = find_slangc()
        .context("could not locate `slangc` binary. Set $SLANGC or add it to PATH.")?;
    let shader_compile_timeout = timeout_from_env_ms(
        "LANIUS_SHADER_COMPILE_TIMEOUT_MS",
        DEFAULT_SHADER_COMPILE_TIMEOUT_MS,
    )?;
    let out_dir = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR not set"));
    let shader_out_dir = stable_shader_artifact_root(&workspace_root);
    fs::create_dir_all(&shader_out_dir)
        .with_context(|| format!("create shader artifact root {}", shader_out_dir.display()))?;
    println!(
        "cargo:rustc-env=LANIUS_SHADER_ARTIFACT_ROOT={}",
        shader_out_dir.display()
    );
    let mut sources =
        collect_slang_sources(&shader_root).context("walk workspace shaders/ for .slang files")?;
    sources.sort();
    let mut shader_artifacts = Vec::new();
    let mut shader_compile_jobs = Vec::new();
    let max_shader_spv_bytes = shader_max_spv_bytes()?;

    // Only compile files that contain an entrypoint attribute, e.g. [shader("compute")]
    for ep in sources {
        if ep.extension().and_then(|e| e.to_str()) != Some("slang") {
            continue;
        }
        if !has_entrypoint(&ep).unwrap_or(false) {
            // Still tracked for rebuild via track_dir_recursively; just not compiled as an entrypoint.
            continue;
        }
        if is_unwired_shader_entrypoint(&shader_root, &ep)? {
            // These are retained as source/audit fixtures, but the default compiler no longer
            // loads their SPIR-V. Skipping them keeps clean builds from paying for dead pipelines.
            continue;
        }

        let artifact_key = shader_artifact_key(&shader_root, &ep)?;
        let spv_out = shader_out_dir.join(format!("{artifact_key}.spv"));
        let refl_out = shader_out_dir.join(format!("{artifact_key}.reflect.json"));
        let stamp_out = shader_out_dir.join(format!("{artifact_key}.stamp"));
        if let Some(parent) = spv_out.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("create shader artifact dir {}", parent.display()))?;
        }
        let extra = env::var("SLANGC_EXTRA_FLAGS").unwrap_or_default();
        let extra_args = slangc_extra_args(&extra)?;
        let opt_level = shader_opt_level_for_artifact(&artifact_key)?;
        let minimum_slang_opt = shader_minimum_slang_optimization();
        let disable_non_essential_validations =
            env_truthy("LANIUS_SHADER_DISABLE_NON_ESSENTIAL_VALIDATIONS");
        let skip_spirv_validation = env_truthy("LANIUS_SHADER_SKIP_SPIRV_VALIDATION");
        let report_downstream_time = env_truthy("LANIUS_SHADER_REPORT_DOWNSTREAM_TIME");
        let report_perf = env_truthy("LANIUS_SHADER_REPORT_PERF");
        let report_detailed_perf = env_truthy("LANIUS_SHADER_REPORT_DETAILED_PERF");
        let compile_stamp = format!(
            "slangc={}\nopt={}\nminimum_slang_opt={}\ndisable_non_essential_validations={}\nskip_spirv_validation={}\nreport_downstream_time={}\nreport_perf={}\nreport_detailed_perf={}\nextra={}\n",
            slangc.display(),
            opt_level,
            minimum_slang_opt,
            disable_non_essential_validations,
            skip_spirv_validation,
            report_downstream_time,
            report_perf,
            report_detailed_perf,
            extra
        );
        if shader_outputs_fresh(
            &shader_root,
            &ep,
            &spv_out,
            &refl_out,
            &stamp_out,
            &compile_stamp,
        )? {
            validate_shader_artifact_size(&ep, &spv_out, max_shader_spv_bytes)?;
            shader_artifacts.push((artifact_key, spv_out, refl_out));
            continue;
        }

        shader_compile_jobs.push(ShaderCompileJob {
            ep,
            artifact_key,
            spv_out,
            refl_out,
            stamp_out,
            opt_level,
            minimum_slang_opt,
            disable_non_essential_validations,
            skip_spirv_validation,
            report_downstream_time,
            report_perf,
            report_detailed_perf,
            debug: env_truthy("LANIUS_SHADER_DEBUG"),
            extra_args,
            compile_stamp,
        });
    }
    shader_artifacts.extend(compile_shader_jobs(
        shader_compile_jobs,
        &shader_root,
        &slangc,
        shader_compile_timeout,
        max_shader_spv_bytes,
    )?);
    let active_artifact_keys: HashSet<String> = shader_artifacts
        .iter()
        .map(|(artifact_key, _, _)| artifact_key.clone())
        .collect();
    remove_stale_shader_artifacts(&shader_out_dir, &active_artifact_keys)?;
    write_generated_shader_artifacts(&out_dir, &shader_artifacts)?;
    let shader_digest = shader_artifact_digest(&shader_artifacts)?;
    let shader_size_summary = shader_artifact_size_summary(&shader_artifacts)?;
    let (shader_size_guard_status, shader_size_guard_max_bytes) =
        shader_size_guard_build_metadata(max_shader_spv_bytes);
    let shader_metadata = ShaderArtifactBuildMetadata {
        digest: shader_digest,
        count: shader_size_summary.count,
        max_spv_bytes: shader_size_summary.max_spv_bytes,
        max_spv_name: shader_size_summary.max_spv_name,
        size_guard_status: shader_size_guard_status.to_string(),
        size_guard_max_bytes: shader_size_guard_max_bytes,
    };
    write_shader_artifact_metadata(&shader_out_dir, &shader_metadata)?;
    if !runtime_loaded_debug_shader_artifacts() {
        emit_shader_artifact_rustc_env(&shader_metadata);
    }

    Ok(())
}

fn workspace_root() -> Result<PathBuf> {
    let manifest_dir =
        PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    manifest_dir
        .parent()
        .and_then(Path::parent)
        .map(Path::to_path_buf)
        .ok_or_else(|| {
            anyhow!(
                "could not find workspace root from {}",
                manifest_dir.display()
            )
        })
}

fn stable_shader_artifact_root(workspace_root: &Path) -> PathBuf {
    let target_dir = env::var_os("CARGO_TARGET_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| workspace_root.join("target"));
    let profile = env::var("PROFILE").unwrap_or_else(|_| "debug".to_string());
    target_dir
        .join("laniusc-shader-artifacts")
        .join(profile)
        .join("shaders")
}

fn env_truthy(name: &str) -> bool {
    env::var(name)
        .map(|value| {
            let value = value.to_ascii_lowercase();
            value != "0" && value != "false" && value != "off"
        })
        .unwrap_or(false)
}

fn shader_opt_level() -> Result<String> {
    let value = match env::var("LANIUS_SHADER_OPT_LEVEL") {
        Ok(value) => value,
        Err(env::VarError::NotPresent) => return Ok("1".into()),
        Err(env::VarError::NotUnicode(_)) => {
            return Err(anyhow!(
                "LANIUS_SHADER_OPT_LEVEL must be a UTF-8 Slang optimization level"
            ));
        }
    };
    let value = value.trim();
    if value.is_empty() {
        return Ok("1".into());
    }
    match value {
        "0" | "1" | "2" | "3" | "none" | "default" | "high" | "maximal" => Ok(value.into()),
        _ => Err(anyhow!(
            "LANIUS_SHADER_OPT_LEVEL={value:?} is not a supported Slang optimization level; use 0, 1, 2, 3, none, default, high, or maximal"
        )),
    }
}

fn shader_opt_level_for_artifact(artifact_key: &str) -> Result<String> {
    let default = shader_opt_level()?;
    if default != "0" && force_minimum_wasm_body_artifact_optimization(artifact_key) {
        return Ok("0".to_string());
    }
    Ok(default)
}

fn force_minimum_wasm_body_artifact_optimization(artifact_key: &str) -> bool {
    matches!(
        artifact_key,
        "codegen/wasm/module"
            | "codegen/wasm/hir/body_plan"
            | "codegen/wasm/hir/body_plan_collect"
            | "codegen/wasm/hir/body_plan_validate"
            | "codegen/wasm/hir/body_plan_validate_return"
            | "codegen/wasm/hir/body_plan_validate_return_call"
            | "codegen/wasm/hir/body_plan_validate_return_agg_call"
            | "codegen/wasm/hir/body_plan_validate_return_nested_call"
            | "codegen/wasm/hir/body_plan_validate_assign"
            | "codegen/wasm/hir/body_plan_validate_control"
            | "codegen/wasm/hir/body_plan_validate_agg_range_control"
            | "codegen/wasm/hir/body_plan_validate_if_simple"
            | "codegen/wasm/hir/body_plan_validate_print_simple"
            | "codegen/wasm/hir/body_plan_validate_call"
            | "codegen/wasm/hir/body_plan_validate_host_void_call"
            | "codegen/wasm/hir/body_plan_validate_let_host"
            | "codegen/wasm/hir/body_plan_validate_let_host_env"
            | "codegen/wasm/hir/body_plan_validate_let_host_io"
            | "codegen/wasm/hir/body_plan_validate_let_host_string"
            | "codegen/wasm/hir/body_plan_validate_return_host_io"
            | "codegen/wasm/hir/body_plan_validate_return_host_string"
            | "codegen/wasm/hir/body_plan_validate_let_direct_call"
            | "codegen/wasm/hir/body_plan_validate_let_call"
            | "codegen/wasm/hir/body_plan_validate_let_call_status"
            | "codegen/wasm/hir/body_plan_agg_direct_call"
            | "codegen/wasm/hir/body_plan_agg_struct"
            | "codegen/wasm/hir/body_plan_arrays"
            | "codegen/wasm/hir/body_agg_call_arg_counts"
            | "codegen/wasm/hir/body_agg_call_arg_records"
            | "codegen/wasm/hir/body_agg_call_finalize"
            | "codegen/wasm/hir/body_direct_call_arg_records"
            | "codegen/wasm/hir/body_direct_call_finalize"
            | "codegen/wasm/hir/body_scatter_frame"
            | "codegen/wasm/hir/body_scatter_if_simple"
            | "codegen/wasm/hir/body_scatter_return_scalar"
            | "codegen/wasm/hir/body_scatter_return_expr"
            | "codegen/wasm/hir/body_scatter_conversion_expr"
            | "codegen/wasm/hir/body_scatter"
            | "codegen/wasm/hir/body_scatter_direct_nested_call"
            | "codegen/wasm/hir/body_scatter_array_lean"
            | "codegen/wasm/hir/body_scatter_let_const"
            | "codegen/wasm/hir/body_scatter_expr_control"
            | "codegen/wasm/hir/body_scatter_agg_range_control"
            | "codegen/wasm/hir/body_scatter_host_io"
            | "codegen/wasm/hir/body_scatter_host"
            | "codegen/wasm/hir/body_scatter_arrays"
            | "codegen/wasm/hir/body_scatter_agg_copy"
            | "codegen/wasm/hir/body_scatter_agg_call_args"
            | "codegen/wasm/hir/body_scatter_nested_call_args"
            | "codegen/wasm/hir/body_scatter_agg_direct_call"
            | "codegen/wasm/hir/body_scatter_return_member"
            | "codegen/wasm/hir/body_scatter_member_expr"
            | "codegen/wasm/hir/body_scatter_binary_direct_call"
            | "codegen/wasm/hir/body_scatter_return_agg_direct_call"
    )
}

fn shader_minimum_slang_optimization() -> bool {
    env::var("LANIUS_SHADER_MINIMUM_SLANG_OPT")
        .map(|value| {
            let value = value.to_ascii_lowercase();
            value != "0" && value != "false" && value != "off"
        })
        .unwrap_or(true)
}

fn slangc_extra_args(extra: &str) -> Result<Vec<String>> {
    let args: Vec<&str> = extra.split_whitespace().filter(|s| !s.is_empty()).collect();
    for arg in &args {
        if is_build_policy_slangc_flag(arg) {
            return Err(anyhow!(
                "SLANGC_EXTRA_FLAGS contains {arg:?}, but this build owns Slang optimization, validation, and timing flags through named Lanius env vars. Use LANIUS_SHADER_OPT_LEVEL, LANIUS_SHADER_MINIMUM_SLANG_OPT, LANIUS_SHADER_DISABLE_NON_ESSENTIAL_VALIDATIONS, LANIUS_SHADER_SKIP_SPIRV_VALIDATION, LANIUS_SHADER_REPORT_DOWNSTREAM_TIME, LANIUS_SHADER_REPORT_PERF, or LANIUS_SHADER_REPORT_DETAILED_PERF instead."
            ));
        }
    }
    Ok(args.into_iter().map(str::to_string).collect())
}

fn is_build_policy_slangc_flag(arg: &str) -> bool {
    arg == "-minimum-slang-optimization"
        || arg == "-disable-non-essential-validations"
        || arg == "-skip-spirv-validation"
        || arg == "-report-downstream-time"
        || arg == "-report-perf-benchmark"
        || arg == "-report-detailed-perf-benchmark"
        || arg == "-optimization-level"
        || arg.starts_with("-optimization-level=")
        || matches!(
            arg,
            "-O" | "-O0" | "-O1" | "-O2" | "-O3" | "-Onone" | "-Odefault" | "-Ohigh" | "-Omaximal"
        )
}

fn timeout_from_env_ms(name: &str, default_ms: u64) -> Result<Option<Duration>> {
    let value = match env::var(name) {
        Ok(value) => value,
        Err(env::VarError::NotPresent) => return Ok(Some(Duration::from_millis(default_ms))),
        Err(env::VarError::NotUnicode(_)) => {
            return Err(anyhow!("{name} must be a UTF-8 unsigned millisecond count"));
        }
    };
    let value = value.trim();
    if value.is_empty() {
        return Ok(Some(Duration::from_millis(default_ms)));
    }
    let parsed = value
        .parse::<u64>()
        .with_context(|| format!("parse {name}={value:?} as an unsigned millisecond count"))?;
    Ok((parsed != 0).then_some(Duration::from_millis(parsed)))
}

fn shader_max_spv_bytes() -> Result<Option<u64>> {
    const DEFAULT_MAX_SPV_BYTES: u64 = 5 * 1024 * 1024;

    let value = match env::var("LANIUS_SHADER_MAX_SPV_BYTES") {
        Ok(value) => value,
        Err(env::VarError::NotPresent) => return Ok(Some(DEFAULT_MAX_SPV_BYTES)),
        Err(env::VarError::NotUnicode(_)) => {
            return Err(anyhow!(
                "LANIUS_SHADER_MAX_SPV_BYTES must be a UTF-8 unsigned byte count"
            ));
        }
    };
    let value = value.trim();
    if value.is_empty() {
        return Ok(Some(DEFAULT_MAX_SPV_BYTES));
    }
    let parsed = value.parse::<u64>().with_context(|| {
        format!("parse LANIUS_SHADER_MAX_SPV_BYTES={value:?} as an unsigned byte count")
    })?;
    Ok((parsed != 0).then_some(parsed))
}

fn validate_shader_artifact_size(ep: &Path, spv_out: &Path, max_bytes: Option<u64>) -> Result<()> {
    let Some(max_bytes) = max_bytes else {
        return Ok(());
    };
    let size = fs::metadata(spv_out)
        .with_context(|| format!("stat shader artifact {}", spv_out.display()))?
        .len();
    if size <= max_bytes {
        return Ok(());
    }

    Err(anyhow!(
        "compiled shader artifact {} for {} is {} bytes, exceeding LANIUS_SHADER_MAX_SPV_BYTES={} bytes. Split the shader into smaller record/count/scan/scatter/join passes before relying on this pipeline; set LANIUS_SHADER_MAX_SPV_BYTES=0 only for local investigation.",
        spv_out.display(),
        ep.display(),
        size,
        max_bytes
    ))
}

struct ShaderCompileJob {
    ep: PathBuf,
    artifact_key: String,
    spv_out: PathBuf,
    refl_out: PathBuf,
    stamp_out: PathBuf,
    opt_level: String,
    minimum_slang_opt: bool,
    disable_non_essential_validations: bool,
    skip_spirv_validation: bool,
    report_downstream_time: bool,
    report_perf: bool,
    report_detailed_perf: bool,
    debug: bool,
    extra_args: Vec<String>,
    compile_stamp: String,
}

fn compile_shader_jobs(
    jobs: Vec<ShaderCompileJob>,
    shader_root: &Path,
    slangc: &Path,
    timeout: Option<Duration>,
    max_shader_spv_bytes: Option<u64>,
) -> Result<Vec<(String, PathBuf, PathBuf)>> {
    let job_count = jobs.len();
    if job_count == 0 {
        return Ok(Vec::new());
    }

    let worker_count = shader_build_jobs(job_count)?;
    let queue = Arc::new(Mutex::new(VecDeque::from(jobs)));
    let (tx, rx) = mpsc::channel();

    thread::scope(|scope| {
        for _ in 0..worker_count {
            let queue = Arc::clone(&queue);
            let tx = tx.clone();
            let shader_root = shader_root.to_path_buf();
            let slangc = slangc.to_path_buf();
            scope.spawn(move || {
                loop {
                    let job = {
                        let mut queue = queue
                            .lock()
                            .expect("shader compile queue lock should not be poisoned");
                        queue.pop_front()
                    };
                    let Some(job) = job else {
                        break;
                    };
                    let result = compile_shader_job(
                        job,
                        &shader_root,
                        &slangc,
                        timeout,
                        max_shader_spv_bytes,
                    );
                    if tx.send(result).is_err() {
                        break;
                    }
                }
            });
        }
        drop(tx);

        let mut compiled = Vec::with_capacity(job_count);
        for result in rx {
            compiled.push(result?);
        }
        Ok(compiled)
    })
}

fn shader_build_jobs(job_count: usize) -> Result<usize> {
    let default = thread::available_parallelism()
        .map(usize::from)
        .unwrap_or(1)
        .clamp(1, 8)
        .min(job_count);
    let value = match env::var("LANIUS_SHADER_BUILD_JOBS") {
        Ok(value) => value,
        Err(env::VarError::NotPresent) => return Ok(default),
        Err(env::VarError::NotUnicode(_)) => {
            return Err(anyhow!(
                "LANIUS_SHADER_BUILD_JOBS must be a UTF-8 positive integer"
            ));
        }
    };
    let value = value.trim();
    if value.is_empty() {
        return Ok(default);
    }
    let parsed = value
        .parse::<usize>()
        .with_context(|| format!("parse LANIUS_SHADER_BUILD_JOBS={value:?}"))?;
    Ok(parsed.clamp(1, job_count))
}

fn compile_shader_job(
    job: ShaderCompileJob,
    shader_root: &Path,
    slangc: &Path,
    timeout: Option<Duration>,
    max_shader_spv_bytes: Option<u64>,
) -> Result<(String, PathBuf, PathBuf)> {
    let mut cmd = Command::new(slangc);
    cmd.arg("-target")
        .arg("spirv")
        .arg("-profile")
        .arg("glsl_450")
        .arg("-fvk-use-entrypoint-name")
        .arg("-reflection-json")
        .arg(&job.refl_out)
        .arg("-emit-spirv-directly")
        .arg(format!("-O{}", job.opt_level))
        .arg("-I")
        .arg(shader_root)
        .arg("-I")
        .arg(shader_root.join("lexer"))
        .arg("-I")
        .arg(shader_root.join("parser"))
        .arg("-I")
        .arg(shader_root.join("type_checker"))
        .arg("-I")
        .arg(shader_root.join("codegen"))
        .arg("-o")
        .arg(&job.spv_out);

    if job.minimum_slang_opt {
        cmd.arg("-minimum-slang-optimization");
    }
    if job.disable_non_essential_validations {
        cmd.arg("-disable-non-essential-validations");
    }
    if job.skip_spirv_validation {
        cmd.arg("-skip-spirv-validation");
    }
    if job.report_downstream_time {
        cmd.arg("-report-downstream-time");
    }
    if job.report_perf {
        cmd.arg("-report-perf-benchmark");
    }
    if job.report_detailed_perf {
        cmd.arg("-report-detailed-perf-benchmark");
    }
    if job.debug {
        cmd.arg("-g3");
    }
    for arg in &job.extra_args {
        cmd.arg(arg);
    }
    cmd.arg(&job.ep);

    let out = command_output_with_timeout(&mut cmd, timeout)
        .with_context(|| format!("failed running slangc for {:?}", job.ep))?;
    if !out.stdout.is_empty() {
        for line in String::from_utf8_lossy(&out.stdout).lines() {
            println!("cargo:warning=slangc {} STDOUT: {line}", job.artifact_key);
        }
    }
    if !out.stderr.is_empty() {
        for line in String::from_utf8_lossy(&out.stderr).lines() {
            eprintln!("slangc {}: {line}", job.artifact_key);
        }
    }
    if !out.status.success() {
        return Err(anyhow!(
            "slangc failed on {:?} (exit: {:?}). See diagnostics above.",
            job.ep,
            out.status.code()
        ));
    }
    validate_shader_artifact_size(&job.ep, &job.spv_out, max_shader_spv_bytes)?;
    fs::write(&job.stamp_out, &job.compile_stamp)
        .with_context(|| format!("write shader stamp {}", job.stamp_out.display()))?;
    Ok((job.artifact_key, job.spv_out, job.refl_out))
}

fn command_output_with_timeout(
    command: &mut Command,
    timeout: Option<Duration>,
) -> io::Result<Output> {
    let Some(timeout) = timeout else {
        return command.output();
    };

    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = command.spawn()?;
    let start = Instant::now();
    loop {
        if child.try_wait()?.is_some() {
            return child.wait_with_output();
        }
        if start.elapsed() >= timeout {
            if let Err(err) = child.kill()
                && err.kind() != io::ErrorKind::InvalidInput
            {
                return Err(err);
            }
            let _ = child.wait_with_output();
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                format!("command timed out after {} ms", timeout.as_millis()),
            ));
        }
        thread::sleep(Duration::from_millis(10));
    }
}

fn shader_artifact_digest(artifacts: &[(String, PathBuf, PathBuf)]) -> Result<String> {
    let mut hash = StableHasher::new();
    for (name, spv, refl) in artifacts {
        hash.update(name.as_bytes());
        hash.update(&[0]);
        hash.update(
            &fs::read(spv).with_context(|| format!("read shader artifact {}", spv.display()))?,
        );
        hash.update(&[0]);
        hash.update(
            &fs::read(refl)
                .with_context(|| format!("read shader reflection artifact {}", refl.display()))?,
        );
        hash.update(&[0xff]);
    }
    Ok(hash.finish_hex())
}

struct ShaderArtifactSizeSummary {
    count: usize,
    max_spv_bytes: u64,
    max_spv_name: String,
}

struct ShaderArtifactBuildMetadata {
    digest: String,
    count: usize,
    max_spv_bytes: u64,
    max_spv_name: String,
    size_guard_status: String,
    size_guard_max_bytes: String,
}

fn write_shader_artifact_metadata(
    shader_out_dir: &Path,
    metadata: &ShaderArtifactBuildMetadata,
) -> Result<()> {
    let path = shader_out_dir.join("artifacts.env");
    let text = format!(
        "digest={}\ncount={}\nmax_spv_bytes={}\nmax_spv_name={}\nsize_guard_status={}\nsize_guard_max_bytes={}\n",
        metadata.digest,
        metadata.count,
        metadata.max_spv_bytes,
        metadata.max_spv_name,
        metadata.size_guard_status,
        metadata.size_guard_max_bytes,
    );
    write_if_changed(&path, text.as_bytes())
        .with_context(|| format!("write shader artifact metadata {}", path.display()))
}

fn write_generated_shader_artifacts(
    out_dir: &Path,
    artifacts: &[(String, PathBuf, PathBuf)],
) -> Result<()> {
    let path = out_dir.join("shader_artifacts_generated.rs");
    let mut text = String::new();
    text.push_str("#[cfg(any(not(debug_assertions), target_arch = \"wasm32\"))]\n");
    text.push_str("pub(super) fn embedded_artifact(file: &str) -> Option<&'static [u8]> {\n");
    text.push_str("    match file {\n");
    for (key, spv, reflection) in artifacts {
        let spv_file = format!("{key}.spv");
        let reflection_file = format!("{key}.reflect.json");
        text.push_str(&format!(
            "        {spv_file:?} => Some(include_bytes!({spv:?})),\n"
        ));
        text.push_str(&format!(
            "        {reflection_file:?} => Some(include_bytes!({reflection:?})),\n"
        ));
    }
    text.push_str("        _ => None,\n");
    text.push_str("    }\n");
    text.push_str("}\n\n");
    text.push_str("#[cfg(all(debug_assertions, not(target_arch = \"wasm32\")))]\n");
    text.push_str("pub(super) fn embedded_artifact(_file: &str) -> Option<&'static [u8]> {\n");
    text.push_str("    None\n");
    text.push_str("}\n");
    write_if_changed(&path, text.as_bytes())
        .with_context(|| format!("write generated shader artifact lookup {}", path.display()))
}

fn write_if_changed(path: &Path, bytes: &[u8]) -> Result<()> {
    if fs::read(path).ok().as_deref() == Some(bytes) {
        return Ok(());
    }
    fs::write(path, bytes)?;
    Ok(())
}

fn remove_stale_shader_artifacts(
    shader_out_dir: &Path,
    active_keys: &HashSet<String>,
) -> Result<()> {
    fn walk(dir: &Path, shader_out_dir: &Path, active_keys: &HashSet<String>) -> Result<()> {
        let Ok(read_dir) = fs::read_dir(dir) else {
            return Ok(());
        };
        for entry in read_dir {
            let entry = entry?;
            let path = entry.path();
            let file_type = entry.file_type()?;
            if file_type.is_dir() {
                walk(&path, shader_out_dir, active_keys)?;
                remove_dir_if_empty(&path)?;
                continue;
            }
            if !file_type.is_file() {
                continue;
            }
            let Some(key) = shader_artifact_key_from_output_path(shader_out_dir, &path)? else {
                continue;
            };
            if !active_keys.contains(&key) {
                fs::remove_file(&path)
                    .with_context(|| format!("remove stale shader artifact {}", path.display()))?;
            }
        }
        Ok(())
    }

    walk(shader_out_dir, shader_out_dir, active_keys)
}

fn remove_dir_if_empty(path: &Path) -> Result<()> {
    if fs::read_dir(path)?.next().is_none() {
        fs::remove_dir(path)
            .with_context(|| format!("remove empty shader artifact dir {}", path.display()))?;
    }
    Ok(())
}

fn shader_artifact_key_from_output_path(
    shader_out_dir: &Path,
    path: &Path,
) -> Result<Option<String>> {
    let rel = path.strip_prefix(shader_out_dir).with_context(|| {
        format!(
            "shader output {} is outside {}",
            path.display(),
            shader_out_dir.display()
        )
    })?;
    let rel = rel.to_string_lossy().replace('\\', "/");
    let key = rel
        .strip_suffix(".reflect.json")
        .or_else(|| rel.strip_suffix(".spv"))
        .or_else(|| rel.strip_suffix(".stamp"));
    Ok(key.map(str::to_string))
}

fn emit_shader_artifact_rustc_env(metadata: &ShaderArtifactBuildMetadata) {
    println!(
        "cargo:rustc-env=LANIUS_SHADER_ARTIFACT_DIGEST={}",
        metadata.digest
    );
    println!(
        "cargo:rustc-env=LANIUS_SHADER_ARTIFACT_COUNT={}",
        metadata.count
    );
    println!(
        "cargo:rustc-env=LANIUS_SHADER_ARTIFACT_MAX_BYTES={}",
        metadata.max_spv_bytes
    );
    println!(
        "cargo:rustc-env=LANIUS_SHADER_ARTIFACT_MAX_NAME={}",
        metadata.max_spv_name
    );
    println!(
        "cargo:rustc-env=LANIUS_SHADER_SIZE_GUARD_STATUS={}",
        metadata.size_guard_status
    );
    println!(
        "cargo:rustc-env=LANIUS_SHADER_SIZE_GUARD_MAX_BYTES={}",
        metadata.size_guard_max_bytes
    );
}

fn runtime_loaded_debug_shader_artifacts() -> bool {
    env::var_os("CARGO_CFG_DEBUG_ASSERTIONS").is_some()
        && env::var("CARGO_CFG_TARGET_ARCH").ok().as_deref() != Some("wasm32")
}

fn shader_artifact_size_summary(
    artifacts: &[(String, PathBuf, PathBuf)],
) -> Result<ShaderArtifactSizeSummary> {
    let mut summary = ShaderArtifactSizeSummary {
        count: 0,
        max_spv_bytes: 0,
        max_spv_name: "none".to_string(),
    };
    for (name, spv, _) in artifacts {
        let size = fs::metadata(spv)
            .with_context(|| format!("stat shader artifact {}", spv.display()))?
            .len();
        summary.count += 1;
        if size > summary.max_spv_bytes {
            summary.max_spv_bytes = size;
            summary.max_spv_name = name.clone();
        }
    }
    Ok(summary)
}

fn shader_size_guard_build_metadata(max_shader_spv_bytes: Option<u64>) -> (&'static str, String) {
    match max_shader_spv_bytes {
        Some(max_bytes) => ("enforced", max_bytes.to_string()),
        None => ("disabled", "disabled".to_string()),
    }
}

struct StableHasher {
    value: u64,
}

impl StableHasher {
    fn new() -> Self {
        Self {
            value: 0xcbf29ce484222325,
        }
    }

    fn update(&mut self, bytes: &[u8]) {
        for byte in bytes {
            self.value ^= u64::from(*byte);
            self.value = self.value.wrapping_mul(0x100000001b3);
        }
    }

    fn finish_hex(&self) -> String {
        format!("{:016x}", self.value)
    }
}

fn is_unwired_shader_entrypoint(shader_root: &Path, path: &Path) -> Result<bool> {
    let rel = path.strip_prefix(shader_root).with_context(|| {
        format!(
            "shader path {} is outside {}",
            path.display(),
            shader_root.display()
        )
    })?;
    let rel = rel.to_string_lossy().replace('\\', "/");
    Ok(matches!(
        rel.as_str(),
        "codegen/x86_virtual_liveness_dispatch_args.slang"
            | "codegen/x86_virtual_use_counts.slang"
            | "codegen/x86_virtual_use_edges.slang"
            | "codegen/x86_virtual_use_scan_blocks.slang"
            | "codegen/x86_virtual_use_scan_local.slang"
            | "codegen/x86/virtual/liveness/dispatch_args.slang"
            | "codegen/x86/virtual/use/counts.slang"
            | "codegen/x86/virtual/use/edges.slang"
            | "codegen/x86/virtual/use/scan/blocks.slang"
            | "codegen/x86/virtual/use/scan/local.slang"
            | "codegen/wasm/hir/body_scatter_direct.slang"
    ))
}

fn shader_artifact_key(shader_root: &Path, path: &Path) -> Result<String> {
    let rel = path.strip_prefix(shader_root).with_context(|| {
        format!(
            "shader path {} is outside {}",
            path.display(),
            shader_root.display()
        )
    })?;
    let no_ext = rel.with_extension("");
    let mut key = String::new();
    for component in no_ext.components() {
        if !key.is_empty() {
            key.push('/');
        }
        key.push_str(
            component
                .as_os_str()
                .to_str()
                .ok_or_else(|| anyhow!("non-utf8 shader artifact path {}", path.display()))?,
        );
    }
    if key.is_empty() {
        return Err(anyhow!("empty shader artifact key for {}", path.display()));
    }
    Ok(key)
}

fn shader_outputs_fresh(
    shader_root: &Path,
    ep: &Path,
    spv_out: &Path,
    refl_out: &Path,
    stamp_out: &Path,
    compile_stamp: &str,
) -> Result<bool> {
    if fs::read_to_string(stamp_out).ok().as_deref() != Some(compile_stamp) {
        return Ok(false);
    }
    let output_mtime = oldest_mtime([spv_out, refl_out, stamp_out]);
    let Some(output_mtime) = output_mtime else {
        return Ok(false);
    };

    let mut deps = Vec::new();
    let mut seen = HashSet::new();
    collect_shader_dependencies(shader_root, ep, &mut seen, &mut deps)?;
    for dep in deps {
        let input_mtime = fs::metadata(&dep)
            .and_then(|metadata| metadata.modified())
            .with_context(|| format!("read shader dependency mtime for {}", dep.display()))?;
        if input_mtime > output_mtime {
            return Ok(false);
        }
    }
    Ok(true)
}

fn oldest_mtime<const N: usize>(paths: [&Path; N]) -> Option<SystemTime> {
    paths
        .into_iter()
        .map(|path| {
            fs::metadata(path)
                .and_then(|metadata| metadata.modified())
                .ok()
        })
        .try_fold(None, |oldest, mtime| {
            let mtime = mtime?;
            Some(Some(match oldest {
                Some(oldest) if oldest <= mtime => oldest,
                _ => mtime,
            }))
        })
        .flatten()
}

fn collect_shader_dependencies(
    shader_root: &Path,
    path: &Path,
    seen: &mut HashSet<PathBuf>,
    out: &mut Vec<PathBuf>,
) -> Result<()> {
    let path = path.to_path_buf();
    if !seen.insert(path.clone()) {
        return Ok(());
    }
    out.push(path.clone());

    let text = fs::read_to_string(&path)
        .with_context(|| format!("read shader dependency {}", path.display()))?;
    for import in shader_imports(&text) {
        let dep = resolve_shader_import(shader_root, &path, import).ok_or_else(|| {
            anyhow!(
                "unresolved shader import `{import}` while collecting dependencies for {}",
                path.display()
            )
        })?;
        collect_shader_dependencies(shader_root, &dep, seen, out)?;
    }
    Ok(())
}

fn shader_imports(text: &str) -> impl Iterator<Item = &str> {
    text.lines().filter_map(|line| {
        let line = line.split("//").next().unwrap_or("").trim();
        let rest = line.strip_prefix("import ")?;
        rest.strip_suffix(';').map(str::trim)
    })
}

fn resolve_shader_import(shader_root: &Path, importer: &Path, import: &str) -> Option<PathBuf> {
    let rel = PathBuf::from(format!(
        "{}.slang",
        import.replace("::", "/").replace('.', "/")
    ));
    let mut candidates = Vec::new();
    if let Some(parent) = importer.parent() {
        candidates.push(parent.join(&rel));
    }
    candidates.extend([
        shader_root.join(&rel),
        shader_root.join("lexer").join(&rel),
        shader_root.join("parser").join(&rel),
        shader_root.join("type_checker").join(&rel),
        shader_root.join("codegen").join(&rel),
    ]);
    candidates.into_iter().find(|candidate| candidate.is_file())
}

fn find_slangc() -> Result<PathBuf> {
    if let Ok(p) = env::var("SLANGC") {
        let pb = PathBuf::from(p);
        if pb.is_file() {
            return Ok(pb);
        }
    }
    if let Ok(pb) = which::which("slangc") {
        return Ok(pb);
    }
    if let Ok(ld) = env::var("LD_LIBRARY_PATH") {
        for comp in ld.split(':') {
            let p = Path::new(comp);
            if p.ends_with("lib")
                && let Some(c) = p.parent().map(|x| x.join("bin").join("slangc"))
                && c.is_file()
            {
                return Ok(c);
            }
        }
    }
    Err(anyhow!("`slangc` not found"))
}

fn track_dir_recursively<P: AsRef<Path>>(dir: P) {
    let path = dir.as_ref();

    println!("cargo:rerun-if-changed={}", path.display());

    let Ok(read_dir) = fs::read_dir(path) else {
        return;
    };
    for entry in read_dir.flatten() {
        let p = entry.path();
        let Ok(ft) = entry.file_type() else {
            continue;
        };

        #[cfg(unix)]
        if ft.is_symlink() {
            continue;
        }

        if ft.is_dir() {
            track_dir_recursively(&p);
        } else if ft.is_file() {
            println!("cargo:rerun-if-changed={}", p.display());
        }
    }
}

fn collect_slang_sources(root: &Path) -> io::Result<Vec<PathBuf>> {
    let mut out = Vec::new();
    fn walk(dir: &Path, out: &mut Vec<PathBuf>) -> io::Result<()> {
        for ent in fs::read_dir(dir)? {
            let ent = ent?;
            let p = ent.path();
            if p.is_dir() {
                walk(&p, out)?;
            } else if p.extension().and_then(|e| e.to_str()) == Some("slang") {
                out.push(p);
            }
        }
        Ok(())
    }
    walk(root, &mut out)?;
    Ok(out)
}

/// Heuristic: does this source contain a Slang entrypoint attribute?
/// We detect `[shader("...")]` anywhere in the file.
fn has_entrypoint(path: &Path) -> io::Result<bool> {
    let text = fs::read_to_string(path)?;
    Ok(text.contains("[shader(\"") || text.contains("[shader('") || text.contains("[shader("))
}

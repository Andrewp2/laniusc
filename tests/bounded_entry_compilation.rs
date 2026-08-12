mod common;

use std::path::{Path, PathBuf};

use laniusc_compiler::{
    codegen::unit::{CompilationUnitLimits, SourcePackBuildShardLimits, SourcePackJobBatchLimits},
    compiler::{
        CompileError,
        ExplicitSourceLibraryPathStream,
        ExplicitSourceLibraryPaths,
        FilesystemArtifactStore,
        GpuSourcePackArtifactDescriptor,
        compile_entry_to_wasm_with_source_root,
        compile_entry_to_x86_64_with_source_root,
        compile_source_pack_path_manifest_to_x86_64_with_gpu_codegen,
        run_path_stream_worker_to_wasm,
        run_path_stream_worker_to_x86_64,
    },
    gpu::buffers::{reset_tracked_buffer_allocation_peaks, tracked_buffer_allocation_peak_stats},
};

const IMPORTED_MODULE_COUNT: usize = 65;

#[cfg(all(unix, target_arch = "x86_64"))]
#[test]
#[ignore = "materializes and compiles a 1 GiB physical-GPU source pack"]
fn one_gibibyte_project_keeps_gpu_workspace_bounded_by_unit_size() {
    const MIB: usize = 1024 * 1024;
    const PEAK_METADATA_ALLOWANCE: u64 = 128 * MIB as u64;
    let max_unit_bytes = std::env::var("LANIUS_BOUNDED_SCALE_MAX_UNIT_BYTES")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(5 * MIB);

    let baseline = ScaleProject::create(
        "baseline",
        max_unit_bytes + max_unit_bytes / 2,
        max_unit_bytes,
    );
    reset_tracked_buffer_allocation_peaks();
    let elf = run_scale_worker(&baseline).expect("bounded baseline should compile to x86_64");
    assert_eq!(
        common::run_x86_64_elf_output("bounded scale baseline", "bounded_scale", &elf)
            .status
            .code(),
        Some(1),
    );
    let baseline_peak = tracked_buffer_allocation_peak_stats();
    drop(baseline);

    let target_module_bytes = std::env::var("LANIUS_BOUNDED_SCALE_TOTAL_BYTES")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(1024 * MIB);
    let project = match std::env::var_os("LANIUS_BOUNDED_SCALE_PROJECT_ROOT") {
        Some(root) => ScaleProject::open(PathBuf::from(root)),
        None => ScaleProject::create("one_gib", target_module_bytes, max_unit_bytes),
    };
    reset_tracked_buffer_allocation_peaks();
    assert_eq!(
        project.source_bytes(),
        target_module_bytes + project.entry_bytes()
    );
    let expected_exit = project.expected_exit_code();
    let elf = run_scale_worker(&project).expect("one GiB bounded project should compile to x86_64");
    assert_eq!(
        common::run_x86_64_elf_output("one GiB bounded execution", "bounded_one_gib", &elf)
            .status
            .code(),
        Some(expected_exit),
    );
    let project_peak = tracked_buffer_allocation_peak_stats();
    eprintln!(
        "bounded_scale_memory baseline_peak_bytes={} baseline_peak_allocations={} project_peak_bytes={} project_peak_allocations={}",
        baseline_peak.bytes,
        baseline_peak.allocations,
        project_peak.bytes,
        project_peak.allocations,
    );
    assert!(
        project_peak.bytes <= baseline_peak.bytes + PEAK_METADATA_ALLOWANCE,
        "one GiB project peak {} exceeded bounded baseline peak {} plus {} bytes of interface/link metadata",
        project_peak.bytes,
        baseline_peak.bytes,
        PEAK_METADATA_ALLOWANCE,
    );
}

#[test]
fn bounded_entry_compilation_emits_runnable_wasm_across_units() {
    common::require_node();
    let project = MultiUnitProject::create("wasm");
    let entry = project.entry().to_path_buf();
    let source_root = project.source_root().to_path_buf();
    let wasm = common::run_gpu_codegen_with_timeout("bounded Wasm entry compilation", move || {
        pollster::block_on(compile_entry_to_wasm_with_source_root(entry, source_root))
    })
    .expect("multi-unit entry should compile to Wasm");

    assert_eq!(
        common::run_wasm_main_return_with_node(
            "bounded Wasm entry execution",
            "bounded_entry",
            &wasm,
        ),
        64
    );
}

#[cfg(all(unix, target_arch = "x86_64"))]
#[test]
fn bounded_entry_compilation_emits_runnable_x86_64_across_units() {
    let project = MultiUnitProject::create("x86");
    let entry = project.entry().to_path_buf();
    let source_root = project.source_root().to_path_buf();
    let elf = common::run_gpu_codegen_with_timeout("bounded x86 entry compilation", move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_root(entry, source_root))
    })
    .expect("multi-unit entry should compile to x86_64");

    let output =
        common::run_x86_64_elf_output("bounded x86 entry execution", "bounded_entry", &elf);
    assert_eq!(output.status.code(), Some(64));
}

#[test]
fn bounded_wasm_worker_emits_runnable_output_through_multiple_link_levels() {
    common::require_node();
    let project = SmallLimitProject::create("wasm");
    let (wasm, link_group_count) = run_small_limit_worker(&project, SmallLimitTarget::Wasm);
    assert!(
        link_group_count >= 3,
        "small link fanout should force multiple hierarchical groups"
    );
    assert_eq!(
        common::run_wasm_main_return_with_node(
            "hierarchical Wasm entry execution",
            "hierarchical_bounded_entry",
            &wasm,
        ),
        4
    );
}

#[cfg(all(unix, target_arch = "x86_64"))]
#[test]
fn bounded_x86_worker_emits_runnable_output_through_multiple_link_levels() {
    let project = SmallLimitProject::create("x86");
    let (elf, link_group_count) = run_small_limit_worker(&project, SmallLimitTarget::X86_64);
    assert!(
        link_group_count >= 3,
        "small link fanout should force multiple hierarchical groups"
    );
    let output = common::run_x86_64_elf_output(
        "hierarchical x86 entry execution",
        "hierarchical_bounded_entry",
        &elf,
    );
    assert_eq!(output.status.code(), Some(4));
}

#[derive(Clone, Copy)]
enum SmallLimitTarget {
    Wasm,
    X86_64,
}

fn run_small_limit_worker(
    project: &SmallLimitProject,
    target: SmallLimitTarget,
) -> (Vec<u8>, usize) {
    let paths = project.paths.clone();
    let artifact_root = project.root.join("artifacts");
    let worker_root = artifact_root.clone();
    common::run_gpu_codegen_with_timeout("small-limit hierarchical compilation", move || {
        let limits = CompilationUnitLimits {
            max_source_bytes: 1024,
            max_source_files: 1,
        };
        let batch_limits = SourcePackJobBatchLimits {
            max_jobs_per_batch: 2,
            max_source_bytes_per_batch: 2048,
            max_source_files_per_batch: 2,
        };
        let mut executed_link_group_count = 0usize;
        for _ in 0..128 {
            let libraries = vec![ExplicitSourceLibraryPathStream {
                library_id: 1,
                source_file_count: paths.len(),
                paths: paths.clone(),
                dependency_library_ids: Vec::new(),
            }];
            let run = match target {
                SmallLimitTarget::Wasm => pollster::block_on(run_path_stream_worker_to_wasm(
                    libraries,
                    &worker_root,
                    limits,
                    batch_limits,
                    SourcePackBuildShardLimits::default(),
                    "small-limit-wasm-worker",
                    64,
                    None,
                    64,
                )),
                SmallLimitTarget::X86_64 => pollster::block_on(run_path_stream_worker_to_x86_64(
                    libraries,
                    &worker_root,
                    limits,
                    batch_limits,
                    SourcePackBuildShardLimits::default(),
                    "small-limit-x86-worker",
                    64,
                    None,
                    64,
                )),
            };
            match run {
                Ok(run) => {
                    executed_link_group_count =
                        executed_link_group_count.saturating_add(run.executed_link_group_count);
                    if run.progress.complete {
                        let linked_output_path = run.linked_output_path.ok_or_else(|| {
                            CompileError::GpuCodegen(
                                "completed hierarchical build did not report target output".into(),
                            )
                        })?;
                        let descriptor_bytes = std::fs::read(&linked_output_path).map_err(|err| {
                            CompileError::GpuCodegen(format!(
                                "read hierarchical linked-output descriptor {}: {err}",
                                linked_output_path.display()
                            ))
                        })?;
                        let descriptor: GpuSourcePackArtifactDescriptor =
                            serde_json::from_slice(&descriptor_bytes).map_err(|err| {
                                CompileError::GpuCodegen(format!(
                                    "parse hierarchical linked-output descriptor {}: {err}",
                                    linked_output_path.display()
                                ))
                            })?;
                        let storage_key = descriptor
                            .output_record_arrays
                            .iter()
                            .chain(descriptor.record_arrays.iter())
                            .find(|array| array.name == "emitted_byte_records")
                            .and_then(|array| array.storage_key.as_deref())
                            .ok_or_else(|| {
                                CompileError::GpuCodegen(
                                    "hierarchical linked-output descriptor has no emitted-byte artifact"
                                        .into(),
                                )
                            })?;
                        let output_path = FilesystemArtifactStore::new(&worker_root)
                            .path_for_key(storage_key)?;
                        let bytes = std::fs::read(&output_path).map_err(|err| {
                            CompileError::GpuCodegen(format!(
                                "read hierarchical target output {}: {err}",
                                output_path.display()
                            ))
                        })?;
                        return Ok((bytes, executed_link_group_count));
                    }
                }
                Err(CompileError::Diagnostic(diagnostic)) if diagnostic.code == "LNC0064" => {}
                Err(err) => return Err(err),
            }
        }
        Err(CompileError::GpuCodegen(
            "hierarchical worker did not complete after 128 bounded runs".into(),
        ))
    })
    .expect("small-limit hierarchical build should emit target bytes")
}

struct MultiUnitProject {
    root: PathBuf,
    source_root: PathBuf,
    entry: PathBuf,
}

impl MultiUnitProject {
    fn create(target: &str) -> Self {
        let root = common::temp_artifact_path(
            "laniusc_bounded_entry",
            &format!("multi_unit_{target}"),
            None,
        );
        let source_root = root.join("src");
        let app_root = source_root.join("app");
        std::fs::create_dir_all(&app_root).expect("create bounded entry source root");

        for index in 0..IMPORTED_MODULE_COUNT {
            std::fs::write(
                app_root.join(format!("m{index:02}.lani")),
                format!("module app::m{index:02};\npub fn value() -> i32 {{ return {index}; }}\n"),
            )
            .expect("write bounded entry module");
        }
        let imports = (0..IMPORTED_MODULE_COUNT)
            .map(|index| format!("import app::m{index:02};\n"))
            .collect::<String>();
        let entry = root.join("main.lani");
        std::fs::write(
            &entry,
            format!(
                "module app::main;\n{imports}fn main() -> i32 {{ return app::m64::value(); }}\n"
            ),
        )
        .expect("write bounded entry point");

        Self {
            root,
            source_root,
            entry,
        }
    }

    fn source_root(&self) -> &Path {
        &self.source_root
    }

    fn entry(&self) -> &Path {
        &self.entry
    }
}

impl Drop for MultiUnitProject {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

struct SmallLimitProject {
    root: PathBuf,
    paths: Vec<PathBuf>,
}

impl SmallLimitProject {
    fn create(target: &str) -> Self {
        let root = common::temp_artifact_path(
            "laniusc_hierarchical_entry",
            &format!("small_limit_{target}"),
            None,
        );
        let source_root = root.join("src");
        std::fs::create_dir_all(&source_root).expect("create hierarchical source root");
        let mut paths = Vec::new();
        for index in 0..4 {
            let path = source_root.join(format!("m{index}.lani"));
            std::fs::write(
                &path,
                format!("module app::m{index};\npub fn value() -> i32 {{ return {index}; }}\n"),
            )
            .expect("write hierarchical module");
            paths.push(path);
        }
        let entry = source_root.join("main.lani");
        std::fs::write(
            &entry,
            "module app::main;\nimport app::m3;\nfn main() -> i32 { return app::m3::value() + 1; }\n",
        )
        .expect("write hierarchical entry");
        paths.push(entry);
        Self { root, paths }
    }
}

impl Drop for SmallLimitProject {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

struct ScaleProject {
    root: PathBuf,
    paths: Vec<PathBuf>,
    source_bytes: usize,
    entry_bytes: usize,
}

impl ScaleProject {
    fn create(label: &str, total_module_bytes: usize, max_module_bytes: usize) -> Self {
        assert!(total_module_bytes != 0);
        assert!(max_module_bytes != 0);
        let module_count = total_module_bytes.div_ceil(max_module_bytes);
        let root = common::temp_artifact_path("laniusc_bounded_scale", label, None);
        let source_root = root.join("src");
        let app_root = source_root.join("app");
        std::fs::create_dir_all(&app_root).expect("create bounded scale source root");

        let mut paths = Vec::with_capacity(module_count + 1);
        let mut remaining_bytes = total_module_bytes;
        for index in 0..module_count {
            let module_bytes = remaining_bytes.min(max_module_bytes);
            let mut source = vec![b' '; module_bytes];
            let header =
                format!("module app::m{index};\npub fn value() -> i32 {{ return {index}; }}\n");
            assert!(header.len() <= source.len());
            source[..header.len()].copy_from_slice(header.as_bytes());
            let path = app_root.join(format!("m{index}.lani"));
            std::fs::write(&path, &source).expect("write bounded scale module");
            paths.push(path);
            remaining_bytes -= module_bytes;
        }
        assert_eq!(remaining_bytes, 0);

        let last = module_count - 1;
        let entry = root.join("main.lani");
        let entry_source = format!(
            "module app::main;\nimport app::m{last};\nfn main() -> i32 {{ return app::m{last}::value(); }}\n"
        );
        std::fs::write(&entry, &entry_source).expect("write bounded scale entry point");
        paths.push(entry);
        Self {
            root,
            paths,
            source_bytes: total_module_bytes + entry_source.len(),
            entry_bytes: entry_source.len(),
        }
    }

    fn source_bytes(&self) -> usize {
        self.source_bytes
    }

    fn entry_bytes(&self) -> usize {
        self.entry_bytes
    }

    fn expected_exit_code(&self) -> i32 {
        self.paths.len().saturating_sub(2) as i32 & 0xff
    }

    fn open(root: PathBuf) -> Self {
        let app_root = root.join("src/app");
        let mut indexed_paths = std::fs::read_dir(&app_root)
            .expect("read existing bounded scale source root")
            .map(|entry| {
                let path = entry.expect("read bounded scale source entry").path();
                let index = path
                    .file_stem()
                    .and_then(|stem| stem.to_str())
                    .and_then(|stem| stem.strip_prefix('m'))
                    .and_then(|index| index.parse::<usize>().ok())
                    .expect("bounded scale module filename should contain a numeric index");
                (index, path)
            })
            .collect::<Vec<_>>();
        indexed_paths.sort_unstable_by_key(|(index, _)| *index);
        let mut paths = indexed_paths
            .into_iter()
            .map(|(_, path)| path)
            .collect::<Vec<_>>();
        let entry = root.join("main.lani");
        let entry_bytes = std::fs::metadata(&entry)
            .expect("stat existing bounded scale entry")
            .len() as usize;
        let source_bytes = paths.iter().fold(entry_bytes, |total, path| {
            total
                + std::fs::metadata(path)
                    .expect("stat existing bounded scale module")
                    .len() as usize
        });
        paths.push(entry);
        Self {
            root,
            paths,
            source_bytes,
            entry_bytes,
        }
    }
}

impl Drop for ScaleProject {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn run_scale_worker(project: &ScaleProject) -> Result<Vec<u8>, CompileError> {
    let paths = project.paths.clone();
    common::run_gpu_codegen_with_timeout("bounded scale source-pack compile", move || {
        let manifest =
            laniusc_compiler::compiler::ExplicitSourcePackPathManifest::from_libraries(vec![
                ExplicitSourceLibraryPaths {
                    library_id: 1,
                    paths,
                    dependency_library_ids: Vec::new(),
                },
            ])?;
        pollster::block_on(compile_source_pack_path_manifest_to_x86_64_with_gpu_codegen(&manifest))
    })
}

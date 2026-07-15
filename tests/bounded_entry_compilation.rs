mod common;

use std::path::{Path, PathBuf};

use laniusc_compiler::{
    codegen::unit::{CodegenUnitLimits, SourcePackBuildShardLimits, SourcePackJobBatchLimits},
    compiler::{
        CompileError,
        ExplicitSourceLibraryPathStream,
        compile_entry_to_wasm_with_source_root,
        compile_entry_to_x86_64_with_source_root,
        run_path_stream_worker_to_wasm,
        run_path_stream_worker_to_x86_64,
    },
};

const IMPORTED_MODULE_COUNT: usize = 65;

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
        let limits = CodegenUnitLimits {
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
                        let bytes = std::fs::read(&linked_output_path).map_err(|err| {
                            CompileError::GpuCodegen(format!(
                                "read hierarchical target output {}: {err}",
                                linked_output_path.display()
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

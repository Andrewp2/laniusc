use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

use super::*;

static NEXT_BOUNDED_BUILD_ID: AtomicU64 = AtomicU64::new(0);

fn resident_source_unit_limits() -> CompilationUnitLimits {
    CompilationUnitLimits::default()
}

impl<'gpu> GpuCompiler<'gpu> {
    /// Compile a path-backed source pack to Wasm, retaining the resident fast
    /// path when it fits one unit and otherwise executing bounded units.
    pub async fn compile_path_manifest_to_wasm(
        &self,
        source_pack: &ExplicitSourcePackPathManifest,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_path_manifest(source_pack, SourcePackArtifactTarget::Wasm)
            .await
    }

    /// Compile a path-backed source pack to x86_64, retaining the resident fast
    /// path when it fits one unit and otherwise executing bounded units.
    pub async fn compile_path_manifest_to_x86_64(
        &self,
        source_pack: &ExplicitSourcePackPathManifest,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_path_manifest(source_pack, SourcePackArtifactTarget::X86_64)
            .await
    }

    async fn compile_path_manifest(
        &self,
        source_pack: &ExplicitSourcePackPathManifest,
        target: SourcePackArtifactTarget,
    ) -> Result<Vec<u8>, CompileError> {
        let limits = resident_source_unit_limits();
        // A manifest with multiple libraries must retain its dependency graph
        // even when the aggregate source fits the resident unit.  Flattening
        // such a manifest into one ordinary source-pack job erases library
        // identity and makes backend lowering observe declarations from the
        // wrong unit.  Use the same bounded-unit executor for this case; it is
        // still capacity-bounded and is the only path that persists semantic
        // interfaces between libraries.
        let has_multiple_libraries = source_pack
            .files
            .iter()
            .map(|file| file.library_id)
            .collect::<std::collections::BTreeSet<_>>()
            .len()
            > 1;
        let bounded =
            has_multiple_libraries || source_pack.requires_bounded_compilation_with_limits(limits);
        let report_memory = crate::gpu::env::env_bool_strict("LANIUS_GPU_BUFFER_BREAKDOWN", false);
        if report_memory {
            crate::gpu::buffers::reset_tracked_buffer_allocation_peaks();
        }
        let result = if bounded {
            self.compile_path_manifest_bounded(source_pack, target, limits)
                .await
        } else {
            let source_pack = load_explicit_source_pack_from_path_manifest(source_pack)?;
            match target {
                SourcePackArtifactTarget::Wasm => {
                    self.compile_source_pack_manifest_to_wasm(&source_pack)
                        .await
                }
                SourcePackArtifactTarget::X86_64 => {
                    self.compile_source_pack_manifest_to_x86_64(&source_pack)
                        .await
                }
                SourcePackArtifactTarget::Generic => unreachable!("concrete backend required"),
            }
        };
        if report_memory {
            let units = source_pack.frontend_unit_plan(limits);
            let peak = crate::gpu::buffers::tracked_buffer_allocation_peak_stats();
            eprintln!(
                "source_pack_scale target={target:?} mode={} source_bytes={} source_files={} units={} max_unit_bytes={} peak_gpu_bytes={} peak_gpu_allocations={}",
                if bounded { "bounded" } else { "resident" },
                source_pack
                    .files
                    .iter()
                    .map(|file| file.byte_len)
                    .sum::<usize>(),
                source_pack.files.len(),
                units.unit_count(),
                units.max_unit_source_bytes(),
                peak.bytes,
                peak.allocations,
            );
            if let Err(error) = &result {
                eprintln!("source_pack_scale_error error={error:?}");
            }
        }
        result
    }

    pub(in crate::compiler) async fn compile_path_manifest_bounded(
        &self,
        source_pack: &ExplicitSourcePackPathManifest,
        target: SourcePackArtifactTarget,
        limits: CompilationUnitLimits,
    ) -> Result<Vec<u8>, CompileError> {
        let artifact_root = TemporaryBoundedArtifactRoot::create()?;
        let libraries = path_manifest_libraries(source_pack)?;
        prepare_ordered_library_path_metadata_for_target(libraries, artifact_root.path(), target)?;

        let batch_limits = SourcePackJobBatchLimits::from_codegen_unit_limits(limits);
        let shard_limits = SourcePackBuildShardLimits::default();
        loop {
            let step = prepare_artifact_build_chunk(
                artifact_root.path(),
                limits,
                batch_limits,
                shard_limits,
                target,
                ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
            )?;
            if step.complete {
                break;
            }
            if step.new_item_count == 0 && step.stage == step.next_stage {
                return Err(source_pack_preparation_incomplete_error(format!(
                    "bounded source-pack preparation made no progress in stage {:?}",
                    step.stage
                )));
            }
        }

        let worker_id = format!("laniusc-bounded-{}", std::process::id());
        let linked_output_path = loop {
            let run = self
                .run_descriptor_work_queue(
                    artifact_root.path(),
                    target,
                    &worker_id,
                    SOURCE_PACK_WORK_QUEUE_WORKER_RUN_DEFAULT_ITEM_LIMIT,
                    None,
                    SOURCE_PACK_READY_STATE_ITEM_DEFAULT_LIMIT,
                )
                .await?;
            if run.progress.complete {
                break run.linked_output_path.ok_or_else(|| {
                    source_pack_artifact_store_error(
                        "completed bounded source-pack build did not report linked output",
                    )
                })?;
            }
            if run.executed_item_count == 0 {
                return Err(source_pack_preparation_incomplete_error(format!(
                    "bounded source-pack worker has no ready work after completing {} of {} items",
                    run.progress.completed_item_count, run.progress.work_item_count
                )));
            }
        };

        // The descriptor work queue returns the linked-output *contract*;
        // its emitted-byte record points at the concrete target artifact.
        // Return those bytes to the public compile API rather than exposing
        // the JSON descriptor itself.
        let descriptor_bytes = fs::read(&linked_output_path).map_err(|err| {
            source_pack_artifact_store_error(format!(
                "read bounded source-pack linked-output descriptor {}: {err}",
                linked_output_path.display()
            ))
        })?;
        let descriptor: GpuSourcePackArtifactDescriptor = serde_json::from_slice(&descriptor_bytes)
            .map_err(|err| {
                source_pack_artifact_store_error(format!(
                    "parse bounded source-pack linked-output descriptor {}: {err}",
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
                source_pack_artifact_store_error(
                    "bounded source-pack linked-output descriptor has no emitted-byte artifact",
                )
            })?;
        let artifact_path = artifact_path(artifact_root.path(), storage_key)?;
        fs::read(&artifact_path).map_err(|err| {
            source_pack_artifact_store_error(format!(
                "read bounded source-pack linked output {}: {err}",
                artifact_path.display()
            ))
        })
    }
}

fn path_manifest_libraries<'a>(
    source_pack: &'a ExplicitSourcePackPathManifest,
) -> Result<Vec<ExplicitSourceLibraryPaths<&'a Path>>, CompileError> {
    let mut libraries = Vec::new();
    let mut seen_library_ids = BTreeSet::new();
    let mut current_library_id = None;
    let mut current_paths = Vec::new();

    for file in &source_pack.files {
        if current_library_id != Some(file.library_id) {
            if let Some(library_id) = current_library_id {
                libraries.push(path_manifest_library(
                    source_pack,
                    library_id,
                    std::mem::take(&mut current_paths),
                ));
            }
            if !seen_library_ids.insert(file.library_id) {
                return Err(explicit_source_pack_manifest_invalid(
                    Some(file.library_id),
                    "path-backed source files for one library must be contiguous",
                ));
            }
            current_library_id = Some(file.library_id);
        }
        current_paths.push(file.path.as_path());
    }
    if let Some(library_id) = current_library_id {
        libraries.push(path_manifest_library(
            source_pack,
            library_id,
            current_paths,
        ));
    }
    Ok(libraries)
}

fn path_manifest_library<'a>(
    source_pack: &ExplicitSourcePackPathManifest,
    library_id: u32,
    paths: Vec<&'a Path>,
) -> ExplicitSourceLibraryPaths<&'a Path> {
    ExplicitSourceLibraryPaths {
        library_id,
        paths,
        dependency_library_ids: source_pack
            .library_dependencies
            .iter()
            .filter(|dependency| dependency.library_id == library_id)
            .map(|dependency| dependency.depends_on_library_id)
            .collect(),
    }
}

struct TemporaryBoundedArtifactRoot {
    path: PathBuf,
}

impl TemporaryBoundedArtifactRoot {
    fn create() -> Result<Self, CompileError> {
        let id = NEXT_BOUNDED_BUILD_ID.fetch_add(1, Ordering::Relaxed);
        let created_unix_nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_nanos())
            .unwrap_or(0);
        let path = std::env::temp_dir().join(format!(
            "laniusc-bounded-build-{}-{created_unix_nanos}-{id}",
            std::process::id(),
        ));
        fs::create_dir(&path).map_err(|err| {
            source_pack_artifact_store_error(format!(
                "create bounded source-pack artifact root {}: {err}",
                path.display()
            ))
        })?;
        Ok(Self { path })
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TemporaryBoundedArtifactRoot {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file(library_id: u32, index: usize, byte_len: usize) -> ExplicitSourcePathFile {
        ExplicitSourcePathFile {
            library_id,
            path: PathBuf::from(format!("source-{index}.lani")),
            byte_len,
            modified_unix_nanos: None,
            line_count: None,
        }
    }

    #[test]
    fn bounded_path_routing_uses_resident_workspace_limits() {
        let limits = resident_source_unit_limits();
        let small = ExplicitSourcePackPathManifest {
            files: vec![file(0, 0, limits.max_source_bytes)],
            library_dependencies: Vec::new(),
        };
        assert!(!small.requires_bounded_compilation_with_limits(limits));

        let small_multi_library = ExplicitSourcePackPathManifest {
            files: vec![file(0, 0, 1), file(1, 1, 1)],
            library_dependencies: vec![SourcePackLibraryDependency {
                library_id: 1,
                depends_on_library_id: 0,
            }],
        };
        assert!(!small_multi_library.requires_bounded_compilation_with_limits(limits));

        let oversized = ExplicitSourcePackPathManifest {
            files: vec![file(0, 0, limits.max_source_bytes + 1)],
            library_dependencies: Vec::new(),
        };
        assert!(oversized.requires_bounded_compilation_with_limits(limits));

        let oversized_aggregate = ExplicitSourcePackPathManifest {
            files: vec![
                file(0, 0, limits.max_source_bytes / 2 + 1),
                file(1, 1, limits.max_source_bytes / 2),
            ],
            library_dependencies: vec![SourcePackLibraryDependency {
                library_id: 1,
                depends_on_library_id: 0,
            }],
        };
        assert!(oversized_aggregate.requires_bounded_compilation_with_limits(limits));

        let many_files = ExplicitSourcePackPathManifest {
            files: (0..=limits.max_source_files)
                .map(|index| file(0, index, 1))
                .collect(),
            library_dependencies: Vec::new(),
        };
        assert!(many_files.requires_bounded_compilation_with_limits(limits));
    }

    #[test]
    fn hundred_mebibyte_project_is_split_at_the_ten_mebibyte_capacity() {
        let limits = resident_source_unit_limits();
        assert_eq!(limits.max_source_bytes, 10 * 1024 * 1024);

        let source_pack = ExplicitSourcePackPathManifest {
            files: (0..10)
                .map(|index| file(0, index, 10 * 1024 * 1024))
                .collect(),
            library_dependencies: Vec::new(),
        };
        assert!(source_pack.requires_bounded_compilation_with_limits(limits));

        let inputs = source_pack
            .files
            .iter()
            .enumerate()
            .map(|(source_index, file)| SourceFileUnitInput {
                library_id: file.library_id,
                source_index,
                byte_len: file.byte_len,
                line_count: file.line_count.unwrap_or(0),
            })
            .collect::<Vec<_>>();
        let frontend = CompilationUnitPlan::from_files(&inputs, limits);
        let codegen = CompilationUnitPlan::from_files(&inputs, limits);

        assert_eq!(frontend.unit_count(), 10);
        assert_eq!(codegen.unit_count(), 10);
        assert_eq!(frontend.max_unit_source_bytes(), limits.max_source_bytes);
        assert_eq!(codegen.max_unit_source_bytes(), limits.max_source_bytes);
    }

    #[test]
    fn bounded_path_libraries_preserve_dependencies_and_order() {
        let source_pack = ExplicitSourcePackPathManifest {
            files: vec![file(4, 0, 1), file(4, 1, 1), file(9, 2, 1)],
            library_dependencies: vec![SourcePackLibraryDependency {
                library_id: 9,
                depends_on_library_id: 4,
            }],
        };
        let libraries = path_manifest_libraries(&source_pack).unwrap();
        assert_eq!(libraries.len(), 2);
        assert_eq!(libraries[0].library_id, 4);
        assert_eq!(libraries[0].paths.len(), 2);
        assert!(libraries[0].dependency_library_ids.is_empty());
        assert_eq!(libraries[1].library_id, 9);
        assert_eq!(libraries[1].dependency_library_ids, vec![4]);
    }
}

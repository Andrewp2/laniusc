use std::{
    fs,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

use super::*;

static NEXT_BOUNDED_BUILD_ID: AtomicU64 = AtomicU64::new(0);

// Source-file metadata is linear in the file count and is not constrained by
// the 64-record pages used by persisted source-pack manifests.  Keep enough
// resident rows for ordinary many-file projects; source bytes remain the
// primary frontend workspace bound.
const DEFAULT_RESIDENT_SOURCE_FILE_CAPACITY: usize = 16 * 1024;
const DEFAULT_RESIDENT_SOURCE_BYTE_CAPACITY: usize = DEFAULT_CODEGEN_UNIT_MAX_SOURCE_BYTES;

fn default_resident_source_unit_limits() -> CompilationUnitLimits {
    CompilationUnitLimits {
        max_source_bytes: DEFAULT_RESIDENT_SOURCE_BYTE_CAPACITY,
        max_source_files: DEFAULT_RESIDENT_SOURCE_FILE_CAPACITY,
    }
}

impl<'gpu> GpuCompiler<'gpu> {
    pub(crate) fn resident_source_unit_limits(&self) -> CompilationUnitLimits {
        default_resident_source_unit_limits()
    }

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
        let limits = self.resident_source_unit_limits();
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
            let lowering_target = match target {
                SourcePackArtifactTarget::Wasm => LoweringTarget::Wasm,
                SourcePackArtifactTarget::X86_64 => LoweringTarget::X86_64,
                SourcePackArtifactTarget::Generic => unreachable!("concrete backend required"),
            };
            self.compile_checked_source_pack_with_lowering(
                &source_pack.sources,
                Some(&source_pack.source_paths),
                lowering_target,
            )
            .await
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
        let batch_limits = SourcePackJobBatchLimits::from_codegen_unit_limits(limits);
        let build_plan = source_pack.bounded_frontend_build_plan(limits);
        let mut executor = GpuSourcePackArtifactExecutor::new(self, artifact_root.path(), target);
        let linked_output_path = execute_path_batched_link_build_async(
            source_pack,
            &build_plan,
            batch_limits,
            &mut executor,
        )
        .await?
        .linked_output
        .path;

        // The bounded executor returns the linked-output contract; its
        // emitted-byte record points at the concrete target artifact.
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
        let limits = default_resident_source_unit_limits();
        assert!(limits.max_source_files >= 10_000);
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
    fn one_gibibyte_project_is_split_at_the_resident_workspace_capacity() {
        let limits = default_resident_source_unit_limits();
        assert_eq!(limits.max_source_bytes, 5 * 1024 * 1024);

        let source_pack = ExplicitSourcePackPathManifest {
            files: (0..1024).map(|index| file(0, index, 1024 * 1024)).collect(),
            library_dependencies: Vec::new(),
        };
        assert_eq!(
            source_pack
                .files
                .iter()
                .map(|source| source.byte_len)
                .sum::<usize>(),
            1024 * 1024 * 1024,
        );
        assert!(source_pack.requires_bounded_compilation_with_limits(limits));

        let frontend = source_pack.frontend_unit_plan(limits);
        let codegen = source_pack.codegen_unit_plan(limits);
        let schedule = source_pack.bounded_frontend_job_schedule(limits);

        assert_eq!(frontend.unit_count(), 205);
        assert_eq!(codegen.unit_count(), 205);
        assert_eq!(frontend.oversized_unit_count(), 0);
        assert_eq!(codegen.oversized_unit_count(), 0);
        assert_eq!(frontend.max_unit_source_bytes(), 5 * 1024 * 1024);
        assert_eq!(codegen.max_unit_source_bytes(), 5 * 1024 * 1024);
        assert_eq!(schedule.frontend_job_count(), 205);
        assert_eq!(schedule.codegen_job_count(), 205);
        assert_eq!(schedule.link_job_count(), 1);
        assert!(schedule.max_job_source_bytes() <= limits.max_source_bytes);
        assert!(schedule.max_job_source_files() <= limits.max_source_files);
    }

    #[test]
    fn resident_planner_packs_one_hundred_and_ten_thousand_file_projects_by_capacity() {
        let limits = default_resident_source_unit_limits();
        let cases = [
            (1usize, 4 * 1024 * 1024, 1usize),
            (100, 20 * 1024, 1),
            (10_000, 2 * 1024, 4),
        ];

        for (file_count, bytes_per_file, expected_units) in cases {
            let source_pack = ExplicitSourcePackPathManifest {
                files: (0..file_count)
                    .map(|index| file(0, index, bytes_per_file))
                    .collect(),
                library_dependencies: Vec::new(),
            };
            let units = source_pack.frontend_unit_plan(limits);

            assert_eq!(units.unit_count(), expected_units, "{file_count} files");
            assert!(units.max_unit_source_bytes() <= limits.max_source_bytes);
            assert!(units.max_unit_source_files() <= limits.max_source_files);
        }
    }
}

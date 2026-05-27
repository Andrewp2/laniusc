use std::{
    collections::{BTreeMap, hash_map::DefaultHasher},
    hash::{Hash, Hasher},
};

use super::*;

fn assert_stored_partition_index_has_no_inline_partitions(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
) {
    let index_json = std::fs::read_to_string(store.library_partition_index_path_for_target(target))
        .expect("read stored library partition index json");
    assert!(
        !index_json.contains("\"partitions\""),
        "stored library partition index should leave partition records in partition pages"
    );
}

fn assert_stored_schedule_index_has_no_inline_entries(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
) {
    let index_json = std::fs::read_to_string(store.library_schedule_index_path_for_target(target))
        .expect("read stored library schedule index json");
    assert!(
        !index_json.contains("\"entries\""),
        "stored library schedule index should leave per-library entries in schedule pages"
    );
}

fn buffer_id(buffer: &wgpu::Buffer) -> u64 {
    let mut hasher = DefaultHasher::new();
    buffer.hash(&mut hasher);
    hasher.finish()
}

fn assert_distinct_from(buffer: &wgpu::Buffer, protected: &[&wgpu::Buffer]) {
    let id = buffer_id(buffer);
    for protected_buffer in protected {
        assert_ne!(id, buffer_id(protected_buffer));
    }
}

fn resident_parser_buffers_for_scratch_tests() -> ParserBuffers {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../../tables/parse_tables.bin"))
            .expect("parse tables");
    let action_table = tables.to_action_header_grid_bytes();
    ParserBuffers::new_resident_capacity_with_tree_capacity(
        device::global().device.as_ref(),
        8,
        tables.n_kinds,
        &action_table,
        &tables,
        Some(64),
    )
}

fn resident_lexer_buffers_for_scratch_tests() -> LexerBuffers {
    let token_map = vec![0u32; crate::lexer::tables::dfa::N_STATES];
    let next_emit_words = vec![0u32; (256 * crate::lexer::tables::dfa::N_STATES).div_ceil(2)];
    let next_u8_words = vec![0u32; 256 * crate::lexer::tables::dfa::N_STATES.div_ceil(4)];
    LexerBuffers::new(
        device::global().device.as_ref(),
        128,
        1,
        0,
        &next_emit_words,
        &next_u8_words,
        &token_map,
        [u32::MAX; 4],
    )
}

fn scratch_u32_buffer(label: &str, words: usize) -> wgpu::Buffer {
    device::global()
        .device
        .create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: (words.max(1) * 4) as u64,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        })
}

#[test]
fn in_memory_source_pack_validation_rejects_oversized_default_codegen_units() {
    let limits = CodegenUnitLimits::default().normalized();
    let too_many_files = vec![""; limits.max_source_files + 1];
    let too_many_files_err = validate_in_memory_source_pack_fits_default_codegen_unit(
        "test in-memory source pack",
        &too_many_files,
    )
    .expect_err("too many in-memory source files should be rejected");
    assert!(
        too_many_files_err
            .to_string()
            .contains("persisted source-pack descriptor work queues"),
        "unexpected too-many-files error: {too_many_files_err}"
    );

    let oversized_file = "x".repeat(limits.max_source_bytes + 1);
    let oversized_file_err = validate_in_memory_source_pack_fits_default_codegen_unit(
        "test in-memory source pack",
        &[oversized_file.as_str()],
    )
    .expect_err("oversized in-memory source file should be rejected");
    assert!(
        oversized_file_err
            .to_string()
            .contains("bounded codegen-unit limit"),
        "unexpected oversized-file error: {oversized_file_err}"
    );
}

fn source_pack_contract_test_manifest() -> SourcePackPathBuildManifest {
    let source_files = vec![
        ExplicitSourcePathFile {
            library_id: 10,
            path: std::path::PathBuf::from("core.lani"),
            byte_len: 4,
            modified_unix_nanos: None,
            line_count: Some(1),
        },
        ExplicitSourcePathFile {
            library_id: 20,
            path: std::path::PathBuf::from("app.lani"),
            byte_len: 4,
            modified_unix_nanos: None,
            line_count: Some(1),
        },
        ExplicitSourcePathFile {
            library_id: 20,
            path: std::path::PathBuf::from("worker.lani"),
            byte_len: 4,
            modified_unix_nanos: None,
            line_count: Some(1),
        },
    ];
    let library_dependencies = vec![SourcePackLibraryDependency {
        library_id: 20,
        depends_on_library_id: 10,
    }];
    let path_manifest = ExplicitSourcePackPathManifest {
        files: source_files.clone(),
        library_dependencies: library_dependencies.clone(),
    };
    let file_inputs = source_files
        .iter()
        .enumerate()
        .map(|(source_index, file)| SourceFileUnitInput {
            library_id: file.library_id,
            source_index,
            byte_len: file.byte_len,
            line_count: file.line_count.unwrap_or(0),
        })
        .collect::<Vec<_>>();
    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 1,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };
    let build_plan = SourcePackJobPlan::from_files_with_dependencies(
        &file_inputs,
        &library_dependencies,
        limits,
    )
    .build_plan();
    let artifacts = build_plan.retained_build_artifact_manifest(batch_limits);
    source_pack_path_build_manifest(&path_manifest, limits, batch_limits, artifacts)
}

#[test]
fn source_pack_path_manifest_preserves_source_line_totals() {
    let manifest = source_pack_contract_test_manifest();
    validate_source_pack_path_build_manifest_versions(&manifest)
        .expect("test manifest with line totals should be valid");
    assert_eq!(manifest.source_file_count, 3);
    assert_eq!(manifest.source_byte_count, 12);
    assert_eq!(manifest.source_line_count, 3);

    let source_pack = manifest
        .source_pack_path_manifest()
        .expect("contract test manifest should retain source files");
    let partition_plan =
        source_pack_library_partition_plan(&source_pack, SourcePackArtifactTarget::Generic)
            .expect("partition plan should preserve line totals");
    let partition_index = &partition_plan.index;
    assert_eq!(partition_index.source_line_count, 3);
    assert_eq!(
        partition_plan
            .partitions
            .iter()
            .map(|partition| partition.source_line_count)
            .collect::<Vec<_>>(),
        vec![1, 2]
    );
    let source_file_pages = source_pack_library_source_file_pages(&source_pack, &partition_plan)
        .expect("source-file pages should preserve line totals");
    assert_eq!(
        source_file_pages
            .iter()
            .map(|page| page.source_line_count)
            .collect::<Vec<_>>(),
        vec![1, 2]
    );
}

#[test]
fn source_pack_compact_path_build_manifest_ready_queries_require_persisted_progress() {
    let mut manifest = source_pack_contract_test_manifest();
    manifest.artifacts = source_pack_compact_build_artifact_manifest(&manifest.artifacts)
        .expect("compact artifact manifest");
    assert!(manifest.artifacts.batch_dependency_count > 0);
    assert!(manifest.artifacts.batch_dependencies.batches.is_empty());

    let direct_err = manifest
        .ready_batch_indices_limited(&[], Some(1))
        .expect_err("compact manifest direct ready query must use persisted progress");
    assert!(
        direct_err.to_string().contains("persisted progress state"),
        "unexpected direct ready query error: {direct_err}"
    );

    let state = SourcePackBuildState::new();
    let state_err = manifest
        .ready_batch_indices_from_state_limited(&state, Some(1))
        .expect_err("compact manifest state ready query must use persisted progress");
    assert!(
        state_err.to_string().contains("persisted progress state"),
        "unexpected state ready query error: {state_err}"
    );

    let unclaimed_err = manifest
        .ready_unclaimed_batch_indices_from_state_limited(&state, None, Some(1))
        .expect_err("compact manifest unclaimed ready query must use persisted progress");
    assert!(
        unclaimed_err
            .to_string()
            .contains("persisted progress state"),
        "unexpected unclaimed ready query error: {unclaimed_err}"
    );
}

#[test]
fn source_pack_compact_artifact_manifest_execution_requires_persisted_shards() {
    let mut manifest = source_pack_contract_test_manifest();
    manifest.artifacts = source_pack_compact_build_artifact_manifest(&manifest.artifacts)
        .expect("compact artifact manifest");
    assert!(manifest.artifacts.job_count > 0);
    assert!(manifest.artifacts.job_schedule.jobs.is_empty());
    let source_pack = manifest
        .source_pack_path_manifest()
        .expect("test manifest keeps source-file metadata");
    let mut executor = RecordingSourcePackPathHandleExecutor::default();
    let mut store = RecordingSourcePackArtifactStore::default();

    let build_err = execute_source_pack_path_artifact_manifest_store_build(
        &source_pack,
        &manifest.artifacts,
        &mut executor,
        &mut store,
    )
    .expect_err("compact artifact manifest build must use persisted execution shards");
    assert!(
        build_err.to_string().contains("persisted execution shards"),
        "unexpected compact artifact-manifest build error: {build_err}"
    );

    let batch_err = execute_source_pack_path_artifact_manifest_store_batch(
        &source_pack,
        &manifest.artifacts,
        0,
        &mut executor,
        &mut store,
    )
    .expect_err("compact artifact manifest batch must use persisted execution shards");
    assert!(
        batch_err.to_string().contains("persisted execution shards"),
        "unexpected compact artifact-manifest batch error: {batch_err}"
    );
    assert!(executor.events.is_empty());
    assert!(store.events.is_empty());
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct TestLibraryInterface {
    library_id: u32,
    source_file_count: usize,
    dependency_libraries: Vec<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct TestCodegenObject {
    library_id: u32,
    source_range: std::ops::Range<usize>,
    dependency_libraries: Vec<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct TestLinkedOutput {
    interface_count: usize,
    object_count: usize,
    object_libraries: Vec<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct TestLinkHandle {
    interface_count: usize,
    object_libraries: Vec<u32>,
}

#[derive(Default)]
struct RecordingSourcePackExecutor {
    events: Vec<String>,
    max_codegen_source_files: usize,
}

impl SourcePackBuildExecutor for RecordingSourcePackExecutor {
    type LibraryInterface = TestLibraryInterface;
    type CodegenObject = TestCodegenObject;
    type LinkedOutput = TestLinkedOutput;

    fn build_library_interface(
        &mut self,
        job: &SourcePackJob,
        sources: &[String],
        dependency_interfaces: &[&Self::LibraryInterface],
    ) -> Result<Self::LibraryInterface, CompileError> {
        let dependency_libraries = dependency_interfaces
            .iter()
            .map(|interface| interface.library_id)
            .collect::<Vec<_>>();
        self.events.push(format!(
            "frontend:{}:{}:{dependency_libraries:?}",
            job.library_id,
            sources.len()
        ));
        Ok(TestLibraryInterface {
            library_id: job.library_id,
            source_file_count: sources.len(),
            dependency_libraries,
        })
    }

    fn build_codegen_object(
        &mut self,
        job: &SourcePackJob,
        sources: &[String],
        _library_interface: &Self::LibraryInterface,
        dependency_interfaces: &[&Self::LibraryInterface],
    ) -> Result<Self::CodegenObject, CompileError> {
        self.max_codegen_source_files = self.max_codegen_source_files.max(sources.len());
        let dependency_libraries = dependency_interfaces
            .iter()
            .map(|interface| interface.library_id)
            .collect::<Vec<_>>();
        self.events.push(format!(
            "codegen:{}:{:?}:{dependency_libraries:?}",
            job.library_id,
            job.source_range()
        ));
        Ok(TestCodegenObject {
            library_id: job.library_id,
            source_range: job.source_range(),
            dependency_libraries,
        })
    }

    fn link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
        library_interfaces: &[&Self::LibraryInterface],
        codegen_objects: &[&Self::CodegenObject],
    ) -> Result<Self::LinkedOutput, CompileError> {
        let object_libraries = codegen_objects
            .iter()
            .map(|object| object.library_id)
            .collect::<Vec<_>>();
        self.events.push(format!(
            "link:{}:{}:{}",
            job.job_index,
            library_interfaces.len(),
            codegen_objects.len()
        ));
        Ok(TestLinkedOutput {
            interface_count: library_interfaces.len(),
            object_count: codegen_objects.len(),
            object_libraries,
        })
    }
}

#[derive(Default)]
struct RecordingSourcePackPathExecutor {
    events: Vec<String>,
    max_codegen_source_files: usize,
}

impl SourcePackPathBuildExecutor for RecordingSourcePackPathExecutor {
    type LibraryInterface = TestLibraryInterface;
    type CodegenObject = TestCodegenObject;
    type LinkedOutput = TestLinkedOutput;

    fn build_library_interface(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        dependency_interfaces: &[&Self::LibraryInterface],
    ) -> Result<Self::LibraryInterface, CompileError> {
        let dependency_libraries = dependency_interfaces
            .iter()
            .map(|interface| interface.library_id)
            .collect::<Vec<_>>();
        self.events.push(format!(
            "frontend:{}:{}:{dependency_libraries:?}",
            job.library_id,
            source_files.len()
        ));
        Ok(TestLibraryInterface {
            library_id: job.library_id,
            source_file_count: source_files.len(),
            dependency_libraries,
        })
    }

    fn build_codegen_object(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        _library_interface: &Self::LibraryInterface,
        dependency_interfaces: &[&Self::LibraryInterface],
    ) -> Result<Self::CodegenObject, CompileError> {
        self.max_codegen_source_files = self.max_codegen_source_files.max(source_files.len());
        let dependency_libraries = dependency_interfaces
            .iter()
            .map(|interface| interface.library_id)
            .collect::<Vec<_>>();
        self.events.push(format!(
            "codegen:{}:{:?}:{}:{dependency_libraries:?}",
            job.library_id,
            job.source_range(),
            source_files.iter().map(|file| file.byte_len).sum::<usize>()
        ));
        Ok(TestCodegenObject {
            library_id: job.library_id,
            source_range: job.source_range(),
            dependency_libraries,
        })
    }

    fn link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
        library_interfaces: &[&Self::LibraryInterface],
        codegen_objects: &[&Self::CodegenObject],
    ) -> Result<Self::LinkedOutput, CompileError> {
        let object_libraries = codegen_objects
            .iter()
            .map(|object| object.library_id)
            .collect::<Vec<_>>();
        self.events.push(format!(
            "link:{}:{}:{}",
            job.job_index,
            library_interfaces.len(),
            codegen_objects.len()
        ));
        Ok(TestLinkedOutput {
            interface_count: library_interfaces.len(),
            object_count: codegen_objects.len(),
            object_libraries,
        })
    }
}

#[derive(Default)]
struct RecordingSourcePackPathHandleExecutor {
    events: Vec<String>,
}

impl SourcePackPathHandleBuildExecutor for RecordingSourcePackPathHandleExecutor {
    type LibraryInterfaceHandle = TestLibraryInterface;
    type CodegenObjectHandle = TestCodegenObject;
    type LinkedOutput = TestLinkedOutput;

    fn build_library_interface(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        dependency_interfaces: &[Self::LibraryInterfaceHandle],
    ) -> Result<Self::LibraryInterfaceHandle, CompileError> {
        let dependency_libraries = dependency_interfaces
            .iter()
            .map(|interface| interface.library_id)
            .collect::<Vec<_>>();
        self.events.push(format!(
            "frontend:{}:{}:{dependency_libraries:?}",
            job.library_id,
            source_files.len()
        ));
        Ok(TestLibraryInterface {
            library_id: job.library_id,
            source_file_count: source_files.len(),
            dependency_libraries,
        })
    }

    fn build_codegen_object(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        _library_interface: &Self::LibraryInterfaceHandle,
        dependency_interfaces: &[Self::LibraryInterfaceHandle],
    ) -> Result<Self::CodegenObjectHandle, CompileError> {
        let dependency_libraries = dependency_interfaces
            .iter()
            .map(|interface| interface.library_id)
            .collect::<Vec<_>>();
        self.events.push(format!(
            "codegen:{}:{:?}:{}:{dependency_libraries:?}",
            job.library_id,
            job.source_range(),
            source_files.iter().map(|file| file.byte_len).sum::<usize>()
        ));
        Ok(TestCodegenObject {
            library_id: job.library_id,
            source_range: job.source_range(),
            dependency_libraries,
        })
    }

    fn link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
        library_interfaces: &[Self::LibraryInterfaceHandle],
        codegen_objects: &[Self::CodegenObjectHandle],
    ) -> Result<Self::LinkedOutput, CompileError> {
        let object_libraries = codegen_objects
            .iter()
            .map(|object| object.library_id)
            .collect::<Vec<_>>();
        self.events.push(format!(
            "link:{}:{}:{}",
            job.job_index,
            library_interfaces.len(),
            codegen_objects.len()
        ));
        Ok(TestLinkedOutput {
            interface_count: library_interfaces.len(),
            object_count: codegen_objects.len(),
            object_libraries,
        })
    }

    fn release_library_interface(
        &mut self,
        handle: Self::LibraryInterfaceHandle,
    ) -> Result<(), CompileError> {
        self.events
            .push(format!("release-interface:{}", handle.library_id));
        Ok(())
    }

    fn release_codegen_object(
        &mut self,
        handle: Self::CodegenObjectHandle,
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "release-object:{}:{:?}",
            handle.library_id, handle.source_range
        ));
        Ok(())
    }
}

impl SourcePackPathHandleBatchedLinkBuildExecutor for RecordingSourcePackPathHandleExecutor {
    type LibraryInterfaceHandle = TestLibraryInterface;
    type CodegenObjectHandle = TestCodegenObject;
    type LinkHandle = TestLinkHandle;
    type LinkedOutput = TestLinkedOutput;

    fn build_library_interface(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        dependency_interfaces: &[Self::LibraryInterfaceHandle],
    ) -> Result<Self::LibraryInterfaceHandle, CompileError> {
        let dependency_libraries = dependency_interfaces
            .iter()
            .map(|interface| interface.library_id)
            .collect::<Vec<_>>();
        self.events.push(format!(
            "frontend:{}:{}:{dependency_libraries:?}",
            job.library_id,
            source_files.len()
        ));
        Ok(TestLibraryInterface {
            library_id: job.library_id,
            source_file_count: source_files.len(),
            dependency_libraries,
        })
    }

    fn build_codegen_object(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        _library_interface: &Self::LibraryInterfaceHandle,
        dependency_interfaces: &[Self::LibraryInterfaceHandle],
    ) -> Result<Self::CodegenObjectHandle, CompileError> {
        let dependency_libraries = dependency_interfaces
            .iter()
            .map(|interface| interface.library_id)
            .collect::<Vec<_>>();
        self.events.push(format!(
            "codegen:{}:{:?}:{}:{dependency_libraries:?}",
            job.library_id,
            job.source_range(),
            source_files.iter().map(|file| file.byte_len).sum::<usize>()
        ));
        Ok(TestCodegenObject {
            library_id: job.library_id,
            source_range: job.source_range(),
            dependency_libraries,
        })
    }

    fn begin_link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
    ) -> Result<Self::LinkHandle, CompileError> {
        self.events.push(format!("begin-link:{}", job.job_index));
        Ok(TestLinkHandle {
            interface_count: 0,
            object_libraries: Vec::new(),
        })
    }

    fn link_library_interface_batch(
        &mut self,
        _job: &SourcePackJob,
        link_handle: &mut Self::LinkHandle,
        batch: &SourcePackLinkInterfaceBatch,
        library_interfaces: &[Self::LibraryInterfaceHandle],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "link-interfaces:{}:{}",
            batch.batch_index,
            library_interfaces.len()
        ));
        link_handle.interface_count += library_interfaces.len();
        Ok(())
    }

    fn link_codegen_object_batch(
        &mut self,
        _job: &SourcePackJob,
        link_handle: &mut Self::LinkHandle,
        batch: &SourcePackLinkObjectBatch,
        codegen_objects: &[Self::CodegenObjectHandle],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "link-batch:{}:{}",
            batch.batch_index,
            codegen_objects.len()
        ));
        link_handle
            .object_libraries
            .extend(codegen_objects.iter().map(|object| object.library_id));
        Ok(())
    }

    fn finish_link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
        link_handle: Self::LinkHandle,
    ) -> Result<Self::LinkedOutput, CompileError> {
        self.events.push(format!(
            "finish-link:{}:{}:{}",
            job.job_index,
            link_handle.interface_count,
            link_handle.object_libraries.len()
        ));
        Ok(TestLinkedOutput {
            interface_count: link_handle.interface_count,
            object_count: link_handle.object_libraries.len(),
            object_libraries: link_handle.object_libraries,
        })
    }

    fn release_library_interface(
        &mut self,
        handle: Self::LibraryInterfaceHandle,
    ) -> Result<(), CompileError> {
        self.events
            .push(format!("release-interface:{}", handle.library_id));
        Ok(())
    }

    fn release_codegen_object(
        &mut self,
        handle: Self::CodegenObjectHandle,
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "release-object:{}:{:?}",
            handle.library_id, handle.source_range
        ));
        Ok(())
    }
}

impl SourcePackPathArtifactBuildExecutor for RecordingSourcePackPathHandleExecutor {
    type LibraryInterfaceArtifact = TestLibraryInterface;
    type CodegenObjectArtifact = TestCodegenObject;
    type LinkHandle = TestLinkHandle;
    type LinkedOutputArtifact = TestLinkedOutput;

    fn build_library_interface(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<Self::LibraryInterfaceArtifact, CompileError> {
        let dependency_libraries = dependency_interfaces
            .iter()
            .map(|interface| interface.library_id)
            .collect::<Vec<_>>();
        self.events.push(format!(
            "frontend:{}:{}:{dependency_libraries:?}",
            job.library_id,
            source_files.len()
        ));
        Ok(TestLibraryInterface {
            library_id: job.library_id,
            source_file_count: source_files.len(),
            dependency_libraries,
        })
    }

    fn build_codegen_object(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        _library_interface: &Self::LibraryInterfaceArtifact,
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<Self::CodegenObjectArtifact, CompileError> {
        let dependency_libraries = dependency_interfaces
            .iter()
            .map(|interface| interface.library_id)
            .collect::<Vec<_>>();
        self.events.push(format!(
            "codegen:{}:{:?}:{}:{dependency_libraries:?}",
            job.library_id,
            job.source_range(),
            source_files.iter().map(|file| file.byte_len).sum::<usize>()
        ));
        Ok(TestCodegenObject {
            library_id: job.library_id,
            source_range: job.source_range(),
            dependency_libraries,
        })
    }

    fn begin_link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
    ) -> Result<Self::LinkHandle, CompileError> {
        self.events.push(format!("begin-link:{}", job.job_index));
        Ok(TestLinkHandle {
            interface_count: 0,
            object_libraries: Vec::new(),
        })
    }

    fn link_library_interface_batch(
        &mut self,
        _job: &SourcePackJob,
        link_handle: &mut Self::LinkHandle,
        batch: &SourcePackLinkInterfaceBatch,
        library_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "link-interfaces:{}:{}",
            batch.batch_index,
            library_interfaces.len()
        ));
        link_handle.interface_count += library_interfaces.len();
        Ok(())
    }

    fn link_codegen_object_batch(
        &mut self,
        _job: &SourcePackJob,
        link_handle: &mut Self::LinkHandle,
        batch: &SourcePackLinkObjectBatch,
        codegen_objects: &[Self::CodegenObjectArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "link-batch:{}:{}",
            batch.batch_index,
            codegen_objects.len()
        ));
        link_handle
            .object_libraries
            .extend(codegen_objects.iter().map(|object| object.library_id));
        Ok(())
    }

    fn finish_link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
        link_handle: Self::LinkHandle,
    ) -> Result<Self::LinkedOutputArtifact, CompileError> {
        self.events.push(format!(
            "finish-link:{}:{}:{}",
            job.job_index,
            link_handle.interface_count,
            link_handle.object_libraries.len()
        ));
        Ok(TestLinkedOutput {
            interface_count: link_handle.interface_count,
            object_count: link_handle.object_libraries.len(),
            object_libraries: link_handle.object_libraries,
        })
    }
}

#[derive(Default)]
struct RecordingSourcePackArtifactStore {
    events: Vec<String>,
    interfaces: BTreeMap<String, TestLibraryInterface>,
    objects: BTreeMap<String, TestCodegenObject>,
    outputs: BTreeMap<String, TestLinkedOutput>,
}

impl SourcePackPathArtifactStore for RecordingSourcePackArtifactStore {
    type LibraryInterfaceArtifact = TestLibraryInterface;
    type CodegenObjectArtifact = TestCodegenObject;
    type LinkedOutputArtifact = TestLinkedOutput;

    fn load_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<Self::LibraryInterfaceArtifact, CompileError> {
        self.events.push(format!("load-interface:{}", artifact.key));
        self.interfaces.get(&artifact.key).cloned().ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "missing library interface artifact {}",
                artifact.key
            ))
        })
    }

    fn store_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
        interface: Self::LibraryInterfaceArtifact,
    ) -> Result<(), CompileError> {
        self.events
            .push(format!("store-interface:{}", artifact.key));
        self.interfaces.insert(artifact.key.clone(), interface);
        Ok(())
    }

    fn release_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<(), CompileError> {
        self.events
            .push(format!("release-interface:{}", artifact.key));
        self.interfaces.remove(&artifact.key);
        Ok(())
    }

    fn load_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<Self::CodegenObjectArtifact, CompileError> {
        self.events.push(format!("load-object:{}", artifact.key));
        self.objects.get(&artifact.key).cloned().ok_or_else(|| {
            CompileError::GpuFrontend(format!("missing codegen object artifact {}", artifact.key))
        })
    }

    fn store_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
        object: Self::CodegenObjectArtifact,
    ) -> Result<(), CompileError> {
        self.events.push(format!("store-object:{}", artifact.key));
        self.objects.insert(artifact.key.clone(), object);
        Ok(())
    }

    fn release_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<(), CompileError> {
        self.events.push(format!("release-object:{}", artifact.key));
        self.objects.remove(&artifact.key);
        Ok(())
    }

    fn store_linked_output(
        &mut self,
        artifact: &SourcePackArtifactRef,
        output: Self::LinkedOutputArtifact,
    ) -> Result<(), CompileError> {
        self.events.push(format!("store-output:{}", artifact.key));
        self.outputs.insert(artifact.key.clone(), output);
        Ok(())
    }
}

#[derive(Default)]
struct RecordingSourcePackByteArtifactExecutor {
    events: Vec<String>,
    fail_library_interface_calls: usize,
    record_paged_dependency_batches: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct TestByteLinkHandle {
    interface_count: usize,
    object_count: usize,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct TestByteBuildHandle {
    library_id: u32,
    first_source_index: usize,
    source_file_count: usize,
    source_files_len: usize,
    dependency_count: usize,
}

fn test_partial_link_counts(partial: &[u8]) -> Result<(usize, usize), CompileError> {
    let text = std::str::from_utf8(partial).map_err(|err| {
        CompileError::GpuFrontend(format!("test partial link artifact was not utf8: {err}"))
    })?;
    let parts = text.split(':').collect::<Vec<_>>();
    if parts.len() != 4 || parts[0] != "partial" {
        return Err(CompileError::GpuFrontend(format!(
            "test partial link artifact has invalid shape {text:?}"
        )));
    }
    let interface_count = parts[2].parse::<usize>().map_err(|err| {
        CompileError::GpuFrontend(format!(
            "test partial link interface count {:?} is invalid: {err}",
            parts[2]
        ))
    })?;
    let object_count = parts[3].parse::<usize>().map_err(|err| {
        CompileError::GpuFrontend(format!(
            "test partial link object count {:?} is invalid: {err}",
            parts[3]
        ))
    })?;
    Ok((interface_count, object_count))
}

impl SourcePackPathArtifactBuildExecutor for RecordingSourcePackByteArtifactExecutor {
    type LibraryInterfaceArtifact = Vec<u8>;
    type CodegenObjectArtifact = Vec<u8>;
    type LinkHandle = TestByteLinkHandle;
    type LinkedOutputArtifact = Vec<u8>;

    fn build_library_interface(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<Self::LibraryInterfaceArtifact, CompileError> {
        if self.fail_library_interface_calls > 0 {
            self.fail_library_interface_calls -= 1;
            self.events.push(format!(
                "fail-frontend:{}:{}:{}",
                job.library_id,
                source_files.len(),
                dependency_interfaces.len()
            ));
            return Err(CompileError::GpuFrontend(format!(
                "test injected frontend failure for job {}",
                job.job_index
            )));
        }
        self.events.push(format!(
            "frontend:{}:{}:{}",
            job.library_id,
            source_files.len(),
            dependency_interfaces.len()
        ));
        Ok(format!(
            "iface:{}:{}:{}",
            job.library_id,
            source_files.len(),
            dependency_interfaces.len()
        )
        .into_bytes())
    }

    fn build_codegen_object(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        library_interface: &Self::LibraryInterfaceArtifact,
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<Self::CodegenObjectArtifact, CompileError> {
        let expected_interface_prefix = format!("iface:{}:", job.library_id);
        let interface = std::str::from_utf8(library_interface).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "test library interface artifact was not utf8: {err}"
            ))
        })?;
        if !interface.starts_with(&expected_interface_prefix) {
            return Err(CompileError::GpuFrontend(format!(
                "codegen job {} received wrong owning interface artifact {interface:?}",
                job.job_index
            )));
        }
        self.events.push(format!(
            "codegen:{}:{:?}:{}:{}",
            job.library_id,
            job.source_range(),
            source_files.len(),
            dependency_interfaces.len()
        ));
        Ok(format!(
            "obj:{}:{}-{}:{}",
            job.library_id,
            job.first_source_index,
            job.first_source_index + job.source_file_count,
            dependency_interfaces.len()
        )
        .into_bytes())
    }

    fn begin_link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
    ) -> Result<Self::LinkHandle, CompileError> {
        self.events.push(format!("begin-link:{}", job.job_index));
        Ok(TestByteLinkHandle::default())
    }

    fn link_library_interface_batch(
        &mut self,
        _job: &SourcePackJob,
        link_handle: &mut Self::LinkHandle,
        batch: &SourcePackLinkInterfaceBatch,
        library_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "link-interfaces:{}:{}",
            batch.batch_index,
            library_interfaces.len()
        ));
        link_handle.interface_count += library_interfaces.len();
        Ok(())
    }

    fn link_codegen_object_batch(
        &mut self,
        _job: &SourcePackJob,
        link_handle: &mut Self::LinkHandle,
        batch: &SourcePackLinkObjectBatch,
        codegen_objects: &[Self::CodegenObjectArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "link-objects:{}:{}",
            batch.batch_index,
            codegen_objects.len()
        ));
        link_handle.object_count += codegen_objects.len();
        Ok(())
    }

    fn finish_link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
        link_handle: Self::LinkHandle,
    ) -> Result<Self::LinkedOutputArtifact, CompileError> {
        self.events.push(format!(
            "finish-link:{}:{}:{}",
            job.job_index, link_handle.interface_count, link_handle.object_count
        ));
        Ok(format!(
            "linked:{}:{}",
            link_handle.interface_count, link_handle.object_count
        )
        .into_bytes())
    }
}

impl SourcePackPathPagedArtifactBuildExecutor for RecordingSourcePackByteArtifactExecutor {
    type LibraryInterfaceBuildHandle = TestByteBuildHandle;
    type CodegenObjectBuildHandle = TestByteBuildHandle;

    fn begin_library_interface(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
    ) -> Result<Self::LibraryInterfaceBuildHandle, CompileError> {
        if self.record_paged_dependency_batches {
            self.events.push(format!(
                "begin-frontend:{}:{}",
                job.library_id,
                source_files.len()
            ));
        }
        Ok(TestByteBuildHandle {
            library_id: job.library_id,
            first_source_index: job.first_source_index,
            source_file_count: job.source_file_count,
            source_files_len: source_files.len(),
            dependency_count: 0,
        })
    }

    fn add_library_interface_dependency_batch(
        &mut self,
        job: &SourcePackJob,
        handle: &mut Self::LibraryInterfaceBuildHandle,
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError> {
        if self.record_paged_dependency_batches {
            self.events.push(format!(
                "frontend-deps:{}:{}",
                job.library_id,
                dependency_interfaces.len()
            ));
        }
        handle.dependency_count = handle
            .dependency_count
            .saturating_add(dependency_interfaces.len());
        Ok(())
    }

    fn finish_library_interface(
        &mut self,
        job: &SourcePackJob,
        handle: Self::LibraryInterfaceBuildHandle,
    ) -> Result<Self::LibraryInterfaceArtifact, CompileError> {
        if self.fail_library_interface_calls > 0 {
            self.fail_library_interface_calls -= 1;
            self.events.push(format!(
                "fail-frontend:{}:{}:{}",
                handle.library_id, handle.source_files_len, handle.dependency_count
            ));
            return Err(CompileError::GpuFrontend(format!(
                "test injected frontend failure for job {}",
                job.job_index
            )));
        }
        self.events.push(format!(
            "frontend:{}:{}:{}",
            handle.library_id, handle.source_files_len, handle.dependency_count
        ));
        Ok(format!(
            "iface:{}:{}:{}",
            handle.library_id, handle.source_files_len, handle.dependency_count
        )
        .into_bytes())
    }

    fn begin_codegen_object(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        library_interface: &Self::LibraryInterfaceArtifact,
    ) -> Result<Self::CodegenObjectBuildHandle, CompileError> {
        let expected_interface_prefix = format!("iface:{}:", job.library_id);
        let interface = std::str::from_utf8(library_interface).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "test library interface artifact was not utf8: {err}"
            ))
        })?;
        if !interface.starts_with(&expected_interface_prefix) {
            return Err(CompileError::GpuFrontend(format!(
                "codegen job {} received wrong owning interface artifact {interface:?}",
                job.job_index
            )));
        }
        if self.record_paged_dependency_batches {
            self.events.push(format!(
                "begin-codegen:{}:{}",
                job.library_id,
                source_files.len()
            ));
        }
        Ok(TestByteBuildHandle {
            library_id: job.library_id,
            first_source_index: job.first_source_index,
            source_file_count: job.source_file_count,
            source_files_len: source_files.len(),
            dependency_count: 0,
        })
    }

    fn add_codegen_object_dependency_batch(
        &mut self,
        job: &SourcePackJob,
        handle: &mut Self::CodegenObjectBuildHandle,
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError> {
        if self.record_paged_dependency_batches {
            self.events.push(format!(
                "codegen-deps:{}:{}",
                job.library_id,
                dependency_interfaces.len()
            ));
        }
        handle.dependency_count = handle
            .dependency_count
            .saturating_add(dependency_interfaces.len());
        Ok(())
    }

    fn finish_codegen_object(
        &mut self,
        _job: &SourcePackJob,
        handle: Self::CodegenObjectBuildHandle,
    ) -> Result<Self::CodegenObjectArtifact, CompileError> {
        let source_end = handle
            .first_source_index
            .saturating_add(handle.source_file_count);
        self.events.push(format!(
            "codegen:{}:{:?}:{}:{}",
            handle.library_id,
            handle.first_source_index..source_end,
            handle.source_files_len,
            handle.dependency_count
        ));
        Ok(format!(
            "obj:{}:{}-{}:{}",
            handle.library_id, handle.first_source_index, source_end, handle.dependency_count
        )
        .into_bytes())
    }
}

impl SourcePackPathAsyncPagedArtifactBuildExecutor for RecordingSourcePackByteArtifactExecutor {
    type LibraryInterfaceArtifact = Vec<u8>;
    type CodegenObjectArtifact = Vec<u8>;
    type LinkHandle = TestByteLinkHandle;
    type LinkedOutputArtifact = Vec<u8>;
    type LibraryInterfaceBuildHandle = TestByteBuildHandle;
    type CodegenObjectBuildHandle = TestByteBuildHandle;

    fn begin_library_interface<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        source_files: &'a [ExplicitSourcePathFile],
    ) -> SourcePackBoxFuture<'a, Self::LibraryInterfaceBuildHandle> {
        Box::pin(async move {
            <Self as SourcePackPathPagedArtifactBuildExecutor>::begin_library_interface(
                self,
                job,
                source_files,
            )
        })
    }

    fn add_library_interface_dependency_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: &'a mut Self::LibraryInterfaceBuildHandle,
        dependency_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            <Self as SourcePackPathPagedArtifactBuildExecutor>::add_library_interface_dependency_batch(
                    self,
                    job,
                    handle,
                    dependency_interfaces,
                )
        })
    }

    fn finish_library_interface<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: Self::LibraryInterfaceBuildHandle,
    ) -> SourcePackBoxFuture<'a, Self::LibraryInterfaceArtifact> {
        Box::pin(async move {
            <Self as SourcePackPathPagedArtifactBuildExecutor>::finish_library_interface(
                self, job, handle,
            )
        })
    }

    fn begin_codegen_object<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        source_files: &'a [ExplicitSourcePathFile],
        library_interface: &'a Self::LibraryInterfaceArtifact,
    ) -> SourcePackBoxFuture<'a, Self::CodegenObjectBuildHandle> {
        Box::pin(async move {
            <Self as SourcePackPathPagedArtifactBuildExecutor>::begin_codegen_object(
                self,
                job,
                source_files,
                library_interface,
            )
        })
    }

    fn add_codegen_object_dependency_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: &'a mut Self::CodegenObjectBuildHandle,
        dependency_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            <Self as SourcePackPathPagedArtifactBuildExecutor>::add_codegen_object_dependency_batch(
                self,
                job,
                handle,
                dependency_interfaces,
            )
        })
    }

    fn finish_codegen_object<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: Self::CodegenObjectBuildHandle,
    ) -> SourcePackBoxFuture<'a, Self::CodegenObjectArtifact> {
        Box::pin(async move {
            <Self as SourcePackPathPagedArtifactBuildExecutor>::finish_codegen_object(
                self, job, handle,
            )
        })
    }

    fn begin_link_codegen_objects<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
    ) -> SourcePackBoxFuture<'a, Self::LinkHandle> {
        Box::pin(async move {
            <Self as SourcePackPathArtifactBuildExecutor>::begin_link_codegen_objects(self, job)
        })
    }

    fn link_library_interface_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: &'a mut Self::LinkHandle,
        batch: &'a SourcePackLinkInterfaceBatch,
        library_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            <Self as SourcePackPathArtifactBuildExecutor>::link_library_interface_batch(
                self,
                job,
                link_handle,
                batch,
                library_interfaces,
            )
        })
    }

    fn link_codegen_object_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: &'a mut Self::LinkHandle,
        batch: &'a SourcePackLinkObjectBatch,
        codegen_objects: &'a [Self::CodegenObjectArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            <Self as SourcePackPathArtifactBuildExecutor>::link_codegen_object_batch(
                self,
                job,
                link_handle,
                batch,
                codegen_objects,
            )
        })
    }

    fn finish_link_codegen_objects<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: Self::LinkHandle,
    ) -> SourcePackBoxFuture<'a, Self::LinkedOutputArtifact> {
        Box::pin(async move {
            <Self as SourcePackPathArtifactBuildExecutor>::finish_link_codegen_objects(
                self,
                job,
                link_handle,
            )
        })
    }
}

impl SourcePackPathHierarchicalLinkExecutor for RecordingSourcePackByteArtifactExecutor {
    type PartialLinkArtifact = Vec<u8>;

    fn begin_hierarchical_link_group(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
    ) -> Result<Self::LinkHandle, CompileError> {
        self.events.push(format!(
            "begin-hlink:{}:{}",
            page.group_index, page.job_index
        ));
        Ok(TestByteLinkHandle::default())
    }

    fn link_hierarchical_library_interfaces(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: &mut Self::LinkHandle,
        library_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "hlink-interfaces:{}:{}",
            page.group_index,
            library_interfaces.len()
        ));
        link_handle.interface_count += library_interfaces.len();
        Ok(())
    }

    fn link_hierarchical_codegen_objects(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: &mut Self::LinkHandle,
        codegen_objects: &[Self::CodegenObjectArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "hlink-objects:{}:{}",
            page.group_index,
            codegen_objects.len()
        ));
        link_handle.object_count += codegen_objects.len();
        Ok(())
    }

    fn link_hierarchical_partial_links(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: &mut Self::LinkHandle,
        partial_links: &[Self::PartialLinkArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "hlink-partials:{}:{}",
            page.group_index,
            partial_links.len()
        ));
        for partial in partial_links {
            let (interface_count, object_count) = test_partial_link_counts(partial)?;
            link_handle.interface_count += interface_count;
            link_handle.object_count += object_count;
        }
        Ok(())
    }

    fn finish_hierarchical_partial_link_group(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: Self::LinkHandle,
    ) -> Result<Self::PartialLinkArtifact, CompileError> {
        self.events.push(format!(
            "finish-hpartial:{}:{}:{}",
            page.group_index, link_handle.interface_count, link_handle.object_count
        ));
        Ok(format!(
            "partial:{}:{}:{}",
            page.group_index, link_handle.interface_count, link_handle.object_count
        )
        .into_bytes())
    }

    fn finish_hierarchical_link_output(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: Self::LinkHandle,
    ) -> Result<Self::LinkedOutputArtifact, CompileError> {
        self.events.push(format!(
            "finish-hlink:{}:{}:{}",
            page.group_index, link_handle.interface_count, link_handle.object_count
        ));
        Ok(format!(
            "hlinked:{}:{}",
            link_handle.interface_count, link_handle.object_count
        )
        .into_bytes())
    }
}

struct RecordingSourcePackFileArtifactExecutor {
    root: PathBuf,
    events: Vec<String>,
    next_artifact_index: usize,
}

impl RecordingSourcePackFileArtifactExecutor {
    fn new(root: PathBuf) -> Self {
        Self {
            root,
            events: Vec::new(),
            next_artifact_index: 0,
        }
    }

    fn write_artifact(
        &mut self,
        label: &str,
        contents: impl AsRef<[u8]>,
    ) -> Result<SourcePackFilesystemArtifactPath, CompileError> {
        std::fs::create_dir_all(&self.root).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "create test file artifact root {}: {err}",
                self.root.display()
            ))
        })?;
        let artifact_index = self.next_artifact_index;
        self.next_artifact_index = self.next_artifact_index.saturating_add(1);
        let key = format!("tmp/{label}-{artifact_index}");
        let path = self.root.join(format!("{label}-{artifact_index}.bin"));
        std::fs::write(&path, contents).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "write test file artifact {}: {err}",
                path.display()
            ))
        })?;
        Ok(SourcePackFilesystemArtifactPath { key, path })
    }
}

impl SourcePackPathArtifactBuildExecutor for RecordingSourcePackFileArtifactExecutor {
    type LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath;
    type CodegenObjectArtifact = SourcePackFilesystemArtifactPath;
    type LinkHandle = TestByteLinkHandle;
    type LinkedOutputArtifact = SourcePackFilesystemArtifactPath;

    fn build_library_interface(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<Self::LibraryInterfaceArtifact, CompileError> {
        self.events.push(format!(
            "frontend:{}:{}:{}",
            job.library_id,
            source_files.len(),
            dependency_interfaces.len()
        ));
        self.write_artifact(
            "iface",
            format!(
                "iface:{}:{}:{}",
                job.library_id,
                source_files.len(),
                dependency_interfaces.len()
            ),
        )
    }

    fn build_codegen_object(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        library_interface: &Self::LibraryInterfaceArtifact,
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<Self::CodegenObjectArtifact, CompileError> {
        if !library_interface.path.is_file() {
            return Err(CompileError::GpuFrontend(format!(
                "test codegen job {} received missing interface path {}",
                job.job_index,
                library_interface.path.display()
            )));
        }
        self.events.push(format!(
            "codegen:{}:{:?}:{}:{}",
            job.library_id,
            job.source_range(),
            source_files.len(),
            dependency_interfaces.len()
        ));
        self.write_artifact(
            "obj",
            format!(
                "obj:{}:{}-{}:{}",
                job.library_id,
                job.first_source_index,
                job.first_source_index + job.source_file_count,
                dependency_interfaces.len()
            ),
        )
    }

    fn begin_link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
    ) -> Result<Self::LinkHandle, CompileError> {
        self.events.push(format!("begin-link:{}", job.job_index));
        Ok(TestByteLinkHandle::default())
    }

    fn link_library_interface_batch(
        &mut self,
        _job: &SourcePackJob,
        link_handle: &mut Self::LinkHandle,
        batch: &SourcePackLinkInterfaceBatch,
        library_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "link-interfaces:{}:{}",
            batch.batch_index,
            library_interfaces.len()
        ));
        if library_interfaces
            .iter()
            .any(|artifact| !artifact.path.is_file())
        {
            return Err(CompileError::GpuFrontend(
                "test link received a missing library interface path".into(),
            ));
        }
        link_handle.interface_count += library_interfaces.len();
        Ok(())
    }

    fn link_codegen_object_batch(
        &mut self,
        _job: &SourcePackJob,
        link_handle: &mut Self::LinkHandle,
        batch: &SourcePackLinkObjectBatch,
        codegen_objects: &[Self::CodegenObjectArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "link-objects:{}:{}",
            batch.batch_index,
            codegen_objects.len()
        ));
        if codegen_objects
            .iter()
            .any(|artifact| !artifact.path.is_file())
        {
            return Err(CompileError::GpuFrontend(
                "test link received a missing codegen object path".into(),
            ));
        }
        link_handle.object_count += codegen_objects.len();
        Ok(())
    }

    fn finish_link_codegen_objects(
        &mut self,
        job: &SourcePackJob,
        link_handle: Self::LinkHandle,
    ) -> Result<Self::LinkedOutputArtifact, CompileError> {
        self.events.push(format!(
            "finish-link:{}:{}:{}",
            job.job_index, link_handle.interface_count, link_handle.object_count
        ));
        self.write_artifact(
            "linked",
            format!(
                "linked:{}:{}",
                link_handle.interface_count, link_handle.object_count
            ),
        )
    }
}

impl SourcePackPathPagedArtifactBuildExecutor for RecordingSourcePackFileArtifactExecutor {
    type LibraryInterfaceBuildHandle = TestByteBuildHandle;
    type CodegenObjectBuildHandle = TestByteBuildHandle;

    fn begin_library_interface(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
    ) -> Result<Self::LibraryInterfaceBuildHandle, CompileError> {
        Ok(TestByteBuildHandle {
            library_id: job.library_id,
            first_source_index: job.first_source_index,
            source_file_count: job.source_file_count,
            source_files_len: source_files.len(),
            dependency_count: 0,
        })
    }

    fn add_library_interface_dependency_batch(
        &mut self,
        _job: &SourcePackJob,
        handle: &mut Self::LibraryInterfaceBuildHandle,
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError> {
        if dependency_interfaces
            .iter()
            .any(|artifact| !artifact.path.is_file())
        {
            return Err(CompileError::GpuFrontend(
                "test frontend received a missing dependency interface path".into(),
            ));
        }
        handle.dependency_count = handle
            .dependency_count
            .saturating_add(dependency_interfaces.len());
        Ok(())
    }

    fn finish_library_interface(
        &mut self,
        _job: &SourcePackJob,
        handle: Self::LibraryInterfaceBuildHandle,
    ) -> Result<Self::LibraryInterfaceArtifact, CompileError> {
        self.events.push(format!(
            "frontend:{}:{}:{}",
            handle.library_id, handle.source_files_len, handle.dependency_count
        ));
        self.write_artifact(
            "iface",
            format!(
                "iface:{}:{}:{}",
                handle.library_id, handle.source_files_len, handle.dependency_count
            ),
        )
    }

    fn begin_codegen_object(
        &mut self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        library_interface: &Self::LibraryInterfaceArtifact,
    ) -> Result<Self::CodegenObjectBuildHandle, CompileError> {
        if !library_interface.path.is_file() {
            return Err(CompileError::GpuFrontend(format!(
                "test codegen job {} received missing owning interface path {}",
                job.job_index,
                library_interface.path.display()
            )));
        }
        Ok(TestByteBuildHandle {
            library_id: job.library_id,
            first_source_index: job.first_source_index,
            source_file_count: job.source_file_count,
            source_files_len: source_files.len(),
            dependency_count: 0,
        })
    }

    fn add_codegen_object_dependency_batch(
        &mut self,
        _job: &SourcePackJob,
        handle: &mut Self::CodegenObjectBuildHandle,
        dependency_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError> {
        if dependency_interfaces
            .iter()
            .any(|artifact| !artifact.path.is_file())
        {
            return Err(CompileError::GpuFrontend(
                "test codegen received a missing dependency interface path".into(),
            ));
        }
        handle.dependency_count = handle
            .dependency_count
            .saturating_add(dependency_interfaces.len());
        Ok(())
    }

    fn finish_codegen_object(
        &mut self,
        _job: &SourcePackJob,
        handle: Self::CodegenObjectBuildHandle,
    ) -> Result<Self::CodegenObjectArtifact, CompileError> {
        let source_end = handle
            .first_source_index
            .saturating_add(handle.source_file_count);
        self.events.push(format!(
            "codegen:{}:{:?}:{}:{}",
            handle.library_id,
            handle.first_source_index..source_end,
            handle.source_files_len,
            handle.dependency_count
        ));
        self.write_artifact(
            "obj",
            format!(
                "obj:{}:{}-{}:{}",
                handle.library_id, handle.first_source_index, source_end, handle.dependency_count
            ),
        )
    }
}

impl SourcePackPathHierarchicalLinkExecutor for RecordingSourcePackFileArtifactExecutor {
    type PartialLinkArtifact = SourcePackFilesystemArtifactPath;

    fn begin_hierarchical_link_group(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
    ) -> Result<Self::LinkHandle, CompileError> {
        self.events.push(format!(
            "begin-hlink:{}:{}",
            page.group_index, page.job_index
        ));
        Ok(TestByteLinkHandle::default())
    }

    fn link_hierarchical_library_interfaces(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: &mut Self::LinkHandle,
        library_interfaces: &[Self::LibraryInterfaceArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "hlink-interfaces:{}:{}",
            page.group_index,
            library_interfaces.len()
        ));
        if library_interfaces
            .iter()
            .any(|artifact| !artifact.path.is_file())
        {
            return Err(CompileError::GpuFrontend(
                "test hierarchical link received a missing library interface path".into(),
            ));
        }
        link_handle.interface_count += library_interfaces.len();
        Ok(())
    }

    fn link_hierarchical_codegen_objects(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: &mut Self::LinkHandle,
        codegen_objects: &[Self::CodegenObjectArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "hlink-objects:{}:{}",
            page.group_index,
            codegen_objects.len()
        ));
        if codegen_objects
            .iter()
            .any(|artifact| !artifact.path.is_file())
        {
            return Err(CompileError::GpuFrontend(
                "test hierarchical link received a missing codegen object path".into(),
            ));
        }
        link_handle.object_count += codegen_objects.len();
        Ok(())
    }

    fn link_hierarchical_partial_links(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: &mut Self::LinkHandle,
        partial_links: &[Self::PartialLinkArtifact],
    ) -> Result<(), CompileError> {
        self.events.push(format!(
            "hlink-partials:{}:{}",
            page.group_index,
            partial_links.len()
        ));
        for partial in partial_links {
            let bytes = std::fs::read(&partial.path).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "read test partial link artifact {}: {err}",
                    partial.path.display()
                ))
            })?;
            let (interface_count, object_count) = test_partial_link_counts(&bytes)?;
            link_handle.interface_count += interface_count;
            link_handle.object_count += object_count;
        }
        Ok(())
    }

    fn finish_hierarchical_partial_link_group(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: Self::LinkHandle,
    ) -> Result<Self::PartialLinkArtifact, CompileError> {
        self.events.push(format!(
            "finish-hpartial:{}:{}:{}",
            page.group_index, link_handle.interface_count, link_handle.object_count
        ));
        self.write_artifact(
            "partial",
            format!(
                "partial:{}:{}:{}",
                page.group_index, link_handle.interface_count, link_handle.object_count
            ),
        )
    }

    fn finish_hierarchical_link_output(
        &mut self,
        page: &SourcePackHierarchicalLinkExecutionPage,
        link_handle: Self::LinkHandle,
    ) -> Result<Self::LinkedOutputArtifact, CompileError> {
        self.events.push(format!(
            "finish-hlink:{}:{}:{}",
            page.group_index, link_handle.interface_count, link_handle.object_count
        ));
        self.write_artifact(
            "hlinked",
            format!(
                "hlinked:{}:{}",
                link_handle.interface_count, link_handle.object_count
            ),
        )
    }
}

impl SourcePackPathAsyncPagedArtifactBuildExecutor for RecordingSourcePackFileArtifactExecutor {
    type LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath;
    type CodegenObjectArtifact = SourcePackFilesystemArtifactPath;
    type LinkHandle = TestByteLinkHandle;
    type LinkedOutputArtifact = SourcePackFilesystemArtifactPath;
    type LibraryInterfaceBuildHandle = TestByteBuildHandle;
    type CodegenObjectBuildHandle = TestByteBuildHandle;

    fn begin_library_interface<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        source_files: &'a [ExplicitSourcePathFile],
    ) -> SourcePackBoxFuture<'a, Self::LibraryInterfaceBuildHandle> {
        Box::pin(async move {
            <Self as SourcePackPathPagedArtifactBuildExecutor>::begin_library_interface(
                self,
                job,
                source_files,
            )
        })
    }

    fn add_library_interface_dependency_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: &'a mut Self::LibraryInterfaceBuildHandle,
        dependency_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            <Self as SourcePackPathPagedArtifactBuildExecutor>::add_library_interface_dependency_batch(
                    self,
                    job,
                    handle,
                    dependency_interfaces,
                )
        })
    }

    fn finish_library_interface<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: Self::LibraryInterfaceBuildHandle,
    ) -> SourcePackBoxFuture<'a, Self::LibraryInterfaceArtifact> {
        Box::pin(async move {
            <Self as SourcePackPathPagedArtifactBuildExecutor>::finish_library_interface(
                self, job, handle,
            )
        })
    }

    fn begin_codegen_object<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        source_files: &'a [ExplicitSourcePathFile],
        library_interface: &'a Self::LibraryInterfaceArtifact,
    ) -> SourcePackBoxFuture<'a, Self::CodegenObjectBuildHandle> {
        Box::pin(async move {
            <Self as SourcePackPathPagedArtifactBuildExecutor>::begin_codegen_object(
                self,
                job,
                source_files,
                library_interface,
            )
        })
    }

    fn add_codegen_object_dependency_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: &'a mut Self::CodegenObjectBuildHandle,
        dependency_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            <Self as SourcePackPathPagedArtifactBuildExecutor>::add_codegen_object_dependency_batch(
                self,
                job,
                handle,
                dependency_interfaces,
            )
        })
    }

    fn finish_codegen_object<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        handle: Self::CodegenObjectBuildHandle,
    ) -> SourcePackBoxFuture<'a, Self::CodegenObjectArtifact> {
        Box::pin(async move {
            <Self as SourcePackPathPagedArtifactBuildExecutor>::finish_codegen_object(
                self, job, handle,
            )
        })
    }

    fn begin_link_codegen_objects<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
    ) -> SourcePackBoxFuture<'a, Self::LinkHandle> {
        Box::pin(async move {
            <Self as SourcePackPathArtifactBuildExecutor>::begin_link_codegen_objects(self, job)
        })
    }

    fn link_library_interface_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: &'a mut Self::LinkHandle,
        batch: &'a SourcePackLinkInterfaceBatch,
        library_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            <Self as SourcePackPathArtifactBuildExecutor>::link_library_interface_batch(
                self,
                job,
                link_handle,
                batch,
                library_interfaces,
            )
        })
    }

    fn link_codegen_object_batch<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: &'a mut Self::LinkHandle,
        batch: &'a SourcePackLinkObjectBatch,
        codegen_objects: &'a [Self::CodegenObjectArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            <Self as SourcePackPathArtifactBuildExecutor>::link_codegen_object_batch(
                self,
                job,
                link_handle,
                batch,
                codegen_objects,
            )
        })
    }

    fn finish_link_codegen_objects<'a>(
        &'a mut self,
        job: &'a SourcePackJob,
        link_handle: Self::LinkHandle,
    ) -> SourcePackBoxFuture<'a, Self::LinkedOutputArtifact> {
        Box::pin(async move {
            <Self as SourcePackPathArtifactBuildExecutor>::finish_link_codegen_objects(
                self,
                job,
                link_handle,
            )
        })
    }
}

impl SourcePackPathAsyncHierarchicalLinkExecutor for RecordingSourcePackFileArtifactExecutor {
    type PartialLinkArtifact = SourcePackFilesystemArtifactPath;

    fn begin_hierarchical_link_group<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
    ) -> SourcePackBoxFuture<'a, Self::LinkHandle> {
        Box::pin(async move {
            <Self as SourcePackPathHierarchicalLinkExecutor>::begin_hierarchical_link_group(
                self, page,
            )
        })
    }

    fn link_hierarchical_library_interfaces<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: &'a mut Self::LinkHandle,
        library_interfaces: &'a [Self::LibraryInterfaceArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            <Self as SourcePackPathHierarchicalLinkExecutor>::link_hierarchical_library_interfaces(
                self,
                page,
                link_handle,
                library_interfaces,
            )
        })
    }

    fn link_hierarchical_codegen_objects<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: &'a mut Self::LinkHandle,
        codegen_objects: &'a [Self::CodegenObjectArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            <Self as SourcePackPathHierarchicalLinkExecutor>::link_hierarchical_codegen_objects(
                self,
                page,
                link_handle,
                codegen_objects,
            )
        })
    }

    fn link_hierarchical_partial_links<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: &'a mut Self::LinkHandle,
        partial_links: &'a [Self::PartialLinkArtifact],
    ) -> SourcePackBoxFuture<'a, ()> {
        Box::pin(async move {
            <Self as SourcePackPathHierarchicalLinkExecutor>::link_hierarchical_partial_links(
                self,
                page,
                link_handle,
                partial_links,
            )
        })
    }

    fn finish_hierarchical_partial_link_group<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: Self::LinkHandle,
    ) -> SourcePackBoxFuture<'a, Self::PartialLinkArtifact> {
        Box::pin(async move {
            <Self as SourcePackPathHierarchicalLinkExecutor>::finish_hierarchical_partial_link_group(
                self,
                page,
                link_handle,
            )
        })
    }

    fn finish_hierarchical_link_output<'a>(
        &'a mut self,
        page: &'a SourcePackHierarchicalLinkExecutionPage,
        link_handle: Self::LinkHandle,
    ) -> SourcePackBoxFuture<'a, Self::LinkedOutputArtifact> {
        Box::pin(async move {
            <Self as SourcePackPathHierarchicalLinkExecutor>::finish_hierarchical_link_output(
                self,
                page,
                link_handle,
            )
        })
    }
}

#[test]
fn source_pack_execution_lookup_supports_direct_and_sparse_job_indices() {
    fn job(job_index: usize) -> SourcePackJob {
        SourcePackJob {
            job_index,
            phase: SourcePackJobPhase::Codegen,
            phase_unit_index: job_index,
            library_job_index: None,
            library_id: job_index as u32,
            first_source_index: job_index,
            source_file_count: 1,
            source_bytes: 1,
            source_lines: 1,
            oversized_source_file: false,
            dependency_job_indices: Vec::new(),
        }
    }

    fn manifest(job_index: usize) -> SourcePackJobArtifactManifest {
        SourcePackJobArtifactManifest {
            job_index,
            phase: SourcePackJobPhase::Codegen,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interface_artifact_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_object_artifact_ranges: Vec::new(),
            input_objects: Vec::new(),
            outputs: Vec::new(),
        }
    }

    let direct_schedule = SourcePackJobSchedule {
        jobs: vec![job(0), job(1)],
        dependency_job_ranges_by_job_index: Vec::new(),
    };
    assert_eq!(
        source_pack_schedule_job(&direct_schedule, 1)
            .expect("direct schedule lookup")
            .library_id,
        1
    );

    let sparse_schedule = SourcePackJobSchedule {
        jobs: vec![job(7), job(3)],
        dependency_job_ranges_by_job_index: Vec::new(),
    };
    assert_eq!(
        source_pack_schedule_job(&sparse_schedule, 3)
            .expect("fallback schedule lookup")
            .job_index,
        3
    );
    assert!(
        source_pack_schedule_job(&sparse_schedule, 1)
            .expect_err("missing sparse schedule job")
            .to_string()
            .contains("missing job 1")
    );

    let direct_manifest = SourcePackJobArtifactManifestPlan {
        jobs: vec![manifest(0), manifest(1)],
    };
    assert_eq!(
        source_pack_job_artifact_manifest(&direct_manifest, 1)
            .expect("direct manifest lookup")
            .job_index,
        1
    );

    let sparse_manifest = SourcePackJobArtifactManifestPlan {
        jobs: vec![manifest(7), manifest(3)],
    };
    assert_eq!(
        source_pack_job_artifact_manifest(&sparse_manifest, 3)
            .expect("fallback manifest lookup")
            .job_index,
        3
    );
    assert!(
        source_pack_job_artifact_manifest(&sparse_manifest, 1)
            .expect_err("missing sparse manifest job")
            .to_string()
            .contains("missing job 1")
    );
}

#[test]
fn hierarchical_link_execution_rejects_truncated_paged_inputs() {
    fn artifact_ref(
        target: SourcePackArtifactTarget,
        kind: SourcePackArtifactKind,
        artifact_index: usize,
        producing_job_index: usize,
    ) -> SourcePackArtifactRef {
        SourcePackArtifactRef {
            artifact_index,
            key: source_pack_artifact_key_for_output(
                target,
                kind,
                producing_job_index as u32,
                producing_job_index,
                0,
                1,
            ),
            producing_job_index,
            kind,
        }
    }

    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-hlink-truncated-page-test-{}-{suffix}",
        std::process::id()
    ));
    let mut store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;

    let interface_ref = artifact_ref(target, SourcePackArtifactKind::LibraryInterface, 0, 0);
    let object_ref = artifact_ref(target, SourcePackArtifactKind::CodegenObject, 1, 1);
    store
        .store_library_interface(&interface_ref, b"iface".to_vec())
        .expect("store interface artifact");
    store
        .store_codegen_object(&object_ref, b"object".to_vec())
        .expect("store object artifact");
    store
        .store_hierarchical_link_execution_object_page(
            &SourcePackHierarchicalLinkExecutionObjectPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
                target,
                group_index: 0,
                job_index: 10,
                page_index: 0,
                first_input_position: 0,
                input_count: 1,
                input_objects: vec![object_ref],
            },
        )
        .expect("store truncated object input page");

    let leaf_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: 0,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: 10,
        input_interface_count: 1,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: vec![interface_ref],
        input_object_count: 2,
        input_object_page_count: 1,
        input_objects: Vec::new(),
        input_group_count: 0,
        input_group_page_count: 0,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: source_pack_hierarchical_link_partial_output_key(target, 0, 10),
        final_output: false,
    };
    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    assert!(
            execute_source_pack_hierarchical_link_execution_page(
                &leaf_page,
                &mut executor,
                &mut store,
            )
            .expect_err("truncated object pages should be rejected")
            .to_string()
            .contains("streamed 1 object refs but expected 2")
        );

    let partial_key = source_pack_hierarchical_link_partial_output_key(target, 0, 20);
    store
        .store_partial_link_output(&partial_key, b"partial:0:1:1".to_vec())
        .expect("store partial link artifact");
    store
        .store_hierarchical_link_execution_partial_page(
            &SourcePackHierarchicalLinkExecutionPartialPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION,
                target,
                group_index: 3,
                job_index: 20,
                page_index: 0,
                first_input_position: 0,
                input_count: 1,
                input_group_indices: vec![0],
                input_group_output_keys: vec![partial_key],
            },
        )
        .expect("store truncated partial input page");

    let reduce_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: 3,
        kind: SourcePackHierarchicalLinkGroupKind::Reduce,
        job_index: 20,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: Vec::new(),
        input_group_count: 2,
        input_group_page_count: 1,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: source_pack_hierarchical_link_partial_output_key(target, 3, 20),
        final_output: false,
    };
    assert!(
        execute_source_pack_hierarchical_link_execution_page(
            &reduce_page,
            &mut executor,
            &mut store,
        )
        .expect_err("truncated partial-link pages should be rejected")
        .to_string()
        .contains("streamed 1 partial-link refs but expected 2")
    );

    std::fs::remove_dir_all(&root).expect("remove truncated hlink page test dir");
}

#[test]
fn source_pack_job_shape_rejects_invalid_oversized_and_link_payloads() {
    let valid_codegen = SourcePackJob {
        job_index: 3,
        phase: SourcePackJobPhase::Codegen,
        phase_unit_index: 0,
        library_job_index: Some(0),
        library_id: 7,
        first_source_index: 9,
        source_file_count: 1,
        source_bytes: 1,
        source_lines: 1,
        oversized_source_file: true,
        dependency_job_indices: vec![0],
    };
    validate_source_pack_job_shape(&valid_codegen, "test", CompileError::GpuFrontend)
        .expect("single oversized source file should be accepted");

    let multi_file_oversized = SourcePackJob {
        source_file_count: 2,
        ..valid_codegen.clone()
    };
    assert!(
        validate_source_pack_job_shape(&multi_file_oversized, "test", CompileError::GpuFrontend,)
            .expect_err("oversized jobs must not span multiple source files")
            .to_string()
            .contains("oversized source file but spans 2 files")
    );

    let link_with_source_payload = SourcePackJob {
        job_index: 4,
        phase: SourcePackJobPhase::Link,
        phase_unit_index: 0,
        library_job_index: None,
        library_id: u32::MAX,
        first_source_index: 9,
        source_file_count: 1,
        source_bytes: 1,
        source_lines: 1,
        oversized_source_file: false,
        dependency_job_indices: Vec::new(),
    };
    assert!(
        validate_source_pack_job_shape(
            &link_with_source_payload,
            "test",
            CompileError::GpuFrontend,
        )
        .expect_err("link jobs must not carry source payload")
        .to_string()
        .contains("link job 4 has non-link job payload")
    );
}

#[test]
fn explicit_source_pack_codegen_plan_keeps_library_boundaries() {
    let pack = ExplicitSourcePack::new(
        vec![
            "fn a() {}\n".into(),
            "fn b() {}\n".into(),
            "fn c() {}\n".into(),
        ],
        vec![0, 0, 1],
    )
    .expect("explicit source pack");

    let limits = CodegenUnitLimits {
        max_source_bytes: 64,
        max_source_files: 8,
    };
    let batch_limits = SourcePackJobBatchLimits::from_codegen_unit_limits(limits);
    let plan = pack.codegen_unit_plan(limits);
    let job_plan = pack.job_plan(limits);

    assert_eq!(plan.unit_count(), 2);
    assert_eq!(plan.units[0].source_range(), 0..2);
    assert_eq!(plan.units[1].source_range(), 2..3);
    assert_eq!(job_plan.libraries.library_count(), 2);
    assert_eq!(job_plan.codegen_units, plan);
    let schedule = pack.job_schedule(limits);
    let build_plan = pack.build_plan(limits);
    let compact_manifest = pack.compact_build_artifact_manifest(limits, batch_limits);
    let retained_compact_manifest = build_plan.compact_build_artifact_manifest(batch_limits);
    assert_eq!(schedule.frontend_job_count(), 2);
    assert_eq!(schedule.codegen_job_count(), 2);
    assert_eq!(schedule.link_job_count(), 1);
    assert_eq!(build_plan.interface_artifact_count(), 2);
    assert_eq!(build_plan.object_artifact_count(), 2);
    assert_eq!(build_plan.linked_output_artifact_count(), 1);
    assert_eq!(
        compact_manifest.artifact_count,
        retained_compact_manifest.artifact_count
    );
    assert_eq!(
        compact_manifest.job_count,
        retained_compact_manifest.job_count
    );
    assert_eq!(
        compact_manifest.job_batch_count,
        retained_compact_manifest.job_batch_count
    );
    assert_eq!(
        compact_manifest.link_object_batch_count,
        retained_compact_manifest.link_object_batch_count
    );
    assert!(compact_manifest.job_schedule.jobs.is_empty());
    assert!(compact_manifest.artifacts.artifacts.is_empty());
    assert_eq!(
        pack.source_slice_for_unit(&plan.units[1]),
        &pack.sources[2..3]
    );
    assert_eq!(
        pack.source_slice_for_job(&schedule.jobs[3]),
        &pack.sources[2..3]
    );
    assert_eq!(
        pack.source_slice_for_artifact(
            &build_plan.artifacts[build_plan.link.output_artifact_index]
        ),
        &pack.sources[..]
    );
}

#[test]
fn explicit_source_pack_compact_manifest_uses_bounded_frontend_jobs() {
    let pack = ExplicitSourcePack::new(
        vec!["aaaa".into(), "bbbb".into(), "cccc".into()],
        vec![7, 7, 11],
    )
    .expect("explicit source pack");
    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 8,
    };
    let batch_limits = SourcePackJobBatchLimits::from_codegen_unit_limits(limits);
    let compact_manifest = pack.compact_build_artifact_manifest(limits, batch_limits);
    let default_compact_manifest = pack
        .build_plan(limits)
        .compact_build_artifact_manifest(batch_limits);
    let bounded_compact_manifest = pack
        .bounded_frontend_build_plan(limits)
        .compact_build_artifact_manifest(batch_limits);
    let unbounded_compact_manifest = pack
        .whole_library_frontend_build_plan(limits)
        .compact_build_artifact_manifest(batch_limits);

    assert_eq!(
        compact_manifest.job_count,
        bounded_compact_manifest.job_count
    );
    assert_eq!(
        default_compact_manifest.job_count,
        bounded_compact_manifest.job_count
    );
    assert_eq!(
        compact_manifest.artifact_count,
        bounded_compact_manifest.artifact_count
    );
    assert_eq!(
        default_compact_manifest.artifact_count,
        bounded_compact_manifest.artifact_count
    );
    assert_eq!(
        compact_manifest.link_interface_batch_count,
        bounded_compact_manifest.link_interface_batch_count
    );
    assert_ne!(
        compact_manifest.job_count,
        unbounded_compact_manifest.job_count
    );
    assert_ne!(
        default_compact_manifest.job_count,
        unbounded_compact_manifest.job_count
    );
    assert_eq!(compact_manifest.job_count, 7);
    assert_eq!(compact_manifest.artifact_count, 7);
    assert!(compact_manifest.job_schedule.jobs.is_empty());
    assert!(compact_manifest.artifacts.artifacts.is_empty());
}

#[test]
fn explicit_source_pack_build_executor_receives_bounded_jobs_and_dependencies() {
    let pack = ExplicitSourcePack::from_libraries(vec![
        ExplicitSourceLibrary {
            library_id: 1,
            sources: vec!["aaaa".into(), "bbbb".into()],
            dependency_library_ids: Vec::new(),
        },
        ExplicitSourceLibrary {
            library_id: 2,
            sources: vec!["cccc".into()],
            dependency_library_ids: vec![1],
        },
        ExplicitSourceLibrary {
            library_id: 3,
            sources: vec!["dddd".into()],
            dependency_library_ids: vec![1, 2],
        },
    ])
    .expect("source pack");
    let mut executor = RecordingSourcePackExecutor::default();
    let result = pack
        .execute_build_plan(
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 8,
            },
            &mut executor,
        )
        .expect("execute source-pack build plan");

    assert_eq!(result.library_interfaces.len(), 4);
    assert_eq!(result.codegen_objects.len(), 4);
    assert_eq!(
        result
            .codegen_objects
            .iter()
            .map(|object| (object.library_id, object.source_range.clone()))
            .collect::<Vec<_>>(),
        vec![(1, 0..1), (1, 1..2), (2, 2..3), (3, 3..4)]
    );
    assert_eq!(result.linked_output.interface_count, 4);
    assert_eq!(result.linked_output.object_count, 4);
    assert_eq!(result.linked_output.object_libraries, vec![1, 1, 2, 3]);
    assert_eq!(
        result.library_interfaces[3].dependency_libraries,
        vec![1, 1, 2]
    );
    assert_eq!(
        result.codegen_objects[3].dependency_libraries,
        vec![1, 1, 2]
    );
    assert_eq!(executor.max_codegen_source_files, 1);
    assert_eq!(
        executor.events,
        vec![
            "frontend:1:1:[]",
            "frontend:1:1:[]",
            "frontend:2:1:[1, 1]",
            "codegen:1:0..1:[1]",
            "codegen:1:1..2:[1]",
            "frontend:3:1:[1, 1, 2]",
            "codegen:2:2..3:[1, 1]",
            "codegen:3:3..4:[1, 1, 2]",
            "link:8:4:4",
        ]
    );
}

#[test]
fn explicit_source_pack_topologically_orders_out_of_order_libraries() {
    let pack = ExplicitSourcePack::from_libraries(vec![
        ExplicitSourceLibrary {
            library_id: 3,
            sources: vec!["module app;\n".into()],
            dependency_library_ids: vec![1, 2],
        },
        ExplicitSourceLibrary {
            library_id: 1,
            sources: vec!["module core;\n".into()],
            dependency_library_ids: Vec::new(),
        },
        ExplicitSourceLibrary {
            library_id: 2,
            sources: vec!["module util;\n".into()],
            dependency_library_ids: vec![1],
        },
    ])
    .expect("topologically ordered source pack");

    assert_eq!(pack.library_ids, vec![1, 2, 3]);
    assert_eq!(
        pack.sources,
        vec!["module core;\n", "module util;\n", "module app;\n"]
    );
    let schedule = pack.job_schedule(CodegenUnitLimits::default());
    assert_eq!(
        schedule
            .jobs
            .iter()
            .filter(|job| job.phase == SourcePackJobPhase::LibraryFrontend)
            .map(|job| (job.library_id, job.dependency_job_indices.clone()))
            .collect::<Vec<_>>(),
        vec![(1, vec![]), (2, vec![0]), (3, vec![0, 1])]
    );
}

#[test]
fn explicit_source_pack_topology_deduplicates_parallel_dependency_edges() {
    let pack = ExplicitSourcePack::from_libraries(vec![
        ExplicitSourceLibrary {
            library_id: 2,
            sources: vec!["module app;\n".into()],
            dependency_library_ids: vec![1, 1],
        },
        ExplicitSourceLibrary {
            library_id: 1,
            sources: vec!["module core;\n".into()],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect("duplicate dependency edges should not block topological order");
    let schedule = pack.job_schedule(CodegenUnitLimits::default());

    assert_eq!(pack.library_ids, vec![1, 2]);
    assert_eq!(
        schedule
            .jobs
            .iter()
            .filter(|job| job.phase == SourcePackJobPhase::LibraryFrontend)
            .map(|job| (job.library_id, job.dependency_job_indices.clone()))
            .collect::<Vec<_>>(),
        vec![(1, vec![]), (2, vec![0])]
    );
}

#[test]
fn explicit_source_pack_rejects_library_dependency_cycles() {
    let err = ExplicitSourcePack::from_libraries(vec![
        ExplicitSourceLibrary {
            library_id: 1,
            sources: vec!["module a;\n".into()],
            dependency_library_ids: vec![2],
        },
        ExplicitSourceLibrary {
            library_id: 2,
            sources: vec!["module b;\n".into()],
            dependency_library_ids: vec![1],
        },
    ])
    .expect_err("cycle should fail");

    assert!(err.to_string().contains("cycle"));
}

#[test]
fn explicit_source_pack_from_libraries_flattens_arbitrary_libraries() {
    let pack = ExplicitSourcePack::from_libraries(vec![
        ExplicitSourceLibrary {
            library_id: 7,
            sources: vec!["module a;\n".into(), "module a::x;\n".into()],
            dependency_library_ids: Vec::new(),
        },
        ExplicitSourceLibrary {
            library_id: 11,
            sources: vec!["module b;\n".into()],
            dependency_library_ids: vec![7],
        },
        ExplicitSourceLibrary {
            library_id: 42,
            sources: vec!["module c;\n".into(), "module c::x;\n".into()],
            dependency_library_ids: vec![7, 11],
        },
    ])
    .expect("explicit source pack from libraries");

    assert_eq!(
        pack.library_ids,
        vec![7, 7, 11, 42, 42],
        "library ids should track every flattened source file"
    );
    let job_plan = pack.job_plan(CodegenUnitLimits::default());
    let schedule = pack.job_schedule(CodegenUnitLimits::default());
    let build_plan = pack.build_plan(CodegenUnitLimits::default());
    assert_eq!(job_plan.libraries.library_count(), 3);
    assert_eq!(
        job_plan
            .libraries
            .libraries
            .iter()
            .map(|library| (library.library_id, library.source_range()))
            .collect::<Vec<_>>(),
        vec![(7, 0..2), (11, 2..3), (42, 3..5)]
    );
    assert_eq!(schedule.frontend_job_count(), 3);
    assert_eq!(schedule.codegen_job_count(), 3);
    assert_eq!(schedule.link_job_count(), 1);
    assert_eq!(schedule.dependency_edge_count(), 12);
    assert_eq!(schedule.max_job_dependency_count(), 3);
    assert_eq!(build_plan.interface_artifact_count(), 3);
    assert_eq!(build_plan.object_artifact_count(), 3);
    assert_eq!(build_plan.linked_output_artifact_count(), 1);
}

#[test]
fn explicit_source_pack_path_loader_records_stdlib_and_user_libraries() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-source-pack-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create temp source-pack dir");
    let stdlib_path = root.join("std.lanius");
    let user_path = root.join("app.lanius");
    std::fs::write(&stdlib_path, "module std::prelude;\n").expect("write stdlib source");
    std::fs::write(&user_path, "module app::main;\n").expect("write user source");

    let pack = load_explicit_source_pack_manifest_from_paths(&[&stdlib_path], &[&user_path])
        .expect("load explicit source-pack manifest");
    let legacy_sources = load_explicit_source_pack_from_paths(&[&stdlib_path], &[&user_path])
        .expect("load legacy explicit source pack");
    let job_plan = plan_explicit_source_pack_jobs_from_paths(
        &[&stdlib_path],
        &[&user_path],
        CodegenUnitLimits::default(),
    )
    .expect("plan explicit source-pack jobs");
    let compact_manifest = plan_explicit_source_pack_compact_artifact_manifest_from_paths(
        &[&stdlib_path],
        &[&user_path],
        CodegenUnitLimits::default(),
        SourcePackJobBatchLimits::from_codegen_unit_limits(CodegenUnitLimits::default()),
    )
    .expect("plan explicit source-pack compact artifact manifest");
    let build_plan = plan_explicit_source_pack_build_from_paths(
        &[&stdlib_path],
        &[&user_path],
        CodegenUnitLimits::default(),
    )
    .expect("plan explicit source-pack build");
    std::fs::remove_dir_all(&root).expect("remove temp source-pack dir");

    assert_eq!(
        pack.sources,
        vec!["module std::prelude;\n", "module app::main;\n"]
    );
    assert_eq!(pack.library_ids, vec![0, 1]);
    assert_eq!(
        pack.library_dependencies,
        vec![SourcePackLibraryDependency {
            library_id: 1,
            depends_on_library_id: 0,
        }]
    );
    assert_eq!(legacy_sources, pack.sources);
    assert_eq!(job_plan.libraries.library_count(), 2);
    assert_eq!(job_plan.codegen_units.unit_count(), 2);
    assert_eq!(build_plan.schedule.dependency_edge_count(), 6);
    assert_eq!(build_plan.schedule.max_job_dependency_count(), 2);
    assert_eq!(build_plan.interface_artifact_count(), 2);
    assert_eq!(build_plan.object_artifact_count(), 2);
    assert_eq!(build_plan.linked_output_artifact_count(), 1);
    assert_eq!(compact_manifest.job_count, build_plan.schedule.jobs.len());
    assert_eq!(compact_manifest.artifact_count, build_plan.artifacts.len());
    assert_eq!(
        compact_manifest.job_artifact_count,
        build_plan.schedule.jobs.len()
    );
    assert_eq!(
        compact_manifest.job_artifact_io_count,
        build_plan.schedule.jobs.len()
    );
    assert!(compact_manifest.job_schedule.jobs.is_empty());
    assert!(compact_manifest.artifacts.artifacts.is_empty());
}

#[test]
fn explicit_source_library_path_loader_accepts_arbitrary_libraries() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-library-paths-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create temp library-path dir");
    let core_path = root.join("core.lani");
    let util_path = root.join("util.lani");
    let app_main_path = root.join("app_main.lani");
    let app_worker_path = root.join("app_worker.lani");
    std::fs::write(&core_path, "module core;\n").expect("write core source");
    std::fs::write(&util_path, "module util;\nimport core;\n").expect("write util source");
    std::fs::write(&app_main_path, "module app::main;\nimport util;\n")
        .expect("write app main source");
    std::fs::write(&app_worker_path, "module app::worker;\nimport core;\n")
        .expect("write app worker source");

    let libraries = vec![
        ExplicitSourceLibraryPaths {
            library_id: 30,
            paths: vec![app_main_path.clone(), app_worker_path.clone()],
            dependency_library_ids: vec![10, 20],
        },
        ExplicitSourceLibraryPaths {
            library_id: 10,
            paths: vec![core_path.clone()],
            dependency_library_ids: Vec::new(),
        },
        ExplicitSourceLibraryPaths {
            library_id: 20,
            paths: vec![util_path.clone()],
            dependency_library_ids: vec![10],
        },
    ];
    let pack = load_explicit_source_libraries_from_paths(libraries)
        .expect("load arbitrary source libraries");
    let job_plan = plan_explicit_source_libraries_jobs_from_paths(
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 30,
                paths: vec![app_main_path.clone(), app_worker_path.clone()],
                dependency_library_ids: vec![10, 20],
            },
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path.clone()],
                dependency_library_ids: Vec::new(),
            },
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![util_path.clone()],
                dependency_library_ids: vec![10],
            },
        ],
        CodegenUnitLimits::default(),
    )
    .expect("plan arbitrary source library jobs");
    let build_plan = plan_explicit_source_libraries_build_from_paths(
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 30,
                paths: vec![app_main_path.clone(), app_worker_path.clone()],
                dependency_library_ids: vec![10, 20],
            },
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path.clone()],
                dependency_library_ids: Vec::new(),
            },
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![util_path.clone()],
                dependency_library_ids: vec![10],
            },
        ],
        CodegenUnitLimits::default(),
    )
    .expect("plan arbitrary source library build");
    let compact_manifest = plan_explicit_source_libraries_compact_artifact_manifest_from_paths(
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 30,
                paths: vec![app_main_path, app_worker_path],
                dependency_library_ids: vec![10, 20],
            },
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            },
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![util_path],
                dependency_library_ids: vec![10],
            },
        ],
        CodegenUnitLimits::default(),
        SourcePackJobBatchLimits::from_codegen_unit_limits(CodegenUnitLimits::default()),
    )
    .expect("plan arbitrary source library compact artifact manifest");
    std::fs::remove_dir_all(&root).expect("remove temp library-path dir");

    assert_eq!(
        pack.sources,
        vec![
            "module core;\n",
            "module util;\nimport core;\n",
            "module app::main;\nimport util;\n",
            "module app::worker;\nimport core;\n",
        ]
    );
    assert_eq!(pack.library_ids, vec![10, 20, 30, 30]);
    assert_eq!(
        pack.library_dependencies,
        vec![
            SourcePackLibraryDependency {
                library_id: 30,
                depends_on_library_id: 10,
            },
            SourcePackLibraryDependency {
                library_id: 30,
                depends_on_library_id: 20,
            },
            SourcePackLibraryDependency {
                library_id: 20,
                depends_on_library_id: 10,
            },
        ]
    );
    assert_eq!(job_plan.libraries.library_count(), 3);
    assert_eq!(build_plan.interface_artifact_count(), 3);
    assert_eq!(build_plan.object_artifact_count(), 3);
    assert_eq!(build_plan.linked_output_artifact_count(), 1);
    assert_eq!(build_plan.schedule.dependency_edge_count(), 12);
    assert_eq!(compact_manifest.job_count, build_plan.schedule.jobs.len());
    assert_eq!(compact_manifest.artifact_count, build_plan.artifacts.len());
    assert_eq!(
        compact_manifest.link_interface_batch_count,
        build_plan
            .link_interface_batches(SourcePackJobBatchLimits::from_codegen_unit_limits(
                CodegenUnitLimits::default()
            ))
            .batch_count()
    );
    assert!(compact_manifest.job_schedule.jobs.is_empty());
    assert!(compact_manifest.artifacts.artifacts.is_empty());
}

#[test]
fn explicit_source_path_manifest_plans_from_metadata_without_reading_sources() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-path-metadata-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create temp path-metadata dir");
    let core_path = root.join("core.lani");
    let core_extra_path = root.join("core_extra.lani");
    let app_path = root.join("app.lani");
    std::fs::write(&core_path, b"core\n").expect("write core source");
    std::fs::write(&core_extra_path, b"util\n").expect("write extra core source");
    std::fs::write(&app_path, [0xff, 0xfe, 0xfd, b'\n']).expect("write invalid utf8 app");

    let manifest = load_explicit_source_libraries_path_manifest(vec![
        ExplicitSourceLibraryPaths {
            library_id: 2,
            paths: vec![app_path.clone()],
            dependency_library_ids: vec![1],
        },
        ExplicitSourceLibraryPaths {
            library_id: 1,
            paths: vec![core_path.clone(), core_extra_path.clone()],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect("load metadata-only source manifest");
    let limits = CodegenUnitLimits {
        max_source_bytes: 5,
        max_source_files: 8,
    };
    let job_plan = plan_explicit_source_libraries_jobs_from_paths(
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 2,
                paths: vec![app_path.clone()],
                dependency_library_ids: vec![1],
            },
            ExplicitSourceLibraryPaths {
                library_id: 1,
                paths: vec![core_path.clone(), core_extra_path.clone()],
                dependency_library_ids: Vec::new(),
            },
        ],
        limits,
    )
    .expect("plan metadata-only source jobs");
    let compact_manifest = manifest.compact_build_artifact_manifest(
        limits,
        SourcePackJobBatchLimits::from_codegen_unit_limits(limits),
    );
    let stream_compact_manifest =
            plan_ordered_explicit_source_library_path_dependency_streams_compact_artifact_manifest_from_path_metadata_for_target(
                vec![
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 1,
                        source_file_count: 2,
                        paths: vec![core_path.clone(), core_extra_path.clone()],
                        dependency_library_count: 0,
                        dependency_library_ids: Vec::<u32>::new(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 2,
                        source_file_count: 1,
                        paths: vec![app_path.clone()],
                        dependency_library_count: 1,
                        dependency_library_ids: vec![1],
                    },
                ],
                limits,
                SourcePackJobBatchLimits::from_codegen_unit_limits(limits),
                SourcePackArtifactTarget::X86_64,
            )
            .expect("plan streamed compact artifact manifest from metadata");
    std::fs::remove_dir_all(&root).expect("remove temp path-metadata dir");

    assert_eq!(
        manifest
            .files
            .iter()
            .map(|file| (
                file.library_id,
                file.path.clone(),
                file.byte_len,
                file.modified_unix_nanos.is_some(),
                file.line_count
            ))
            .collect::<Vec<_>>(),
        vec![
            (1, core_path, 5, true, None),
            (1, core_extra_path, 5, true, None),
            (2, app_path, 4, true, None),
        ]
    );
    assert_eq!(
        manifest.library_dependencies,
        vec![SourcePackLibraryDependency {
            library_id: 2,
            depends_on_library_id: 1,
        }]
    );
    assert_eq!(job_plan.libraries.library_count(), 2);
    assert_eq!(job_plan.codegen_units.unit_count(), 3);
    assert_eq!(job_plan.codegen_units.max_unit_source_bytes(), 5);
    assert_eq!(compact_manifest.job_count, 7);
    assert_eq!(compact_manifest.artifact_count, 7);
    assert_eq!(compact_manifest.job_artifact_count, 7);
    assert_eq!(compact_manifest.job_artifact_io_count, 7);
    assert_eq!(compact_manifest.artifact_use_count, 7);
    assert!(compact_manifest.job_schedule.jobs.is_empty());
    assert!(compact_manifest.artifacts.artifacts.is_empty());
    assert!(compact_manifest.job_artifacts.jobs.is_empty());
    assert_eq!(
        stream_compact_manifest.target,
        SourcePackArtifactTarget::X86_64
    );
    assert_eq!(
        stream_compact_manifest.job_count,
        compact_manifest.job_count
    );
    assert_eq!(
        stream_compact_manifest.artifact_count,
        compact_manifest.artifact_count
    );
    assert_eq!(
        stream_compact_manifest.link_interface_batch_count,
        compact_manifest.link_interface_batch_count
    );
    assert!(stream_compact_manifest.job_schedule.jobs.is_empty());
    assert!(stream_compact_manifest.artifacts.artifacts.is_empty());
}

#[test]
fn streamed_compact_artifact_manifest_rejects_invalid_library_stream_contracts() {
    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 8,
    };
    let batch_limits = SourcePackJobBatchLimits::from_codegen_unit_limits(limits);
    let empty_err =
            plan_ordered_explicit_source_library_path_dependency_streams_compact_artifact_manifest_from_path_metadata::<
                Vec<ExplicitSourceLibraryPathDependencyStream<Vec<std::path::PathBuf>, Vec<u32>>>,
                Vec<std::path::PathBuf>,
                Vec<u32>,
                std::path::PathBuf,
            >(Vec::new(), limits, batch_limits)
            .expect_err("empty compact stream must be rejected");
    assert!(
        empty_err.to_string().contains("no source files"),
        "unexpected empty stream error: {empty_err}"
    );

    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-stream-contract-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create temp stream-contract dir");
    let app_path = root.join("app.lani");
    std::fs::write(&app_path, b"app\n").expect("write app source");

    let later_dependency_err =
            plan_ordered_explicit_source_library_path_dependency_streams_compact_artifact_manifest_from_path_metadata(
                vec![ExplicitSourceLibraryPathDependencyStream {
                    library_id: 2,
                    source_file_count: 1,
                    paths: vec![app_path.clone()],
                    dependency_library_count: 1,
                    dependency_library_ids: vec![1],
                }],
                limits,
                batch_limits,
            )
            .expect_err("later dependency compact stream must be rejected");
    std::fs::remove_dir_all(&root).expect("remove temp stream-contract dir");
    assert!(
        later_dependency_err
            .to_string()
            .contains("depends on missing or later library 1"),
        "unexpected later dependency error: {later_dependency_err}"
    );
}

#[test]
fn ordered_dependency_stream_schedule_rejects_invalid_dependency_records() {
    fn err_for<F>(case_name: &str, build_libraries: F) -> CompileError
    where
        F: FnOnce(
            PathBuf,
            PathBuf,
        )
            -> Vec<ExplicitSourceLibraryPathDependencyStream<Vec<PathBuf>, Vec<u32>>>,
    {
        let suffix = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = std::env::temp_dir().join(format!(
            "laniusc-dependency-stream-{case_name}-{}-{suffix}",
            std::process::id()
        ));
        let source_root = root.join("sources");
        let artifact_root = root.join("artifacts");
        std::fs::create_dir_all(&source_root).expect("create temp dependency-stream dir");
        let core_path = source_root.join("core.lani");
        let app_path = source_root.join("app.lani");
        std::fs::write(&core_path, b"core\n").expect("write core source");
        std::fs::write(&app_path, b"app\n").expect("write app source");

        let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
        let result = prepare_library_schedule_pages(
            build_libraries(core_path, app_path),
            &store,
            SourcePackArtifactTarget::X86_64,
            CodegenUnitLimits {
                max_source_bytes: 8,
                max_source_files: 4,
            },
        );
        std::fs::remove_dir_all(&root).expect("remove temp dependency-stream dir");
        match result {
            Ok(_) => panic!("{case_name} dependency stream should be rejected"),
            Err(err) => err,
        }
    }

    let missing_count_err = err_for("missing-count", |core_path, app_path| {
        vec![
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 1,
                source_file_count: 1,
                paths: vec![core_path],
                dependency_library_count: 0,
                dependency_library_ids: Vec::new(),
            },
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 2,
                source_file_count: 1,
                paths: vec![app_path],
                dependency_library_count: 2,
                dependency_library_ids: vec![1],
            },
        ]
    });
    assert!(
        missing_count_err
            .to_string()
            .contains("received 1 dependency libraries but expected 2"),
        "unexpected missing dependency-count error: {missing_count_err}"
    );

    let extra_count_err = err_for("extra-count", |core_path, app_path| {
        vec![
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 1,
                source_file_count: 1,
                paths: vec![core_path],
                dependency_library_count: 0,
                dependency_library_ids: Vec::new(),
            },
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 2,
                source_file_count: 1,
                paths: vec![app_path],
                dependency_library_count: 0,
                dependency_library_ids: vec![1],
            },
        ]
    });
    assert!(
        extra_count_err
            .to_string()
            .contains("received more than 0 dependency libraries"),
        "unexpected extra dependency-count error: {extra_count_err}"
    );

    let duplicate_err = err_for("duplicate", |core_path, app_path| {
        vec![
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 1,
                source_file_count: 1,
                paths: vec![core_path],
                dependency_library_count: 0,
                dependency_library_ids: Vec::new(),
            },
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 2,
                source_file_count: 1,
                paths: vec![app_path],
                dependency_library_count: 2,
                dependency_library_ids: vec![1, 1],
            },
        ]
    });
    assert!(
        duplicate_err
            .to_string()
            .contains("dependency ids must be strictly sorted and unique"),
        "unexpected duplicate dependency error: {duplicate_err}"
    );

    let self_err = err_for("self", |core_path, _app_path| {
        vec![ExplicitSourceLibraryPathDependencyStream {
            library_id: 1,
            source_file_count: 1,
            paths: vec![core_path],
            dependency_library_count: 1,
            dependency_library_ids: vec![1],
        }]
    });
    assert!(
        self_err.to_string().contains("depends on itself"),
        "unexpected self dependency error: {self_err}"
    );

    let missing_later_err = err_for("missing-later", |_core_path, app_path| {
        vec![ExplicitSourceLibraryPathDependencyStream {
            library_id: 2,
            source_file_count: 1,
            paths: vec![app_path],
            dependency_library_count: 1,
            dependency_library_ids: vec![1],
        }]
    });
    assert!(
        missing_later_err
            .to_string()
            .contains("depends on missing or later library 1"),
        "unexpected missing/later dependency error: {missing_later_err}"
    );
}

#[test]
fn explicit_source_path_manifest_loads_only_requested_job_sources() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-job-source-slice-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create temp source-slice dir");
    let first_path = root.join("first.lani");
    let second_path = root.join("second.lani");
    std::fs::write(&first_path, "first\n").expect("write first source");
    std::fs::write(&second_path, "second\n").expect("write second source");

    let manifest = load_explicit_source_libraries_path_manifest(vec![ExplicitSourceLibraryPaths {
        library_id: 7,
        paths: vec![first_path.clone(), second_path.clone()],
        dependency_library_ids: Vec::new(),
    }])
    .expect("load source path manifest");
    let schedule = manifest.job_schedule(CodegenUnitLimits {
        max_source_bytes: 6,
        max_source_files: 8,
    });
    let first_codegen_job = schedule
        .jobs
        .iter()
        .find(|job| job.phase == SourcePackJobPhase::Codegen && job.source_range() == (0..1))
        .expect("first codegen job");
    let loaded_sources = manifest
        .load_sources_for_job(first_codegen_job)
        .expect("load bounded job source slice");
    std::fs::remove_dir_all(&root).expect("remove temp source-slice dir");

    assert_eq!(
        manifest
            .source_files_for_job(first_codegen_job)
            .iter()
            .map(|file| file.path.clone())
            .collect::<Vec<_>>(),
        vec![first_path]
    );
    assert_eq!(loaded_sources, vec!["first\n"]);
    assert_eq!(schedule.codegen_job_count(), 2);
}

#[test]
fn explicit_source_path_manifest_rejects_changed_job_source_metadata() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-job-source-metadata-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create temp source-metadata dir");
    let source_path = root.join("source.lani");
    std::fs::write(&source_path, "first\n").expect("write source");

    let manifest = load_explicit_source_libraries_path_manifest(vec![ExplicitSourceLibraryPaths {
        library_id: 7,
        paths: vec![source_path.clone()],
        dependency_library_ids: Vec::new(),
    }])
    .expect("load source path manifest");
    std::fs::write(&source_path, "changed\n").expect("change source after planning");
    let schedule = manifest.job_schedule(CodegenUnitLimits {
        max_source_bytes: 64,
        max_source_files: 8,
    });
    let frontend_job = schedule
        .jobs
        .iter()
        .find(|job| job.phase == SourcePackJobPhase::LibraryFrontend)
        .expect("frontend job");
    let err = manifest
        .load_sources_for_job(frontend_job)
        .expect_err("changed source metadata should reject stale manifest");
    std::fs::remove_dir_all(&root).expect("remove temp source-metadata dir");

    assert!(
        err.to_string()
            .contains("changed since manifest was planned"),
        "unexpected changed-source error: {err}"
    );
}

#[test]
fn explicit_source_path_manifest_executor_receives_bounded_file_slices() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-path-executor-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create temp path-executor dir");
    let core_path = root.join("core.lani");
    let app_path = root.join("app.lani");
    let worker_path = root.join("worker.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");
    std::fs::write(&worker_path, [0xff, 0xfe, 0xfd, b'!']).expect("write invalid utf8 worker");

    let manifest = load_explicit_source_libraries_path_manifest(vec![
        ExplicitSourceLibraryPaths {
            library_id: 2,
            paths: vec![app_path, worker_path],
            dependency_library_ids: vec![1],
        },
        ExplicitSourceLibraryPaths {
            library_id: 1,
            paths: vec![core_path],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect("load path manifest");
    let mut executor = RecordingSourcePackPathExecutor::default();
    let result = manifest
        .execute_build_plan(
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 8,
            },
            &mut executor,
        )
        .expect("execute path build plan");
    std::fs::remove_dir_all(&root).expect("remove temp path-executor dir");

    assert_eq!(result.library_interfaces.len(), 3);
    assert_eq!(result.codegen_objects.len(), 3);
    assert_eq!(result.linked_output.interface_count, 3);
    assert_eq!(result.linked_output.object_libraries, vec![1, 2, 2]);
    assert_eq!(executor.max_codegen_source_files, 1);
    assert_eq!(
        executor.events,
        vec![
            "frontend:1:1:[]",
            "frontend:2:1:[1]",
            "frontend:2:1:[1]",
            "codegen:1:0..1:4:[]",
            "codegen:2:1..2:4:[2, 1]",
            "codegen:2:2..3:4:[2, 1]",
            "link:6:3:3",
        ]
    );
}

#[test]
fn explicit_source_path_manifest_handle_executor_releases_intermediate_handles() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-path-handle-executor-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create temp path-handle-executor dir");
    let core_path = root.join("core.lani");
    let app_path = root.join("app.lani");
    let worker_path = root.join("worker.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");
    std::fs::write(&worker_path, [0xff, 0xfe, 0xfd, b'!']).expect("write invalid utf8 worker");

    let manifest = load_explicit_source_libraries_path_manifest(vec![
        ExplicitSourceLibraryPaths {
            library_id: 2,
            paths: vec![app_path, worker_path],
            dependency_library_ids: vec![1],
        },
        ExplicitSourceLibraryPaths {
            library_id: 1,
            paths: vec![core_path],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect("load path manifest");
    let mut executor = RecordingSourcePackPathHandleExecutor::default();
    let result = manifest
        .execute_build_plan_with_handles(
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 8,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
            &mut executor,
        )
        .expect("execute path handle build plan");
    std::fs::remove_dir_all(&root).expect("remove temp path-handle-executor dir");

    assert_eq!(result.linked_output.interface_count, 3);
    assert_eq!(result.linked_output.object_count, 3);
    assert_eq!(result.linked_output.object_libraries, vec![1, 2, 2]);
    assert_eq!(
        executor.events,
        vec![
            "frontend:1:1:[]",
            "frontend:2:1:[1]",
            "frontend:2:1:[1]",
            "codegen:1:0..1:4:[]",
            "codegen:2:1..2:4:[2, 1]",
            "codegen:2:2..3:4:[2, 1]",
            "link:6:3:3",
            "release-interface:1",
            "release-interface:2",
            "release-interface:2",
            "release-object:1:0..1",
            "release-object:2:1..2",
            "release-object:2:2..3",
        ]
    );
}

#[test]
fn explicit_source_path_manifest_batched_link_releases_handles_per_batch() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-path-batched-link-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create temp batched-link dir");
    let first_path = root.join("first.lani");
    let second_path = root.join("second.lani");
    let third_path = root.join("third.lani");
    let fourth_path = root.join("fourth.lani");
    std::fs::write(&first_path, b"aaaa").expect("write first source");
    std::fs::write(&second_path, b"bbbb").expect("write second source");
    std::fs::write(&third_path, b"cccc").expect("write third source");
    std::fs::write(&fourth_path, b"dddd").expect("write fourth source");

    let manifest = load_explicit_source_libraries_path_manifest(vec![
        ExplicitSourceLibraryPaths {
            library_id: 7,
            paths: vec![first_path, second_path],
            dependency_library_ids: Vec::new(),
        },
        ExplicitSourceLibraryPaths {
            library_id: 8,
            paths: vec![third_path, fourth_path],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect("load path manifest");
    let mut executor = RecordingSourcePackPathHandleExecutor::default();
    let result = manifest
        .execute_build_plan_with_batched_link_handles(
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 8,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 2,
                max_source_bytes_per_batch: 8,
                max_source_files_per_batch: 2,
            },
            &mut executor,
        )
        .expect("execute batched-link path handle build plan");
    std::fs::remove_dir_all(&root).expect("remove temp batched-link dir");

    assert_eq!(result.linked_output.interface_count, 4);
    assert_eq!(result.linked_output.object_count, 4);
    assert_eq!(result.linked_output.object_libraries, vec![7, 7, 8, 8]);
    assert_eq!(
        executor.events,
        vec![
            "frontend:7:1:[]",
            "frontend:7:1:[]",
            "frontend:8:1:[]",
            "frontend:8:1:[]",
            "codegen:7:0..1:4:[7]",
            "codegen:7:1..2:4:[7]",
            "codegen:8:2..3:4:[8]",
            "codegen:8:3..4:4:[8]",
            "begin-link:8",
            "link-interfaces:0:2",
            "release-interface:7",
            "release-interface:7",
            "link-interfaces:1:2",
            "release-interface:8",
            "release-interface:8",
            "link-batch:0:2",
            "release-object:7:0..1",
            "release-object:7:1..2",
            "link-batch:1:2",
            "release-object:8:2..3",
            "release-object:8:3..4",
            "finish-link:8:4:4",
        ]
    );
}

#[test]
fn explicit_source_path_manifest_artifact_store_uses_keyed_artifacts() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-path-artifact-store-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create temp artifact-store dir");
    let first_path = root.join("first.lani");
    let second_path = root.join("second.lani");
    let third_path = root.join("third.lani");
    let fourth_path = root.join("fourth.lani");
    std::fs::write(&first_path, b"aaaa").expect("write first source");
    std::fs::write(&second_path, b"bbbb").expect("write second source");
    std::fs::write(&third_path, b"cccc").expect("write third source");
    std::fs::write(&fourth_path, b"dddd").expect("write fourth source");

    let manifest = load_explicit_source_libraries_path_manifest(vec![
        ExplicitSourceLibraryPaths {
            library_id: 7,
            paths: vec![first_path, second_path],
            dependency_library_ids: Vec::new(),
        },
        ExplicitSourceLibraryPaths {
            library_id: 8,
            paths: vec![third_path, fourth_path],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect("load path manifest");
    let mut executor = RecordingSourcePackPathHandleExecutor::default();
    let mut store = RecordingSourcePackArtifactStore::default();
    let result = manifest
        .execute_build_plan_with_artifact_store(
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 8,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 2,
                max_source_bytes_per_batch: 8,
                max_source_files_per_batch: 2,
            },
            &mut executor,
            &mut store,
        )
        .expect("execute artifact-store path build plan");
    std::fs::remove_dir_all(&root).expect("remove temp artifact-store dir");

    assert_eq!(result.linked_output_key, "linked-output/job-8/src-0-4");
    assert_eq!(store.interfaces, BTreeMap::new());
    assert_eq!(store.objects, BTreeMap::new());
    assert_eq!(
        store.outputs,
        BTreeMap::from([(
            "linked-output/job-8/src-0-4".to_string(),
            TestLinkedOutput {
                interface_count: 4,
                object_count: 4,
                object_libraries: vec![7, 7, 8, 8],
            },
        )])
    );
    assert_eq!(
        executor.events,
        vec![
            "frontend:7:1:[]",
            "frontend:7:1:[]",
            "frontend:8:1:[]",
            "frontend:8:1:[]",
            "codegen:7:0..1:4:[7]",
            "codegen:7:1..2:4:[7]",
            "codegen:8:2..3:4:[8]",
            "codegen:8:3..4:4:[8]",
            "begin-link:8",
            "link-interfaces:0:2",
            "link-interfaces:1:2",
            "link-batch:0:2",
            "link-batch:1:2",
            "finish-link:8:4:4",
        ]
    );
    assert_eq!(
        store.events,
        vec![
            "store-interface:library-interface/lib-7/job-0/src-0-1",
            "store-interface:library-interface/lib-7/job-1/src-1-2",
            "store-interface:library-interface/lib-8/job-2/src-2-3",
            "store-interface:library-interface/lib-8/job-3/src-3-4",
            "load-interface:library-interface/lib-7/job-0/src-0-1",
            "load-interface:library-interface/lib-7/job-1/src-1-2",
            "store-object:codegen-object/lib-7/job-4/src-0-1",
            "load-interface:library-interface/lib-7/job-1/src-1-2",
            "load-interface:library-interface/lib-7/job-0/src-0-1",
            "store-object:codegen-object/lib-7/job-5/src-1-2",
            "load-interface:library-interface/lib-8/job-2/src-2-3",
            "load-interface:library-interface/lib-8/job-3/src-3-4",
            "store-object:codegen-object/lib-8/job-6/src-2-3",
            "load-interface:library-interface/lib-8/job-3/src-3-4",
            "load-interface:library-interface/lib-8/job-2/src-2-3",
            "store-object:codegen-object/lib-8/job-7/src-3-4",
            "load-interface:library-interface/lib-7/job-0/src-0-1",
            "load-interface:library-interface/lib-7/job-1/src-1-2",
            "load-interface:library-interface/lib-8/job-2/src-2-3",
            "load-interface:library-interface/lib-8/job-3/src-3-4",
            "load-object:codegen-object/lib-7/job-4/src-0-1",
            "load-object:codegen-object/lib-7/job-5/src-1-2",
            "load-object:codegen-object/lib-8/job-6/src-2-3",
            "load-object:codegen-object/lib-8/job-7/src-3-4",
            "store-output:linked-output/job-8/src-0-4",
            "release-interface:library-interface/lib-7/job-0/src-0-1",
            "release-interface:library-interface/lib-7/job-1/src-1-2",
            "release-interface:library-interface/lib-8/job-2/src-2-3",
            "release-interface:library-interface/lib-8/job-3/src-3-4",
            "release-object:codegen-object/lib-7/job-4/src-0-1",
            "release-object:codegen-object/lib-7/job-5/src-1-2",
            "release-object:codegen-object/lib-8/job-6/src-2-3",
            "release-object:codegen-object/lib-8/job-7/src-3-4",
        ]
    );
}

#[test]
fn source_pack_build_artifact_manifest_contract_rejects_corrupt_artifact_ref() {
    let mut manifest = source_pack_contract_test_manifest();
    validate_source_pack_path_build_manifest_versions(&manifest)
        .expect("test manifest is initially valid");

    manifest.artifacts.job_artifacts.jobs[0].outputs[0]
        .key
        .push_str("-stale");

    let err = validate_source_pack_path_build_manifest_versions(&manifest)
        .expect_err("corrupt artifact ref should fail validation");
    assert!(
        err.to_string().contains("artifact ref"),
        "unexpected error: {err}"
    );
}

#[test]
fn source_pack_build_artifact_manifest_contract_rejects_stale_batch_dependencies() {
    let mut manifest = source_pack_contract_test_manifest();
    validate_source_pack_path_build_manifest_versions(&manifest)
        .expect("test manifest is initially valid");
    let dependent_batch = manifest
        .artifacts
        .batch_dependencies
        .batches
        .iter_mut()
        .find(|batch| !batch.dependency_batch_indices.is_empty())
        .expect("manifest has a dependent batch");
    dependent_batch.dependency_batch_indices.clear();

    let err = validate_source_pack_path_build_manifest_versions(&manifest)
        .expect_err("stale batch dependencies should fail validation");
    assert!(
        err.to_string().contains("batch dependency mismatch"),
        "unexpected error: {err}"
    );
}

#[test]
fn source_pack_filesystem_artifact_manifest_load_rejects_corrupt_contract() {
    let manifest = source_pack_contract_test_manifest();
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-corrupt-artifact-manifest-load-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    store
        .store_path_build_manifest(&manifest)
        .expect("store valid path build manifest");

    let mut corrupt = manifest;
    corrupt.artifacts.job_artifacts.jobs[0].outputs[0]
        .key
        .push_str("-stale");
    let bytes = serde_json::to_vec_pretty(&corrupt).expect("serialize corrupt path build manifest");
    std::fs::write(store.build_manifest_path(), bytes).expect("overwrite corrupt manifest");

    let err = store
        .load_path_build_manifest()
        .expect_err("load should reject corrupt manifest contract");
    assert!(
        err.to_string()
            .contains("invalid source-pack artifact manifest"),
        "unexpected error: {err}"
    );
    std::fs::remove_dir_all(&root).expect("remove corrupt manifest test dir");
}

#[test]
fn source_pack_filesystem_store_path_build_manifest_honors_custom_artifact_shard_limits() {
    let manifest = source_pack_contract_test_manifest();
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-store-path-build-manifest-custom-shards-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let shard_limits = SourcePackBuildShardLimits {
        max_batches_per_shard: 1,
        max_jobs_per_shard: 1,
        max_artifacts_per_shard: 4,
    };

    store
        .store_path_build_manifest_with_shard_limits(&manifest, shard_limits)
        .expect("store path build manifest with custom shard limits");

    let shard_index = store
        .load_build_artifact_shard_index()
        .expect("load custom shard index");
    assert_eq!(shard_index.limits, shard_limits.normalized());
    assert!(shard_index.shard_count() > manifest.artifacts.job_batches.batch_count());
    let first_shard = store
        .load_build_artifact_shard_for_target(SourcePackArtifactTarget::Generic, 0)
        .expect("load first custom artifact shard");
    assert_eq!(first_shard.limits, shard_limits.normalized());
    let stored_manifest = store
        .load_path_build_manifest()
        .expect("load compact stored path build manifest");
    assert!(stored_manifest.source_files.is_empty());
    assert!(stored_manifest.library_dependencies.is_empty());

    std::fs::remove_dir_all(&root).expect("remove custom manifest shard dir");
}

#[test]
fn source_pack_build_job_batch_pages_reject_unbounded_inline_jobs() {
    let target = SourcePackArtifactTarget::Wasm;
    let oversized_jobs =
        (0..=SOURCE_PACK_BUILD_JOB_BATCH_INLINE_JOB_DEFAULT_RECORD_CAP).collect::<Vec<_>>();
    let page = SourcePackBuildJobBatchPage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_PAGE_VERSION,
        target,
        batch_index: 0,
        batch: SourcePackJobBatch {
            batch_index: 0,
            wave_index: 0,
            job_indices: oversized_jobs,
            source_bytes: 1,
            source_file_count: 1,
            source_lines: 1,
            oversized: false,
        },
        dependency: SourcePackJobBatchDependency {
            batch_index: 0,
            dependency_batch_count: 0,
            dependency_page_count: 0,
            dependency_range_count: 0,
            dependency_range_page_count: 0,
            dependency_range_batch_count: 0,
            dependency_batch_indices: Vec::new(),
            dependency_batch_ranges: Vec::new(),
        },
    };

    assert!(
        validate_source_pack_build_job_batch_page(&page, target, Some(0))
            .expect_err("oversized job-batch inline jobs should be rejected")
            .to_string()
            .contains("record cap")
    );
}

#[test]
fn source_pack_build_job_batch_page_spills_forward_dependencies_to_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-job-batch-dependency-page-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let dependency_batch_indices =
        (0..=SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE).collect::<Vec<_>>();
    let batch_index = dependency_batch_indices.len();
    let page = SourcePackBuildJobBatchPage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_PAGE_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        batch_index,
        batch: SourcePackJobBatch {
            batch_index,
            wave_index: 3,
            job_indices: vec![batch_index],
            source_bytes: 1,
            source_file_count: 1,
            source_lines: 1,
            oversized: false,
        },
        dependency: SourcePackJobBatchDependency {
            batch_index,
            dependency_batch_count: 0,
            dependency_page_count: 0,
            dependency_range_count: 0,
            dependency_range_page_count: 0,
            dependency_range_batch_count: 0,
            dependency_batch_indices: dependency_batch_indices.clone(),
            dependency_batch_ranges: Vec::new(),
        },
    };

    store
        .store_build_job_batch_page(&page)
        .expect("store job-batch page with spilled dependencies");
    let loaded = store
        .load_build_job_batch_page_for_target(SourcePackArtifactTarget::Wasm, batch_index)
        .expect("load compact job-batch page");
    assert!(loaded.dependency.dependency_batch_indices.is_empty());
    assert_eq!(
        loaded.dependency.dependency_batch_count,
        dependency_batch_indices.len()
    );
    assert_eq!(loaded.dependency.dependency_page_count, 2);

    let first_dependency_page = store
        .load_build_job_batch_dependency_page_for_target(
            SourcePackArtifactTarget::Wasm,
            batch_index,
            0,
        )
        .expect("load first dependency page");
    assert_eq!(
        first_dependency_page.dependency_count,
        SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE
    );
    assert_eq!(
        first_dependency_page.dependency_batch_indices,
        dependency_batch_indices[..SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE]
    );
    let second_dependency_page = store
        .load_build_job_batch_dependency_page_for_target(
            SourcePackArtifactTarget::Wasm,
            batch_index,
            1,
        )
        .expect("load second dependency page");
    assert_eq!(
        second_dependency_page.dependency_batch_indices,
        vec![SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE]
    );

    let mut visited = Vec::new();
    source_pack_for_each_stored_job_batch_dependency_index(
        &store,
        SourcePackArtifactTarget::Wasm,
        &loaded.dependency,
        |dependency_batch_index| {
            visited.push(dependency_batch_index);
            Ok(())
        },
    )
    .expect("stream stored job-batch dependencies");
    assert_eq!(visited, dependency_batch_indices);
    std::fs::remove_dir_all(&root).expect("remove job-batch dependency page test dir");
}

#[test]
fn source_pack_build_job_batch_page_spills_dependency_ranges_to_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-job-batch-dependency-range-page-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let dependency_batch_ranges = (0
        ..=SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE)
        .map(|range_index| SourcePackJobBatchDependencyRange {
            first_batch_index: range_index * 2,
            batch_count: 1,
        })
        .collect::<Vec<_>>();
    let batch_index = dependency_batch_ranges
        .last()
        .expect("dependency range")
        .first_batch_index
        + 1;
    let page = SourcePackBuildJobBatchPage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_PAGE_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        batch_index,
        batch: SourcePackJobBatch {
            batch_index,
            wave_index: 3,
            job_indices: vec![batch_index],
            source_bytes: 1,
            source_file_count: 1,
            source_lines: 1,
            oversized: false,
        },
        dependency: SourcePackJobBatchDependency {
            batch_index,
            dependency_batch_count: 0,
            dependency_page_count: 0,
            dependency_range_count: 0,
            dependency_range_page_count: 0,
            dependency_range_batch_count: 0,
            dependency_batch_indices: Vec::new(),
            dependency_batch_ranges: dependency_batch_ranges.clone(),
        },
    };

    store
        .store_build_job_batch_page(&page)
        .expect("store job-batch page with spilled dependency ranges");
    let loaded = store
        .load_build_job_batch_page_for_target(SourcePackArtifactTarget::Wasm, batch_index)
        .expect("load compact job-batch page");
    assert!(loaded.dependency.dependency_batch_ranges.is_empty());
    assert_eq!(
        loaded.dependency.dependency_range_count,
        dependency_batch_ranges.len()
    );
    assert_eq!(loaded.dependency.dependency_range_page_count, 2);
    assert_eq!(
        loaded.dependency.dependency_range_batch_count,
        dependency_batch_ranges.len()
    );

    let first_range_page = store
        .load_build_job_batch_dependency_range_page_for_target(
            SourcePackArtifactTarget::Wasm,
            batch_index,
            0,
        )
        .expect("load first dependency range page");
    assert_eq!(
        first_range_page.range_count,
        SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE
    );
    assert_eq!(
        first_range_page.dependency_batch_ranges,
        dependency_batch_ranges[..SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE]
    );
    let second_range_page = store
        .load_build_job_batch_dependency_range_page_for_target(
            SourcePackArtifactTarget::Wasm,
            batch_index,
            1,
        )
        .expect("load second dependency range page");
    assert_eq!(
        second_range_page.dependency_batch_ranges,
        vec![SourcePackJobBatchDependencyRange {
            first_batch_index: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE * 2,
            batch_count: 1,
        }]
    );

    let mut visited = Vec::new();
    source_pack_for_each_stored_job_batch_dependency_index(
        &store,
        SourcePackArtifactTarget::Wasm,
        &loaded.dependency,
        |dependency_batch_index| {
            visited.push(dependency_batch_index);
            Ok(())
        },
    )
    .expect("stream stored job-batch dependency ranges");
    assert_eq!(
        visited,
        dependency_batch_ranges
            .iter()
            .map(|range| range.first_batch_index)
            .collect::<Vec<_>>()
    );
    std::fs::remove_dir_all(&root).expect("remove job-batch dependency range page test dir");
}

#[test]
fn source_pack_build_job_batch_page_rejects_oversized_retained_dependency_records() {
    let target = SourcePackArtifactTarget::Wasm;
    let dependency_batch_indices =
        (0..=SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE).collect::<Vec<_>>();
    let batch_index = dependency_batch_indices.len();
    let page = SourcePackBuildJobBatchPage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_PAGE_VERSION,
        target,
        batch_index,
        batch: SourcePackJobBatch {
            batch_index,
            wave_index: 3,
            job_indices: vec![batch_index],
            source_bytes: 1,
            source_file_count: 1,
            source_lines: 1,
            oversized: false,
        },
        dependency: SourcePackJobBatchDependency {
            batch_index,
            dependency_batch_count: 0,
            dependency_page_count: 0,
            dependency_range_count: 0,
            dependency_range_page_count: 0,
            dependency_range_batch_count: 0,
            dependency_batch_indices,
            dependency_batch_ranges: Vec::new(),
        },
    };
    let err = validate_source_pack_build_job_batch_page(&page, target, Some(batch_index))
        .expect_err("retained dependency records over the page cap should fail");
    assert!(
        format!("{err:?}").contains("inline dependency records"),
        "unexpected validation error: {err:?}"
    );

    let dependency_batch_ranges = (0
        ..=SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE)
        .map(|range_index| SourcePackJobBatchDependencyRange {
            first_batch_index: range_index,
            batch_count: 1,
        })
        .collect::<Vec<_>>();
    let mut range_page = page;
    range_page.batch_index = dependency_batch_ranges.len();
    range_page.batch.batch_index = range_page.batch_index;
    range_page.batch.job_indices = vec![range_page.batch_index];
    range_page.dependency.batch_index = range_page.batch_index;
    range_page.dependency.dependency_batch_indices.clear();
    range_page.dependency.dependency_batch_ranges = dependency_batch_ranges;
    let err = validate_source_pack_build_job_batch_page(
        &range_page,
        target,
        Some(range_page.batch_index),
    )
    .expect_err("retained dependency ranges over the page cap should fail");
    assert!(
        format!("{err:?}").contains("inline dependency range records"),
        "unexpected validation error: {err:?}"
    );
}

#[test]
fn source_pack_execution_shard_store_spills_inline_batch_edges_to_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-execution-shard-edge-page-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let dependency_batch_indices =
        (0..=SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE).collect::<Vec<_>>();
    let dependency_batch_ranges = (0
        ..=SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE)
        .map(|range_index| SourcePackJobBatchDependencyRange {
            first_batch_index: dependency_batch_indices.len() + range_index,
            batch_count: 1,
        })
        .collect::<Vec<_>>();
    let batch_index = dependency_batch_indices.len() + dependency_batch_ranges.len();
    let dependent_batch_indices = vec![batch_index + 1, batch_index + 2];
    let batch_count = batch_index + 3;
    let artifact_ref = SourcePackArtifactRef {
        artifact_index: 0,
        key: "wasm/library-interface/job-0/src-0-1".to_string(),
        producing_job_index: 0,
        kind: SourcePackArtifactKind::LibraryInterface,
    };
    let execution_shard = SourcePackBuildArtifactExecutionShard {
        version: SOURCE_PACK_BUILD_ARTIFACT_EXECUTION_SHARD_VERSION,
        target,
        shard: SourcePackBuildArtifactShard {
            version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
            target,
            limits: SourcePackBuildShardLimits {
                max_batches_per_shard: 1,
                max_jobs_per_shard: 1,
                max_artifacts_per_shard: 1,
            },
            shard_index: 0,
            kind: SourcePackBuildArtifactShardKind::JobBatches,
            batch_indices: vec![batch_index],
            job_indices: vec![0],
            input_artifact_indices: Vec::new(),
            input_artifact_ranges: Vec::new(),
            output_artifact_indices: vec![0],
            source_bytes: 1,
            source_file_count: 1,
            source_lines: 1,
            oversized: false,
        },
        source_files: Vec::new(),
        job_batches: vec![SourcePackJobBatch {
            batch_index,
            wave_index: 0,
            job_indices: vec![0],
            source_bytes: 1,
            source_file_count: 1,
            source_lines: 1,
            oversized: false,
        }],
        batch_dependencies: vec![SourcePackJobBatchDependency {
            batch_index,
            dependency_batch_count: 0,
            dependency_page_count: 0,
            dependency_range_count: 0,
            dependency_range_page_count: 0,
            dependency_range_batch_count: 0,
            dependency_batch_indices: dependency_batch_indices.clone(),
            dependency_batch_ranges: dependency_batch_ranges.clone(),
        }],
        batch_dependents: vec![SourcePackJobBatchDependents {
            batch_index,
            dependent_batch_indices: dependent_batch_indices.clone(),
        }],
        jobs: vec![SourcePackJob {
            job_index: 0,
            phase: SourcePackJobPhase::LibraryFrontend,
            phase_unit_index: 0,
            library_job_index: None,
            library_id: 1,
            first_source_index: 0,
            source_file_count: 1,
            source_bytes: 1,
            source_lines: 1,
            oversized_source_file: false,
            dependency_job_indices: Vec::new(),
        }],
        job_artifacts: vec![SourcePackJobArtifactManifest {
            job_index: 0,
            phase: SourcePackJobPhase::LibraryFrontend,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interface_artifact_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_object_artifact_ranges: Vec::new(),
            input_objects: Vec::new(),
            outputs: vec![artifact_ref.clone()],
        }],
        artifact_refs: vec![artifact_ref],
        link_interface_batches: Vec::new(),
        link_object_batches: Vec::new(),
    };

    store
        .store_build_artifact_execution_shard_record(&execution_shard)
        .expect("store execution shard with spilled batch edges");
    let loaded = store
        .load_build_artifact_execution_shard_for_target(target, 0)
        .expect("load compact execution shard");
    let loaded_dependency = source_pack_execution_shard_batch_dependency(&loaded, batch_index)
        .expect("load compact batch dependency from execution shard");
    assert!(loaded_dependency.dependency_batch_indices.is_empty());
    assert_eq!(
        loaded_dependency.dependency_batch_count,
        dependency_batch_indices.len()
    );
    assert_eq!(loaded_dependency.dependency_page_count, 2);
    assert!(loaded_dependency.dependency_batch_ranges.is_empty());
    assert_eq!(
        loaded_dependency.dependency_range_count,
        dependency_batch_ranges.len()
    );
    assert_eq!(loaded_dependency.dependency_range_page_count, 2);
    assert_eq!(
        loaded_dependency.dependency_range_batch_count,
        dependency_batch_ranges.len()
    );
    let mut visited_dependencies = Vec::new();
    source_pack_for_each_stored_job_batch_dependency_index(
        &store,
        target,
        loaded_dependency,
        |dependency_batch_index| {
            visited_dependencies.push(dependency_batch_index);
            Ok(())
        },
    )
    .expect("stream compact execution-shard batch dependencies");
    let mut expected_dependencies = dependency_batch_indices;
    expected_dependencies.extend(
        dependency_batch_ranges
            .iter()
            .map(|range| range.first_batch_index),
    );
    assert_eq!(visited_dependencies, expected_dependencies);

    let loaded_dependents = source_pack_execution_shard_batch_dependents(&loaded, batch_index)
        .expect("load compact batch dependents from execution shard");
    assert!(loaded_dependents.dependent_batch_indices.is_empty());
    let stored_dependents = store
        .load_build_job_batch_dependents_page_for_target(target, batch_index, batch_count)
        .expect("load spilled execution-shard batch dependents");
    assert!(
        stored_dependents
            .dependents
            .dependent_batch_indices
            .is_empty()
    );
    assert_eq!(
        stored_dependents.dependent_batch_count,
        dependent_batch_indices.len()
    );
    let dependent_page = store
        .load_build_job_batch_dependent_batch_page_for_target(target, batch_index, 0, batch_count)
        .expect("load execution-shard dependent-batch page");
    assert_eq!(
        dependent_page.dependent_batch_indices,
        dependent_batch_indices
    );

    std::fs::remove_dir_all(&root).expect("remove execution-shard edge page test dir");
}

#[test]
fn source_pack_artifact_shards_reject_unbounded_record_arrays() {
    let target = SourcePackArtifactTarget::Wasm;
    let limits = SourcePackBuildShardLimits {
        max_batches_per_shard: 2,
        max_jobs_per_shard: 2,
        max_artifacts_per_shard: 2,
    };
    let capped_shard = SourcePackBuildArtifactShard {
        version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
        target,
        limits,
        shard_index: 0,
        kind: SourcePackBuildArtifactShardKind::JobBatches,
        batch_indices: vec![0, 1],
        job_indices: vec![0, 1],
        input_artifact_indices: vec![0],
        input_artifact_ranges: Vec::new(),
        output_artifact_indices: vec![1],
        source_bytes: 1,
        source_file_count: 1,
        source_lines: 1,
        oversized: false,
    };
    validate_source_pack_build_artifact_shard(&capped_shard, target)
        .expect("artifact shard at record cap should validate");

    let mut oversized_batches = capped_shard.clone();
    oversized_batches.batch_indices = vec![0, 1, 2];
    oversized_batches.oversized = true;
    assert!(
        validate_source_pack_build_artifact_shard(&oversized_batches, target)
            .expect_err("oversized artifact shard batch records should be rejected")
            .to_string()
            .contains("record cap")
    );

    let mut oversized_jobs = capped_shard.clone();
    oversized_jobs.job_indices = vec![0, 1, 2];
    oversized_jobs.oversized = true;
    assert!(
        validate_source_pack_build_artifact_shard(&oversized_jobs, target)
            .expect_err("oversized artifact shard job records should be rejected")
            .to_string()
            .contains("record cap")
    );

    let mut oversized_artifacts = capped_shard.clone();
    oversized_artifacts.output_artifact_indices = vec![1, 2];
    oversized_artifacts.oversized = true;
    assert!(
        validate_source_pack_build_artifact_shard(&oversized_artifacts, target)
            .expect_err("oversized artifact shard artifact records should be rejected")
            .to_string()
            .contains("record cap")
    );
}

#[test]
fn source_pack_execution_shards_reject_unbounded_record_arrays() {
    let target = SourcePackArtifactTarget::Wasm;
    let output_ref = SourcePackArtifactRef {
        artifact_index: 0,
        key: "wasm/library-interface/job-0/src-0-1".to_string(),
        producing_job_index: 0,
        kind: SourcePackArtifactKind::LibraryInterface,
    };
    let valid = SourcePackBuildArtifactExecutionShard {
        version: SOURCE_PACK_BUILD_ARTIFACT_EXECUTION_SHARD_VERSION,
        target,
        shard: SourcePackBuildArtifactShard {
            version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
            target,
            limits: SourcePackBuildShardLimits {
                max_batches_per_shard: 1,
                max_jobs_per_shard: 1,
                max_artifacts_per_shard: 1,
            },
            shard_index: 0,
            kind: SourcePackBuildArtifactShardKind::JobBatches,
            batch_indices: vec![0],
            job_indices: vec![0],
            input_artifact_indices: Vec::new(),
            input_artifact_ranges: Vec::new(),
            output_artifact_indices: vec![0],
            source_bytes: 1,
            source_file_count: 1,
            source_lines: 1,
            oversized: false,
        },
        source_files: Vec::new(),
        job_batches: vec![SourcePackJobBatch {
            batch_index: 0,
            wave_index: 0,
            job_indices: vec![0],
            source_bytes: 1,
            source_file_count: 1,
            source_lines: 1,
            oversized: false,
        }],
        batch_dependencies: vec![SourcePackJobBatchDependency {
            batch_index: 0,
            dependency_batch_count: 0,
            dependency_page_count: 0,
            dependency_range_count: 0,
            dependency_range_page_count: 0,
            dependency_range_batch_count: 0,
            dependency_batch_indices: Vec::new(),
            dependency_batch_ranges: Vec::new(),
        }],
        batch_dependents: vec![SourcePackJobBatchDependents {
            batch_index: 0,
            dependent_batch_indices: Vec::new(),
        }],
        jobs: vec![SourcePackJob {
            job_index: 0,
            phase: SourcePackJobPhase::LibraryFrontend,
            phase_unit_index: 0,
            library_job_index: None,
            library_id: 1,
            first_source_index: 0,
            source_file_count: 1,
            source_bytes: 1,
            source_lines: 1,
            oversized_source_file: false,
            dependency_job_indices: Vec::new(),
        }],
        job_artifacts: vec![SourcePackJobArtifactManifest {
            job_index: 0,
            phase: SourcePackJobPhase::LibraryFrontend,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interface_artifact_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_object_artifact_ranges: Vec::new(),
            input_objects: Vec::new(),
            outputs: vec![output_ref.clone()],
        }],
        artifact_refs: vec![output_ref.clone()],
        link_interface_batches: Vec::new(),
        link_object_batches: Vec::new(),
    };
    validate_source_pack_build_artifact_execution_shard(&valid, target)
        .expect("execution shard at record caps should validate");

    let assert_oversized = |label: &str, shard: SourcePackBuildArtifactExecutionShard| {
        assert!(
            validate_source_pack_build_artifact_execution_shard(&shard, target)
                .expect_err(&format!("oversized {label} records should be rejected"))
                .to_string()
                .contains("record cap"),
            "oversized {label} records should report the record cap"
        );
    };

    let mut shard = valid.clone();
    shard.job_batches.push(shard.job_batches[0].clone());
    assert_oversized("job-batch", shard);

    let mut shard = valid.clone();
    shard
        .batch_dependencies
        .push(shard.batch_dependencies[0].clone());
    assert_oversized("batch-dependency", shard);

    let mut shard = valid.clone();
    shard
        .batch_dependents
        .push(shard.batch_dependents[0].clone());
    assert_oversized("batch-dependent", shard);

    let dependency_batch_indices =
        (0..=SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE).collect::<Vec<_>>();
    let batch_index = dependency_batch_indices.len();
    let mut shard = valid.clone();
    shard.shard.batch_indices = vec![batch_index];
    shard.job_batches[0].batch_index = batch_index;
    shard.batch_dependencies[0].batch_index = batch_index;
    shard.batch_dependencies[0].dependency_batch_indices = dependency_batch_indices;
    shard.batch_dependents[0].batch_index = batch_index;
    assert_oversized("inline batch-dependency", shard);

    let dependency_batch_ranges = (0
        ..=SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE)
        .map(|range_index| SourcePackJobBatchDependencyRange {
            first_batch_index: range_index,
            batch_count: 1,
        })
        .collect::<Vec<_>>();
    let batch_index = dependency_batch_ranges.len();
    let mut shard = valid.clone();
    shard.shard.batch_indices = vec![batch_index];
    shard.job_batches[0].batch_index = batch_index;
    shard.batch_dependencies[0].batch_index = batch_index;
    shard.batch_dependencies[0].dependency_batch_ranges = dependency_batch_ranges;
    shard.batch_dependents[0].batch_index = batch_index;
    assert_oversized("inline batch-dependency range", shard);

    let dependent_batch_indices =
        (1..=SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE + 1).collect::<Vec<_>>();
    let mut shard = valid.clone();
    shard.batch_dependents[0].dependent_batch_indices = dependent_batch_indices;
    assert_oversized("inline batch-dependent", shard);

    let mut shard = valid.clone();
    shard.jobs.push(shard.jobs[0].clone());
    assert_oversized("job", shard);

    let mut shard = valid.clone();
    shard.job_artifacts.push(shard.job_artifacts[0].clone());
    assert_oversized("job-artifact", shard);

    let mut shard = valid.clone();
    shard.artifact_refs.push(SourcePackArtifactRef {
        artifact_index: 1,
        key: "wasm/library-interface/job-1/src-1-1".to_string(),
        producing_job_index: 1,
        kind: SourcePackArtifactKind::LibraryInterface,
    });
    assert_oversized("artifact-ref", shard);

    let mut shard = valid.clone();
    shard.source_files = vec![
        SourcePackShardSourceFile {
            source_index: 0,
            file: ExplicitSourcePathFile {
                library_id: 1,
                path: PathBuf::from("source-0.lani"),
                byte_len: 1,
                modified_unix_nanos: None,
                line_count: Some(1),
            },
        },
        SourcePackShardSourceFile {
            source_index: 1,
            file: ExplicitSourcePathFile {
                library_id: 1,
                path: PathBuf::from("source-1.lani"),
                byte_len: 1,
                modified_unix_nanos: None,
                line_count: Some(1),
            },
        },
    ];
    assert!(
        validate_source_pack_build_artifact_execution_shard(&shard, target)
            .expect_err("execution shard source-file side records must fit shard metadata")
            .to_string()
            .contains("shard records 1 source files")
    );

    let mut link_shard = valid;
    link_shard.shard.kind = SourcePackBuildArtifactShardKind::LinkInterfaceBatches;
    link_shard.shard.job_indices.clear();
    link_shard.shard.output_artifact_indices.clear();
    link_shard.job_batches.clear();
    link_shard.batch_dependencies.clear();
    link_shard.batch_dependents.clear();
    link_shard.jobs.clear();
    link_shard.job_artifacts.clear();
    link_shard.artifact_refs.clear();
    link_shard.link_interface_batches = vec![
        SourcePackLinkInterfaceBatch {
            batch_index: 0,
            input_interface_artifact_indices: Vec::new(),
            source_bytes: 0,
            source_file_count: 0,
            source_lines: 0,
        },
        SourcePackLinkInterfaceBatch {
            batch_index: 1,
            input_interface_artifact_indices: Vec::new(),
            source_bytes: 0,
            source_file_count: 0,
            source_lines: 0,
        },
    ];
    assert_oversized("link-interface-batch", link_shard);
}

#[test]
fn source_pack_execution_shard_store_spills_inline_job_artifact_interfaces_to_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-execution-shard-job-interface-page-test-{}-{suffix}",
        std::process::id()
    ));
    let mut store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let input_interfaces = (0..=SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE)
            .map(|artifact_index| SourcePackArtifactRef {
                artifact_index,
                key: format!("wasm/library-interface/lib-{artifact_index}/job-{artifact_index}/src-{artifact_index}-1"),
                producing_job_index: artifact_index,
                kind: SourcePackArtifactKind::LibraryInterface,
            })
            .collect::<Vec<_>>();
    let job_index = input_interfaces.len() + 1;
    let output_artifact_index = job_index;
    let output_ref = SourcePackArtifactRef {
        artifact_index: output_artifact_index,
        key: format!("wasm/codegen-object/lib-7/job-{job_index}/src-0-1"),
        producing_job_index: job_index,
        kind: SourcePackArtifactKind::CodegenObject,
    };
    let execution_shard = SourcePackBuildArtifactExecutionShard {
        version: SOURCE_PACK_BUILD_ARTIFACT_EXECUTION_SHARD_VERSION,
        target,
        shard: SourcePackBuildArtifactShard {
            version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
            target,
            limits: SourcePackBuildShardLimits {
                max_batches_per_shard: 1,
                max_jobs_per_shard: 1,
                max_artifacts_per_shard: input_interfaces.len() + 1,
            },
            shard_index: 0,
            kind: SourcePackBuildArtifactShardKind::JobBatches,
            batch_indices: vec![0],
            job_indices: vec![job_index],
            input_artifact_indices: input_interfaces
                .iter()
                .map(|artifact| artifact.artifact_index)
                .collect(),
            input_artifact_ranges: Vec::new(),
            output_artifact_indices: vec![output_artifact_index],
            source_bytes: 1,
            source_file_count: 1,
            source_lines: 1,
            oversized: false,
        },
        source_files: Vec::new(),
        job_batches: vec![SourcePackJobBatch {
            batch_index: 0,
            wave_index: 0,
            job_indices: vec![job_index],
            source_bytes: 1,
            source_file_count: 1,
            source_lines: 1,
            oversized: false,
        }],
        batch_dependencies: vec![SourcePackJobBatchDependency {
            batch_index: 0,
            dependency_batch_count: 0,
            dependency_page_count: 0,
            dependency_range_count: 0,
            dependency_range_page_count: 0,
            dependency_range_batch_count: 0,
            dependency_batch_indices: Vec::new(),
            dependency_batch_ranges: Vec::new(),
        }],
        batch_dependents: vec![SourcePackJobBatchDependents {
            batch_index: 0,
            dependent_batch_indices: Vec::new(),
        }],
        jobs: vec![SourcePackJob {
            job_index,
            phase: SourcePackJobPhase::Codegen,
            phase_unit_index: 0,
            library_job_index: Some(0),
            library_id: 7,
            first_source_index: 0,
            source_file_count: 1,
            source_bytes: 1,
            source_lines: 1,
            oversized_source_file: false,
            dependency_job_indices: Vec::new(),
        }],
        job_artifacts: vec![SourcePackJobArtifactManifest {
            job_index,
            phase: SourcePackJobPhase::Codegen,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interface_artifact_ranges: Vec::new(),
            input_interfaces: input_interfaces.clone(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_object_artifact_ranges: Vec::new(),
            input_objects: Vec::new(),
            outputs: vec![output_ref.clone()],
        }],
        artifact_refs: input_interfaces
            .iter()
            .cloned()
            .chain(std::iter::once(output_ref))
            .collect(),
        link_interface_batches: Vec::new(),
        link_object_batches: Vec::new(),
    };

    store
        .store_build_artifact_execution_shard_record(&execution_shard)
        .expect("store execution shard with spilled job artifact interfaces");
    let loaded = store
        .load_build_artifact_execution_shard_for_target(target, 0)
        .expect("load compact execution shard");
    let job_manifest = source_pack_execution_shard_job_artifact(&loaded, job_index)
        .expect("load compact job artifact manifest");
    assert!(job_manifest.input_interfaces.is_empty());
    assert_eq!(job_manifest.input_interface_count, input_interfaces.len());
    assert_eq!(job_manifest.input_interface_page_count, 2);
    let legacy_err =
        source_pack_execution_shard_job_input_interface_refs(&loaded, &store, target, job_manifest)
            .expect_err("legacy input loader must reject paged interface refs");
    assert!(
        legacy_err.to_string().contains("paged execution"),
        "unexpected legacy input loader error: {legacy_err}"
    );

    for artifact in &input_interfaces {
        store
            .store_library_interface(artifact, vec![artifact.artifact_index as u8])
            .expect("store streamed interface artifact");
    }
    let mut streamed_batch_sizes = Vec::new();
    let streamed_count = source_pack_for_each_execution_shard_job_input_interface_batch(
        &mut store,
        target,
        job_manifest,
        None,
        |interfaces| {
            streamed_batch_sizes.push(interfaces.len());
            Ok(())
        },
    )
    .expect("stream paged job artifact interface refs");
    assert_eq!(streamed_count, input_interfaces.len());
    assert_eq!(
        streamed_batch_sizes,
        vec![
            SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE,
            1
        ]
    );

    std::fs::remove_dir_all(&root).expect("remove execution-shard job interface page test dir");
}

#[test]
fn source_pack_execution_shard_store_prunes_ranged_artifact_refs_and_streams_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-execution-shard-ranged-artifact-ref-test-{}-{suffix}",
        std::process::id()
    ));
    let mut store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let dependency_refs = (0..2)
        .map(|artifact_index| SourcePackArtifactRef {
            artifact_index,
            key: format!("wasm/library-interface/job-{artifact_index}/src-{artifact_index}"),
            producing_job_index: artifact_index,
            kind: SourcePackArtifactKind::LibraryInterface,
        })
        .collect::<Vec<_>>();
    let owner_ref = SourcePackArtifactRef {
        artifact_index: 2,
        key: "wasm/library-interface/job-2/src-2".to_string(),
        producing_job_index: 2,
        kind: SourcePackArtifactKind::LibraryInterface,
    };
    let output_ref = SourcePackArtifactRef {
        artifact_index: 3,
        key: "wasm/codegen-object/job-3/src-3".to_string(),
        producing_job_index: 3,
        kind: SourcePackArtifactKind::CodegenObject,
    };
    let artifact_count = 5;
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count,
            interface_artifact_count: 3,
            object_artifact_count: 1,
            final_output_artifact_index: artifact_count - 1,
            final_output_key: "wasm/linked-output/job-4/src-4".to_string(),
            total_source_file_count: artifact_count,
            total_source_byte_count: artifact_count,
            total_source_line_count: artifact_count,
        })
        .expect("store artifact-ref index for ranged execution shard");
    for artifact in dependency_refs.iter().chain(std::iter::once(&owner_ref)) {
        store
            .store_build_artifact_ref_page(
                &SourcePackBuildArtifactRefPage {
                    version: SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION,
                    target,
                    artifact_index: artifact.artifact_index,
                    artifact_ref: artifact.clone(),
                    source_bytes: 1,
                    source_file_count: 1,
                    source_lines: 1,
                },
                artifact_count,
            )
            .expect("store artifact-ref page for ranged interface input");
        store
            .store_library_interface(artifact, vec![artifact.artifact_index as u8])
            .expect("store interface artifact for ranged execution shard");
    }
    let input_range = SourcePackArtifactIndexRange {
        first_artifact_index: 0,
        artifact_count: dependency_refs.len(),
    };
    let execution_shard = SourcePackBuildArtifactExecutionShard {
        version: SOURCE_PACK_BUILD_ARTIFACT_EXECUTION_SHARD_VERSION,
        target,
        shard: SourcePackBuildArtifactShard {
            version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
            target,
            limits: SourcePackBuildShardLimits {
                max_batches_per_shard: 1,
                max_jobs_per_shard: 1,
                max_artifacts_per_shard: 3,
            },
            shard_index: 0,
            kind: SourcePackBuildArtifactShardKind::JobBatches,
            batch_indices: vec![0],
            job_indices: vec![output_ref.producing_job_index],
            input_artifact_indices: vec![owner_ref.artifact_index],
            input_artifact_ranges: vec![input_range.clone()],
            output_artifact_indices: vec![output_ref.artifact_index],
            source_bytes: 1,
            source_file_count: 1,
            source_lines: 1,
            oversized: false,
        },
        source_files: Vec::new(),
        job_batches: vec![SourcePackJobBatch {
            batch_index: 0,
            wave_index: 0,
            job_indices: vec![output_ref.producing_job_index],
            source_bytes: 1,
            source_file_count: 1,
            source_lines: 1,
            oversized: false,
        }],
        batch_dependencies: vec![SourcePackJobBatchDependency {
            batch_index: 0,
            dependency_batch_count: 0,
            dependency_page_count: 0,
            dependency_range_count: 0,
            dependency_range_page_count: 0,
            dependency_range_batch_count: 0,
            dependency_batch_indices: Vec::new(),
            dependency_batch_ranges: Vec::new(),
        }],
        batch_dependents: vec![SourcePackJobBatchDependents {
            batch_index: 0,
            dependent_batch_indices: Vec::new(),
        }],
        jobs: vec![SourcePackJob {
            job_index: output_ref.producing_job_index,
            phase: SourcePackJobPhase::Codegen,
            phase_unit_index: 0,
            library_job_index: Some(owner_ref.producing_job_index),
            library_id: 7,
            first_source_index: 0,
            source_file_count: 1,
            source_bytes: 1,
            source_lines: 1,
            oversized_source_file: false,
            dependency_job_indices: Vec::new(),
        }],
        job_artifacts: vec![SourcePackJobArtifactManifest {
            job_index: output_ref.producing_job_index,
            phase: SourcePackJobPhase::Codegen,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interface_artifact_ranges: vec![input_range.clone()],
            input_interfaces: vec![owner_ref.clone()],
            input_object_count: 0,
            input_object_page_count: 0,
            input_object_artifact_ranges: Vec::new(),
            input_objects: Vec::new(),
            outputs: vec![output_ref.clone()],
        }],
        artifact_refs: dependency_refs
            .iter()
            .cloned()
            .chain(std::iter::once(owner_ref.clone()))
            .chain(std::iter::once(output_ref.clone()))
            .collect(),
        link_interface_batches: Vec::new(),
        link_object_batches: Vec::new(),
    };

    store
        .store_build_artifact_execution_shard_record(&execution_shard)
        .expect("store compact execution shard with ranged artifact refs");
    let loaded = store
        .load_build_artifact_execution_shard_for_target(target, 0)
        .expect("load compact ranged execution shard");
    assert_eq!(
        loaded.shard.input_artifact_ranges,
        vec![input_range.clone()]
    );
    assert_eq!(
        loaded
            .artifact_refs
            .iter()
            .map(|artifact| artifact.artifact_index)
            .collect::<Vec<_>>(),
        vec![owner_ref.artifact_index, output_ref.artifact_index]
    );

    let job_manifest =
        source_pack_execution_shard_job_artifact(&loaded, output_ref.producing_job_index)
            .expect("load compact ranged job artifact manifest");
    assert!(job_manifest.input_interfaces.is_empty());
    assert_eq!(job_manifest.input_interface_page_count, 1);
    assert_eq!(job_manifest.input_interface_count, 3);
    assert_eq!(
        job_manifest.input_interface_artifact_ranges,
        vec![input_range.clone()]
    );
    let legacy_err =
        source_pack_execution_shard_job_input_interface_refs(&loaded, &store, target, job_manifest)
            .expect_err("legacy input loader must reject ranged interface refs");
    assert!(
        legacy_err.to_string().contains("paged execution"),
        "unexpected legacy input loader error: {legacy_err}"
    );
    let ranged_ref = source_pack_execution_shard_job_input_interface_ref(
        &store,
        target,
        job_manifest,
        dependency_refs[1].producing_job_index,
    )
    .expect("load ranged interface artifact ref from artifact-ref pages");
    assert_eq!(ranged_ref, dependency_refs[1]);

    let mut streamed_inputs = Vec::new();
    let streamed_count = source_pack_for_each_execution_shard_job_input_interface_batch(
        &mut store,
        target,
        job_manifest,
        None,
        |interfaces| {
            streamed_inputs.extend(interfaces.iter().map(|interface| interface[0] as usize));
            Ok(())
        },
    )
    .expect("stream ranged interface artifact refs from pages");
    assert_eq!(streamed_count, 3);
    assert_eq!(
        streamed_inputs,
        vec![
            owner_ref.artifact_index,
            dependency_refs[0].artifact_index,
            dependency_refs[1].artifact_index,
        ]
    );

    std::fs::remove_dir_all(&root).expect("remove ranged artifact-ref test dir");
}

#[test]
fn source_pack_execution_shard_input_interface_ref_uses_direct_artifact_range_lookup() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-direct-ranged-interface-ref-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let artifact_count = 4;
    let wanted_ref = SourcePackArtifactRef {
        artifact_index: 1,
        key: "wasm/library-interface/job-1/src-1".to_string(),
        producing_job_index: 1,
        kind: SourcePackArtifactKind::LibraryInterface,
    };
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count,
            interface_artifact_count: 3,
            object_artifact_count: 0,
            final_output_artifact_index: artifact_count - 1,
            final_output_key: "wasm/linked-output/job-3/src-3".to_string(),
            total_source_file_count: artifact_count,
            total_source_byte_count: artifact_count,
            total_source_line_count: artifact_count,
        })
        .expect("store artifact-ref index for direct ranged lookup");
    store
        .store_build_artifact_ref_page(
            &SourcePackBuildArtifactRefPage {
                version: SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION,
                target,
                artifact_index: wanted_ref.artifact_index,
                artifact_ref: wanted_ref.clone(),
                source_bytes: 1,
                source_file_count: 1,
                source_lines: 1,
            },
            artifact_count,
        )
        .expect("store only requested ranged artifact-ref page");

    let job_manifest = SourcePackJobArtifactManifest {
        job_index: 9,
        phase: SourcePackJobPhase::Codegen,
        input_interface_count: 3,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interface_artifact_ranges: vec![SourcePackArtifactIndexRange {
            first_artifact_index: 0,
            artifact_count: 3,
        }],
        input_interfaces: Vec::new(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_object_artifact_ranges: Vec::new(),
        input_objects: Vec::new(),
        outputs: Vec::new(),
    };

    let loaded_ref = source_pack_execution_shard_job_input_interface_ref(
        &store,
        target,
        &job_manifest,
        wanted_ref.producing_job_index,
    )
    .expect("direct ranged lookup should not scan unrelated artifact-ref pages");
    assert_eq!(loaded_ref, wanted_ref);

    std::fs::remove_dir_all(&root).expect("remove direct ranged lookup test dir");
}

#[test]
fn source_pack_job_batch_dependents_pages_are_sparse_for_batches_without_dependents() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-job-batch-sparse-dependents-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let batch_count = 4usize;
    store
        .store_build_job_batch_page_index(&SourcePackBuildJobBatchPageIndex {
            version: SOURCE_PACK_BUILD_JOB_BATCH_PAGE_INDEX_VERSION,
            target,
            batch_count,
            scheduled_job_count: batch_count,
            dependency_edge_count: 2,
        })
        .expect("store sparse dependents batch index");
    let dependencies = vec![
        SourcePackJobBatchDependency {
            batch_index: 1,
            dependency_batch_count: 0,
            dependency_page_count: 0,
            dependency_range_count: 0,
            dependency_range_page_count: 0,
            dependency_range_batch_count: 0,
            dependency_batch_indices: vec![0],
            dependency_batch_ranges: Vec::new(),
        },
        SourcePackJobBatchDependency {
            batch_index: 2,
            dependency_batch_count: 0,
            dependency_page_count: 0,
            dependency_range_count: 0,
            dependency_range_page_count: 0,
            dependency_range_batch_count: 0,
            dependency_batch_indices: vec![0],
            dependency_batch_ranges: Vec::new(),
        },
    ];
    store_source_pack_job_batch_dependents_pages_from_manifest_dependencies(
        &store,
        target,
        &dependencies,
        batch_count,
    )
    .expect("store sparse reverse dependents");

    assert!(
        store
            .build_job_batch_dependents_page_path_for_target(target, 0)
            .is_file(),
        "batches with real dependents should store a count page"
    );
    assert!(
        !store
            .build_job_batch_dependents_page_path_for_target(target, 3)
            .exists(),
        "batches without reverse dependents should not get empty placeholder pages"
    );
    let empty = store
        .load_build_job_batch_dependents_page_for_target(target, 3, batch_count)
        .expect("load sparse empty dependents page");
    assert_eq!(empty.batch_index, 3);
    assert_eq!(empty.dependent_batch_count, 0);
    assert_eq!(empty.dependent_page_count, 0);
    assert!(empty.dependents.dependent_batch_indices.is_empty());

    let mut visited = Vec::new();
    source_pack_for_each_job_batch_dependent_index(
        &store,
        target,
        3,
        batch_count,
        |dependent_batch_index| {
            visited.push(dependent_batch_index);
            Ok(())
        },
    )
    .expect("iterate sparse empty dependents");
    assert!(visited.is_empty());
    source_pack_for_each_job_batch_dependent_index(
        &store,
        target,
        0,
        batch_count,
        |dependent_batch_index| {
            visited.push(dependent_batch_index);
            Ok(())
        },
    )
    .expect("iterate stored dependents");
    assert_eq!(visited, vec![1, 2]);

    std::fs::remove_dir_all(&root).expect("remove sparse dependents test dir");
}

#[test]
fn source_pack_job_batch_dependents_from_stored_pages_chunk_resumes() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-job-batch-dependents-chunk-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let batch_count = 4usize;
    store
        .store_build_job_batch_page_index(&SourcePackBuildJobBatchPageIndex {
            version: SOURCE_PACK_BUILD_JOB_BATCH_PAGE_INDEX_VERSION,
            target,
            batch_count,
            scheduled_job_count: batch_count,
            dependency_edge_count: 4,
        })
        .expect("store chunked dependents batch index");
    for (batch_index, dependencies) in [
        (0usize, Vec::<usize>::new()),
        (1usize, vec![0]),
        (2usize, vec![0]),
        (3usize, vec![1, 2]),
    ] {
        store
            .store_build_job_batch_page(&SourcePackBuildJobBatchPage {
                version: SOURCE_PACK_BUILD_JOB_BATCH_PAGE_VERSION,
                target,
                batch_index,
                batch: SourcePackJobBatch {
                    batch_index,
                    wave_index: batch_index,
                    job_indices: vec![batch_index],
                    source_bytes: 1,
                    source_file_count: 1,
                    source_lines: 1,
                    oversized: false,
                },
                dependency: SourcePackJobBatchDependency {
                    batch_index,
                    dependency_batch_count: 0,
                    dependency_page_count: 0,
                    dependency_range_count: 0,
                    dependency_range_page_count: 0,
                    dependency_range_batch_count: 0,
                    dependency_batch_indices: dependencies,
                    dependency_batch_ranges: Vec::new(),
                },
            })
            .expect("store chunked dependents job-batch page");
    }

    let first = prepare_source_pack_filesystem_job_batch_dependents_from_batches_chunk_for_target(
        &root, target, 3,
    )
    .expect("prepare first job-batch dependents chunk");
    assert!(!first.complete);
    assert_eq!(first.batch_count, 4);
    assert_eq!(first.next_batch_index, 3);
    assert_eq!(first.new_batch_count, 3);
    assert_eq!(first.dependent_edge_count, 2);
    assert!(
        store
            .build_job_batch_dependents_prepare_progress_path_for_target(target)
            .is_file()
    );
    let batch_zero_dependents = store
        .load_build_job_batch_dependents_page_for_target(target, 0, batch_count)
        .expect("load chunked batch zero dependents");
    assert_eq!(batch_zero_dependents.dependent_batch_count, 2);
    let batch_zero_dependent_page = store
        .load_build_job_batch_dependent_batch_page_for_target(target, 0, 0, batch_count)
        .expect("load chunked batch zero dependent-batch page");
    assert_eq!(
        batch_zero_dependent_page.dependent_batch_indices,
        vec![1, 2]
    );
    assert!(
        !store
            .build_job_batch_dependents_page_path_for_target(target, 1)
            .is_file(),
        "later reverse dependents should not be created before their dependent batch is processed"
    );

    let final_chunk =
        prepare_source_pack_filesystem_job_batch_dependents_from_batches_chunk_for_target(
            &root, target, 1,
        )
        .expect("prepare final job-batch dependents chunk");
    assert!(final_chunk.complete);
    assert_eq!(final_chunk.next_batch_index, 4);
    assert_eq!(final_chunk.new_batch_count, 1);
    assert_eq!(final_chunk.dependent_edge_count, 4);
    for (batch_index, expected) in [(1usize, vec![3]), (2usize, vec![3])] {
        let dependents = store
            .load_build_job_batch_dependents_page_for_target(target, batch_index, batch_count)
            .expect("load final chunked dependents page");
        assert_eq!(dependents.dependent_batch_count, expected.len());
        let dependent_page = store
            .load_build_job_batch_dependent_batch_page_for_target(
                target,
                batch_index,
                0,
                batch_count,
            )
            .expect("load final chunked dependent-batch page");
        assert_eq!(dependent_page.dependent_batch_indices, expected);
    }
    assert!(
        !store
            .build_job_batch_dependents_page_path_for_target(target, 3)
            .exists(),
        "batches without reverse dependents should remain sparse"
    );

    let already_complete =
        prepare_source_pack_filesystem_job_batch_dependents_from_batches_chunk_for_target(
            &root, target, 1,
        )
        .expect("completed job-batch dependents chunk should reuse progress");
    assert!(already_complete.complete);
    assert_eq!(already_complete.new_batch_count, 0);
    assert_eq!(already_complete.next_batch_index, 4);

    std::fs::remove_dir_all(&root).expect("remove chunked dependents test dir");
}

#[test]
fn source_pack_job_batch_dependents_page_spills_inline_dependents_to_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-job-batch-dependent-page-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let dependent_batch_indices =
        (1..=SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE + 1).collect::<Vec<_>>();
    let batch_count = dependent_batch_indices.len() + 1;
    let page = SourcePackBuildJobBatchDependentsPage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PAGE_VERSION,
        target,
        batch_count,
        batch_index: 0,
        dependents: SourcePackJobBatchDependents {
            batch_index: 0,
            dependent_batch_indices: dependent_batch_indices.clone(),
        },
        dependent_batch_count: 0,
        dependent_page_count: 0,
    };

    store
        .store_build_job_batch_dependents_page(&page, batch_count)
        .expect("store job-batch dependents page");

    let stored_page = store
        .load_build_job_batch_dependents_page_for_target(target, 0, batch_count)
        .expect("load compact job-batch dependents page");
    assert!(stored_page.dependents.dependent_batch_indices.is_empty());
    assert_eq!(
        stored_page.dependent_batch_count,
        dependent_batch_indices.len()
    );
    assert_eq!(stored_page.dependent_page_count, 2);
    let first_dependent_page = store
        .load_build_job_batch_dependent_batch_page_for_target(target, 0, 0, batch_count)
        .expect("load first dependent-batch page");
    assert_eq!(
        first_dependent_page.dependent_batch_indices,
        dependent_batch_indices[..SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE]
            .to_vec()
    );
    let second_dependent_page = store
        .load_build_job_batch_dependent_batch_page_for_target(target, 0, 1, batch_count)
        .expect("load second dependent-batch page");
    assert_eq!(
        second_dependent_page.dependent_batch_indices,
        vec![SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE + 1]
    );

    std::fs::remove_dir_all(&root).expect("remove dependent page test dir");
}

#[test]
fn source_pack_job_batch_dependents_page_rejects_oversized_retained_dependents() {
    let target = SourcePackArtifactTarget::Wasm;
    let dependent_batch_indices =
        (1..=SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE + 1).collect::<Vec<_>>();
    let batch_count = dependent_batch_indices.len() + 1;
    let page = SourcePackBuildJobBatchDependentsPage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PAGE_VERSION,
        target,
        batch_count,
        batch_index: 0,
        dependents: SourcePackJobBatchDependents {
            batch_index: 0,
            dependent_batch_indices,
        },
        dependent_batch_count: 0,
        dependent_page_count: 0,
    };

    let err =
        validate_source_pack_build_job_batch_dependents_page(&page, target, batch_count, Some(0))
            .expect_err("retained dependents over the page cap should fail");
    assert!(
        format!("{err:?}").contains("inline dependent records"),
        "unexpected validation error: {err:?}"
    );
}

#[test]
fn source_pack_stored_job_batch_dependency_writes_dependency_pages_directly() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-stored-job-batch-dependency-page-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let dependency_count = SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE + 1;
    let first_codegen_job_index = dependency_count;
    let second_codegen_job_index = dependency_count + 1;
    let batch_index = dependency_count;
    let schedule_index = SourcePackLibraryScheduleIndex {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        partition_count: dependency_count,
        frontend_job_count: dependency_count,
        codegen_job_count: 2,
        link_job_index: second_codegen_job_index + 1,
        job_count: second_codegen_job_index + 2,
    };
    let codegen_job = |job_index| SourcePackJob {
        job_index,
        phase: SourcePackJobPhase::Codegen,
        phase_unit_index: 0,
        library_job_index: Some(0),
        library_id: 0,
        first_source_index: 0,
        source_file_count: 1,
        source_bytes: 1,
        source_lines: 0,
        oversized_source_file: false,
        dependency_job_indices: (0..dependency_count).collect(),
    };
    let first_codegen_job = codegen_job(first_codegen_job_index);
    let second_codegen_job = codegen_job(second_codegen_job_index);
    store_schedule_job_page_with_dependencies(
        &store,
        schedule_index.target,
        schedule_index.job_count,
        &first_codegen_job,
        |writer| {
            for dependency_job_index in 0..dependency_count {
                writer.push(dependency_job_index)?;
            }
            Ok(())
        },
    )
    .expect("store first paged schedule-job dependencies");
    store_schedule_job_page_with_dependencies(
        &store,
        schedule_index.target,
        schedule_index.job_count,
        &second_codegen_job,
        |writer| {
            for dependency_job_index in 0..dependency_count {
                writer.push(dependency_job_index)?;
            }
            Ok(())
        },
    )
    .expect("store second paged schedule-job dependencies");
    for dependency_job_index in 0..dependency_count {
        store
            .store_build_job_batch_job_locator_page(
                &SourcePackBuildJobBatchJobLocatorPage {
                    version: SOURCE_PACK_BUILD_JOB_BATCH_JOB_LOCATOR_PAGE_VERSION,
                    target: SourcePackArtifactTarget::Wasm,
                    job_index: dependency_job_index,
                    batch_index: dependency_job_index,
                },
                schedule_index.job_count,
            )
            .expect("store dependency job batch locator");
    }
    store_source_pack_stored_job_batch_page(
        &store,
        &schedule_index,
        vec![first_codegen_job, second_codegen_job],
        batch_index,
        0,
        1,
        1,
        1,
        false,
    )
    .expect("store job-batch page from paged schedule dependencies");

    let loaded = store
        .load_build_job_batch_page_for_target(SourcePackArtifactTarget::Wasm, batch_index)
        .expect("load compact stored job-batch page");
    assert!(loaded.dependency.dependency_batch_indices.is_empty());
    assert_eq!(loaded.dependency.dependency_batch_count, dependency_count);
    assert_eq!(loaded.dependency.dependency_page_count, 2);
    let first_page = store
        .load_build_job_batch_dependency_page_for_target(
            SourcePackArtifactTarget::Wasm,
            batch_index,
            0,
        )
        .expect("load first stored dependency page");
    assert_eq!(
        first_page.dependency_batch_indices,
        (0..SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE).collect::<Vec<_>>()
    );
    let second_page = store
        .load_build_job_batch_dependency_page_for_target(
            SourcePackArtifactTarget::Wasm,
            batch_index,
            1,
        )
        .expect("load second stored dependency page");
    assert_eq!(
        second_page.dependency_batch_indices,
        vec![SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE]
    );

    let mut visited = Vec::new();
    source_pack_for_each_stored_job_batch_dependency_index(
        &store,
        SourcePackArtifactTarget::Wasm,
        &loaded.dependency,
        |dependency_batch_index| {
            visited.push(dependency_batch_index);
            Ok(())
        },
    )
    .expect("stream direct dependency pages");
    assert_eq!(visited, (0..dependency_count).collect::<Vec<_>>());

    std::fs::remove_dir_all(&root).expect("remove stored dependency page test dir");
}

#[test]
fn source_pack_job_batch_execution_shards_keep_dependency_artifacts_paged_per_job() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-job-batch-shard-paged-input-artifacts-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let core_path = source_root.join("core.lani");
    let util_path = source_root.join("util.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&util_path, b"util").expect("write util source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_for_target(
            vec![
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 10,
                    source_file_count: 1,
                    paths: std::iter::once(core_path),
                    dependency_library_count: 0,
                    dependency_library_ids: Vec::<u32>::new().into_iter(),
                },
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 20,
                    source_file_count: 1,
                    paths: std::iter::once(util_path),
                    dependency_library_count: 0,
                    dependency_library_ids: Vec::<u32>::new().into_iter(),
                },
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 30,
                    source_file_count: 1,
                    paths: std::iter::once(app_path),
                    dependency_library_count: 2,
                    dependency_library_ids: vec![10, 20].into_iter(),
                },
            ],
            &artifact_root,
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 1,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
            SourcePackArtifactTarget::Wasm,
        )
        .expect("prepare dependent libraries artifact build");

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store
        .load_library_schedule_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load schedule index");
    let core_locator = store
        .load_library_frontend_job_locator_page_for_target(SourcePackArtifactTarget::Wasm, 10)
        .expect("load core frontend locator");
    let util_locator = store
        .load_library_frontend_job_locator_page_for_target(SourcePackArtifactTarget::Wasm, 20)
        .expect("load util frontend locator");
    let app_locator = store
        .load_library_frontend_job_locator_page_for_target(SourcePackArtifactTarget::Wasm, 30)
        .expect("load app frontend locator");
    let app_schedule_page = store
        .load_library_schedule_page_for_target(
            SourcePackArtifactTarget::Wasm,
            app_locator.partition_index,
        )
        .expect("load app schedule page");
    let app_codegen_job_index = app_schedule_page.first_codegen_job_index;
    let batch_locator = store
        .load_build_job_batch_job_locator_page_for_target(
            SourcePackArtifactTarget::Wasm,
            app_codegen_job_index,
            schedule_index.job_count,
        )
        .expect("load app codegen batch locator");
    let shard_locator = store
        .load_build_batch_shard_locator_for_target(
            SourcePackArtifactTarget::Wasm,
            batch_locator.batch_index,
        )
        .expect("load app codegen shard locator");
    let execution_shard = store
        .load_build_artifact_execution_shard_for_target(
            SourcePackArtifactTarget::Wasm,
            shard_locator.shard_index,
        )
        .expect("load app codegen execution shard");

    assert_eq!(
        execution_shard.shard.kind,
        SourcePackBuildArtifactShardKind::JobBatches
    );
    assert!(
        execution_shard.shard.input_artifact_indices.is_empty(),
        "job-batch shards should not embed per-job dependency artifact refs"
    );
    let mut shard_artifact_ref_indices = execution_shard
        .artifact_refs
        .iter()
        .map(|artifact| artifact.artifact_index)
        .collect::<Vec<_>>();
    shard_artifact_ref_indices.sort_unstable();
    let mut output_artifact_indices = execution_shard.shard.output_artifact_indices.clone();
    output_artifact_indices.sort_unstable();
    assert_eq!(
        shard_artifact_ref_indices, output_artifact_indices,
        "job-batch execution shards should keep only output artifact refs"
    );
    let job_manifest =
        source_pack_execution_shard_job_artifact(&execution_shard, app_codegen_job_index)
            .expect("load app codegen job manifest");
    assert_eq!(job_manifest.input_interface_count, 3);
    assert_eq!(job_manifest.input_interface_page_count, 1);
    assert_eq!(job_manifest.input_interface_ranges.len(), 2);
    assert!(job_manifest.input_interfaces.is_empty());

    let input_page = store
        .load_job_artifact_input_interface_page_for_target(
            SourcePackArtifactTarget::Wasm,
            app_codegen_job_index,
            0,
        )
        .expect("load app codegen input interface page");
    let mut input_producers = input_page
        .input_interfaces
        .iter()
        .map(|artifact| artifact.producing_job_index)
        .collect::<Vec<_>>();
    input_producers.sort_unstable();
    assert_eq!(input_producers, vec![app_locator.frontend_job_index]);
    let range_producers = job_manifest
        .input_interface_ranges
        .iter()
        .flat_map(|range| range.iter().expect("input interface range"))
        .collect::<Vec<_>>();
    assert_eq!(
        range_producers,
        vec![
            core_locator.frontend_job_index,
            util_locator.frontend_job_index
        ]
    );

    std::fs::remove_dir_all(&root).expect("remove temp job-batch shard paged input artifacts dir");
}

#[test]
fn source_pack_filesystem_prepare_honors_custom_artifact_shard_limits() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-custom-artifact-shard-limits-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let core_path = source_root.join("core.lani");
    let util_path = source_root.join("util.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&util_path, b"util").expect("write util source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let shard_limits = SourcePackBuildShardLimits {
        max_batches_per_shard: 1,
        max_jobs_per_shard: 1,
        max_artifacts_per_shard: 1,
    };
    let prepared = prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target(
            vec![
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 10,
                    source_file_count: 1,
                    paths: std::iter::once(core_path),
                    dependency_library_count: 0,
                    dependency_library_ids: Vec::<u32>::new().into_iter(),
                },
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 20,
                    source_file_count: 1,
                    paths: std::iter::once(util_path),
                    dependency_library_count: 1,
                    dependency_library_ids: vec![10].into_iter(),
                },
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 30,
                    source_file_count: 1,
                    paths: std::iter::once(app_path),
                    dependency_library_count: 2,
                    dependency_library_ids: vec![10, 20].into_iter(),
                },
            ],
            &artifact_root,
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 1,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
            shard_limits,
            SourcePackArtifactTarget::Wasm,
        )
        .expect("prepare filesystem artifact build with custom shard limits");

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let shard_index = store
        .load_build_artifact_shard_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared artifact shard index");
    assert_eq!(shard_index.limits, shard_limits.normalized());
    assert_eq!(shard_index.shard_count(), prepared.artifact_shard_count);
    assert!(
        shard_index.shard_count() > prepared.batch_count,
        "link input shards should be split separately from one-batch job shards"
    );

    for shard_index in 0..prepared.artifact_shard_count {
        let shard = store
            .load_build_artifact_shard_for_target(SourcePackArtifactTarget::Wasm, shard_index)
            .expect("load prepared artifact shard");
        assert_eq!(shard.limits, shard_limits.normalized());
        assert!(
            shard.batch_count() <= 1 || shard.oversized,
            "custom shard limits should bound batch fan-in per persisted shard"
        );
        assert!(
            shard.job_count() <= 1 || shard.oversized,
            "custom shard limits should bound job fan-in per persisted shard"
        );
        assert!(
            shard.artifact_count() <= 1 || shard.oversized,
            "custom shard limits should bound artifact fan-in per persisted shard"
        );
    }

    std::fs::remove_dir_all(&root).expect("remove custom artifact shard limits test dir");
}

#[test]
fn source_pack_artifact_shards_from_stored_batches_chunk_resumes() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-artifact-shards-chunk-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let core_path = source_root.join("core.lani");
    let util_path = source_root.join("util.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&util_path, b"util").expect("write util source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
        vec![
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 10,
                source_file_count: 1,
                paths: std::iter::once(core_path.as_path()),
                dependency_library_count: 0,
                dependency_library_ids: Vec::<u32>::new().into_iter(),
            },
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 20,
                source_file_count: 1,
                paths: std::iter::once(util_path.as_path()),
                dependency_library_count: 1,
                dependency_library_ids: vec![10].into_iter(),
            },
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 30,
                source_file_count: 1,
                paths: std::iter::once(app_path.as_path()),
                dependency_library_count: 2,
                dependency_library_ids: vec![10, 20].into_iter(),
            },
        ],
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare persisted metadata for artifact-shard chunks");
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 1,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };
    let schedule_pages = prepare_library_schedule_pages_from_metadata(
        &store,
        SourcePackArtifactTarget::Wasm,
        limits,
    )
    .expect("prepare schedule pages for artifact-shard chunks");
    store_source_pack_build_artifact_ref_pages_from_stored_schedule_pages(
        &store,
        &schedule_pages.library_schedule_index,
    )
    .expect("prepare artifact refs for artifact-shard chunks");
    let job_batches = store_source_pack_build_job_batch_pages_from_stored_schedule_pages(
        &store,
        &schedule_pages.library_schedule_index,
        batch_limits,
    )
    .expect("prepare job batches for artifact-shard chunks");
    store_source_pack_build_link_batch_pages_from_stored_artifact_ref_pages(
        &store,
        SourcePackArtifactTarget::Wasm,
        &schedule_pages.library_schedule_index,
        &store
            .load_build_artifact_ref_index_for_target(SourcePackArtifactTarget::Wasm)
            .expect("load artifact-ref index for link batches"),
        batch_limits,
    )
    .expect("prepare link batches for artifact-shard chunks");
    prepare_source_pack_filesystem_job_batch_dependents_from_batches_chunk_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        100,
    )
    .expect("prepare reverse dependents before artifact-shard chunks");

    let shard_limits = SourcePackBuildShardLimits {
        max_batches_per_shard: 1,
        max_jobs_per_shard: 1,
        max_artifacts_per_shard: 1,
    };
    let first = prepare_source_pack_filesystem_artifact_shards_from_batches_chunk_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        shard_limits,
        2,
    )
    .expect("prepare first artifact-shard chunk");
    assert!(!first.complete);
    assert_eq!(first.new_input_batch_count, 2);
    assert_eq!(first.new_shard_count, 1);
    assert_eq!(
        first.next_input_kind,
        Some(SourcePackBuildArtifactShardKind::JobBatches)
    );
    assert!(
        store
            .artifact_shard_prepare_progress_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );
    assert!(
        store
            .artifact_shard_path_for_target(SourcePackArtifactTarget::Wasm, 0)
            .is_file()
    );
    assert!(
        !store
            .artifact_shard_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );

    let mut saw_progress_directory_page = false;
    let mut saw_progress_directory_index_page = false;
    let mut saw_additional_shard = false;
    let mut final_chunk = None;
    for _ in 0..64 {
        let step = prepare_source_pack_filesystem_artifact_shards_from_batches_chunk_for_target(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            shard_limits,
            1,
        )
        .expect("resume artifact-shard chunk");
        if step.new_shard_count != 0 {
            saw_additional_shard = true;
        }
        if step.new_progress_directory_page_count != 0 {
            saw_progress_directory_page = true;
            assert!(
                !store
                    .artifact_shard_index_path_for_target(SourcePackArtifactTarget::Wasm)
                    .is_file(),
                "artifact-shard index should wait for progress directory-index pages"
            );
        }
        if step.new_progress_directory_index_page_count != 0 {
            saw_progress_directory_index_page = true;
        }
        if step.complete {
            final_chunk = Some(step);
            break;
        }
    }
    let final_chunk = final_chunk.expect("artifact-shard chunks should complete");
    assert!(final_chunk.complete);
    assert!(saw_additional_shard);
    assert_eq!(final_chunk.next_input_kind, None);
    assert!(final_chunk.artifact_shard_index_path.is_some());
    assert!(final_chunk.link_input_shard_index_path.is_some());
    assert!(saw_progress_directory_page);
    assert!(saw_progress_directory_index_page);
    assert_eq!(
        final_chunk.next_progress_directory_page_index,
        final_chunk.progress_directory_page_count
    );
    assert_eq!(
        final_chunk.next_progress_directory_index_page_index,
        final_chunk.progress_directory_index_page_count
    );
    assert!(
        store
            .build_progress_directory_page_path_for_target(SourcePackArtifactTarget::Wasm, 0)
            .is_file()
    );
    assert!(
        store
            .build_progress_directory_index_page_path_for_target(SourcePackArtifactTarget::Wasm, 0)
            .is_file()
    );
    let shard_index = store
        .load_build_artifact_shard_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load chunked artifact-shard index");
    assert_eq!(shard_index.limits, shard_limits.normalized());
    assert_eq!(shard_index.job_batch_count, job_batches.index.batch_count);
    assert_eq!(shard_index.shard_count, final_chunk.shard_count);
    assert!(shard_index.shard_count > shard_index.job_batch_count);
    let link_input_index = store
        .load_link_input_shard_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load chunked link-input shard index");
    assert!(link_input_index.link_interface_shard_range.is_some());
    assert!(link_input_index.link_object_shard_range.is_some());
    let progress_summary = store
        .load_build_progress_summary_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load chunked build progress summary");
    assert_eq!(
        progress_summary.job_batch_shard_count,
        final_chunk.job_batch_shard_count
    );
    assert!(progress_summary.ready_batch_count > 0);
    store
        .load_build_artifact_execution_shard_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load chunked execution shard");

    let already_complete =
        prepare_source_pack_filesystem_artifact_shards_from_batches_chunk_for_target(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            shard_limits,
            1,
        )
        .expect("completed artifact-shard chunk should reopen index");
    assert!(already_complete.complete);
    assert_eq!(already_complete.new_input_batch_count, 0);
    assert_eq!(already_complete.new_shard_count, 0);
    assert_eq!(already_complete.new_progress_directory_page_count, 0);
    assert_eq!(already_complete.new_progress_directory_index_page_count, 0);
    assert_eq!(
        already_complete.progress_directory_page_count,
        final_chunk.progress_directory_page_count
    );

    std::fs::remove_dir_all(&root).expect("remove artifact-shard chunk test dir");
}

#[test]
fn ordered_path_dependency_stream_execute_honors_custom_artifact_shard_limits() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-custom-artifact-shard-execute-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let core_path = source_root.join("core.lani");
    let util_path = source_root.join("util.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&util_path, b"util").expect("write util source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let shard_limits = SourcePackBuildShardLimits {
        max_batches_per_shard: 1,
        max_jobs_per_shard: 1,
        max_artifacts_per_shard: 1,
    };
    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let result = execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target(
            vec![
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 10,
                    source_file_count: 1,
                    paths: std::iter::once(core_path),
                    dependency_library_count: 0,
                    dependency_library_ids: Vec::<u32>::new().into_iter(),
                },
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 20,
                    source_file_count: 1,
                    paths: std::iter::once(util_path),
                    dependency_library_count: 1,
                    dependency_library_ids: vec![10].into_iter(),
                },
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 30,
                    source_file_count: 1,
                    paths: std::iter::once(app_path),
                    dependency_library_count: 2,
                    dependency_library_ids: vec![10, 20].into_iter(),
                },
            ],
            &artifact_root,
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 1,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
            shard_limits,
            SourcePackArtifactTarget::Wasm,
            &mut executor,
        )
        .expect("execute filesystem artifact build with custom shard limits");

    assert_eq!(result.linked_output_key, "wasm/linked-output/job-6/src-0-3");
    assert_eq!(
        std::fs::read(&result.linked_output_path).expect("read linked output"),
        b"linked:3:3"
    );
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let shard_index = store
        .load_build_artifact_shard_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load executed artifact shard index");
    assert_eq!(shard_index.limits, shard_limits.normalized());
    assert!(shard_index.shard_count() > 7);
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "finish-link:6:3:3"),
        "one-shot execution should still reach the final link job"
    );

    std::fs::remove_dir_all(&root).expect("remove custom artifact shard execute test dir");
}

#[test]
fn source_pack_artifact_worker_run_honors_zero_batch_limit() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-artifact-zero-worker-run-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    std::fs::write(&core_path, b"core").expect("write core source");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let run =
        execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_for_target(
            [ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            }],
            &artifact_root,
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 1,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
            SourcePackArtifactTarget::Wasm,
            "worker-zero",
            0,
            None,
            &mut executor,
        )
        .expect("zero-batch worker run should prepare and report progress");

    assert_eq!(run.worker_id, "worker-zero");
    assert_eq!(run.executed_batch_count, 0);
    assert_eq!(run.completed_batch_count, 0);
    assert_eq!(run.ready_batch_count, 1);
    assert!(!run.complete);
    assert_eq!(run.linked_output_key, None);
    assert!(executor.events.is_empty());

    let ready_zero = execute_source_pack_filesystem_artifact_manifest_ready_batches_for_target(
        &artifact_root,
        0,
        SourcePackArtifactTarget::Wasm,
        &mut executor,
    )
    .expect("zero ready-batch execution should report progress");
    assert_eq!(ready_zero.executed_batch_count, 0);
    assert_eq!(ready_zero.completed_batch_count, 0);
    assert_eq!(ready_zero.ready_batch_count, 1);
    assert!(!ready_zero.complete);
    assert!(executor.events.is_empty());

    std::fs::remove_dir_all(&root).expect("remove zero-batch worker run test dir");
}

#[test]
fn ordered_explicit_libraries_worker_run_executes_bounded_batches() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-ordered-libraries-worker-run-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let core_path = source_root.join("core.lani");
    let util_path = source_root.join("util.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&util_path, b"util").expect("write util source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let first =
        execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_for_target(
            [
                ExplicitSourceLibraryPaths {
                    library_id: 10,
                    paths: vec![core_path],
                    dependency_library_ids: Vec::new(),
                },
                ExplicitSourceLibraryPaths {
                    library_id: 20,
                    paths: vec![util_path],
                    dependency_library_ids: vec![10],
                },
                ExplicitSourceLibraryPaths {
                    library_id: 30,
                    paths: vec![app_path],
                    dependency_library_ids: vec![10, 20],
                },
            ],
            &artifact_root,
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 1,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
            SourcePackArtifactTarget::Wasm,
            "worker-a",
            2,
            None,
            &mut executor,
        )
        .expect("prepare and run bounded ordered library worker batches");

    assert_eq!(first.worker_id, "worker-a");
    assert_eq!(first.executed_batch_count, 2);
    assert_eq!(first.completed_batch_count, 2);
    assert!(!first.complete);
    assert_eq!(first.linked_output_key, None);
    assert_eq!(executor.events, vec!["frontend:10:1:0", "frontend:20:1:1"]);

    let resumed = execute_source_pack_filesystem_artifact_manifest_worker_run_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        "worker-b",
        16,
        None,
        &mut executor,
    )
    .expect("resume ordered library worker batches");

    assert_eq!(resumed.worker_id, "worker-b");
    assert_eq!(resumed.executed_batch_count, 5);
    assert!(resumed.complete);
    assert_eq!(
        resumed.linked_output_key.as_deref(),
        Some("wasm/linked-output/job-6/src-0-3")
    );
    assert_eq!(
        std::fs::read(
            resumed
                .linked_output_path
                .as_ref()
                .expect("resumed worker linked output path")
        )
        .expect("read resumed linked output"),
        b"linked:3:3"
    );
    assert_eq!(
        executor.events,
        vec![
            "frontend:10:1:0",
            "frontend:20:1:1",
            "frontend:30:1:2",
            "codegen:10:0..1:1:0",
            "codegen:20:1..2:1:1",
            "codegen:30:2..3:1:2",
            "begin-link:6",
            "link-interfaces:0:1",
            "link-interfaces:1:1",
            "link-interfaces:2:1",
            "link-objects:0:1",
            "link-objects:1:1",
            "link-objects:2:1",
            "finish-link:6:3:3",
        ]
    );

    std::fs::remove_dir_all(&root).expect("remove temp ordered library worker run dir");
}

#[test]
fn ordered_explicit_libraries_path_artifact_worker_run_executes_bounded_batches() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-ordered-libraries-path-artifact-worker-run-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    let executor_root = root.join("executor-artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let core_path = source_root.join("core.lani");
    let util_path = source_root.join("util.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&util_path, b"util").expect("write util source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let mut executor = RecordingSourcePackFileArtifactExecutor::new(executor_root);
    let first =
            execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_path_artifacts_for_target(
                [
                    ExplicitSourceLibraryPaths {
                        library_id: 10,
                        paths: vec![core_path],
                        dependency_library_ids: Vec::new(),
                    },
                    ExplicitSourceLibraryPaths {
                        library_id: 20,
                        paths: vec![util_path],
                        dependency_library_ids: vec![10],
                    },
                    ExplicitSourceLibraryPaths {
                        library_id: 30,
                        paths: vec![app_path],
                        dependency_library_ids: vec![10, 20],
                    },
                ],
                &artifact_root,
                CodegenUnitLimits {
                    max_source_bytes: 4,
                    max_source_files: 1,
                },
                SourcePackJobBatchLimits {
                    max_jobs_per_batch: 1,
                    max_source_bytes_per_batch: 4,
                    max_source_files_per_batch: 1,
                },
                SourcePackArtifactTarget::Wasm,
                "worker-a",
                2,
                None,
                &mut executor,
            )
            .expect("prepare and run bounded ordered library path-artifact worker batches");

    assert_eq!(first.worker_id, "worker-a");
    assert_eq!(first.executed_batch_count, 2);
    assert!(!first.complete);
    assert_eq!(first.linked_output_key, None);
    assert_eq!(executor.events, vec!["frontend:10:1:0", "frontend:20:1:1"]);

    let resumed =
        execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            "worker-b",
            16,
            None,
            &mut executor,
        )
        .expect("resume ordered library path-artifact worker batches");

    assert_eq!(resumed.worker_id, "worker-b");
    assert_eq!(resumed.executed_batch_count, 5);
    assert!(resumed.complete);
    assert_eq!(
        resumed.linked_output_key.as_deref(),
        Some("wasm/linked-output/job-6/src-0-3")
    );
    let linked_output_path = resumed
        .linked_output_path
        .as_ref()
        .expect("path-artifact worker linked output path");
    assert!(linked_output_path.starts_with(&artifact_root));
    assert_eq!(
        std::fs::read(linked_output_path).expect("read copied linked output"),
        b"linked:3:3"
    );
    assert_eq!(
        executor.events,
        vec![
            "frontend:10:1:0",
            "frontend:20:1:1",
            "frontend:30:1:2",
            "codegen:10:0..1:1:0",
            "codegen:20:1..2:1:1",
            "codegen:30:2..3:1:2",
            "begin-link:6",
            "link-interfaces:0:1",
            "link-interfaces:1:1",
            "link-interfaces:2:1",
            "link-objects:0:1",
            "link-objects:1:1",
            "link-objects:2:1",
            "finish-link:6:3:3",
        ]
    );

    std::fs::remove_dir_all(&root)
        .expect("remove temp ordered library path-artifact worker run dir");
}

#[test]
fn ordered_path_dependency_stream_worker_run_executes_bounded_batches() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-path-dependency-stream-worker-run-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let core_path = source_root.join("core.lani");
    let util_path = source_root.join("util.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&util_path, b"util").expect("write util source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let first = execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_for_target(
            vec![
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 10,
                    source_file_count: 1,
                    paths: std::iter::once(core_path),
                    dependency_library_count: 0,
                    dependency_library_ids: Vec::<u32>::new().into_iter(),
                },
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 20,
                    source_file_count: 1,
                    paths: std::iter::once(util_path),
                    dependency_library_count: 1,
                    dependency_library_ids: vec![10].into_iter(),
                },
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 30,
                    source_file_count: 1,
                    paths: std::iter::once(app_path),
                    dependency_library_count: 2,
                    dependency_library_ids: vec![10, 20].into_iter(),
                },
            ],
            &artifact_root,
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 1,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
            SourcePackArtifactTarget::Wasm,
            "worker-a",
            2,
            None,
            &mut executor,
        )
        .expect("prepare and run bounded ordered path+dependency stream worker batches");

    assert_eq!(first.worker_id, "worker-a");
    assert_eq!(first.executed_batch_count, 2);
    assert_eq!(first.completed_batch_count, 2);
    assert!(!first.complete);
    assert_eq!(first.linked_output_key, None);
    assert_eq!(executor.events, vec!["frontend:10:1:0", "frontend:20:1:1"]);

    let resumed = execute_source_pack_filesystem_artifact_manifest_worker_run_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        "worker-b",
        16,
        None,
        &mut executor,
    )
    .expect("resume ordered path+dependency stream worker batches");

    assert_eq!(resumed.worker_id, "worker-b");
    assert_eq!(resumed.executed_batch_count, 5);
    assert!(resumed.complete);
    assert_eq!(
        resumed.linked_output_key.as_deref(),
        Some("wasm/linked-output/job-6/src-0-3")
    );
    assert_eq!(
        std::fs::read(
            resumed
                .linked_output_path
                .as_ref()
                .expect("resumed worker linked output path")
        )
        .expect("read resumed linked output"),
        b"linked:3:3"
    );
    assert_eq!(
        executor.events,
        vec![
            "frontend:10:1:0",
            "frontend:20:1:1",
            "frontend:30:1:2",
            "codegen:10:0..1:1:0",
            "codegen:20:1..2:1:1",
            "codegen:30:2..3:1:2",
            "begin-link:6",
            "link-interfaces:0:1",
            "link-interfaces:1:1",
            "link-interfaces:2:1",
            "link-objects:0:1",
            "link-objects:1:1",
            "link-objects:2:1",
            "finish-link:6:3:3",
        ]
    );

    std::fs::remove_dir_all(&root)
        .expect("remove temp ordered path+dependency stream worker run dir");
}

#[test]
fn ordered_path_dependency_stream_path_artifact_worker_run_executes_bounded_batches() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-path-dependency-stream-path-artifact-worker-run-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    let executor_root = root.join("executor-artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let core_path = source_root.join("core.lani");
    let util_path = source_root.join("util.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&util_path, b"util").expect("write util source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let mut executor = RecordingSourcePackFileArtifactExecutor::new(executor_root);
    let first = execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_path_artifacts_for_target(
            vec![
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 10,
                    source_file_count: 1,
                    paths: std::iter::once(core_path),
                    dependency_library_count: 0,
                    dependency_library_ids: Vec::<u32>::new().into_iter(),
                },
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 20,
                    source_file_count: 1,
                    paths: std::iter::once(util_path),
                    dependency_library_count: 1,
                    dependency_library_ids: vec![10].into_iter(),
                },
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 30,
                    source_file_count: 1,
                    paths: std::iter::once(app_path),
                    dependency_library_count: 2,
                    dependency_library_ids: vec![10, 20].into_iter(),
                },
            ],
            &artifact_root,
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 1,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
            SourcePackArtifactTarget::Wasm,
            "worker-a",
            2,
            None,
            &mut executor,
        )
        .expect("prepare and run bounded ordered path+dependency stream path-artifact worker batches");

    assert_eq!(first.worker_id, "worker-a");
    assert_eq!(first.executed_batch_count, 2);
    assert_eq!(first.completed_batch_count, 2);
    assert!(!first.complete);
    assert_eq!(first.linked_output_key, None);
    assert_eq!(executor.events, vec!["frontend:10:1:0", "frontend:20:1:1"]);

    let resumed =
        execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            "worker-b",
            16,
            None,
            &mut executor,
        )
        .expect("resume ordered path+dependency stream path-artifact worker batches");

    assert_eq!(resumed.worker_id, "worker-b");
    assert_eq!(resumed.executed_batch_count, 5);
    assert!(resumed.complete);
    assert_eq!(
        resumed.linked_output_key.as_deref(),
        Some("wasm/linked-output/job-6/src-0-3")
    );
    let linked_output_path = resumed
        .linked_output_path
        .as_ref()
        .expect("path-artifact dependency stream linked output path");
    assert!(linked_output_path.starts_with(&artifact_root));
    assert_eq!(
        std::fs::read(linked_output_path).expect("read copied linked output"),
        b"linked:3:3"
    );
    assert_eq!(
        executor.events,
        vec![
            "frontend:10:1:0",
            "frontend:20:1:1",
            "frontend:30:1:2",
            "codegen:10:0..1:1:0",
            "codegen:20:1..2:1:1",
            "codegen:30:2..3:1:2",
            "begin-link:6",
            "link-interfaces:0:1",
            "link-interfaces:1:1",
            "link-interfaces:2:1",
            "link-objects:0:1",
            "link-objects:1:1",
            "link-objects:2:1",
            "finish-link:6:3:3",
        ]
    );

    std::fs::remove_dir_all(&root)
        .expect("remove temp ordered path+dependency stream path-artifact worker run dir");
}

#[test]
fn ordered_path_stream_worker_run_executes_bounded_batches() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-path-stream-worker-run-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let core_path = source_root.join("core.lani");
    let util_path = source_root.join("util.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&util_path, b"util").expect("write util source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let first = execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_for_target(
            [
                ExplicitSourceLibraryPathStream {
                    library_id: 10,
                    source_file_count: 1,
                    paths: std::iter::once(core_path),
                    dependency_library_ids: Vec::new(),
                },
                ExplicitSourceLibraryPathStream {
                    library_id: 20,
                    source_file_count: 1,
                    paths: std::iter::once(util_path),
                    dependency_library_ids: vec![10],
                },
                ExplicitSourceLibraryPathStream {
                    library_id: 30,
                    source_file_count: 1,
                    paths: std::iter::once(app_path),
                    dependency_library_ids: vec![10, 20],
                },
            ],
            &artifact_root,
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 1,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
            SourcePackArtifactTarget::Wasm,
            "worker-a",
            2,
            None,
            &mut executor,
        )
        .expect("prepare and run bounded ordered path-stream worker batches");

    assert_eq!(first.worker_id, "worker-a");
    assert_eq!(first.executed_batch_count, 2);
    assert_eq!(first.completed_batch_count, 2);
    assert!(!first.complete);
    assert_eq!(first.linked_output_key, None);
    assert_eq!(executor.events, vec!["frontend:10:1:0", "frontend:20:1:1"]);

    let resumed = execute_source_pack_filesystem_artifact_manifest_worker_run_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        "worker-b",
        16,
        None,
        &mut executor,
    )
    .expect("resume ordered path-stream worker batches");

    assert_eq!(resumed.worker_id, "worker-b");
    assert_eq!(resumed.executed_batch_count, 5);
    assert!(resumed.complete);
    assert_eq!(
        resumed.linked_output_key.as_deref(),
        Some("wasm/linked-output/job-6/src-0-3")
    );
    assert_eq!(
        std::fs::read(
            resumed
                .linked_output_path
                .as_ref()
                .expect("resumed worker linked output path")
        )
        .expect("read resumed linked output"),
        b"linked:3:3"
    );
    assert_eq!(
        executor.events,
        vec![
            "frontend:10:1:0",
            "frontend:20:1:1",
            "frontend:30:1:2",
            "codegen:10:0..1:1:0",
            "codegen:20:1..2:1:1",
            "codegen:30:2..3:1:2",
            "begin-link:6",
            "link-interfaces:0:1",
            "link-interfaces:1:1",
            "link-interfaces:2:1",
            "link-objects:0:1",
            "link-objects:1:1",
            "link-objects:2:1",
            "finish-link:6:3:3",
        ]
    );

    std::fs::remove_dir_all(&root).expect("remove temp ordered path-stream worker run dir");
}

#[test]
fn ordered_explicit_libraries_execute_honors_custom_artifact_shard_limits() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-ordered-libraries-custom-shards-execute-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let core_path = source_root.join("core.lani");
    let util_path = source_root.join("util.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&util_path, b"util").expect("write util source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let shard_limits = SourcePackBuildShardLimits {
        max_batches_per_shard: 1,
        max_jobs_per_shard: 1,
        max_artifacts_per_shard: 1,
    };
    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let result =
            execute_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target(
                [
                    ExplicitSourceLibraryPaths {
                        library_id: 10,
                        paths: vec![core_path],
                        dependency_library_ids: Vec::new(),
                    },
                    ExplicitSourceLibraryPaths {
                        library_id: 20,
                        paths: vec![util_path],
                        dependency_library_ids: vec![10],
                    },
                    ExplicitSourceLibraryPaths {
                        library_id: 30,
                        paths: vec![app_path],
                        dependency_library_ids: vec![10, 20],
                    },
                ],
                &artifact_root,
                CodegenUnitLimits {
                    max_source_bytes: 4,
                    max_source_files: 1,
                },
                SourcePackJobBatchLimits {
                    max_jobs_per_batch: 1,
                    max_source_bytes_per_batch: 4,
                    max_source_files_per_batch: 1,
                },
                shard_limits,
                SourcePackArtifactTarget::Wasm,
                &mut executor,
            )
            .expect("execute ordered library filesystem artifact build with custom shard limits");

    assert_eq!(result.linked_output_key, "wasm/linked-output/job-6/src-0-3");
    assert_eq!(
        std::fs::read(&result.linked_output_path).expect("read linked output"),
        b"linked:3:3"
    );
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let shard_index = store
        .load_build_artifact_shard_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load ordered library artifact shard index");
    assert_eq!(shard_index.limits, shard_limits.normalized());
    assert!(shard_index.shard_count() > 7);
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "finish-link:6:3:3"),
        "ordered library one-shot execution should still reach the final link job"
    );

    std::fs::remove_dir_all(&root).expect("remove ordered library custom shard test dir");
}

#[test]
fn ordered_path_stream_execute_honors_custom_artifact_shard_limits() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-path-stream-custom-shards-execute-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let core_path = source_root.join("core.lani");
    let util_path = source_root.join("util.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&util_path, b"util").expect("write util source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let shard_limits = SourcePackBuildShardLimits {
        max_batches_per_shard: 1,
        max_jobs_per_shard: 1,
        max_artifacts_per_shard: 1,
    };
    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let result = execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target(
            [
                ExplicitSourceLibraryPathStream {
                    library_id: 10,
                    source_file_count: 1,
                    paths: std::iter::once(core_path),
                    dependency_library_ids: Vec::new(),
                },
                ExplicitSourceLibraryPathStream {
                    library_id: 20,
                    source_file_count: 1,
                    paths: std::iter::once(util_path),
                    dependency_library_ids: vec![10],
                },
                ExplicitSourceLibraryPathStream {
                    library_id: 30,
                    source_file_count: 1,
                    paths: std::iter::once(app_path),
                    dependency_library_ids: vec![10, 20],
                },
            ],
            &artifact_root,
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 1,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
            shard_limits,
            SourcePackArtifactTarget::Wasm,
            &mut executor,
        )
        .expect("execute ordered path-stream filesystem artifact build with custom shard limits");

    assert_eq!(result.linked_output_key, "wasm/linked-output/job-6/src-0-3");
    assert_eq!(
        std::fs::read(&result.linked_output_path).expect("read linked output"),
        b"linked:3:3"
    );
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let shard_index = store
        .load_build_artifact_shard_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load ordered path-stream artifact shard index");
    assert_eq!(shard_index.limits, shard_limits.normalized());
    assert!(shard_index.shard_count() > 7);
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "finish-link:6:3:3"),
        "ordered path-stream one-shot execution should still reach the final link job"
    );

    std::fs::remove_dir_all(&root).expect("remove ordered path-stream custom shard test dir");
}

#[test]
fn explicit_source_pack_path_streams_execute_honors_custom_artifact_shard_limits() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-pack-path-streams-custom-shards-execute-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let stdlib_path = source_root.join("stdlib.lani");
    let user_path = source_root.join("user.lani");
    std::fs::write(&stdlib_path, b"core").expect("write stdlib source");
    std::fs::write(&user_path, b"user").expect("write user source");

    let shard_limits = SourcePackBuildShardLimits {
        max_batches_per_shard: 1,
        max_jobs_per_shard: 1,
        max_artifacts_per_shard: 1,
    };
    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let result = execute_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target(
            1,
            std::iter::once(stdlib_path.as_path()),
            1,
            std::iter::once(user_path.as_path()),
            &artifact_root,
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 1,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
            shard_limits,
            SourcePackArtifactTarget::Wasm,
            &mut executor,
        )
        .expect("execute stdlib/user path-stream filesystem artifact build with custom shard limits");

    assert_eq!(result.linked_output_key, "wasm/linked-output/job-4/src-0-2");
    assert_eq!(
        std::fs::read(&result.linked_output_path).expect("read linked output"),
        b"linked:2:2"
    );
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let shard_index = store
        .load_build_artifact_shard_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load stdlib/user path-stream artifact shard index");
    assert_eq!(shard_index.limits, shard_limits.normalized());
    assert!(shard_index.shard_count() > 5);
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "finish-link:4:2:2"),
        "stdlib/user path-stream one-shot execution should still reach the final link job"
    );

    std::fs::remove_dir_all(&root).expect("remove stdlib/user path-stream shard test dir");
}

#[test]
fn explicit_source_pack_path_streams_worker_run_executes_bounded_batches() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-pack-path-streams-worker-run-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let stdlib_path = source_root.join("stdlib.lani");
    let user_path = source_root.join("user.lani");
    std::fs::write(&stdlib_path, b"core").expect("write stdlib source");
    std::fs::write(&user_path, b"user").expect("write user source");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let first =
        execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_for_target(
            1,
            std::iter::once(stdlib_path.as_path()),
            1,
            std::iter::once(user_path.as_path()),
            &artifact_root,
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 1,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
            SourcePackArtifactTarget::Wasm,
            "worker-a",
            1,
            None,
            &mut executor,
        )
        .expect("prepare and run one stdlib/user path-stream worker batch");

    assert_eq!(first.worker_id, "worker-a");
    assert_eq!(first.executed_batch_count, 1);
    assert_eq!(first.completed_batch_count, 1);
    assert!(!first.complete);
    assert_eq!(first.linked_output_key, None);
    assert_eq!(executor.events, vec!["frontend:0:1:0"]);

    let resumed = execute_source_pack_filesystem_artifact_manifest_worker_run_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        "worker-b",
        16,
        None,
        &mut executor,
    )
    .expect("resume stdlib/user path-stream worker batches");

    assert_eq!(resumed.worker_id, "worker-b");
    assert_eq!(resumed.executed_batch_count, 4);
    assert!(resumed.complete);
    assert_eq!(
        resumed.linked_output_key.as_deref(),
        Some("wasm/linked-output/job-4/src-0-2")
    );
    assert_eq!(
        std::fs::read(
            resumed
                .linked_output_path
                .as_ref()
                .expect("resumed worker linked output path")
        )
        .expect("read resumed linked output"),
        b"linked:2:2"
    );
    assert_eq!(
        executor.events,
        vec![
            "frontend:0:1:0",
            "frontend:1:1:1",
            "codegen:0:0..1:1:0",
            "codegen:1:1..2:1:1",
            "begin-link:4",
            "link-interfaces:0:1",
            "link-interfaces:1:1",
            "link-objects:0:1",
            "link-objects:1:1",
            "finish-link:4:2:2",
        ]
    );

    std::fs::remove_dir_all(&root).expect("remove stdlib/user path-stream worker run test dir");
}

#[test]
fn explicit_source_pack_paths_execute_honors_custom_artifact_shard_limits() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-pack-paths-custom-shards-execute-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let stdlib_path = source_root.join("stdlib.lani");
    let user_path = source_root.join("user.lani");
    std::fs::write(&stdlib_path, b"core").expect("write stdlib source");
    std::fs::write(&user_path, b"user").expect("write user source");

    let shard_limits = SourcePackBuildShardLimits {
        max_batches_per_shard: 1,
        max_jobs_per_shard: 1,
        max_artifacts_per_shard: 1,
    };
    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let result =
        execute_explicit_source_pack_paths_filesystem_artifact_build_with_shard_limits_for_target(
            &[stdlib_path],
            &[user_path],
            &artifact_root,
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 1,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
            shard_limits,
            SourcePackArtifactTarget::Wasm,
            &mut executor,
        )
        .expect("execute stdlib/user filesystem artifact build with custom shard limits");

    assert_eq!(result.linked_output_key, "wasm/linked-output/job-4/src-0-2");
    assert_eq!(
        std::fs::read(&result.linked_output_path).expect("read linked output"),
        b"linked:2:2"
    );
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let shard_index = store
        .load_build_artifact_shard_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load stdlib/user artifact shard index");
    assert_eq!(shard_index.limits, shard_limits.normalized());
    assert!(shard_index.shard_count() > 5);
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "finish-link:4:2:2"),
        "stdlib/user one-shot execution should still reach the final link job"
    );

    std::fs::remove_dir_all(&root).expect("remove stdlib/user custom shard execute test dir");
}

#[test]
fn explicit_source_path_manifest_filesystem_artifact_store_spills_keyed_artifacts_to_disk() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-path-filesystem-artifact-store-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let first_path = source_root.join("first.lani");
    let second_path = source_root.join("second.lani");
    let third_path = source_root.join("third.lani");
    let fourth_path = source_root.join("fourth.lani");
    std::fs::write(&first_path, b"aaaa").expect("write first source");
    std::fs::write(&second_path, b"bbbb").expect("write second source");
    std::fs::write(&third_path, b"cccc").expect("write third source");
    std::fs::write(&fourth_path, b"dddd").expect("write fourth source");

    let manifest = load_explicit_source_libraries_path_manifest(vec![
        ExplicitSourceLibraryPaths {
            library_id: 7,
            paths: vec![first_path, second_path],
            dependency_library_ids: Vec::new(),
        },
        ExplicitSourceLibraryPaths {
            library_id: 8,
            paths: vec![third_path, fourth_path],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect("load path manifest");
    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let mut store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let result = manifest
        .execute_build_plan_with_artifact_store(
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 8,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 2,
                max_source_bytes_per_batch: 8,
                max_source_files_per_batch: 2,
            },
            &mut executor,
            &mut store,
        )
        .expect("execute filesystem artifact-store path build plan");

    assert_eq!(result.linked_output_key, "linked-output/job-6/src-0-4");
    assert_eq!(
        store
            .load_linked_output(&result.linked_output_key)
            .expect("load linked output artifact"),
        b"linked:2:4"
    );
    assert!(
        !store
            .path_for_key("library-interface/lib-7/job-0/src-0-2")
            .expect("interface artifact path")
            .exists()
    );
    assert!(
        !store
            .path_for_key("codegen-object/lib-8/job-5/src-3-4")
            .expect("object artifact path")
            .exists()
    );
    assert!(
        store
            .path_for_key("linked-output/job-6/src-0-4")
            .expect("linked output artifact path")
            .exists()
    );
    assert_eq!(
        executor.events,
        vec![
            "frontend:7:2:0",
            "frontend:8:2:0",
            "codegen:7:0..1:1:0",
            "codegen:7:1..2:1:0",
            "codegen:8:2..3:1:0",
            "codegen:8:3..4:1:0",
            "begin-link:6",
            "link-interfaces:0:1",
            "link-interfaces:1:1",
            "link-objects:0:2",
            "link-objects:1:2",
            "finish-link:6:2:4",
        ]
    );
    std::fs::remove_dir_all(&root).expect("remove temp filesystem artifact-store dir");
}

#[test]
fn explicit_source_pack_paths_filesystem_artifact_prepare_streams_path_slices() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-pack-paths-filesystem-artifact-prepare-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let stdlib_path = source_root.join("stdlib.lani");
    let user_path = source_root.join("user.lani");
    std::fs::write(&stdlib_path, b"core").expect("write stdlib source");
    std::fs::write(&user_path, b"user").expect("write user source");

    let prepared = prepare_explicit_source_pack_paths_filesystem_artifact_build_for_target(
        &[stdlib_path],
        &[user_path],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 1,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare stdlib/user filesystem artifact build from path slices");

    assert_eq!(prepared.library_count, 2);
    assert_eq!(prepared.source_file_count, 2);
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store
        .load_library_schedule_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared schedule index");
    let stdlib_locator = store
        .load_library_frontend_job_locator_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load stdlib frontend locator");
    let user_locator = store
        .load_library_frontend_job_locator_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load user frontend locator");
    let user_frontend_job = store
        .load_library_schedule_job_page_for_target(
            SourcePackArtifactTarget::Wasm,
            user_locator.frontend_job_index,
            schedule_index.job_count,
        )
        .expect("load user frontend schedule job");
    assert_eq!(
        source_pack_schedule_job_page_dependency_count(&user_frontend_job),
        1
    );
    assert_eq!(
        user_frontend_job.dependency_job_ranges,
        vec![SourcePackJobIndexRange {
            first_job_index: stdlib_locator.frontend_job_index,
            job_count: 1,
        }]
    );
    assert_eq!(user_frontend_job.dependency_job_count, 0);
    assert_eq!(user_frontend_job.dependency_page_count, 0);
    assert!(
        user_frontend_job.job.dependency_job_indices.is_empty(),
        "path-slice prepare should leave dependencies outside inline job records"
    );

    std::fs::remove_dir_all(&root).expect("remove temp pack paths filesystem artifact prepare dir");
}

#[test]
fn explicit_source_libraries_filesystem_artifact_prepare_writes_bounded_frontend_unit_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-filesystem-artifact-frontend-units-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let paths = (0..3)
        .map(|source_index| {
            let path = source_root.join(format!("source-{source_index}.lani"));
            std::fs::write(&path, b"unit").expect("write source");
            path
        })
        .collect::<Vec<_>>();

    let prepared = prepare_explicit_source_libraries_filesystem_artifact_build(
        vec![ExplicitSourceLibraryPaths {
            library_id: 7,
            paths,
            dependency_library_ids: Vec::new(),
        }],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 1,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
    )
    .expect("prepare filesystem artifact build with bounded frontend units");

    assert_eq!(prepared.library_count, 1);
    assert_eq!(prepared.source_file_count, 3);
    assert_eq!(prepared.scheduled_job_count, 7);
    assert_eq!(prepared.artifact_count, 7);
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store
        .load_library_schedule_index_for_target(SourcePackArtifactTarget::Generic)
        .expect("load compact schedule index");
    assert_eq!(schedule_index.partition_count, 1);
    assert_eq!(schedule_index.frontend_job_count, 3);
    assert_eq!(schedule_index.codegen_job_count, 3);
    assert_eq!(schedule_index.link_job_index, 6);
    let frontend_locator = store
        .load_library_frontend_job_locator_page_for_target(SourcePackArtifactTarget::Generic, 7)
        .expect("load frontend-job range locator");
    assert_eq!(frontend_locator.frontend_job_index, 0);
    assert_eq!(frontend_locator.frontend_job_count, 3);
    let schedule_page = store
        .load_library_schedule_page_for_target(SourcePackArtifactTarget::Generic, 0)
        .expect("load compact schedule page");
    assert_eq!(schedule_page.frontend_job_index, 0);
    assert_eq!(schedule_page.frontend_job_count, 3);
    assert_eq!(schedule_page.first_codegen_job_index, 3);
    assert!(
        schedule_page.frontend_jobs.is_empty(),
        "prepared schedule pages should leave frontend jobs in per-job pages"
    );
    let build_unit_page = store
        .load_library_build_unit_page_for_target(SourcePackArtifactTarget::Generic, 0)
        .expect("load compact build-unit page");
    assert_eq!(build_unit_page.library_id, 7);
    assert_eq!(build_unit_page.frontend_unit_count, 3);
    assert_eq!(build_unit_page.codegen_unit_count, 3);
    assert!(
        build_unit_page.frontend_units.is_empty(),
        "prepared build-unit pages should leave frontend units in per-unit pages"
    );
    assert!(
        build_unit_page.codegen_units.is_empty(),
        "prepared build-unit pages should leave codegen units in per-unit pages"
    );

    for unit_index in 0..3 {
        let frontend_job = source_pack_stored_schedule_job(&store, &schedule_index, unit_index)
            .expect("load prepared frontend-unit schedule job");
        assert_eq!(frontend_job.phase, SourcePackJobPhase::LibraryFrontend);
        assert_eq!(frontend_job.library_id, 7);
        assert_eq!(frontend_job.first_source_index, unit_index);
        assert_eq!(frontend_job.source_file_count, 1);
        assert!(frontend_job.dependency_job_indices.is_empty());

        let frontend_unit_page = store
            .load_library_frontend_unit_page_for_target(
                SourcePackArtifactTarget::Generic,
                0,
                unit_index,
            )
            .expect("load prepared frontend-unit page");
        assert_eq!(frontend_unit_page.library_id, 7);
        assert_eq!(frontend_unit_page.frontend_unit_count, 3);
        assert_eq!(frontend_unit_page.unit.unit_index, unit_index);
        assert_eq!(frontend_unit_page.unit.first_source_index, unit_index);
        assert_eq!(frontend_unit_page.unit.source_file_count, 1);
        assert_eq!(frontend_unit_page.unit.source_bytes, 4);

        let codegen_unit_page = store
            .load_library_codegen_unit_page_for_target(
                SourcePackArtifactTarget::Generic,
                0,
                unit_index,
            )
            .expect("load prepared codegen-unit page");
        assert_eq!(codegen_unit_page.codegen_unit_count, 3);
        assert_eq!(codegen_unit_page.unit.first_source_index, unit_index);

        let codegen_job_index = 3 + unit_index;
        let codegen_job_page = store
            .load_library_schedule_job_page_for_target(
                SourcePackArtifactTarget::Generic,
                codegen_job_index,
                schedule_index.job_count,
            )
            .expect("load prepared codegen schedule job page");
        assert_eq!(codegen_job_page.dependency_job_count, 1);
        assert_eq!(codegen_job_page.dependency_page_count, 1);
        let expected_ranges = match unit_index {
            0 => vec![SourcePackJobIndexRange {
                first_job_index: 1,
                job_count: 2,
            }],
            1 => vec![
                SourcePackJobIndexRange {
                    first_job_index: 0,
                    job_count: 1,
                },
                SourcePackJobIndexRange {
                    first_job_index: 2,
                    job_count: 1,
                },
            ],
            2 => vec![SourcePackJobIndexRange {
                first_job_index: 0,
                job_count: 2,
            }],
            _ => unreachable!("test only builds three units"),
        };
        assert_eq!(codegen_job_page.dependency_job_ranges, expected_ranges);
        let dependency_page = store
            .load_library_schedule_job_dependency_page_for_target(
                SourcePackArtifactTarget::Generic,
                codegen_job_index,
                0,
                schedule_index.job_count,
            )
            .expect("load prepared codegen dependency page");
        assert_eq!(dependency_page.dependency_job_indices, vec![unit_index]);
        let work_queue_page = store
            .load_work_queue_page_for_target(SourcePackArtifactTarget::Generic, codegen_job_index)
            .expect("load prepared codegen work-queue page");
        assert!(
            work_queue_page.dependency_item_indices.is_empty(),
            "prepared work queue should keep explicit dependencies in dependency pages"
        );
        assert_eq!(work_queue_page.dependency_item_count, 1);
        assert_eq!(work_queue_page.dependency_page_count, 1);
        assert_eq!(work_queue_page.dependency_item_ranges, expected_ranges);
        assert_eq!(
            source_pack_work_queue_page_dependency_count(&work_queue_page),
            3
        );
        let work_queue_dependency_page = store
            .load_work_queue_dependencies_page_for_target(
                SourcePackArtifactTarget::Generic,
                codegen_job_index,
                0,
            )
            .expect("load prepared codegen work-queue dependency page");
        assert_eq!(
            work_queue_dependency_page.dependency_item_indices,
            vec![unit_index]
        );
        let codegen_job =
            source_pack_stored_schedule_job(&store, &schedule_index, codegen_job_index)
                .expect("load prepared codegen schedule job");
        assert_eq!(codegen_job.phase, SourcePackJobPhase::Codegen);
        assert_eq!(codegen_job.library_job_index, Some(unit_index));
        assert_eq!(
            codegen_job.dependency_job_indices.first(),
            Some(&unit_index)
        );
        assert_eq!(
            codegen_job
                .dependency_job_indices
                .iter()
                .copied()
                .collect::<BTreeSet<_>>(),
            BTreeSet::from([0, 1, 2])
        );
    }
    let first_frontend_work_item = store
        .load_work_queue_page_for_target(SourcePackArtifactTarget::Generic, 0)
        .expect("load first frontend work-queue page");
    assert_eq!(first_frontend_work_item.dependent_item_count, 1);
    assert_eq!(first_frontend_work_item.dependent_page_count, 1);
    assert_eq!(
        first_frontend_work_item.dependent_item_ranges,
        vec![
            SourcePackJobIndexRange {
                first_job_index: 3,
                job_count: 3,
            },
            SourcePackJobIndexRange {
                first_job_index: 7,
                job_count: 2,
            },
        ]
    );
    assert_eq!(
        source_pack_work_queue_page_dependent_count(&first_frontend_work_item),
        6
    );

    std::fs::remove_dir_all(&root).expect("remove temp filesystem artifact frontend-unit dir");
}

#[test]
fn explicit_source_libraries_filesystem_artifact_prepare_uses_metadata_only() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-filesystem-artifact-prepare-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, [0xff, 0xfe, 0xfd, b'!']).expect("write invalid utf8 app source");

    let prepared = prepare_explicit_source_libraries_filesystem_artifact_build_for_target(
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path],
                dependency_library_ids: vec![10],
            },
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            },
        ],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 8,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare filesystem artifact build from metadata only");

    assert_eq!(prepared.target, SourcePackArtifactTarget::Wasm);
    assert_eq!(prepared.source_file_count, 2);
    assert_eq!(prepared.source_byte_count, 8);
    assert_eq!(prepared.library_count, 2);
    assert_eq!(prepared.artifact_count, 5);
    assert_eq!(prepared.scheduled_job_count, 5);
    assert_eq!(prepared.batch_count, 5);
    assert_eq!(prepared.initial_ready_batch_count, 1);
    assert_eq!(prepared.first_ready_batch_index, Some(0));
    assert!(
        prepared
            .build_manifest_path
            .ends_with("source-pack-build.wasm.json")
    );
    assert_eq!(prepared.library_partition_count, 2);
    assert!(
        prepared
            .library_partition_index_path
            .ends_with("source-pack-library-partitions.wasm.json")
    );
    assert_eq!(prepared.library_source_file_page_count, 2);
    assert_eq!(prepared.library_build_unit_page_count, 2);
    assert!(
        prepared
            .library_schedule_index_path
            .ends_with("source-pack-library-schedule.wasm.json")
    );
    assert_eq!(prepared.library_schedule_page_count, 2);
    assert!(
        prepared
            .hierarchical_link_plan_index_path
            .ends_with("source-pack-hierarchical-link-plan.wasm.json")
    );
    assert!(prepared.hierarchical_link_group_count >= 1);
    assert!(
        prepared
            .hierarchical_link_execution_index_path
            .ends_with("source-pack-hierarchical-link-execution.wasm.json")
    );
    assert_eq!(
        prepared.hierarchical_link_execution_group_count,
        prepared.hierarchical_link_group_count
    );
    assert!(
        prepared
            .work_queue_index_path
            .ends_with("source-pack-work-queue.wasm.json")
    );
    assert!(prepared.work_queue_item_count >= prepared.scheduled_job_count);
    assert!(
        prepared
            .work_queue_progress_index_path
            .ends_with("source-pack-work-queue-progress.wasm.json")
    );
    assert!(prepared.work_queue_progress_page_count >= 1);
    assert_eq!(prepared.initial_ready_work_item_count, 1);
    assert_eq!(prepared.first_ready_work_item_index, Some(0));
    assert!(
        prepared
            .artifact_manifest_path
            .ends_with("source-pack-artifacts.wasm.json")
    );
    assert!(
        prepared
            .artifact_shard_index_path
            .ends_with("source-pack-artifact-shards.wasm.json")
    );
    assert!(prepared.artifact_shard_count > 0);
    assert!(
        prepared
            .build_state_path
            .ends_with("source-pack-state.wasm.json")
    );

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let state = store
        .load_build_state_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared build state");
    assert_eq!(state, SourcePackBuildState::new());
    let path_manifest = store
        .load_path_build_manifest_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared path build manifest");
    assert_eq!(
        path_manifest.artifacts.target,
        SourcePackArtifactTarget::Wasm
    );
    assert_eq!(path_manifest.source_file_count, 2);
    assert_eq!(path_manifest.source_byte_count, 8);
    assert!(
        path_manifest.source_files.is_empty(),
        "prepared path build manifest should leave source-file records in source-file pages"
    );
    assert_eq!(path_manifest.artifacts.job_batch_count, 5);
    assert!(
        path_manifest.artifacts.job_schedule.jobs.is_empty(),
        "prepared path build manifest should leave artifact job records in execution shards"
    );
    let library_partition_index = store
        .load_library_partition_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared library partition index");
    assert_eq!(
        library_partition_index.target,
        SourcePackArtifactTarget::Wasm
    );
    assert_eq!(library_partition_index.partition_count, 2);
    assert_eq!(library_partition_index.source_file_count, 2);
    assert_eq!(library_partition_index.source_byte_count, 8);
    assert_stored_partition_index_has_no_inline_partitions(&store, SourcePackArtifactTarget::Wasm);
    let app_partition = store
        .load_library_partition_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load prepared app library partition");
    assert_eq!(app_partition.library_id, 20);
    assert!(
        app_partition.dependency_library_ids.is_empty(),
        "prepared library partition pages should leave dependency libraries in dependency pages"
    );
    assert_eq!(app_partition.dependency_library_count, 1);
    assert_eq!(app_partition.dependency_page_count, 1);
    let app_dependency_page = store
        .load_library_dependency_page_for_target(SourcePackArtifactTarget::Wasm, 1, 0)
        .expect("load prepared app library dependency page");
    assert_eq!(app_dependency_page.dependency_library_ids, vec![10]);
    assert_eq!(
        source_pack_load_library_dependency_ids(&store, &app_partition)
            .expect("load prepared app library dependencies"),
        vec![10]
    );
    let app_source_file_page = store
        .load_library_source_file_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load prepared app library source-file page");
    assert_eq!(app_source_file_page.library_id, 20);
    assert_eq!(app_source_file_page.source_file_count, 1);
    assert!(
        app_source_file_page.source_files.is_empty(),
        "prepared source-file pages should leave source-file records in per-file pages"
    );
    let app_source_file_record = store
        .load_library_source_file_record_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load prepared app source-file record");
    assert_eq!(app_source_file_record.partition_index, 1);
    assert_eq!(app_source_file_record.library_id, 20);
    assert_eq!(app_source_file_record.file.byte_len, 4);
    let app_build_unit_page = store
        .load_library_build_unit_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load prepared app library build-unit page");
    assert_eq!(app_build_unit_page.library_id, 20);
    assert!(
        app_build_unit_page.dependency_library_ids.is_empty(),
        "prepared build-unit pages should consume dependency libraries from partition dependency pages"
    );
    assert_eq!(app_build_unit_page.frontend_unit.source_file_count, 1);
    assert_eq!(app_build_unit_page.codegen_unit_count, 1);
    assert!(
        app_build_unit_page.codegen_units.is_empty(),
        "prepared build-unit pages should leave codegen units in per-unit pages"
    );
    let app_codegen_unit_page = store
        .load_library_codegen_unit_page_for_target(SourcePackArtifactTarget::Wasm, 1, 0)
        .expect("load prepared app codegen-unit page");
    assert_eq!(app_codegen_unit_page.library_id, 20);
    assert_eq!(app_codegen_unit_page.unit.first_source_index, 1);
    let schedule_index = store
        .load_library_schedule_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared library schedule index");
    assert_eq!(schedule_index.partition_count, 2);
    assert_stored_schedule_index_has_no_inline_entries(&store, SourcePackArtifactTarget::Wasm);
    let job_locator_index = store
        .load_library_schedule_job_locator_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared schedule job-locator index");
    assert_eq!(job_locator_index.job_count, prepared.scheduled_job_count);
    assert_eq!(
        job_locator_index.locator_count,
        prepared.scheduled_job_count
    );
    let app_frontend_locator = store
        .load_library_schedule_job_locator_page_for_target(
            SourcePackArtifactTarget::Wasm,
            1,
            job_locator_index.job_count,
        )
        .expect("load prepared app frontend job locator");
    assert_eq!(
        app_frontend_locator.phase,
        SourcePackJobPhase::LibraryFrontend
    );
    assert_eq!(app_frontend_locator.partition_index, Some(1));
    let app_schedule_page = store
        .load_library_schedule_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load prepared app library schedule page");
    assert_eq!(app_schedule_page.library_id, 20);
    assert!(
        app_schedule_page.dependency_library_ids.is_empty(),
        "prepared schedule pages should consume dependency libraries from partition dependency pages"
    );
    assert!(
        app_schedule_page
            .frontend_job
            .dependency_job_indices
            .is_empty(),
        "prepared schedule pages should leave frontend dependency jobs in per-job dependency pages"
    );
    assert!(
        app_schedule_page.codegen_jobs.is_empty(),
        "prepared schedule pages should leave codegen jobs in per-job pages"
    );
    assert_eq!(app_schedule_page.codegen_job_count, 1);
    let app_frontend_job_page = store
        .load_library_schedule_job_page_for_target(
            SourcePackArtifactTarget::Wasm,
            app_schedule_page.frontend_job_index,
            job_locator_index.job_count,
        )
        .expect("load prepared app frontend schedule job page");
    assert!(
        app_frontend_job_page.job.dependency_job_indices.is_empty(),
        "prepared frontend schedule job pages should leave dependency jobs in dependency pages"
    );
    assert_eq!(
        source_pack_schedule_job_page_dependency_count(&app_frontend_job_page),
        1
    );
    assert_eq!(app_frontend_job_page.dependency_job_count, 0);
    assert_eq!(app_frontend_job_page.dependency_page_count, 0);
    assert_eq!(
        app_frontend_job_page.dependency_job_ranges,
        vec![SourcePackJobIndexRange {
            first_job_index: 0,
            job_count: 1,
        }]
    );
    let app_frontend_job = source_pack_stored_schedule_job(
        &store,
        &schedule_index,
        app_schedule_page.frontend_job_index,
    )
    .expect("resolve app frontend job from dependency pages");
    assert_eq!(app_frontend_job.dependency_job_indices, vec![0]);
    let app_codegen_job_index = app_schedule_page.first_codegen_job_index;
    let app_codegen_locator = store
        .load_library_schedule_job_locator_page_for_target(
            SourcePackArtifactTarget::Wasm,
            app_codegen_job_index,
            job_locator_index.job_count,
        )
        .expect("load prepared app codegen job locator");
    assert_eq!(app_codegen_locator.phase, SourcePackJobPhase::Codegen);
    assert_eq!(app_codegen_locator.partition_index, Some(1));
    assert_eq!(app_codegen_locator.codegen_job_offset, Some(0));
    let app_codegen_job_page = store
        .load_library_schedule_job_page_for_target(
            SourcePackArtifactTarget::Wasm,
            app_codegen_job_index,
            job_locator_index.job_count,
        )
        .expect("load prepared app codegen schedule job page");
    assert_eq!(app_codegen_job_page.job.phase, SourcePackJobPhase::Codegen);
    assert_eq!(app_codegen_job_page.job.library_id, 20);
    assert!(
        app_codegen_job_page.job.dependency_job_indices.is_empty(),
        "prepared schedule job pages should leave dependency jobs in dependency pages"
    );
    assert_eq!(
        source_pack_schedule_job_page_dependency_count(&app_codegen_job_page),
        2
    );
    assert_eq!(app_codegen_job_page.dependency_job_count, 1);
    assert_eq!(app_codegen_job_page.dependency_page_count, 1);
    assert_eq!(
        app_codegen_job_page.dependency_job_ranges,
        vec![SourcePackJobIndexRange {
            first_job_index: 0,
            job_count: 1,
        }]
    );
    let app_codegen_dependency_page = store
        .load_library_schedule_job_dependency_page_for_target(
            SourcePackArtifactTarget::Wasm,
            app_codegen_job_index,
            0,
            job_locator_index.job_count,
        )
        .expect("load prepared app codegen dependency page");
    assert_eq!(app_codegen_dependency_page.dependency_job_indices, vec![1]);
    let app_codegen_job =
        source_pack_stored_schedule_job(&store, &schedule_index, app_codegen_job_index)
            .expect("resolve app codegen job from locator and schedule page");
    assert_eq!(app_codegen_job.phase, SourcePackJobPhase::Codegen);
    assert_eq!(app_codegen_job.library_id, 20);
    assert_eq!(app_codegen_job.dependency_job_indices, vec![1, 0]);
    let link_job =
        source_pack_stored_schedule_job(&store, &schedule_index, schedule_index.link_job_index)
            .expect("resolve link job from locator");
    assert_eq!(link_job.phase, SourcePackJobPhase::Link);
    let artifact_ref_index = store
        .load_build_artifact_ref_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared artifact-ref index");
    assert_eq!(artifact_ref_index.artifact_count, prepared.artifact_count);
    assert_eq!(artifact_ref_index.interface_artifact_count, 2);
    assert_eq!(artifact_ref_index.object_artifact_count, 2);
    assert_eq!(
        artifact_ref_index.final_output_artifact_index,
        schedule_index.link_job_index
    );
    let core_interface_artifact_ref = store
        .load_build_artifact_ref_page_for_target(
            SourcePackArtifactTarget::Wasm,
            0,
            artifact_ref_index.artifact_count,
        )
        .expect("load prepared core interface artifact-ref page");
    assert_eq!(
        core_interface_artifact_ref.artifact_ref.kind,
        SourcePackArtifactKind::LibraryInterface
    );
    assert_eq!(core_interface_artifact_ref.source_bytes, 4);
    let app_codegen_artifact_ref = store
        .load_build_artifact_ref_page_for_target(
            SourcePackArtifactTarget::Wasm,
            app_codegen_job_index,
            artifact_ref_index.artifact_count,
        )
        .expect("load prepared app codegen artifact-ref page");
    assert_eq!(
        app_codegen_artifact_ref.artifact_ref.kind,
        SourcePackArtifactKind::CodegenObject
    );
    assert_eq!(app_codegen_artifact_ref.source_file_count, 1);
    let final_artifact_ref = store
        .load_build_artifact_ref_page_for_target(
            SourcePackArtifactTarget::Wasm,
            schedule_index.link_job_index,
            artifact_ref_index.artifact_count,
        )
        .expect("load prepared final artifact-ref page");
    assert_eq!(
        final_artifact_ref.artifact_ref.kind,
        SourcePackArtifactKind::LinkedOutput
    );
    assert_eq!(
        final_artifact_ref.artifact_ref.key,
        artifact_ref_index.final_output_key
    );
    let link_plan_index = store
        .load_hierarchical_link_plan_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared hierarchical link plan index");
    assert_eq!(link_plan_index.input_partition_count, 2);
    assert_eq!(
        link_plan_index.link_group_count,
        prepared.hierarchical_link_group_count
    );
    let link_plan_index_json = String::from_utf8(
        std::fs::read(
            store.hierarchical_link_plan_index_path_for_target(SourcePackArtifactTarget::Wasm),
        )
        .expect("read prepared hierarchical link plan index"),
    )
    .expect("hierarchical link plan index is utf8");
    assert!(
        !link_plan_index_json.contains("\"groups\""),
        "prepared hierarchical link plan index should leave group summaries in group pages"
    );
    let first_link_group = store
        .load_hierarchical_link_group_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load prepared first hierarchical link group");
    assert_eq!(
        first_link_group.kind,
        SourcePackHierarchicalLinkGroupKind::Leaf
    );
    let link_execution_index = store
        .load_hierarchical_link_execution_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared hierarchical link execution index");
    assert_eq!(
        link_execution_index.link_group_count,
        prepared.hierarchical_link_execution_group_count
    );
    let link_execution_index_json = String::from_utf8(
        std::fs::read(
            store.hierarchical_link_execution_index_path_for_target(SourcePackArtifactTarget::Wasm),
        )
        .expect("read prepared hierarchical link execution index"),
    )
    .expect("hierarchical link execution index is utf8");
    assert!(
        !link_execution_index_json.contains("\"groups\""),
        "prepared hierarchical link execution index should leave group summaries in execution pages"
    );
    assert_eq!(
        link_execution_index.final_link_group_index,
        link_plan_index.final_link_group_index
    );
    let first_link_execution = store
        .load_hierarchical_link_execution_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load prepared first hierarchical link execution page");
    assert_eq!(
        first_link_execution.kind,
        SourcePackHierarchicalLinkGroupKind::Leaf
    );
    assert!(first_link_execution.input_interfaces.is_empty());
    assert!(first_link_execution.input_interface_count > 0);
    assert!(first_link_execution.input_interface_page_count > 0);
    let first_link_interface_page = store
        .load_hierarchical_link_execution_interface_page_for_target(
            SourcePackArtifactTarget::Wasm,
            first_link_execution.group_index,
            0,
        )
        .expect("load prepared first hierarchical link interface page");
    assert!(!first_link_interface_page.input_interfaces.is_empty());
    let app_link_group_index = (0..link_plan_index.link_group_count)
        .find(|&group_index| {
            let group = store
                .load_hierarchical_link_group_page_for_target(
                    SourcePackArtifactTarget::Wasm,
                    group_index,
                )
                .expect("load prepared hierarchical link group while finding app group");
            group.kind == SourcePackHierarchicalLinkGroupKind::Leaf
                && group
                    .input_codegen_job_indices
                    .contains(&app_codegen_job_index)
        })
        .expect("find app hierarchical link group");
    let app_link_execution = store
        .load_hierarchical_link_execution_page_for_target(
            SourcePackArtifactTarget::Wasm,
            app_link_group_index,
        )
        .expect("load prepared app hierarchical link execution page");
    assert_eq!(
        app_link_execution.kind,
        SourcePackHierarchicalLinkGroupKind::Leaf
    );
    assert!(app_link_execution.input_interfaces.is_empty());
    assert_eq!(app_link_execution.input_interface_count, 2);
    assert_eq!(app_link_execution.input_interface_page_count, 1);
    assert_eq!(
        app_link_execution.input_interface_ranges,
        vec![SourcePackJobIndexRange {
            first_job_index: 0,
            job_count: 1,
        }]
    );
    let app_link_interface_page = store
        .load_hierarchical_link_execution_interface_page_for_target(
            SourcePackArtifactTarget::Wasm,
            app_link_execution.group_index,
            0,
        )
        .expect("load prepared app hierarchical link interface page");
    assert_eq!(
        app_link_interface_page
            .input_interfaces
            .iter()
            .map(|artifact| artifact.producing_job_index)
            .collect::<Vec<_>>(),
        vec![app_schedule_page.frontend_job_index]
    );
    assert!(first_link_execution.input_objects.is_empty());
    assert!(first_link_execution.input_object_count > 0);
    assert!(first_link_execution.input_object_page_count > 0);
    let first_link_object_page = store
        .load_hierarchical_link_execution_object_page_for_target(
            SourcePackArtifactTarget::Wasm,
            first_link_execution.group_index,
            0,
        )
        .expect("load prepared first hierarchical link object page");
    assert!(!first_link_object_page.input_objects.is_empty());
    let final_link_execution = store
        .load_hierarchical_link_execution_page_for_target(
            SourcePackArtifactTarget::Wasm,
            link_execution_index.final_link_group_index,
        )
        .expect("load prepared final hierarchical link execution page");
    assert!(final_link_execution.final_output);
    assert_eq!(
        final_link_execution.output_key,
        link_execution_index.final_output_key
    );
    assert_eq!(
        final_artifact_ref.artifact_ref.key,
        link_execution_index.final_output_key
    );
    let job_batch_index = store
        .load_build_job_batch_page_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared job-batch page index");
    assert_eq!(job_batch_index.batch_count, prepared.batch_count);
    assert_eq!(
        job_batch_index.scheduled_job_count,
        prepared.scheduled_job_count
    );
    let first_job_batch = store
        .load_build_job_batch_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load prepared first job-batch page");
    assert_eq!(first_job_batch.target, SourcePackArtifactTarget::Wasm);
    assert_eq!(first_job_batch.batch.batch_index, 0);
    assert!(
        first_job_batch
            .dependency
            .dependency_batch_indices
            .is_empty()
    );
    assert!(
        first_job_batch
            .dependency
            .dependency_batch_ranges
            .is_empty()
    );
    let first_job_batch_dependents = store
        .load_build_job_batch_dependents_page_for_target(
            SourcePackArtifactTarget::Wasm,
            0,
            job_batch_index.batch_count,
        )
        .expect("load prepared first job-batch dependents page");
    assert_eq!(first_job_batch_dependents.batch_index, 0);
    assert!(
        first_job_batch_dependents
            .dependents
            .dependent_batch_indices
            .is_empty(),
        "prepared build should keep reverse dependents out of the count page"
    );
    assert!(
        first_job_batch_dependents.dependent_batch_count > 0,
        "prepared build should persist reverse dependent counts per batch"
    );
    assert!(
        first_job_batch_dependents.dependent_page_count > 0,
        "prepared build should persist reverse dependent page counts per batch"
    );
    let first_dependent_batch_page = store
        .load_build_job_batch_dependent_batch_page_for_target(
            SourcePackArtifactTarget::Wasm,
            0,
            0,
            job_batch_index.batch_count,
        )
        .expect("load prepared first dependent-batch page");
    assert_eq!(
        first_dependent_batch_page.dependent_count,
        first_dependent_batch_page.dependent_batch_indices.len()
    );
    let first_job_batch_locator = store
        .load_build_job_batch_job_locator_page_for_target(
            SourcePackArtifactTarget::Wasm,
            0,
            job_batch_index.scheduled_job_count,
        )
        .expect("load first job's persisted batch locator");
    assert_eq!(first_job_batch_locator.batch_index, 0);
    let app_codegen_batch_locator = store
        .load_build_job_batch_job_locator_page_for_target(
            SourcePackArtifactTarget::Wasm,
            app_codegen_job_index,
            job_batch_index.scheduled_job_count,
        )
        .expect("load app codegen job's persisted batch locator");
    let app_codegen_batch = store
        .load_build_job_batch_page_for_target(
            SourcePackArtifactTarget::Wasm,
            app_codegen_batch_locator.batch_index,
        )
        .expect("load app codegen job batch from locator");
    assert!(
        app_codegen_batch
            .batch
            .job_indices
            .contains(&app_codegen_job_index)
    );
    let final_link_batch_locator = store
        .load_build_job_batch_job_locator_page_for_target(
            SourcePackArtifactTarget::Wasm,
            schedule_index.link_job_index,
            job_batch_index.scheduled_job_count,
        )
        .expect("load final link job's persisted batch locator");
    let final_link_job_batch = store
        .load_build_job_batch_page_for_target(
            SourcePackArtifactTarget::Wasm,
            final_link_batch_locator.batch_index,
        )
        .expect("load final link job batch");
    let first_codegen_batch_locator = store
        .load_build_job_batch_job_locator_page_for_target(
            SourcePackArtifactTarget::Wasm,
            schedule_index.partition_count,
            job_batch_index.scheduled_job_count,
        )
        .expect("load first codegen job's batch locator");
    let last_codegen_batch_locator = store
        .load_build_job_batch_job_locator_page_for_target(
            SourcePackArtifactTarget::Wasm,
            schedule_index.link_job_index - 1,
            job_batch_index.scheduled_job_count,
        )
        .expect("load last codegen job's batch locator");
    assert!(
        final_link_job_batch
            .dependency
            .dependency_batch_indices
            .is_empty(),
        "final-link dependency should not materialize one edge per codegen batch"
    );
    assert!(
        final_link_job_batch
            .dependency
            .dependency_batch_ranges
            .is_empty(),
        "final-link dependency should keep dependency ranges in range pages"
    );
    assert_eq!(final_link_job_batch.dependency.dependency_range_count, 1);
    assert_eq!(
        final_link_job_batch.dependency.dependency_range_page_count,
        1
    );
    assert_eq!(
        final_link_job_batch.dependency.dependency_range_batch_count,
        last_codegen_batch_locator
            .batch_index
            .saturating_sub(first_codegen_batch_locator.batch_index)
            .saturating_add(1)
    );
    let final_link_dependency_range_page = store
        .load_build_job_batch_dependency_range_page_for_target(
            SourcePackArtifactTarget::Wasm,
            final_link_job_batch.batch_index,
            0,
        )
        .expect("load final-link dependency range page");
    assert_eq!(
        final_link_dependency_range_page.dependency_batch_ranges,
        vec![SourcePackJobBatchDependencyRange {
            first_batch_index: first_codegen_batch_locator.batch_index,
            batch_count: last_codegen_batch_locator
                .batch_index
                .saturating_sub(first_codegen_batch_locator.batch_index)
                .saturating_add(1),
        }]
    );
    let link_batch_index = store
        .load_build_link_batch_page_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared link-batch page index");
    assert!(link_batch_index.link_interface_batch_count >= 1);
    assert!(link_batch_index.link_object_batch_count >= 1);
    let first_link_interface_batch = store
        .load_build_link_interface_batch_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load prepared first link-interface batch page");
    assert_eq!(
        first_link_interface_batch.target,
        SourcePackArtifactTarget::Wasm
    );
    assert_eq!(first_link_interface_batch.batch.batch_index, 0);
    assert!(
        !first_link_interface_batch
            .batch
            .input_interface_artifact_indices
            .is_empty()
    );
    let first_link_object_batch = store
        .load_build_link_object_batch_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load prepared first link-object batch page");
    assert_eq!(
        first_link_object_batch.target,
        SourcePackArtifactTarget::Wasm
    );
    assert_eq!(first_link_object_batch.batch.batch_index, 0);
    assert!(
        !first_link_object_batch
            .batch
            .input_object_artifact_indices
            .is_empty()
    );
    let work_queue = store
        .load_work_queue_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared work queue index");
    assert_eq!(work_queue.work_item_count, prepared.work_queue_item_count);
    let work_queue_index_json = String::from_utf8(
        std::fs::read(store.work_queue_index_path_for_target(SourcePackArtifactTarget::Wasm))
            .expect("read prepared work queue index"),
    )
    .expect("work queue index is utf8");
    assert!(
        !work_queue_index_json.contains("\"items\""),
        "prepared work queue index should not persist one summary per work item"
    );
    let first_work_item = store
        .load_work_queue_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load prepared first work item");
    assert!(
        first_work_item.dependent_item_indices.is_empty(),
        "prepared work queue should keep reverse dependents out of item pages"
    );
    assert!(
        first_work_item.dependent_item_count > 0,
        "prepared work queue should persist reverse dependent counts in item pages"
    );
    assert!(
        first_work_item.dependent_page_count > 0,
        "prepared work queue should persist reverse dependent page counts in item pages"
    );
    let first_dependent_page = store
        .load_work_queue_dependents_page_for_target(SourcePackArtifactTarget::Wasm, 0, 0)
        .expect("load prepared first dependent page");
    assert_eq!(
        first_dependent_page.dependent_count,
        first_dependent_page.dependent_item_indices.len()
    );
    for dependent_item_index in &first_dependent_page.dependent_item_indices {
        let dependent_work_item = store
            .load_work_queue_page_for_target(SourcePackArtifactTarget::Wasm, *dependent_item_index)
            .expect("load dependent work item");
        assert!(
            dependent_work_item.dependency_item_indices.is_empty(),
            "prepared work queue should keep dependencies out of item pages"
        );
        assert!(
            source_pack_work_queue_page_dependency_count(&dependent_work_item) > 0,
            "prepared work queue should persist dependency counts in item pages or range records"
        );
        assert!(
            dependent_work_item.dependency_page_count > 0
                || !dependent_work_item.dependency_item_ranges.is_empty(),
            "prepared work queue should persist dependency pages or compact dependency ranges"
        );
        let dependency_zero_in_page = if dependent_work_item.dependency_page_count > 0 {
            let dependency_page = store
                .load_work_queue_dependencies_page_for_target(
                    SourcePackArtifactTarget::Wasm,
                    *dependent_item_index,
                    0,
                )
                .expect("load dependent work item dependency page");
            dependency_page.dependency_item_indices.contains(&0)
        } else {
            false
        };
        let dependency_zero_in_range = dependent_work_item
            .dependency_item_ranges
            .iter()
            .any(|range| range.iter().is_some_and(|indices| indices.contains(&0)));
        assert!(
            dependency_zero_in_page || dependency_zero_in_range,
            "dependent work item {dependent_item_index} should reference first work item through dependency pages or range records"
        );
    }
    let work_queue_progress = store
        .load_work_queue_progress_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared work queue progress index");
    assert_eq!(
        work_queue_progress.work_item_count,
        prepared.work_queue_item_count
    );
    assert_eq!(work_queue_progress.first_ready_item_index, Some(0));
    assert_eq!(
        work_queue_progress.ready_item_count,
        prepared.initial_ready_work_item_count
    );
    let ready_progress_page = store
        .load_work_queue_progress_page_for_target(
            SourcePackArtifactTarget::Wasm,
            work_queue_progress
                .first_ready_item_index
                .expect("prepared work queue should have a ready item")
                / work_queue_progress.page_size,
        )
        .expect("load prepared ready work queue progress page");
    assert!(ready_progress_page.ready_item_indices.contains(&0));
    let final_work_item = store
        .load_work_queue_page_for_target(
            SourcePackArtifactTarget::Wasm,
            work_queue.final_item_index,
        )
        .expect("load prepared final work item");
    assert!(matches!(
        final_work_item.kind,
        SourcePackWorkQueueItemKind::LinkLeaf | SourcePackWorkQueueItemKind::LinkReduce
    ));
    let shard_index = store
        .load_build_artifact_shard_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared artifact shard index");
    assert_eq!(shard_index.target, SourcePackArtifactTarget::Wasm);
    assert_eq!(shard_index.job_batch_count, 5);
    assert_eq!(shard_index.shard_count(), prepared.artifact_shard_count);
    let shard_index_json = String::from_utf8(
        std::fs::read(store.artifact_shard_index_path_for_target(SourcePackArtifactTarget::Wasm))
            .expect("read prepared artifact shard index"),
    )
    .expect("artifact shard index is utf8");
    assert!(
        !shard_index_json.contains("\"shards\""),
        "prepared artifact shard index should leave shard records in shard pages"
    );
    let link_input_index = store
        .load_link_input_shard_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared link input shard index");
    let first_link_interface_shard_index = link_input_index
        .link_interface_shard_range
        .as_ref()
        .expect("prepared link input index should range-encode interface shards")
        .first_shard_index;
    assert!(
        link_input_index.link_object_shard_range.is_some(),
        "prepared link input index should range-encode object shards"
    );
    let first_link_input_shard = store
        .load_build_artifact_execution_shard_for_target(
            SourcePackArtifactTarget::Wasm,
            first_link_interface_shard_index,
        )
        .expect("load first prepared link input execution shard");
    assert_eq!(
        first_link_input_shard.shard.kind,
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches
    );
    assert!(
        first_link_input_shard.jobs.is_empty(),
        "link input shards should not duplicate the final link job"
    );
    assert!(
        first_link_input_shard.job_artifacts.is_empty(),
        "link input shards should keep refs in artifact pages and link batches"
    );
    assert_eq!(
        first_link_input_shard.artifact_refs.len(),
        first_link_input_shard.shard.input_artifact_indices.len()
    );
    assert_eq!(
        store
            .load_build_artifact_shard_for_target(SourcePackArtifactTarget::Wasm, 0)
            .expect("load first prepared artifact shard")
            .target,
        SourcePackArtifactTarget::Wasm
    );
    assert_eq!(
        store
            .load_build_artifact_execution_shard_for_target(SourcePackArtifactTarget::Wasm, 0)
            .expect("load first prepared artifact execution shard")
            .target,
        SourcePackArtifactTarget::Wasm
    );
    std::fs::write(
        store.artifact_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt artifact manifest");
    std::fs::write(
        store.hierarchical_link_plan_index_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt link plan index");
    assert_eq!(
        store
            .load_hierarchical_link_execution_page_for_target(
                SourcePackArtifactTarget::Wasm,
                link_execution_index.final_link_group_index,
            )
            .expect("load link execution page without manifest or plan"),
        final_link_execution
    );
    assert_eq!(
        store
            .load_build_job_batch_page_for_target(SourcePackArtifactTarget::Wasm, 0)
            .expect("load job-batch page without manifest or plan"),
        first_job_batch
    );
    assert_eq!(
        store
            .load_library_schedule_job_locator_page_for_target(
                SourcePackArtifactTarget::Wasm,
                app_codegen_job_index,
                job_locator_index.job_count,
            )
            .expect("load job locator without manifest or plan"),
        app_codegen_locator
    );
    assert_eq!(
        store
            .load_build_job_batch_job_locator_page_for_target(
                SourcePackArtifactTarget::Wasm,
                app_codegen_job_index,
                job_batch_index.scheduled_job_count,
            )
            .expect("load batch job locator without manifest or plan"),
        app_codegen_batch_locator
    );
    std::fs::write(
        store.library_schedule_page_path_for_target(SourcePackArtifactTarget::Wasm, 1),
        b"not json",
    )
    .expect("corrupt schedule page after prepare");
    assert_eq!(
        source_pack_stored_schedule_job(&store, &schedule_index, app_codegen_job_index)
            .expect("load stored schedule job from job page without schedule page"),
        app_codegen_job
    );
    assert_eq!(
        store
            .load_library_schedule_job_page_for_target(
                SourcePackArtifactTarget::Wasm,
                app_codegen_job_index,
                job_locator_index.job_count,
            )
            .expect("load schedule job page without schedule page"),
        app_codegen_job_page
    );
    assert_eq!(
        store
            .load_build_artifact_ref_index_for_target(SourcePackArtifactTarget::Wasm)
            .expect("load artifact-ref index without manifest or plan"),
        artifact_ref_index
    );
    assert_eq!(
        store
            .load_build_artifact_ref_page_for_target(
                SourcePackArtifactTarget::Wasm,
                app_codegen_job_index,
                artifact_ref_index.artifact_count,
            )
            .expect("load artifact-ref page without manifest or plan"),
        app_codegen_artifact_ref
    );
    assert_eq!(
        store
            .load_build_artifact_execution_shard_for_target(
                SourcePackArtifactTarget::Wasm,
                first_link_interface_shard_index,
            )
            .expect("load link input execution shard without manifest or plan"),
        first_link_input_shard
    );
    assert_eq!(
        store
            .load_build_link_interface_batch_page_for_target(SourcePackArtifactTarget::Wasm, 0)
            .expect("load link-interface batch page without manifest or plan"),
        first_link_interface_batch
    );
    assert_eq!(
        store
            .load_build_link_object_batch_page_for_target(SourcePackArtifactTarget::Wasm, 0)
            .expect("load link-object batch page without manifest or plan"),
        first_link_object_batch
    );

    std::fs::remove_dir_all(&root).expect("remove temp filesystem prepare dir");
}

#[test]
fn source_pack_build_link_batch_pages_cap_input_records() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-link-batch-page-cap-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let input_count = SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE + 1;
    let artifact_count = input_count + 1;
    let artifact_ref_index = SourcePackBuildArtifactRefIndex {
        version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
        target,
        artifact_count,
        interface_artifact_count: input_count,
        object_artifact_count: 0,
        final_output_artifact_index: artifact_count - 1,
        final_output_key: "wasm/linked-output/job-65/src-0-65".to_string(),
        total_source_file_count: input_count,
        total_source_byte_count: input_count,
        total_source_line_count: input_count,
    };
    store
        .store_build_artifact_ref_index(&artifact_ref_index)
        .expect("store artifact ref index");
    for artifact_index in 0..input_count {
        store
            .store_build_artifact_ref_page(
                &SourcePackBuildArtifactRefPage {
                    version: SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION,
                    target,
                    artifact_index,
                    artifact_ref: SourcePackArtifactRef {
                        artifact_index,
                        key: format!(
                            "wasm/library-interface/job-{artifact_index}/src-{artifact_index}"
                        ),
                        producing_job_index: artifact_index,
                        kind: SourcePackArtifactKind::LibraryInterface,
                    },
                    source_bytes: 1,
                    source_file_count: 1,
                    source_lines: 1,
                },
                artifact_count,
            )
            .expect("store artifact ref page");
    }
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: input_count,
        max_source_bytes_per_batch: usize::MAX,
        max_source_files_per_batch: usize::MAX,
    };

    let batch_count =
        store_source_pack_build_link_interface_batch_pages_from_stored_artifact_ref_pages(
            &store,
            target,
            &artifact_ref_index,
            0..input_count,
            batch_limits,
        )
        .expect("store capped link-interface batch pages");

    assert_eq!(batch_count, 2);
    assert_eq!(
        store
            .load_build_link_interface_batch_page_for_target(target, 0)
            .expect("load first link-interface batch page")
            .batch
            .input_interface_artifact_indices
            .len(),
        SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
    );
    assert_eq!(
        store
            .load_build_link_interface_batch_page_for_target(target, 1)
            .expect("load second link-interface batch page")
            .batch
            .input_interface_artifact_indices,
        vec![SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE]
    );
    let oversize_object_page = SourcePackBuildLinkObjectBatchPage {
        version: SOURCE_PACK_BUILD_LINK_OBJECT_BATCH_PAGE_VERSION,
        target,
        batch_index: 0,
        batch: SourcePackLinkObjectBatch {
            batch_index: 0,
            input_object_artifact_indices: (0..input_count).collect(),
            source_bytes: input_count,
            source_file_count: input_count,
            source_lines: input_count,
        },
    };
    let err = store
        .store_build_link_object_batch_page(&oversize_object_page)
        .expect_err("oversized link-object batch pages must be rejected");
    assert!(
        format!("{err:?}").contains("page limit"),
        "unexpected oversize error: {err:?}"
    );

    std::fs::remove_dir_all(&root).expect("remove temp link batch page cap dir");
}

#[test]
fn ordered_explicit_source_libraries_filesystem_artifact_prepare_streams_in_dependency_order() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-ordered-filesystem-artifact-prepare-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    let cli_path = source_root.join("cli.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, [0xff, 0xfe, 0xfd, b'!']).expect("write invalid utf8 app source");
    std::fs::write(&cli_path, b"cli!!").expect("write cli source");

    let prepared = prepare_ordered_explicit_source_libraries_filesystem_artifact_build_for_target(
        [
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            },
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path],
                dependency_library_ids: vec![10],
            },
            ExplicitSourceLibraryPaths {
                library_id: 30,
                paths: vec![cli_path],
                dependency_library_ids: vec![20],
            },
        ],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 8,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare ordered filesystem artifact build from metadata only");

    assert_eq!(prepared.target, SourcePackArtifactTarget::Wasm);
    assert_eq!(prepared.source_file_count, 3);
    assert_eq!(prepared.source_byte_count, 13);
    assert_eq!(prepared.library_count, 3);
    assert_eq!(prepared.library_partition_count, 3);
    assert_eq!(prepared.library_schedule_page_count, 3);

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let schedule = store
        .load_library_schedule_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load ordered schedule index");
    assert_eq!(schedule.partition_count, 3);
    assert_stored_schedule_index_has_no_inline_entries(&store, SourcePackArtifactTarget::Wasm);
    for (partition_index, expected_dependency_jobs) in
        [(0usize, vec![]), (1, vec![0]), (2, vec![1])]
    {
        let page = store
            .load_library_schedule_page_for_target(SourcePackArtifactTarget::Wasm, partition_index)
            .expect("load ordered schedule page");
        assert!(
            page.frontend_job.dependency_job_indices.is_empty(),
            "ordered prepare should persist frontend dependency jobs in per-job dependency pages"
        );
        let frontend_job =
            source_pack_stored_schedule_job(&store, &schedule, page.frontend_job_index)
                .expect("load ordered frontend job from dependency pages");
        assert_eq!(
            frontend_job.dependency_job_indices,
            expected_dependency_jobs
        );
    }
    let app_link_group = store
        .load_hierarchical_link_group_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load ordered app link group");
    assert!(app_link_group.input_frontend_job_indices.is_empty());
    assert_eq!(app_link_group.input_frontend_job_count, 2);
    let cli_link_group = store
        .load_hierarchical_link_group_page_for_target(SourcePackArtifactTarget::Wasm, 2)
        .expect("load ordered cli link group");
    assert!(cli_link_group.input_frontend_job_indices.is_empty());
    assert_eq!(cli_link_group.input_frontend_job_count, 2);
    let path_manifest = store
        .load_path_build_manifest_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load compact ordered path manifest");
    assert!(path_manifest.source_files.is_empty());
    assert!(
        path_manifest.library_dependencies.is_empty(),
        "compact path build manifest should leave library dependency edges in stored schedule job pages"
    );

    std::fs::remove_dir_all(&root).expect("remove temp ordered filesystem prepare dir");
}

#[test]
fn ordered_explicit_source_libraries_filesystem_artifact_build_entrypoint_streams() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-ordered-filesystem-artifact-entrypoint-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let result = execute_ordered_explicit_source_libraries_filesystem_artifact_build(
        [
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            },
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path],
                dependency_library_ids: vec![10],
            },
        ],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 8,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
        &mut executor,
    )
    .expect("execute ordered filesystem artifact-store entrypoint");

    assert_eq!(result.linked_output_key, "linked-output/job-4/src-0-2");
    assert_eq!(
        std::fs::read(&result.linked_output_path).expect("read linked output"),
        b"linked:2:2"
    );
    assert_eq!(
        executor.events,
        vec![
            "frontend:10:1:0",
            "frontend:20:1:1",
            "codegen:10:0..1:1:0",
            "codegen:20:1..2:1:1",
            "begin-link:4",
            "link-interfaces:0:1",
            "link-interfaces:1:1",
            "link-objects:0:1",
            "link-objects:1:1",
            "finish-link:4:2:2",
        ]
    );

    let stored_path_manifest = SourcePackFilesystemArtifactStore::new(&artifact_root)
        .load_path_build_manifest()
        .expect("load ordered source-pack path build manifest");
    assert!(stored_path_manifest.source_files.is_empty());
    assert!(stored_path_manifest.library_dependencies.is_empty());

    std::fs::remove_dir_all(&root).expect("remove temp ordered filesystem entrypoint dir");
}

#[test]
fn ordered_explicit_source_library_path_streams_filesystem_artifact_build_entrypoint_streams() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-ordered-path-stream-artifact-entrypoint-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let result = execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build(
        [
            ExplicitSourceLibraryPathStream {
                library_id: 10,
                source_file_count: 1,
                paths: std::iter::once(core_path),
                dependency_library_ids: Vec::new(),
            },
            ExplicitSourceLibraryPathStream {
                library_id: 20,
                source_file_count: 1,
                paths: std::iter::once(app_path),
                dependency_library_ids: vec![10],
            },
        ],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 8,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
        &mut executor,
    )
    .expect("execute ordered path-stream filesystem artifact-store entrypoint");

    assert_eq!(result.linked_output_key, "linked-output/job-4/src-0-2");
    assert_eq!(
        std::fs::read(&result.linked_output_path).expect("read linked output"),
        b"linked:2:2"
    );
    assert_eq!(
        executor.events,
        vec![
            "frontend:10:1:0",
            "frontend:20:1:1",
            "codegen:10:0..1:1:0",
            "codegen:20:1..2:1:1",
            "begin-link:4",
            "link-interfaces:0:1",
            "link-interfaces:1:1",
            "link-objects:0:1",
            "link-objects:1:1",
            "finish-link:4:2:2",
        ]
    );

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let stored_path_manifest = store
        .load_path_build_manifest()
        .expect("load ordered path-stream source-pack path build manifest");
    assert!(stored_path_manifest.source_files.is_empty());
    assert!(stored_path_manifest.library_dependencies.is_empty());
    let first_record = store
        .load_library_source_file_record_page_for_target(SourcePackArtifactTarget::Generic, 0)
        .expect("load first path-stream source-file record");
    assert_eq!(first_record.source_file_count, 1);
    assert_eq!(first_record.source_index, 0);

    std::fs::remove_dir_all(&root).expect("remove temp ordered path-stream entrypoint dir");
}

#[test]
fn ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_entrypoint_streams()
 {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-ordered-path-dependency-stream-artifact-entrypoint-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let result =
        execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build(
            [
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 10,
                    source_file_count: 1,
                    paths: std::iter::once(core_path),
                    dependency_library_count: 0,
                    dependency_library_ids: Vec::<u32>::new().into_iter(),
                },
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 20,
                    source_file_count: 1,
                    paths: std::iter::once(app_path),
                    dependency_library_count: 1,
                    dependency_library_ids: vec![10].into_iter(),
                },
            ],
            &artifact_root,
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 8,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
            &mut executor,
        )
        .expect("execute ordered path+dependency stream filesystem artifact-store entrypoint");

    assert_eq!(result.linked_output_key, "linked-output/job-4/src-0-2");
    assert_eq!(
        std::fs::read(&result.linked_output_path).expect("read linked output"),
        b"linked:2:2"
    );
    assert_eq!(
        executor.events,
        vec![
            "frontend:10:1:0",
            "frontend:20:1:1",
            "codegen:10:0..1:1:0",
            "codegen:20:1..2:1:1",
            "begin-link:4",
            "link-interfaces:0:1",
            "link-interfaces:1:1",
            "link-objects:0:1",
            "link-objects:1:1",
            "finish-link:4:2:2",
        ]
    );

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let app_partition = store
        .load_library_partition_for_target(SourcePackArtifactTarget::Generic, 1)
        .expect("load path+dependency stream app partition");
    assert!(app_partition.dependency_library_ids.is_empty());
    assert_eq!(app_partition.dependency_library_count, 1);
    assert_eq!(app_partition.dependency_page_count, 1);
    let app_dependency_page = store
        .load_library_dependency_page_for_target(SourcePackArtifactTarget::Generic, 1, 0)
        .expect("load path+dependency stream app dependency page");
    assert_eq!(app_dependency_page.dependency_library_ids, vec![10]);

    std::fs::remove_dir_all(&root)
        .expect("remove temp ordered path+dependency stream entrypoint dir");
}

#[test]
fn explicit_source_pack_paths_filesystem_metadata_prepare_streams_path_slices() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-pack-paths-filesystem-metadata-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let stdlib_path = source_root.join("stdlib.lani");
    let user_path = source_root.join("user.lani");
    std::fs::write(&stdlib_path, b"core").expect("write stdlib source");
    std::fs::write(&user_path, b"user").expect("write user source");

    let prepared = prepare_explicit_source_pack_paths_filesystem_metadata_for_target(
        &[stdlib_path],
        &[user_path],
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare stdlib/user filesystem metadata from path slices");

    assert_eq!(prepared.target, SourcePackArtifactTarget::Wasm);
    assert_eq!(prepared.source_file_count, 2);
    assert_eq!(prepared.source_byte_count, 8);
    assert_eq!(prepared.library_count, 2);
    assert_eq!(prepared.library_partition_count, 2);
    assert_eq!(prepared.library_source_file_page_count, 2);

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let partition_index = store
        .load_library_partition_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load stdlib/user metadata partition index");
    assert_eq!(partition_index.partition_count, 2);
    assert_stored_partition_index_has_no_inline_partitions(&store, SourcePackArtifactTarget::Wasm);
    let user_partition = store
        .load_library_partition_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load user metadata partition");
    assert_eq!(user_partition.library_id, 1);
    assert!(user_partition.dependency_library_ids.is_empty());
    assert_eq!(user_partition.dependency_library_count, 1);
    assert_eq!(user_partition.dependency_page_count, 1);
    let dependency_page = store
        .load_library_dependency_page_for_target(SourcePackArtifactTarget::Wasm, 1, 0)
        .expect("load user metadata dependency page");
    assert_eq!(dependency_page.dependency_library_ids, vec![0]);
    let user_source_page = store
        .load_library_source_file_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load user metadata source-file page");
    assert!(user_source_page.source_files.is_empty());
    let user_record = store
        .load_library_source_file_record_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load user metadata source-file record");
    assert_eq!(user_record.library_id, 1);
    assert_eq!(user_record.source_index, 1);
    assert_eq!(user_record.file.byte_len, 4);
    assert!(
        !store
            .library_schedule_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .exists(),
        "metadata-only path-slice prepare must not create a schedule index"
    );

    std::fs::remove_dir_all(&root).expect("remove temp pack paths filesystem metadata dir");
}

#[test]
fn source_pack_metadata_prepare_resumes_completed_library_prefix_without_paths() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-metadata-prefix-resume-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
        [ExplicitSourceLibraryPathDependencyStream {
            library_id: 10,
            source_file_count: 1,
            paths: std::iter::once(core_path.as_path()),
            dependency_library_count: 0,
            dependency_library_ids: Vec::<u32>::new().into_iter(),
        }],
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare first library metadata prefix");
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    std::fs::remove_file(
        store.library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm),
    )
    .expect("remove compact metadata index to simulate interrupted metadata phase");
    std::fs::remove_file(&core_path).expect("remove completed prefix source");

    let resumed = prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
            [
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 10,
                    source_file_count: 1,
                    paths: std::iter::once(core_path.as_path()),
                    dependency_library_count: 0,
                    dependency_library_ids: Vec::<u32>::new().into_iter(),
                },
                ExplicitSourceLibraryPathDependencyStream {
                    library_id: 20,
                    source_file_count: 1,
                    paths: std::iter::once(app_path.as_path()),
                    dependency_library_count: 1,
                    dependency_library_ids: vec![10].into_iter(),
                },
            ],
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
        )
        .expect("resume metadata from stored completed library prefix");

    assert_eq!(resumed.source_file_count, 2);
    assert_eq!(resumed.source_byte_count, 8);
    assert_eq!(resumed.library_partition_count, 2);
    let partition_index = store
        .load_library_partition_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load resumed compact metadata index");
    assert_eq!(partition_index.partition_count, 2);
    let app_partition = store
        .load_library_partition_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load resumed app partition");
    assert_eq!(app_partition.library_id, 20);
    assert_eq!(
        source_pack_load_library_dependency_ids(&store, &app_partition)
            .expect("load resumed app dependencies"),
        vec![10]
    );

    std::fs::remove_dir_all(&root).expect("remove temp metadata prefix resume dir");
}

#[test]
fn source_pack_metadata_chunk_prepares_bounded_new_libraries() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-metadata-chunk-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    let cli_path = source_root.join("cli.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");
    std::fs::write(&cli_path, b"cli!").expect("write cli source");

    let first =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_for_target(
                [
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 10,
                        source_file_count: 1,
                        paths: std::iter::once(core_path.as_path()),
                        dependency_library_count: 0,
                        dependency_library_ids: Vec::<u32>::new().into_iter(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 20,
                        source_file_count: 1,
                        paths: std::iter::once(app_path.as_path()),
                        dependency_library_count: 1,
                        dependency_library_ids: vec![10].into_iter(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 30,
                        source_file_count: 1,
                        paths: std::iter::once(cli_path.as_path()),
                        dependency_library_count: 1,
                        dependency_library_ids: vec![20].into_iter(),
                    },
                ],
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                1,
            )
            .expect("prepare first metadata chunk");
    assert!(!first.complete);
    assert_eq!(first.new_library_count, 1);
    assert_eq!(first.library_partition_count, 1);
    assert!(first.library_partition_index_path.is_none());
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    assert!(
        !store
            .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );
    std::fs::remove_file(&core_path).expect("remove first chunk source");

    let second =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_for_target(
                [
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 10,
                        source_file_count: 1,
                        paths: std::iter::once(core_path.as_path()),
                        dependency_library_count: 0,
                        dependency_library_ids: Vec::<u32>::new().into_iter(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 20,
                        source_file_count: 1,
                        paths: std::iter::once(app_path.as_path()),
                        dependency_library_count: 1,
                        dependency_library_ids: vec![10].into_iter(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 30,
                        source_file_count: 1,
                        paths: std::iter::once(cli_path.as_path()),
                        dependency_library_count: 1,
                        dependency_library_ids: vec![20].into_iter(),
                    },
                ],
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                1,
            )
            .expect("prepare second metadata chunk");
    assert!(!second.complete);
    assert_eq!(second.new_library_count, 1);
    assert_eq!(second.library_partition_count, 2);
    assert_eq!(second.source_file_count, 2);
    std::fs::remove_file(&app_path).expect("remove second chunk source");

    let final_chunk =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_for_target(
                [
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 10,
                        source_file_count: 1,
                        paths: std::iter::once(core_path.as_path()),
                        dependency_library_count: 0,
                        dependency_library_ids: Vec::<u32>::new().into_iter(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 20,
                        source_file_count: 1,
                        paths: std::iter::once(app_path.as_path()),
                        dependency_library_count: 1,
                        dependency_library_ids: vec![10].into_iter(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 30,
                        source_file_count: 1,
                        paths: std::iter::once(cli_path.as_path()),
                        dependency_library_count: 1,
                        dependency_library_ids: vec![20].into_iter(),
                    },
                ],
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                1,
            )
            .expect("prepare final metadata chunk");
    assert!(final_chunk.complete);
    assert_eq!(final_chunk.new_library_count, 1);
    assert_eq!(final_chunk.library_partition_count, 3);
    assert!(final_chunk.library_partition_index_path.is_some());
    let partition_index = store
        .load_library_partition_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load final metadata chunk compact index");
    assert_eq!(partition_index.partition_count, 3);
    assert_eq!(partition_index.source_file_count, 3);

    std::fs::remove_dir_all(&root).expect("remove temp metadata chunk dir");
}

#[test]
fn source_pack_metadata_chunk_public_apis_cap_oversized_library_limit() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-metadata-chunk-cap-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let direct_artifact_root = root.join("direct-artifacts");
    let progress_artifact_root = root.join("progress-artifacts");
    let full_artifact_root = root.join("full-artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let capped_library_count = SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_CHUNK_LIMIT;
    let mut source_paths = Vec::with_capacity(capped_library_count);
    for index in 0..capped_library_count {
        let source_path = source_root.join(format!("library-{index}.lani"));
        std::fs::write(&source_path, format!("library {index}\n")).expect("write capped source");
        source_paths.push(source_path);
    }
    let missing_path = source_root.join("library-over-cap.lani");
    let make_libraries =
        || -> Vec<ExplicitSourceLibraryPathDependencyStream<Vec<PathBuf>, Vec<u32>>> {
            (0..=capped_library_count)
                .map(|index| {
                    let path = if index < capped_library_count {
                        source_paths[index].clone()
                    } else {
                        missing_path.clone()
                    };
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: (index + 1) as u32,
                        source_file_count: 1,
                        paths: vec![path],
                        dependency_library_count: 0,
                        dependency_library_ids: Vec::<u32>::new(),
                    }
                })
                .collect()
        };
    let assert_capped_metadata_step =
        |store: &SourcePackFilesystemArtifactStore,
         step: &SourcePackFilesystemLibraryMetadataPrepareStepResult| {
            assert!(!step.complete);
            assert_eq!(step.new_library_count, capped_library_count);
            assert_eq!(step.library_partition_count, capped_library_count);
            assert_eq!(step.library_source_file_page_count, capped_library_count);
            assert_eq!(step.source_file_count, capped_library_count);
            assert!(step.library_partition_index_path.is_none());
            assert!(
                !store
                    .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
                    .is_file()
            );
            assert!(
                store
                    .library_partition_path_for_target(
                        SourcePackArtifactTarget::Wasm,
                        capped_library_count - 1,
                    )
                    .is_file()
            );
            assert!(
                !store
                    .library_partition_path_for_target(
                        SourcePackArtifactTarget::Wasm,
                        capped_library_count,
                    )
                    .is_file()
            );
            assert!(
                store
                    .library_source_file_page_path_for_target(
                        SourcePackArtifactTarget::Wasm,
                        capped_library_count - 1,
                    )
                    .is_file()
            );
            assert!(
                !store
                    .library_source_file_page_path_for_target(
                        SourcePackArtifactTarget::Wasm,
                        capped_library_count,
                    )
                    .is_file()
            );
        };

    let direct =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_for_target(
                make_libraries(),
                &direct_artifact_root,
                SourcePackArtifactTarget::Wasm,
                usize::MAX,
            )
            .expect("direct metadata chunk caps oversized caller limit before statting later paths");
    let direct_store = SourcePackFilesystemArtifactStore::new(&direct_artifact_root);
    assert_capped_metadata_step(&direct_store, &direct);

    let progress =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_from_progress_for_target(
                make_libraries(),
                &progress_artifact_root,
                SourcePackArtifactTarget::Wasm,
                usize::MAX,
                true,
            )
            .expect("progress metadata chunk caps oversized caller limit before statting later paths");
    let progress_store = SourcePackFilesystemArtifactStore::new(&progress_artifact_root);
    assert_capped_metadata_step(&progress_store, &progress);

    let full_err =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
                make_libraries(),
                &full_artifact_root,
                SourcePackArtifactTarget::Wasm,
            )
            .expect_err("full metadata convenience API must stop after its bounded library window");
    assert!(
        full_err
            .to_string()
            .contains("source-pack metadata prepare did not complete within"),
        "unexpected full metadata cap error: {full_err}"
    );
    let full_store = SourcePackFilesystemArtifactStore::new(&full_artifact_root);
    assert!(
        !full_store
            .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );
    assert!(
        full_store
            .library_partition_path_for_target(
                SourcePackArtifactTarget::Wasm,
                capped_library_count - 1,
            )
            .is_file()
    );
    assert!(
            !full_store
                .library_partition_path_for_target(
                    SourcePackArtifactTarget::Wasm,
                    capped_library_count,
                )
                .is_file()
        );

    std::fs::remove_dir_all(&root).expect("remove temp metadata chunk cap dir");
}

#[test]
fn source_pack_metadata_chunk_public_apis_reject_oversized_single_library_before_paths() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-metadata-chunk-source-cap-test-{}-{suffix}",
        std::process::id()
    ));
    let direct_artifact_root = root.join("direct-artifacts");
    let progress_artifact_root = root.join("progress-artifacts");
    std::fs::create_dir_all(&root).expect("create temp metadata chunk source cap dir");

    let oversized_source_file_count =
        SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_SOURCE_FILE_LIMIT + 1;
    let missing_path = root.join("missing-source.lani");
    let make_libraries =
        || -> Vec<ExplicitSourceLibraryPathDependencyStream<Vec<PathBuf>, Vec<u32>>> {
            vec![ExplicitSourceLibraryPathDependencyStream {
                library_id: 99,
                source_file_count: oversized_source_file_count,
                paths: vec![missing_path.clone()],
                dependency_library_count: 1,
                dependency_library_ids: vec![1],
            }]
        };
    let assert_rejected_before_records = |artifact_root: &Path, err: CompileError, label: &str| {
        let message = err.to_string();
        assert!(
            message.contains("exceeding chunk source-file cap") && message.contains("library 99"),
            "unexpected {label} metadata source-file cap error: {message}"
        );
        assert!(
            !message.contains("stat explicit"),
            "{label} metadata cap must reject before statting source paths: {message}"
        );
        let store = SourcePackFilesystemArtifactStore::new(artifact_root);
        assert!(
            !store
                .library_dependency_page_path_for_target(SourcePackArtifactTarget::Wasm, 0, 0,)
                .is_file(),
            "{label} metadata cap must reject before writing dependency pages"
        );
        assert!(
            !store
                .library_source_file_record_page_path_for_target(SourcePackArtifactTarget::Wasm, 0,)
                .is_file(),
            "{label} metadata cap must reject before writing source-file records"
        );
        assert!(
            !store
                .library_partition_path_for_target(SourcePackArtifactTarget::Wasm, 0)
                .is_file(),
            "{label} metadata cap must reject before writing partition pages"
        );
    };

    let direct_err =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_for_target(
                make_libraries(),
                &direct_artifact_root,
                SourcePackArtifactTarget::Wasm,
                usize::MAX,
            )
            .expect_err("direct metadata chunk must reject oversized single-library source count");
    assert_rejected_before_records(&direct_artifact_root, direct_err, "direct");

    let progress_err =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_from_progress_for_target(
                make_libraries(),
                &progress_artifact_root,
                SourcePackArtifactTarget::Wasm,
                usize::MAX,
                true,
            )
            .expect_err("progress metadata chunk must reject oversized single-library source count");
    assert_rejected_before_records(&progress_artifact_root, progress_err, "progress");

    std::fs::remove_dir_all(&root).expect("remove temp metadata source cap dir");
}

#[test]
fn source_pack_metadata_chunk_public_apis_reject_oversized_dependency_fan_in_before_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-metadata-chunk-dependency-cap-test-{}-{suffix}",
        std::process::id()
    ));
    let direct_artifact_root = root.join("direct-artifacts");
    let progress_artifact_root = root.join("progress-artifacts");
    std::fs::create_dir_all(&root).expect("create temp metadata chunk dependency cap dir");

    let oversized_dependency_count =
        SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_DEPENDENCY_LIMIT + 1;
    let missing_path = root.join("missing-source.lani");
    let make_libraries =
        || -> Vec<ExplicitSourceLibraryPathDependencyStream<Vec<PathBuf>, Vec<u32>>> {
            vec![ExplicitSourceLibraryPathDependencyStream {
                library_id: 99,
                source_file_count: 1,
                paths: vec![missing_path.clone()],
                dependency_library_count: oversized_dependency_count,
                dependency_library_ids: vec![1],
            }]
        };
    let assert_rejected_before_records = |artifact_root: &Path, err: CompileError, label: &str| {
        let message = err.to_string();
        assert!(
            message.contains("exceeding chunk dependency cap") && message.contains("library 99"),
            "unexpected {label} metadata dependency cap error: {message}"
        );
        assert!(
            !message.contains("depends on missing")
                && !message.contains("received")
                && !message.contains("stat explicit"),
            "{label} metadata dependency cap must reject before dependency/path scans: {message}"
        );
        let store = SourcePackFilesystemArtifactStore::new(artifact_root);
        assert!(
            !store
                .library_dependency_page_path_for_target(SourcePackArtifactTarget::Wasm, 0, 0,)
                .is_file(),
            "{label} metadata dependency cap must reject before writing dependency pages"
        );
        assert!(
            !store
                .library_source_file_record_page_path_for_target(SourcePackArtifactTarget::Wasm, 0,)
                .is_file(),
            "{label} metadata dependency cap must reject before writing source-file records"
        );
        assert!(
            !store
                .library_partition_path_for_target(SourcePackArtifactTarget::Wasm, 0)
                .is_file(),
            "{label} metadata dependency cap must reject before writing partition pages"
        );
    };

    let direct_err =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_for_target(
                make_libraries(),
                &direct_artifact_root,
                SourcePackArtifactTarget::Wasm,
                usize::MAX,
            )
            .expect_err("direct metadata chunk must reject oversized dependency fan-in");
    assert_rejected_before_records(&direct_artifact_root, direct_err, "direct");

    let progress_err =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_from_progress_for_target(
                make_libraries(),
                &progress_artifact_root,
                SourcePackArtifactTarget::Wasm,
                usize::MAX,
                true,
            )
            .expect_err("progress metadata chunk must reject oversized dependency fan-in");
    assert_rejected_before_records(&progress_artifact_root, progress_err, "progress");

    std::fs::remove_dir_all(&root).expect("remove temp metadata dependency cap dir");
}

#[test]
fn source_pack_metadata_chunk_rejects_changed_resumed_dependencies() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-metadata-changed-deps-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let alt_path = source_root.join("alt.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&alt_path, b"alt!").expect("write alt source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let first =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_for_target(
                [
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 10,
                        source_file_count: 1,
                        paths: std::iter::once(core_path.as_path()),
                        dependency_library_count: 0,
                        dependency_library_ids: Vec::<u32>::new().into_iter(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 20,
                        source_file_count: 1,
                        paths: std::iter::once(alt_path.as_path()),
                        dependency_library_count: 0,
                        dependency_library_ids: Vec::<u32>::new().into_iter(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 30,
                        source_file_count: 1,
                        paths: std::iter::once(app_path.as_path()),
                        dependency_library_count: 1,
                        dependency_library_ids: vec![10].into_iter(),
                    },
                ],
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                3,
            )
            .expect("prepare complete metadata before removing compact marker");
    assert!(first.complete);
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    std::fs::remove_file(
        store.library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm),
    )
    .expect("remove compact metadata index to simulate interrupted metadata phase");

    let err =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_for_target(
                [
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 10,
                        source_file_count: 1,
                        paths: std::iter::once(core_path.as_path()),
                        dependency_library_count: 0,
                        dependency_library_ids: Vec::<u32>::new().into_iter(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 20,
                        source_file_count: 1,
                        paths: std::iter::once(alt_path.as_path()),
                        dependency_library_count: 0,
                        dependency_library_ids: Vec::<u32>::new().into_iter(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 30,
                        source_file_count: 1,
                        paths: std::iter::once(app_path.as_path()),
                        dependency_library_count: 1,
                        dependency_library_ids: vec![20].into_iter(),
                    },
                ],
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                1,
            )
            .expect_err("resumed metadata must reject changed dependency ids");
    assert!(
        err.to_string().contains("stored dependency 10")
            && err.to_string().contains("manifest declares 20")
    );
    assert!(
        !store
            .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );

    std::fs::remove_dir_all(&root).expect("remove temp metadata changed-deps dir");
}

#[test]
fn source_pack_artifact_prepare_resumes_from_persisted_metadata_without_paths() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-artifact-from-metadata-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let metadata =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
                [
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 10,
                        source_file_count: 1,
                        paths: std::iter::once(core_path.as_path()),
                        dependency_library_count: 0,
                        dependency_library_ids: Vec::<u32>::new().into_iter(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 20,
                        source_file_count: 1,
                        paths: std::iter::once(app_path.as_path()),
                        dependency_library_count: 1,
                        dependency_library_ids: vec![10].into_iter(),
                    },
                ],
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
            )
            .expect("prepare persisted source-pack metadata");
    assert_eq!(metadata.source_file_count, 2);
    assert_eq!(metadata.library_partition_count, 2);

    std::fs::remove_file(&core_path).expect("remove core source after metadata");
    std::fs::remove_file(&app_path).expect("remove app source after metadata");

    let prepared =
        prepare_source_pack_filesystem_artifact_build_from_metadata_with_shard_limits_for_target(
            &artifact_root,
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 8,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
            SourcePackBuildShardLimits {
                max_batches_per_shard: 2,
                max_jobs_per_shard: 2,
                max_artifacts_per_shard: 2,
            },
            SourcePackArtifactTarget::Wasm,
        )
        .expect("prepare artifacts from persisted metadata after source paths are gone");

    assert_eq!(prepared.target, SourcePackArtifactTarget::Wasm);
    assert_eq!(prepared.source_file_count, metadata.source_file_count);
    assert_eq!(prepared.source_byte_count, metadata.source_byte_count);
    assert_eq!(prepared.source_line_count, metadata.source_line_count);
    assert_eq!(prepared.library_count, metadata.library_count);
    assert_eq!(
        prepared.library_partition_count,
        metadata.library_partition_count
    );
    assert_eq!(
        prepared.library_source_file_page_count,
        metadata.library_source_file_page_count
    );
    assert_eq!(prepared.library_build_unit_page_count, 2);
    assert_eq!(prepared.library_schedule_page_count, 2);
    assert_eq!(prepared.scheduled_job_count, 5);
    assert_eq!(prepared.artifact_count, 5);
    assert_eq!(prepared.work_queue_item_count, 7);
    assert_eq!(prepared.initial_ready_work_item_count, 1);
    assert!(prepared.artifact_shard_count >= 3);

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    assert_stored_schedule_index_has_no_inline_entries(&store, SourcePackArtifactTarget::Wasm);
    let schedule = store
        .load_library_schedule_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load schedule from metadata-derived artifact prepare");
    assert_eq!(schedule.partition_count, 2);
    let app_frontend = source_pack_stored_schedule_job(&store, &schedule, 1)
        .expect("load app frontend job from persisted dependencies");
    assert_eq!(app_frontend.dependency_job_indices, vec![0]);

    std::fs::remove_dir_all(&root).expect("remove temp artifact-from-metadata test dir");
}

#[test]
fn source_pack_artifact_build_from_metadata_chunk_orchestrates_persisted_stages_without_paths() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-artifact-build-from-metadata-chunk-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let metadata =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
                [
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 10,
                        source_file_count: 1,
                        paths: std::iter::once(core_path.as_path()),
                        dependency_library_count: 0,
                        dependency_library_ids: Vec::<u32>::new().into_iter(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 20,
                        source_file_count: 1,
                        paths: std::iter::once(app_path.as_path()),
                        dependency_library_count: 1,
                        dependency_library_ids: vec![10].into_iter(),
                    },
                ],
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
            )
            .expect("prepare persisted metadata for top-level artifact chunks");
    std::fs::remove_file(&core_path).expect("remove core source after metadata");
    std::fs::remove_file(&app_path).expect("remove app source after metadata");

    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 1,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };
    let shard_limits = SourcePackBuildShardLimits {
        max_batches_per_shard: 1,
        max_jobs_per_shard: 1,
        max_artifacts_per_shard: 1,
    };
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let first =
            prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target(
                &artifact_root,
                limits,
                batch_limits,
                shard_limits,
                SourcePackArtifactTarget::Wasm,
                1,
            )
            .expect("prepare first top-level artifact chunk");
    assert!(!first.complete);
    assert_eq!(
        first.stage,
        SourcePackFilesystemArtifactBuildPrepareStage::LibrarySchedule
    );
    assert_eq!(first.new_item_count, 1);
    assert!(
        !store
            .library_schedule_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );

    let mut stages = vec![first.stage];
    let mut prepared = None;
    for _ in 0..128 {
        let step =
                prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target(
                    &artifact_root,
                    limits,
                    batch_limits,
                    shard_limits,
                    SourcePackArtifactTarget::Wasm,
                    1,
                )
                .expect("resume top-level artifact chunk");
        stages.push(step.stage);
        if step.stage == SourcePackFilesystemArtifactBuildPrepareStage::BuildManifests {
            assert!(
                store
                    .build_manifest_path_for_target(SourcePackArtifactTarget::Wasm)
                    .is_file()
            );
            assert!(
                store
                    .artifact_manifest_path_for_target(SourcePackArtifactTarget::Wasm)
                    .is_file()
            );
            assert!(
                !store
                    .build_state_path_for_target(SourcePackArtifactTarget::Wasm)
                    .is_file()
            );
        }
        if step.complete {
            prepared = step.prepared;
            break;
        }
    }
    let prepared = prepared.expect("top-level artifact chunks should complete");
    assert_eq!(prepared.target, SourcePackArtifactTarget::Wasm);
    assert_eq!(prepared.source_file_count, metadata.source_file_count);
    assert_eq!(prepared.source_byte_count, metadata.source_byte_count);
    assert_eq!(prepared.library_count, metadata.library_count);
    assert_eq!(
        prepared.library_partition_count,
        metadata.library_partition_count
    );
    assert!(prepared.artifact_shard_count > 0);
    assert_eq!(prepared.work_queue_progress_page_count, 1);
    assert!(
        store
            .build_state_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );
    for expected in [
        SourcePackFilesystemArtifactBuildPrepareStage::LibrarySchedule,
        SourcePackFilesystemArtifactBuildPrepareStage::ArtifactRefs,
        SourcePackFilesystemArtifactBuildPrepareStage::JobBatches,
        SourcePackFilesystemArtifactBuildPrepareStage::LinkBatches,
        SourcePackFilesystemArtifactBuildPrepareStage::JobBatchDependents,
        SourcePackFilesystemArtifactBuildPrepareStage::ArtifactShards,
        SourcePackFilesystemArtifactBuildPrepareStage::HierarchicalLinkLeafGroups,
        SourcePackFilesystemArtifactBuildPrepareStage::HierarchicalLinkPlanReduceGroups,
        SourcePackFilesystemArtifactBuildPrepareStage::HierarchicalLinkExecution,
        SourcePackFilesystemArtifactBuildPrepareStage::WorkQueuePages,
        SourcePackFilesystemArtifactBuildPrepareStage::WorkQueueProgress,
        SourcePackFilesystemArtifactBuildPrepareStage::BuildManifests,
        SourcePackFilesystemArtifactBuildPrepareStage::BuildState,
    ] {
        assert!(
            stages.contains(&expected),
            "top-level artifact chunks did not visit {expected:?}; visited {stages:?}"
        );
    }

    let already_complete =
            prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target(
                &artifact_root,
                limits,
                batch_limits,
                shard_limits,
                SourcePackArtifactTarget::Wasm,
                1,
            )
            .expect("completed top-level artifact chunk should reopen prepared result");
    assert!(already_complete.complete);
    assert_eq!(
        already_complete.stage,
        SourcePackFilesystemArtifactBuildPrepareStage::Complete
    );
    assert_eq!(already_complete.new_item_count, 0);
    assert!(already_complete.prepared.is_some());

    std::fs::remove_dir_all(&root).expect("remove temp top-level artifact chunk dir");
}

#[test]
fn source_pack_artifact_build_from_metadata_chunk_caps_oversized_item_limit() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-artifact-build-chunk-cap-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create source root");

    let library_count = SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT + 1;
    let mut libraries = Vec::with_capacity(library_count);
    for library_index in 0..library_count {
        let library_id = (library_index + 1) as u32;
        let source_path = source_root.join(format!("lib_{library_id}.lani"));
        std::fs::write(
            &source_path,
            format!("let lib_{library_id} = {library_id};\n"),
        )
        .expect("write source");
        libraries.push(ExplicitSourceLibraryPathDependencyStream {
            library_id,
            source_file_count: 1,
            paths: vec![source_path],
            dependency_library_count: 0,
            dependency_library_ids: Vec::<u32>::new(),
        });
    }

    let metadata =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
                libraries,
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
            )
            .expect("prepare metadata for capped chunk test");
    assert_eq!(metadata.library_count, library_count);

    let step =
            prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target(
                &artifact_root,
                CodegenUnitLimits {
                    max_source_bytes: 1024,
                    max_source_files: 1,
                },
                SourcePackJobBatchLimits {
                    max_jobs_per_batch: 1,
                    max_source_bytes_per_batch: 1024,
                    max_source_files_per_batch: 1,
                },
                SourcePackBuildShardLimits::default(),
                SourcePackArtifactTarget::Wasm,
                usize::MAX,
            )
            .expect("prepare capped artifact build chunk");
    assert_eq!(
        step.stage,
        SourcePackFilesystemArtifactBuildPrepareStage::LibrarySchedule
    );
    assert!(!step.complete);
    assert_eq!(
        step.new_item_count,
        SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT
    );
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    assert!(
        store
            .library_build_unit_page_path_for_target(
                SourcePackArtifactTarget::Wasm,
                SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT - 1,
            )
            .is_file()
    );
    assert!(
        !store
            .library_build_unit_page_path_for_target(
                SourcePackArtifactTarget::Wasm,
                SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
            )
            .is_file(),
        "oversized caller limit must not prepare past the default chunk cap"
    );
    assert!(
        !store
            .library_schedule_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file(),
        "capped first chunk must not finish the full library schedule"
    );

    std::fs::remove_dir_all(&root).expect("remove temp capped artifact chunk dir");
}

#[test]
fn source_pack_library_schedule_chunk_public_api_caps_oversized_library_limit() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-library-schedule-chunk-cap-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create source root");

    let capped_library_count = SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT;
    let library_count = capped_library_count + 1;
    let mut libraries = Vec::with_capacity(library_count);
    for library_index in 0..library_count {
        let library_id = (library_index + 1) as u32;
        let source_path = source_root.join(format!("lib_{library_id}.lani"));
        std::fs::write(
            &source_path,
            format!("let lib_{library_id} = {library_id};\n"),
        )
        .expect("write source");
        libraries.push(ExplicitSourceLibraryPathDependencyStream {
            library_id,
            source_file_count: 1,
            paths: vec![source_path],
            dependency_library_count: 0,
            dependency_library_ids: Vec::<u32>::new(),
        });
    }

    let metadata =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
                libraries,
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
            )
            .expect("prepare metadata for public schedule chunk cap test");
    assert_eq!(metadata.library_count, library_count);

    let step = prepare_source_pack_filesystem_library_schedule_from_metadata_chunk_for_target(
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 1024,
            max_source_files: 1,
        },
        SourcePackArtifactTarget::Wasm,
        usize::MAX,
    )
    .expect("prepare capped public schedule chunk");
    assert!(!step.complete);
    assert_eq!(step.new_library_build_unit_page_count, capped_library_count);
    assert_eq!(step.new_library_schedule_page_count, 0);
    assert_eq!(step.library_build_unit_page_count, capped_library_count);
    assert!(step.library_schedule_index_path.is_none());

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    assert!(
        store
            .library_build_unit_page_path_for_target(
                SourcePackArtifactTarget::Wasm,
                capped_library_count - 1,
            )
            .is_file()
    );
    assert!(
        !store
            .library_build_unit_page_path_for_target(
                SourcePackArtifactTarget::Wasm,
                capped_library_count,
            )
            .is_file(),
        "oversized public schedule chunk limit must not prepare past the default cap"
    );
    assert!(
        !store
            .library_schedule_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file(),
        "capped public schedule chunk must not finish the full schedule"
    );

    std::fs::remove_dir_all(&root).expect("remove temp public schedule chunk cap dir");
}

#[test]
fn source_pack_schedule_from_metadata_reconstructs_multi_unit_libraries_without_paths() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-schedule-from-metadata-multi-unit-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_paths = [
        source_root.join("core-a.lani"),
        source_root.join("core-b.lani"),
        source_root.join("core-c.lani"),
    ];
    let app_paths = [
        source_root.join("app-a.lani"),
        source_root.join("app-b.lani"),
    ];
    for path in core_paths.iter().chain(app_paths.iter()) {
        std::fs::write(path, b"unit").expect("write source file");
    }

    let metadata =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
                [
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 10,
                        source_file_count: core_paths.len(),
                        paths: core_paths.iter(),
                        dependency_library_count: 0,
                        dependency_library_ids: Vec::<u32>::new().into_iter(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 20,
                        source_file_count: app_paths.len(),
                        paths: app_paths.iter(),
                        dependency_library_count: 1,
                        dependency_library_ids: vec![10].into_iter(),
                    },
                ],
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
            )
            .expect("prepare persisted multi-unit source-pack metadata");
    assert_eq!(metadata.source_file_count, 5);
    assert_eq!(metadata.source_byte_count, 20);
    assert_eq!(metadata.library_partition_count, 2);
    assert_eq!(metadata.library_source_file_page_count, 2);

    for path in core_paths.iter().chain(app_paths.iter()) {
        std::fs::remove_file(path).expect("remove source file after metadata");
    }

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let prepared_pages = prepare_library_schedule_pages_from_metadata(
        &store,
        SourcePackArtifactTarget::Wasm,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 1,
        },
    )
    .expect("prepare multi-unit schedule pages from persisted metadata");

    assert_eq!(prepared_pages.library_partition_index.source_file_count, 5);
    assert_eq!(prepared_pages.library_source_file_page_count, 2);
    assert_eq!(prepared_pages.library_build_unit_page_count, 2);
    assert_eq!(prepared_pages.library_schedule_page_count, 2);
    let schedule = store
        .load_library_schedule_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load persisted multi-unit schedule index");
    assert_eq!(schedule.frontend_job_count, 5);
    assert_eq!(schedule.codegen_job_count, 5);
    assert_eq!(schedule.link_job_index, 10);
    assert_eq!(schedule.job_count, 11);

    let core_build_unit = store
        .load_library_build_unit_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load core build-unit page");
    assert_eq!(core_build_unit.frontend_unit_count, 3);
    assert_eq!(core_build_unit.codegen_unit_count, 3);
    assert!(core_build_unit.frontend_units.is_empty());
    assert!(core_build_unit.codegen_units.is_empty());
    let app_build_unit = store
        .load_library_build_unit_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load app build-unit page");
    assert_eq!(app_build_unit.frontend_unit_count, 2);
    assert_eq!(app_build_unit.codegen_unit_count, 2);

    for unit_index in 0..3 {
        let frontend_unit = store
            .load_library_frontend_unit_page_for_target(
                SourcePackArtifactTarget::Wasm,
                0,
                unit_index,
            )
            .expect("load core frontend unit page");
        assert_eq!(frontend_unit.unit.first_source_index, unit_index);
        assert_eq!(frontend_unit.unit.source_file_count, 1);
        let codegen_unit = store
            .load_library_codegen_unit_page_for_target(
                SourcePackArtifactTarget::Wasm,
                0,
                unit_index,
            )
            .expect("load core codegen unit page");
        assert_eq!(codegen_unit.unit.first_source_index, unit_index);
        assert_eq!(codegen_unit.unit.source_file_count, 1);
    }
    for unit_index in 0..2 {
        let frontend_unit = store
            .load_library_frontend_unit_page_for_target(
                SourcePackArtifactTarget::Wasm,
                1,
                unit_index,
            )
            .expect("load app frontend unit page");
        assert_eq!(frontend_unit.unit.first_source_index, 3 + unit_index);
        assert_eq!(frontend_unit.unit.source_file_count, 1);
        let codegen_unit = store
            .load_library_codegen_unit_page_for_target(
                SourcePackArtifactTarget::Wasm,
                1,
                unit_index,
            )
            .expect("load app codegen unit page");
        assert_eq!(codegen_unit.unit.first_source_index, 3 + unit_index);
        assert_eq!(codegen_unit.unit.source_file_count, 1);
    }

    let core_locator = store
        .load_library_frontend_job_locator_page_for_target(SourcePackArtifactTarget::Wasm, 10)
        .expect("load core frontend job locator");
    assert_eq!(core_locator.frontend_job_index, 0);
    assert_eq!(core_locator.frontend_job_count, 3);
    let app_locator = store
        .load_library_frontend_job_locator_page_for_target(SourcePackArtifactTarget::Wasm, 20)
        .expect("load app frontend job locator");
    assert_eq!(app_locator.frontend_job_index, 3);
    assert_eq!(app_locator.frontend_job_count, 2);

    let app_schedule_page = store
        .load_library_schedule_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load app schedule page");
    assert_eq!(app_schedule_page.frontend_job_index, 3);
    assert_eq!(app_schedule_page.frontend_job_count, 2);
    assert_eq!(app_schedule_page.first_codegen_job_index, 8);
    assert_eq!(app_schedule_page.codegen_job_count, 2);
    assert!(app_schedule_page.frontend_jobs.is_empty());
    assert!(app_schedule_page.codegen_jobs.is_empty());

    let dependency_set = |job_index| {
        source_pack_stored_schedule_job(&store, &schedule, job_index)
            .expect("load stored schedule job")
            .dependency_job_indices
            .into_iter()
            .collect::<BTreeSet<_>>()
    };
    assert!(dependency_set(0).is_empty());
    assert!(dependency_set(1).is_empty());
    assert!(dependency_set(2).is_empty());
    assert_eq!(dependency_set(3), BTreeSet::from([0usize, 1, 2]));
    assert_eq!(dependency_set(4), BTreeSet::from([0usize, 1, 2]));
    assert_eq!(dependency_set(5), BTreeSet::from([0usize, 1, 2]));
    assert_eq!(dependency_set(6), BTreeSet::from([0usize, 1, 2]));
    assert_eq!(dependency_set(7), BTreeSet::from([0usize, 1, 2]));
    assert_eq!(dependency_set(8), BTreeSet::from([0usize, 1, 2, 3, 4]));
    assert_eq!(dependency_set(9), BTreeSet::from([0usize, 1, 2, 3, 4]));

    std::fs::remove_dir_all(&root).expect("remove temp schedule-from-metadata multi-unit test dir");
}

#[test]
fn source_pack_schedule_from_metadata_chunk_prepares_bounded_libraries_without_paths() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-schedule-from-metadata-chunk-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let metadata =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
                [
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 10,
                        source_file_count: 1,
                        paths: std::iter::once(core_path.as_path()),
                        dependency_library_count: 0,
                        dependency_library_ids: Vec::<u32>::new().into_iter(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 20,
                        source_file_count: 1,
                        paths: std::iter::once(app_path.as_path()),
                        dependency_library_count: 1,
                        dependency_library_ids: vec![10].into_iter(),
                    },
                ],
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
            )
            .expect("prepare persisted metadata for schedule chunks");
    assert_eq!(metadata.library_partition_count, 2);
    std::fs::remove_file(&core_path).expect("remove core source after metadata");
    std::fs::remove_file(&app_path).expect("remove app source after metadata");

    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 1,
    };
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);

    let first = prepare_source_pack_filesystem_library_schedule_from_metadata_chunk_for_target(
        &artifact_root,
        limits,
        SourcePackArtifactTarget::Wasm,
        1,
    )
    .expect("prepare first schedule chunk");
    assert!(!first.complete);
    assert_eq!(first.new_library_build_unit_page_count, 1);
    assert_eq!(first.library_build_unit_page_count, 1);
    assert!(first.library_schedule_index_path.is_none());
    assert!(
        !store
            .library_schedule_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );
    assert!(
        !store
            .library_build_unit_page_path_for_target(SourcePackArtifactTarget::Wasm, 1)
            .is_file()
    );
    let first_progress = store
        .load_library_schedule_prepare_progress_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load first schedule progress");
    assert_eq!(
        first_progress.phase,
        SourcePackFilesystemLibrarySchedulePreparePhase::BuildUnitPages
    );
    assert_eq!(first_progress.next_partition_index, 1);

    let second = prepare_source_pack_filesystem_library_schedule_from_metadata_chunk_for_target(
        &artifact_root,
        limits,
        SourcePackArtifactTarget::Wasm,
        1,
    )
    .expect("prepare second schedule chunk");
    assert!(!second.complete);
    assert_eq!(second.new_library_build_unit_page_count, 1);
    assert_eq!(second.library_build_unit_page_count, 2);
    assert_eq!(second.library_schedule_page_count, 0);
    assert!(second.library_schedule_index_path.is_some());
    assert!(
        store
            .library_schedule_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );
    assert!(
        !store
            .library_schedule_page_path_for_target(SourcePackArtifactTarget::Wasm, 0)
            .is_file()
    );
    let second_progress = store
        .load_library_schedule_prepare_progress_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load second schedule progress");
    assert_eq!(
        second_progress.phase,
        SourcePackFilesystemLibrarySchedulePreparePhase::SchedulePages
    );
    assert_eq!(second_progress.next_partition_index, 0);
    assert_eq!(second_progress.frontend_job_count, 2);
    assert_eq!(second_progress.codegen_job_count, 2);

    let third = prepare_source_pack_filesystem_library_schedule_from_metadata_chunk_for_target(
        &artifact_root,
        limits,
        SourcePackArtifactTarget::Wasm,
        1,
    )
    .expect("prepare third schedule chunk");
    assert!(!third.complete);
    assert_eq!(third.new_library_build_unit_page_count, 0);
    assert_eq!(third.new_library_schedule_page_count, 1);
    assert_eq!(third.library_schedule_page_count, 1);
    assert!(
        store
            .library_schedule_page_path_for_target(SourcePackArtifactTarget::Wasm, 0)
            .is_file()
    );
    assert!(
        !store
            .library_schedule_page_path_for_target(SourcePackArtifactTarget::Wasm, 1)
            .is_file()
    );
    let third_progress = store
        .load_library_schedule_prepare_progress_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load third schedule progress");
    assert_eq!(
        third_progress.phase,
        SourcePackFilesystemLibrarySchedulePreparePhase::SchedulePages
    );
    assert_eq!(third_progress.next_partition_index, 1);

    let final_chunk =
        prepare_source_pack_filesystem_library_schedule_from_metadata_chunk_for_target(
            &artifact_root,
            limits,
            SourcePackArtifactTarget::Wasm,
            1,
        )
        .expect("prepare final schedule chunk");
    assert!(final_chunk.complete);
    assert_eq!(final_chunk.new_library_build_unit_page_count, 0);
    assert_eq!(final_chunk.new_library_schedule_page_count, 1);
    assert_eq!(final_chunk.library_build_unit_page_count, 2);
    assert_eq!(final_chunk.library_schedule_page_count, 2);
    assert_eq!(final_chunk.frontend_job_count, 2);
    assert_eq!(final_chunk.codegen_job_count, 2);
    assert_eq!(final_chunk.scheduled_job_count, 5);
    let schedule = store
        .load_library_schedule_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load completed schedule index");
    assert_eq!(schedule.partition_count, 2);
    let final_progress = store
        .load_library_schedule_prepare_progress_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load final schedule progress");
    assert_eq!(
        final_progress.phase,
        SourcePackFilesystemLibrarySchedulePreparePhase::Complete
    );
    let app_schedule = store
        .load_library_schedule_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load completed app schedule page");
    assert_eq!(app_schedule.frontend_job_index, 1);
    assert_eq!(app_schedule.first_codegen_job_index, 3);
    let app_codegen = source_pack_stored_schedule_job(&store, &schedule, 3)
        .expect("load app codegen job from chunked schedule");
    assert_eq!(app_codegen.dependency_job_indices, vec![1, 0]);

    std::fs::remove_dir_all(&root).expect("remove temp schedule chunk dir");
}

#[test]
fn source_pack_artifact_refs_from_schedule_chunk_prepares_bounded_libraries_without_paths() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-artifact-ref-chunk-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let metadata =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
                [
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 10,
                        source_file_count: 1,
                        paths: std::iter::once(core_path.as_path()),
                        dependency_library_count: 0,
                        dependency_library_ids: Vec::<u32>::new().into_iter(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 20,
                        source_file_count: 1,
                        paths: std::iter::once(app_path.as_path()),
                        dependency_library_count: 1,
                        dependency_library_ids: vec![10].into_iter(),
                    },
                ],
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
            )
            .expect("prepare persisted metadata for artifact-ref chunks");
    assert_eq!(metadata.library_partition_count, 2);
    std::fs::remove_file(&core_path).expect("remove core source after metadata");
    std::fs::remove_file(&app_path).expect("remove app source after metadata");

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    prepare_library_schedule_pages_from_metadata(
        &store,
        SourcePackArtifactTarget::Wasm,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 1,
        },
    )
    .expect("prepare schedule pages from persisted metadata");
    assert!(
        !store
            .build_artifact_ref_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );

    let first = prepare_source_pack_filesystem_artifact_refs_from_schedule_chunk_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        1,
    )
    .expect("prepare first artifact-ref chunk");
    assert!(!first.complete);
    assert_eq!(first.new_library_count, 1);
    assert_eq!(first.artifact_ref_page_count, 2);
    assert!(first.artifact_ref_index_path.is_none());
    let schedule_index = store
        .load_library_schedule_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load schedule index for artifact-ref progress");
    let metadata_index = store
        .load_library_partition_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load metadata index for artifact-ref progress");
    let first_progress = store
        .load_build_artifact_ref_prepare_progress_for_target(
            SourcePackArtifactTarget::Wasm,
            &schedule_index,
            &metadata_index,
        )
        .expect("load first artifact-ref progress");
    assert_eq!(first_progress.next_partition_index, 1);
    assert_eq!(first_progress.artifact_ref_page_count, 2);
    assert_eq!(first_progress.interface_artifact_count, 1);
    assert_eq!(first_progress.object_artifact_count, 1);
    assert!(
        store
            .build_artifact_ref_page_path_for_target(SourcePackArtifactTarget::Wasm, 0)
            .is_file()
    );
    assert!(
        store
            .build_artifact_ref_page_path_for_target(SourcePackArtifactTarget::Wasm, 2)
            .is_file()
    );
    assert!(
        !store
            .build_artifact_ref_page_path_for_target(SourcePackArtifactTarget::Wasm, 1)
            .is_file()
    );

    let final_chunk = prepare_source_pack_filesystem_artifact_refs_from_schedule_chunk_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        1,
    )
    .expect("prepare final artifact-ref chunk");
    assert!(final_chunk.complete);
    assert_eq!(final_chunk.new_library_count, 1);
    assert_eq!(final_chunk.artifact_count, 5);
    assert_eq!(final_chunk.artifact_ref_page_count, 5);
    assert_eq!(final_chunk.interface_artifact_count, 2);
    assert_eq!(final_chunk.object_artifact_count, 2);
    assert_eq!(final_chunk.final_output_artifact_index, 4);
    assert_eq!(final_chunk.total_source_file_count, 2);
    assert_eq!(final_chunk.total_source_byte_count, 8);
    assert!(final_chunk.final_output_key.is_some());
    assert!(final_chunk.artifact_ref_index_path.is_some());
    let final_progress = store
        .load_build_artifact_ref_prepare_progress_for_target(
            SourcePackArtifactTarget::Wasm,
            &schedule_index,
            &metadata_index,
        )
        .expect("load final artifact-ref progress");
    assert_eq!(final_progress.next_partition_index, 2);
    assert_eq!(final_progress.artifact_ref_page_count, 4);
    assert_eq!(final_progress.interface_artifact_count, 2);
    assert_eq!(final_progress.object_artifact_count, 2);
    let index = store
        .load_build_artifact_ref_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load completed artifact-ref index");
    assert_eq!(index.artifact_count, 5);
    let final_output_page = store
        .load_build_artifact_ref_page_for_target(SourcePackArtifactTarget::Wasm, 4, 5)
        .expect("load final output artifact ref page");
    assert_eq!(
        final_output_page.artifact_ref.kind,
        SourcePackArtifactKind::LinkedOutput
    );

    let already_complete =
        prepare_source_pack_filesystem_artifact_refs_from_schedule_chunk_for_target(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            1,
        )
        .expect("already completed artifact-ref chunks should reopen index");
    assert!(already_complete.complete);
    assert_eq!(already_complete.new_library_count, 0);
    assert_eq!(already_complete.artifact_count, 5);

    std::fs::remove_dir_all(&root).expect("remove temp artifact-ref chunk dir");
}

#[test]
fn source_pack_job_batches_from_schedule_chunk_resumes_from_progress_without_paths() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-job-batch-chunk-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
        [
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 10,
                source_file_count: 1,
                paths: std::iter::once(core_path.as_path()),
                dependency_library_count: 0,
                dependency_library_ids: Vec::<u32>::new().into_iter(),
            },
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 20,
                source_file_count: 1,
                paths: std::iter::once(app_path.as_path()),
                dependency_library_count: 1,
                dependency_library_ids: vec![10].into_iter(),
            },
        ],
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare persisted metadata for job-batch chunks");
    std::fs::remove_file(&core_path).expect("remove core source after metadata");
    std::fs::remove_file(&app_path).expect("remove app source after metadata");

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    prepare_library_schedule_pages_from_metadata(
        &store,
        SourcePackArtifactTarget::Wasm,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 1,
        },
    )
    .expect("prepare schedule pages from persisted metadata");
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };

    let first = prepare_source_pack_filesystem_job_batches_from_schedule_chunk_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        batch_limits,
        2,
    )
    .expect("prepare first job-batch chunk");
    assert!(!first.complete);
    assert_eq!(first.new_batch_count, 2);
    assert_eq!(first.batch_count, 2);
    assert_eq!(first.next_job_index, 2);
    assert!(first.job_batch_index_path.is_none());
    assert!(
        store
            .build_job_batch_prepare_progress_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );
    assert!(
        !store
            .build_job_batch_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );
    assert!(
        store
            .build_job_batch_page_path_for_target(SourcePackArtifactTarget::Wasm, 1)
            .is_file()
    );
    assert!(
        !store
            .build_job_batch_page_path_for_target(SourcePackArtifactTarget::Wasm, 2)
            .is_file()
    );

    let second = prepare_source_pack_filesystem_job_batches_from_schedule_chunk_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        batch_limits,
        2,
    )
    .expect("prepare second job-batch chunk");
    assert!(!second.complete);
    assert_eq!(second.new_batch_count, 2);
    assert_eq!(second.batch_count, 4);
    assert_eq!(second.next_job_index, 4);
    assert!(
        store
            .build_job_batch_page_path_for_target(SourcePackArtifactTarget::Wasm, 3)
            .is_file()
    );
    assert!(
        !store
            .build_job_batch_page_path_for_target(SourcePackArtifactTarget::Wasm, 4)
            .is_file()
    );

    let final_chunk = prepare_source_pack_filesystem_job_batches_from_schedule_chunk_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        batch_limits,
        2,
    )
    .expect("prepare final job-batch chunk");
    assert!(final_chunk.complete);
    assert_eq!(final_chunk.new_batch_count, 1);
    assert_eq!(final_chunk.scheduled_job_count, 5);
    assert_eq!(final_chunk.batch_count, 5);
    assert_eq!(final_chunk.next_job_index, 5);
    assert!(final_chunk.dependency_edge_count > 0);
    assert!(final_chunk.job_batch_index_path.is_some());
    let index = store
        .load_build_job_batch_page_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load completed job-batch index");
    assert_eq!(index.batch_count, 5);
    assert_eq!(index.scheduled_job_count, 5);
    assert_eq!(
        index.dependency_edge_count,
        final_chunk.dependency_edge_count
    );
    let link_batch = store
        .load_build_job_batch_page_for_target(SourcePackArtifactTarget::Wasm, 4)
        .expect("load completed link job batch");
    assert!(link_batch.dependency.has_dependencies());

    let already_complete =
        prepare_source_pack_filesystem_job_batches_from_schedule_chunk_for_target(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            batch_limits,
            2,
        )
        .expect("completed job-batch chunk should reopen index");
    assert!(already_complete.complete);
    assert_eq!(already_complete.new_batch_count, 0);
    assert_eq!(already_complete.batch_count, 5);

    std::fs::remove_dir_all(&root).expect("remove temp job-batch chunk dir");
}

#[test]
fn source_pack_link_batches_from_artifact_refs_chunk_resumes_from_progress_without_paths() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-link-batch-chunk-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
        [
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 10,
                source_file_count: 1,
                paths: std::iter::once(core_path.as_path()),
                dependency_library_count: 0,
                dependency_library_ids: Vec::<u32>::new().into_iter(),
            },
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 20,
                source_file_count: 1,
                paths: std::iter::once(app_path.as_path()),
                dependency_library_count: 1,
                dependency_library_ids: vec![10].into_iter(),
            },
        ],
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare persisted metadata for link-batch chunks");
    std::fs::remove_file(&core_path).expect("remove core source after metadata");
    std::fs::remove_file(&app_path).expect("remove app source after metadata");

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let schedule_pages = prepare_library_schedule_pages_from_metadata(
        &store,
        SourcePackArtifactTarget::Wasm,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 1,
        },
    )
    .expect("prepare schedule pages from persisted metadata");
    let artifact_ref_index = store_source_pack_build_artifact_ref_pages_from_stored_schedule_pages(
        &store,
        &schedule_pages.library_schedule_index,
    )
    .expect("prepare artifact refs from schedule pages");
    assert_eq!(artifact_ref_index.interface_artifact_count, 2);
    assert_eq!(artifact_ref_index.object_artifact_count, 2);
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };

    let first = prepare_source_pack_filesystem_link_batches_from_artifact_refs_chunk_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        batch_limits,
        1,
    )
    .expect("prepare first link-batch chunk");
    assert!(!first.complete);
    assert_eq!(first.new_batch_count, 1);
    assert_eq!(first.link_interface_batch_count, 1);
    assert_eq!(first.link_object_batch_count, 0);
    assert_eq!(first.next_interface_artifact_index, 1);
    assert_eq!(first.next_object_artifact_index, 2);
    assert!(first.link_batch_index_path.is_none());
    assert!(
        store
            .build_link_batch_prepare_progress_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );
    assert!(
        store
            .build_link_interface_batch_page_path_for_target(SourcePackArtifactTarget::Wasm, 0)
            .is_file()
    );
    assert!(
        !store
            .build_link_batch_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );

    let second = prepare_source_pack_filesystem_link_batches_from_artifact_refs_chunk_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        batch_limits,
        1,
    )
    .expect("prepare second link-batch chunk");
    assert!(!second.complete);
    assert_eq!(second.new_batch_count, 1);
    assert_eq!(second.link_interface_batch_count, 2);
    assert_eq!(second.link_object_batch_count, 0);
    assert_eq!(second.next_interface_artifact_index, 2);
    assert_eq!(second.next_object_artifact_index, 2);
    assert!(
        !store
            .build_link_object_batch_page_path_for_target(SourcePackArtifactTarget::Wasm, 0)
            .is_file()
    );

    let third = prepare_source_pack_filesystem_link_batches_from_artifact_refs_chunk_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        batch_limits,
        1,
    )
    .expect("prepare third link-batch chunk");
    assert!(!third.complete);
    assert_eq!(third.new_batch_count, 1);
    assert_eq!(third.link_interface_batch_count, 2);
    assert_eq!(third.link_object_batch_count, 1);
    assert_eq!(third.next_object_artifact_index, 3);

    let final_chunk =
        prepare_source_pack_filesystem_link_batches_from_artifact_refs_chunk_for_target(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            batch_limits,
            1,
        )
        .expect("prepare final link-batch chunk");
    assert!(final_chunk.complete);
    assert_eq!(final_chunk.new_batch_count, 1);
    assert_eq!(final_chunk.link_interface_batch_count, 2);
    assert_eq!(final_chunk.link_object_batch_count, 2);
    assert_eq!(final_chunk.next_interface_artifact_index, 2);
    assert_eq!(final_chunk.next_object_artifact_index, 4);
    assert!(final_chunk.link_batch_index_path.is_some());
    let index = store
        .load_build_link_batch_page_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load completed link-batch index");
    assert_eq!(index.link_interface_batch_count, 2);
    assert_eq!(index.link_object_batch_count, 2);
    let object_page = store
        .load_build_link_object_batch_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load second object link batch");
    assert_eq!(object_page.batch.input_object_artifact_indices, vec![3]);

    let already_complete =
        prepare_source_pack_filesystem_link_batches_from_artifact_refs_chunk_for_target(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            batch_limits,
            1,
        )
        .expect("completed link-batch chunk should reopen index");
    assert!(already_complete.complete);
    assert_eq!(already_complete.new_batch_count, 0);
    assert_eq!(already_complete.link_interface_batch_count, 2);
    assert_eq!(already_complete.link_object_batch_count, 2);

    std::fs::remove_dir_all(&root).expect("remove temp link-batch chunk dir");
}

#[test]
fn source_pack_hierarchical_link_leaf_groups_from_schedule_chunk_resumes_without_paths() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-link-leaf-chunk-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
        [
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 10,
                source_file_count: 1,
                paths: std::iter::once(core_path.as_path()),
                dependency_library_count: 0,
                dependency_library_ids: Vec::<u32>::new().into_iter(),
            },
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 20,
                source_file_count: 1,
                paths: std::iter::once(app_path.as_path()),
                dependency_library_count: 1,
                dependency_library_ids: vec![10].into_iter(),
            },
        ],
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare persisted metadata for link leaf chunks");
    std::fs::remove_file(&core_path).expect("remove core source after metadata");
    std::fs::remove_file(&app_path).expect("remove app source after metadata");

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    prepare_library_schedule_pages_from_metadata(
        &store,
        SourcePackArtifactTarget::Wasm,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 1,
        },
    )
    .expect("prepare schedule pages from persisted metadata");
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };

    let first =
            prepare_source_pack_filesystem_hierarchical_link_leaf_groups_from_schedule_chunk_for_target(
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                batch_limits,
                1,
            )
            .expect("prepare first hierarchical link leaf chunk");
    assert!(!first.complete);
    assert_eq!(first.schedule_partition_count, 2);
    assert_eq!(first.next_partition_index, 1);
    assert_eq!(first.new_leaf_group_count, 1);
    assert_eq!(first.leaf_group_count, 1);
    assert!(
        store
            .hierarchical_link_plan_prepare_progress_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );
    assert!(
        store
            .hierarchical_link_group_page_path_for_target(SourcePackArtifactTarget::Wasm, 0)
            .is_file()
    );
    assert!(
        !store
            .hierarchical_link_group_page_path_for_target(SourcePackArtifactTarget::Wasm, 1)
            .is_file()
    );
    let first_group = store
        .load_hierarchical_link_group_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load first leaf link group");
    assert_eq!(first_group.kind, SourcePackHierarchicalLinkGroupKind::Leaf);
    assert_eq!(first_group.level, 0);

    let second =
            prepare_source_pack_filesystem_hierarchical_link_leaf_groups_from_schedule_chunk_for_target(
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                batch_limits,
                1,
            )
            .expect("prepare second hierarchical link leaf chunk");
    assert!(second.complete);
    assert_eq!(second.next_partition_index, 2);
    assert_eq!(second.new_leaf_group_count, 1);
    assert_eq!(second.leaf_group_count, 2);
    assert!(
        !store
            .hierarchical_link_plan_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file(),
        "leaf-group chunking must not publish the compact link-plan index"
    );
    let second_group = store
        .load_hierarchical_link_group_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load second leaf link group");
    assert_eq!(second_group.kind, SourcePackHierarchicalLinkGroupKind::Leaf);
    assert_eq!(second_group.level, 0);

    let already_complete =
            prepare_source_pack_filesystem_hierarchical_link_leaf_groups_from_schedule_chunk_for_target(
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                batch_limits,
                1,
            )
            .expect("completed hierarchical link leaf chunk should reopen progress");
    assert!(already_complete.complete);
    assert_eq!(already_complete.new_leaf_group_count, 0);
    assert_eq!(already_complete.leaf_group_count, 2);
    assert_eq!(already_complete.next_partition_index, 2);

    std::fs::remove_dir_all(&root).expect("remove temp link leaf chunk dir");
}

#[test]
fn source_pack_hierarchical_link_plan_reduce_groups_from_schedule_chunk_resumes_without_paths() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-link-reduce-chunk-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let util_path = source_root.join("util.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&util_path, b"util").expect("write util source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
        [
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 10,
                source_file_count: 1,
                paths: std::iter::once(core_path.as_path()),
                dependency_library_count: 0,
                dependency_library_ids: Vec::<u32>::new().into_iter(),
            },
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 20,
                source_file_count: 1,
                paths: std::iter::once(util_path.as_path()),
                dependency_library_count: 1,
                dependency_library_ids: vec![10].into_iter(),
            },
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 30,
                source_file_count: 1,
                paths: std::iter::once(app_path.as_path()),
                dependency_library_count: 1,
                dependency_library_ids: vec![20].into_iter(),
            },
        ],
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare persisted metadata for link reduce chunks");
    std::fs::remove_file(&core_path).expect("remove core source after metadata");
    std::fs::remove_file(&util_path).expect("remove util source after metadata");
    std::fs::remove_file(&app_path).expect("remove app source after metadata");

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    prepare_library_schedule_pages_from_metadata(
        &store,
        SourcePackArtifactTarget::Wasm,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 1,
        },
    )
    .expect("prepare schedule pages from persisted metadata");
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 2,
        max_source_bytes_per_batch: 8,
        max_source_files_per_batch: 2,
    };

    let leaf =
            prepare_source_pack_filesystem_hierarchical_link_leaf_groups_from_schedule_chunk_for_target(
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                batch_limits,
                3,
            )
            .expect("prepare all hierarchical link leaf groups");
    assert!(leaf.complete);
    assert_eq!(leaf.leaf_group_count, 3);
    assert!(
        !store
            .hierarchical_link_plan_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );

    let first =
            prepare_source_pack_filesystem_hierarchical_link_plan_reduce_groups_from_schedule_chunk_for_target(
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                batch_limits,
                1,
            )
            .expect("prepare first hierarchical link reduce chunk");
    assert!(!first.complete);
    assert_eq!(first.new_reduce_group_count, 1);
    assert_eq!(first.reduce_level, 1);
    assert_eq!(first.current_level_first_group_index, 0);
    assert_eq!(first.current_level_group_count, 3);
    assert_eq!(first.next_input_group_index, 2);
    assert_eq!(first.link_group_count, 4);
    assert!(first.hierarchical_link_plan_index_path.is_none());
    let first_reduce = store
        .load_hierarchical_link_group_page_for_target(SourcePackArtifactTarget::Wasm, 3)
        .expect("load first reduce group");
    assert_eq!(
        first_reduce.kind,
        SourcePackHierarchicalLinkGroupKind::Reduce
    );
    assert_eq!(first_reduce.level, 1);
    assert_eq!(first_reduce.input_link_group_indices, vec![0, 1]);
    assert_eq!(first_reduce.input_partition_count, 2);

    let second =
            prepare_source_pack_filesystem_hierarchical_link_plan_reduce_groups_from_schedule_chunk_for_target(
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                batch_limits,
                1,
            )
            .expect("prepare second hierarchical link reduce chunk");
    assert!(!second.complete);
    assert_eq!(second.new_reduce_group_count, 1);
    assert_eq!(second.reduce_level, 2);
    assert_eq!(second.current_level_first_group_index, 3);
    assert_eq!(second.current_level_group_count, 2);
    assert_eq!(second.next_input_group_index, 3);
    assert_eq!(second.link_group_count, 5);
    assert!(second.hierarchical_link_plan_index_path.is_none());
    let second_reduce = store
        .load_hierarchical_link_group_page_for_target(SourcePackArtifactTarget::Wasm, 4)
        .expect("load second reduce group");
    assert_eq!(
        second_reduce.kind,
        SourcePackHierarchicalLinkGroupKind::Reduce
    );
    assert_eq!(second_reduce.level, 1);
    assert_eq!(second_reduce.input_link_group_indices, vec![2]);
    assert_eq!(second_reduce.input_partition_count, 1);

    let final_chunk =
            prepare_source_pack_filesystem_hierarchical_link_plan_reduce_groups_from_schedule_chunk_for_target(
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                batch_limits,
                1,
            )
            .expect("prepare final hierarchical link reduce chunk");
    assert!(final_chunk.complete);
    assert_eq!(final_chunk.new_reduce_group_count, 1);
    assert_eq!(final_chunk.link_group_count, 6);
    assert_eq!(final_chunk.final_link_group_index, Some(5));
    assert!(final_chunk.hierarchical_link_plan_index_path.is_some());
    let final_reduce = store
        .load_hierarchical_link_group_page_for_target(SourcePackArtifactTarget::Wasm, 5)
        .expect("load final reduce group");
    assert_eq!(
        final_reduce.kind,
        SourcePackHierarchicalLinkGroupKind::Reduce
    );
    assert_eq!(final_reduce.level, 2);
    assert_eq!(final_reduce.input_link_group_indices, vec![3, 4]);
    assert_eq!(final_reduce.input_partition_count, 3);
    let index = store
        .load_hierarchical_link_plan_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load completed hierarchical link plan index");
    assert_eq!(index.link_group_count, 6);
    assert_eq!(index.final_link_group_index, 5);

    let already_complete =
            prepare_source_pack_filesystem_hierarchical_link_plan_reduce_groups_from_schedule_chunk_for_target(
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                batch_limits,
                1,
            )
            .expect("completed hierarchical link reduce chunk should reopen index");
    assert!(already_complete.complete);
    assert_eq!(already_complete.new_reduce_group_count, 0);
    assert_eq!(already_complete.link_group_count, 6);
    assert_eq!(already_complete.final_link_group_index, Some(5));

    std::fs::remove_dir_all(&root).expect("remove temp link reduce chunk dir");
}

#[test]
fn source_pack_hierarchical_link_execution_from_plan_chunk_resumes_without_paths() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-link-execution-chunk-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
        [
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 10,
                source_file_count: 1,
                paths: std::iter::once(core_path.as_path()),
                dependency_library_count: 0,
                dependency_library_ids: Vec::<u32>::new().into_iter(),
            },
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 20,
                source_file_count: 1,
                paths: std::iter::once(app_path.as_path()),
                dependency_library_count: 1,
                dependency_library_ids: vec![10].into_iter(),
            },
        ],
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare persisted metadata for link execution chunks");
    std::fs::remove_file(&core_path).expect("remove core source after metadata");
    std::fs::remove_file(&app_path).expect("remove app source after metadata");

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let schedule_pages = prepare_library_schedule_pages_from_metadata(
        &store,
        SourcePackArtifactTarget::Wasm,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 1,
        },
    )
    .expect("prepare schedule pages from persisted metadata");
    store_source_pack_build_artifact_ref_pages_from_stored_schedule_pages(
        &store,
        &schedule_pages.library_schedule_index,
    )
    .expect("prepare artifact refs from schedule pages");
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 2,
        max_source_bytes_per_batch: 8,
        max_source_files_per_batch: 2,
    };
    let leaf =
            prepare_source_pack_filesystem_hierarchical_link_leaf_groups_from_schedule_chunk_for_target(
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                batch_limits,
                2,
            )
            .expect("prepare all hierarchical link leaf groups");
    assert!(leaf.complete);
    let plan =
            prepare_source_pack_filesystem_hierarchical_link_plan_reduce_groups_from_schedule_chunk_for_target(
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                batch_limits,
                10,
            )
            .expect("prepare hierarchical link reduce plan");
    assert!(plan.complete);
    assert_eq!(plan.link_group_count, 3);
    assert!(
        !store
            .hierarchical_link_execution_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );

    let first =
        prepare_source_pack_filesystem_hierarchical_link_execution_from_plan_chunk_for_target(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            2,
        )
        .expect("prepare first hierarchical link execution chunk");
    assert!(!first.complete);
    assert_eq!(first.link_group_count, 3);
    assert_eq!(first.next_group_index, 2);
    assert_eq!(first.new_execution_page_count, 2);
    assert!(!first.final_output_seen);
    assert!(first.hierarchical_link_execution_index_path.is_none());
    assert!(
        store
            .hierarchical_link_execution_prepare_progress_path_for_target(
                SourcePackArtifactTarget::Wasm
            )
            .is_file()
    );
    let first_page = store
        .load_hierarchical_link_execution_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load first leaf execution page");
    assert_eq!(first_page.kind, SourcePackHierarchicalLinkGroupKind::Leaf);
    assert_eq!(first_page.input_object_count, 1);
    assert_eq!(first_page.input_object_page_count, 1);
    assert!(
        store
            .hierarchical_link_execution_object_page_path_for_target(
                SourcePackArtifactTarget::Wasm,
                0,
                0,
            )
            .is_file()
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(SourcePackArtifactTarget::Wasm, 2)
            .is_file()
    );

    let final_chunk =
        prepare_source_pack_filesystem_hierarchical_link_execution_from_plan_chunk_for_target(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            1,
        )
        .expect("prepare final hierarchical link execution chunk");
    assert!(final_chunk.complete);
    assert_eq!(final_chunk.next_group_index, 3);
    assert_eq!(final_chunk.new_execution_page_count, 1);
    assert!(final_chunk.final_output_seen);
    assert!(final_chunk.hierarchical_link_execution_index_path.is_some());
    let final_page = store
        .load_hierarchical_link_execution_page_for_target(SourcePackArtifactTarget::Wasm, 2)
        .expect("load final reduce execution page");
    assert_eq!(final_page.kind, SourcePackHierarchicalLinkGroupKind::Reduce);
    assert!(final_page.final_output);
    assert_eq!(final_page.input_group_count, 2);
    assert_eq!(final_page.input_group_page_count, 1);
    assert!(
        store
            .hierarchical_link_execution_partial_page_path_for_target(
                SourcePackArtifactTarget::Wasm,
                2,
                0,
            )
            .is_file()
    );
    let index = store
        .load_hierarchical_link_execution_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load completed hierarchical link execution index");
    assert_eq!(index.link_group_count, 3);
    assert_eq!(index.final_link_group_index, 2);

    let already_complete =
        prepare_source_pack_filesystem_hierarchical_link_execution_from_plan_chunk_for_target(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            1,
        )
        .expect("completed hierarchical link execution chunk should reopen index");
    assert!(already_complete.complete);
    assert_eq!(already_complete.new_execution_page_count, 0);
    assert_eq!(already_complete.next_group_index, 3);

    std::fs::remove_dir_all(&root).expect("remove temp link execution chunk dir");
}

#[test]
fn source_pack_work_queue_pages_from_schedule_chunk_resumes_without_paths() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-chunk-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
        [
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 10,
                source_file_count: 1,
                paths: std::iter::once(core_path.as_path()),
                dependency_library_count: 0,
                dependency_library_ids: Vec::<u32>::new().into_iter(),
            },
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 20,
                source_file_count: 1,
                paths: std::iter::once(app_path.as_path()),
                dependency_library_count: 1,
                dependency_library_ids: vec![10].into_iter(),
            },
        ],
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare persisted metadata for work queue chunks");
    std::fs::remove_file(&core_path).expect("remove core source after metadata");
    std::fs::remove_file(&app_path).expect("remove app source after metadata");

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let schedule_pages = prepare_library_schedule_pages_from_metadata(
        &store,
        SourcePackArtifactTarget::Wasm,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 1,
        },
    )
    .expect("prepare schedule pages from persisted metadata");
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 2,
        max_source_bytes_per_batch: 8,
        max_source_files_per_batch: 2,
    };
    store_source_pack_build_job_batch_pages_from_stored_schedule_pages(
        &store,
        &schedule_pages.library_schedule_index,
        batch_limits,
    )
    .expect("prepare job batches for work queue chunks");
    let leaf =
            prepare_source_pack_filesystem_hierarchical_link_leaf_groups_from_schedule_chunk_for_target(
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                batch_limits,
                2,
            )
            .expect("prepare work queue leaf link groups");
    assert!(leaf.complete);
    let plan =
            prepare_source_pack_filesystem_hierarchical_link_plan_reduce_groups_from_schedule_chunk_for_target(
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
                batch_limits,
                10,
            )
            .expect("prepare work queue link plan");
    assert!(plan.complete);
    assert_eq!(plan.link_group_count, 3);

    let first = prepare_source_pack_filesystem_work_queue_pages_from_schedule_chunk_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        4,
    )
    .expect("prepare frontend and codegen work queue chunk");
    assert!(!first.complete);
    assert_eq!(first.work_item_count, 7);
    assert_eq!(first.artifact_item_count, 4);
    assert_eq!(first.next_item_index, 4);
    assert_eq!(first.new_work_item_count, 4);
    assert!(first.work_queue_index_path.is_none());
    assert!(
        store
            .work_queue_prepare_progress_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );
    assert!(
        !store
            .work_queue_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );
    assert!(
        !store
            .work_queue_page_path_for_target(SourcePackArtifactTarget::Wasm, 4)
            .is_file()
    );
    let app_codegen = store
        .load_work_queue_page_for_target(SourcePackArtifactTarget::Wasm, 3)
        .expect("load chunked app codegen work item");
    assert_eq!(app_codegen.kind, SourcePackWorkQueueItemKind::Codegen);
    assert!(source_pack_work_queue_page_dependency_count(&app_codegen) > 0);

    let second = prepare_source_pack_filesystem_work_queue_pages_from_schedule_chunk_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        1,
    )
    .expect("prepare first link work queue chunk");
    assert!(!second.complete);
    assert_eq!(second.next_item_index, 5);
    assert_eq!(second.new_work_item_count, 1);
    let first_link = store
        .load_work_queue_page_for_target(SourcePackArtifactTarget::Wasm, 4)
        .expect("load first link work item");
    assert_eq!(first_link.kind, SourcePackWorkQueueItemKind::LinkLeaf);
    assert_eq!(first_link.link_group_index, Some(0));
    assert!(source_pack_work_queue_page_dependency_count(&first_link) > 0);
    assert!(
        !store
            .work_queue_page_path_for_target(SourcePackArtifactTarget::Wasm, 5)
            .is_file()
    );

    let final_chunk =
        prepare_source_pack_filesystem_work_queue_pages_from_schedule_chunk_for_target(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            10,
        )
        .expect("prepare final work queue chunk");
    assert!(final_chunk.complete);
    assert_eq!(final_chunk.next_item_index, 7);
    assert_eq!(final_chunk.new_work_item_count, 2);
    assert!(final_chunk.work_queue_index_path.is_some());
    let index = store
        .load_work_queue_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load completed work queue index");
    assert_eq!(index.work_item_count, 7);
    assert_eq!(index.artifact_item_count, 4);
    assert_eq!(index.final_item_index, 6);
    let final_link = store
        .load_work_queue_page_for_target(SourcePackArtifactTarget::Wasm, 6)
        .expect("load final reduce link work item");
    assert_eq!(final_link.kind, SourcePackWorkQueueItemKind::LinkReduce);
    assert_eq!(final_link.link_group_index, Some(2));
    assert!(source_pack_work_queue_page_dependency_count(&final_link) > 0);

    let already_complete =
        prepare_source_pack_filesystem_work_queue_pages_from_schedule_chunk_for_target(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            1,
        )
        .expect("completed work queue chunk should reopen index");
    assert!(already_complete.complete);
    assert_eq!(already_complete.new_work_item_count, 0);
    assert_eq!(already_complete.next_item_index, 7);

    let progress_first =
        prepare_source_pack_filesystem_work_queue_progress_from_queue_chunk_for_target(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            2,
            1,
        )
        .expect("prepare first work queue progress chunk");
    assert!(!progress_first.complete);
    assert_eq!(progress_first.work_item_count, 7);
    assert_eq!(progress_first.page_size, 2);
    assert_eq!(progress_first.page_count, 4);
    assert_eq!(progress_first.next_page_index, 1);
    assert_eq!(progress_first.new_progress_page_count, 1);
    assert_eq!(progress_first.artifact_item_count, 2);
    assert!(progress_first.ready_item_count > 0);
    assert!(progress_first.work_queue_progress_index_path.is_none());
    assert!(
        store
            .work_queue_progress_prepare_progress_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );
    assert!(
        !store
            .work_queue_progress_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );
    assert!(
        !store
            .work_queue_progress_page_path_for_target(SourcePackArtifactTarget::Wasm, 1)
            .is_file()
    );
    let first_progress_page = store
        .load_work_queue_progress_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load first chunked work queue progress page");
    assert_eq!(first_progress_page.item_count, 2);
    assert!(first_progress_page.ready_item_indices.contains(&0));

    let progress_final =
        prepare_source_pack_filesystem_work_queue_progress_from_queue_chunk_for_target(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            2,
            10,
        )
        .expect("prepare final work queue progress chunk");
    assert!(progress_final.complete);
    assert_eq!(progress_final.next_page_index, 4);
    assert_eq!(progress_final.new_progress_page_count, 3);
    assert_eq!(progress_final.artifact_item_count, 4);
    assert!(progress_final.work_queue_progress_index_path.is_some());
    assert!(
        store
            .work_queue_progress_directory_page_path_for_target(SourcePackArtifactTarget::Wasm, 0)
            .is_file()
    );
    assert!(
        store
            .work_queue_progress_directory_index_page_path_for_target(
                SourcePackArtifactTarget::Wasm,
                0
            )
            .is_file()
    );
    let progress_index = store
        .load_work_queue_progress_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load chunked work queue progress index");
    assert_eq!(progress_index.work_item_count, 7);
    assert_eq!(progress_index.page_size, 2);
    assert_eq!(progress_index.page_count, 4);
    assert_eq!(progress_index.artifact_item_count, 4);
    assert!(progress_index.ready_item_count > 0);

    let progress_already_complete =
        prepare_source_pack_filesystem_work_queue_progress_from_queue_chunk_for_target(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            2,
            1,
        )
        .expect("completed work queue progress chunk should reopen index");
    assert!(progress_already_complete.complete);
    assert_eq!(progress_already_complete.new_progress_page_count, 0);
    assert_eq!(progress_already_complete.next_page_index, 4);

    std::fs::remove_dir_all(&root).expect("remove temp work queue chunk dir");
}

#[test]
fn explicit_source_pack_path_streams_metadata_streams_without_materialized_path_slices() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-pack-path-streams-filesystem-metadata-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let stdlib_path = source_root.join("stdlib.lani");
    let user_path = source_root.join("user.lani");
    std::fs::write(&stdlib_path, b"core").expect("write stdlib source");
    std::fs::write(&user_path, b"user").expect("write user source");

    let prepared = prepare_explicit_source_pack_path_streams_filesystem_metadata_for_target(
        1,
        std::iter::once(stdlib_path.as_path()),
        1,
        std::iter::once(user_path.as_path()),
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare stdlib/user filesystem metadata from path streams");

    assert_eq!(prepared.target, SourcePackArtifactTarget::Wasm);
    assert_eq!(prepared.source_file_count, 2);
    assert_eq!(prepared.source_byte_count, 8);
    assert_eq!(prepared.library_count, 2);
    assert_eq!(prepared.library_partition_count, 2);
    assert_eq!(prepared.library_source_file_page_count, 2);

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let partition_index = store
        .load_library_partition_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load stdlib/user path-stream metadata partition index");
    assert_eq!(partition_index.partition_count, 2);
    assert_stored_partition_index_has_no_inline_partitions(&store, SourcePackArtifactTarget::Wasm);
    let user_partition = store
        .load_library_partition_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load path-stream user metadata partition");
    assert_eq!(user_partition.library_id, 1);
    assert!(user_partition.dependency_library_ids.is_empty());
    assert_eq!(user_partition.dependency_library_count, 1);
    assert_eq!(user_partition.dependency_page_count, 1);
    let dependency_page = store
        .load_library_dependency_page_for_target(SourcePackArtifactTarget::Wasm, 1, 0)
        .expect("load path-stream user metadata dependency page");
    assert_eq!(dependency_page.dependency_library_ids, vec![0]);
    let stdlib_record = store
        .load_library_source_file_record_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load path-stream stdlib metadata source-file record");
    assert_eq!(stdlib_record.library_id, 0);
    assert_eq!(stdlib_record.source_index, 0);
    assert_eq!(stdlib_record.file.byte_len, 4);
    let user_record = store
        .load_library_source_file_record_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load path-stream user metadata source-file record");
    assert_eq!(user_record.library_id, 1);
    assert_eq!(user_record.source_index, 1);
    assert_eq!(user_record.file.byte_len, 4);
    assert!(
        !store
            .library_schedule_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .exists(),
        "metadata-only path-stream prepare must not create a schedule index"
    );

    std::fs::remove_dir_all(&root).expect("remove temp pack path-streams filesystem metadata dir");
}

#[test]
fn ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_prepare_streams() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-ordered-path-dependency-stream-metadata-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let prepared =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
                [
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 10,
                        source_file_count: 1,
                        paths: std::iter::once(core_path),
                        dependency_library_count: 0,
                        dependency_library_ids: Vec::<u32>::new().into_iter(),
                    },
                    ExplicitSourceLibraryPathDependencyStream {
                        library_id: 20,
                        source_file_count: 1,
                        paths: std::iter::once(app_path),
                        dependency_library_count: 1,
                        dependency_library_ids: vec![10].into_iter(),
                    },
                ],
                &artifact_root,
                SourcePackArtifactTarget::Wasm,
            )
            .expect("prepare ordered path+dependency stream filesystem metadata");

    assert_eq!(prepared.target, SourcePackArtifactTarget::Wasm);
    assert_eq!(prepared.source_file_count, 2);
    assert_eq!(prepared.source_byte_count, 8);
    assert_eq!(prepared.library_count, 2);
    assert_eq!(prepared.library_partition_count, 2);
    assert_eq!(prepared.library_source_file_page_count, 2);

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let partition_index = store
        .load_library_partition_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load path+dependency stream metadata partition index");
    assert_eq!(partition_index.partition_count, 2);
    assert_stored_partition_index_has_no_inline_partitions(&store, SourcePackArtifactTarget::Wasm);
    let app_partition = store
        .load_library_partition_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load path+dependency stream metadata app partition");
    assert_eq!(app_partition.library_id, 20);
    assert!(app_partition.dependency_library_ids.is_empty());
    assert_eq!(app_partition.dependency_library_count, 1);
    assert_eq!(app_partition.dependency_page_count, 1);
    let app_dependency_page = store
        .load_library_dependency_page_for_target(SourcePackArtifactTarget::Wasm, 1, 0)
        .expect("load path+dependency stream metadata app dependency page");
    assert_eq!(app_dependency_page.dependency_library_ids, vec![10]);
    let app_source_page = store
        .load_library_source_file_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load path+dependency stream metadata app source-file page");
    assert_eq!(app_source_page.library_id, 20);
    assert!(
        app_source_page.source_files.is_empty(),
        "path+dependency stream metadata source-file page should be compact"
    );
    let app_record = store
        .load_library_source_file_record_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load path+dependency stream metadata app source-file record");
    assert_eq!(app_record.partition_index, 1);
    assert_eq!(app_record.library_id, 20);
    assert_eq!(app_record.source_index, 1);
    assert_eq!(app_record.file.byte_len, 4);
    assert!(
        !store
            .library_schedule_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .exists(),
        "path+dependency stream metadata prepare must not create a schedule index"
    );

    std::fs::remove_dir_all(&root)
        .expect("remove temp ordered path+dependency stream metadata dir");
}

#[test]
fn ordered_explicit_source_libraries_filesystem_metadata_prepare_streams() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-ordered-library-metadata-prepare-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    let cli_path = source_root.join("cli.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, [0xff, 0xfe, 0xfd, b'!']).expect("write invalid utf8 app source");
    std::fs::write(&cli_path, b"cli!!").expect("write cli source");

    let prepared = prepare_ordered_explicit_source_libraries_filesystem_metadata_for_target(
        [
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            },
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path],
                dependency_library_ids: vec![10],
            },
            ExplicitSourceLibraryPaths {
                library_id: 30,
                paths: vec![cli_path],
                dependency_library_ids: vec![20],
            },
        ],
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare ordered filesystem library metadata");

    assert_eq!(prepared.target, SourcePackArtifactTarget::Wasm);
    assert_eq!(prepared.source_file_count, 3);
    assert_eq!(prepared.source_byte_count, 13);
    assert_eq!(prepared.library_count, 3);
    assert_eq!(prepared.library_partition_count, 3);
    assert_eq!(prepared.library_source_file_page_count, 3);

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let partition_index = store
        .load_library_partition_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load ordered metadata partition index");
    assert_eq!(partition_index.partition_count, 3);
    assert_stored_partition_index_has_no_inline_partitions(&store, SourcePackArtifactTarget::Wasm);
    let app_locator = store
        .load_library_partition_locator_page_for_target(SourcePackArtifactTarget::Wasm, 20)
        .expect("load ordered metadata app partition locator");
    assert_eq!(app_locator.partition_index, 1);
    let app_partition = store
        .load_library_partition_for_target(
            SourcePackArtifactTarget::Wasm,
            app_locator.partition_index,
        )
        .expect("load ordered metadata app partition");
    assert_eq!(app_partition.library_id, 20);
    assert!(
        app_partition.dependency_library_ids.is_empty(),
        "ordered metadata partition pages should leave dependency libraries in dependency pages"
    );
    assert_eq!(
        source_pack_load_library_dependency_ids(&store, &app_partition)
            .expect("load ordered metadata app dependency pages"),
        vec![10]
    );
    assert!(
        !store
            .library_schedule_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .exists(),
        "ordered metadata prepare must not create a schedule index"
    );
    assert!(
        !store
            .build_manifest_path_for_target(SourcePackArtifactTarget::Wasm)
            .exists(),
        "ordered metadata prepare must not create a build manifest"
    );

    std::fs::remove_dir_all(&root).expect("remove temp ordered library metadata prepare dir");
}

#[test]
fn explicit_source_libraries_filesystem_metadata_prepare_avoids_build_manifest() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-library-metadata-prepare-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    let cli_path = source_root.join("cli.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, [0xff, 0xfe, 0xfd, b'!']).expect("write invalid utf8 app source");
    std::fs::write(&cli_path, b"cli!!").expect("write cli source");

    let prepared = prepare_explicit_source_libraries_filesystem_metadata_for_target(
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 30,
                paths: vec![cli_path],
                dependency_library_ids: vec![20],
            },
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path],
                dependency_library_ids: vec![10],
            },
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            },
        ],
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare filesystem library metadata without full build manifest");

    assert_eq!(prepared.target, SourcePackArtifactTarget::Wasm);
    assert_eq!(prepared.source_file_count, 3);
    assert_eq!(prepared.source_byte_count, 13);
    assert_eq!(prepared.library_count, 3);
    assert_eq!(prepared.library_partition_count, 3);
    assert_eq!(prepared.library_source_file_page_count, 3);
    assert!(
        prepared
            .library_partition_index_path
            .ends_with("source-pack-library-partitions.wasm.json")
    );

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    assert!(
        !store
            .build_manifest_path_for_target(SourcePackArtifactTarget::Wasm)
            .exists()
    );
    assert!(
        !store
            .artifact_manifest_path_for_target(SourcePackArtifactTarget::Wasm)
            .exists()
    );
    assert!(
        !store
            .build_state_path_for_target(SourcePackArtifactTarget::Wasm)
            .exists()
    );
    let partition_index = store
        .load_library_partition_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load metadata-only partition index");
    assert_eq!(partition_index.partition_count, 3);
    assert_eq!(partition_index.source_file_count, 3);
    assert_eq!(partition_index.source_byte_count, 13);
    assert_stored_partition_index_has_no_inline_partitions(&store, SourcePackArtifactTarget::Wasm);
    assert_eq!(
        (0..partition_index.partition_count)
            .map(|partition_index| {
                let partition = store
                    .load_library_partition_for_target(
                        SourcePackArtifactTarget::Wasm,
                        partition_index,
                    )
                    .expect("load metadata-only library partition");
                let dependency_library_ids =
                    source_pack_load_library_dependency_ids(&store, &partition)
                        .expect("load metadata-only partition dependencies");
                (
                    partition.library_id,
                    partition.first_source_index,
                    partition.source_file_count,
                    dependency_library_ids,
                )
            })
            .collect::<Vec<_>>(),
        vec![
            (10, 0, 1, Vec::new()),
            (20, 1, 1, vec![10]),
            (30, 2, 1, vec![20])
        ]
    );
    let app_page = store
        .load_library_source_file_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load metadata-only app source-file page");
    assert_eq!(app_page.library_id, 20);
    assert!(
        app_page.source_files.is_empty(),
        "metadata-only source-file pages should leave source-file records in per-file pages"
    );
    let app_record = store
        .load_library_source_file_record_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load metadata-only app source-file record");
    assert_eq!(app_record.partition_index, 1);
    assert_eq!(app_record.library_id, 20);
    assert_eq!(app_record.file.byte_len, 4);

    std::fs::write(
        store.build_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("write corrupt unrelated build manifest");
    let core_page = store
        .load_library_source_file_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load source-file page without reading corrupt build manifest");
    assert_eq!(core_page.library_id, 10);

    std::fs::remove_dir_all(&root).expect("remove temp library metadata prepare dir");
}

#[test]
fn source_pack_library_build_unit_page_plans_from_one_source_page() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-library-build-unit-page-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let partition = SourcePackLibraryPartition {
        version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
        target: SourcePackArtifactTarget::X86_64,
        partition_index: 1,
        library_id: 42,
        first_source_index: 100,
        source_file_count: 3,
        source_byte_count: 11,
        source_line_count: 0,
        dependency_library_ids: vec![7],
        dependency_library_count: 0,
        dependency_page_count: 0,
    };
    let source_file_page = SourcePackLibrarySourceFilePage {
        version: SOURCE_PACK_LIBRARY_SOURCE_FILE_PAGE_VERSION,
        target: SourcePackArtifactTarget::X86_64,
        partition_index: 1,
        library_id: 42,
        first_source_index: 100,
        source_file_count: 3,
        source_byte_count: 11,
        source_line_count: 0,
        source_files: vec![
            SourcePackShardSourceFile {
                source_index: 100,
                file: ExplicitSourcePathFile {
                    library_id: 42,
                    path: PathBuf::from("lib42/a.lani"),
                    byte_len: 4,
                    modified_unix_nanos: Some(1),
                    line_count: None,
                },
            },
            SourcePackShardSourceFile {
                source_index: 101,
                file: ExplicitSourcePathFile {
                    library_id: 42,
                    path: PathBuf::from("lib42/b.lani"),
                    byte_len: 5,
                    modified_unix_nanos: Some(2),
                    line_count: None,
                },
            },
            SourcePackShardSourceFile {
                source_index: 102,
                file: ExplicitSourcePathFile {
                    library_id: 42,
                    path: PathBuf::from("lib42/c.lani"),
                    byte_len: 2,
                    modified_unix_nanos: Some(3),
                    line_count: None,
                },
            },
        ],
    };
    let limits = CodegenUnitLimits {
        max_source_bytes: 7,
        max_source_files: 8,
    };
    let build_unit_page =
        source_pack_library_build_unit_page(&partition, &source_file_page, limits)
            .expect("build codegen units from one library source-file page");

    assert_eq!(build_unit_page.target, SourcePackArtifactTarget::X86_64);
    assert_eq!(build_unit_page.partition_index, 1);
    assert_eq!(build_unit_page.library_id, 42);
    assert_eq!(build_unit_page.dependency_library_ids, vec![7]);
    assert_eq!(build_unit_page.frontend_unit.first_source_index, 100);
    assert_eq!(build_unit_page.frontend_unit.source_file_count, 3);
    assert_eq!(
        build_unit_page
            .codegen_units
            .iter()
            .map(|unit| (
                unit.unit_index,
                unit.first_source_index,
                unit.source_file_count,
                unit.source_bytes,
                unit.oversized_source_file,
            ))
            .collect::<Vec<_>>(),
        vec![(0, 100, 1, 4, false), (1, 101, 2, 7, false)]
    );

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let build_unit_page_path = store
        .store_library_build_unit_page(&build_unit_page)
        .expect("store library build-unit page");
    assert!(build_unit_page_path.ends_with("source-pack-library-build-units-00000001.x86_64.json"));
    std::fs::write(
        store.library_source_file_page_path_for_target(SourcePackArtifactTarget::X86_64, 1),
        b"not json",
    )
    .expect("corrupt source-file page path");
    std::fs::write(
        store.library_partition_index_path_for_target(SourcePackArtifactTarget::X86_64),
        b"not json",
    )
    .expect("corrupt partition index path");
    let loaded = store
        .load_library_build_unit_page_for_target(SourcePackArtifactTarget::X86_64, 1)
        .expect("load build-unit page without reading source page or partition index");
    let mut compact_build_unit_page = build_unit_page.clone();
    compact_build_unit_page.dependency_library_ids.clear();
    compact_build_unit_page.frontend_units.clear();
    compact_build_unit_page.codegen_units.clear();
    assert_eq!(loaded, compact_build_unit_page);
    let build_unit_json = std::fs::read_to_string(
        store.library_build_unit_page_path_for_target(SourcePackArtifactTarget::X86_64, 1),
    )
    .expect("read persisted build-unit page json");
    assert!(
        !build_unit_json.contains("\"frontend_units\"")
            && !build_unit_json.contains("\"codegen_units\""),
        "persisted build-unit pages should leave unit records in per-unit pages"
    );
    assert!(
        !build_unit_page.frontend_units.is_empty(),
        "test should cover frontend-unit pages"
    );
    for unit in &build_unit_page.frontend_units {
        let loaded_unit = store
            .load_library_frontend_unit_page_for_target(
                SourcePackArtifactTarget::X86_64,
                build_unit_page.partition_index,
                unit.unit_index,
            )
            .expect("load spilled frontend-unit page");
        assert_eq!(
            loaded_unit.frontend_unit_count,
            build_unit_page.frontend_units.len()
        );
        assert_eq!(&loaded_unit.unit, unit);
    }
    for unit in &build_unit_page.codegen_units {
        let loaded_unit = store
            .load_library_codegen_unit_page_for_target(
                SourcePackArtifactTarget::X86_64,
                build_unit_page.partition_index,
                unit.unit_index,
            )
            .expect("load spilled codegen-unit page");
        assert_eq!(
            loaded_unit.codegen_unit_count,
            build_unit_page.codegen_units.len()
        );
        assert_eq!(&loaded_unit.unit, unit);
    }

    std::fs::remove_dir_all(&root).expect("remove temp library build-unit page dir");
}

#[test]
fn source_pack_library_schedule_pages_assign_global_jobs_from_build_unit_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-library-schedule-page-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let build_unit_pages = vec![
        SourcePackLibraryBuildUnitPage {
            version: SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            partition_index: 0,
            library_id: 10,
            dependency_library_ids: Vec::new(),
            first_source_index: 0,
            source_file_count: 2,
            source_byte_count: 9,
            source_line_count: 0,
            limits: CodegenUnitLimits {
                max_source_bytes: 5,
                max_source_files: 8,
            },
            frontend_unit: LibraryUnit {
                library_index: 0,
                library_id: 10,
                first_source_index: 0,
                source_file_count: 2,
                source_bytes: 9,
                source_lines: 0,
            },
            frontend_unit_count: 2,
            frontend_units: Vec::new(),
            codegen_unit_count: 2,
            codegen_units: vec![
                CodegenUnit {
                    unit_index: 0,
                    library_id: 10,
                    first_source_index: 0,
                    source_file_count: 1,
                    source_bytes: 4,
                    source_lines: 0,
                    oversized_source_file: false,
                },
                CodegenUnit {
                    unit_index: 1,
                    library_id: 10,
                    first_source_index: 1,
                    source_file_count: 1,
                    source_bytes: 5,
                    source_lines: 0,
                    oversized_source_file: false,
                },
            ],
        },
        SourcePackLibraryBuildUnitPage {
            version: SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            partition_index: 1,
            library_id: 20,
            dependency_library_ids: vec![10],
            first_source_index: 2,
            source_file_count: 1,
            source_byte_count: 3,
            source_line_count: 0,
            limits: CodegenUnitLimits {
                max_source_bytes: 5,
                max_source_files: 8,
            },
            frontend_unit: LibraryUnit {
                library_index: 0,
                library_id: 20,
                first_source_index: 2,
                source_file_count: 1,
                source_bytes: 3,
                source_lines: 0,
            },
            frontend_unit_count: 1,
            frontend_units: Vec::new(),
            codegen_unit_count: 1,
            codegen_units: vec![CodegenUnit {
                unit_index: 0,
                library_id: 20,
                first_source_index: 2,
                source_file_count: 1,
                source_bytes: 3,
                source_lines: 0,
                oversized_source_file: false,
            }],
        },
    ];

    let schedule_plan =
        source_pack_library_schedule_plan(&build_unit_pages).expect("build schedule plan");
    let schedule_index = &schedule_plan.index;
    assert_eq!(schedule_index.partition_count, 2);
    assert_eq!(schedule_index.codegen_job_count, 3);
    assert_eq!(schedule_index.link_job_index, 5);
    assert_eq!(
        schedule_plan
            .entries
            .iter()
            .map(|entry| (
                entry.library_id,
                entry.frontend_job_index,
                entry.first_codegen_job_index,
                entry.codegen_job_count,
            ))
            .collect::<Vec<_>>(),
        vec![(10, 0, 2, 2), (20, 1, 4, 1)]
    );
    let schedule_pages = source_pack_library_schedule_pages(&build_unit_pages, &schedule_plan)
        .expect("build schedule pages from build-unit pages");
    assert_eq!(schedule_pages.len(), 2);
    assert_eq!(
        schedule_pages[0].frontend_job.dependency_job_indices,
        Vec::<usize>::new()
    );
    assert_eq!(
        schedule_pages[0].codegen_jobs[0].dependency_job_indices,
        vec![0]
    );
    assert_eq!(schedule_pages[0].codegen_jobs[1].job_index, 3);
    assert_eq!(schedule_pages[0].codegen_jobs[1].phase_unit_index, 1);
    assert_eq!(
        schedule_pages[1].frontend_job.dependency_job_indices,
        vec![0]
    );
    assert_eq!(schedule_pages[1].codegen_jobs[0].job_index, 4);
    assert_eq!(schedule_pages[1].codegen_jobs[0].phase_unit_index, 2);
    assert_eq!(
        schedule_pages[1].codegen_jobs[0].dependency_job_indices,
        vec![1, 0]
    );

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let schedule_index_path = store
        .store_library_schedule_index(schedule_index)
        .expect("store schedule index");
    assert!(schedule_index_path.ends_with("source-pack-library-schedule.wasm.json"));
    let schedule_page_store = store
        .store_library_schedule_pages(&schedule_pages)
        .expect("store schedule pages");
    assert_eq!(schedule_page_store.library_schedule_page_count, 2);
    let stored_frontend_job = source_pack_stored_schedule_job(&store, schedule_index, 1)
        .expect("load stored frontend job from compact schedule page");
    assert_eq!(
        stored_frontend_job.dependency_job_indices,
        vec![0],
        "schedule-page store should spill frontend job dependencies to job pages"
    );
    let stored_codegen_job = source_pack_stored_schedule_job(&store, schedule_index, 4)
        .expect("load stored codegen job from compact schedule page");
    assert_eq!(
        stored_codegen_job.dependency_job_indices,
        vec![1, 0],
        "schedule-page store should spill codegen job dependencies to job pages"
    );
    std::fs::write(
        store.library_build_unit_page_path_for_target(SourcePackArtifactTarget::Wasm, 1),
        b"not json",
    )
    .expect("corrupt build-unit page path");
    std::fs::write(
        store.build_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt unrelated build manifest path");
    let loaded_schedule_page = store
        .load_library_schedule_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load schedule page without reading build-unit page or build manifest");
    let mut compact_schedule_page = schedule_pages[1].clone();
    compact_schedule_page.dependency_library_ids.clear();
    compact_schedule_page
        .frontend_job
        .dependency_job_indices
        .clear();
    compact_schedule_page.codegen_jobs.clear();
    assert_eq!(loaded_schedule_page, compact_schedule_page);
    assert_eq!(loaded_schedule_page.codegen_job_count, 1);
    assert!(
        loaded_schedule_page.codegen_jobs.is_empty(),
        "stored schedule pages should leave codegen jobs in per-job pages"
    );
    assert!(
        loaded_schedule_page
            .frontend_job
            .dependency_job_indices
            .is_empty(),
        "stored schedule pages should leave frontend dependencies in per-job dependency pages"
    );
    let loaded_schedule_index = store
        .load_library_schedule_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load schedule index without reading build-unit pages");
    assert_eq!(
        loaded_schedule_index.partition_count,
        schedule_index.partition_count
    );
    assert_eq!(
        loaded_schedule_index.codegen_job_count,
        schedule_index.codegen_job_count
    );
    assert_eq!(
        loaded_schedule_index.link_job_index,
        schedule_index.link_job_index
    );
    assert_eq!(loaded_schedule_index.job_count, schedule_index.job_count);
    assert_stored_schedule_index_has_no_inline_entries(&store, SourcePackArtifactTarget::Wasm);

    std::fs::remove_dir_all(&root).expect("remove temp library schedule page dir");
}

#[test]
fn source_pack_hierarchical_link_plan_groups_schedule_pages() {
    fn build_unit_page(
        partition_index: usize,
        library_id: u32,
        first_source_index: usize,
        dependency_library_ids: Vec<u32>,
    ) -> SourcePackLibraryBuildUnitPage {
        SourcePackLibraryBuildUnitPage {
            version: SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            partition_index,
            library_id,
            dependency_library_ids,
            first_source_index,
            source_file_count: 1,
            source_byte_count: 4,
            source_line_count: 0,
            limits: CodegenUnitLimits {
                max_source_bytes: 8,
                max_source_files: 8,
            },
            frontend_unit: LibraryUnit {
                library_index: 0,
                library_id,
                first_source_index,
                source_file_count: 1,
                source_bytes: 4,
                source_lines: 0,
            },
            frontend_unit_count: 1,
            frontend_units: Vec::new(),
            codegen_unit_count: 1,
            codegen_units: vec![CodegenUnit {
                unit_index: 0,
                library_id,
                first_source_index,
                source_file_count: 1,
                source_bytes: 4,
                source_lines: 0,
                oversized_source_file: false,
            }],
        }
    }

    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-hierarchical-link-plan-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let build_unit_pages = vec![
        build_unit_page(0, 10, 0, Vec::new()),
        build_unit_page(1, 20, 1, vec![10]),
        build_unit_page(2, 30, 2, vec![10, 20]),
    ];
    let schedule_plan =
        source_pack_library_schedule_plan(&build_unit_pages).expect("build schedule plan");
    let schedule_index = &schedule_plan.index;
    let schedule_pages = source_pack_library_schedule_pages(&build_unit_pages, &schedule_plan)
        .expect("build schedule pages");
    let limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 2,
        max_source_bytes_per_batch: 8,
        max_source_files_per_batch: 2,
    };
    let (link_plan_index, link_group_pages) =
        source_pack_hierarchical_link_plan(&schedule_index, &schedule_pages, limits)
            .expect("build hierarchical link plan");

    assert_eq!(link_plan_index.input_partition_count, 3);
    assert_eq!(
        link_plan_index.first_link_job_index,
        schedule_index.link_job_index
    );
    assert_eq!(link_plan_index.link_group_count, 6);
    assert_eq!(link_plan_index.final_link_group_index, 5);
    assert_eq!(
        link_plan_index.final_link_job_index,
        schedule_index.link_job_index + 5
    );
    assert_eq!(
        link_group_pages
            .iter()
            .map(|group| (
                group.group_index,
                group.kind,
                group.level,
                group.input_partition_indices.clone(),
                group.input_codegen_job_indices.clone(),
                group.input_link_group_indices.clone(),
            ))
            .collect::<Vec<_>>(),
        vec![
            (
                0,
                SourcePackHierarchicalLinkGroupKind::Leaf,
                0,
                vec![0],
                vec![3],
                Vec::new(),
            ),
            (
                1,
                SourcePackHierarchicalLinkGroupKind::Leaf,
                0,
                vec![1],
                vec![4],
                Vec::new(),
            ),
            (
                2,
                SourcePackHierarchicalLinkGroupKind::Leaf,
                0,
                vec![2],
                vec![5],
                Vec::new(),
            ),
            (
                3,
                SourcePackHierarchicalLinkGroupKind::Reduce,
                1,
                vec![0, 1],
                Vec::new(),
                vec![0, 1],
            ),
            (
                4,
                SourcePackHierarchicalLinkGroupKind::Reduce,
                1,
                vec![2],
                Vec::new(),
                vec![2],
            ),
            (
                5,
                SourcePackHierarchicalLinkGroupKind::Reduce,
                2,
                vec![0, 1, 2],
                Vec::new(),
                vec![3, 4],
            ),
        ]
    );
    assert!(!link_group_pages[1].oversized_input);
    assert_eq!(link_group_pages[2].input_frontend_job_count, 3);
    assert!(
        link_group_pages[2].oversized_input,
        "leaf link groups must account for large frontend/interface fan-in"
    );

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let link_plan_path = store
        .store_hierarchical_link_plan(&link_plan_index, &link_group_pages)
        .expect("store hierarchical link plan");
    assert!(link_plan_path.ends_with("source-pack-hierarchical-link-plan.wasm.json"));
    std::fs::write(
        store.library_schedule_page_path_for_target(SourcePackArtifactTarget::Wasm, 2),
        b"not json",
    )
    .expect("corrupt schedule page path");
    std::fs::write(
        store.build_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt unrelated build manifest path");
    let loaded_final_group = store
        .load_hierarchical_link_group_page_for_target(SourcePackArtifactTarget::Wasm, 5)
        .expect("load final link group without reading schedule pages or build manifest");
    let mut expected_final_group = link_group_pages[5].clone();
    expected_final_group.input_partition_count = expected_final_group.input_partition_indices.len();
    expected_final_group.input_partition_indices.clear();
    expected_final_group.input_frontend_job_count =
        expected_final_group.input_frontend_job_indices.len();
    expected_final_group.input_frontend_job_indices.clear();
    assert_eq!(loaded_final_group, expected_final_group);
    let loaded_app_leaf_group = store
        .load_hierarchical_link_group_page_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load app link group without reading schedule pages or build manifest");
    assert!(loaded_app_leaf_group.input_frontend_job_indices.is_empty());
    assert_eq!(
        loaded_app_leaf_group.input_frontend_job_count,
        link_group_pages[1].input_frontend_job_indices.len()
    );
    let loaded_link_plan = store
        .load_hierarchical_link_plan_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load hierarchical link plan index");
    assert_eq!(
        loaded_link_plan.link_group_count,
        link_plan_index.link_group_count
    );
    assert_eq!(
        loaded_link_plan.final_link_group_index,
        link_plan_index.final_link_group_index
    );
    let link_plan_index_json = String::from_utf8(
        std::fs::read(
            store.hierarchical_link_plan_index_path_for_target(SourcePackArtifactTarget::Wasm),
        )
        .expect("read hierarchical link plan index"),
    )
    .expect("hierarchical link plan index is utf8");
    assert!(
        !link_plan_index_json.contains("\"groups\""),
        "persisted hierarchical link plan index should leave group summaries in group pages"
    );

    std::fs::remove_dir_all(&root).expect("remove temp hierarchical link plan dir");
}

#[test]
fn source_pack_hierarchical_link_execution_pages_derive_refs_from_schedule_pages() {
    fn compact_expected_execution_page(
        page: &SourcePackHierarchicalLinkExecutionPage,
    ) -> SourcePackHierarchicalLinkExecutionPage {
        let mut expected = page.clone();
        expected.input_interface_count = page.input_interfaces.len().saturating_add(
            source_pack_job_index_range_dependency_count(&page.input_interface_ranges),
        );
        expected.input_interface_page_count = page
            .input_interfaces
            .len()
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE);
        expected.input_interfaces.clear();
        expected.input_object_count = page.input_objects.len();
        expected.input_object_page_count = page
            .input_objects
            .len()
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE);
        expected.input_objects.clear();
        expected.input_group_count = page.input_group_indices.len();
        expected.input_group_page_count = page
            .input_group_indices
            .len()
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE);
        expected.input_group_indices.clear();
        expected.input_group_output_keys.clear();
        expected
    }

    fn build_unit_page(
        partition_index: usize,
        library_id: u32,
        first_source_index: usize,
        dependency_library_ids: Vec<u32>,
    ) -> SourcePackLibraryBuildUnitPage {
        SourcePackLibraryBuildUnitPage {
            version: SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            partition_index,
            library_id,
            dependency_library_ids,
            first_source_index,
            source_file_count: 1,
            source_byte_count: 4,
            source_line_count: 0,
            limits: CodegenUnitLimits {
                max_source_bytes: 8,
                max_source_files: 8,
            },
            frontend_unit: LibraryUnit {
                library_index: 0,
                library_id,
                first_source_index,
                source_file_count: 1,
                source_bytes: 4,
                source_lines: 0,
            },
            frontend_unit_count: 1,
            frontend_units: Vec::new(),
            codegen_unit_count: 1,
            codegen_units: vec![CodegenUnit {
                unit_index: 0,
                library_id,
                first_source_index,
                source_file_count: 1,
                source_bytes: 4,
                source_lines: 0,
                oversized_source_file: false,
            }],
        }
    }

    let build_unit_pages = vec![
        build_unit_page(0, 10, 0, Vec::new()),
        build_unit_page(1, 20, 1, vec![10]),
        build_unit_page(2, 30, 2, vec![20]),
    ];
    let schedule_plan =
        source_pack_library_schedule_plan(&build_unit_pages).expect("build schedule plan");
    let schedule_index = &schedule_plan.index;
    let schedule_pages = source_pack_library_schedule_pages(&build_unit_pages, &schedule_plan)
        .expect("build schedule pages");
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 2,
        max_source_bytes_per_batch: 8,
        max_source_files_per_batch: 2,
    };
    let metadata =
        source_pack_build_artifact_page_metadata(&schedule_index, &schedule_pages, batch_limits)
            .expect("derive artifact metadata from schedule pages");
    let (link_plan_index, link_group_pages) =
        source_pack_hierarchical_link_plan(&schedule_index, &schedule_pages, batch_limits)
            .expect("build hierarchical link plan");
    let page_execution = source_pack_hierarchical_link_execution_plan_from_schedule_pages(
        &link_plan_index,
        &link_group_pages,
        &schedule_index,
        &schedule_pages,
    )
    .expect("build hierarchical link execution from schedule pages");

    let path_manifest = ExplicitSourcePackPathManifest {
        files: vec![
            ExplicitSourcePathFile {
                library_id: 10,
                path: PathBuf::from("core.lani"),
                byte_len: 4,
                modified_unix_nanos: Some(1),
                line_count: None,
            },
            ExplicitSourcePathFile {
                library_id: 20,
                path: PathBuf::from("app.lani"),
                byte_len: 4,
                modified_unix_nanos: Some(2),
                line_count: None,
            },
            ExplicitSourcePathFile {
                library_id: 30,
                path: PathBuf::from("cli.lani"),
                byte_len: 4,
                modified_unix_nanos: Some(3),
                line_count: None,
            },
        ],
        library_dependencies: vec![
            SourcePackLibraryDependency {
                library_id: 20,
                depends_on_library_id: 10,
            },
            SourcePackLibraryDependency {
                library_id: 30,
                depends_on_library_id: 20,
            },
        ],
    };
    let artifact_manifest = path_manifest
        .build_plan(CodegenUnitLimits {
            max_source_bytes: 8,
            max_source_files: 8,
        })
        .retained_build_artifact_manifest_for_target(batch_limits, SourcePackArtifactTarget::Wasm);
    let legacy_execution = source_pack_hierarchical_link_execution_plan(
        &link_plan_index,
        &link_group_pages,
        &artifact_manifest,
    )
    .expect("build hierarchical link execution from legacy artifact manifest");

    assert_eq!(metadata.artifact_count, artifact_manifest.artifact_count);
    assert_eq!(metadata.scheduled_job_count, artifact_manifest.job_count);
    assert_eq!(page_execution, legacy_execution);
    assert_eq!(
        page_execution.0.final_output_key,
        "wasm/linked-output/job-6/src-0-3"
    );
    assert!(
        page_execution
            .1
            .iter()
            .any(|page| page.kind == SourcePackHierarchicalLinkGroupKind::Reduce),
        "test should cover reduce-link pages, not only leaf pages"
    );

    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-hierarchical-link-execution-page-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let execution_index_path = store
        .store_hierarchical_link_execution(&page_execution.0, &page_execution.1)
        .expect("store direct hierarchical link execution pages");
    assert!(execution_index_path.ends_with("source-pack-hierarchical-link-execution.wasm.json"));

    let leaf_page = page_execution
        .1
        .iter()
        .find(|page| {
            page.kind == SourcePackHierarchicalLinkGroupKind::Leaf
                && !page.input_interfaces.is_empty()
                && !page.input_objects.is_empty()
        })
        .expect("find leaf execution page with interface and object inputs");
    let loaded_leaf_page = store
        .load_hierarchical_link_execution_page_for_target(
            SourcePackArtifactTarget::Wasm,
            leaf_page.group_index,
        )
        .expect("load compact leaf hierarchical link execution page");
    assert_eq!(loaded_leaf_page, compact_expected_execution_page(leaf_page));
    assert!(loaded_leaf_page.input_interfaces.is_empty());
    assert!(loaded_leaf_page.input_objects.is_empty());
    assert_eq!(loaded_leaf_page.input_interface_page_count, 1);
    assert_eq!(loaded_leaf_page.input_object_page_count, 1);
    let leaf_interface_page = store
        .load_hierarchical_link_execution_interface_page_for_target(
            SourcePackArtifactTarget::Wasm,
            leaf_page.group_index,
            0,
        )
        .expect("load leaf interface input page");
    assert_eq!(
        leaf_interface_page.input_interfaces,
        leaf_page.input_interfaces
    );
    let leaf_object_page = store
        .load_hierarchical_link_execution_object_page_for_target(
            SourcePackArtifactTarget::Wasm,
            leaf_page.group_index,
            0,
        )
        .expect("load leaf object input page");
    assert_eq!(leaf_object_page.input_objects, leaf_page.input_objects);

    let reduce_page = page_execution
        .1
        .iter()
        .find(|page| {
            page.kind == SourcePackHierarchicalLinkGroupKind::Reduce
                && !page.input_group_indices.is_empty()
        })
        .expect("find reduce execution page with partial-link inputs");
    let loaded_reduce_page = store
        .load_hierarchical_link_execution_page_for_target(
            SourcePackArtifactTarget::Wasm,
            reduce_page.group_index,
        )
        .expect("load compact reduce hierarchical link execution page");
    assert_eq!(
        loaded_reduce_page,
        compact_expected_execution_page(reduce_page)
    );
    assert!(loaded_reduce_page.input_group_indices.is_empty());
    assert!(loaded_reduce_page.input_group_output_keys.is_empty());
    assert_eq!(loaded_reduce_page.input_group_page_count, 1);
    let reduce_partial_page = store
        .load_hierarchical_link_execution_partial_page_for_target(
            SourcePackArtifactTarget::Wasm,
            reduce_page.group_index,
            0,
        )
        .expect("load reduce partial-link input page");
    assert_eq!(
        reduce_partial_page.input_group_indices,
        reduce_page.input_group_indices
    );
    assert_eq!(
        reduce_partial_page.input_group_output_keys,
        reduce_page.input_group_output_keys
    );

    std::fs::remove_dir_all(&root).expect("remove temp hierarchical link execution page dir");
}

#[test]
fn source_pack_hierarchical_link_execution_store_spills_large_inline_inputs() {
    fn artifact_ref(
        target: SourcePackArtifactTarget,
        kind: SourcePackArtifactKind,
        artifact_index: usize,
    ) -> SourcePackArtifactRef {
        SourcePackArtifactRef {
            artifact_index,
            key: source_pack_artifact_key_for_output(
                target,
                kind,
                7,
                artifact_index,
                artifact_index,
                1,
            ),
            producing_job_index: artifact_index,
            kind,
        }
    }

    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-hierarchical-link-execution-spill-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let record_count = SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE + 1;
    let leaf_job_index = record_count + 100;
    let leaf_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: 0,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: leaf_job_index,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: (0..record_count)
            .map(|artifact_index| {
                artifact_ref(
                    target,
                    SourcePackArtifactKind::LibraryInterface,
                    artifact_index,
                )
            })
            .collect(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: (0..record_count)
            .map(|artifact_index| {
                artifact_ref(
                    target,
                    SourcePackArtifactKind::CodegenObject,
                    artifact_index,
                )
            })
            .collect(),
        input_group_count: 0,
        input_group_page_count: 0,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: record_count,
        source_file_count: record_count,
        source_line_count: record_count,
        output_key: source_pack_hierarchical_link_partial_output_key(target, 0, leaf_job_index),
        final_output: false,
    };

    store
        .store_hierarchical_link_execution_page(&leaf_page)
        .expect("store large inline leaf inputs through compact pages");
    let loaded_leaf = store
        .load_hierarchical_link_execution_page_for_target(target, leaf_page.group_index)
        .expect("load compact leaf execution page");
    assert!(loaded_leaf.input_interfaces.is_empty());
    assert!(loaded_leaf.input_objects.is_empty());
    assert_eq!(loaded_leaf.input_interface_count, record_count);
    assert_eq!(loaded_leaf.input_object_count, record_count);
    assert_eq!(loaded_leaf.input_interface_page_count, 2);
    assert_eq!(loaded_leaf.input_object_page_count, 2);
    assert_eq!(
        store
            .load_hierarchical_link_execution_interface_page_for_target(target, 0, 0)
            .expect("load first spilled interface page")
            .input_interfaces
            .len(),
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE
    );
    assert_eq!(
        store
            .load_hierarchical_link_execution_interface_page_for_target(target, 0, 1)
            .expect("load second spilled interface page")
            .input_interfaces
            .len(),
        1
    );
    assert_eq!(
        store
            .load_hierarchical_link_execution_object_page_for_target(target, 0, 0)
            .expect("load first spilled object page")
            .input_objects
            .len(),
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE
    );
    assert_eq!(
        store
            .load_hierarchical_link_execution_object_page_for_target(target, 0, 1)
            .expect("load second spilled object page")
            .input_objects
            .len(),
        1
    );

    let partial_record_count =
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE + 1;
    let reduce_group_index = partial_record_count + 1;
    let reduce_job_index = partial_record_count + 200;
    let reduce_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: reduce_group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Reduce,
        job_index: reduce_job_index,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: Vec::new(),
        input_group_count: 0,
        input_group_page_count: 0,
        input_group_indices: (0..partial_record_count).collect(),
        input_group_output_keys: (0..partial_record_count)
            .map(|group_index| {
                source_pack_hierarchical_link_partial_output_key(
                    target,
                    group_index,
                    group_index + 100,
                )
            })
            .collect(),
        source_byte_count: partial_record_count,
        source_file_count: partial_record_count,
        source_line_count: partial_record_count,
        output_key: source_pack_hierarchical_link_partial_output_key(
            target,
            reduce_group_index,
            reduce_job_index,
        ),
        final_output: false,
    };

    store
        .store_hierarchical_link_execution_page(&reduce_page)
        .expect("store large inline reduce inputs through compact pages");
    let loaded_reduce = store
        .load_hierarchical_link_execution_page_for_target(target, reduce_group_index)
        .expect("load compact reduce execution page");
    assert!(loaded_reduce.input_group_indices.is_empty());
    assert!(loaded_reduce.input_group_output_keys.is_empty());
    assert_eq!(loaded_reduce.input_group_count, partial_record_count);
    assert_eq!(loaded_reduce.input_group_page_count, 2);
    assert_eq!(
            store
                .load_hierarchical_link_execution_partial_page_for_target(
                    target,
                    reduce_group_index,
                    0,
                )
                .expect("load first spilled partial-link page")
                .input_group_indices
                .len(),
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE
        );
    assert_eq!(
            store
                .load_hierarchical_link_execution_partial_page_for_target(
                    target,
                    reduce_group_index,
                    1,
                )
                .expect("load second spilled partial-link page")
                .input_group_indices
                .len(),
            1
        );

    std::fs::remove_dir_all(&root).expect("remove hierarchical link execution spill test dir");
}

#[test]
fn source_pack_work_queue_pages_encode_prior_dependencies() {
    fn build_unit_page(
        partition_index: usize,
        library_id: u32,
        first_source_index: usize,
        dependency_library_ids: Vec<u32>,
    ) -> SourcePackLibraryBuildUnitPage {
        SourcePackLibraryBuildUnitPage {
            version: SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            partition_index,
            library_id,
            dependency_library_ids,
            first_source_index,
            source_file_count: 1,
            source_byte_count: 4,
            source_line_count: 0,
            limits: CodegenUnitLimits {
                max_source_bytes: 8,
                max_source_files: 8,
            },
            frontend_unit: LibraryUnit {
                library_index: 0,
                library_id,
                first_source_index,
                source_file_count: 1,
                source_bytes: 4,
                source_lines: 0,
            },
            frontend_unit_count: 1,
            frontend_units: Vec::new(),
            codegen_unit_count: 1,
            codegen_units: vec![CodegenUnit {
                unit_index: 0,
                library_id,
                first_source_index,
                source_file_count: 1,
                source_bytes: 4,
                source_lines: 0,
                oversized_source_file: false,
            }],
        }
    }

    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-page-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let build_unit_pages = vec![
        build_unit_page(0, 10, 0, Vec::new()),
        build_unit_page(1, 20, 1, vec![10]),
        build_unit_page(2, 30, 2, vec![20]),
    ];
    let schedule_plan =
        source_pack_library_schedule_plan(&build_unit_pages).expect("build schedule plan");
    let schedule_index = &schedule_plan.index;
    let schedule_pages = source_pack_library_schedule_pages(&build_unit_pages, &schedule_plan)
        .expect("build schedule pages");
    let (link_plan_index, link_group_pages) = source_pack_hierarchical_link_plan(
        &schedule_index,
        &schedule_pages,
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 2,
            max_source_bytes_per_batch: 8,
            max_source_files_per_batch: 2,
        },
    )
    .expect("build hierarchical link plan");
    let (work_queue_index, work_queue_pages) = source_pack_work_queue(
        &schedule_index,
        &schedule_pages,
        &link_plan_index,
        &link_group_pages,
    )
    .expect("build work queue");

    assert_eq!(work_queue_index.work_item_count, 12);
    assert_eq!(work_queue_index.final_item_index, 11);
    assert_eq!(
        work_queue_pages[0].kind,
        SourcePackWorkQueueItemKind::LibraryFrontend
    );
    assert_eq!(
        work_queue_pages[0].dependency_item_indices,
        Vec::<usize>::new()
    );
    assert_eq!(work_queue_pages[1].dependency_item_indices, vec![0]);
    assert_eq!(
        work_queue_pages[4].kind,
        SourcePackWorkQueueItemKind::Codegen
    );
    assert_eq!(work_queue_pages[4].dependency_item_indices, vec![1, 0]);
    assert_eq!(
        work_queue_pages[6].kind,
        SourcePackWorkQueueItemKind::LinkLeaf
    );
    assert_eq!(work_queue_pages[6].dependency_item_indices, vec![0, 3]);
    assert_eq!(work_queue_pages[7].dependency_item_indices, vec![0, 1, 4]);
    assert_eq!(
        work_queue_pages[9].kind,
        SourcePackWorkQueueItemKind::LinkReduce
    );
    assert_eq!(work_queue_pages[9].dependency_item_indices, vec![6, 7]);
    assert_eq!(work_queue_pages[11].dependency_item_indices, vec![9, 10]);

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let work_queue_index_path = store
        .store_work_queue(&work_queue_index, &work_queue_pages)
        .expect("store work queue");
    assert!(work_queue_index_path.ends_with("source-pack-work-queue.wasm.json"));
    std::fs::write(
        store.hierarchical_link_plan_index_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt hierarchical link plan index path");
    std::fs::write(
        store.library_schedule_page_path_for_target(SourcePackArtifactTarget::Wasm, 2),
        b"not json",
    )
    .expect("corrupt schedule page path");
    let loaded_final = store
        .load_work_queue_page_for_target(SourcePackArtifactTarget::Wasm, 11)
        .expect("load final work item without schedule/link plans");
    let mut expected_final = work_queue_pages[11].clone();
    expected_final.dependency_item_count = expected_final.dependency_item_indices.len();
    expected_final.dependency_page_count = expected_final
        .dependency_item_count
        .div_ceil(SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE);
    expected_final.dependency_item_indices.clear();
    expected_final.dependent_item_count = expected_final.dependent_item_indices.len();
    expected_final.dependent_page_count = expected_final
        .dependent_item_count
        .div_ceil(SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE);
    expected_final.dependent_item_indices.clear();
    expected_final.input_frontend_job_count = expected_final
        .input_frontend_job_count
        .max(expected_final.input_frontend_job_indices.len());
    expected_final.input_frontend_job_indices.clear();
    if matches!(expected_final.kind, SourcePackWorkQueueItemKind::LinkReduce) {
        expected_final.partition_count = expected_final
            .partition_count
            .max(expected_final.partition_indices.len());
        expected_final.partition_indices.clear();
    }
    assert_eq!(loaded_final, expected_final);
    let final_dependency_page = store
        .load_work_queue_dependencies_page_for_target(SourcePackArtifactTarget::Wasm, 11, 0)
        .expect("load final work item dependencies without schedule/link plans");
    assert_eq!(final_dependency_page.dependency_item_indices, vec![9, 10]);
    let loaded_first = store
        .load_work_queue_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load first work item without schedule/link plans");
    assert!(loaded_first.dependent_item_indices.is_empty());
    assert_eq!(
        loaded_first.dependent_item_count,
        work_queue_pages[0].dependent_item_indices.len()
    );
    let first_dependent_page = store
        .load_work_queue_dependents_page_for_target(SourcePackArtifactTarget::Wasm, 0, 0)
        .expect("load first work item dependents without schedule/link plans");
    assert_eq!(
        first_dependent_page.dependent_item_indices,
        work_queue_pages[0].dependent_item_indices
    );
    let loaded_index = store
        .load_work_queue_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load work queue index without schedule/link plans");
    assert_eq!(
        loaded_index.work_item_count,
        work_queue_index.work_item_count
    );
    assert_eq!(
        loaded_index.final_item_index,
        work_queue_index.final_item_index
    );
    assert_eq!(
        loaded_index.final_job_index,
        work_queue_index.final_job_index
    );
    let work_queue_index_json = String::from_utf8(
        std::fs::read(store.work_queue_index_path_for_target(SourcePackArtifactTarget::Wasm))
            .expect("read work queue index"),
    )
    .expect("work queue index is utf8");
    assert!(
        !work_queue_index_json.contains("\"items\""),
        "persisted work queue index should leave per-item summaries in work item pages"
    );

    std::fs::remove_dir_all(&root).expect("remove temp work queue page dir");
}

#[test]
fn source_pack_work_queue_page_store_compacts_link_metadata() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-link-metadata-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let leaf_page = SourcePackWorkQueuePage {
        version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
        target,
        item_index: 4,
        kind: SourcePackWorkQueueItemKind::LinkLeaf,
        job_index: 4,
        dependency_item_indices: vec![0, 1, 2, 3],
        dependency_item_count: 0,
        dependency_page_count: 0,
        dependency_item_ranges: Vec::new(),
        dependent_item_indices: Vec::new(),
        dependent_item_count: 0,
        dependent_page_count: 0,
        dependent_item_ranges: Vec::new(),
        artifact_batch_index: None,
        partition_count: 1,
        partition_indices: vec![0],
        link_group_index: Some(0),
        input_frontend_job_count: SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 1,
        input_frontend_job_indices: (0..=SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE).collect(),
        input_codegen_job_count: 1,
        input_codegen_job_indices: vec![3],
        input_link_group_count: 0,
        input_link_group_indices: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
    };

    store
        .store_work_queue_page(&leaf_page)
        .expect("store compact link leaf page");
    let loaded_leaf = store
        .load_work_queue_page_for_target(target, leaf_page.item_index)
        .expect("load compact link leaf page");
    assert_eq!(
        loaded_leaf.input_frontend_job_count,
        SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 1
    );
    assert!(loaded_leaf.input_frontend_job_indices.is_empty());
    assert_eq!(loaded_leaf.input_codegen_job_indices, vec![3]);

    let reduce_page = SourcePackWorkQueuePage {
        version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
        target,
        item_index: 70,
        kind: SourcePackWorkQueueItemKind::LinkReduce,
        job_index: 70,
        dependency_item_indices: vec![60, 61],
        dependency_item_count: 0,
        dependency_page_count: 0,
        dependency_item_ranges: Vec::new(),
        dependent_item_indices: Vec::new(),
        dependent_item_count: 0,
        dependent_page_count: 0,
        dependent_item_ranges: Vec::new(),
        artifact_batch_index: None,
        partition_count: SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 1,
        partition_indices: (0..=SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE).collect(),
        link_group_index: Some(66),
        input_frontend_job_count: 0,
        input_frontend_job_indices: Vec::new(),
        input_codegen_job_count: 0,
        input_codegen_job_indices: Vec::new(),
        input_link_group_count: 2,
        input_link_group_indices: vec![60, 61],
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
    };

    store
        .store_work_queue_page(&reduce_page)
        .expect("store compact link reduce page");
    let loaded_reduce = store
        .load_work_queue_page_for_target(target, reduce_page.item_index)
        .expect("load compact link reduce page");
    assert_eq!(
        loaded_reduce.partition_count,
        SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 1
    );
    assert!(loaded_reduce.partition_indices.is_empty());
    assert_eq!(loaded_reduce.input_link_group_indices, vec![60, 61]);

    std::fs::remove_dir_all(&root).expect("remove temp work queue link metadata dir");
}

#[test]
fn source_pack_work_queue_dependency_writer_rejects_duplicate_dependencies_across_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-writer-duplicate-dependency-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let item_index = SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE * 2 + 2;
    let work_item_count = item_index + 1;
    let compile_page = |item_index: usize,
                        dependent_item_count: usize,
                        dependent_page_count: usize|
     -> SourcePackWorkQueuePage {
        SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index,
            kind: SourcePackWorkQueueItemKind::LibraryFrontend,
            job_index: item_index,
            dependency_item_indices: Vec::new(),
            dependency_item_count: 0,
            dependency_page_count: 0,
            dependency_item_ranges: Vec::new(),
            dependent_item_indices: Vec::new(),
            dependent_item_count,
            dependent_page_count,
            dependent_item_ranges: Vec::new(),
            artifact_batch_index: None,
            partition_count: 1,
            partition_indices: vec![item_index],
            link_group_index: None,
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 0,
            input_codegen_job_indices: Vec::new(),
            input_link_group_count: 0,
            input_link_group_indices: Vec::new(),
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        }
    };

    let initial_dependent_count = SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE * 2 - 1;
    store
        .store_work_queue_page(&compile_page(0, initial_dependent_count, 2))
        .expect("store dependency page with nearly full dependent pages");
    store
        .store_work_queue_dependents_page(&SourcePackWorkQueueDependentsPage {
            version: SOURCE_PACK_WORK_QUEUE_DEPENDENTS_PAGE_VERSION,
            target,
            item_index: 0,
            page_index: 0,
            first_dependent_position: 0,
            dependent_count: SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE,
            dependent_item_indices: (1..=SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE)
                .collect(),
        })
        .expect("store first prefilled dependent page");
    store
        .store_work_queue_dependents_page(&SourcePackWorkQueueDependentsPage {
            version: SOURCE_PACK_WORK_QUEUE_DEPENDENTS_PAGE_VERSION,
            target,
            item_index: 0,
            page_index: 1,
            first_dependent_position: SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE,
            dependent_count: SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE - 1,
            dependent_item_indices: ((SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE + 2)
                ..(item_index - 1))
                .collect(),
        })
        .expect("store second nearly full dependent page");

    for dependency_item_index in 1..SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE {
        store
            .store_work_queue_page(&compile_page(dependency_item_index, 0, 0))
            .expect("store dependency work queue page");
    }

    let page = SourcePackWorkQueuePage {
        version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
        target,
        item_index,
        kind: SourcePackWorkQueueItemKind::LinkReduce,
        job_index: item_index,
        dependency_item_indices: Vec::new(),
        dependency_item_count: 0,
        dependency_page_count: 0,
        dependency_item_ranges: Vec::new(),
        dependent_item_indices: Vec::new(),
        dependent_item_count: 0,
        dependent_page_count: 0,
        dependent_item_ranges: Vec::new(),
        artifact_batch_index: None,
        partition_count: 1,
        partition_indices: Vec::new(),
        link_group_index: Some(item_index),
        input_frontend_job_count: 0,
        input_frontend_job_indices: Vec::new(),
        input_codegen_job_count: 0,
        input_codegen_job_indices: Vec::new(),
        input_link_group_count: 1,
        input_link_group_indices: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
    };
    let err = store_source_pack_work_queue_page_with_dependency_writer(
        &store,
        &page,
        work_item_count,
        |writer| {
            writer.push(0)?;
            for dependency_item_index in 1..SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE {
                writer.push(dependency_item_index)?;
            }
            writer.push(0)
        },
    )
    .expect_err("duplicate dependency across writer pages should be rejected");
    assert!(
        err.to_string().contains("duplicate dependency item 0"),
        "unexpected duplicate dependency error: {err}"
    );
    let dependency_zero = store
        .load_work_queue_page_for_target(target, 0)
        .expect("load dependency zero after rejected duplicate");
    assert_eq!(
        dependency_zero.dependent_item_count,
        SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE * 2
    );
    assert!(
        !store
            .work_queue_dependents_page_path_for_target(target, 0, 2)
            .exists(),
        "duplicate dependency must not create a cross-page duplicate dependent edge"
    );

    std::fs::remove_dir_all(&root).expect("remove temp work queue duplicate writer dir");
}

#[test]
fn source_pack_work_queue_dependency_writer_rejects_duplicates_between_ranges_and_explicit_dependencies()
 {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-writer-range-duplicate-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let item_index = 4;
    let work_item_count = item_index + 1;
    let work_queue_page =
        |item_index: usize, kind: SourcePackWorkQueueItemKind| SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index,
            kind,
            job_index: item_index,
            dependency_item_indices: Vec::new(),
            dependency_item_count: 0,
            dependency_page_count: 0,
            dependency_item_ranges: Vec::new(),
            dependent_item_indices: Vec::new(),
            dependent_item_count: 0,
            dependent_page_count: 0,
            dependent_item_ranges: Vec::new(),
            artifact_batch_index: None,
            partition_count: 1,
            partition_indices: vec![item_index],
            link_group_index: matches!(kind, SourcePackWorkQueueItemKind::LinkReduce)
                .then_some(item_index),
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 0,
            input_codegen_job_indices: Vec::new(),
            input_link_group_count: matches!(kind, SourcePackWorkQueueItemKind::LinkReduce)
                as usize,
            input_link_group_indices: Vec::new(),
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        };

    for dependency_item_index in 0..item_index {
        store
            .store_work_queue_page(&work_queue_page(
                dependency_item_index,
                SourcePackWorkQueueItemKind::LibraryFrontend,
            ))
            .expect("store dependency work queue page");
    }
    let page = work_queue_page(item_index, SourcePackWorkQueueItemKind::LinkReduce);
    let err = store_source_pack_work_queue_page_with_dependency_writer(
        &store,
        &page,
        work_item_count,
        |writer| {
            writer.push_range(0, 3)?;
            writer.push(1)
        },
    )
    .expect_err("explicit dependency already covered by a compact range should be rejected");
    assert!(
        err.to_string()
            .contains("duplicate ranged dependency item 1"),
        "unexpected duplicate range dependency error: {err}"
    );

    std::fs::remove_dir_all(&root).expect("remove temp work queue range duplicate writer dir");
}

#[test]
fn source_pack_work_queue_dependency_writer_preserves_reverse_dependent_ranges() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-writer-dependent-range-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let work_item_count = 4;
    let work_queue_page =
        |item_index: usize, kind: SourcePackWorkQueueItemKind| SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index,
            kind,
            job_index: item_index,
            dependency_item_indices: Vec::new(),
            dependency_item_count: 0,
            dependency_page_count: 0,
            dependency_item_ranges: Vec::new(),
            dependent_item_indices: Vec::new(),
            dependent_item_count: 0,
            dependent_page_count: 0,
            dependent_item_ranges: Vec::new(),
            artifact_batch_index: None,
            partition_count: 1,
            partition_indices: vec![item_index],
            link_group_index: matches!(kind, SourcePackWorkQueueItemKind::LinkReduce)
                .then_some(item_index),
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 0,
            input_codegen_job_indices: Vec::new(),
            input_link_group_count: matches!(kind, SourcePackWorkQueueItemKind::LinkReduce)
                as usize,
            input_link_group_indices: Vec::new(),
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        };

    for dependency_item_index in 0..2 {
        store
            .store_work_queue_page(&work_queue_page(
                dependency_item_index,
                SourcePackWorkQueueItemKind::LibraryFrontend,
            ))
            .expect("store dependency work queue page");
    }
    for dependent_item_index in 2..4 {
        let page = work_queue_page(
            dependent_item_index,
            SourcePackWorkQueueItemKind::LinkReduce,
        );
        store_source_pack_work_queue_page_with_dependency_writer(
            &store,
            &page,
            work_item_count,
            |writer| writer.push_range(0, 2),
        )
        .expect("store ranged dependent work queue page");
    }

    for dependency_item_index in 0..2 {
        let dependency_page = store
            .load_work_queue_page_for_target(target, dependency_item_index)
            .expect("load dependency work queue page after ranged dependents");
        assert_eq!(dependency_page.dependent_item_count, 0);
        assert_eq!(dependency_page.dependent_page_count, 0);
        assert_eq!(
            dependency_page.dependent_item_ranges,
            vec![SourcePackJobIndexRange {
                first_job_index: 2,
                job_count: 2,
            }]
        );
        assert_eq!(
            source_pack_work_queue_page_dependent_count(&dependency_page),
            2
        );
        assert!(
            !store
                .work_queue_dependents_page_path_for_target(target, dependency_item_index, 0)
                .exists(),
            "compact reverse-dependent ranges should not create explicit dependent pages"
        );
    }

    std::fs::remove_dir_all(&root).expect("remove temp work queue dependent range writer dir");
}

#[test]
fn source_pack_link_group_and_work_queue_pages_reject_oversized_retained_inputs() {
    let target = SourcePackArtifactTarget::Wasm;
    let oversized_codegen_inputs =
        (0..=SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE).collect::<Vec<_>>();
    let oversized_group = SourcePackHierarchicalLinkGroupPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
        target,
        group_index: 0,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        level: 0,
        job_index: 0,
        input_partition_count: 1,
        input_partition_indices: vec![0],
        input_frontend_job_count: 1,
        input_frontend_job_indices: vec![0],
        input_codegen_job_indices: oversized_codegen_inputs,
        input_link_group_indices: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        oversized_input: true,
    };
    assert!(
        validate_source_pack_hierarchical_link_group_page(&oversized_group, target, Some(0))
            .is_err(),
        "oversized retained hierarchical link inputs must be rejected"
    );

    let assert_work_queue_record_cap =
        |page: SourcePackWorkQueuePage, expected_item_index: usize, label: &str| {
            assert!(
                validate_source_pack_work_queue_page(&page, target, Some(expected_item_index),)
                    .expect_err(&format!(
                        "oversized retained work-queue {label} should be rejected"
                    ))
                    .to_string()
                    .contains("record cap"),
                "oversized retained work-queue {label} must be rejected by the record cap"
            );
        };

    let oversized_dependency_count = SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE + 1;
    assert_work_queue_record_cap(
        SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index: oversized_dependency_count,
            kind: SourcePackWorkQueueItemKind::Codegen,
            job_index: oversized_dependency_count,
            dependency_item_indices: (0..oversized_dependency_count).collect(),
            dependency_item_count: 0,
            dependency_page_count: 0,
            dependency_item_ranges: Vec::new(),
            dependent_item_indices: Vec::new(),
            dependent_item_count: 0,
            dependent_page_count: 0,
            dependent_item_ranges: Vec::new(),
            artifact_batch_index: None,
            partition_count: 1,
            partition_indices: vec![0],
            link_group_index: None,
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 0,
            input_codegen_job_indices: Vec::new(),
            input_link_group_count: 0,
            input_link_group_indices: Vec::new(),
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        },
        oversized_dependency_count,
        "dependencies",
    );

    let oversized_dependent_count = SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE + 1;
    assert_work_queue_record_cap(
        SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index: 0,
            kind: SourcePackWorkQueueItemKind::LibraryFrontend,
            job_index: 0,
            dependency_item_indices: Vec::new(),
            dependency_item_count: 0,
            dependency_page_count: 0,
            dependency_item_ranges: Vec::new(),
            dependent_item_indices: (1..=oversized_dependent_count).collect(),
            dependent_item_count: 0,
            dependent_page_count: 0,
            dependent_item_ranges: Vec::new(),
            artifact_batch_index: None,
            partition_count: 1,
            partition_indices: vec![0],
            link_group_index: None,
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 0,
            input_codegen_job_indices: Vec::new(),
            input_link_group_count: 0,
            input_link_group_indices: Vec::new(),
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        },
        0,
        "dependents",
    );

    let oversized_dependent_ranges = (0..=SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE)
        .map(|range_index| SourcePackJobIndexRange {
            first_job_index: range_index + 1,
            job_count: 1,
        })
        .collect::<Vec<_>>();
    assert_work_queue_record_cap(
        SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index: 0,
            kind: SourcePackWorkQueueItemKind::LibraryFrontend,
            job_index: 0,
            dependency_item_indices: Vec::new(),
            dependency_item_count: 0,
            dependency_page_count: 0,
            dependency_item_ranges: Vec::new(),
            dependent_item_indices: Vec::new(),
            dependent_item_count: 0,
            dependent_page_count: 0,
            dependent_item_ranges: oversized_dependent_ranges,
            artifact_batch_index: None,
            partition_count: 1,
            partition_indices: vec![0],
            link_group_index: None,
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 0,
            input_codegen_job_indices: Vec::new(),
            input_link_group_count: 0,
            input_link_group_indices: Vec::new(),
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        },
        0,
        "dependent ranges",
    );

    let oversized_frontend_inputs =
        (0..=SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE).collect::<Vec<_>>();
    assert_work_queue_record_cap(
        SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index: SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 2,
            kind: SourcePackWorkQueueItemKind::LinkLeaf,
            job_index: SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 2,
            dependency_item_indices: Vec::new(),
            dependency_item_count: 0,
            dependency_page_count: 0,
            dependency_item_ranges: Vec::new(),
            dependent_item_indices: Vec::new(),
            dependent_item_count: 0,
            dependent_page_count: 0,
            dependent_item_ranges: Vec::new(),
            artifact_batch_index: None,
            partition_count: 1,
            partition_indices: vec![0],
            link_group_index: Some(0),
            input_frontend_job_count: oversized_frontend_inputs.len(),
            input_frontend_job_indices: oversized_frontend_inputs,
            input_codegen_job_count: 1,
            input_codegen_job_indices: vec![SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 1],
            input_link_group_count: 0,
            input_link_group_indices: Vec::new(),
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        },
        SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 2,
        "frontend inputs",
    );

    let oversized_partitions =
        (0..=SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE).collect::<Vec<_>>();
    assert_work_queue_record_cap(
        SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index: SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 2,
            kind: SourcePackWorkQueueItemKind::LinkReduce,
            job_index: SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 2,
            dependency_item_indices: Vec::new(),
            dependency_item_count: 0,
            dependency_page_count: 0,
            dependency_item_ranges: Vec::new(),
            dependent_item_indices: Vec::new(),
            dependent_item_count: 0,
            dependent_page_count: 0,
            dependent_item_ranges: Vec::new(),
            artifact_batch_index: None,
            partition_count: oversized_partitions.len(),
            partition_indices: oversized_partitions,
            link_group_index: Some(SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 1),
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 0,
            input_codegen_job_indices: Vec::new(),
            input_link_group_count: 1,
            input_link_group_indices: vec![0],
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        },
        SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 2,
        "partitions",
    );

    let oversized_work_queue_codegen_inputs =
        (0..=SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE).collect::<Vec<_>>();
    let oversized_work_queue_codegen_page = SourcePackWorkQueuePage {
        version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
        target,
        item_index: SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 1,
        kind: SourcePackWorkQueueItemKind::LinkLeaf,
        job_index: SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 1,
        dependency_item_indices: Vec::new(),
        dependency_item_count: 0,
        dependency_page_count: 0,
        dependency_item_ranges: Vec::new(),
        dependent_item_indices: Vec::new(),
        dependent_item_count: 0,
        dependent_page_count: 0,
        dependent_item_ranges: Vec::new(),
        artifact_batch_index: None,
        partition_count: 1,
        partition_indices: vec![0],
        link_group_index: Some(0),
        input_frontend_job_count: 1,
        input_frontend_job_indices: vec![0],
        input_codegen_job_count: oversized_work_queue_codegen_inputs.len(),
        input_codegen_job_indices: oversized_work_queue_codegen_inputs,
        input_link_group_count: 0,
        input_link_group_indices: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
    };
    assert!(
        validate_source_pack_work_queue_page(
            &oversized_work_queue_codegen_page,
            target,
            Some(SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 1),
        )
        .expect_err("oversized retained work-queue codegen inputs should be rejected")
        .to_string()
        .contains("record cap"),
        "oversized retained work-queue codegen inputs must be rejected by the record cap"
    );

    let oversized_link_inputs =
        (0..=SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE).collect::<Vec<_>>();
    let oversized_work_queue_page = SourcePackWorkQueuePage {
        version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
        target,
        item_index: SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 1,
        kind: SourcePackWorkQueueItemKind::LinkReduce,
        job_index: SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 1,
        dependency_item_indices: Vec::new(),
        dependency_item_count: 0,
        dependency_page_count: 0,
        dependency_item_ranges: Vec::new(),
        dependent_item_indices: Vec::new(),
        dependent_item_count: 0,
        dependent_page_count: 0,
        dependent_item_ranges: Vec::new(),
        artifact_batch_index: None,
        partition_count: 1,
        partition_indices: Vec::new(),
        link_group_index: Some(SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 1),
        input_frontend_job_count: 0,
        input_frontend_job_indices: Vec::new(),
        input_codegen_job_count: 0,
        input_codegen_job_indices: Vec::new(),
        input_link_group_count: oversized_link_inputs.len(),
        input_link_group_indices: oversized_link_inputs,
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
    };
    assert!(
        validate_source_pack_work_queue_page(
            &oversized_work_queue_page,
            target,
            Some(SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE + 1),
        )
        .expect_err("oversized retained work-queue link inputs should be rejected")
        .to_string()
        .contains("record cap"),
        "oversized retained work-queue link inputs must be rejected by the record cap"
    );
}

#[test]
fn source_pack_work_queue_progress_pages_reject_unbounded_records() {
    let target = SourcePackArtifactTarget::Wasm;
    let capped_page = SourcePackWorkQueueProgressPage {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
        target,
        page_index: 0,
        first_item_index: 0,
        item_count: SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE,
        artifact_item_indices: vec![1],
        remaining_dependency_counts: vec![SourcePackWorkQueueRemainingDependencyCount {
            item_index: 2,
            remaining_dependency_count: 1,
        }],
        remaining_dependent_counts: vec![SourcePackWorkQueueRemainingDependentCount {
            item_index: 3,
            remaining_dependent_count: 1,
        }],
        completed_item_indices: vec![4],
        ready_item_indices: vec![1],
        ready_artifact_item_indices: vec![1],
        claimed_items: vec![SourcePackWorkQueueItemClaim {
            item_index: 1,
            worker_id: "worker-a".to_string(),
            lease_expires_unix_nanos: Some(10),
        }],
    };
    validate_source_pack_work_queue_progress_page(&capped_page, target, Some(0))
        .expect("work-queue progress page at record cap should validate");

    let oversized_indices =
        (0..=SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE).collect::<Vec<_>>();
    let oversized_remaining_dependencies = oversized_indices
        .iter()
        .map(|item_index| SourcePackWorkQueueRemainingDependencyCount {
            item_index: *item_index,
            remaining_dependency_count: 1,
        })
        .collect::<Vec<_>>();
    let oversized_remaining_dependents = oversized_indices
        .iter()
        .map(|item_index| SourcePackWorkQueueRemainingDependentCount {
            item_index: *item_index,
            remaining_dependent_count: 1,
        })
        .collect::<Vec<_>>();
    let oversized_claims = oversized_indices
        .iter()
        .map(|item_index| SourcePackWorkQueueItemClaim {
            item_index: *item_index,
            worker_id: format!("worker-{item_index}"),
            lease_expires_unix_nanos: Some(10),
        })
        .collect::<Vec<_>>();

    let mut oversized_page_items = capped_page.clone();
    oversized_page_items.item_count = SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE + 1;
    assert!(
        validate_source_pack_work_queue_progress_page(&oversized_page_items, target, Some(0))
            .expect_err("oversized work-queue progress page items should be rejected")
            .to_string()
            .contains("record cap")
    );

    let assert_oversized_page = |label: &str, page: SourcePackWorkQueueProgressPage| {
        assert!(
            validate_source_pack_work_queue_progress_page(&page, target, Some(0))
                .expect_err(&format!("oversized {label} should be rejected"))
                .to_string()
                .contains("record cap"),
            "oversized {label} should report the record cap"
        );
    };

    let mut page = capped_page.clone();
    page.artifact_item_indices = oversized_indices.clone();
    assert_oversized_page("artifact items", page);

    let mut page = capped_page.clone();
    page.remaining_dependency_counts = oversized_remaining_dependencies;
    assert_oversized_page("remaining dependencies", page);

    let mut page = capped_page.clone();
    page.remaining_dependent_counts = oversized_remaining_dependents;
    assert_oversized_page("remaining dependents", page);

    let mut page = capped_page.clone();
    page.completed_item_indices = oversized_indices.clone();
    assert_oversized_page("completed items", page);

    let mut page = capped_page.clone();
    page.ready_item_indices = oversized_indices.clone();
    assert_oversized_page("ready items", page);

    let mut page = capped_page.clone();
    page.ready_artifact_item_indices = oversized_indices.clone();
    assert_oversized_page("ready artifact items", page);

    let mut page = capped_page.clone();
    page.claimed_items = oversized_claims;
    assert_oversized_page("claims", page);

    let oversized_index = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target,
        work_item_count: SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE + 1,
        page_size: SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE + 1,
        page_count: 1,
        artifact_item_count: 0,
        completed_item_count: 0,
        ready_item_count: 0,
        ready_artifact_item_count: 0,
        claimed_item_count: 0,
        first_ready_item_index: None,
        first_ready_artifact_item_index: None,
    };
    assert!(
        validate_source_pack_work_queue_progress_index(&oversized_index, target)
            .expect_err("oversized work-queue progress index page size should be rejected")
            .to_string()
            .contains("record cap")
    );

    let oversized_summary = SourcePackWorkQueueProgressPageSummary {
        page_index: 0,
        first_item_index: 0,
        item_count: SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE + 1,
        artifact_item_count: 0,
        completed_item_count: 0,
        ready_item_count: 0,
        first_ready_item_index: None,
        ready_artifact_item_count: 0,
        first_ready_artifact_item_index: None,
        blocked_item_count: 0,
        pending_dependent_item_count: 0,
        claimed_item_count: 0,
        ready_claimed_item_count: 0,
        ready_artifact_claimed_item_count: 0,
        earliest_claim_lease_expires_unix_nanos: None,
    };
    assert!(
        validate_source_pack_work_queue_progress_page_summary(&oversized_summary)
            .expect_err("oversized work-queue progress summary should be rejected")
            .to_string()
            .contains("record cap")
    );
}

#[test]
fn source_pack_initial_work_queue_progress_pages_ready_frontier() {
    fn build_unit_page(
        partition_index: usize,
        library_id: u32,
        first_source_index: usize,
        dependency_library_ids: Vec<u32>,
    ) -> SourcePackLibraryBuildUnitPage {
        SourcePackLibraryBuildUnitPage {
            version: SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            partition_index,
            library_id,
            dependency_library_ids,
            first_source_index,
            source_file_count: 1,
            source_byte_count: 4,
            source_line_count: 0,
            limits: CodegenUnitLimits {
                max_source_bytes: 8,
                max_source_files: 8,
            },
            frontend_unit: LibraryUnit {
                library_index: 0,
                library_id,
                first_source_index,
                source_file_count: 1,
                source_bytes: 4,
                source_lines: 0,
            },
            frontend_unit_count: 1,
            frontend_units: Vec::new(),
            codegen_unit_count: 1,
            codegen_units: vec![CodegenUnit {
                unit_index: 0,
                library_id,
                first_source_index,
                source_file_count: 1,
                source_bytes: 4,
                source_lines: 0,
                oversized_source_file: false,
            }],
        }
    }

    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-progress-page-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let build_unit_pages = vec![
        build_unit_page(0, 10, 0, Vec::new()),
        build_unit_page(1, 20, 1, vec![10]),
        build_unit_page(2, 30, 2, vec![20]),
    ];
    let schedule_plan =
        source_pack_library_schedule_plan(&build_unit_pages).expect("build schedule plan");
    let schedule_index = &schedule_plan.index;
    let schedule_pages = source_pack_library_schedule_pages(&build_unit_pages, &schedule_plan)
        .expect("build schedule pages");
    let (link_plan_index, link_group_pages) = source_pack_hierarchical_link_plan(
        &schedule_index,
        &schedule_pages,
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 2,
            max_source_bytes_per_batch: 8,
            max_source_files_per_batch: 2,
        },
    )
    .expect("build hierarchical link plan");
    let (work_queue_index, work_queue_pages) = source_pack_work_queue(
        &schedule_index,
        &schedule_pages,
        &link_plan_index,
        &link_group_pages,
    )
    .expect("build work queue");
    let (progress_index, progress_pages) =
        source_pack_initial_work_queue_progress_from_pages(&work_queue_index, &work_queue_pages, 4)
            .expect("build initial work queue progress");

    assert_eq!(work_queue_index.work_item_count, 12);
    assert_eq!(progress_index.work_item_count, 12);
    assert_eq!(progress_index.page_size, 4);
    assert_eq!(progress_index.page_count, 3);
    assert_eq!(progress_index.completed_item_count, 0);
    assert_eq!(progress_index.artifact_item_count, 6);
    assert_eq!(progress_index.ready_item_count, 1);
    assert_eq!(progress_index.ready_artifact_item_count, 1);
    assert_eq!(progress_index.claimed_item_count, 0);
    assert_eq!(progress_index.first_ready_item_index, Some(0));
    assert_eq!(progress_index.first_ready_artifact_item_index, Some(0));
    assert_eq!(progress_pages.len(), 3);
    assert_eq!(progress_pages[0].first_item_index, 0);
    assert_eq!(progress_pages[0].item_count, 4);
    assert_eq!(progress_pages[0].artifact_item_indices, vec![0, 1, 2, 3]);
    assert_eq!(progress_pages[0].ready_item_indices, vec![0]);
    assert_eq!(progress_pages[0].ready_artifact_item_indices, vec![0]);
    assert_eq!(progress_pages[1].ready_item_indices, Vec::<usize>::new());
    assert_eq!(progress_pages[2].ready_item_indices, Vec::<usize>::new());
    let first_progress_summary = source_pack_work_queue_progress_page_summary(&progress_pages[0]);
    assert_eq!(first_progress_summary.artifact_item_count, 4);
    assert_eq!(first_progress_summary.ready_item_count, 1);
    assert_eq!(first_progress_summary.ready_artifact_item_count, 1);
    assert_eq!(
        source_pack_work_queue_progress_page_summary(&progress_pages[1]).ready_item_count,
        0
    );
    assert_eq!(
        source_pack_work_queue_progress_page_summary(&progress_pages[2]).ready_item_count,
        0
    );
    let (page_progress_index, page_progress_pages) =
        source_pack_initial_work_queue_progress_from_pages(&work_queue_index, &work_queue_pages, 4)
            .expect("build initial progress from compact index and work item pages");
    assert_eq!(page_progress_index, progress_index);
    assert_eq!(page_progress_pages, progress_pages);

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    store
        .store_work_queue(&work_queue_index, &work_queue_pages)
        .expect("store work queue");
    let streaming_progress_index = store_initial_work_queue_progress_from_stored_work_queue_pages(
        &store,
        SourcePackArtifactTarget::Wasm,
        work_queue_index.work_item_count,
        4,
    )
    .expect("store streaming initial work queue progress");
    assert_eq!(streaming_progress_index, progress_index);
    assert!(
        store
            .work_queue_progress_directory_page_path_for_target(SourcePackArtifactTarget::Wasm, 0,)
            .is_file(),
        "streaming initial progress should persist compact directory pages"
    );
    assert!(
        store
            .work_queue_progress_directory_index_page_path_for_target(
                SourcePackArtifactTarget::Wasm,
                0,
            )
            .is_file(),
        "streaming initial progress should persist compact directory-index pages"
    );
    let progress_index_path = store
        .store_work_queue_progress(&progress_index, &progress_pages)
        .expect("store work queue progress");
    assert!(progress_index_path.ends_with("source-pack-work-queue-progress.wasm.json"));
    std::fs::write(
        store.work_queue_index_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt work queue index path");
    std::fs::write(
        store.work_queue_page_path_for_target(SourcePackArtifactTarget::Wasm, 0),
        b"not json",
    )
    .expect("corrupt work queue page path");
    let loaded_progress = store
        .load_work_queue_progress_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load work queue progress index without reading work queue");
    assert_eq!(loaded_progress, progress_index);
    let loaded_ready_page = store
        .load_work_queue_progress_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load ready progress page without reading work queue");
    assert_eq!(loaded_ready_page, progress_pages[0]);

    std::fs::remove_dir_all(&root).expect("remove temp work queue progress page dir");
}

#[test]
fn source_pack_work_queue_ready_scan_skips_fully_claimed_pages_by_summary() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-progress-summary-skip-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let first_page = SourcePackWorkQueueProgressPage {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        page_index: 0,
        first_item_index: 0,
        item_count: 2,
        artifact_item_indices: Vec::new(),
        remaining_dependency_counts: Vec::new(),
        remaining_dependent_counts: Vec::new(),
        completed_item_indices: Vec::new(),
        ready_item_indices: vec![0, 1],
        ready_artifact_item_indices: Vec::new(),
        claimed_items: vec![
            SourcePackWorkQueueItemClaim {
                item_index: 0,
                worker_id: "worker-a".into(),
                lease_expires_unix_nanos: Some(100),
            },
            SourcePackWorkQueueItemClaim {
                item_index: 1,
                worker_id: "worker-b".into(),
                lease_expires_unix_nanos: Some(100),
            },
        ],
    };
    let second_page = SourcePackWorkQueueProgressPage {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        page_index: 1,
        first_item_index: 2,
        item_count: 2,
        artifact_item_indices: Vec::new(),
        remaining_dependency_counts: Vec::new(),
        remaining_dependent_counts: Vec::new(),
        completed_item_indices: Vec::new(),
        ready_item_indices: vec![2],
        ready_artifact_item_indices: Vec::new(),
        claimed_items: Vec::new(),
    };
    store
        .store_work_queue_progress_page(&first_page)
        .expect("store fully claimed ready progress page");
    store
        .store_work_queue_progress_page(&second_page)
        .expect("store unclaimed ready progress page");
    assert!(
        store
            .work_queue_progress_page_summary_path_for_target(SourcePackArtifactTarget::Wasm, 0)
            .is_file(),
        "progress page store should write a compact summary sidecar"
    );
    std::fs::write(
        store.work_queue_progress_page_path_for_target(SourcePackArtifactTarget::Wasm, 0),
        b"not json",
    )
    .expect("corrupt fully claimed progress page body");

    let index = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        work_item_count: 4,
        page_size: 2,
        page_count: 2,
        artifact_item_count: 0,
        completed_item_count: 0,
        ready_item_count: 3,
        ready_artifact_item_count: 0,
        claimed_item_count: 2,
        first_ready_item_index: Some(0),
        first_ready_artifact_item_index: None,
    };
    let ready = source_pack_work_queue_progress_ready_unclaimed_item_indices_from_index_limited(
        &store,
        SourcePackArtifactTarget::Wasm,
        &index,
        Some(0),
        Some(1),
    )
    .expect("ready scan should use summary sidecars before loading progress-page bodies");

    assert_eq!(ready, vec![2]);
    std::fs::remove_dir_all(&root).expect("remove progress summary skip test dir");
}

#[test]
fn source_pack_work_queue_progress_store_rejects_unproven_compact_counts() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-compact-progress-count-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let progress_page = SourcePackWorkQueueProgressPage {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        page_index: 0,
        first_item_index: 0,
        item_count: 1,
        artifact_item_indices: vec![0],
        remaining_dependency_counts: Vec::new(),
        remaining_dependent_counts: Vec::new(),
        completed_item_indices: Vec::new(),
        ready_item_indices: vec![0],
        ready_artifact_item_indices: vec![0],
        claimed_items: Vec::new(),
    };
    let index = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        work_item_count: 1,
        page_size: 1,
        page_count: 1,
        artifact_item_count: 1,
        completed_item_count: 0,
        ready_item_count: 1,
        ready_artifact_item_count: 1,
        claimed_item_count: 0,
        first_ready_item_index: Some(0),
        first_ready_artifact_item_index: Some(0),
    };
    let mismatched_index = SourcePackWorkQueueProgressIndex {
        claimed_item_count: 1,
        ..index.clone()
    };

    let err = store
        .store_work_queue_progress(&mismatched_index, std::slice::from_ref(&progress_page))
        .expect_err("store should reject compact counts not proven by page records");
    assert!(
        err.to_string().contains("do not match compact index"),
        "unexpected compact count mismatch error: {err:?}"
    );
    store
        .store_work_queue_progress(&index, &[progress_page])
        .expect("store progress with counts proven from page records");

    std::fs::remove_dir_all(&root).expect("remove compact progress count test dir");
}

#[test]
fn source_pack_work_queue_ready_scan_skips_empty_directory_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-progress-directory-skip-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let page_count = SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE + 1;
    let mut pages = Vec::new();
    for page_index in 0..page_count {
        let ready_item_indices = match page_index {
            0 => vec![0],
            page_index if page_index + 1 == page_count => vec![page_index],
            _ => Vec::new(),
        };
        let claimed_items = if page_index == 0 {
            vec![SourcePackWorkQueueItemClaim {
                item_index: 0,
                worker_id: "worker-a".into(),
                lease_expires_unix_nanos: Some(100),
            }]
        } else {
            Vec::new()
        };
        pages.push(SourcePackWorkQueueProgressPage {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            page_index,
            first_item_index: page_index,
            item_count: 1,
            artifact_item_indices: Vec::new(),
            remaining_dependency_counts: Vec::new(),
            remaining_dependent_counts: Vec::new(),
            completed_item_indices: Vec::new(),
            ready_item_indices,
            ready_artifact_item_indices: Vec::new(),
            claimed_items,
        });
    }
    let index = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        work_item_count: page_count,
        page_size: 1,
        page_count,
        artifact_item_count: 0,
        completed_item_count: 0,
        ready_item_count: 2,
        ready_artifact_item_count: 0,
        claimed_item_count: 1,
        first_ready_item_index: Some(0),
        first_ready_artifact_item_index: None,
    };
    store
        .store_work_queue_progress(&index, &pages)
        .expect("store progress with directory pages");
    assert!(
        store
            .work_queue_progress_directory_page_path_for_target(SourcePackArtifactTarget::Wasm, 0,)
            .is_file(),
        "progress store should write compact directory pages"
    );
    std::fs::write(
        store.work_queue_progress_page_summary_path_for_target(SourcePackArtifactTarget::Wasm, 1),
        b"not json",
    )
    .expect("corrupt empty progress summary that directory skip should avoid");

    let ready = source_pack_work_queue_progress_ready_unclaimed_item_indices_from_index_limited(
        &store,
        SourcePackArtifactTarget::Wasm,
        &index,
        Some(0),
        Some(1),
    )
    .expect("ready scan should skip empty progress pages through directory records");

    assert_eq!(ready, vec![page_count - 1]);
    std::fs::remove_dir_all(&root).expect("remove progress directory skip test dir");
}

#[test]
fn source_pack_work_queue_ready_scan_skips_fully_claimed_directory_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-progress-claimed-directory-skip-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let page_count = SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE * 2 + 1;
    let mut pages = Vec::new();
    for page_index in 0..page_count {
        let ready_item_indices = match page_index {
            0 => vec![0],
            page_index if page_index + 1 == page_count => vec![page_index],
            _ => Vec::new(),
        };
        let claimed_items = if page_index == 0 {
            vec![SourcePackWorkQueueItemClaim {
                item_index: 0,
                worker_id: "worker-a".into(),
                lease_expires_unix_nanos: Some(100),
            }]
        } else {
            Vec::new()
        };
        pages.push(SourcePackWorkQueueProgressPage {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            page_index,
            first_item_index: page_index,
            item_count: 1,
            artifact_item_indices: Vec::new(),
            remaining_dependency_counts: Vec::new(),
            remaining_dependent_counts: Vec::new(),
            completed_item_indices: Vec::new(),
            ready_item_indices,
            ready_artifact_item_indices: Vec::new(),
            claimed_items,
        });
    }
    let index = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        work_item_count: page_count,
        page_size: 1,
        page_count,
        artifact_item_count: 0,
        completed_item_count: 0,
        ready_item_count: 2,
        ready_artifact_item_count: 0,
        claimed_item_count: 1,
        first_ready_item_index: Some(0),
        first_ready_artifact_item_index: None,
    };
    store
        .store_work_queue_progress(&index, &pages)
        .expect("store progress with directory pages");
    std::fs::write(
        store.work_queue_progress_page_summary_path_for_target(SourcePackArtifactTarget::Wasm, 0),
        b"not json",
    )
    .expect("corrupt fully claimed progress summary that directory skip should avoid");

    let ready = source_pack_work_queue_progress_ready_unclaimed_item_indices_from_index_limited(
        &store,
        SourcePackArtifactTarget::Wasm,
        &index,
        Some(0),
        Some(1),
    )
    .expect("ready scan should skip fully claimed progress pages through directory records");

    assert_eq!(ready, vec![page_count - 1]);
    std::fs::remove_dir_all(&root).expect("remove progress claimed-directory skip test dir");
}

#[test]
fn source_pack_work_queue_ready_scan_skips_fully_claimed_directory_index_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-progress-directory-index-skip-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let final_directory_page_index =
        SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE;
    let final_page_index =
        final_directory_page_index * SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE;
    let page_count = final_page_index + 1;
    let index = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        work_item_count: page_count,
        page_size: 1,
        page_count,
        artifact_item_count: 0,
        completed_item_count: 0,
        ready_item_count: 2,
        ready_artifact_item_count: 0,
        claimed_item_count: 1,
        first_ready_item_index: Some(0),
        first_ready_artifact_item_index: None,
    };
    store
        .store_work_queue_progress_page(&SourcePackWorkQueueProgressPage {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            page_index: final_page_index,
            first_item_index: final_page_index,
            item_count: 1,
            artifact_item_indices: Vec::new(),
            remaining_dependency_counts: Vec::new(),
            remaining_dependent_counts: Vec::new(),
            completed_item_indices: Vec::new(),
            ready_item_indices: vec![final_page_index],
            ready_artifact_item_indices: Vec::new(),
            claimed_items: Vec::new(),
        })
        .expect("store final ready progress page");
    store
        .store_work_queue_progress_directory_page_for_target(
            SourcePackArtifactTarget::Wasm,
            &SourcePackWorkQueueProgressDirectoryPage {
                version: SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_PAGE_VERSION,
                target: SourcePackArtifactTarget::Wasm,
                directory_page_index: final_directory_page_index,
                first_progress_page_index: final_page_index,
                progress_page_count: 1,
                ready_page_count: 1,
                first_ready_page_index: Some(final_page_index),
                ready_artifact_page_count: 0,
                first_ready_artifact_page_index: None,
                ready_claimed_page_count: 0,
                ready_artifact_claimed_page_count: 0,
                earliest_claim_lease_expires_unix_nanos: None,
            },
        )
        .expect("store final progress directory page");
    store
        .store_work_queue_progress_directory_index_page_for_target(
            SourcePackArtifactTarget::Wasm,
            &SourcePackWorkQueueProgressDirectoryIndexPage {
                version: SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION,
                target: SourcePackArtifactTarget::Wasm,
                directory_index_page_index: 0,
                first_directory_page_index: 0,
                directory_page_count:
                    SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE,
                ready_directory_page_count: 1,
                first_ready_directory_page_index: Some(0),
                ready_artifact_directory_page_count: 0,
                first_ready_artifact_directory_page_index: None,
                ready_claimed_directory_page_count: 1,
                ready_artifact_claimed_directory_page_count: 0,
                fully_claimed_ready_directory_page_count: 1,
                fully_claimed_ready_artifact_directory_page_count: 0,
                earliest_claim_lease_expires_unix_nanos: Some(100),
            },
            &index,
        )
        .expect("store claimed directory-index page");
    store
        .store_work_queue_progress_directory_index_page_for_target(
            SourcePackArtifactTarget::Wasm,
            &SourcePackWorkQueueProgressDirectoryIndexPage {
                version: SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION,
                target: SourcePackArtifactTarget::Wasm,
                directory_index_page_index: 1,
                first_directory_page_index: final_directory_page_index,
                directory_page_count: 1,
                ready_directory_page_count: 1,
                first_ready_directory_page_index: Some(final_directory_page_index),
                ready_artifact_directory_page_count: 0,
                first_ready_artifact_directory_page_index: None,
                ready_claimed_directory_page_count: 0,
                ready_artifact_claimed_directory_page_count: 0,
                fully_claimed_ready_directory_page_count: 0,
                fully_claimed_ready_artifact_directory_page_count: 0,
                earliest_claim_lease_expires_unix_nanos: None,
            },
            &index,
        )
        .expect("store final directory-index page");
    if let Some(parent) = store
        .work_queue_progress_directory_page_path_for_target(SourcePackArtifactTarget::Wasm, 0)
        .parent()
    {
        std::fs::create_dir_all(parent).expect("create corrupt directory page parent");
    }
    std::fs::write(
        store.work_queue_progress_directory_page_path_for_target(SourcePackArtifactTarget::Wasm, 0),
        b"not json",
    )
    .expect("corrupt claimed directory page that directory-index skip should avoid");

    let ready = source_pack_work_queue_progress_ready_unclaimed_item_indices_from_index_limited(
        &store,
        SourcePackArtifactTarget::Wasm,
        &index,
        Some(0),
        Some(1),
    )
    .expect("ready scan should skip claimed directory groups through directory-index records");

    assert_eq!(ready, vec![final_page_index]);
    std::fs::remove_dir_all(&root).expect("remove progress directory-index skip test dir");
}

#[test]
fn source_pack_work_queue_artifact_claim_uses_ready_artifact_counter() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-artifact-ready-counter-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let work_queue_index = SourcePackWorkQueueIndex {
        version: SOURCE_PACK_WORK_QUEUE_INDEX_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        work_item_count: 2,
        artifact_item_count: 1,
        final_item_index: 1,
        final_job_index: 1,
    };
    let work_queue_index_bytes =
        serde_json::to_vec_pretty(&work_queue_index).expect("serialize work queue index");
    write_source_pack_filesystem_file_atomically(
        &store.work_queue_index_path_for_target(SourcePackArtifactTarget::Wasm),
        &work_queue_index_bytes,
        "test work queue index",
    )
    .expect("store compact work queue index");
    let progress_page = SourcePackWorkQueueProgressPage {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        page_index: 0,
        first_item_index: 0,
        item_count: 2,
        artifact_item_indices: vec![1],
        remaining_dependency_counts: Vec::new(),
        remaining_dependent_counts: Vec::new(),
        completed_item_indices: Vec::new(),
        ready_item_indices: vec![0],
        ready_artifact_item_indices: Vec::new(),
        claimed_items: Vec::new(),
    };
    store
        .store_work_queue_progress_page(&progress_page)
        .expect("store link-ready progress page");
    std::fs::write(
        store.work_queue_progress_page_path_for_target(SourcePackArtifactTarget::Wasm, 0),
        b"not json",
    )
    .expect("corrupt link-ready progress page body");
    let index = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        work_item_count: 2,
        page_size: 2,
        page_count: 1,
        artifact_item_count: 1,
        completed_item_count: 0,
        ready_item_count: 1,
        ready_artifact_item_count: 0,
        claimed_item_count: 0,
        first_ready_item_index: Some(0),
        first_ready_artifact_item_index: None,
    };

    let claimed = source_pack_work_queue_first_ready_unclaimed_artifact_item(
        &store,
        SourcePackArtifactTarget::Wasm,
        &index,
        Some(0),
    )
    .expect("artifact claim should stop from persisted ready-artifact counters");

    assert_eq!(claimed, None);
    std::fs::remove_dir_all(&root).expect("remove artifact ready counter test dir");
}

#[test]
fn source_pack_work_queue_artifact_claim_uses_progress_artifact_counters_without_work_queue_index()
{
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-artifact-stale-counter-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    std::fs::create_dir_all(&artifact_root).expect("create temp artifact dir");
    std::fs::write(
        &store.work_queue_index_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt compact work queue index");
    let progress_index = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        work_item_count: 1,
        page_size: 1,
        page_count: 1,
        artifact_item_count: 0,
        completed_item_count: 0,
        ready_item_count: 1,
        ready_artifact_item_count: 0,
        claimed_item_count: 0,
        first_ready_item_index: Some(0),
        first_ready_artifact_item_index: None,
    };

    let claimed = source_pack_work_queue_first_ready_unclaimed_artifact_item(
        &store,
        SourcePackArtifactTarget::Wasm,
        &progress_index,
        Some(0),
    )
    .expect("artifact claims should use persisted progress counters");
    assert_eq!(claimed, None);
    std::fs::remove_dir_all(&root).expect("remove stale artifact counter test dir");
}

#[test]
fn source_pack_work_queue_ready_frontier_recompute_uses_summary_sidecar() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-ready-summary-frontier-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let progress_page = SourcePackWorkQueueProgressPage {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        page_index: 0,
        first_item_index: 0,
        item_count: 2,
        artifact_item_indices: vec![1],
        remaining_dependency_counts: Vec::new(),
        remaining_dependent_counts: Vec::new(),
        completed_item_indices: Vec::new(),
        ready_item_indices: vec![1],
        ready_artifact_item_indices: vec![1],
        claimed_items: Vec::new(),
    };
    store
        .store_work_queue_progress_page(&progress_page)
        .expect("store progress page with summary frontier");
    std::fs::write(
        store.work_queue_progress_page_path_for_target(SourcePackArtifactTarget::Wasm, 0),
        b"not json",
    )
    .expect("corrupt progress page body");
    let index = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        work_item_count: 2,
        page_size: 2,
        page_count: 1,
        artifact_item_count: 1,
        completed_item_count: 0,
        ready_item_count: 1,
        ready_artifact_item_count: 1,
        claimed_item_count: 0,
        first_ready_item_index: Some(0),
        first_ready_artifact_item_index: Some(0),
    };

    let first_ready = source_pack_work_queue_progress_first_ready_item_index_from_index(
        &store,
        SourcePackArtifactTarget::Wasm,
        &index,
        &[],
    )
    .expect("ready frontier recompute should use progress summary sidecar");
    let first_ready_artifact =
        source_pack_work_queue_progress_first_ready_artifact_item_index_from_index(
            &store,
            SourcePackArtifactTarget::Wasm,
            &index,
            &[],
        )
        .expect("artifact-ready frontier recompute should use progress summary sidecar");

    assert_eq!(first_ready, Some(1));
    assert_eq!(first_ready_artifact, Some(1));
    std::fs::remove_dir_all(&root).expect("remove ready summary frontier test dir");
}

#[test]
fn source_pack_work_queue_release_counter_skips_dependent_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-release-counter-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let progress_page = SourcePackWorkQueueProgressPage {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        page_index: 0,
        first_item_index: 0,
        item_count: 1,
        artifact_item_indices: Vec::new(),
        remaining_dependency_counts: Vec::new(),
        remaining_dependent_counts: vec![SourcePackWorkQueueRemainingDependentCount {
            item_index: 0,
            remaining_dependent_count: 1,
        }],
        completed_item_indices: vec![0],
        ready_item_indices: Vec::new(),
        ready_artifact_item_indices: Vec::new(),
        claimed_items: Vec::new(),
    };
    let progress_index = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        work_item_count: 1,
        page_size: 1,
        page_count: 1,
        artifact_item_count: 0,
        completed_item_count: 1,
        ready_item_count: 0,
        ready_artifact_item_count: 0,
        claimed_item_count: 0,
        first_ready_item_index: None,
        first_ready_artifact_item_index: None,
    };
    store
        .store_work_queue_progress(&progress_index, &[progress_page])
        .expect("store progress with release counter");
    let corrupt_dependents_path =
        store.work_queue_dependents_page_path_for_target(SourcePackArtifactTarget::Wasm, 0, 0);
    if let Some(parent) = corrupt_dependents_path.parent() {
        std::fs::create_dir_all(parent).expect("create corrupt dependents parent");
    }
    std::fs::write(&corrupt_dependents_path, b"not json").expect("write corrupt dependents page");

    let mut loaded_index = store
        .load_work_queue_progress_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load compact progress index");
    let mut changed_page_batch = SourcePackWorkQueueProgressChangedPageBatch::new(
        SOURCE_PACK_WORK_QUEUE_PROGRESS_CHANGED_PAGE_BATCH_LIMIT,
    );
    let no_remaining_dependents =
        source_pack_work_queue_record_dependent_completed_for_release_candidate(
            &store,
            SourcePackArtifactTarget::Wasm,
            &mut loaded_index,
            &mut changed_page_batch,
            0,
        )
        .expect("release counter update should not scan dependent pages");
    assert!(no_remaining_dependents);
    changed_page_batch
        .flush(&store, SourcePackArtifactTarget::Wasm, &mut loaded_index)
        .expect("flush release counter batch");
    let updated_page = store
        .load_work_queue_progress_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load updated progress page");
    assert!(updated_page.remaining_dependent_counts.is_empty());

    std::fs::remove_dir_all(&root).expect("remove release counter test dir");
}

#[test]
fn source_pack_work_queue_release_counter_range_updates_progress_pages() {
    fn frontend_work_queue_page(
        target: SourcePackArtifactTarget,
        item_index: usize,
        dependent_count: usize,
    ) -> SourcePackWorkQueuePage {
        SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index,
            kind: SourcePackWorkQueueItemKind::LibraryFrontend,
            job_index: item_index,
            dependency_item_indices: Vec::new(),
            dependency_item_count: 0,
            dependency_page_count: 0,
            dependency_item_ranges: Vec::new(),
            dependent_item_indices: Vec::new(),
            dependent_item_count: dependent_count,
            dependent_page_count: dependent_count
                .div_ceil(SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE),
            dependent_item_ranges: Vec::new(),
            artifact_batch_index: None,
            partition_count: 1,
            partition_indices: vec![item_index],
            link_group_index: None,
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 0,
            input_codegen_job_indices: Vec::new(),
            input_link_group_count: 0,
            input_link_group_indices: Vec::new(),
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        }
    }

    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-release-range-counter-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let target = SourcePackArtifactTarget::Wasm;
    let progress_index = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target,
        work_item_count: 6,
        page_size: 2,
        page_count: 3,
        artifact_item_count: 0,
        completed_item_count: 0,
        ready_item_count: 0,
        ready_artifact_item_count: 0,
        claimed_item_count: 0,
        first_ready_item_index: None,
        first_ready_artifact_item_index: None,
    };
    let progress_pages = vec![
        SourcePackWorkQueueProgressPage {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
            target,
            page_index: 0,
            first_item_index: 0,
            item_count: 2,
            artifact_item_indices: Vec::new(),
            remaining_dependency_counts: Vec::new(),
            remaining_dependent_counts: vec![SourcePackWorkQueueRemainingDependentCount {
                item_index: 1,
                remaining_dependent_count: 1,
            }],
            completed_item_indices: Vec::new(),
            ready_item_indices: Vec::new(),
            ready_artifact_item_indices: Vec::new(),
            claimed_items: Vec::new(),
        },
        SourcePackWorkQueueProgressPage {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
            target,
            page_index: 1,
            first_item_index: 2,
            item_count: 2,
            artifact_item_indices: Vec::new(),
            remaining_dependency_counts: Vec::new(),
            remaining_dependent_counts: vec![
                SourcePackWorkQueueRemainingDependentCount {
                    item_index: 2,
                    remaining_dependent_count: 2,
                },
                SourcePackWorkQueueRemainingDependentCount {
                    item_index: 3,
                    remaining_dependent_count: 1,
                },
            ],
            completed_item_indices: Vec::new(),
            ready_item_indices: Vec::new(),
            ready_artifact_item_indices: Vec::new(),
            claimed_items: Vec::new(),
        },
        SourcePackWorkQueueProgressPage {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
            target,
            page_index: 2,
            first_item_index: 4,
            item_count: 2,
            artifact_item_indices: Vec::new(),
            remaining_dependency_counts: Vec::new(),
            remaining_dependent_counts: vec![SourcePackWorkQueueRemainingDependentCount {
                item_index: 4,
                remaining_dependent_count: 1,
            }],
            completed_item_indices: Vec::new(),
            ready_item_indices: Vec::new(),
            ready_artifact_item_indices: Vec::new(),
            claimed_items: Vec::new(),
        },
    ];
    store
        .store_work_queue_progress(&progress_index, &progress_pages)
        .expect("store compact release progress pages");
    for (item_index, dependent_count) in [(1, 1), (3, 1), (4, 1)] {
        store
            .store_work_queue_page(&frontend_work_queue_page(
                target,
                item_index,
                dependent_count,
            ))
            .expect("store no-output release candidate work item");
    }
    let mut loaded_index = store
        .load_work_queue_progress_index_for_target(target)
        .expect("load compact progress index");
    let mut changed_page_batch = SourcePackWorkQueueProgressChangedPageBatch::new(1);
    let released_count = release_source_pack_work_queue_dependency_range_after_item_completion(
        &store,
        target,
        &mut loaded_index,
        &mut changed_page_batch,
        &SourcePackJobIndexRange {
            first_job_index: 1,
            job_count: 4,
        },
    )
    .expect("update range release counters from bounded progress pages");
    changed_page_batch
        .flush(&store, target, &mut loaded_index)
        .expect("flush release range progress pages");

    assert_eq!(released_count, 0);
    let first_page = store
        .load_work_queue_progress_page_for_target(target, 0)
        .expect("load first release progress page");
    assert!(first_page.remaining_dependent_counts.is_empty());
    let second_page = store
        .load_work_queue_progress_page_for_target(target, 1)
        .expect("load second release progress page");
    assert_eq!(
        second_page.remaining_dependent_counts,
        vec![SourcePackWorkQueueRemainingDependentCount {
            item_index: 2,
            remaining_dependent_count: 1,
        }]
    );
    let third_page = store
        .load_work_queue_progress_page_for_target(target, 2)
        .expect("load third release progress page");
    assert!(third_page.remaining_dependent_counts.is_empty());

    std::fs::remove_dir_all(&root).expect("remove release range counter test dir");
}

#[test]
fn source_pack_work_queue_completion_requires_persisted_progress_counters() {
    let mut progress_page = SourcePackWorkQueueProgressPage {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        page_index: 0,
        first_item_index: 0,
        item_count: 2,
        artifact_item_indices: Vec::new(),
        remaining_dependency_counts: Vec::new(),
        remaining_dependent_counts: Vec::new(),
        completed_item_indices: Vec::new(),
        ready_item_indices: Vec::new(),
        ready_artifact_item_indices: Vec::new(),
        claimed_items: Vec::new(),
    };

    let dependency_err =
        source_pack_work_queue_progress_page_record_dependency_completed(&mut progress_page, 0)
            .expect_err("blocked item must have a persisted remaining-dependency counter");
    assert!(
        dependency_err
            .to_string()
            .contains("remaining dependency counter"),
        "unexpected dependency counter error: {dependency_err}"
    );

    let dependent_err =
        source_pack_work_queue_progress_page_record_dependent_completed(&mut progress_page, 1)
            .expect_err("item with pending dependents must have a persisted counter");
    assert!(
        dependent_err
            .to_string()
            .contains("remaining dependent counter"),
        "unexpected dependent counter error: {dependent_err}"
    );
}

#[test]
fn source_pack_work_queue_progress_page_transitions_match_reference_model() {
    #[derive(Clone, Debug)]
    struct ProgressPageModel {
        artifact_items: Vec<usize>,
        remaining_dependencies: BTreeMap<usize, usize>,
        remaining_dependents: BTreeMap<usize, usize>,
        completed_items: Vec<usize>,
        ready_items: Vec<usize>,
        claimed_items: BTreeMap<usize, String>,
    }

    impl ProgressPageModel {
        fn ready_artifact_items(&self) -> Vec<usize> {
            self.ready_items
                .iter()
                .copied()
                .filter(|item_index| self.artifact_items.contains(item_index))
                .collect()
        }

        fn dependency_records(&self) -> Vec<SourcePackWorkQueueRemainingDependencyCount> {
            self.remaining_dependencies
                .iter()
                .map(|(&item_index, &remaining_dependency_count)| {
                    SourcePackWorkQueueRemainingDependencyCount {
                        item_index,
                        remaining_dependency_count,
                    }
                })
                .collect()
        }

        fn dependent_records(&self) -> Vec<SourcePackWorkQueueRemainingDependentCount> {
            self.remaining_dependents
                .iter()
                .map(|(&item_index, &remaining_dependent_count)| {
                    SourcePackWorkQueueRemainingDependentCount {
                        item_index,
                        remaining_dependent_count,
                    }
                })
                .collect()
        }

        fn claim_records(&self) -> Vec<SourcePackWorkQueueItemClaim> {
            self.claimed_items
                .iter()
                .map(|(&item_index, worker_id)| SourcePackWorkQueueItemClaim {
                    item_index,
                    worker_id: worker_id.clone(),
                    lease_expires_unix_nanos: None,
                })
                .collect()
        }

        fn sorted_push(values: &mut Vec<usize>, value: usize) {
            if !values.contains(&value) {
                values.push(value);
                values.sort_unstable();
            }
        }

        fn dependency_completed(&mut self, item_index: usize) -> (bool, bool) {
            if self.completed_items.contains(&item_index) || self.ready_items.contains(&item_index)
            {
                return (false, false);
            }
            let remaining = self
                .remaining_dependencies
                .get_mut(&item_index)
                .expect("model blocked item should have a dependency counter");
            if *remaining > 1 {
                *remaining -= 1;
                return (true, false);
            }
            self.remaining_dependencies.remove(&item_index);
            Self::sorted_push(&mut self.ready_items, item_index);
            (true, true)
        }

        fn dependency_range_completed(
            &mut self,
            first_item_index: usize,
            item_count: usize,
        ) -> (bool, usize) {
            let mut changed = false;
            let mut newly_ready = 0usize;
            for item_index in first_item_index..first_item_index + item_count {
                let (item_changed, item_ready) = self.dependency_completed(item_index);
                changed |= item_changed;
                newly_ready += usize::from(item_ready);
            }
            (changed, newly_ready)
        }

        fn claim(&mut self, item_index: usize, worker_id: &str) {
            assert!(self.ready_items.contains(&item_index));
            assert!(!self.completed_items.contains(&item_index));
            self.claimed_items.insert(item_index, worker_id.to_string());
        }

        fn complete(&mut self, item_index: usize) {
            Self::sorted_push(&mut self.completed_items, item_index);
            self.ready_items
                .retain(|ready_item_index| *ready_item_index != item_index);
            self.claimed_items.remove(&item_index);
            self.remaining_dependencies.remove(&item_index);
        }

        fn dependent_completed(&mut self, item_index: usize) -> bool {
            let remaining = self
                .remaining_dependents
                .get_mut(&item_index)
                .expect("model dependent item should have a dependent counter");
            if *remaining > 1 {
                *remaining -= 1;
                return false;
            }
            self.remaining_dependents.remove(&item_index);
            true
        }

        fn dependent_range_completed(
            &mut self,
            first_item_index: usize,
            item_count: usize,
        ) -> Vec<usize> {
            let mut released = Vec::new();
            for item_index in first_item_index..first_item_index + item_count {
                if self.dependent_completed(item_index) {
                    released.push(item_index);
                }
            }
            released
        }

        fn assert_matches_page(&self, page: &SourcePackWorkQueueProgressPage, label: &str) {
            assert_eq!(page.artifact_item_indices, self.artifact_items, "{label}");
            assert_eq!(
                page.remaining_dependency_counts,
                self.dependency_records(),
                "{label}"
            );
            assert_eq!(
                page.remaining_dependent_counts,
                self.dependent_records(),
                "{label}"
            );
            assert_eq!(page.completed_item_indices, self.completed_items, "{label}");
            assert_eq!(page.ready_item_indices, self.ready_items, "{label}");
            assert_eq!(
                page.ready_artifact_item_indices,
                self.ready_artifact_items(),
                "{label}"
            );
            assert_eq!(page.claimed_items, self.claim_records(), "{label}");

            let summary = source_pack_work_queue_progress_page_summary(page);
            assert_eq!(
                summary.artifact_item_count,
                self.artifact_items.len(),
                "{label}"
            );
            assert_eq!(
                summary.completed_item_count,
                self.completed_items.len(),
                "{label}"
            );
            assert_eq!(summary.ready_item_count, self.ready_items.len(), "{label}");
            assert_eq!(
                summary.ready_artifact_item_count,
                self.ready_artifact_items().len(),
                "{label}"
            );
            assert_eq!(
                summary.blocked_item_count,
                self.remaining_dependencies.len(),
                "{label}"
            );
            assert_eq!(
                summary.pending_dependent_item_count,
                self.remaining_dependents.len(),
                "{label}"
            );
            assert_eq!(
                summary.claimed_item_count,
                self.claimed_items.len(),
                "{label}"
            );
            let ready_claimed = self
                .claimed_items
                .keys()
                .filter(|item_index| self.ready_items.contains(item_index))
                .count();
            let ready_artifact_claimed = self
                .claimed_items
                .keys()
                .filter(|item_index| self.ready_artifact_items().contains(item_index))
                .count();
            assert_eq!(summary.ready_claimed_item_count, ready_claimed, "{label}");
            assert_eq!(
                summary.ready_artifact_claimed_item_count, ready_artifact_claimed,
                "{label}"
            );
        }
    }

    let target = SourcePackArtifactTarget::Wasm;
    let mut progress_page = SourcePackWorkQueueProgressPage {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
        target,
        page_index: 0,
        first_item_index: 0,
        item_count: 6,
        artifact_item_indices: vec![0, 2, 4],
        remaining_dependency_counts: vec![
            SourcePackWorkQueueRemainingDependencyCount {
                item_index: 1,
                remaining_dependency_count: 2,
            },
            SourcePackWorkQueueRemainingDependencyCount {
                item_index: 2,
                remaining_dependency_count: 1,
            },
            SourcePackWorkQueueRemainingDependencyCount {
                item_index: 4,
                remaining_dependency_count: 1,
            },
        ],
        remaining_dependent_counts: vec![
            SourcePackWorkQueueRemainingDependentCount {
                item_index: 0,
                remaining_dependent_count: 1,
            },
            SourcePackWorkQueueRemainingDependentCount {
                item_index: 2,
                remaining_dependent_count: 2,
            },
            SourcePackWorkQueueRemainingDependentCount {
                item_index: 3,
                remaining_dependent_count: 1,
            },
        ],
        completed_item_indices: Vec::new(),
        ready_item_indices: vec![0, 3],
        ready_artifact_item_indices: vec![0],
        claimed_items: vec![SourcePackWorkQueueItemClaim {
            item_index: 3,
            worker_id: "expired-worker".to_string(),
            lease_expires_unix_nanos: Some(5),
        }],
    };
    let mut model = ProgressPageModel {
        artifact_items: vec![0, 2, 4],
        remaining_dependencies: BTreeMap::from([(1, 2), (2, 1), (4, 1)]),
        remaining_dependents: BTreeMap::from([(0, 1), (2, 2), (3, 1)]),
        completed_items: Vec::new(),
        ready_items: vec![0, 3],
        claimed_items: BTreeMap::new(),
    };

    source_pack_work_queue_progress_page_record_item_claim(
        &mut progress_page,
        0,
        "worker-a",
        None,
        Some(10),
    )
    .expect("ready item should be claimable and stale claims should be pruned");
    model.claim(0, "worker-a");
    model.assert_matches_page(&progress_page, "after first claim");

    let blocked_claim = source_pack_work_queue_progress_page_record_item_claim(
        &mut progress_page,
        1,
        "worker-b",
        None,
        Some(10),
    )
    .expect_err("blocked item must not be claimable");
    assert!(blocked_claim.to_string().contains("not ready"));

    assert_eq!(
        source_pack_work_queue_progress_page_record_dependency_completed(&mut progress_page, 1)
            .expect("first dependency completion"),
        model.dependency_completed(1)
    );
    model.assert_matches_page(&progress_page, "after first item-1 dependency");

    assert_eq!(
        source_pack_work_queue_progress_page_record_dependency_completed(&mut progress_page, 2)
            .expect("item 2 dependency completion"),
        model.dependency_completed(2)
    );
    model.assert_matches_page(&progress_page, "after item-2 dependency");

    assert_eq!(
        source_pack_work_queue_progress_page_record_dependency_range_completed(
            &mut progress_page,
            1,
            4,
        )
        .expect("range dependency completion"),
        model.dependency_range_completed(1, 4)
    );
    model.assert_matches_page(&progress_page, "after dependency range");

    source_pack_work_queue_progress_page_record_item_claim(
        &mut progress_page,
        4,
        "worker-b",
        None,
        Some(10),
    )
    .expect("newly ready artifact item should be claimable");
    model.claim(4, "worker-b");
    model.assert_matches_page(&progress_page, "after artifact claim");

    assert!(
        source_pack_work_queue_progress_page_record_item_completed(
            &mut progress_page,
            0,
            "worker-a",
            Some(10),
        )
        .expect("claimed item should complete")
    );
    model.complete(0);
    model.assert_matches_page(&progress_page, "after item completion");

    assert!(
        !source_pack_work_queue_progress_page_record_item_completed(
            &mut progress_page,
            0,
            "worker-a",
            Some(10),
        )
        .expect("completed item should be idempotent")
    );
    model.assert_matches_page(&progress_page, "after duplicate completion");

    assert_eq!(
        source_pack_work_queue_progress_page_record_dependent_completed(&mut progress_page, 0)
            .expect("item 0 dependent completion"),
        model.dependent_completed(0)
    );
    model.assert_matches_page(&progress_page, "after dependent completion");

    assert_eq!(
        source_pack_work_queue_progress_page_record_dependent_range_completed(
            &mut progress_page,
            2,
            2,
        )
        .expect("dependent range completion"),
        (true, model.dependent_range_completed(2, 2))
    );
    model.assert_matches_page(&progress_page, "after dependent range");

    validate_source_pack_work_queue_progress_page(&progress_page, target, Some(0))
        .expect("model-driven progress page should remain valid");
}

#[test]
fn source_pack_work_queue_dependent_range_completion_updates_progress_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-dependent-range-progress-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let target = SourcePackArtifactTarget::Wasm;
    let progress_index = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target,
        work_item_count: 6,
        page_size: 2,
        page_count: 3,
        artifact_item_count: 0,
        completed_item_count: 0,
        ready_item_count: 2,
        ready_artifact_item_count: 0,
        claimed_item_count: 0,
        first_ready_item_index: Some(0),
        first_ready_artifact_item_index: None,
    };
    let progress_pages = vec![
        SourcePackWorkQueueProgressPage {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
            target,
            page_index: 0,
            first_item_index: 0,
            item_count: 2,
            artifact_item_indices: Vec::new(),
            remaining_dependency_counts: vec![SourcePackWorkQueueRemainingDependencyCount {
                item_index: 1,
                remaining_dependency_count: 1,
            }],
            remaining_dependent_counts: Vec::new(),
            completed_item_indices: Vec::new(),
            ready_item_indices: vec![0],
            ready_artifact_item_indices: Vec::new(),
            claimed_items: Vec::new(),
        },
        SourcePackWorkQueueProgressPage {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
            target,
            page_index: 1,
            first_item_index: 2,
            item_count: 2,
            artifact_item_indices: Vec::new(),
            remaining_dependency_counts: vec![
                SourcePackWorkQueueRemainingDependencyCount {
                    item_index: 2,
                    remaining_dependency_count: 2,
                },
                SourcePackWorkQueueRemainingDependencyCount {
                    item_index: 3,
                    remaining_dependency_count: 1,
                },
            ],
            remaining_dependent_counts: Vec::new(),
            completed_item_indices: Vec::new(),
            ready_item_indices: Vec::new(),
            ready_artifact_item_indices: Vec::new(),
            claimed_items: Vec::new(),
        },
        SourcePackWorkQueueProgressPage {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
            target,
            page_index: 2,
            first_item_index: 4,
            item_count: 2,
            artifact_item_indices: Vec::new(),
            remaining_dependency_counts: vec![SourcePackWorkQueueRemainingDependencyCount {
                item_index: 5,
                remaining_dependency_count: 1,
            }],
            remaining_dependent_counts: Vec::new(),
            completed_item_indices: Vec::new(),
            ready_item_indices: vec![4],
            ready_artifact_item_indices: Vec::new(),
            claimed_items: Vec::new(),
        },
    ];
    store
        .store_work_queue_progress(&progress_index, &progress_pages)
        .expect("store compact progress pages");
    let mut loaded_index = store
        .load_work_queue_progress_index_for_target(target)
        .expect("load compact progress index");
    let mut changed_page_batch = SourcePackWorkQueueProgressChangedPageBatch::new(1);
    let newly_ready_count = source_pack_work_queue_record_dependent_range_dependency_completed(
        &store,
        target,
        &mut loaded_index,
        &mut changed_page_batch,
        &SourcePackJobIndexRange {
            first_job_index: 1,
            job_count: 4,
        },
    )
    .expect("update range dependents from bounded progress pages");
    changed_page_batch
        .flush(&store, target, &mut loaded_index)
        .expect("flush changed progress pages");
    store
        .store_work_queue_progress_index(&loaded_index)
        .expect("store updated compact progress index");

    assert_eq!(newly_ready_count, 2);
    assert_eq!(loaded_index.ready_item_count, 4);
    let first_page = store
        .load_work_queue_progress_page_for_target(target, 0)
        .expect("load first changed progress page");
    assert!(first_page.remaining_dependency_counts.is_empty());
    assert_eq!(first_page.ready_item_indices, vec![0, 1]);
    let second_page = store
        .load_work_queue_progress_page_for_target(target, 1)
        .expect("load second changed progress page");
    assert_eq!(
        second_page.remaining_dependency_counts,
        vec![SourcePackWorkQueueRemainingDependencyCount {
            item_index: 2,
            remaining_dependency_count: 1,
        }]
    );
    assert_eq!(second_page.ready_item_indices, vec![3]);
    let third_page = store
        .load_work_queue_progress_page_for_target(target, 2)
        .expect("load third progress page");
    assert_eq!(third_page.ready_item_indices, vec![4]);
    assert_eq!(
        third_page.remaining_dependency_counts,
        vec![SourcePackWorkQueueRemainingDependencyCount {
            item_index: 5,
            remaining_dependency_count: 1,
        }]
    );

    std::fs::remove_dir_all(&root).expect("remove dependent range progress test dir");
}

#[test]
fn source_pack_work_queue_progress_claims_complete_and_ready_dependents() {
    fn build_unit_page(
        partition_index: usize,
        library_id: u32,
        first_source_index: usize,
        dependency_library_ids: Vec<u32>,
    ) -> SourcePackLibraryBuildUnitPage {
        SourcePackLibraryBuildUnitPage {
            version: SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            partition_index,
            library_id,
            dependency_library_ids,
            first_source_index,
            source_file_count: 1,
            source_byte_count: 4,
            source_line_count: 0,
            limits: CodegenUnitLimits {
                max_source_bytes: 8,
                max_source_files: 8,
            },
            frontend_unit: LibraryUnit {
                library_index: 0,
                library_id,
                first_source_index,
                source_file_count: 1,
                source_bytes: 4,
                source_lines: 0,
            },
            frontend_unit_count: 1,
            frontend_units: Vec::new(),
            codegen_unit_count: 1,
            codegen_units: vec![CodegenUnit {
                unit_index: 0,
                library_id,
                first_source_index,
                source_file_count: 1,
                source_bytes: 4,
                source_lines: 0,
                oversized_source_file: false,
            }],
        }
    }

    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-progress-claim-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let build_unit_pages = vec![
        build_unit_page(0, 10, 0, Vec::new()),
        build_unit_page(1, 20, 1, vec![10]),
        build_unit_page(2, 30, 2, vec![20]),
    ];
    let schedule_plan =
        source_pack_library_schedule_plan(&build_unit_pages).expect("build schedule plan");
    let schedule_index = &schedule_plan.index;
    let schedule_pages = source_pack_library_schedule_pages(&build_unit_pages, &schedule_plan)
        .expect("build schedule pages");
    let (link_plan_index, link_group_pages) = source_pack_hierarchical_link_plan(
        &schedule_index,
        &schedule_pages,
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 2,
            max_source_bytes_per_batch: 8,
            max_source_files_per_batch: 2,
        },
    )
    .expect("build hierarchical link plan");
    let (work_queue_index, work_queue_pages) = source_pack_work_queue(
        &schedule_index,
        &schedule_pages,
        &link_plan_index,
        &link_group_pages,
    )
    .expect("build work queue");
    let (progress_index, progress_pages) =
        source_pack_initial_work_queue_progress_from_pages(&work_queue_index, &work_queue_pages, 4)
            .expect("build initial work queue progress");

    for page in &work_queue_pages {
        for &dependency_item_index in &page.dependency_item_indices {
            assert!(
                work_queue_pages[dependency_item_index]
                    .dependent_item_indices
                    .contains(&page.item_index),
                "dependency item {dependency_item_index} should list {} as a dependent",
                page.item_index
            );
        }
    }

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    store
        .store_work_queue(&work_queue_index, &work_queue_pages)
        .expect("store work queue");
    store
        .store_work_queue_progress(&progress_index, &progress_pages)
        .expect("store work queue progress");

    let initial = source_pack_filesystem_work_queue_progress_snapshot_for_target_at(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        8,
        Some(0),
    )
    .expect("initial work queue progress snapshot");
    assert_eq!(initial.completed_item_count, 0);
    assert_eq!(initial.ready_item_count, 1);
    assert_eq!(initial.claimed_item_count, 0);
    assert_eq!(initial.ready_item_indices, vec![0]);

    let first_claim = source_pack_filesystem_work_queue_claim_ready_item_for_target_at(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        "worker-a",
        Some(100),
        8,
        Some(0),
    )
    .expect("claim first ready work item");
    assert_eq!(first_claim.claimed_item_index, Some(0));
    assert_eq!(first_claim.progress.ready_item_indices, Vec::<usize>::new());
    assert_eq!(first_claim.progress.claimed_item_count, 1);

    let blocked_claim = source_pack_filesystem_work_queue_claim_ready_item_for_target_at(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        "worker-b",
        Some(100),
        8,
        Some(0),
    )
    .expect("active claim should hide ready work from another worker");
    assert_eq!(blocked_claim.claimed_item_index, None);

    let completion = source_pack_filesystem_work_queue_record_claimed_item_complete_for_target_at(
        &artifact_root,
        0,
        SourcePackArtifactTarget::Wasm,
        "worker-a",
        8,
        Some(0),
    )
    .expect("complete first claimed work item");
    assert!(completion.newly_completed);
    assert_eq!(completion.newly_ready_item_count, 2);
    assert_eq!(completion.progress.completed_item_count, 1);
    assert_eq!(completion.progress.claimed_item_count, 0);
    assert_eq!(completion.progress.ready_item_indices, vec![1, 3]);

    let wrong_worker_err =
        source_pack_filesystem_work_queue_record_claimed_item_complete_for_target_at(
            &artifact_root,
            1,
            SourcePackArtifactTarget::Wasm,
            "worker-b",
            8,
            Some(0),
        )
        .expect_err("unclaimed ready work item should reject completion");
    assert!(
        wrong_worker_err.to_string().contains("not claimed"),
        "unexpected unclaimed completion error: {wrong_worker_err}"
    );

    let second_claim = source_pack_filesystem_work_queue_claim_ready_item_for_target_at(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        "worker-c",
        Some(100),
        8,
        Some(0),
    )
    .expect("claim next ready work item");
    assert_eq!(second_claim.claimed_item_index, Some(1));
    assert_eq!(second_claim.progress.ready_item_indices, vec![3]);

    let second_completion =
        source_pack_filesystem_work_queue_record_claimed_item_complete_for_target_at(
            &artifact_root,
            1,
            SourcePackArtifactTarget::Wasm,
            "worker-c",
            8,
            Some(0),
        )
        .expect("complete second claimed work item");
    assert_eq!(second_completion.newly_ready_item_count, 2);
    assert_eq!(second_completion.progress.ready_item_indices, vec![2, 3, 4]);

    std::fs::remove_dir_all(&root).expect("remove temp work queue progress claim dir");
}

#[test]
fn source_pack_work_queue_progress_snapshot_reports_frontier_counts_only() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-progress-snapshot-compact-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let index = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target,
        work_item_count: 1,
        page_size: 1,
        page_count: 1,
        artifact_item_count: 0,
        completed_item_count: 0,
        ready_item_count: 1,
        ready_artifact_item_count: 0,
        claimed_item_count: 1,
        first_ready_item_index: Some(0),
        first_ready_artifact_item_index: None,
    };

    let snapshot = source_pack_filesystem_work_queue_progress_snapshot_from_index(
        &store,
        target,
        &index,
        0,
        Some(0),
    )
    .expect("build compact work-queue snapshot");

    assert_eq!(snapshot.ready_item_count, 1);
    assert_eq!(snapshot.claimed_item_count, 1);
    assert_eq!(snapshot.ready_item_indices, Vec::<usize>::new());

    if root.exists() {
        std::fs::remove_dir_all(&root).expect("remove temp work-queue snapshot compact dir");
    }
}

#[test]
fn source_pack_work_queue_artifact_items_execute_from_singleton_execution_shards() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-artifact-item-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let prepared = prepare_explicit_source_libraries_filesystem_artifact_build_for_target(
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path],
                dependency_library_ids: vec![10],
            },
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            },
        ],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 8,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare singleton artifact-backed work queue");
    assert_eq!(prepared.initial_ready_work_item_count, 1);
    assert_eq!(prepared.first_ready_work_item_index, Some(0));

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let first_work_item = store
        .load_work_queue_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load first work item");
    assert_eq!(
        first_work_item.kind,
        SourcePackWorkQueueItemKind::LibraryFrontend
    );
    assert_eq!(first_work_item.artifact_batch_index, Some(0));
    let link_leaf = store
        .load_work_queue_page_for_target(SourcePackArtifactTarget::Wasm, 4)
        .expect("load first link work item");
    assert_eq!(link_leaf.kind, SourcePackWorkQueueItemKind::LinkLeaf);
    assert_eq!(link_leaf.artifact_batch_index, None);

    std::fs::write(
        store.build_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic build manifest");
    std::fs::write(
        store.artifact_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic artifact manifest");
    std::fs::write(
        store.work_queue_index_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt work queue index");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let first_claim = source_pack_filesystem_work_queue_claim_ready_artifact_item_for_target_at(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        "worker-a",
        Some(100),
        8,
        Some(0),
    )
    .expect("claim first artifact-backed work item");
    assert_eq!(first_claim.claimed_item_index, Some(0));
    assert_eq!(first_claim.progress.claimed_item_count, 1);
    assert_eq!(first_claim.progress.ready_item_indices, Vec::<usize>::new());

    let first_execution =
        execute_source_pack_filesystem_work_queue_claimed_artifact_item_for_target_at(
            &artifact_root,
            0,
            SourcePackArtifactTarget::Wasm,
            "worker-a",
            8,
            Some(0),
            &mut executor,
        )
        .expect("execute first artifact-backed work item");
    assert_eq!(first_execution.executed_batch.batch_index, 0);
    assert_eq!(first_execution.executed_batch.job_count, 1);
    assert!(first_execution.completion.newly_completed);
    assert_eq!(first_execution.completion.newly_ready_item_count, 2);
    assert_eq!(
        first_execution.completion.progress.ready_item_indices,
        vec![1, 2]
    );
    assert_eq!(executor.events, vec!["frontend:10:1:0"]);

    let second_claim = source_pack_filesystem_work_queue_claim_ready_artifact_item_for_target_at(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        "worker-b",
        Some(100),
        8,
        Some(0),
    )
    .expect("claim second artifact-backed work item");
    assert_eq!(second_claim.claimed_item_index, Some(1));
    assert_eq!(second_claim.progress.ready_item_indices, vec![2]);

    let second_execution =
        execute_source_pack_filesystem_work_queue_claimed_artifact_item_for_target_at(
            &artifact_root,
            1,
            SourcePackArtifactTarget::Wasm,
            "worker-b",
            8,
            Some(0),
            &mut executor,
        )
        .expect("execute second artifact-backed work item");
    assert_eq!(second_execution.executed_batch.batch_index, 1);
    assert_eq!(second_execution.executed_batch.job_count, 1);
    assert_eq!(second_execution.completion.newly_ready_item_count, 1);
    assert_eq!(
        second_execution.completion.progress.ready_item_indices,
        vec![2, 3]
    );
    assert_eq!(executor.events, vec!["frontend:10:1:0", "frontend:20:1:1"]);

    std::fs::remove_dir_all(&root).expect("remove temp work queue artifact item dir");
}

#[test]
fn source_pack_work_queue_worker_reclaims_compile_item_after_failed_nested_batch_claim() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-expired-compile-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    prepare_explicit_source_libraries_filesystem_artifact_build_for_target(
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path],
                dependency_library_ids: vec![10],
            },
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            },
        ],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 8,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare bounded work queue");

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    std::fs::write(
        store.build_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic build manifest");
    std::fs::write(
        store.artifact_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic artifact manifest");
    std::fs::write(
        store.work_queue_index_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic work queue index");

    let stale_claim = source_pack_filesystem_work_queue_claim_ready_item_for_target_at(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        "worker-a",
        Some(10),
        16,
        Some(0),
    )
    .expect("claim compile item with expiring lease");
    assert_eq!(stale_claim.claimed_item_index, Some(0));

    let mut executor = RecordingSourcePackByteArtifactExecutor {
        fail_library_interface_calls: 1,
        ..Default::default()
    };
    let failed = execute_source_pack_filesystem_work_queue_claimed_item_for_target_at(
        &artifact_root,
        0,
        SourcePackArtifactTarget::Wasm,
        "worker-a",
        16,
        Some(0),
        &mut executor,
    )
    .expect_err("injected failure should stop before work item completion");
    assert!(
        failed
            .to_string()
            .contains("test injected frontend failure"),
        "unexpected injected failure: {failed}"
    );
    assert_eq!(executor.events, vec!["fail-frontend:10:1:0"]);

    let resumed = execute_source_pack_filesystem_work_queue_worker_run_for_target_at(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        "worker-b",
        16,
        None,
        16,
        Some(20),
        &mut executor,
    )
    .expect("resume after compile-item and nested batch lease expiry");
    assert_eq!(resumed.executed_item_count, 7);
    assert_eq!(resumed.executed_artifact_batch_count, 4);
    assert_eq!(resumed.executed_link_group_count, 3);
    assert!(resumed.progress.complete);
    let final_link_output_key = store
        .load_hierarchical_link_execution_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load link execution index after retry")
        .final_output_key;
    let final_link_output = store
        .load_linked_output(&final_link_output_key)
        .expect("load final linked output after retry");
    assert_eq!(final_link_output, b"hlinked:3:2");

    std::fs::remove_dir_all(&root).expect("remove temp expired compile item dir");
}

#[test]
fn source_pack_work_queue_artifact_items_stream_dependency_interfaces_in_paged_batches() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-paged-artifact-item-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    prepare_explicit_source_libraries_filesystem_artifact_build_for_target(
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path],
                dependency_library_ids: vec![10],
            },
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            },
        ],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 8,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
        SourcePackArtifactTarget::Generic,
    )
    .expect("prepare bounded work queue with paged artifact inputs");

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    for (batch_index, job_index, input_count) in [(1usize, 1usize, 1usize), (3, 3, 2)] {
        let execution_shard = source_pack_execution_shard_for_batch_locator(
            &store,
            SourcePackArtifactTarget::Generic,
            batch_index,
        )
        .expect("load execution shard for paged input manifest");
        let job_manifest = source_pack_execution_shard_job_artifact(&execution_shard, job_index)
            .expect("load job artifact manifest from execution shard");
        assert_eq!(job_manifest.input_interface_count, input_count);
        if job_index == 1 {
            assert_eq!(job_manifest.input_interface_page_count, 0);
            assert_eq!(job_manifest.input_interface_ranges.len(), 1);
        } else {
            assert_eq!(job_manifest.input_interface_page_count, 1);
            assert_eq!(job_manifest.input_interface_ranges.len(), 1);
        }
        assert!(
            job_manifest.input_interfaces.is_empty(),
            "stored execution shards must reference dependency interfaces through pages or ranges"
        );
    }

    std::fs::write(
        store.build_manifest_path_for_target(SourcePackArtifactTarget::Generic),
        b"not json",
    )
    .expect("corrupt monolithic build manifest");
    std::fs::write(
        store.artifact_manifest_path_for_target(SourcePackArtifactTarget::Generic),
        b"not json",
    )
    .expect("corrupt monolithic artifact manifest");
    std::fs::write(
        store.work_queue_index_path_for_target(SourcePackArtifactTarget::Generic),
        b"not json",
    )
    .expect("corrupt monolithic work queue index");

    let mut executor = RecordingSourcePackByteArtifactExecutor {
        record_paged_dependency_batches: true,
        ..Default::default()
    };
    let run = execute_source_pack_filesystem_work_queue_worker_run_for_target_at(
        &artifact_root,
        SourcePackArtifactTarget::Generic,
        "worker-a",
        16,
        Some(100),
        16,
        Some(0),
        &mut executor,
    )
    .expect("run paged work queue");
    assert!(run.progress.complete);
    let final_output_key = store
        .load_hierarchical_link_execution_index_for_target(SourcePackArtifactTarget::Generic)
        .expect("load hierarchical link execution index")
        .final_output_key;
    let final_output_path = store
        .path_for_key(&final_output_key)
        .expect("resolve final output path");
    assert_eq!(
        std::fs::read(final_output_path).expect("read linked output"),
        b"hlinked:3:2"
    );
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "frontend-deps:20:1"),
        "app frontend dependencies should be streamed as a paged batch: {:?}",
        executor.events
    );
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "codegen-deps:20:1"),
        "app codegen dependencies should be streamed as a paged batch: {:?}",
        executor.events
    );
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "frontend:20:1:1"),
        "paged frontend finish should see exactly one dependency: {:?}",
        executor.events
    );
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "codegen:20:1..2:1:1"),
        "paged codegen finish should exclude the owning interface and see one dependency: {:?}",
        executor.events
    );

    std::fs::remove_dir_all(&root).expect("remove temp paged artifact item dir");
}

#[test]
fn source_pack_public_execution_limit_helpers_preserve_zero_and_cap_oversized_values() {
    assert_eq!(source_pack_limit_ready_state_batches(0), 0);
    assert_eq!(source_pack_limit_ready_state_batches(2), 2);
    assert_eq!(
        source_pack_limit_ready_state_batches(SOURCE_PACK_READY_STATE_BATCH_DEFAULT_LIMIT + 1),
        SOURCE_PACK_READY_STATE_BATCH_DEFAULT_LIMIT
    );
    assert_eq!(source_pack_limit_ready_state_items(0), 0);
    assert_eq!(source_pack_limit_ready_state_items(2), 2);
    assert_eq!(
        source_pack_limit_ready_state_items(SOURCE_PACK_READY_STATE_ITEM_DEFAULT_LIMIT + 1),
        SOURCE_PACK_READY_STATE_ITEM_DEFAULT_LIMIT
    );
    assert_eq!(source_pack_limit_artifact_worker_run_batches(0), 0);
    assert_eq!(source_pack_limit_artifact_worker_run_batches(2), 2);
    assert_eq!(
        source_pack_limit_artifact_worker_run_batches(
            SOURCE_PACK_ARTIFACT_MANIFEST_WORKER_RUN_DEFAULT_BATCH_LIMIT + 1
        ),
        SOURCE_PACK_ARTIFACT_MANIFEST_WORKER_RUN_DEFAULT_BATCH_LIMIT
    );
    assert_eq!(source_pack_limit_artifact_manifest_full_build_batches(0), 0);
    assert_eq!(source_pack_limit_artifact_manifest_full_build_batches(2), 2);
    assert_eq!(
        source_pack_limit_artifact_manifest_full_build_batches(
            SOURCE_PACK_ARTIFACT_MANIFEST_FULL_BUILD_DEFAULT_BATCH_LIMIT + 1
        ),
        SOURCE_PACK_ARTIFACT_MANIFEST_FULL_BUILD_DEFAULT_BATCH_LIMIT
    );
    assert_eq!(source_pack_limit_work_queue_worker_run_items(0), 0);
    assert_eq!(source_pack_limit_work_queue_worker_run_items(2), 2);
    assert_eq!(
        source_pack_limit_work_queue_worker_run_items(
            SOURCE_PACK_WORK_QUEUE_WORKER_RUN_DEFAULT_ITEM_LIMIT + 1
        ),
        SOURCE_PACK_WORK_QUEUE_WORKER_RUN_DEFAULT_ITEM_LIMIT
    );
}

#[test]
fn source_pack_work_queue_worker_run_honors_zero_item_limit() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-zero-worker-run-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    std::fs::write(&core_path, b"core").expect("write core source");

    prepare_explicit_source_libraries_filesystem_artifact_build_for_target(
        vec![ExplicitSourceLibraryPaths {
            library_id: 10,
            paths: vec![core_path],
            dependency_library_ids: Vec::new(),
        }],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 1,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare bounded work queue");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let run = execute_source_pack_filesystem_work_queue_worker_run_for_target_at(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        "worker-zero",
        0,
        Some(100),
        8,
        Some(0),
        &mut executor,
    )
    .expect("zero-item work queue run should report progress");

    assert_eq!(run.worker_id, "worker-zero");
    assert_eq!(run.executed_item_count, 0);
    assert_eq!(run.executed_artifact_batch_count, 0);
    assert_eq!(run.executed_link_group_count, 0);
    assert_eq!(run.progress.completed_item_count, 0);
    assert_eq!(run.progress.ready_item_count, 1);
    assert_eq!(run.progress.ready_item_indices, vec![0]);
    assert!(!run.progress.complete);
    assert_eq!(run.linked_output_key, None);
    assert_eq!(run.linked_output_path, None);
    assert!(executor.events.is_empty());

    std::fs::remove_dir_all(&root).expect("remove zero-item work queue run test dir");
}

#[test]
fn source_pack_work_queue_executes_hierarchical_link_items_from_bounded_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-link-item-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let prepared = prepare_explicit_source_libraries_filesystem_artifact_build_for_target(
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path],
                dependency_library_ids: vec![10],
            },
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            },
        ],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 8,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare bounded work queue");
    assert_eq!(prepared.hierarchical_link_execution_group_count, 3);

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    std::fs::write(
        store.build_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic build manifest");
    std::fs::write(
        store.artifact_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic artifact manifest");
    std::fs::write(
        store.work_queue_index_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic work queue index");
    let releasable_output_paths = (0..6usize)
        .filter_map(|item_index| {
            let item = store
                .load_work_queue_page_for_target(SourcePackArtifactTarget::Wasm, item_index)
                .expect("load bounded work item page");
            source_pack_work_queue_item_output_key_for_release(
                &store,
                SourcePackArtifactTarget::Wasm,
                &item,
            )
            .expect("resolve releasable output key")
            .map(|(key, _label)| {
                let path = store.path_for_key(&key).expect("output key path");
                (key, path)
            })
        })
        .collect::<Vec<_>>();
    assert_eq!(releasable_output_paths.len(), 6);

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let run = execute_source_pack_filesystem_work_queue_worker_run_for_target_at(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        "worker-all",
        16,
        None,
        16,
        None,
        &mut executor,
    )
    .expect("run mixed work queue worker");

    assert_eq!(run.executed_item_count, 7);
    assert_eq!(run.executed_artifact_batch_count, 4);
    assert_eq!(run.executed_link_group_count, 3);
    let final_link_output_key = store
        .load_hierarchical_link_execution_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load link execution index after worker run")
        .final_output_key;
    let final_link_output = store
        .load_linked_output(&final_link_output_key)
        .expect("load bounded final linked output");
    assert_eq!(final_link_output, b"hlinked:3:2");
    assert_eq!(
        run.linked_output_key.as_deref(),
        Some(final_link_output_key.as_str())
    );
    assert_eq!(
        run.linked_output_path.as_deref(),
        Some(
            store
                .path_for_key(&final_link_output_key)
                .expect("resolve final linked output path")
                .as_path()
        )
    );
    for (key, path) in releasable_output_paths {
        assert!(
            !path.exists(),
            "bounded intermediate artifact {key:?} should be released"
        );
    }
    let progress_index = store
        .load_work_queue_progress_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load completed work queue progress index");
    let mut progress_index = progress_index;
    let final_work_item = store
        .load_work_queue_page_for_target(SourcePackArtifactTarget::Wasm, 6)
        .expect("load final bounded work item");
    let replayed_release_count =
        release_source_pack_work_queue_consumed_outputs_after_item_completion(
            &store,
            SourcePackArtifactTarget::Wasm,
            &mut progress_index,
            &final_work_item,
        )
        .expect("replay cleanup after intermediate artifacts were already released");
    assert_eq!(replayed_release_count, 2);
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "finish-hlink:2:3:2")
    );
    assert!(run.progress.complete);

    std::fs::remove_dir_all(&root).expect("remove temp work queue link item dir");
}

#[test]
fn source_pack_work_queue_path_artifacts_execute_hierarchical_link_items_from_bounded_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-path-artifact-link-item-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    let executor_root = root.join("executor-artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let prepared = prepare_explicit_source_libraries_filesystem_artifact_build_for_target(
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path],
                dependency_library_ids: vec![10],
            },
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            },
        ],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 8,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare bounded path-artifact work queue");
    assert_eq!(prepared.hierarchical_link_execution_group_count, 3);

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    std::fs::write(
        store.build_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic build manifest");
    std::fs::write(
        store.artifact_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic artifact manifest");
    std::fs::write(
        store.work_queue_index_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic work queue index");

    let mut executor = RecordingSourcePackFileArtifactExecutor::new(executor_root);
    let run =
        execute_source_pack_filesystem_work_queue_worker_run_with_path_artifacts_for_target_at(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            "worker-all",
            16,
            None,
            16,
            None,
            &mut executor,
        )
        .expect("run path-artifact mixed work queue worker");

    assert_eq!(run.executed_item_count, 7);
    assert_eq!(run.executed_artifact_batch_count, 4);
    assert_eq!(run.executed_link_group_count, 3);
    assert!(run.progress.complete);
    let final_link_output_key = store
        .load_hierarchical_link_execution_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load path-artifact link execution index after worker run")
        .final_output_key;
    let final_link_output_path = store
        .path_for_key(&final_link_output_key)
        .expect("resolve path-artifact final linked output path");
    assert_eq!(
        std::fs::read(&final_link_output_path).expect("read path-artifact final linked output"),
        b"hlinked:3:2"
    );
    assert_eq!(
        run.linked_output_key.as_deref(),
        Some(final_link_output_key.as_str())
    );
    assert_eq!(
        run.linked_output_path.as_deref(),
        Some(final_link_output_path.as_path())
    );
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "finish-hlink:2:3:2"),
        "path-artifact hierarchical link should finish final output: {:?}",
        executor.events
    );

    std::fs::remove_dir_all(&root).expect("remove temp path-artifact work queue link item dir");
}

#[test]
fn prepared_path_artifact_work_queue_chunk_can_resume_without_manifests() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-sync-path-artifact-work-queue-entrypoint-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    let executor_root = root.join("executor-artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 8,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };
    let prepared = prepare_explicit_source_pack_paths_filesystem_artifact_build_for_target(
        &[&core_path],
        &[&app_path],
        &artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare path-artifact work queue");
    assert_eq!(prepared.artifact_root, artifact_root);
    assert_eq!(prepared.target, SourcePackArtifactTarget::Wasm);
    assert_eq!(prepared.work_queue_item_count, 7);
    assert_eq!(prepared.initial_ready_work_item_count, 1);
    let prepared_build = prepared.prepared_build();
    assert_eq!(prepared_build.artifact_root(), artifact_root.as_path());
    assert_eq!(prepared_build.target(), SourcePackArtifactTarget::Wasm);
    assert_eq!(
        prepared_build
            .work_queue_progress_snapshot(16)
            .expect("prepared progress snapshot")
            .completed_item_count,
        0
    );

    let mut executor = RecordingSourcePackFileArtifactExecutor::new(executor_root);
    let first = prepared_build
        .submit_path_artifact_work_queue_step("worker-a", None, 16, &mut executor)
        .expect("run one prepared path-artifact work-queue step");
    assert_eq!(first.claimed_item_index, Some(0));
    let first_item = first
        .executed_item
        .as_ref()
        .expect("first prepared work-queue step should execute one item");
    assert!(matches!(
        &first_item.executed,
        SourcePackFilesystemWorkQueueExecutedItem::ArtifactBatch(_)
    ));
    assert_eq!(first.progress.completed_item_count, 1);
    assert!(!first.progress.complete);
    assert_eq!(executor.events, vec!["frontend:0:1:0"]);

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    std::fs::write(
        store.build_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic build manifest");
    std::fs::write(
        store.artifact_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic artifact manifest");
    std::fs::write(
        store.work_queue_index_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic work queue index");

    let reopened_build = SourcePackFilesystemPreparedArtifactBuild::new(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    );
    let reopened_summary = reopened_build
        .bounded_summary(1)
        .expect("summarize reopened prepared build from persisted indexes");
    assert_eq!(reopened_summary.target, SourcePackArtifactTarget::Wasm);
    assert_eq!(reopened_summary.artifact_root, artifact_root);
    assert_eq!(
        reopened_summary.source_file_count,
        prepared.source_file_count
    );
    assert_eq!(
        reopened_summary.source_byte_count,
        prepared.source_byte_count
    );
    assert_eq!(
        reopened_summary.source_line_count,
        prepared.source_line_count
    );
    assert_eq!(
        reopened_summary.scheduled_job_count,
        prepared.scheduled_job_count
    );
    assert_eq!(reopened_summary.batch_count, prepared.batch_count);
    assert_eq!(reopened_summary.artifact_count, prepared.artifact_count);
    assert_eq!(
        reopened_summary.artifact_shard_count,
        prepared.artifact_shard_count
    );
    assert_eq!(
        reopened_summary.work_queue_item_count,
        prepared.work_queue_item_count
    );
    assert_eq!(
        reopened_summary.work_queue_progress_page_count,
        prepared.work_queue_progress_page_count
    );
    assert_eq!(reopened_summary.progress.completed_item_count, 1);
    assert!(reopened_summary.progress.ready_item_indices.len() <= 1);
    assert!(!reopened_summary.final_output_key.is_empty());
    let resumed = reopened_build
        .submit_path_artifact_work_queue_chunk("worker-b", 16, None, 16, &mut executor)
        .expect("resume prepared sync path-artifact work queue");
    assert_eq!(resumed.executed_item_count, 6);
    assert_eq!(resumed.executed_artifact_batch_count, 3);
    assert_eq!(resumed.executed_link_group_count, 3);
    assert!(resumed.progress.complete);

    let final_link_output_key = store
        .load_hierarchical_link_execution_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load path-artifact link execution index after resume")
        .final_output_key;
    let final_link_output_path = store
        .path_for_key(&final_link_output_key)
        .expect("resolve path-artifact final linked output path");
    assert_eq!(
        std::fs::read(&final_link_output_path).expect("read path-artifact final linked output"),
        b"hlinked:3:2"
    );
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "frontend:1:1:1"),
        "user frontend should consume stdlib interface through path artifacts: {:?}",
        executor.events
    );
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "codegen:1:1..2:1:1"),
        "user codegen should consume stdlib interface through path artifacts: {:?}",
        executor.events
    );
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "finish-hlink:2:3:2"),
        "path-artifact hierarchical link should finish final output: {:?}",
        executor.events
    );

    std::fs::remove_dir_all(&root)
        .expect("remove temp sync path-artifact work queue entrypoint dir");
}

#[test]
fn prepared_path_artifact_work_queue_async_step_can_resume_without_manifests() {
    pollster::block_on(async {
        let suffix = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = std::env::temp_dir().join(format!(
            "laniusc-async-path-artifact-work-queue-entrypoint-test-{}-{suffix}",
            std::process::id()
        ));
        let source_root = root.join("sources");
        let artifact_root = root.join("artifacts");
        let executor_root = root.join("executor-artifacts");
        std::fs::create_dir_all(&source_root).expect("create temp source dir");
        let core_path = source_root.join("core.lani");
        let app_path = source_root.join("app.lani");
        std::fs::write(&core_path, b"core").expect("write core source");
        std::fs::write(&app_path, b"app!").expect("write app source");

        let limits = CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 8,
        };
        let batch_limits = SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        };
        let mut executor = RecordingSourcePackFileArtifactExecutor::new(executor_root);
        let first =
                execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target(
                    &[&core_path],
                    &[&app_path],
                    &artifact_root,
                    limits,
                    batch_limits,
                    SourcePackArtifactTarget::Wasm,
                    "worker-a",
                    None,
                    16,
                    &mut executor,
                )
                .await
                .expect("run one async path-artifact work-queue step");
        assert_eq!(first.claimed_item_index, Some(0));
        let first_item = first
            .executed_item
            .as_ref()
            .expect("first async work-queue step should execute one item");
        assert!(matches!(
            &first_item.executed,
            SourcePackFilesystemWorkQueueExecutedItem::ArtifactBatch(_)
        ));
        assert_eq!(first.progress.completed_item_count, 1);
        assert!(!first.progress.complete);
        assert_eq!(executor.events, vec!["frontend:0:1:0"]);

        let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
        std::fs::write(
            store.build_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
            b"not json",
        )
        .expect("corrupt monolithic build manifest");
        std::fs::write(
            store.artifact_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
            b"not json",
        )
        .expect("corrupt monolithic artifact manifest");
        std::fs::write(
            store.work_queue_index_path_for_target(SourcePackArtifactTarget::Wasm),
            b"not json",
        )
        .expect("corrupt monolithic work queue index");

        let reopened_build = SourcePackFilesystemPreparedArtifactBuild::new(
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
        );
        let reopened_summary = reopened_build
            .bounded_summary(1)
            .expect("summarize reopened prepared async build from persisted indexes");
        assert_eq!(reopened_summary.progress.completed_item_count, 1);
        assert!(reopened_summary.progress.ready_item_indices.len() <= 1);
        assert!(!reopened_summary.final_output_key.is_empty());
        let resumed = reopened_build
            .submit_path_artifact_work_queue_chunk_async("worker-b", 16, None, 16, &mut executor)
            .await
            .expect("resume prepared async path-artifact work queue");
        assert_eq!(resumed.executed_item_count, 6);
        assert_eq!(resumed.executed_artifact_batch_count, 3);
        assert_eq!(resumed.executed_link_group_count, 3);
        assert!(resumed.progress.complete);

        let final_link_output_key = store
            .load_hierarchical_link_execution_index_for_target(SourcePackArtifactTarget::Wasm)
            .expect("load path-artifact link execution index after async resume")
            .final_output_key;
        let final_link_output_path = store
            .path_for_key(&final_link_output_key)
            .expect("resolve async path-artifact final linked output path");
        assert_eq!(
            std::fs::read(&final_link_output_path)
                .expect("read async path-artifact final linked output"),
            b"hlinked:3:2"
        );
        assert!(
            executor
                .events
                .iter()
                .any(|event| event == "frontend:1:1:1"),
            "async user frontend should consume stdlib interface through path artifacts: {:?}",
            executor.events
        );
        assert!(
            executor
                .events
                .iter()
                .any(|event| event == "codegen:1:1..2:1:1"),
            "async user codegen should consume stdlib interface through path artifacts: {:?}",
            executor.events
        );
        assert!(
            executor
                .events
                .iter()
                .any(|event| event == "finish-hlink:2:3:2"),
            "async path-artifact hierarchical link should finish final output: {:?}",
            executor.events
        );

        std::fs::remove_dir_all(&root)
            .expect("remove temp async path-artifact work queue entrypoint dir");
    });
}

#[test]
fn prepared_work_queue_completion_uses_progress_dependency_counters() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-dependency-counter-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    let executor_root = root.join("executor-artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let prepared = prepare_explicit_source_pack_paths_filesystem_artifact_build_for_target(
        &[&core_path],
        &[&app_path],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 8,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare path-artifact work queue");
    assert_eq!(prepared.initial_ready_work_item_count, 1);

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let first_work_item = store
        .load_work_queue_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load first work item");
    assert!(
        source_pack_work_queue_page_dependent_count(&first_work_item) > 0,
        "initial ready item should have finalized reverse-dependent counts"
    );
    let progress_index = store
        .load_work_queue_progress_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load prepared progress index");
    let first_progress_page_index =
        source_pack_work_queue_progress_page_index_for_item(&progress_index, 0)
            .expect("first work item progress page index");
    let first_progress_page = store
        .load_work_queue_progress_page_for_target(
            SourcePackArtifactTarget::Wasm,
            first_progress_page_index,
        )
        .expect("load first progress page");
    let first_release_counter = first_progress_page
        .remaining_dependent_counts
        .iter()
        .find(|remaining| remaining.item_index == first_work_item.item_index)
        .expect("prepared progress should seed reverse-dependent release counter");
    assert_eq!(
        first_release_counter.remaining_dependent_count,
        source_pack_work_queue_page_dependent_count(&first_work_item)
    );
    let mut dependent_item_index = None;
    source_pack_for_each_work_queue_dependent_item(
        &store,
        SourcePackArtifactTarget::Wasm,
        &first_work_item,
        |item_index| {
            let item = store
                .load_work_queue_page_for_target(SourcePackArtifactTarget::Wasm, item_index)?;
            if item.dependency_page_count > 0
                && source_pack_work_queue_page_dependency_count(&item) == 1
            {
                dependent_item_index = Some(item_index);
                return Ok(false);
            }
            Ok(true)
        },
    )
    .expect("find single-dependency dependent of initial ready item");
    let dependent_item_index =
        dependent_item_index.expect("initial ready item should have a single-dependency dependent");
    let dependent_work_item = store
        .load_work_queue_page_for_target(SourcePackArtifactTarget::Wasm, dependent_item_index)
        .expect("load dependent work item");
    assert!(
        dependent_work_item.dependency_page_count > 0,
        "dependent fixture should store dependencies as paged records"
    );
    let dependent_dependency_page = store.work_queue_dependencies_page_path_for_target(
        SourcePackArtifactTarget::Wasm,
        dependent_item_index,
        0,
    );
    assert!(
        dependent_dependency_page.is_file(),
        "dependent fixture should store dependencies as a paged record"
    );
    std::fs::write(&dependent_dependency_page, b"not json")
        .expect("corrupt dependent dependency page");

    let mut executor = RecordingSourcePackFileArtifactExecutor::new(executor_root);
    let first = prepared
        .prepared_build()
        .submit_path_artifact_work_queue_chunk("worker-a", 1, None, 16, &mut executor)
        .expect("dependency counters should ready dependents without rescanning dependencies");
    assert_eq!(first.executed_item_count, 1);
    assert_eq!(first.progress.completed_item_count, 1);
    assert!(
        first
            .progress
            .ready_item_indices
            .contains(&dependent_item_index),
        "completed first item should make dependent {dependent_item_index} ready through progress counters: {:?}",
        first.progress.ready_item_indices
    );

    std::fs::remove_dir_all(&root).expect("remove dependency counter test dir");
}

#[test]
fn source_pack_work_queue_worker_reclaims_expired_link_item() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-expired-link-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    prepare_explicit_source_libraries_filesystem_artifact_build_for_target(
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path],
                dependency_library_ids: vec![10],
            },
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            },
        ],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 8,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare bounded work queue");

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    std::fs::write(
        store.build_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic build manifest");
    std::fs::write(
        store.artifact_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic artifact manifest");
    std::fs::write(
        store.work_queue_index_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("corrupt monolithic work queue index");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let compile_frontier = execute_source_pack_filesystem_work_queue_worker_run_for_target_at(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        "worker-a",
        4,
        None,
        16,
        Some(0),
        &mut executor,
    )
    .expect("run compile frontier");
    assert_eq!(compile_frontier.executed_item_count, 4);
    assert_eq!(compile_frontier.executed_artifact_batch_count, 4);
    assert_eq!(compile_frontier.progress.ready_item_indices, vec![4, 5]);

    let stale_claim = source_pack_filesystem_work_queue_claim_ready_item_for_target_at(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        "stale-link-worker",
        Some(10),
        16,
        Some(0),
    )
    .expect("claim first link item with expiring lease");
    assert_eq!(stale_claim.claimed_item_index, Some(4));
    assert_eq!(stale_claim.progress.claimed_item_count, 1);
    assert_eq!(stale_claim.progress.ready_item_indices, vec![5]);

    let resumed = execute_source_pack_filesystem_work_queue_worker_run_for_target_at(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        "worker-b",
        16,
        None,
        16,
        Some(20),
        &mut executor,
    )
    .expect("resume after link-item lease expiry");
    assert_eq!(resumed.executed_item_count, 3);
    assert_eq!(resumed.executed_link_group_count, 3);
    assert!(resumed.progress.complete);
    let final_link_output_key = store
        .load_hierarchical_link_execution_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load link execution index after retry")
        .final_output_key;
    let final_link_output = store
        .load_linked_output(&final_link_output_key)
        .expect("load final linked output after retry");
    assert_eq!(final_link_output, b"hlinked:3:2");

    std::fs::remove_dir_all(&root).expect("remove temp expired link item dir");
}

#[test]
fn source_pack_filesystem_library_partitions_page_libraries() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-library-partition-page-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_a_path = source_root.join("core_a.lani");
    let core_b_path = source_root.join("core_b.lani");
    let app_path = source_root.join("app.lani");
    let cli_path = source_root.join("cli.lani");
    std::fs::write(&core_a_path, b"core").expect("write core_a source");
    std::fs::write(&core_b_path, b"base!").expect("write core_b source");
    std::fs::write(&app_path, b"app").expect("write app source");
    std::fs::write(&cli_path, b"cli!!").expect("write cli source");

    let manifest = ExplicitSourcePackPathManifest::from_libraries(vec![
        ExplicitSourceLibraryPaths {
            library_id: 20,
            paths: vec![app_path],
            dependency_library_ids: vec![10],
        },
        ExplicitSourceLibraryPaths {
            library_id: 30,
            paths: vec![cli_path],
            dependency_library_ids: vec![10, 20],
        },
        ExplicitSourceLibraryPaths {
            library_id: 10,
            paths: vec![core_a_path, core_b_path],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect("build explicit source path manifest");
    let partition_plan =
        source_pack_library_partition_plan(&manifest, SourcePackArtifactTarget::X86_64)
            .expect("build library partition plan");
    let index = &partition_plan.index;
    let source_file_pages = source_pack_library_source_file_pages(&manifest, &partition_plan)
        .expect("build library source-file pages");

    assert_eq!(index.target, SourcePackArtifactTarget::X86_64);
    assert_eq!(index.source_file_count, 4);
    assert_eq!(index.source_byte_count, 17);
    assert_eq!(
        partition_plan
            .partitions
            .iter()
            .map(|partition| (
                partition.library_id,
                partition.first_source_index,
                partition.source_file_count,
                partition.source_byte_count,
                partition.dependency_library_ids.clone(),
            ))
            .collect::<Vec<_>>(),
        vec![
            (10, 0, 2, 9, Vec::new()),
            (20, 2, 1, 3, vec![10]),
            (30, 3, 1, 5, vec![10, 20]),
        ]
    );
    assert_eq!(
        source_file_pages
            .iter()
            .map(|page| (
                page.library_id,
                page.first_source_index,
                page.source_file_count,
                page.source_files
                    .iter()
                    .map(|source_file| source_file.source_index)
                    .collect::<Vec<_>>(),
            ))
            .collect::<Vec<_>>(),
        vec![
            (10, 0, 2, vec![0, 1]),
            (20, 2, 1, vec![2]),
            (30, 3, 1, vec![3])
        ]
    );

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let stored = store
        .store_library_partition_index(index, &partition_plan.partitions)
        .expect("store library partition index");
    let source_file_page_store = store
        .store_library_source_file_pages(&source_file_pages)
        .expect("store library source-file pages");
    assert!(
        stored
            .library_partition_index_path
            .ends_with("source-pack-library-partitions.x86_64.json")
    );
    assert_eq!(stored.library_partition_count, 3);
    assert_eq!(source_file_page_store.library_source_file_page_count, 3);

    let loaded_index = store
        .load_library_partition_index_for_target(SourcePackArtifactTarget::X86_64)
        .expect("load library partition index");
    assert_eq!(loaded_index.target, index.target);
    assert_eq!(loaded_index.partition_count, index.partition_count);
    assert_eq!(loaded_index.source_file_count, index.source_file_count);
    assert_eq!(loaded_index.source_byte_count, index.source_byte_count);
    assert_stored_partition_index_has_no_inline_partitions(
        &store,
        SourcePackArtifactTarget::X86_64,
    );
    let loaded_app_partition = store
        .load_library_partition_for_target(SourcePackArtifactTarget::X86_64, 1)
        .expect("load app library partition");
    assert_eq!(loaded_app_partition.library_id, 20);
    assert!(
        loaded_app_partition.dependency_library_ids.is_empty(),
        "persisted partition pages should leave dependency libraries in dependency pages"
    );
    assert_eq!(
        source_pack_load_library_dependency_ids(&store, &loaded_app_partition)
            .expect("load app library dependency pages"),
        vec![10]
    );
    let loaded_app_source_file_page = store
        .load_library_source_file_page_for_target(SourcePackArtifactTarget::X86_64, 1)
        .expect("load app library source-file page");
    assert_eq!(loaded_app_source_file_page.library_id, 20);
    assert!(
        loaded_app_source_file_page.source_files.is_empty(),
        "persisted source-file pages should leave source-file records in per-source pages"
    );
    let loaded_app_source_file_record = store
        .load_library_source_file_record_page_for_target(SourcePackArtifactTarget::X86_64, 2)
        .expect("load app source-file record page");
    assert_eq!(loaded_app_source_file_record.partition_index, 1);
    assert_eq!(loaded_app_source_file_record.library_id, 20);
    assert_eq!(loaded_app_source_file_record.file.byte_len, 3);

    std::fs::write(
        store.library_partition_path_for_target(SourcePackArtifactTarget::X86_64, 2),
        b"not json",
    )
    .expect("corrupt unrelated library partition");
    let loaded_core_partition = store
        .load_library_partition_for_target(SourcePackArtifactTarget::X86_64, 0)
        .expect("load unaffected core library partition");
    assert_eq!(loaded_core_partition.library_id, 10);
    store
        .load_library_partition_index_for_target(SourcePackArtifactTarget::X86_64)
        .expect("load index without reading corrupted partition page");
    std::fs::write(
        store.library_source_file_page_path_for_target(SourcePackArtifactTarget::X86_64, 2),
        b"not json",
    )
    .expect("corrupt unrelated library source-file page");
    let mut partition_cache = BTreeMap::new();
    let mut source_file_page_cache = BTreeMap::new();
    let app_file = source_pack_stored_source_file_for_index(
        &store,
        SourcePackArtifactTarget::X86_64,
        &loaded_index,
        2,
        &mut partition_cache,
        &mut source_file_page_cache,
    )
    .expect("compact partition index should resolve source file from stored pages");
    assert_eq!(app_file.library_id, 20);
    assert_eq!(app_file.byte_len, 3);
    let loaded_core_source_file_page = store
        .load_library_source_file_page_for_target(SourcePackArtifactTarget::X86_64, 0)
        .expect("load unaffected core library source-file page");
    assert_eq!(loaded_core_source_file_page.library_id, 10);

    std::fs::write(
        store.library_partition_index_path_for_target(SourcePackArtifactTarget::X86_64),
        b"not json",
    )
    .expect("corrupt library partition index");
    let loaded_app_partition = store
        .load_library_partition_for_target(SourcePackArtifactTarget::X86_64, 1)
        .expect("load library partition without reading corrupted index");
    assert_eq!(loaded_app_partition.library_id, 20);
    let loaded_app_source_file_page = store
        .load_library_source_file_page_for_target(SourcePackArtifactTarget::X86_64, 1)
        .expect("load source-file page without reading corrupted index");
    assert_eq!(loaded_app_source_file_page.library_id, 20);

    std::fs::remove_dir_all(&root).expect("remove temp library partition dir");
}

#[test]
fn source_pack_library_source_file_pages_reject_unbounded_inline_records() {
    let target = SourcePackArtifactTarget::Wasm;
    let source_file_count = SOURCE_PACK_LIBRARY_SOURCE_FILE_INLINE_DEFAULT_RECORD_CAP + 1;
    let source_files = (0..source_file_count)
        .map(|source_index| SourcePackShardSourceFile {
            source_index,
            file: ExplicitSourcePathFile {
                library_id: 7,
                path: PathBuf::from(format!("source-{source_index}.lani")),
                byte_len: 1,
                modified_unix_nanos: None,
                line_count: Some(1),
            },
        })
        .collect::<Vec<_>>();
    let oversized_inline_page = SourcePackLibrarySourceFilePage {
        version: SOURCE_PACK_LIBRARY_SOURCE_FILE_PAGE_VERSION,
        target,
        partition_index: 0,
        library_id: 7,
        first_source_index: 0,
        source_file_count,
        source_byte_count: source_file_count,
        source_line_count: source_file_count,
        source_files,
    };
    assert!(
        validate_source_pack_library_source_file_page(&oversized_inline_page, target, Some(0))
            .expect_err("oversized inline source-file page should be rejected")
            .to_string()
            .contains("record cap")
    );

    let compact_page = SourcePackLibrarySourceFilePage {
        source_files: Vec::new(),
        ..oversized_inline_page
    };
    validate_source_pack_library_source_file_page(&compact_page, target, Some(0))
        .expect("compact source-file page should allow large partition counts");
}

#[test]
fn source_pack_library_partitions_reject_unbounded_inline_dependency_records() {
    let target = SourcePackArtifactTarget::Wasm;
    let dependency_count = SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE + 1;
    let partition = SourcePackLibraryPartition {
        version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
        target,
        partition_index: dependency_count + 1,
        library_id: 7,
        first_source_index: 0,
        source_file_count: 1,
        source_byte_count: 1,
        source_line_count: 1,
        dependency_library_ids: Vec::new(),
        dependency_library_count: dependency_count,
        dependency_page_count: dependency_count
            .div_ceil(SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE),
    };
    validate_source_pack_library_partition(&partition, target, Some(partition.partition_index))
        .expect("compact partition should allow large paged dependency counts");

    let oversized_inline_partition = SourcePackLibraryPartition {
        dependency_library_ids: (100..).take(dependency_count).collect(),
        dependency_library_count: 0,
        dependency_page_count: 0,
        ..partition
    };
    assert!(
        validate_source_pack_library_partition(
            &oversized_inline_partition,
            target,
            Some(oversized_inline_partition.partition_index),
        )
        .expect_err("oversized inline partition dependencies should be rejected")
        .to_string()
        .contains("record cap")
    );
}

#[test]
fn source_pack_library_build_unit_pages_reject_unbounded_inline_records() {
    fn frontend_unit(unit_index: usize, library_id: u32) -> FrontendUnit {
        FrontendUnit {
            unit_index,
            library_id,
            first_source_index: unit_index,
            source_file_count: 1,
            source_bytes: 1,
            source_lines: 1,
            oversized_source_file: false,
        }
    }

    fn codegen_unit(unit_index: usize, library_id: u32) -> CodegenUnit {
        CodegenUnit {
            unit_index,
            library_id,
            first_source_index: unit_index,
            source_file_count: 1,
            source_bytes: 1,
            source_lines: 1,
            oversized_source_file: false,
        }
    }

    let target = SourcePackArtifactTarget::Wasm;
    let inline_record_count = SOURCE_PACK_LIBRARY_BUILD_UNIT_INLINE_DEFAULT_RECORD_CAP + 1;
    let page = SourcePackLibraryBuildUnitPage {
        version: SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION,
        target,
        partition_index: 0,
        library_id: 7,
        dependency_library_ids: Vec::new(),
        first_source_index: 0,
        source_file_count: inline_record_count,
        source_byte_count: inline_record_count,
        source_line_count: inline_record_count,
        limits: CodegenUnitLimits::default(),
        frontend_unit: LibraryUnit {
            library_index: 0,
            library_id: 7,
            first_source_index: 0,
            source_file_count: inline_record_count,
            source_bytes: inline_record_count,
            source_lines: inline_record_count,
        },
        frontend_unit_count: inline_record_count,
        codegen_unit_count: inline_record_count,
        frontend_units: Vec::new(),
        codegen_units: Vec::new(),
    };
    validate_source_pack_library_build_unit_page(&page, target, Some(0))
        .expect("compact build-unit page should allow large unit counts");

    let oversized_dependencies = SourcePackLibraryBuildUnitPage {
        dependency_library_ids: (100..)
            .take(SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE + 1)
            .collect(),
        ..page.clone()
    };
    assert!(
        validate_source_pack_library_build_unit_page(&oversized_dependencies, target, Some(0))
            .expect_err("oversized inline dependency records should be rejected")
            .to_string()
            .contains("record cap")
    );

    let oversized_frontend_units = SourcePackLibraryBuildUnitPage {
        frontend_units: (0..inline_record_count)
            .map(|unit_index| frontend_unit(unit_index, 7))
            .collect(),
        ..page.clone()
    };
    assert!(
        validate_source_pack_library_build_unit_page(&oversized_frontend_units, target, Some(0))
            .expect_err("oversized inline frontend-unit records should be rejected")
            .to_string()
            .contains("record cap")
    );

    let oversized_codegen_units = SourcePackLibraryBuildUnitPage {
        codegen_units: (0..inline_record_count)
            .map(|unit_index| codegen_unit(unit_index, 7))
            .collect(),
        ..page
    };
    assert!(
        validate_source_pack_library_build_unit_page(&oversized_codegen_units, target, Some(0))
            .expect_err("oversized inline codegen-unit records should be rejected")
            .to_string()
            .contains("record cap")
    );
}

#[test]
fn source_pack_library_schedule_pages_reject_unbounded_inline_records() {
    fn frontend_job(job_index: usize, phase_unit_index: usize, library_id: u32) -> SourcePackJob {
        SourcePackJob {
            job_index,
            phase: SourcePackJobPhase::LibraryFrontend,
            phase_unit_index,
            library_job_index: None,
            library_id,
            first_source_index: phase_unit_index,
            source_file_count: 1,
            source_bytes: 1,
            source_lines: 1,
            oversized_source_file: false,
            dependency_job_indices: Vec::new(),
        }
    }

    fn codegen_job(job_index: usize, phase_unit_index: usize, library_id: u32) -> SourcePackJob {
        SourcePackJob {
            job_index,
            phase: SourcePackJobPhase::Codegen,
            phase_unit_index,
            library_job_index: Some(0),
            library_id,
            first_source_index: phase_unit_index,
            source_file_count: 1,
            source_bytes: 1,
            source_lines: 1,
            oversized_source_file: false,
            dependency_job_indices: vec![0],
        }
    }

    let target = SourcePackArtifactTarget::Wasm;
    let inline_job_count = SOURCE_PACK_LIBRARY_SCHEDULE_INLINE_JOB_DEFAULT_RECORD_CAP + 1;
    let page = SourcePackLibrarySchedulePage {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_PAGE_VERSION,
        target,
        partition_index: 0,
        library_id: 7,
        dependency_library_ids: Vec::new(),
        frontend_job_index: 0,
        first_frontend_unit_index: 0,
        frontend_job_count: inline_job_count,
        first_codegen_unit_index: 0,
        first_codegen_job_index: inline_job_count,
        codegen_job_count: inline_job_count,
        link_job_index: inline_job_count * 2,
        frontend_job: frontend_job(0, 0, 7),
        frontend_jobs: Vec::new(),
        codegen_jobs: Vec::new(),
    };
    validate_source_pack_library_schedule_page(&page, target, Some(0))
        .expect("compact schedule page should allow large job counts");

    let mut oversized_legacy_frontend_job = page.clone();
    oversized_legacy_frontend_job
        .frontend_job
        .oversized_source_file = true;
    oversized_legacy_frontend_job.frontend_job.source_file_count = 2;
    oversized_legacy_frontend_job.frontend_job.source_bytes = 2;
    oversized_legacy_frontend_job.frontend_job.source_lines = 2;
    assert!(
            validate_source_pack_library_schedule_page(
                &oversized_legacy_frontend_job,
                target,
                Some(0),
            )
            .expect_err("invalid legacy frontend job shape should be rejected")
            .to_string()
            .contains("oversized source file")
        );

    let mut oversized_inline_frontend_job = SourcePackLibrarySchedulePage {
        frontend_job_count: 1,
        first_codegen_job_index: 1,
        codegen_job_count: 1,
        link_job_index: 2,
        frontend_jobs: vec![frontend_job(0, 0, 7)],
        ..page.clone()
    };
    oversized_inline_frontend_job.frontend_jobs[0].oversized_source_file = true;
    oversized_inline_frontend_job.frontend_jobs[0].source_file_count = 2;
    oversized_inline_frontend_job.frontend_jobs[0].source_bytes = 2;
    oversized_inline_frontend_job.frontend_jobs[0].source_lines = 2;
    assert!(
            validate_source_pack_library_schedule_page(
                &oversized_inline_frontend_job,
                target,
                Some(0),
            )
            .expect_err("invalid inline frontend job shape should be rejected")
            .to_string()
            .contains("oversized source file")
        );

    let mut oversized_inline_codegen_job = SourcePackLibrarySchedulePage {
        frontend_job_count: 1,
        first_codegen_job_index: 1,
        codegen_job_count: 1,
        link_job_index: 2,
        codegen_jobs: vec![codegen_job(1, 0, 7)],
        ..page.clone()
    };
    oversized_inline_codegen_job.codegen_jobs[0].oversized_source_file = true;
    oversized_inline_codegen_job.codegen_jobs[0].source_file_count = 2;
    oversized_inline_codegen_job.codegen_jobs[0].source_bytes = 2;
    oversized_inline_codegen_job.codegen_jobs[0].source_lines = 2;
    assert!(
        validate_source_pack_library_schedule_page(&oversized_inline_codegen_job, target, Some(0),)
            .expect_err("invalid inline codegen job shape should be rejected")
            .to_string()
            .contains("oversized source file")
    );

    let oversized_dependencies = SourcePackLibrarySchedulePage {
        dependency_library_ids: (100..)
            .take(SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE + 1)
            .collect(),
        ..page.clone()
    };
    assert!(
        validate_source_pack_library_schedule_page(&oversized_dependencies, target, Some(0))
            .expect_err("oversized inline library dependencies should be rejected")
            .to_string()
            .contains("record cap")
    );

    let mut oversized_frontend_dependency_page = page.clone();
    oversized_frontend_dependency_page.frontend_job.job_index =
        SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE + 1;
    oversized_frontend_dependency_page.frontend_job_index =
        oversized_frontend_dependency_page.frontend_job.job_index;
    oversized_frontend_dependency_page.first_codegen_job_index =
        oversized_frontend_dependency_page.frontend_job.job_index + inline_job_count;
    oversized_frontend_dependency_page.link_job_index =
        oversized_frontend_dependency_page.first_codegen_job_index + inline_job_count;
    oversized_frontend_dependency_page
        .frontend_job
        .dependency_job_indices =
        (0..=SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE).collect();
    assert!(
        validate_source_pack_library_schedule_page(
            &oversized_frontend_dependency_page,
            target,
            Some(0),
        )
        .expect_err("oversized inline frontend dependencies should be rejected")
        .to_string()
        .contains("record cap")
    );

    let oversized_frontend_jobs = SourcePackLibrarySchedulePage {
        frontend_jobs: (0..inline_job_count)
            .map(|offset| frontend_job(offset, offset, 7))
            .collect(),
        ..page.clone()
    };
    assert!(
        validate_source_pack_library_schedule_page(&oversized_frontend_jobs, target, Some(0))
            .expect_err("oversized inline frontend-job records should be rejected")
            .to_string()
            .contains("record cap")
    );

    let oversized_codegen_jobs = SourcePackLibrarySchedulePage {
        frontend_job_count: 1,
        first_codegen_job_index: 1,
        codegen_job_count: inline_job_count,
        link_job_index: inline_job_count + 1,
        codegen_jobs: (0..inline_job_count)
            .map(|offset| codegen_job(offset + 1, offset, 7))
            .collect(),
        ..page
    };
    assert!(
        validate_source_pack_library_schedule_page(&oversized_codegen_jobs, target, Some(0))
            .expect_err("oversized inline codegen-job records should be rejected")
            .to_string()
            .contains("record cap")
    );
}

#[test]
fn source_pack_library_schedule_job_pages_reject_unbounded_inline_dependencies() {
    fn schedule_job(job_index: usize, dependencies: Vec<usize>) -> SourcePackJob {
        SourcePackJob {
            job_index,
            phase: SourcePackJobPhase::Codegen,
            phase_unit_index: 0,
            library_job_index: Some(0),
            library_id: 7,
            first_source_index: 0,
            source_file_count: 1,
            source_bytes: 1,
            source_lines: 1,
            oversized_source_file: false,
            dependency_job_indices: dependencies,
        }
    }

    let target = SourcePackArtifactTarget::Wasm;
    let dependency_count = SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE + 1;
    let job_index = dependency_count + 1;
    let page = SourcePackLibraryScheduleJobPage {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_PAGE_VERSION,
        target,
        job_index,
        job: schedule_job(job_index, Vec::new()),
        dependency_job_count: dependency_count,
        dependency_page_count: dependency_count
            .div_ceil(SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE),
        dependency_job_ranges: Vec::new(),
    };
    validate_source_pack_library_schedule_job_page(&page, target, job_index + 1, Some(job_index))
        .expect("compact schedule job page should allow large paged dependency counts");

    let oversized_inline_dependencies = SourcePackLibraryScheduleJobPage {
        job: schedule_job(job_index, (0..dependency_count).collect()),
        dependency_job_count: 0,
        dependency_page_count: 0,
        ..page.clone()
    };
    assert!(
        validate_source_pack_library_schedule_job_page(
            &oversized_inline_dependencies,
            target,
            job_index + 1,
            Some(job_index),
        )
        .expect_err("oversized inline schedule dependencies should be rejected")
        .to_string()
        .contains("record cap")
    );

    let oversized_inline_ranges = SourcePackLibraryScheduleJobPage {
        dependency_job_count: 0,
        dependency_page_count: 0,
        dependency_job_ranges: (0..dependency_count)
            .map(|dependency_job_index| SourcePackJobIndexRange {
                first_job_index: dependency_job_index,
                job_count: 1,
            })
            .collect(),
        ..page
    };
    assert!(
        validate_source_pack_library_schedule_job_page(
            &oversized_inline_ranges,
            target,
            job_index + 1,
            Some(job_index),
        )
        .expect_err("oversized inline schedule dependency ranges should be rejected")
        .to_string()
        .contains("record cap")
    );
}

#[test]
fn source_pack_hierarchical_link_group_pages_reject_unbounded_inline_records() {
    let target = SourcePackArtifactTarget::Wasm;
    let record_count = SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE + 1;
    let compact_reduce_group = SourcePackHierarchicalLinkGroupPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
        target,
        group_index: 1,
        kind: SourcePackHierarchicalLinkGroupKind::Reduce,
        level: 1,
        job_index: 100,
        input_partition_count: record_count,
        input_partition_indices: Vec::new(),
        input_frontend_job_count: 0,
        input_frontend_job_indices: Vec::new(),
        input_codegen_job_indices: Vec::new(),
        input_link_group_indices: vec![0],
        source_byte_count: record_count,
        source_file_count: record_count,
        source_line_count: record_count,
        oversized_input: false,
    };
    validate_source_pack_hierarchical_link_group_page(&compact_reduce_group, target, Some(1))
        .expect("compact reduce group should allow large partition counts");

    let oversized_partition_inputs = SourcePackHierarchicalLinkGroupPage {
        input_partition_indices: (0..record_count).collect(),
        ..compact_reduce_group.clone()
    };
    assert!(
        validate_source_pack_hierarchical_link_group_page(
            &oversized_partition_inputs,
            target,
            Some(1),
        )
        .expect_err("oversized inline partition inputs should be rejected")
        .to_string()
        .contains("record cap")
    );

    let oversized_frontend_inputs = SourcePackHierarchicalLinkGroupPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
        target,
        group_index: 0,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        level: 0,
        job_index: 100,
        input_partition_count: 1,
        input_partition_indices: vec![0],
        input_frontend_job_count: record_count,
        input_frontend_job_indices: (0..record_count).collect(),
        input_codegen_job_indices: vec![record_count],
        input_link_group_indices: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        oversized_input: false,
    };
    assert!(
        validate_source_pack_hierarchical_link_group_page(
            &oversized_frontend_inputs,
            target,
            Some(0),
        )
        .expect_err("oversized inline frontend inputs should be rejected")
        .to_string()
        .contains("record cap")
    );

    let oversized_codegen_inputs = SourcePackHierarchicalLinkGroupPage {
        input_frontend_job_count: 1,
        input_frontend_job_indices: vec![0],
        input_codegen_job_indices: (0..record_count).collect(),
        ..oversized_frontend_inputs.clone()
    };
    assert!(
        validate_source_pack_hierarchical_link_group_page(
            &oversized_codegen_inputs,
            target,
            Some(0),
        )
        .expect_err("oversized inline codegen inputs should be rejected")
        .to_string()
        .contains("record cap")
    );

    let oversized_link_group_inputs = SourcePackHierarchicalLinkGroupPage {
        group_index: record_count,
        input_link_group_indices: (0..record_count).collect(),
        ..compact_reduce_group
    };
    assert!(
        validate_source_pack_hierarchical_link_group_page(
            &oversized_link_group_inputs,
            target,
            Some(record_count),
        )
        .expect_err("oversized inline link-group inputs should be rejected")
        .to_string()
        .contains("record cap")
    );
}

#[test]
fn source_pack_hierarchical_link_execution_pages_reject_unbounded_inline_records() {
    fn artifact_ref(
        target: SourcePackArtifactTarget,
        kind: SourcePackArtifactKind,
        artifact_index: usize,
    ) -> SourcePackArtifactRef {
        SourcePackArtifactRef {
            artifact_index,
            key: source_pack_artifact_key_for_output(
                target,
                kind,
                7,
                artifact_index,
                artifact_index,
                1,
            ),
            producing_job_index: artifact_index,
            kind,
        }
    }

    let target = SourcePackArtifactTarget::Wasm;
    let record_count = SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE + 1;
    let leaf_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: 0,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: record_count + 100,
        input_interface_count: record_count,
        input_interface_page_count: record_count
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE),
        input_interface_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: record_count,
        input_object_page_count: record_count
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE),
        input_objects: Vec::new(),
        input_group_count: 0,
        input_group_page_count: 0,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: source_pack_hierarchical_link_partial_output_key(target, 0, record_count),
        final_output: false,
    };
    validate_source_pack_hierarchical_link_execution_page(&leaf_page, target, Some(0))
        .expect("compact leaf execution page should allow large paged input counts");

    let oversized_interface_ranges = SourcePackHierarchicalLinkExecutionPage {
        input_interface_count: record_count,
        input_interface_page_count: 0,
        input_interface_ranges: (0..record_count)
            .map(|first_job_index| SourcePackJobIndexRange {
                first_job_index,
                job_count: 1,
            })
            .collect(),
        ..leaf_page.clone()
    };
    assert!(
        validate_source_pack_hierarchical_link_execution_page(
            &oversized_interface_ranges,
            target,
            Some(0),
        )
        .expect_err("oversized inline interface ranges should be rejected")
        .to_string()
        .contains("record cap")
    );

    let oversized_interfaces = SourcePackHierarchicalLinkExecutionPage {
        input_interface_count: record_count,
        input_interface_page_count: 0,
        input_interfaces: (0..record_count)
            .map(|artifact_index| {
                artifact_ref(
                    target,
                    SourcePackArtifactKind::LibraryInterface,
                    artifact_index,
                )
            })
            .collect(),
        ..leaf_page.clone()
    };
    assert!(
        validate_source_pack_hierarchical_link_execution_page(
            &oversized_interfaces,
            target,
            Some(0),
        )
        .expect_err("oversized inline interface refs should be rejected")
        .to_string()
        .contains("record cap")
    );

    let oversized_objects = SourcePackHierarchicalLinkExecutionPage {
        input_object_count: record_count,
        input_object_page_count: 0,
        input_objects: (0..record_count)
            .map(|artifact_index| {
                artifact_ref(
                    target,
                    SourcePackArtifactKind::CodegenObject,
                    artifact_index,
                )
            })
            .collect(),
        ..leaf_page.clone()
    };
    assert!(
        validate_source_pack_hierarchical_link_execution_page(&oversized_objects, target, Some(0),)
            .expect_err("oversized inline object refs should be rejected")
            .to_string()
            .contains("record cap")
    );

    let partial_record_count =
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE + 1;
    let reduce_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: partial_record_count,
        kind: SourcePackHierarchicalLinkGroupKind::Reduce,
        job_index: partial_record_count + 100,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: Vec::new(),
        input_group_count: partial_record_count,
        input_group_page_count: partial_record_count
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE),
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: source_pack_hierarchical_link_partial_output_key(
            target,
            partial_record_count,
            partial_record_count + 100,
        ),
        final_output: false,
    };
    validate_source_pack_hierarchical_link_execution_page(
        &reduce_page,
        target,
        Some(partial_record_count),
    )
    .expect("compact reduce execution page should allow large paged input counts");

    let oversized_partial_groups = SourcePackHierarchicalLinkExecutionPage {
        input_group_page_count: 0,
        input_group_indices: (0..partial_record_count).collect(),
        input_group_output_keys: (0..partial_record_count)
            .map(|group_index| {
                source_pack_hierarchical_link_partial_output_key(
                    target,
                    group_index,
                    group_index + 100,
                )
            })
            .collect(),
        ..reduce_page.clone()
    };
    assert!(
        validate_source_pack_hierarchical_link_execution_page(
            &oversized_partial_groups,
            target,
            Some(partial_record_count),
        )
        .expect_err("oversized inline partial-link records should be rejected")
        .to_string()
        .contains("record cap")
    );

    let oversized_partial_keys = SourcePackHierarchicalLinkExecutionPage {
        input_group_count: 1,
        input_group_page_count: 0,
        input_group_indices: vec![0],
        input_group_output_keys: (0..partial_record_count)
            .map(|group_index| {
                source_pack_hierarchical_link_partial_output_key(
                    target,
                    group_index,
                    group_index + 100,
                )
            })
            .collect(),
        ..reduce_page
    };
    assert!(
        validate_source_pack_hierarchical_link_execution_page(
            &oversized_partial_keys,
            target,
            Some(partial_record_count),
        )
        .expect_err("oversized inline partial-link keys should be rejected")
        .to_string()
        .contains("record cap")
    );
}

#[test]
fn explicit_source_libraries_filesystem_artifact_build_entrypoint_uses_metadata_plan() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-library-filesystem-artifact-entrypoint-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let result = execute_explicit_source_libraries_filesystem_artifact_build(
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path],
                dependency_library_ids: vec![10],
            },
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            },
        ],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 8,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
        &mut executor,
    )
    .expect("execute filesystem artifact-store entrypoint");

    assert_eq!(result.linked_output_key, "linked-output/job-4/src-0-2");
    assert!(result.linked_output_path.exists());
    assert_eq!(
        std::fs::read(&result.linked_output_path).expect("read linked output"),
        b"linked:2:2"
    );
    assert!(result.build_manifest_path.exists());
    assert!(result.artifact_manifest_path.exists());
    assert!(result.build_state_path.exists());
    assert!(
        result
            .build_manifest_path
            .ends_with("source-pack-build.json")
    );
    assert!(
        result
            .artifact_manifest_path
            .ends_with("source-pack-artifacts.json")
    );
    assert!(result.build_state_path.ends_with("source-pack-state.json"));
    let stored_path_manifest = SourcePackFilesystemArtifactStore::new(&artifact_root)
        .load_path_build_manifest()
        .expect("load source-pack path build manifest");
    assert_eq!(
        stored_path_manifest.version,
        SOURCE_PACK_PATH_BUILD_MANIFEST_VERSION
    );
    assert_eq!(stored_path_manifest.source_file_count, 2);
    assert_eq!(stored_path_manifest.source_byte_count, 8);
    assert!(
        stored_path_manifest.source_files.is_empty(),
        "persisted path build manifest should leave source-file records in source-file pages"
    );
    assert!(
        stored_path_manifest.library_dependencies.is_empty(),
        "persisted path build manifest should leave library dependency edges in schedule pages"
    );
    assert_eq!(
        stored_path_manifest.limits,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 8,
        }
    );
    assert_eq!(
        stored_path_manifest.batch_limits,
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        }
    );
    assert_eq!(stored_path_manifest.artifacts.artifact_count, 5);
    assert_eq!(stored_path_manifest.artifacts.job_count, 5);
    assert_eq!(stored_path_manifest.artifacts.job_batch_count, 5);
    assert!(
        stored_path_manifest.artifacts.job_schedule.jobs.is_empty(),
        "persisted path build manifest should leave artifact job records in execution shards"
    );
    let stored_manifest = SourcePackFilesystemArtifactStore::new(&artifact_root)
        .load_build_artifact_manifest()
        .expect("load durable artifact manifest");
    assert_eq!(stored_manifest.job_count, 5);
    assert_eq!(stored_manifest.job_batch_count, 5);
    assert_eq!(stored_manifest.batch_dependency_count, 5);
    assert_eq!(stored_manifest.artifact_count, 5);
    assert_eq!(stored_manifest.job_artifact_count, 5);
    assert_eq!(stored_manifest.job_artifact_io_count, 5);
    assert_eq!(stored_manifest.artifact_use_count, 5);
    assert_eq!(stored_manifest.link_interface_batch_count, 2);
    assert_eq!(stored_manifest.link_object_batch_count, 2);
    assert!(
        stored_manifest.job_schedule.jobs.is_empty(),
        "persisted artifact manifest should leave job records in execution shards"
    );
    let stored_state = SourcePackFilesystemArtifactStore::new(&artifact_root)
        .load_build_state()
        .expect("load durable build state");
    assert_eq!(stored_state.version, SOURCE_PACK_BUILD_STATE_VERSION);
    assert_eq!(stored_state.completed_batch_count(), 5);
    assert_eq!(stored_state.claimed_batch_count, 0);
    assert_eq!(
        stored_state.linked_output_key.as_deref(),
        Some("linked-output/job-4/src-0-2")
    );
    assert_eq!(
        executor.events,
        vec![
            "frontend:10:1:0",
            "frontend:20:1:1",
            "codegen:10:0..1:1:0",
            "codegen:20:1..2:1:1",
            "begin-link:4",
            "link-interfaces:0:1",
            "link-interfaces:1:1",
            "link-objects:0:1",
            "link-objects:1:1",
            "finish-link:4:2:2",
        ]
    );
    std::fs::remove_dir_all(&root).expect("remove temp filesystem entrypoint dir");
}

#[test]
fn explicit_source_libraries_filesystem_artifact_build_separates_target_manifests() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-library-filesystem-target-artifact-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 8,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };
    let libraries = || {
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path.clone()],
                dependency_library_ids: vec![10],
            },
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path.clone()],
                dependency_library_ids: Vec::new(),
            },
        ]
    };

    let mut wasm_executor = RecordingSourcePackByteArtifactExecutor::default();
    let wasm = execute_explicit_source_libraries_filesystem_artifact_build_for_target(
        libraries(),
        &artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Wasm,
        &mut wasm_executor,
    )
    .expect("execute wasm target filesystem artifact build");
    let mut x86_executor = RecordingSourcePackByteArtifactExecutor::default();
    let x86 = execute_explicit_source_libraries_filesystem_artifact_build_for_target(
        libraries(),
        &artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::X86_64,
        &mut x86_executor,
    )
    .expect("execute x86 target filesystem artifact build");

    assert_eq!(wasm.linked_output_key, "wasm/linked-output/job-4/src-0-2");
    assert_eq!(x86.linked_output_key, "x86_64/linked-output/job-4/src-0-2");
    assert!(wasm.linked_output_path.exists());
    assert!(x86.linked_output_path.exists());
    assert_ne!(wasm.linked_output_path, x86.linked_output_path);
    assert!(
        wasm.build_manifest_path
            .ends_with("source-pack-build.wasm.json")
    );
    assert!(
        wasm.artifact_manifest_path
            .ends_with("source-pack-artifacts.wasm.json")
    );
    assert!(
        wasm.build_state_path
            .ends_with("source-pack-state.wasm.json")
    );
    assert!(
        x86.build_manifest_path
            .ends_with("source-pack-build.x86_64.json")
    );
    assert!(
        x86.artifact_manifest_path
            .ends_with("source-pack-artifacts.x86_64.json")
    );
    assert!(
        x86.build_state_path
            .ends_with("source-pack-state.x86_64.json")
    );

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let wasm_manifest = store
        .load_path_build_manifest_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load wasm path build manifest");
    let x86_manifest = store
        .load_path_build_manifest_for_target(SourcePackArtifactTarget::X86_64)
        .expect("load x86 path build manifest");
    assert_eq!(
        wasm_manifest.artifacts.target,
        SourcePackArtifactTarget::Wasm
    );
    assert_eq!(
        x86_manifest.artifacts.target,
        SourcePackArtifactTarget::X86_64
    );
    assert_eq!(
        store
            .load_build_state_for_target(SourcePackArtifactTarget::Wasm)
            .expect("load wasm build state")
            .linked_output_key
            .as_deref(),
        Some("wasm/linked-output/job-4/src-0-2")
    );
    assert_eq!(
        store
            .load_build_state_for_target(SourcePackArtifactTarget::X86_64)
            .expect("load x86 build state")
            .linked_output_key
            .as_deref(),
        Some("x86_64/linked-output/job-4/src-0-2")
    );
    std::fs::remove_dir_all(&root).expect("remove temp target artifact dir");
}

#[test]
fn source_pack_filesystem_artifact_manifest_build_executes_persisted_schedule() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-filesystem-artifact-manifest-build-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let first_path = source_root.join("first.lani");
    let second_path = source_root.join("second.lani");
    let third_path = source_root.join("third.lani");
    let fourth_path = source_root.join("fourth.lani");
    std::fs::write(&first_path, b"aaaa").expect("write first source");
    std::fs::write(&second_path, b"bbbb").expect("write second source");
    std::fs::write(&third_path, b"cccc").expect("write third source");
    std::fs::write(&fourth_path, b"dddd").expect("write fourth source");

    let manifest = load_explicit_source_libraries_path_manifest(vec![
        ExplicitSourceLibraryPaths {
            library_id: 7,
            paths: vec![first_path, second_path],
            dependency_library_ids: Vec::new(),
        },
        ExplicitSourceLibraryPaths {
            library_id: 8,
            paths: vec![third_path, fourth_path],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect("load path manifest");
    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 8,
    };
    let persisted_batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 2,
        max_source_bytes_per_batch: 8,
        max_source_files_per_batch: 2,
    };
    let ignored_batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 99,
        max_source_bytes_per_batch: 99,
        max_source_files_per_batch: 99,
    };
    let build_plan = manifest.build_plan(limits);
    let artifact_manifest = build_plan.retained_build_artifact_manifest(persisted_batch_limits);
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    store
        .store_build_artifact_manifest(&artifact_manifest)
        .expect("store artifact manifest");
    let path_build_manifest =
        source_pack_path_build_manifest(&manifest, limits, ignored_batch_limits, artifact_manifest);
    store
        .store_path_build_manifest(&path_build_manifest)
        .expect("store path build manifest");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let result = execute_source_pack_filesystem_artifact_manifest_build(
        artifact_root.clone(),
        &mut executor,
    )
    .expect("execute filesystem artifact manifest build");

    assert_eq!(result.linked_output_key, "linked-output/job-6/src-0-4");
    assert_eq!(
        std::fs::read(&result.linked_output_path).expect("read linked output"),
        b"linked:2:4"
    );
    assert!(
        result
            .build_manifest_path
            .ends_with("source-pack-build.json")
    );
    assert!(
        result
            .artifact_manifest_path
            .ends_with("source-pack-artifacts.json")
    );
    assert_eq!(
        executor.events,
        vec![
            "frontend:7:2:0",
            "frontend:8:2:0",
            "codegen:7:0..1:1:0",
            "codegen:7:1..2:1:0",
            "codegen:8:2..3:1:0",
            "codegen:8:3..4:1:0",
            "begin-link:6",
            "link-interfaces:0:1",
            "link-interfaces:1:1",
            "link-objects:0:2",
            "link-objects:1:2",
            "finish-link:6:2:4",
        ]
    );
    std::fs::remove_dir_all(&root).expect("remove temp filesystem manifest build dir");
}

#[test]
fn source_pack_filesystem_artifact_manifest_full_build_stops_at_batch_limit() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-filesystem-artifact-manifest-build-limit-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let source_paths = (0..SOURCE_PACK_ARTIFACT_MANIFEST_FULL_BUILD_DEFAULT_BATCH_LIMIT)
        .map(|source_index| {
            let path = source_root.join(format!("source-{source_index}.lani"));
            std::fs::write(&path, b"x").expect("write source");
            path
        })
        .collect::<Vec<_>>();
    let manifest = load_explicit_source_libraries_path_manifest(vec![ExplicitSourceLibraryPaths {
        library_id: 7,
        paths: source_paths,
        dependency_library_ids: Vec::new(),
    }])
    .expect("load path manifest");
    let limits = CodegenUnitLimits {
        max_source_bytes: 1,
        max_source_files: 1,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 1,
        max_source_files_per_batch: 1,
    };
    let build_plan = manifest.build_plan(limits);
    let artifact_manifest = build_plan.retained_build_artifact_manifest(batch_limits);
    assert!(
        artifact_manifest.job_batches.batch_count()
            > SOURCE_PACK_ARTIFACT_MANIFEST_FULL_BUILD_DEFAULT_BATCH_LIMIT
    );

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    store
        .store_build_artifact_manifest(&artifact_manifest)
        .expect("store artifact manifest");
    let path_build_manifest =
        source_pack_path_build_manifest(&manifest, limits, batch_limits, artifact_manifest);
    store
        .store_path_build_manifest(&path_build_manifest)
        .expect("store path build manifest");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let err = execute_source_pack_filesystem_artifact_manifest_build(&artifact_root, &mut executor)
        .expect_err("full manifest build should stop at the bounded batch limit");
    assert!(
        err.to_string()
            .contains("did not complete within 64 bounded batches"),
        "unexpected full-build limit error: {err}"
    );
    assert_eq!(
        executor.events.len(),
        SOURCE_PACK_ARTIFACT_MANIFEST_FULL_BUILD_DEFAULT_BATCH_LIMIT
    );
    let state = store
        .load_build_state()
        .expect("load resumable state after bounded full build");
    assert_eq!(
        state.completed_batch_count,
        SOURCE_PACK_ARTIFACT_MANIFEST_FULL_BUILD_DEFAULT_BATCH_LIMIT
    );
    assert_eq!(state.linked_output_key, None);

    std::fs::remove_dir_all(&root).expect("remove temp filesystem manifest build limit dir");
}

#[test]
fn source_pack_filesystem_artifact_manifest_batch_executes_persisted_batch() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-filesystem-artifact-manifest-batch-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let first_path = source_root.join("first.lani");
    let second_path = source_root.join("second.lani");
    let third_path = source_root.join("third.lani");
    let fourth_path = source_root.join("fourth.lani");
    std::fs::write(&first_path, b"aaaa").expect("write first source");
    std::fs::write(&second_path, b"bbbb").expect("write second source");
    std::fs::write(&third_path, b"cccc").expect("write third source");
    std::fs::write(&fourth_path, b"dddd").expect("write fourth source");

    let manifest = load_explicit_source_libraries_path_manifest(vec![
        ExplicitSourceLibraryPaths {
            library_id: 7,
            paths: vec![first_path, second_path],
            dependency_library_ids: Vec::new(),
        },
        ExplicitSourceLibraryPaths {
            library_id: 8,
            paths: vec![third_path, fourth_path],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect("load path manifest");
    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 8,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 2,
        max_source_bytes_per_batch: 8,
        max_source_files_per_batch: 2,
    };
    let build_plan = manifest.build_plan(limits);
    let artifact_manifest = build_plan.retained_build_artifact_manifest(batch_limits);
    let expected_batches = artifact_manifest
        .job_batches
        .batches
        .iter()
        .map(|batch| batch.job_indices.clone())
        .collect::<Vec<_>>();
    assert!(expected_batches.len() > 1);

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    store
        .store_build_artifact_manifest(&artifact_manifest)
        .expect("store artifact manifest");
    let path_build_manifest =
        source_pack_path_build_manifest(&manifest, limits, batch_limits, artifact_manifest);
    store
        .store_path_build_manifest(&path_build_manifest)
        .expect("store path build manifest");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let not_ready_err = execute_source_pack_filesystem_artifact_manifest_batch(
        artifact_root.clone(),
        2,
        &mut executor,
    )
    .expect_err("non-ready filesystem artifact manifest batch should not execute");
    assert!(
        not_ready_err.to_string().contains("is not ready"),
        "unexpected non-ready batch error: {not_ready_err}"
    );
    assert_eq!(executor.events, Vec::<String>::new());
    let mut linked_output_path = None;
    for (batch_index, expected_job_indices) in expected_batches.iter().enumerate() {
        let ready_batch_indices =
            source_pack_filesystem_artifact_manifest_ready_state_batches(artifact_root.clone())
                .expect("load ready filesystem artifact manifest batches from state");
        assert!(
            ready_batch_indices.contains(&batch_index),
            "batch {batch_index} should be ready from persisted state; ready: {ready_batch_indices:?}"
        );
        let result = execute_source_pack_filesystem_artifact_manifest_batch(
            artifact_root.clone(),
            batch_index,
            &mut executor,
        )
        .expect("execute filesystem artifact manifest batch");
        assert_eq!(result.batch_index, batch_index);
        assert_eq!(result.job_count, expected_job_indices.len());
        assert!(
            result
                .build_manifest_path
                .ends_with("source-pack-build.json")
        );
        assert!(
            result
                .artifact_manifest_path
                .ends_with("source-pack-artifacts.json")
        );
        assert!(result.build_state_path.ends_with("source-pack-state.json"));
        let state = source_pack_filesystem_artifact_manifest_build_state(artifact_root.clone())
            .expect("load filesystem artifact manifest build state");
        assert_eq!(state.completed_batch_count(), batch_index + 1);
        assert_eq!(state.claimed_batch_count, 0);
        if batch_index + 1 == expected_batches.len() {
            assert_eq!(
                result.linked_output_key.as_deref(),
                Some("linked-output/job-6/src-0-4")
            );
            assert_eq!(
                state.linked_output_key.as_deref(),
                Some("linked-output/job-6/src-0-4")
            );
            linked_output_path = result.linked_output_path;
        } else {
            assert_eq!(result.linked_output_key, None);
            assert_eq!(result.linked_output_path, None);
            assert_eq!(state.linked_output_key, None);
        }

        let event_count_after_batch = executor.events.len();
        let replay = execute_source_pack_filesystem_artifact_manifest_batch(
            artifact_root.clone(),
            batch_index,
            &mut executor,
        )
        .expect("replay completed filesystem artifact manifest batch");
        assert_eq!(replay.batch_index, batch_index);
        assert_eq!(replay.job_count, expected_job_indices.len());
        assert_eq!(executor.events.len(), event_count_after_batch);
    }

    assert_eq!(
        source_pack_filesystem_artifact_manifest_ready_state_batches(artifact_root.clone(),)
            .expect("load final ready filesystem artifact manifest batches from state"),
        Vec::<usize>::new()
    );
    let final_state = source_pack_filesystem_artifact_manifest_build_state(artifact_root.clone())
        .expect("load final filesystem artifact manifest build state");
    assert_eq!(final_state.completed_batch_count(), expected_batches.len());
    assert_eq!(final_state.claimed_batch_count, 0);
    let linked_output_path = linked_output_path.expect("linked output path from final batch");
    assert_eq!(
        std::fs::read(&linked_output_path).expect("read linked output"),
        b"linked:2:4"
    );
    assert_eq!(
        executor.events,
        vec![
            "frontend:7:2:0",
            "frontend:8:2:0",
            "codegen:7:0..1:1:0",
            "codegen:7:1..2:1:0",
            "codegen:8:2..3:1:0",
            "codegen:8:3..4:1:0",
            "begin-link:6",
            "link-interfaces:0:1",
            "link-interfaces:1:1",
            "link-objects:0:2",
            "link-objects:1:2",
            "finish-link:6:2:4",
        ]
    );
    std::fs::remove_dir_all(&root).expect("remove temp filesystem manifest batch dir");
}

#[test]
fn source_pack_filesystem_artifact_manifest_ready_state_batches_are_limited() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-filesystem-artifact-ready-state-limit-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");

    let libraries = (0..3)
        .map(|index| {
            let source_path = source_root.join(format!("lib-{index}.lani"));
            std::fs::write(&source_path, b"unit").expect("write source");
            ExplicitSourceLibraryPathDependencyStream {
                library_id: 10 + index,
                source_file_count: 1,
                paths: std::iter::once(source_path),
                dependency_library_count: 0,
                dependency_library_ids: Vec::<u32>::new().into_iter(),
            }
        })
        .collect::<Vec<_>>();

    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_for_target(
            libraries,
            &artifact_root,
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 1,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
            SourcePackArtifactTarget::Wasm,
        )
        .expect("prepare path+dependency stream filesystem artifact build");

    let limited = source_pack_filesystem_artifact_manifest_ready_state_batches_limited_for_target(
        &artifact_root,
        2,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("load limited ready state batches");
    assert_eq!(limited, vec![0, 1]);

    let default = source_pack_filesystem_artifact_manifest_ready_state_batches_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("load default-limited ready state batches");
    assert_eq!(default, vec![0, 1, 2]);

    std::fs::remove_dir_all(&root).expect("remove temp filesystem ready-state limit dir");
}

#[test]
fn source_pack_build_progress_summary_store_uses_compact_frontier_counts() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-progress-summary-compact-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let summary = SourcePackBuildProgressSummary {
        version: SOURCE_PACK_BUILD_PROGRESS_SUMMARY_VERSION,
        target,
        job_batch_count: 2,
        job_batch_shard_count: 2,
        completed_batch_count: 0,
        ready_batch_count: 1,
        first_ready_batch_index: Some(1),
        claimed_batch_count: 1,
        ready_claimed_batch_count: 0,
        earliest_claim_lease_expires_unix_nanos: None,
        linked_output_key: None,
    };

    store
        .store_build_progress_summary(&summary)
        .expect("store compact progress summary");
    let loaded = store
        .load_build_progress_summary_for_target(target)
        .expect("load compact progress summary");
    assert_eq!(loaded.ready_batch_count, 1);
    assert_eq!(loaded.claimed_batch_count, 1);

    let snapshot = source_pack_filesystem_artifact_manifest_progress_snapshot_for_target_at(
        &root,
        0,
        target,
        Some(0),
    )
    .expect("build compact progress snapshot");
    assert_eq!(snapshot.ready_batch_count, 1);
    assert_eq!(snapshot.claimed_batch_count, 1);
    assert_eq!(snapshot.ready_batch_indices, Vec::<usize>::new());

    std::fs::remove_dir_all(&root).expect("remove temp progress summary compact dir");
}

#[test]
fn source_pack_build_progress_shards_reject_unbounded_batch_records() {
    let target = SourcePackArtifactTarget::Wasm;
    let capped_batch_indices = (0..DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES).collect::<Vec<_>>();
    let capped_shard = SourcePackBuildProgressShard {
        version: SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION,
        target,
        shard_index: 0,
        batch_indices: capped_batch_indices,
        completed_batch_indices: vec![0],
        ready_batch_indices: vec![1],
        claimed_batches: vec![SourcePackBuildBatchClaim {
            batch_index: 2,
            worker_id: "worker-a".to_string(),
            lease_expires_unix_nanos: Some(10),
        }],
        linked_output_key: None,
    };
    validate_source_pack_build_progress_shard(&capped_shard)
        .expect("progress shard at record cap should validate");

    let oversized_indices = (0..=DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES).collect::<Vec<_>>();
    let mut oversized_batches = capped_shard.clone();
    oversized_batches.batch_indices = oversized_indices.clone();
    let err = validate_source_pack_build_progress_shard(&oversized_batches)
        .expect_err("oversized progress shard batches should be rejected");
    assert!(
        err.to_string().contains("record cap"),
        "unexpected oversized batch error: {err}"
    );

    let mut oversized_completed = capped_shard.clone();
    oversized_completed.completed_batch_indices = oversized_indices.clone();
    assert!(
        validate_source_pack_build_progress_shard(&oversized_completed)
            .expect_err("oversized completed progress shard batches should be rejected")
            .to_string()
            .contains("record cap")
    );

    let mut oversized_ready = capped_shard.clone();
    oversized_ready.ready_batch_indices = oversized_indices.clone();
    assert!(
        validate_source_pack_build_progress_shard(&oversized_ready)
            .expect_err("oversized ready progress shard batches should be rejected")
            .to_string()
            .contains("record cap")
    );

    let mut oversized_claims = capped_shard.clone();
    oversized_claims.claimed_batches = oversized_indices
        .iter()
        .map(|batch_index| SourcePackBuildBatchClaim {
            batch_index: *batch_index,
            worker_id: format!("worker-{batch_index}"),
            lease_expires_unix_nanos: Some(10),
        })
        .collect();
    assert!(
        validate_source_pack_build_progress_shard(&oversized_claims)
            .expect_err("oversized claimed progress shard batches should be rejected")
            .to_string()
            .contains("record cap")
    );

    let oversized_summary = SourcePackBuildProgressShardSummary {
        version: SOURCE_PACK_BUILD_PROGRESS_SHARD_SUMMARY_VERSION,
        target,
        shard_index: 0,
        batch_count: DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES + 1,
        completed_batch_count: 0,
        ready_batch_count: 0,
        first_ready_batch_index: None,
        claimed_batch_count: 0,
        ready_claimed_batch_count: 0,
        earliest_claim_lease_expires_unix_nanos: None,
    };
    assert!(
        validate_source_pack_build_progress_shard_summary(&oversized_summary)
            .expect_err("oversized progress shard summary should be rejected")
            .to_string()
            .contains("record cap")
    );
}

#[test]
fn source_pack_build_progress_ready_query_scans_job_shards_not_batch_gaps() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-progress-shard-ready-query-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let limits = SourcePackBuildShardLimits::default();
    let first_shard = SourcePackBuildArtifactShard {
        version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
        target,
        limits,
        shard_index: 0,
        kind: SourcePackBuildArtifactShardKind::JobBatches,
        batch_indices: vec![0, 1, 2],
        job_indices: vec![0, 1, 2],
        input_artifact_indices: Vec::new(),
        input_artifact_ranges: Vec::new(),
        output_artifact_indices: Vec::new(),
        source_bytes: 3,
        source_file_count: 3,
        source_lines: 3,
        oversized: false,
    };
    store_source_pack_build_batch_shard_locators(&store, &first_shard)
        .expect("store first ready batch locator only");
    store
        .write_build_progress_shard_file(&SourcePackBuildProgressShard {
            version: SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION,
            target,
            shard_index: 0,
            batch_indices: vec![0, 1, 2],
            completed_batch_indices: Vec::new(),
            ready_batch_indices: vec![0],
            claimed_batches: vec![SourcePackBuildBatchClaim {
                batch_index: 0,
                worker_id: "worker-a".to_string(),
                lease_expires_unix_nanos: Some(20),
            }],
            linked_output_key: None,
        })
        .expect("store first progress shard");
    store
        .write_build_progress_shard_file(&SourcePackBuildProgressShard {
            version: SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION,
            target,
            shard_index: 1,
            batch_indices: vec![100, 101, 102],
            completed_batch_indices: Vec::new(),
            ready_batch_indices: vec![100],
            claimed_batches: Vec::new(),
            linked_output_key: None,
        })
        .expect("store sparse second progress shard");
    let summary = SourcePackBuildProgressSummary {
        version: SOURCE_PACK_BUILD_PROGRESS_SUMMARY_VERSION,
        target,
        job_batch_count: 103,
        job_batch_shard_count: 2,
        completed_batch_count: 0,
        ready_batch_count: 2,
        first_ready_batch_index: Some(0),
        claimed_batch_count: 1,
        ready_claimed_batch_count: 1,
        earliest_claim_lease_expires_unix_nanos: Some(20),
        linked_output_key: None,
    };
    store
        .store_build_progress_summary(&summary)
        .expect("store sparse progress summary");

    let ready = source_pack_build_progress_ready_unclaimed_batch_indices_from_summary_limited(
        &store,
        target,
        &summary,
        Some(10),
        Some(1),
    )
    .expect("load ready batch through shard scan");
    assert_eq!(ready, vec![100]);
    std::fs::remove_dir_all(&root).expect("remove temp progress shard ready query dir");
}

#[test]
fn source_pack_build_progress_ready_query_skips_claimed_shards_by_summary() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-progress-shard-summary-skip-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let limits = SourcePackBuildShardLimits::default();
    let first_shard = SourcePackBuildArtifactShard {
        version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
        target,
        limits,
        shard_index: 0,
        kind: SourcePackBuildArtifactShardKind::JobBatches,
        batch_indices: vec![0, 1],
        job_indices: vec![0, 1],
        input_artifact_indices: Vec::new(),
        input_artifact_ranges: Vec::new(),
        output_artifact_indices: Vec::new(),
        source_bytes: 2,
        source_file_count: 2,
        source_lines: 2,
        oversized: false,
    };
    store_source_pack_build_batch_shard_locators(&store, &first_shard)
        .expect("store first ready batch locator");
    store
        .write_build_progress_shard_file(&SourcePackBuildProgressShard {
            version: SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION,
            target,
            shard_index: 0,
            batch_indices: vec![0, 1],
            completed_batch_indices: Vec::new(),
            ready_batch_indices: vec![0, 1],
            claimed_batches: vec![
                SourcePackBuildBatchClaim {
                    batch_index: 0,
                    worker_id: "worker-a".to_string(),
                    lease_expires_unix_nanos: Some(100),
                },
                SourcePackBuildBatchClaim {
                    batch_index: 1,
                    worker_id: "worker-b".to_string(),
                    lease_expires_unix_nanos: Some(100),
                },
            ],
            linked_output_key: None,
        })
        .expect("store fully claimed progress shard");
    store
        .write_build_progress_shard_file(&SourcePackBuildProgressShard {
            version: SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION,
            target,
            shard_index: 1,
            batch_indices: vec![100, 101],
            completed_batch_indices: Vec::new(),
            ready_batch_indices: vec![100],
            claimed_batches: Vec::new(),
            linked_output_key: None,
        })
        .expect("store unclaimed sparse progress shard");
    assert!(
        store
            .build_progress_shard_summary_path_for_target(target, 0)
            .is_file(),
        "progress shard store should write a compact summary sidecar"
    );
    std::fs::write(
        store.build_progress_shard_path_for_target(target, 0),
        b"not json",
    )
    .expect("corrupt fully claimed progress shard body");
    let summary = SourcePackBuildProgressSummary {
        version: SOURCE_PACK_BUILD_PROGRESS_SUMMARY_VERSION,
        target,
        job_batch_count: 102,
        job_batch_shard_count: 2,
        completed_batch_count: 0,
        ready_batch_count: 3,
        first_ready_batch_index: Some(0),
        claimed_batch_count: 2,
        ready_claimed_batch_count: 2,
        earliest_claim_lease_expires_unix_nanos: Some(100),
        linked_output_key: None,
    };

    let ready = source_pack_build_progress_ready_unclaimed_batch_indices_from_summary_limited(
        &store,
        target,
        &summary,
        Some(10),
        Some(1),
    )
    .expect("ready scan should use summary sidecars before loading progress shard bodies");

    assert_eq!(ready, vec![100]);
    std::fs::remove_dir_all(&root).expect("remove progress shard summary skip test dir");
}

#[test]
fn source_pack_build_progress_ready_query_skips_fully_claimed_frontier_by_summary() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-progress-summary-fully-claimed-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create fully claimed progress summary test dir");
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let summary = SourcePackBuildProgressSummary {
        version: SOURCE_PACK_BUILD_PROGRESS_SUMMARY_VERSION,
        target,
        job_batch_count: 128,
        job_batch_shard_count: 4,
        completed_batch_count: 0,
        ready_batch_count: 2,
        first_ready_batch_index: Some(64),
        claimed_batch_count: 2,
        ready_claimed_batch_count: 2,
        earliest_claim_lease_expires_unix_nanos: Some(100),
        linked_output_key: None,
    };

    let ready = source_pack_build_progress_ready_unclaimed_batch_indices_from_summary_limited(
        &store,
        target,
        &summary,
        Some(10),
        Some(1),
    )
    .expect("fully claimed frontier should not read shard locators");
    let first = source_pack_build_progress_first_ready_unclaimed_batch_index_from_summary(
        &store,
        target,
        &summary,
        Some(10),
    )
    .expect("fully claimed first-ready query should not read shard locators");

    assert!(ready.is_empty());
    assert_eq!(first, None);
    std::fs::remove_dir_all(&root).expect("remove fully claimed progress summary test dir");
}

#[test]
fn source_pack_build_progress_ready_query_skips_empty_directory_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-progress-directory-skip-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let limits = SourcePackBuildShardLimits::default();
    let first_shard = SourcePackBuildArtifactShard {
        version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
        target,
        limits,
        shard_index: 0,
        kind: SourcePackBuildArtifactShardKind::JobBatches,
        batch_indices: vec![0],
        job_indices: vec![0],
        input_artifact_indices: Vec::new(),
        input_artifact_ranges: Vec::new(),
        output_artifact_indices: Vec::new(),
        source_bytes: 1,
        source_file_count: 1,
        source_lines: 1,
        oversized: false,
    };
    store_source_pack_build_batch_shard_locators(&store, &first_shard)
        .expect("store first ready batch locator");
    store
        .write_build_progress_shard_file(&SourcePackBuildProgressShard {
            version: SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION,
            target,
            shard_index: 0,
            batch_indices: vec![0],
            completed_batch_indices: Vec::new(),
            ready_batch_indices: vec![0],
            claimed_batches: vec![SourcePackBuildBatchClaim {
                batch_index: 0,
                worker_id: "worker-a".to_string(),
                lease_expires_unix_nanos: Some(100),
            }],
            linked_output_key: None,
        })
        .expect("store claimed first progress shard");
    for shard_index in 1..SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE {
        store
            .store_build_progress_shard_summary_for_target(
                target,
                &SourcePackBuildProgressShardSummary {
                    version: SOURCE_PACK_BUILD_PROGRESS_SHARD_SUMMARY_VERSION,
                    target,
                    shard_index,
                    batch_count: 1,
                    completed_batch_count: 0,
                    ready_batch_count: 0,
                    first_ready_batch_index: None,
                    claimed_batch_count: 0,
                    ready_claimed_batch_count: 0,
                    earliest_claim_lease_expires_unix_nanos: None,
                },
            )
            .expect("store empty first-directory shard summary");
    }
    let final_shard_index = SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE * 2;
    store
        .write_build_progress_shard_file(&SourcePackBuildProgressShard {
            version: SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION,
            target,
            shard_index: final_shard_index,
            batch_indices: vec![final_shard_index],
            completed_batch_indices: Vec::new(),
            ready_batch_indices: vec![final_shard_index],
            claimed_batches: Vec::new(),
            linked_output_key: None,
        })
        .expect("store unclaimed final progress shard");
    std::fs::write(
        store.build_progress_shard_summary_path_for_target(
            target,
            SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE,
        ),
        b"not json",
    )
    .expect("corrupt empty middle-directory shard summary");
    let summary = SourcePackBuildProgressSummary {
        version: SOURCE_PACK_BUILD_PROGRESS_SUMMARY_VERSION,
        target,
        job_batch_count: final_shard_index + 1,
        job_batch_shard_count: final_shard_index + 1,
        completed_batch_count: 0,
        ready_batch_count: 2,
        first_ready_batch_index: Some(0),
        claimed_batch_count: 1,
        ready_claimed_batch_count: 1,
        earliest_claim_lease_expires_unix_nanos: Some(100),
        linked_output_key: None,
    };
    for directory_page in [
        SourcePackBuildProgressDirectoryPage {
            version: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_PAGE_VERSION,
            target,
            directory_page_index: 0,
            first_shard_index: 0,
            shard_count: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE,
            ready_shard_count: 1,
            first_ready_shard_index: Some(0),
            ready_claimed_shard_count: 1,
            fully_claimed_ready_shard_count: 1,
            earliest_claim_lease_expires_unix_nanos: Some(100),
        },
        SourcePackBuildProgressDirectoryPage {
            version: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_PAGE_VERSION,
            target,
            directory_page_index: 1,
            first_shard_index: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE,
            shard_count: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE,
            ready_shard_count: 0,
            first_ready_shard_index: None,
            ready_claimed_shard_count: 0,
            fully_claimed_ready_shard_count: 0,
            earliest_claim_lease_expires_unix_nanos: None,
        },
        SourcePackBuildProgressDirectoryPage {
            version: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_PAGE_VERSION,
            target,
            directory_page_index: 2,
            first_shard_index: final_shard_index,
            shard_count: 1,
            ready_shard_count: 1,
            first_ready_shard_index: Some(final_shard_index),
            ready_claimed_shard_count: 0,
            fully_claimed_ready_shard_count: 0,
            earliest_claim_lease_expires_unix_nanos: None,
        },
    ] {
        store
            .store_build_progress_directory_page_for_target(target, &directory_page, &summary)
            .expect("store progress directory page");
    }
    std::fs::write(
        store.build_progress_shard_summary_path_for_target(target, 0),
        b"not json",
    )
    .expect("corrupt fully claimed progress shard summary");

    let ready = source_pack_build_progress_ready_unclaimed_batch_indices_from_summary_limited(
        &store,
        target,
        &summary,
        Some(10),
        Some(1),
    )
    .expect(
        "ready scan should skip claimed and empty directory pages before reading shard summaries",
    );

    assert_eq!(ready, vec![final_shard_index]);
    std::fs::remove_dir_all(&root).expect("remove progress directory skip test dir");
}

#[test]
fn source_pack_build_progress_ready_query_skips_claimed_directory_index_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-progress-directory-index-skip-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let limits = SourcePackBuildShardLimits::default();
    let first_shard = SourcePackBuildArtifactShard {
        version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
        target,
        limits,
        shard_index: 0,
        kind: SourcePackBuildArtifactShardKind::JobBatches,
        batch_indices: vec![0],
        job_indices: vec![0],
        input_artifact_indices: Vec::new(),
        input_artifact_ranges: Vec::new(),
        output_artifact_indices: Vec::new(),
        source_bytes: 1,
        source_file_count: 1,
        source_lines: 1,
        oversized: false,
    };
    store_source_pack_build_batch_shard_locators(&store, &first_shard)
        .expect("store first ready batch locator");
    let final_directory_page_index = SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE;
    let final_shard_index =
        final_directory_page_index * SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE;
    store
        .write_build_progress_shard_file(&SourcePackBuildProgressShard {
            version: SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION,
            target,
            shard_index: final_shard_index,
            batch_indices: vec![final_shard_index],
            completed_batch_indices: Vec::new(),
            ready_batch_indices: vec![final_shard_index],
            claimed_batches: Vec::new(),
            linked_output_key: None,
        })
        .expect("store unclaimed final progress shard");
    let summary = SourcePackBuildProgressSummary {
        version: SOURCE_PACK_BUILD_PROGRESS_SUMMARY_VERSION,
        target,
        job_batch_count: final_shard_index + 1,
        job_batch_shard_count: final_shard_index + 1,
        completed_batch_count: 0,
        ready_batch_count: 2,
        first_ready_batch_index: Some(0),
        claimed_batch_count: 1,
        ready_claimed_batch_count: 1,
        earliest_claim_lease_expires_unix_nanos: Some(100),
        linked_output_key: None,
    };
    store
        .store_build_progress_directory_index_page_for_target(
            target,
            &SourcePackBuildProgressDirectoryIndexPage {
                version: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION,
                target,
                directory_index_page_index: 0,
                first_directory_page_index: 0,
                directory_page_count: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE,
                ready_directory_page_count: 1,
                first_ready_directory_page_index: Some(0),
                ready_claimed_directory_page_count: 1,
                fully_claimed_ready_directory_page_count: 1,
                earliest_claim_lease_expires_unix_nanos: Some(100),
            },
            &summary,
        )
        .expect("store fully claimed directory-index page");
    store
        .store_build_progress_directory_index_page_for_target(
            target,
            &SourcePackBuildProgressDirectoryIndexPage {
                version: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION,
                target,
                directory_index_page_index: 1,
                first_directory_page_index: final_directory_page_index,
                directory_page_count: 1,
                ready_directory_page_count: 1,
                first_ready_directory_page_index: Some(final_directory_page_index),
                ready_claimed_directory_page_count: 0,
                fully_claimed_ready_directory_page_count: 0,
                earliest_claim_lease_expires_unix_nanos: None,
            },
            &summary,
        )
        .expect("store final directory-index page");
    store
        .store_build_progress_directory_page_for_target(
            target,
            &SourcePackBuildProgressDirectoryPage {
                version: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_PAGE_VERSION,
                target,
                directory_page_index: final_directory_page_index,
                first_shard_index: final_shard_index,
                shard_count: 1,
                ready_shard_count: 1,
                first_ready_shard_index: Some(final_shard_index),
                ready_claimed_shard_count: 0,
                fully_claimed_ready_shard_count: 0,
                earliest_claim_lease_expires_unix_nanos: None,
            },
            &summary,
        )
        .expect("store final progress directory page");
    std::fs::write(
        store.build_progress_directory_page_path_for_target(target, 0),
        b"not json",
    )
    .expect("corrupt claimed directory page that directory-index skip should avoid");

    let ready = source_pack_build_progress_ready_unclaimed_batch_indices_from_summary_limited(
        &store,
        target,
        &summary,
        Some(10),
        Some(1),
    )
    .expect("ready scan should skip fully claimed directory pages through directory-index records");

    assert_eq!(ready, vec![final_shard_index]);
    std::fs::remove_dir_all(&root).expect("remove progress directory-index skip test dir");
}

#[test]
fn source_pack_build_progress_lease_recompute_uses_directory_pages() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-progress-lease-directory-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    store
        .write_build_progress_shard_file(&SourcePackBuildProgressShard {
            version: SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION,
            target,
            shard_index: 0,
            batch_indices: vec![0],
            completed_batch_indices: Vec::new(),
            ready_batch_indices: vec![0],
            claimed_batches: vec![SourcePackBuildBatchClaim {
                batch_index: 0,
                worker_id: "worker-a".to_string(),
                lease_expires_unix_nanos: Some(10),
            }],
            linked_output_key: None,
        })
        .expect("store earliest claimed progress shard");
    for shard_index in 1..SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE {
        store
            .store_build_progress_shard_summary_for_target(
                target,
                &SourcePackBuildProgressShardSummary {
                    version: SOURCE_PACK_BUILD_PROGRESS_SHARD_SUMMARY_VERSION,
                    target,
                    shard_index,
                    batch_count: 1,
                    completed_batch_count: 0,
                    ready_batch_count: 0,
                    first_ready_batch_index: None,
                    claimed_batch_count: 0,
                    ready_claimed_batch_count: 0,
                    earliest_claim_lease_expires_unix_nanos: None,
                },
            )
            .expect("store empty changed-directory shard summary");
    }
    let final_shard_index = SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE * 2;
    store
        .write_build_progress_shard_file(&SourcePackBuildProgressShard {
            version: SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION,
            target,
            shard_index: final_shard_index,
            batch_indices: vec![final_shard_index],
            completed_batch_indices: Vec::new(),
            ready_batch_indices: vec![final_shard_index],
            claimed_batches: vec![SourcePackBuildBatchClaim {
                batch_index: final_shard_index,
                worker_id: "worker-b".to_string(),
                lease_expires_unix_nanos: Some(50),
            }],
            linked_output_key: None,
        })
        .expect("store later claimed progress shard");
    std::fs::write(
        store.build_progress_shard_summary_path_for_target(
            target,
            SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE,
        ),
        b"not json",
    )
    .expect("corrupt empty middle-directory shard summary");
    let summary = SourcePackBuildProgressSummary {
        version: SOURCE_PACK_BUILD_PROGRESS_SUMMARY_VERSION,
        target,
        job_batch_count: final_shard_index + 1,
        job_batch_shard_count: final_shard_index + 1,
        completed_batch_count: 0,
        ready_batch_count: 2,
        first_ready_batch_index: Some(0),
        claimed_batch_count: 2,
        ready_claimed_batch_count: 2,
        earliest_claim_lease_expires_unix_nanos: Some(10),
        linked_output_key: None,
    };
    store
        .store_build_progress_summary(&summary)
        .expect("store progress summary before lease recompute");
    for directory_page in [
        SourcePackBuildProgressDirectoryPage {
            version: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_PAGE_VERSION,
            target,
            directory_page_index: 0,
            first_shard_index: 0,
            shard_count: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE,
            ready_shard_count: 1,
            first_ready_shard_index: Some(0),
            ready_claimed_shard_count: 1,
            fully_claimed_ready_shard_count: 1,
            earliest_claim_lease_expires_unix_nanos: Some(10),
        },
        SourcePackBuildProgressDirectoryPage {
            version: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_PAGE_VERSION,
            target,
            directory_page_index: 1,
            first_shard_index: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE,
            shard_count: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE,
            ready_shard_count: 0,
            first_ready_shard_index: None,
            ready_claimed_shard_count: 0,
            fully_claimed_ready_shard_count: 0,
            earliest_claim_lease_expires_unix_nanos: None,
        },
        SourcePackBuildProgressDirectoryPage {
            version: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_PAGE_VERSION,
            target,
            directory_page_index: 2,
            first_shard_index: final_shard_index,
            shard_count: 1,
            ready_shard_count: 1,
            first_ready_shard_index: Some(final_shard_index),
            ready_claimed_shard_count: 1,
            fully_claimed_ready_shard_count: 1,
            earliest_claim_lease_expires_unix_nanos: Some(50),
        },
    ] {
        store
            .store_build_progress_directory_page_for_target(target, &directory_page, &summary)
            .expect("store progress directory page");
    }

    store
        .store_build_progress_shard(&SourcePackBuildProgressShard {
            version: SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION,
            target,
            shard_index: 0,
            batch_indices: vec![0],
            completed_batch_indices: Vec::new(),
            ready_batch_indices: vec![0],
            claimed_batches: vec![SourcePackBuildBatchClaim {
                batch_index: 0,
                worker_id: "worker-a".to_string(),
                lease_expires_unix_nanos: Some(100),
            }],
            linked_output_key: None,
        })
        .expect("update old earliest lease through directory-backed recompute");
    let recomputed = store
        .load_build_progress_summary_for_target(target)
        .expect("load recomputed progress summary");

    assert_eq!(recomputed.earliest_claim_lease_expires_unix_nanos, Some(50));
    std::fs::remove_dir_all(&root).expect("remove progress lease directory test dir");
}

#[test]
fn source_pack_build_state_store_rejects_unproven_compact_counts() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-build-state-locator-replay-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let stdlib_path = source_root.join("stdlib.lani");
    let user_path = source_root.join("user.lani");
    std::fs::write(&stdlib_path, b"core").expect("write stdlib source");
    std::fs::write(&user_path, b"user").expect("write user source");
    let target = SourcePackArtifactTarget::Wasm;
    let prepared = prepare_explicit_source_pack_paths_filesystem_artifact_build_for_target(
        &[stdlib_path],
        &[user_path],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 1,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
        target,
    )
    .expect("prepare filesystem artifact build");
    assert!(prepared.batch_count > 1);
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    std::fs::write(
        store.artifact_shard_index_path_for_target(target),
        b"not json",
    )
    .expect("corrupt global shard index that locator replay must not read");
    let state = SourcePackBuildState {
        version: SOURCE_PACK_BUILD_STATE_VERSION,
        completed_batch_count: 1,
        claimed_batch_count: 1,
        linked_output_key: None,
    };

    let err = store
        .store_build_state_for_target(target, &state)
        .expect_err("compact build state counts must match persisted progress");
    assert!(
        err.to_string()
            .contains("persisted progress summary records 0"),
        "unexpected compact build state error: {err}"
    );

    let summary = store
        .load_build_progress_summary_for_target(target)
        .expect("load progress summary after rejected compact state");
    assert_eq!(summary.completed_batch_count, 0);
    assert_eq!(summary.claimed_batch_count, 0);

    store
        .store_build_state_for_target(target, &SourcePackBuildState::new())
        .expect("store matching compact build state marker");
    let marker = serde_json::from_slice::<SourcePackBuildState>(
        &std::fs::read(store.build_state_path_for_target(target))
            .expect("read compact build state marker"),
    )
    .expect("parse compact build state marker");
    assert_eq!(marker.completed_batch_count(), 0);
    assert_eq!(marker.claimed_batch_count, 0);
    std::fs::remove_dir_all(&root).expect("remove build state locator replay test dir");
}

#[test]
fn source_pack_filesystem_artifact_manifest_ready_state_rejects_missing_completed_artifact() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-filesystem-artifact-missing-completed-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let source_path = source_root.join("source.lani");
    std::fs::write(&source_path, b"core").expect("write source");

    let manifest = load_explicit_source_libraries_path_manifest(vec![ExplicitSourceLibraryPaths {
        library_id: 10,
        paths: vec![source_path],
        dependency_library_ids: Vec::new(),
    }])
    .expect("load path manifest");
    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 8,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };
    let build_plan = manifest.build_plan(limits);
    let artifact_manifest = build_plan.retained_build_artifact_manifest(batch_limits);
    let interface_key = artifact_manifest.job_artifacts.jobs[0].outputs[0]
        .key
        .clone();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    store
        .store_build_artifact_manifest(&artifact_manifest)
        .expect("store artifact manifest");
    let path_build_manifest =
        source_pack_path_build_manifest(&manifest, limits, batch_limits, artifact_manifest);
    store
        .store_path_build_manifest(&path_build_manifest)
        .expect("store path build manifest");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let first = execute_source_pack_filesystem_artifact_manifest_batch(
        artifact_root.clone(),
        0,
        &mut executor,
    )
    .expect("execute first persisted batch");
    assert_eq!(first.batch_index, 0);
    let interface_path = store.path_for_key(&interface_key).expect("interface path");
    assert!(interface_path.exists());
    std::fs::remove_file(&interface_path).expect("remove completed interface artifact");

    let err = source_pack_filesystem_artifact_manifest_ready_state_batches(artifact_root.clone())
        .expect_err("missing completed artifact should reject ready-state query");
    std::fs::remove_dir_all(&root).expect("remove temp missing-completed-artifact dir");

    assert!(
        err.to_string()
            .contains("marks batch 0 complete but output artifact"),
        "unexpected missing completed artifact error: {err}"
    );
}

#[test]
fn source_pack_filesystem_artifact_manifest_ready_runner_resumes_from_state() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-filesystem-artifact-manifest-ready-runner-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let manifest = load_explicit_source_libraries_path_manifest(vec![
        ExplicitSourceLibraryPaths {
            library_id: 20,
            paths: vec![app_path],
            dependency_library_ids: vec![10],
        },
        ExplicitSourceLibraryPaths {
            library_id: 10,
            paths: vec![core_path],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect("load path manifest");
    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 8,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };
    let build_plan = manifest.build_plan(limits);
    let artifact_manifest = build_plan.retained_build_artifact_manifest(batch_limits);
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    store
        .store_build_artifact_manifest(&artifact_manifest)
        .expect("store artifact manifest");
    let path_build_manifest =
        source_pack_path_build_manifest(&manifest, limits, batch_limits, artifact_manifest);
    store
        .store_path_build_manifest(&path_build_manifest)
        .expect("store path build manifest");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let first = execute_source_pack_filesystem_artifact_manifest_ready_batches(
        artifact_root.clone(),
        1,
        &mut executor,
    )
    .expect("execute first ready batch");
    assert_eq!(first.executed_batch_count, 1);
    assert_eq!(first.completed_batch_count, 1);
    assert_eq!(first.ready_batch_count, 2);
    assert_eq!(first.linked_output_key, None);
    assert!(!first.complete);
    assert!(first.build_state_path.ends_with("source-pack-state.json"));

    let second = execute_source_pack_filesystem_artifact_manifest_ready_batches(
        artifact_root.clone(),
        2,
        &mut executor,
    )
    .expect("execute next two ready batches");
    assert_eq!(second.executed_batch_count, 2);
    assert_eq!(second.completed_batch_count, 3);
    assert_eq!(second.ready_batch_count, 1);
    assert!(!second.complete);

    let third = execute_source_pack_filesystem_artifact_manifest_ready_batches(
        artifact_root.clone(),
        10,
        &mut executor,
    )
    .expect("execute resumed codegen batch");
    assert_eq!(third.executed_batch_count, 1);
    assert_eq!(third.completed_batch_count, 4);
    assert_eq!(third.ready_batch_count, 1);
    assert!(!third.complete);

    let fourth = execute_source_pack_filesystem_artifact_manifest_ready_batches(
        artifact_root.clone(),
        10,
        &mut executor,
    )
    .expect("execute final link batch");
    assert_eq!(fourth.executed_batch_count, 1);
    assert_eq!(fourth.completed_batch_count, 5);
    assert_eq!(fourth.ready_batch_count, 0);
    assert_eq!(
        fourth.linked_output_key.as_deref(),
        Some("linked-output/job-4/src-0-2")
    );
    assert!(fourth.complete);
    assert_eq!(
        std::fs::read(
            fourth
                .linked_output_path
                .as_ref()
                .expect("linked output path")
        )
        .expect("read linked output"),
        b"linked:2:2"
    );

    let event_count_after_complete = executor.events.len();
    let replay = execute_source_pack_filesystem_artifact_manifest_ready_batches(
        artifact_root.clone(),
        10,
        &mut executor,
    )
    .expect("resume completed build");
    assert_eq!(replay.executed_batch_count, 0);
    assert!(replay.complete);
    assert_eq!(executor.events.len(), event_count_after_complete);
    assert_eq!(
        executor.events,
        vec![
            "frontend:10:1:0",
            "frontend:20:1:1",
            "codegen:10:0..1:1:0",
            "codegen:20:1..2:1:1",
            "begin-link:4",
            "link-interfaces:0:1",
            "link-interfaces:1:1",
            "link-objects:0:1",
            "link-objects:1:1",
            "finish-link:4:2:2",
        ]
    );
    std::fs::remove_dir_all(&root).expect("remove temp filesystem ready-runner dir");
}

#[test]
fn source_pack_filesystem_artifact_manifest_claims_ready_batches_for_workers() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-filesystem-artifact-claim-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let manifest = load_explicit_source_libraries_path_manifest(vec![
        ExplicitSourceLibraryPaths {
            library_id: 20,
            paths: vec![app_path],
            dependency_library_ids: vec![10],
        },
        ExplicitSourceLibraryPaths {
            library_id: 10,
            paths: vec![core_path],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect("load path manifest");
    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 8,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };
    let build_plan = manifest.build_plan(limits);
    let artifact_manifest = build_plan.retained_build_artifact_manifest(batch_limits);
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    store
        .store_build_artifact_manifest(&artifact_manifest)
        .expect("store artifact manifest");
    let path_build_manifest =
        source_pack_path_build_manifest(&manifest, limits, batch_limits, artifact_manifest);
    store
        .store_path_build_manifest(&path_build_manifest)
        .expect("store path build manifest");

    let first_claim = source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-a",
        None,
        Some(0),
    )
    .expect("claim first ready batch");
    assert_eq!(first_claim.claimed_batch_index, Some(0));
    assert_eq!(first_claim.completed_batch_count, 0);
    assert_eq!(first_claim.claimed_batch_count, 1);
    assert!(
        first_claim
            .build_state_path
            .ends_with("source-pack-state.json")
    );

    let blocked_claim = source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-b",
        None,
        Some(0),
    )
    .expect("second worker sees no unclaimed ready batch");
    assert_eq!(blocked_claim.claimed_batch_index, None);
    assert_eq!(blocked_claim.claimed_batch_count, 1);

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let unclaimed_err = execute_source_pack_filesystem_artifact_manifest_batch_for_target(
        artifact_root.clone(),
        0,
        SourcePackArtifactTarget::Generic,
        &mut executor,
    )
    .expect_err("unclaimed execution should reject claimed batch");
    assert!(
        unclaimed_err
            .to_string()
            .contains("claimed by another worker"),
        "unexpected claimed-batch error: {unclaimed_err}"
    );
    let wrong_worker_err =
        execute_source_pack_filesystem_artifact_manifest_claimed_batch_for_target_at(
            artifact_root.clone(),
            0,
            SourcePackArtifactTarget::Generic,
            "worker-b",
            Some(0),
            &mut executor,
        )
        .expect_err("wrong worker should not execute claimed batch");
    assert!(
        wrong_worker_err.to_string().contains("claimed by worker"),
        "unexpected wrong-worker error: {wrong_worker_err}"
    );
    assert_eq!(executor.events, Vec::<String>::new());

    let first_batch = execute_source_pack_filesystem_artifact_manifest_claimed_batch_for_target_at(
        artifact_root.clone(),
        0,
        SourcePackArtifactTarget::Generic,
        "worker-a",
        Some(0),
        &mut executor,
    )
    .expect("execute claimed first batch");
    assert_eq!(first_batch.batch_index, 0);
    let state_after_first = store
        .load_build_state()
        .expect("load state after first claimed batch");
    assert_eq!(state_after_first.completed_batch_count(), 1);
    assert_eq!(state_after_first.claimed_batch_count, 0);

    let second_claim = source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-b",
        Some(10),
        Some(0),
    )
    .expect("claim second ready batch");
    assert_eq!(second_claim.claimed_batch_index, Some(1));
    assert_eq!(second_claim.claimed_batch_count, 1);

    let replacement_claim =
        source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at(
            artifact_root.clone(),
            SourcePackArtifactTarget::Generic,
            "worker-c",
            Some(30),
            Some(11),
        )
        .expect("replace expired second-batch claim");
    assert_eq!(replacement_claim.claimed_batch_index, Some(1));
    let state_after_replacement = store
        .load_build_state()
        .expect("load state after replacement claim");
    assert_eq!(state_after_replacement.completed_batch_count(), 1);
    assert_eq!(state_after_replacement.claimed_batch_count, 1);

    let expired_owner_err =
        execute_source_pack_filesystem_artifact_manifest_claimed_batch_for_target_at(
            artifact_root.clone(),
            1,
            SourcePackArtifactTarget::Generic,
            "worker-b",
            Some(11),
            &mut executor,
        )
        .expect_err("expired claim owner should not execute replacement claim");
    assert!(
        expired_owner_err.to_string().contains("claimed by worker"),
        "unexpected expired-owner error: {expired_owner_err}"
    );

    let second_batch =
        execute_source_pack_filesystem_artifact_manifest_claimed_batch_for_target_at(
            artifact_root.clone(),
            1,
            SourcePackArtifactTarget::Generic,
            "worker-c",
            Some(11),
            &mut executor,
        )
        .expect("execute replacement-claimed second batch");
    assert_eq!(second_batch.batch_index, 1);
    let state_after_second = store
        .load_build_state()
        .expect("load state after second claimed batch");
    assert_eq!(state_after_second.completed_batch_count(), 2);
    assert_eq!(state_after_second.claimed_batch_count, 0);
    assert_eq!(executor.events, vec!["frontend:10:1:0", "frontend:20:1:1"]);

    std::fs::remove_dir_all(&root).expect("remove temp filesystem claim dir");
}

#[test]
fn source_pack_filesystem_artifact_claim_and_execute_from_shards_without_path_manifest() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-filesystem-artifact-shard-claimed-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    prepare_explicit_source_libraries_filesystem_artifact_build(
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path],
                dependency_library_ids: vec![10],
            },
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            },
        ],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 8,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
    )
    .expect("prepare filesystem artifact build");

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let initial_progress_summary =
        source_pack_filesystem_artifact_manifest_progress_summary(artifact_root.clone())
            .expect("load initial progress summary");
    assert_eq!(initial_progress_summary.job_batch_count, 5);
    assert_eq!(initial_progress_summary.completed_batch_count, 0);
    assert_eq!(initial_progress_summary.ready_batch_count, 1);
    assert_eq!(initial_progress_summary.first_ready_batch_index, Some(0));
    std::fs::write(store.build_manifest_path(), b"not json")
        .expect("corrupt monolithic path build manifest before claim");
    std::fs::write(store.artifact_manifest_path(), b"not json")
        .expect("corrupt monolithic artifact manifest before claim");

    let claim = source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-a",
        None,
        Some(0),
    )
    .expect("claim first ready batch");
    assert_eq!(claim.claimed_batch_index, Some(0));
    let claimed_progress_summary =
        source_pack_filesystem_artifact_manifest_progress_summary(artifact_root.clone())
            .expect("load claimed progress summary");
    assert_eq!(claimed_progress_summary.completed_batch_count, 0);
    assert_eq!(claimed_progress_summary.ready_batch_count, 1);
    assert_eq!(claimed_progress_summary.first_ready_batch_index, Some(0));
    let second_claim = source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-b",
        None,
        Some(0),
    )
    .expect("active first claim should make frontier empty for another worker");
    assert_eq!(second_claim.claimed_batch_index, None);

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let result = execute_source_pack_filesystem_artifact_manifest_claimed_batch_for_target_at(
        artifact_root.clone(),
        0,
        SourcePackArtifactTarget::Generic,
        "worker-a",
        Some(0),
        &mut executor,
    )
    .expect("claimed batch execution should use execution shard");

    assert_eq!(result.batch_index, 0);
    assert_eq!(executor.events, vec!["frontend:10:1:0"]);
    assert_eq!(
        source_pack_filesystem_artifact_manifest_ready_state_batches(artifact_root.clone())
            .expect("ready-state query should use progress frontier"),
        vec![1, 2]
    );
    let progress_summary_after_first =
        source_pack_filesystem_artifact_manifest_progress_summary(artifact_root.clone())
            .expect("load progress summary after first batch");
    assert_eq!(progress_summary_after_first.completed_batch_count, 1);
    assert_eq!(progress_summary_after_first.ready_batch_count, 2);
    assert_eq!(
        progress_summary_after_first.first_ready_batch_index,
        Some(1)
    );
    let direct_result = execute_source_pack_filesystem_artifact_manifest_batch_for_target(
        artifact_root.clone(),
        1,
        SourcePackArtifactTarget::Generic,
        &mut executor,
    )
    .expect("direct ready batch execution should use execution shard");
    assert_eq!(direct_result.batch_index, 1);
    assert_eq!(executor.events, vec!["frontend:10:1:0", "frontend:20:1:1"]);
    let progress_summary_after_second =
        source_pack_filesystem_artifact_manifest_progress_summary(artifact_root.clone())
            .expect("load progress summary after second batch");
    assert_eq!(progress_summary_after_second.completed_batch_count, 2);
    assert_eq!(progress_summary_after_second.ready_batch_count, 2);
    assert_eq!(
        progress_summary_after_second.first_ready_batch_index,
        Some(2)
    );
    assert_eq!(
        source_pack_filesystem_artifact_manifest_ready_state_batches(artifact_root.clone())
            .expect("ready-state query should use progress frontier"),
        vec![2, 3]
    );
    let shard_index = store
        .load_build_artifact_shard_index()
        .expect("load artifact shard index");
    assert!(shard_index.shard_count() > 0);
    let shard_index_json = String::from_utf8(
        std::fs::read(store.artifact_shard_index_path())
            .expect("read persisted artifact shard index"),
    )
    .expect("artifact shard index is utf8");
    assert!(
        !shard_index_json.contains("\"shards\""),
        "persisted artifact shard index should leave shard records in shard pages"
    );
    let batch_zero_locator = store
        .load_build_batch_shard_locator_for_target(SourcePackArtifactTarget::Generic, 0)
        .expect("load batch 0 shard locator");
    let batch_zero_progress = store
        .load_build_progress_shard_for_target(
            SourcePackArtifactTarget::Generic,
            batch_zero_locator.shard_index,
        )
        .expect("load batch 0 progress shard");
    assert!(batch_zero_progress.completed_batch_indices.contains(&0));
    let batch_one_locator = store
        .load_build_batch_shard_locator_for_target(SourcePackArtifactTarget::Generic, 1)
        .expect("load batch 1 shard locator");
    let batch_one_progress = store
        .load_build_progress_shard_for_target(
            SourcePackArtifactTarget::Generic,
            batch_one_locator.shard_index,
        )
        .expect("load batch 1 progress shard");
    assert!(batch_one_progress.completed_batch_indices.contains(&1));
    let state_marker = serde_json::from_slice::<SourcePackBuildState>(
        &std::fs::read(store.build_state_path()).expect("read root build state marker"),
    )
    .expect("parse root build state marker");
    assert_eq!(state_marker.completed_batch_count(), 2);
    assert_eq!(state_marker.claimed_batch_count, 0);
    let progress_summary =
        source_pack_filesystem_artifact_manifest_progress_summary(artifact_root.clone())
            .expect("load progress summary");
    assert_eq!(progress_summary.job_batch_count, 5);
    assert_eq!(progress_summary.completed_batch_count, 2);
    assert_eq!(progress_summary.ready_batch_count, 2);
    assert_eq!(progress_summary.first_ready_batch_index, Some(2));
    assert_eq!(progress_summary.linked_output_key, None);
    let compact_state = store
        .load_build_state()
        .expect("load compact build state from progress shards");
    assert_eq!(compact_state.completed_batch_count(), 2);
    assert_eq!(compact_state.claimed_batch_count, 0);
    std::fs::remove_dir_all(&root).expect("remove temp shard claimed dir");
}

#[test]
fn source_pack_filesystem_artifact_completion_uses_reverse_dependents() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-filesystem-artifact-reverse-dependent-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let manifest = load_explicit_source_libraries_path_manifest(vec![
        ExplicitSourceLibraryPaths {
            library_id: 20,
            paths: vec![app_path],
            dependency_library_ids: vec![10],
        },
        ExplicitSourceLibraryPaths {
            library_id: 10,
            paths: vec![core_path],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect("load path manifest");
    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 8,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };
    let artifact_manifest = manifest
        .build_plan(limits)
        .retained_build_artifact_manifest(batch_limits);
    let path_build_manifest =
        source_pack_path_build_manifest(&manifest, limits, batch_limits, artifact_manifest);
    let shard_plan =
        path_build_manifest
            .artifacts
            .build_artifact_shard_plan(SourcePackBuildShardLimits {
                max_batches_per_shard: 1,
                max_jobs_per_shard: 1,
                max_artifacts_per_shard: 8,
            });
    let shard_index = &shard_plan.index;
    assert_eq!(shard_index.job_batch_count, 5);
    assert_eq!(shard_plan.max_shard_batch_count(), 1);

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    store
        .store_build_artifact_manifest(&path_build_manifest.artifacts)
        .expect("store artifact manifest");
    let execution_shard_store = store
        .store_build_artifact_execution_shards(&path_build_manifest, &shard_plan)
        .expect("store execution shards");
    assert_eq!(
        execution_shard_store.artifact_execution_shard_count,
        shard_index.shard_count()
    );
    let shard_store = store
        .store_build_artifact_shard_plan(&shard_plan)
        .expect("store shard index");
    assert_eq!(shard_store.artifact_shard_count, shard_index.shard_count());
    assert_eq!(
        shard_store.batch_shard_locator_count,
        shard_index.job_batch_count
    );
    let progress_shard_store = store
        .store_initial_build_progress_shards(&shard_index)
        .expect("store initial progress shards");
    assert_eq!(progress_shard_store.build_progress_shard_count, 5);
    let link_input_index = store
        .load_link_input_shard_index_for_target(SourcePackArtifactTarget::Generic)
        .expect("load compact link input shard index");
    assert!(
        link_input_index.link_interface_shard_range.is_some(),
        "stored link input index should range-encode interface shards"
    );
    assert!(
        link_input_index.link_object_shard_range.is_some(),
        "stored link input index should range-encode object shards"
    );

    let batch_zero_shard =
        source_pack_artifact_shard_for_job_batch(&shard_plan.shards, 0).expect("batch 0 shard");
    let batch_zero_execution = store
        .load_build_artifact_execution_shard_for_target(
            SourcePackArtifactTarget::Generic,
            batch_zero_shard.shard_index,
        )
        .expect("load batch 0 execution shard");
    assert_eq!(
        source_pack_execution_shard_batch_dependents(&batch_zero_execution, 0)
            .expect("batch 0 dependents")
            .dependent_batch_indices
            .as_slice(),
        &[] as &[usize]
    );
    let batch_zero_dependents = store
        .load_build_job_batch_dependents_page_for_target(SourcePackArtifactTarget::Generic, 0, 5)
        .expect("load batch 0 dependent count page");
    assert_eq!(batch_zero_dependents.dependent_batch_count, 3);
    assert_eq!(batch_zero_dependents.dependent_page_count, 1);
    assert!(
        batch_zero_dependents
            .dependents
            .dependent_batch_indices
            .is_empty(),
        "execution reverse dependents should be stored in dependent-batch pages"
    );
    assert_eq!(
        store
            .load_build_job_batch_dependent_batch_page_for_target(
                SourcePackArtifactTarget::Generic,
                0,
                0,
                5,
            )
            .expect("load batch 0 dependent-batch page")
            .dependent_batch_indices
            .as_slice(),
        &[1, 2, 3]
    );

    let unrelated_shard =
        source_pack_artifact_shard_for_job_batch(&shard_plan.shards, 4).expect("batch 4 shard");
    let initial_progress_summary =
        source_pack_filesystem_artifact_manifest_progress_summary(artifact_root.clone())
            .expect("load initial progress summary");
    assert_eq!(initial_progress_summary.ready_batch_count, 1);
    assert_eq!(initial_progress_summary.first_ready_batch_index, Some(0));

    let unrelated_progress_path = store.build_progress_shard_path(unrelated_shard.shard_index);
    let unrelated_progress_bytes =
        std::fs::read(&unrelated_progress_path).expect("read unrelated progress shard");
    std::fs::write(&unrelated_progress_path, b"not json")
        .expect("corrupt unrelated progress shard");
    assert_eq!(
        source_pack_filesystem_artifact_manifest_ready_state_batches(artifact_root.clone())
            .expect("ready-state query should only load ready progress shards"),
        vec![0]
    );
    let initial_page = source_pack_filesystem_artifact_manifest_progress_page_for_target_at(
        artifact_root.clone(),
        batch_zero_shard.shard_index,
        SourcePackArtifactTarget::Generic,
        Some(0),
    )
    .expect("progress page should only load requested shard");
    assert_eq!(initial_page.batch_indices, vec![0]);
    assert_eq!(initial_page.ready_batch_indices, vec![0]);
    assert_eq!(initial_page.completed_batch_indices, Vec::<usize>::new());
    assert_eq!(initial_page.claimed_batch_indices, Vec::<usize>::new());
    let shard_index_path = store.artifact_shard_index_path();
    let shard_index_bytes = std::fs::read(&shard_index_path).expect("read shard index");
    std::fs::write(&shard_index_path, b"not json")
        .expect("corrupt global shard index before progress claim");
    let claim = source_pack_filesystem_artifact_manifest_claim_ready_batch_progress_for_target_at(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-a",
        None,
        4,
        Some(0),
    )
    .expect("progress claim should not load unrelated progress shards");
    assert_eq!(claim.claimed_batch_index, Some(0));
    assert_eq!(claim.progress.completed_batch_count, 0);
    assert_eq!(claim.progress.claimed_batch_count, 1);
    assert_eq!(claim.progress.ready_batch_count, 1);
    assert_eq!(claim.progress.ready_batch_indices, Vec::<usize>::new());
    assert_eq!(
        std::fs::read(&shard_index_path).expect("read corrupted shard index after claim"),
        b"not json"
    );
    std::fs::write(&shard_index_path, shard_index_bytes.clone()).expect("restore shard index");
    let claimed_page = source_pack_filesystem_artifact_manifest_progress_page_for_target_at(
        artifact_root.clone(),
        batch_zero_shard.shard_index,
        SourcePackArtifactTarget::Generic,
        Some(0),
    )
    .expect("claimed progress page should only load requested shard");
    assert_eq!(claimed_page.claimed_batch_indices, vec![0]);
    assert_eq!(claimed_page.claimed_batches.len(), 1);
    std::fs::write(&unrelated_progress_path, unrelated_progress_bytes)
        .expect("restore unrelated progress shard");

    std::fs::write(&shard_index_path, b"not json").expect("corrupt global shard index");
    let unrelated_execution_path = store.artifact_execution_shard_path(unrelated_shard.shard_index);
    let unrelated_execution_bytes =
        std::fs::read(&unrelated_execution_path).expect("read unrelated execution shard");
    std::fs::write(&unrelated_execution_path, b"not json")
        .expect("corrupt unrelated execution shard");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let result = execute_source_pack_filesystem_artifact_manifest_claimed_batch_for_target_at(
        artifact_root.clone(),
        0,
        SourcePackArtifactTarget::Generic,
        "worker-a",
        Some(0),
        &mut executor,
    )
    .expect("completion should only load reverse-dependent execution shards");
    assert_eq!(result.batch_index, 0);
    assert_eq!(executor.events, vec!["frontend:10:1:0"]);
    assert_eq!(
        std::fs::read(&shard_index_path).expect("read corrupted shard index"),
        b"not json"
    );

    std::fs::write(&shard_index_path, shard_index_bytes.clone()).expect("restore shard index");
    let progress_summary =
        source_pack_filesystem_artifact_manifest_progress_summary(artifact_root.clone())
            .expect("load progress summary after bounded completion update");
    assert_eq!(progress_summary.completed_batch_count, 1);
    assert_eq!(progress_summary.ready_batch_count, 2);
    assert_eq!(progress_summary.claimed_batch_count, 0);
    assert_eq!(progress_summary.first_ready_batch_index, Some(1));
    assert_eq!(
        source_pack_filesystem_artifact_manifest_ready_state_batches(artifact_root.clone())
            .expect("ready-state query should use progress frontier"),
        vec![1, 2]
    );
    std::fs::write(&unrelated_execution_path, unrelated_execution_bytes)
        .expect("restore unrelated execution shard");

    std::fs::write(&shard_index_path, b"not json").expect("corrupt shard index during run");
    let worker_run =
        execute_source_pack_filesystem_artifact_manifest_worker_run_progress_for_target_at(
            artifact_root.clone(),
            SourcePackArtifactTarget::Generic,
            "worker-b",
            2,
            None,
            4,
            Some(1),
            &mut executor,
        )
        .expect("progress worker run should return compact counts");
    assert_eq!(worker_run.executed_batch_count, 2);
    assert_eq!(worker_run.progress.completed_batch_count, 3);
    assert_eq!(worker_run.progress.claimed_batch_count, 0);
    assert_eq!(worker_run.progress.ready_batch_count, 1);
    assert_eq!(worker_run.progress.ready_batch_indices, vec![3]);
    assert_eq!(
        std::fs::read(&shard_index_path).expect("read corrupted shard index after run"),
        b"not json"
    );

    let final_run =
        execute_source_pack_filesystem_artifact_manifest_worker_run_progress_for_target_at(
            artifact_root.clone(),
            SourcePackArtifactTarget::Generic,
            "worker-c",
            10,
            None,
            4,
            Some(2),
            &mut executor,
        )
        .expect("progress worker run should finish remaining batches");
    assert_eq!(final_run.executed_batch_count, 2);
    assert_eq!(final_run.progress.completed_batch_count, 5);
    assert_eq!(final_run.progress.claimed_batch_count, 0);
    assert_eq!(final_run.progress.ready_batch_count, 0);
    assert!(final_run.progress.complete);
    assert_eq!(
        final_run.progress.linked_output_key.as_deref(),
        Some("linked-output/job-4/src-0-2")
    );
    let linked_output_path = final_run
        .progress
        .linked_output_path
        .as_ref()
        .expect("linked output path");
    assert_eq!(
        std::fs::read(linked_output_path).expect("read linked output"),
        b"linked:2:2"
    );
    assert_eq!(
        std::fs::read(&shard_index_path).expect("read corrupted shard index after link"),
        b"not json"
    );

    let link_input_shards = shard_plan
        .shards
        .iter()
        .filter(|shard| {
            matches!(
                shard.kind,
                SourcePackBuildArtifactShardKind::LinkInterfaceBatches
                    | SourcePackBuildArtifactShardKind::LinkObjectBatches
            )
        })
        .cloned()
        .collect::<Vec<_>>();
    assert!(
        link_input_shards.len() >= 2,
        "test fixture should have at least two link-input shards"
    );
    let first_link_input_shard = &link_input_shards[0];
    let second_link_input_shard = &link_input_shards[1];
    let first_link_input_execution = store
        .load_build_artifact_execution_shard_for_target(
            SourcePackArtifactTarget::Generic,
            first_link_input_shard.shard_index,
        )
        .expect("load first link-input execution shard");
    let first_releasable_artifacts = first_link_input_execution
        .artifact_refs
        .iter()
        .filter(|artifact| match first_link_input_shard.kind {
            SourcePackBuildArtifactShardKind::LinkInterfaceBatches => {
                artifact.kind == SourcePackArtifactKind::LibraryInterface
            }
            SourcePackBuildArtifactShardKind::LinkObjectBatches => {
                artifact.kind == SourcePackArtifactKind::CodegenObject
            }
            SourcePackBuildArtifactShardKind::JobBatches => false,
        })
        .cloned()
        .collect::<Vec<_>>();
    assert!(
        !first_releasable_artifacts.is_empty(),
        "test fixture should release artifacts from the first link-input shard"
    );
    let first_releasable_paths = first_releasable_artifacts
        .iter()
        .map(|artifact| store.path_for_key(&artifact.key).expect("artifact path"))
        .collect::<Vec<_>>();
    for path in &first_releasable_paths {
        assert!(
            path.exists(),
            "link input artifacts should remain until explicit bounded cleanup: {}",
            path.display()
        );
    }

    let second_link_execution_path =
        store.artifact_execution_shard_path(second_link_input_shard.shard_index);
    let second_link_execution_bytes =
        std::fs::read(&second_link_execution_path).expect("read second link-input shard");
    std::fs::write(&second_link_execution_path, b"not json")
        .expect("corrupt unrelated link-input execution shard");
    let release = release_source_pack_filesystem_artifact_manifest_link_input_shard_for_target(
        artifact_root.clone(),
        first_link_input_shard.shard_index,
        SourcePackArtifactTarget::Generic,
    )
    .expect("release should only load the requested link-input shard");
    assert_eq!(release.target, SourcePackArtifactTarget::Generic);
    assert_eq!(release.shard_index, first_link_input_shard.shard_index);
    assert_eq!(release.shard_kind, first_link_input_shard.kind);
    assert_eq!(
        release.linked_output_key,
        "linked-output/job-4/src-0-2".to_string()
    );
    assert_eq!(release.linked_output_path, *linked_output_path);
    assert_eq!(
        release.artifact_execution_shard_path,
        store.artifact_execution_shard_path(first_link_input_shard.shard_index)
    );
    match first_link_input_shard.kind {
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches => {
            assert_eq!(
                release.released_interface_count,
                first_releasable_artifacts.len()
            );
            assert_eq!(release.released_object_count, 0);
        }
        SourcePackBuildArtifactShardKind::LinkObjectBatches => {
            assert_eq!(release.released_interface_count, 0);
            assert_eq!(
                release.released_object_count,
                first_releasable_artifacts.len()
            );
        }
        SourcePackBuildArtifactShardKind::JobBatches => unreachable!(),
    }
    for path in &first_releasable_paths {
        assert!(
            !path.exists(),
            "released link input artifact should be removed: {}",
            path.display()
        );
    }
    assert_eq!(
        std::fs::read(&second_link_execution_path).expect("read corrupted second link-input shard"),
        b"not json"
    );
    assert_eq!(
        std::fs::read(&shard_index_path).expect("read corrupted shard index after release"),
        b"not json"
    );
    std::fs::write(&shard_index_path, shard_index_bytes).expect("restore shard index");
    std::fs::write(&second_link_execution_path, second_link_execution_bytes)
        .expect("restore second link-input execution shard");

    std::fs::remove_dir_all(&root).expect("remove temp reverse-dependent dir");
}

#[test]
fn source_pack_filesystem_artifact_manifest_claim_respects_state_lock() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-filesystem-artifact-state-lock-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let source_path = source_root.join("core.lani");
    std::fs::write(&source_path, b"core").expect("write source");

    let manifest = load_explicit_source_libraries_path_manifest(vec![ExplicitSourceLibraryPaths {
        library_id: 10,
        paths: vec![source_path],
        dependency_library_ids: Vec::new(),
    }])
    .expect("load path manifest");
    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 8,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };
    let artifact_manifest = manifest
        .build_plan(limits)
        .retained_build_artifact_manifest(batch_limits);
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    store
        .store_build_artifact_manifest(&artifact_manifest)
        .expect("store artifact manifest");
    let path_build_manifest =
        source_pack_path_build_manifest(&manifest, limits, batch_limits, artifact_manifest);
    store
        .store_path_build_manifest(&path_build_manifest)
        .expect("store path build manifest");

    let lock_path = store.build_state_lock_path();
    std::fs::write(&lock_path, b"held").expect("create held state lock");
    let err = source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-a",
        None,
        Some(0),
    )
    .expect_err("held state lock should reject claim");
    assert!(
        err.to_string().contains("build state lock is already held"),
        "unexpected held-lock error: {err}"
    );
    let state = store
        .load_or_init_build_state()
        .expect("load state after rejected claim");
    assert_eq!(state, SourcePackBuildState::new());
    std::fs::remove_file(&lock_path).expect("remove held state lock");

    let claim = source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-a",
        None,
        Some(0),
    )
    .expect("claim after releasing state lock");
    assert_eq!(claim.claimed_batch_index, Some(0));
    assert!(!lock_path.exists());

    let state_file_names = std::fs::read_dir(&artifact_root)
        .expect("read artifact root")
        .map(|entry| {
            entry
                .expect("read artifact root entry")
                .file_name()
                .to_string_lossy()
                .into_owned()
        })
        .collect::<Vec<_>>();
    assert!(
        state_file_names
            .iter()
            .all(|name| !name.starts_with("source-pack-state.json.tmp-")),
        "state temp file should not remain: {state_file_names:?}"
    );

    std::fs::remove_dir_all(&root).expect("remove temp filesystem state-lock dir");
}

#[test]
fn source_pack_filesystem_artifact_manifest_worker_step_executes_ready_batches() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-filesystem-artifact-worker-step-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 8,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };
    let prepared = prepare_explicit_source_libraries_filesystem_artifact_build(
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path],
                dependency_library_ids: vec![10],
            },
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            },
        ],
        &artifact_root,
        limits,
        batch_limits,
    )
    .expect("prepare filesystem artifact build");
    assert_eq!(prepared.target, SourcePackArtifactTarget::Generic);
    assert_eq!(prepared.source_file_count, 2);
    assert_eq!(prepared.source_byte_count, 8);
    assert_eq!(prepared.library_count, 2);
    assert_eq!(prepared.artifact_count, 5);
    assert_eq!(prepared.scheduled_job_count, 5);
    assert_eq!(prepared.batch_count, 5);
    assert_eq!(prepared.initial_ready_batch_count, 1);
    assert_eq!(prepared.first_ready_batch_index, Some(0));
    assert!(prepared.build_manifest_path.exists());
    assert!(prepared.artifact_manifest_path.exists());
    assert!(prepared.artifact_shard_index_path.exists());
    assert!(prepared.artifact_shard_count > 0);
    assert!(prepared.build_state_path.exists());

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let mut final_linked_output_path = None;
    for batch_index in 0..5 {
        let worker_id = format!("worker-{batch_index}");
        let step = execute_source_pack_filesystem_artifact_manifest_worker_step_for_target_at(
            artifact_root.clone(),
            SourcePackArtifactTarget::Generic,
            worker_id.clone(),
            Some(100),
            Some(0),
            &mut executor,
        )
        .expect("worker step should claim and execute the next ready batch");
        assert_eq!(step.worker_id, worker_id);
        assert_eq!(step.claimed_batch_index, Some(batch_index));
        let executed_batch = step
            .executed_batch
            .as_ref()
            .expect("worker step should execute a claimed batch");
        assert_eq!(executed_batch.batch_index, batch_index);
        assert_eq!(step.completed_batch_count, batch_index + 1);
        assert!(step.build_state_path.ends_with("source-pack-state.json"));
        if batch_index == 4 {
            assert!(step.complete);
            assert_eq!(step.ready_batch_count, 0);
            assert_eq!(
                step.linked_output_key.as_deref(),
                Some("linked-output/job-4/src-0-2")
            );
            final_linked_output_path = step.linked_output_path;
        } else {
            assert!(!step.complete);
            assert_eq!(step.linked_output_key, None);
            assert_eq!(step.linked_output_path, None);
            assert!(step.ready_batch_count > 0);
        }
    }

    let replay = execute_source_pack_filesystem_artifact_manifest_worker_step_for_target_at(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-done",
        Some(100),
        Some(0),
        &mut executor,
    )
    .expect("worker step should be idempotent after completion");
    assert_eq!(replay.claimed_batch_index, None);
    assert_eq!(replay.executed_batch, None);
    assert!(replay.complete);
    assert_eq!(replay.completed_batch_count, 5);

    let linked_output_path = final_linked_output_path.expect("linked output path");
    assert_eq!(
        std::fs::read(&linked_output_path).expect("read linked output"),
        b"linked:2:2"
    );
    assert_eq!(
        executor.events,
        vec![
            "frontend:10:1:0",
            "frontend:20:1:1",
            "codegen:10:0..1:1:0",
            "codegen:20:1..2:1:1",
            "begin-link:4",
            "link-interfaces:0:1",
            "link-interfaces:1:1",
            "link-objects:0:1",
            "link-objects:1:1",
            "finish-link:4:2:2",
        ]
    );

    std::fs::remove_dir_all(&root).expect("remove temp filesystem worker-step dir");
}

#[test]
fn source_pack_filesystem_artifact_manifest_worker_streams_dependency_interfaces_in_paged_batches()
{
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-filesystem-artifact-manifest-paged-worker-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    prepare_explicit_source_libraries_filesystem_artifact_build(
        vec![
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path],
                dependency_library_ids: vec![10],
            },
            ExplicitSourceLibraryPaths {
                library_id: 10,
                paths: vec![core_path],
                dependency_library_ids: Vec::new(),
            },
        ],
        &artifact_root,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 8,
        },
        SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        },
    )
    .expect("prepare manifest worker paged dependency test");

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    for (batch_index, job_index, input_count) in [(1usize, 1usize, 1usize), (3, 3, 2)] {
        let execution_shard = source_pack_execution_shard_for_batch_locator(
            &store,
            SourcePackArtifactTarget::Generic,
            batch_index,
        )
        .expect("load execution shard for manifest worker paged input");
        let job_manifest = source_pack_execution_shard_job_artifact(&execution_shard, job_index)
            .expect("load manifest worker job artifact manifest");
        assert_eq!(job_manifest.input_interface_count, input_count);
        if job_index == 1 {
            assert_eq!(job_manifest.input_interface_page_count, 0);
            assert_eq!(job_manifest.input_interface_ranges.len(), 1);
        } else {
            assert_eq!(job_manifest.input_interface_page_count, 1);
            assert_eq!(job_manifest.input_interface_ranges.len(), 1);
        }
        assert!(job_manifest.input_interfaces.is_empty());
    }
    std::fs::write(store.build_manifest_path(), b"not json")
        .expect("corrupt monolithic build manifest");
    std::fs::write(store.artifact_manifest_path(), b"not json")
        .expect("corrupt monolithic artifact manifest");

    let mut executor = RecordingSourcePackByteArtifactExecutor {
        record_paged_dependency_batches: true,
        ..Default::default()
    };
    let run = execute_source_pack_filesystem_artifact_manifest_worker_run_for_target_at(
        &artifact_root,
        SourcePackArtifactTarget::Generic,
        "worker-a",
        16,
        Some(100),
        Some(0),
        &mut executor,
    )
    .expect("run manifest worker through paged dependency batches");
    assert!(run.complete);
    let linked_output_path = run.linked_output_path.expect("linked output path");
    assert_eq!(
        std::fs::read(&linked_output_path).expect("read linked output"),
        b"linked:2:2"
    );
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "frontend-deps:20:1"),
        "app frontend dependencies should be streamed as a paged batch: {:?}",
        executor.events
    );
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "codegen-deps:20:1"),
        "app codegen dependencies should be streamed as a paged batch: {:?}",
        executor.events
    );
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "frontend:20:1:1"),
        "paged frontend finish should see exactly one dependency: {:?}",
        executor.events
    );
    assert!(
        executor
            .events
            .iter()
            .any(|event| event == "codegen:20:1..2:1:1"),
        "paged codegen finish should exclude the owning interface and see one dependency: {:?}",
        executor.events
    );

    std::fs::remove_dir_all(&root).expect("remove temp manifest paged worker dir");
}

#[test]
fn source_pack_filesystem_async_claimed_batch_streams_dependency_interfaces_in_paged_batches() {
    pollster::block_on(async {
        let suffix = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = std::env::temp_dir().join(format!(
            "laniusc-filesystem-async-claimed-batch-paged-test-{}-{suffix}",
            std::process::id()
        ));
        let source_root = root.join("sources");
        let artifact_root = root.join("artifacts");
        std::fs::create_dir_all(&source_root).expect("create temp source dir");
        let core_path = source_root.join("core.lani");
        let app_path = source_root.join("app.lani");
        std::fs::write(&core_path, b"core").expect("write core source");
        std::fs::write(&app_path, b"app!").expect("write app source");

        prepare_explicit_source_libraries_filesystem_artifact_build(
            vec![
                ExplicitSourceLibraryPaths {
                    library_id: 20,
                    paths: vec![app_path],
                    dependency_library_ids: vec![10],
                },
                ExplicitSourceLibraryPaths {
                    library_id: 10,
                    paths: vec![core_path],
                    dependency_library_ids: Vec::new(),
                },
            ],
            &artifact_root,
            CodegenUnitLimits {
                max_source_bytes: 4,
                max_source_files: 8,
            },
            SourcePackJobBatchLimits {
                max_jobs_per_batch: 1,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 1,
            },
        )
        .expect("prepare async claimed-batch paged dependency test");

        let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
        for (batch_index, job_index, input_count) in [(1usize, 1usize, 1usize), (3, 3, 2)] {
            let execution_shard = source_pack_execution_shard_for_batch_locator(
                &store,
                SourcePackArtifactTarget::Generic,
                batch_index,
            )
            .expect("load execution shard for async claimed-batch paged input");
            let job_manifest =
                source_pack_execution_shard_job_artifact(&execution_shard, job_index)
                    .expect("load async claimed-batch job artifact manifest");
            assert_eq!(job_manifest.input_interface_count, input_count);
            if job_index == 1 {
                assert_eq!(job_manifest.input_interface_page_count, 0);
                assert_eq!(job_manifest.input_interface_ranges.len(), 1);
            } else {
                assert_eq!(job_manifest.input_interface_page_count, 1);
                assert_eq!(job_manifest.input_interface_ranges.len(), 1);
            }
            assert!(job_manifest.input_interfaces.is_empty());
        }
        std::fs::write(store.build_manifest_path(), b"not json")
            .expect("corrupt monolithic build manifest");
        std::fs::write(store.artifact_manifest_path(), b"not json")
            .expect("corrupt monolithic artifact manifest");

        let mut executor = RecordingSourcePackByteArtifactExecutor {
            record_paged_dependency_batches: true,
            ..Default::default()
        };
        let mut final_batch = None;
        for _ in 0..5 {
            let claim = source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at(
                &artifact_root,
                SourcePackArtifactTarget::Generic,
                "async-worker",
                Some(100),
                Some(0),
            )
            .expect("claim ready async batch");
            let batch_index = claim
                .claimed_batch_index
                .expect("async claimed-batch test should have a ready batch");
            let executed =
                    execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_for_target_at(
                        &artifact_root,
                        batch_index,
                        SourcePackArtifactTarget::Generic,
                        "async-worker",
                        Some(0),
                        &mut executor,
                    )
                    .await
                    .expect("execute async claimed batch");
            final_batch = Some(executed);
        }

        let final_batch = final_batch.expect("final async batch result");
        assert_eq!(
            final_batch.linked_output_key.as_deref(),
            Some("linked-output/job-4/src-0-2")
        );
        let linked_output_path = final_batch
            .linked_output_path
            .as_ref()
            .expect("async linked output path");
        assert_eq!(
            std::fs::read(linked_output_path).expect("read async linked output"),
            b"linked:2:2"
        );
        assert!(
            executor
                .events
                .iter()
                .any(|event| event == "frontend-deps:20:1"),
            "async frontend dependencies should be streamed as a paged batch: {:?}",
            executor.events
        );
        assert!(
            executor
                .events
                .iter()
                .any(|event| event == "codegen-deps:20:1"),
            "async codegen dependencies should be streamed as a paged batch: {:?}",
            executor.events
        );

        std::fs::remove_dir_all(&root).expect("remove temp async claimed-batch dir");
    });
}

#[test]
fn gpu_source_pack_artifact_descriptors_name_record_array_boundaries() {
    let frontend_job = SourcePackJob {
        job_index: 7,
        phase: SourcePackJobPhase::LibraryFrontend,
        phase_unit_index: 1,
        library_job_index: None,
        library_id: 42,
        first_source_index: 3,
        source_file_count: 2,
        source_bytes: 128,
        source_lines: 9,
        oversized_source_file: false,
        dependency_job_indices: vec![1, 2],
    };
    let frontend = GpuSourcePackArtifactDescriptor::library_interface_for_job(
        SourcePackArtifactTarget::Wasm,
        &frontend_job,
        GpuSourcePackDependencyInterfaceSummary::counted(2, 1),
    );

    assert_eq!(
        frontend.version,
        GPU_SOURCE_PACK_ARTIFACT_DESCRIPTOR_VERSION
    );
    assert_eq!(frontend.target, SourcePackArtifactTarget::Wasm);
    assert_eq!(frontend.stage, GpuSourcePackArtifactStage::LibraryInterface);
    assert_eq!(frontend.job_index, 7);
    assert_eq!(frontend.source_lines, 9);
    assert_eq!(frontend.dependency_interface_count, 2);
    assert_eq!(frontend.dependency_interface_batch_count, 1);
    let frontend_arrays = frontend
        .record_arrays
        .iter()
        .map(|record| record.name.as_str())
        .collect::<Vec<_>>();
    let frontend_input_arrays = frontend
        .input_record_arrays
        .iter()
        .map(|record| record.name.as_str())
        .collect::<Vec<_>>();
    let frontend_output_arrays = frontend
        .output_record_arrays
        .iter()
        .map(|record| record.name.as_str())
        .collect::<Vec<_>>();
    assert!(frontend_input_arrays.contains(&"source_file_records"));
    assert!(frontend_input_arrays.contains(&"dependency_semantic_interface_records"));
    assert!(frontend_output_arrays.contains(&"token_records"));
    assert!(frontend_output_arrays.contains(&"parse_tree_records"));
    assert!(frontend_output_arrays.contains(&"hir_node_records"));
    assert!(frontend_output_arrays.contains(&"resolver_records"));
    assert!(frontend_output_arrays.contains(&"type_instance_records"));
    assert!(frontend_output_arrays.contains(&"semantic_interface_records"));
    assert!(frontend_arrays.contains(&"token_records"));
    assert!(frontend_arrays.contains(&"parse_tree_records"));
    assert!(frontend_arrays.contains(&"hir_node_records"));
    assert!(frontend_arrays.contains(&"resolver_records"));
    assert!(frontend_arrays.contains(&"type_instance_records"));
    assert!(frontend_arrays.contains(&"semantic_interface_records"));
    assert!(!frontend_arrays.contains(&"virtual_instruction_records"));

    let codegen_job = SourcePackJob {
        phase: SourcePackJobPhase::Codegen,
        library_job_index: Some(frontend_job.job_index),
        ..frontend_job.clone()
    };
    let codegen = GpuSourcePackArtifactDescriptor::codegen_object_contract_for_job(
        SourcePackArtifactTarget::X86_64,
        &codegen_job,
        GpuSourcePackDependencyInterfaceSummary::counted(2, 1),
    );
    let codegen_arrays = codegen
        .record_arrays
        .iter()
        .map(|record| record.name.as_str())
        .collect::<Vec<_>>();
    let codegen_input_arrays = codegen
        .input_record_arrays
        .iter()
        .map(|record| record.name.as_str())
        .collect::<Vec<_>>();
    let codegen_output_arrays = codegen
        .output_record_arrays
        .iter()
        .map(|record| record.name.as_str())
        .collect::<Vec<_>>();
    assert_eq!(codegen.stage, GpuSourcePackArtifactStage::CodegenObject);
    assert_eq!(codegen.source_lines, 9);
    assert_eq!(codegen.dependency_interface_count, 2);
    assert_eq!(codegen.dependency_interface_batch_count, 1);
    assert!(codegen_input_arrays.contains(&"attributed_hir_records"));
    assert!(codegen_input_arrays.contains(&"resolver_records"));
    assert!(codegen_input_arrays.contains(&"type_instance_records"));
    assert!(codegen_input_arrays.contains(&"literal_records"));
    assert!(codegen_input_arrays.contains(&"dependency_semantic_interface_records"));
    assert!(!codegen_input_arrays.contains(&"source_file_records"));
    assert!(!codegen_input_arrays.contains(&"token_records"));
    assert!(codegen_output_arrays.contains(&"node_instruction_count_records"));
    assert!(codegen_output_arrays.contains(&"instruction_location_records"));
    assert!(codegen_output_arrays.contains(&"virtual_instruction_records"));
    assert!(codegen_output_arrays.contains(&"virtual_register_records"));
    assert!(codegen_output_arrays.contains(&"relocation_records"));
    assert!(codegen_arrays.contains(&"node_instruction_count_records"));
    assert!(codegen_arrays.contains(&"instruction_location_records"));
    assert!(codegen_arrays.contains(&"virtual_instruction_records"));
    assert!(codegen_arrays.contains(&"virtual_register_records"));
    assert!(!codegen_arrays.contains(&"emitted_byte_records"));

    let link_job = SourcePackJob {
        job_index: 9,
        phase: SourcePackJobPhase::Link,
        library_job_index: None,
        dependency_job_indices: vec![7, 8],
        ..frontend_job.clone()
    };
    let linked = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
        SourcePackArtifactTarget::X86_64,
        &link_job,
        2,
        3,
    );
    let linked_arrays = linked
        .record_arrays
        .iter()
        .map(|record| record.name.as_str())
        .collect::<Vec<_>>();
    let linked_input_arrays = linked
        .input_record_arrays
        .iter()
        .map(|record| record.name.as_str())
        .collect::<Vec<_>>();
    let linked_output_arrays = linked
        .output_record_arrays
        .iter()
        .map(|record| record.name.as_str())
        .collect::<Vec<_>>();
    assert_eq!(linked.stage, GpuSourcePackArtifactStage::LinkedOutput);
    assert_eq!(linked.source_lines, 9);
    assert_eq!(linked.dependency_interface_count, 2);
    assert_eq!(linked.dependency_codegen_object_count, 3);
    assert!(linked_input_arrays.contains(&"allocated_instruction_records"));
    assert!(linked_input_arrays.contains(&"function_offset_records"));
    assert!(linked_input_arrays.contains(&"link_relocation_records"));
    assert_eq!(linked_output_arrays, vec!["emitted_byte_records"]);
    assert!(linked_arrays.contains(&"allocated_instruction_records"));
    assert!(linked_arrays.contains(&"function_offset_records"));
    assert!(linked_arrays.contains(&"link_relocation_records"));
    assert!(linked_arrays.contains(&"emitted_byte_records"));

    let partial_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target: SourcePackArtifactTarget::X86_64,
        group_index: 4,
        kind: SourcePackHierarchicalLinkGroupKind::Reduce,
        job_index: 12,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: Vec::new(),
        input_group_count: 2,
        input_group_page_count: 0,
        input_group_indices: vec![0, 1],
        input_group_output_keys: vec!["a".to_string(), "b".to_string()],
        source_byte_count: 512,
        source_file_count: 6,
        source_line_count: 42,
        output_key: "partial-link".to_string(),
        final_output: false,
    };
    let partial =
        GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(&partial_page, 0, 0, 2);
    let partial_arrays = partial
        .record_arrays
        .iter()
        .map(|record| record.name.as_str())
        .collect::<Vec<_>>();
    let partial_input_arrays = partial
        .input_record_arrays
        .iter()
        .map(|record| record.name.as_str())
        .collect::<Vec<_>>();
    let partial_output_arrays = partial
        .output_record_arrays
        .iter()
        .map(|record| record.name.as_str())
        .collect::<Vec<_>>();
    assert_eq!(partial.stage, GpuSourcePackArtifactStage::PartialLink);
    assert_eq!(partial.group_index, Some(4));
    assert_eq!(partial.source_lines, 42);
    assert_eq!(partial.dependency_partial_link_count, 2);
    assert!(partial_input_arrays.contains(&"allocated_instruction_records"));
    assert!(partial_input_arrays.contains(&"function_offset_records"));
    assert!(partial_input_arrays.contains(&"link_relocation_records"));
    assert!(partial_input_arrays.contains(&"input_partial_link_relocation_records"));
    assert_eq!(
        partial_output_arrays,
        vec!["partial_link_relocation_records"]
    );
    assert!(partial_arrays.contains(&"allocated_instruction_records"));
    assert!(partial_arrays.contains(&"partial_link_relocation_records"));
    assert!(!partial_arrays.contains(&"emitted_byte_records"));

    assert_eq!(
        gpu_source_pack_descriptor_artifact_key(
            SourcePackArtifactTarget::Wasm,
            GpuSourcePackArtifactStage::LibraryInterface,
            "job-7",
        ),
        "gpu-source-pack/wasm/library-interface/job-7.json"
    );
}

#[test]
fn source_pack_path_manifest_bounded_frontend_build_splits_large_library_frontend_artifacts() {
    let files = (0..3)
        .map(|source_index| ExplicitSourcePathFile {
            library_id: 5,
            path: PathBuf::from(format!("lib5-{source_index}.lani")),
            byte_len: 4,
            modified_unix_nanos: None,
            line_count: Some(1),
        })
        .collect::<Vec<_>>();
    let manifest = ExplicitSourcePackPathManifest {
        files,
        library_dependencies: Vec::new(),
    };
    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 1,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };
    let build_plan = manifest.build_plan(limits);
    assert_eq!(build_plan, manifest.bounded_frontend_build_plan(limits));
    let artifacts = build_plan.retained_build_artifact_manifest(batch_limits);

    assert_eq!(artifacts.job_schedule.frontend_job_count(), 3);
    assert_eq!(artifacts.job_schedule.codegen_job_count(), 3);
    assert_eq!(artifacts.job_batches.oversized_batch_count(), 0);
    assert_eq!(
        artifacts
            .artifacts
            .artifacts
            .iter()
            .filter(|artifact| artifact.kind == SourcePackArtifactKind::LibraryInterface)
            .map(|artifact| (
                artifact.producing_job_index,
                artifact.first_source_index,
                artifact.source_file_count,
                artifact.source_bytes,
                artifact.source_lines,
            ))
            .collect::<Vec<_>>(),
        vec![(0, 0, 1, 4, 1), (1, 1, 1, 4, 1), (2, 2, 1, 4, 1)]
    );
    assert_eq!(
        artifacts
            .link_interface_batches
            .batches
            .iter()
            .map(|batch| batch.source_lines)
            .collect::<Vec<_>>(),
        vec![1, 1, 1]
    );
    assert_eq!(
        artifacts
            .link_object_batches
            .batches
            .iter()
            .map(|batch| batch.source_lines)
            .collect::<Vec<_>>(),
        vec![1, 1, 1]
    );
    assert_eq!(
        artifacts.job_schedule.jobs[3].dependency_job_indices,
        vec![0]
    );
    assert_eq!(
        artifacts.job_schedule.dependency_job_ranges(3),
        &[SourcePackJobIndexRange {
            first_job_index: 1,
            job_count: 2,
        }]
    );

    let path_build_manifest =
        source_pack_path_build_manifest(&manifest, limits, batch_limits, artifacts);
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-bounded-frontend-path-manifest-test-{}-{suffix}",
        std::process::id()
    ));
    let store = SourcePackFilesystemArtifactStore::new(&root);
    store
        .store_path_build_manifest(&path_build_manifest)
        .expect("store bounded frontend path build manifest");

    let execution_shard =
        source_pack_execution_shard_for_batch_locator(&store, SourcePackArtifactTarget::Generic, 0)
            .expect("load first bounded frontend execution shard");
    let first_job = source_pack_execution_shard_job(&execution_shard, 0)
        .expect("load first bounded frontend job");
    assert_eq!(first_job.phase, SourcePackJobPhase::LibraryFrontend);
    assert_eq!(first_job.source_file_count, 1);
    assert_eq!(first_job.source_bytes, 4);
    assert_eq!(first_job.source_lines, 1);
    assert_eq!(execution_shard.shard.source_lines, 6);

    std::fs::remove_dir_all(&root).expect("remove temp bounded frontend path manifest dir");
}

#[test]
fn source_pack_filesystem_artifact_manifest_worker_run_resumes_across_workers() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-filesystem-artifact-worker-run-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let core_path = source_root.join("core.lani");
    let app_path = source_root.join("app.lani");
    std::fs::write(&core_path, b"core").expect("write core source");
    std::fs::write(&app_path, b"app!").expect("write app source");

    let manifest = load_explicit_source_libraries_path_manifest(vec![
        ExplicitSourceLibraryPaths {
            library_id: 20,
            paths: vec![app_path],
            dependency_library_ids: vec![10],
        },
        ExplicitSourceLibraryPaths {
            library_id: 10,
            paths: vec![core_path],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect("load path manifest");
    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 8,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };
    let artifact_manifest = manifest
        .build_plan(limits)
        .retained_build_artifact_manifest(batch_limits);
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    store
        .store_build_artifact_manifest(&artifact_manifest)
        .expect("store artifact manifest");
    let path_build_manifest =
        source_pack_path_build_manifest(&manifest, limits, batch_limits, artifact_manifest);
    store
        .store_path_build_manifest(&path_build_manifest)
        .expect("store path build manifest");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let first = execute_source_pack_filesystem_artifact_manifest_worker_run_for_target_at(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-a",
        2,
        Some(100),
        Some(0),
        &mut executor,
    )
    .expect("first worker run should execute two batches");
    assert_eq!(first.worker_id, "worker-a");
    assert_eq!(first.executed_batch_count, 2);
    assert_eq!(first.completed_batch_count, 2);
    assert_eq!(first.ready_batch_count, 2);
    assert!(!first.complete);

    let second = execute_source_pack_filesystem_artifact_manifest_worker_run_for_target_at(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-b",
        10,
        Some(100),
        Some(0),
        &mut executor,
    )
    .expect("second worker run should resume and finish");
    assert_eq!(second.worker_id, "worker-b");
    assert_eq!(second.executed_batch_count, 3);
    assert_eq!(second.completed_batch_count, 5);
    assert_eq!(second.ready_batch_count, 0);
    assert!(second.complete);
    assert_eq!(
        second.linked_output_key.as_deref(),
        Some("linked-output/job-4/src-0-2")
    );

    let replay = execute_source_pack_filesystem_artifact_manifest_worker_run_for_target_at(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-c",
        10,
        Some(100),
        Some(0),
        &mut executor,
    )
    .expect("completed worker run should not execute more batches");
    assert_eq!(replay.executed_batch_count, 0);
    assert!(replay.complete);
    assert_eq!(replay.completed_batch_count, 5);

    let linked_output_path = second.linked_output_path.expect("linked output path");
    assert_eq!(
        std::fs::read(&linked_output_path).expect("read linked output"),
        b"linked:2:2"
    );
    assert_eq!(
        executor.events,
        vec![
            "frontend:10:1:0",
            "frontend:20:1:1",
            "codegen:10:0..1:1:0",
            "codegen:20:1..2:1:1",
            "begin-link:4",
            "link-interfaces:0:1",
            "link-interfaces:1:1",
            "link-objects:0:1",
            "link-objects:1:1",
            "finish-link:4:2:2",
        ]
    );

    std::fs::remove_dir_all(&root).expect("remove temp filesystem worker-run dir");
}

#[test]
fn source_pack_filesystem_artifact_manifest_batch_rejects_changed_source_metadata() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-filesystem-artifact-changed-source-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create temp source dir");
    let source_path = source_root.join("source.lani");
    std::fs::write(&source_path, b"core").expect("write source");

    let manifest = load_explicit_source_libraries_path_manifest(vec![ExplicitSourceLibraryPaths {
        library_id: 10,
        paths: vec![source_path.clone()],
        dependency_library_ids: Vec::new(),
    }])
    .expect("load path manifest");
    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 8,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };
    let build_plan = manifest.build_plan(limits);
    let artifact_manifest = build_plan.retained_build_artifact_manifest(batch_limits);
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    store
        .store_build_artifact_manifest(&artifact_manifest)
        .expect("store artifact manifest");
    let path_build_manifest =
        source_pack_path_build_manifest(&manifest, limits, batch_limits, artifact_manifest);
    store
        .store_path_build_manifest(&path_build_manifest)
        .expect("store path build manifest");
    std::fs::write(&source_path, b"changed").expect("change source after planning");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let err = execute_source_pack_filesystem_artifact_manifest_batch(
        artifact_root.clone(),
        0,
        &mut executor,
    )
    .expect_err("changed source metadata should reject stale persisted manifest batch");
    std::fs::remove_dir_all(&root).expect("remove temp changed-source dir");

    assert!(
        err.to_string()
            .contains("changed since manifest was planned"),
        "unexpected changed-source batch error: {err}"
    );
    assert_eq!(executor.events, Vec::<String>::new());
}

#[test]
fn source_pack_filesystem_artifact_store_rejects_non_relative_keys() {
    let store = SourcePackFilesystemArtifactStore::new(std::env::temp_dir());

    for key in ["../escape", "/absolute", "valid/../escape"] {
        let err = store
            .path_for_key(key)
            .expect_err("artifact store key should be rejected");
        assert!(
            err.to_string().contains("not relative and normal"),
            "unexpected error for {key:?}: {err}"
        );
    }

    assert!(
        store
            .path_for_key("library-interface/lib-1/job-0/src-0-1")
            .expect("valid artifact key")
            .ends_with("library-interface/lib-1/job-0/src-0-1")
    );
}

#[test]
fn x86_inst_capacity_uses_semantic_hir_count() {
    assert_eq!(
        x86_inst_hir_node_count_for_backend_capacity(17_164_633, 14_614_800),
        14_614_800
    );
}

#[test]
fn x86_inst_capacity_stays_within_parser_storage() {
    assert_eq!(x86_inst_hir_node_count_for_backend_capacity(128, 256), 128);
    assert_eq!(x86_inst_hir_node_count_for_backend_capacity(0, 0), 1);
}

#[test]
fn x86_split_typecheck_capacity_uses_parser_emit_len() {
    assert_eq!(
        hir_node_capacity_for_parser_emit(17_164_633, 3_650_001),
        3_650_001
    );
    assert_eq!(hir_node_capacity_for_parser_emit(128, 256), 128);
    assert_eq!(hir_node_capacity_for_parser_emit(0, 0), 1);
}

#[test]
fn x86_backend_parser_replay_handoff_keeps_only_lexer_inputs() {
    let lexer_bufs = resident_lexer_buffers_for_scratch_tests();
    let parser_bufs = resident_parser_buffers_for_scratch_tests();
    let replay_inputs = OwnedLexerParserInputBuffers::from_lexer_buffers(&lexer_bufs);

    assert_eq!(replay_inputs.source_len, lexer_bufs.n);
    assert_eq!(
        buffer_id(&replay_inputs.in_bytes),
        buffer_id(&lexer_bufs.in_bytes.buffer)
    );
    assert_eq!(
        buffer_id(&replay_inputs.tokens_out),
        buffer_id(&lexer_bufs.tokens_out.buffer)
    );
    assert_eq!(
        buffer_id(&replay_inputs.token_count),
        buffer_id(&lexer_bufs.token_count.buffer)
    );
    assert_eq!(
        buffer_id(&replay_inputs.token_file_id),
        buffer_id(&lexer_bufs.token_file_id.buffer)
    );

    let first_parse_hir_outputs = [
        &parser_bufs.ll1_status.buffer,
        &parser_bufs.hir_kind.buffer,
        &parser_bufs.parent.buffer,
        &parser_bufs.first_child.buffer,
        &parser_bufs.next_sibling.buffer,
        &parser_bufs.subtree_end.buffer,
        &parser_bufs.hir_token_pos.buffer,
        &parser_bufs.hir_expr_record.buffer,
        &parser_bufs.hir_stmt_record.buffer,
    ];
    for replay_input in [
        &replay_inputs.in_bytes,
        &replay_inputs.tokens_out,
        &replay_inputs.token_count,
        &replay_inputs.token_file_id,
    ] {
        assert_distinct_from(replay_input, &first_parse_hir_outputs);
    }
}

#[test]
fn compiler_cross_phase_scratch_uses_dead_frontend_workspaces() {
    let lexer_bufs = resident_lexer_buffers_for_scratch_tests();
    let bufs = resident_parser_buffers_for_scratch_tests();
    let typecheck_parse = OwnedTypecheckParserBuffers::from_parser_buffers(&bufs);
    let typecheck_scratch = GpuCompiler::typecheck_external_scratch_from_frontend_buffers(
        &lexer_bufs,
        &typecheck_parse,
    );

    assert_eq!(
        buffer_id(typecheck_scratch.fn_entrypoint_tag),
        buffer_id(&bufs.tree_prefix.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_expr_ref_tag),
        buffer_id(&lexer_bufs.end_positions.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_expr_ref_payload),
        buffer_id(&lexer_bufs.types_compact.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_generic_param_slot_by_token),
        buffer_id(&bufs.hir_list_rank_node.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_const_param_slot_by_token),
        buffer_id(&bufs.hir_list_rank_local_prefix.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.record_family_flag),
        buffer_id(&bufs.hir_type_alias_owner_value_a.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.module_record_prefix),
        buffer_id(&bufs.hir_type_alias_owner_value_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.record_scan_local_prefix),
        buffer_id(&bufs.hir_type_alias_owner_link_a.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.module_path_key_radix_block_histogram),
        buffer_id(&bufs.hir_list_rank_local_prefix.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.module_path_key_radix_block_bucket_prefix),
        buffer_id(&bufs.hir_list_rank_node.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_generic_param_slot_by_token),
        buffer_id(typecheck_scratch.module_path_key_radix_block_bucket_prefix)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_const_param_slot_by_token),
        buffer_id(typecheck_scratch.module_path_key_radix_block_histogram)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.path_id_by_owner_hir),
        buffer_id(&bufs.hir_type_alias_owner_link_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.decl_module_file_id),
        buffer_id(&bufs.token_brace_semantic_kind.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.decl_module_id),
        buffer_id(&bufs.token_bracket_semantic_kind.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.decl_name_id),
        buffer_id(&bufs.token_statement_context_kind.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.decl_namespace),
        buffer_id(&bufs.token_brace_match_depth.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.decl_visibility),
        buffer_id(&bufs.semantic_token_kinds.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.decl_token_start),
        buffer_id(&bufs.token_depth_brace_inblock.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.decl_token_end),
        buffer_id(&bufs.token_depth_bracket_inblock.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.decl_key_to_decl_id),
        buffer_id(&bufs.hir_semantic_prefix_before_node.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.decl_key_order_tmp),
        buffer_id(&bufs.hir_array_element_previous.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.decl_status),
        buffer_id(&bufs.out_headers.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.call_param_count),
        buffer_id(&bufs.hir_type_arg_rank_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.call_arg_record),
        buffer_id(&bufs.hir_match_rank_node.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.function_lookup_key),
        buffer_id(&bufs.hir_match_rank_local_prefix.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.function_lookup_fn),
        buffer_id(&bufs.hir_match_arm_previous.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_decl_generic_param_count),
        buffer_id(&bufs.out_headers.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_decl_generic_param_count_by_node),
        buffer_id(&bufs.hir_type_path_leaf_value_a.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_instance_head_token),
        buffer_id(&bufs.default_token_file_id.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_instance_arg_start),
        buffer_id(&bufs.token_brace_semantic_kind.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_instance_arg_count),
        buffer_id(&bufs.token_depth_bracket_inblock.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_instance_arg_start),
        buffer_id(typecheck_scratch.decl_module_file_id)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_instance_arg_count),
        buffer_id(typecheck_scratch.decl_token_end)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_instance_arg_ref_tag),
        buffer_id(&bufs.hir_variant_rank_a.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_instance_arg_ref_payload),
        buffer_id(&bufs.hir_variant_payload_link_a.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_instance_elem_ref_tag),
        buffer_id(&lexer_bufs.dfa_02_ping.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_instance_elem_ref_payload),
        buffer_id(&lexer_bufs.dfa_02_pong.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_instance_len_kind),
        buffer_id(&bufs.semantic_token_kinds.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_instance_len_payload),
        buffer_id(&lexer_bufs.dfa_chunk_summaries.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_instance_len_kind),
        buffer_id(typecheck_scratch.decl_visibility)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_instance_len_payload),
        buffer_id(typecheck_scratch.decl_type_key_to_decl_id)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_instance_state),
        buffer_id(&bufs.token_bracket_semantic_kind.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_instance_state),
        buffer_id(typecheck_scratch.decl_module_id)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.decl_type_key_to_decl_id),
        buffer_id(&lexer_bufs.dfa_chunk_summaries.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.decl_value_key_to_decl_id),
        buffer_id(&bufs.hir_variant_payload_link_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.method_decl_module_id),
        buffer_id(&bufs.hir_type_alias_owner_value_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.method_decl_impl_node),
        buffer_id(&bufs.hir_type_alias_owner_link_a.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.method_decl_name_token),
        buffer_id(&bufs.match_for_index.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.call_param_type),
        buffer_id(&bufs.out_headers.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_decl_generic_param_count),
        buffer_id(typecheck_scratch.decl_status)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.type_decl_generic_param_count),
        buffer_id(typecheck_scratch.call_param_type)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.method_decl_name_id),
        buffer_id(&bufs.hir_variant_payload_rank_a.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.method_decl_param_offset),
        buffer_id(&bufs.hir_semantic_parent.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.method_decl_receiver_mode),
        buffer_id(&bufs.hir_variant_payload_rank_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.method_decl_visibility),
        buffer_id(&bufs.hir_variant_payload_owner_a.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.method_key_to_fn_token),
        buffer_id(&bufs.hir_fn_signature_owner_link_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.method_key_status),
        buffer_id(&bufs.hir_match_rank_node.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.method_key_radix_block_histogram),
        buffer_id(&bufs.hir_fn_signature_function_owner_a.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.method_key_radix_block_bucket_prefix),
        buffer_id(&bufs.hir_fn_signature_function_owner_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.method_call_receiver_ref_tag),
        buffer_id(&bufs.hir_type_arg_previous.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.method_call_receiver_ref_payload),
        buffer_id(&bufs.hir_match_rank_local_prefix.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.method_call_name_id),
        buffer_id(&bufs.hir_variant_payload_owner_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.method_call_site_module_id),
        buffer_id(&bufs.hir_variant_payload_link_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.import_visible_type_count),
        buffer_id(&bufs.hir_variant_payload_rank_a.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.import_visible_value_count),
        buffer_id(&bufs.hir_variant_payload_rank_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.import_visible_type_prefix),
        buffer_id(&bufs.hir_variant_payload_owner_a.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.import_visible_value_prefix),
        buffer_id(&bufs.hir_variant_payload_owner_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.resolved_type_decl),
        buffer_id(&lexer_bufs.tok_types.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.resolved_value_decl),
        buffer_id(&lexer_bufs.flags_packed.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.resolved_type_status),
        buffer_id(&lexer_bufs.s_all_final.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.resolved_value_status),
        buffer_id(&lexer_bufs.s_keep_final.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.member_result_ref_payload),
        buffer_id(&bufs.hir_call_arg_owner_a.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.member_result_field_ordinal),
        buffer_id(&bufs.hir_call_arg_owner_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.struct_init_field_expected_ref_tag),
        buffer_id(&bufs.hir_call_arg_link_a.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.struct_init_field_expected_ref_payload),
        buffer_id(&bufs.hir_call_arg_link_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.struct_init_field_context_instance),
        buffer_id(&bufs.hir_call_arg_rank_a.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.struct_init_field_ordinal),
        buffer_id(&bufs.hir_call_arg_rank_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.path_start),
        buffer_id(&lexer_bufs.end_positions.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.path_len),
        buffer_id(&lexer_bufs.types_compact.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.path_segment_count),
        buffer_id(&lexer_bufs.all_index_compact.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.path_segment_base),
        buffer_id(&bufs.sc_offsets.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.path_segment_name_id),
        buffer_id(&bufs.emit_offsets.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.path_segment_token),
        buffer_id(&bufs.pack_sc_prefix_a.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.path_owner_hir),
        buffer_id(&bufs.pack_sc_prefix_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.path_owner_token),
        buffer_id(&bufs.pack_emit_prefix_a.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.path_owner_module_id),
        buffer_id(&bufs.pack_emit_prefix_b.buffer)
    );
    assert_eq!(
        buffer_id(typecheck_scratch.path_kind),
        buffer_id(&bufs.hir_list_rank_flag.buffer)
    );

    let typecheck_hir_inputs = [
        &lexer_bufs.in_bytes.buffer,
        &lexer_bufs.tokens_out.buffer,
        &lexer_bufs.token_count.buffer,
        &lexer_bufs.token_file_id.buffer,
        &bufs.hir_kind.buffer,
        &bufs.hir_token_pos.buffer,
        &bufs.hir_token_end.buffer,
        &bufs.hir_token_file_id.buffer,
        &bufs.ll1_status.buffer,
        &bufs.node_kind.buffer,
        &bufs.parent.buffer,
        &bufs.first_child.buffer,
        &bufs.next_sibling.buffer,
        &bufs.subtree_end.buffer,
        &bufs.hir_type_path_leaf_node.buffer,
        &bufs.hir_type_arg_start.buffer,
        &bufs.hir_type_arg_count.buffer,
        &bufs.hir_type_arg_next.buffer,
        &bufs.hir_type_alias_target_node.buffer,
        &bufs.hir_fn_return_type_node.buffer,
    ];
    let typecheck_record_bytes = bufs.n_tokens.saturating_sub(2).max(1).saturating_mul(4);
    assert_distinct_from(typecheck_scratch.fn_entrypoint_tag, &typecheck_hir_inputs);
    assert_distinct_from(typecheck_scratch.type_expr_ref_tag, &typecheck_hir_inputs);
    assert_distinct_from(
        typecheck_scratch.type_expr_ref_payload,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(
        typecheck_scratch.type_generic_param_slot_by_token,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(
        typecheck_scratch.type_const_param_slot_by_token,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(typecheck_scratch.record_family_flag, &typecheck_hir_inputs);
    assert_distinct_from(
        typecheck_scratch.module_record_prefix,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(
        typecheck_scratch.record_scan_local_prefix,
        &typecheck_hir_inputs,
    );
    for scratch in [
        typecheck_scratch.module_path_key_radix_block_histogram,
        typecheck_scratch.module_path_key_radix_block_bucket_prefix,
        typecheck_scratch.decl_module_file_id,
        typecheck_scratch.decl_module_id,
        typecheck_scratch.decl_name_id,
        typecheck_scratch.decl_namespace,
        typecheck_scratch.decl_visibility,
        typecheck_scratch.decl_token_start,
        typecheck_scratch.decl_token_end,
        typecheck_scratch.decl_key_to_decl_id,
        typecheck_scratch.decl_key_order_tmp,
        typecheck_scratch.decl_status,
    ] {
        assert_distinct_from(scratch, &typecheck_hir_inputs);
        assert!(scratch.size() >= typecheck_record_bytes as u64);
    }
    assert_distinct_from(
        typecheck_scratch.path_id_by_owner_hir,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(
        typecheck_scratch.type_decl_generic_param_count,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(
        typecheck_scratch.type_decl_generic_param_count_by_node,
        &typecheck_hir_inputs,
    );
    for scratch in [
        typecheck_scratch.call_param_count,
        typecheck_scratch.call_arg_record,
        typecheck_scratch.function_lookup_key,
        typecheck_scratch.function_lookup_fn,
    ] {
        assert_distinct_from(scratch, &typecheck_hir_inputs);
    }
    let call_workspace_ids = [
        buffer_id(typecheck_scratch.call_param_count),
        buffer_id(typecheck_scratch.call_arg_record),
        buffer_id(typecheck_scratch.function_lookup_key),
        buffer_id(typecheck_scratch.function_lookup_fn),
    ];
    for i in 0..call_workspace_ids.len() {
        for j in i + 1..call_workspace_ids.len() {
            assert_ne!(call_workspace_ids[i], call_workspace_ids[j]);
        }
    }
    assert_distinct_from(
        typecheck_scratch.type_instance_head_token,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(
        typecheck_scratch.type_instance_arg_start,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(
        typecheck_scratch.type_instance_arg_count,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(
        typecheck_scratch.type_instance_arg_ref_payload,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(
        typecheck_scratch.type_instance_arg_ref_tag,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(
        typecheck_scratch.type_instance_elem_ref_tag,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(
        typecheck_scratch.type_instance_elem_ref_payload,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(
        typecheck_scratch.decl_value_key_to_decl_id,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(
        typecheck_scratch.decl_type_key_to_decl_id,
        &typecheck_hir_inputs,
    );
    for scratch in [
        typecheck_scratch.method_decl_module_id,
        typecheck_scratch.method_decl_impl_node,
        typecheck_scratch.method_decl_name_token,
        typecheck_scratch.method_decl_name_id,
        typecheck_scratch.method_decl_param_offset,
        typecheck_scratch.method_decl_receiver_mode,
        typecheck_scratch.method_decl_visibility,
        typecheck_scratch.method_key_to_fn_token,
        typecheck_scratch.method_key_status,
        typecheck_scratch.method_key_radix_block_histogram,
        typecheck_scratch.method_key_radix_block_bucket_prefix,
        typecheck_scratch.method_call_receiver_ref_tag,
        typecheck_scratch.method_call_receiver_ref_payload,
        typecheck_scratch.method_call_name_id,
        typecheck_scratch.method_call_site_module_id,
    ] {
        assert_distinct_from(scratch, &typecheck_hir_inputs);
    }
    let method_clear_scratch_ids = [
        buffer_id(typecheck_scratch.method_decl_module_id),
        buffer_id(typecheck_scratch.method_decl_impl_node),
        buffer_id(typecheck_scratch.method_decl_name_token),
        buffer_id(typecheck_scratch.method_decl_name_id),
        buffer_id(typecheck_scratch.method_decl_param_offset),
        buffer_id(typecheck_scratch.method_decl_receiver_mode),
        buffer_id(typecheck_scratch.method_decl_visibility),
        buffer_id(typecheck_scratch.method_key_to_fn_token),
        buffer_id(typecheck_scratch.method_key_status),
        buffer_id(typecheck_scratch.method_key_radix_block_histogram),
        buffer_id(typecheck_scratch.method_key_radix_block_bucket_prefix),
        buffer_id(typecheck_scratch.method_call_receiver_ref_tag),
        buffer_id(typecheck_scratch.method_call_receiver_ref_payload),
        buffer_id(typecheck_scratch.method_call_name_id),
        buffer_id(typecheck_scratch.method_call_site_module_id),
    ];
    for i in 0..method_clear_scratch_ids.len() {
        for j in i + 1..method_clear_scratch_ids.len() {
            assert_ne!(method_clear_scratch_ids[i], method_clear_scratch_ids[j]);
        }
    }
    assert_distinct_from(
        typecheck_scratch.import_visible_type_count,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(
        typecheck_scratch.import_visible_value_count,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(
        typecheck_scratch.import_visible_type_prefix,
        &typecheck_hir_inputs,
    );
    assert_distinct_from(
        typecheck_scratch.import_visible_value_prefix,
        &typecheck_hir_inputs,
    );
    for scratch in [
        typecheck_scratch.resolved_type_decl,
        typecheck_scratch.resolved_value_decl,
        typecheck_scratch.resolved_type_status,
        typecheck_scratch.resolved_value_status,
        typecheck_scratch.member_result_ref_payload,
        typecheck_scratch.member_result_field_ordinal,
        typecheck_scratch.struct_init_field_expected_ref_tag,
        typecheck_scratch.struct_init_field_expected_ref_payload,
        typecheck_scratch.struct_init_field_context_instance,
        typecheck_scratch.struct_init_field_ordinal,
        typecheck_scratch.path_start,
        typecheck_scratch.path_len,
        typecheck_scratch.path_segment_count,
        typecheck_scratch.path_segment_base,
        typecheck_scratch.path_segment_name_id,
        typecheck_scratch.path_segment_token,
        typecheck_scratch.path_owner_hir,
        typecheck_scratch.path_owner_token,
        typecheck_scratch.path_owner_module_id,
        typecheck_scratch.path_kind,
    ] {
        assert_distinct_from(scratch, &typecheck_hir_inputs);
        assert!(scratch.size() >= typecheck_record_bytes as u64);
    }
    assert!(
        bufs.hir_variant_rank_a.byte_size
            >= (bufs.n_tokens as usize)
                .saturating_mul(gpu_type_checker::TYPE_INSTANCE_ARG_REF_STRIDE)
                .saturating_mul(4)
    );
    assert!(
        bufs.hir_variant_payload_link_a.byte_size
            >= (bufs.n_tokens as usize)
                .saturating_mul(gpu_type_checker::TYPE_INSTANCE_ARG_REF_STRIDE)
                .saturating_mul(4)
    );
    for scratch in [
        typecheck_scratch.type_expr_ref_tag,
        typecheck_scratch.type_expr_ref_payload,
        typecheck_scratch.type_generic_param_slot_by_token,
        typecheck_scratch.type_const_param_slot_by_token,
        typecheck_scratch.call_param_count,
        typecheck_scratch.call_param_type,
        typecheck_scratch.method_decl_module_id,
        typecheck_scratch.method_decl_impl_node,
        typecheck_scratch.method_decl_name_id,
        typecheck_scratch.method_decl_param_offset,
        typecheck_scratch.method_decl_receiver_mode,
        typecheck_scratch.method_decl_visibility,
        typecheck_scratch.method_key_to_fn_token,
        typecheck_scratch.method_key_status,
        typecheck_scratch.method_key_radix_block_histogram,
        typecheck_scratch.method_key_radix_block_bucket_prefix,
        typecheck_scratch.method_call_receiver_ref_tag,
        typecheck_scratch.method_call_receiver_ref_payload,
        typecheck_scratch.method_call_name_id,
        typecheck_scratch.method_call_site_module_id,
        typecheck_scratch.type_instance_head_token,
        typecheck_scratch.type_instance_arg_start,
        typecheck_scratch.type_instance_arg_count,
        typecheck_scratch.type_instance_elem_ref_tag,
        typecheck_scratch.type_instance_elem_ref_payload,
        typecheck_scratch.type_decl_generic_param_count,
        typecheck_scratch.type_decl_generic_param_count_by_node,
        typecheck_scratch.type_instance_arg_ref_tag,
        typecheck_scratch.type_instance_arg_ref_payload,
        typecheck_scratch.decl_type_key_to_decl_id,
        typecheck_scratch.decl_value_key_to_decl_id,
        typecheck_scratch.import_visible_type_count,
        typecheck_scratch.import_visible_value_count,
        typecheck_scratch.import_visible_type_prefix,
        typecheck_scratch.import_visible_value_prefix,
    ] {
        assert!(scratch.size() >= (bufs.n_tokens as u64).saturating_mul(4));
    }
    assert!(
        typecheck_scratch.call_arg_record.size()
            >= (bufs.n_tokens as u64).saturating_mul(4).saturating_mul(4)
    );
    for scratch in [
        typecheck_scratch.function_lookup_key,
        typecheck_scratch.function_lookup_fn,
    ] {
        assert!(scratch.size() >= (bufs.n_tokens as u64).saturating_mul(2).saturating_mul(4));
    }

    let dummy_codegen = scratch_u32_buffer("test.codegen.dummy", 1);
    let codegen_fn_entrypoint_tag = scratch_u32_buffer(
        "test.codegen.fn_entrypoint_tag",
        bufs.tree_capacity as usize,
    );
    let codegen = gpu_type_checker::GpuX86CodegenBuffers {
        enclosing_fn: &dummy_codegen,
        visible_decl: &dummy_codegen,
        visible_type: &dummy_codegen,
        path_count_out: &dummy_codegen,
        path_id_by_owner_hir: &dummy_codegen,
        resolved_value_decl: &dummy_codegen,
        resolved_value_status: &dummy_codegen,
        decl_count_out: &dummy_codegen,
        decl_kind: &dummy_codegen,
        decl_name_token: &dummy_codegen,
        decl_id_by_name_token: &dummy_codegen,
        decl_hir_node: &dummy_codegen,
        decl_parent_type_decl: &dummy_codegen,
        decl_type_ref_tag: &dummy_codegen,
        decl_type_ref_payload: &dummy_codegen,
        call_fn_index: &dummy_codegen,
        call_intrinsic_tag: &dummy_codegen,
        fn_entrypoint_tag: &codegen_fn_entrypoint_tag,
        call_return_type: &dummy_codegen,
        call_return_type_token: &dummy_codegen,
        call_param_type: &dummy_codegen,
        method_decl_receiver_ref_tag: &dummy_codegen,
        method_decl_receiver_ref_payload: &dummy_codegen,
        method_decl_param_offset: &dummy_codegen,
        type_instance_kind: &dummy_codegen,
        type_instance_decl_token: &dummy_codegen,
        type_instance_len_kind: &dummy_codegen,
        type_instance_len_payload: &dummy_codegen,
        member_result_field_ordinal: &dummy_codegen,
        struct_init_field_ordinal: &dummy_codegen,
        struct_init_field_ordinal_by_node: &dummy_codegen,
    };

    let x86_parse = OwnedX86ParserBuffers::from_parser_buffers(&bufs);
    let x86_scratch = GpuCompiler::x86_external_scratch_from_frontend_and_codegen_buffers(
        &x86_parse,
        codegen,
        8,
        x86::X86FeatureSummary::default(),
    );
    assert_eq!(x86_scratch.borrowed_buffer_count(), 21);
    assert!(x86_scratch.node_inst_scan_local_prefix.is_none());
    assert_eq!(
        buffer_id(x86_scratch.call_record.expect("no-call scratch")),
        buffer_id(&bufs.hir_param_record.buffer)
    );
    assert!(x86_scratch.call_type_record.is_none());
    assert_eq!(
        buffer_id(
            x86_scratch
                .node_inst_count_info
                .expect("count-info scratch")
        ),
        buffer_id(&codegen_fn_entrypoint_tag)
    );
    assert_eq!(
        buffer_id(
            x86_scratch
                .node_inst_count_payload
                .expect("count-payload scratch")
        ),
        buffer_id(&bufs.hir_type_arg_rank_a.buffer)
    );
    assert_eq!(
        buffer_id(
            x86_scratch
                .node_inst_subtree_bound_start
                .expect("subtree-start scratch")
        ),
        buffer_id(&bufs.hir_type_arg_rank_a.buffer)
    );
    assert_eq!(
        buffer_id(
            x86_scratch
                .node_inst_subtree_bound_end
                .expect("subtree-end scratch")
        ),
        buffer_id(&bufs.hir_array_element_previous.buffer)
    );
    assert!(x86_scratch.node_inst_gen_node_record.is_none());
    for scratch in [
        x86_scratch.node_inst_count_info.expect("count-info"),
        x86_scratch.node_inst_count_payload.expect("count-payload"),
        x86_scratch
            .node_inst_subtree_bound_start
            .expect("subtree-start"),
        x86_scratch
            .node_inst_subtree_bound_end
            .expect("subtree-end"),
    ] {
        assert!(scratch.size() >= (bufs.tree_capacity as u64).saturating_mul(4));
    }
    assert_eq!(
        buffer_id(
            x86_scratch
                .node_inst_range_start
                .expect("range start scratch")
        ),
        buffer_id(&bufs.hir_type_path_leaf_link_a.buffer)
    );
    assert_eq!(
        buffer_id(
            x86_scratch
                .node_inst_range_info
                .expect("range info scratch")
        ),
        buffer_id(&bufs.hir_type_path_leaf_link_b.buffer)
    );
    assert!(x86_scratch.decl_layout_record.is_some());
    assert!(x86_scratch.const_value_record.is_some());
    assert!(x86_scratch.param_reg_record.is_some());
    assert!(x86_scratch.local_literal_record.is_some());
    let param_program_scratch = GpuCompiler::x86_external_scratch_from_frontend_and_codegen_buffers(
        &x86_parse,
        codegen,
        8,
        x86::X86FeatureSummary {
            param_count: 1,
            ..x86::X86FeatureSummary::default()
        },
    );
    assert!(param_program_scratch.call_record.is_none());
    assert!(param_program_scratch.call_type_record.is_none());
    assert!(
        bufs.hir_type_len_value.byte_size >= (bufs.tree_capacity as usize).saturating_add(1) * 4
    );
    assert_eq!(
        buffer_id(&bufs.hir_struct_field_type_node.buffer),
        buffer_id(&bufs.hir_struct_lit_field_value_node.buffer)
    );

    let x86_parser_inputs = [
        &bufs.parent.buffer,
        &bufs.first_child.buffer,
        &bufs.next_sibling.buffer,
        &bufs.subtree_end.buffer,
        &bufs.hir_kind.buffer,
        &bufs.hir_item_decl_token.buffer,
        &bufs.hir_item_name_token.buffer,
        &bufs.hir_token_pos.buffer,
        &bufs.hir_expr_record.buffer,
        &bufs.hir_expr_int_value.buffer,
        &bufs.hir_stmt_record.buffer,
        &bufs.hir_call_callee_node.buffer,
        &bufs.hir_call_arg_start.buffer,
        &bufs.hir_call_arg_end.buffer,
        &bufs.hir_call_arg_count.buffer,
        &bufs.hir_call_arg_parent_call.buffer,
        &bufs.hir_member_receiver_node.buffer,
        &bufs.hir_member_name_token.buffer,
        &bufs.hir_array_lit_first_element.buffer,
        &bufs.hir_array_lit_element_count.buffer,
        &bufs.hir_array_element_parent_lit.buffer,
        &bufs.hir_array_element_ordinal.buffer,
        &bufs.hir_array_element_next.buffer,
        &bufs.hir_variant_parent_enum.buffer,
        &bufs.hir_variant_ordinal.buffer,
        &bufs.hir_variant_payload_count.buffer,
        &bufs.hir_match_scrutinee_node.buffer,
        &bufs.hir_match_arm_start.buffer,
        &bufs.hir_match_arm_count.buffer,
        &bufs.hir_match_arm_next.buffer,
        &bufs.hir_match_arm_pattern_node.buffer,
        &bufs.hir_match_arm_payload_start.buffer,
        &bufs.hir_match_arm_payload_count.buffer,
        &bufs.hir_match_arm_result_node.buffer,
        &bufs.hir_struct_decl_field_count.buffer,
        &bufs.hir_struct_lit_field_parent_lit.buffer,
        &bufs.hir_struct_lit_field_start.buffer,
        &bufs.hir_struct_lit_field_count.buffer,
        &bufs.hir_struct_lit_field_value_node.buffer,
        &bufs.hir_struct_lit_field_next.buffer,
    ];

    for scratch in [
        x86_scratch.expr_resolved_final,
        x86_scratch.node_func,
        x86_scratch.func_owner_scan_local_prefix,
        x86_scratch.func_slot_by_node,
        x86_scratch.match_pattern_owner,
        x86_scratch.match_pattern_node_owner,
        x86_scratch.match_pattern_node_variant,
        x86_scratch.match_pattern_node_payload_decl,
        x86_scratch.match_pattern_first_use_node,
        x86_scratch.enclosing_let_node_a,
        x86_scratch.enclosing_let_node_b,
        x86_scratch.node_inst_same_end_link_a,
        x86_scratch.node_inst_same_end_link_b,
        x86_scratch.call_record,
        x86_scratch.call_type_record,
        x86_scratch.node_inst_count_info,
        x86_scratch.node_inst_count_payload,
        x86_scratch.node_inst_range_start,
        x86_scratch.node_inst_range_info,
        x86_scratch.node_inst_subtree_bound_start,
        x86_scratch.node_inst_subtree_bound_end,
        x86_scratch.node_inst_gen_node_record,
        x86_scratch.decl_layout_record,
        x86_scratch.const_value_record,
        x86_scratch.param_reg_record,
        x86_scratch.local_literal_record,
    ]
    .into_iter()
    .flatten()
    {
        assert_distinct_from(scratch, &x86_parser_inputs);
    }
}

#[test]
fn x86_only_compiler_does_not_initialize_wasm_backend() {
    let compiler = pollster::block_on(GpuCompiler::new_with_device_and_backends(
        device::global(),
        GpuCompilerBackends::x86_only(),
    ))
    .expect("initialize x86-only GPU compiler");

    assert!(
        compiler.wasm_generator.is_err(),
        "x86-only global compiler path must not initialize legacy WASM backend pipelines"
    );
    assert!(
        compiler.x86_generator.is_ok(),
        "x86-only global compiler path should initialize x86 backend pipelines"
    );
}

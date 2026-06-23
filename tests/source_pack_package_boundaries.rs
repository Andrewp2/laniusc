mod common;

use laniusc_compiler::{
    codegen::unit::{
        CodegenUnitLimits,
        SourcePackArtifactKind,
        SourcePackArtifactRef,
        SourcePackArtifactTarget,
        SourcePackJob,
        SourcePackJobBatchDependencyRange,
        SourcePackJobBatchLimits,
        SourcePackJobIndexRange,
        SourcePackJobPhase,
        SourcePackLibraryDependency,
        source_pack_artifact_key_for_output,
    },
    compiler::{
        ArtifactStore,
        CompileError,
        EntrySourceRoots,
        ExplicitSourceLibrary,
        ExplicitSourceLibraryPathDependencyStream,
        ExplicitSourceLibraryPaths,
        ExplicitSourcePack,
        ExplicitSourcePackPathManifest,
        FilesystemArtifactStore,
        GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        HierarchicalLinkArtifactStore,
        SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
        SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION,
        SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_PAGE_VERSION,
        SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_VERSION,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_VERSION,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_VERSION,
        SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
        SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE,
        SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
        SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
        SOURCE_PACK_LIBRARY_SCHEDULE_PAGE_VERSION,
        SOURCE_PACK_PATH_BUILD_MANIFEST_VERSION,
        SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_PAGE_VERSION,
        SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
        SourcePackBuildArtifactRefIndex,
        SourcePackBuildArtifactRefPage,
        SourcePackBuildJobBatchDependencyPage,
        SourcePackBuildJobBatchDependencyRangePage,
        SourcePackHierarchicalLinkExecutionIndex,
        SourcePackHierarchicalLinkExecutionInterfacePage,
        SourcePackHierarchicalLinkExecutionObjectPage,
        SourcePackHierarchicalLinkExecutionPage,
        SourcePackHierarchicalLinkExecutionPartialPage,
        SourcePackHierarchicalLinkGroupKind,
        SourcePackHierarchicalLinkGroupPage,
        SourcePackHierarchicalLinkPlanIndex,
        SourcePackLibraryPartitionIndex,
        SourcePackLibraryScheduleIndex,
        SourcePackLibrarySchedulePage,
        SourcePackLinkDescriptorSummary,
        SourcePackPathBuildManifest,
        SourcePackWorkQueueDependenciesPage,
        SourcePackWorkQueueItemKind,
        SourcePackWorkQueuePage,
        load_entry_path_manifest_with_source_root,
        load_entry_path_manifest_with_source_root_and_stdlib,
        load_entry_path_manifest_with_source_roots,
        load_entry_with_source_root,
        load_entry_with_source_root_and_stdlib,
        prepare_artifact_refs_chunk,
        prepare_artifact_shards_chunk,
        prepare_link_execution_chunk,
        prepare_link_leaf_groups_chunk,
        prepare_metadata_chunk_for_target,
    },
};

fn assert_source_pack_artifact_store_failed(err: CompileError, reason: &str) {
    let diagnostic = match err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => panic!("expected structured source-pack artifact-store diagnostic, got {other:?}"),
    };
    assert_eq!(diagnostic.code, "LNC0059");
    assert_eq!(diagnostic.message, "source-pack artifact store failed");
    assert!(
        diagnostic.primary_label.is_none(),
        "artifact-store errors should not invent a source span"
    );
    let rendered = diagnostic.render();
    assert!(
        rendered.contains(reason),
        "diagnostic should explain the artifact-store failure: {rendered}"
    );
    assert!(
        rendered.contains("canonical artifact identities"),
        "diagnostic should include the shared artifact-store contract: {rendered}"
    );
    assert!(
        !rendered.contains("frontend error:"),
        "diagnostic should not fall back to raw frontend display: {rendered}"
    );
}

#[test]
fn explicit_source_pack_library_ids_are_planning_boundaries_not_package_boundaries() {
    let pack = ExplicitSourcePack::from_libraries(vec![
        ExplicitSourceLibrary {
            library_id: 20,
            sources: vec!["module shared::api;\nfn app() -> i32 { return 20; }\n".into()],
            dependency_library_ids: vec![10],
        },
        ExplicitSourceLibrary {
            library_id: 10,
            sources: vec!["module shared::api;\nfn core() -> i32 { return 10; }\n".into()],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect("source-pack planning should not treat library ids as semantic package namespaces");

    assert_eq!(
        pack.library_ids,
        vec![20, 10],
        "source-pack construction should preserve caller source order instead of topologically rewriting inputs"
    );
    assert_eq!(pack.library_dependencies.len(), 1);
    assert_eq!(
        pack.library_dependencies[0],
        SourcePackLibraryDependency {
            library_id: 20,
            depends_on_library_id: 10,
        }
    );

    let schedule = pack.bounded_frontend_job_schedule(CodegenUnitLimits {
        max_source_bytes: 1024,
        max_source_files: 1,
    });
    let frontend_jobs = schedule
        .jobs
        .iter()
        .filter(|job| job.phase == SourcePackJobPhase::LibraryFrontend)
        .map(|job| (job.library_id, pack.source_slice_for_job(job).len()))
        .collect::<Vec<_>>();

    assert_eq!(frontend_jobs.len(), 2);
    assert!(frontend_jobs.contains(&(10, 1)));
    assert!(frontend_jobs.contains(&(20, 1)));
    let dependency_position = frontend_jobs
        .iter()
        .position(|(library_id, _)| *library_id == 10)
        .expect("dependency library should have a frontend job");
    let dependent_position = frontend_jobs
        .iter()
        .position(|(library_id, _)| *library_id == 20)
        .expect("dependent library should have a frontend job");
    assert!(
        dependency_position < dependent_position,
        "library frontend schedule should run dependencies before dependents: {frontend_jobs:?}"
    );
}

#[test]
fn source_pack_batch_dependencies_cover_split_frontend_library_dependencies() {
    let pack = ExplicitSourcePack::from_libraries(vec![
        ExplicitSourceLibrary {
            library_id: 10,
            sources: (0..3)
                .map(|index| {
                    format!("module core::part{index};\npub const VALUE: i32 = {index};\n")
                })
                .collect(),
            dependency_library_ids: Vec::new(),
        },
        ExplicitSourceLibrary {
            library_id: 20,
            sources: vec![
                "module app::main;\nimport core::part0;\nfn main() -> i32 { return 0; }\n".into(),
            ],
            dependency_library_ids: vec![10],
        },
    ])
    .expect("create explicit source pack with a split library dependency");

    let schedule = pack.bounded_frontend_job_schedule(CodegenUnitLimits {
        max_source_bytes: 1024,
        max_source_files: 1,
    });
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 1024,
        max_source_files_per_batch: 1,
    };
    let batches = schedule
        .try_execution_batches(batch_limits)
        .expect("split library dependency schedule should be acyclic");
    let batch_dependencies = schedule
        .try_batch_dependency_plan(&batches)
        .expect("split library dependency batches should be dependency-plannable");
    let batch_index_for_job = |job_index| {
        batches
            .batches
            .iter()
            .find(|batch| batch.job_indices.contains(&job_index))
            .map(|batch| batch.batch_index)
    };

    let mut expected_dependency_batches = schedule
        .jobs
        .iter()
        .filter(|job| job.phase == SourcePackJobPhase::LibraryFrontend && job.library_id == 10)
        .map(|job| {
            batch_index_for_job(job.job_index)
                .expect("each dependency frontend job should be assigned to a batch")
        })
        .collect::<Vec<_>>();
    expected_dependency_batches.sort_unstable();
    assert!(
        expected_dependency_batches.len() > 1,
        "test fixture should split the dependency library into multiple frontend batches"
    );

    let dependent_frontend_batch_index = schedule
        .jobs
        .iter()
        .find(|job| job.phase == SourcePackJobPhase::LibraryFrontend && job.library_id == 20)
        .and_then(|job| batch_index_for_job(job.job_index))
        .expect("dependent library frontend job should be assigned to a batch");
    let dependent_batch_dependencies = batch_dependencies
        .batches
        .iter()
        .find(|dependency| dependency.batch_index == dependent_frontend_batch_index)
        .expect("dependent frontend batch should have dependency metadata");
    let mut actual_dependency_batches = dependent_batch_dependencies
        .dependency_batch_indices
        .clone();
    for range in &dependent_batch_dependencies.dependency_batch_ranges {
        actual_dependency_batches.extend(
            range
                .iter()
                .expect("dependency batch range should not overflow"),
        );
    }
    actual_dependency_batches.sort_unstable();
    actual_dependency_batches.dedup();

    assert_eq!(
        actual_dependency_batches, expected_dependency_batches,
        "coarse batch scheduling must not make a dependent library frontend ready before every split dependency frontend batch has completed"
    );
}

#[test]
fn explicit_source_pack_rejects_duplicate_library_dependency_edges() {
    let err = ExplicitSourcePack::from_libraries(vec![
        ExplicitSourceLibrary {
            library_id: 20,
            sources: vec!["module app::main;\nfn main() { return 0; }\n".into()],
            dependency_library_ids: vec![10, 10],
        },
        ExplicitSourceLibrary {
            library_id: 10,
            sources: vec!["module core::api;\npub const VALUE: i32 = 1;\n".into()],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect_err("duplicate library dependencies should not enter source-pack planning metadata");
    assert_duplicate_library_dependency_error(&err, 20, 10);

    let path_manifest_err = ExplicitSourcePackPathManifest::from_libraries(vec![
        ExplicitSourceLibraryPaths {
            library_id: 20,
            paths: vec![std::path::PathBuf::from("app/main.lani")],
            dependency_library_ids: vec![10, 10],
        },
        ExplicitSourceLibraryPaths {
            library_id: 10,
            paths: vec![std::path::PathBuf::from("core/api.lani")],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect_err(
        "duplicate path-manifest dependencies should fail before source file metadata is read",
    );
    assert_duplicate_library_dependency_error(&path_manifest_err, 20, 10);

    let manual_dependency_err = ExplicitSourcePack::new(
        vec![
            "module app::main;\nfn main() { return 0; }\n".into(),
            "module core::api;\npub const VALUE: i32 = 1;\n".into(),
        ],
        vec![20, 10],
    )
    .expect("explicit source pack should accept two planning libraries")
    .with_library_dependencies(vec![
        SourcePackLibraryDependency {
            library_id: 20,
            depends_on_library_id: 10,
        },
        SourcePackLibraryDependency {
            library_id: 20,
            depends_on_library_id: 10,
        },
    ])
    .expect_err("manual source-pack dependency metadata should reject duplicate edges");
    assert_duplicate_library_dependency_error(&manual_dependency_err, 20, 10);
}

#[test]
fn source_pack_schedule_pages_reject_noncanonical_dependency_library_order() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "schedule_dependency_order",
        None,
    );
    let page = SourcePackLibrarySchedulePage {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_PAGE_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        partition_index: 2,
        library_id: 30,
        dependency_library_ids: vec![20, 10],
        frontend_job_index: 0,
        first_frontend_unit_index: 0,
        frontend_job_count: 1,
        first_codegen_unit_index: 0,
        first_codegen_job_index: 1,
        codegen_job_count: 1,
        link_job_index: 2,
        frontend_job: SourcePackJob {
            job_index: 0,
            phase: SourcePackJobPhase::LibraryFrontend,
            phase_unit_index: 0,
            library_job_index: None,
            library_id: 30,
            first_source_index: 0,
            source_file_count: 1,
            source_bytes: 32,
            source_lines: 2,
            oversized_source_file: false,
            dependency_job_indices: Vec::new(),
        },
        frontend_jobs: Vec::new(),
        codegen_jobs: Vec::new(),
    };

    let err = FilesystemArtifactStore::new(&root)
        .store_library_schedule_page(&page)
        .expect_err("persisted schedule pages must keep dependency libraries canonical");
    let message = format!("{err:?}");
    assert!(
        message.contains("dependency library ids")
            && message.contains("strictly ascending")
            && message.contains("20")
            && message.contains("10"),
        "expected noncanonical schedule dependency order error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove schedule dependency-order temp root");
}

#[test]
fn source_pack_path_manifest_rejects_frontend_source_range_overlap() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "frontend_ranges", None);
    let app_root = root.join("app");
    std::fs::create_dir_all(&app_root).expect("create app source directory");
    let main_path = app_root.join("main.lani");
    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &main_path,
        "module app::main;\nimport app::helper;\nfn main() { return 0; }\n",
    )
    .expect("write package entry source");
    std::fs::write(
        &helper_path,
        "module app::helper;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write package helper source");

    let source_pack =
        ExplicitSourcePackPathManifest::from_libraries(vec![ExplicitSourceLibraryPaths {
            library_id: 1,
            paths: vec![main_path, helper_path],
            dependency_library_ids: Vec::new(),
        }])
        .expect("create explicit package path manifest");
    let limits = CodegenUnitLimits {
        max_source_bytes: 1024,
        max_source_files: 1,
    };
    let batch_limits = SourcePackJobBatchLimits::default();
    let artifacts = source_pack
        .bounded_frontend_build_plan(limits)
        .retained_build_artifact_manifest(batch_limits);
    let mut manifest = SourcePackPathBuildManifest {
        version: SOURCE_PACK_PATH_BUILD_MANIFEST_VERSION,
        source_file_count: source_pack.files.len(),
        source_byte_count: source_pack.files.iter().map(|file| file.byte_len).sum(),
        source_line_count: source_pack
            .files
            .iter()
            .map(|file| file.line_count.unwrap_or(0))
            .sum(),
        source_files: source_pack.files.clone(),
        library_dependencies: source_pack.library_dependencies.clone(),
        limits,
        batch_limits,
        artifacts,
    };
    manifest
        .validate_contract()
        .expect("generated path build manifest should cover every source once");

    let duplicated_frontend_job = manifest
        .artifacts
        .job_schedule
        .jobs
        .iter_mut()
        .find(|job| job.phase == SourcePackJobPhase::LibraryFrontend && job.first_source_index == 1)
        .expect("bounded frontend schedule should split the two package sources");
    let duplicated_job_index = duplicated_frontend_job.job_index;
    duplicated_frontend_job.first_source_index = 0;

    let err = manifest
        .validate_contract()
        .expect_err("path build manifests must reject duplicate frontend source coverage");
    let message = format!("{err:?}");
    assert!(
        message.contains("library frontend job source ranges overlap")
            && message.contains("source file 0")
            && message.contains(&format!("job {duplicated_job_index}")),
        "expected frontend source coverage invariant error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove frontend range temp root");
}

#[test]
fn source_pack_artifact_store_rejects_cross_kind_artifact_identities() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "artifact_store_kind_identity",
        None,
    );
    let mut store = FilesystemArtifactStore::new(&root);

    let forged_object_ref = SourcePackArtifactRef {
        artifact_index: 2,
        key: "library-interface/lib-0/job-2/src-0-1".into(),
        producing_job_index: 2,
        kind: SourcePackArtifactKind::CodegenObject,
    };
    let err = store
        .store_codegen_object(&forged_object_ref, b"object".to_vec())
        .expect_err("codegen objects must not publish under interface artifact keys");
    assert_source_pack_artifact_store_failed(err, "does not identify a CodegenObject artifact");
    assert!(
        !store
            .path_for_key(&forged_object_ref.key)
            .expect("resolve forged object key")
            .exists(),
        "rejected cross-kind object artifact must not be persisted"
    );

    let forged_producer_ref = SourcePackArtifactRef {
        artifact_index: 2,
        key: "codegen-object/lib-0/job-3/src-0-1".into(),
        producing_job_index: 2,
        kind: SourcePackArtifactKind::CodegenObject,
    };
    let err = store
        .store_codegen_object(&forged_producer_ref, b"object".to_vec())
        .expect_err("artifact refs must agree with the producer encoded by their key");
    assert_source_pack_artifact_store_failed(err, "records producer job 3");
    assert!(
        !store
            .path_for_key(&forged_producer_ref.key)
            .expect("resolve forged producer key")
            .exists(),
        "rejected producer-job artifact identity must not be persisted"
    );

    let forged_artifact_index_ref = SourcePackArtifactRef {
        artifact_index: 42,
        key: "codegen-object/lib-0/job-3/src-0-1".into(),
        producing_job_index: 3,
        kind: SourcePackArtifactKind::CodegenObject,
    };
    let err = store
        .store_codegen_object(&forged_artifact_index_ref, b"object".to_vec())
        .expect_err("artifact refs must use the dense producer job as artifact index");
    assert_source_pack_artifact_store_failed(err, "dense producer job as artifact index");
    assert!(
        !store
            .path_for_key(&forged_artifact_index_ref.key)
            .expect("resolve forged artifact-index key")
            .exists(),
        "rejected artifact-index identity must not be persisted"
    );

    let object_ref = SourcePackArtifactRef {
        artifact_index: 2,
        key: "codegen-object/lib-0/job-2/src-0-1".into(),
        producing_job_index: 2,
        kind: SourcePackArtifactKind::CodegenObject,
    };
    store
        .store_codegen_object(&object_ref, b"object".to_vec())
        .expect("valid codegen object artifact should persist");

    let x86_object_ref = SourcePackArtifactRef {
        artifact_index: 4,
        key: "x86_64/codegen-object/lib-0/job-4/src-0-1".into(),
        producing_job_index: 4,
        kind: SourcePackArtifactKind::CodegenObject,
    };
    store
        .store_codegen_object(&x86_object_ref, b"x86 object".to_vec())
        .expect("valid x86-prefixed codegen object artifact should persist");
    assert!(
        store
            .path_for_key(&x86_object_ref.key)
            .expect("resolve x86 object key")
            .exists(),
        "accepted x86-prefixed codegen object artifact must be persisted"
    );

    let err = store
        .load_partial_link_output(&object_ref.key)
        .expect_err("partial-link loads must reject object artifact keys");
    assert_source_pack_artifact_store_failed(err, "does not identify a partial-link artifact");

    std::fs::remove_dir_all(&root).expect("remove artifact store kind identity temp root");
}

#[test]
fn source_pack_artifact_store_rejects_malformed_partial_link_keys() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "partial_link_key_identity",
        None,
    );
    let mut store = FilesystemArtifactStore::new(&root);

    let malformed_key = "partial-link/group-00000000/not-job-00000002";
    let err = store
        .store_partial_link_output(malformed_key, b"partial".to_vec())
        .expect_err("partial-link artifacts must use canonical group/job identities");
    assert_source_pack_artifact_store_failed(err, "partial-link producer job");
    assert!(
        !store
            .path_for_key(malformed_key)
            .expect("resolve malformed partial-link key path")
            .exists(),
        "rejected partial-link artifact must not be persisted"
    );

    let noncanonical_key = "wasm/partial-link/group-000000001/job-000000002";
    let err = store
        .load_partial_link_output(noncanonical_key)
        .expect_err("partial-link loads should reject widened keys with leading zeroes");
    assert_source_pack_artifact_store_failed(err, "non-canonical partial-link group index");

    let canonical_key = "wasm/partial-link/group-00000000/job-00000002";
    store
        .store_partial_link_output(canonical_key, b"partial".to_vec())
        .expect("canonical partial-link artifacts should still persist");
    assert_eq!(
        store
            .load_partial_link_output(canonical_key)
            .expect("canonical partial-link artifact should load"),
        b"partial".to_vec()
    );

    std::fs::remove_dir_all(&root).expect("remove partial-link key identity temp root");
}

#[test]
fn source_pack_artifact_store_rejects_malformed_hierarchical_linked_output_keys() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "linked_output_key_store_identity",
        None,
    );
    let mut store = FilesystemArtifactStore::new(&root);

    let malformed_key = "linked-output/job-2/not-src-0-1";
    let err = store
        .store_hierarchical_linked_output(malformed_key, b"linked".to_vec())
        .expect_err("hierarchical linked outputs must include canonical source ranges");
    assert_source_pack_artifact_store_failed(err, "source range");
    assert!(
        !store
            .path_for_key(malformed_key)
            .expect("resolve malformed linked-output key path")
            .exists(),
        "rejected linked-output artifact must not be persisted"
    );

    let noncanonical_key = "wasm/linked-output/job-00000002/src-0-1";
    let err = store
        .store_hierarchical_linked_output(noncanonical_key, b"linked".to_vec())
        .expect_err("hierarchical linked outputs must use canonical producer-job fields");
    assert_source_pack_artifact_store_failed(err, "non-canonical producer job");
    assert!(
        !store
            .path_for_key(noncanonical_key)
            .expect("resolve noncanonical linked-output key path")
            .exists(),
        "rejected noncanonical linked-output artifact must not be persisted"
    );

    let canonical_key = "wasm/linked-output/job-2/src-0-1";
    store
        .store_hierarchical_linked_output(canonical_key, b"linked".to_vec())
        .expect("canonical hierarchical linked outputs should still persist");
    assert!(
        store
            .path_for_key(canonical_key)
            .expect("resolve canonical linked-output key")
            .exists(),
        "accepted linked-output artifact must be persisted"
    );

    std::fs::remove_dir_all(&root).expect("remove linked-output key identity temp root");
}

#[test]
fn source_pack_artifact_manifest_rejects_link_records_that_omit_codegen_object() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "link_inputs", None);
    let pack = ExplicitSourcePack::from_libraries(vec![ExplicitSourceLibrary {
        library_id: 1,
        sources: vec!["module app::main;\nfn main() { return 0; }\n".into()],
        dependency_library_ids: Vec::new(),
    }])
    .expect("create explicit package source pack");
    let manifest = pack
        .bounded_frontend_build_plan(CodegenUnitLimits {
            max_source_bytes: 1024,
            max_source_files: 1,
        })
        .retained_build_artifact_manifest(SourcePackJobBatchLimits::default());
    FilesystemArtifactStore::new(root.join("valid"))
        .store_build_artifact_manifest(&manifest)
        .expect("generated retained artifact manifest should satisfy link-input coverage");

    let link_job_index = manifest
        .job_schedule
        .jobs
        .iter()
        .find(|job| job.phase == SourcePackJobPhase::Link)
        .expect("source-pack plan should include a link job")
        .job_index;
    let omitted_object_artifact_index = manifest
        .artifacts
        .artifacts
        .iter()
        .find(|artifact| artifact.kind == SourcePackArtifactKind::CodegenObject)
        .expect("source-pack plan should include a codegen object")
        .artifact_index;

    let mut tampered = manifest.clone();
    let link_job_manifest = &mut tampered.job_artifacts.jobs[link_job_index];
    link_job_manifest.input_object_count = 0;
    link_job_manifest.input_object_page_count = 0;
    link_job_manifest.input_object_artifact_ranges.clear();
    link_job_manifest.input_objects.clear();

    let link_job_io = &mut tampered.job_artifact_io.jobs[link_job_index];
    link_job_io.input_object_artifact_count = 0;
    link_job_io.input_object_artifact_ranges.clear();
    link_job_io.input_object_artifact_indices.clear();

    let object_use = &mut tampered.artifact_uses.uses[omitted_object_artifact_index];
    object_use
        .consumer_job_indices
        .retain(|&consumer_job_index| consumer_job_index != link_job_index);
    object_use.last_consumer_job_index = object_use.consumer_job_indices.iter().copied().max();

    tampered.link_object_batch_count = 0;
    tampered.link_object_batches.batches.clear();

    let err = FilesystemArtifactStore::new(root.join("tampered"))
        .store_build_artifact_manifest(&tampered)
        .expect_err("persisted link records must cover every retained codegen object");
    let message = format!("{err:?}");
    assert!(
        message.contains("link job input objects")
            && message.contains("do not cover all codegen object artifacts")
            && message.contains(&format!("missing [{omitted_object_artifact_index}]")),
        "expected omitted codegen object link-input coverage error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove link-input manifest temp root");
}

#[test]
fn source_pack_artifact_manifest_rejects_partial_explicit_link_dependencies() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_partial_dependencies",
        None,
    );
    let pack = ExplicitSourcePack::from_libraries(vec![ExplicitSourceLibrary {
        library_id: 1,
        sources: vec![
            "module app::main;\nfn main() { return 0; }\n".into(),
            "module app::helper;\npub const VALUE: i32 = 1;\n".into(),
        ],
        dependency_library_ids: Vec::new(),
    }])
    .expect("create explicit package source pack");
    let manifest = pack
        .bounded_frontend_build_plan(CodegenUnitLimits {
            max_source_bytes: 1024,
            max_source_files: 1,
        })
        .retained_build_artifact_manifest(SourcePackJobBatchLimits::default());
    FilesystemArtifactStore::new(root.join("valid"))
        .store_build_artifact_manifest(&manifest)
        .expect("generated retained artifact manifest should keep link readiness implicit");

    let codegen_job_indices = manifest
        .job_schedule
        .jobs
        .iter()
        .filter(|job| job.phase == SourcePackJobPhase::Codegen)
        .map(|job| job.job_index)
        .collect::<Vec<_>>();
    assert!(
        codegen_job_indices.len() >= 2,
        "test fixture should split package codegen into multiple object producers"
    );
    let link_job_index = manifest
        .job_schedule
        .jobs
        .iter()
        .find(|job| job.phase == SourcePackJobPhase::Link)
        .expect("source-pack plan should include a link job")
        .job_index;

    let mut tampered = manifest.clone();
    tampered.job_schedule.jobs[link_job_index].dependency_job_indices =
        vec![codegen_job_indices[0]];
    if let Some(link_dependency_ranges) = tampered
        .job_schedule
        .dependency_job_ranges_by_job_index
        .get_mut(link_job_index)
    {
        link_dependency_ranges.clear();
    }

    let err = FilesystemArtifactStore::new(root.join("tampered"))
        .store_build_artifact_manifest(&tampered)
        .expect_err("explicit link dependencies must cover every codegen object producer");
    let message = format!("{err:?}");
    assert!(
        message.contains("link job")
            && message.contains("explicit dependencies")
            && message.contains("codegen object producer jobs")
            && message.contains(&format!("missing [{}]", codegen_job_indices[1])),
        "expected partial explicit link dependency error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove partial-link-dependency manifest temp root");
}

#[test]
fn source_pack_artifact_manifest_rejects_non_dependency_interface_inputs() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "non_dependency_interface_input",
        None,
    );
    let pack = ExplicitSourcePack::from_libraries(vec![
        ExplicitSourceLibrary {
            library_id: 10,
            sources: vec!["module dep;\npub const VALUE: i32 = 1;\n".into()],
            dependency_library_ids: Vec::new(),
        },
        ExplicitSourceLibrary {
            library_id: 20,
            sources: vec!["module app;\nfn main() { return 0; }\n".into()],
            dependency_library_ids: Vec::new(),
        },
    ])
    .expect("create explicit source pack with independent libraries");
    let manifest = pack
        .bounded_frontend_build_plan(CodegenUnitLimits {
            max_source_bytes: 1024,
            max_source_files: 1,
        })
        .retained_build_artifact_manifest(SourcePackJobBatchLimits::default());
    FilesystemArtifactStore::new(root.join("valid"))
        .store_build_artifact_manifest(&manifest)
        .expect(
            "generated retained artifact manifest should keep interface inputs dependency-ready",
        );

    let foreign_interface = manifest
        .artifacts
        .artifacts
        .iter()
        .find(|artifact| {
            artifact.kind == SourcePackArtifactKind::LibraryInterface && artifact.library_id == 10
        })
        .expect("dependency fixture should include the foreign library interface")
        .clone();
    let target_codegen_job_index = manifest
        .job_schedule
        .jobs
        .iter()
        .find(|job| job.phase == SourcePackJobPhase::Codegen && job.library_id == 20)
        .expect("dependency fixture should include an app codegen job")
        .job_index;

    let forged_ref = SourcePackArtifactRef {
        artifact_index: foreign_interface.artifact_index,
        key: foreign_interface.key.clone(),
        producing_job_index: foreign_interface.producing_job_index,
        kind: foreign_interface.kind,
    };

    let mut tampered = manifest.clone();
    let target_job_manifest = &mut tampered.job_artifacts.jobs[target_codegen_job_index];
    target_job_manifest.input_interface_count =
        target_job_manifest.input_interface_count.saturating_add(1);
    target_job_manifest.input_interfaces.push(forged_ref);

    let target_job_io = &mut tampered.job_artifact_io.jobs[target_codegen_job_index];
    target_job_io.input_interface_artifact_count = target_job_io
        .input_interface_artifact_count
        .saturating_add(1);
    target_job_io
        .input_interface_artifact_indices
        .push(foreign_interface.artifact_index);
    target_job_io
        .input_interface_artifact_indices
        .sort_unstable();
    target_job_io.input_interface_artifact_indices.dedup();

    let artifact_use = &mut tampered.artifact_uses.uses[foreign_interface.artifact_index];
    artifact_use
        .consumer_job_indices
        .push(target_codegen_job_index);
    artifact_use.consumer_job_indices.sort_unstable();
    artifact_use.consumer_job_indices.dedup();
    artifact_use.last_consumer_job_index = artifact_use.consumer_job_indices.iter().copied().max();

    let err = FilesystemArtifactStore::new(root.join("tampered"))
        .store_build_artifact_manifest(&tampered)
        .expect_err("package replay must reject interface inputs without a schedule dependency");
    let message = format!("{err:?}");
    assert!(
        message.contains("library-interface artifact")
            && message.contains("not in the job's scheduled dependencies")
            && message.contains("package/import replay")
            && message.contains("dependency-ready"),
        "expected non-dependency interface input error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove non-dependency interface input temp root");
}

#[test]
fn source_pack_artifact_manifest_rejects_dangling_dependency_range_rows() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "dangling_dependency_range_rows",
        None,
    );
    let pack = ExplicitSourcePack::from_libraries(vec![ExplicitSourceLibrary {
        library_id: 1,
        sources: vec!["module app::main;\nfn main() { return 0; }\n".into()],
        dependency_library_ids: Vec::new(),
    }])
    .expect("create explicit package source pack");
    let manifest = pack
        .bounded_frontend_build_plan(CodegenUnitLimits {
            max_source_bytes: 1024,
            max_source_files: 1,
        })
        .retained_build_artifact_manifest(SourcePackJobBatchLimits::default());
    FilesystemArtifactStore::new(root.join("valid"))
        .store_build_artifact_manifest(&manifest)
        .expect("generated retained artifact manifest should use one dependency-range row per job");
    assert_eq!(
        manifest
            .job_schedule
            .dependency_job_ranges_by_job_index
            .len(),
        manifest.job_count,
        "fixture should persist positional dependency range rows"
    );

    let mut tampered = manifest.clone();
    tampered
        .job_schedule
        .dependency_job_ranges_by_job_index
        .push(vec![SourcePackJobIndexRange {
            first_job_index: 0,
            job_count: 1,
        }]);

    let err = FilesystemArtifactStore::new(root.join("tampered"))
        .store_build_artifact_manifest(&tampered)
        .expect_err("dangling dependency-range rows must not be silently ignored");
    let message = format!("{err:?}");
    assert!(
        message.contains("positional dependency-range rows")
            && message.contains(&format!("job_count {}", manifest.job_count))
            && message.contains("exactly one row per job"),
        "expected stale dependency range row error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove dangling dependency-range-row temp root");
}

#[test]
fn source_pack_artifact_manifest_rejects_frontend_codegen_object_inputs() {
    let root =
        common::temp_artifact_path("laniusc_package_boundaries", "frontend_object_input", None);
    let pack = ExplicitSourcePack::from_libraries(vec![ExplicitSourceLibrary {
        library_id: 1,
        sources: vec!["module app::main;\nfn main() { return 0; }\n".into()],
        dependency_library_ids: Vec::new(),
    }])
    .expect("create explicit package source pack");
    let manifest = pack
        .bounded_frontend_build_plan(CodegenUnitLimits {
            max_source_bytes: 1024,
            max_source_files: 1,
        })
        .retained_build_artifact_manifest(SourcePackJobBatchLimits::default());
    FilesystemArtifactStore::new(root.join("valid"))
        .store_build_artifact_manifest(&manifest)
        .expect("generated retained artifact manifest should keep object inputs link-only");

    let frontend_job_index = manifest
        .job_schedule
        .jobs
        .iter()
        .find(|job| job.phase == SourcePackJobPhase::LibraryFrontend)
        .expect("source-pack plan should include a frontend job")
        .job_index;
    let object_artifact = manifest
        .artifacts
        .artifacts
        .iter()
        .find(|artifact| artifact.kind == SourcePackArtifactKind::CodegenObject)
        .expect("source-pack plan should include a codegen object")
        .clone();
    let forged_object_ref = SourcePackArtifactRef {
        artifact_index: object_artifact.artifact_index,
        key: object_artifact.key.clone(),
        producing_job_index: object_artifact.producing_job_index,
        kind: object_artifact.kind,
    };

    let mut tampered = manifest.clone();
    let frontend_job_manifest = &mut tampered.job_artifacts.jobs[frontend_job_index];
    frontend_job_manifest.input_object_count = 1;
    frontend_job_manifest
        .input_objects
        .push(forged_object_ref.clone());

    let frontend_job_io = &mut tampered.job_artifact_io.jobs[frontend_job_index];
    frontend_job_io.input_object_artifact_count = 1;
    frontend_job_io
        .input_object_artifact_indices
        .push(object_artifact.artifact_index);

    let object_use = &mut tampered.artifact_uses.uses[object_artifact.artifact_index];
    object_use.consumer_job_indices.push(frontend_job_index);
    object_use.consumer_job_indices.sort_unstable();
    object_use.consumer_job_indices.dedup();
    object_use.last_consumer_job_index = object_use.consumer_job_indices.iter().copied().max();

    let err = FilesystemArtifactStore::new(root.join("tampered"))
        .store_build_artifact_manifest(&tampered)
        .expect_err("persisted frontend jobs must not consume codegen object artifacts");
    let message = format!("{err:?}");
    assert!(
        message.contains("phase LibraryFrontend")
            && message.contains("codegen object inputs")
            && message.contains("only link jobs may consume codegen objects"),
        "expected frontend codegen-object input contract error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove frontend-object-input manifest temp root");
}

#[test]
fn source_pack_artifact_manifest_rejects_forged_linked_output_key_identity() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "linked_output_key_identity",
        None,
    );
    let pack = ExplicitSourcePack::from_libraries(vec![ExplicitSourceLibrary {
        library_id: 1,
        sources: vec!["module app::main;\nfn main() { return 0; }\n".into()],
        dependency_library_ids: Vec::new(),
    }])
    .expect("create explicit package source pack");
    let manifest = pack
        .bounded_frontend_build_plan(CodegenUnitLimits {
            max_source_bytes: 1024,
            max_source_files: 1,
        })
        .retained_build_artifact_manifest(SourcePackJobBatchLimits::default());
    FilesystemArtifactStore::new(root.join("valid"))
        .store_build_artifact_manifest(&manifest)
        .expect("generated retained artifact manifest should use canonical artifact keys");

    let linked_output_artifact = manifest
        .artifacts
        .artifacts
        .iter()
        .find(|artifact| artifact.kind == SourcePackArtifactKind::LinkedOutput)
        .expect("source-pack plan should include a linked output artifact")
        .clone();
    let source_end = linked_output_artifact
        .first_source_index
        .saturating_add(linked_output_artifact.source_file_count);
    let forged_key = format!(
        "linked-output/job-{}/src-{}-{}",
        linked_output_artifact.producing_job_index + 1,
        linked_output_artifact.first_source_index,
        source_end
    );
    assert_ne!(
        forged_key, linked_output_artifact.key,
        "test fixture should forge a contradictory but well-formed linked-output key"
    );

    let mut tampered = manifest.clone();
    let artifact_entry = tampered
        .artifacts
        .artifacts
        .iter_mut()
        .find(|artifact| artifact.artifact_index == linked_output_artifact.artifact_index)
        .expect("tampered manifest should contain linked output artifact");
    artifact_entry.key = forged_key.clone();
    let mut updated_output_ref = false;
    for job_manifest in &mut tampered.job_artifacts.jobs {
        for output in &mut job_manifest.outputs {
            if output.artifact_index == linked_output_artifact.artifact_index {
                output.key = forged_key.clone();
                updated_output_ref = true;
            }
        }
    }
    assert!(
        updated_output_ref,
        "tampered manifest should keep output refs internally consistent with the forged key"
    );

    let err = FilesystemArtifactStore::new(root.join("tampered"))
        .store_build_artifact_manifest(&tampered)
        .expect_err("persisted artifact keys must match their artifact identity fields");
    let message = format!("{err:?}");
    assert!(
        message.contains("artifact")
            && message.contains("key")
            && message.contains("persisted artifact identity")
            && message.contains("linked-output")
            && message.contains("producer job"),
        "expected forged linked-output artifact identity error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove linked-output-key temp root");
}

#[test]
fn source_pack_artifact_manifest_rejects_cross_library_codegen_artifact_provenance() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "codegen_artifact_provenance",
        None,
    );
    let pack = ExplicitSourcePack::from_libraries(vec![
        ExplicitSourceLibrary {
            library_id: 10,
            sources: vec!["module core::api;\npub const VALUE: i32 = 1;\n".into()],
            dependency_library_ids: Vec::new(),
        },
        ExplicitSourceLibrary {
            library_id: 20,
            sources: vec![
                "module app::main;\nimport core::api;\nfn main() -> i32 { return 0; }\n".into(),
            ],
            dependency_library_ids: vec![10],
        },
    ])
    .expect("create explicit package source pack");
    let manifest = pack
        .bounded_frontend_build_plan(CodegenUnitLimits {
            max_source_bytes: 1024,
            max_source_files: 1,
        })
        .retained_build_artifact_manifest(SourcePackJobBatchLimits::default());
    FilesystemArtifactStore::new(root.join("valid"))
        .store_build_artifact_manifest(&manifest)
        .expect("generated retained artifact manifest should bind artifacts to producer jobs");

    let object_artifact = manifest
        .artifacts
        .artifacts
        .iter()
        .find(|artifact| {
            artifact.kind == SourcePackArtifactKind::CodegenObject && artifact.library_id == 20
        })
        .expect("source-pack plan should include an app codegen object")
        .clone();
    let forged_library_id = 10;
    let forged_key = source_pack_artifact_key_for_output(
        manifest.target,
        object_artifact.kind,
        forged_library_id,
        object_artifact.producing_job_index,
        object_artifact.first_source_index,
        object_artifact.source_file_count,
    );
    assert_ne!(
        forged_key, object_artifact.key,
        "test fixture should forge a canonical-looking key for the wrong library"
    );

    let mut tampered = manifest.clone();
    let artifact_entry = tampered
        .artifacts
        .artifacts
        .iter_mut()
        .find(|artifact| artifact.artifact_index == object_artifact.artifact_index)
        .expect("tampered manifest should contain codegen object artifact");
    artifact_entry.library_id = forged_library_id;
    artifact_entry.key = forged_key.clone();

    let mut rewritten_refs = 0usize;
    for job_manifest in &mut tampered.job_artifacts.jobs {
        for artifact_ref in job_manifest
            .outputs
            .iter_mut()
            .chain(job_manifest.input_objects.iter_mut())
        {
            if artifact_ref.artifact_index == object_artifact.artifact_index {
                artifact_ref.key = forged_key.clone();
                rewritten_refs = rewritten_refs.saturating_add(1);
            }
        }
    }
    assert!(
        rewritten_refs >= 2,
        "tampered manifest should keep output and link input refs internally consistent"
    );

    let err = FilesystemArtifactStore::new(root.join("tampered"))
        .store_build_artifact_manifest(&tampered)
        .expect_err("artifact provenance must come from the producer job, not a relabeled key");
    let message = format!("{err:?}");
    assert!(
        message.contains("artifact")
            && message.contains("provenance")
            && message.contains("producer job")
            && message.contains("artifact library 10")
            && message.contains("producer library 20"),
        "expected cross-library artifact provenance error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove codegen-artifact-provenance temp root");
}

#[test]
fn source_pack_artifact_manifest_rejects_unsorted_link_object_batch_inputs() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "link_batch_order", None);
    let pack = ExplicitSourcePack::from_libraries(vec![ExplicitSourceLibrary {
        library_id: 1,
        sources: vec![
            "module app::main;\nfn main() { return 0; }\n".into(),
            "module app::helper;\npub const VALUE: i32 = 1;\n".into(),
        ],
        dependency_library_ids: Vec::new(),
    }])
    .expect("create explicit package source pack");
    let manifest = pack
        .bounded_frontend_build_plan(CodegenUnitLimits {
            max_source_bytes: 1024,
            max_source_files: 1,
        })
        .retained_build_artifact_manifest(SourcePackJobBatchLimits::default());
    FilesystemArtifactStore::new(root.join("valid"))
        .store_build_artifact_manifest(&manifest)
        .expect("generated retained artifact manifest should use canonical link-batch input order");

    let mut tampered = manifest.clone();
    let link_object_batch = tampered
        .link_object_batches
        .batches
        .iter_mut()
        .find(|batch| batch.input_object_artifact_indices.len() >= 2)
        .expect("two codegen objects should share one link-object input batch");
    link_object_batch.input_object_artifact_indices.reverse();

    let err = FilesystemArtifactStore::new(root.join("tampered"))
        .store_build_artifact_manifest(&tampered)
        .expect_err("persisted link-object input batches must be canonical");
    let message = format!("{err:?}");
    assert!(
        message.contains("link object batch")
            && message.contains("inputs")
            && message.contains("strictly ascending"),
        "expected unsorted link-object batch input error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove link-batch-order manifest temp root");
}

#[test]
fn source_pack_artifact_manifest_rejects_stale_link_object_batch_source_lines() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "link_batch_lines", None);
    let pack = ExplicitSourcePack::from_libraries(vec![ExplicitSourceLibrary {
        library_id: 1,
        sources: vec![
            "module app::main;\nfn main() { return 0; }\n".into(),
            "module app::helper;\npub const VALUE: i32 = 1;\n".into(),
        ],
        dependency_library_ids: Vec::new(),
    }])
    .expect("create explicit package source pack");
    let manifest = pack
        .bounded_frontend_build_plan(CodegenUnitLimits {
            max_source_bytes: 1024,
            max_source_files: 1,
        })
        .retained_build_artifact_manifest(SourcePackJobBatchLimits::default());
    FilesystemArtifactStore::new(root.join("valid"))
        .store_build_artifact_manifest(&manifest)
        .expect("generated retained artifact manifest should replay link-batch line totals");

    let mut tampered = manifest.clone();
    let link_object_batch = tampered
        .link_object_batches
        .batches
        .first_mut()
        .expect("source-pack plan should include a link-object input batch");
    link_object_batch.source_lines = link_object_batch.source_lines.saturating_add(1);

    let err = FilesystemArtifactStore::new(root.join("tampered"))
        .store_build_artifact_manifest(&tampered)
        .expect_err(
            "persisted link-object input batches must replay source-line totals from artifact refs",
        );
    let message = format!("{err:?}");
    assert!(
        message.contains("link object batch")
            && message.contains("source lines")
            && message.contains("artifacts sum"),
        "expected stale link-object source-line summary error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove link-batch-lines manifest temp root");
}

#[test]
fn source_pack_artifact_manifest_rejects_empty_inline_link_object_batches() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "link_batch_empty", None);
    let pack = ExplicitSourcePack::from_libraries(vec![ExplicitSourceLibrary {
        library_id: 1,
        sources: vec![
            "module app::main;\nfn main() { return 0; }\n".into(),
            "module app::helper;\npub const VALUE: i32 = 1;\n".into(),
        ],
        dependency_library_ids: Vec::new(),
    }])
    .expect("create explicit package source pack");
    let manifest = pack
        .bounded_frontend_build_plan(CodegenUnitLimits {
            max_source_bytes: 1024,
            max_source_files: 1,
        })
        .retained_build_artifact_manifest(SourcePackJobBatchLimits::default());
    FilesystemArtifactStore::new(root.join("valid"))
        .store_build_artifact_manifest(&manifest)
        .expect("generated retained artifact manifest should use nonempty link batches");

    let mut tampered = manifest.clone();
    let mut empty_batch = tampered
        .link_object_batches
        .batches
        .first()
        .expect("source-pack plan should include a link-object input batch")
        .clone();
    empty_batch.batch_index = tampered.link_object_batches.batches.len();
    empty_batch.input_object_artifact_indices.clear();
    empty_batch.source_bytes = 0;
    empty_batch.source_file_count = 0;
    empty_batch.source_lines = 0;
    tampered.link_object_batches.batches.push(empty_batch);
    tampered.link_object_batch_count = tampered.link_object_batches.batches.len();

    let err = FilesystemArtifactStore::new(root.join("tampered"))
        .store_build_artifact_manifest(&tampered)
        .expect_err("persisted inline link-object batches must carry concrete artifact inputs");
    let message = format!("{err:?}");
    assert!(
        message.contains("link object batch") && message.contains("has no input artifacts"),
        "expected empty link-object batch error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove link-batch-empty manifest temp root");
}

#[test]
fn source_pack_job_batch_sidecars_reject_noncanonical_dependency_order() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "job_batch_dependency_order",
        None,
    );
    std::fs::create_dir_all(&root).expect("create dependency-order temp root");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;

    let unsorted_dependency_page = SourcePackBuildJobBatchDependencyPage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_PAGE_VERSION,
        target,
        batch_index: 3,
        page_index: 0,
        first_dependency_position: 0,
        dependency_count: 2,
        dependency_batch_indices: vec![2, 1],
    };
    let dependency_err = store
        .store_build_job_batch_dependency_page(&unsorted_dependency_page)
        .expect_err("dependency sidecars must be canonical for replay");
    let dependency_message = dependency_err.to_string();
    assert!(
        dependency_message.contains("strictly ascending"),
        "expected noncanonical dependency order error, got {dependency_message}"
    );

    let unsorted_range_page = SourcePackBuildJobBatchDependencyRangePage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_VERSION,
        target,
        batch_index: 4,
        page_index: 0,
        first_range_position: 0,
        range_count: 2,
        dependency_batch_count: 2,
        dependency_batch_ranges: vec![
            SourcePackJobBatchDependencyRange {
                first_batch_index: 2,
                batch_count: 1,
            },
            SourcePackJobBatchDependencyRange {
                first_batch_index: 0,
                batch_count: 1,
            },
        ],
    };
    let range_err = store
        .store_build_job_batch_dependency_range_page(&unsorted_range_page)
        .expect_err("dependency range sidecars must be canonical for replay");
    let range_message = range_err.to_string();
    assert!(
        range_message.contains("sorted and non-overlapping"),
        "expected noncanonical dependency range order error, got {range_message}"
    );

    std::fs::remove_dir_all(&root).expect("remove dependency-order temp root");
}

#[test]
fn source_pack_work_queue_rejects_link_leaf_input_missing_from_dependency_sidecar() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "work_queue_deps", None);
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let link_item_index = 3;
    let codegen_input_job_index = 2;

    store
        .store_work_queue_page(&SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index: link_item_index,
            kind: SourcePackWorkQueueItemKind::LinkLeaf,
            job_index: link_item_index,
            dependency_item_indices: vec![1, codegen_input_job_index],
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
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 1,
            input_codegen_job_indices: vec![codegen_input_job_index],
            input_link_group_count: 0,
            input_link_group_indices: Vec::new(),
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        })
        .expect("valid link leaf page should persist its dependency sidecar");

    let tampered_dependency_page = SourcePackWorkQueueDependenciesPage {
        version: SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_PAGE_VERSION,
        target,
        item_index: link_item_index,
        page_index: 0,
        first_dependency_position: 0,
        dependency_count: 2,
        dependency_item_indices: vec![0, 1],
    };
    let dependency_page_path =
        store.work_queue_dependencies_page_path_for_target(target, link_item_index, 0);
    std::fs::write(
        &dependency_page_path,
        serde_json::to_vec_pretty(&tampered_dependency_page)
            .expect("serialize tampered dependency sidecar"),
    )
    .expect("tamper persisted dependency sidecar");

    let err = store
        .load_work_queue_page_for_target(target, link_item_index)
        .expect_err("persisted link leaf pages must fail closed when an object input is not dependency-ready");
    let message = err.to_string();
    assert!(
        message.contains("codegen inputs")
            && message.contains("not listed as dependencies")
            && message.contains(&codegen_input_job_index.to_string()),
        "expected missing codegen-input dependency error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove work queue dependency temp root");
}

#[test]
fn source_pack_link_groups_reject_noncanonical_or_non_prior_leaf_inputs() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "link_group_inputs", None);
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;

    let valid_group = SourcePackHierarchicalLinkGroupPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
        target,
        group_index: 4,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        level: 0,
        job_index: 20,
        input_partition_count: 1,
        input_partition_indices: vec![0],
        input_frontend_job_count: 2,
        input_frontend_job_indices: vec![2, 3],
        input_codegen_job_indices: vec![10, 11],
        input_link_group_indices: Vec::new(),
        source_byte_count: 16,
        source_file_count: 2,
        source_line_count: 2,
        oversized_input: false,
    };
    store
        .store_hierarchical_link_group_page(&valid_group)
        .expect("canonical prior link leaf inputs should be persisted");

    let mut unsorted_codegen_inputs = valid_group.clone();
    unsorted_codegen_inputs.group_index = 5;
    unsorted_codegen_inputs.input_codegen_job_indices = vec![11, 10];
    let err = store
        .store_hierarchical_link_group_page(&unsorted_codegen_inputs)
        .expect_err("persisted link leaf codegen inputs must use canonical order");
    let message = err.to_string();
    assert!(
        message.contains("hierarchical link group 5 codegen jobs")
            && message.contains("strictly ascending"),
        "expected noncanonical link-group input order error, got {message}"
    );

    let mut future_codegen_input = valid_group;
    future_codegen_input.group_index = 6;
    future_codegen_input.input_codegen_job_indices = vec![10, 20];
    let err = store
        .store_hierarchical_link_group_page(&future_codegen_input)
        .expect_err("persisted link leaf inputs must be producer jobs that precede the link job");
    let message = err.to_string();
    assert!(
        message.contains("hierarchical link leaf group 6")
            && message.contains("non-prior codegen input job 20")
            && message.contains("link job 20"),
        "expected non-prior link-group input error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove link group input temp root");
}

#[test]
fn source_pack_link_leaf_planning_rejects_stale_schedule_page_index_membership() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "stale_schedule_index_membership",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let schedule_index = SourcePackLibraryScheduleIndex {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
        target,
        partition_count: 1,
        frontend_job_count: 1,
        codegen_job_count: 1,
        link_job_index: 2,
        job_count: 3,
    };
    store
        .store_library_schedule_index(&schedule_index)
        .expect("store schedule index for stale page membership fixture");

    let frontend_job = SourcePackJob {
        job_index: 0,
        phase: SourcePackJobPhase::LibraryFrontend,
        phase_unit_index: 0,
        library_job_index: None,
        library_id: 1,
        first_source_index: 0,
        source_file_count: 1,
        source_bytes: 16,
        source_lines: 1,
        oversized_source_file: false,
        dependency_job_indices: Vec::new(),
    };
    let codegen_job = SourcePackJob {
        job_index: 1,
        phase: SourcePackJobPhase::Codegen,
        phase_unit_index: 0,
        library_job_index: Some(0),
        library_id: 1,
        first_source_index: 0,
        source_file_count: 1,
        source_bytes: 16,
        source_lines: 1,
        oversized_source_file: false,
        dependency_job_indices: vec![0],
    };
    store
        .store_library_schedule_page(&SourcePackLibrarySchedulePage {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_PAGE_VERSION,
            target,
            partition_index: 0,
            library_id: 1,
            dependency_library_ids: Vec::new(),
            frontend_job_index: 0,
            first_frontend_unit_index: 0,
            frontend_job_count: 1,
            first_codegen_unit_index: 0,
            first_codegen_job_index: 1,
            codegen_job_count: 1,
            link_job_index: 2,
            frontend_job,
            frontend_jobs: Vec::new(),
            codegen_jobs: vec![codegen_job],
        })
        .expect("store compact schedule page with job sidecars");

    let mut stale_page = store
        .load_library_schedule_page_for_target(target, 0)
        .expect("reload compact schedule page before tampering");
    stale_page.link_job_index = 99;
    std::fs::write(
        store.library_schedule_page_path_for_target(target, 0),
        serde_json::to_vec_pretty(&stale_page).expect("serialize stale schedule page"),
    )
    .expect("tamper compact schedule page link job");

    let err = prepare_link_leaf_groups_chunk(&root, target, SourcePackJobBatchLimits::default(), 1)
        .expect_err("link planning must reject stale schedule pages before emitting groups");
    let message = err.to_string();
    assert!(
        message.contains("schedule page 0 link job 99")
            && message.contains("schedule index link job 2"),
        "expected stale schedule page/index membership error, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_group_page_path_for_target(target, 0)
            .exists(),
        "rejected stale schedule page must not publish link group evidence"
    );

    std::fs::remove_dir_all(&root).expect("remove stale schedule index membership temp root");
}

#[test]
fn source_pack_link_execution_pages_reject_malformed_source_summaries() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_execution_source_bytes",
        None,
    );
    std::fs::create_dir_all(&root).expect("create link execution source-byte temp root");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;

    let leaf_page = |group_index: usize,
                     job_index: usize,
                     source_byte_count: usize,
                     source_file_count: usize,
                     source_line_count: usize| {
        SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index,
            input_interface_count: 1,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![SourcePackArtifactRef {
                artifact_index: 0,
                key: "library-interface/lib-0/job-0/src-0-1".into(),
                producing_job_index: 0,
                kind: SourcePackArtifactKind::LibraryInterface,
            }],
            input_object_count: 1,
            input_object_page_count: 0,
            input_objects: vec![SourcePackArtifactRef {
                artifact_index: 1,
                key: "codegen-object/lib-0/job-1/src-0-1".into(),
                producing_job_index: 1,
                kind: SourcePackArtifactKind::CodegenObject,
            }],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count,
            source_file_count,
            source_line_count,
            output_key: format!("partial-link/group-{group_index:08}/job-{job_index:08}"),
            final_output: false,
            descriptor_summary: Default::default(),
        }
    };

    let empty_summary = leaf_page(0, 2, 0, 1, 1);
    let err = store
        .store_hierarchical_link_execution_page(&empty_summary)
        .expect_err("link execution pages must carry source-byte provenance");
    let message = err.to_string();
    assert!(
        message.contains("empty source-byte summary")
            && message.contains("concrete source-byte evidence"),
        "expected empty source-byte summary error, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, 0)
            .exists(),
        "rejected link execution page must not be persisted"
    );

    let impossible_summary = leaf_page(1, 3, 1, 2, 2);
    let err = store
        .store_hierarchical_link_execution_page(&impossible_summary)
        .expect_err("link execution pages must not report fewer bytes than source files");
    let message = err.to_string();
    assert!(
        message.contains("source-byte summary 1") && message.contains("source-file count 2"),
        "expected impossible source-byte summary error, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, 1)
            .exists(),
        "rejected impossible source-byte link execution page must not be persisted"
    );

    let empty_line_summary = leaf_page(2, 4, 2, 2, 0);
    let err = store
        .store_hierarchical_link_execution_page(&empty_line_summary)
        .expect_err("link execution pages must carry source-line provenance");
    let message = err.to_string();
    assert!(
        message.contains("empty source-line summary")
            && message.contains("concrete source-line evidence"),
        "expected empty source-line summary error, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, 2)
            .exists(),
        "rejected source-line link execution page must not be persisted"
    );

    let impossible_line_summary = leaf_page(3, 5, 2, 2, 1);
    let err = store
        .store_hierarchical_link_execution_page(&impossible_line_summary)
        .expect_err("link execution pages must not report fewer lines than source files");
    let message = err.to_string();
    assert!(
        message.contains("source-line summary 1") && message.contains("source-file count 2"),
        "expected impossible source-line summary error, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, 3)
            .exists(),
        "rejected impossible source-line link execution page must not be persisted"
    );

    std::fs::remove_dir_all(&root).expect("remove link execution source-byte temp root");
}

#[test]
fn source_pack_link_execution_rejects_reduce_group_summary_that_does_not_match_inputs() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "reduce_summary", None);
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 2,
            frontend_job_count: 2,
            codegen_job_count: 2,
            link_job_index: 4,
            job_count: 5,
        })
        .expect("store minimal schedule index for link-execution replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: 5,
            interface_artifact_count: 2,
            object_artifact_count: 2,
            final_output_artifact_index: 4,
            final_output_key: "linked-output/job-4/src-0-2".into(),
            total_source_file_count: 2,
            total_source_byte_count: 30,
            total_source_line_count: 3,
        })
        .expect("store minimal artifact-ref index for link-execution replay");

    let leaf_group = |group_index: usize,
                      job_index: usize,
                      partition_index: usize,
                      codegen_job_index: usize,
                      source_byte_count: usize,
                      source_line_count: usize| {
        SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            level: 0,
            job_index,
            input_partition_count: 1,
            input_partition_indices: vec![partition_index],
            input_frontend_job_count: 1,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_indices: vec![codegen_job_index],
            input_link_group_indices: Vec::new(),
            source_byte_count,
            source_file_count: 1,
            source_line_count,
            oversized_input: false,
        }
    };
    store
        .store_hierarchical_link_group_page(&leaf_group(0, 4, 0, 2, 10, 1))
        .expect("store first leaf group");
    store
        .store_hierarchical_link_group_page(&leaf_group(1, 5, 1, 3, 20, 2))
        .expect("store second leaf group");
    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: 2,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            level: 1,
            job_index: 6,
            input_partition_count: 2,
            input_partition_indices: Vec::new(),
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_indices: Vec::new(),
            input_link_group_indices: vec![0, 1],
            source_byte_count: 30,
            source_file_count: 3,
            source_line_count: 3,
            oversized_input: false,
        })
        .expect("local reduce group shape is not enough to prove its summary");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 2,
        first_link_job_index: 4,
        final_link_group_index: 2,
        final_link_job_index: 6,
        link_group_count: 3,
    };
    std::fs::write(
        store.hierarchical_link_plan_index_path_for_target(target),
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");
    std::fs::write(
        store.link_execution_prepare_progress_path_for_target(target),
        serde_json::to_vec_pretty(&serde_json::json!({
            "version": SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_VERSION,
            "target": target,
            "link_group_count": 3,
            "next_group_index": 2,
            "final_output_seen": false,
        }))
        .expect("serialize resumable link-execution progress"),
    )
    .expect("persist resumable link-execution progress");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("reduce link execution must fail closed on stale input summaries");
    let message = err.to_string();
    assert!(
        message.contains("hierarchical link reduce group 2 summary")
            && message.contains("does not match input groups")
            && message.contains("files=3")
            && message.contains("expected")
            && message.contains("files=2"),
        "expected reduce-group reference summary error, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_index_path_for_target(target)
            .exists(),
        "rejected reduce summary must not publish a completed link-execution index"
    );

    std::fs::remove_dir_all(&root).expect("remove reduce summary temp root");
}

#[test]
fn source_pack_link_execution_completion_rejects_stale_final_source_summary() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_completion_stale_final_summary",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;

    let frontend_job = SourcePackJob {
        job_index: 0,
        phase: SourcePackJobPhase::LibraryFrontend,
        phase_unit_index: 0,
        library_job_index: None,
        library_id: 1,
        first_source_index: 0,
        source_file_count: 1,
        source_bytes: 16,
        source_lines: 1,
        oversized_source_file: false,
        dependency_job_indices: Vec::new(),
    };
    let codegen_job = SourcePackJob {
        job_index: 1,
        phase: SourcePackJobPhase::Codegen,
        phase_unit_index: 0,
        library_job_index: Some(0),
        library_id: 1,
        first_source_index: 0,
        source_file_count: 1,
        source_bytes: 16,
        source_lines: 1,
        oversized_source_file: false,
        dependency_job_indices: vec![0],
    };

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: 2,
            job_count: 3,
        })
        .expect("store schedule index for link completion");
    store
        .store_library_schedule_page(&SourcePackLibrarySchedulePage {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_PAGE_VERSION,
            target,
            partition_index: 0,
            library_id: 1,
            dependency_library_ids: Vec::new(),
            frontend_job_index: 0,
            first_frontend_unit_index: 0,
            frontend_job_count: 1,
            first_codegen_unit_index: 0,
            first_codegen_job_index: 1,
            codegen_job_count: 1,
            link_job_index: 2,
            frontend_job,
            frontend_jobs: Vec::new(),
            codegen_jobs: vec![codegen_job],
        })
        .expect("store schedule page for link completion");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: 3,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: 2,
            final_output_key: "linked-output/job-2/src-0-1".into(),
            total_source_file_count: 1,
            total_source_byte_count: 32,
            total_source_line_count: 2,
        })
        .expect("store artifact-ref index with current final source totals");
    store
        .store_build_artifact_ref_page(
            &SourcePackBuildArtifactRefPage {
                version: SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION,
                target,
                artifact_index: 0,
                artifact_ref: SourcePackArtifactRef {
                    artifact_index: 0,
                    key: "library-interface/lib-1/job-0/src-0-1".into(),
                    producing_job_index: 0,
                    kind: SourcePackArtifactKind::LibraryInterface,
                },
                source_bytes: 16,
                source_file_count: 1,
                source_lines: 1,
            },
            3,
        )
        .expect("store interface artifact-ref page");
    store
        .store_build_artifact_ref_page(
            &SourcePackBuildArtifactRefPage {
                version: SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION,
                target,
                artifact_index: 1,
                artifact_ref: SourcePackArtifactRef {
                    artifact_index: 1,
                    key: "codegen-object/lib-1/job-1/src-0-1".into(),
                    producing_job_index: 1,
                    kind: SourcePackArtifactKind::CodegenObject,
                },
                source_bytes: 16,
                source_file_count: 1,
                source_lines: 1,
            },
            3,
        )
        .expect("store object artifact-ref page");
    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            level: 0,
            job_index: 2,
            input_partition_count: 1,
            input_partition_indices: vec![0],
            input_frontend_job_count: 1,
            input_frontend_job_indices: vec![0],
            input_codegen_job_indices: vec![1],
            input_link_group_indices: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store stale final link group summary");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index: 2,
        final_link_group_index: 0,
        final_link_job_index: 2,
        link_group_count: 1,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("link completion must not publish stale final source-summary evidence");
    let message = err.to_string();
    assert!(
        message.contains("final page source summary bytes/files/lines 16/1/1")
            && message.contains("current artifact-ref totals 32/1/2")
            && message.contains("stale linked-output source evidence"),
        "expected stale final source-summary completion error, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_index_path_for_target(target)
            .exists(),
        "rejected final source summary must not publish a completed link-execution index"
    );

    std::fs::remove_dir_all(&root).expect("remove stale final-summary completion temp root");
}

#[test]
fn source_pack_link_execution_rejects_final_group_missing_plan_input_partitions() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_final_group_partition_range",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 2,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: 2,
            job_count: 3,
        })
        .expect("store schedule index with two input partitions");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: 3,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: 2,
            final_output_key: "linked-output/job-2/src-0-2".into(),
            total_source_file_count: 2,
            total_source_byte_count: 32,
            total_source_line_count: 2,
        })
        .expect("store artifact-ref index for final output");
    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            level: 0,
            job_index: 2,
            input_partition_count: 1,
            input_partition_indices: vec![0],
            input_frontend_job_count: 1,
            input_frontend_job_indices: vec![0],
            input_codegen_job_indices: vec![1],
            input_link_group_indices: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("local leaf group shape is valid before plan-level partition coverage");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 2,
        first_link_job_index: 2,
        final_link_group_index: 0,
        final_link_job_index: 2,
        link_group_count: 1,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("final link groups must cover every plan input partition");
    let message = err.to_string();
    assert!(
        message.contains("hierarchical link final group 0")
            && message.contains("records 1 input partitions")
            && message.contains("plan has 2 input partitions")
            && message.contains("complete input partition range"),
        "expected final group input-partition coverage error, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_index_path_for_target(target)
            .exists(),
        "rejected final group partition coverage must not publish completed link metadata"
    );

    std::fs::remove_dir_all(&root).expect("remove final group partition-range temp root");
}

#[test]
fn source_pack_artifact_refs_resume_requires_final_linked_output_page_evidence() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "artifact_ref_final_page_evidence",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;

    store
        .store_library_partition_compact_index(&SourcePackLibraryPartitionIndex {
            version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
            target,
            partition_count: 1,
            source_file_count: 1,
            source_byte_count: 16,
            source_line_count: 1,
        })
        .expect("store minimal metadata index for artifact-ref replay");
    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: 2,
            job_count: 3,
        })
        .expect("store minimal schedule index for artifact-ref replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: 3,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: 2,
            final_output_key: "linked-output/job-2/src-0-1".into(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store forged completed artifact-ref index without final page evidence");

    let err = prepare_artifact_refs_chunk(&root, target, 1).expect_err(
        "completed artifact-ref index must not stand in for linked-output page evidence",
    );
    let message = err.to_string();
    assert!(
        message.contains("requires final linked-output artifact-ref page evidence")
            && message.contains("artifact 2")
            && message.contains("read source-pack artifact-ref page"),
        "expected missing final artifact-ref page evidence error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove artifact-ref evidence temp root");
}

#[test]
fn source_pack_artifact_refs_reject_source_counts_without_byte_provenance() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "artifact_ref_source_bytes",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;

    let err = store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: 3,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: 2,
            final_output_key: "linked-output/job-2/src-0-1".into(),
            total_source_file_count: 1,
            total_source_byte_count: 0,
            total_source_line_count: 1,
        })
        .expect_err("artifact-ref indexes must not replay source counts without bytes");
    let message = err.to_string();
    assert!(
        message.contains("artifact-ref index")
            && message.contains("source-byte summary 0")
            && message.contains("source-file count 1")
            && message.contains("source-byte provenance"),
        "expected artifact-ref index source-byte provenance error, got {message}"
    );
    assert!(
        !store
            .build_artifact_ref_index_path_for_target(target)
            .exists(),
        "rejected artifact-ref index must not be persisted"
    );

    let err = store
        .store_build_artifact_ref_page(
            &SourcePackBuildArtifactRefPage {
                version: SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION,
                target,
                artifact_index: 2,
                artifact_ref: SourcePackArtifactRef {
                    artifact_index: 2,
                    key: "linked-output/job-2/src-0-1".into(),
                    producing_job_index: 2,
                    kind: SourcePackArtifactKind::LinkedOutput,
                },
                source_bytes: 0,
                source_file_count: 1,
                source_lines: 1,
            },
            3,
        )
        .expect_err("artifact-ref pages must not replay source counts without bytes");
    let message = err.to_string();
    assert!(
        message.contains("artifact-ref page 2")
            && message.contains("source-byte summary 0")
            && message.contains("source-file count 1")
            && message.contains("source-byte provenance"),
        "expected artifact-ref page source-byte provenance error, got {message}"
    );
    assert!(
        !store
            .build_artifact_ref_page_path_for_target(target, 2)
            .exists(),
        "rejected artifact-ref page must not be persisted"
    );

    if root.exists() {
        std::fs::remove_dir_all(&root).expect("remove artifact-ref source-byte temp root");
    }
}

#[test]
fn source_pack_artifact_shards_reject_stale_partition_count_source_total() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "artifact_shards_stale_partition_count",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let stale_index = SourcePackLibraryPartitionIndex {
        version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
        target,
        partition_count: 2,
        source_file_count: 1,
        source_byte_count: 16,
        source_line_count: 1,
    };
    let index_path = store.library_partition_index_path_for_target(target);
    std::fs::create_dir_all(index_path.parent().expect("partition index parent"))
        .expect("create partition index parent");
    std::fs::write(
        &index_path,
        serde_json::to_vec_pretty(&stale_index).expect("serialize stale partition index"),
    )
    .expect("persist stale partition index");

    let err = prepare_artifact_shards_chunk(&root, target, Default::default(), 1)
        .expect_err("artifact-shard planning must reject stale partition/source totals");
    let message = err.to_string();
    assert!(
        message.contains("partition index has 2 library partitions for 1 source files")
            && message.contains("scheduling or linking"),
        "expected stale partition-count/source-total error, got {message}"
    );
    assert!(
        !store.artifact_shard_index_path_for_target(target).exists(),
        "rejected stale partition index must not publish artifact-shard evidence"
    );

    std::fs::remove_dir_all(&root).expect("remove stale partition-count temp root");
}

#[test]
fn source_pack_artifact_refs_resume_rejects_stale_schedule_identity() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "artifact_ref_stale_schedule",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;

    store
        .store_library_partition_compact_index(&SourcePackLibraryPartitionIndex {
            version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
            target,
            partition_count: 1,
            source_file_count: 2,
            source_byte_count: 32,
            source_line_count: 2,
        })
        .expect("store current metadata index for artifact-ref replay");
    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 2,
            codegen_job_count: 1,
            link_job_index: 3,
            job_count: 4,
        })
        .expect("store current schedule index for artifact-ref replay");

    let stale_final_output_key = "linked-output/job-2/src-0-1".to_string();
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: 3,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: 2,
            final_output_key: stale_final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store stale completed artifact-ref index from an older schedule");
    store
        .store_build_artifact_ref_page(
            &SourcePackBuildArtifactRefPage {
                version: SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION,
                target,
                artifact_index: 2,
                artifact_ref: SourcePackArtifactRef {
                    artifact_index: 2,
                    key: stale_final_output_key,
                    producing_job_index: 2,
                    kind: SourcePackArtifactKind::LinkedOutput,
                },
                source_bytes: 16,
                source_file_count: 1,
                source_lines: 1,
            },
            3,
        )
        .expect("stale final artifact-ref page is internally consistent");

    let err = prepare_artifact_refs_chunk(&root, target, 1)
        .expect_err("completed artifact-ref replay must match the current dense schedule");
    let message = err.to_string();
    assert!(
        message.contains("artifact count 3")
            && message.contains("current schedule job count 4")
            && message.contains("current dense job schedule"),
        "expected stale schedule identity error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove stale artifact-ref schedule temp root");
}

#[test]
fn source_pack_link_execution_resume_requires_final_page_record_evidence() {
    let root =
        common::temp_artifact_path("laniusc_package_boundaries", "link_index_evidence", None);
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let final_output_key = "linked-output/job-2/src-0-1".to_string();

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: 2,
            job_count: 3,
        })
        .expect("store minimal schedule index for link-execution replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: 3,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: 2,
            final_output_key: final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store minimal artifact-ref index for link-execution replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index: 2,
        final_link_group_index: 0,
        final_link_job_index: 2,
        link_group_count: 1,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index: 2,
        final_link_group_index: 0,
        final_link_job_index: 2,
        link_group_count: 1,
        final_output_key,
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist forged completed link execution index");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed link-execution metadata must require final page evidence");
    let message = err.to_string();
    assert!(
        message.contains("requires final execution page evidence")
            && message.contains("group 0")
            && message.contains("read source-pack hierarchical link execution page"),
        "expected missing final-page evidence error, got {message}"
    );

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: 2,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![SourcePackArtifactRef {
                artifact_index: 0,
                key: "library-interface/lib-0/job-0/src-0-1".into(),
                producing_job_index: 0,
                kind: SourcePackArtifactKind::LibraryInterface,
            }],
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: vec![SourcePackArtifactRef {
                artifact_index: 1,
                key: "codegen-object/lib-0/job-1/src-0-1".into(),
                producing_job_index: 1,
                kind: SourcePackArtifactKind::CodegenObject,
            }],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: execution_index.final_output_key.clone(),
            final_output: true,
            descriptor_summary: Default::default(),
        })
        .expect("final execution page record should satisfy resumed-completion evidence");
    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            level: 0,
            job_index: 2,
            input_partition_count: 1,
            input_partition_indices: vec![0],
            input_frontend_job_count: 1,
            input_frontend_job_indices: vec![0],
            input_codegen_job_indices: vec![1],
            input_link_group_indices: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("current final link group should satisfy completed replay evidence");
    let resumed = prepare_link_execution_chunk(&root, target, 1)
        .expect("completed link execution index with final page evidence should resume");
    assert!(resumed.complete);
    assert_eq!(resumed.new_execution_page_count, 0);
    assert_eq!(
        resumed.hierarchical_link_execution_index_path.as_deref(),
        Some(execution_index_path.as_path())
    );

    std::fs::remove_dir_all(&root).expect("remove link-index-evidence temp root");
}

#[test]
fn source_pack_link_execution_resume_accepts_final_interface_range_evidence() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_final_interface_ranges",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let final_output_key = "linked-output/job-2/src-0-1".to_string();

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: 2,
            job_count: 3,
        })
        .expect("store minimal schedule index for interface-range replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: 3,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: 2,
            final_output_key: final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for interface-range replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index: 2,
        final_link_group_index: 0,
        final_link_job_index: 2,
        link_group_count: 1,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index: 2,
        final_link_group_index: 0,
        final_link_job_index: 2,
        link_group_count: 1,
        final_output_key,
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist completed link execution index");

    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            level: 0,
            job_index: 2,
            input_partition_count: 1,
            input_partition_indices: vec![0],
            input_frontend_job_count: 1,
            input_frontend_job_indices: vec![0],
            input_codegen_job_indices: vec![1],
            input_link_group_indices: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store current final leaf group");
    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: 2,
            input_interface_count: 1,
            input_interface_page_count: 0,
            input_interface_ranges: vec![SourcePackJobIndexRange {
                first_job_index: 0,
                job_count: 1,
            }],
            input_interfaces: Vec::new(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: vec![SourcePackArtifactRef {
                artifact_index: 1,
                key: "codegen-object/lib-0/job-1/src-0-1".into(),
                producing_job_index: 1,
                kind: SourcePackArtifactKind::CodegenObject,
            }],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: execution_index.final_output_key.clone(),
            final_output: true,
            descriptor_summary: Default::default(),
        })
        .expect("store final execution page with ranged interface evidence");

    assert!(
        !store
            .hierarchical_link_execution_interface_page_path_for_target(target, 0, 0)
            .exists(),
        "range-backed interface evidence should not require a concrete interface sidecar page"
    );
    let resumed = prepare_link_execution_chunk(&root, target, 1)
        .expect("completed link execution should replay range-backed interface evidence");
    assert!(resumed.complete);
    assert_eq!(resumed.new_execution_page_count, 0);
    assert_eq!(
        resumed.hierarchical_link_execution_index_path.as_deref(),
        Some(execution_index_path.as_path())
    );

    std::fs::remove_dir_all(&root).expect("remove interface-range replay temp root");
}

#[test]
fn source_pack_link_execution_resume_rejects_stale_final_output_key() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_stale_final_output",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let stale_final_output_key = "linked-output/job-2/src-0-1".to_string();
    let current_final_output_key = "linked-output/job-2/src-0-2".to_string();

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: 2,
            job_count: 3,
        })
        .expect("store minimal schedule index for stale completed link replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: 3,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: 2,
            final_output_key: current_final_output_key.clone(),
            total_source_file_count: 2,
            total_source_byte_count: 32,
            total_source_line_count: 2,
        })
        .expect("store current artifact-ref index for stale completed link replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index: 2,
        final_link_group_index: 0,
        final_link_job_index: 2,
        link_group_count: 1,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index: 2,
        final_link_group_index: 0,
        final_link_job_index: 2,
        link_group_count: 1,
        final_output_key: stale_final_output_key.clone(),
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist stale completed link execution index");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: 2,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![SourcePackArtifactRef {
                artifact_index: 0,
                key: "library-interface/lib-0/job-0/src-0-1".into(),
                producing_job_index: 0,
                kind: SourcePackArtifactKind::LibraryInterface,
            }],
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: vec![SourcePackArtifactRef {
                artifact_index: 1,
                key: "codegen-object/lib-0/job-1/src-0-1".into(),
                producing_job_index: 1,
                kind: SourcePackArtifactKind::CodegenObject,
            }],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: stale_final_output_key.clone(),
            final_output: true,
            descriptor_summary: Default::default(),
        })
        .expect("store stale final execution page and input sidecars");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed link execution must match the current artifact-ref final output");
    let message = err.to_string();
    assert!(
        message.contains("completed source-pack link execution index final output")
            && message.contains(&stale_final_output_key)
            && message.contains(&current_final_output_key)
            && message.contains("current artifact-ref index final output"),
        "expected stale final output key error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove stale final-output temp root");
}

#[test]
fn source_pack_link_execution_resume_rejects_stale_final_page_source_summary() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_stale_final_summary",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let final_output_key = "linked-output/job-2/src-0-1".to_string();

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: 2,
            job_count: 3,
        })
        .expect("store minimal schedule index for stale completed link summary replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: 3,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: 2,
            final_output_key: final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 32,
            total_source_line_count: 2,
        })
        .expect("store current artifact-ref index for stale completed link summary replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index: 2,
        final_link_group_index: 0,
        final_link_job_index: 2,
        link_group_count: 1,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index: 2,
        final_link_group_index: 0,
        final_link_job_index: 2,
        link_group_count: 1,
        final_output_key,
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist completed link execution index");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: 2,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![SourcePackArtifactRef {
                artifact_index: 0,
                key: "library-interface/lib-0/job-0/src-0-1".into(),
                producing_job_index: 0,
                kind: SourcePackArtifactKind::LibraryInterface,
            }],
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: vec![SourcePackArtifactRef {
                artifact_index: 1,
                key: "codegen-object/lib-0/job-1/src-0-1".into(),
                producing_job_index: 1,
                kind: SourcePackArtifactKind::CodegenObject,
            }],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: execution_index.final_output_key.clone(),
            final_output: true,
            descriptor_summary: Default::default(),
        })
        .expect("store stale final execution page with current final output key");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed link execution must reject stale final source summaries");
    let message = err.to_string();
    assert!(
        message.contains("final page source summary bytes/files/lines 16/1/1")
            && message.contains("current artifact-ref totals 32/1/2")
            && message.contains("stale linked-output source evidence"),
        "expected stale final-page source summary error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove stale final-summary temp root");
}

#[test]
fn source_pack_link_execution_resume_rejects_stale_final_group_shape() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_stale_final_group_shape",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let first_link_job_index = 2;
    let final_link_group_index = 1;
    let final_link_job_index = 3;
    let final_output_key = "linked-output/job-2/src-0-1".to_string();

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: first_link_job_index,
            job_count: first_link_job_index + 1,
        })
        .expect("store schedule index for stale final-group replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: first_link_job_index + 1,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: first_link_job_index,
            final_output_key: final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for stale final-group replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 2,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 2,
        final_output_key,
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist completed link execution index");

    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: final_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            level: 1,
            job_index: final_link_job_index,
            input_partition_count: 1,
            input_partition_indices: Vec::new(),
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_indices: Vec::new(),
            input_link_group_indices: vec![0],
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store current final reduce group shape");
    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: final_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: final_link_job_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![SourcePackArtifactRef {
                artifact_index: 0,
                key: "library-interface/lib-0/job-0/src-0-1".into(),
                producing_job_index: 0,
                kind: SourcePackArtifactKind::LibraryInterface,
            }],
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: vec![SourcePackArtifactRef {
                artifact_index: 1,
                key: "codegen-object/lib-0/job-1/src-0-1".into(),
                producing_job_index: 1,
                kind: SourcePackArtifactKind::CodegenObject,
            }],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: execution_index.final_output_key.clone(),
            final_output: true,
            descriptor_summary: Default::default(),
        })
        .expect("store stale final execution page that still matches completed index evidence");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed replay must reject stale final group shape");
    let message = err.to_string();
    assert!(
        message.contains("records kind Leaf") && message.contains("current link group is Reduce"),
        "expected stale final group shape error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove stale final-group temp root");
}

#[test]
fn source_pack_link_execution_resume_rejects_stale_final_leaf_object_job() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_stale_final_leaf_object",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let first_link_job_index = 3;
    let final_link_group_index = 0;
    let final_link_job_index = first_link_job_index;
    let final_output_key = "linked-output/job-3/src-0-1".to_string();

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 2,
            link_job_index: first_link_job_index,
            job_count: first_link_job_index + 1,
        })
        .expect("store schedule index for stale final leaf-object replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: first_link_job_index + 1,
            interface_artifact_count: 1,
            object_artifact_count: 2,
            final_output_artifact_index: first_link_job_index,
            final_output_key: final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for stale final leaf-object replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 1,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 1,
        final_output_key,
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist completed link execution index");

    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: final_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            level: 0,
            job_index: final_link_job_index,
            input_partition_count: 1,
            input_partition_indices: vec![0],
            input_frontend_job_count: 1,
            input_frontend_job_indices: vec![0],
            input_codegen_job_indices: vec![2],
            input_link_group_indices: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store current final leaf group with codegen job 2");
    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: final_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: final_link_job_index,
            input_interface_count: 1,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![SourcePackArtifactRef {
                artifact_index: 0,
                key: "library-interface/lib-0/job-0/src-0-1".into(),
                producing_job_index: 0,
                kind: SourcePackArtifactKind::LibraryInterface,
            }],
            input_object_count: 1,
            input_object_page_count: 0,
            input_objects: vec![SourcePackArtifactRef {
                artifact_index: 1,
                key: "codegen-object/lib-0/job-1/src-0-1".into(),
                producing_job_index: 1,
                kind: SourcePackArtifactKind::CodegenObject,
            }],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: execution_index.final_output_key.clone(),
            final_output: true,
            descriptor_summary: Default::default(),
        })
        .expect("store final leaf execution page with stale object artifact identity");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed replay must reject stale final leaf object inputs");
    let message = err.to_string();
    assert!(
        message.contains("object input jobs do not match current link group")
            && message.contains("persisted 1, current 2")
            && message.contains("current dense link-group evidence"),
        "expected stale final leaf object evidence error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove stale final leaf-object temp root");
}

#[test]
fn source_pack_link_execution_resume_rejects_stale_final_reduce_input_group() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_stale_reduce_input_group",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let first_link_job_index = 2;
    let final_link_group_index = 2;
    let final_link_job_index = 4;
    let final_output_key = "linked-output/job-2/src-0-1".to_string();
    let stale_partial_output_key = "partial-link/group-00000000/job-00000002".to_string();

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: first_link_job_index,
            job_count: first_link_job_index + 1,
        })
        .expect("store schedule index for stale reduce-input replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: first_link_job_index + 1,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: first_link_job_index,
            final_output_key: final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for stale reduce-input replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 3,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 3,
        final_output_key,
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist completed link execution index");

    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: final_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            level: 1,
            job_index: final_link_job_index,
            input_partition_count: 1,
            input_partition_indices: Vec::new(),
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_indices: Vec::new(),
            input_link_group_indices: vec![1],
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store current final reduce group with a different dense input group");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: first_link_job_index,
            input_interface_count: 1,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![SourcePackArtifactRef {
                artifact_index: 0,
                key: "library-interface/lib-0/job-0/src-0-1".into(),
                producing_job_index: 0,
                kind: SourcePackArtifactKind::LibraryInterface,
            }],
            input_object_count: 1,
            input_object_page_count: 0,
            input_objects: vec![SourcePackArtifactRef {
                artifact_index: 1,
                key: "codegen-object/lib-0/job-1/src-0-1".into(),
                producing_job_index: 1,
                kind: SourcePackArtifactKind::CodegenObject,
            }],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: stale_partial_output_key.clone(),
            final_output: false,
            descriptor_summary: Default::default(),
        })
        .expect("store stale partial-link producer that still satisfies completed replay evidence");
    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: final_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            job_index: final_link_job_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: Vec::new(),
            input_group_count: 1,
            input_group_page_count: 0,
            input_group_indices: vec![0],
            input_group_output_keys: vec![stale_partial_output_key],
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: execution_index.final_output_key.clone(),
            final_output: true,
            descriptor_summary: Default::default(),
        })
        .expect("store final reduce page with stale partial-link input identity");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed replay must reject stale reduce input group identity");
    let message = err.to_string();
    assert!(
        message.contains("partial-link input groups do not match current link group")
            && message.contains("persisted 0, current 1")
            && message.contains("current dense link-group evidence"),
        "expected stale reduce input group evidence error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove stale reduce-input temp root");
}

#[test]
fn source_pack_link_execution_resume_rejects_reduce_descriptor_summary_without_partial_evidence() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_reduce_descriptor_summary",
        None,
    );
    let mut store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let first_link_job_index = 2;
    let final_link_group_index = 1;
    let final_link_job_index = 3;
    let final_output_key = "linked-output/job-2/src-0-1".to_string();
    let partial_output_key = "partial-link/group-00000000/job-00000002".to_string();

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: first_link_job_index,
            job_count: first_link_job_index + 1,
        })
        .expect("store schedule index for descriptor-summary replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: 3,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: first_link_job_index,
            final_output_key: final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for descriptor-summary replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 2,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 2,
        final_output_key,
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist completed link execution index");

    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            level: 0,
            job_index: first_link_job_index,
            input_partition_count: 1,
            input_partition_indices: vec![0],
            input_frontend_job_count: 1,
            input_frontend_job_indices: vec![0],
            input_codegen_job_indices: vec![1],
            input_link_group_indices: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store partial-link producer group");
    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: final_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            level: 1,
            job_index: final_link_job_index,
            input_partition_count: 1,
            input_partition_indices: Vec::new(),
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_indices: Vec::new(),
            input_link_group_indices: vec![0],
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store final reduce group");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: first_link_job_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![SourcePackArtifactRef {
                artifact_index: 0,
                key: "library-interface/lib-0/job-0/src-0-1".into(),
                producing_job_index: 0,
                kind: SourcePackArtifactKind::LibraryInterface,
            }],
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: vec![SourcePackArtifactRef {
                artifact_index: 1,
                key: "codegen-object/lib-0/job-1/src-0-1".into(),
                producing_job_index: 1,
                kind: SourcePackArtifactKind::CodegenObject,
            }],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: partial_output_key.clone(),
            final_output: false,
            descriptor_summary: SourcePackLinkDescriptorSummary {
                object_section_count: 1,
                relocation_count: 1,
                ..SourcePackLinkDescriptorSummary::default()
            }
            .with_record_contracts_from_counts(),
        })
        .expect("store partial-link producer carrying descriptor evidence");
    let final_reduce_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: final_link_group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Reduce,
        job_index: final_link_job_index,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: Vec::new(),
        input_group_count: 0,
        input_group_page_count: 0,
        input_group_indices: vec![0],
        input_group_output_keys: vec![partial_output_key.clone()],
        source_byte_count: 16,
        source_file_count: 1,
        source_line_count: 1,
        output_key: execution_index.final_output_key.clone(),
        final_output: true,
        descriptor_summary: Default::default(),
    };
    store
        .store_hierarchical_link_execution_page(&final_reduce_page)
        .expect("store final reduce page consuming partial descriptor evidence");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed replay must reject descriptor-only partial-link evidence");
    let message = err.to_string();
    assert!(
        message.contains("descriptor summary requires concrete partial-link output artifact")
            && message.contains(&partial_output_key)
            && message.contains("descriptor summaries are not link artifact evidence"),
        "expected missing partial-link artifact evidence error, got {message}"
    );

    store
        .store_partial_link_output(
            &partial_output_key,
            b"partial-link-record-evidence".to_vec(),
        )
        .expect("store concrete partial-link artifact evidence");
    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed replay must not drop partial producer descriptor records");
    let message = err.to_string();
    assert!(
        message.contains("descriptor summary records 0 object section records")
            && message.contains("partial-link producer execution pages carry 1")
            && message.contains("cannot drop producer partial-link/object record evidence"),
        "expected dropped partial-link descriptor evidence error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove reduce descriptor-summary temp root");
}

#[test]
fn source_pack_link_execution_resume_requires_final_linked_output_artifact_evidence() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_final_descriptor_summary",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let first_link_job_index = 2;
    let final_link_group_index = 1;
    let final_link_job_index = 3;
    let final_output_key = "linked-output/job-2/src-0-1".to_string();
    let partial_output_key = "partial-link/group-00000000/job-00000002".to_string();

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: first_link_job_index,
            job_count: first_link_job_index + 1,
        })
        .expect("store schedule index for final descriptor replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: 3,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: first_link_job_index,
            final_output_key: final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for final descriptor replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 2,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 2,
        final_output_key,
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist completed link execution index");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: first_link_job_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![SourcePackArtifactRef {
                artifact_index: 0,
                key: "library-interface/lib-0/job-0/src-0-1".into(),
                producing_job_index: 0,
                kind: SourcePackArtifactKind::LibraryInterface,
            }],
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: vec![SourcePackArtifactRef {
                artifact_index: 1,
                key: "codegen-object/lib-0/job-1/src-0-1".into(),
                producing_job_index: 1,
                kind: SourcePackArtifactKind::CodegenObject,
            }],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: partial_output_key.clone(),
            final_output: false,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        })
        .expect("store partial-link producer execution page");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: final_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            job_index: final_link_job_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: Vec::new(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: vec![0],
            input_group_output_keys: vec![partial_output_key],
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: execution_index.final_output_key.clone(),
            final_output: true,
            descriptor_summary: SourcePackLinkDescriptorSummary {
                export_symbol_count: 1,
                ..SourcePackLinkDescriptorSummary::default()
            }
            .with_record_contracts_from_counts(),
        })
        .expect("store final page carrying linked-output descriptor evidence");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed replay must reject descriptor-only final output evidence");
    let message = err.to_string();
    assert!(
        message.contains("descriptor summary requires concrete linked-output artifact")
            && message.contains("linked-output/job-2/src-0-1")
            && message.contains("descriptor summaries are not link artifact evidence"),
        "expected missing linked-output artifact evidence error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove final descriptor-summary temp root");
}

#[test]
fn source_pack_link_execution_resume_requires_final_page_sidecar_evidence() {
    let root =
        common::temp_artifact_path("laniusc_package_boundaries", "link_sidecar_evidence", None);
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let final_output_key = "linked-output/job-2/src-0-1".to_string();

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: 2,
            job_count: 3,
        })
        .expect("store minimal schedule index for completed link replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: 3,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: 2,
            final_output_key: final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store minimal artifact-ref index for completed link replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index: 2,
        final_link_group_index: 0,
        final_link_job_index: 2,
        link_group_count: 1,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index: 2,
        final_link_group_index: 0,
        final_link_job_index: 2,
        link_group_count: 1,
        final_output_key,
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist completed link execution index");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: 2,
            input_interface_count: 1,
            input_interface_page_count: 1,
            input_interface_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 1,
            input_object_page_count: 1,
            input_objects: Vec::new(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: execution_index.final_output_key.clone(),
            final_output: true,
            descriptor_summary: Default::default(),
        })
        .expect("store final execution page that references paged link inputs");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed link execution must not resume without input sidecar evidence");
    let message = err.to_string();
    assert!(
        message.contains("requires interface input sidecar evidence")
            && message.contains("final group 0 page 0"),
        "expected missing final-page interface sidecar evidence error, got {message}"
    );

    store
        .store_hierarchical_link_execution_interface_page(
            &SourcePackHierarchicalLinkExecutionInterfacePage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_VERSION,
                target,
                group_index: 0,
                job_index: 2,
                page_index: 0,
                first_input_position: 0,
                input_count: 1,
                input_interfaces: vec![SourcePackArtifactRef {
                    artifact_index: 0,
                    key: "library-interface/lib-1/job-0/src-0-1".into(),
                    producing_job_index: 0,
                    kind: SourcePackArtifactKind::LibraryInterface,
                }],
            },
        )
        .expect("store final-page interface sidecar evidence");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed link execution must also require object sidecar evidence");
    let message = err.to_string();
    assert!(
        message.contains("requires object input sidecar evidence")
            && message.contains("final group 0 page 0"),
        "expected missing final-page object sidecar evidence error, got {message}"
    );

    store
        .store_hierarchical_link_execution_object_page(
            &SourcePackHierarchicalLinkExecutionObjectPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
                target,
                group_index: 0,
                job_index: 3,
                page_index: 0,
                first_input_position: 0,
                input_count: 1,
                input_objects: vec![SourcePackArtifactRef {
                    artifact_index: 1,
                    key: "codegen-object/lib-1/job-1/src-0-1".into(),
                    producing_job_index: 1,
                    kind: SourcePackArtifactKind::CodegenObject,
                }],
            },
        )
        .expect("store forged final-page object sidecar with mismatched link job");
    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed link execution must reject sidecars from a different link job");
    let message = err.to_string();
    assert!(
        message.contains("object input sidecar page 0 records job 3")
            && message.contains("final execution page records job 2"),
        "expected mismatched final-page object sidecar job error, got {message}"
    );

    store
        .store_hierarchical_link_execution_object_page(
            &SourcePackHierarchicalLinkExecutionObjectPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
                target,
                group_index: 0,
                job_index: 2,
                page_index: 0,
                first_input_position: 0,
                input_count: 1,
                input_objects: vec![SourcePackArtifactRef {
                    artifact_index: 1,
                    key: "codegen-object/lib-1/job-1/src-0-1".into(),
                    producing_job_index: 1,
                    kind: SourcePackArtifactKind::CodegenObject,
                }],
            },
        )
        .expect("store final-page object sidecar evidence");

    let resumed = prepare_link_execution_chunk(&root, target, 1)
        .expect("completed link execution index with final page and sidecars should resume");
    assert!(resumed.complete);
    assert_eq!(resumed.new_execution_page_count, 0);
    assert_eq!(
        resumed.hierarchical_link_execution_index_path.as_deref(),
        Some(execution_index_path.as_path())
    );

    std::fs::remove_dir_all(&root).expect("remove link-sidecar-evidence temp root");
}

#[test]
fn source_pack_link_execution_resume_requires_partial_input_group_execution_page_evidence() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_partial_input_page_evidence",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let first_link_job_index = 2;
    let final_link_group_index = 1;
    let final_link_job_index = 3;
    let final_output_key = "linked-output/job-2/src-0-1".to_string();
    let partial_output_key = "partial-link/group-00000000/job-00000002".to_string();

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: first_link_job_index,
            job_count: first_link_job_index + 1,
        })
        .expect("store minimal schedule index for completed reduce-link replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: first_link_job_index + 1,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: first_link_job_index,
            final_output_key: final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for completed reduce-link replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 2,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 2,
        final_output_key,
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist completed reduce-link execution index");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: final_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            job_index: final_link_job_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: Vec::new(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: vec![0],
            input_group_output_keys: vec![partial_output_key],
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: execution_index.final_output_key.clone(),
            final_output: true,
            descriptor_summary: Default::default(),
        })
        .expect("store final reduce execution page and partial-link input sidecar");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed reduce-link replay must require producer execution pages");
    let message = err.to_string();
    assert!(
        message.contains("partial-link input sidecar page 0")
            && message.contains("requires partial-link producer execution page evidence")
            && message.contains("input group 0"),
        "expected missing partial-input producer execution page evidence error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove partial-input evidence temp root");
}

#[test]
fn source_pack_link_execution_resume_rejects_unbound_runtime_services_from_partial_inputs() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_runtime_service_partial_evidence",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let first_link_job_index = 2;
    let final_link_group_index = 1;
    let final_link_job_index = 3;
    let final_output_key = "linked-output/job-2/src-0-1".to_string();
    let partial_output_key = "partial-link/group-00000000/job-00000002".to_string();

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: first_link_job_index,
            job_count: first_link_job_index + 1,
        })
        .expect("store schedule index for completed runtime-service replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: first_link_job_index + 1,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: first_link_job_index,
            final_output_key: final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for completed runtime-service replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 2,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 2,
        final_output_key,
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist completed reduce-link execution index");

    let mut partial_descriptor = SourcePackLinkDescriptorSummary::default();
    partial_descriptor.set_required_runtime_services([GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID]);
    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: first_link_job_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![SourcePackArtifactRef {
                artifact_index: 0,
                key: "library-interface/lib-1/job-0/src-0-1".into(),
                producing_job_index: 0,
                kind: SourcePackArtifactKind::LibraryInterface,
            }],
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: vec![SourcePackArtifactRef {
                artifact_index: 1,
                key: "codegen-object/lib-1/job-1/src-0-1".into(),
                producing_job_index: 1,
                kind: SourcePackArtifactKind::CodegenObject,
            }],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: partial_output_key.clone(),
            final_output: false,
            descriptor_summary: partial_descriptor,
        })
        .expect("store partial-link producer that still requires runtime services");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: final_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            job_index: final_link_job_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: Vec::new(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: vec![0],
            input_group_output_keys: vec![partial_output_key],
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: execution_index.final_output_key.clone(),
            final_output: true,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        })
        .expect("store final reduce execution page that consumes the partial-link producer");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed replay must fail closed until runtime binding evidence exists");
    let message = err.to_string();
    assert!(
        message.contains("unbound runtime services")
            && message.contains("partial-link producer execution page")
            && message.contains("runtime binding evidence"),
        "expected unbound runtime-service replay evidence error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove runtime-service partial evidence temp root");
}

#[test]
fn source_pack_link_execution_resume_rejects_stale_partial_input_source_summary() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_partial_input_source_summary",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let first_link_job_index = 2;
    let final_link_group_index = 1;
    let final_link_job_index = 3;
    let final_output_key = "linked-output/job-2/src-0-1".to_string();
    let partial_output_key = "partial-link/group-00000000/job-00000002".to_string();

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: first_link_job_index,
            job_count: first_link_job_index + 1,
        })
        .expect("store schedule index for stale partial-source replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: first_link_job_index + 1,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: first_link_job_index,
            final_output_key: final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for stale partial-source replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 2,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 2,
        final_output_key,
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist completed reduce-link execution index");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: first_link_job_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![SourcePackArtifactRef {
                artifact_index: 0,
                key: "library-interface/lib-1/job-0/src-0-1".into(),
                producing_job_index: 0,
                kind: SourcePackArtifactKind::LibraryInterface,
            }],
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: vec![SourcePackArtifactRef {
                artifact_index: 1,
                key: "codegen-object/lib-1/job-1/src-0-1".into(),
                producing_job_index: 1,
                kind: SourcePackArtifactKind::CodegenObject,
            }],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 15,
            source_file_count: 1,
            source_line_count: 1,
            output_key: partial_output_key.clone(),
            final_output: false,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        })
        .expect("store stale partial-link producer execution page");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: final_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            job_index: final_link_job_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: Vec::new(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: vec![0],
            input_group_output_keys: vec![partial_output_key],
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: execution_index.final_output_key.clone(),
            final_output: true,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        })
        .expect("store final reduce execution page with current source summary");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed replay must reject stale partial-link source evidence");
    let message = err.to_string();
    assert!(
        message.contains("partial input source summary bytes/files/lines 15/1/1")
            && message.contains("final page 16/1/1")
            && message.contains("stale partial-link source evidence"),
        "expected stale partial input source summary error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove stale partial-source temp root");
}

#[test]
fn source_pack_link_execution_resume_rejects_stale_partial_producer_leaf_inputs() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_partial_producer_stale_leaf_inputs",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let first_link_job_index = 3;
    let final_link_group_index = 1;
    let final_link_job_index = 4;
    let final_output_key = "linked-output/job-3/src-0-1".to_string();
    let partial_output_key = "partial-link/group-00000000/job-00000003".to_string();

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 2,
            link_job_index: first_link_job_index,
            job_count: first_link_job_index + 1,
        })
        .expect("store schedule index for stale partial producer replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: first_link_job_index + 1,
            interface_artifact_count: 1,
            object_artifact_count: 2,
            final_output_artifact_index: first_link_job_index,
            final_output_key: final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for stale partial producer replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 2,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 2,
        final_output_key,
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist completed reduce-link execution index");

    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            level: 0,
            job_index: first_link_job_index,
            input_partition_count: 1,
            input_partition_indices: vec![0],
            input_frontend_job_count: 1,
            input_frontend_job_indices: vec![0],
            input_codegen_job_indices: vec![2],
            input_link_group_indices: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store current partial producer leaf group");
    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: final_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            level: 1,
            job_index: final_link_job_index,
            input_partition_count: 1,
            input_partition_indices: Vec::new(),
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_indices: Vec::new(),
            input_link_group_indices: vec![0],
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store current final reduce group");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: first_link_job_index,
            input_interface_count: 1,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![SourcePackArtifactRef {
                artifact_index: 0,
                key: "library-interface/lib-1/job-0/src-0-1".into(),
                producing_job_index: 0,
                kind: SourcePackArtifactKind::LibraryInterface,
            }],
            input_object_count: 1,
            input_object_page_count: 0,
            input_objects: vec![SourcePackArtifactRef {
                artifact_index: 1,
                key: "codegen-object/lib-1/job-1/src-0-1".into(),
                producing_job_index: 1,
                kind: SourcePackArtifactKind::CodegenObject,
            }],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: partial_output_key.clone(),
            final_output: false,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        })
        .expect("store stale partial-link producer execution page");
    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: final_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            job_index: final_link_job_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: Vec::new(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: vec![0],
            input_group_output_keys: vec![partial_output_key],
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: execution_index.final_output_key.clone(),
            final_output: true,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        })
        .expect("store completed final reduce execution page");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed replay must reject stale partial producer leaf inputs");
    let message = err.to_string();
    assert!(
        message.contains("partial-link input sidecar page 0 producer group 0 object input jobs")
            && message.contains("persisted 1, current 2")
            && message.contains("current dense link-group evidence"),
        "expected stale partial producer leaf input error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove stale partial producer temp root");
}

#[test]
fn source_pack_link_execution_resume_rejects_stale_nested_partial_producer_leaf_inputs() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_nested_partial_producer_stale_leaf",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let first_link_job_index = 4;
    let intermediate_link_group_index = 1;
    let final_link_group_index = 2;
    let final_link_job_index = 6;
    let final_output_key = "linked-output/job-4/src-0-1".to_string();
    let leaf_partial_output_key = "partial-link/group-00000000/job-00000004".to_string();
    let reduce_partial_output_key = "partial-link/group-00000001/job-00000005".to_string();

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 3,
            link_job_index: first_link_job_index,
            job_count: first_link_job_index + 1,
        })
        .expect("store schedule index for nested stale partial producer replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: first_link_job_index + 1,
            interface_artifact_count: 1,
            object_artifact_count: 3,
            final_output_artifact_index: first_link_job_index,
            final_output_key: final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for nested stale partial producer replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 3,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: 3,
        final_output_key,
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist completed reduce-link execution index");

    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            level: 0,
            job_index: first_link_job_index,
            input_partition_count: 1,
            input_partition_indices: vec![0],
            input_frontend_job_count: 1,
            input_frontend_job_indices: vec![0],
            input_codegen_job_indices: vec![2],
            input_link_group_indices: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store current nested leaf producer group");
    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: intermediate_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            level: 1,
            job_index: first_link_job_index + intermediate_link_group_index,
            input_partition_count: 1,
            input_partition_indices: Vec::new(),
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_indices: Vec::new(),
            input_link_group_indices: vec![0],
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store current intermediate reduce group");
    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: final_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            level: 2,
            job_index: final_link_job_index,
            input_partition_count: 1,
            input_partition_indices: Vec::new(),
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_indices: Vec::new(),
            input_link_group_indices: vec![intermediate_link_group_index],
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store current final reduce group");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: first_link_job_index,
            input_interface_count: 1,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![SourcePackArtifactRef {
                artifact_index: 0,
                key: "library-interface/lib-1/job-0/src-0-1".into(),
                producing_job_index: 0,
                kind: SourcePackArtifactKind::LibraryInterface,
            }],
            input_object_count: 1,
            input_object_page_count: 0,
            input_objects: vec![SourcePackArtifactRef {
                artifact_index: 1,
                key: "codegen-object/lib-1/job-1/src-0-1".into(),
                producing_job_index: 1,
                kind: SourcePackArtifactKind::CodegenObject,
            }],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: leaf_partial_output_key.clone(),
            final_output: false,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        })
        .expect("store stale nested leaf producer execution page");
    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: intermediate_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            job_index: first_link_job_index + intermediate_link_group_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: Vec::new(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: vec![0],
            input_group_output_keys: vec![leaf_partial_output_key],
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: reduce_partial_output_key.clone(),
            final_output: false,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        })
        .expect("store intermediate reduce execution page");
    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: final_link_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            job_index: final_link_job_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: Vec::new(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: vec![intermediate_link_group_index],
            input_group_output_keys: vec![reduce_partial_output_key],
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: execution_index.final_output_key.clone(),
            final_output: true,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        })
        .expect("store completed final reduce execution page");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed replay must reject stale nested partial producer leaf inputs");
    let message = err.to_string();
    assert!(
        message.contains("producer group 0 object input jobs")
            && message.contains("persisted 1, current 2")
            && message.contains("current dense link-group evidence"),
        "expected stale nested partial producer leaf input error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove nested partial producer temp root");
}

#[test]
fn source_pack_link_execution_resume_requires_previous_group_execution_page_evidence() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_resume_tail_evidence",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let first_link_job_index = 2;

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: first_link_job_index,
            job_count: first_link_job_index + 1,
        })
        .expect("store schedule index for resumed link-execution replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: first_link_job_index + 1,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: first_link_job_index,
            final_output_key: "linked-output/job-2/src-0-1".into(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for resumed link-execution replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index,
        final_link_group_index: 1,
        final_link_job_index: first_link_job_index + 1,
        link_group_count: 2,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            level: 0,
            job_index: first_link_job_index,
            input_partition_count: 1,
            input_partition_indices: vec![0],
            input_frontend_job_count: 1,
            input_frontend_job_indices: vec![0],
            input_codegen_job_indices: vec![1],
            input_link_group_indices: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store current link group that progress claims has already been prepared");

    let progress_path = store.link_execution_prepare_progress_path_for_target(target);
    std::fs::create_dir_all(progress_path.parent().expect("link progress parent"))
        .expect("create link progress dir");
    std::fs::write(
        &progress_path,
        serde_json::to_vec_pretty(&serde_json::json!({
            "version": SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_VERSION,
            "target": target,
            "link_group_count": 2,
            "next_group_index": 1,
            "final_output_seen": false,
        }))
        .expect("serialize resumable link-execution progress"),
    )
    .expect("persist resumable link-execution progress");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("resumed link execution must prove the previous prepared page still exists");
    let message = err.to_string();
    assert!(
        message.contains("resumable source-pack link execution progress at group 1")
            && message.contains("requires execution page evidence for prepared group 0"),
        "expected missing previous execution page replay evidence error, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, 1)
            .exists(),
        "rejected replay progress must not continue to the next execution page"
    );

    std::fs::remove_dir_all(&root).expect("remove link replay tail evidence temp root");
}

#[test]
fn source_pack_link_execution_resume_requires_reduce_tail_partial_producer_evidence() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_resume_reduce_tail_producer_evidence",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let first_link_job_index = 2;
    let reduce_group_index = 1;
    let next_group_index = 2;

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: first_link_job_index,
            job_count: first_link_job_index + 1,
        })
        .expect("store schedule index for resumed reduce-tail replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: first_link_job_index + 1,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: first_link_job_index,
            final_output_key: "linked-output/job-2/src-0-1".into(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for resumed reduce-tail replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index,
        final_link_group_index: 2,
        final_link_job_index: first_link_job_index + 2,
        link_group_count: 3,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            level: 0,
            job_index: first_link_job_index,
            input_partition_count: 1,
            input_partition_indices: vec![0],
            input_frontend_job_count: 1,
            input_frontend_job_indices: vec![0],
            input_codegen_job_indices: vec![1],
            input_link_group_indices: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store current partial producer link group without its execution page");
    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: reduce_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            level: 1,
            job_index: first_link_job_index + reduce_group_index,
            input_partition_count: 1,
            input_partition_indices: Vec::new(),
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_indices: Vec::new(),
            input_link_group_indices: vec![0],
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store current reduce link group");
    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: reduce_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            job_index: first_link_job_index + reduce_group_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: Vec::new(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: vec![0],
            input_group_output_keys: vec!["partial-link/group-00000000/job-00000002".into()],
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: "partial-link/group-00000001/job-00000003".into(),
            final_output: false,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        })
        .expect("store prepared reduce execution page with inline partial-link input");

    let progress_path = store.link_execution_prepare_progress_path_for_target(target);
    std::fs::create_dir_all(progress_path.parent().expect("link progress parent"))
        .expect("create link progress dir");
    std::fs::write(
        &progress_path,
        serde_json::to_vec_pretty(&serde_json::json!({
            "version": SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_VERSION,
            "target": target,
            "link_group_count": 3,
            "next_group_index": next_group_index,
            "final_output_seen": false,
        }))
        .expect("serialize resumable link-execution progress"),
    )
    .expect("persist resumable link-execution progress");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("resumed reduce progress must prove partial-link producer pages still exist");
    let message = err.to_string();
    assert!(
        message.contains("resumable source-pack link execution progress at group 2")
            && message.contains("prepared reduce group 1")
            && message.contains("requires partial-link producer execution page evidence")
            && message.contains("input group 0"),
        "expected missing reduce-tail producer evidence error, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, next_group_index)
            .exists(),
        "rejected replay progress must not continue to the next execution page"
    );

    std::fs::remove_dir_all(&root).expect("remove reduce-tail producer evidence temp root");
}

#[test]
fn source_pack_link_execution_resume_requires_previous_group_sidecar_evidence() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_resume_tail_sidecars",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let first_link_job_index = 2;

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: 1,
            link_job_index: first_link_job_index,
            job_count: first_link_job_index + 1,
        })
        .expect("store schedule index for resumed link-execution sidecar replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: first_link_job_index + 1,
            interface_artifact_count: 1,
            object_artifact_count: 1,
            final_output_artifact_index: first_link_job_index,
            final_output_key: "linked-output/job-2/src-0-1".into(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for resumed link-execution sidecar replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index,
        final_link_group_index: 1,
        final_link_job_index: first_link_job_index + 1,
        link_group_count: 2,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            level: 0,
            job_index: first_link_job_index,
            input_partition_count: 1,
            input_partition_indices: vec![0],
            input_frontend_job_count: 1,
            input_frontend_job_indices: vec![0],
            input_codegen_job_indices: vec![1],
            input_link_group_indices: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store current link group that progress claims has already been prepared");
    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: first_link_job_index,
            input_interface_count: 1,
            input_interface_page_count: 1,
            input_interface_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 1,
            input_object_page_count: 1,
            input_objects: Vec::new(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: "partial-link/group-00000000/job-00000002".into(),
            final_output: false,
            descriptor_summary: Default::default(),
        })
        .expect("store prepared execution page that references missing sidecars");

    let progress_path = store.link_execution_prepare_progress_path_for_target(target);
    std::fs::create_dir_all(progress_path.parent().expect("link progress parent"))
        .expect("create link progress dir");
    std::fs::write(
        &progress_path,
        serde_json::to_vec_pretty(&serde_json::json!({
            "version": SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_VERSION,
            "target": target,
            "link_group_count": 2,
            "next_group_index": 1,
            "final_output_seen": false,
        }))
        .expect("serialize resumable link-execution progress"),
    )
    .expect("persist resumable link-execution progress");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("resumed link execution must prove prepared input sidecars still exist");
    let message = err.to_string();
    assert!(
        message.contains("resumable source-pack link execution progress at group 1")
            && message.contains("requires interface input sidecar evidence")
            && message.contains("prepared group 0 page 0"),
        "expected missing replay-tail sidecar evidence error, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, 1)
            .exists(),
        "rejected replay progress must not continue to the next execution page"
    );

    std::fs::remove_dir_all(&root).expect("remove link replay tail sidecar temp root");
}

#[test]
fn source_pack_link_execution_resume_rejects_previous_group_summary_mismatch_before_sidecars() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_resume_sparse_tail_sidecars",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let object_page_capacity = SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE;
    let object_input_count = object_page_capacity + 1;
    let first_link_job_index = object_input_count + 1;

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: object_input_count,
            link_job_index: first_link_job_index,
            job_count: first_link_job_index + 1,
        })
        .expect("store schedule index for resumed sparse sidecar replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: first_link_job_index + 1,
            interface_artifact_count: 1,
            object_artifact_count: object_input_count,
            final_output_artifact_index: first_link_job_index,
            final_output_key: format!("linked-output/job-{first_link_job_index}/src-0-1"),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for resumed sparse sidecar replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: object_page_capacity,
        first_link_job_index,
        final_link_group_index: 1,
        final_link_job_index: first_link_job_index + 1,
        link_group_count: 2,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let input_codegen_job_indices = (1..=object_page_capacity).collect::<Vec<_>>();
    store
        .store_hierarchical_link_group_page(&SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            level: 0,
            job_index: first_link_job_index,
            input_partition_count: object_page_capacity,
            input_partition_indices: (0..object_page_capacity).collect(),
            input_frontend_job_count: object_page_capacity,
            input_frontend_job_indices: (0..object_page_capacity).collect(),
            input_codegen_job_indices,
            input_link_group_indices: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        })
        .expect("store current link group with paged object inputs");
    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: first_link_job_index,
            input_interface_count: 1,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![SourcePackArtifactRef {
                artifact_index: 0,
                key: "library-interface/lib-1/job-0/src-0-1".into(),
                producing_job_index: 0,
                kind: SourcePackArtifactKind::LibraryInterface,
            }],
            input_object_count: object_input_count,
            input_object_page_count: 0,
            input_objects: (1..=object_input_count)
                .map(|job_index| SourcePackArtifactRef {
                    artifact_index: job_index,
                    key: format!("codegen-object/lib-1/job-{job_index}/src-0-1"),
                    producing_job_index: job_index,
                    kind: SourcePackArtifactKind::CodegenObject,
                })
                .collect(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: format!("partial-link/group-00000000/job-{first_link_job_index:08}"),
            final_output: false,
            descriptor_summary: Default::default(),
        })
        .expect("store prepared execution page with two paged object sidecars");

    store
        .store_hierarchical_link_execution_object_page(
            &SourcePackHierarchicalLinkExecutionObjectPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
                target,
                group_index: 0,
                job_index: first_link_job_index,
                page_index: 0,
                first_input_position: 0,
                input_count: 1,
                input_objects: vec![SourcePackArtifactRef {
                    artifact_index: 1,
                    key: "codegen-object/lib-1/job-1/src-0-1".into(),
                    producing_job_index: 1,
                    kind: SourcePackArtifactKind::CodegenObject,
                }],
            },
        )
        .expect("store sparse first object sidecar page");
    let second_page_inputs = (2..=object_input_count)
        .map(|job_index| SourcePackArtifactRef {
            artifact_index: job_index,
            key: format!("codegen-object/lib-1/job-{job_index}/src-0-1"),
            producing_job_index: job_index,
            kind: SourcePackArtifactKind::CodegenObject,
        })
        .collect::<Vec<_>>();
    assert_eq!(
        second_page_inputs.len(),
        object_page_capacity,
        "fixture should make the first page sparse while keeping total evidence count correct"
    );
    store
        .store_hierarchical_link_execution_object_page(
            &SourcePackHierarchicalLinkExecutionObjectPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
                target,
                group_index: 0,
                job_index: first_link_job_index,
                page_index: 1,
                first_input_position: object_page_capacity,
                input_count: second_page_inputs.len(),
                input_objects: second_page_inputs,
            },
        )
        .expect("store full second object sidecar page");

    let progress_path = store.link_execution_prepare_progress_path_for_target(target);
    std::fs::create_dir_all(progress_path.parent().expect("link progress parent"))
        .expect("create link progress dir");
    std::fs::write(
        &progress_path,
        serde_json::to_vec_pretty(&serde_json::json!({
            "version": SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_VERSION,
            "target": target,
            "link_group_count": 2,
            "next_group_index": 1,
            "final_output_seen": false,
        }))
        .expect("serialize resumable link-execution progress"),
    )
    .expect("persist resumable link-execution progress");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("resumed progress must reject previous-group summary drift before sidecars");
    let message = err.to_string();
    assert!(
        message.contains("group 0 input summary interfaces/objects/groups 1/65/0")
            && message.contains("does not match current link group 64/64/0"),
        "expected previous-group input summary mismatch error, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, 1)
            .exists(),
        "rejected replay progress must not continue to the next execution page"
    );

    std::fs::remove_dir_all(&root).expect("remove sparse replay-tail sidecar temp root");
}

#[test]
fn source_pack_link_execution_resume_rejects_sparse_final_page_sidecars() {
    let root =
        common::temp_artifact_path("laniusc_package_boundaries", "link_sparse_sidecars", None);
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let object_page_capacity = SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE;
    let object_input_count = object_page_capacity + 1;
    let link_job_index = object_input_count + 1;
    let final_output_key = format!("linked-output/job-{link_job_index}/src-0-1");

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: object_input_count,
            link_job_index,
            job_count: link_job_index + 1,
        })
        .expect("store schedule index for sparse completed link replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: link_job_index + 1,
            interface_artifact_count: 1,
            object_artifact_count: object_input_count,
            final_output_artifact_index: link_job_index,
            final_output_key: final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for sparse completed link replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index: link_job_index,
        final_link_group_index: 0,
        final_link_job_index: link_job_index,
        link_group_count: 1,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index: link_job_index,
        final_link_group_index: 0,
        final_link_job_index: link_job_index,
        link_group_count: 1,
        final_output_key,
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist completed link execution index");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: link_job_index,
            input_interface_count: 1,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![SourcePackArtifactRef {
                artifact_index: 0,
                key: "library-interface/lib-1/job-0/src-0-1".into(),
                producing_job_index: 0,
                kind: SourcePackArtifactKind::LibraryInterface,
            }],
            input_object_count: object_input_count,
            input_object_page_count: 0,
            input_objects: (1..=object_input_count)
                .map(|job_index| SourcePackArtifactRef {
                    artifact_index: job_index,
                    key: format!("codegen-object/lib-1/job-{job_index}/src-0-1"),
                    producing_job_index: job_index,
                    kind: SourcePackArtifactKind::CodegenObject,
                })
                .collect(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: execution_index.final_output_key.clone(),
            final_output: true,
            descriptor_summary: Default::default(),
        })
        .expect("store final execution page with two paged object sidecars");

    store
        .store_hierarchical_link_execution_object_page(
            &SourcePackHierarchicalLinkExecutionObjectPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
                target,
                group_index: 0,
                job_index: link_job_index,
                page_index: 0,
                first_input_position: 0,
                input_count: 1,
                input_objects: vec![SourcePackArtifactRef {
                    artifact_index: 1,
                    key: "codegen-object/lib-1/job-1/src-0-1".into(),
                    producing_job_index: 1,
                    kind: SourcePackArtifactKind::CodegenObject,
                }],
            },
        )
        .expect("store sparse first object sidecar page");
    let second_page_inputs = (2..=object_input_count)
        .map(|job_index| SourcePackArtifactRef {
            artifact_index: job_index,
            key: format!("codegen-object/lib-1/job-{job_index}/src-0-1"),
            producing_job_index: job_index,
            kind: SourcePackArtifactKind::CodegenObject,
        })
        .collect::<Vec<_>>();
    assert_eq!(
        second_page_inputs.len(),
        object_page_capacity,
        "fixture should fill the second sidecar page while leaving the first sparse"
    );
    store
        .store_hierarchical_link_execution_object_page(
            &SourcePackHierarchicalLinkExecutionObjectPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
                target,
                group_index: 0,
                job_index: link_job_index,
                page_index: 1,
                first_input_position: object_page_capacity,
                input_count: second_page_inputs.len(),
                input_objects: second_page_inputs,
            },
        )
        .expect("store second object sidecar page after the sparse first page");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed link execution must reject sparse sidecar evidence");
    let message = err.to_string();
    assert!(
        message.contains("object input sidecar page 0 records 1 inputs before later sidecar pages")
            && message.contains("cannot hide missing link input evidence"),
        "expected sparse final-page object sidecar evidence error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove sparse sidecar temp root");
}

#[test]
fn source_pack_link_execution_resume_rejects_noncanonical_final_sidecar_page_sequence() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "link_sidecar_page_order",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let object_page_capacity = SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE;
    let object_input_count = object_page_capacity * 2;
    let link_job_index = object_input_count + 1;
    let final_output_key = format!("linked-output/job-{link_job_index}/src-0-1");

    store
        .store_library_schedule_index(&SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target,
            partition_count: 1,
            frontend_job_count: 1,
            codegen_job_count: object_input_count,
            link_job_index,
            job_count: link_job_index + 1,
        })
        .expect("store schedule index for completed link sidecar-order replay");
    store
        .store_build_artifact_ref_index(&SourcePackBuildArtifactRefIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
            target,
            artifact_count: link_job_index + 1,
            interface_artifact_count: 1,
            object_artifact_count: object_input_count,
            final_output_artifact_index: link_job_index,
            final_output_key: final_output_key.clone(),
            total_source_file_count: 1,
            total_source_byte_count: 16,
            total_source_line_count: 1,
        })
        .expect("store artifact-ref index for completed link sidecar-order replay");

    let plan_index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        input_partition_count: 1,
        first_link_job_index: link_job_index,
        final_link_group_index: 0,
        final_link_job_index: link_job_index,
        link_group_count: 1,
    };
    let plan_path = store.hierarchical_link_plan_index_path_for_target(target);
    std::fs::create_dir_all(plan_path.parent().expect("link plan parent"))
        .expect("create link plan dir");
    std::fs::write(
        &plan_path,
        serde_json::to_vec_pretty(&plan_index).expect("serialize link plan index"),
    )
    .expect("persist link plan index");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index: link_job_index,
        final_link_group_index: 0,
        final_link_job_index: link_job_index,
        link_group_count: 1,
        final_output_key,
    };
    let execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        execution_index_path
            .parent()
            .expect("link execution parent"),
    )
    .expect("create link execution dir");
    std::fs::write(
        &execution_index_path,
        serde_json::to_vec_pretty(&execution_index).expect("serialize link execution index"),
    )
    .expect("persist completed link execution index");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: link_job_index,
            input_interface_count: 1,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![SourcePackArtifactRef {
                artifact_index: 0,
                key: "library-interface/lib-1/job-0/src-0-1".into(),
                producing_job_index: 0,
                kind: SourcePackArtifactKind::LibraryInterface,
            }],
            input_object_count: object_input_count,
            input_object_page_count: 0,
            input_objects: (1..=object_input_count)
                .map(|job_index| SourcePackArtifactRef {
                    artifact_index: job_index,
                    key: format!("codegen-object/lib-1/job-{job_index}/src-0-1"),
                    producing_job_index: job_index,
                    kind: SourcePackArtifactKind::CodegenObject,
                })
                .collect(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: execution_index.final_output_key.clone(),
            final_output: true,
            descriptor_summary: Default::default(),
        })
        .expect("store final execution page with two paged object sidecars");

    let first_page_inputs = (0..object_page_capacity)
        .map(|offset| {
            let producer_job_index = object_page_capacity + 1 + offset;
            SourcePackArtifactRef {
                artifact_index: producer_job_index,
                key: format!("codegen-object/lib-1/job-{producer_job_index}/src-0-1"),
                producing_job_index: producer_job_index,
                kind: SourcePackArtifactKind::CodegenObject,
            }
        })
        .collect::<Vec<_>>();
    store
        .store_hierarchical_link_execution_object_page(
            &SourcePackHierarchicalLinkExecutionObjectPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
                target,
                group_index: 0,
                job_index: link_job_index,
                page_index: 0,
                first_input_position: 0,
                input_count: first_page_inputs.len(),
                input_objects: first_page_inputs,
            },
        )
        .expect("store locally canonical first object sidecar page");

    let second_page_inputs = (1..=object_page_capacity)
        .map(|producer_job_index| SourcePackArtifactRef {
            artifact_index: producer_job_index,
            key: format!("codegen-object/lib-1/job-{producer_job_index}/src-0-1"),
            producing_job_index: producer_job_index,
            kind: SourcePackArtifactKind::CodegenObject,
        })
        .collect::<Vec<_>>();
    store
        .store_hierarchical_link_execution_object_page(
            &SourcePackHierarchicalLinkExecutionObjectPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
                target,
                group_index: 0,
                job_index: link_job_index,
                page_index: 1,
                first_input_position: object_page_capacity,
                input_count: second_page_inputs.len(),
                input_objects: second_page_inputs,
            },
        )
        .expect("store locally canonical second object sidecar page");

    let err = prepare_link_execution_chunk(&root, target, 1)
        .expect_err("completed link execution must reject globally noncanonical sidecars");
    let message = err.to_string();
    assert!(
        message.contains("object input sidecar page 1")
            && message.contains("globally strictly ascending")
            && message
                .contains("completed indexes cannot hide duplicate or missing link input evidence"),
        "expected completed sidecar page-order error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove sidecar-order temp root");
}

#[test]
fn source_pack_link_execution_inputs_reject_noncanonical_record_order() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "link_record_order", None);
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;

    let object_page = SourcePackHierarchicalLinkExecutionObjectPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
        target,
        group_index: 0,
        job_index: 7,
        page_index: 0,
        first_input_position: 0,
        input_count: 2,
        input_objects: vec![
            SourcePackArtifactRef {
                artifact_index: 2,
                key: "wasm/codegen-object/lib-0/job-2/src-0-1".into(),
                producing_job_index: 2,
                kind: SourcePackArtifactKind::CodegenObject,
            },
            SourcePackArtifactRef {
                artifact_index: 3,
                key: "wasm/codegen-object/lib-0/job-3/src-0-1".into(),
                producing_job_index: 3,
                kind: SourcePackArtifactKind::CodegenObject,
            },
        ],
    };
    store
        .store_hierarchical_link_execution_object_page(&object_page)
        .expect("canonical object artifact refs should persist as link inputs");

    let mut unsorted_object_page = object_page;
    unsorted_object_page.group_index = 1;
    unsorted_object_page.input_objects.reverse();
    let err = store
        .store_hierarchical_link_execution_object_page(&unsorted_object_page)
        .expect_err("object artifact refs must be persisted in producer order");
    let message = err.to_string();
    assert!(
        message.contains("producer jobs")
            && message.contains("strictly ascending")
            && message.contains("producer job 2 follows 3"),
        "expected noncanonical object-ref order error, got {message}"
    );

    let partial_key =
        |group: usize, job: usize| format!("wasm/partial-link/group-{group:08}/job-{job:08}");
    let partial_page = SourcePackHierarchicalLinkExecutionPartialPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION,
        target,
        group_index: 4,
        job_index: 24,
        page_index: 0,
        first_input_position: 0,
        input_count: 2,
        input_group_indices: vec![1, 2],
        input_group_output_keys: vec![partial_key(1, 21), partial_key(2, 22)],
    };
    store
        .store_hierarchical_link_execution_partial_page(&partial_page)
        .expect("canonical partial-link input records should persist");

    let mut unsorted_partial_page = partial_page;
    unsorted_partial_page.group_index = 5;
    unsorted_partial_page.job_index = 25;
    unsorted_partial_page.input_group_indices = vec![2, 1];
    unsorted_partial_page.input_group_output_keys = vec![partial_key(2, 22), partial_key(1, 21)];
    let err = store
        .store_hierarchical_link_execution_partial_page(&unsorted_partial_page)
        .expect_err("partial-link inputs must be persisted in group order");
    let message = err.to_string();
    assert!(
        message.contains("partial page 5:0 input groups") && message.contains("strictly ascending"),
        "expected noncanonical partial-link input order error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove link record order temp root");
}

#[test]
fn source_pack_link_execution_rejects_descriptor_summary_without_artifact_evidence() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "descriptor_only_link_state",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let group_index = 0;
    let link_job_index = 7;

    let descriptor_only_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: link_job_index,
        input_interface_count: 1,
        input_interface_page_count: 1,
        input_interface_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: 1,
        input_object_page_count: 1,
        input_objects: Vec::new(),
        input_group_count: 0,
        input_group_page_count: 0,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: "partial-link/group-00000000/job-00000007".into(),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            interface_symbol_count: 1,
            object_symbol_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        },
    };

    let err = store
        .store_hierarchical_link_execution_page(&descriptor_only_page)
        .expect_err(
            "descriptor summaries should not let package linking persist missing artifacts",
        );
    let message = err.to_string();
    assert!(
        message.contains("descriptor summary")
            && message.contains("interface artifact refs")
            && message.contains("object artifact refs")
            && message.contains("not link artifact evidence"),
        "expected descriptor-only link artifact evidence error, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, group_index)
            .exists(),
        "rejected descriptor-only link state must not publish an execution page"
    );

    if root.exists() {
        std::fs::remove_dir_all(&root).expect("remove descriptor-only link state temp root");
    }
}

#[test]
fn source_pack_link_execution_rejects_empty_final_output_source_range() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "empty_final_output_source_range",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let group_index = 0;
    let link_job_index = 7;

    let empty_final_output_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: link_job_index,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: vec![SourcePackArtifactRef {
            artifact_index: 1,
            key: "library-interface/lib-0/job-1/src-0-1".into(),
            producing_job_index: 1,
            kind: SourcePackArtifactKind::LibraryInterface,
        }],
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: vec![SourcePackArtifactRef {
            artifact_index: 2,
            key: "codegen-object/lib-0/job-2/src-0-1".into(),
            producing_job_index: 2,
            kind: SourcePackArtifactKind::CodegenObject,
        }],
        input_group_count: 0,
        input_group_page_count: 0,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 0,
        source_file_count: 0,
        source_line_count: 0,
        output_key: "linked-output/job-7/src-0-0".into(),
        final_output: true,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };

    let err = store
        .store_hierarchical_link_execution_page(&empty_final_output_page)
        .expect_err("final linked-output pages must not persist empty source ranges");
    let message = err.to_string();
    assert!(
        message.contains("final linked output key")
            && message.contains("empty source range 0..0")
            && message.contains("at least one source file"),
        "expected empty final-output source-range rejection, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, group_index)
            .exists(),
        "rejected empty final-output page must not be persisted"
    );

    if root.exists() {
        std::fs::remove_dir_all(&root).expect("remove empty final-output temp root");
    }
}

#[test]
fn source_pack_link_execution_rejects_noncanonical_descriptor_record_contract_order() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "descriptor_contract_order",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let group_index = 0;
    let link_job_index = 7;

    let mut descriptor_summary = SourcePackLinkDescriptorSummary {
        interface_symbol_count: 1,
        object_section_count: 1,
        object_symbol_count: 1,
        ..SourcePackLinkDescriptorSummary::default()
    }
    .with_record_contracts_from_counts();
    descriptor_summary.record_contracts.reverse();

    let noncanonical_contract_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: link_job_index,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: vec![SourcePackArtifactRef {
            artifact_index: 1,
            key: "library-interface/lib-0/job-1/src-0-1".into(),
            producing_job_index: 1,
            kind: SourcePackArtifactKind::LibraryInterface,
        }],
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: vec![SourcePackArtifactRef {
            artifact_index: 2,
            key: "codegen-object/lib-0/job-2/src-0-1".into(),
            producing_job_index: 2,
            kind: SourcePackArtifactKind::CodegenObject,
        }],
        input_group_count: 0,
        input_group_page_count: 0,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: "partial-link/group-00000000/job-00000007".into(),
        final_output: false,
        descriptor_summary,
    };

    let err = store
        .store_hierarchical_link_execution_page(&noncanonical_contract_page)
        .expect_err("descriptor record contracts must replay in canonical counts-derived order");
    let message = err.to_string();
    assert!(
        message.contains("explicit link record contracts")
            && message.contains("canonical counts-derived sequence")
            && message.contains("descriptor-only link evidence"),
        "expected noncanonical descriptor contract order error, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, group_index)
            .exists(),
        "rejected descriptor contract order must not publish an execution page"
    );

    if root.exists() {
        std::fs::remove_dir_all(&root).expect("remove descriptor contract order temp root");
    }
}

#[test]
fn source_pack_link_execution_rejects_descriptor_summary_with_forged_object_artifact_identity() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "forged_link_object_identity",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let group_index = 0;
    let link_job_index = 7;

    let forged_object_identity_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: link_job_index,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: vec![SourcePackArtifactRef {
            artifact_index: 1,
            key: "library-interface/lib-0/job-1/src-0-1".into(),
            producing_job_index: 1,
            kind: SourcePackArtifactKind::LibraryInterface,
        }],
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: vec![SourcePackArtifactRef {
            artifact_index: 42,
            key: "codegen-object/lib-0/job-2/src-0-1".into(),
            producing_job_index: 2,
            kind: SourcePackArtifactKind::CodegenObject,
        }],
        input_group_count: 0,
        input_group_page_count: 0,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: "partial-link/group-00000000/job-00000007".into(),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            object_section_count: 1,
            relocation_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        }
        .with_record_contracts_from_counts(),
    };

    let err = store
        .store_hierarchical_link_execution_page(&forged_object_identity_page)
        .expect_err("descriptor-backed object refs must use dense GPU producer identities");
    let message = err.to_string();
    assert!(
        message.contains("artifact index 42")
            && message.contains("producer job 2")
            && message.contains("producer-owned CodegenObject evidence"),
        "expected forged object identity rejection, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, group_index)
            .exists(),
        "rejected forged object identity must not publish an execution page"
    );

    if root.exists() {
        std::fs::remove_dir_all(&root).expect("remove forged object identity temp root");
    }
}

#[test]
fn source_pack_link_execution_rejects_sidecar_with_impossible_dense_link_job() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "impossible_link_sidecar_job",
        None,
    );
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let group_index = 3;
    let page_index = 0;

    let impossible_dense_job_sidecar = SourcePackHierarchicalLinkExecutionObjectPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
        target,
        group_index,
        job_index: 2,
        page_index,
        first_input_position: 0,
        input_count: 1,
        input_objects: vec![SourcePackArtifactRef {
            artifact_index: 1,
            key: "codegen-object/lib-0/job-1/src-0-1".into(),
            producing_job_index: 1,
            kind: SourcePackArtifactKind::CodegenObject,
        }],
    };

    let err = store
        .store_hierarchical_link_execution_object_page(&impossible_dense_job_sidecar)
        .expect_err("link sidecars must not publish impossible dense link slots");
    let message = err.to_string();
    assert!(
        message.contains("object page 3:0")
            && message.contains("link job 2")
            && message.contains("dense group index 3")
            && message.contains("input artifact evidence"),
        "expected impossible dense-link sidecar rejection, got {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_object_page_path_for_target(
                target,
                group_index,
                page_index
            )
            .exists(),
        "rejected sidecar input evidence must not be persisted"
    );

    if root.exists() {
        std::fs::remove_dir_all(&root).expect("remove impossible link sidecar temp root");
    }
}

#[test]
fn source_pack_work_queue_rejects_link_reduce_input_missing_from_dependency_sidecar() {
    let root =
        common::temp_artifact_path("laniusc_package_boundaries", "work_queue_reduce_deps", None);
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let link_item_index = 6;
    let link_group_index = 3;
    let input_link_group_index = 1;
    let required_input_item_index = link_item_index - link_group_index + input_link_group_index;

    store
        .store_work_queue_page(&SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index: link_item_index,
            kind: SourcePackWorkQueueItemKind::LinkReduce,
            job_index: link_item_index,
            dependency_item_indices: vec![required_input_item_index],
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
            link_group_index: Some(link_group_index),
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 0,
            input_codegen_job_indices: Vec::new(),
            input_link_group_count: 1,
            input_link_group_indices: vec![input_link_group_index],
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        })
        .expect("valid link reduce page should persist its dependency sidecar");

    let tampered_dependency_page = SourcePackWorkQueueDependenciesPage {
        version: SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_PAGE_VERSION,
        target,
        item_index: link_item_index,
        page_index: 0,
        first_dependency_position: 0,
        dependency_count: 1,
        dependency_item_indices: vec![required_input_item_index - 1],
    };
    let dependency_page_path =
        store.work_queue_dependencies_page_path_for_target(target, link_item_index, 0);
    std::fs::write(
        &dependency_page_path,
        serde_json::to_vec_pretty(&tampered_dependency_page)
            .expect("serialize tampered dependency sidecar"),
    )
    .expect("tamper persisted dependency sidecar");

    let err = store
        .load_work_queue_page_for_target(target, link_item_index)
        .expect_err("persisted link reduce pages must fail closed when a partial-link input is not dependency-ready");
    let message = err.to_string();
    assert!(
        message.contains("link-group input items")
            && message.contains("not listed as dependencies")
            && message.contains(&required_input_item_index.to_string()),
        "expected missing link-group dependency error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove work queue reduce dependency temp root");
}

#[test]
fn source_pack_metadata_chunks_preserve_large_library_dependency_fan_in() {
    let root = common::temp_artifact_path("laniusc_source_pack_dependencies", "fan_in", None);
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    std::fs::create_dir_all(&source_root).expect("create fan-in source root");

    let dependency_count = SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE + 1;
    let dependent_library_id = 10_000u32;
    let mut libraries = Vec::new();
    for library_id in 0..u32::try_from(dependency_count).expect("dependency count fits u32") {
        let path = source_root.join(format!("lib_{library_id}.lani"));
        std::fs::write(
            &path,
            format!("module lib_{library_id};\npub const VALUE: i32 = {library_id};\n"),
        )
        .expect("write dependency source");
        libraries.push((library_id, path, Vec::<u32>::new()));
    }

    let dependent_path = source_root.join("app.lani");
    std::fs::write(&dependent_path, "module app;\nfn main() { return 0; }\n")
        .expect("write dependent source");
    let expected_dependency_ids = (0..u32::try_from(dependency_count)
        .expect("dependency count fits u32"))
        .collect::<Vec<_>>();
    libraries.push((
        dependent_library_id,
        dependent_path,
        expected_dependency_ids.clone(),
    ));

    let streams = || {
        libraries.iter().map(|(library_id, path, dependencies)| {
            ExplicitSourceLibraryPathDependencyStream {
                library_id: *library_id,
                source_file_count: 1,
                paths: std::iter::once(path.as_path()),
                dependency_library_count: dependencies.len(),
                dependency_library_ids: dependencies.clone().into_iter(),
            }
        })
    };

    let mut metadata_complete = false;
    for chunk_index in 0..=libraries.len() {
        let step = prepare_metadata_chunk_for_target(
            streams(),
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE,
        )
        .unwrap_or_else(|err| panic!("prepare dependency metadata chunk {chunk_index}: {err}"));
        if step.complete {
            metadata_complete = true;
            break;
        }
        assert!(
            step.new_library_count > 0,
            "metadata preparation should make bounded progress before completion"
        );
    }
    assert!(
        metadata_complete,
        "metadata preparation should complete after bounded chunks"
    );

    let store = FilesystemArtifactStore::new(&artifact_root);
    let locator = store
        .load_library_partition_locator_page_for_target(
            SourcePackArtifactTarget::Wasm,
            dependent_library_id,
        )
        .expect("load dependent library partition locator");
    let partition = store
        .load_library_partition_for_target(SourcePackArtifactTarget::Wasm, locator.partition_index)
        .expect("load dependent library partition");
    assert_eq!(
        partition.dependency_library_count,
        expected_dependency_ids.len()
    );
    let mut actual_dependency_ids = partition.dependency_library_ids.clone();
    for page_index in 0..partition.dependency_page_count {
        let page = store
            .load_library_dependency_page_for_target(
                SourcePackArtifactTarget::Wasm,
                locator.partition_index,
                page_index,
            )
            .unwrap_or_else(|err| panic!("load dependency page {page_index}: {err}"));
        actual_dependency_ids.extend(page.dependency_library_ids);
    }
    assert_eq!(
        actual_dependency_ids, expected_dependency_ids,
        "chunked source-pack metadata preparation should preserve every declared library dependency"
    );

    std::fs::remove_dir_all(&root).expect("remove fan-in metadata root");
}

#[test]
fn source_root_loader_rejects_same_file_across_user_and_stdlib_boundaries() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "overlap", None);
    let core_root = root.join("core");
    std::fs::create_dir_all(&core_root).expect("create overlapping source root");
    let shared_path = core_root.join("shared.lani");
    std::fs::write(
        &shared_path,
        "module core::shared;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write shared module");
    let entry = common::TempArtifact::new("laniusc_package_boundaries", "main", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import core::shared;
fn main() { return 0; }
"#,
    );

    let err = load_entry_with_source_root_and_stdlib(entry.path(), &root, &root)
        .expect_err("the same canonical file must not belong to user and stdlib boundaries");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0003");
            let message = diagnostic.render();
            assert!(message.contains("ambiguous source-root module core::shared"));
            assert!(message.contains(&entry.path().display().to_string()));
            assert!(message.contains("import core::shared;"));
            assert!(message.contains("ambiguous import"));
            assert!(message.contains("source root:"));
            assert!(message.contains("stdlib root:"));
            assert!(message.contains(&shared_path.display().to_string()));
        }
        other => panic!("expected package-boundary diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove overlapping source root");
}

#[cfg(unix)]
#[test]
fn source_root_loader_rejects_duplicate_canonical_user_roots() {
    let root =
        common::temp_artifact_path("laniusc_package_boundaries", "duplicate_user_root", None);
    let source_root = root.join("src");
    let source_root_alias = root.join("src-link");
    let app_root = source_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create app source root");
    std::os::unix::fs::symlink(&source_root, &source_root_alias)
        .expect("create source-root symlink alias");

    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        "module app::helper;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write helper source");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        "module app::main;\nimport app::helper;\nfn main() { return 0; }\n",
    )
    .expect("write entry source");

    let err = load_entry_path_manifest_with_source_roots(
        &entry_path,
        &EntrySourceRoots {
            stdlib_root: None,
            user_roots: vec![source_root.clone(), source_root_alias],
        },
    )
    .expect_err("source-root loading should reject duplicate canonical user roots");
    let message = format!("{err:?}");
    let canonical_source_root =
        std::fs::canonicalize(&source_root).expect("canonicalize source root");
    assert!(
        message.contains("duplicate source root")
            && message.contains(&canonical_source_root.display().to_string()),
        "expected duplicate source-root error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove duplicate source root temp root");
}

#[test]
fn source_root_loader_rejects_overlapping_user_roots_before_import_discovery() {
    let root =
        common::temp_artifact_path("laniusc_package_boundaries", "overlapping_user_roots", None);
    let source_root = root.join("src");
    let app_root = source_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create nested app source root");

    let entry_path = app_root.join("main.lani");
    std::fs::write(&entry_path, "module app::main;\nfn main() { return 0; }\n")
        .expect("write entry source");

    let err = load_entry_path_manifest_with_source_roots(
        &entry_path,
        &EntrySourceRoots {
            stdlib_root: None,
            user_roots: vec![source_root.clone(), app_root.clone()],
        },
    )
    .expect_err("source-root loading should reject nested user roots");
    let message = format!("{err:?}");
    let canonical_source_root =
        std::fs::canonicalize(&source_root).expect("canonicalize source root");
    let canonical_app_root = std::fs::canonicalize(&app_root).expect("canonicalize app root");
    assert!(
        message.contains("overlapping source roots")
            && message.contains(&canonical_source_root.display().to_string())
            && message.contains(&canonical_app_root.display().to_string())
            && message.contains("user source roots must be disjoint"),
        "expected overlapping source-root error, got {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove overlapping user root temp root");
}

#[test]
fn source_root_loader_rejects_ambiguous_module_across_user_roots() {
    let root =
        common::temp_artifact_path("laniusc_package_boundaries", "ambiguous_user_roots", None);
    let first_root = root.join("first");
    let second_root = root.join("second");
    let app_root = first_root.join("app");
    let first_shared_root = first_root.join("shared");
    let second_shared_root = second_root.join("shared");
    std::fs::create_dir_all(&app_root).expect("create first app source root");
    std::fs::create_dir_all(&first_shared_root).expect("create first shared source root");
    std::fs::create_dir_all(&second_shared_root).expect("create second shared source root");

    let first_shared_path = first_shared_root.join("util.lani");
    std::fs::write(
        &first_shared_path,
        "module shared::util;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write first shared module");
    let second_shared_path = second_shared_root.join("util.lani");
    std::fs::write(
        &second_shared_path,
        "module shared::util;\npub const VALUE: i32 = 2;\n",
    )
    .expect("write second shared module");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        "module app::main;\nimport shared::util;\nfn main() { return 0; }\n",
    )
    .expect("write entry source");

    let err = load_entry_path_manifest_with_source_roots(
        &entry_path,
        &EntrySourceRoots {
            stdlib_root: None,
            user_roots: vec![first_root.clone(), second_root],
        },
    )
    .expect_err("ambiguous user-root import should fail closed");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0003");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("ambiguous import diagnostic should carry a primary label");
            assert_eq!(label.source_line.as_deref(), Some("import shared::util;"));
            assert_eq!(label.message, "ambiguous import");
            let message = diagnostic.render();
            assert!(message.contains("ambiguous source-root module shared::util"));
            assert!(message.contains(&first_shared_path.display().to_string()));
            assert!(message.contains(&second_shared_path.display().to_string()));
        }
        other => panic!("expected ambiguous user-root diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove ambiguous user-root temp root");
}

#[test]
fn source_root_loader_rejects_stdlib_nested_import_aliasing_user_boundary() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "nested_overlap", None);
    let source_root = root.join("src");
    let stdlib_root = source_root.join("stdlib");
    let app_root = source_root.join("app");
    let user_core_root = source_root.join("core");
    let stdlib_core_root = stdlib_root.join("core");
    let stdlib_std_root = stdlib_root.join("std");
    std::fs::create_dir_all(&app_root).expect("create app source root");
    std::fs::create_dir_all(&user_core_root).expect("create user core source root");
    std::fs::create_dir_all(&stdlib_core_root).expect("create stdlib core source root");
    std::fs::create_dir_all(&stdlib_std_root).expect("create stdlib std source root");

    let shared_path = stdlib_core_root.join("shared.lani");
    std::fs::write(
        &shared_path,
        "module core::shared;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write shared stdlib module");
    std::os::unix::fs::symlink(&shared_path, user_core_root.join("shared.lani"))
        .expect("create user-root alias to stdlib module");

    let shim_path = stdlib_std_root.join("shim.lani");
    std::fs::write(
        &shim_path,
        "module std::shim;\nimport core::shared;\npub const VALUE: i32 = 2;\n",
    )
    .expect("write stdlib shim module");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        "module app::main;\nimport std::shim;\nfn main() { return 0; }\n",
    )
    .expect("write package entry");

    let err = load_entry_with_source_root_and_stdlib(&entry_path, &source_root, &stdlib_root)
        .expect_err(
            "stdlib nested imports must not accept a source file aliased into the user boundary",
        );
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0003");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("boundary diagnostic should carry a primary label");
            assert_eq!(
                label.path,
                std::fs::canonicalize(&shim_path).expect("canonicalize stdlib shim")
            );
            assert_eq!(label.source_line.as_deref(), Some("import core::shared;"));
            let message = diagnostic.render();
            assert!(message.contains("ambiguous source-root module core::shared"));
            assert!(message.contains("source root:"));
            assert!(message.contains("stdlib root:"));
            assert!(message.contains(&shared_path.display().to_string()));
        }
        other => panic!("expected nested boundary diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove nested overlap source root");
}

#[test]
fn source_root_loader_rejects_import_symlink_to_non_source_file() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "non_source_import", None);
    let app_root = root.join("app");
    std::fs::create_dir_all(&app_root).expect("create temp app source root");
    let non_source_path = app_root.join("helper.txt");
    std::fs::write(
        &non_source_path,
        "module app::helper;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write non-source target");
    std::os::unix::fs::symlink(&non_source_path, app_root.join("helper.lani"))
        .expect("create source-looking symlink");
    let entry = common::TempArtifact::new(
        "laniusc_package_boundaries",
        "non_source_import_main",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;
import app::helper;
fn main() { return 0; }
"#,
    );

    let err = load_entry_with_source_root(entry.path(), &root)
        .expect_err("source-root imports should reject non-source canonical targets");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0030");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("non-source import diagnostic should point at the import");
            assert_eq!(label.path, entry.path());
            assert_eq!(label.source_line, Some("import app::helper;".to_string()));
            let message = diagnostic.render();
            assert!(message.contains("source-root module app::helper resolves to non-source file"));
            assert!(message.contains(&non_source_path.display().to_string()));
            assert!(message.contains("canonical .lani source files"));
        }
        other => panic!("expected non-source source-root diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove temp source root");
}

#[test]
fn source_root_loader_rejects_import_symlink_escape_to_source_file() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "source_escape", None);
    let app_root = root.join("app");
    let outside_root =
        common::temp_artifact_path("laniusc_package_boundaries", "source_escape_outside", None);
    std::fs::create_dir_all(&app_root).expect("create temp app source root");
    std::fs::create_dir_all(&outside_root).expect("create escaped source root");

    let escaped_source = outside_root.join("helper.lani");
    std::fs::write(
        &escaped_source,
        "module app::helper;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write escaped source target");
    std::os::unix::fs::symlink(&escaped_source, app_root.join("helper.lani"))
        .expect("create source symlink escaping source root");

    let entry = common::TempArtifact::new(
        "laniusc_package_boundaries",
        "source_escape_main",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;
import app::helper;
fn main() { return 0; }
"#,
    );

    let err = load_entry_with_source_root(entry.path(), &root)
        .expect_err("source-root imports should reject canonical source-file escapes");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0004");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("source-root escape diagnostic should point at the import");
            assert_eq!(label.path, entry.path());
            assert_eq!(label.source_line, Some("import app::helper;".to_string()));
            let message = diagnostic.render();
            assert!(message.contains("source-root module app::helper escapes source root"));
            assert!(message.contains(&escaped_source.display().to_string()));
            assert!(message.contains("resolves outside source root"));
        }
        other => panic!("expected source-root escape diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove temp source root");
    std::fs::remove_dir_all(&outside_root).expect("remove escaped source root");
}

#[test]
fn source_root_loader_reports_deep_import_path_as_stable_diagnostic() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "deep_import", None);
    let source_root = root.join("src");
    std::fs::create_dir_all(&source_root).expect("create source root");
    let entry =
        common::TempArtifact::new("laniusc_package_boundaries", "deep_import", Some("lani"));
    entry.write_str(
        "module app::main;\nimport a::b::c::d::e::f::g::h::i;\nfn main() { return 0; }\n",
    );

    let err = load_entry_with_source_root(entry.path(), &source_root)
        .expect_err("source-root discovery should report over-deep path imports before lookup");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0012");
            let message = diagnostic.render();
            assert!(message.contains("error[LNC0012]: import path too deep"));
            assert!(message.contains(&entry.path().display().to_string()));
            assert!(message.contains("import a::b::c::d::e::f::g::h::i;"));
            assert!(message.contains("import path exceeds the current resolver depth limit"));
            assert!(message.contains("source-root discovery supports at most eight"));
            assert!(
                !message.contains("GPU frontend error"),
                "source-root path-depth failures should be structured diagnostics: {message}"
            );
        }
        other => panic!("expected source-root import-depth diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove deep import source root");
}

#[test]
fn source_root_loader_resolves_import_paths_through_documented_depth_boundary() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "depth_boundary", None);
    let source_root = root.join("src");
    std::fs::create_dir_all(&source_root).expect("create source root");

    for segment_count in 1..=8 {
        let segments = (0..segment_count)
            .map(|index| format!("m{index}"))
            .collect::<Vec<_>>();
        let module_path = segments.join("::");
        let imported_path = source_root_module_file_path(&source_root, &segments);
        std::fs::create_dir_all(
            imported_path
                .parent()
                .expect("imported source path should have a parent directory"),
        )
        .expect("create imported source directory");
        std::fs::write(
            &imported_path,
            format!("module {module_path};\npub const VALUE: i32 = {segment_count};\n"),
        )
        .expect("write imported source-root module");

        let entry = common::TempArtifact::new(
            "laniusc_package_boundaries",
            &format!("depth_boundary_{segment_count}"),
            Some("lani"),
        );
        entry.write_str(&format!(
            "module app::main;\nimport {module_path};\nfn main() {{ return 0; }}\n"
        ));

        let manifest = load_entry_path_manifest_with_source_root(entry.path(), &source_root)
            .unwrap_or_else(|err| {
                panic!("source-root import with {segment_count} segments should load: {err:?}")
            });
        let canonical_imported_path =
            std::fs::canonicalize(&imported_path).expect("canonicalize imported source");
        assert!(
            manifest
                .files
                .iter()
                .any(|file| file.path == canonical_imported_path),
            "manifest should include {segment_count}-segment imported source {}",
            canonical_imported_path.display()
        );
    }

    let too_deep_segments = (0..9)
        .map(|index| format!("deep{index}"))
        .collect::<Vec<_>>();
    let too_deep_module_path = too_deep_segments.join("::");
    let too_deep_imported_path = source_root_module_file_path(&source_root, &too_deep_segments);
    std::fs::create_dir_all(
        too_deep_imported_path
            .parent()
            .expect("deep imported source path should have a parent directory"),
    )
    .expect("create deep imported source directory");
    std::fs::write(
        &too_deep_imported_path,
        format!("module {too_deep_module_path};\npub const VALUE: i32 = 9;\n"),
    )
    .expect("write too-deep imported source-root module");

    let entry = common::TempArtifact::new(
        "laniusc_package_boundaries",
        "depth_boundary_too_deep",
        Some("lani"),
    );
    let too_deep_import_line = format!("import {too_deep_module_path};");
    entry.write_str(&format!(
        "module app::main;\n{too_deep_import_line}\nfn main() {{ return 0; }}\n"
    ));

    let err = load_entry_path_manifest_with_source_root(entry.path(), &source_root)
        .expect_err("source-root imports beyond the documented depth should fail before lookup");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0012");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("depth diagnostic should carry a primary label");
            assert_eq!(
                label.source_line.as_deref(),
                Some(too_deep_import_line.as_str())
            );
            assert_eq!(label.line, 2);
            assert_eq!(label.column, 8);
            let rendered = diagnostic.render();
            assert!(
                !rendered.contains("missing source-root module"),
                "over-deep imports should fail as a depth violation, not as a missing file: {rendered}"
            );
        }
        other => panic!("expected source-root import-depth diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove depth-boundary source root");
}

#[test]
fn source_root_loader_reports_malformed_import_metadata_as_stable_syntax_diagnostic() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "bad_import", None);
    let source_root = root.join("src");
    std::fs::create_dir_all(&source_root).expect("create source root");
    let entry = common::TempArtifact::new("laniusc_package_boundaries", "bad_import", Some("lani"));
    entry.write_str("module app::main;\nimport ;\nfn main() { return 0; }\n");

    let err = load_entry_with_source_root(entry.path(), &source_root)
        .expect_err("malformed source-root import metadata should report a stable diagnostic");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0016");
            assert_eq!(diagnostic.message, "syntax error");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("syntax diagnostic should carry a primary label");
            assert_eq!(label.path.as_path(), entry.path());
            assert_eq!(label.line, 2);
            assert_eq!(label.source_line.as_deref(), Some("import ;"));
            assert_eq!(label.message, "expected module path after `import`");

            let rendered = diagnostic.render();
            assert!(
                !rendered.contains("source-root import loading")
                    && !rendered.contains("GPU frontend error")
                    && !rendered.contains("invalid syntax here"),
                "source-root metadata syntax failures should not leak raw loader errors: {rendered}"
            );
        }
        other => panic!("expected source-root syntax diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove malformed import source root");
}

#[test]
fn source_root_loader_rejects_quoted_imports_before_returning_path_manifest() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "quoted_import", None);
    let source_root = root.join("src");
    std::fs::create_dir_all(&source_root).expect("create source root");
    let entry =
        common::TempArtifact::new("laniusc_package_boundaries", "quoted_import", Some("lani"));
    entry.write_str("module app::main;\nimport \"app/helper.lani\";\nfn main() { return 0; }\n");

    let err = load_entry_path_manifest_with_source_root(entry.path(), &source_root)
        .expect_err("quoted source-root imports must not produce incomplete path manifests");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0011");
            assert_eq!(diagnostic.message, "unsupported import form");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("quoted import diagnostic should carry a primary label");
            assert_eq!(label.path.as_path(), entry.path());
            assert_eq!(
                label.message,
                "quoted imports are not supported by source-root discovery"
            );

            let rendered = diagnostic.render();
            assert!(rendered.contains("explicit module-path source candidates"));
            assert!(
                !rendered.contains("missing source-root module")
                    && !rendered.contains("GPU frontend error"),
                "quoted imports should not fall through to lookup or raw frontend errors: {rendered}"
            );
        }
        other => panic!("expected source-root quoted-import diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove quoted import source root");
}

#[test]
fn source_root_loader_rejects_glob_and_alias_imports_before_lookup() {
    let root =
        common::temp_artifact_path("laniusc_package_boundaries", "unsupported_imports", None);
    let source_root = root.join("src");
    std::fs::create_dir_all(&source_root).expect("create source root");

    for (stem, import_line, label_message) in [
        (
            "glob_import",
            "import app::*;",
            "import globs are not supported by source-root discovery",
        ),
        (
            "alias_import",
            "import app::helper as helper;",
            "import aliases are not supported by source-root discovery",
        ),
    ] {
        let entry = common::TempArtifact::new("laniusc_package_boundaries", stem, Some("lani"));
        entry.write_str(&format!(
            "module app::main;\n{import_line}\nfn main() {{ return 0; }}\n"
        ));

        let err = load_entry_path_manifest_with_source_root(entry.path(), &source_root)
            .expect_err("unsupported source-root imports should fail before source lookup");
        match err {
            CompileError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0011");
                assert_eq!(diagnostic.message, "unsupported import form");
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("unsupported import diagnostic should carry a primary label");
                assert_eq!(label.path.as_path(), entry.path());
                assert_eq!(label.line, 2);
                assert_eq!(label.message, label_message);

                let rendered = diagnostic.render();
                assert!(
                    rendered.contains("parsed module/import records")
                        || rendered.contains("explicit module-path source candidates"),
                    "unsupported import diagnostics should name the module/import metadata boundary: {rendered}"
                );
                assert!(
                    !rendered.contains("missing source-root module")
                        && !rendered.contains("GPU frontend error"),
                    "unsupported imports should not fall through to lookup or raw frontend errors: {rendered}"
                );
            }
            other => panic!("expected source-root unsupported-import diagnostic, got {other:?}"),
        }
    }

    std::fs::remove_dir_all(&root).expect("remove unsupported-import source root");
}

#[test]
fn source_root_loader_rejects_import_path_separators_before_lookup() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "import_separators", None);
    let source_root = root.join("src");
    std::fs::create_dir_all(&source_root).expect("create source root");

    for (stem, import_line) in [
        ("slash_import", "import app/helper;"),
        ("backslash_import", "import app\\helper;"),
        ("dot_import", "import app.helper;"),
        ("single_colon_import", "import app:helper;"),
    ] {
        let entry = common::TempArtifact::new("laniusc_package_boundaries", stem, Some("lani"));
        entry.write_str(&format!(
            "module app::main;\n{import_line}\nfn main() {{ return 0; }}\n"
        ));

        let err = load_entry_path_manifest_with_source_root(entry.path(), &source_root)
            .expect_err("path-shaped source-root imports should fail before source lookup");
        match err {
            CompileError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0011");
                assert_eq!(diagnostic.message, "unsupported import form");
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("separator diagnostic should carry a primary label");
                assert_eq!(label.path.as_path(), entry.path());
                assert_eq!(label.line, 2);
                assert_eq!(label.message, "import paths must use `::` separators");

                let rendered = diagnostic.render();
                assert!(rendered.contains("semantic module identity"));
                assert!(
                    !rendered.contains("missing source-root module")
                        && !rendered.contains("GPU frontend error"),
                    "path separator imports should not fall through to lookup or raw frontend errors: {rendered}"
                );
            }
            other => panic!("expected source-root path-separator diagnostic, got {other:?}"),
        }
    }

    std::fs::remove_dir_all(&root).expect("remove source-root import separator temp root");
}

#[test]
fn source_root_loader_rejects_reserved_import_segments_before_lookup() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "reserved_import", None);
    let source_root = root.join("src");
    let app_root = source_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create app source root");
    std::fs::write(
        app_root.join("fn.lani"),
        "module app::helper;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write source file behind reserved import segment");

    let entry = common::TempArtifact::new(
        "laniusc_package_boundaries",
        "reserved_import",
        Some("lani"),
    );
    entry.write_str("module app::main;\nimport app::fn;\nfn main() { return 0; }\n");

    let err = load_entry_path_manifest_with_source_root(entry.path(), &source_root)
        .expect_err("reserved import path segments should fail before source-root lookup");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0011");
            assert_eq!(diagnostic.message, "unsupported import form");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("reserved import diagnostic should carry a primary label");
            assert_eq!(label.path.as_path(), entry.path());
            assert_eq!(label.line, 2);
            assert_eq!(label.message, "invalid import path segment");

            let rendered = diagnostic.render();
            assert!(rendered.contains("reserved keywords"));
            assert!(rendered.contains("parsed module/import identifier records"));
            assert!(
                !rendered.contains("missing source-root module")
                    && !rendered.contains("GPU frontend error"),
                "reserved import segments should not fall through to lookup or raw frontend errors: {rendered}"
            );
        }
        other => panic!("expected source-root reserved-import diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove reserved-import source root");
}

#[test]
fn source_root_loader_reports_unterminated_block_comment_as_stable_syntax_diagnostic() {
    let root =
        common::temp_artifact_path("laniusc_package_boundaries", "unterminated_comment", None);
    let source_root = root.join("src");
    std::fs::create_dir_all(&source_root).expect("create source root");
    let entry = common::TempArtifact::new(
        "laniusc_package_boundaries",
        "unterminated_comment",
        Some("lani"),
    );
    entry.write_str("module app::main;\n/* import app::helper;\nfn main() { return 0; }\n");

    let err = load_entry_path_manifest_with_source_root(entry.path(), &source_root)
        .expect_err("source-root discovery should reject malformed comments before GPU parsing");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0016");
            assert_eq!(diagnostic.message, "syntax error");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("unterminated block comment diagnostic should carry a primary label");
            assert_eq!(label.path.as_path(), entry.path());
            assert_eq!(label.line, 2);
            assert_eq!(label.column, 1);
            assert_eq!(label.source_line.as_deref(), Some("/* import app::helper;"));
            assert_eq!(label.message, "unterminated block comment");

            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0016]: syntax error"));
            assert!(rendered.contains("source-root replay"));
            assert!(rendered.contains("module/import metadata"));
            assert!(
                !rendered.contains("GPU frontend error"),
                "source-root malformed-comment failures should not leak raw loader errors: {rendered}"
            );
        }
        other => panic!("expected source-root syntax diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove unterminated comment source root");
}

#[test]
fn source_root_loader_keeps_direct_self_import_as_gpu_semantics() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "self_import", None);
    let source_root = root.join("src");
    let stdlib_root = root.join("empty-stdlib");
    let app_root = source_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");
    std::fs::create_dir_all(&stdlib_root).expect("create empty stdlib source root");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        "module app::main;\nimport app::main;\nfn main() { return 0; }\n",
    )
    .expect("write self-importing package entry");

    let manifest = load_entry_path_manifest_with_source_root_and_stdlib(
        &entry_path,
        &source_root,
        &stdlib_root,
    )
    .expect("source-root loader should use self-imports only as recursion guards");
    assert_eq!(
        manifest.files.len(),
        1,
        "a direct self-import should not duplicate the entry source file"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry_path),
        "entry source should stay a user-library source-pack file"
    );

    std::fs::remove_dir_all(&root).expect("remove self-import source root");
}

#[test]
fn source_root_loader_deduplicates_two_file_import_cycle_for_gpu_validation() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "two_file_cycle", None);
    let source_root = root.join("src");
    let app_root = source_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create package app source root");

    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        "module app::main;\nimport app::helper;\nfn main() { return 0; }\n",
    )
    .expect("write package entry");
    let helper_path = app_root.join("helper.lani");
    std::fs::write(
        &helper_path,
        "module app::helper;\nimport app::main;\npub fn value() -> i32 { return 1; }\n",
    )
    .expect("write package helper");

    let manifest =
        load_entry_path_manifest_with_source_root_and_stdlib(&entry_path, &source_root, &root)
            .expect("source-root loader should not make the semantic cycle decision");
    let canonical_helper = std::fs::canonicalize(&helper_path).expect("canonicalize helper");
    assert_eq!(
        manifest.files.len(),
        2,
        "entry and cyclic helper should be loaded once each"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry_path),
        "entry source should stay in the user library"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == canonical_helper),
        "cyclic imported source should be loaded once for GPU cycle validation"
    );

    std::fs::remove_dir_all(&root).expect("remove two-file cycle source root");
}

#[test]
fn source_root_loader_keeps_stdlib_only_imports_separate_from_entry_library() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "stdlib_only", None);
    let stdlib_root = root.join("stdlib");
    let stdlib_core_root = stdlib_root.join("core");
    let app_root = root.join("app");
    std::fs::create_dir_all(&stdlib_core_root).expect("create stdlib source root");
    std::fs::create_dir_all(&app_root).expect("create entry source root");

    let stdlib_math = stdlib_core_root.join("math.lani");
    std::fs::write(
        &stdlib_math,
        "module core::math;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write stdlib import target");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        "module app::main;\nimport core::math;\nfn main() { return 0; }\n",
    )
    .expect("write package entry");

    let manifest = load_entry_path_manifest_with_source_roots(
        &entry_path,
        &EntrySourceRoots {
            stdlib_root: Some(stdlib_root),
            user_roots: Vec::new(),
        },
    )
    .expect("stdlib-only source-root imports should produce a two-library source pack");
    let canonical_stdlib_math =
        std::fs::canonicalize(&stdlib_math).expect("canonicalize stdlib import target");

    assert_eq!(
        manifest.library_dependencies,
        vec![SourcePackLibraryDependency {
            library_id: 1,
            depends_on_library_id: 0,
        }]
    );
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == canonical_stdlib_math),
        "stdlib import should be planned in the stdlib source-pack library"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry_path),
        "entry source should remain in the user source-pack library"
    );

    std::fs::remove_dir_all(&root).expect("remove stdlib-only import temp root");
}

#[test]
fn source_root_loader_resolves_stdlib_nested_imports_inside_stdlib_boundary() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "stdlib_nested", None);
    let source_root = root.join("src");
    let stdlib_root = root.join("stdlib");
    let app_root = source_root.join("app");
    let user_core_root = source_root.join("core");
    let stdlib_core_root = stdlib_root.join("core");
    let stdlib_std_root = stdlib_root.join("std");
    std::fs::create_dir_all(&app_root).expect("create app source root");
    std::fs::create_dir_all(&user_core_root).expect("create user core source root");
    std::fs::create_dir_all(&stdlib_core_root).expect("create stdlib core source root");
    std::fs::create_dir_all(&stdlib_std_root).expect("create stdlib std source root");

    let user_number = user_core_root.join("number.lani");
    std::fs::write(
        &user_number,
        "module core::number;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write user-shadowed core module");
    let stdlib_number = stdlib_core_root.join("number.lani");
    std::fs::write(
        &stdlib_number,
        "module core::number;\npub const VALUE: i32 = 2;\n",
    )
    .expect("write stdlib core module");
    let stdlib_user = stdlib_std_root.join("uses_number.lani");
    std::fs::write(
        &stdlib_user,
        "module std::uses_number;\nimport core::number;\npub const VALUE: i32 = 3;\n",
    )
    .expect("write stdlib module with nested core import");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        "module app::main;\nimport core::number;\nimport std::uses_number;\nfn main() { return 0; }\n",
    )
    .expect("write package entry");

    let manifest = load_entry_path_manifest_with_source_root_and_stdlib(
        &entry_path,
        &source_root,
        &stdlib_root,
    )
    .expect("source-root path manifest should keep user and stdlib imports separate");

    let canonical_user_number =
        std::fs::canonicalize(&user_number).expect("canonicalize user core module");
    let canonical_stdlib_number =
        std::fs::canonicalize(&stdlib_number).expect("canonicalize stdlib core module");
    let canonical_stdlib_user =
        std::fs::canonicalize(&stdlib_user).expect("canonicalize stdlib dependent module");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == canonical_user_number),
        "entry imports should still prefer the user source-root module"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == canonical_stdlib_user),
        "entry imports should load the stdlib module"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == canonical_stdlib_number),
        "stdlib nested imports should resolve inside the stdlib boundary even when a user module shadows the same path"
    );

    std::fs::remove_dir_all(&root).expect("remove stdlib nested import temp root");
}

#[test]
fn source_root_loader_rejects_stdlib_imports_into_user_roots_with_stable_diagnostic() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "stdlib_back_edge", None);
    let source_root = root.join("src");
    let stdlib_root = root.join("stdlib");
    let app_root = source_root.join("app");
    let stdlib_core_root = stdlib_root.join("core");
    std::fs::create_dir_all(&app_root).expect("create app source root");
    std::fs::create_dir_all(&stdlib_core_root).expect("create stdlib core source root");

    let leaf_path = app_root.join("leaf.lani");
    std::fs::write(&leaf_path, "module app::leaf;\npub const VALUE: i32 = 4;\n")
        .expect("write package leaf module");
    let shim_path = stdlib_core_root.join("shim.lani");
    std::fs::write(
        &shim_path,
        "module core::shim;\nimport app::leaf;\npub const VALUE: i32 = 5;\n",
    )
    .expect("write stdlib shim module");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &entry_path,
        "module app::main;\nimport core::shim;\nfn main() { return 0; }\n",
    )
    .expect("write package entry");

    let err = load_entry_with_source_root_and_stdlib(&entry_path, &source_root, &stdlib_root)
        .expect_err("source-root discovery should reject stdlib imports back into user roots");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0024");
            assert_eq!(
                diagnostic.message,
                "source-root package boundary for app::leaf"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("package-boundary diagnostic should carry a primary label");
            assert_eq!(
                label.path,
                std::fs::canonicalize(&shim_path).expect("canonicalize stdlib shim")
            );
            assert_eq!(label.line, 2);
            assert_eq!(label.source_line.as_deref(), Some("import app::leaf;"));
            assert_eq!(label.message, "stdlib import targets a user source root");
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0024]: source-root package boundary"));
            assert!(rendered.contains("stdlib sources may not import package/user roots"));
            assert!(rendered.contains(&leaf_path.display().to_string()));
        }
        other => panic!("expected source-root package-boundary diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove stdlib back-edge temp root");
}

#[test]
fn source_root_loader_leaves_deep_module_paths_for_gpu_validation() {
    let root = common::temp_artifact_path("laniusc_package_boundaries", "deep_module", None);
    let source_root = root.join("src");
    std::fs::create_dir_all(&source_root).expect("create source root");
    let entry =
        common::TempArtifact::new("laniusc_package_boundaries", "deep_module", Some("lani"));
    entry.write_str("module a::b::c::d::e::f::g::h::i;\nfn main() { return 0; }\n");

    let source_pack = load_entry_with_source_root(entry.path(), &source_root)
        .expect("source-root discovery should not preempt resolver module-depth validation");
    assert_eq!(source_pack.sources.len(), 1);
    assert_eq!(source_pack.library_ids, vec![1]);
    assert_eq!(
        source_pack.source_paths,
        vec![Some(entry.path().to_path_buf())]
    );

    std::fs::remove_dir_all(&root).expect("remove deep module source root");
}

fn source_root_module_file_path(
    source_root: &std::path::Path,
    segments: &[String],
) -> std::path::PathBuf {
    let mut path = source_root.to_path_buf();
    for segment in segments {
        path.push(segment);
    }
    path.set_extension("lani");
    path
}

fn assert_duplicate_library_dependency_error(
    err: &CompileError,
    library_id: u32,
    depends_on_library_id: u32,
) {
    let message = format!("{err:?}");
    assert!(
        message.contains("duplicate library dependency")
            && message.contains(&format!("{library_id} -> {depends_on_library_id}")),
        "expected duplicate library dependency error for {library_id} -> {depends_on_library_id}, got {message}"
    );
}

use super::*;

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
    validate_path_manifest(&manifest).expect("test manifest with line totals should be valid");
    let source_pack = manifest
        .path_manifest()
        .expect("contract test manifest should retain source files");
    let expected_source_file_count = source_pack.files.len();
    let expected_source_byte_count = source_pack
        .files
        .iter()
        .map(|file| file.byte_len)
        .sum::<usize>();
    let expected_source_line_count = source_pack
        .files
        .iter()
        .map(|file| file.line_count.unwrap_or(0))
        .sum::<usize>();
    assert_eq!(manifest.source_file_count, expected_source_file_count);
    assert_eq!(manifest.source_byte_count, expected_source_byte_count);
    assert_eq!(manifest.source_line_count, expected_source_line_count);

    let partition_plan = library_partition_plan(&source_pack, SourcePackArtifactTarget::Generic)
        .expect("partition plan should preserve line totals");
    let partition_index = &partition_plan.index;
    assert_eq!(
        partition_index.source_line_count,
        expected_source_line_count
    );
    assert_eq!(
        partition_plan
            .partitions
            .iter()
            .map(|partition| partition.source_line_count)
            .sum::<usize>(),
        manifest.source_line_count
    );
    let source_file_pages = library_source_file_pages(&source_pack, &partition_plan)
        .expect("source-file pages should preserve line totals");
    assert_eq!(
        source_file_pages
            .iter()
            .map(|page| page.source_line_count)
            .sum::<usize>(),
        manifest.source_line_count
    );
}

use super::test_support::*;

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
    let mut store = FilesystemArtifactStore::new(&root);
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
        output_key: hierarchical_link_partial_output_key(target, 0, 10),
        final_output: false,
    };
    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    assert!(
        execute_hierarchical_link_page(&leaf_page, &mut executor, &mut store)
            .expect_err("truncated object pages should be rejected")
            .to_string()
            .contains("streamed 1 object refs but expected 2")
    );

    let partial_key = hierarchical_link_partial_output_key(target, 0, 20);
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
        output_key: hierarchical_link_partial_output_key(target, 3, 20),
        final_output: false,
    };
    assert!(
        execute_hierarchical_link_page(&reduce_page, &mut executor, &mut store)
            .expect_err("truncated partial-link pages should be rejected")
            .to_string()
            .contains("streamed 1 partial-link refs but expected 2")
    );

    std::fs::remove_dir_all(&root).expect("remove truncated hlink page test dir");
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

    let manifest = ExplicitSourcePackPathManifest::from_libraries(vec![
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
    let stream_compact_manifest = plan_dependency_streams_compact_manifest_for_target(
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
    assert_eq!(
        stream_compact_manifest.target,
        SourcePackArtifactTarget::X86_64
    );
    assert!(
        stream_compact_manifest.job_count >= manifest.files.len(),
        "planned job graph should cover every source file"
    );
    assert!(
        stream_compact_manifest.artifact_count >= manifest.files.len(),
        "planned artifact graph should cover every source file"
    );
}

#[test]
fn compact_artifact_manifest_rejects_bad_library_streams() {
    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 8,
    };
    let batch_limits = SourcePackJobBatchLimits::from_codegen_unit_limits(limits);
    let empty_err = plan_dependency_streams_compact_manifest::<
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

    let later_dependency_err = plan_dependency_streams_compact_manifest(
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

        let store = FilesystemArtifactStore::new(&artifact_root);
        let result = prepare_schedule(
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

    let manifest =
        ExplicitSourcePackPathManifest::from_libraries(vec![ExplicitSourceLibraryPaths {
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

    let manifest =
        ExplicitSourcePackPathManifest::from_libraries(vec![ExplicitSourceLibraryPaths {
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
fn artifact_manifest_load_rejects_corrupt_contract() {
    let manifest = source_pack_contract_test_manifest();
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-corrupt-artifact-manifest-load-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    store
        .store_path_build_manifest(&manifest)
        .expect("store valid path build manifest");

    let mut corrupt = manifest;
    corrupt.artifacts.job_artifacts.jobs[0].outputs[0]
        .key
        .push_str("-stale");
    let bytes = serde_json::to_vec_pretty(&corrupt).expect("serialize corrupt path build manifest");
    std::fs::write(
        store.build_manifest_path_for_target(SourcePackArtifactTarget::Generic),
        bytes,
    )
    .expect("overwrite corrupt manifest");

    let err = store
        .load_path_build_manifest_for_target(SourcePackArtifactTarget::Generic)
        .expect_err("load should reject corrupt manifest contract");
    assert!(
        err.to_string()
            .contains("invalid source-pack artifact manifest"),
        "unexpected error: {err}"
    );
    std::fs::remove_dir_all(&root).expect("remove corrupt manifest test dir");
}

#[test]
fn metadata_prepare_resumes_completed_library_prefix() {
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
    let source_paths = [&core_path, &app_path];
    let expected_source_file_count = source_paths.len();
    let expected_source_byte_count = source_paths
        .iter()
        .map(|path| {
            usize::try_from(std::fs::metadata(path).expect("source metadata").len())
                .expect("source byte count fits usize")
        })
        .sum::<usize>();

    prepare_dependency_stream_metadata_for_target(
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
    let store = FilesystemArtifactStore::new(&artifact_root);
    std::fs::remove_file(
        store.library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm),
    )
    .expect("remove compact metadata index to simulate interrupted metadata phase");
    std::fs::remove_file(&core_path).expect("remove completed prefix source");

    let resumed = prepare_dependency_stream_metadata_for_target(
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

    assert_eq!(resumed.source_file_count, expected_source_file_count);
    assert_eq!(resumed.source_byte_count, expected_source_byte_count);
    assert_eq!(resumed.library_partition_count, expected_source_file_count);
    let partition_index = store
        .load_library_partition_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load resumed compact metadata index");
    assert_eq!(
        partition_index.partition_count,
        resumed.library_partition_count
    );
    let app_partition = store
        .load_library_partition_for_target(SourcePackArtifactTarget::Wasm, 1)
        .expect("load resumed app partition");
    assert_eq!(app_partition.library_id, 20);
    assert_eq!(
        load_library_dependency_ids(&store, &app_partition).expect("load resumed app dependencies"),
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
    let store = FilesystemArtifactStore::new(&artifact_root);
    let libraries = [
        (10, core_path.as_path(), Vec::<u32>::new()),
        (20, app_path.as_path(), vec![10]),
        (30, cli_path.as_path(), vec![20]),
    ];
    let expected_source_byte_count = libraries
        .iter()
        .map(|(_, path, _)| {
            usize::try_from(std::fs::metadata(path).expect("source metadata").len())
                .expect("source byte count fits usize")
        })
        .sum::<usize>();
    let chunk_limit = 1usize;
    let streams = || {
        libraries.iter().map(|(library_id, path, dependencies)| {
            ExplicitSourceLibraryPathDependencyStream {
                library_id: *library_id,
                source_file_count: 1,
                paths: std::iter::once(*path),
                dependency_library_count: dependencies.len(),
                dependency_library_ids: dependencies.iter().copied(),
            }
        })
    };

    let mut final_chunk = None;
    for chunk_index in 0..libraries.len() {
        let step = prepare_metadata_chunk_for_target(
            streams(),
            &artifact_root,
            SourcePackArtifactTarget::Wasm,
            chunk_limit,
        )
        .unwrap_or_else(|err| panic!("prepare metadata chunk {chunk_index}: {err}"));
        let previous_prepared_libraries = chunk_index.saturating_mul(chunk_limit);
        let expected_prepared_libraries = previous_prepared_libraries
            .saturating_add(chunk_limit)
            .min(libraries.len());
        let expected_new_libraries =
            expected_prepared_libraries.saturating_sub(previous_prepared_libraries);
        let expected_complete = expected_prepared_libraries == libraries.len();

        assert_eq!(step.complete, expected_complete);
        assert!(step.new_library_count <= chunk_limit);
        assert_eq!(step.new_library_count, expected_new_libraries);
        assert_eq!(step.library_partition_count, expected_prepared_libraries);
        assert_eq!(step.source_file_count, expected_prepared_libraries);
        assert_eq!(
            step.library_partition_index_path.is_some(),
            expected_complete
        );
        assert_eq!(
            store
                .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
                .is_file(),
            expected_complete
        );

        if !expected_complete {
            std::fs::remove_file(libraries[chunk_index].1).expect("remove completed chunk source");
        }
        final_chunk = Some(step);
    }

    let final_chunk = final_chunk.expect("metadata chunk loop should run");
    assert_eq!(final_chunk.source_byte_count, expected_source_byte_count);
    let partition_index = store
        .load_library_partition_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load final metadata chunk compact index");
    assert_eq!(
        partition_index.partition_count,
        final_chunk.library_partition_count
    );
    assert_eq!(
        partition_index.source_file_count,
        final_chunk.source_file_count
    );

    std::fs::remove_dir_all(&root).expect("remove temp metadata chunk dir");
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

    let first = prepare_metadata_chunk_for_target(
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
    let store = FilesystemArtifactStore::new(&artifact_root);
    std::fs::remove_file(
        store.library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm),
    )
    .expect("remove compact metadata index to simulate interrupted metadata phase");

    let err = prepare_metadata_chunk_for_target(
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
    let source_paths = [&core_path, &app_path];
    let expected_source_file_count = source_paths.len();
    let expected_library_count = 2usize;

    let metadata = prepare_dependency_stream_metadata_for_target(
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
    assert_eq!(metadata.source_file_count, expected_source_file_count);
    assert_eq!(metadata.library_partition_count, expected_library_count);

    std::fs::remove_file(&core_path).expect("remove core source after metadata");
    std::fs::remove_file(&app_path).expect("remove app source after metadata");

    let prepared = prepare_artifact_build(
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
    assert!(prepared.scheduled_job_count > 0);
    assert!(prepared.artifact_count > 0);
    assert!(prepared.work_queue_item_count > 0);
    assert!(prepared.artifact_shard_count > 0);

    std::fs::remove_dir_all(&root).expect("remove temp artifact-from-metadata test dir");
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

    let library_count = ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT + 1;
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

    let metadata = prepare_dependency_stream_metadata_for_target(
        libraries,
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare metadata for capped chunk test");
    assert_eq!(metadata.library_count, library_count);

    let step = prepare_artifact_build_chunk(
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
    assert!(!step.complete);
    assert!(step.new_item_count <= ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    assert!(
        !FilesystemArtifactStore::new(&artifact_root)
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

    let capped_library_count = ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT;
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

    let metadata = prepare_dependency_stream_metadata_for_target(
        libraries,
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare metadata for public schedule chunk cap test");
    assert_eq!(metadata.library_count, library_count);

    let step = prepare_library_schedule_chunk(
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
    assert!(step.new_library_build_unit_page_count <= capped_library_count);
    assert!(step.library_schedule_index_path.is_none());
    assert!(
        !FilesystemArtifactStore::new(&artifact_root)
            .library_schedule_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file(),
        "capped public schedule chunk must not finish the full schedule"
    );

    std::fs::remove_dir_all(&root).expect("remove temp public schedule chunk cap dir");
}

#[test]
fn metadata_schedule_reconstructs_multi_unit_libraries() {
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
    let source_paths = core_paths
        .iter()
        .chain(app_paths.iter())
        .collect::<Vec<_>>();
    let expected_source_file_count = source_paths.len();
    let expected_source_byte_count = source_paths
        .iter()
        .map(|path| {
            usize::try_from(std::fs::metadata(path).expect("source metadata").len())
                .expect("source byte count fits usize")
        })
        .sum::<usize>();
    let expected_library_count = 2usize;

    let metadata = prepare_dependency_stream_metadata_for_target(
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
    assert_eq!(metadata.source_file_count, expected_source_file_count);
    assert_eq!(metadata.source_byte_count, expected_source_byte_count);
    assert_eq!(metadata.library_partition_count, expected_library_count);
    assert_eq!(
        metadata.library_source_file_page_count,
        metadata.library_partition_count
    );

    for path in source_paths {
        std::fs::remove_file(path).expect("remove source file after metadata");
    }

    let store = FilesystemArtifactStore::new(&artifact_root);
    let prepared_pages = prepare_schedule_from_metadata(
        &store,
        SourcePackArtifactTarget::Wasm,
        CodegenUnitLimits {
            max_source_bytes: 4,
            max_source_files: 1,
        },
    )
    .expect("prepare multi-unit schedule pages from persisted metadata");

    assert_eq!(
        prepared_pages.library_partition_index.source_file_count,
        metadata.source_file_count
    );
    assert!(prepared_pages.library_build_unit_page_count > 0);
    assert!(prepared_pages.library_schedule_page_count > 0);
    let schedule = store
        .load_library_schedule_index_for_target(SourcePackArtifactTarget::Wasm)
        .expect("load persisted multi-unit schedule index");
    assert_eq!(schedule.frontend_job_count, metadata.source_file_count);
    assert_eq!(schedule.codegen_job_count, metadata.source_file_count);
    assert!(schedule.job_count > schedule.codegen_job_count);

    std::fs::remove_dir_all(&root).expect("remove temp schedule-from-metadata multi-unit test dir");
}

#[test]
fn library_metadata_prepare_skips_build_manifest() {
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
    let libraries = vec![
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
    ];
    let expected_source_file_count = libraries
        .iter()
        .map(|library| library.paths.len())
        .sum::<usize>();
    let expected_source_byte_count = libraries
        .iter()
        .flat_map(|library| library.paths.iter())
        .map(|path| {
            usize::try_from(std::fs::metadata(path).expect("source metadata").len())
                .expect("source byte count fits usize")
        })
        .sum::<usize>();
    let expected_library_count = libraries.len();

    let prepared = prepare_library_path_metadata_for_target(
        libraries,
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare filesystem library metadata without full build manifest");

    assert_eq!(prepared.target, SourcePackArtifactTarget::Wasm);
    assert_eq!(prepared.source_file_count, expected_source_file_count);
    assert_eq!(prepared.source_byte_count, expected_source_byte_count);
    assert_eq!(prepared.library_count, expected_library_count);
    assert_eq!(prepared.library_partition_count, expected_library_count);
    assert_eq!(
        prepared.library_source_file_page_count,
        prepared.library_partition_count
    );

    let store = FilesystemArtifactStore::new(&artifact_root);
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
    assert_eq!(
        partition_index.partition_count,
        prepared.library_partition_count
    );
    assert_eq!(
        partition_index.source_file_count,
        prepared.source_file_count
    );
    assert_eq!(
        partition_index.source_byte_count,
        prepared.source_byte_count
    );

    std::fs::write(
        store.build_manifest_path_for_target(SourcePackArtifactTarget::Wasm),
        b"not json",
    )
    .expect("write corrupt unrelated build manifest");
    store
        .load_library_source_file_page_for_target(SourcePackArtifactTarget::Wasm, 0)
        .expect("load source-file page without reading corrupt build manifest");

    std::fs::remove_dir_all(&root).expect("remove temp library metadata prepare dir");
}

#[test]
fn work_queue_worker_run_honors_zero_item_limit() {
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

    prepare_library_paths_for_target(
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
    let run = run_work_queue(
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
    assert!(!run.progress.complete);
    assert_eq!(run.linked_output_key, None);
    assert_eq!(run.linked_output_path, None);

    std::fs::remove_dir_all(&root).expect("remove zero-item work queue run test dir");
}

mod work_queue_artifacts;

mod common;

use laniusc::{
    codegen::unit::{
        CodegenUnitLimits,
        SourcePackArtifactKind,
        SourcePackArtifactRef,
        SourcePackArtifactTarget,
        SourcePackJobBatchDependencyRange,
        SourcePackJobBatchLimits,
        SourcePackJobPhase,
        SourcePackLibraryDependency,
    },
    compiler::{
        CompileError,
        ExplicitSourceLibrary,
        ExplicitSourceLibraryPaths,
        ExplicitSourcePack,
        ExplicitSourcePackPathManifest,
        FilesystemArtifactStore,
        SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
        SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_PAGE_VERSION,
        SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_VERSION,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_VERSION,
        SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
        SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
        SOURCE_PACK_PATH_BUILD_MANIFEST_VERSION,
        SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_PAGE_VERSION,
        SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
        SourcePackBuildArtifactRefIndex,
        SourcePackBuildJobBatchDependencyPage,
        SourcePackBuildJobBatchDependencyRangePage,
        SourcePackHierarchicalLinkExecutionIndex,
        SourcePackHierarchicalLinkExecutionObjectPage,
        SourcePackHierarchicalLinkExecutionPage,
        SourcePackHierarchicalLinkExecutionPartialPage,
        SourcePackHierarchicalLinkGroupKind,
        SourcePackHierarchicalLinkGroupPage,
        SourcePackHierarchicalLinkPlanIndex,
        SourcePackLibraryScheduleIndex,
        SourcePackLinkDescriptorSummary,
        SourcePackPathBuildManifest,
        SourcePackWorkQueueDependenciesPage,
        SourcePackWorkQueueItemKind,
        SourcePackWorkQueuePage,
        load_entry_path_manifest_with_source_root,
        load_entry_path_manifest_with_source_root_and_stdlib,
        load_entry_with_source_root,
        load_entry_with_source_root_and_stdlib,
        prepare_link_execution_chunk,
    },
};

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
fn source_pack_job_batch_sidecars_reject_noncanonical_dependency_order() {
    let root = common::temp_artifact_path(
        "laniusc_package_boundaries",
        "job_batch_dependency_order",
        None,
    );
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
            assert_eq!(label.message, "invalid syntax here");

            let rendered = diagnostic.render();
            assert!(
                !rendered.contains("source-root import loading")
                    && !rendered.contains("GPU frontend error"),
                "source-root metadata syntax failures should not leak raw loader errors: {rendered}"
            );
        }
        other => panic!("expected source-root syntax diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove malformed import source root");
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
        .expect("source-root discovery should not preempt GPU module-depth validation");
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

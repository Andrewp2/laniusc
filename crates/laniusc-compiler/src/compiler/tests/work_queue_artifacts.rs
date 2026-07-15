use super::super::{test_support::*, *};
use crate::compiler::artifact_descriptor::{
    GpuSourcePackDescriptorRecord,
    GpuSourcePackDescriptorRecordDomain,
    GpuSourcePackDescriptorRecordFlow,
    GpuSourcePackDescriptorRecordKind,
};

fn test_compile_work_queue_page(item_index: usize) -> SourcePackWorkQueuePage {
    SourcePackWorkQueuePage {
        version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
        target: SourcePackArtifactTarget::Generic,
        item_index,
        kind: SourcePackWorkQueueItemKind::LibraryFrontend,
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

fn test_link_reduce_work_queue_page(
    item_index: usize,
    link_group_index: usize,
    input_link_group_indices: Vec<usize>,
) -> SourcePackWorkQueuePage {
    SourcePackWorkQueuePage {
        version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
        target: SourcePackArtifactTarget::Generic,
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
        link_group_index: Some(link_group_index),
        input_frontend_job_count: 0,
        input_frontend_job_indices: Vec::new(),
        input_codegen_job_count: 0,
        input_codegen_job_indices: Vec::new(),
        input_link_group_count: input_link_group_indices.len(),
        input_link_group_indices,
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
    }
}

fn test_link_leaf_work_queue_page(
    item_index: usize,
    input_frontend_job_count: usize,
    input_codegen_job_count: usize,
) -> SourcePackWorkQueuePage {
    SourcePackWorkQueuePage {
        version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
        target: SourcePackArtifactTarget::Generic,
        item_index,
        kind: SourcePackWorkQueueItemKind::LinkLeaf,
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
        partition_indices: vec![0],
        link_group_index: Some(0),
        input_frontend_job_count,
        input_frontend_job_indices: Vec::new(),
        input_codegen_job_count,
        input_codegen_job_indices: Vec::new(),
        input_link_group_count: 0,
        input_link_group_indices: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
    }
}

fn remaining_dependency_counts(page: &SourcePackWorkQueueProgressPage) -> Vec<(usize, usize)> {
    page.remaining_dependency_counts
        .iter()
        .map(|remaining| (remaining.item_index, remaining.remaining_dependency_count))
        .collect()
}

fn remaining_dependent_counts(page: &SourcePackWorkQueueProgressPage) -> Vec<(usize, usize)> {
    page.remaining_dependent_counts
        .iter()
        .map(|remaining| (remaining.item_index, remaining.remaining_dependent_count))
        .collect()
}

#[test]
fn work_queue_sidecar_pages_reject_empty_records() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-empty-work-queue-sidecar-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create temp artifact dir");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;

    let empty_dependency_page = SourcePackWorkQueueDependenciesPage {
        version: SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_PAGE_VERSION,
        target,
        item_index: 1,
        page_index: 0,
        first_dependency_position: 0,
        dependency_count: 0,
        dependency_item_indices: Vec::new(),
    };
    let dependency_err = store
        .store_work_queue_dependencies_page(&empty_dependency_page)
        .expect_err("empty dependency sidecar pages should be rejected");
    assert!(
        dependency_err.to_string().contains("dependency count 0"),
        "unexpected empty dependency page error: {dependency_err}"
    );

    let empty_dependent_page = SourcePackWorkQueueDependentsPage {
        version: SOURCE_PACK_WORK_QUEUE_DEPENDENTS_PAGE_VERSION,
        target,
        item_index: 0,
        page_index: 0,
        first_dependent_position: 0,
        dependent_count: 0,
        dependent_item_indices: Vec::new(),
    };
    let dependent_err = store
        .store_work_queue_dependents_page(&empty_dependent_page)
        .expect_err("empty dependent sidecar pages should be rejected");
    assert!(
        dependent_err.to_string().contains("dependent count 0"),
        "unexpected empty dependent page error: {dependent_err}"
    );

    std::fs::remove_dir_all(&root).expect("remove temp artifact dir");
}

#[test]
fn link_reduce_work_queue_inputs_must_reference_prior_groups() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-link-reduce-work-queue-input-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;

    let valid_page = test_link_reduce_work_queue_page(10, 3, vec![0, 2]);
    store
        .store_work_queue_page(&valid_page)
        .expect("prior link-group inputs should persist");
    let persisted = store
        .load_work_queue_page_for_target(target, 10)
        .expect("load persisted link-reduce work item");
    assert_eq!(persisted.link_group_index, Some(3));
    assert_eq!(persisted.input_link_group_count, 2);
    assert_eq!(persisted.input_link_group_indices, vec![0, 2]);

    let same_group_page = test_link_reduce_work_queue_page(11, 3, vec![3]);
    assert!(
        store.store_work_queue_page(&same_group_page).is_err(),
        "a reduce work item must not consume its own group"
    );
    assert!(
        !store.work_queue_page_path_for_target(target, 11).exists(),
        "rejected same-group input must not leave a persisted work item"
    );

    let future_group_page = test_link_reduce_work_queue_page(12, 3, vec![4]);
    assert!(
        store.store_work_queue_page(&future_group_page).is_err(),
        "a reduce work item must not consume a future group"
    );
    assert!(
        !store.work_queue_page_path_for_target(target, 12).exists(),
        "rejected future-group input must not leave a persisted work item"
    );

    std::fs::remove_dir_all(&root).expect("remove link-reduce work queue input test dir");
}

#[test]
fn link_leaf_work_queue_requires_frontend_input_for_each_codegen_input() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-link-leaf-work-queue-input-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;

    let valid_page = test_link_leaf_work_queue_page(10, 2, 2);
    store
        .store_work_queue_page(&valid_page)
        .expect("matching leaf frontend/codegen inputs should persist");

    let stale_page = test_link_leaf_work_queue_page(11, 1, 2);
    let err = store
        .store_work_queue_page(&stale_page)
        .expect_err("leaf link pages must not claim fewer frontend than codegen inputs");
    assert!(
        err.to_string()
            .contains("frontend inputs for 2 codegen inputs"),
        "unexpected leaf input-count validation error: {err}"
    );
    assert!(
        !store.work_queue_page_path_for_target(target, 11).exists(),
        "rejected leaf work item must not be persisted"
    );

    std::fs::remove_dir_all(&root).expect("remove link-leaf work queue input test dir");
}

#[test]
fn persisted_link_prepare_progress_rejects_early_final_output_marker() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-link-prepare-progress-resume-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let progress_path = store.link_execution_prepare_progress_path_for_target(target);
    std::fs::create_dir_all(progress_path.parent().expect("progress parent"))
        .expect("create link progress dir");
    std::fs::write(
        &progress_path,
        serde_json::to_vec_pretty(&serde_json::json!({
            "version": SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_VERSION,
            "target": "Wasm",
            "link_group_count": 3,
            "next_group_index": 1,
            "final_output_seen": true
        }))
        .expect("serialize malformed link progress"),
    )
    .expect("write malformed link progress");

    let err = load_link_execution_prepare_progress(&store, target, 3)
        .expect_err("resumed link progress must reject an early final-output marker");
    let message = err.to_string();
    assert!(
        message.contains("final output") && message.contains("before all link groups"),
        "unexpected link progress resume error: {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove link progress resume test dir");
}

#[test]
fn persisted_link_execution_index_requires_dense_final_output_slot() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-link-execution-final-slot-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let first_link_job_index = 20;
    let final_link_group_index = 2;
    let final_link_job_index = first_link_job_index + final_link_group_index;
    let index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(index_path.parent().expect("link index parent"))
        .expect("create link index dir");

    let valid_output_key = source_pack_artifact_key_for_output(
        target,
        SourcePackArtifactKind::LinkedOutput,
        0,
        first_link_job_index,
        0,
        3,
    );
    let wrong_output_key = source_pack_artifact_key_for_output(
        target,
        SourcePackArtifactKind::LinkedOutput,
        0,
        final_link_job_index,
        0,
        3,
    );
    let mut index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: final_link_group_index + 1,
        final_output_key: wrong_output_key,
    };
    std::fs::write(
        &index_path,
        serde_json::to_vec_pretty(&index).expect("serialize malformed link execution index"),
    )
    .expect("write malformed link execution index");

    let err = store
        .load_hierarchical_link_execution_index_for_target(target)
        .expect_err("resumed link execution index must reject the wrong final output slot");
    let message = err.to_string();
    assert!(
        message.contains("producer job 22") && message.contains("first link job 20"),
        "unexpected final output slot validation error: {message}"
    );

    index.final_output_key = valid_output_key.clone();
    std::fs::write(
        &index_path,
        serde_json::to_vec_pretty(&index).expect("serialize valid link execution index"),
    )
    .expect("write valid link execution index");
    assert_eq!(
        store
            .load_hierarchical_link_execution_index_for_target(target)
            .expect("link execution index should load with the dense final output slot")
            .final_output_key,
        valid_output_key
    );

    std::fs::remove_dir_all(&root).expect("remove link execution final-slot test dir");
}

#[test]
fn persisted_link_execution_index_requires_final_group_to_be_last() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-link-execution-final-group-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(index_path.parent().expect("link index parent"))
        .expect("create link index dir");

    let index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index: 20,
        final_link_group_index: 1,
        final_link_job_index: 21,
        link_group_count: 3,
        final_output_key: source_pack_artifact_key_for_output(
            target,
            SourcePackArtifactKind::LinkedOutput,
            0,
            20,
            0,
            3,
        ),
    };
    std::fs::write(
        &index_path,
        serde_json::to_vec_pretty(&index).expect("serialize malformed link execution index"),
    )
    .expect("write malformed link execution index");

    let err = store
        .load_hierarchical_link_execution_index_for_target(target)
        .expect_err("resumed link execution index must reject a non-final dense group");
    let message = err.to_string();
    assert!(
        message.contains("final group 1") && message.contains("group count 3"),
        "unexpected final group validation error: {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove link execution final group test dir");
}

#[test]
fn execution_shard_link_job_rejects_undeclared_output_before_writing_linked_output() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-link-shard-undeclared-output-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create undeclared link output test dir");
    let mut store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let link_job_index = 7;
    let output_key = source_pack_artifact_key_for_output(
        target,
        SourcePackArtifactKind::LinkedOutput,
        0,
        link_job_index,
        0,
        1,
    );
    let output_ref = SourcePackArtifactRef {
        artifact_index: link_job_index,
        key: output_key.clone(),
        producing_job_index: link_job_index,
        kind: SourcePackArtifactKind::LinkedOutput,
    };
    let execution_shard = SourcePackBuildArtifactExecutionShard {
        version: SOURCE_PACK_BUILD_ARTIFACT_EXECUTION_SHARD_VERSION,
        target,
        shard: SourcePackBuildArtifactShard {
            version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
            target,
            limits: SourcePackBuildShardLimits::default().normalized(),
            shard_index: 0,
            kind: SourcePackBuildArtifactShardKind::JobBatches,
            batch_indices: vec![0],
            job_indices: vec![link_job_index],
            input_artifact_indices: Vec::new(),
            input_artifact_ranges: Vec::new(),
            output_artifact_indices: Vec::new(),
            source_bytes: 1,
            source_file_count: 1,
            source_lines: 1,
            oversized: false,
        },
        source_files: Vec::new(),
        job_batches: Vec::new(),
        batch_dependencies: Vec::new(),
        batch_dependents: Vec::new(),
        jobs: Vec::new(),
        job_artifacts: Vec::new(),
        artifact_refs: Vec::new(),
        link_interface_batches: Vec::new(),
        link_object_batches: Vec::new(),
    };
    let link_input_shard_index = SourcePackBuildLinkInputShardIndex {
        version: SOURCE_PACK_BUILD_LINK_INPUT_SHARD_INDEX_VERSION,
        target,
        link_interface_shard_range: None,
        link_object_shard_range: None,
    };
    let job = SourcePackJob {
        job_index: link_job_index,
        phase: SourcePackJobPhase::Link,
        phase_unit_index: 0,
        library_job_index: None,
        library_id: 0,
        first_source_index: 0,
        source_file_count: 1,
        source_bytes: 1,
        source_lines: 1,
        oversized_source_file: false,
        dependency_job_indices: Vec::new(),
    };
    let job_manifest = SourcePackJobArtifactManifest {
        job_index: link_job_index,
        phase: SourcePackJobPhase::Link,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interface_artifact_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_object_artifact_ranges: Vec::new(),
        input_objects: Vec::new(),
        outputs: vec![output_ref],
    };

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let err = execute_execution_shard_link_job(
        &execution_shard,
        &link_input_shard_index,
        target,
        &job,
        &job_manifest,
        &mut executor,
        &mut store,
    )
    .expect_err("link execution must reject outputs missing from the execution shard");
    let message = err.to_string();
    assert!(
        message.contains("output artifact 7") && message.contains("not listed in execution shard"),
        "unexpected undeclared link output error: {message}"
    );
    assert!(
        executor.events.is_empty(),
        "undeclared link outputs must be rejected before link execution begins: {:?}",
        executor.events
    );
    assert!(
        !store
            .path_for_key(&output_key)
            .expect("linked output artifact path")
            .exists(),
        "rejected undeclared link output must not leave linked-output bytes"
    );

    std::fs::remove_dir_all(&root).expect("remove undeclared link output test dir");
}

#[test]
fn final_link_work_queue_rejects_stale_dense_output_key() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-final-link-stale-output-key-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let first_link_job_index = 20;
    let group_index = 2;
    let link_job_index = first_link_job_index + group_index;
    let expected_output_key = source_pack_artifact_key_for_output(
        target,
        SourcePackArtifactKind::LinkedOutput,
        0,
        first_link_job_index,
        0,
        1,
    );
    let stale_output_key = source_pack_artifact_key_for_output(
        target,
        SourcePackArtifactKind::LinkedOutput,
        0,
        first_link_job_index + 1,
        0,
        1,
    );
    let link_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Reduce,
        job_index: link_job_index,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: Vec::new(),
        input_group_count: 1,
        input_group_page_count: 1,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: stale_output_key.clone(),
        final_output: true,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };
    let link_page_path =
        store.hierarchical_link_execution_page_path_for_target(target, group_index);
    std::fs::create_dir_all(link_page_path.parent().expect("link page parent"))
        .expect("create persisted link page dir");
    std::fs::write(
        &link_page_path,
        serde_json::to_vec_pretty(&link_page).expect("serialize stale final link page"),
    )
    .expect("write stale final link page");
    store
        .store_work_queue_page(&SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index: link_job_index,
            kind: SourcePackWorkQueueItemKind::LinkReduce,
            job_index: link_job_index,
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
            link_group_index: Some(group_index),
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 0,
            input_codegen_job_indices: Vec::new(),
            input_link_group_count: 1,
            input_link_group_indices: vec![0],
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        })
        .expect("store final reduce work item");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let err = execute_claimed_link_work_queue_item(
        &root,
        link_job_index,
        target,
        "worker-a",
        8,
        Some(100),
        &mut executor,
    )
    .expect_err("final link work item must reject a stale dense output key");
    let message = err.to_string();
    assert!(
        message.contains("dense final output artifact") && message.contains("first link job 20"),
        "unexpected final-link output-key validation error: {message}"
    );
    assert!(
        !store
            .path_for_key(&stale_output_key)
            .expect("stale linked output path")
            .exists(),
        "rejected stale final output key must not leave linked-output bytes"
    );
    assert!(
        !store
            .path_for_key(&expected_output_key)
            .expect("expected linked output path")
            .exists(),
        "rejected stale final output page must not write the expected linked output either"
    );

    std::fs::remove_dir_all(&root).expect("remove final link stale output key test dir");
}

#[test]
fn store_link_execution_page_rejects_descriptor_only_paged_object_state() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-descriptor-only-link-state-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create descriptor-only link state test dir");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let group_index = 0;
    let link_job_index = 7;
    let link_page = SourcePackHierarchicalLinkExecutionPage {
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
        output_key: hierarchical_link_partial_output_key(target, group_index, link_job_index),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            object_symbol_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        },
    };

    let err = store
        .store_hierarchical_link_execution_page(&link_page)
        .expect_err("descriptor rows without concrete object refs are not link evidence");
    let message = err.to_string();
    assert!(
        message.contains("descriptor summary")
            && message.contains("object artifact refs")
            && message.contains("not link artifact evidence"),
        "unexpected descriptor-only link state error: {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, group_index)
            .exists(),
        "rejected descriptor-only link state must not persist a link execution page"
    );

    std::fs::remove_dir_all(&root).expect("remove descriptor-only link state test dir");
}

#[test]
fn store_link_execution_page_rejects_descriptor_summary_with_only_interface_ranges() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-interface-range-descriptor-link-state-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create interface-range link state test dir");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let group_index = 0;
    let link_job_index = 7;
    let link_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: link_job_index,
        input_interface_count: 1,
        input_interface_page_count: 0,
        input_interface_ranges: vec![SourcePackJobIndexRange {
            first_job_index: 1,
            job_count: 1,
        }],
        input_interfaces: Vec::new(),
        input_object_count: 1,
        input_object_page_count: 0,
        input_objects: vec![SourcePackArtifactRef {
            artifact_index: 2,
            key: "wasm/codegen-object/lib-0/job-2/src-0-1".into(),
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
        output_key: hierarchical_link_partial_output_key(target, group_index, link_job_index),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            interface_symbol_count: 1,
            object_symbol_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        },
    };

    let err = store
        .store_hierarchical_link_execution_page(&link_page)
        .expect_err("interface dependency ranges alone are not persisted interface evidence");
    let message = err.to_string();
    assert!(
        message.contains("interface artifact refs")
            && message.contains("dependency ranges")
            && message.contains("not link artifact evidence"),
        "unexpected interface-range descriptor evidence error: {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, group_index)
            .exists(),
        "rejected interface-range descriptor state must not persist a link execution page"
    );

    std::fs::remove_dir_all(&root).expect("remove interface-range link state test dir");
}

#[test]
fn store_link_execution_page_rejects_descriptor_summary_with_mixed_interface_ranges() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-mixed-interface-range-descriptor-link-state-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create mixed interface-range link state test dir");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let group_index = 0;
    let link_job_index = 7;
    let link_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: link_job_index,
        input_interface_count: 2,
        input_interface_page_count: 0,
        input_interface_ranges: vec![SourcePackJobIndexRange {
            first_job_index: 3,
            job_count: 1,
        }],
        input_interfaces: vec![SourcePackArtifactRef {
            artifact_index: 1,
            key: "wasm/library-interface/lib-0/job-1/src-0-1".into(),
            producing_job_index: 1,
            kind: SourcePackArtifactKind::LibraryInterface,
        }],
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: vec![SourcePackArtifactRef {
            artifact_index: 2,
            key: "wasm/codegen-object/lib-0/job-2/src-0-1".into(),
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
        output_key: hierarchical_link_partial_output_key(target, group_index, link_job_index),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            interface_symbol_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        }
        .with_record_contracts_from_counts(),
    };

    let err = store
        .store_hierarchical_link_execution_page(&link_page)
        .expect_err("interface descriptors must not be backed by dependency-range cursors");
    let message = err.to_string();
    assert!(
        message.contains("interface symbol descriptor contracts")
            && message.contains("dependency ranges")
            && message.contains("concrete interface artifact refs"),
        "unexpected mixed interface-range descriptor evidence error: {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, group_index)
            .exists(),
        "rejected mixed interface-range descriptor state must not persist a link execution page"
    );

    std::fs::remove_dir_all(&root).expect("remove mixed interface-range link state test dir");
}

#[test]
fn persisted_link_execution_page_rejects_interface_descriptor_with_only_ranges() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-persisted-interface-range-descriptor-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let group_index = 0;
    let link_job_index = 7;
    let link_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: link_job_index,
        input_interface_count: 1,
        input_interface_page_count: 0,
        input_interface_ranges: vec![SourcePackJobIndexRange {
            first_job_index: 1,
            job_count: 1,
        }],
        input_interfaces: Vec::new(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: vec![SourcePackArtifactRef {
            artifact_index: 2,
            key: "wasm/codegen-object/lib-0/job-2/src-0-1".into(),
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
        output_key: hierarchical_link_partial_output_key(target, group_index, link_job_index),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            interface_symbol_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        }
        .with_record_contracts_from_counts(),
    };
    let link_page_path =
        store.hierarchical_link_execution_page_path_for_target(target, group_index);
    std::fs::create_dir_all(link_page_path.parent().expect("link page parent"))
        .expect("create persisted link page dir");
    std::fs::write(
        &link_page_path,
        serde_json::to_vec_pretty(&link_page)
            .expect("serialize persisted range-only descriptor link page"),
    )
    .expect("write persisted range-only descriptor link page");

    let err = store
        .load_hierarchical_link_execution_page_for_target(target, group_index)
        .expect_err("persisted interface descriptors need concrete artifact refs");
    let message = err.to_string();
    assert!(
        message.contains("interface symbol descriptor contracts")
            && message.contains("dependency ranges")
            && message.contains("concrete interface artifact refs"),
        "unexpected persisted interface-range descriptor error: {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove persisted interface-range descriptor test dir");
}

#[test]
fn store_link_execution_page_rejects_descriptor_counts_without_record_contracts() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-link-record-contract-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create link record contract test dir");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let group_index = 0;
    let link_job_index = 7;
    let link_page = SourcePackHierarchicalLinkExecutionPage {
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
            key: "wasm/library-interface/lib-0/job-1/src-0-1".into(),
            producing_job_index: 1,
            kind: SourcePackArtifactKind::LibraryInterface,
        }],
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: vec![SourcePackArtifactRef {
            artifact_index: 2,
            key: "wasm/codegen-object/lib-0/job-2/src-0-1".into(),
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
        output_key: hierarchical_link_partial_output_key(target, group_index, link_job_index),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            interface_symbol_count: 1,
            object_section_count: 1,
            object_symbol_count: 1,
            relocation_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        },
    };

    let err = store
        .store_hierarchical_link_execution_page(&link_page)
        .expect_err("descriptor counts must be backed by explicit link record contracts");
    let message = err.to_string();
    assert!(
        message.contains("descriptor counts")
            && message
                .contains("explicit interface/object/section/symbol/relocation record contracts"),
        "unexpected missing link record contract error: {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, group_index)
            .exists(),
        "rejected descriptor counts must not persist as link execution evidence"
    );

    std::fs::remove_dir_all(&root).expect("remove link record contract test dir");
}

#[test]
fn store_link_execution_page_rejects_job_index_before_group_index() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-link-page-negative-dense-base-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create dense-base link page test dir");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let group_index = 8;
    let link_job_index = 7;
    let link_page = SourcePackHierarchicalLinkExecutionPage {
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
            key: "wasm/library-interface/lib-0/job-1/src-0-1".into(),
            producing_job_index: 1,
            kind: SourcePackArtifactKind::LibraryInterface,
        }],
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: vec![SourcePackArtifactRef {
            artifact_index: 2,
            key: "wasm/codegen-object/lib-0/job-2/src-0-1".into(),
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
        output_key: hierarchical_link_partial_output_key(target, group_index, link_job_index),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };

    store
        .store_hierarchical_link_execution_page(&link_page)
        .expect_err("link execution pages must encode a nonnegative dense link-job base");
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, group_index)
            .exists(),
        "rejected stale dense-base page must not persist as link execution evidence"
    );

    std::fs::remove_dir_all(&root).expect("remove dense-base link page test dir");
}

#[test]
fn store_link_execution_page_rejects_stale_object_artifact_index() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-stale-link-object-index-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create stale object index test dir");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let group_index = 0;
    let link_job_index = 7;
    let object_key = "wasm/codegen-object/lib-0/job-2/src-0-1".to_string();
    let link_page = SourcePackHierarchicalLinkExecutionPage {
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
            key: "wasm/library-interface/lib-0/job-1/src-0-1".into(),
            producing_job_index: 1,
            kind: SourcePackArtifactKind::LibraryInterface,
        }],
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: vec![
            SourcePackArtifactRef {
                artifact_index: 2,
                key: object_key.clone(),
                producing_job_index: 2,
                kind: SourcePackArtifactKind::CodegenObject,
            },
            SourcePackArtifactRef {
                artifact_index: 42,
                key: object_key,
                producing_job_index: 2,
                kind: SourcePackArtifactKind::CodegenObject,
            },
        ],
        input_group_count: 0,
        input_group_page_count: 0,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: hierarchical_link_partial_output_key(target, group_index, link_job_index),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };

    let err = store
        .store_hierarchical_link_execution_page(&link_page)
        .expect_err("stale object artifact indices must not persist as link input evidence");
    let message = err.to_string();
    assert!(
        message.contains("artifact index 42")
            && message.contains("producer job 2")
            && message.contains("dense producer job")
            && message.contains("CodegenObject"),
        "unexpected stale object artifact-index error: {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, group_index)
            .exists(),
        "rejected stale object artifact index must not persist a link execution page"
    );

    std::fs::remove_dir_all(&root).expect("remove stale object index test dir");
}

#[test]
fn store_artifact_ref_page_rejects_stale_key_producer_and_source_range() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-stale-artifact-ref-page-key-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create stale artifact-ref page key test dir");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let artifact_count = 8;

    let valid_page = SourcePackBuildArtifactRefPage {
        version: SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION,
        target,
        artifact_index: 3,
        artifact_ref: SourcePackArtifactRef {
            artifact_index: 3,
            key: source_pack_artifact_key_for_output(
                target,
                SourcePackArtifactKind::CodegenObject,
                0,
                3,
                4,
                2,
            ),
            producing_job_index: 3,
            kind: SourcePackArtifactKind::CodegenObject,
        },
        source_bytes: 32,
        source_file_count: 2,
        source_lines: 4,
    };
    store
        .store_build_artifact_ref_page(&valid_page, artifact_count)
        .expect("self-consistent artifact-ref page should persist");
    assert_eq!(
        store
            .load_build_artifact_ref_page_for_target(target, 3, artifact_count)
            .expect("load persisted artifact-ref page")
            .artifact_ref
            .key,
        valid_page.artifact_ref.key
    );

    let stale_producer_page = SourcePackBuildArtifactRefPage {
        artifact_index: 4,
        artifact_ref: SourcePackArtifactRef {
            artifact_index: 4,
            key: source_pack_artifact_key_for_output(
                target,
                SourcePackArtifactKind::CodegenObject,
                0,
                3,
                4,
                2,
            ),
            producing_job_index: 4,
            kind: SourcePackArtifactKind::CodegenObject,
        },
        ..valid_page.clone()
    };
    let err = store
        .store_build_artifact_ref_page(&stale_producer_page, artifact_count)
        .expect_err("artifact-ref page key producer must match the persisted producer job");
    let message = err.to_string();
    assert!(
        message.contains("producer job 3") && message.contains("artifact ref producer job 4"),
        "unexpected stale producer validation error: {message}"
    );
    assert!(
        !store
            .build_artifact_ref_page_path_for_target(target, 4)
            .exists(),
        "rejected stale artifact-ref producer must not persist a page"
    );

    let stale_source_range_page = SourcePackBuildArtifactRefPage {
        artifact_index: 5,
        artifact_ref: SourcePackArtifactRef {
            artifact_index: 5,
            key: source_pack_artifact_key_for_output(
                target,
                SourcePackArtifactKind::CodegenObject,
                0,
                5,
                4,
                1,
            ),
            producing_job_index: 5,
            kind: SourcePackArtifactKind::CodegenObject,
        },
        ..valid_page
    };
    let err = store
        .store_build_artifact_ref_page(&stale_source_range_page, artifact_count)
        .expect_err("artifact-ref page key source range must match persisted page metadata");
    let message = err.to_string();
    assert!(
        message.contains("covers 1 files") && message.contains("source file count 2"),
        "unexpected stale source-range validation error: {message}"
    );
    assert!(
        !store
            .build_artifact_ref_page_path_for_target(target, 5)
            .exists(),
        "rejected stale artifact-ref source range must not persist a page"
    );

    std::fs::remove_dir_all(&root).expect("remove stale artifact-ref page key test dir");
}

#[test]
fn store_artifact_ref_page_rejects_linked_output_in_non_final_slot() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-artifact-ref-final-slot-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create artifact-ref final-slot test dir");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let artifact_count = 3;

    let linked_output_in_non_final_slot = SourcePackBuildArtifactRefPage {
        version: SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION,
        target,
        artifact_index: 1,
        artifact_ref: SourcePackArtifactRef {
            artifact_index: 1,
            key: source_pack_artifact_key_for_output(
                target,
                SourcePackArtifactKind::LinkedOutput,
                0,
                1,
                0,
                1,
            ),
            producing_job_index: 1,
            kind: SourcePackArtifactKind::LinkedOutput,
        },
        source_bytes: 8,
        source_file_count: 1,
        source_lines: 1,
    };
    store
        .store_build_artifact_ref_page(&linked_output_in_non_final_slot, artifact_count)
        .expect_err("linked-output artifact refs must only occupy the dense final slot");
    assert!(
        !store
            .build_artifact_ref_page_path_for_target(target, 1)
            .exists(),
        "rejected non-final linked-output row must not persist an artifact-ref page"
    );

    let object_in_final_slot = SourcePackBuildArtifactRefPage {
        version: SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION,
        target,
        artifact_index: 2,
        artifact_ref: SourcePackArtifactRef {
            artifact_index: 2,
            key: source_pack_artifact_key_for_output(
                target,
                SourcePackArtifactKind::CodegenObject,
                0,
                2,
                0,
                1,
            ),
            producing_job_index: 2,
            kind: SourcePackArtifactKind::CodegenObject,
        },
        source_bytes: 8,
        source_file_count: 1,
        source_lines: 1,
    };
    store
        .store_build_artifact_ref_page(&object_in_final_slot, artifact_count)
        .expect_err("the dense final artifact slot must carry linked-output evidence");
    assert!(
        !store
            .build_artifact_ref_page_path_for_target(target, 2)
            .exists(),
        "rejected final-slot object row must not persist an artifact-ref page"
    );

    std::fs::remove_dir_all(&root).expect("remove artifact-ref final-slot test dir");
}

#[test]
fn store_link_execution_page_rejects_pre_paged_partial_link_inputs() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-prepaged-partial-link-input-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create pre-paged partial input test dir");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let group_index = 2;
    let link_job_index = 9;
    let link_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Reduce,
        job_index: link_job_index,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: Vec::new(),
        input_group_count: 1,
        input_group_page_count: 1,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: hierarchical_link_partial_output_key(target, group_index, link_job_index),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };

    let err = store
        .store_hierarchical_link_execution_page(&link_page)
        .expect_err("store input must not persist missing partial-link sidecar evidence");
    let message = err.to_string();
    assert!(
        message.contains("pre-paged")
            && message.contains("partial-link output keys")
            && message.contains("missing artifact evidence"),
        "unexpected pre-paged partial-link input error: {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, group_index)
            .exists(),
        "rejected pre-paged partial-link input must not persist a link execution page"
    );

    std::fs::remove_dir_all(&root).expect("remove pre-paged partial input test dir");
}

#[test]
fn final_link_work_queue_rejects_persisted_relocation_descriptor_summary() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-final-link-relocation-summary-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let link_job_index = 7;
    let group_index = 0;
    let output_key = "wasm/linked-output/job-7/src-0-1".to_string();
    let link_page = SourcePackHierarchicalLinkExecutionPage {
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
        output_key: output_key.clone(),
        final_output: true,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            relocation_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        }
        .with_record_contracts_from_counts(),
    };
    let link_page_path =
        store.hierarchical_link_execution_page_path_for_target(target, group_index);
    std::fs::create_dir_all(link_page_path.parent().expect("link page parent"))
        .expect("create persisted link page dir");
    std::fs::write(
        &link_page_path,
        serde_json::to_vec_pretty(&link_page).expect("serialize persisted link page"),
    )
    .expect("write persisted link page");
    store
        .store_work_queue_page(&SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index: link_job_index,
            kind: SourcePackWorkQueueItemKind::LinkLeaf,
            job_index: link_job_index,
            dependency_item_indices: vec![0, 1],
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
            link_group_index: Some(group_index),
            input_frontend_job_count: 1,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 1,
            input_codegen_job_indices: vec![1],
            input_link_group_count: 0,
            input_link_group_indices: Vec::new(),
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        })
        .expect("store link work item");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let err = execute_claimed_link_work_queue_item(
        &root,
        link_job_index,
        target,
        "worker-a",
        8,
        Some(100),
        &mut executor,
    )
    .expect_err("final link work item must reject unresolved relocation descriptors");
    let message = err.to_string();
    assert!(
        message.contains("final linked output") && message.contains("relocation descriptors"),
        "unexpected final-link descriptor error: {message}"
    );
    assert!(
        !store
            .path_for_key(&output_key)
            .expect("linked output artifact path")
            .exists(),
        "rejected final link descriptor must not leave linked-output bytes"
    );

    std::fs::remove_dir_all(&root).expect("remove final link relocation summary test dir");
}

#[test]
fn store_final_link_execution_page_rejects_object_domain_output_contracts() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-final-link-object-domain-contract-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create final object-domain contract test dir");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let group_index = 0;
    let link_job_index = 7;
    let link_page = SourcePackHierarchicalLinkExecutionPage {
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
            key: "wasm/library-interface/lib-0/job-1/src-0-1".into(),
            producing_job_index: 1,
            kind: SourcePackArtifactKind::LibraryInterface,
        }],
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: vec![SourcePackArtifactRef {
            artifact_index: 2,
            key: "wasm/codegen-object/lib-0/job-2/src-0-1".into(),
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
        output_key: "wasm/linked-output/job-7/src-0-1".into(),
        final_output: true,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            object_section_count: 1,
            object_symbol_count: 1,
            export_symbol_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        }
        .with_record_contracts_from_counts(),
    };

    let err = store
        .store_hierarchical_link_execution_page(&link_page)
        .expect_err("final linked-output pages must not persist object-domain output evidence");
    let message = err.to_string();
    assert!(
        message.contains("final linked output")
            && message.contains("object-domain")
            && message.contains("linked-output records"),
        "unexpected final object-domain contract error: {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, group_index)
            .exists(),
        "rejected final object-domain descriptor page must not persist link execution evidence"
    );

    std::fs::remove_dir_all(&root).expect("remove final object-domain contract test dir");
}

#[test]
fn store_final_link_execution_page_rejects_interface_domain_output_contracts() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-final-link-interface-domain-contract-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create final interface-domain contract test dir");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let group_index = 0;
    let link_job_index = 7;
    let link_page = SourcePackHierarchicalLinkExecutionPage {
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
            key: "wasm/library-interface/lib-0/job-1/src-0-1".into(),
            producing_job_index: 1,
            kind: SourcePackArtifactKind::LibraryInterface,
        }],
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: vec![SourcePackArtifactRef {
            artifact_index: 2,
            key: "wasm/codegen-object/lib-0/job-2/src-0-1".into(),
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
        output_key: "wasm/linked-output/job-7/src-0-1".into(),
        final_output: true,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            interface_symbol_count: 1,
            export_symbol_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        }
        .with_record_contracts_from_counts(),
    };

    let err = store
        .store_hierarchical_link_execution_page(&link_page)
        .expect_err("final linked-output pages must not persist interface-domain output evidence");
    let message = err.to_string();
    assert!(
        message.contains("final linked output")
            && message.contains("interface-domain")
            && message.contains("linked-output records"),
        "unexpected final interface-domain contract error: {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, group_index)
            .exists(),
        "rejected final interface-domain descriptor page must not persist link execution evidence"
    );

    std::fs::remove_dir_all(&root).expect("remove final interface-domain contract test dir");
}

#[test]
fn store_partial_link_execution_page_rejects_linked_output_domain_contracts() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-partial-link-linked-output-contract-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create partial linked-output contract test dir");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let group_index = 0;
    let link_job_index = 7;
    let link_page = SourcePackHierarchicalLinkExecutionPage {
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
            key: "wasm/library-interface/lib-0/job-1/src-0-1".into(),
            producing_job_index: 1,
            kind: SourcePackArtifactKind::LibraryInterface,
        }],
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: vec![SourcePackArtifactRef {
            artifact_index: 2,
            key: "wasm/codegen-object/lib-0/job-2/src-0-1".into(),
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
        output_key: hierarchical_link_partial_output_key(target, group_index, link_job_index),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            export_symbol_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        }
        .with_record_contracts_from_counts(),
    };

    let err = store
        .store_hierarchical_link_execution_page(&link_page)
        .expect_err("partial-link pages must not persist linked-output record evidence");
    let message = err.to_string();
    assert!(
        message.contains("partial-link output")
            && message.contains("linked-output symbol descriptor contracts")
            && message.contains("final linked-output artifact evidence"),
        "unexpected partial linked-output contract error: {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, group_index)
            .exists(),
        "rejected partial linked-output descriptor page must not persist link execution evidence"
    );

    std::fs::remove_dir_all(&root).expect("remove partial linked-output contract test dir");
}

#[test]
fn x86_link_work_queue_rejects_object_inputs_without_descriptor_metadata() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-x86-link-object-metadata-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::X86_64;
    let link_job_index = 7;
    let group_index = 0;
    let output_key = "x86_64/linked-output/job-7/src-0-1".to_string();
    let link_page = SourcePackHierarchicalLinkExecutionPage {
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
        output_key: output_key.clone(),
        final_output: true,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            interface_symbol_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        }
        .with_record_contracts_from_counts(),
    };
    let link_page_path =
        store.hierarchical_link_execution_page_path_for_target(target, group_index);
    std::fs::create_dir_all(link_page_path.parent().expect("link page parent"))
        .expect("create persisted x86 link page dir");
    std::fs::write(
        &link_page_path,
        serde_json::to_vec_pretty(&link_page).expect("serialize persisted x86 link page"),
    )
    .expect("write persisted x86 link page");
    store
        .store_work_queue_page(&SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index: link_job_index,
            kind: SourcePackWorkQueueItemKind::LinkLeaf,
            job_index: link_job_index,
            dependency_item_indices: vec![0, 1],
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
            link_group_index: Some(group_index),
            input_frontend_job_count: 1,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 1,
            input_codegen_job_indices: vec![1],
            input_link_group_count: 0,
            input_link_group_indices: Vec::new(),
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        })
        .expect("store x86 link work item");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let err = execute_claimed_link_work_queue_item(
        &root,
        link_job_index,
        target,
        "worker-a",
        8,
        Some(100),
        &mut executor,
    )
    .expect_err("x86 link work item must reject object inputs without metadata");
    let message = err.to_string();
    assert!(
        message.contains("x86_64")
            && message.contains("object inputs")
            && message.contains("descriptor metadata"),
        "unexpected x86 object metadata validation error: {message}"
    );
    assert!(
        !store
            .path_for_key(&output_key)
            .expect("linked output artifact path")
            .exists(),
        "rejected x86 link page must not leave linked-output bytes"
    );

    std::fs::remove_dir_all(&root).expect("remove x86 link object metadata test dir");
}

#[test]
fn x86_link_execution_rejects_object_symbol_metadata_without_sections() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-x86-link-object-section-metadata-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create object section metadata test dir");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::X86_64;
    let group_index = 0;
    let link_job_index = 7;
    let link_page = SourcePackHierarchicalLinkExecutionPage {
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
            key: "x86_64/library-interface/lib-0/job-1/src-0-1".into(),
            producing_job_index: 1,
            kind: SourcePackArtifactKind::LibraryInterface,
        }],
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: vec![SourcePackArtifactRef {
            artifact_index: 2,
            key: "x86_64/codegen-object/lib-0/job-2/src-0-1".into(),
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
        output_key: hierarchical_link_partial_output_key(target, group_index, link_job_index),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            interface_symbol_count: 1,
            object_symbol_count: 1,
            relocation_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        }
        .with_record_contracts_from_counts(),
    };

    let err = store
        .store_hierarchical_link_execution_page(&link_page)
        .expect_err("x86 object link metadata must include object section rows");
    let message = err.to_string();
    assert!(
        message.contains("object symbol, unresolved-symbol, or relocation contracts")
            && message.contains("object section record contracts"),
        "unexpected x86 object section metadata validation error: {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, group_index)
            .exists(),
        "rejected object-section metadata must not publish a link execution page"
    );

    std::fs::remove_dir_all(&root).expect("remove object section metadata test dir");
}

#[test]
fn reduce_link_execution_rejects_carried_object_metadata_without_sections() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-reduce-link-object-section-metadata-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create reduce object section metadata test dir");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let group_index = 1;
    let first_link_job_index = 7;
    let link_job_index = first_link_job_index + group_index;
    let link_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Reduce,
        job_index: link_job_index,
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
        input_group_output_keys: vec![hierarchical_link_partial_output_key(
            target,
            0,
            first_link_job_index,
        )],
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: hierarchical_link_partial_output_key(target, group_index, link_job_index),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            object_symbol_count: 1,
            relocation_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        }
        .with_record_contracts_from_counts(),
    };

    let err = store
        .store_hierarchical_link_execution_page(&link_page)
        .expect_err("carried partial-link object metadata must include object section rows");
    let message = err.to_string();
    assert!(
        message.contains("object symbol, unresolved-symbol, or relocation contracts")
            && message.contains("object section record contracts"),
        "unexpected reduce object section metadata validation error: {message}"
    );
    assert!(
        !store
            .hierarchical_link_execution_page_path_for_target(target, group_index)
            .exists(),
        "rejected reduce object metadata must not publish a link execution page"
    );

    std::fs::remove_dir_all(&root).expect("remove reduce object section metadata test dir");
}

#[test]
fn partial_link_work_queue_rejects_mismatched_persisted_output_key() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-partial-link-output-key-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let link_job_index = 8;
    let group_index = 2;
    let expected_output_key =
        hierarchical_link_partial_output_key(target, group_index, link_job_index);
    let wrong_output_key =
        hierarchical_link_partial_output_key(target, group_index - 1, link_job_index);
    let link_page = SourcePackHierarchicalLinkExecutionPage {
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
        output_key: wrong_output_key.clone(),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };
    let link_page_path =
        store.hierarchical_link_execution_page_path_for_target(target, group_index);
    std::fs::create_dir_all(link_page_path.parent().expect("link page parent"))
        .expect("create persisted link page dir");
    std::fs::write(
        &link_page_path,
        serde_json::to_vec_pretty(&link_page).expect("serialize persisted link page"),
    )
    .expect("write persisted link page");
    store
        .store_work_queue_page(&SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index: link_job_index,
            kind: SourcePackWorkQueueItemKind::LinkLeaf,
            job_index: link_job_index,
            dependency_item_indices: vec![0, 1],
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
            link_group_index: Some(group_index),
            input_frontend_job_count: 1,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 1,
            input_codegen_job_indices: vec![1],
            input_link_group_count: 0,
            input_link_group_indices: Vec::new(),
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        })
        .expect("store partial-link work item");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let err = execute_claimed_link_work_queue_item(
        &root,
        link_job_index,
        target,
        "worker-a",
        8,
        Some(100),
        &mut executor,
    )
    .expect_err("partial link work item must reject a mismatched persisted output key");
    let message = err.to_string();
    assert!(
        message.contains("partial-link output key") && message.contains(&expected_output_key),
        "unexpected partial-link output key error: {message}"
    );
    assert!(
        !store
            .path_for_key(&wrong_output_key)
            .expect("wrong partial-link artifact path")
            .exists(),
        "rejected partial-link page must not write the mismatched output key"
    );
    assert!(
        !store
            .path_for_key(&expected_output_key)
            .expect("expected partial-link artifact path")
            .exists(),
        "rejected partial-link page must not write the expected output key either"
    );

    std::fs::remove_dir_all(&root).expect("remove partial-link output key test dir");
}

#[test]
fn partial_link_work_queue_requires_producer_execution_page_before_consuming_partial_artifact() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-partial-link-producer-evidence-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create partial producer evidence test dir");
    let mut store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let producer_group_index = 0;
    let consumer_group_index = 1;
    let first_link_job_index = 7;
    let link_job_index = first_link_job_index + consumer_group_index;
    let partial_output_key =
        hierarchical_link_partial_output_key(target, producer_group_index, first_link_job_index);
    let reduce_output_key =
        hierarchical_link_partial_output_key(target, consumer_group_index, link_job_index);

    store
        .store_partial_link_output(&partial_output_key, vec![1, 2, 3])
        .expect("store orphan partial-link bytes");

    let link_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: consumer_group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Reduce,
        job_index: link_job_index,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: Vec::new(),
        input_group_count: 0,
        input_group_page_count: 0,
        input_group_indices: vec![producer_group_index],
        input_group_output_keys: vec![partial_output_key.clone()],
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: reduce_output_key.clone(),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };
    let link_page_path =
        store.hierarchical_link_execution_page_path_for_target(target, consumer_group_index);
    std::fs::create_dir_all(link_page_path.parent().expect("link page parent"))
        .expect("create persisted link page dir");
    std::fs::write(
        &link_page_path,
        serde_json::to_vec_pretty(&link_page).expect("serialize reduce link page"),
    )
    .expect("write reduce link page");
    store
        .store_work_queue_page(&SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index: link_job_index,
            kind: SourcePackWorkQueueItemKind::LinkReduce,
            job_index: link_job_index,
            dependency_item_indices: vec![first_link_job_index],
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
            link_group_index: Some(consumer_group_index),
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 0,
            input_codegen_job_indices: Vec::new(),
            input_link_group_count: 1,
            input_link_group_indices: vec![producer_group_index],
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        })
        .expect("store reduce link work item");
    store
        .store_work_queue_progress_page(&SourcePackWorkQueueProgressPage {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
            target,
            page_index: 0,
            first_item_index: 0,
            item_count: link_job_index + 1,
            artifact_item_indices: Vec::new(),
            remaining_dependency_counts: Vec::new(),
            remaining_dependent_counts: Vec::new(),
            completed_item_indices: Vec::new(),
            ready_item_indices: vec![link_job_index],
            ready_artifact_item_indices: Vec::new(),
            claimed_items: vec![SourcePackWorkQueueItemClaim {
                item_index: link_job_index,
                worker_id: "worker-a".into(),
                lease_expires_unix_nanos: Some(200),
            }],
        })
        .expect("store claimed reduce link progress page");
    store
        .store_work_queue_progress_index(&SourcePackWorkQueueProgressIndex {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
            target,
            work_item_count: link_job_index + 1,
            page_size: link_job_index + 1,
            page_count: 1,
            artifact_item_count: 0,
            completed_item_count: 0,
            ready_item_count: 1,
            ready_artifact_item_count: 0,
            claimed_item_count: 1,
            first_ready_item_index: Some(link_job_index),
            first_ready_artifact_item_index: None,
        })
        .expect("store claimed reduce link progress index");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let err = execute_claimed_link_work_queue_item(
        &root,
        link_job_index,
        target,
        "worker-a",
        8,
        Some(100),
        &mut executor,
    )
    .expect_err("reduce link execution must prove partial-link producer page evidence");
    let message = err.to_string();
    assert!(
        message.contains("partial-link producer execution page evidence")
            && message.contains(&partial_output_key)
            && message.contains("before consuming partial-link artifact"),
        "unexpected missing producer-page evidence error: {message}"
    );
    assert!(
        !store
            .path_for_key(&reduce_output_key)
            .expect("reduce partial-link output path")
            .exists(),
        "rejected reduce link execution must not write a partial-link output"
    );
    assert!(
        executor.events.is_empty(),
        "missing partial-link producer evidence must be rejected before link execution begins: {:?}",
        executor.events
    );

    std::fs::remove_dir_all(&root).expect("remove partial producer evidence test dir");
}

#[test]
fn completed_link_replay_rejects_partial_descriptor_summary_without_artifact_bytes() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-completed-partial-artifact-evidence-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create completed partial evidence test dir");
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let first_link_job_index = 7;
    let producer_group_index = 0;
    let final_group_index = 1;
    let final_link_job_index = first_link_job_index + final_group_index;
    let partial_output_key =
        hierarchical_link_partial_output_key(target, producer_group_index, first_link_job_index);
    let final_output_key = "linked-output/job-7/src-0-1".to_string();

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: producer_group_index,
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
            source_byte_count: 1,
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
        .expect("store descriptor-carrying partial-link producer page");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: final_group_index,
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
            input_group_indices: vec![producer_group_index],
            input_group_output_keys: vec![partial_output_key.clone()],
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
            output_key: final_output_key.clone(),
            final_output: true,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        })
        .expect("store final reduce page consuming descriptor-carrying producer");

    let execution_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index,
        final_link_group_index: final_group_index,
        final_link_job_index,
        link_group_count: 2,
        final_output_key,
    };
    let err = validate_completed_link_execution_index_evidence(&store, &execution_index)
        .expect_err("completed replay must require concrete partial-link artifact bytes");
    let message = err.to_string();
    assert!(
        message.contains("descriptor summary requires concrete partial-link output artifact")
            && message.contains(&partial_output_key)
            && message.contains("descriptor summaries are not link artifact evidence"),
        "expected missing partial-link artifact evidence error, got {message}"
    );
    assert!(
        !store
            .path_for_key(&partial_output_key)
            .expect("partial-link artifact path")
            .exists(),
        "test must leave the producer partial-link bytes absent"
    );

    std::fs::remove_dir_all(&root).expect("remove completed partial evidence test dir");
}

#[test]
fn partial_link_work_queue_rejects_stale_producer_source_summary() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-partial-link-source-summary-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create partial source summary test dir");
    let mut store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let producer_group_index = 0;
    let consumer_group_index = 1;
    let first_link_job_index = 7;
    let link_job_index = first_link_job_index + consumer_group_index;
    let partial_output_key =
        hierarchical_link_partial_output_key(target, producer_group_index, first_link_job_index);
    let reduce_output_key =
        hierarchical_link_partial_output_key(target, consumer_group_index, link_job_index);

    store
        .store_partial_link_output(&partial_output_key, b"partial:0:0:0".to_vec())
        .expect("store partial-link bytes for stale source-summary test");
    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: producer_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: first_link_job_index,
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
            source_byte_count: 16,
            source_file_count: 2,
            source_line_count: 3,
            output_key: partial_output_key.clone(),
            final_output: false,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        })
        .expect("store partial-link producer execution page");

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: consumer_group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            job_index: link_job_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: Vec::new(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: vec![producer_group_index],
            input_group_output_keys: vec![partial_output_key.clone()],
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
            output_key: reduce_output_key.clone(),
            final_output: false,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        })
        .expect("store stale reduce execution page");

    store
        .store_work_queue_page(&SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index: link_job_index,
            kind: SourcePackWorkQueueItemKind::LinkReduce,
            job_index: link_job_index,
            dependency_item_indices: vec![first_link_job_index],
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
            link_group_index: Some(consumer_group_index),
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 0,
            input_codegen_job_indices: Vec::new(),
            input_link_group_count: 1,
            input_link_group_indices: vec![producer_group_index],
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        })
        .expect("store reduce link work item");
    store
        .store_work_queue_progress_page(&SourcePackWorkQueueProgressPage {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
            target,
            page_index: 0,
            first_item_index: 0,
            item_count: link_job_index + 1,
            artifact_item_indices: Vec::new(),
            remaining_dependency_counts: Vec::new(),
            remaining_dependent_counts: Vec::new(),
            completed_item_indices: Vec::new(),
            ready_item_indices: vec![link_job_index],
            ready_artifact_item_indices: Vec::new(),
            claimed_items: vec![SourcePackWorkQueueItemClaim {
                item_index: link_job_index,
                worker_id: "worker-a".into(),
                lease_expires_unix_nanos: Some(200),
            }],
        })
        .expect("store claimed reduce link progress page");
    store
        .store_work_queue_progress_index(&SourcePackWorkQueueProgressIndex {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
            target,
            work_item_count: link_job_index + 1,
            page_size: link_job_index + 1,
            page_count: 1,
            artifact_item_count: 0,
            completed_item_count: 0,
            ready_item_count: 1,
            ready_artifact_item_count: 0,
            claimed_item_count: 1,
            first_ready_item_index: Some(link_job_index),
            first_ready_artifact_item_index: None,
        })
        .expect("store claimed reduce link progress index");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let err = execute_claimed_link_work_queue_item(
        &root,
        link_job_index,
        target,
        "worker-a",
        8,
        Some(100),
        &mut executor,
    )
    .expect_err("reduce link execution must reject stale producer source summaries");
    let message = err.to_string();
    assert!(
        message.contains("partial-link producer source summary bytes/files/lines 16/2/3")
            && message.contains("does not match reduce page 1/1/1")
            && message.contains("must not write stale partial-link source evidence"),
        "unexpected partial-link source summary error: {message}"
    );
    assert!(
        !store
            .path_for_key(&reduce_output_key)
            .expect("reduce partial-link output path")
            .exists(),
        "rejected reduce link execution must not write stale partial-link output"
    );

    std::fs::remove_dir_all(&root).expect("remove partial source summary test dir");
}

#[test]
fn persisted_partial_link_input_keys_reject_non_dense_producer_jobs() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-partial-link-input-key-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let group_index = 3;
    let page_index = 0;
    let partial_page_path = store.hierarchical_link_execution_partial_page_path_for_target(
        target,
        group_index,
        page_index,
    );
    std::fs::create_dir_all(partial_page_path.parent().expect("partial page parent"))
        .expect("create partial input page dir");
    std::fs::write(
        &partial_page_path,
        serde_json::to_vec_pretty(&SourcePackHierarchicalLinkExecutionPartialPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION,
            target,
            group_index,
            job_index: 53,
            page_index,
            first_input_position: 0,
            input_count: 1,
            input_group_indices: vec![1],
            input_group_output_keys: vec![hierarchical_link_partial_output_key(target, 1, 99)],
        })
        .expect("serialize malformed partial input page"),
    )
    .expect("write malformed partial input page");

    let err = store
        .load_hierarchical_link_execution_partial_page_for_target(target, group_index, page_index)
        .expect_err("persisted partial-link input keys must name the dense producer job");
    let message = err.to_string();
    assert!(
        message.contains("producer job 99") && message.contains("expected dense producer job 51"),
        "unexpected partial-link input key validation error: {message}"
    );

    std::fs::remove_dir_all(&root).expect("remove partial-link input key test dir");
}

#[test]
fn linked_output_descriptor_rejects_partial_link_output_records() {
    let target = SourcePackArtifactTarget::Wasm;
    let page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: 2,
        kind: SourcePackHierarchicalLinkGroupKind::Reduce,
        job_index: 92,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: Vec::new(),
        input_group_count: 1,
        input_group_page_count: 1,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: "wasm/linked-output/job-92/src-0-1".into(),
        final_output: true,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };
    let descriptor = GpuSourcePackArtifactDescriptor::hierarchical_linked_output_contract_for_page(
        &page, 0, 0, 1,
    );
    descriptor
        .validate_contract()
        .expect("baseline final linked-output contract is valid");

    let mut document =
        serde_json::to_value(&descriptor).expect("serialize linked-output descriptor");
    for arrays_key in ["output_record_arrays", "record_arrays"] {
        let arrays = document
            .get_mut(arrays_key)
            .and_then(serde_json::Value::as_array_mut)
            .unwrap_or_else(|| panic!("descriptor JSON should include {arrays_key}"));
        arrays.push(serde_json::json!({
            "name": "accidental_partial_link_relocation_records"
        }));
    }
    document
        .get_mut("descriptor_records")
        .and_then(serde_json::Value::as_array_mut)
        .expect("descriptor JSON should include descriptor records")
        .push(serde_json::json!({
            "name": "accidental_partial_link_relocations",
            "domain": "PartialLink",
            "kind": "Relocation",
            "flow": "Output",
            "record_array": "accidental_partial_link_relocation_records"
        }));

    let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document)
        .expect("parse tampered linked-output descriptor JSON");
    let err = parsed
        .validate_contract()
        .expect_err("final linked-output descriptor must not output partial-link records");
    assert!(err.contains("must only output LinkedOutput records"));
    assert!(err.contains("PartialLink"));
}

#[test]
fn linked_output_descriptor_rejects_partial_link_inputs_without_group() {
    let target = SourcePackArtifactTarget::Wasm;
    let page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: 2,
        kind: SourcePackHierarchicalLinkGroupKind::Reduce,
        job_index: 92,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: Vec::new(),
        input_group_count: 1,
        input_group_page_count: 1,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: "wasm/linked-output/job-92/src-0-1".into(),
        final_output: true,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };
    let descriptor = GpuSourcePackArtifactDescriptor::hierarchical_linked_output_contract_for_page(
        &page, 0, 0, 1,
    );
    descriptor
        .validate_contract()
        .expect("baseline final linked-output descriptor is valid");

    let mut document =
        serde_json::to_value(&descriptor).expect("serialize linked-output descriptor");
    document["group_index"] = serde_json::Value::Null;
    let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document)
        .expect("parse persisted linked-output descriptor without group identity");
    assert_eq!(
        parsed.group_index, None,
        "persisted descriptor should retain the missing group identity"
    );

    let err = parsed
        .validate_contract()
        .expect_err("partial-link final outputs must keep hierarchical link group evidence");
    assert!(err.contains("partial-link dependencies"));
    assert!(err.contains("hierarchical link group"));
}

#[test]
fn link_descriptors_track_unresolved_symbols_until_final_output() {
    let target = SourcePackArtifactTarget::Wasm;
    let partial_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: 1,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: 91,
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
        output_key: hierarchical_link_partial_output_key(target, 1, 91),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };
    let partial_descriptor =
        GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(&partial_page, 1, 1, 0);
    partial_descriptor
        .validate_contract()
        .expect("baseline partial-link descriptor contract is valid");
    assert!(
        partial_descriptor
            .output_record_arrays
            .iter()
            .any(|array| array.name == "partial_link_unresolved_symbol_records"),
        "partial-link output must reserve unresolved-symbol rows for resumable linking"
    );
    assert!(
        partial_descriptor.descriptor_records.iter().any(|record| {
            record.domain == GpuSourcePackDescriptorRecordDomain::PartialLink
                && record.kind == GpuSourcePackDescriptorRecordKind::UnresolvedSymbol
                && record.flow == GpuSourcePackDescriptorRecordFlow::Output
        }),
        "partial-link descriptor records must name unresolved-symbol output rows"
    );

    let mut missing_unresolved_symbols =
        serde_json::to_value(&partial_descriptor).expect("serialize partial-link descriptor");
    let descriptor_records = missing_unresolved_symbols
        .get_mut("descriptor_records")
        .and_then(serde_json::Value::as_array_mut)
        .expect("descriptor JSON should include descriptor records");
    descriptor_records.retain(|record| {
        record.get("kind").and_then(serde_json::Value::as_str) != Some("UnresolvedSymbol")
            || record.get("flow").and_then(serde_json::Value::as_str) != Some("Output")
    });
    let parsed_missing =
        serde_json::from_value::<GpuSourcePackArtifactDescriptor>(missing_unresolved_symbols)
            .expect("parse partial-link descriptor without unresolved-symbol rows");
    let err = parsed_missing
        .validate_contract()
        .expect_err("partial-link descriptors must declare unresolved-symbol outputs");
    assert!(err.contains("output unresolved symbols"));

    let final_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: 2,
        kind: SourcePackHierarchicalLinkGroupKind::Reduce,
        job_index: 92,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: Vec::new(),
        input_group_count: 1,
        input_group_page_count: 1,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: "wasm/linked-output/job-92/src-0-1".into(),
        final_output: true,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };
    let final_descriptor =
        GpuSourcePackArtifactDescriptor::hierarchical_linked_output_contract_for_page(
            &final_page,
            0,
            0,
            1,
        );
    final_descriptor
        .validate_contract()
        .expect("baseline linked-output descriptor contract is valid");
    let mut unresolved_final =
        serde_json::to_value(&final_descriptor).expect("serialize linked-output descriptor");
    for arrays_key in ["output_record_arrays", "record_arrays"] {
        unresolved_final
            .get_mut(arrays_key)
            .and_then(serde_json::Value::as_array_mut)
            .unwrap_or_else(|| panic!("descriptor JSON should include {arrays_key}"))
            .push(serde_json::json!({
                "name": "linked_output_unresolved_symbol_records"
            }));
    }
    unresolved_final
        .get_mut("descriptor_records")
        .and_then(serde_json::Value::as_array_mut)
        .expect("descriptor JSON should include descriptor records")
        .push(serde_json::json!({
            "name": "linked_output_unresolved_symbols",
            "domain": "LinkedOutput",
            "kind": "UnresolvedSymbol",
            "flow": "Output",
            "record_array": "linked_output_unresolved_symbol_records"
        }));
    let parsed_final = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(unresolved_final)
        .expect("parse linked-output descriptor with unresolved-symbol output rows");
    let err = parsed_final
        .validate_contract()
        .expect_err("final linked-output descriptors must not emit unresolved symbols");
    assert!(err.contains("unresolved symbol descriptors"));
}

#[test]
fn linked_output_descriptor_rejects_object_domain_output_arrays() {
    let target = SourcePackArtifactTarget::Wasm;
    let page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: 2,
        kind: SourcePackHierarchicalLinkGroupKind::Reduce,
        job_index: 92,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: Vec::new(),
        input_group_count: 1,
        input_group_page_count: 1,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: "wasm/linked-output/job-92/src-0-1".into(),
        final_output: true,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };
    let descriptor = GpuSourcePackArtifactDescriptor::hierarchical_linked_output_contract_for_page(
        &page, 0, 0, 1,
    );
    descriptor
        .validate_contract()
        .expect("baseline final linked-output contract is valid");

    let mut document =
        serde_json::to_value(&descriptor).expect("serialize linked-output descriptor");
    for arrays_key in ["output_record_arrays", "record_arrays"] {
        let arrays = document
            .get_mut(arrays_key)
            .and_then(serde_json::Value::as_array_mut)
            .unwrap_or_else(|| panic!("descriptor JSON should include {arrays_key}"));
        arrays.push(serde_json::json!({
            "name": "object_symbol_records"
        }));
    }

    let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document)
        .expect("parse tampered linked-output descriptor JSON");
    assert!(
        parsed
            .output_record_arrays
            .iter()
            .any(|array| array.name == "object_symbol_records"),
        "persisted descriptor should retain the incoherent output array"
    );
    let err = parsed
        .validate_contract()
        .expect_err("final linked-output descriptor must not claim object output arrays");
    assert!(err.contains("output record array \"object_symbol_records\""));
    assert!(err.contains("LinkedOutput"));
    assert!(err.contains("Object"));
}

#[test]
fn persisted_descriptor_rejects_output_only_arrays_as_inputs() {
    let target = SourcePackArtifactTarget::Wasm;
    let page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: 1,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: 91,
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
        output_key: hierarchical_link_partial_output_key(target, 1, 91),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };
    let descriptor =
        GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(&page, 1, 1, 0);
    descriptor
        .validate_contract()
        .expect("baseline partial-link descriptor contract is valid");

    let mut document =
        serde_json::to_value(&descriptor).expect("serialize partial-link descriptor");
    document
        .get_mut("input_record_arrays")
        .and_then(serde_json::Value::as_array_mut)
        .expect("descriptor JSON should include input record arrays")
        .push(serde_json::json!({
            "name": "linked_symbol_records"
        }));
    document
        .get_mut("record_arrays")
        .and_then(serde_json::Value::as_array_mut)
        .expect("descriptor JSON should include combined record arrays")
        .insert(
            descriptor.input_record_arrays.len(),
            serde_json::json!({
                "name": "linked_symbol_records"
            }),
        );

    let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document)
        .expect("parse descriptor JSON with output-only rows in input arrays");
    assert!(
        parsed
            .input_record_arrays
            .iter()
            .any(|array| array.name == "linked_symbol_records"),
        "persisted descriptor should retain the incoherent input array"
    );
    let err = parsed
        .validate_contract()
        .expect_err("descriptor inputs must not claim output-only linked rows");
    assert!(err.contains("output-only LinkedOutput record array"));
    assert!(err.contains("linked_symbol_records"));
}

#[test]
fn persisted_descriptor_record_arrays_reject_mixed_semantic_shapes() {
    let descriptor = GpuSourcePackArtifactDescriptor::codegen_object_contract_for_job(
        SourcePackArtifactTarget::Wasm,
        &SourcePackJob {
            job_index: 44,
            phase: SourcePackJobPhase::Codegen,
            phase_unit_index: 0,
            library_job_index: Some(0),
            library_id: 7,
            first_source_index: 0,
            source_file_count: 1,
            source_bytes: 4,
            source_lines: 1,
            oversized_source_file: false,
            dependency_job_indices: Vec::new(),
        },
        GpuSourcePackDependencyInterfaceSummary::default(),
    );
    descriptor
        .validate_contract()
        .expect("baseline codegen descriptor contract is valid");

    let mut persisted_descriptor = descriptor;
    persisted_descriptor
        .descriptor_records
        .push(GpuSourcePackDescriptorRecord::new(
            "object_symbol_records_retyped_as_sections",
            GpuSourcePackDescriptorRecordDomain::Object,
            GpuSourcePackDescriptorRecordKind::Section,
            GpuSourcePackDescriptorRecordFlow::Output,
            "object_symbol_records",
        ));

    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-descriptor-record-array-shape-test-{}-{suffix}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("create temp descriptor dir");
    let descriptor_path = root.join("codegen-object-descriptor.json");
    std::fs::write(
        &descriptor_path,
        serde_json::to_vec_pretty(&persisted_descriptor).expect("serialize descriptor artifact"),
    )
    .expect("persist descriptor artifact");

    let persisted = serde_json::from_slice::<GpuSourcePackArtifactDescriptor>(
        &std::fs::read(&descriptor_path).expect("read persisted descriptor artifact"),
    )
    .expect("parse persisted descriptor artifact");
    let object_symbol_record = persisted
        .descriptor_records
        .iter()
        .find(|record| record.name == "object_symbols")
        .expect("persisted descriptor should retain object symbol record");
    assert_eq!(
        (
            object_symbol_record.domain,
            object_symbol_record.kind,
            object_symbol_record.flow,
            object_symbol_record.record_array.as_str(),
        ),
        (
            GpuSourcePackDescriptorRecordDomain::Object,
            GpuSourcePackDescriptorRecordKind::Symbol,
            GpuSourcePackDescriptorRecordFlow::Output,
            "object_symbol_records",
        )
    );
    let retyped_record = persisted
        .descriptor_records
        .iter()
        .find(|record| record.name == "object_symbol_records_retyped_as_sections")
        .expect("persisted descriptor should retain the incoherent record");
    assert_eq!(
        (
            retyped_record.domain,
            retyped_record.kind,
            retyped_record.flow,
            retyped_record.record_array.as_str(),
        ),
        (
            GpuSourcePackDescriptorRecordDomain::Object,
            GpuSourcePackDescriptorRecordKind::Section,
            GpuSourcePackDescriptorRecordFlow::Output,
            "object_symbol_records",
        )
    );

    let err = persisted
        .validate_contract()
        .expect_err("one record array must not carry two descriptor shapes");
    assert!(err.contains("record array \"object_symbol_records\""));
    assert!(err.contains("Symbol"));
    assert!(err.contains("Section"));

    std::fs::remove_dir_all(&root).expect("remove descriptor record-array shape test dir");
}

#[test]
fn parsed_descriptor_records_reject_duplicate_semantic_names() {
    let target = SourcePackArtifactTarget::Wasm;
    let page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: 2,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: 92,
        input_interface_count: 0,
        input_interface_page_count: 0,
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
        output_key: "wasm/linked-output/job-92/src-0-1".into(),
        final_output: true,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };
    let descriptor = GpuSourcePackArtifactDescriptor::hierarchical_linked_output_contract_for_page(
        &page, 0, 1, 0,
    );
    descriptor
        .validate_contract()
        .expect("baseline linked-output descriptor contract is valid");

    let mut document =
        serde_json::to_value(&descriptor).expect("serialize linked-output descriptor");
    let descriptor_records = document
        .get_mut("descriptor_records")
        .and_then(serde_json::Value::as_array_mut)
        .expect("descriptor JSON should include descriptor records");
    let linked_output_symbols = descriptor_records
        .iter_mut()
        .find(|record| {
            record.get("name").and_then(serde_json::Value::as_str) == Some("linked_output_symbols")
        })
        .expect("descriptor JSON should include linked output symbols");
    linked_output_symbols["name"] = serde_json::Value::String("object_symbols".into());

    let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document)
        .expect("parse linked-output descriptor with duplicate semantic names");
    assert_eq!(
        parsed
            .descriptor_records
            .iter()
            .filter(|record| record.name == "object_symbols")
            .count(),
        2,
        "parsed descriptor should retain both duplicated semantic records"
    );
    let err = parsed
        .validate_contract()
        .expect_err("descriptor records must have unique semantic names");
    assert!(err.contains("descriptor record name \"object_symbols\""));
    assert!(err.contains("listed more than once"));
}

#[test]
fn persisted_work_queue_ready_frontier_uses_bounded_pages_and_ranges() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-persisted-work-queue-readiness-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let work_item_count = 4;

    store_work_queue_page_with_dependency_writer(
        &store,
        &test_compile_work_queue_page(0),
        work_item_count,
        |_| Ok(()),
    )
    .expect("store independent work item 0");
    store_work_queue_page_with_dependency_writer(
        &store,
        &test_compile_work_queue_page(1),
        work_item_count,
        |_| Ok(()),
    )
    .expect("store independent work item 1");
    store_work_queue_page_with_dependency_writer(
        &store,
        &test_compile_work_queue_page(2),
        work_item_count,
        |writer| writer.push(0),
    )
    .expect("store item 2 with paged dependency on 0");
    store_work_queue_page_with_dependency_writer(
        &store,
        &test_compile_work_queue_page(3),
        work_item_count,
        |writer| writer.push_range(0, 2),
    )
    .expect("store item 3 with ranged dependencies on 0..2");

    let item_0 = store
        .load_work_queue_page_for_target(target, 0)
        .expect("load item 0");
    let item_1 = store
        .load_work_queue_page_for_target(target, 1)
        .expect("load item 1");
    let item_2 = store
        .load_work_queue_page_for_target(target, 2)
        .expect("load item 2");
    let item_3 = store
        .load_work_queue_page_for_target(target, 3)
        .expect("load item 3");
    assert_eq!(item_0.dependent_item_count, 1);
    assert_eq!(item_0.dependent_page_count, 1);
    assert_eq!(
        store
            .load_work_queue_dependents_page_for_target(target, 0, 0)
            .expect("load item 0 paged dependents")
            .dependent_item_indices,
        vec![2]
    );
    assert_eq!(
        item_0.dependent_item_ranges,
        vec![SourcePackJobIndexRange {
            first_job_index: 3,
            job_count: 1,
        }]
    );
    assert_eq!(
        item_1.dependent_item_ranges,
        vec![SourcePackJobIndexRange {
            first_job_index: 3,
            job_count: 1,
        }]
    );
    assert_eq!(item_2.dependency_item_count, 1);
    assert_eq!(item_2.dependency_page_count, 1);
    assert_eq!(
        store
            .load_work_queue_dependencies_page_for_target(target, 2, 0)
            .expect("load item 2 paged dependencies")
            .dependency_item_indices,
        vec![0]
    );
    assert_eq!(
        item_3.dependency_item_ranges,
        vec![SourcePackJobIndexRange {
            first_job_index: 0,
            job_count: 2,
        }]
    );

    let queue = SourcePackWorkQueueIndex {
        version: SOURCE_PACK_WORK_QUEUE_INDEX_VERSION,
        target,
        work_item_count,
        artifact_item_count: work_item_count,
        final_item_index: work_item_count - 1,
        final_job_index: work_item_count - 1,
    };
    store_work_queue_compact_index(&store, &queue).expect("store compact work queue index");
    let first_progress_chunk =
        store_initial_progress_chunk(&store, &queue, 2, 1).expect("store first progress chunk");
    assert!(!first_progress_chunk.complete);
    assert_eq!(first_progress_chunk.next_page_index, 1);
    assert_eq!(first_progress_chunk.ready_item_count, 2);
    assert_eq!(first_progress_chunk.first_ready_item_index, Some(0));
    let final_progress_chunk =
        store_initial_progress_chunk(&store, &queue, 2, 1).expect("store second progress chunk");
    assert!(final_progress_chunk.complete);
    assert_eq!(final_progress_chunk.next_page_index, 2);
    assert_eq!(final_progress_chunk.ready_item_count, 2);

    let page_0 = store
        .load_work_queue_progress_page_for_target(target, 0)
        .expect("load first progress page");
    let page_1 = store
        .load_work_queue_progress_page_for_target(target, 1)
        .expect("load second progress page");
    assert_eq!(page_0.ready_item_indices, vec![0, 1]);
    assert_eq!(remaining_dependent_counts(&page_0), vec![(0, 2), (1, 1)]);
    assert_eq!(page_1.ready_item_indices, Vec::<usize>::new());
    assert_eq!(remaining_dependency_counts(&page_1), vec![(2, 1), (3, 2)]);

    let initial = work_queue_progress_snapshot_at(&root, target, 8, Some(0))
        .expect("load initial work queue snapshot");
    assert_eq!(initial.ready_item_indices, vec![0, 1]);

    let claim_0 = claim_ready_work_queue_item(&root, target, "worker-a", Some(10), 8, Some(0))
        .expect("claim first ready work item");
    assert_eq!(claim_0.claimed_item_index, Some(0));
    assert_eq!(claim_0.progress.ready_item_indices, vec![1]);

    let complete_0 = complete_claimed_work_queue_item(&root, 0, target, "worker-a", 8, Some(1))
        .expect("complete first ready work item");
    assert_eq!(complete_0.newly_ready_item_count, 1);
    assert_eq!(complete_0.progress.completed_item_count, 1);
    assert_eq!(complete_0.progress.ready_item_indices, vec![1, 2]);
    let page_1_after_item_0 = store
        .load_work_queue_progress_page_for_target(target, 1)
        .expect("load second progress page after item 0 completion");
    assert_eq!(page_1_after_item_0.ready_item_indices, vec![2]);
    assert_eq!(
        remaining_dependency_counts(&page_1_after_item_0),
        vec![(3, 1)]
    );

    let claim_1 = claim_ready_work_queue_item(&root, target, "worker-b", Some(20), 8, Some(2))
        .expect("claim second independent work item");
    assert_eq!(claim_1.claimed_item_index, Some(1));
    let complete_1 = complete_claimed_work_queue_item(&root, 1, target, "worker-b", 8, Some(3))
        .expect("complete second independent work item");
    assert_eq!(complete_1.newly_ready_item_count, 1);
    assert_eq!(complete_1.progress.completed_item_count, 2);
    assert_eq!(complete_1.progress.ready_item_indices, vec![2, 3]);
    let page_1_after_item_1 = store
        .load_work_queue_progress_page_for_target(target, 1)
        .expect("load second progress page after item 1 completion");
    assert_eq!(page_1_after_item_1.ready_item_indices, vec![2, 3]);
    assert_eq!(
        remaining_dependency_counts(&page_1_after_item_1),
        Vec::<(usize, usize)>::new()
    );

    std::fs::remove_dir_all(&root).expect("remove temp persisted work queue readiness dir");
}

#[test]
fn artifact_build_separates_target_manifests() {
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
                library_id: 10,
                paths: vec![core_path.clone()],
                dependency_library_ids: Vec::new(),
            },
            ExplicitSourceLibraryPaths {
                library_id: 20,
                paths: vec![app_path.clone()],
                dependency_library_ids: vec![10],
            },
        ]
    };

    let mut wasm_executor = RecordingSourcePackByteArtifactExecutor::default();
    prepare_library_paths_for_target(
        libraries(),
        &artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Wasm,
    )
    .expect("prepare wasm target filesystem artifact build");
    let wasm = execute_artifact_manifest_build_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        &mut wasm_executor,
    )
    .expect("execute wasm target filesystem artifact build");
    let mut x86_executor = RecordingSourcePackByteArtifactExecutor::default();
    prepare_library_paths_for_target(
        libraries(),
        &artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::X86_64,
    )
    .expect("prepare x86 target filesystem artifact build");
    let x86 = execute_artifact_manifest_build_for_target(
        &artifact_root,
        SourcePackArtifactTarget::X86_64,
        &mut x86_executor,
    )
    .expect("execute x86 target filesystem artifact build");

    assert!(
        wasm.linked_output_key.starts_with("wasm/linked-output/"),
        "wasm linked output should be target-qualified: {}",
        wasm.linked_output_key
    );
    assert!(
        x86.linked_output_key.starts_with("x86_64/linked-output/"),
        "x86 linked output should be target-qualified: {}",
        x86.linked_output_key
    );
    assert_ne!(wasm.linked_output_key, x86.linked_output_key);
    assert!(wasm.linked_output_path.exists());
    assert!(x86.linked_output_path.exists());
    assert_ne!(wasm.linked_output_path, x86.linked_output_path);

    let store = FilesystemArtifactStore::new(&artifact_root);
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
        Some(wasm.linked_output_key.as_str())
    );
    assert_eq!(
        store
            .load_build_state_for_target(SourcePackArtifactTarget::X86_64)
            .expect("load x86 build state")
            .linked_output_key
            .as_deref(),
        Some(x86.linked_output_key.as_str())
    );
    std::fs::remove_dir_all(&root).expect("remove temp target artifact dir");
}

#[test]
fn artifact_manifest_build_stops_at_batch_limit() {
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
    let manifest =
        ExplicitSourcePackPathManifest::from_libraries(vec![ExplicitSourceLibraryPaths {
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

    let store = FilesystemArtifactStore::new(&artifact_root);
    store
        .store_build_artifact_manifest(&artifact_manifest)
        .expect("store artifact manifest");
    let path_build_manifest =
        source_pack_path_build_manifest(&manifest, limits, batch_limits, artifact_manifest);
    store
        .store_path_build_manifest(&path_build_manifest)
        .expect("store path build manifest");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let err = execute_artifact_manifest_build_for_target(
        &artifact_root,
        SourcePackArtifactTarget::Generic,
        &mut executor,
    )
    .expect_err("full manifest build should stop at the bounded batch limit");
    match &err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0058");
            assert_eq!(diagnostic.message, "source-pack progress state invalid");
        }
        other => panic!("expected source-pack progress diagnostic, got {other:?}"),
    }
    assert!(
        err.to_string()
            .contains("did not complete within 64 bounded batches"),
        "unexpected full-build limit error: {err}"
    );
    let state = store
        .load_build_state_for_target(SourcePackArtifactTarget::Generic)
        .expect("load resumable state after bounded full build");
    assert_eq!(
        state.completed_batch_count,
        SOURCE_PACK_ARTIFACT_MANIFEST_FULL_BUILD_DEFAULT_BATCH_LIMIT
    );
    assert_eq!(state.linked_output_key, None);

    std::fs::remove_dir_all(&root).expect("remove temp filesystem manifest build limit dir");
}

#[test]
fn artifact_manifest_ready_batches_reject_missing_completed_artifact() {
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

    let manifest =
        ExplicitSourcePackPathManifest::from_libraries(vec![ExplicitSourceLibraryPaths {
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
    let first_ready_batch_index = artifact_manifest
        .batch_dependencies
        .ready_batch_indices_limited(&[], Some(1))
        .into_iter()
        .next()
        .expect("artifact manifest should have an initially ready batch");
    let first_ready_batch = artifact_manifest
        .job_batches
        .batches
        .iter()
        .find(|batch| batch.batch_index == first_ready_batch_index)
        .expect("initially ready batch should exist");
    let first_ready_job_index = first_ready_batch
        .job_indices
        .first()
        .copied()
        .expect("initially ready batch should contain jobs");
    let missing_output_key = artifact_manifest.job_artifacts.jobs[first_ready_job_index].outputs[0]
        .key
        .clone();
    let store = FilesystemArtifactStore::new(&artifact_root);
    store
        .store_build_artifact_manifest(&artifact_manifest)
        .expect("store artifact manifest");
    let path_build_manifest =
        source_pack_path_build_manifest(&manifest, limits, batch_limits, artifact_manifest);
    store
        .store_path_build_manifest(&path_build_manifest)
        .expect("store path build manifest");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let first = execute_artifact_manifest_batch_for_target(
        artifact_root.clone(),
        first_ready_batch_index,
        SourcePackArtifactTarget::Generic,
        &mut executor,
    )
    .expect("execute first persisted batch");
    assert_eq!(first.batch_index, first_ready_batch_index);
    let missing_output_path = store
        .path_for_key(&missing_output_key)
        .expect("completed output path");
    assert!(missing_output_path.exists());
    std::fs::remove_file(&missing_output_path).expect("remove completed output artifact");

    let err = artifact_manifest_ready_batch_indices(artifact_root.clone())
        .expect_err("missing completed artifact should reject ready-state query");
    match &err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0058");
            assert_eq!(diagnostic.message, "source-pack progress state invalid");
        }
        other => panic!("expected source-pack progress diagnostic, got {other:?}"),
    }
    let message = err.to_string();
    std::fs::remove_dir_all(&root).expect("remove temp missing-completed-artifact dir");

    assert!(
        message.contains(&format!("marks batch {first_ready_batch_index} complete"))
            && message.contains(&missing_output_key),
        "unexpected missing completed artifact error: {message}"
    );
}

#[test]
fn artifact_manifest_claims_ready_batches_for_workers() {
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

    let limits = CodegenUnitLimits {
        max_source_bytes: 4,
        max_source_files: 8,
    };
    let batch_limits = SourcePackJobBatchLimits {
        max_jobs_per_batch: 1,
        max_source_bytes_per_batch: 4,
        max_source_files_per_batch: 1,
    };
    let store = FilesystemArtifactStore::new(&artifact_root);
    prepare_library_paths_for_target(
        vec![
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
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
    .expect("prepare filesystem artifact work queue");
    let initial_state = store
        .load_or_init_build_state_for_target(SourcePackArtifactTarget::Generic)
        .expect("load initial claim state");

    let first_claim = claim_ready_artifact_manifest_batch(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-a",
        None,
        Some(0),
    )
    .expect("claim first ready batch");
    let first_batch_index = first_claim
        .claimed_batch_index
        .expect("first worker should claim a ready batch");
    let expected_claimed_count_after_first_claim = initial_state.claimed_batch_count + 1;
    assert_eq!(
        first_claim.completed_batch_count,
        initial_state.completed_batch_count()
    );
    assert_eq!(
        first_claim.claimed_batch_count,
        expected_claimed_count_after_first_claim
    );

    let blocked_claim = claim_ready_artifact_manifest_batch(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-b",
        None,
        Some(0),
    )
    .expect("second worker sees no unclaimed ready batch");
    assert_eq!(blocked_claim.claimed_batch_index, None);
    assert_eq!(
        blocked_claim.completed_batch_count,
        first_claim.completed_batch_count
    );
    assert_eq!(
        blocked_claim.claimed_batch_count,
        expected_claimed_count_after_first_claim
    );

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let unclaimed_err = execute_artifact_manifest_batch_for_target(
        artifact_root.clone(),
        first_batch_index,
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
    let wrong_worker_err = execute_claimed_artifact_manifest_batch(
        artifact_root.clone(),
        first_batch_index,
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
    let first_batch = execute_claimed_artifact_manifest_batch(
        artifact_root.clone(),
        first_batch_index,
        SourcePackArtifactTarget::Generic,
        "worker-a",
        Some(0),
        &mut executor,
    )
    .expect("execute claimed first batch");
    assert_eq!(first_batch.batch_index, first_batch_index);
    let state_after_first = store
        .load_build_state_for_target(SourcePackArtifactTarget::Generic)
        .expect("load state after first claimed batch");
    let mut completed_batches = vec![first_batch_index];
    assert_eq!(
        state_after_first.completed_batch_count(),
        initial_state.completed_batch_count() + completed_batches.len()
    );
    assert_eq!(
        state_after_first.claimed_batch_count,
        initial_state.claimed_batch_count
    );

    let second_claim = claim_ready_artifact_manifest_batch(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-b",
        Some(10),
        Some(0),
    )
    .expect("claim second ready batch");
    let second_batch_index = second_claim
        .claimed_batch_index
        .expect("second worker should claim another ready batch");
    assert_ne!(second_batch_index, first_batch_index);
    assert_eq!(
        second_claim.completed_batch_count,
        state_after_first.completed_batch_count()
    );
    assert_eq!(
        second_claim.claimed_batch_count,
        initial_state.claimed_batch_count + 1
    );

    let replacement_claim = claim_ready_artifact_manifest_batch(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-c",
        Some(30),
        Some(11),
    )
    .expect("replace expired second-batch claim");
    assert_eq!(
        replacement_claim.claimed_batch_index,
        Some(second_batch_index)
    );
    let state_after_replacement = store
        .load_build_state_for_target(SourcePackArtifactTarget::Generic)
        .expect("load state after replacement claim");
    assert_eq!(
        state_after_replacement.completed_batch_count(),
        state_after_first.completed_batch_count()
    );
    assert_eq!(
        state_after_replacement.claimed_batch_count,
        second_claim.claimed_batch_count
    );

    let expired_owner_err = execute_claimed_artifact_manifest_batch(
        artifact_root.clone(),
        second_batch_index,
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

    let second_batch = execute_claimed_artifact_manifest_batch(
        artifact_root.clone(),
        second_batch_index,
        SourcePackArtifactTarget::Generic,
        "worker-c",
        Some(11),
        &mut executor,
    )
    .expect("execute replacement-claimed second batch");
    assert_eq!(second_batch.batch_index, second_batch_index);
    let state_after_second = store
        .load_build_state_for_target(SourcePackArtifactTarget::Generic)
        .expect("load state after second claimed batch");
    completed_batches.push(second_batch_index);
    assert_eq!(
        state_after_second.completed_batch_count(),
        initial_state.completed_batch_count() + completed_batches.len()
    );
    assert_eq!(
        state_after_second.claimed_batch_count,
        initial_state.claimed_batch_count
    );

    std::fs::remove_dir_all(&root).expect("remove temp filesystem claim dir");
}

#[test]
fn artifact_manifest_claim_respects_state_lock() {
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

    let manifest =
        ExplicitSourcePackPathManifest::from_libraries(vec![ExplicitSourceLibraryPaths {
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
    let store = FilesystemArtifactStore::new(&artifact_root);
    store
        .store_build_artifact_manifest(&artifact_manifest)
        .expect("store artifact manifest");
    let path_build_manifest =
        source_pack_path_build_manifest(&manifest, limits, batch_limits, artifact_manifest);
    store
        .store_path_build_manifest(&path_build_manifest)
        .expect("store path build manifest");

    let lock_path = store.build_state_lock_path_for_target(SourcePackArtifactTarget::Generic);
    std::fs::write(&lock_path, b"held").expect("create held state lock");
    let err = claim_ready_artifact_manifest_batch(
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
        .load_or_init_build_state_for_target(SourcePackArtifactTarget::Generic)
        .expect("load state after rejected claim");
    assert_eq!(state, SourcePackBuildState::new());
    std::fs::remove_file(&lock_path).expect("remove held state lock");

    let claim = claim_ready_artifact_manifest_batch(
        artifact_root.clone(),
        SourcePackArtifactTarget::Generic,
        "worker-a",
        None,
        Some(0),
    )
    .expect("claim after releasing state lock");
    assert!(claim.claimed_batch_index.is_some());
    assert!(!lock_path.exists());
    let state_after_claim = store
        .load_build_state_for_target(SourcePackArtifactTarget::Generic)
        .expect("load state after successful claim");
    assert_eq!(state_after_claim.completed_batch_count(), 0);
    assert_eq!(state_after_claim.claimed_batch_count, 1);

    std::fs::remove_dir_all(&root).expect("remove temp filesystem state-lock dir");
}

#[test]
fn artifact_manifest_batch_rejects_changed_source_metadata() {
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

    let manifest =
        ExplicitSourcePackPathManifest::from_libraries(vec![ExplicitSourceLibraryPaths {
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
    let store = FilesystemArtifactStore::new(&artifact_root);
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
    let err = execute_artifact_manifest_batch_for_target(
        artifact_root.clone(),
        0,
        SourcePackArtifactTarget::Generic,
        &mut executor,
    )
    .expect_err("changed source metadata should reject stale persisted manifest batch");
    std::fs::remove_dir_all(&root).expect("remove temp changed-source dir");

    assert!(
        err.to_string()
            .contains("changed since manifest was planned"),
        "unexpected changed-source batch error: {err}"
    );
}

#[test]
fn source_pack_filesystem_artifact_store_rejects_non_relative_keys() {
    let store = FilesystemArtifactStore::new(std::env::temp_dir());

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

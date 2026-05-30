use super::*;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct WorkQueueProgressPageModel {
    ready: std::collections::BTreeSet<usize>,
    completed: std::collections::BTreeSet<usize>,
    remaining_dependencies: std::collections::BTreeMap<usize, usize>,
    claims: std::collections::BTreeMap<usize, (String, Option<u128>)>,
}

impl WorkQueueProgressPageModel {
    fn prune_claims(&mut self, now_unix_nanos: Option<u128>) {
        let completed = &self.completed;
        self.claims.retain(|item_index, (_, expires)| {
            !completed.contains(item_index)
                && !matches!((now_unix_nanos, *expires), (Some(now), Some(expires)) if expires <= now)
        });
    }

    fn claim(
        &mut self,
        item_index: usize,
        worker_id: &str,
        lease_expires_unix_nanos: Option<u128>,
        now_unix_nanos: Option<u128>,
    ) {
        self.prune_claims(now_unix_nanos);
        assert!(self.ready.contains(&item_index));
        assert!(!self.completed.contains(&item_index));
        self.claims.insert(
            item_index,
            (worker_id.to_string(), lease_expires_unix_nanos),
        );
    }

    fn complete(&mut self, item_index: usize, worker_id: &str, now_unix_nanos: Option<u128>) {
        self.prune_claims(now_unix_nanos);
        assert_eq!(
            self.claims.get(&item_index).map(|claim| claim.0.as_str()),
            Some(worker_id)
        );
        self.completed.insert(item_index);
        self.ready.remove(&item_index);
        self.remaining_dependencies.remove(&item_index);
        self.claims.remove(&item_index);
    }

    fn record_dependency_completed(&mut self, item_index: usize) {
        if self.completed.contains(&item_index) || self.ready.contains(&item_index) {
            return;
        }
        let remaining = self
            .remaining_dependencies
            .get_mut(&item_index)
            .expect("blocked model item should have dependency count");
        if *remaining > 1 {
            *remaining -= 1;
            return;
        }
        self.remaining_dependencies.remove(&item_index);
        self.ready.insert(item_index);
    }
}

fn assert_progress_page_matches_model(
    page: &SourcePackWorkQueueProgressPage,
    model: &WorkQueueProgressPageModel,
) {
    let ready = page
        .ready_item_indices
        .iter()
        .copied()
        .collect::<std::collections::BTreeSet<_>>();
    let completed = page
        .completed_item_indices
        .iter()
        .copied()
        .collect::<std::collections::BTreeSet<_>>();
    let remaining_dependencies = page
        .remaining_dependency_counts
        .iter()
        .map(|remaining| (remaining.item_index, remaining.remaining_dependency_count))
        .collect::<std::collections::BTreeMap<_, _>>();
    let claims = page
        .claimed_items
        .iter()
        .map(|claim| {
            (
                claim.item_index,
                (claim.worker_id.clone(), claim.lease_expires_unix_nanos),
            )
        })
        .collect::<std::collections::BTreeMap<_, _>>();

    assert_eq!(ready, model.ready, "ready item set should match model");
    assert_eq!(
        completed, model.completed,
        "completed item set should match model"
    );
    assert_eq!(
        remaining_dependencies, model.remaining_dependencies,
        "blocked dependency counters should match model"
    );
    assert_eq!(claims, model.claims, "active claims should match model");
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

    let half_plus_one = limits.max_source_bytes / 2 + 1;
    let first = "x".repeat(half_plus_one);
    let second = "y".repeat(half_plus_one);
    let oversized_total_err = validate_in_memory_source_pack_fits_default_codegen_unit(
        "test in-memory source pack",
        &[first.as_str(), second.as_str()],
    )
    .expect_err("total in-memory source bytes above the default codegen unit should be rejected");
    assert!(
        oversized_total_err
            .to_string()
            .contains("total in-memory source bytes"),
        "unexpected oversized-total error: {oversized_total_err}"
    );
    assert!(
        oversized_total_err
            .to_string()
            .contains("persisted source-pack descriptor work queues"),
        "oversized-total error should direct callers to persisted work queues: {oversized_total_err}"
    );
}

#[test]
fn source_pack_work_queue_progress_page_transitions_match_reference_model() {
    let mut page = SourcePackWorkQueueProgressPage {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
        target: SourcePackArtifactTarget::Generic,
        page_index: 0,
        first_item_index: 0,
        item_count: 3,
        artifact_item_indices: Vec::new(),
        remaining_dependency_counts: vec![
            SourcePackWorkQueueRemainingDependencyCount {
                item_index: 1,
                remaining_dependency_count: 1,
            },
            SourcePackWorkQueueRemainingDependencyCount {
                item_index: 2,
                remaining_dependency_count: 2,
            },
        ],
        remaining_dependent_counts: Vec::new(),
        completed_item_indices: Vec::new(),
        ready_item_indices: vec![0],
        ready_artifact_item_indices: Vec::new(),
        claimed_items: Vec::new(),
    };
    let mut model = WorkQueueProgressPageModel {
        ready: [0].into_iter().collect(),
        completed: std::collections::BTreeSet::new(),
        remaining_dependencies: [(1, 1), (2, 2)].into_iter().collect(),
        claims: std::collections::BTreeMap::new(),
    };
    assert_progress_page_matches_model(&page, &model);

    progress_page_record_item_claim(&mut page, 0, "worker-a", Some(10), Some(0))
        .expect("ready item should be claimable");
    model.claim(0, "worker-a", Some(10), Some(0));
    assert_progress_page_matches_model(&page, &model);

    progress_page_prune_inactive_claims(&mut page, Some(10));
    model.prune_claims(Some(10));
    assert_progress_page_matches_model(&page, &model);

    progress_page_record_item_claim(&mut page, 0, "worker-a", Some(20), Some(11))
        .expect("expired item should be claimable again");
    model.claim(0, "worker-a", Some(20), Some(11));
    assert_progress_page_matches_model(&page, &model);

    assert!(
        progress_page_record_item_completed(&mut page, 0, "worker-a", Some(11))
            .expect("claimed item should complete")
    );
    model.complete(0, "worker-a", Some(11));
    assert_progress_page_matches_model(&page, &model);

    assert_eq!(
        progress_page_record_dependency_completed(&mut page, 1)
            .expect("first blocked item should become ready"),
        (true, true)
    );
    model.record_dependency_completed(1);
    assert_progress_page_matches_model(&page, &model);

    assert_eq!(
        progress_page_record_dependency_completed(&mut page, 2)
            .expect("first dependency completion should decrement only"),
        (true, false)
    );
    model.record_dependency_completed(2);
    assert_progress_page_matches_model(&page, &model);

    assert_eq!(
        progress_page_record_dependency_completed(&mut page, 2)
            .expect("second dependency completion should ready item"),
        (true, true)
    );
    model.record_dependency_completed(2);
    assert_progress_page_matches_model(&page, &model);
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
fn hierarchical_link_execution_store_spills_inline_inputs_to_bounded_pages() {
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
        "laniusc-hlink-bounded-pages-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let link_job_index = 200;
    let page_size = SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE;
    let input_count = page_size + 1;
    assert_eq!(
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE,
        page_size
    );

    let interface_refs = (0..input_count)
        .map(|index| {
            artifact_ref(
                target,
                SourcePackArtifactKind::LibraryInterface,
                index,
                index,
            )
        })
        .collect::<Vec<_>>();
    let object_refs = (0..input_count)
        .map(|index| {
            artifact_ref(
                target,
                SourcePackArtifactKind::CodegenObject,
                1000 + index,
                100 + index,
            )
        })
        .collect::<Vec<_>>();

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: link_job_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: interface_refs.clone(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: object_refs.clone(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
            output_key: hierarchical_link_partial_output_key(target, 0, link_job_index),
            final_output: false,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        })
        .expect("store hierarchical link execution descriptor");

    let persisted_page = store
        .load_hierarchical_link_execution_page_for_target(target, 0)
        .expect("load persisted hierarchical link execution descriptor");
    assert_eq!(persisted_page.input_interface_count, input_count);
    assert_eq!(persisted_page.input_interface_page_count, 2);
    assert!(persisted_page.input_interfaces.is_empty());
    assert_eq!(persisted_page.input_object_count, input_count);
    assert_eq!(persisted_page.input_object_page_count, 2);
    assert!(persisted_page.input_objects.is_empty());

    let first_interface_page = store
        .load_hierarchical_link_execution_interface_page_for_target(target, 0, 0)
        .expect("load first bounded interface page");
    let second_interface_page = store
        .load_hierarchical_link_execution_interface_page_for_target(target, 0, 1)
        .expect("load second bounded interface page");
    assert_eq!(
        first_interface_page.input_count,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE
    );
    assert_eq!(second_interface_page.first_input_position, page_size);
    assert_eq!(second_interface_page.input_count, 1);
    assert_eq!(
        first_interface_page.input_interfaces,
        interface_refs[..page_size].to_vec()
    );
    assert_eq!(
        second_interface_page.input_interfaces,
        interface_refs[page_size..].to_vec()
    );

    let first_object_page = store
        .load_hierarchical_link_execution_object_page_for_target(target, 0, 0)
        .expect("load first bounded object page");
    let second_object_page = store
        .load_hierarchical_link_execution_object_page_for_target(target, 0, 1)
        .expect("load second bounded object page");
    assert_eq!(
        first_object_page.input_count,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE
    );
    assert_eq!(second_object_page.first_input_position, page_size);
    assert_eq!(second_object_page.input_count, 1);
    assert_eq!(
        first_object_page.input_objects,
        object_refs[..page_size].to_vec()
    );
    assert_eq!(
        second_object_page.input_objects,
        object_refs[page_size..].to_vec()
    );

    std::fs::remove_dir_all(&root).expect("remove bounded hlink page test dir");
}

#[test]
fn hierarchical_link_execution_descriptor_summary_persists_and_rejects_impossible_link_records() {
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
        "laniusc-hlink-descriptor-summary-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let link_job_index = 50;
    let descriptor_summary = SourcePackLinkDescriptorSummary {
        interface_symbol_count: 2,
        object_section_count: 1,
        object_symbol_count: 3,
        unresolved_symbol_count: 5,
        relocation_count: 4,
        export_symbol_count: 1,
        ..SourcePackLinkDescriptorSummary::default()
    }
    .with_record_contracts_from_counts();
    let interface_ref = artifact_ref(target, SourcePackArtifactKind::LibraryInterface, 0, 1);
    let object_ref = artifact_ref(target, SourcePackArtifactKind::CodegenObject, 1, 2);

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: link_job_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![interface_ref],
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: vec![object_ref],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 10,
            source_file_count: 1,
            source_line_count: 1,
            output_key: hierarchical_link_partial_output_key(target, 0, link_job_index),
            final_output: false,
            descriptor_summary: descriptor_summary.clone(),
        })
        .expect("store descriptor summary with bounded link inputs");

    let persisted_page = store
        .load_hierarchical_link_execution_page_for_target(target, 0)
        .expect("load persisted descriptor summary");
    assert_eq!(persisted_page.descriptor_summary, descriptor_summary);
    assert_eq!(persisted_page.input_interface_count, 1);
    assert_eq!(persisted_page.input_object_count, 1);
    assert!(
        persisted_page.input_interfaces.is_empty() && persisted_page.input_objects.is_empty(),
        "stored page should keep descriptor counts without retaining inline artifact refs"
    );

    let invalid_group_index = 1;
    let invalid_interface_ref =
        artifact_ref(target, SourcePackArtifactKind::LibraryInterface, 2, 3);
    let invalid_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: invalid_group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: link_job_index + 1,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: vec![invalid_interface_ref],
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: Vec::new(),
        input_group_count: 0,
        input_group_page_count: 0,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 10,
        source_file_count: 1,
        source_line_count: 1,
        output_key: hierarchical_link_partial_output_key(
            target,
            invalid_group_index,
            link_job_index + 1,
        ),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            relocation_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        }
        .with_record_contracts_from_counts(),
    };
    let invalid_path =
        store.hierarchical_link_execution_page_path_for_target(target, invalid_group_index);
    std::fs::create_dir_all(invalid_path.parent().expect("link page parent"))
        .expect("create invalid persisted descriptor directory");
    std::fs::write(
        &invalid_path,
        serde_json::to_vec_pretty(&invalid_page).expect("serialize invalid descriptor page"),
    )
    .expect("write invalid persisted descriptor page");
    let err = store
        .load_hierarchical_link_execution_page_for_target(target, invalid_group_index)
        .expect_err("readback should reject impossible relocation descriptors");
    assert!(
        err.to_string()
            .contains("relocation descriptors without object or partial-link inputs"),
        "unexpected descriptor validation error: {err}"
    );

    let invalid_unresolved_group_index = 2;
    let invalid_unresolved_ref =
        artifact_ref(target, SourcePackArtifactKind::LibraryInterface, 3, 4);
    let invalid_unresolved_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: invalid_unresolved_group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: link_job_index + 2,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: vec![invalid_unresolved_ref],
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: Vec::new(),
        input_group_count: 0,
        input_group_page_count: 0,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 10,
        source_file_count: 1,
        source_line_count: 1,
        output_key: hierarchical_link_partial_output_key(
            target,
            invalid_unresolved_group_index,
            link_job_index + 2,
        ),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            unresolved_symbol_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        }
        .with_record_contracts_from_counts(),
    };
    let invalid_unresolved_path = store
        .hierarchical_link_execution_page_path_for_target(target, invalid_unresolved_group_index);
    std::fs::create_dir_all(invalid_unresolved_path.parent().expect("link page parent"))
        .expect("create invalid unresolved-symbol descriptor directory");
    std::fs::write(
        &invalid_unresolved_path,
        serde_json::to_vec_pretty(&invalid_unresolved_page)
            .expect("serialize invalid unresolved-symbol descriptor page"),
    )
    .expect("write invalid unresolved-symbol descriptor page");
    let err = store
        .load_hierarchical_link_execution_page_for_target(target, invalid_unresolved_group_index)
        .expect_err("readback should reject impossible unresolved-symbol descriptors");
    assert!(
        err.to_string()
            .contains("unresolved symbol descriptors without object or partial-link inputs"),
        "unexpected descriptor validation error: {err}"
    );

    let final_group_index = 3;
    let final_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: final_group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: link_job_index + 3,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: vec![artifact_ref(
            target,
            SourcePackArtifactKind::LibraryInterface,
            4,
            5,
        )],
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: vec![artifact_ref(
            target,
            SourcePackArtifactKind::CodegenObject,
            5,
            6,
        )],
        input_group_count: 0,
        input_group_page_count: 0,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 10,
        source_file_count: 1,
        source_line_count: 1,
        output_key: source_pack_artifact_key_for_output(
            target,
            SourcePackArtifactKind::LinkedOutput,
            u32::MAX,
            link_job_index,
            0,
            1,
        ),
        final_output: true,
        descriptor_summary: SourcePackLinkDescriptorSummary {
            unresolved_symbol_count: 1,
            ..SourcePackLinkDescriptorSummary::default()
        }
        .with_record_contracts_from_counts(),
    };
    let final_path =
        store.hierarchical_link_execution_page_path_for_target(target, final_group_index);
    std::fs::create_dir_all(final_path.parent().expect("link page parent"))
        .expect("create invalid final descriptor directory");
    std::fs::write(
        &final_path,
        serde_json::to_vec_pretty(&final_page)
            .expect("serialize invalid final unresolved-symbol descriptor page"),
    )
    .expect("write invalid final unresolved-symbol descriptor page");
    let err = store
        .load_hierarchical_link_execution_page_for_target(target, final_group_index)
        .expect_err("final readback should reject unresolved-symbol descriptors");
    assert!(
        err.to_string()
            .contains("final linked output records 1 unresolved symbol descriptors"),
        "unexpected descriptor validation error: {err}"
    );

    std::fs::remove_dir_all(&root).expect("remove descriptor summary test dir");
}

#[test]
fn persisted_final_output_records_reject_non_linked_output_keys() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-final-output-key-kind-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let partial_key = hierarchical_link_partial_output_key(target, 0, 2);
    let linked_key = source_pack_artifact_key_for_output(
        target,
        SourcePackArtifactKind::LinkedOutput,
        0,
        2,
        0,
        1,
    );

    let artifact_ref_index_path = store.build_artifact_ref_index_path_for_target(target);
    std::fs::create_dir_all(
        artifact_ref_index_path
            .parent()
            .expect("artifact index parent"),
    )
    .expect("create artifact-ref index directory");
    let invalid_artifact_ref_index = SourcePackBuildArtifactRefIndex {
        version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
        target,
        artifact_count: 3,
        interface_artifact_count: 1,
        object_artifact_count: 1,
        final_output_artifact_index: 2,
        final_output_key: partial_key.clone(),
        total_source_file_count: 1,
        total_source_byte_count: 1,
        total_source_line_count: 1,
    };
    std::fs::write(
        &artifact_ref_index_path,
        serde_json::to_vec_pretty(&invalid_artifact_ref_index)
            .expect("serialize invalid artifact-ref index"),
    )
    .expect("write invalid artifact-ref index");
    let err = store
        .load_build_artifact_ref_index_for_target(target)
        .expect_err("artifact-ref index final output must use a linked-output key");
    assert!(
        err.to_string()
            .contains("does not identify a LinkedOutput artifact"),
        "unexpected artifact-ref index key-kind error: {err}"
    );

    let mut valid_artifact_ref_index = invalid_artifact_ref_index;
    valid_artifact_ref_index.final_output_key = linked_key.clone();
    std::fs::write(
        &artifact_ref_index_path,
        serde_json::to_vec_pretty(&valid_artifact_ref_index)
            .expect("serialize valid artifact-ref index"),
    )
    .expect("write valid artifact-ref index");
    assert_eq!(
        store
            .load_build_artifact_ref_index_for_target(target)
            .expect("linked-output final artifact-ref index should load")
            .final_output_key,
        linked_key
    );

    let invalid_ref_page = SourcePackBuildArtifactRefPage {
        version: SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION,
        target,
        artifact_index: 0,
        artifact_ref: SourcePackArtifactRef {
            artifact_index: 0,
            key: source_pack_artifact_key_for_output(
                target,
                SourcePackArtifactKind::CodegenObject,
                0,
                0,
                0,
                1,
            ),
            producing_job_index: 0,
            kind: SourcePackArtifactKind::LibraryInterface,
        },
        source_bytes: 1,
        source_file_count: 1,
        source_lines: 1,
    };
    let artifact_ref_page_path = store.build_artifact_ref_page_path_for_target(target, 0);
    std::fs::create_dir_all(
        artifact_ref_page_path
            .parent()
            .expect("artifact page parent"),
    )
    .expect("create artifact-ref page directory");
    std::fs::write(
        &artifact_ref_page_path,
        serde_json::to_vec_pretty(&invalid_ref_page).expect("serialize invalid artifact-ref page"),
    )
    .expect("write invalid artifact-ref page");
    let err = store
        .load_build_artifact_ref_page_for_target(target, 0, 3)
        .expect_err("artifact-ref page key must match its recorded artifact kind");
    assert!(
        err.to_string()
            .contains("does not identify a LibraryInterface artifact"),
        "unexpected artifact-ref page key-kind error: {err}"
    );

    let link_execution_index_path = store.hierarchical_link_execution_index_path_for_target(target);
    std::fs::create_dir_all(
        link_execution_index_path
            .parent()
            .expect("link index parent"),
    )
    .expect("create link execution index directory");
    let invalid_link_index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index: 2,
        final_link_group_index: 0,
        final_link_job_index: 2,
        link_group_count: 1,
        final_output_key: partial_key,
    };
    std::fs::write(
        &link_execution_index_path,
        serde_json::to_vec_pretty(&invalid_link_index)
            .expect("serialize invalid link execution index"),
    )
    .expect("write invalid link execution index");
    let err = store
        .load_hierarchical_link_execution_index_for_target(target)
        .expect_err("link execution index final output must use a linked-output key");
    assert!(
        err.to_string()
            .contains("does not identify a LinkedOutput artifact"),
        "unexpected link execution index key-kind error: {err}"
    );

    std::fs::remove_dir_all(&root).expect("remove final-output key-kind test dir");
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
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
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
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
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
fn completed_link_work_queue_resume_requires_persisted_output_artifact() {
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
        "laniusc-hlink-resume-output-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let link_job_index = 2;
    let group_index = 0;
    let output_key = hierarchical_link_partial_output_key(target, group_index, link_job_index);
    let interface_ref = artifact_ref(target, SourcePackArtifactKind::LibraryInterface, 0, 0);
    let object_ref = artifact_ref(target, SourcePackArtifactKind::CodegenObject, 1, 1);

    store
        .store_hierarchical_link_execution_page(&SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: link_job_index,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![interface_ref],
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: vec![object_ref],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
            output_key: output_key.clone(),
            final_output: false,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        })
        .expect("store link execution page");
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
            input_frontend_job_indices: vec![0],
            input_codegen_job_count: 1,
            input_codegen_job_indices: vec![1],
            input_link_group_count: 0,
            input_link_group_indices: Vec::new(),
            source_byte_count: 1,
            source_file_count: 1,
            source_line_count: 1,
        })
        .expect("store completed link work item");
    store
        .store_work_queue_progress_page(&SourcePackWorkQueueProgressPage {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
            target,
            page_index: 0,
            first_item_index: 0,
            item_count: 3,
            artifact_item_indices: Vec::new(),
            remaining_dependency_counts: Vec::new(),
            remaining_dependent_counts: Vec::new(),
            completed_item_indices: vec![link_job_index],
            ready_item_indices: Vec::new(),
            ready_artifact_item_indices: Vec::new(),
            claimed_items: Vec::new(),
        })
        .expect("store completed link progress page");
    store
        .store_work_queue_progress_index(&SourcePackWorkQueueProgressIndex {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
            target,
            work_item_count: 3,
            page_size: 3,
            page_count: 1,
            artifact_item_count: 0,
            completed_item_count: 1,
            ready_item_count: 0,
            ready_artifact_item_count: 0,
            claimed_item_count: 0,
            first_ready_item_index: None,
            first_ready_artifact_item_index: None,
        })
        .expect("store completed link progress index");

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
    .expect_err("resume must reject a completed link item when its output is missing");
    assert!(
        err.to_string()
            .contains("completed partial link output artifact"),
        "unexpected missing-output resume error: {err}"
    );
    assert!(
        executor.events.is_empty(),
        "completed resume must not rebuild the link group: {:?}",
        executor.events
    );

    let mut store = FilesystemArtifactStore::new(&root);
    store
        .store_partial_link_output(&output_key, b"partial:0:1:1".to_vec())
        .expect("store completed partial link output");
    let resumed = execute_claimed_link_work_queue_item(
        &root,
        link_job_index,
        target,
        "worker-a",
        8,
        Some(101),
        &mut executor,
    )
    .expect("resume should report persisted partial output without rebuilding");

    assert_eq!(resumed.executed_link_group.output_key, output_key);
    assert!(resumed.executed_link_group.output_path.is_file());
    assert_eq!(resumed.executed_link_group.linked_output_key, None);
    assert!(!resumed.completion.newly_completed);
    assert!(
        executor.events.is_empty(),
        "completed resume should stay idempotent: {:?}",
        executor.events
    );

    std::fs::remove_dir_all(&root).expect("remove completed hlink resume test dir");
}

#[test]
fn work_queue_progress_index_rejects_complete_with_ready_or_claimed_items() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-work-queue-progress-complete-contract-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Generic;
    let mut index = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target,
        work_item_count: 2,
        page_size: 2,
        page_count: 1,
        artifact_item_count: 0,
        completed_item_count: 2,
        ready_item_count: 1,
        ready_artifact_item_count: 0,
        claimed_item_count: 0,
        first_ready_item_index: Some(1),
        first_ready_artifact_item_index: None,
    };

    let err = store
        .store_work_queue_progress_index(&index)
        .expect_err("complete progress must not also advertise ready work");
    assert!(
        err.to_string().contains("completed/ready counts"),
        "unexpected complete-with-ready progress error: {err}"
    );

    index.ready_item_count = 0;
    index.first_ready_item_index = None;
    index.claimed_item_count = 1;
    let err = store
        .store_work_queue_progress_index(&index)
        .expect_err("complete progress must not keep live claims");
    assert!(
        err.to_string()
            .contains("must not advertise ready or claimed work"),
        "unexpected complete-with-claimed progress error: {err}"
    );
    assert!(
        !store
            .work_queue_progress_index_path_for_target(target)
            .exists(),
        "rejected progress index must not be persisted"
    );

    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn work_queue_progress_page_summary_rejects_claims_without_ready_items() {
    let summary = SourcePackWorkQueueProgressPageSummary {
        page_index: 0,
        first_item_index: 0,
        item_count: 2,
        artifact_item_count: 0,
        completed_item_count: 1,
        ready_item_count: 0,
        first_ready_item_index: None,
        ready_artifact_item_count: 0,
        first_ready_artifact_item_index: None,
        blocked_item_count: 1,
        pending_dependent_item_count: 0,
        claimed_item_count: 1,
        ready_claimed_item_count: 0,
        ready_artifact_claimed_item_count: 0,
        earliest_claim_lease_expires_unix_nanos: None,
    };

    let err = validate_progress_page_summary(&summary)
        .expect_err("persisted summaries must not claim non-ready work items");
    assert!(
        err.to_string().contains("claims must refer to ready items"),
        "unexpected non-ready claim summary error: {err}"
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

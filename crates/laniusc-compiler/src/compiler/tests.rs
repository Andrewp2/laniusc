use super::*;

#[test]
fn compile_error_fallback_display_uses_public_diagnostic() {
    let cases = [
        (
            CompileError::GpuFrontend("failed to load source".into()),
            "preparing frontend work",
            "failed to load source",
            "frontend error:",
        ),
        (
            CompileError::GpuSyntax("unexpected token".into()),
            "parsing",
            "unexpected token",
            "syntax error:",
        ),
        (
            CompileError::GpuTypeCheck("unknown type".into()),
            "type checking",
            "unknown type",
            "type check error:",
        ),
        (
            CompileError::GpuCodegen("unsupported target".into()),
            "generating target output",
            "unsupported target",
            "code generation error:",
        ),
    ];

    for (error, phase_note, raw_detail, legacy_prefix) in cases {
        let rendered = error.to_string();
        assert!(rendered.contains("error[LNC0057]: compiler execution failed"));
        assert!(
            rendered.contains(phase_note),
            "fallback display should identify the public compiler phase: {rendered}"
        );
        assert!(!rendered.contains("GPU"));
        assert!(
            !rendered.contains(raw_detail),
            "fallback display should not expose legacy raw detail: {rendered}"
        );
        assert!(
            !rendered.contains(legacy_prefix),
            "fallback display should not use legacy prefixes: {rendered}"
        );
    }
}

#[test]
fn compile_error_public_diagnostic_lowers_raw_phase_errors() {
    let cases = [
        (
            CompileError::GpuFrontend("GPU LL(1) parser rejected token: 4".into()),
            "preparing frontend work",
        ),
        (
            CompileError::GpuSyntax("GPU syntax error: status token 7".into()),
            "parsing",
        ),
        (
            CompileError::GpuTypeCheck("typecheck.modules.projected_refs failed".into()),
            "type checking",
        ),
        (
            CompileError::GpuCodegen("source-pack file 3 did not map".into()),
            "generating target output",
        ),
    ];

    for (error, phase_note) in cases {
        let diagnostic = error.into_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0057");
        assert_eq!(diagnostic.title, "compiler execution failed");
        assert_eq!(diagnostic.category, "tooling");
        assert_eq!(diagnostic.message, "compiler execution failed");
        assert!(diagnostic.primary_label.is_none());
        assert!(
            diagnostic
                .notes
                .iter()
                .any(|note| note.contains(phase_note)),
            "fallback diagnostic should identify the public compiler phase: {diagnostic:?}"
        );

        let rendered = diagnostic.render();
        assert!(rendered.contains("error[LNC0057]: compiler execution failed"));
        assert!(!rendered.contains("GPU"));
        assert!(!rendered.contains("source-pack file 3"));
        assert!(!rendered.contains("projected_refs"));
        assert!(!rendered.contains("status token"));
    }
}

#[test]
fn compiler_execution_failed_error_reports_operation_without_raw_detail() {
    let error = compiler_execution_failed_error(
        "the compiler stopped while initializing GPU frontend pipelines",
        "initialize parser",
        "wgpu pipeline parser.ll1.accept status readback failed",
    );

    let diagnostic = error.into_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0057");
    assert_eq!(diagnostic.message, "compiler execution failed");
    assert!(
        diagnostic
            .notes
            .iter()
            .any(|note| note == "operation: initialize parser"),
        "fallback diagnostic should identify the public operation: {diagnostic:?}"
    );

    let rendered = diagnostic.render();
    assert!(rendered.contains("error[LNC0057]: compiler execution failed"));
    assert!(rendered.contains("operation: initialize parser"));
    assert!(!rendered.contains("wgpu pipeline"));
    assert!(!rendered.contains("parser.ll1.accept"));
    assert!(!rendered.contains("readback failed"));
}

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
    let too_many_files_diagnostic = match too_many_files_err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => panic!("expected structured too-many-files diagnostic, got {other:?}"),
    };
    assert_eq!(too_many_files_diagnostic.code, "LNC0048");
    assert_eq!(
        too_many_files_diagnostic.message,
        "source-pack input limit exceeded"
    );
    assert!(
        too_many_files_diagnostic.primary_label.is_none(),
        "file-count limit errors should not invent a source span"
    );
    let rendered = too_many_files_diagnostic.render();
    assert!(rendered.contains("operation: test in-memory source pack"));
    assert!(rendered.contains("received"));
    assert!(rendered.contains("bounded codegen-unit source-file limit"));
    assert!(rendered.contains("persisted source-pack descriptor work queues"));
    assert!(!rendered.contains("frontend error:"));

    let oversized_file = "x".repeat(limits.max_source_bytes + 1);
    let oversized_file_err = validate_in_memory_source_pack_fits_default_codegen_unit(
        "test in-memory source pack",
        &[oversized_file.as_str()],
    )
    .expect_err("oversized in-memory source file should be rejected");
    let oversized_file_diagnostic = match oversized_file_err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => panic!("expected structured oversized-file diagnostic, got {other:?}"),
    };
    assert_eq!(oversized_file_diagnostic.code, "LNC0048");
    let label = oversized_file_diagnostic
        .primary_label
        .as_ref()
        .expect("oversized-file diagnostic should identify the in-memory source index");
    assert_eq!(label.path, PathBuf::from("<source pack file 0>"));
    assert_eq!(
        label.message,
        "this in-memory source file exceeds the bounded codegen-unit byte limit"
    );
    let rendered = oversized_file_diagnostic.render();
    assert!(rendered.contains("source file 0 has"));
    assert!(rendered.contains("bounded codegen-unit byte limit"));
    assert!(!rendered.contains("frontend error:"));

    let half_plus_one = limits.max_source_bytes / 2 + 1;
    let first = "x".repeat(half_plus_one);
    let second = "y".repeat(half_plus_one);
    let oversized_total_err = validate_in_memory_source_pack_fits_default_codegen_unit(
        "test in-memory source pack",
        &[first.as_str(), second.as_str()],
    )
    .expect_err("total in-memory source bytes above the default codegen unit should be rejected");
    let oversized_total_diagnostic = match oversized_total_err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => panic!("expected structured oversized-total diagnostic, got {other:?}"),
    };
    assert_eq!(oversized_total_diagnostic.code, "LNC0048");
    assert!(
        oversized_total_diagnostic.primary_label.is_none(),
        "aggregate byte limit errors should not invent a source span"
    );
    let rendered = oversized_total_diagnostic.render();
    assert!(rendered.contains("total in-memory source bytes"));
    assert!(rendered.contains("persisted source-pack descriptor work queues"));
    assert!(!rendered.contains("frontend error:"));
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

#[test]
fn source_pack_work_queue_progress_page_errors_are_structured() {
    let mut page = SourcePackWorkQueueProgressPage {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
        target: SourcePackArtifactTarget::Generic,
        page_index: 0,
        first_item_index: 0,
        item_count: 3,
        artifact_item_indices: Vec::new(),
        remaining_dependency_counts: Vec::new(),
        remaining_dependent_counts: Vec::new(),
        completed_item_indices: vec![1],
        ready_item_indices: vec![0],
        ready_artifact_item_indices: Vec::new(),
        claimed_items: Vec::new(),
    };

    let err = progress_page_record_item_claim(&mut page, 0, "   ", Some(10), Some(0))
        .expect_err("empty worker id should be rejected");
    assert_source_pack_progress_state_invalid(err, "worker id must not be empty");

    let err = progress_page_record_item_claim(&mut page, 0, "worker-a", Some(10), Some(10))
        .expect_err("expired claim lease should be rejected");
    assert_source_pack_progress_state_invalid(err, "is not after now");

    let err = progress_page_record_item_claim(&mut page, 1, "worker-a", Some(20), Some(0))
        .expect_err("completed item should not be claimable");
    assert_source_pack_progress_state_invalid(err, "already complete and cannot be claimed");

    let err = progress_page_record_item_claim(&mut page, 2, "worker-a", Some(20), Some(0))
        .expect_err("not-ready item should not be claimable");
    assert_source_pack_progress_state_invalid(err, "is not ready and cannot be claimed");

    let err = progress_page_record_item_claim(&mut page, 3, "worker-a", Some(20), Some(0))
        .expect_err("out-of-page item should not be claimable");
    assert_source_pack_library_partition_invalid(err, "cannot claim item 3 outside range");

    progress_page_record_item_claim(&mut page, 0, "worker-a", Some(20), Some(0))
        .expect("ready item should be claimable");
    let err = progress_page_record_item_claim(&mut page, 0, "worker-b", Some(20), Some(0))
        .expect_err("item claimed by another worker should be rejected");
    assert_source_pack_progress_state_invalid(err, "already claimed by worker");

    let err = progress_page_record_item_claim(&mut page, 1, "worker-a", Some(20), Some(0))
        .expect_err("completed item should still not be claimable after another claim");
    assert_source_pack_progress_state_invalid(err, "already complete and cannot be claimed");

    let err = progress_page_require_item_claimed_by(&page, 1, "worker-a", Some(0))
        .expect_err("unclaimed item should reject worker ownership");
    assert_source_pack_progress_state_invalid(err, "is not claimed by worker");

    let err = progress_page_require_item_claimed_by(&page, 0, "worker-b", Some(0))
        .expect_err("wrong worker should reject claim ownership");
    assert_source_pack_progress_state_invalid(err, "not \"worker-b\"");

    let err = progress_page_item_claim_lease_expires_by(&page, 1, "worker-a", Some(0))
        .expect_err("unclaimed item should not report lease");
    assert_source_pack_progress_state_invalid(err, "is not claimed by worker");

    let err = progress_page_item_claim_lease_expires_by(&page, 0, "worker-b", Some(0))
        .expect_err("wrong worker should not report lease");
    assert_source_pack_progress_state_invalid(err, "not \"worker-b\"");
}

#[test]
fn source_pack_work_queue_progress_validation_errors_are_structured() {
    let index = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION + 1,
        target: SourcePackArtifactTarget::Generic,
        work_item_count: 1,
        page_size: 1,
        page_count: 1,
        artifact_item_count: 0,
        completed_item_count: 0,
        ready_item_count: 0,
        ready_artifact_item_count: 0,
        claimed_item_count: 0,
        first_ready_item_index: None,
        first_ready_artifact_item_index: None,
    };
    let err = validate_progress_index(&index, SourcePackArtifactTarget::Generic)
        .expect_err("unsupported progress index version should be rejected");
    assert_source_pack_progress_state_invalid(
        err,
        "unsupported source-pack work queue progress index version",
    );

    let page = SourcePackWorkQueueProgressPage {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION + 1,
        target: SourcePackArtifactTarget::Generic,
        page_index: 0,
        first_item_index: 0,
        item_count: 1,
        artifact_item_indices: Vec::new(),
        remaining_dependency_counts: Vec::new(),
        remaining_dependent_counts: Vec::new(),
        completed_item_indices: Vec::new(),
        ready_item_indices: Vec::new(),
        ready_artifact_item_indices: Vec::new(),
        claimed_items: Vec::new(),
    };
    let err = validate_progress_page(&page, SourcePackArtifactTarget::Generic, Some(0))
        .expect_err("unsupported progress page version should be rejected");
    assert_source_pack_progress_state_invalid(
        err,
        "unsupported source-pack work queue progress page version",
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

#[test]
fn source_pack_path_manifest_rejects_compact_empty_source_byte_summaries() {
    let mut empty_summary = source_pack_contract_test_manifest();
    empty_summary.source_files.clear();
    empty_summary.source_byte_count = 0;
    let err = validate_path_manifest(&empty_summary)
        .expect_err("compact path manifests must carry source-byte evidence");
    let message = err.to_string();
    assert!(
        message.contains("path build manifest")
            && message.contains("empty source-byte summary")
            && message.contains("concrete source-byte evidence"),
        "unexpected compact source-byte summary error: {message}"
    );

    let mut under_file_count = source_pack_contract_test_manifest();
    under_file_count.source_files.clear();
    under_file_count.source_byte_count = under_file_count.source_file_count - 1;
    let err = validate_path_manifest(&under_file_count)
        .expect_err("compact path manifests must not report fewer bytes than files");
    let message = err.to_string();
    assert!(
        message.contains("source-byte summary")
            && message.contains("source-file count")
            && message.contains("package input"),
        "unexpected compact source byte/file count error: {message}"
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
        ..SourcePackLinkDescriptorSummary::default()
    }
    .with_record_contracts_from_counts();
    let interface_ref = artifact_ref(target, SourcePackArtifactKind::LibraryInterface, 1, 1);
    let object_ref = artifact_ref(target, SourcePackArtifactKind::CodegenObject, 2, 2);

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
        artifact_ref(target, SourcePackArtifactKind::LibraryInterface, 3, 3);
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
        artifact_ref(target, SourcePackArtifactKind::LibraryInterface, 4, 4);
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
            5,
            5,
        )],
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: vec![artifact_ref(
            target,
            SourcePackArtifactKind::CodegenObject,
            6,
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

    let reduce_job_index = 20usize;
    let first_link_job_index = reduce_job_index - 3;
    let partial_key = hierarchical_link_partial_output_key(target, 0, first_link_job_index);
    store
        .store_partial_link_output(&partial_key, b"partial:0:1:1".to_vec())
        .expect("store partial link artifact");
    store
        .store_hierarchical_link_execution_partial_page(
            &SourcePackHierarchicalLinkExecutionPartialPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION,
                target,
                group_index: 3,
                job_index: reduce_job_index,
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
        job_index: reduce_job_index,
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
        output_key: hierarchical_link_partial_output_key(target, 3, reduce_job_index),
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
fn hierarchical_reduce_link_requires_partial_artifact_before_beginning() {
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
        "laniusc-hlink-missing-partial-artifact-test-{}-{suffix}",
        std::process::id()
    ));
    let mut store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let producer_group_index = 0usize;
    let consumer_group_index = 1usize;
    let first_link_job_index = 2usize;
    let consumer_job_index = first_link_job_index + consumer_group_index;
    let partial_key =
        hierarchical_link_partial_output_key(target, producer_group_index, first_link_job_index);
    let reduce_output_key =
        hierarchical_link_partial_output_key(target, consumer_group_index, consumer_job_index);

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
            input_interfaces: vec![artifact_ref(
                target,
                SourcePackArtifactKind::LibraryInterface,
                0,
                0,
            )],
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: vec![artifact_ref(
                target,
                SourcePackArtifactKind::CodegenObject,
                1,
                1,
            )],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 16,
            source_file_count: 1,
            source_line_count: 1,
            output_key: partial_key.clone(),
            final_output: false,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        })
        .expect("store producer execution-page evidence without partial-link bytes");

    assert!(
        !store
            .path_for_key(&partial_key)
            .expect("partial-link artifact path")
            .exists(),
        "test setup must leave the producer partial-link bytes absent"
    );

    let reduce_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: consumer_group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Reduce,
        job_index: consumer_job_index,
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
        input_group_output_keys: vec![partial_key],
        source_byte_count: 16,
        source_file_count: 1,
        source_line_count: 1,
        output_key: reduce_output_key.clone(),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let err = execute_hierarchical_link_page(&reduce_page, &mut executor, &mut store)
        .expect_err("reduce links must require concrete partial-link artifact bytes");
    let message = err.to_string();
    assert!(
        message.contains("partial link output artifact"),
        "expected missing partial-link artifact evidence error, got {message}"
    );
    assert!(
        executor.events.is_empty(),
        "missing partial-link bytes must be rejected before the link executor begins: {:?}",
        executor.events
    );
    assert!(
        !store
            .path_for_key(&reduce_output_key)
            .expect("reduce output path")
            .exists(),
        "rejected reduce link must not write a partial-link output"
    );

    std::fs::remove_dir_all(&root).expect("remove missing partial-link artifact test dir");
}

#[test]
fn hierarchical_link_execution_rejects_sparse_nonfinal_sidecar_pages() {
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
        "laniusc-hlink-sparse-sidecar-test-{}-{suffix}",
        std::process::id()
    ));
    let mut store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;

    let interface_ref = artifact_ref(target, SourcePackArtifactKind::LibraryInterface, 0, 0);
    store
        .store_library_interface(&interface_ref, b"iface".to_vec())
        .expect("store interface artifact");

    let object_ref = artifact_ref(target, SourcePackArtifactKind::CodegenObject, 1, 1);
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
        .expect("store sparse first object sidecar page");

    let object_page_capacity = SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE;
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
        input_object_count: object_page_capacity + 1,
        input_object_page_count: 2,
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
    let err = execute_hierarchical_link_page(&leaf_page, &mut executor, &mut store)
        .expect_err("sparse non-final object sidecars must be rejected before linking");
    assert!(
        err.to_string().contains("object sidecar page 0")
            && err.to_string().contains("non-final sidecar pages")
            && err.to_string().contains("hide missing link input evidence"),
        "expected sparse object sidecar evidence error, got {err}"
    );

    let partial_page_capacity = SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE;
    let reduce_group_index = partial_page_capacity + 2;
    let reduce_job_index = reduce_group_index + 20;
    let first_link_job_index = reduce_job_index - reduce_group_index;
    let partial_key = hierarchical_link_partial_output_key(target, 0, first_link_job_index);
    store
        .store_hierarchical_link_execution_partial_page(
            &SourcePackHierarchicalLinkExecutionPartialPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION,
                target,
                group_index: reduce_group_index,
                job_index: reduce_job_index,
                page_index: 0,
                first_input_position: 0,
                input_count: 1,
                input_group_indices: vec![0],
                input_group_output_keys: vec![partial_key],
            },
        )
        .expect("store sparse first partial-link sidecar page");

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
        input_group_count: partial_page_capacity + 1,
        input_group_page_count: 2,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: hierarchical_link_partial_output_key(
            target,
            reduce_group_index,
            reduce_job_index,
        ),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };
    let err = execute_hierarchical_link_page(&reduce_page, &mut executor, &mut store)
        .expect_err("sparse non-final partial-link sidecars must be rejected before linking");
    assert!(
        err.to_string().contains("partial-link sidecar page 0")
            && err.to_string().contains("non-final sidecar pages")
            && err.to_string().contains("hide missing link input evidence"),
        "expected sparse partial-link sidecar evidence error, got {err}"
    );

    std::fs::remove_dir_all(&root).expect("remove sparse hlink sidecar test dir");
}

#[test]
fn hierarchical_link_execution_rejects_sidecar_job_mismatch_before_streaming_inputs() {
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
        "laniusc-hlink-sidecar-job-test-{}-{suffix}",
        std::process::id()
    ));
    let mut store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;

    let interface_ref = artifact_ref(target, SourcePackArtifactKind::LibraryInterface, 0, 0);
    store
        .store_library_interface(&interface_ref, b"iface".to_vec())
        .expect("store interface artifact");

    let object_ref = artifact_ref(target, SourcePackArtifactKind::CodegenObject, 1, 1);
    store
        .store_hierarchical_link_execution_object_page(
            &SourcePackHierarchicalLinkExecutionObjectPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
                target,
                group_index: 0,
                job_index: 11,
                page_index: 0,
                first_input_position: 0,
                input_count: 1,
                input_objects: vec![object_ref],
            },
        )
        .expect("store object sidecar for a different link job");

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
        output_key: hierarchical_link_partial_output_key(target, 0, 10),
        final_output: false,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };
    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let err = execute_hierarchical_link_page(&leaf_page, &mut executor, &mut store)
        .expect_err("sidecars from a different dense link job must be rejected");
    let message = err.to_string();
    assert!(
        message.contains("object sidecar page 0 records job 11")
            && message.contains("execution page records job 10")
            && message.contains("same dense link job"),
        "expected sidecar job identity error, got {message}"
    );
    assert!(
        !executor
            .events
            .iter()
            .any(|event| event.starts_with("hlink-objects:")),
        "mismatched object sidecars must be rejected before object inputs are streamed"
    );

    std::fs::remove_dir_all(&root).expect("remove mismatched hlink sidecar test dir");
}

#[test]
fn hierarchical_link_execution_rejects_noncanonical_sidecar_page_sequence() {
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
        "laniusc-hlink-sidecar-order-test-{}-{suffix}",
        std::process::id()
    ));
    let mut store = FilesystemArtifactStore::new(&root);
    let target = SourcePackArtifactTarget::Wasm;
    let object_page_capacity = SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE;
    let link_job_index = object_page_capacity * 3;

    let interface_ref = artifact_ref(target, SourcePackArtifactKind::LibraryInterface, 0, 0);
    store
        .store_library_interface(&interface_ref, b"iface".to_vec())
        .expect("store interface artifact");

    let first_page_objects = (0..object_page_capacity)
        .map(|offset| {
            artifact_ref(
                target,
                SourcePackArtifactKind::CodegenObject,
                100 + offset,
                object_page_capacity + offset,
            )
        })
        .collect::<Vec<_>>();
    let second_page_objects = (0..object_page_capacity)
        .map(|offset| {
            artifact_ref(
                target,
                SourcePackArtifactKind::CodegenObject,
                200 + offset,
                1 + offset,
            )
        })
        .collect::<Vec<_>>();

    for object_ref in &first_page_objects {
        store
            .store_codegen_object(object_ref, b"object".to_vec())
            .expect("store first-page object artifact");
    }
    store
        .store_hierarchical_link_execution_object_page(
            &SourcePackHierarchicalLinkExecutionObjectPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
                target,
                group_index: 0,
                job_index: link_job_index,
                page_index: 0,
                first_input_position: 0,
                input_count: first_page_objects.len(),
                input_objects: first_page_objects,
            },
        )
        .expect("store locally canonical first object page");
    store
        .store_hierarchical_link_execution_object_page(
            &SourcePackHierarchicalLinkExecutionObjectPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
                target,
                group_index: 0,
                job_index: link_job_index,
                page_index: 1,
                first_input_position: object_page_capacity,
                input_count: second_page_objects.len(),
                input_objects: second_page_objects,
            },
        )
        .expect("store locally canonical second object page");

    let leaf_page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target,
        group_index: 0,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: link_job_index,
        input_interface_count: 1,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: vec![interface_ref],
        input_object_count: object_page_capacity * 2,
        input_object_page_count: 2,
        input_objects: Vec::new(),
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
    };
    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let err = execute_hierarchical_link_page(&leaf_page, &mut executor, &mut store)
        .expect_err("sidecar pages must be globally canonical, not only page-local");
    let message = err.to_string();
    assert!(
        message.contains("object sidecar page 1")
            && message.contains("globally strictly ascending")
            && message.contains("duplicate or missing artifact evidence"),
        "expected cross-page sidecar order error, got {message}"
    );
    assert_eq!(
        executor
            .events
            .iter()
            .filter(|event| event.starts_with("hlink-objects:"))
            .count(),
        1,
        "the forged second page must be rejected before its object inputs are streamed"
    );

    std::fs::remove_dir_all(&root).expect("remove noncanonical hlink sidecar order test dir");
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

fn assert_explicit_source_pack_manifest_invalid(
    err: CompileError,
    library_id: Option<u32>,
    reason: &str,
) {
    let diagnostic = match err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => panic!("expected structured explicit source-pack diagnostic, got {other:?}"),
    };
    assert_eq!(diagnostic.code, "LNC0049");
    assert_eq!(diagnostic.message, "explicit source-pack manifest invalid");
    assert!(
        diagnostic.primary_label.is_none(),
        "dependency-stream manifest errors should not invent a source span"
    );
    let rendered = diagnostic.render();
    assert!(
        rendered.contains(reason),
        "diagnostic should explain the invalid manifest field: {rendered}"
    );
    if let Some(library_id) = library_id {
        assert!(
            rendered.contains(&format!("library id: {library_id}")),
            "diagnostic should include the affected library id: {rendered}"
        );
    }
    assert!(
        rendered.contains("each explicit source-pack library must appear once"),
        "diagnostic should include the shared source-pack manifest contract: {rendered}"
    );
    assert!(
        !rendered.contains("frontend error:"),
        "diagnostic should not fall back to raw frontend display: {rendered}"
    );
}

fn assert_source_pack_library_partition_invalid(err: CompileError, reason: &str) {
    let diagnostic = match err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => panic!("expected structured source-pack partition diagnostic, got {other:?}"),
    };
    assert_eq!(diagnostic.code, "LNC0050");
    assert_eq!(diagnostic.message, "source-pack library partition invalid");
    assert!(
        diagnostic.primary_label.is_none(),
        "partition metadata errors should not invent a source span"
    );
    let rendered = diagnostic.render();
    assert!(
        rendered.contains(reason),
        "diagnostic should explain the partition contract failure: {rendered}"
    );
    assert!(
        rendered.contains("source-pack library partition metadata must be complete"),
        "diagnostic should include the shared partition contract: {rendered}"
    );
    assert!(
        !rendered.contains("frontend error:"),
        "diagnostic should not fall back to raw frontend display: {rendered}"
    );
}

fn assert_source_pack_artifact_manifest_invalid(err: CompileError, reason: &str) {
    let diagnostic = match err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => {
            panic!("expected structured source-pack artifact manifest diagnostic, got {other:?}")
        }
    };
    assert_eq!(diagnostic.code, "LNC0051");
    assert_eq!(diagnostic.message, "source-pack artifact manifest invalid");
    assert!(
        diagnostic.primary_label.is_none(),
        "artifact manifest metadata errors should not invent a source span"
    );
    let rendered = diagnostic.render();
    assert!(
        rendered.contains(reason),
        "diagnostic should explain the artifact manifest contract failure: {rendered}"
    );
    assert!(
        rendered.contains("source-pack artifact manifests must describe consistent job"),
        "diagnostic should include the shared artifact manifest contract: {rendered}"
    );
    assert!(
        !rendered.contains("frontend error:"),
        "diagnostic should not fall back to raw frontend display: {rendered}"
    );
}

fn assert_source_pack_artifact_shard_invalid(err: CompileError, reason: &str) {
    let diagnostic = match err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => panic!("expected structured source-pack artifact shard diagnostic, got {other:?}"),
    };
    assert_eq!(diagnostic.code, "LNC0052");
    assert_eq!(
        diagnostic.message,
        "source-pack artifact shard metadata invalid"
    );
    assert!(
        diagnostic.primary_label.is_none(),
        "artifact shard metadata errors should not invent a source span"
    );
    let rendered = diagnostic.render();
    assert!(
        rendered.contains(reason),
        "diagnostic should explain the artifact shard contract failure: {rendered}"
    );
    assert!(
        rendered.contains("source-pack artifact shard metadata must be complete"),
        "diagnostic should include the shared artifact shard contract: {rendered}"
    );
    assert!(
        !rendered.contains("frontend error:"),
        "diagnostic should not fall back to raw frontend display: {rendered}"
    );
}

fn assert_source_pack_progress_state_invalid(err: CompileError, reason: &str) {
    let diagnostic = match err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => panic!("expected structured source-pack progress diagnostic, got {other:?}"),
    };
    assert_eq!(diagnostic.code, "LNC0058");
    assert_eq!(diagnostic.message, "source-pack progress state invalid");
    assert!(
        diagnostic.primary_label.is_none(),
        "progress-state errors should not invent a source span"
    );
    let rendered = diagnostic.render();
    assert!(
        rendered.contains(reason),
        "diagnostic should explain the progress-state failure: {rendered}"
    );
    assert!(
        rendered.contains("persisted progress shards"),
        "diagnostic should include the shared progress-state contract: {rendered}"
    );
    assert!(
        !rendered.contains("frontend error:"),
        "diagnostic should not fall back to raw frontend display: {rendered}"
    );
}

fn assert_source_pack_work_queue_invalid(err: CompileError, reason: &str) {
    let diagnostic = match err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => panic!("expected structured source-pack work-queue diagnostic, got {other:?}"),
    };
    assert_eq!(diagnostic.code, "LNC0063");
    assert_eq!(diagnostic.message, "source-pack work queue invalid");
    assert!(
        diagnostic.primary_label.is_none(),
        "work-queue metadata errors should not invent a source span"
    );
    let rendered = diagnostic.render();
    assert!(
        rendered.contains(reason),
        "diagnostic should explain the work-queue contract failure: {rendered}"
    );
    assert!(
        rendered.contains("map each work item"),
        "diagnostic should include the shared work-queue contract: {rendered}"
    );
    assert!(
        !rendered.contains("frontend error:"),
        "diagnostic should not fall back to raw frontend display: {rendered}"
    );
}

fn assert_source_pack_preparation_incomplete(err: CompileError, reason: &str) {
    let diagnostic = match err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => panic!("expected structured source-pack preparation diagnostic, got {other:?}"),
    };
    assert_eq!(diagnostic.code, "LNC0064");
    assert_eq!(diagnostic.message, "source-pack preparation incomplete");
    assert!(
        diagnostic.primary_label.is_none(),
        "bounded-preparation errors should not invent a source span"
    );
    let rendered = diagnostic.render();
    assert!(
        rendered.contains(reason),
        "diagnostic should explain the incomplete preparation: {rendered}"
    );
    assert!(
        rendered.contains("bounded source-pack preparation may require multiple calls"),
        "diagnostic should include the shared preparation contract: {rendered}"
    );
    assert!(
        !rendered.contains("frontend error:"),
        "diagnostic should not fall back to raw frontend display: {rendered}"
    );
}

fn assert_source_pack_preparation_limit_invalid(err: CompileError, reason: &str) {
    let diagnostic = match err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => {
            panic!("expected structured source-pack preparation-limit diagnostic, got {other:?}")
        }
    };
    assert_eq!(diagnostic.code, "LNC0065");
    assert_eq!(diagnostic.message, "source-pack preparation limit invalid");
    assert!(
        diagnostic.primary_label.is_none(),
        "bounded-preparation limit errors should not invent a source span"
    );
    let rendered = diagnostic.render();
    assert!(
        rendered.contains(reason),
        "diagnostic should explain the invalid preparation limit: {rendered}"
    );
    assert!(
        rendered.contains("bounded source-pack preparation APIs require positive chunk limits"),
        "diagnostic should include the shared preparation-limit contract: {rendered}"
    );
    assert!(
        !rendered.contains("frontend error:"),
        "diagnostic should not fall back to raw frontend display: {rendered}"
    );
}

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

fn assert_source_pack_metadata_store_failed(err: CompileError, reason: &str) {
    let diagnostic = match err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => panic!("expected structured source-pack metadata-store diagnostic, got {other:?}"),
    };
    assert_eq!(diagnostic.code, "LNC0060");
    assert_eq!(diagnostic.message, "source-pack metadata store failed");
    assert!(
        diagnostic.primary_label.is_none(),
        "metadata-store errors should not invent a source span"
    );
    let rendered = diagnostic.render();
    assert!(
        rendered.contains(reason),
        "diagnostic should explain the metadata-store failure: {rendered}"
    );
    assert!(
        rendered.contains("readable JSON records"),
        "diagnostic should include the shared metadata-store contract: {rendered}"
    );
    assert!(
        !rendered.contains("frontend error:"),
        "diagnostic should not fall back to raw frontend display: {rendered}"
    );
}

fn unique_compiler_test_root(label: &str) -> PathBuf {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    std::env::temp_dir().join(format!("laniusc-{label}-{}-{suffix}", std::process::id()))
}

fn diagnostic_test_explicit_source_file(library_id: u32) -> ExplicitSourcePathFile {
    ExplicitSourcePathFile {
        library_id,
        path: std::path::PathBuf::from("diagnostic-test.lanius"),
        byte_len: 1,
        modified_unix_nanos: None,
        line_count: Some(1),
    }
}

fn diagnostic_test_library_unit(library_id: u32) -> LibraryUnit {
    LibraryUnit {
        library_index: 0,
        library_id,
        first_source_index: 0,
        source_file_count: 1,
        source_bytes: 1,
        source_lines: 1,
    }
}

fn diagnostic_test_frontend_unit(library_id: u32) -> FrontendUnit {
    FrontendUnit {
        unit_index: 0,
        library_id,
        first_source_index: 0,
        source_file_count: 1,
        source_bytes: 1,
        source_lines: 1,
        oversized_source_file: false,
    }
}

fn diagnostic_test_codegen_unit(library_id: u32) -> CodegenUnit {
    CodegenUnit {
        unit_index: 0,
        library_id,
        first_source_index: 0,
        source_file_count: 1,
        source_bytes: 1,
        source_lines: 1,
        oversized_source_file: false,
    }
}

fn diagnostic_test_artifact_ref(
    kind: SourcePackArtifactKind,
    artifact_index: usize,
    producing_job_index: usize,
) -> SourcePackArtifactRef {
    SourcePackArtifactRef {
        artifact_index,
        key: "diagnostic-test-artifact".into(),
        producing_job_index,
        kind,
    }
}

fn diagnostic_test_artifact_manifest(
    version: u32,
    target: SourcePackArtifactTarget,
) -> SourcePackBuildArtifactManifest {
    SourcePackBuildArtifactManifest {
        version,
        target,
        job_count: 0,
        job_batch_count: 0,
        batch_dependency_count: 0,
        artifact_count: 0,
        job_artifact_count: 0,
        job_artifact_io_count: 0,
        artifact_use_count: 0,
        link_interface_batch_count: 0,
        link_object_batch_count: 0,
        job_schedule: Default::default(),
        job_batches: Default::default(),
        batch_dependencies: Default::default(),
        artifacts: Default::default(),
        job_artifacts: Default::default(),
        job_artifact_io: Default::default(),
        artifact_uses: Default::default(),
        link_interface_batches: Default::default(),
        link_object_batches: Default::default(),
    }
}

fn assert_input_read_failed(err: CompileError, path: &Path, operation: &str, label: &str) {
    let diagnostic = match err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => panic!("expected structured input-read diagnostic, got {other:?}"),
    };
    assert_eq!(diagnostic.code, "LNC0040");
    assert_eq!(diagnostic.message, "input read failed");
    let primary = diagnostic
        .primary_label
        .as_ref()
        .expect("input-read diagnostics should label the filesystem path");
    assert_eq!(primary.path, path);
    assert_eq!(primary.message, label);
    let rendered = diagnostic.render();
    assert!(
        rendered.contains(operation),
        "diagnostic should name the failed input operation: {rendered}"
    );
    assert!(
        rendered.contains(&path.display().to_string()),
        "diagnostic should include the input path: {rendered}"
    );
    assert!(
        !rendered.contains("frontend error:"),
        "diagnostic should not fall back to raw frontend display: {rendered}"
    );
}

fn assert_source_root_input_invalid(err: CompileError, reason: &str) {
    let diagnostic = match err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => panic!("expected structured source-root input diagnostic, got {other:?}"),
    };
    assert_eq!(diagnostic.code, "LNC0061");
    assert_eq!(diagnostic.message, "source-root input invalid");
    assert!(diagnostic.primary_label.is_none());
    let rendered = diagnostic.render();
    assert!(
        rendered.contains(reason),
        "diagnostic should explain the invalid source-root input: {rendered}"
    );
    assert!(
        rendered.contains("readable, disjoint source-root directories"),
        "diagnostic should include the shared source-root contract: {rendered}"
    );
    assert!(
        !rendered.contains("frontend error:"),
        "diagnostic should not fall back to raw frontend display: {rendered}"
    );
}

fn assert_source_pack_target_invalid(err: CompileError, operation: &str) {
    let diagnostic = match err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => panic!("expected structured source-pack target diagnostic, got {other:?}"),
    };
    assert_eq!(diagnostic.code, "LNC0062");
    assert_eq!(diagnostic.message, "source-pack target invalid");
    assert!(diagnostic.primary_label.is_none());
    let rendered = diagnostic.render();
    assert!(
        rendered.contains(operation),
        "diagnostic should name the invalid target operation: {rendered}"
    );
    assert!(
        rendered.contains("received target: Generic"),
        "diagnostic should include the rejected target: {rendered}"
    );
    assert!(
        rendered.contains("expected target:"),
        "diagnostic should describe accepted targets: {rendered}"
    );
    assert!(
        !rendered.contains("frontend error:"),
        "diagnostic should not fall back to raw frontend display: {rendered}"
    );
}

#[test]
fn public_source_path_input_errors_are_structured() {
    let root = unique_compiler_test_root("public-source-path-diagnostics");
    std::fs::create_dir_all(&root).expect("create temp public-source-path dir");

    let missing = root.join("missing.lani");
    let stdlib_paths: Vec<PathBuf> = Vec::new();
    let err = load_explicit_source_pack_manifest_from_paths(&stdlib_paths, &[missing.clone()])
        .expect_err("missing explicit source path should fail as input-read diagnostic");
    assert_input_read_failed(
        err,
        &missing,
        "operation: read explicit user source file 0",
        "could not read this explicit source file",
    );

    let stale = root.join("stale.lani");
    std::fs::write(&stale, "one\n").expect("write stale source");
    let file = read_explicit_source_path_metadata("user", 0, 1, &stale)
        .expect("source metadata should load before source changes");
    std::fs::write(&stale, "changed source\n").expect("change stale source length");
    let err = validate_explicit_source_path_file_metadata("user", 0, &file)
        .expect_err("changed source metadata should invalidate the path manifest");
    let diagnostic = match err {
        CompileError::Diagnostic(diagnostic) => diagnostic,
        other => panic!("expected structured stale path-manifest diagnostic, got {other:?}"),
    };
    assert_eq!(diagnostic.code, "LNC0049");
    assert_eq!(diagnostic.message, "explicit source-pack manifest invalid");
    let primary = diagnostic
        .primary_label
        .as_ref()
        .expect("stale path-manifest diagnostic should label the changed file");
    assert_eq!(primary.path, stale);
    assert_eq!(
        primary.message,
        "this source file changed since the manifest was planned"
    );
    let rendered = diagnostic.render();
    assert!(rendered.contains("changed since manifest was planned"));
    assert!(rendered.contains("byte_len was"));
    assert!(!rendered.contains("frontend error:"));

    std::fs::remove_dir_all(&root).expect("remove public-source-path diagnostics dir");
}

#[test]
fn source_root_configuration_errors_are_structured() {
    let root = unique_compiler_test_root("source-root-config-diagnostics");
    let source_root = root.join("src");
    std::fs::create_dir_all(&source_root).expect("create source root");
    let roots = EntrySourceRoots {
        stdlib_root: None,
        user_roots: vec![source_root.clone(), source_root.clone()],
    };

    let err = load_entry_with_source_roots(root.join("entry.lani"), &roots)
        .expect_err("duplicate source roots should be rejected before import discovery");
    assert_source_root_input_invalid(err, "duplicate source root");

    std::fs::remove_dir_all(&root).expect("remove source-root config diagnostics dir");
}

#[test]
fn descriptor_worker_rejects_generic_target_with_structured_diagnostic() {
    let root = unique_compiler_test_root("descriptor-target-diagnostics");

    let run_err = pollster::block_on(run_prepared_descriptor_worker_for_target(
        &root,
        SourcePackArtifactTarget::Generic,
        "worker",
        1,
        None,
        1,
    ))
    .expect_err("generic descriptor run target should be rejected before GPU work");
    assert_source_pack_target_invalid(run_err, "run prepared descriptor worker");

    let step_err = pollster::block_on(step_prepared_descriptor_worker_for_target(
        &root,
        SourcePackArtifactTarget::Generic,
        "worker",
        None,
        1,
    ))
    .expect_err("generic descriptor step target should be rejected before GPU work");
    assert_source_pack_target_invalid(step_err, "step prepared descriptor worker");
}

#[test]
fn bounded_source_pack_preparation_errors_are_structured() {
    let err = source_pack_preparation_incomplete_error(
        "source-pack Wasm work queue is not prepared after one bounded preparation chunk of 1 item",
    );
    assert_source_pack_preparation_incomplete(
        err,
        "not prepared after one bounded preparation chunk",
    );

    let root = unique_compiler_test_root("bounded-preparation-limit-diagnostics");
    let err = prepare_artifact_build_chunk(
        &root,
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
        0,
    )
    .expect_err("zero artifact-build preparation chunks should be rejected");
    assert_source_pack_preparation_limit_invalid(err, "max_new_items must be greater than zero");

    let libraries = Vec::<ExplicitSourceLibraryPathDependencyStream<Vec<PathBuf>, Vec<u32>>>::new();
    let err =
        prepare_metadata_chunk_for_target(libraries, &root, SourcePackArtifactTarget::Wasm, 0)
            .expect_err("zero metadata preparation chunks should be rejected");
    assert_source_pack_preparation_limit_invalid(
        err,
        "max_new_libraries must be greater than zero",
    );

    let err = validate_metadata_chunk_limits(
        7,
        SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_SOURCE_FILE_LIMIT + 1,
        0,
    )
    .expect_err("oversized metadata chunks should be preparation-limit diagnostics");
    assert_source_pack_preparation_limit_invalid(
        err,
        "source-pack metadata chunk library 7 declares",
    );

    if root.exists() {
        std::fs::remove_dir_all(&root).expect("remove bounded preparation diagnostics dir");
    }
}

#[test]
fn full_metadata_prepare_continuation_errors_are_structured() {
    let root = unique_compiler_test_root("metadata-prepare-incomplete-diagnostics");
    let source_dir = root.join("src");
    std::fs::create_dir_all(&source_dir).expect("create metadata diagnostic source dir");
    let source_path = source_dir.join("lib.lanius");
    std::fs::write(&source_path, "x").expect("write metadata diagnostic source");
    let store = FilesystemArtifactStore::new(root.join("artifacts"));
    let libraries = (0..=SOURCE_PACK_LIBRARY_METADATA_FULL_PREPARE_DEFAULT_LIBRARY_LIMIT)
        .map(|library_id| ExplicitSourceLibraryPathDependencyStream {
            library_id: library_id as u32,
            source_file_count: 1,
            paths: vec![source_path.clone()],
            dependency_library_count: 0,
            dependency_library_ids: Vec::<u32>::new(),
        })
        .collect::<Vec<_>>();

    let err = prepare_metadata(libraries, &store, SourcePackArtifactTarget::Generic)
        .expect_err("full metadata prepare should report resumable bounded continuation");
    assert_source_pack_preparation_incomplete(err, "source-pack metadata prepare did not complete");

    std::fs::remove_dir_all(&root).expect("remove metadata prepare diagnostics dir");
}

#[test]
fn public_work_queue_execution_contract_errors_are_structured() {
    let root = unique_compiler_test_root("public-work-queue-contract-diagnostics");
    let target = SourcePackArtifactTarget::Generic;
    let item_index = 0usize;
    let store = FilesystemArtifactStore::new(&root);
    store
        .store_work_queue_page(&SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target,
            item_index,
            kind: SourcePackWorkQueueItemKind::LibraryFrontend,
            job_index: 0,
            dependency_item_indices: Vec::new(),
            dependency_item_count: 0,
            dependency_page_count: 0,
            dependency_item_ranges: Vec::new(),
            dependent_item_indices: Vec::new(),
            dependent_item_count: 0,
            dependent_page_count: 0,
            dependent_item_ranges: Vec::new(),
            artifact_batch_index: Some(0),
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
        })
        .expect("store non-link work item");

    let mut executor = RecordingSourcePackByteArtifactExecutor::default();
    let err = execute_claimed_link_work_queue_item(
        &root,
        item_index,
        target,
        "worker-a",
        8,
        Some(100),
        &mut executor,
    )
    .expect_err("link execution should reject a non-link work item");
    assert_source_pack_work_queue_invalid(err, "not a link item");
    assert!(
        executor.events.is_empty(),
        "contract rejection must happen before executor work: {:?}",
        executor.events
    );

    std::fs::remove_dir_all(&root).expect("remove work-queue contract diagnostics dir");
}

#[test]
fn source_pack_work_queue_validation_version_errors_are_structured() {
    let target = SourcePackArtifactTarget::Generic;

    let index = SourcePackWorkQueueIndex {
        version: SOURCE_PACK_WORK_QUEUE_INDEX_VERSION + 1,
        target,
        work_item_count: 1,
        artifact_item_count: 1,
        final_item_index: 0,
        final_job_index: 0,
    };
    let err = validate_work_queue_index(&index, target)
        .expect_err("unsupported work-queue index versions should be structured");
    assert_source_pack_work_queue_invalid(err, "unsupported source-pack work queue index version");

    let page = SourcePackWorkQueuePage {
        version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION + 1,
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
        dependent_item_ranges: Vec::new(),
        artifact_batch_index: Some(0),
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
    };
    let err = validate_work_queue_page(&page, target, Some(0))
        .expect_err("unsupported work-queue page versions should be structured");
    assert_source_pack_work_queue_invalid(err, "unsupported source-pack work queue page version");

    let dependencies_page = SourcePackWorkQueueDependenciesPage {
        version: SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_PAGE_VERSION + 1,
        target,
        item_index: 1,
        page_index: 0,
        first_dependency_position: 0,
        dependency_count: 1,
        dependency_item_indices: vec![0],
    };
    let err = validate_work_queue_dependencies_page(&dependencies_page, target, 1, 0)
        .expect_err("unsupported work-queue dependency page versions should be structured");
    assert_source_pack_work_queue_invalid(
        err,
        "unsupported source-pack work queue dependencies page version",
    );

    let dependents_page = SourcePackWorkQueueDependentsPage {
        version: SOURCE_PACK_WORK_QUEUE_DEPENDENTS_PAGE_VERSION + 1,
        target,
        item_index: 0,
        page_index: 0,
        first_dependent_position: 0,
        dependent_count: 1,
        dependent_item_indices: vec![1],
    };
    let err = validate_work_queue_dependents_page(&dependents_page, target, 0, 0)
        .expect_err("unsupported work-queue dependent page versions should be structured");
    assert_source_pack_work_queue_invalid(
        err,
        "unsupported source-pack work queue dependents page version",
    );
}

#[test]
fn source_pack_work_queue_prepare_progress_version_errors_are_structured() {
    let target = SourcePackArtifactTarget::Generic;
    let queue = SourcePackWorkQueueIndex {
        version: SOURCE_PACK_WORK_QUEUE_INDEX_VERSION,
        target,
        work_item_count: 1,
        artifact_item_count: 1,
        final_item_index: 0,
        final_job_index: 0,
    };

    let progress = WorkQueuePrepareProgress {
        version: SOURCE_PACK_WORK_QUEUE_PREPARE_PROGRESS_VERSION + 1,
        target,
        work_item_count: 1,
        next_item_index: 0,
    };
    let err = validate_work_queue_prepare_progress(&progress, target, 1)
        .expect_err("unsupported work-queue prepare versions should be structured");
    assert_source_pack_work_queue_invalid(
        err,
        "unsupported source-pack work queue prepare progress version",
    );

    let progress = InitialWorkQueueProgressPrepareProgress {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PREPARE_PROGRESS_VERSION + 1,
        target,
        work_item_count: 1,
        page_size: 1,
        page_count: 1,
        next_page_index: 0,
        artifact_item_count: 0,
        ready_item_count: 0,
        ready_artifact_item_count: 0,
        first_ready_item_index: None,
        first_ready_artifact_item_index: None,
    };
    let err = validate_initial_work_queue_progress_prepare_progress(&progress, &queue, 1)
        .expect_err("unsupported work-queue progress prepare versions should be structured");
    assert_source_pack_work_queue_invalid(
        err,
        "unsupported source-pack work queue progress prepare progress version",
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
    assert_explicit_source_pack_manifest_invalid(
        empty_err,
        None,
        "manifest contains no source libraries",
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
    assert_explicit_source_pack_manifest_invalid(
        later_dependency_err,
        Some(2),
        "depends on missing or later library 1",
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
    assert_source_pack_library_partition_invalid(
        missing_count_err,
        "partition 1 received 1 dependency libraries but expected 2",
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
    assert_source_pack_library_partition_invalid(
        extra_count_err,
        "partition 1 received more than 0 dependency libraries",
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
    assert_explicit_source_pack_manifest_invalid(
        duplicate_err,
        Some(2),
        "dependency ids must be strictly sorted and unique",
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
    assert_explicit_source_pack_manifest_invalid(self_err, Some(1), "library depends on itself");

    let missing_later_err = err_for("missing-later", |_core_path, app_path| {
        vec![ExplicitSourceLibraryPathDependencyStream {
            library_id: 2,
            source_file_count: 1,
            paths: vec![app_path],
            dependency_library_count: 1,
            dependency_library_ids: vec![1],
        }]
    });
    assert_explicit_source_pack_manifest_invalid(
        missing_later_err,
        Some(2),
        "depends on missing or later library 1",
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
    assert_source_pack_artifact_manifest_invalid(err, "stale");
    std::fs::remove_dir_all(&root).expect("remove corrupt manifest test dir");
}

#[test]
fn artifact_shard_contract_errors_are_structured() {
    assert_source_pack_artifact_shard_invalid(
        artifact_shard_contract_error("artifact-shard test contract failure"),
        "artifact-shard test contract failure",
    );
}

#[test]
fn source_pack_prepare_progress_version_errors_are_structured() {
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
    let artifact_ref_index = SourcePackBuildArtifactRefIndex {
        version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
        target,
        artifact_count: 3,
        interface_artifact_count: 1,
        object_artifact_count: 1,
        final_output_artifact_index: 2,
        final_output_key: "linked-output".into(),
        total_source_file_count: 1,
        total_source_byte_count: 1,
        total_source_line_count: 1,
    };
    let job_batch_page_index = SourcePackBuildJobBatchPageIndex {
        version: SOURCE_PACK_BUILD_JOB_BATCH_PAGE_INDEX_VERSION,
        target,
        batch_count: 1,
        scheduled_job_count: 3,
        dependency_edge_count: 0,
    };
    let link_batch_page_index = SourcePackBuildLinkBatchPageIndex {
        version: SOURCE_PACK_BUILD_LINK_BATCH_PAGE_INDEX_VERSION,
        target,
        link_interface_batch_count: 0,
        link_object_batch_count: 0,
    };
    let library_partition_index = SourcePackLibraryPartitionIndex {
        version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
        target,
        partition_count: 1,
        source_file_count: 1,
        source_byte_count: 1,
        source_line_count: 1,
    };

    let artifact_shard_progress = ArtifactShardPrepareProgress {
        version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_PREPARE_PROGRESS_VERSION + 1,
        target,
        limits: SourcePackBuildShardLimits::default(),
        job_count: 3,
        job_batch_count: 1,
        artifact_count: 3,
        link_interface_batch_count: 0,
        link_object_batch_count: 0,
        phase: ArtifactShardPreparePhase::JobBatches,
        next_batch_index: 0,
        next_shard_index: 0,
        current_builder: Some(ArtifactShardBuilder::new(
            SourcePackBuildArtifactShardKind::JobBatches,
        )),
        job_batch_shard_count: 0,
        link_interface_shard_range: None,
        link_object_shard_range: None,
        ready_batch_count: 0,
        first_ready_batch_index: None,
    };
    let err = validate_artifact_shard_prepare_progress(
        &artifact_shard_progress,
        target,
        SourcePackBuildShardLimits::default(),
        &schedule_index,
        &artifact_ref_index,
        &job_batch_page_index,
        &link_batch_page_index,
    )
    .expect_err("unsupported artifact-shard prepare versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack artifact-shard prepare progress version",
    );

    let job_batch_progress = JobBatchPrepareProgress {
        version: SOURCE_PACK_BUILD_JOB_BATCH_PREPARE_PROGRESS_VERSION + 1,
        target,
        batch_limits: SourcePackJobBatchLimits::default().normalized(),
        scheduled_job_count: 3,
        next_job_index: 0,
        next_batch_index: 0,
        dependency_edge_count: 0,
    };
    let err = validate_build_job_batch_prepare_progress(
        &job_batch_progress,
        target,
        3,
        SourcePackJobBatchLimits::default(),
    )
    .expect_err("unsupported job-batch prepare progress versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack job-batch prepare progress version",
    );

    let dependents_progress = JobBatchDependentsPrepareProgress {
        version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PREPARE_PROGRESS_VERSION + 1,
        target,
        batch_count: 1,
        next_batch_index: 0,
        dependent_edge_count: 0,
    };
    let err = validate_job_batch_dependents_prepare_progress(&dependents_progress, target, 1)
        .expect_err("unsupported job-batch dependents prepare versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack job-batch dependents prepare progress version",
    );

    let link_execution_progress = HierarchicalLinkExecutionPrepareProgress {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_VERSION + 1,
        target,
        link_group_count: 1,
        next_group_index: 0,
        final_output_seen: false,
    };
    let err = validate_link_execution_prepare_progress(&link_execution_progress, target, 1)
        .expect_err("unsupported link execution prepare versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack hierarchical link execution prepare progress version",
    );

    let link_plan_progress = HierarchicalLinkPlanPrepareProgress {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_PREPARE_PROGRESS_VERSION + 1,
        target,
        limits: SourcePackJobBatchLimits::default().normalized(),
        schedule_partition_count: 1,
        next_partition_index: 0,
        leaf_group_count: 0,
        reduce_level: 0,
        current_level_first_group_index: 0,
        current_level_group_count: 0,
        next_input_group_index: 0,
        next_level_first_group_index: 0,
        next_level_group_count: 0,
        next_group_index: 0,
    };
    let err = validate_link_plan_prepare_progress(
        &link_plan_progress,
        target,
        1,
        SourcePackJobBatchLimits::default(),
    )
    .expect_err("unsupported link plan prepare versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack hierarchical link plan prepare progress version",
    );

    let artifact_ref_progress = ArtifactRefPrepareProgress {
        version: SOURCE_PACK_BUILD_ARTIFACT_REF_PREPARE_PROGRESS_VERSION + 1,
        target,
        partition_count: 1,
        artifact_count: 3,
        next_partition_index: 0,
        artifact_ref_page_count: 0,
        interface_artifact_count: 0,
        object_artifact_count: 0,
        total_source_file_count: 1,
        total_source_byte_count: 1,
        total_source_line_count: 1,
    };
    let err = validate_build_artifact_ref_prepare_progress(
        &artifact_ref_progress,
        &schedule_index,
        &library_partition_index,
    )
    .expect_err("unsupported artifact-ref prepare versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack artifact-ref prepare progress version",
    );

    let link_batch_progress = LinkBatchPrepareProgress {
        version: SOURCE_PACK_BUILD_LINK_BATCH_PREPARE_PROGRESS_VERSION + 1,
        target,
        batch_limits: SourcePackJobBatchLimits::default().normalized(),
        artifact_count: artifact_ref_index.artifact_count,
        interface_artifact_count: artifact_ref_index.interface_artifact_count,
        object_artifact_count: artifact_ref_index.object_artifact_count,
        next_interface_artifact_index: 0,
        next_interface_batch_index: 0,
        next_object_artifact_index: artifact_ref_index.interface_artifact_count,
        next_object_batch_index: 0,
    };
    let err = validate_build_link_batch_prepare_progress(
        &link_batch_progress,
        target,
        &artifact_ref_index,
        SourcePackJobBatchLimits::default(),
    )
    .expect_err("unsupported link-batch prepare progress versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack link-batch prepare progress version",
    );
}

#[test]
fn source_pack_schedule_validation_version_errors_are_structured() {
    let target = SourcePackArtifactTarget::Generic;
    let schedule_index = SourcePackLibraryScheduleIndex {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION + 1,
        target,
        partition_count: 1,
        frontend_job_count: 1,
        codegen_job_count: 1,
        link_job_index: 2,
        job_count: 3,
    };
    let err = validate_library_schedule_index(&schedule_index, target)
        .expect_err("unsupported schedule index versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack library schedule index version",
    );

    let progress = FilesystemLibrarySchedulePrepareProgress {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_PREPARE_PROGRESS_VERSION + 1,
        target,
        phase: FilesystemLibrarySchedulePreparePhase::BuildUnitPages,
        next_partition_index: 0,
        source_file_count: 1,
        source_byte_count: 1,
        source_line_count: 1,
        library_count: 1,
        library_partition_count: 1,
        library_source_file_page_count: 1,
        library_build_unit_page_count: 0,
        library_schedule_page_count: 0,
        frontend_job_count: 0,
        codegen_job_count: 0,
        next_frontend_job_index: 0,
        next_codegen_job_index: 0,
    };
    let err = validate_library_schedule_prepare_progress(&progress, target)
        .expect_err("unsupported schedule prepare progress versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack library schedule prepare progress version",
    );

    let frontend_job = SourcePackJob {
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
    };
    let schedule_page = SourcePackLibrarySchedulePage {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_PAGE_VERSION + 1,
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
        codegen_jobs: Vec::new(),
    };
    let err = validate_library_schedule_page(&schedule_page, target, Some(0))
        .expect_err("unsupported schedule page versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack library schedule page version",
    );
}

#[test]
fn source_pack_partition_validation_version_errors_are_structured() {
    let target = SourcePackArtifactTarget::Generic;

    let empty_manifest = ExplicitSourcePackPathManifest {
        files: Vec::new(),
        library_dependencies: Vec::new(),
    };
    let err = library_partition_plan(&empty_manifest, target)
        .expect_err("empty partition plans should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "source-pack library partition index has no source files",
    );

    let index = SourcePackLibraryPartitionIndex {
        version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION + 1,
        target,
        partition_count: 1,
        source_file_count: 1,
        source_byte_count: 1,
        source_line_count: 1,
    };
    let err = validate_library_partition_index(&index, target)
        .expect_err("unsupported partition index versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack library partition index version",
    );

    let progress = FilesystemLibraryMetadataPrepareProgress {
        version: SOURCE_PACK_LIBRARY_METADATA_PREPARE_PROGRESS_VERSION + 1,
        target,
        source_file_count: 1,
        source_byte_count: 1,
        source_line_count: 1,
        library_count: 1,
        library_partition_count: 1,
        library_source_file_page_count: 1,
    };
    let err = validate_library_metadata_prepare_progress(&progress, target)
        .expect_err("unsupported library metadata progress versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack library metadata prepare progress version",
    );

    let partition = SourcePackLibraryPartition {
        version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION + 1,
        target,
        partition_index: 0,
        library_id: 1,
        first_source_index: 0,
        source_file_count: 1,
        source_byte_count: 1,
        source_line_count: 1,
        dependency_library_ids: Vec::new(),
        dependency_library_count: 0,
        dependency_page_count: 0,
    };
    let err = validate_library_partition(&partition, target, Some(0))
        .expect_err("unsupported library partition versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack library partition version",
    );

    let dependency_page = SourcePackLibraryDependencyPage {
        version: SOURCE_PACK_LIBRARY_DEPENDENCY_PAGE_VERSION + 1,
        target,
        partition_index: 0,
        page_index: 0,
        first_dependency_position: 0,
        dependency_count: 0,
        dependency_library_ids: Vec::new(),
    };
    let err = validate_library_dependency_page(&dependency_page, target, 0, 0)
        .expect_err("unsupported library dependency page versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack library dependency page version",
    );
}

#[test]
fn source_pack_source_file_validation_version_errors_are_structured() {
    let target = SourcePackArtifactTarget::Generic;

    let locator = SourcePackLibraryPartitionLocatorPage {
        version: SOURCE_PACK_LIBRARY_PARTITION_LOCATOR_PAGE_VERSION + 1,
        target,
        library_id: 1,
        partition_index: 0,
    };
    let err = validate_library_partition_locator_page(&locator, target, Some(1))
        .expect_err("unsupported library partition locator versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack library partition locator page version",
    );

    let source_file = diagnostic_test_explicit_source_file(1);
    let source_page = SourcePackLibrarySourceFilePage {
        version: SOURCE_PACK_LIBRARY_SOURCE_FILE_PAGE_VERSION + 1,
        target,
        partition_index: 0,
        library_id: 1,
        first_source_index: 0,
        source_file_count: 1,
        source_byte_count: 1,
        source_line_count: 1,
        source_files: vec![SourcePackShardSourceFile {
            source_index: 0,
            file: source_file.clone(),
        }],
    };
    let err = validate_library_source_file_page(&source_page, target, Some(0))
        .expect_err("unsupported source-file page versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack library source-file page version",
    );

    let source_record_page = SourcePackLibrarySourceFileRecordPage {
        version: SOURCE_PACK_LIBRARY_SOURCE_FILE_RECORD_PAGE_VERSION + 1,
        target,
        partition_index: 0,
        library_id: 1,
        first_source_index: 0,
        source_file_count: 1,
        source_index: 0,
        file: source_file,
    };
    let err = validate_library_source_file_record_page(&source_record_page, target, Some(0))
        .expect_err("unsupported source-file record page versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack library source-file record page version",
    );
}

#[test]
fn source_pack_build_unit_validation_version_errors_are_structured() {
    let target = SourcePackArtifactTarget::Generic;
    let library_id = 1;
    let limits = CodegenUnitLimits::default().normalized();
    let frontend_unit = diagnostic_test_frontend_unit(library_id);
    let codegen_unit = diagnostic_test_codegen_unit(library_id);

    let build_unit_page = SourcePackLibraryBuildUnitPage {
        version: SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION + 1,
        target,
        partition_index: 0,
        library_id,
        dependency_library_ids: Vec::new(),
        first_source_index: 0,
        source_file_count: 1,
        source_byte_count: 1,
        source_line_count: 1,
        limits,
        frontend_unit: diagnostic_test_library_unit(library_id),
        frontend_unit_count: 1,
        codegen_unit_count: 1,
        frontend_units: vec![frontend_unit.clone()],
        codegen_units: vec![codegen_unit.clone()],
    };
    let err = validate_library_build_unit_page(&build_unit_page, target, Some(0))
        .expect_err("unsupported build-unit page versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack library build-unit page version",
    );

    let frontend_unit_page = SourcePackLibraryFrontendUnitPage {
        version: SOURCE_PACK_LIBRARY_FRONTEND_UNIT_PAGE_VERSION + 1,
        target,
        partition_index: 0,
        library_id,
        limits,
        frontend_unit_index: 0,
        frontend_unit_count: 1,
        unit: frontend_unit,
    };
    let err = validate_frontend_unit_page(&frontend_unit_page, target, Some(0), Some(0))
        .expect_err("unsupported frontend-unit page versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack library frontend-unit page version",
    );

    let codegen_unit_page = SourcePackLibraryCodegenUnitPage {
        version: SOURCE_PACK_LIBRARY_CODEGEN_UNIT_PAGE_VERSION + 1,
        target,
        partition_index: 0,
        library_id,
        limits,
        codegen_unit_index: 0,
        codegen_unit_count: 1,
        unit: codegen_unit,
    };
    let err = validate_codegen_unit_page(&codegen_unit_page, target, Some(0), Some(0))
        .expect_err("unsupported codegen-unit page versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack library codegen-unit page version",
    );
}

#[test]
fn source_pack_link_plan_validation_version_errors_are_structured() {
    let target = SourcePackArtifactTarget::Generic;
    let limits = SourcePackJobBatchLimits::default().normalized();

    let index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION + 1,
        target,
        limits,
        input_partition_count: 1,
        first_link_job_index: 0,
        final_link_group_index: 0,
        final_link_job_index: 0,
        link_group_count: 1,
    };
    let err = validate_link_plan_index(&index, target)
        .expect_err("unsupported link-plan index versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack hierarchical link plan version",
    );

    let group = SourcePackHierarchicalLinkGroupPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION + 1,
        target,
        group_index: 0,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        level: 0,
        job_index: 0,
        input_partition_count: 1,
        input_partition_indices: vec![0],
        input_frontend_job_count: 1,
        input_frontend_job_indices: vec![0],
        input_codegen_job_indices: vec![1],
        input_link_group_indices: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        oversized_input: false,
    };
    let err = validate_link_group_page(&group, target, Some(0))
        .expect_err("unsupported link group versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack hierarchical link group version",
    );
}

#[test]
fn source_pack_link_execution_validation_version_errors_are_structured() {
    let target = SourcePackArtifactTarget::Generic;

    let index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION + 1,
        target,
        first_link_job_index: 0,
        final_link_group_index: 0,
        final_link_job_index: 0,
        link_group_count: 1,
        final_output_key: "linked-output".into(),
    };
    let err = validate_link_execution_index(&index, target)
        .expect_err("unsupported link execution index versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack hierarchical link execution index version",
    );

    let page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION + 1,
        target,
        group_index: 0,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        job_index: 0,
        input_interface_count: 0,
        input_interface_page_count: 0,
        input_interface_ranges: Vec::new(),
        input_interfaces: Vec::new(),
        input_object_count: 0,
        input_object_page_count: 0,
        input_objects: Vec::new(),
        input_group_count: 0,
        input_group_page_count: 0,
        input_group_indices: Vec::new(),
        input_group_output_keys: Vec::new(),
        source_byte_count: 1,
        source_file_count: 1,
        source_line_count: 1,
        output_key: "linked-output".into(),
        final_output: true,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };
    let err = validate_link_execution_page(&page, target, Some(0))
        .expect_err("unsupported link execution page versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack hierarchical link execution page version",
    );

    let interface_page = SourcePackHierarchicalLinkExecutionInterfacePage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_VERSION + 1,
        target,
        group_index: 0,
        job_index: 0,
        page_index: 0,
        first_input_position: 0,
        input_count: 1,
        input_interfaces: vec![diagnostic_test_artifact_ref(
            SourcePackArtifactKind::LibraryInterface,
            0,
            0,
        )],
    };
    let err = validate_link_execution_interface_page(&interface_page, target, 0, 0)
        .expect_err("unsupported link execution interface page versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack hierarchical link execution interface page version",
    );

    let object_page = SourcePackHierarchicalLinkExecutionObjectPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION + 1,
        target,
        group_index: 0,
        job_index: 0,
        page_index: 0,
        first_input_position: 0,
        input_count: 1,
        input_objects: vec![diagnostic_test_artifact_ref(
            SourcePackArtifactKind::CodegenObject,
            1,
            0,
        )],
    };
    let err = validate_link_execution_object_page(&object_page, target, 0, 0)
        .expect_err("unsupported link execution object page versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack hierarchical link execution object page version",
    );

    let partial_page = SourcePackHierarchicalLinkExecutionPartialPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION + 1,
        target,
        group_index: 0,
        job_index: 0,
        page_index: 0,
        first_input_position: 0,
        input_count: 1,
        input_group_indices: vec![0],
        input_group_output_keys: vec!["partial-output".into()],
    };
    let err = validate_link_execution_partial_page(&partial_page, target, 0, 0)
        .expect_err("unsupported link execution partial page versions should be structured");
    assert_source_pack_library_partition_invalid(
        err,
        "unsupported source-pack hierarchical link execution partial page version",
    );
}

#[test]
fn source_pack_artifact_ref_validation_version_errors_are_structured() {
    let target = SourcePackArtifactTarget::Generic;

    let manifest =
        diagnostic_test_artifact_manifest(SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION + 1, target);
    let err = validate_artifact_manifest_version(&manifest)
        .expect_err("unsupported artifact manifest versions should be structured");
    assert_source_pack_artifact_manifest_invalid(
        err,
        "unsupported source-pack artifact manifest version",
    );

    let mut compact_manifest =
        diagnostic_test_artifact_manifest(SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION, target);
    compact_manifest.job_count = 1;
    let err = ensure_manifest_execution_records(&compact_manifest)
        .expect_err("compact manifests without inline records should be structured");
    assert_source_pack_artifact_manifest_invalid(
        err,
        "source-pack artifact-manifest execution requires inline job schedule records",
    );

    let index = SourcePackBuildArtifactRefIndex {
        version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION + 1,
        target,
        artifact_count: 1,
        interface_artifact_count: 0,
        object_artifact_count: 0,
        final_output_artifact_index: 0,
        final_output_key: "linked-output".into(),
        total_source_file_count: 1,
        total_source_byte_count: 1,
        total_source_line_count: 1,
    };
    let err = validate_artifact_ref_index(&index, target)
        .expect_err("unsupported artifact-ref index versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack artifact-ref index version",
    );

    let artifact_ref_page = SourcePackBuildArtifactRefPage {
        version: SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION + 1,
        target,
        artifact_index: 0,
        artifact_ref: diagnostic_test_artifact_ref(SourcePackArtifactKind::LinkedOutput, 0, 0),
        source_bytes: 1,
        source_file_count: 1,
        source_lines: 1,
    };
    let err = validate_artifact_ref_page(&artifact_ref_page, target, 1, Some(0))
        .expect_err("unsupported artifact-ref page versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack artifact-ref page version",
    );

    let input_page = SourcePackJobArtifactInputInterfacePage {
        version: SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_PAGE_VERSION + 1,
        target,
        job_index: 0,
        page_index: 0,
        first_input_position: 0,
        input_count: 1,
        input_interfaces: vec![diagnostic_test_artifact_ref(
            SourcePackArtifactKind::LibraryInterface,
            0,
            0,
        )],
    };
    let err = validate_job_artifact_input_interface_page(&input_page, target, 0, 0)
        .expect_err("unsupported job artifact input interface page versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack job artifact input interface page version",
    );

    let shard_index = SourcePackBuildArtifactShardIndex {
        version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION + 1,
        target,
        limits: SourcePackBuildShardLimits::default(),
        shard_count: 1,
        job_count: 1,
        job_batch_count: 1,
        artifact_count: 1,
        link_interface_batch_count: 0,
        link_object_batch_count: 0,
    };
    let err = validate_artifact_shard_index(&shard_index)
        .expect_err("unsupported artifact-shard index versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack artifact shard index version",
    );

    let shard = SourcePackBuildArtifactShard {
        version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION + 1,
        target,
        limits: SourcePackBuildShardLimits::default(),
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
    };
    let err = validate_artifact_shard(&shard, target)
        .expect_err("unsupported artifact-shard versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack artifact shard version",
    );

    let execution_shard = SourcePackBuildArtifactExecutionShard {
        version: SOURCE_PACK_BUILD_ARTIFACT_EXECUTION_SHARD_VERSION + 1,
        target,
        shard,
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
    let err = validate_execution_shard(&execution_shard, target)
        .expect_err("unsupported execution-shard versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack artifact execution shard version",
    );
}

#[test]
fn source_pack_build_state_version_errors_are_structured() {
    let mut state = SourcePackBuildState::new();
    state.version = SOURCE_PACK_BUILD_STATE_VERSION + 1;
    let err = validate_build_state_version(&state)
        .expect_err("unsupported build-state versions should be structured");
    assert_source_pack_progress_state_invalid(err, "unsupported source-pack build state version");
}

#[test]
fn source_pack_job_batch_manifest_version_errors_are_structured() {
    let target = SourcePackArtifactTarget::Generic;

    let locator = SourcePackBuildBatchShardLocator {
        version: SOURCE_PACK_BUILD_BATCH_SHARD_LOCATOR_VERSION + 1,
        target,
        batch_index: 0,
        shard_index: 0,
    };
    let err = validate_batch_shard_locator(&locator, target, 0)
        .expect_err("unsupported batch shard locator versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack batch shard locator version",
    );

    let index = SourcePackBuildJobBatchPageIndex {
        version: SOURCE_PACK_BUILD_JOB_BATCH_PAGE_INDEX_VERSION + 1,
        target,
        batch_count: 1,
        scheduled_job_count: 1,
        dependency_edge_count: 0,
    };
    let err = validate_job_batch_page_index(&index, target)
        .expect_err("unsupported job-batch index versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack job-batch page index version",
    );

    let batch = SourcePackJobBatch {
        batch_index: 0,
        wave_index: 0,
        job_indices: vec![0],
        source_bytes: 1,
        source_file_count: 1,
        source_lines: 1,
        oversized: false,
    };
    let dependency = SourcePackJobBatchDependency {
        batch_index: 0,
        dependency_batch_count: 0,
        dependency_page_count: 0,
        dependency_range_count: 0,
        dependency_range_page_count: 0,
        dependency_range_batch_count: 0,
        dependency_batch_indices: Vec::new(),
        dependency_batch_ranges: Vec::new(),
    };
    let page = SourcePackBuildJobBatchPage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_PAGE_VERSION + 1,
        target,
        batch_index: 0,
        batch,
        dependency,
    };
    let err = validate_job_batch_page(&page, target, Some(0))
        .expect_err("unsupported job-batch page versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack job-batch page version",
    );

    let dependency_page = SourcePackBuildJobBatchDependencyPage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_PAGE_VERSION + 1,
        target,
        batch_index: 0,
        page_index: 0,
        first_dependency_position: 0,
        dependency_count: 1,
        dependency_batch_indices: vec![0],
    };
    let err = validate_job_batch_dependency_page(&dependency_page, target, 0, 0)
        .expect_err("unsupported job-batch dependency page versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack job-batch dependency page version",
    );

    let range_page = SourcePackBuildJobBatchDependencyRangePage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_VERSION + 1,
        target,
        batch_index: 0,
        page_index: 0,
        first_range_position: 0,
        range_count: 1,
        dependency_batch_count: 1,
        dependency_batch_ranges: vec![SourcePackJobBatchDependencyRange {
            first_batch_index: 0,
            batch_count: 1,
        }],
    };
    let err = validate_job_batch_dependency_range_page(&range_page, target, 0, 0)
        .expect_err("unsupported job-batch dependency range page versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack job-batch dependency range page version",
    );

    let job_locator = SourcePackBuildJobBatchJobLocatorPage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_JOB_LOCATOR_PAGE_VERSION + 1,
        target,
        job_index: 0,
        batch_index: 0,
    };
    let err = validate_job_batch_locator_page(&job_locator, target, 1, Some(0))
        .expect_err("unsupported job-batch job-locator page versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack job-batch job-locator page version",
    );

    let dependents_page = SourcePackBuildJobBatchDependentsPage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PAGE_VERSION + 1,
        target,
        batch_count: 1,
        batch_index: 0,
        dependents: SourcePackJobBatchDependents {
            batch_index: 0,
            dependent_batch_indices: Vec::new(),
        },
        dependent_batch_count: 0,
        dependent_page_count: 0,
    };
    let err = validate_job_batch_dependents_page(&dependents_page, target, 1, Some(0))
        .expect_err("unsupported job-batch dependents page versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack job-batch dependents page version",
    );

    let dependent_batch_page = SourcePackBuildJobBatchDependentBatchPage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENT_BATCH_PAGE_VERSION + 1,
        target,
        batch_count: 2,
        batch_index: 0,
        page_index: 0,
        first_dependent_position: 0,
        dependent_count: 1,
        dependent_batch_indices: vec![1],
    };
    let err = validate_job_batch_dependent_batch_page(&dependent_batch_page, target, 2, 0, 0)
        .expect_err("unsupported job-batch dependent-batch page versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack job-batch dependent-batch page version",
    );
}

#[test]
fn source_pack_link_batch_manifest_version_errors_are_structured() {
    let target = SourcePackArtifactTarget::Generic;

    let index = SourcePackBuildLinkBatchPageIndex {
        version: SOURCE_PACK_BUILD_LINK_BATCH_PAGE_INDEX_VERSION + 1,
        target,
        link_interface_batch_count: 1,
        link_object_batch_count: 1,
    };
    let err = validate_link_batch_page_index(&index, target)
        .expect_err("unsupported link-batch index versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack link-batch page index version",
    );

    let interface_page = SourcePackBuildLinkInterfaceBatchPage {
        version: SOURCE_PACK_BUILD_LINK_INTERFACE_BATCH_PAGE_VERSION + 1,
        target,
        batch_index: 0,
        batch: SourcePackLinkInterfaceBatch {
            batch_index: 0,
            input_interface_artifact_indices: vec![0],
            source_bytes: 1,
            source_file_count: 1,
            source_lines: 1,
        },
    };
    let err = validate_link_interface_batch_page(&interface_page, target, Some(0))
        .expect_err("unsupported link-interface batch versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack link-interface batch page version",
    );

    let object_page = SourcePackBuildLinkObjectBatchPage {
        version: SOURCE_PACK_BUILD_LINK_OBJECT_BATCH_PAGE_VERSION + 1,
        target,
        batch_index: 0,
        batch: SourcePackLinkObjectBatch {
            batch_index: 0,
            input_object_artifact_indices: vec![1],
            source_bytes: 1,
            source_file_count: 1,
            source_lines: 1,
        },
    };
    let err = validate_link_object_batch_page(&object_page, target, Some(0))
        .expect_err("unsupported link-object batch versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack link-object batch page version",
    );

    let link_input_index = SourcePackBuildLinkInputShardIndex {
        version: SOURCE_PACK_BUILD_LINK_INPUT_SHARD_INDEX_VERSION + 1,
        target,
        link_interface_shard_range: Some(SourcePackLinkInputShardRange {
            first_shard_index: 0,
            shard_count: 1,
        }),
        link_object_shard_range: Some(SourcePackLinkInputShardRange {
            first_shard_index: 1,
            shard_count: 1,
        }),
    };
    let err = validate_link_input_shard_index(&link_input_index, target)
        .expect_err("unsupported link input shard index versions should be structured");
    assert_source_pack_artifact_shard_invalid(
        err,
        "unsupported source-pack link input shard index version",
    );
}

#[test]
fn path_build_manifest_ready_queries_report_progress_state_diagnostics() {
    let manifest = source_pack_contract_test_manifest();
    assert!(
        manifest.artifacts.job_batch_count > 1,
        "contract fixture should need more than one artifact batch"
    );

    let mut partial_state = SourcePackBuildState::new();
    partial_state.completed_batch_count = 1;
    let err = manifest
        .ready_batch_indices_from_state_limited(&partial_state, Some(1))
        .expect_err("partial compact build state lacks completed-batch identities");
    assert_source_pack_progress_state_invalid(
        err,
        "compact build state does not record completed-batch identities",
    );

    let mut claimed_state = SourcePackBuildState::new();
    claimed_state.claimed_batch_count = 1;
    let err = manifest
        .ready_unclaimed_batch_indices_from_state_limited(&claimed_state, None, Some(1))
        .expect_err("compact build state lacks claimed-batch identities");
    assert_source_pack_progress_state_invalid(
        err,
        "compact build state does not record claimed-batch identities",
    );
}

#[test]
fn build_state_progress_summary_mismatches_are_structured() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-build-state-progress-diagnostic-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);

    let summary = SourcePackBuildProgressSummary::new(SourcePackArtifactTarget::Wasm, 2);
    store
        .store_build_progress_summary(&summary)
        .expect("store progress summary fixture");

    let mut state = SourcePackBuildState::new();
    state.completed_batch_count = 1;
    let err = store
        .store_build_state_for_target(SourcePackArtifactTarget::Wasm, &state)
        .expect_err("build state should not disagree with progress summary");
    assert_source_pack_progress_state_invalid(err, "records 1 completed batches");

    std::fs::remove_dir_all(&root).expect("remove build-state progress diagnostic temp root");
}

#[test]
fn source_pack_build_progress_errors_are_structured() {
    let mut shard = SourcePackBuildProgressShard {
        version: SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION + 1,
        target: SourcePackArtifactTarget::Generic,
        shard_index: 0,
        batch_indices: vec![0],
        completed_batch_indices: Vec::new(),
        ready_batch_indices: Vec::new(),
        claimed_batches: Vec::new(),
        linked_output_key: None,
    };
    let err = validate_build_progress_shard(&shard)
        .expect_err("unsupported progress shard versions should be progress diagnostics");
    assert_source_pack_progress_state_invalid(
        err,
        "unsupported source-pack build progress shard version",
    );

    shard.version = SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION;
    shard.completed_batch_indices = vec![2];
    let err = validate_build_progress_shard(&shard)
        .expect_err("completed batches outside the shard should be progress diagnostics");
    assert_source_pack_progress_state_invalid(err, "completed batch 2 outside shard batches");

    let shard_summary = SourcePackBuildProgressShardSummary {
        version: SOURCE_PACK_BUILD_PROGRESS_SHARD_SUMMARY_VERSION,
        target: SourcePackArtifactTarget::Generic,
        shard_index: 0,
        batch_count: 1,
        completed_batch_count: 0,
        ready_batch_count: 1,
        first_ready_batch_index: None,
        claimed_batch_count: 0,
        ready_claimed_batch_count: 0,
        earliest_claim_lease_expires_unix_nanos: None,
    };
    let err = validate_build_progress_shard_summary(&shard_summary)
        .expect_err("ready shard summaries should name their first ready batch");
    assert_source_pack_progress_state_invalid(err, "ready batches but no first ready batch");

    let mut summary = SourcePackBuildProgressSummary::new(SourcePackArtifactTarget::Generic, 1);
    summary.ready_batch_count = 1;
    summary.first_ready_batch_index = Some(2);
    let err = validate_build_progress_summary(&summary)
        .expect_err("root summaries should bound their first ready batch");
    assert_source_pack_progress_state_invalid(err, "first ready batch 2 exceeds job batch count 1");

    let mut complete_summary =
        SourcePackBuildProgressSummary::new(SourcePackArtifactTarget::Generic, 1);
    complete_summary.completed_batch_count = 1;
    let store = FilesystemArtifactStore::new(std::env::temp_dir().join(format!(
        "laniusc-build-progress-diagnostic-test-{}",
        std::process::id()
    )));
    let err = validate_progress_summary_complete_output(&store, &complete_summary)
        .expect_err("complete progress summaries should record a linked output key");
    assert_source_pack_progress_state_invalid(err, "complete but has no linked output key");

    let target_mismatch_summary =
        SourcePackBuildProgressSummary::new(SourcePackArtifactTarget::Generic, 1);
    let err = first_ready_batch_from_summary_pages(
        &store,
        SourcePackArtifactTarget::Wasm,
        &target_mismatch_summary,
    )
    .expect_err("ready-frontier scans should reject mismatched targets");
    assert_source_pack_progress_state_invalid(err, "does not match requested target");

    let mut mutable_shard = SourcePackBuildProgressShard {
        version: SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION,
        target: SourcePackArtifactTarget::Generic,
        shard_index: 0,
        batch_indices: vec![0],
        completed_batch_indices: Vec::new(),
        ready_batch_indices: Vec::new(),
        claimed_batches: Vec::new(),
        linked_output_key: None,
    };
    let err = mutable_shard
        .record_batch_ready(2)
        .expect_err("readying an out-of-shard batch should be a progress diagnostic");
    assert_source_pack_progress_state_invalid(err, "cannot ready batch 2");

    let err = mutable_shard
        .require_batch_claimed_by(0, "worker-a", None)
        .expect_err("missing claims should be progress diagnostics");
    assert_source_pack_progress_state_invalid(err, "is not claimed by worker");

    let err = mutable_shard
        .record_batch_claim(0, "", None, None)
        .expect_err("empty worker ids should be progress diagnostics");
    assert_source_pack_progress_state_invalid(err, "worker id must not be empty");

    let err = mutable_shard
        .record_batch_claim(0, "worker-a", Some(10), Some(10))
        .expect_err("expired claim leases should be progress diagnostics");
    assert_source_pack_progress_state_invalid(err, "is not after now");

    mutable_shard
        .record_batch_claim(0, "worker-a", Some(20), Some(10))
        .expect("valid claim should be recorded");
    let err = mutable_shard
        .require_batch_claimed_by(0, "worker-b", Some(10))
        .expect_err("wrong-worker claims should be progress diagnostics");
    assert_source_pack_progress_state_invalid(err, "not \"worker-b\"");

    let mut completed_shard = SourcePackBuildProgressShard {
        completed_batch_indices: vec![0],
        ..mutable_shard.clone()
    };
    completed_shard.claimed_batches.clear();
    let err = completed_shard
        .record_batch_claim(0, "worker-a", None, None)
        .expect_err("completed batches should not be claimable");
    assert_source_pack_progress_state_invalid(err, "already complete and cannot be claimed");

    let mut result_shard = SourcePackBuildProgressShard {
        linked_output_key: Some("linked-output-old".into()),
        ..mutable_shard
    };
    let out_of_shard_result = ArtifactStoreBatchExecutionResult {
        batch_index: 2,
        job_count: 0,
        linked_output_key: None,
    };
    let err = result_shard
        .record_batch_result(&out_of_shard_result)
        .expect_err("recording an out-of-shard batch should be a progress diagnostic");
    assert_source_pack_progress_state_invalid(err, "cannot record batch 2");

    let conflicting_output_result = ArtifactStoreBatchExecutionResult {
        batch_index: 0,
        job_count: 1,
        linked_output_key: Some("linked-output-new".into()),
    };
    let err = result_shard
        .record_batch_result(&conflicting_output_result)
        .expect_err("conflicting linked outputs should be progress diagnostics");
    assert_source_pack_progress_state_invalid(err, "already recorded linked output");
}

#[test]
fn source_pack_artifact_store_errors_are_structured() {
    let err = artifact_path(std::path::Path::new("artifact-root"), "../escape")
        .expect_err("artifact store should reject non-normal keys");
    assert_source_pack_artifact_store_failed(err, "not relative and normal");

    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-artifact-store-diagnostic-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);
    let key = "library-interface/lib-0/job-0/src-0-1";

    let err = store
        .require_artifact_key_file(key, "library interface")
        .expect_err("missing artifact files should be structured diagnostics");
    assert_source_pack_artifact_store_failed(err, "is missing at");

    let err = read_artifact(&root, key, "library interface")
        .expect_err("missing artifact reads should be structured diagnostics");
    assert_source_pack_artifact_store_failed(err, "read source-pack library interface artifact");
}

#[test]
fn source_pack_artifact_lookup_errors_are_structured() {
    let manifest = source_pack_contract_test_manifest();
    let err = artifact_manifest_batch(&manifest.artifacts, usize::MAX)
        .expect_err("missing job batches should be manifest diagnostics");
    assert_source_pack_artifact_manifest_invalid(err, "references missing job batch");

    let err = artifact_ref_for_index(&SourcePackArtifactManifest::default(), 0)
        .expect_err("missing artifact refs should be manifest diagnostics");
    assert_source_pack_artifact_manifest_invalid(err, "references missing artifact 0");

    let job_manifest = SourcePackJobArtifactManifest {
        job_index: 7,
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
        outputs: Vec::new(),
    };
    let err = single_output_artifact_ref(&job_manifest, SourcePackArtifactKind::LinkedOutput)
        .expect_err("missing output artifacts should be manifest diagnostics");
    assert_source_pack_artifact_manifest_invalid(err, "has no LinkedOutput output artifact");
}

#[test]
fn source_pack_handle_lookup_errors_are_structured() {
    let manifest = source_pack_contract_test_manifest();
    let source_pack = manifest
        .path_manifest()
        .expect("contract fixture should retain source files");
    let build_plan = source_pack.build_plan(manifest.limits);
    let interface_artifact = build_plan
        .artifacts
        .iter()
        .find(|artifact| artifact.kind == SourcePackArtifactKind::LibraryInterface)
        .expect("contract fixture should produce library interface artifacts")
        .clone();

    let mut missing_artifact_plan = build_plan.clone();
    missing_artifact_plan
        .link
        .input_interface_artifact_ranges
        .clear();
    missing_artifact_plan.link.input_interface_artifact_indices =
        vec![missing_artifact_plan.artifacts.len()];
    let err = collect_link_interface_handle_clones::<String>(&[], &missing_artifact_plan)
        .expect_err("bad link artifact indices should be manifest diagnostics");
    assert_source_pack_artifact_manifest_invalid(err, "references missing artifact");

    let mut missing_handle_plan = build_plan.clone();
    missing_handle_plan
        .link
        .input_interface_artifact_ranges
        .clear();
    missing_handle_plan.link.input_interface_artifact_indices =
        vec![interface_artifact.artifact_index];
    let missing_handles = vec![None; interface_artifact.producing_job_index + 1];
    let err =
        collect_link_interface_handle_clones::<String>(&missing_handles, &missing_handle_plan)
            .expect_err("missing produced handles should be progress diagnostics");
    assert_source_pack_progress_state_invalid(err, "missing produced handle");

    let mut handle_by_job = vec![None; interface_artifact.producing_job_index + 1];
    handle_by_job[interface_artifact.producing_job_index] = Some(99);
    let produced_interfaces = Vec::<String>::new();
    let err =
        collect_link_interface_refs(&produced_interfaces, &handle_by_job, &missing_handle_plan)
            .expect_err("bad produced-handle slots should be progress diagnostics");
    assert_source_pack_progress_state_invalid(err, "missing slot 99");
}

#[test]
fn source_pack_execution_contract_errors_are_structured() {
    let codegen_job = SourcePackJob {
        job_index: 4,
        phase: SourcePackJobPhase::Codegen,
        phase_unit_index: 0,
        library_job_index: None,
        library_id: 10,
        first_source_index: 0,
        source_file_count: 1,
        source_bytes: 4,
        source_lines: 1,
        oversized_source_file: false,
        dependency_job_indices: Vec::new(),
    };
    let err = codegen_library_job_index(&codegen_job)
        .expect_err("codegen jobs without owning frontend jobs should be manifest diagnostics");
    assert_source_pack_artifact_manifest_invalid(err, "has no owning library job");

    assert_source_pack_artifact_manifest_invalid(
        missing_link_job_error(),
        "did not execute a link job",
    );
    assert_source_pack_artifact_manifest_invalid(
        duplicate_linked_output_error("source-pack test execution", "linked-output-key"),
        "produced more than one linked output",
    );
}

#[test]
fn gpu_source_pack_descriptor_errors_are_structured() {
    let mut job = SourcePackJob {
        job_index: 4,
        phase: SourcePackJobPhase::Codegen,
        phase_unit_index: 0,
        library_job_index: None,
        library_id: 10,
        first_source_index: 0,
        source_file_count: 1,
        source_bytes: 1,
        source_lines: 1,
        oversized_source_file: false,
        dependency_job_indices: Vec::new(),
    };
    let source_file = diagnostic_test_explicit_source_file(job.library_id);

    let mut wrong_phase = job.clone();
    wrong_phase.phase = SourcePackJobPhase::LibraryFrontend;
    let err = validate_gpu_source_pack_descriptor_job_source_file_records(
        "codegen",
        &wrong_phase,
        std::slice::from_ref(&source_file),
    )
    .expect_err("descriptor job phase mismatches should be structured");
    assert_source_pack_artifact_shard_invalid(err, "has phase LibraryFrontend");

    let err = validate_gpu_source_pack_descriptor_job_source_file_records("codegen", &job, &[])
        .expect_err("descriptor source-file count mismatches should be structured");
    assert_source_pack_artifact_shard_invalid(err, "received 0 source-file records but expected 1");

    let mut wrong_library_file = source_file.clone();
    wrong_library_file.library_id = job.library_id + 1;
    let err = validate_gpu_source_pack_descriptor_job_source_file_records(
        "codegen",
        &job,
        std::slice::from_ref(&wrong_library_file),
    )
    .expect_err("descriptor source library mismatches should be structured");
    assert_source_pack_artifact_shard_invalid(err, "belongs to library 11 but expected 10");

    job.source_bytes = 2;
    let err = validate_gpu_source_pack_descriptor_job_source_file_records(
        "codegen",
        &job,
        std::slice::from_ref(&source_file),
    )
    .expect_err("descriptor source-byte mismatches should be structured");
    assert_source_pack_artifact_shard_invalid(err, "has 1 bytes but job record declares 2");

    let root = unique_compiler_test_root("descriptor-artifact-diagnostics");
    let missing_artifact = ArtifactPath {
        key: "missing-dependency".into(),
        path: root.join("missing-dependency.json"),
    };
    let err = validate_gpu_source_pack_descriptor_artifact_paths(
        "link object batch",
        4,
        std::slice::from_ref(&missing_artifact),
    )
    .expect_err("missing descriptor dependency artifacts should be structured");
    assert_source_pack_artifact_store_failed(err, "missing dependency artifact");
}

#[test]
fn source_pack_metadata_store_errors_are_structured() {
    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "laniusc-metadata-store-diagnostic-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&root);

    let err = store
        .load_build_progress_summary_for_target(SourcePackArtifactTarget::Generic)
        .expect_err("missing progress summary should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "read source-pack build progress summary");

    let summary_path =
        store.build_progress_summary_path_for_target(SourcePackArtifactTarget::Generic);
    std::fs::create_dir_all(summary_path.parent().expect("summary path has parent"))
        .expect("create corrupt summary parent");
    std::fs::write(&summary_path, b"{").expect("write corrupt progress summary");
    let err = store
        .load_build_progress_summary_for_target(SourcePackArtifactTarget::Generic)
        .expect_err("corrupt progress summary should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "parse source-pack build progress summary");

    let err = store
        .load_library_partition_index_for_target(SourcePackArtifactTarget::Generic)
        .expect_err("missing library partition index should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "read source-pack library partition index");

    let library_index_path =
        store.library_partition_index_path_for_target(SourcePackArtifactTarget::Generic);
    std::fs::create_dir_all(
        library_index_path
            .parent()
            .expect("library index path has parent"),
    )
    .expect("create corrupt library index parent");
    std::fs::write(&library_index_path, b"{").expect("write corrupt library partition index");
    let err = store
        .load_library_partition_index_for_target(SourcePackArtifactTarget::Generic)
        .expect_err("corrupt library partition index should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "parse source-pack library partition index");

    let err = store
        .load_build_artifact_ref_index_for_target(SourcePackArtifactTarget::Generic)
        .expect_err("missing artifact-ref index should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "read source-pack artifact-ref index");

    let err = store
        .load_work_queue_index_for_target(SourcePackArtifactTarget::Generic)
        .expect_err("missing work-queue index should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "read source-pack work queue index");

    let work_queue_prepare_progress_path =
        store.work_queue_prepare_progress_path_for_target(SourcePackArtifactTarget::Generic);
    std::fs::create_dir_all(
        work_queue_prepare_progress_path
            .parent()
            .expect("work-queue prepare progress path has parent"),
    )
    .expect("create corrupt work-queue prepare progress parent");
    std::fs::write(&work_queue_prepare_progress_path, b"{")
        .expect("write corrupt work-queue prepare progress");
    let err = load_work_queue_prepare_progress(&store, SourcePackArtifactTarget::Generic, 1)
        .expect_err("corrupt work-queue prepare progress should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "parse source-pack work queue prepare progress");

    let queue = SourcePackWorkQueueIndex {
        version: SOURCE_PACK_WORK_QUEUE_INDEX_VERSION,
        target: SourcePackArtifactTarget::Generic,
        work_item_count: 1,
        artifact_item_count: 1,
        final_item_index: 0,
        final_job_index: 0,
    };
    let work_queue_progress_prepare_progress_path = store
        .work_queue_progress_prepare_progress_path_for_target(SourcePackArtifactTarget::Generic);
    std::fs::create_dir_all(
        work_queue_progress_prepare_progress_path
            .parent()
            .expect("work-queue progress prepare progress path has parent"),
    )
    .expect("create corrupt work-queue progress prepare progress parent");
    std::fs::write(&work_queue_progress_prepare_progress_path, b"{")
        .expect("write corrupt work-queue progress prepare progress");
    let err = load_initial_work_queue_progress_prepare_progress(&store, &queue, 1).expect_err(
        "corrupt work-queue progress prepare progress should be a metadata-store diagnostic",
    );
    assert_source_pack_metadata_store_failed(
        err,
        "parse source-pack work queue progress prepare progress",
    );

    let work_queue_summary_path = store
        .work_queue_progress_page_summary_path_for_target(SourcePackArtifactTarget::Generic, 0);
    std::fs::create_dir_all(
        work_queue_summary_path
            .parent()
            .expect("work-queue summary path has parent"),
    )
    .expect("create corrupt work-queue summary parent");
    std::fs::write(&work_queue_summary_path, b"{").expect("write corrupt work-queue summary");
    let err = store
        .try_load_work_queue_progress_page_summary_for_target(SourcePackArtifactTarget::Generic, 0)
        .expect_err("corrupt optional work-queue summary should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(
        err,
        "parse source-pack work queue progress page summary",
    );

    let err = store
        .load_build_link_batch_page_index_for_target(SourcePackArtifactTarget::Generic)
        .expect_err("missing link-batch page index should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "read source-pack link-batch page index");

    let err = store
        .load_build_job_batch_page_index_for_target(SourcePackArtifactTarget::Generic)
        .expect_err("missing job-batch page index should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "read source-pack job-batch page index");

    let job_batch_index_path =
        store.build_job_batch_index_path_for_target(SourcePackArtifactTarget::Generic);
    std::fs::create_dir_all(
        job_batch_index_path
            .parent()
            .expect("job-batch index path has parent"),
    )
    .expect("create corrupt job-batch index parent");
    std::fs::write(&job_batch_index_path, b"{").expect("write corrupt job-batch index");
    let err = store
        .load_build_job_batch_page_index_for_target(SourcePackArtifactTarget::Generic)
        .expect_err("corrupt job-batch page index should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "parse source-pack job-batch page index");

    let job_batch_dependents_progress_path = store
        .build_job_batch_dependents_prepare_progress_path_for_target(
            SourcePackArtifactTarget::Generic,
        );
    std::fs::create_dir_all(
        job_batch_dependents_progress_path
            .parent()
            .expect("job-batch dependents progress path has parent"),
    )
    .expect("create corrupt job-batch dependents progress parent");
    std::fs::write(&job_batch_dependents_progress_path, b"{")
        .expect("write corrupt job-batch dependents progress");
    let err =
        load_job_batch_dependents_prepare_progress(&store, SourcePackArtifactTarget::Generic, 1)
            .expect_err(
                "corrupt job-batch dependents progress should be a metadata-store diagnostic",
            );
    assert_source_pack_metadata_store_failed(
        err,
        "parse source-pack job-batch dependents prepare progress",
    );

    let dependent_page_path = store.build_job_batch_dependent_batch_page_path_for_target(
        SourcePackArtifactTarget::Generic,
        0,
        0,
    );
    std::fs::create_dir_all(
        dependent_page_path
            .parent()
            .expect("job-batch dependent page path has parent"),
    )
    .expect("create dangling job-batch dependent page parent");
    std::fs::write(&dependent_page_path, b"{}").expect("write dangling job-batch dependent page");
    let err = store
        .load_build_job_batch_dependents_page_for_target(SourcePackArtifactTarget::Generic, 0, 1)
        .expect_err("dangling job-batch dependent pages should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(
        err,
        "missing count page but dependent-batch pages exist",
    );

    let err = store
        .load_build_artifact_manifest_for_target(SourcePackArtifactTarget::Generic)
        .expect_err("missing build artifact manifest should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "read source-pack build artifact manifest");

    let err = store
        .load_build_artifact_shard_index_for_target(SourcePackArtifactTarget::Generic)
        .expect_err("missing artifact shard index should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "read source-pack build artifact shard index");

    let artifact_shard_progress_path =
        store.artifact_shard_prepare_progress_path_for_target(SourcePackArtifactTarget::Generic);
    std::fs::create_dir_all(
        artifact_shard_progress_path
            .parent()
            .expect("artifact-shard progress path has parent"),
    )
    .expect("create corrupt artifact-shard progress parent");
    std::fs::write(&artifact_shard_progress_path, b"{")
        .expect("write corrupt artifact-shard progress");
    let schedule_index = SourcePackLibraryScheduleIndex {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
        target: SourcePackArtifactTarget::Generic,
        partition_count: 1,
        frontend_job_count: 1,
        codegen_job_count: 1,
        link_job_index: 2,
        job_count: 3,
    };
    let artifact_ref_index = SourcePackBuildArtifactRefIndex {
        version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
        target: SourcePackArtifactTarget::Generic,
        artifact_count: 3,
        interface_artifact_count: 1,
        object_artifact_count: 1,
        final_output_artifact_index: 2,
        final_output_key: "linked-output".into(),
        total_source_file_count: 1,
        total_source_byte_count: 1,
        total_source_line_count: 1,
    };
    let job_batch_page_index = SourcePackBuildJobBatchPageIndex {
        version: SOURCE_PACK_BUILD_JOB_BATCH_PAGE_INDEX_VERSION,
        target: SourcePackArtifactTarget::Generic,
        batch_count: 1,
        scheduled_job_count: 3,
        dependency_edge_count: 0,
    };
    let link_batch_page_index = SourcePackBuildLinkBatchPageIndex {
        version: SOURCE_PACK_BUILD_LINK_BATCH_PAGE_INDEX_VERSION,
        target: SourcePackArtifactTarget::Generic,
        link_interface_batch_count: 0,
        link_object_batch_count: 0,
    };
    let err = load_artifact_shard_prepare_progress(
        &store,
        SourcePackArtifactTarget::Generic,
        SourcePackBuildShardLimits::default(),
        &schedule_index,
        &artifact_ref_index,
        &job_batch_page_index,
        &link_batch_page_index,
    )
    .expect_err("corrupt artifact-shard progress should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(
        err,
        "parse source-pack artifact-shard prepare progress",
    );

    let path_build_manifest_path =
        store.build_manifest_path_for_target(SourcePackArtifactTarget::Generic);
    std::fs::create_dir_all(
        path_build_manifest_path
            .parent()
            .expect("path build manifest path has parent"),
    )
    .expect("create corrupt path build manifest parent");
    std::fs::write(&path_build_manifest_path, b"{").expect("write corrupt path build manifest");
    let err = store
        .load_path_build_manifest_for_target(SourcePackArtifactTarget::Generic)
        .expect_err("corrupt path build manifest should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "parse source-pack path build manifest");

    let err = store
        .load_library_schedule_index_for_target(SourcePackArtifactTarget::Generic)
        .expect_err("missing library schedule index should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "read source-pack library schedule index");

    let schedule_index_path =
        store.library_schedule_index_path_for_target(SourcePackArtifactTarget::Generic);
    std::fs::create_dir_all(
        schedule_index_path
            .parent()
            .expect("library schedule index path has parent"),
    )
    .expect("create corrupt library schedule index parent");
    std::fs::write(&schedule_index_path, b"{").expect("write corrupt library schedule index");
    let err = store
        .load_library_schedule_index_for_target(SourcePackArtifactTarget::Generic)
        .expect_err("corrupt library schedule index should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "parse source-pack library schedule index");

    let err = store
        .load_hierarchical_link_plan_index_for_target(SourcePackArtifactTarget::Generic)
        .expect_err("missing hierarchical link plan index should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "read source-pack hierarchical link plan index");

    let link_plan_progress_path = store
        .hierarchical_link_plan_prepare_progress_path_for_target(SourcePackArtifactTarget::Generic);
    std::fs::create_dir_all(
        link_plan_progress_path
            .parent()
            .expect("hierarchical link plan progress path has parent"),
    )
    .expect("create corrupt hierarchical link plan progress parent");
    std::fs::write(&link_plan_progress_path, b"{")
        .expect("write corrupt hierarchical link plan progress");
    let err = load_link_plan_prepare_progress(
        &store,
        SourcePackArtifactTarget::Generic,
        1,
        SourcePackJobBatchLimits::default(),
    )
    .expect_err("corrupt hierarchical link plan progress should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(
        err,
        "parse source-pack hierarchical link plan prepare progress",
    );

    let link_execution_index_path =
        store.hierarchical_link_execution_index_path_for_target(SourcePackArtifactTarget::Generic);
    std::fs::create_dir_all(
        link_execution_index_path
            .parent()
            .expect("hierarchical link execution index path has parent"),
    )
    .expect("create corrupt hierarchical link execution index parent");
    std::fs::write(&link_execution_index_path, b"{")
        .expect("write corrupt hierarchical link execution index");
    let err = store
        .load_hierarchical_link_execution_index_for_target(SourcePackArtifactTarget::Generic)
        .expect_err(
            "corrupt hierarchical link execution index should be a metadata-store diagnostic",
        );
    assert_source_pack_metadata_store_failed(
        err,
        "parse source-pack hierarchical link execution index",
    );

    let link_execution_progress_path =
        store.link_execution_prepare_progress_path_for_target(SourcePackArtifactTarget::Generic);
    std::fs::create_dir_all(
        link_execution_progress_path
            .parent()
            .expect("hierarchical link execution progress path has parent"),
    )
    .expect("create corrupt hierarchical link execution progress parent");
    std::fs::write(&link_execution_progress_path, b"{")
        .expect("write corrupt hierarchical link execution progress");
    let err = load_link_execution_prepare_progress(&store, SourcePackArtifactTarget::Generic, 1)
        .expect_err(
            "corrupt hierarchical link execution progress should be a metadata-store diagnostic",
        );
    assert_source_pack_metadata_store_failed(
        err,
        "parse source-pack hierarchical link execution prepare progress",
    );

    let err = store
        .load_build_state_for_target(SourcePackArtifactTarget::Wasm)
        .expect_err("missing build state should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "read source-pack build state");

    let build_state_path = store.build_state_path_for_target(SourcePackArtifactTarget::Wasm);
    std::fs::create_dir_all(
        build_state_path
            .parent()
            .expect("build state path has parent"),
    )
    .expect("create corrupt build state parent");
    std::fs::write(&build_state_path, b"{").expect("write corrupt build state");
    let err = store
        .load_build_state_for_target(SourcePackArtifactTarget::Wasm)
        .expect_err("corrupt build state should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "parse source-pack build state");

    let mut unsupported_build_state = SourcePackBuildState::new();
    unsupported_build_state.version = SOURCE_PACK_BUILD_STATE_VERSION + 1;
    let bytes =
        serde_json::to_vec_pretty(&unsupported_build_state).expect("serialize build state fixture");
    std::fs::write(&build_state_path, bytes).expect("write unsupported build state");
    let err = store
        .load_build_state_for_target(SourcePackArtifactTarget::Wasm)
        .expect_err("unsupported build state should be a metadata-store diagnostic");
    assert_source_pack_metadata_store_failed(err, "unsupported source-pack build state version");

    let summary = SourcePackBuildProgressShardSummary {
        version: SOURCE_PACK_BUILD_PROGRESS_SHARD_SUMMARY_VERSION,
        target: SourcePackArtifactTarget::Generic,
        shard_index: 0,
        batch_count: 0,
        completed_batch_count: 0,
        ready_batch_count: 0,
        first_ready_batch_index: None,
        claimed_batch_count: 0,
        ready_claimed_batch_count: 0,
        earliest_claim_lease_expires_unix_nanos: None,
    };
    let err = store
        .store_build_progress_shard_summary_for_target(SourcePackArtifactTarget::Wasm, &summary)
        .expect_err("mismatched progress summary target should be a progress-state diagnostic");
    assert_source_pack_progress_state_invalid(err, "does not match requested target");

    std::fs::remove_dir_all(&root).expect("remove metadata-store diagnostic temp root");
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

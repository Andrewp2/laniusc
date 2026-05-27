use super::super::{test_support::*, *};

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
    std::fs::remove_dir_all(&root).expect("remove temp missing-completed-artifact dir");
    let message = err.to_string();

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

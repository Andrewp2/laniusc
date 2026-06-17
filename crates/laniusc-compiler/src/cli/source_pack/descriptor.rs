use std::{
    fs,
    path::{Path, PathBuf},
};

use super::{
    Options,
    artifact_target_for_emit,
    artifacts::{
        has_prepared_build,
        has_prepared_metadata,
        require_artifact_root,
        require_prepared_build_for_descriptor_compile,
        require_prepared_metadata_for_direct_compile,
        require_prepared_metadata_for_manifest_compile,
    },
    max_items,
    max_ready_items,
};
use crate::compiler::{
    FilesystemArtifactStore,
    FilesystemWorkQueueWorkerRunExecutionResult,
    run_prepared_descriptor_worker_for_target,
};

pub(crate) fn compile_from_metadata(emit: &str, source_pack: &Options) -> Result<PathBuf, String> {
    let artifact_root = require_artifact_root(
        source_pack,
        "--source-pack-build-from-metadata requires --source-pack-artifact-root",
    )?;
    let worker_id = format!("laniusc-{}", std::process::id());
    compile_prepared_root(emit, artifact_root, source_pack, worker_id)
}

pub(crate) fn compile_direct(emit: &str, source_pack: &Options) -> Result<PathBuf, String> {
    let artifact_root = require_artifact_root(
        source_pack,
        "source-pack descriptor compile requires --source-pack-artifact-root; run --source-pack-prepare-only with --source-pack-artifact-root until preparation completes, then rerun compile",
    )?;
    compile_prepared_or_require_metadata(emit, artifact_root, source_pack, false)
}

pub(crate) fn compile_library_manifest(
    emit: &str,
    source_pack: &Options,
) -> Result<PathBuf, String> {
    let artifact_root = require_artifact_root(
        source_pack,
        "--source-pack-library-manifest descriptor compile requires --source-pack-artifact-root",
    )?;
    compile_prepared_or_require_metadata(emit, artifact_root, source_pack, true)
}

pub(crate) fn compile_manifest(emit: &str, source_pack: &Options) -> Result<PathBuf, String> {
    let artifact_root = require_artifact_root(
        source_pack,
        "--source-pack-manifest descriptor compile requires --source-pack-artifact-root",
    )?;
    compile_prepared_or_require_metadata(emit, artifact_root, source_pack, true)
}

fn compile_prepared_or_require_metadata(
    emit: &str,
    artifact_root: &Path,
    source_pack: &Options,
    manifest_mode: bool,
) -> Result<PathBuf, String> {
    let worker_id = format!("laniusc-{}", std::process::id());
    if has_prepared_build(artifact_root, emit) {
        return run_descriptor_worker(emit, artifact_root, source_pack, worker_id);
    }
    if has_prepared_metadata(artifact_root, emit) {
        return compile_prepared_root(emit, artifact_root, source_pack, worker_id);
    }
    if manifest_mode {
        require_prepared_metadata_for_manifest_compile(artifact_root, emit)?;
    } else {
        require_prepared_metadata_for_direct_compile(artifact_root, emit)?;
    }
    compile_prepared_root(emit, artifact_root, source_pack, worker_id)
}

fn compile_prepared_root(
    emit: &str,
    artifact_root: &Path,
    source_pack: &Options,
    worker_id: String,
) -> Result<PathBuf, String> {
    require_prepared_build_for_descriptor_compile(artifact_root, emit)?;
    run_descriptor_worker(emit, artifact_root, source_pack, worker_id)
}

fn run_descriptor_worker(
    emit: &str,
    artifact_root: &Path,
    source_pack: &Options,
    worker_id: String,
) -> Result<PathBuf, String> {
    let max_items = max_items(source_pack);
    let max_ready_items = max_ready_items(source_pack);
    let run = pollster::block_on(run_prepared_descriptor_worker_for_target(
        artifact_root,
        artifact_target_for_emit(emit),
        worker_id,
        max_items,
        None,
        max_ready_items,
    ))
    .map_err(|err| err.to_string())?;
    linked_output_path(artifact_root, run)
}

fn linked_output_path(
    artifact_root: &Path,
    run: FilesystemWorkQueueWorkerRunExecutionResult,
) -> Result<PathBuf, String> {
    if !run.progress.complete {
        return Err(format!(
            "source-pack descriptor build stopped before completion at {}; executed_items={} completed_items={} work_items={} ready_items={}; rerun with --source-pack-artifact-root {} to continue the bounded work queue",
            artifact_root.display(),
            run.executed_item_count,
            run.progress.completed_item_count,
            run.progress.work_item_count,
            run.progress.ready_item_count,
            artifact_root.display(),
        ));
    }
    let linked_output_path = run.linked_output_path.ok_or_else(|| {
        "completed source-pack descriptor build did not report a linked output path".to_string()
    })?;
    let linked_output_key = run.linked_output_key.ok_or_else(|| {
        "completed source-pack descriptor build did not report a linked output key".to_string()
    })?;
    let store = FilesystemArtifactStore::new(artifact_root);
    let expected_linked_output_path = store
        .path_for_key(&linked_output_key)
        .map_err(|err| err.to_string())?;
    if !linked_output_path.is_file() {
        return Err(format!(
            "completed source-pack linked output is missing at {}",
            linked_output_path.display()
        ));
    }
    let canonical_root = fs::canonicalize(artifact_root).map_err(|err| {
        format!(
            "canonicalize source-pack artifact root {}: {err}",
            artifact_root.display()
        )
    })?;
    let canonical_output = fs::canonicalize(&linked_output_path).map_err(|err| {
        format!(
            "canonicalize completed source-pack linked output {}: {err}",
            linked_output_path.display()
        )
    })?;
    let canonical_expected = fs::canonicalize(&expected_linked_output_path).map_err(|err| {
        format!(
            "canonicalize source-pack linked output artifact {:?} at {}: {err}",
            linked_output_key,
            expected_linked_output_path.display()
        )
    })?;
    if canonical_output != canonical_expected {
        return Err(format!(
            "completed source-pack linked output path {} does not match linked output artifact {:?} at {}",
            linked_output_path.display(),
            linked_output_key,
            expected_linked_output_path.display()
        ));
    }
    if !canonical_output.starts_with(&canonical_root) {
        return Err(format!(
            "completed source-pack linked output artifact {:?} resolves outside artifact root {}: {}",
            linked_output_key,
            artifact_root.display(),
            canonical_output.display()
        ));
    }
    Ok(linked_output_path)
}

#[cfg(test)]
mod tests {
    use std::{
        env,
        time::{SystemTime, UNIX_EPOCH},
    };

    use super::*;
    use crate::{
        codegen::unit::SourcePackArtifactTarget,
        compiler::FilesystemWorkQueueProgressSnapshot,
    };

    fn completed_run(
        linked_output_key: String,
        linked_output_path: PathBuf,
    ) -> FilesystemWorkQueueWorkerRunExecutionResult {
        FilesystemWorkQueueWorkerRunExecutionResult {
            worker_id: "test-worker".into(),
            executed_item_count: 1,
            executed_artifact_batch_count: 0,
            executed_link_group_count: 1,
            linked_output_key: Some(linked_output_key),
            linked_output_path: Some(linked_output_path),
            progress: FilesystemWorkQueueProgressSnapshot {
                target: SourcePackArtifactTarget::Wasm,
                work_item_count: 1,
                completed_item_count: 1,
                ready_item_count: 0,
                claimed_item_count: 0,
                first_ready_item_index: None,
                ready_item_indices: Vec::new(),
                complete: true,
                work_queue_index_path: PathBuf::from("source-pack-work-queue.json"),
                progress_index_path: PathBuf::from("source-pack-work-queue-progress.json"),
            },
        }
    }

    fn temp_root(name: &str) -> PathBuf {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        env::temp_dir().join(format!("laniusc-{name}-{}-{suffix}", std::process::id()))
    }

    #[test]
    fn descriptor_completion_rejects_linked_output_path_outside_artifact_key() {
        let root = temp_root("descriptor-linked-output-path");
        let artifact_root = root.join("artifacts");
        let outside_output = root.join("outside-linked-output");
        fs::create_dir_all(&artifact_root).expect("create artifact root");
        fs::write(&outside_output, b"outside").expect("write outside output");

        let linked_output_key = "wasm/linked-output/job-0/src-0-1".to_string();
        let expected_output_path = FilesystemArtifactStore::new(&artifact_root)
            .path_for_key(&linked_output_key)
            .expect("linked output key path");
        fs::create_dir_all(
            expected_output_path
                .parent()
                .expect("linked output path has parent"),
        )
        .expect("create linked output directory");
        fs::write(&expected_output_path, b"expected").expect("write expected output");

        let err = linked_output_path(
            &artifact_root,
            completed_run(linked_output_key.clone(), outside_output),
        )
        .expect_err("descriptor completion must reject paths outside the linked output key");
        assert!(
            err.contains("does not match linked output artifact")
                && err.contains(&linked_output_key),
            "unexpected linked output path error: {err}"
        );

        fs::remove_dir_all(&root).expect("remove descriptor completion root");
    }
}

use std::path::Path;

use super::{Options, artifact_target_for_emit};
use crate::{codegen::unit::SourcePackArtifactTarget, compiler::FilesystemArtifactStore};

/// Returns the artifact root required by persisted source-pack operations.
pub(super) fn require_artifact_root<'a>(
    source_pack: &'a Options,
    message: &str,
) -> Result<&'a Path, String> {
    source_pack
        .artifact_root
        .as_deref()
        .ok_or_else(|| message.to_string())
}

/// Checks whether the artifact root already has a prepared build queue.
pub(super) fn has_prepared_build(artifact_root: &Path, emit: &str) -> bool {
    let store = FilesystemArtifactStore::new(artifact_root);
    store
        .build_state_path_for_target(artifact_target_for_emit(emit))
        .is_file()
}

/// Checks whether the artifact root already has prepared library metadata.
pub(super) fn has_prepared_metadata(artifact_root: &Path, emit: &str) -> bool {
    let store = FilesystemArtifactStore::new(artifact_root);
    store
        .library_partition_index_path_for_target(artifact_target_for_emit(emit))
        .is_file()
}

/// Counts the prepared library prefix available for incremental metadata prep.
pub(super) fn prepared_library_prefix_count(
    artifact_root: &Path,
    target: SourcePackArtifactTarget,
) -> usize {
    let store = FilesystemArtifactStore::new(artifact_root);
    if let Ok(index) = store.load_library_partition_index_for_target(target) {
        return index.partition_count;
    }
    if let Ok(progress) = store.load_library_metadata_prepare_progress_for_target(target) {
        return progress.library_partition_count;
    }

    let mut partition_count = 0usize;
    while store
        .library_partition_path_for_target(target, partition_count)
        .is_file()
    {
        partition_count = partition_count.saturating_add(1);
    }
    partition_count
}

/// Requires persisted metadata before direct source-pack descriptor compile.
pub(super) fn require_prepared_metadata_for_direct_compile(
    artifact_root: &Path,
    emit: &str,
) -> Result<(), String> {
    if has_prepared_build(artifact_root, emit) || has_prepared_metadata(artifact_root, emit) {
        return Ok(());
    }
    Err(format!(
        "source-pack descriptor compile at {} has no persisted metadata for target {emit}; run --source-pack-prepare-only with --source-pack-artifact-root {} until preparation completes, then rerun compile",
        artifact_root.display(),
        artifact_root.display()
    ))
}

/// Requires persisted metadata before manifest-backed descriptor compile.
pub(super) fn require_prepared_metadata_for_manifest_compile(
    artifact_root: &Path,
    emit: &str,
) -> Result<(), String> {
    if has_prepared_build(artifact_root, emit) || has_prepared_metadata(artifact_root, emit) {
        return Ok(());
    }
    Err(format!(
        "source-pack manifest descriptor compile at {} has no persisted metadata for target {emit}; run --source-pack-prepare-only with --source-pack-library-manifest and --source-pack-artifact-root {} until preparation completes, then rerun compile",
        artifact_root.display(),
        artifact_root.display()
    ))
}

/// Requires a prepared build queue before descriptor link output is requested.
pub(super) fn require_prepared_build_for_descriptor_compile(
    artifact_root: &Path,
    emit: &str,
) -> Result<(), String> {
    if has_prepared_build(artifact_root, emit) {
        return Ok(());
    }
    Err(format!(
        "source-pack descriptor compile at {} has persisted metadata but no prepared build queue for target {emit}; run --source-pack-prepare-only or --source-pack-build-from-metadata --source-pack-build-prepare-only with --source-pack-artifact-root {} until preparation completes, then rerun compile",
        artifact_root.display(),
        artifact_root.display()
    ))
}

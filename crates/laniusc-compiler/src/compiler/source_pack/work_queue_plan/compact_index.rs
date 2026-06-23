use super::*;

/// Stores the final compact work-queue index.
///
/// The index is validated and written atomically after every work-queue item
/// page has been materialized.
pub(in crate::compiler) fn store_work_queue_compact_index(
    store: &FilesystemArtifactStore,
    index: &SourcePackWorkQueueIndex,
) -> Result<PathBuf, CompileError> {
    validate_work_queue_index(index, index.target)?;
    let path = store.work_queue_index_path_for_target(index.target);
    let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
        source_pack_store_metadata_error(format!("serialize source-pack work queue index: {err}"))
    })?;
    write_file_atomic(&path, &bytes, "source-pack work queue index")?;
    Ok(path)
}

use super::*;

/// Builds the error returned when one bounded preparation chunk did not finish the work queue.
pub(in crate::compiler) fn work_queue_not_prepared_error(
    target: SourcePackArtifactTarget,
    max_new_items: usize,
) -> CompileError {
    CompileError::GpuFrontend(format!(
        "source-pack {:?} work queue is not prepared after one bounded preparation chunk of {max_new_items} items; rerun the descriptor worker or call prepare_metadata_chunk_for_target and prepare_artifact_build_chunk until the persisted work queue is complete",
        target
    ))
}

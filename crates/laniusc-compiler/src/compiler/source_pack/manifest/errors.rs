use super::*;

/// Creates a manifest-contract compiler error.
pub(in crate::compiler) fn manifest_contract_error(message: impl Into<String>) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0051", "source-pack artifact manifest invalid")
            .with_note(message)
            .with_note(
                "source-pack artifact manifests must describe consistent job, batch, artifact, and artifact-use records before persisted build replay can continue",
            ),
    )
}

/// Creates an artifact-shard-contract compiler error.
pub(in crate::compiler) fn artifact_shard_contract_error(
    message: impl Into<String>,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0052", "source-pack artifact shard metadata invalid")
            .with_note(message)
            .with_note(
                "source-pack artifact shard metadata must be complete and internally consistent before artifact preparation or persisted build replay can continue",
            ),
    )
}

/// Creates a library-partition-contract compiler error.
pub(crate) fn library_partition_contract_error(message: impl Into<String>) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0050", "source-pack library partition invalid")
            .with_note(message)
            .with_note(
                "source-pack library partition metadata must be complete and internally consistent before schedule or artifact preparation can continue",
            ),
    )
}

/// Creates a source-pack progress-state compiler error.
pub(in crate::compiler) fn source_pack_progress_state_error(
    message: impl Into<String>,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0058", "source-pack progress state invalid")
            .with_note(message)
            .with_note(
                "source-pack progress queries and resumed artifact builds require persisted progress shards that agree with completed, claimed, ready, and linked-output state",
            )
            .with_help(
                "continue the persisted build with source-pack worker APIs or regenerate the source-pack artifact root before querying ready batches",
            ),
    )
}

/// Creates a source-pack work-queue-contract compiler error.
pub(in crate::compiler) fn source_pack_work_queue_contract_error(
    message: impl Into<String>,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0063", "source-pack work queue invalid")
            .with_note(message)
            .with_note(
                "source-pack work queues must map each work item to the artifact batch or hierarchical link group required by its item kind before workers can claim or execute persisted work",
            )
            .with_help(
                "regenerate the source-pack work queue metadata or rerun artifact preparation before resuming descriptor workers",
            ),
    )
}

/// Creates a source-pack preparation-incomplete compiler error.
pub(crate) fn source_pack_preparation_incomplete_error(message: impl Into<String>) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0064", "source-pack preparation incomplete")
            .with_note(message)
            .with_note(
                "bounded source-pack preparation may require multiple calls before all persisted metadata, work queues, and artifact build records are ready for execution",
            )
            .with_help(
                "continue calling the bounded source-pack preparation API with the same artifact root, or increase the chunk limit for one-shot preparation",
            ),
    )
}

/// Creates a source-pack preparation-limit compiler error.
pub(in crate::compiler) fn source_pack_preparation_limit_invalid_error(
    message: impl Into<String>,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0065", "source-pack preparation limit invalid")
            .with_note(message)
            .with_note(
                "bounded source-pack preparation APIs require positive chunk limits so each call can make forward progress or report a completed preparation state",
            )
            .with_help(
                "pass a chunk limit greater than zero, or use the full preparation API when bounded resumability is not needed",
            ),
    )
}

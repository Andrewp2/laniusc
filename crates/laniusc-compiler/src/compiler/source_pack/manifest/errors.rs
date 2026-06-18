use super::*;

/// Creates a manifest-contract compiler error.
pub(in crate::compiler) fn manifest_contract_error(message: impl Into<String>) -> CompileError {
    CompileError::GpuFrontend(format!(
        "invalid source-pack artifact manifest: {}",
        message.into()
    ))
}

/// Creates an artifact-shard-contract compiler error.
pub(in crate::compiler) fn artifact_shard_contract_error(
    message: impl Into<String>,
) -> CompileError {
    CompileError::GpuFrontend(format!(
        "invalid source-pack artifact shard index: {}",
        message.into()
    ))
}

/// Creates a library-partition-contract compiler error.
pub(in crate::compiler) fn library_partition_contract_error(
    message: impl Into<String>,
) -> CompileError {
    CompileError::GpuFrontend(format!(
        "invalid source-pack library partition index: {}",
        message.into()
    ))
}

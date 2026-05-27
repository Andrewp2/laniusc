use super::*;

pub(in crate::compiler) fn manifest_contract_error(message: impl Into<String>) -> CompileError {
    CompileError::GpuFrontend(format!(
        "invalid source-pack artifact manifest: {}",
        message.into()
    ))
}

pub(in crate::compiler) fn artifact_shard_contract_error(
    message: impl Into<String>,
) -> CompileError {
    CompileError::GpuFrontend(format!(
        "invalid source-pack artifact shard index: {}",
        message.into()
    ))
}

pub(in crate::compiler) fn library_partition_contract_error(
    message: impl Into<String>,
) -> CompileError {
    CompileError::GpuFrontend(format!(
        "invalid source-pack library partition index: {}",
        message.into()
    ))
}

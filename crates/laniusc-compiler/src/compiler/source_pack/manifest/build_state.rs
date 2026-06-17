use super::*;

pub(in crate::compiler) fn validate_build_state_version(
    state: &SourcePackBuildState,
) -> Result<(), CompileError> {
    if state.version != SOURCE_PACK_BUILD_STATE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack build state version {}; expected {}",
            state.version, SOURCE_PACK_BUILD_STATE_VERSION
        )));
    }
    Ok(())
}

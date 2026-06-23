use super::*;

/// Validates the serialized build-state version.
pub(in crate::compiler) fn validate_build_state_version(
    state: &SourcePackBuildState,
) -> Result<(), CompileError> {
    if state.version != SOURCE_PACK_BUILD_STATE_VERSION {
        return Err(source_pack_progress_state_error(format!(
            "unsupported source-pack build state version {}; expected {}",
            state.version, SOURCE_PACK_BUILD_STATE_VERSION
        )));
    }
    Ok(())
}

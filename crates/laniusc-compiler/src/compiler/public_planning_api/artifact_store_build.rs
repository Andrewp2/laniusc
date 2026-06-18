use super::*;

/// Load stdlib and user source paths, plan a build, and execute it through a
/// caller-provided artifact store.
pub fn execute_pack_paths_store_build<SP, UP, E, S>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
    store: &mut S,
) -> Result<ArtifactStoreBuildExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
    E: ArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: ArtifactStore,
{
    load_explicit_source_pack_path_manifest_from_paths(stdlib_paths, user_paths)?
        .execute_build_plan_with_artifact_store(limits, batch_limits, executor, store)
}

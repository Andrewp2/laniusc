use super::*;

/// Plan frontend library/codegen units from stdlib and user source paths.
pub fn plan_pack_frontend_from_paths<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    limits: CodegenUnitLimits,
) -> Result<SourcePackBuildPlan, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    Ok(
        load_explicit_source_pack_path_manifest_from_paths(stdlib_paths, user_paths)?
            .bounded_frontend_build_plan(limits),
    )
}

/// Plan a compact artifact manifest from stdlib and user source paths.
pub fn plan_pack_artifacts_from_paths<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackBuildArtifactManifest, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    plan_source_pack_streams_compact_manifest(
        stdlib_paths.len(),
        stdlib_paths.iter().map(|path| path.as_ref()),
        user_paths.len(),
        user_paths.iter().map(|path| path.as_ref()),
        limits,
        batch_limits,
    )
}

/// Plan frontend library/codegen units from explicit library path groups.
pub fn plan_libraries_frontend_from_paths<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    limits: CodegenUnitLimits,
) -> Result<SourcePackBuildPlan, CompileError>
where
    P: AsRef<Path>,
{
    Ok(ExplicitSourcePackPathManifest::from_libraries(libraries)?
        .bounded_frontend_build_plan(limits))
}

/// Plan a compact artifact manifest from explicit library path groups.
pub fn plan_libraries_artifacts_from_paths<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackBuildArtifactManifest, CompileError>
where
    P: AsRef<Path>,
{
    let ordered_libraries = ordered_dependency_streams_from_library_paths(libraries)?;
    compact_manifest_from_dependency_streams(
        ordered_libraries,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

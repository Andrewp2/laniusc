use super::*;

pub fn execute_libraries_store_build<P, E, S>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
    store: &mut S,
) -> Result<ArtifactStoreBuildExecutionResult, CompileError>
where
    P: AsRef<Path>,
    E: ArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: ArtifactStore,
{
    ExplicitSourcePackPathManifest::from_libraries(libraries)?
        .execute_build_plan_with_artifact_store(limits, batch_limits, executor, store)
}

pub fn prepare_library_paths<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<PrepareResult, CompileError>
where
    P: AsRef<Path>,
{
    prepare_library_paths_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_library_paths_for_target<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<PrepareResult, CompileError>
where
    P: AsRef<Path>,
{
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let state_lock = store.try_lock_build_state_for_target(target)?;
    let ordered_libraries = ordered_dependency_streams_from_library_paths(libraries)?;
    let prepared_library_pages = prepare_schedule(ordered_libraries, &store, target, limits)?;
    drop(state_lock);
    prepare_library_pages_artifact_build(
        prepared_library_pages,
        &store,
        limits,
        batch_limits,
        target,
    )
}

pub fn prepare_ordered_library_paths<I, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<PrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    prepare_ordered_library_paths_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_ordered_library_paths_with_shards<I, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
) -> Result<PrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    prepare_ordered_library_paths_for_target_with_shards(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_ordered_library_paths_for_target<I, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<PrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    prepare_ordered_library_paths_for_target_with_shards(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
    )
}

pub fn prepare_ordered_library_paths_for_target_with_shards<I, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
) -> Result<PrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let state_lock = store.try_lock_build_state_for_target(target)?;
    let dependency_streams = dependency_streams_from_library_paths(libraries);
    let prepared_library_pages = prepare_schedule(dependency_streams, &store, target, limits)?;
    drop(state_lock);
    prepare_library_pages_artifact_build_with_shards(
        prepared_library_pages,
        &store,
        limits,
        batch_limits,
        shard_limits,
        target,
    )
}

pub fn prepare_ordered_path_streams<I, PI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<PrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    prepare_ordered_path_streams_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_ordered_path_streams_with_shards<I, PI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
) -> Result<PrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    prepare_ordered_path_streams_for_target_with_shards(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_ordered_path_streams_for_target<I, PI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<PrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    prepare_ordered_path_streams_for_target_with_shards(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
    )
}

pub fn prepare_ordered_path_streams_for_target_with_shards<I, PI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
) -> Result<PrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let state_lock = store.try_lock_build_state_for_target(target)?;
    let dependency_streams = dependency_streams_from_path_streams(libraries);
    let prepared_library_pages = prepare_schedule(dependency_streams, &store, target, limits)?;
    drop(state_lock);
    prepare_library_pages_artifact_build_with_shards(
        prepared_library_pages,
        &store,
        limits,
        batch_limits,
        shard_limits,
        target,
    )
}

pub fn prepare_dependency_streams<I, PI, DI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<PrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    prepare_dependency_streams_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_dependency_streams_with_shards<I, PI, DI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
) -> Result<PrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    prepare_dependency_streams_for_target_with_shards(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_dependency_streams_for_target<I, PI, DI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<PrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    prepare_dependency_streams_for_target_with_shards(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
    )
}

pub fn prepare_dependency_streams_for_target_with_shards<I, PI, DI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
) -> Result<PrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let state_lock = store.try_lock_build_state_for_target(target)?;
    let prepared_library_pages = prepare_schedule(libraries, &store, target, limits)?;
    drop(state_lock);
    prepare_library_pages_artifact_build_with_shards(
        prepared_library_pages,
        &store,
        limits,
        batch_limits,
        shard_limits,
        target,
    )
}

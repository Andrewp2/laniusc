use super::*;

pub fn prepare_pack_paths_metadata<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
) -> Result<FilesystemLibraryMetadataPrepareResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    prepare_pack_paths_metadata_for_target(
        stdlib_paths,
        user_paths,
        artifact_root,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_pack_path_stream_metadata<'a, SI, UI, P>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
) -> Result<FilesystemLibraryMetadataPrepareResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
{
    prepare_pack_path_stream_metadata_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_pack_path_stream_metadata_for_target<'a, SI, UI, P>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
) -> Result<FilesystemLibraryMetadataPrepareResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
{
    let has_stdlib_sources = stdlib_source_file_count != 0;
    let stdlib_library = has_stdlib_sources.then(|| ExplicitSourceLibraryPathDependencyStream {
        library_id: 0,
        source_file_count: stdlib_source_file_count,
        paths: Box::new(stdlib_paths.into_iter()) as Box<dyn Iterator<Item = P> + 'a>,
        dependency_library_count: 0,
        dependency_library_ids: Vec::new(),
    });
    let user_library = (user_source_file_count != 0).then(|| {
        let dependency_library_ids = if has_stdlib_sources {
            vec![0]
        } else {
            Vec::new()
        };
        ExplicitSourceLibraryPathDependencyStream {
            library_id: 1,
            source_file_count: user_source_file_count,
            paths: Box::new(user_paths.into_iter()) as Box<dyn Iterator<Item = P> + 'a>,
            dependency_library_count: dependency_library_ids.len(),
            dependency_library_ids,
        }
    });
    let libraries = stdlib_library.into_iter().chain(user_library);
    prepare_dependency_stream_metadata_for_target(libraries, artifact_root, target)
}

pub fn prepare_pack_paths_metadata_for_target<'a, SP, UP>(
    stdlib_paths: &'a [SP],
    user_paths: &'a [UP],
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
) -> Result<FilesystemLibraryMetadataPrepareResult, CompileError>
where
    SP: AsRef<Path> + 'a,
    UP: AsRef<Path> + 'a,
{
    prepare_pack_path_stream_metadata_for_target(
        stdlib_paths.len(),
        stdlib_paths.iter().map(|path| path.as_ref()),
        user_paths.len(),
        user_paths.iter().map(|path| path.as_ref()),
        artifact_root,
        target,
    )
}

pub fn prepare_ordered_library_path_metadata<I, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
) -> Result<FilesystemLibraryMetadataPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    prepare_ordered_library_path_metadata_for_target(
        libraries,
        artifact_root,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_ordered_library_path_metadata_for_target<I, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
) -> Result<FilesystemLibraryMetadataPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    let store = FilesystemArtifactStore::new(artifact_root);
    let dependency_streams = dependency_streams_from_library_paths(libraries);
    prepare_metadata(dependency_streams, &store, target)
}

pub fn prepare_dependency_stream_metadata<I, PI, DI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
) -> Result<FilesystemLibraryMetadataPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    prepare_dependency_stream_metadata_for_target(
        libraries,
        artifact_root,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_dependency_stream_metadata_for_target<I, PI, DI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
) -> Result<FilesystemLibraryMetadataPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    let store = FilesystemArtifactStore::new(artifact_root);
    prepare_metadata(libraries, &store, target)
}

pub fn prepare_metadata_chunk_for_target<I, PI, DI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    max_new_libraries: usize,
) -> Result<FilesystemLibraryMetadataPrepareStepResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    if max_new_libraries == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack metadata chunk max_new_libraries must be greater than zero".into(),
        ));
    }
    let max_new_libraries =
        max_new_libraries.min(SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_CHUNK_LIMIT);
    let store = FilesystemArtifactStore::new(artifact_root);
    prepare_metadata_chunk(libraries, &store, target, Some(max_new_libraries))
}

pub fn resume_metadata_chunk_for_target<I, PI, DI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    max_new_libraries: usize,
    manifest_complete_after_input: bool,
) -> Result<FilesystemLibraryMetadataPrepareStepResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    if max_new_libraries == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack metadata chunk max_new_libraries must be greater than zero".into(),
        ));
    }
    let max_new_libraries =
        max_new_libraries.min(SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_CHUNK_LIMIT);
    let store = FilesystemArtifactStore::new(artifact_root);
    resume_metadata_chunk(
        libraries,
        &store,
        target,
        max_new_libraries,
        manifest_complete_after_input,
    )
}

pub fn prepare_library_path_metadata<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    artifact_root: impl Into<PathBuf>,
) -> Result<FilesystemLibraryMetadataPrepareResult, CompileError>
where
    P: AsRef<Path>,
{
    prepare_library_path_metadata_for_target(
        libraries,
        artifact_root,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_library_path_metadata_for_target<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
) -> Result<FilesystemLibraryMetadataPrepareResult, CompileError>
where
    P: AsRef<Path>,
{
    let store = FilesystemArtifactStore::new(artifact_root);
    let ordered_libraries = ordered_dependency_streams_from_library_paths(libraries)?;
    prepare_metadata(ordered_libraries, &store, target)
}

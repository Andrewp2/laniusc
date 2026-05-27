use super::*;

pub fn load_explicit_source_pack_from_paths<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
) -> Result<Vec<String>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    Ok(load_explicit_source_pack_manifest_from_paths(stdlib_paths, user_paths)?.sources)
}

pub fn load_explicit_source_pack_manifest_from_paths<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
) -> Result<ExplicitSourcePack, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    let mut libraries = Vec::with_capacity(2);
    let stdlib_sources = read_explicit_source_paths("stdlib", stdlib_paths)?;
    let has_stdlib_sources = !stdlib_sources.is_empty();
    if !stdlib_sources.is_empty() {
        libraries.push(ExplicitSourceLibrary {
            library_id: 0,
            sources: stdlib_sources,
            dependency_library_ids: Vec::new(),
        });
    }
    let user_sources = read_explicit_source_paths("user", user_paths)?;
    if !user_sources.is_empty() {
        libraries.push(ExplicitSourceLibrary {
            library_id: 1,
            sources: user_sources,
            dependency_library_ids: if has_stdlib_sources {
                vec![0]
            } else {
                Vec::new()
            },
        });
    }
    ExplicitSourcePack::from_libraries(libraries)
}

pub fn load_explicit_source_pack_path_manifest_from_paths<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
) -> Result<ExplicitSourcePackPathManifest, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    let mut libraries = Vec::with_capacity(2);
    let has_stdlib_sources = !stdlib_paths.is_empty();
    if has_stdlib_sources {
        libraries.push(ExplicitSourceLibraryPaths {
            library_id: 0,
            paths: stdlib_paths
                .iter()
                .map(|path| path.as_ref().to_path_buf())
                .collect(),
            dependency_library_ids: Vec::new(),
        });
    }
    if !user_paths.is_empty() {
        libraries.push(ExplicitSourceLibraryPaths {
            library_id: 1,
            paths: user_paths
                .iter()
                .map(|path| path.as_ref().to_path_buf())
                .collect(),
            dependency_library_ids: if has_stdlib_sources {
                vec![0]
            } else {
                Vec::new()
            },
        });
    }
    ExplicitSourcePackPathManifest::from_libraries(libraries)
}

pub fn load_explicit_source_libraries_from_paths<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
) -> Result<ExplicitSourcePack, CompileError>
where
    P: AsRef<Path>,
{
    let mut source_libraries = Vec::with_capacity(libraries.len());
    for library in libraries {
        let label = format!("library {}", library.library_id);
        let sources = read_explicit_source_paths(&label, &library.paths)?;
        source_libraries.push(ExplicitSourceLibrary {
            library_id: library.library_id,
            sources,
            dependency_library_ids: library.dependency_library_ids,
        });
    }
    ExplicitSourcePack::from_libraries(source_libraries)
}

pub fn load_explicit_source_libraries_path_manifest<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
) -> Result<ExplicitSourcePackPathManifest, CompileError>
where
    P: AsRef<Path>,
{
    ExplicitSourcePackPathManifest::from_libraries(libraries)
}

pub(super) fn compact_manifest_from_dependency_streams<I, PI, DI, P>(
    libraries: I,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackBuildArtifactManifest, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    let mut plan_builder = SourcePackJobPlanBuilder::new(limits);
    let mut library_dependencies = Vec::new();
    let mut seen_library_ids = BTreeSet::new();
    let mut library_count = 0usize;
    let mut next_source_index = 0usize;

    for library in libraries {
        library_count = library_count.checked_add(1).ok_or_else(|| {
            CompileError::GpuFrontend("explicit source pack library count overflows".into())
        })?;
        if library.source_file_count == 0 {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {} has no source files",
                library.library_id
            )));
        }
        if !seen_library_ids.insert(library.library_id) {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {} appears more than once",
                library.library_id
            )));
        }

        let mut dependency_library_count = 0usize;
        let mut previous_dependency_library_id = None;
        for dependency_library_id in library.dependency_library_ids {
            if dependency_library_count >= library.dependency_library_count {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack library {} declares {} dependencies but provides at least {}",
                    library.library_id,
                    library.dependency_library_count,
                    dependency_library_count.saturating_add(1)
                )));
            }
            if dependency_library_id == library.library_id {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack library {} depends on itself",
                    library.library_id
                )));
            }
            if previous_dependency_library_id
                .is_some_and(|previous| dependency_library_id <= previous)
            {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack library {} dependency ids must be strictly sorted and unique",
                    library.library_id
                )));
            }
            if !seen_library_ids.contains(&dependency_library_id) {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack library {} depends on missing or later library {}",
                    library.library_id, dependency_library_id
                )));
            }
            library_dependencies.push(SourcePackLibraryDependency {
                library_id: library.library_id,
                depends_on_library_id: dependency_library_id,
            });
            previous_dependency_library_id = Some(dependency_library_id);
            dependency_library_count = dependency_library_count.saturating_add(1);
        }
        if dependency_library_count != library.dependency_library_count {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {} declares {} dependencies but provides {}",
                library.library_id, library.dependency_library_count, dependency_library_count
            )));
        }

        let label = format!("library {}", library.library_id);
        let mut stored_source_file_count = 0usize;
        for (path_index, path) in library.paths.into_iter().enumerate() {
            if path_index >= library.source_file_count {
                return Err(CompileError::GpuFrontend(format!(
                    "explicit source pack library {} declares {} source files but provides at least {}",
                    library.library_id,
                    library.source_file_count,
                    path_index + 1
                )));
            }
            let source_index = next_source_index;
            next_source_index = next_source_index.checked_add(1).ok_or_else(|| {
                CompileError::GpuFrontend("explicit source pack source index overflows".into())
            })?;
            let file = read_explicit_source_path_metadata(
                &label,
                path_index,
                library.library_id,
                path.as_ref(),
            )?;
            plan_builder.push(SourceFileUnitInput {
                library_id: library.library_id,
                source_index,
                byte_len: file.byte_len,
                line_count: file.line_count.unwrap_or(0),
            });
            stored_source_file_count += 1;
        }
        if stored_source_file_count != library.source_file_count {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {} provides {} source files but declares {}",
                library.library_id, stored_source_file_count, library.source_file_count
            )));
        }
    }
    if library_count == 0 {
        return Err(CompileError::GpuFrontend(
            "explicit source pack has no source files".into(),
        ));
    }

    let plan = plan_builder.finish(&library_dependencies);
    let schedule = plan.bounded_frontend_job_schedule();
    plan.try_compact_build_artifact_manifest_for_schedule(&schedule, batch_limits, target)
        .map_err(source_pack_schedule_error)
}

pub fn plan_explicit_source_pack_path_streams_compact_artifact_manifest_from_path_metadata<
    'a,
    SI,
    UI,
    P,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackBuildArtifactManifest, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
{
    plan_explicit_source_pack_path_streams_compact_artifact_manifest_from_path_metadata_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn plan_explicit_source_pack_path_streams_compact_artifact_manifest_from_path_metadata_for_target<
    'a,
    SI,
    UI,
    P,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackBuildArtifactManifest, CompileError>
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
    compact_manifest_from_dependency_streams(libraries, limits, batch_limits, target)
}

pub fn plan_ordered_explicit_source_library_path_streams_compact_artifact_manifest_from_path_metadata<
    I,
    PI,
    P,
>(
    libraries: I,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackBuildArtifactManifest, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    plan_ordered_explicit_source_library_path_streams_compact_artifact_manifest_from_path_metadata_for_target(
        libraries,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn plan_ordered_explicit_source_library_path_streams_compact_artifact_manifest_from_path_metadata_for_target<
    I,
    PI,
    P,
>(
    libraries: I,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackBuildArtifactManifest, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    let dependency_streams = dependency_streams_from_path_streams(libraries);
    compact_manifest_from_dependency_streams(dependency_streams, limits, batch_limits, target)
}

pub fn plan_ordered_explicit_source_library_path_dependency_streams_compact_artifact_manifest_from_path_metadata<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackBuildArtifactManifest, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    plan_ordered_explicit_source_library_path_dependency_streams_compact_artifact_manifest_from_path_metadata_for_target(
        libraries,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn plan_ordered_explicit_source_library_path_dependency_streams_compact_artifact_manifest_from_path_metadata_for_target<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackBuildArtifactManifest, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    compact_manifest_from_dependency_streams(libraries, limits, batch_limits, target)
}

pub fn plan_explicit_source_pack_jobs_from_paths<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    limits: CodegenUnitLimits,
) -> Result<SourcePackJobPlan, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    plan_explicit_source_pack_jobs_from_path_metadata(stdlib_paths, user_paths, limits)
}

pub fn plan_explicit_source_pack_jobs_from_path_metadata<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    limits: CodegenUnitLimits,
) -> Result<SourcePackJobPlan, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    Ok(
        load_explicit_source_pack_path_manifest_from_paths(stdlib_paths, user_paths)?
            .job_plan(limits),
    )
}

pub fn plan_explicit_source_libraries_jobs_from_paths<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    limits: CodegenUnitLimits,
) -> Result<SourcePackJobPlan, CompileError>
where
    P: AsRef<Path>,
{
    plan_explicit_source_libraries_jobs_from_path_metadata(libraries, limits)
}

pub fn plan_explicit_source_libraries_jobs_from_path_metadata<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    limits: CodegenUnitLimits,
) -> Result<SourcePackJobPlan, CompileError>
where
    P: AsRef<Path>,
{
    Ok(load_explicit_source_libraries_path_manifest(libraries)?.job_plan(limits))
}

pub fn plan_explicit_source_pack_build_from_paths<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    limits: CodegenUnitLimits,
) -> Result<SourcePackBuildPlan, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    plan_explicit_source_pack_build_from_path_metadata(stdlib_paths, user_paths, limits)
}

pub fn plan_explicit_source_pack_build_from_path_metadata<SP, UP>(
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
            .build_plan(limits),
    )
}

pub fn plan_explicit_source_pack_bounded_frontend_build_from_paths<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    limits: CodegenUnitLimits,
) -> Result<SourcePackBuildPlan, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    plan_explicit_source_pack_bounded_frontend_build_from_path_metadata(
        stdlib_paths,
        user_paths,
        limits,
    )
}

pub fn plan_explicit_source_pack_bounded_frontend_build_from_path_metadata<SP, UP>(
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

pub fn plan_explicit_source_pack_compact_artifact_manifest_from_paths<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackBuildArtifactManifest, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    plan_explicit_source_pack_compact_artifact_manifest_from_path_metadata(
        stdlib_paths,
        user_paths,
        limits,
        batch_limits,
    )
}

pub fn plan_explicit_source_pack_compact_artifact_manifest_from_path_metadata<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackBuildArtifactManifest, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    plan_explicit_source_pack_path_streams_compact_artifact_manifest_from_path_metadata(
        stdlib_paths.len(),
        stdlib_paths.iter().map(|path| path.as_ref()),
        user_paths.len(),
        user_paths.iter().map(|path| path.as_ref()),
        limits,
        batch_limits,
    )
}

pub fn plan_explicit_source_libraries_build_from_paths<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    limits: CodegenUnitLimits,
) -> Result<SourcePackBuildPlan, CompileError>
where
    P: AsRef<Path>,
{
    plan_explicit_source_libraries_build_from_path_metadata(libraries, limits)
}

pub fn plan_explicit_source_libraries_build_from_path_metadata<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    limits: CodegenUnitLimits,
) -> Result<SourcePackBuildPlan, CompileError>
where
    P: AsRef<Path>,
{
    Ok(load_explicit_source_libraries_path_manifest(libraries)?.build_plan(limits))
}

pub fn plan_explicit_source_libraries_bounded_frontend_build_from_paths<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    limits: CodegenUnitLimits,
) -> Result<SourcePackBuildPlan, CompileError>
where
    P: AsRef<Path>,
{
    plan_explicit_source_libraries_bounded_frontend_build_from_path_metadata(libraries, limits)
}

pub fn plan_explicit_source_libraries_bounded_frontend_build_from_path_metadata<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    limits: CodegenUnitLimits,
) -> Result<SourcePackBuildPlan, CompileError>
where
    P: AsRef<Path>,
{
    Ok(
        load_explicit_source_libraries_path_manifest(libraries)?
            .bounded_frontend_build_plan(limits),
    )
}

pub fn plan_explicit_source_libraries_compact_artifact_manifest_from_paths<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackBuildArtifactManifest, CompileError>
where
    P: AsRef<Path>,
{
    plan_explicit_source_libraries_compact_artifact_manifest_from_path_metadata(
        libraries,
        limits,
        batch_limits,
    )
}

pub fn plan_explicit_source_libraries_compact_artifact_manifest_from_path_metadata<P>(
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

pub fn execute_explicit_source_pack_paths_artifact_store_build<SP, UP, E, S>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
    store: &mut S,
) -> Result<SourcePackArtifactStoreBuildExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
    E: SourcePackPathArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore,
{
    load_explicit_source_pack_path_manifest_from_paths(stdlib_paths, user_paths)?
        .execute_build_plan_with_artifact_store(limits, batch_limits, executor, store)
}

pub fn prepare_explicit_source_pack_path_streams_filesystem_artifact_build<'a, SI, UI, P>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
{
    prepare_explicit_source_pack_path_streams_filesystem_artifact_build_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits<
    'a,
    SI,
    UI,
    P,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
{
    prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_explicit_source_pack_path_streams_filesystem_artifact_build_for_target<
    'a,
    SI,
    UI,
    P,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
{
    prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
    )
}

pub fn prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target<
    'a,
    SI,
    UI,
    P,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
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
    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
    )
}

pub fn prepare_explicit_source_pack_paths_filesystem_artifact_build<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    prepare_explicit_source_pack_paths_filesystem_artifact_build_for_target(
        stdlib_paths,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_explicit_source_pack_paths_filesystem_artifact_build_with_shard_limits<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    prepare_explicit_source_pack_paths_filesystem_artifact_build_with_shard_limits_for_target(
        stdlib_paths,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_explicit_source_pack_paths_filesystem_artifact_build_for_target<'a, SP, UP>(
    stdlib_paths: &'a [SP],
    user_paths: &'a [UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    SP: AsRef<Path> + 'a,
    UP: AsRef<Path> + 'a,
{
    prepare_explicit_source_pack_paths_filesystem_artifact_build_with_shard_limits_for_target(
        stdlib_paths,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
    )
}

pub fn prepare_explicit_source_pack_paths_filesystem_artifact_build_with_shard_limits_for_target<
    'a,
    SP,
    UP,
>(
    stdlib_paths: &'a [SP],
    user_paths: &'a [UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    SP: AsRef<Path> + 'a,
    UP: AsRef<Path> + 'a,
{
    prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target(
        stdlib_paths.len(),
        stdlib_paths.iter().map(|path| path.as_ref()),
        user_paths.len(),
        user_paths.iter().map(|path| path.as_ref()),
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
    )
}

pub fn execute_explicit_source_pack_paths_filesystem_artifact_build<SP, UP, E>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_explicit_source_pack_paths_filesystem_artifact_build_for_target(
        stdlib_paths,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build<'a, SI, UI, P, E>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_explicit_source_pack_path_streams_filesystem_artifact_build_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits<
    'a,
    SI,
    UI,
    P,
    E,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_for_target<
    'a,
    SI,
    UI,
    P,
    E,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        executor,
    )
}

pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_for_target<
    'a,
    SI,
    UI,
    P,
    E,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
}

pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target<
    'a,
    SI,
    UI,
    P,
    E,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    prepare_explicit_source_pack_path_streams_filesystem_artifact_build_with_shard_limits_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        &artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
    )?;
    execute_source_pack_filesystem_artifact_manifest_build_for_target(
        artifact_root,
        target,
        executor,
    )
}

pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target<
    'a,
    SI,
    UI,
    P,
    E,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let prepare_chunk_limit = source_pack_limit_artifact_worker_run_batches(max_batches).max(1);
    let prepared =
        prepare_explicit_source_pack_path_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(
            stdlib_source_file_count,
            stdlib_paths,
            user_source_file_count,
            user_paths,
            &artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            prepare_chunk_limit,
        )?;
    if !prepared {
        return Err(
            source_pack_work_queue_not_prepared_after_bounded_chunk_error(
                target,
                prepare_chunk_limit,
            ),
        );
    }
    execute_source_pack_filesystem_artifact_manifest_worker_run_for_target(
        artifact_root,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
}

pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_with_path_artifacts_for_target<
    'a,
    SI,
    UI,
    P,
    E,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
}

pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target<
    'a,
    SI,
    UI,
    P,
    E,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let prepare_chunk_limit = source_pack_limit_artifact_worker_run_batches(max_batches).max(1);
    let prepared =
        prepare_explicit_source_pack_path_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(
            stdlib_source_file_count,
            stdlib_paths,
            user_source_file_count,
            user_paths,
            &artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            prepare_chunk_limit,
        )?;
    if !prepared {
        return Err(
            source_pack_work_queue_not_prepared_after_bounded_chunk_error(
                target,
                prepare_chunk_limit,
            ),
        );
    }
    execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target(
        artifact_root,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
}

pub async fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target<
    'a,
    SI,
    UI,
    P,
    E,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
    .await
}

pub async fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target<
    'a,
    SI,
    UI,
    P,
    E,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let prepare_chunk_limit = source_pack_limit_work_queue_worker_run_items(max_items).max(1);
    let prepared =
        prepare_explicit_source_pack_path_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(
            stdlib_source_file_count,
            stdlib_paths,
            user_source_file_count,
            user_paths,
            &artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            prepare_chunk_limit,
        )?;
    if !prepared {
        return Err(
            source_pack_work_queue_not_prepared_after_bounded_chunk_error(
                target,
                prepare_chunk_limit,
            ),
        );
    }
    execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target(
        artifact_root,
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
    .await
}

pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target<
    'a,
    SP,
    UP,
    E,
>(
    stdlib_paths: &'a [SP],
    user_paths: &'a [UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    SP: AsRef<Path> + 'a,
    UP: AsRef<Path> + 'a,
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target(
        stdlib_paths,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
    .await
}

pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target<
    'a,
    SP,
    UP,
    E,
>(
    stdlib_paths: &'a [SP],
    user_paths: &'a [UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    SP: AsRef<Path> + 'a,
    UP: AsRef<Path> + 'a,
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target(
        stdlib_paths.len(),
        stdlib_paths.iter().map(|path| path.as_ref()),
        user_paths.len(),
        user_paths.iter().map(|path| path.as_ref()),
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
    .await
}

pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_with_shard_limits<SP, UP, E>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_explicit_source_pack_paths_filesystem_artifact_build_with_shard_limits_for_target(
        stdlib_paths,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_for_target<SP, UP, E>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_explicit_source_pack_paths_filesystem_artifact_build_with_shard_limits_for_target(
        stdlib_paths,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        executor,
    )
}

pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_with_shard_limits_for_target<
    SP,
    UP,
    E,
>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    prepare_explicit_source_pack_paths_filesystem_artifact_build_with_shard_limits_for_target(
        stdlib_paths,
        user_paths,
        &artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
    )?;
    execute_source_pack_filesystem_artifact_manifest_build_for_target(
        artifact_root,
        target,
        executor,
    )
}

pub fn execute_explicit_source_libraries_artifact_store_build<P, E, S>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
    store: &mut S,
) -> Result<SourcePackArtifactStoreBuildExecutionResult, CompileError>
where
    P: AsRef<Path>,
    E: SourcePackPathArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore,
{
    load_explicit_source_libraries_path_manifest(libraries)?.execute_build_plan_with_artifact_store(
        limits,
        batch_limits,
        executor,
        store,
    )
}

pub fn prepare_explicit_source_libraries_filesystem_artifact_build<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    P: AsRef<Path>,
{
    prepare_explicit_source_libraries_filesystem_artifact_build_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_explicit_source_libraries_filesystem_artifact_build_for_target<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    P: AsRef<Path>,
{
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let state_lock = store.try_lock_build_state_for_target(target)?;
    let ordered_libraries = ordered_dependency_streams_from_library_paths(libraries)?;
    let prepared_library_pages =
        prepare_library_schedule_pages(ordered_libraries, &store, target, limits)?;
    drop(state_lock);
    prepare_explicit_source_prepared_library_pages_filesystem_artifact_build_for_target(
        prepared_library_pages,
        &store,
        limits,
        batch_limits,
        target,
    )
}

pub fn prepare_ordered_explicit_source_libraries_filesystem_artifact_build<I, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    prepare_ordered_explicit_source_libraries_filesystem_artifact_build_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits<I, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    prepare_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_ordered_explicit_source_libraries_filesystem_artifact_build_for_target<I, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    prepare_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
    )
}

pub fn prepare_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target<
    I,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let state_lock = store.try_lock_build_state_for_target(target)?;
    let dependency_streams = dependency_streams_from_library_paths(libraries);
    let prepared_library_pages =
        prepare_library_schedule_pages(dependency_streams, &store, target, limits)?;
    drop(state_lock);
    prepare_explicit_source_prepared_library_pages_filesystem_artifact_build_with_shard_limits_for_target(
        prepared_library_pages,
        &store,
        limits,
        batch_limits,
        shard_limits,
        target,
    )
}

pub fn prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build<I, PI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits<
    I,
    PI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_for_target<
    I,
    PI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
    )
}

pub fn prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target<
    I,
    PI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let state_lock = store.try_lock_build_state_for_target(target)?;
    let dependency_streams = dependency_streams_from_path_streams(libraries);
    let prepared_library_pages =
        prepare_library_schedule_pages(dependency_streams, &store, target, limits)?;
    drop(state_lock);
    prepare_explicit_source_prepared_library_pages_filesystem_artifact_build_with_shard_limits_for_target(
        prepared_library_pages,
        &store,
        limits,
        batch_limits,
        shard_limits,
        target,
    )
}

pub fn prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_for_target<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
    )
}

pub fn prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let state_lock = store.try_lock_build_state_for_target(target)?;
    let prepared_library_pages = prepare_library_schedule_pages(libraries, &store, target, limits)?;
    drop(state_lock);
    prepare_explicit_source_prepared_library_pages_filesystem_artifact_build_with_shard_limits_for_target(
        prepared_library_pages,
        &store,
        limits,
        batch_limits,
        shard_limits,
        target,
    )
}

pub fn prepare_explicit_source_pack_paths_filesystem_metadata<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
) -> Result<SourcePackFilesystemLibraryMetadataPrepareResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    prepare_explicit_source_pack_paths_filesystem_metadata_for_target(
        stdlib_paths,
        user_paths,
        artifact_root,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_explicit_source_pack_path_streams_filesystem_metadata<'a, SI, UI, P>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
) -> Result<SourcePackFilesystemLibraryMetadataPrepareResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
{
    prepare_explicit_source_pack_path_streams_filesystem_metadata_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_explicit_source_pack_path_streams_filesystem_metadata_for_target<'a, SI, UI, P>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemLibraryMetadataPrepareResult, CompileError>
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
    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
        libraries,
        artifact_root,
        target,
    )
}

pub fn prepare_explicit_source_pack_paths_filesystem_metadata_for_target<'a, SP, UP>(
    stdlib_paths: &'a [SP],
    user_paths: &'a [UP],
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemLibraryMetadataPrepareResult, CompileError>
where
    SP: AsRef<Path> + 'a,
    UP: AsRef<Path> + 'a,
{
    prepare_explicit_source_pack_path_streams_filesystem_metadata_for_target(
        stdlib_paths.len(),
        stdlib_paths.iter().map(|path| path.as_ref()),
        user_paths.len(),
        user_paths.iter().map(|path| path.as_ref()),
        artifact_root,
        target,
    )
}

pub fn prepare_ordered_explicit_source_libraries_filesystem_metadata<I, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
) -> Result<SourcePackFilesystemLibraryMetadataPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    prepare_ordered_explicit_source_libraries_filesystem_metadata_for_target(
        libraries,
        artifact_root,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_ordered_explicit_source_libraries_filesystem_metadata_for_target<I, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemLibraryMetadataPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    let store = SourcePackFilesystemArtifactStore::new(artifact_root);
    let dependency_streams = dependency_streams_from_library_paths(libraries);
    prepare_library_metadata_pages(dependency_streams, &store, target)
}

pub fn prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
) -> Result<SourcePackFilesystemLibraryMetadataPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target(
        libraries,
        artifact_root,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_for_target<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemLibraryMetadataPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    let store = SourcePackFilesystemArtifactStore::new(artifact_root);
    prepare_library_metadata_pages(libraries, &store, target)
}

pub fn prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_for_target<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    max_new_libraries: usize,
) -> Result<SourcePackFilesystemLibraryMetadataPrepareStepResult, CompileError>
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
    let store = SourcePackFilesystemArtifactStore::new(artifact_root);
    prepare_library_metadata_pages_chunk(libraries, &store, target, Some(max_new_libraries))
}

pub fn prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_from_progress_for_target<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    max_new_libraries: usize,
    manifest_complete_after_input: bool,
) -> Result<SourcePackFilesystemLibraryMetadataPrepareStepResult, CompileError>
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
    let store = SourcePackFilesystemArtifactStore::new(artifact_root);
    resume_library_metadata_pages_chunk(
        libraries,
        &store,
        target,
        max_new_libraries,
        manifest_complete_after_input,
    )
}

pub fn prepare_explicit_source_libraries_filesystem_metadata<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    artifact_root: impl Into<PathBuf>,
) -> Result<SourcePackFilesystemLibraryMetadataPrepareResult, CompileError>
where
    P: AsRef<Path>,
{
    prepare_explicit_source_libraries_filesystem_metadata_for_target(
        libraries,
        artifact_root,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_explicit_source_libraries_filesystem_metadata_for_target<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemLibraryMetadataPrepareResult, CompileError>
where
    P: AsRef<Path>,
{
    let store = SourcePackFilesystemArtifactStore::new(artifact_root);
    let ordered_libraries = ordered_dependency_streams_from_library_paths(libraries)?;
    prepare_library_metadata_pages(ordered_libraries, &store, target)
}

pub fn prepare_source_pack_filesystem_artifact_build_from_metadata(
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError> {
    prepare_source_pack_filesystem_artifact_build_from_metadata_for_target(
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_source_pack_filesystem_artifact_build_from_metadata_for_target(
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError> {
    prepare_source_pack_filesystem_artifact_build_from_metadata_with_shard_limits_for_target(
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
    )
}

pub fn prepare_source_pack_filesystem_library_schedule_from_metadata_chunk_for_target(
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    target: SourcePackArtifactTarget,
    max_new_libraries: usize,
) -> Result<SourcePackFilesystemLibrarySchedulePrepareStepResult, CompileError> {
    let max_new_libraries =
        max_new_libraries.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    prepare_library_schedule_pages_from_metadata_chunk(&store, target, limits, max_new_libraries)
}

pub fn prepare_source_pack_filesystem_artifact_refs_from_schedule_chunk_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    max_new_libraries: usize,
) -> Result<SourcePackFilesystemArtifactRefPrepareStepResult, CompileError> {
    let max_new_libraries =
        max_new_libraries.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store.load_library_schedule_index_for_target(target)?;
    store_source_pack_build_artifact_ref_pages_from_stored_schedule_pages_chunk(
        &store,
        &schedule_index,
        max_new_libraries,
    )
}

pub fn prepare_source_pack_filesystem_job_batches_from_schedule_chunk_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    batch_limits: SourcePackJobBatchLimits,
    max_new_batches: usize,
) -> Result<SourcePackFilesystemJobBatchPrepareStepResult, CompileError> {
    let max_new_batches =
        max_new_batches.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store.load_library_schedule_index_for_target(target)?;
    store_source_pack_build_job_batch_pages_from_stored_schedule_pages_chunk(
        &store,
        &schedule_index,
        batch_limits,
        max_new_batches,
    )
}

pub fn prepare_source_pack_filesystem_job_batch_dependents_from_batches_chunk_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    max_new_batches: usize,
) -> Result<SourcePackFilesystemJobBatchDependentsPrepareStepResult, CompileError> {
    let max_new_batches =
        max_new_batches.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let job_batch_index = store.load_build_job_batch_page_index_for_target(target)?;
    store_source_pack_job_batch_dependents_pages_from_stored_job_batch_pages_chunk(
        &store,
        target,
        &job_batch_index,
        max_new_batches,
    )
}

pub fn prepare_source_pack_filesystem_artifact_shards_from_batches_chunk_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    shard_limits: SourcePackBuildShardLimits,
    max_new_batches: usize,
) -> Result<SourcePackFilesystemArtifactShardPrepareStepResult, CompileError> {
    let max_new_batches =
        max_new_batches.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let library_partition_index = store.load_library_partition_index_for_target(target)?;
    let schedule_index = store.load_library_schedule_index_for_target(target)?;
    let artifact_ref_index = store.load_build_artifact_ref_index_for_target(target)?;
    let job_batch_page_index = store.load_build_job_batch_page_index_for_target(target)?;
    let link_batch_page_index = store.load_build_link_batch_page_index_for_target(target)?;
    store_source_pack_build_artifact_shards_from_page_metadata_chunk(
        &store,
        target,
        shard_limits,
        &schedule_index,
        &artifact_ref_index,
        &job_batch_page_index,
        &link_batch_page_index,
        &library_partition_index,
        max_new_batches,
    )
}

pub fn prepare_source_pack_filesystem_link_batches_from_artifact_refs_chunk_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    batch_limits: SourcePackJobBatchLimits,
    max_new_batches: usize,
) -> Result<SourcePackFilesystemLinkBatchPrepareStepResult, CompileError> {
    let max_new_batches =
        max_new_batches.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store.load_library_schedule_index_for_target(target)?;
    let artifact_ref_index = store.load_build_artifact_ref_index_for_target(target)?;
    store_source_pack_build_link_batch_pages_from_stored_artifact_ref_pages_chunk(
        &store,
        target,
        &schedule_index,
        &artifact_ref_index,
        batch_limits,
        max_new_batches,
    )
}

pub fn prepare_source_pack_filesystem_hierarchical_link_leaf_groups_from_schedule_chunk_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    batch_limits: SourcePackJobBatchLimits,
    max_new_partitions: usize,
) -> Result<SourcePackFilesystemHierarchicalLinkLeafPrepareStepResult, CompileError> {
    let max_new_partitions =
        max_new_partitions.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store.load_library_schedule_index_for_target(target)?;
    store_source_pack_hierarchical_link_leaf_groups_from_stored_schedule_pages_chunk(
        &store,
        &schedule_index,
        batch_limits,
        max_new_partitions,
    )
}

pub fn prepare_source_pack_filesystem_hierarchical_link_plan_reduce_groups_from_schedule_chunk_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    batch_limits: SourcePackJobBatchLimits,
    max_new_reduce_groups: usize,
) -> Result<SourcePackFilesystemHierarchicalLinkPlanPrepareStepResult, CompileError> {
    let max_new_reduce_groups = max_new_reduce_groups
        .min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store.load_library_schedule_index_for_target(target)?;
    store_source_pack_hierarchical_link_reduce_groups_from_stored_leaf_groups_chunk(
        &store,
        &schedule_index,
        batch_limits,
        max_new_reduce_groups,
    )
}

pub fn prepare_source_pack_filesystem_hierarchical_link_execution_from_plan_chunk_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    max_new_groups: usize,
) -> Result<SourcePackFilesystemHierarchicalLinkExecutionPrepareStepResult, CompileError> {
    let max_new_groups =
        max_new_groups.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store.load_library_schedule_index_for_target(target)?;
    let artifact_ref_index = store.load_build_artifact_ref_index_for_target(target)?;
    let link_plan_index = store.load_hierarchical_link_plan_index_for_target(target)?;
    store_source_pack_hierarchical_link_execution_from_stored_schedule_pages_chunk(
        &store,
        &link_plan_index,
        &schedule_index,
        &artifact_ref_index,
        max_new_groups,
    )
}

pub fn prepare_source_pack_filesystem_work_queue_pages_from_schedule_chunk_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    max_new_items: usize,
) -> Result<SourcePackFilesystemWorkQueuePrepareStepResult, CompileError> {
    let max_new_items =
        max_new_items.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store.load_library_schedule_index_for_target(target)?;
    let link_plan_index = store.load_hierarchical_link_plan_index_for_target(target)?;
    store_source_pack_work_queue_pages_from_stored_schedule_pages_chunk(
        &store,
        &schedule_index,
        &link_plan_index,
        max_new_items,
    )
}

pub fn prepare_source_pack_filesystem_work_queue_progress_from_queue_chunk_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    page_size: usize,
    max_new_pages: usize,
) -> Result<SourcePackFilesystemWorkQueueProgressPrepareStepResult, CompileError> {
    let max_new_pages =
        max_new_pages.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let work_queue_index = store.load_work_queue_index_for_target(target)?;
    store_initial_work_queue_progress_from_stored_work_queue_pages_chunk(
        &store,
        &work_queue_index,
        page_size,
        max_new_pages,
    )
}

pub(super) fn source_pack_filesystem_artifact_prepare_result_from_stored_indexes(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError> {
    let library_partition_index = store.load_library_partition_index_for_target(target)?;
    let library_schedule_index = store.load_library_schedule_index_for_target(target)?;
    let artifact_ref_index = store.load_build_artifact_ref_index_for_target(target)?;
    let job_batch_page_index = store.load_build_job_batch_page_index_for_target(target)?;
    let artifact_shard_index = store.load_build_artifact_shard_index_for_target(target)?;
    let hierarchical_link_plan_index =
        store.load_hierarchical_link_plan_index_for_target(target)?;
    let hierarchical_link_execution_index =
        store.load_hierarchical_link_execution_index_for_target(target)?;
    let work_queue_index = store.load_work_queue_index_for_target(target)?;
    let work_queue_progress_index = store.load_work_queue_progress_index_for_target(target)?;
    let build_progress_summary = store.load_build_progress_summary_for_target(target)?;
    let build_manifest = store.load_path_build_manifest_for_target(target)?;
    let artifact_manifest = store.load_build_artifact_manifest_for_target(target)?;
    validate_source_pack_path_build_manifest_versions(&build_manifest)?;
    validate_source_pack_build_artifact_manifest(&artifact_manifest)?;
    if build_manifest.artifacts.target != target || artifact_manifest.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "stored build manifests target {:?}/{:?} do not match requested target {:?}",
            build_manifest.artifacts.target, artifact_manifest.target, target
        )));
    }
    if artifact_manifest.artifact_count != artifact_ref_index.artifact_count
        || artifact_manifest.job_batch_count != job_batch_page_index.batch_count
        || artifact_manifest.job_count != library_schedule_index.job_count
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "stored artifact manifest jobs/batches/artifacts {}/{}/{} do not match indexes {}/{}/{}",
            artifact_manifest.job_count,
            artifact_manifest.job_batch_count,
            artifact_manifest.artifact_count,
            library_schedule_index.job_count,
            job_batch_page_index.batch_count,
            artifact_ref_index.artifact_count
        )));
    }
    let build_state_path = store.build_state_path_for_target(target);
    if !build_state_path.is_file() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "prepared source-pack build state is missing at {}",
            build_state_path.display()
        )));
    }
    Ok(SourcePackFilesystemArtifactPrepareResult {
        target,
        artifact_root: store.root().to_path_buf(),
        source_file_count: library_partition_index.source_file_count,
        source_byte_count: library_partition_index.source_byte_count,
        source_line_count: library_partition_index.source_line_count,
        library_count: library_partition_index.partition_count,
        artifact_count: artifact_ref_index.artifact_count,
        scheduled_job_count: library_schedule_index.job_count,
        batch_count: job_batch_page_index.batch_count,
        initial_ready_batch_count: build_progress_summary.ready_batch_count,
        first_ready_batch_index: build_progress_summary.first_ready_batch_index,
        build_manifest_path: store.build_manifest_path_for_target(target),
        library_partition_index_path: store.library_partition_index_path_for_target(target),
        library_partition_count: library_partition_index.partition_count,
        library_source_file_page_count: library_partition_index.partition_count,
        library_build_unit_page_count: library_schedule_index.partition_count,
        library_schedule_index_path: store.library_schedule_index_path_for_target(target),
        library_schedule_page_count: library_schedule_index.partition_count,
        hierarchical_link_plan_index_path: store
            .hierarchical_link_plan_index_path_for_target(target),
        hierarchical_link_group_count: hierarchical_link_plan_index.link_group_count,
        hierarchical_link_execution_index_path: store
            .hierarchical_link_execution_index_path_for_target(target),
        hierarchical_link_execution_group_count: hierarchical_link_execution_index.link_group_count,
        work_queue_index_path: store.work_queue_index_path_for_target(target),
        work_queue_item_count: work_queue_index.work_item_count,
        work_queue_progress_index_path: store.work_queue_progress_index_path_for_target(target),
        work_queue_progress_page_count: work_queue_progress_index.page_count,
        initial_ready_work_item_count: work_queue_progress_index.ready_item_count,
        first_ready_work_item_index: work_queue_progress_index.first_ready_item_index,
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        artifact_shard_index_path: store.artifact_shard_index_path_for_target(target),
        artifact_shard_count: artifact_shard_index.shard_count(),
        build_state_path,
    })
}

pub(super) fn source_pack_store_compact_build_manifests_from_stored_indexes(
    store: &SourcePackFilesystemArtifactStore,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<(PathBuf, PathBuf), CompileError> {
    let library_partition_index = store.load_library_partition_index_for_target(target)?;
    let library_schedule_index = store.load_library_schedule_index_for_target(target)?;
    let artifact_ref_index = store.load_build_artifact_ref_index_for_target(target)?;
    let job_batch_page_index = store.load_build_job_batch_page_index_for_target(target)?;
    let link_batch_page_index = store.load_build_link_batch_page_index_for_target(target)?;
    let path_build_manifest = source_pack_compact_path_build_manifest_from_stored_indexes(
        limits,
        batch_limits,
        target,
        &library_schedule_index,
        &artifact_ref_index,
        &job_batch_page_index,
        &link_batch_page_index,
        library_partition_index.source_file_count,
        library_partition_index.source_byte_count,
        library_partition_index.source_line_count,
    );
    let artifact_manifest_path =
        store.store_build_artifact_manifest(&path_build_manifest.artifacts)?;
    let build_manifest_path = store.store_compact_path_build_manifest(&path_build_manifest)?;
    Ok((build_manifest_path, artifact_manifest_path))
}

pub(super) fn source_pack_job_batch_dependents_complete_for_target(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_count: usize,
) -> Result<bool, CompileError> {
    let path = store.build_job_batch_dependents_prepare_progress_path_for_target(target);
    if !path.is_file() {
        return Ok(false);
    }
    let progress =
        source_pack_load_job_batch_dependents_prepare_progress(store, target, batch_count)?;
    Ok(progress.next_batch_index == batch_count)
}

pub(super) fn source_pack_hierarchical_link_leaf_groups_complete_for_target(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<bool, CompileError> {
    let progress_path =
        store.hierarchical_link_plan_prepare_progress_path_for_target(schedule_index.target);
    if !progress_path.is_file() {
        return Ok(false);
    }
    let progress = source_pack_load_hierarchical_link_plan_prepare_progress(
        store,
        schedule_index.target,
        schedule_index.partition_count,
        batch_limits.normalized(),
    )?;
    Ok(progress.next_partition_index == schedule_index.partition_count)
}

pub(super) fn source_pack_artifact_build_prepare_step_result(
    target: SourcePackArtifactTarget,
    stage: SourcePackFilesystemArtifactBuildPrepareStage,
    next_stage: SourcePackFilesystemArtifactBuildPrepareStage,
    new_item_count: usize,
) -> SourcePackFilesystemArtifactBuildPrepareStepResult {
    SourcePackFilesystemArtifactBuildPrepareStepResult {
        target,
        complete: false,
        stage,
        next_stage,
        new_item_count,
        prepared: None,
    }
}

pub fn prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target(
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    max_new_items: usize,
) -> Result<SourcePackFilesystemArtifactBuildPrepareStepResult, CompileError> {
    if max_new_items == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack artifact build chunk max_new_items must be greater than zero".into(),
        ));
    }
    let max_new_items =
        max_new_items.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let _state_lock = store.try_lock_build_state_for_target(target)?;
    if store.build_state_path_for_target(target).is_file() {
        let prepared =
            source_pack_filesystem_artifact_prepare_result_from_stored_indexes(&store, target)?;
        return Ok(SourcePackFilesystemArtifactBuildPrepareStepResult {
            target,
            complete: true,
            stage: SourcePackFilesystemArtifactBuildPrepareStage::Complete,
            next_stage: SourcePackFilesystemArtifactBuildPrepareStage::Complete,
            new_item_count: 0,
            prepared: Some(prepared),
        });
    }

    if !store
        .library_schedule_job_locator_index_path_for_target(target)
        .is_file()
    {
        let step = prepare_library_schedule_pages_from_metadata_chunk(
            &store,
            target,
            limits,
            max_new_items,
        )?;
        return Ok(source_pack_artifact_build_prepare_step_result(
            target,
            SourcePackFilesystemArtifactBuildPrepareStage::LibrarySchedule,
            if step.complete {
                SourcePackFilesystemArtifactBuildPrepareStage::ArtifactRefs
            } else {
                SourcePackFilesystemArtifactBuildPrepareStage::LibrarySchedule
            },
            step.new_library_build_unit_page_count
                .saturating_add(step.new_library_schedule_page_count),
        ));
    }
    let schedule_index = store.load_library_schedule_index_for_target(target)?;

    if !store
        .build_artifact_ref_index_path_for_target(target)
        .is_file()
    {
        let step = store_source_pack_build_artifact_ref_pages_from_stored_schedule_pages_chunk(
            &store,
            &schedule_index,
            max_new_items,
        )?;
        return Ok(source_pack_artifact_build_prepare_step_result(
            target,
            SourcePackFilesystemArtifactBuildPrepareStage::ArtifactRefs,
            if step.complete {
                SourcePackFilesystemArtifactBuildPrepareStage::JobBatches
            } else {
                SourcePackFilesystemArtifactBuildPrepareStage::ArtifactRefs
            },
            step.new_library_count,
        ));
    }
    let artifact_ref_index = store.load_build_artifact_ref_index_for_target(target)?;

    if !store
        .build_job_batch_index_path_for_target(target)
        .is_file()
    {
        let step = store_source_pack_build_job_batch_pages_from_stored_schedule_pages_chunk(
            &store,
            &schedule_index,
            batch_limits,
            max_new_items,
        )?;
        return Ok(source_pack_artifact_build_prepare_step_result(
            target,
            SourcePackFilesystemArtifactBuildPrepareStage::JobBatches,
            if step.complete {
                SourcePackFilesystemArtifactBuildPrepareStage::LinkBatches
            } else {
                SourcePackFilesystemArtifactBuildPrepareStage::JobBatches
            },
            step.new_batch_count,
        ));
    }
    let job_batch_page_index = store.load_build_job_batch_page_index_for_target(target)?;

    if !store
        .build_link_batch_index_path_for_target(target)
        .is_file()
    {
        let step = store_source_pack_build_link_batch_pages_from_stored_artifact_ref_pages_chunk(
            &store,
            target,
            &schedule_index,
            &artifact_ref_index,
            batch_limits,
            max_new_items,
        )?;
        return Ok(source_pack_artifact_build_prepare_step_result(
            target,
            SourcePackFilesystemArtifactBuildPrepareStage::LinkBatches,
            if step.complete {
                SourcePackFilesystemArtifactBuildPrepareStage::JobBatchDependents
            } else {
                SourcePackFilesystemArtifactBuildPrepareStage::LinkBatches
            },
            step.new_batch_count,
        ));
    }
    let link_batch_page_index = store.load_build_link_batch_page_index_for_target(target)?;

    if !source_pack_job_batch_dependents_complete_for_target(
        &store,
        target,
        job_batch_page_index.batch_count,
    )? {
        let step = store_source_pack_job_batch_dependents_pages_from_stored_job_batch_pages_chunk(
            &store,
            target,
            &job_batch_page_index,
            max_new_items,
        )?;
        return Ok(source_pack_artifact_build_prepare_step_result(
            target,
            SourcePackFilesystemArtifactBuildPrepareStage::JobBatchDependents,
            if step.complete {
                SourcePackFilesystemArtifactBuildPrepareStage::ArtifactShards
            } else {
                SourcePackFilesystemArtifactBuildPrepareStage::JobBatchDependents
            },
            step.new_batch_count,
        ));
    }

    if !store.artifact_shard_index_path_for_target(target).is_file() {
        let library_partition_index = store.load_library_partition_index_for_target(target)?;
        let step = store_source_pack_build_artifact_shards_from_page_metadata_chunk(
            &store,
            target,
            shard_limits,
            &schedule_index,
            &artifact_ref_index,
            &job_batch_page_index,
            &link_batch_page_index,
            &library_partition_index,
            max_new_items,
        )?;
        return Ok(source_pack_artifact_build_prepare_step_result(
            target,
            SourcePackFilesystemArtifactBuildPrepareStage::ArtifactShards,
            if step.complete {
                SourcePackFilesystemArtifactBuildPrepareStage::HierarchicalLinkLeafGroups
            } else {
                SourcePackFilesystemArtifactBuildPrepareStage::ArtifactShards
            },
            step.new_input_batch_count
                .saturating_add(step.new_progress_directory_page_count)
                .saturating_add(step.new_progress_directory_index_page_count),
        ));
    }

    if !store
        .hierarchical_link_plan_index_path_for_target(target)
        .is_file()
        && !source_pack_hierarchical_link_leaf_groups_complete_for_target(
            &store,
            &schedule_index,
            batch_limits,
        )?
    {
        let step =
            store_source_pack_hierarchical_link_leaf_groups_from_stored_schedule_pages_chunk(
                &store,
                &schedule_index,
                batch_limits,
                max_new_items,
            )?;
        return Ok(source_pack_artifact_build_prepare_step_result(
            target,
            SourcePackFilesystemArtifactBuildPrepareStage::HierarchicalLinkLeafGroups,
            if step.complete {
                SourcePackFilesystemArtifactBuildPrepareStage::HierarchicalLinkPlanReduceGroups
            } else {
                SourcePackFilesystemArtifactBuildPrepareStage::HierarchicalLinkLeafGroups
            },
            step.new_leaf_group_count,
        ));
    }

    if !store
        .hierarchical_link_plan_index_path_for_target(target)
        .is_file()
    {
        let step = store_source_pack_hierarchical_link_reduce_groups_from_stored_leaf_groups_chunk(
            &store,
            &schedule_index,
            batch_limits,
            max_new_items,
        )?;
        return Ok(source_pack_artifact_build_prepare_step_result(
            target,
            SourcePackFilesystemArtifactBuildPrepareStage::HierarchicalLinkPlanReduceGroups,
            if step.complete {
                SourcePackFilesystemArtifactBuildPrepareStage::HierarchicalLinkExecution
            } else {
                SourcePackFilesystemArtifactBuildPrepareStage::HierarchicalLinkPlanReduceGroups
            },
            step.new_reduce_group_count,
        ));
    }
    let hierarchical_link_plan_index =
        store.load_hierarchical_link_plan_index_for_target(target)?;

    if !store
        .hierarchical_link_execution_index_path_for_target(target)
        .is_file()
    {
        let step = store_source_pack_hierarchical_link_execution_from_stored_schedule_pages_chunk(
            &store,
            &hierarchical_link_plan_index,
            &schedule_index,
            &artifact_ref_index,
            max_new_items,
        )?;
        return Ok(source_pack_artifact_build_prepare_step_result(
            target,
            SourcePackFilesystemArtifactBuildPrepareStage::HierarchicalLinkExecution,
            if step.complete {
                SourcePackFilesystemArtifactBuildPrepareStage::WorkQueuePages
            } else {
                SourcePackFilesystemArtifactBuildPrepareStage::HierarchicalLinkExecution
            },
            step.new_execution_page_count,
        ));
    }

    if !store.work_queue_index_path_for_target(target).is_file() {
        let step = store_source_pack_work_queue_pages_from_stored_schedule_pages_chunk(
            &store,
            &schedule_index,
            &hierarchical_link_plan_index,
            max_new_items,
        )?;
        return Ok(source_pack_artifact_build_prepare_step_result(
            target,
            SourcePackFilesystemArtifactBuildPrepareStage::WorkQueuePages,
            if step.complete {
                SourcePackFilesystemArtifactBuildPrepareStage::WorkQueueProgress
            } else {
                SourcePackFilesystemArtifactBuildPrepareStage::WorkQueuePages
            },
            step.new_work_item_count,
        ));
    }

    if !store
        .work_queue_progress_index_path_for_target(target)
        .is_file()
    {
        let work_queue_index = store.load_work_queue_index_for_target(target)?;
        let step = store_initial_work_queue_progress_from_stored_work_queue_pages_chunk(
            &store,
            &work_queue_index,
            SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE,
            max_new_items,
        )?;
        return Ok(source_pack_artifact_build_prepare_step_result(
            target,
            SourcePackFilesystemArtifactBuildPrepareStage::WorkQueueProgress,
            if step.complete {
                SourcePackFilesystemArtifactBuildPrepareStage::BuildManifests
            } else {
                SourcePackFilesystemArtifactBuildPrepareStage::WorkQueueProgress
            },
            step.new_progress_page_count,
        ));
    }

    if !store.build_manifest_path_for_target(target).is_file()
        || !store.artifact_manifest_path_for_target(target).is_file()
    {
        source_pack_store_compact_build_manifests_from_stored_indexes(
            &store,
            limits,
            batch_limits,
            target,
        )?;
        return Ok(source_pack_artifact_build_prepare_step_result(
            target,
            SourcePackFilesystemArtifactBuildPrepareStage::BuildManifests,
            SourcePackFilesystemArtifactBuildPrepareStage::BuildState,
            2,
        ));
    }

    let build_state_path =
        store.store_build_state_for_target(target, &SourcePackBuildState::new())?;
    if !build_state_path.is_file() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build state was not stored at {}",
            build_state_path.display()
        )));
    }
    let prepared =
        source_pack_filesystem_artifact_prepare_result_from_stored_indexes(&store, target)?;
    Ok(SourcePackFilesystemArtifactBuildPrepareStepResult {
        target,
        complete: true,
        stage: SourcePackFilesystemArtifactBuildPrepareStage::BuildState,
        next_stage: SourcePackFilesystemArtifactBuildPrepareStage::Complete,
        new_item_count: 1,
        prepared: Some(prepared),
    })
}

pub fn prepare_source_pack_filesystem_artifact_build_from_metadata_with_shard_limits_for_target(
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError> {
    let artifact_root = artifact_root.into();
    for _ in 0..SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_FULL_PREPARE_DEFAULT_STEP_LIMIT {
        let step =
            prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target(
                &artifact_root,
                limits,
                batch_limits,
                shard_limits,
                target,
                SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
            )?;
        if step.complete {
            return step.prepared.ok_or_else(|| {
                source_pack_artifact_shard_contract_error(
                    "completed source-pack artifact build prepare did not return prepared result",
                )
            });
        }
    }
    Err(CompileError::GpuFrontend(format!(
        "source-pack artifact build prepare did not complete within {SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_FULL_PREPARE_DEFAULT_STEP_LIMIT} bounded chunk steps; keep calling prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target to continue persisted preparation"
    )))
}

pub(super) fn prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: &Path,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    max_new_items: usize,
) -> Result<bool, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    if max_new_items == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack work-queue preparation chunk max_new_items must be greater than zero"
                .into(),
        ));
    }
    let max_new_items =
        max_new_items.min(SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let store = SourcePackFilesystemArtifactStore::new(artifact_root);
    if !store
        .library_partition_index_path_for_target(target)
        .is_file()
    {
        let metadata =
            prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_for_target(
                libraries,
                artifact_root,
                target,
                max_new_items,
            )?;
        if !metadata.complete {
            return Ok(false);
        }
    }
    if !store.build_state_path_for_target(target).is_file() {
        let build =
            prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target(
                artifact_root,
                limits,
                batch_limits,
                shard_limits,
                target,
                max_new_items,
            )?;
        return Ok(build.complete);
    }
    Ok(true)
}

#[allow(clippy::too_many_arguments)]
pub(super) fn prepare_explicit_source_pack_path_streams_filesystem_work_queue_chunk_with_shard_limits_for_target<
    'a,
    SI,
    UI,
    P,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: &Path,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    max_new_items: usize,
) -> Result<bool, CompileError>
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
    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
        max_new_items,
    )
}

pub(super) fn source_pack_work_queue_not_prepared_after_bounded_chunk_error(
    target: SourcePackArtifactTarget,
    max_new_items: usize,
) -> CompileError {
    CompileError::GpuFrontend(format!(
        "source-pack {:?} work queue is not prepared after one bounded preparation chunk of {max_new_items} items; rerun the descriptor worker or call prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_metadata_chunk_for_target and prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target until the persisted work queue is complete",
        target
    ))
}

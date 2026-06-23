use super::*;

/// Plans a compact artifact manifest from streamed library paths and dependencies.
pub(in crate::compiler) fn compact_manifest_from_dependency_streams<I, PI, DI, P>(
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
            explicit_source_pack_manifest_invalid(
                None,
                "library count overflowed while planning compact manifest",
            )
        })?;
        if library.source_file_count == 0 {
            return Err(explicit_source_pack_manifest_invalid(
                Some(library.library_id),
                "library declares no source files",
            ));
        }
        if !seen_library_ids.insert(library.library_id) {
            return Err(explicit_source_pack_manifest_invalid(
                Some(library.library_id),
                "library id appears more than once",
            ));
        }

        let mut dependency_library_count = 0usize;
        let mut previous_dependency_library_id = None;
        for dependency_library_id in library.dependency_library_ids {
            if dependency_library_count >= library.dependency_library_count {
                return Err(explicit_source_pack_manifest_invalid(
                    Some(library.library_id),
                    format!(
                        "declares {} dependencies but yielded at least {}",
                        library.dependency_library_count,
                        dependency_library_count.saturating_add(1)
                    ),
                ));
            }
            if dependency_library_id == library.library_id {
                return Err(explicit_source_pack_manifest_invalid(
                    Some(library.library_id),
                    "library depends on itself",
                ));
            }
            if previous_dependency_library_id
                .is_some_and(|previous| dependency_library_id <= previous)
            {
                return Err(explicit_source_pack_manifest_invalid(
                    Some(library.library_id),
                    "dependency ids must be strictly sorted and unique",
                ));
            }
            if !seen_library_ids.contains(&dependency_library_id) {
                return Err(explicit_source_pack_manifest_invalid(
                    Some(library.library_id),
                    format!("depends on missing or later library {dependency_library_id}"),
                ));
            }
            library_dependencies.push(SourcePackLibraryDependency {
                library_id: library.library_id,
                depends_on_library_id: dependency_library_id,
            });
            previous_dependency_library_id = Some(dependency_library_id);
            dependency_library_count = dependency_library_count.saturating_add(1);
        }
        if dependency_library_count != library.dependency_library_count {
            return Err(explicit_source_pack_manifest_invalid(
                Some(library.library_id),
                format!(
                    "declares {} dependencies but yielded {}",
                    library.dependency_library_count, dependency_library_count
                ),
            ));
        }

        let label = format!("library {}", library.library_id);
        let mut stored_source_file_count = 0usize;
        for (path_index, path) in library.paths.into_iter().enumerate() {
            if path_index >= library.source_file_count {
                return Err(explicit_source_pack_manifest_invalid(
                    Some(library.library_id),
                    format!(
                        "declares {} source files but yielded at least {}",
                        library.source_file_count,
                        path_index + 1
                    ),
                ));
            }
            let source_index = next_source_index;
            next_source_index = next_source_index.checked_add(1).ok_or_else(|| {
                explicit_source_pack_manifest_invalid(
                    Some(library.library_id),
                    "source index overflowed while planning compact manifest",
                )
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
            return Err(explicit_source_pack_manifest_invalid(
                Some(library.library_id),
                format!(
                    "declares {} source files but yielded {}",
                    library.source_file_count, stored_source_file_count
                ),
            ));
        }
    }
    if library_count == 0 {
        return Err(explicit_source_pack_manifest_invalid(
            None,
            "manifest contains no source libraries",
        ));
    }

    let plan = plan_builder.finish(&library_dependencies);
    let schedule = plan.bounded_frontend_job_schedule();
    plan.try_compact_build_artifact_manifest_for_schedule(&schedule, batch_limits, target)
        .map_err(schedule_error)
}

/// Plan a generic-target compact artifact manifest from stdlib and user path
/// streams.
pub fn plan_source_pack_streams_compact_manifest<'a, SI, UI, P>(
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
    plan_source_pack_streams_compact_manifest_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

/// Plan a target-specific compact artifact manifest from stdlib and user path
/// streams.
pub fn plan_source_pack_streams_compact_manifest_for_target<'a, SI, UI, P>(
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

/// Plan a generic-target compact artifact manifest from ordered library path
/// streams.
pub fn plan_library_streams_compact_manifest<I, PI, P>(
    libraries: I,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackBuildArtifactManifest, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    plan_library_streams_compact_manifest_for_target(
        libraries,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

/// Plan a target-specific compact artifact manifest from ordered library path
/// streams.
pub fn plan_library_streams_compact_manifest_for_target<I, PI, P>(
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

/// Plan a generic-target compact artifact manifest from explicit dependency
/// streams.
pub fn plan_dependency_streams_compact_manifest<I, PI, DI, P>(
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
    plan_dependency_streams_compact_manifest_for_target(
        libraries,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

/// Plan a target-specific compact artifact manifest from explicit dependency
/// streams.
pub fn plan_dependency_streams_compact_manifest_for_target<I, PI, DI, P>(
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

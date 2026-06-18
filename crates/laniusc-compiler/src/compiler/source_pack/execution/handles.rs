use super::*;

/// Collects cloned interface handles for a job's dependencies.
pub(in crate::compiler) fn collect_interface_handle_clones<T: Clone>(
    library_interfaces: &[Option<T>],
    schedule: &SourcePackJobSchedule,
    job: &SourcePackJob,
) -> Result<Vec<T>, CompileError> {
    collect_interface_handle_clones_excluding(library_interfaces, schedule, job, None)
}

/// Collects cloned interface handles while skipping one dependency job.
pub(in crate::compiler) fn collect_interface_handle_clones_excluding<T: Clone>(
    library_interfaces: &[Option<T>],
    schedule: &SourcePackJobSchedule,
    job: &SourcePackJob,
    excluded_job_index: Option<usize>,
) -> Result<Vec<T>, CompileError> {
    let mut handles = Vec::new();
    for_each_interface_dependency_job_index(
        schedule,
        job,
        excluded_job_index,
        |dependency_job_index| {
            let handle = library_interfaces
                .get(dependency_job_index)
                .and_then(|handle| handle.as_ref())
                .cloned()
                .ok_or_else(|| {
                    CompileError::GpuFrontend(format!(
                        "source-pack job {} missing interface dependency from job {}",
                        job.job_index, dependency_job_index
                    ))
                })?;
            handles.push(handle);
            Ok(())
        },
    )?;
    Ok(handles)
}

/// Collects cloned interface handles consumed by the full link step.
pub(in crate::compiler) fn collect_link_interface_handle_clones<T: Clone>(
    library_interfaces: &[Option<T>],
    build_plan: &SourcePackBuildPlan,
) -> Result<Vec<T>, CompileError> {
    let mut handles = Vec::new();
    build_plan
        .link
        .try_for_each_input_interface_artifact_index(|artifact_index| {
            let artifact = build_plan.artifacts.get(artifact_index).ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack link references missing interface artifact {artifact_index}"
                ))
            })?;
            let handle = library_interfaces
                .get(artifact.producing_job_index)
                .and_then(|handle| handle.as_ref())
                .cloned()
                .ok_or_else(|| {
                    CompileError::GpuFrontend(format!(
                        "source-pack link missing interface from job {}",
                        artifact.producing_job_index
                    ))
                })?;
            handles.push(handle);
            Ok(())
        })?;
    Ok(handles)
}

/// Collects cloned interface handles consumed by one link-interface batch.
pub(in crate::compiler) fn collect_link_interface_handle_clones_for_batch<T: Clone>(
    library_interfaces: &[Option<T>],
    build_plan: &SourcePackBuildPlan,
    batch: &SourcePackLinkInterfaceBatch,
) -> Result<Vec<T>, CompileError> {
    let mut handles = Vec::new();
    for &artifact_index in &batch.input_interface_artifact_indices {
        let artifact = build_plan.artifacts.get(artifact_index).ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack link batch references missing interface artifact {artifact_index}"
            ))
        })?;
        let handle = library_interfaces
            .get(artifact.producing_job_index)
            .and_then(|handle| handle.as_ref())
            .cloned()
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack link batch missing interface from job {}",
                    artifact.producing_job_index
                ))
            })?;
        handles.push(handle);
    }
    Ok(handles)
}

/// Collects cloned codegen-object handles consumed by the full link step.
pub(in crate::compiler) fn collect_link_object_handle_clones<T: Clone>(
    codegen_objects: &[Option<T>],
    build_plan: &SourcePackBuildPlan,
) -> Result<Vec<T>, CompileError> {
    let mut handles = Vec::new();
    build_plan
        .link
        .try_for_each_input_object_artifact_index(|artifact_index| {
            let artifact = build_plan.artifacts.get(artifact_index).ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack link references missing object artifact {artifact_index}"
                ))
            })?;
            let handle = codegen_objects
                .get(artifact.producing_job_index)
                .and_then(|handle| handle.as_ref())
                .cloned()
                .ok_or_else(|| {
                    CompileError::GpuFrontend(format!(
                        "source-pack link missing object from job {}",
                        artifact.producing_job_index
                    ))
                })?;
            handles.push(handle);
            Ok(())
        })?;
    Ok(handles)
}

/// Collects cloned codegen-object handles consumed by one link-object batch.
pub(in crate::compiler) fn collect_link_object_handle_clones_for_batch<T: Clone>(
    codegen_objects: &[Option<T>],
    build_plan: &SourcePackBuildPlan,
    batch: &SourcePackLinkObjectBatch,
) -> Result<Vec<T>, CompileError> {
    let mut handles = Vec::new();
    for &artifact_index in &batch.input_object_artifact_indices {
        let artifact = build_plan.artifacts.get(artifact_index).ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack link batch references missing object artifact {artifact_index}"
            ))
        })?;
        let handle = codegen_objects
            .get(artifact.producing_job_index)
            .and_then(|handle| handle.as_ref())
            .cloned()
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack link batch missing object from job {}",
                    artifact.producing_job_index
                ))
            })?;
        handles.push(handle);
    }
    Ok(handles)
}

/// Releases all interface/object handles consumed by a full link step.
pub(in crate::compiler) fn release_link_input_handles<E>(
    build_plan: &SourcePackBuildPlan,
    library_interfaces: &mut [Option<E::LibraryInterfaceHandle>],
    codegen_objects: &mut [Option<E::CodegenObjectHandle>],
    executor: &mut E,
) -> Result<(), CompileError>
where
    E: PathHandleBuildExecutor,
{
    let mut released_interfaces = BTreeSet::new();
    build_plan
        .link
        .try_for_each_input_interface_artifact_index(|artifact_index| {
            if !released_interfaces.insert(artifact_index) {
                return Ok(());
            }
            let Some(artifact) = build_plan.artifacts.get(artifact_index) else {
                return Ok(());
            };
            if artifact.kind != SourcePackArtifactKind::LibraryInterface {
                return Ok(());
            }
            if let Some(handle) = library_interfaces
                .get_mut(artifact.producing_job_index)
                .and_then(Option::take)
            {
                executor.release_library_interface(handle)?;
            }
            Ok::<(), CompileError>(())
        })?;

    let mut released_objects = BTreeSet::new();
    build_plan
        .link
        .try_for_each_input_object_artifact_index(|artifact_index| {
            if !released_objects.insert(artifact_index) {
                return Ok(());
            }
            let Some(artifact) = build_plan.artifacts.get(artifact_index) else {
                return Ok(());
            };
            if artifact.kind != SourcePackArtifactKind::CodegenObject {
                return Ok(());
            }
            if let Some(handle) = codegen_objects
                .get_mut(artifact.producing_job_index)
                .and_then(Option::take)
            {
                executor.release_codegen_object(handle)?;
            }
            Ok::<(), CompileError>(())
        })?;

    Ok(())
}

/// Releases codegen-object handles consumed by one link-object batch.
pub(in crate::compiler) fn release_codegen_object_handles_for_link_batch<E>(
    build_plan: &SourcePackBuildPlan,
    batch: &SourcePackLinkObjectBatch,
    codegen_objects: &mut [Option<E::CodegenObjectHandle>],
    executor: &mut E,
) -> Result<(), CompileError>
where
    E: PathHandleBatchedLinkBuildExecutor,
{
    for &artifact_index in &batch.input_object_artifact_indices {
        let Some(artifact) = build_plan.artifacts.get(artifact_index) else {
            continue;
        };
        if artifact.kind != SourcePackArtifactKind::CodegenObject {
            continue;
        }
        if let Some(handle) = codegen_objects
            .get_mut(artifact.producing_job_index)
            .and_then(Option::take)
        {
            executor.release_codegen_object(handle)?;
        }
    }
    Ok(())
}

/// Releases library-interface handles consumed by one link-interface batch.
pub(in crate::compiler) fn release_library_interface_handles_for_link_batch<E>(
    build_plan: &SourcePackBuildPlan,
    batch: &SourcePackLinkInterfaceBatch,
    library_interfaces: &mut [Option<E::LibraryInterfaceHandle>],
    executor: &mut E,
) -> Result<(), CompileError>
where
    E: PathHandleBatchedLinkBuildExecutor,
{
    for &artifact_index in &batch.input_interface_artifact_indices {
        let Some(artifact) = build_plan.artifacts.get(artifact_index) else {
            continue;
        };
        if artifact.kind != SourcePackArtifactKind::LibraryInterface {
            continue;
        }
        if let Some(handle) = library_interfaces
            .get_mut(artifact.producing_job_index)
            .and_then(Option::take)
        {
            executor.release_library_interface(handle)?;
        }
    }
    Ok(())
}

/// Collects borrowed interface values for a job's dependencies.
pub(in crate::compiler) fn collect_interface_refs<'a, T>(
    library_interfaces: &'a [T],
    interface_by_job: &[Option<usize>],
    schedule: &SourcePackJobSchedule,
    job: &SourcePackJob,
) -> Result<Vec<&'a T>, CompileError> {
    collect_interface_refs_excluding(library_interfaces, interface_by_job, schedule, job, None)
}

/// Collects borrowed interface values while skipping one dependency job.
pub(in crate::compiler) fn collect_interface_refs_excluding<'a, T>(
    library_interfaces: &'a [T],
    interface_by_job: &[Option<usize>],
    schedule: &SourcePackJobSchedule,
    job: &SourcePackJob,
    excluded_job_index: Option<usize>,
) -> Result<Vec<&'a T>, CompileError> {
    let mut refs = Vec::new();
    for_each_interface_dependency_job_index(
        schedule,
        job,
        excluded_job_index,
        |dependency_job_index| {
            let interface_index = interface_by_job
                .get(dependency_job_index)
                .and_then(|index| *index)
                .ok_or_else(|| {
                    CompileError::GpuFrontend(format!(
                        "source-pack job {} missing interface dependency from job {}",
                        job.job_index, dependency_job_index
                    ))
                })?;
            refs.push(&library_interfaces[interface_index]);
            Ok(())
        },
    )?;
    Ok(refs)
}

/// Visits each unique interface dependency job for a source-pack job.
pub(in crate::compiler) fn for_each_interface_dependency_job_index<F>(
    schedule: &SourcePackJobSchedule,
    job: &SourcePackJob,
    excluded_job_index: Option<usize>,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(usize) -> Result<(), CompileError>,
{
    let mut seen = BTreeSet::new();
    for &dependency_job_index in &job.dependency_job_indices {
        if Some(dependency_job_index) != excluded_job_index && seen.insert(dependency_job_index) {
            visit(dependency_job_index)?;
        }
    }
    for dependency_range in schedule.dependency_job_ranges_for_job(job) {
        let Some(dependency_job_indices) = dependency_range.iter() else {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack job {} interface dependency range starting at {} overflows",
                job.job_index, dependency_range.first_job_index
            )));
        };
        for dependency_job_index in dependency_job_indices {
            if Some(dependency_job_index) != excluded_job_index && seen.insert(dependency_job_index)
            {
                visit(dependency_job_index)?;
            }
        }
    }
    Ok(())
}

/// Collects borrowed interface values consumed by the full link step.
pub(in crate::compiler) fn collect_link_interface_refs<'a, T>(
    library_interfaces: &'a [T],
    interface_by_job: &[Option<usize>],
    build_plan: &SourcePackBuildPlan,
) -> Result<Vec<&'a T>, CompileError> {
    let mut refs = Vec::new();
    build_plan
        .link
        .try_for_each_input_interface_artifact_index(|artifact_index| {
            let artifact = build_plan.artifacts.get(artifact_index).ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack link references missing interface artifact {artifact_index}"
                ))
            })?;
            let interface_index = interface_by_job
                .get(artifact.producing_job_index)
                .and_then(|index| *index)
                .ok_or_else(|| {
                    CompileError::GpuFrontend(format!(
                        "source-pack link missing interface from job {}",
                        artifact.producing_job_index
                    ))
                })?;
            refs.push(&library_interfaces[interface_index]);
            Ok(())
        })?;
    Ok(refs)
}

/// Collects borrowed codegen-object values consumed by the full link step.
pub(in crate::compiler) fn collect_link_object_refs<'a, T>(
    codegen_objects: &'a [T],
    object_by_job: &[Option<usize>],
    build_plan: &SourcePackBuildPlan,
) -> Result<Vec<&'a T>, CompileError> {
    let mut refs = Vec::new();
    build_plan
        .link
        .try_for_each_input_object_artifact_index(|artifact_index| {
            let artifact = build_plan.artifacts.get(artifact_index).ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack link references missing object artifact {artifact_index}"
                ))
            })?;
            let object_index = object_by_job
                .get(artifact.producing_job_index)
                .and_then(|index| *index)
                .ok_or_else(|| {
                    CompileError::GpuFrontend(format!(
                        "source-pack link missing object from job {}",
                        artifact.producing_job_index
                    ))
                })?;
            refs.push(&codegen_objects[object_index]);
            Ok(())
        })?;
    Ok(refs)
}

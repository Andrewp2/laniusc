use super::*;

pub(in crate::compiler) fn execute_build<E>(
    source_pack: &ExplicitSourcePack,
    build_plan: &SourcePackBuildPlan,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
) -> Result<
    BuildExecutionResult<E::LibraryInterface, E::CodegenObject, E::LinkedOutput>,
    CompileError,
>
where
    E: BuildExecutor,
{
    let mut library_interfaces = Vec::new();
    let mut codegen_objects = Vec::new();
    let mut interface_by_job = vec![None; build_plan.schedule.jobs.len()];
    let mut object_by_job = vec![None; build_plan.schedule.jobs.len()];
    let mut linked_output = None;

    build_plan
        .schedule
        .try_for_each_execution_batch(batch_limits, schedule_error, |batch| {
            for &job_index in &batch.job_indices {
                let job = schedule_job(&build_plan.schedule, job_index)?;
                match job.phase {
                    SourcePackJobPhase::LibraryFrontend => {
                        let dependency_interfaces = collect_interface_refs(
                            &library_interfaces,
                            &interface_by_job,
                            &build_plan.schedule,
                            job,
                        )?;
                        let interface = executor.build_library_interface(
                            job,
                            source_pack.source_slice_for_job(job),
                            &dependency_interfaces,
                        )?;
                        interface_by_job[job.job_index] = Some(library_interfaces.len());
                        library_interfaces.push(interface);
                    }
                    SourcePackJobPhase::Codegen => {
                        let library_job_index = job.library_job_index.ok_or_else(|| {
                            CompileError::GpuFrontend(format!(
                                "source-pack codegen job {} has no owning library job",
                                job.job_index
                            ))
                        })?;
                        let library_interface_index = interface_by_job
                            .get(library_job_index)
                            .and_then(|index| *index)
                            .ok_or_else(|| {
                                CompileError::GpuFrontend(format!(
                                "source-pack codegen job {} missing library interface from job {}",
                                job.job_index, library_job_index
                            ))
                            })?;
                        let library_interface = &library_interfaces[library_interface_index];
                        let dependency_interfaces = collect_interface_refs_excluding(
                            &library_interfaces,
                            &interface_by_job,
                            &build_plan.schedule,
                            job,
                            Some(library_job_index),
                        )?;
                        let object = executor.build_codegen_object(
                            job,
                            source_pack.source_slice_for_job(job),
                            library_interface,
                            &dependency_interfaces,
                        )?;
                        object_by_job[job.job_index] = Some(codegen_objects.len());
                        codegen_objects.push(object);
                    }
                    SourcePackJobPhase::Link => {
                        let interface_refs = collect_link_interface_refs(
                            &library_interfaces,
                            &interface_by_job,
                            build_plan,
                        )?;
                        let object_refs =
                            collect_link_object_refs(&codegen_objects, &object_by_job, build_plan)?;
                        linked_output = Some(executor.link_codegen_objects(
                            job,
                            &interface_refs,
                            &object_refs,
                        )?);
                    }
                }
            }
            Ok(())
        })?;

    let linked_output = linked_output.ok_or_else(|| {
        CompileError::GpuFrontend("source-pack build plan did not execute a link job".into())
    })?;

    Ok(BuildExecutionResult {
        library_interfaces,
        codegen_objects,
        linked_output,
    })
}

pub(in crate::compiler) fn execute_path_build<E>(
    source_pack: &ExplicitSourcePackPathManifest,
    build_plan: &SourcePackBuildPlan,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
) -> Result<
    BuildExecutionResult<E::LibraryInterface, E::CodegenObject, E::LinkedOutput>,
    CompileError,
>
where
    E: PathBuildExecutor,
{
    let mut library_interfaces = Vec::new();
    let mut codegen_objects = Vec::new();
    let mut interface_by_job = vec![None; build_plan.schedule.jobs.len()];
    let mut object_by_job = vec![None; build_plan.schedule.jobs.len()];
    let mut linked_output = None;

    build_plan
        .schedule
        .try_for_each_execution_batch(batch_limits, schedule_error, |batch| {
            for &job_index in &batch.job_indices {
                let job = schedule_job(&build_plan.schedule, job_index)?;
                match job.phase {
                    SourcePackJobPhase::LibraryFrontend => {
                        let dependency_interfaces = collect_interface_refs(
                            &library_interfaces,
                            &interface_by_job,
                            &build_plan.schedule,
                            job,
                        )?;
                        let interface = executor.build_library_interface(
                            job,
                            source_pack.source_files_for_job(job),
                            &dependency_interfaces,
                        )?;
                        interface_by_job[job.job_index] = Some(library_interfaces.len());
                        library_interfaces.push(interface);
                    }
                    SourcePackJobPhase::Codegen => {
                        let library_job_index = job.library_job_index.ok_or_else(|| {
                            CompileError::GpuFrontend(format!(
                                "source-pack codegen job {} has no owning library job",
                                job.job_index
                            ))
                        })?;
                        let library_interface_index = interface_by_job
                            .get(library_job_index)
                            .and_then(|index| *index)
                            .ok_or_else(|| {
                                CompileError::GpuFrontend(format!(
                                "source-pack codegen job {} missing library interface from job {}",
                                job.job_index, library_job_index
                            ))
                            })?;
                        let library_interface = &library_interfaces[library_interface_index];
                        let dependency_interfaces = collect_interface_refs_excluding(
                            &library_interfaces,
                            &interface_by_job,
                            &build_plan.schedule,
                            job,
                            Some(library_job_index),
                        )?;
                        let object = executor.build_codegen_object(
                            job,
                            source_pack.source_files_for_job(job),
                            library_interface,
                            &dependency_interfaces,
                        )?;
                        object_by_job[job.job_index] = Some(codegen_objects.len());
                        codegen_objects.push(object);
                    }
                    SourcePackJobPhase::Link => {
                        let interface_refs = collect_link_interface_refs(
                            &library_interfaces,
                            &interface_by_job,
                            build_plan,
                        )?;
                        let object_refs =
                            collect_link_object_refs(&codegen_objects, &object_by_job, build_plan)?;
                        linked_output = Some(executor.link_codegen_objects(
                            job,
                            &interface_refs,
                            &object_refs,
                        )?);
                    }
                }
            }
            Ok(())
        })?;

    let linked_output = linked_output.ok_or_else(|| {
        CompileError::GpuFrontend("source-pack build plan did not execute a link job".into())
    })?;

    Ok(BuildExecutionResult {
        library_interfaces,
        codegen_objects,
        linked_output,
    })
}

pub(in crate::compiler) fn execute_path_handle_build<E>(
    source_pack: &ExplicitSourcePackPathManifest,
    build_plan: &SourcePackBuildPlan,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
) -> Result<HandleBuildExecutionResult<E::LinkedOutput>, CompileError>
where
    E: PathHandleBuildExecutor,
{
    let mut library_interfaces = vec![None; build_plan.schedule.jobs.len()];
    let mut codegen_objects = vec![None; build_plan.schedule.jobs.len()];
    let mut linked_output = None;

    build_plan
        .schedule
        .try_for_each_execution_batch(batch_limits, schedule_error, |batch| {
            for &job_index in &batch.job_indices {
                let job = schedule_job(&build_plan.schedule, job_index)?;
                match job.phase {
                    SourcePackJobPhase::LibraryFrontend => {
                        let dependency_interfaces = collect_interface_handle_clones(
                            &library_interfaces,
                            &build_plan.schedule,
                            job,
                        )?;
                        let interface = executor.build_library_interface(
                            job,
                            source_pack.source_files_for_job(job),
                            &dependency_interfaces,
                        )?;
                        library_interfaces[job.job_index] = Some(interface);
                    }
                    SourcePackJobPhase::Codegen => {
                        let library_job_index = job.library_job_index.ok_or_else(|| {
                            CompileError::GpuFrontend(format!(
                                "source-pack codegen job {} has no owning library job",
                                job.job_index
                            ))
                        })?;
                        let library_interface = library_interfaces
                            .get(library_job_index)
                            .and_then(|handle| handle.as_ref())
                            .cloned()
                            .ok_or_else(|| {
                                CompileError::GpuFrontend(format!(
                                "source-pack codegen job {} missing library interface from job {}",
                                job.job_index, library_job_index
                            ))
                            })?;
                        let dependency_interfaces = collect_interface_handle_clones_excluding(
                            &library_interfaces,
                            &build_plan.schedule,
                            job,
                            Some(library_job_index),
                        )?;
                        let object = executor.build_codegen_object(
                            job,
                            source_pack.source_files_for_job(job),
                            &library_interface,
                            &dependency_interfaces,
                        )?;
                        codegen_objects[job.job_index] = Some(object);
                    }
                    SourcePackJobPhase::Link => {
                        let interface_handles =
                            collect_link_interface_handle_clones(&library_interfaces, build_plan)?;
                        let object_handles =
                            collect_link_object_handle_clones(&codegen_objects, build_plan)?;
                        linked_output = Some(executor.link_codegen_objects(
                            job,
                            &interface_handles,
                            &object_handles,
                        )?);
                        release_link_input_handles(
                            build_plan,
                            &mut library_interfaces,
                            &mut codegen_objects,
                            executor,
                        )?;
                    }
                }
            }
            Ok(())
        })?;

    let linked_output = linked_output.ok_or_else(|| {
        CompileError::GpuFrontend("source-pack build plan did not execute a link job".into())
    })?;

    Ok(HandleBuildExecutionResult { linked_output })
}

pub(in crate::compiler) fn execute_path_batched_link_build<E>(
    source_pack: &ExplicitSourcePackPathManifest,
    build_plan: &SourcePackBuildPlan,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
) -> Result<HandleBuildExecutionResult<E::LinkedOutput>, CompileError>
where
    E: PathHandleBatchedLinkBuildExecutor,
{
    let mut library_interfaces = vec![None; build_plan.schedule.jobs.len()];
    let mut codegen_objects = vec![None; build_plan.schedule.jobs.len()];
    let mut linked_output = None;

    build_plan
        .schedule
        .try_for_each_execution_batch(batch_limits, schedule_error, |batch| {
            for &job_index in &batch.job_indices {
                let job = schedule_job(&build_plan.schedule, job_index)?;
                match job.phase {
                    SourcePackJobPhase::LibraryFrontend => {
                        let dependency_interfaces = collect_interface_handle_clones(
                            &library_interfaces,
                            &build_plan.schedule,
                            job,
                        )?;
                        let interface = executor.build_library_interface(
                            job,
                            source_pack.source_files_for_job(job),
                            &dependency_interfaces,
                        )?;
                        library_interfaces[job.job_index] = Some(interface);
                    }
                    SourcePackJobPhase::Codegen => {
                        let library_job_index = job.library_job_index.ok_or_else(|| {
                            CompileError::GpuFrontend(format!(
                                "source-pack codegen job {} has no owning library job",
                                job.job_index
                            ))
                        })?;
                        let library_interface = library_interfaces
                            .get(library_job_index)
                            .and_then(|handle| handle.as_ref())
                            .cloned()
                            .ok_or_else(|| {
                                CompileError::GpuFrontend(format!(
                                "source-pack codegen job {} missing library interface from job {}",
                                job.job_index, library_job_index
                            ))
                            })?;
                        let dependency_interfaces = collect_interface_handle_clones_excluding(
                            &library_interfaces,
                            &build_plan.schedule,
                            job,
                            Some(library_job_index),
                        )?;
                        let object = executor.build_codegen_object(
                            job,
                            source_pack.source_files_for_job(job),
                            &library_interface,
                            &dependency_interfaces,
                        )?;
                        codegen_objects[job.job_index] = Some(object);
                    }
                    SourcePackJobPhase::Link => {
                        let mut link_handle = executor.begin_link_codegen_objects(job)?;
                        build_plan.try_for_each_link_interface_batch(
                            batch_limits,
                            |link_batch| {
                                let interface_handles =
                                    collect_link_interface_handle_clones_for_batch(
                                        &library_interfaces,
                                        build_plan,
                                        &link_batch,
                                    )?;
                                executor.link_library_interface_batch(
                                    job,
                                    &mut link_handle,
                                    &link_batch,
                                    &interface_handles,
                                )?;
                                release_library_interface_handles_for_link_batch(
                                    build_plan,
                                    &link_batch,
                                    &mut library_interfaces,
                                    executor,
                                )?;
                                Ok::<(), CompileError>(())
                            },
                        )?;
                        build_plan.try_for_each_link_object_batch(batch_limits, |link_batch| {
                            let object_handles = collect_link_object_handle_clones_for_batch(
                                &codegen_objects,
                                build_plan,
                                &link_batch,
                            )?;
                            executor.link_codegen_object_batch(
                                job,
                                &mut link_handle,
                                &link_batch,
                                &object_handles,
                            )?;
                            release_codegen_object_handles_for_link_batch(
                                build_plan,
                                &link_batch,
                                &mut codegen_objects,
                                executor,
                            )?;
                            Ok::<(), CompileError>(())
                        })?;
                        linked_output =
                            Some(executor.finish_link_codegen_objects(job, link_handle)?);
                    }
                }
            }
            Ok(())
        })?;

    let linked_output = linked_output.ok_or_else(|| {
        CompileError::GpuFrontend("source-pack build plan did not execute a link job".into())
    })?;

    Ok(HandleBuildExecutionResult { linked_output })
}

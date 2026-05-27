use super::*;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct JobBatchDependentsPrepareProgress {
    pub(in crate::compiler) version: u32,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) batch_count: usize,
    pub(in crate::compiler) next_batch_index: usize,
    pub(in crate::compiler) dependent_edge_count: usize,
}

pub(in crate::compiler) fn validate_job_batch_dependents_prepare_progress(
    progress: &JobBatchDependentsPrepareProgress,
    target: SourcePackArtifactTarget,
    batch_count: usize,
) -> Result<(), CompileError> {
    if progress.version != SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch dependents prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != target {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependents prepare target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.batch_count != batch_count {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependents prepare batch count {} does not match expected {batch_count}",
            progress.batch_count
        )));
    }
    if progress.next_batch_index > batch_count {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependents prepare next batch {} exceeds batch count {batch_count}",
            progress.next_batch_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn store_job_batch_dependents_pages_from_batch_chunk(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackBuildJobBatchPageIndex,
    max_new_batches: usize,
) -> Result<FilesystemJobBatchDependentsPrepareStepResult, CompileError> {
    if max_new_batches == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack job-batch dependents chunk max_new_batches must be greater than zero"
                .into(),
        ));
    }
    validate_job_batch_page_index(index, target)?;
    let progress_path = store.build_job_batch_dependents_prepare_progress_path_for_target(target);
    let mut progress = if progress_path.is_file() {
        load_job_batch_dependents_prepare_progress(store, target, index.batch_count)?
    } else {
        JobBatchDependentsPrepareProgress {
            version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PREPARE_PROGRESS_VERSION,
            target,
            batch_count: index.batch_count,
            next_batch_index: 0,
            dependent_edge_count: 0,
        }
    };
    validate_job_batch_dependents_prepare_progress(&progress, target, index.batch_count)?;

    let mut new_batch_count = 0usize;
    while progress.next_batch_index < index.batch_count && new_batch_count < max_new_batches {
        let batch_index = progress.next_batch_index;
        let dependency_page = store.load_build_job_batch_page_for_target(target, batch_index)?;
        let mut batch_dependent_edge_count = 0usize;
        for_each_stored_job_batch_dependency_index(
            store,
            target,
            &dependency_page.dependency,
            |dependency_batch_index| {
                if dependency_batch_index >= index.batch_count {
                    return Err(artifact_shard_contract_error(format!(
                        "job-batch page {batch_index} depends on missing batch {dependency_batch_index}"
                    )));
                }
                append_job_batch_dependent_page(
                    store,
                    target,
                    dependency_batch_index,
                    index.batch_count,
                    batch_index,
                )?;
                batch_dependent_edge_count = batch_dependent_edge_count.saturating_add(1);
                Ok(())
            },
        )?;
        progress.dependent_edge_count = progress
            .dependent_edge_count
            .saturating_add(batch_dependent_edge_count);
        progress.next_batch_index = progress.next_batch_index.checked_add(1).ok_or_else(|| {
            artifact_shard_contract_error("job-batch dependents prepare next batch index overflows")
        })?;
        new_batch_count = new_batch_count.checked_add(1).ok_or_else(|| {
            artifact_shard_contract_error("job-batch dependents prepare new batch count overflows")
        })?;
        store_job_batch_dependents_prepare_progress(store, &progress)?;
    }

    Ok(FilesystemJobBatchDependentsPrepareStepResult {
        target,
        complete: progress.next_batch_index == index.batch_count,
        batch_count: index.batch_count,
        next_batch_index: progress.next_batch_index,
        new_batch_count,
        dependent_edge_count: progress.dependent_edge_count,
    })
}

pub(in crate::compiler) fn store_job_batch_dependents_prepare_progress(
    store: &FilesystemArtifactStore,
    progress: &JobBatchDependentsPrepareProgress,
) -> Result<PathBuf, CompileError> {
    validate_job_batch_dependents_prepare_progress(
        progress,
        progress.target,
        progress.batch_count,
    )?;
    let path = store.build_job_batch_dependents_prepare_progress_path_for_target(progress.target);
    let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "serialize source-pack job-batch dependents prepare progress: {err}"
        ))
    })?;
    write_file_atomic(
        &path,
        &bytes,
        "source-pack job-batch dependents prepare progress",
    )?;
    Ok(path)
}

pub(in crate::compiler) fn load_job_batch_dependents_prepare_progress(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_count: usize,
) -> Result<JobBatchDependentsPrepareProgress, CompileError> {
    let path = store.build_job_batch_dependents_prepare_progress_path_for_target(target);
    let bytes = fs::read(&path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "read source-pack job-batch dependents prepare progress {}: {err}",
            path.display()
        ))
    })?;
    let progress =
        serde_json::from_slice::<JobBatchDependentsPrepareProgress>(&bytes).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack job-batch dependents prepare progress {}: {err}",
                path.display()
            ))
        })?;
    validate_job_batch_dependents_prepare_progress(&progress, target, batch_count)?;
    Ok(progress)
}

#[cfg(test)]

pub(in crate::compiler) fn store_job_batch_dependents_from_manifest_dependencies(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_dependencies: &[SourcePackJobBatchDependency],
    batch_count: usize,
) -> Result<(), CompileError> {
    for dependency in batch_dependencies {
        if dependency.batch_index >= batch_count {
            return Err(artifact_shard_contract_error(format!(
                "job-batch dependency {} exceeds batch count {}",
                dependency.batch_index, batch_count
            )));
        }
        for_each_job_batch_dependency_index(dependency, |dependency_batch_index| {
            if dependency_batch_index >= batch_count {
                return Err(artifact_shard_contract_error(format!(
                    "job-batch dependency {} references missing batch {}",
                    dependency.batch_index, dependency_batch_index
                )));
            }
            append_job_batch_dependent_page(
                store,
                target,
                dependency_batch_index,
                batch_count,
                dependency.batch_index,
            )
        })?;
    }
    Ok(())
}

pub(in crate::compiler) fn empty_build_job_batch_dependents_page(
    target: SourcePackArtifactTarget,
    batch_index: usize,
    batch_count: usize,
) -> Result<SourcePackBuildJobBatchDependentsPage, CompileError> {
    let page = SourcePackBuildJobBatchDependentsPage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PAGE_VERSION,
        target,
        batch_count,
        batch_index,
        dependents: SourcePackJobBatchDependents {
            batch_index,
            dependent_batch_indices: Vec::new(),
        },
        dependent_batch_count: 0,
        dependent_page_count: 0,
    };
    validate_job_batch_dependents_page(&page, target, batch_count, Some(batch_index))?;
    Ok(page)
}

pub(in crate::compiler) fn append_job_batch_dependent_page(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_index: usize,
    batch_count: usize,
    dependent_batch_index: usize,
) -> Result<(), CompileError> {
    if batch_index >= batch_count || dependent_batch_index >= batch_count {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependent edge {batch_index}->{dependent_batch_index} exceeds batch count {batch_count}"
        )));
    }
    if batch_index == dependent_batch_index {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependent edge {batch_index}->{dependent_batch_index} is self-referential"
        )));
    }
    let mut dependents_page =
        store.load_build_job_batch_dependents_page_for_target(target, batch_index, batch_count)?;
    if !dependents_page
        .dependents
        .dependent_batch_indices
        .is_empty()
    {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependents page {batch_index} mixes inline dependents with stored dependent pages"
        )));
    }

    let dependent_position = dependents_page.dependent_batch_count;
    let page_index = dependent_position / SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE;
    let is_new_dependent_page =
        dependent_position % SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE == 0;
    let mut dependent_page = if is_new_dependent_page {
        SourcePackBuildJobBatchDependentBatchPage {
            version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENT_BATCH_PAGE_VERSION,
            target,
            batch_count,
            batch_index,
            page_index,
            first_dependent_position: page_index
                .saturating_mul(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE),
            dependent_count: 0,
            dependent_batch_indices: Vec::new(),
        }
    } else {
        store.load_build_job_batch_dependent_batch_page_for_target(
            target,
            batch_index,
            page_index,
            batch_count,
        )?
    };

    dependent_page
        .dependent_batch_indices
        .push(dependent_batch_index);
    dependent_page.dependent_count = dependent_page.dependent_batch_indices.len();
    validate_job_batch_dependent_batch_page(
        &dependent_page,
        target,
        batch_count,
        batch_index,
        page_index,
    )?;
    store.store_build_job_batch_dependent_batch_page(&dependent_page, batch_count)?;

    dependents_page.dependent_batch_count = dependents_page.dependent_batch_count.saturating_add(1);
    dependents_page.dependent_page_count = dependents_page
        .dependent_batch_count
        .div_ceil(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE);
    store.store_build_job_batch_dependents_page(&dependents_page, batch_count)?;
    Ok(())
}

pub(in crate::compiler) fn for_each_job_batch_dependent_index<F>(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_index: usize,
    batch_count: usize,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(usize) -> Result<(), CompileError>,
{
    let dependents_page =
        store.load_build_job_batch_dependents_page_for_target(target, batch_index, batch_count)?;
    if !dependents_page
        .dependents
        .dependent_batch_indices
        .is_empty()
    {
        for &dependent_batch_index in &dependents_page.dependents.dependent_batch_indices {
            visit(dependent_batch_index)?;
        }
        return Ok(());
    }

    let mut seen_dependent_count = 0usize;
    for page_index in 0..dependents_page.dependent_page_count {
        let page = store.load_build_job_batch_dependent_batch_page_for_target(
            target,
            batch_index,
            page_index,
            batch_count,
        )?;
        seen_dependent_count = seen_dependent_count.saturating_add(page.dependent_count);
        for &dependent_batch_index in &page.dependent_batch_indices {
            visit(dependent_batch_index)?;
        }
    }
    if seen_dependent_count != dependents_page.dependent_batch_count {
        return Err(artifact_shard_contract_error(format!(
            "job-batch {batch_index} iterated {seen_dependent_count} dependents but expected {}",
            dependents_page.dependent_batch_count
        )));
    }
    Ok(())
}

use super::*;

pub(in crate::compiler) fn validate_execution_shard_record_count(
    shard_index: usize,
    label: &str,
    count: usize,
    cap: usize,
) -> Result<(), CompileError> {
    if count > cap {
        return Err(artifact_shard_contract_error(format!(
            "execution shard {shard_index} has {count} {label} records but the record cap is {cap}"
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_execution_shard(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    validate_execution_shard_with_mode(
        execution_shard,
        target,
        ExecutionShardValidationMode::Persisted,
    )
}

pub(in crate::compiler) fn validate_execution_shard_store_input(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    validate_execution_shard_with_mode(
        execution_shard,
        target,
        ExecutionShardValidationMode::StoreInput,
    )
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::compiler) enum ExecutionShardValidationMode {
    Persisted,
    StoreInput,
}

pub(in crate::compiler) fn validate_execution_shard_inline_record_count(
    shard_index: usize,
    label: &str,
    count: usize,
    cap: usize,
    mode: ExecutionShardValidationMode,
) -> Result<(), CompileError> {
    if mode == ExecutionShardValidationMode::Persisted && count > cap {
        return Err(artifact_shard_contract_error(format!(
            "execution shard {shard_index} stores {count} inline {label} records, exceeding record cap {cap}"
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_execution_shard_with_mode(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    target: SourcePackArtifactTarget,
    mode: ExecutionShardValidationMode,
) -> Result<(), CompileError> {
    if execution_shard.version != SOURCE_PACK_BUILD_ARTIFACT_EXECUTION_SHARD_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack artifact execution shard version {}; expected {}",
            execution_shard.version, SOURCE_PACK_BUILD_ARTIFACT_EXECUTION_SHARD_VERSION
        )));
    }
    if execution_shard.target != target {
        return Err(artifact_shard_contract_error(format!(
            "execution shard target {:?} does not match requested target {:?}",
            execution_shard.target, target
        )));
    }
    validate_artifact_shard(&execution_shard.shard, target)?;
    let shard = &execution_shard.shard;
    let shard_batch_count = shard.batch_indices.len();
    let shard_job_count = shard.job_indices.len();
    let shard_artifact_ref_count = match mode {
        ExecutionShardValidationMode::Persisted => shard.artifact_record_count(),
        ExecutionShardValidationMode::StoreInput => shard.artifact_count(),
    };
    validate_execution_shard_record_count(
        shard.shard_index,
        "source-file",
        execution_shard.source_files.len(),
        SOURCE_PACK_EXECUTION_SHARD_SOURCE_FILE_DEFAULT_RECORD_CAP,
    )?;
    if !execution_shard.source_files.is_empty()
        && execution_shard.source_files.len() > shard.source_file_count
    {
        return Err(artifact_shard_contract_error(format!(
            "execution shard {} has {} source-file records but the shard records {} source files",
            shard.shard_index,
            execution_shard.source_files.len(),
            shard.source_file_count
        )));
    }
    validate_execution_shard_record_count(
        shard.shard_index,
        "job-batch",
        execution_shard.job_batches.len(),
        shard_batch_count,
    )?;
    validate_execution_shard_record_count(
        shard.shard_index,
        "batch-dependency",
        execution_shard.batch_dependencies.len(),
        shard_batch_count,
    )?;
    validate_execution_shard_record_count(
        shard.shard_index,
        "batch-dependent",
        execution_shard.batch_dependents.len(),
        shard_batch_count,
    )?;
    validate_execution_shard_record_count(
        shard.shard_index,
        "job",
        execution_shard.jobs.len(),
        shard_job_count,
    )?;
    validate_execution_shard_record_count(
        shard.shard_index,
        "job-artifact",
        execution_shard.job_artifacts.len(),
        shard_job_count,
    )?;
    validate_execution_shard_record_count(
        shard.shard_index,
        "artifact-ref",
        execution_shard.artifact_refs.len(),
        shard_artifact_ref_count,
    )?;
    validate_execution_shard_record_count(
        shard.shard_index,
        "link-interface-batch",
        execution_shard.link_interface_batches.len(),
        shard_batch_count,
    )?;
    validate_execution_shard_record_count(
        shard.shard_index,
        "link-object-batch",
        execution_shard.link_object_batches.len(),
        shard_batch_count,
    )?;
    match shard.kind {
        SourcePackBuildArtifactShardKind::JobBatches => {
            if execution_shard.job_batches.len() != shard_batch_count
                || execution_shard.batch_dependencies.len() != shard_batch_count
                || execution_shard.batch_dependents.len() != shard_batch_count
                || !execution_shard.link_interface_batches.is_empty()
                || !execution_shard.link_object_batches.is_empty()
            {
                return Err(artifact_shard_contract_error(format!(
                    "execution shard {} job-batch record arrays do not match shard batch records",
                    shard.shard_index
                )));
            }
        }
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches => {
            if execution_shard.link_interface_batches.len() != shard_batch_count
                || !execution_shard.job_batches.is_empty()
                || !execution_shard.batch_dependencies.is_empty()
                || !execution_shard.batch_dependents.is_empty()
                || !execution_shard.link_object_batches.is_empty()
            {
                return Err(artifact_shard_contract_error(format!(
                    "execution shard {} link-interface record arrays do not match shard batch records",
                    shard.shard_index
                )));
            }
        }
        SourcePackBuildArtifactShardKind::LinkObjectBatches => {
            if execution_shard.link_object_batches.len() != shard_batch_count
                || !execution_shard.job_batches.is_empty()
                || !execution_shard.batch_dependencies.is_empty()
                || !execution_shard.batch_dependents.is_empty()
                || !execution_shard.link_interface_batches.is_empty()
            {
                return Err(artifact_shard_contract_error(format!(
                    "execution shard {} link-object record arrays do not match shard batch records",
                    shard.shard_index
                )));
            }
        }
    }
    if execution_shard.jobs.len() != shard_job_count
        || execution_shard.job_artifacts.len() != shard_job_count
    {
        return Err(artifact_shard_contract_error(format!(
            "execution shard {} job record arrays do not match shard job records",
            shard.shard_index
        )));
    }
    unique_usize_set(
        &execution_shard
            .source_files
            .iter()
            .map(|source_file| source_file.source_index)
            .collect::<Vec<_>>(),
        &format!(
            "execution shard {} source files",
            execution_shard.shard.shard_index
        ),
    )?;
    unique_usize_set(
        &execution_shard
            .batch_dependencies
            .iter()
            .map(|batch| batch.batch_index)
            .collect::<Vec<_>>(),
        &format!(
            "execution shard {} batch dependencies",
            execution_shard.shard.shard_index
        ),
    )?;
    unique_usize_set(
        &execution_shard
            .batch_dependents
            .iter()
            .map(|batch| batch.batch_index)
            .collect::<Vec<_>>(),
        &format!(
            "execution shard {} batch dependents",
            execution_shard.shard.shard_index
        ),
    )?;
    let job_batch_indices = execution_shard
        .job_batches
        .iter()
        .map(|batch| batch.batch_index)
        .collect::<BTreeSet<_>>();
    let dependency_batch_indices = execution_shard
        .batch_dependencies
        .iter()
        .map(|batch| batch.batch_index)
        .collect::<BTreeSet<_>>();
    if job_batch_indices != dependency_batch_indices {
        return Err(artifact_shard_contract_error(format!(
            "execution shard {} job batches {:?} do not match dependency batches {:?}",
            execution_shard.shard.shard_index, job_batch_indices, dependency_batch_indices
        )));
    }
    for dependency in &execution_shard.batch_dependencies {
        validate_execution_shard_inline_record_count(
            shard.shard_index,
            "batch dependency",
            dependency.dependency_batch_indices.len(),
            SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE,
            mode,
        )?;
        validate_execution_shard_inline_record_count(
            shard.shard_index,
            "batch dependency range",
            dependency.dependency_batch_ranges.len(),
            SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE,
            mode,
        )?;
        if !dependency.dependency_batch_indices.is_empty() && dependency.dependency_batch_count != 0
        {
            return Err(artifact_shard_contract_error(format!(
                "execution shard {} batch {} records both inline and paged dependencies",
                execution_shard.shard.shard_index, dependency.batch_index
            )));
        }
        if dependency.dependency_batch_count == 0 {
            if dependency.dependency_page_count != 0 {
                return Err(artifact_shard_contract_error(format!(
                    "execution shard {} batch {} has dependency page count {} without dependencies",
                    execution_shard.shard.shard_index,
                    dependency.batch_index,
                    dependency.dependency_page_count
                )));
            }
        } else {
            let expected_page_count = dependency
                .dependency_batch_count
                .div_ceil(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE);
            if dependency.dependency_page_count != expected_page_count {
                return Err(artifact_shard_contract_error(format!(
                    "execution shard {} batch {} has dependency page count {} but expected {}",
                    execution_shard.shard.shard_index,
                    dependency.batch_index,
                    dependency.dependency_page_count,
                    expected_page_count
                )));
            }
        }
        let explicit_dependencies = unique_usize_set(
            &dependency.dependency_batch_indices,
            &format!(
                "execution shard {} batch {} dependencies",
                execution_shard.shard.shard_index, dependency.batch_index
            ),
        )?;
        validate_job_batch_dependency_range_metadata(
            dependency,
            &format!(
                "execution shard {} batch {}",
                execution_shard.shard.shard_index, dependency.batch_index
            ),
            |message| artifact_shard_contract_error(message),
        )?;
        validate_job_batch_dependency_ranges(
            dependency,
            &explicit_dependencies,
            &format!(
                "execution shard {} batch {}",
                execution_shard.shard.shard_index, dependency.batch_index
            ),
            usize::MAX,
            Some(dependency.batch_index),
            |message| artifact_shard_contract_error(message),
        )?;
    }
    let dependent_record_batch_indices = execution_shard
        .batch_dependents
        .iter()
        .map(|batch| batch.batch_index)
        .collect::<BTreeSet<_>>();
    if execution_shard.shard.kind == SourcePackBuildArtifactShardKind::JobBatches {
        if job_batch_indices != dependent_record_batch_indices {
            return Err(artifact_shard_contract_error(format!(
                "execution shard {} job batches {:?} do not match dependent-record batches {:?}",
                execution_shard.shard.shard_index,
                job_batch_indices,
                dependent_record_batch_indices
            )));
        }
    } else if !dependent_record_batch_indices.is_empty() {
        return Err(artifact_shard_contract_error(format!(
            "execution shard {} has batch dependent records for non-job shard {:?}",
            execution_shard.shard.shard_index, execution_shard.shard.kind
        )));
    }
    for dependents in &execution_shard.batch_dependents {
        validate_execution_shard_inline_record_count(
            shard.shard_index,
            "batch dependent",
            dependents.dependent_batch_indices.len(),
            SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE,
            mode,
        )?;
        if !job_batch_indices.contains(&dependents.batch_index) {
            return Err(artifact_shard_contract_error(format!(
                "execution shard {} has dependent record for batch {} outside shard job batches {:?}",
                execution_shard.shard.shard_index, dependents.batch_index, job_batch_indices
            )));
        }
        unique_usize_set(
            &dependents.dependent_batch_indices,
            &format!(
                "execution shard {} batch {} dependents",
                execution_shard.shard.shard_index, dependents.batch_index
            ),
        )?;
        if dependents
            .dependent_batch_indices
            .contains(&dependents.batch_index)
        {
            return Err(artifact_shard_contract_error(format!(
                "execution shard {} batch {} lists itself as a dependent",
                execution_shard.shard.shard_index, dependents.batch_index
            )));
        }
    }
    unique_usize_set(
        &execution_shard
            .jobs
            .iter()
            .map(|job| job.job_index)
            .collect::<Vec<_>>(),
        &format!("execution shard {} jobs", execution_shard.shard.shard_index),
    )?;
    unique_usize_set(
        &execution_shard
            .job_artifacts
            .iter()
            .map(|job| job.job_index)
            .collect::<Vec<_>>(),
        &format!(
            "execution shard {} job artifacts",
            execution_shard.shard.shard_index
        ),
    )?;
    let execution_artifact_indices = unique_usize_set(
        &execution_shard
            .artifact_refs
            .iter()
            .map(|artifact| artifact.artifact_index)
            .collect::<Vec<_>>(),
        &format!(
            "execution shard {} artifact refs",
            execution_shard.shard.shard_index
        ),
    )?;
    let shard_artifact_indices =
        materialized_execution_shard_artifact_indices(&execution_shard.shard, mode)?;
    if execution_artifact_indices != shard_artifact_indices {
        return Err(artifact_shard_contract_error(format!(
            "execution shard {} artifact refs {:?} do not match shard artifact refs {:?}",
            execution_shard.shard.shard_index, execution_artifact_indices, shard_artifact_indices
        )));
    }
    for job in &execution_shard.jobs {
        validate_job_shape(
            job,
            &format!("execution shard {}", execution_shard.shard.shard_index),
            |message| artifact_shard_contract_error(message),
        )?;
        if !execution_shard.shard.job_indices.contains(&job.job_index) {
            return Err(artifact_shard_contract_error(format!(
                "execution shard {} contains job {} outside shard job set {:?}",
                execution_shard.shard.shard_index, job.job_index, execution_shard.shard.job_indices
            )));
        }
    }
    for job_manifest in &execution_shard.job_artifacts {
        if !execution_shard
            .jobs
            .iter()
            .any(|job| job.job_index == job_manifest.job_index)
        {
            return Err(artifact_shard_contract_error(format!(
                "execution shard {} contains artifact manifest for missing job {}",
                execution_shard.shard.shard_index, job_manifest.job_index
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn materialized_execution_shard_artifact_indices(
    shard: &SourcePackBuildArtifactShard,
    mode: ExecutionShardValidationMode,
) -> Result<BTreeSet<usize>, CompileError> {
    let mut artifact_indices = shard
        .input_artifact_indices
        .iter()
        .chain(shard.output_artifact_indices.iter())
        .copied()
        .collect::<BTreeSet<_>>();
    if mode == ExecutionShardValidationMode::StoreInput {
        for range in &shard.input_artifact_ranges {
            let Some(indices) = range.iter() else {
                return Err(artifact_shard_contract_error(format!(
                    "execution shard {} input artifact range starting at {} overflows",
                    shard.shard_index, range.first_artifact_index
                )));
            };
            artifact_indices.extend(indices);
        }
    }
    Ok(artifact_indices)
}

pub(in crate::compiler) fn prune_persisted_execution_shard_artifact_refs(
    execution_shard: &mut SourcePackBuildArtifactExecutionShard,
) -> Result<(), CompileError> {
    let retained_artifact_indices = materialized_execution_shard_artifact_indices(
        &execution_shard.shard,
        ExecutionShardValidationMode::Persisted,
    )?;
    execution_shard
        .artifact_refs
        .retain(|artifact| retained_artifact_indices.contains(&artifact.artifact_index));
    Ok(())
}

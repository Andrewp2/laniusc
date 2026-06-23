use super::*;

/// Validates the top-level artifact-shard index.
pub(in crate::compiler) fn validate_artifact_shard_index(
    index: &SourcePackBuildArtifactShardIndex,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION {
        return Err(artifact_shard_contract_error(format!(
            "unsupported source-pack artifact shard index version {}; expected {}",
            index.version, SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION
        )));
    }
    if index.shard_count == 0 {
        return Err(artifact_shard_contract_error(
            "artifact shard index has no shards",
        ));
    }
    Ok(())
}

/// Validates one artifact shard against its target and shard limits.
///
/// The shard must carry bounded unique batch, job, and artifact records. Compact
/// input artifact ranges are validated against explicit input artifacts so the
/// two representations do not overlap.
pub(in crate::compiler) fn validate_artifact_shard(
    shard: &SourcePackBuildArtifactShard,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if shard.version != SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION {
        return Err(artifact_shard_contract_error(format!(
            "unsupported source-pack artifact shard version {}; expected {}",
            shard.version, SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION
        )));
    }
    if shard.target != target {
        return Err(artifact_shard_contract_error(format!(
            "shard {} target {:?} does not match index target {:?}",
            shard.shard_index, shard.target, target
        )));
    }
    if shard.batch_indices.is_empty() {
        return Err(artifact_shard_contract_error(format!(
            "shard {} has no batch indices",
            shard.shard_index
        )));
    }
    let limits = shard.limits.normalized();
    if shard.batch_indices.len() > limits.max_batches_per_shard {
        return Err(artifact_shard_contract_error(format!(
            "shard {} has {} batch records but the record cap is {}",
            shard.shard_index,
            shard.batch_indices.len(),
            limits.max_batches_per_shard
        )));
    }
    if shard.job_indices.len() > limits.max_jobs_per_shard {
        return Err(artifact_shard_contract_error(format!(
            "shard {} has {} job records but the record cap is {}",
            shard.shard_index,
            shard.job_indices.len(),
            limits.max_jobs_per_shard
        )));
    }
    let artifact_ref_count = shard
        .input_artifact_indices
        .len()
        .checked_add(shard.input_artifact_ranges.len())
        .ok_or_else(|| {
            artifact_shard_contract_error(format!(
                "shard {} artifact record count overflows",
                shard.shard_index
            ))
        })?
        .checked_add(shard.output_artifact_indices.len())
        .ok_or_else(|| {
            artifact_shard_contract_error(format!(
                "shard {} artifact record count overflows",
                shard.shard_index
            ))
        })?;
    if artifact_ref_count > limits.max_artifacts_per_shard {
        return Err(artifact_shard_contract_error(format!(
            "shard {} has {} artifact records but the record cap is {}",
            shard.shard_index, artifact_ref_count, limits.max_artifacts_per_shard
        )));
    }
    unique_usize_set(
        &shard.batch_indices,
        &format!("shard {} batches", shard.shard_index),
    )?;
    unique_usize_set(
        &shard.job_indices,
        &format!("shard {} jobs", shard.shard_index),
    )?;
    let explicit_input_artifacts = unique_usize_set(
        &shard.input_artifact_indices,
        &format!("shard {} input artifacts", shard.shard_index),
    )?;
    validate_artifact_index_ranges(
        &shard.input_artifact_ranges,
        &explicit_input_artifacts,
        &format!("shard {} input artifact", shard.shard_index),
        |message| artifact_shard_contract_error(message),
    )?;
    unique_usize_set(
        &shard.output_artifact_indices,
        &format!("shard {} output artifacts", shard.shard_index),
    )?;
    let structurally_oversized = shard.batch_count() > limits.max_batches_per_shard
        || shard.job_count() > limits.max_jobs_per_shard
        || artifact_ref_count > limits.max_artifacts_per_shard;
    if structurally_oversized && !shard.oversized {
        return Err(artifact_shard_contract_error(format!(
            "shard {} exceeds shard limits {:?} but oversized flag is false",
            shard.shard_index, shard.limits
        )));
    }
    Ok(())
}

/// Visits each stored artifact shard listed by an index.
pub(in crate::compiler) fn for_each_artifact_shard_from_index<F>(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackBuildArtifactShardIndex,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(&SourcePackBuildArtifactShard) -> Result<(), CompileError>,
{
    validate_artifact_shard_index(index)?;
    if index.target != target {
        return Err(artifact_shard_contract_error(format!(
            "artifact shard index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    for shard_index in 0..index.shard_count {
        let shard = store.load_build_artifact_shard_for_target(target, shard_index)?;
        visit(&shard)?;
    }
    Ok(())
}

/// Visits only job-batch artifact shards listed by an index.
pub(in crate::compiler) fn for_each_job_batch_artifact_shard<F>(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackBuildArtifactShardIndex,
    visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(&SourcePackBuildArtifactShard) -> Result<(), CompileError>,
{
    let mut visit = visit;
    for_each_artifact_shard_from_index(store, target, index, |shard| {
        if shard.kind == SourcePackBuildArtifactShardKind::JobBatches {
            visit(shard)?;
        }
        Ok(())
    })
}

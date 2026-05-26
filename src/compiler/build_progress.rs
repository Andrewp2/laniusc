use super::*;

pub(super) fn validate_source_pack_build_progress_shard(
    shard: &SourcePackBuildProgressShard,
) -> Result<(), CompileError> {
    if shard.version != SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack build progress shard version {}; expected {}",
            shard.version, SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION
        )));
    }
    if shard.batch_indices.len() > DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress shard {} has {} batches but the record cap is {}",
            shard.shard_index,
            shard.batch_indices.len(),
            DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES
        )));
    }
    if shard.completed_batch_indices.len() > DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress shard {} has {} completed batches but the record cap is {}",
            shard.shard_index,
            shard.completed_batch_indices.len(),
            DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES
        )));
    }
    if shard.ready_batch_indices.len() > DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress shard {} has {} ready batches but the record cap is {}",
            shard.shard_index,
            shard.ready_batch_indices.len(),
            DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES
        )));
    }
    if shard.claimed_batches.len() > DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress shard {} has {} claimed batches but the record cap is {}",
            shard.shard_index,
            shard.claimed_batches.len(),
            DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES
        )));
    }
    source_pack_manifest_unique_usize_set(
        &shard.batch_indices,
        &format!("progress shard {} batches", shard.shard_index),
    )?;
    let batch_indices = shard.batch_indices.iter().copied().collect::<BTreeSet<_>>();
    let completed = source_pack_manifest_unique_usize_set(
        &shard.completed_batch_indices,
        &format!("progress shard {} completed batches", shard.shard_index),
    )?;
    let ready = source_pack_manifest_unique_usize_set(
        &shard.ready_batch_indices,
        &format!("progress shard {} ready batches", shard.shard_index),
    )?;
    for batch_index in &completed {
        if !batch_indices.contains(batch_index) {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack progress shard {} completed batch {} outside shard batches {:?}",
                shard.shard_index, batch_index, shard.batch_indices
            )));
        }
    }
    for batch_index in &ready {
        if !batch_indices.contains(batch_index) {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack progress shard {} ready batch {} outside shard batches {:?}",
                shard.shard_index, batch_index, shard.batch_indices
            )));
        }
        if completed.contains(batch_index) {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack progress shard {} marks completed batch {} ready",
                shard.shard_index, batch_index
            )));
        }
    }
    let mut seen_claimed = BTreeSet::new();
    for claim in &shard.claimed_batches {
        if !batch_indices.contains(&claim.batch_index) {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack progress shard {} claimed batch {} outside shard batches {:?}",
                shard.shard_index, claim.batch_index, shard.batch_indices
            )));
        }
        if completed.contains(&claim.batch_index) {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack progress shard {} claims already completed batch {}",
                shard.shard_index, claim.batch_index
            )));
        }
        if !seen_claimed.insert(claim.batch_index) {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack progress shard {} contains duplicate claim for batch {}",
                shard.shard_index, claim.batch_index
            )));
        }
        if claim.worker_id.trim().is_empty() {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack progress shard {} contains empty worker id for batch {}",
                shard.shard_index, claim.batch_index
            )));
        }
    }
    Ok(())
}

pub(super) fn validate_source_pack_build_progress_shard_summary(
    summary: &SourcePackBuildProgressShardSummary,
) -> Result<(), CompileError> {
    if summary.version != SOURCE_PACK_BUILD_PROGRESS_SHARD_SUMMARY_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack build progress shard summary version {}; expected {}",
            summary.version, SOURCE_PACK_BUILD_PROGRESS_SHARD_SUMMARY_VERSION
        )));
    }
    if summary.batch_count > DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress shard summary {} has {} batches but the record cap is {}",
            summary.shard_index, summary.batch_count, DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES
        )));
    }
    if summary.completed_batch_count > summary.batch_count {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress shard summary {} completed {} batches but only has {} batches",
            summary.shard_index, summary.completed_batch_count, summary.batch_count
        )));
    }
    if summary.ready_batch_count > summary.batch_count {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress shard summary {} has {} ready batches but only has {} batches",
            summary.shard_index, summary.ready_batch_count, summary.batch_count
        )));
    }
    if summary.claimed_batch_count > summary.batch_count {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress shard summary {} has {} claimed batches but only has {} batches",
            summary.shard_index, summary.claimed_batch_count, summary.batch_count
        )));
    }
    if summary.ready_claimed_batch_count > summary.ready_batch_count {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress shard summary {} has {} ready claimed batches but only has {} ready batches",
            summary.shard_index, summary.ready_claimed_batch_count, summary.ready_batch_count
        )));
    }
    if summary.ready_claimed_batch_count > summary.claimed_batch_count {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress shard summary {} has {} ready claimed batches but only has {} claimed batches",
            summary.shard_index, summary.ready_claimed_batch_count, summary.claimed_batch_count
        )));
    }
    if summary.ready_batch_count == 0 && summary.first_ready_batch_index.is_some() {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress shard summary {} has no ready batches but first ready batch {:?}",
            summary.shard_index, summary.first_ready_batch_index
        )));
    }
    if summary.ready_batch_count != 0 && summary.first_ready_batch_index.is_none() {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress shard summary {} has {} ready batches but no first ready batch",
            summary.shard_index, summary.ready_batch_count
        )));
    }
    Ok(())
}

pub(super) fn validate_source_pack_build_progress_summary(
    summary: &SourcePackBuildProgressSummary,
) -> Result<(), CompileError> {
    if summary.version != SOURCE_PACK_BUILD_PROGRESS_SUMMARY_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack build progress summary version {}; expected {}",
            summary.version, SOURCE_PACK_BUILD_PROGRESS_SUMMARY_VERSION
        )));
    }
    if summary.completed_batch_count > summary.job_batch_count {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress summary completed {} batches but only has {} job batches",
            summary.completed_batch_count, summary.job_batch_count
        )));
    }
    if summary.job_batch_shard_count > summary.job_batch_count {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress summary has {} job-batch shards but only {} job batches",
            summary.job_batch_shard_count, summary.job_batch_count
        )));
    }
    if summary.ready_batch_count > summary.job_batch_count {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress summary has {} ready batches but only has {} job batches",
            summary.ready_batch_count, summary.job_batch_count
        )));
    }
    if summary.claimed_batch_count > summary.job_batch_count {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress summary has {} claimed batches but only has {} job batches",
            summary.claimed_batch_count, summary.job_batch_count
        )));
    }
    if summary.ready_claimed_batch_count > summary.ready_batch_count {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress summary has {} ready claimed batches but only has {} ready batches",
            summary.ready_claimed_batch_count, summary.ready_batch_count
        )));
    }
    if summary.ready_claimed_batch_count > summary.claimed_batch_count {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress summary has {} ready claimed batches but only has {} claimed batches",
            summary.ready_claimed_batch_count, summary.claimed_batch_count
        )));
    }
    if let Some(first_ready_batch_index) = summary.first_ready_batch_index {
        if first_ready_batch_index >= summary.job_batch_count {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack progress summary first ready batch {} exceeds job batch count {}",
                first_ready_batch_index, summary.job_batch_count
            )));
        }
        if summary.ready_batch_count == 0 {
            return Err(CompileError::GpuFrontend(
                "source-pack progress summary has a first ready batch but zero ready batches"
                    .into(),
            ));
        }
    } else if summary.ready_batch_count != 0 {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress summary has {} ready batches but no first ready batch",
            summary.ready_batch_count
        )));
    }
    Ok(())
}

pub(super) fn source_pack_build_progress_directory_page_index_for_shard(
    shard_index: usize,
) -> usize {
    shard_index / SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE
}

pub(super) fn source_pack_build_progress_directory_page_count(
    summary: &SourcePackBuildProgressSummary,
) -> Result<usize, CompileError> {
    validate_source_pack_build_progress_summary(summary)?;
    Ok(summary
        .job_batch_shard_count
        .div_ceil(SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE))
}

pub(super) fn source_pack_build_progress_directory_page_range(
    summary: &SourcePackBuildProgressSummary,
    directory_page_index: usize,
) -> Result<(usize, usize), CompileError> {
    validate_source_pack_build_progress_summary(summary)?;
    let first_shard_index = directory_page_index
        .checked_mul(SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE)
        .ok_or_else(|| {
            source_pack_artifact_shard_contract_error(format!(
                "source-pack build progress directory page {directory_page_index} start overflows"
            ))
        })?;
    if first_shard_index >= summary.job_batch_shard_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory page {directory_page_index} starts at shard {first_shard_index} but shard count is {}",
            summary.job_batch_shard_count
        )));
    }
    let shard_count = SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE
        .min(summary.job_batch_shard_count - first_shard_index);
    Ok((first_shard_index, shard_count))
}

pub(super) fn validate_source_pack_build_progress_directory_page(
    page: &SourcePackBuildProgressDirectoryPage,
    target: SourcePackArtifactTarget,
    summary: &SourcePackBuildProgressSummary,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack build progress directory page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory page {} target {:?} does not match requested target {:?}",
            page.directory_page_index, page.target, target
        )));
    }
    if summary.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory target {:?} does not match summary target {:?}",
            target, summary.target
        )));
    }
    let (expected_first_shard_index, expected_shard_count) =
        source_pack_build_progress_directory_page_range(summary, page.directory_page_index)?;
    if page.first_shard_index != expected_first_shard_index
        || page.shard_count != expected_shard_count
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory page {} covers shards {}..{} but expected {}..{}",
            page.directory_page_index,
            page.first_shard_index,
            page.first_shard_index.saturating_add(page.shard_count),
            expected_first_shard_index,
            expected_first_shard_index.saturating_add(expected_shard_count)
        )));
    }
    if page.ready_shard_count > page.shard_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory page {} has {} ready shards but only {} shards",
            page.directory_page_index, page.ready_shard_count, page.shard_count
        )));
    }
    if page.ready_claimed_shard_count > page.ready_shard_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory page {} has {} ready-claimed shards but only {} ready shards",
            page.directory_page_index, page.ready_claimed_shard_count, page.ready_shard_count
        )));
    }
    if page.fully_claimed_ready_shard_count > page.ready_claimed_shard_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory page {} has {} fully claimed ready shards but only {} ready-claimed shards",
            page.directory_page_index,
            page.fully_claimed_ready_shard_count,
            page.ready_claimed_shard_count
        )));
    }
    if page.ready_claimed_shard_count == 0 && page.earliest_claim_lease_expires_unix_nanos.is_some()
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory page {} has no ready-claimed shards but an earliest claim lease {:?}",
            page.directory_page_index, page.earliest_claim_lease_expires_unix_nanos
        )));
    }
    let shard_end = page.first_shard_index.saturating_add(page.shard_count);
    if let Some(first_ready_shard_index) = page.first_ready_shard_index {
        if page.ready_shard_count == 0
            || first_ready_shard_index < page.first_shard_index
            || first_ready_shard_index >= shard_end
        {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "source-pack build progress directory page {} has invalid first ready shard {:?}",
                page.directory_page_index, page.first_ready_shard_index
            )));
        }
    } else if page.ready_shard_count != 0 {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory page {} has {} ready shards but no first ready shard",
            page.directory_page_index, page.ready_shard_count
        )));
    }
    Ok(())
}

pub(super) fn source_pack_build_progress_directory_index_page_index_for_directory_page(
    directory_page_index: usize,
) -> usize {
    directory_page_index / SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE
}

pub(super) fn source_pack_build_progress_directory_index_page_count(
    summary: &SourcePackBuildProgressSummary,
) -> Result<usize, CompileError> {
    let directory_page_count = source_pack_build_progress_directory_page_count(summary)?;
    Ok(directory_page_count.div_ceil(SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE))
}

pub(super) fn source_pack_build_progress_directory_index_page_range(
    summary: &SourcePackBuildProgressSummary,
    directory_index_page_index: usize,
) -> Result<(usize, usize), CompileError> {
    let directory_page_count = source_pack_build_progress_directory_page_count(summary)?;
    let first_directory_page_index = directory_index_page_index
        .checked_mul(SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE)
        .ok_or_else(|| {
            source_pack_artifact_shard_contract_error(format!(
                "source-pack build progress directory-index page {directory_index_page_index} start overflows"
            ))
        })?;
    if first_directory_page_index >= directory_page_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory-index page {directory_index_page_index} starts at directory page {first_directory_page_index} but directory page count is {directory_page_count}"
        )));
    }
    let directory_page_count = SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE
        .min(directory_page_count - first_directory_page_index);
    Ok((first_directory_page_index, directory_page_count))
}

pub(super) fn validate_source_pack_build_progress_directory_index_page(
    page: &SourcePackBuildProgressDirectoryIndexPage,
    target: SourcePackArtifactTarget,
    summary: &SourcePackBuildProgressSummary,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack build progress directory-index page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory-index page {} target {:?} does not match requested target {:?}",
            page.directory_index_page_index, page.target, target
        )));
    }
    if summary.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory-index target {:?} does not match summary target {:?}",
            target, summary.target
        )));
    }
    let (expected_first_directory_page_index, expected_directory_page_count) =
        source_pack_build_progress_directory_index_page_range(
            summary,
            page.directory_index_page_index,
        )?;
    if page.first_directory_page_index != expected_first_directory_page_index
        || page.directory_page_count != expected_directory_page_count
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory-index page {} covers directory pages {}..{} but expected {}..{}",
            page.directory_index_page_index,
            page.first_directory_page_index,
            page.first_directory_page_index
                .saturating_add(page.directory_page_count),
            expected_first_directory_page_index,
            expected_first_directory_page_index.saturating_add(expected_directory_page_count)
        )));
    }
    if page.ready_directory_page_count > page.directory_page_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory-index page {} has {} ready directory pages but only {} directory pages",
            page.directory_index_page_index,
            page.ready_directory_page_count,
            page.directory_page_count
        )));
    }
    if page.ready_claimed_directory_page_count > page.ready_directory_page_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory-index page {} has {} ready-claimed directory pages but only {} ready directory pages",
            page.directory_index_page_index,
            page.ready_claimed_directory_page_count,
            page.ready_directory_page_count
        )));
    }
    if page.fully_claimed_ready_directory_page_count > page.ready_claimed_directory_page_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory-index page {} has {} fully claimed ready directory pages but only {} ready-claimed directory pages",
            page.directory_index_page_index,
            page.fully_claimed_ready_directory_page_count,
            page.ready_claimed_directory_page_count
        )));
    }
    if page.ready_claimed_directory_page_count == 0
        && page.earliest_claim_lease_expires_unix_nanos.is_some()
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory-index page {} has no ready-claimed directory pages but an earliest claim lease {:?}",
            page.directory_index_page_index, page.earliest_claim_lease_expires_unix_nanos
        )));
    }
    let directory_page_end = page
        .first_directory_page_index
        .saturating_add(page.directory_page_count);
    if let Some(first_ready_directory_page_index) = page.first_ready_directory_page_index {
        if page.ready_directory_page_count == 0
            || first_ready_directory_page_index < page.first_directory_page_index
            || first_ready_directory_page_index >= directory_page_end
        {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "source-pack build progress directory-index page {} has invalid first ready directory page {:?}",
                page.directory_index_page_index, page.first_ready_directory_page_index
            )));
        }
    } else if page.ready_directory_page_count != 0 {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory-index page {} has {} ready directory pages but no first ready directory page",
            page.directory_index_page_index, page.ready_directory_page_count
        )));
    }
    Ok(())
}

pub(super) fn source_pack_build_progress_shard_summary(
    shard: &SourcePackBuildProgressShard,
) -> Result<SourcePackBuildProgressShardSummary, CompileError> {
    validate_source_pack_build_progress_shard(shard)?;
    let ready_batch_indices = shard
        .ready_batch_indices
        .iter()
        .copied()
        .collect::<BTreeSet<_>>();
    let mut ready_claimed_batch_count = 0usize;
    let mut earliest_claim_lease_expires_unix_nanos = None;
    for claim in &shard.claimed_batches {
        if !ready_batch_indices.contains(&claim.batch_index) {
            continue;
        }
        ready_claimed_batch_count = ready_claimed_batch_count.saturating_add(1);
        if let Some(expires) = claim.lease_expires_unix_nanos {
            earliest_claim_lease_expires_unix_nanos = Some(
                earliest_claim_lease_expires_unix_nanos
                    .map_or(expires, |earliest| expires.min(earliest)),
            );
        }
    }
    let summary = SourcePackBuildProgressShardSummary {
        version: SOURCE_PACK_BUILD_PROGRESS_SHARD_SUMMARY_VERSION,
        target: shard.target,
        shard_index: shard.shard_index,
        batch_count: shard.batch_indices.len(),
        completed_batch_count: shard.completed_batch_indices.len(),
        ready_batch_count: shard.ready_batch_indices.len(),
        first_ready_batch_index: shard.ready_batch_indices.iter().copied().min(),
        claimed_batch_count: shard.claimed_batches.len(),
        ready_claimed_batch_count,
        earliest_claim_lease_expires_unix_nanos,
    };
    validate_source_pack_build_progress_shard_summary(&summary)?;
    Ok(summary)
}

pub(super) fn source_pack_build_progress_shard_ready_batches_are_claimed(
    summary: &SourcePackBuildProgressShardSummary,
    now_unix_nanos: Option<u128>,
) -> bool {
    if summary.ready_batch_count == 0
        || summary.ready_claimed_batch_count < summary.ready_batch_count
    {
        return false;
    }
    match (
        now_unix_nanos,
        summary.earliest_claim_lease_expires_unix_nanos,
    ) {
        (Some(now), Some(expires)) => now < expires,
        _ => true,
    }
}

pub(super) fn source_pack_build_progress_summary_ready_batches_are_claimed(
    summary: &SourcePackBuildProgressSummary,
    now_unix_nanos: Option<u128>,
) -> bool {
    if summary.ready_batch_count == 0
        || summary.ready_claimed_batch_count < summary.ready_batch_count
    {
        return false;
    }
    match (
        now_unix_nanos,
        summary.earliest_claim_lease_expires_unix_nanos,
    ) {
        (Some(now), Some(expires)) => now < expires,
        _ => true,
    }
}

pub(super) fn source_pack_build_progress_directory_ready_shards_are_claimed(
    page: &SourcePackBuildProgressDirectoryPage,
    now_unix_nanos: Option<u128>,
) -> bool {
    if page.ready_shard_count == 0 || page.fully_claimed_ready_shard_count < page.ready_shard_count
    {
        return false;
    }
    match (now_unix_nanos, page.earliest_claim_lease_expires_unix_nanos) {
        (Some(now), Some(expires)) => now < expires,
        _ => true,
    }
}

pub(super) fn source_pack_build_progress_directory_index_ready_pages_are_claimed(
    page: &SourcePackBuildProgressDirectoryIndexPage,
    now_unix_nanos: Option<u128>,
) -> bool {
    if page.ready_directory_page_count == 0
        || page.fully_claimed_ready_directory_page_count < page.ready_directory_page_count
    {
        return false;
    }
    match (now_unix_nanos, page.earliest_claim_lease_expires_unix_nanos) {
        (Some(now), Some(expires)) => now < expires,
        _ => true,
    }
}

pub(super) fn source_pack_validate_progress_shard_matches_artifact_shard(
    progress: &SourcePackBuildProgressShard,
    shard: &SourcePackBuildArtifactShard,
) -> Result<(), CompileError> {
    validate_source_pack_build_progress_shard(progress)?;
    validate_source_pack_build_artifact_shard(shard, progress.target)?;
    if shard.kind != SourcePackBuildArtifactShardKind::JobBatches {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "progress shard {} can only track job-batch artifact shards, found {:?}",
            shard.shard_index, shard.kind
        )));
    }
    if progress.target != shard.target
        || progress.shard_index != shard.shard_index
        || progress.batch_indices != shard.batch_indices
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "progress shard target {:?} index {} batches {:?} do not match artifact shard target {:?} index {} batches {:?}",
            progress.target,
            progress.shard_index,
            progress.batch_indices,
            shard.target,
            shard.shard_index,
            shard.batch_indices
        )));
    }
    Ok(())
}

pub(super) fn load_source_pack_build_state_from_progress_summary(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackBuildState, CompileError> {
    let summary = source_pack_build_progress_summary_for_frontier_bounded(store, target)?;
    source_pack_build_state_from_progress_summary(&summary)
}

pub(super) fn source_pack_build_state_from_progress_summary(
    summary: &SourcePackBuildProgressSummary,
) -> Result<SourcePackBuildState, CompileError> {
    validate_source_pack_build_progress_summary(summary)?;
    let state = SourcePackBuildState {
        version: SOURCE_PACK_BUILD_STATE_VERSION,
        completed_batch_count: summary.completed_batch_count,
        claimed_batch_count: summary.claimed_batch_count,
        linked_output_key: summary.linked_output_key.clone(),
    };
    validate_source_pack_build_state_version(&state)?;
    Ok(state)
}

pub(super) fn validate_source_pack_progress_summary_complete_output(
    store: &SourcePackFilesystemArtifactStore,
    summary: &SourcePackBuildProgressSummary,
) -> Result<(), CompileError> {
    validate_source_pack_build_progress_summary(summary)?;
    if !summary.is_complete() {
        return Ok(());
    }
    let Some(linked_output_key) = &summary.linked_output_key else {
        return Err(CompileError::GpuFrontend(
            "source-pack progress summary is complete but has no linked output key".into(),
        ));
    };
    let linked_output_path = store.path_for_key(linked_output_key)?;
    if !linked_output_path.is_file() {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress summary is complete but linked output artifact {linked_output_key:?} is missing at {}",
            linked_output_path.display()
        )));
    }
    Ok(())
}

pub(super) fn source_pack_root_build_state_marker(
    state: &SourcePackBuildState,
) -> SourcePackBuildState {
    SourcePackBuildState {
        version: SOURCE_PACK_BUILD_STATE_VERSION,
        completed_batch_count: state.completed_batch_count(),
        claimed_batch_count: state.claimed_batch_count,
        linked_output_key: state.linked_output_key.clone(),
    }
}

pub(super) fn source_pack_execution_shard_for_batch_locator(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_index: usize,
) -> Result<SourcePackBuildArtifactExecutionShard, CompileError> {
    let locator = store.load_build_batch_shard_locator_for_target(target, batch_index)?;
    let execution_shard =
        store.load_build_artifact_execution_shard_for_target(target, locator.shard_index)?;
    if execution_shard.shard.kind != SourcePackBuildArtifactShardKind::JobBatches {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "batch {batch_index} locator points to non-job shard {:?}",
            execution_shard.shard.kind
        )));
    }
    if !execution_shard.shard.batch_indices.contains(&batch_index) {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "batch {batch_index} locator points to shard {} with batches {:?}",
            execution_shard.shard.shard_index, execution_shard.shard.batch_indices
        )));
    }
    Ok(execution_shard)
}

pub(super) fn source_pack_progress_shard_for_batch_locator(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_index: usize,
) -> Result<SourcePackBuildProgressShard, CompileError> {
    let locator = store.load_build_batch_shard_locator_for_target(target, batch_index)?;
    let progress = store.load_build_progress_shard_for_target(target, locator.shard_index)?;
    if !progress.batch_indices.contains(&batch_index) {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "batch {batch_index} locator points to progress shard {} with batches {:?}",
            progress.shard_index, progress.batch_indices
        )));
    }
    Ok(progress)
}

pub(super) fn source_pack_progress_batch_is_completed_from_locator(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_index: usize,
) -> Result<bool, CompileError> {
    let progress = source_pack_progress_shard_for_batch_locator(store, target, batch_index)?;
    Ok(progress.is_batch_completed(batch_index))
}

pub(super) fn source_pack_progress_batch_is_ready_unclaimed_from_locator(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_index: usize,
    now_unix_nanos: Option<u128>,
) -> Result<bool, CompileError> {
    let progress = source_pack_progress_shard_for_batch_locator(store, target, batch_index)?;
    Ok(progress.is_batch_ready(batch_index)
        && !progress.is_batch_completed(batch_index)
        && !progress.is_batch_claimed(batch_index, now_unix_nanos)?)
}

pub(super) fn source_pack_build_progress_shard_summary_from_store(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    shard_index: usize,
) -> Result<SourcePackBuildProgressShardSummary, CompileError> {
    if let Some(summary) =
        store.try_load_build_progress_shard_summary_for_target(target, shard_index)?
    {
        return Ok(summary);
    }
    source_pack_build_progress_shard_summary(
        &store.load_build_progress_shard_for_target(target, shard_index)?,
    )
}

pub(super) fn source_pack_build_progress_directory_page_from_summaries(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    summary: &SourcePackBuildProgressSummary,
    directory_page_index: usize,
) -> Result<SourcePackBuildProgressDirectoryPage, CompileError> {
    validate_source_pack_build_progress_summary(summary)?;
    if summary.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory summary target {:?} does not match requested target {:?}",
            summary.target, target
        )));
    }
    let (first_shard_index, shard_count) =
        source_pack_build_progress_directory_page_range(summary, directory_page_index)?;
    let mut ready_shard_count = 0usize;
    let mut first_ready_shard_index = None;
    let mut ready_claimed_shard_count = 0usize;
    let mut fully_claimed_ready_shard_count = 0usize;
    let mut earliest_claim_lease_expires_unix_nanos = None;
    let shard_end = first_shard_index + shard_count;
    for shard_index in first_shard_index..shard_end {
        let shard_summary =
            source_pack_build_progress_shard_summary_from_store(store, target, shard_index)?;
        if shard_summary.ready_batch_count != 0 {
            ready_shard_count = ready_shard_count.saturating_add(1);
            first_ready_shard_index = first_ready_shard_index.or(Some(shard_index));
        }
        if shard_summary.ready_claimed_batch_count != 0 {
            ready_claimed_shard_count = ready_claimed_shard_count.saturating_add(1);
            earliest_claim_lease_expires_unix_nanos = source_pack_progress_summary_min_lease(
                earliest_claim_lease_expires_unix_nanos,
                shard_summary.earliest_claim_lease_expires_unix_nanos,
            );
        }
        if source_pack_build_progress_shard_ready_batches_are_claimed(&shard_summary, None) {
            fully_claimed_ready_shard_count = fully_claimed_ready_shard_count.saturating_add(1);
        }
    }
    let directory_page = SourcePackBuildProgressDirectoryPage {
        version: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_PAGE_VERSION,
        target,
        directory_page_index,
        first_shard_index,
        shard_count,
        ready_shard_count,
        first_ready_shard_index,
        ready_claimed_shard_count,
        fully_claimed_ready_shard_count,
        earliest_claim_lease_expires_unix_nanos,
    };
    validate_source_pack_build_progress_directory_page(&directory_page, target, summary)?;
    Ok(directory_page)
}

pub(super) fn source_pack_build_progress_directory_page_from_store_or_summaries(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    summary: &SourcePackBuildProgressSummary,
    directory_page_index: usize,
) -> Result<SourcePackBuildProgressDirectoryPage, CompileError> {
    if let Some(directory_page) =
        store.try_load_build_progress_directory_page_for_target(target, directory_page_index)?
    {
        validate_source_pack_build_progress_directory_page(&directory_page, target, summary)?;
        return Ok(directory_page);
    }
    source_pack_build_progress_directory_page_from_summaries(
        store,
        target,
        summary,
        directory_page_index,
    )
}

pub(super) fn source_pack_build_progress_directory_index_page_from_directory_pages(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    summary: &SourcePackBuildProgressSummary,
    changed_directory_page: Option<&SourcePackBuildProgressDirectoryPage>,
    directory_index_page_index: usize,
) -> Result<SourcePackBuildProgressDirectoryIndexPage, CompileError> {
    validate_source_pack_build_progress_summary(summary)?;
    if summary.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source-pack build progress directory-index summary target {:?} does not match requested target {:?}",
            summary.target, target
        )));
    }
    if let Some(changed_directory_page) = changed_directory_page {
        validate_source_pack_build_progress_directory_page(
            changed_directory_page,
            target,
            summary,
        )?;
    }
    let (first_directory_page_index, directory_page_count) =
        source_pack_build_progress_directory_index_page_range(summary, directory_index_page_index)?;
    let mut ready_directory_page_count = 0usize;
    let mut first_ready_directory_page_index = None;
    let mut ready_claimed_directory_page_count = 0usize;
    let mut fully_claimed_ready_directory_page_count = 0usize;
    let mut earliest_claim_lease_expires_unix_nanos = None;
    let directory_page_end = first_directory_page_index + directory_page_count;
    for directory_page_index in first_directory_page_index..directory_page_end {
        let directory_page = if changed_directory_page
            .is_some_and(|page| page.directory_page_index == directory_page_index)
        {
            changed_directory_page
                .expect("changed directory page checked above")
                .clone()
        } else {
            source_pack_build_progress_directory_page_from_store_or_summaries(
                store,
                target,
                summary,
                directory_page_index,
            )?
        };
        if directory_page.ready_shard_count != 0 {
            ready_directory_page_count = ready_directory_page_count.saturating_add(1);
            first_ready_directory_page_index =
                first_ready_directory_page_index.or(Some(directory_page_index));
        }
        if directory_page.ready_claimed_shard_count != 0 {
            ready_claimed_directory_page_count =
                ready_claimed_directory_page_count.saturating_add(1);
            earliest_claim_lease_expires_unix_nanos = source_pack_progress_summary_min_lease(
                earliest_claim_lease_expires_unix_nanos,
                directory_page.earliest_claim_lease_expires_unix_nanos,
            );
        }
        if source_pack_build_progress_directory_ready_shards_are_claimed(&directory_page, None) {
            fully_claimed_ready_directory_page_count =
                fully_claimed_ready_directory_page_count.saturating_add(1);
        }
    }
    let page = SourcePackBuildProgressDirectoryIndexPage {
        version: SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION,
        target,
        directory_index_page_index,
        first_directory_page_index,
        directory_page_count,
        ready_directory_page_count,
        first_ready_directory_page_index,
        ready_claimed_directory_page_count,
        fully_claimed_ready_directory_page_count,
        earliest_claim_lease_expires_unix_nanos,
    };
    validate_source_pack_build_progress_directory_index_page(&page, target, summary)?;
    Ok(page)
}

pub(super) fn source_pack_build_progress_directory_index_page_from_store_or_directory_pages(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    summary: &SourcePackBuildProgressSummary,
    changed_directory_page: Option<&SourcePackBuildProgressDirectoryPage>,
    directory_index_page_index: usize,
) -> Result<SourcePackBuildProgressDirectoryIndexPage, CompileError> {
    if let Some(changed_directory_page) = changed_directory_page {
        if source_pack_build_progress_directory_index_page_index_for_directory_page(
            changed_directory_page.directory_page_index,
        ) == directory_index_page_index
        {
            return source_pack_build_progress_directory_index_page_from_directory_pages(
                store,
                target,
                summary,
                Some(changed_directory_page),
                directory_index_page_index,
            );
        }
    }
    if let Some(page) = store.try_load_build_progress_directory_index_page_for_target(
        target,
        directory_index_page_index,
    )? {
        validate_source_pack_build_progress_directory_index_page(&page, target, summary)?;
        return Ok(page);
    }
    source_pack_build_progress_directory_index_page_from_directory_pages(
        store,
        target,
        summary,
        changed_directory_page,
        directory_index_page_index,
    )
}

pub(super) fn source_pack_build_progress_earliest_claim_lease_from_summary_shards_bounded(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    summary: &SourcePackBuildProgressSummary,
    changed_shard_index: Option<usize>,
) -> Result<Option<u128>, CompileError> {
    validate_source_pack_build_progress_summary(summary)?;
    if summary.target != target || summary.ready_claimed_batch_count == 0 {
        return Ok(None);
    }
    let mut earliest = None;
    let changed_directory_page = changed_shard_index
        .map(source_pack_build_progress_directory_page_index_for_shard)
        .map(|directory_page_index| {
            source_pack_build_progress_directory_page_from_summaries(
                store,
                target,
                summary,
                directory_page_index,
            )
        })
        .transpose()?;
    let directory_index_page_count =
        source_pack_build_progress_directory_index_page_count(summary)?;
    for directory_index_page_index in 0..directory_index_page_count {
        let directory_index_page =
            source_pack_build_progress_directory_index_page_from_store_or_directory_pages(
                store,
                target,
                summary,
                changed_directory_page.as_ref(),
                directory_index_page_index,
            )?;
        earliest = source_pack_progress_summary_min_lease(
            earliest,
            directory_index_page.earliest_claim_lease_expires_unix_nanos,
        );
    }
    Ok(earliest)
}

pub(super) fn source_pack_build_progress_summary_for_frontier_bounded(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackBuildProgressSummary, CompileError> {
    store.load_build_progress_summary_for_target(target)
}

pub(super) fn source_pack_build_progress_first_ready_batch_index_from_summary_pages_bounded(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    summary: &SourcePackBuildProgressSummary,
) -> Result<Option<usize>, CompileError> {
    validate_source_pack_build_progress_summary(summary)?;
    if summary.target != target {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress summary target {:?} does not match requested target {:?}",
            summary.target, target
        )));
    }
    if summary.ready_batch_count == 0 {
        return Ok(None);
    }
    let Some(start_batch_index) = summary.first_ready_batch_index else {
        return Ok(None);
    };
    if summary.job_batch_shard_count != 0 {
        let locator = store.load_build_batch_shard_locator_for_target(target, start_batch_index)?;
        if locator.shard_index >= summary.job_batch_shard_count {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "source-pack first ready batch {start_batch_index} points to shard {} but summary records {} job-batch shards",
                locator.shard_index, summary.job_batch_shard_count
            )));
        }
        let first_directory_page_index =
            source_pack_build_progress_directory_page_index_for_shard(locator.shard_index);
        let directory_index_page_count =
            source_pack_build_progress_directory_index_page_count(summary)?;
        let first_directory_index_page_index =
            source_pack_build_progress_directory_index_page_index_for_directory_page(
                first_directory_page_index,
            );
        for directory_index_page_index in
            first_directory_index_page_index..directory_index_page_count
        {
            let directory_index_page =
                source_pack_build_progress_directory_index_page_from_store_or_directory_pages(
                    store,
                    target,
                    summary,
                    None,
                    directory_index_page_index,
                )?;
            if directory_index_page.ready_directory_page_count == 0 {
                continue;
            }
            let directory_start = directory_index_page
                .first_ready_directory_page_index
                .unwrap_or(directory_index_page.first_directory_page_index)
                .max(first_directory_page_index);
            let directory_end = directory_index_page
                .first_directory_page_index
                .saturating_add(directory_index_page.directory_page_count);
            for directory_page_index in directory_start..directory_end {
                let directory_page =
                    source_pack_build_progress_directory_page_from_store_or_summaries(
                        store,
                        target,
                        summary,
                        directory_page_index,
                    )?;
                if directory_page.ready_shard_count == 0 {
                    continue;
                }
                let shard_start = directory_page
                    .first_ready_shard_index
                    .unwrap_or(directory_page.first_shard_index)
                    .max(locator.shard_index);
                let shard_end = directory_page
                    .first_shard_index
                    .saturating_add(directory_page.shard_count);
                for shard_index in shard_start..shard_end {
                    let shard_summary = source_pack_build_progress_shard_summary_from_store(
                        store,
                        target,
                        shard_index,
                    )?;
                    if shard_summary.ready_batch_count == 0 {
                        continue;
                    }
                    if let Some(first_ready) = shard_summary.first_ready_batch_index {
                        if first_ready >= start_batch_index {
                            return Ok(Some(first_ready));
                        }
                    }
                    let progress =
                        store.load_build_progress_shard_for_target(target, shard_index)?;
                    if let Some(first_ready) = progress
                        .ready_batch_indices
                        .iter()
                        .copied()
                        .filter(|&batch_index| {
                            batch_index >= start_batch_index
                                && !progress.is_batch_completed(batch_index)
                        })
                        .min()
                    {
                        return Ok(Some(first_ready));
                    }
                }
            }
        }
        return Ok(None);
    }
    let mut cached_progress = None::<SourcePackBuildProgressShard>;
    for batch_index in start_batch_index..summary.job_batch_count {
        let needs_progress = cached_progress.as_ref().map_or(true, |progress| {
            !progress.batch_indices.contains(&batch_index)
        });
        if needs_progress {
            cached_progress = Some(source_pack_progress_shard_for_batch_locator(
                store,
                target,
                batch_index,
            )?);
        }
        let progress = cached_progress
            .as_ref()
            .expect("progress shard must be loaded before scanning batch");
        if progress.is_batch_ready(batch_index) && !progress.is_batch_completed(batch_index) {
            return Ok(Some(batch_index));
        }
    }
    Ok(None)
}

pub(super) fn source_pack_build_progress_ready_unclaimed_batch_indices_from_summary_limited(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    summary: &SourcePackBuildProgressSummary,
    now_unix_nanos: Option<u128>,
    max_batches: Option<usize>,
) -> Result<Vec<usize>, CompileError> {
    validate_source_pack_build_progress_summary(summary)?;
    if summary.target != target {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress summary target {:?} does not match requested target {:?}",
            summary.target, target
        )));
    }
    if summary.ready_batch_count == 0 || max_batches == Some(0) {
        return Ok(Vec::new());
    }
    if source_pack_build_progress_summary_ready_batches_are_claimed(summary, now_unix_nanos) {
        return Ok(Vec::new());
    }
    let Some(start_batch_index) = summary.first_ready_batch_index else {
        return Ok(Vec::new());
    };

    if summary.job_batch_shard_count != 0 {
        let locator = store.load_build_batch_shard_locator_for_target(target, start_batch_index)?;
        if locator.shard_index >= summary.job_batch_shard_count {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "source-pack first ready batch {start_batch_index} points to shard {} but summary records {} job-batch shards",
                locator.shard_index, summary.job_batch_shard_count
            )));
        }
        let mut ready_batch_indices = Vec::new();
        let mut seen_ready_batch_count = 0usize;
        let first_directory_page_index =
            source_pack_build_progress_directory_page_index_for_shard(locator.shard_index);
        let directory_index_page_count =
            source_pack_build_progress_directory_index_page_count(summary)?;
        let first_directory_index_page_index =
            source_pack_build_progress_directory_index_page_index_for_directory_page(
                first_directory_page_index,
            );
        for directory_index_page_index in
            first_directory_index_page_index..directory_index_page_count
        {
            let directory_index_page =
                source_pack_build_progress_directory_index_page_from_store_or_directory_pages(
                    store,
                    target,
                    summary,
                    None,
                    directory_index_page_index,
                )?;
            if directory_index_page.ready_directory_page_count == 0 {
                continue;
            }
            if source_pack_build_progress_directory_index_ready_pages_are_claimed(
                &directory_index_page,
                now_unix_nanos,
            ) {
                continue;
            }
            let directory_start = directory_index_page
                .first_ready_directory_page_index
                .unwrap_or(directory_index_page.first_directory_page_index)
                .max(first_directory_page_index);
            let directory_end = directory_index_page
                .first_directory_page_index
                .saturating_add(directory_index_page.directory_page_count);
            for directory_page_index in directory_start..directory_end {
                let directory_page =
                    source_pack_build_progress_directory_page_from_store_or_summaries(
                        store,
                        target,
                        summary,
                        directory_page_index,
                    )?;
                if directory_page.ready_shard_count == 0 {
                    continue;
                }
                if source_pack_build_progress_directory_ready_shards_are_claimed(
                    &directory_page,
                    now_unix_nanos,
                ) {
                    continue;
                }
                let shard_start = directory_page
                    .first_ready_shard_index
                    .unwrap_or(directory_page.first_shard_index)
                    .max(locator.shard_index);
                let shard_end = directory_page
                    .first_shard_index
                    .saturating_add(directory_page.shard_count);
                for shard_index in shard_start..shard_end {
                    let shard_summary = source_pack_build_progress_shard_summary_from_store(
                        store,
                        target,
                        shard_index,
                    )?;
                    if shard_summary.ready_batch_count == 0 {
                        continue;
                    }
                    if source_pack_build_progress_shard_ready_batches_are_claimed(
                        &shard_summary,
                        now_unix_nanos,
                    ) {
                        seen_ready_batch_count =
                            seen_ready_batch_count.saturating_add(shard_summary.ready_batch_count);
                        if seen_ready_batch_count >= summary.ready_batch_count {
                            return Ok(ready_batch_indices);
                        }
                        continue;
                    }
                    let progress =
                        store.load_build_progress_shard_for_target(target, shard_index)?;
                    let mut shard_ready_batch_indices = progress
                        .ready_batch_indices
                        .iter()
                        .copied()
                        .filter(|&batch_index| {
                            batch_index >= start_batch_index
                                && !progress.is_batch_completed(batch_index)
                        })
                        .collect::<Vec<_>>();
                    shard_ready_batch_indices.sort_unstable();
                    for batch_index in shard_ready_batch_indices {
                        seen_ready_batch_count = seen_ready_batch_count.saturating_add(1);
                        if !progress.is_batch_claimed(batch_index, now_unix_nanos)? {
                            ready_batch_indices.push(batch_index);
                            if max_batches
                                .is_some_and(|max_batches| ready_batch_indices.len() >= max_batches)
                            {
                                return Ok(ready_batch_indices);
                            }
                        }
                        if seen_ready_batch_count >= summary.ready_batch_count {
                            return Ok(ready_batch_indices);
                        }
                    }
                }
            }
        }
        return Ok(ready_batch_indices);
    }

    let mut ready_batch_indices = Vec::new();
    let mut seen_ready_batch_count = 0usize;
    let mut cached_progress = None::<SourcePackBuildProgressShard>;
    for batch_index in start_batch_index..summary.job_batch_count {
        let needs_progress = cached_progress.as_ref().map_or(true, |progress| {
            !progress.batch_indices.contains(&batch_index)
        });
        if needs_progress {
            cached_progress = Some(source_pack_progress_shard_for_batch_locator(
                store,
                target,
                batch_index,
            )?);
        }
        let progress = cached_progress
            .as_ref()
            .expect("progress shard must be loaded before scanning batch");
        if progress.is_batch_ready(batch_index) && !progress.is_batch_completed(batch_index) {
            seen_ready_batch_count = seen_ready_batch_count.saturating_add(1);
            if !progress.is_batch_claimed(batch_index, now_unix_nanos)? {
                ready_batch_indices.push(batch_index);
                if max_batches.is_some_and(|max_batches| ready_batch_indices.len() >= max_batches) {
                    return Ok(ready_batch_indices);
                }
            }
            if seen_ready_batch_count >= summary.ready_batch_count {
                break;
            }
        }
    }
    Ok(ready_batch_indices)
}

pub(super) fn source_pack_build_progress_first_ready_unclaimed_batch_index_from_summary(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    summary: &SourcePackBuildProgressSummary,
    now_unix_nanos: Option<u128>,
) -> Result<Option<usize>, CompileError> {
    validate_source_pack_build_progress_summary(summary)?;
    if summary.target != target {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack progress summary target {:?} does not match requested target {:?}",
            summary.target, target
        )));
    }
    let Some(first_ready_batch_index) = summary.first_ready_batch_index else {
        return Ok(None);
    };
    if source_pack_build_progress_summary_ready_batches_are_claimed(summary, now_unix_nanos) {
        return Ok(None);
    }
    if source_pack_progress_batch_is_ready_unclaimed_from_locator(
        store,
        target,
        first_ready_batch_index,
        now_unix_nanos,
    )? {
        return Ok(Some(first_ready_batch_index));
    }

    Ok(
        source_pack_build_progress_ready_unclaimed_batch_indices_from_summary_limited(
            store,
            target,
            summary,
            now_unix_nanos,
            Some(1),
        )?
        .first()
        .copied(),
    )
}

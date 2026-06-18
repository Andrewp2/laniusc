use super::*;

/// Version for the persisted source-pack build-state record.
pub const SOURCE_PACK_BUILD_STATE_VERSION: u32 = 1;

/// Lease claim for one artifact-manifest job batch.
///
/// Claims prevent two workers from executing the same batch concurrently. A
/// claim with no expiry remains active until the batch completes or the claim is
/// explicitly pruned by state mutation code.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildBatchClaim {
    pub batch_index: usize,
    pub worker_id: String,
    pub lease_expires_unix_nanos: Option<u128>,
}

impl SourcePackBuildBatchClaim {
    /// Returns whether this claim has expired at `now_unix_nanos`.
    pub fn is_expired(&self, now_unix_nanos: Option<u128>) -> bool {
        matches!(
            (now_unix_nanos, self.lease_expires_unix_nanos),
            (Some(now), Some(expires)) if expires <= now
        )
    }
}

/// Returns the current host time in Unix nanoseconds.
pub(in crate::compiler) fn current_unix_nanos() -> Result<u128, CompileError> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .map_err(|err| CompileError::GpuFrontend(format!("system clock is before epoch: {err}")))
}

/// Returns the earliest non-`None` lease expiry among two candidates.
pub(in crate::compiler) fn earliest_lease_expiry(
    existing: Option<u128>,
    candidate: Option<u128>,
) -> Option<u128> {
    match (existing, candidate) {
        (Some(existing), Some(candidate)) => Some(existing.min(candidate)),
        (Some(existing), None) => Some(existing),
        (None, Some(candidate)) => Some(candidate),
        (None, None) => None,
    }
}

/// Persisted global build state for artifact-manifest execution.
///
/// This record is the small mutable summary guarded by the build-state lock.
/// Detailed ready/completion state lives in progress shards.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildState {
    pub version: u32,
    #[serde(default)]
    pub completed_batch_count: usize,
    #[serde(default)]
    pub claimed_batch_count: usize,
    pub linked_output_key: Option<String>,
}

impl Default for SourcePackBuildState {
    fn default() -> Self {
        Self::new()
    }
}

impl SourcePackBuildState {
    /// Creates an empty build-state record.
    pub fn new() -> Self {
        Self {
            version: SOURCE_PACK_BUILD_STATE_VERSION,
            completed_batch_count: 0,
            claimed_batch_count: 0,
            linked_output_key: None,
        }
    }

    /// Returns the number of completed artifact-manifest batches.
    pub fn completed_batch_count(&self) -> usize {
        self.completed_batch_count
    }
}

/// Version for persisted build-progress shard pages.
pub const SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION: u32 = 1;
/// Version for persisted build-progress shard summaries.
pub const SOURCE_PACK_BUILD_PROGRESS_SHARD_SUMMARY_VERSION: u32 = 1;
/// Version for persisted build-progress directory pages.
pub const SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_PAGE_VERSION: u32 = 1;
/// Version for persisted build-progress directory-index pages.
pub const SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION: u32 = 1;
/// Version for the persisted build-progress summary.
pub const SOURCE_PACK_BUILD_PROGRESS_SUMMARY_VERSION: u32 = 1;
/// Default page size for build-progress directory pages.
pub const SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE: usize = 64;
/// Default page size for build-progress directory-index pages.
pub const SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE: usize = 64;
/// Default number of ready artifact batches returned in one snapshot.
pub const SOURCE_PACK_READY_STATE_BATCH_DEFAULT_LIMIT: usize = 64;
/// Default number of ready work-queue items returned in one snapshot.
pub const SOURCE_PACK_READY_STATE_ITEM_DEFAULT_LIMIT: usize = 64;
/// Default batch limit for one artifact-manifest worker run.
pub const SOURCE_PACK_ARTIFACT_MANIFEST_WORKER_RUN_DEFAULT_BATCH_LIMIT: usize = 64;
/// Default batch limit for full artifact-manifest execution.
pub const SOURCE_PACK_ARTIFACT_MANIFEST_FULL_BUILD_DEFAULT_BATCH_LIMIT: usize = 64;
/// Default item limit for one work-queue worker run.
pub const SOURCE_PACK_WORK_QUEUE_WORKER_RUN_DEFAULT_ITEM_LIMIT: usize = 64;
/// Default bounded chunk limit for library metadata preparation.
pub const SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_CHUNK_LIMIT: usize = 64;
/// Default library limit for full library metadata preparation.
pub const SOURCE_PACK_LIBRARY_METADATA_FULL_PREPARE_DEFAULT_LIBRARY_LIMIT: usize = 64;
/// Default source-file limit for one library metadata preparation chunk.
pub const SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_SOURCE_FILE_LIMIT: usize =
    SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_CHUNK_LIMIT
        * DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES;
/// Default chunk limit for one artifact-build preparation step.
pub const ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT: usize = 64;
/// Default step limit for full artifact-build preparation.
pub const ARTIFACT_BUILD_FULL_PREPARE_DEFAULT_STEP_LIMIT: usize = 64;

/// Clamps a ready-batch request to the default snapshot limit.
pub(in crate::compiler) fn limit_ready_state_batches(max_batches: usize) -> usize {
    max_batches.min(SOURCE_PACK_READY_STATE_BATCH_DEFAULT_LIMIT)
}

/// Clamps a ready-item request to the default snapshot limit.
pub(in crate::compiler) fn limit_ready_state_items(max_items: usize) -> usize {
    max_items.min(SOURCE_PACK_READY_STATE_ITEM_DEFAULT_LIMIT)
}

/// Clamps an artifact worker run to the default batch limit.
pub(in crate::compiler) fn limit_artifact_worker_run_batches(max_batches: usize) -> usize {
    max_batches.min(SOURCE_PACK_ARTIFACT_MANIFEST_WORKER_RUN_DEFAULT_BATCH_LIMIT)
}

/// Clamps full artifact-manifest execution to the default batch limit.
pub(in crate::compiler) fn limit_artifact_manifest_full_build_batches(max_batches: usize) -> usize {
    max_batches.min(SOURCE_PACK_ARTIFACT_MANIFEST_FULL_BUILD_DEFAULT_BATCH_LIMIT)
}

/// Clamps a work-queue worker run to the default item limit.
pub(in crate::compiler) fn limit_work_queue_worker_run_items(max_items: usize) -> usize {
    max_items.min(SOURCE_PACK_WORK_QUEUE_WORKER_RUN_DEFAULT_ITEM_LIMIT)
}

/// Persisted aggregate progress summary for artifact-manifest execution.
///
/// This is the fast path for reporting build progress without scanning every
/// shard. Shard and directory pages remain the source of truth for claim and
/// ready-frontier updates.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildProgressSummary {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub job_batch_count: usize,
    #[serde(default)]
    pub job_batch_shard_count: usize,
    pub completed_batch_count: usize,
    #[serde(default)]
    pub ready_batch_count: usize,
    #[serde(default)]
    pub first_ready_batch_index: Option<usize>,
    #[serde(default)]
    pub claimed_batch_count: usize,
    #[serde(default)]
    pub ready_claimed_batch_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub earliest_claim_lease_expires_unix_nanos: Option<u128>,
    pub linked_output_key: Option<String>,
}

impl SourcePackBuildProgressSummary {
    /// Creates an empty progress summary for a target and job-batch count.
    pub fn new(target: SourcePackArtifactTarget, job_batch_count: usize) -> Self {
        Self {
            version: SOURCE_PACK_BUILD_PROGRESS_SUMMARY_VERSION,
            target,
            job_batch_count,
            job_batch_shard_count: 0,
            completed_batch_count: 0,
            ready_batch_count: 0,
            first_ready_batch_index: None,
            claimed_batch_count: 0,
            ready_claimed_batch_count: 0,
            earliest_claim_lease_expires_unix_nanos: None,
            linked_output_key: None,
        }
    }

    /// Returns whether every planned job batch has completed.
    pub fn is_complete(&self) -> bool {
        self.completed_batch_count == self.job_batch_count
    }
}

/// Persisted progress page for one artifact shard.
///
/// A shard tracks the ready/completed/claimed state for the batch indices owned
/// by one artifact execution shard.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildProgressShard {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub shard_index: usize,
    pub batch_indices: Vec<usize>,
    pub completed_batch_indices: Vec<usize>,
    #[serde(default)]
    pub ready_batch_indices: Vec<usize>,
    #[serde(default)]
    pub claimed_batches: Vec<SourcePackBuildBatchClaim>,
    pub linked_output_key: Option<String>,
}

/// Summary record for one build-progress shard.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildProgressShardSummary {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub shard_index: usize,
    pub batch_count: usize,
    pub completed_batch_count: usize,
    pub ready_batch_count: usize,
    pub first_ready_batch_index: Option<usize>,
    pub claimed_batch_count: usize,
    #[serde(default)]
    pub ready_claimed_batch_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub earliest_claim_lease_expires_unix_nanos: Option<u128>,
}

/// Directory page summarizing a range of build-progress shards.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildProgressDirectoryPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub directory_page_index: usize,
    pub first_shard_index: usize,
    pub shard_count: usize,
    pub ready_shard_count: usize,
    #[serde(default)]
    pub first_ready_shard_index: Option<usize>,
    #[serde(default)]
    pub ready_claimed_shard_count: usize,
    #[serde(default)]
    pub fully_claimed_ready_shard_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub earliest_claim_lease_expires_unix_nanos: Option<u128>,
}

/// Directory-index page summarizing a range of progress directory pages.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildProgressDirectoryIndexPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub directory_index_page_index: usize,
    pub first_directory_page_index: usize,
    pub directory_page_count: usize,
    pub ready_directory_page_count: usize,
    #[serde(default)]
    pub first_ready_directory_page_index: Option<usize>,
    #[serde(default)]
    pub ready_claimed_directory_page_count: usize,
    #[serde(default)]
    pub fully_claimed_ready_directory_page_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub earliest_claim_lease_expires_unix_nanos: Option<u128>,
}

impl SourcePackBuildProgressShard {
    /// Creates an empty progress shard for an artifact shard.
    pub fn new(target: SourcePackArtifactTarget, shard: &SourcePackBuildArtifactShard) -> Self {
        Self {
            version: SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION,
            target,
            shard_index: shard.shard_index,
            batch_indices: shard.batch_indices.clone(),
            completed_batch_indices: Vec::new(),
            ready_batch_indices: Vec::new(),
            claimed_batches: Vec::new(),
            linked_output_key: None,
        }
    }

    /// Returns whether `batch_index` is already completed in this shard.
    pub fn is_batch_completed(&self, batch_index: usize) -> bool {
        self.completed_batch_indices.contains(&batch_index)
    }

    /// Returns currently active claimed batch indices in sorted order.
    pub fn claimed_batch_indices(
        &self,
        now_unix_nanos: Option<u128>,
    ) -> Result<Vec<usize>, CompileError> {
        validate_build_progress_shard(self)?;
        let completed_batch_indices = self
            .completed_batch_indices
            .iter()
            .copied()
            .collect::<BTreeSet<_>>();
        let mut claimed_batch_indices = self
            .claimed_batches
            .iter()
            .filter(|claim| {
                !completed_batch_indices.contains(&claim.batch_index)
                    && !claim.is_expired(now_unix_nanos)
            })
            .map(|claim| claim.batch_index)
            .collect::<Vec<_>>();
        claimed_batch_indices.sort_unstable();
        claimed_batch_indices.dedup();
        Ok(claimed_batch_indices)
    }

    /// Returns whether `batch_index` has an active, unexpired claim.
    pub fn is_batch_claimed(
        &self,
        batch_index: usize,
        now_unix_nanos: Option<u128>,
    ) -> Result<bool, CompileError> {
        validate_build_progress_shard(self)?;
        if self.is_batch_completed(batch_index) {
            return Ok(false);
        }
        Ok(self
            .claimed_batches
            .iter()
            .any(|claim| claim.batch_index == batch_index && !claim.is_expired(now_unix_nanos)))
    }

    /// Returns whether `batch_index` is ready to claim or execute.
    pub fn is_batch_ready(&self, batch_index: usize) -> bool {
        self.ready_batch_indices.contains(&batch_index)
    }

    /// Marks a batch as ready within this shard.
    pub fn record_batch_ready(&mut self, batch_index: usize) -> Result<(), CompileError> {
        validate_build_progress_shard(self)?;
        if !self.batch_indices.contains(&batch_index) {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack progress shard {} cannot ready batch {batch_index}; shard batches are {:?}",
                self.shard_index, self.batch_indices
            )));
        }
        if self.is_batch_completed(batch_index) {
            return Ok(());
        }
        if !self.ready_batch_indices.contains(&batch_index) {
            self.ready_batch_indices.push(batch_index);
            self.ready_batch_indices.sort_unstable();
            self.ready_batch_indices.dedup();
        }
        Ok(())
    }

    /// Removes a batch from the ready set and returns whether anything changed.
    pub fn remove_ready_batch(&mut self, batch_index: usize) -> Result<bool, CompileError> {
        validate_build_progress_shard(self)?;
        let before = self.ready_batch_indices.len();
        self.ready_batch_indices
            .retain(|ready_batch_index| *ready_batch_index != batch_index);
        Ok(before != self.ready_batch_indices.len())
    }

    /// Requires that `batch_index` is actively claimed by `worker_id`.
    pub fn require_batch_claimed_by(
        &self,
        batch_index: usize,
        worker_id: &str,
        now_unix_nanos: Option<u128>,
    ) -> Result<(), CompileError> {
        validate_build_progress_shard(self)?;
        let Some(claim) = self
            .claimed_batches
            .iter()
            .find(|claim| claim.batch_index == batch_index && !claim.is_expired(now_unix_nanos))
        else {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack batch {batch_index} is not claimed by worker {worker_id:?}"
            )));
        };
        if claim.worker_id != worker_id {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack batch {batch_index} is claimed by worker {:?}, not {:?}",
                claim.worker_id, worker_id
            )));
        }
        Ok(())
    }

    /// Removes expired, completed, or duplicate batch claims.
    pub fn prune_inactive_batch_claims(
        &mut self,
        now_unix_nanos: Option<u128>,
    ) -> Result<bool, CompileError> {
        validate_build_progress_shard(self)?;
        Ok(self.prune_inactive_batch_claims_unchecked(now_unix_nanos))
    }

    /// Records or refreshes a worker claim for a ready batch.
    pub fn record_batch_claim(
        &mut self,
        batch_index: usize,
        worker_id: impl Into<String>,
        lease_expires_unix_nanos: Option<u128>,
        now_unix_nanos: Option<u128>,
    ) -> Result<(), CompileError> {
        validate_build_progress_shard(self)?;
        if !self.batch_indices.contains(&batch_index) {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack progress shard {} cannot claim batch {batch_index}; shard batches are {:?}",
                self.shard_index, self.batch_indices
            )));
        }
        let worker_id = worker_id.into();
        if worker_id.trim().is_empty() {
            return Err(CompileError::GpuFrontend(
                "source-pack batch claim worker id must not be empty".into(),
            ));
        }
        if let (Some(now), Some(expires)) = (now_unix_nanos, lease_expires_unix_nanos) {
            if expires <= now {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack batch {batch_index} claim lease expires at {expires}, which is not after now {now}"
                )));
            }
        }
        self.prune_inactive_batch_claims_unchecked(now_unix_nanos);
        if self.is_batch_completed(batch_index) {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack batch {batch_index} is already complete and cannot be claimed"
            )));
        }
        if let Some(claim) = self
            .claimed_batches
            .iter()
            .find(|claim| claim.batch_index == batch_index)
        {
            if claim.worker_id != worker_id {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack batch {batch_index} is already claimed by worker {:?}",
                    claim.worker_id
                )));
            }
        }
        self.claimed_batches
            .retain(|claim| claim.batch_index != batch_index);
        self.claimed_batches.push(SourcePackBuildBatchClaim {
            batch_index,
            worker_id,
            lease_expires_unix_nanos,
        });
        self.claimed_batches
            .sort_by_key(|claim| (claim.batch_index, claim.worker_id.clone()));
        Ok(())
    }

    /// Records a completed batch execution result in this progress shard.
    pub fn record_batch_result(
        &mut self,
        result: &ArtifactStoreBatchExecutionResult,
    ) -> Result<(), CompileError> {
        validate_build_progress_shard(self)?;
        if !self.batch_indices.contains(&result.batch_index) {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack progress shard {} cannot record batch {}; shard batches are {:?}",
                self.shard_index, result.batch_index, self.batch_indices
            )));
        }
        self.remove_ready_batch(result.batch_index)?;
        if !self.is_batch_completed(result.batch_index) {
            self.completed_batch_indices.push(result.batch_index);
            self.completed_batch_indices.sort_unstable();
            self.completed_batch_indices.dedup();
        }
        self.claimed_batches
            .retain(|claim| claim.batch_index != result.batch_index);

        if let Some(linked_output_key) = &result.linked_output_key {
            if self
                .linked_output_key
                .as_ref()
                .is_some_and(|existing| existing != linked_output_key)
            {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack progress shard {} already recorded linked output {:?}, cannot replace with {:?}",
                    self.shard_index,
                    self.linked_output_key.as_deref(),
                    linked_output_key
                )));
            }
            self.linked_output_key = Some(linked_output_key.clone());
        }
        Ok(())
    }

    /// Prunes inactive claims without re-validating the shard first.
    pub(in crate::compiler) fn prune_inactive_batch_claims_unchecked(
        &mut self,
        now_unix_nanos: Option<u128>,
    ) -> bool {
        let before = self.claimed_batches.clone();
        let completed_batch_indices = self
            .completed_batch_indices
            .iter()
            .copied()
            .collect::<BTreeSet<_>>();
        let mut seen_batch_indices = BTreeSet::new();
        self.claimed_batches.retain(|claim| {
            !completed_batch_indices.contains(&claim.batch_index)
                && !claim.is_expired(now_unix_nanos)
                && seen_batch_indices.insert(claim.batch_index)
        });
        self.claimed_batches
            .sort_by_key(|claim| (claim.batch_index, claim.worker_id.clone()));
        before != self.claimed_batches
    }
}

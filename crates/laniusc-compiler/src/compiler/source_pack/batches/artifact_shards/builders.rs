use super::*;

/// Accumulates batch and artifact references before a build-artifact shard is written.
///
/// Builders use sets while collecting records so adjacent batches can be merged
/// without duplicating job or artifact indices. [`Self::finish`] converts those
/// sets into the serialized shard layout and compacts input artifact ranges.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct ArtifactShardBuilder {
    /// Kind of batch records represented by the shard being built.
    pub(in crate::compiler) kind: SourcePackBuildArtifactShardKind,
    /// Batch indices included in insertion order.
    pub(in crate::compiler) batch_indices: Vec<usize>,
    /// Unique schedule job indices touched by the batches.
    pub(in crate::compiler) job_indices: BTreeSet<usize>,
    /// Explicit input artifact indices not represented by a range.
    pub(in crate::compiler) input_artifact_indices: BTreeSet<usize>,
    /// Input artifact ranges gathered from batch-level dependency records.
    pub(in crate::compiler) input_artifact_ranges: Vec<SourcePackArtifactIndexRange>,
    /// Artifact indices produced by the batches.
    pub(in crate::compiler) output_artifact_indices: BTreeSet<usize>,
    /// Combined source byte count for the shard.
    pub(in crate::compiler) source_bytes: usize,
    /// Combined source file count for the shard.
    pub(in crate::compiler) source_file_count: usize,
    /// Combined source line count for the shard.
    pub(in crate::compiler) source_lines: usize,
    /// Whether any absorbed batch was already oversized before sharding.
    pub(in crate::compiler) oversized_batch: bool,
}

impl ArtifactShardBuilder {
    /// Creates an empty builder for a shard kind.
    pub(in crate::compiler) fn new(kind: SourcePackBuildArtifactShardKind) -> Self {
        Self {
            kind,
            batch_indices: Vec::new(),
            job_indices: BTreeSet::new(),
            input_artifact_indices: BTreeSet::new(),
            input_artifact_ranges: Vec::new(),
            output_artifact_indices: BTreeSet::new(),
            source_bytes: 0,
            source_file_count: 0,
            source_lines: 0,
            oversized_batch: false,
        }
    }

    /// Returns whether no batch has been absorbed yet.
    pub(in crate::compiler) fn is_empty(&self) -> bool {
        self.batch_indices.is_empty()
    }

    /// Returns whether absorbing `next` would exceed normalized shard limits.
    ///
    /// The comparison is based on merged batch count, unique job count, and the
    /// compact artifact-record count that would be emitted after range
    /// compaction.
    pub(in crate::compiler) fn would_exceed(
        &self,
        next: &ArtifactShardBuilder,
        limits: SourcePackBuildShardLimits,
    ) -> bool {
        if self.is_empty() {
            return false;
        }
        let batch_count = self
            .batch_indices
            .len()
            .saturating_add(next.batch_indices.len());
        let job_count = self.job_indices.union(&next.job_indices).count();
        let artifact_count = record_union_count(self, next);
        batch_count > limits.max_batches_per_shard
            || job_count > limits.max_jobs_per_shard
            || artifact_count > limits.max_artifacts_per_shard
    }

    /// Merges another builder into this shard candidate.
    ///
    /// Source totals are saturating summaries, while record identities are kept
    /// in sets so duplicate jobs and artifacts collapse before serialization.
    pub(in crate::compiler) fn absorb(&mut self, next: ArtifactShardBuilder) {
        self.batch_indices.extend(next.batch_indices);
        self.job_indices.extend(next.job_indices);
        self.input_artifact_indices
            .extend(next.input_artifact_indices);
        self.input_artifact_ranges
            .extend(next.input_artifact_ranges);
        self.output_artifact_indices
            .extend(next.output_artifact_indices);
        self.source_bytes = self.source_bytes.saturating_add(next.source_bytes);
        self.source_file_count = self
            .source_file_count
            .saturating_add(next.source_file_count);
        self.source_lines = self.source_lines.saturating_add(next.source_lines);
        self.oversized_batch |= next.oversized_batch;
    }

    /// Converts a non-empty builder into a serialized artifact-shard record.
    ///
    /// Input ranges are compacted first, then any explicit input artifact
    /// already covered by a range is removed. The resulting shard is marked
    /// oversized if its final compact record counts exceed the shard limits.
    pub(in crate::compiler) fn finish(
        mut self,
        shard_index: usize,
        target: SourcePackArtifactTarget,
        limits: SourcePackBuildShardLimits,
    ) -> Option<SourcePackBuildArtifactShard> {
        if self.is_empty() {
            return None;
        }
        let input_artifact_ranges =
            compact_artifact_index_ranges(std::mem::take(&mut self.input_artifact_ranges));
        let input_artifact_indices = self
            .input_artifact_indices
            .into_iter()
            .filter(|artifact_index| {
                !artifact_index_covered_by_ranges(*artifact_index, &input_artifact_ranges)
            })
            .collect::<BTreeSet<_>>();
        let artifact_record_count = input_artifact_indices
            .len()
            .saturating_add(input_artifact_ranges.len())
            .saturating_add(self.output_artifact_indices.len());
        let oversized = self.batch_indices.len() > limits.max_batches_per_shard
            || self.job_indices.len() > limits.max_jobs_per_shard
            || artifact_record_count > limits.max_artifacts_per_shard
            || self.oversized_batch;
        Some(SourcePackBuildArtifactShard {
            version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
            target,
            limits,
            shard_index,
            kind: self.kind,
            batch_indices: self.batch_indices,
            job_indices: self.job_indices.into_iter().collect(),
            input_artifact_indices: input_artifact_indices.into_iter().collect(),
            input_artifact_ranges,
            output_artifact_indices: self.output_artifact_indices.into_iter().collect(),
            source_bytes: self.source_bytes,
            source_file_count: self.source_file_count,
            source_lines: self.source_lines,
            oversized,
        })
    }
}

fn record_union_count(left: &ArtifactShardBuilder, right: &ArtifactShardBuilder) -> usize {
    let input_artifact_ranges = compact_artifact_index_ranges(
        left.input_artifact_ranges
            .iter()
            .chain(right.input_artifact_ranges.iter())
            .cloned()
            .collect(),
    );
    let input_artifact_count = left
        .input_artifact_indices
        .iter()
        .chain(right.input_artifact_indices.iter())
        .copied()
        .filter(|artifact_index| {
            !artifact_index_covered_by_ranges(*artifact_index, &input_artifact_ranges)
        })
        .collect::<BTreeSet<_>>()
        .len();
    let output_artifact_count = left
        .output_artifact_indices
        .union(&right.output_artifact_indices)
        .count();
    input_artifact_count
        .saturating_add(input_artifact_ranges.len())
        .saturating_add(output_artifact_count)
}

/// Builds a shard candidate from one job batch and its schedule jobs.
///
/// Each job in the batch contributes a schedule job index and an output artifact
/// index. The batch source totals are copied into the builder so adjacent job
/// batches can be merged into a larger artifact shard.
pub(in crate::compiler) fn job_batch_shard_builder_from_schedule_page(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    batch: &SourcePackJobBatch,
) -> Result<ArtifactShardBuilder, CompileError> {
    let mut builder = ArtifactShardBuilder::new(SourcePackBuildArtifactShardKind::JobBatches);
    builder.batch_indices.push(batch.batch_index);
    builder.oversized_batch = batch.oversized;
    builder.source_bytes = batch.source_bytes;
    builder.source_file_count = batch.source_file_count;
    builder.source_lines = batch.source_lines;

    for &job_index in &batch.job_indices {
        let job = stored_schedule_job_metadata(store, schedule_index, job_index)?;
        builder.job_indices.insert(job_index);
        builder.output_artifact_indices.insert(job.job_index);
    }
    Ok(builder)
}

/// Builds a shard candidate from one link-interface batch page.
///
/// Interface batches consume interface artifacts and do not create schedule-job
/// outputs directly, so the builder records only input artifacts and source
/// totals for later shard aggregation.
pub(in crate::compiler) fn link_interface_batch_shard_builder_from_page(
    page: &SourcePackBuildLinkInterfaceBatchPage,
) -> Result<ArtifactShardBuilder, CompileError> {
    validate_link_interface_batch_page(page, page.target, Some(page.batch_index))?;
    let batch = &page.batch;
    let mut builder =
        ArtifactShardBuilder::new(SourcePackBuildArtifactShardKind::LinkInterfaceBatches);
    builder.batch_indices.push(batch.batch_index);
    builder
        .input_artifact_indices
        .extend(batch.input_interface_artifact_indices.iter().copied());
    builder.source_bytes = batch.source_bytes;
    builder.source_file_count = batch.source_file_count;
    builder.source_lines = batch.source_lines;
    Ok(builder)
}

/// Builds a shard candidate from one link-object batch page.
///
/// Object batches consume object artifacts. Their builder shape mirrors
/// interface batches but records object artifact indices as the shard inputs.
pub(in crate::compiler) fn link_object_batch_shard_builder_from_page(
    page: &SourcePackBuildLinkObjectBatchPage,
) -> Result<ArtifactShardBuilder, CompileError> {
    validate_link_object_batch_page(page, page.target, Some(page.batch_index))?;
    let batch = &page.batch;
    let mut builder =
        ArtifactShardBuilder::new(SourcePackBuildArtifactShardKind::LinkObjectBatches);
    builder.batch_indices.push(batch.batch_index);
    builder
        .input_artifact_indices
        .extend(batch.input_object_artifact_indices.iter().copied());
    builder.source_bytes = batch.source_bytes;
    builder.source_file_count = batch.source_file_count;
    builder.source_lines = batch.source_lines;
    Ok(builder)
}

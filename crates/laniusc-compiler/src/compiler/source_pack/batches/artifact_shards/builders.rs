use super::*;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct ArtifactShardBuilder {
    pub(in crate::compiler) kind: SourcePackBuildArtifactShardKind,
    pub(in crate::compiler) batch_indices: Vec<usize>,
    pub(in crate::compiler) job_indices: BTreeSet<usize>,
    pub(in crate::compiler) input_artifact_indices: BTreeSet<usize>,
    pub(in crate::compiler) input_artifact_ranges: Vec<SourcePackArtifactIndexRange>,
    pub(in crate::compiler) output_artifact_indices: BTreeSet<usize>,
    pub(in crate::compiler) source_bytes: usize,
    pub(in crate::compiler) source_file_count: usize,
    pub(in crate::compiler) source_lines: usize,
    pub(in crate::compiler) oversized_batch: bool,
}

impl ArtifactShardBuilder {
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

    pub(in crate::compiler) fn is_empty(&self) -> bool {
        self.batch_indices.is_empty()
    }

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

use super::*;

/// Current schema version for retained source-pack artifact manifests.
pub const SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION: u32 = 1;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
/// Target namespace used when emitting source-pack artifact keys.
pub enum SourcePackArtifactTarget {
    #[default]
    Generic,
    Wasm,
    X86_64,
}

impl SourcePackArtifactTarget {
    /// Returns the optional target prefix used in artifact keys.
    pub fn key_prefix(self) -> Option<&'static str> {
        match self {
            Self::Generic => None,
            Self::Wasm => Some("wasm"),
            Self::X86_64 => Some("x86_64"),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
/// Retained serializable manifest for source-pack jobs, batches, artifacts, and link inputs.
pub struct SourcePackBuildArtifactManifest {
    pub version: u32,
    #[serde(default)]
    pub target: SourcePackArtifactTarget,
    pub job_count: usize,
    pub job_batch_count: usize,
    pub batch_dependency_count: usize,
    pub artifact_count: usize,
    pub job_artifact_count: usize,
    pub job_artifact_io_count: usize,
    pub artifact_use_count: usize,
    pub link_interface_batch_count: usize,
    pub link_object_batch_count: usize,
    pub job_schedule: SourcePackJobSchedule,
    pub job_batches: SourcePackJobBatchSchedule,
    pub batch_dependencies: SourcePackJobBatchDependencyPlan,
    pub artifacts: SourcePackArtifactManifest,
    pub job_artifacts: SourcePackJobArtifactManifestPlan,
    pub job_artifact_io: SourcePackJobArtifactIoPlan,
    pub artifact_uses: SourcePackArtifactUsePlan,
    pub link_interface_batches: SourcePackLinkInterfaceBatchPlan,
    pub link_object_batches: SourcePackLinkObjectBatchPlan,
}

/// Current schema version for source-pack artifact shard indexes.
pub const SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION: u32 = 1;

/// Default maximum job/link batches retained in one manifest shard.
pub const DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES: usize = 64;
/// Default maximum job records retained in one manifest shard.
pub const DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_JOBS: usize = 256;
/// Default maximum artifact records retained in one manifest shard.
pub const DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_ARTIFACTS: usize = 512;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
/// Record-count bounds for splitting retained manifests into shards.
pub struct SourcePackBuildShardLimits {
    pub max_batches_per_shard: usize,
    pub max_jobs_per_shard: usize,
    pub max_artifacts_per_shard: usize,
}

impl Default for SourcePackBuildShardLimits {
    fn default() -> Self {
        Self {
            max_batches_per_shard: DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES,
            max_jobs_per_shard: DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_JOBS,
            max_artifacts_per_shard: DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_ARTIFACTS,
        }
    }
}

impl SourcePackBuildShardLimits {
    /// Returns shard limits clamped to supported record capacities.
    pub fn normalized(self) -> Self {
        let record_caps = Self::default();
        Self {
            max_batches_per_shard: self
                .max_batches_per_shard
                .max(1)
                .min(record_caps.max_batches_per_shard),
            max_jobs_per_shard: self
                .max_jobs_per_shard
                .max(1)
                .min(record_caps.max_jobs_per_shard),
            max_artifacts_per_shard: self
                .max_artifacts_per_shard
                .max(1)
                .min(record_caps.max_artifacts_per_shard),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
/// Kind of retained manifest data carried by a build artifact shard.
pub enum SourcePackBuildArtifactShardKind {
    JobBatches,
    LinkInterfaceBatches,
    LinkObjectBatches,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
/// Bounded retained manifest slice for a group of jobs or link batches.
pub struct SourcePackBuildArtifactShard {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub limits: SourcePackBuildShardLimits,
    pub shard_index: usize,
    pub kind: SourcePackBuildArtifactShardKind,
    pub batch_indices: Vec<usize>,
    pub job_indices: Vec<usize>,
    pub input_artifact_indices: Vec<usize>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub input_artifact_ranges: Vec<SourcePackArtifactIndexRange>,
    pub output_artifact_indices: Vec<usize>,
    pub source_bytes: usize,
    pub source_file_count: usize,
    #[serde(default)]
    pub source_lines: usize,
    pub oversized: bool,
}

impl SourcePackBuildArtifactShard {
    /// Returns the number of job/link batches represented by this shard.
    pub fn batch_count(&self) -> usize {
        self.batch_indices.len()
    }

    /// Returns the number of jobs referenced by this shard.
    pub fn job_count(&self) -> usize {
        self.job_indices.len()
    }

    /// Returns total input and output artifact count represented by this shard.
    pub fn artifact_count(&self) -> usize {
        self.input_artifact_indices
            .len()
            .saturating_add(artifact_index_range_count(&self.input_artifact_ranges))
            .saturating_add(self.output_artifact_indices.len())
    }

    /// Returns the number of artifact records stored after range compaction.
    pub fn artifact_record_count(&self) -> usize {
        self.input_artifact_indices
            .len()
            .saturating_add(self.input_artifact_ranges.len())
            .saturating_add(self.output_artifact_indices.len())
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
/// Summary index for all retained build artifact shards.
pub struct SourcePackBuildArtifactShardIndex {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub limits: SourcePackBuildShardLimits,
    pub shard_count: usize,
    pub job_count: usize,
    pub job_batch_count: usize,
    pub artifact_count: usize,
    pub link_interface_batch_count: usize,
    pub link_object_batch_count: usize,
}

impl SourcePackBuildArtifactShardIndex {
    /// Returns the number of shards described by this index.
    pub fn shard_count(&self) -> usize {
        self.shard_count
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// In-memory shard index plus retained shard records.
pub struct SourcePackBuildArtifactShardPlan {
    pub index: SourcePackBuildArtifactShardIndex,
    pub shards: Vec<SourcePackBuildArtifactShard>,
}

impl SourcePackBuildArtifactShardPlan {
    /// Returns the number of shards in the plan.
    pub fn shard_count(&self) -> usize {
        self.index.shard_count()
    }

    /// Returns the largest batch count of any shard.
    pub fn max_shard_batch_count(&self) -> usize {
        self.shards
            .iter()
            .map(SourcePackBuildArtifactShard::batch_count)
            .max()
            .unwrap_or(0)
    }

    /// Returns the largest job count of any shard.
    pub fn max_shard_job_count(&self) -> usize {
        self.shards
            .iter()
            .map(SourcePackBuildArtifactShard::job_count)
            .max()
            .unwrap_or(0)
    }

    /// Returns the largest artifact-record count of any shard.
    pub fn max_shard_artifact_count(&self) -> usize {
        self.shards
            .iter()
            .map(SourcePackBuildArtifactShard::artifact_record_count)
            .max()
            .unwrap_or(0)
    }

    /// Counts shards that exceed normalized limits.
    pub fn oversized_shard_count(&self) -> usize {
        self.shards.iter().filter(|shard| shard.oversized).count()
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
/// Per-job artifact indices split by artifact kind for shard and dependency planning.
pub(in crate::codegen::unit) struct SourcePackArtifactIndicesByKind {
    pub(in crate::codegen::unit) library_interfaces: Vec<usize>,
    pub(in crate::codegen::unit) codegen_objects: Vec<usize>,
    pub(in crate::codegen::unit) linked_outputs: Vec<usize>,
}

#[derive(Clone, Debug)]
/// Incremental builder for one source-pack build artifact shard.
pub(in crate::codegen::unit) struct SourcePackBuildArtifactShardBuilder {
    kind: SourcePackBuildArtifactShardKind,
    batch_indices: Vec<usize>,
    job_indices: BTreeSet<usize>,
    input_artifact_indices: BTreeSet<usize>,
    input_artifact_ranges: Vec<SourcePackArtifactIndexRange>,
    output_artifact_indices: BTreeSet<usize>,
    source_bytes: usize,
    source_file_count: usize,
    source_lines: usize,
    oversized_batch: bool,
}

impl SourcePackBuildArtifactShardBuilder {
    fn new(kind: SourcePackBuildArtifactShardKind) -> Self {
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

    fn is_empty(&self) -> bool {
        self.batch_indices.is_empty()
    }

    fn would_exceed(
        &self,
        next: &SourcePackBuildArtifactShardBuilder,
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
        let artifact_count = build_shard_artifact_union_count(self, next);
        batch_count > limits.max_batches_per_shard
            || job_count > limits.max_jobs_per_shard
            || artifact_count > limits.max_artifacts_per_shard
    }

    fn absorb(&mut self, next: SourcePackBuildArtifactShardBuilder) {
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

    fn finish(
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

/// Returns artifact indices for one job and artifact kind, or an empty slice if absent.
pub(in crate::codegen::unit) fn artifact_indices_for_job_kind(
    artifact_indices_by_job_and_kind: &[SourcePackArtifactIndicesByKind],
    job_index: usize,
    kind: SourcePackArtifactKind,
) -> &[usize] {
    let Some(artifact_indices) = artifact_indices_by_job_and_kind.get(job_index) else {
        return &[];
    };
    match kind {
        SourcePackArtifactKind::LibraryInterface => &artifact_indices.library_interfaces,
        SourcePackArtifactKind::CodegenObject => &artifact_indices.codegen_objects,
        SourcePackArtifactKind::LinkedOutput => &artifact_indices.linked_outputs,
    }
}

/// Returns a compact interface-artifact range when a dependency job range is contiguous.
pub(in crate::codegen::unit) fn interface_artifact_range_for_job_range(
    artifact_indices_by_job_and_kind: &[SourcePackArtifactIndicesByKind],
    dependency_job_range: &SourcePackJobIndexRange,
) -> Option<SourcePackArtifactIndexRange> {
    if dependency_job_range.job_count == 0 {
        return None;
    }
    let end_job_index = dependency_job_range.end_job_index()?;
    let first_artifact_index = artifact_indices_for_job_kind(
        artifact_indices_by_job_and_kind,
        dependency_job_range.first_job_index,
        SourcePackArtifactKind::LibraryInterface,
    )
    .first()
    .copied()?;
    let last_artifact_index = artifact_indices_for_job_kind(
        artifact_indices_by_job_and_kind,
        end_job_index - 1,
        SourcePackArtifactKind::LibraryInterface,
    )
    .first()
    .copied()?;
    let artifact_count = last_artifact_index
        .checked_sub(first_artifact_index)
        .and_then(|count| count.checked_add(1))?;
    (artifact_count == dependency_job_range.job_count).then_some(SourcePackArtifactIndexRange {
        first_artifact_index,
        artifact_count,
    })
}

/// Pushes interface inputs for a dependency job range as either one range or unique indices.
pub(in crate::codegen::unit) fn push_interface_artifact_inputs_for_job_range(
    artifact_indices_by_job_and_kind: &[SourcePackArtifactIndicesByKind],
    dependency_job_range: &SourcePackJobIndexRange,
    input_interface_artifact_ranges: &mut Vec<SourcePackArtifactIndexRange>,
    input_interface_artifact_indices: &mut Vec<usize>,
) {
    if let Some(artifact_range) = interface_artifact_range_for_job_range(
        artifact_indices_by_job_and_kind,
        dependency_job_range,
    ) {
        input_interface_artifact_ranges.push(artifact_range);
        return;
    }
    let Some(dependency_job_indices) = dependency_job_range.iter() else {
        return;
    };
    for dependency_job_index in dependency_job_indices {
        for &artifact_index in artifact_indices_for_job_kind(
            artifact_indices_by_job_and_kind,
            dependency_job_index,
            SourcePackArtifactKind::LibraryInterface,
        ) {
            push_unique(input_interface_artifact_indices, artifact_index);
        }
    }
}

impl SourcePackBuildArtifactManifest {
    /// Builds only the shard index, without retaining individual shard records.
    pub fn build_artifact_shard_index(
        &self,
        limits: SourcePackBuildShardLimits,
    ) -> SourcePackBuildArtifactShardIndex {
        let limits = limits.normalized();
        let link_job_index = self
            .job_schedule
            .jobs
            .iter()
            .find(|job| job.phase == SourcePackJobPhase::Link)
            .map(|job| job.job_index);
        let shard_count = count_build_shards(
            SourcePackBuildArtifactShardKind::JobBatches,
            limits,
            self.job_batches
                .batches
                .iter()
                .map(|batch| self.job_batch_shard_builder(batch)),
        )
        .saturating_add(count_build_shards(
            SourcePackBuildArtifactShardKind::LinkInterfaceBatches,
            limits,
            self.link_interface_batches
                .batches
                .iter()
                .map(|batch| link_interface_batch_shard_builder(batch, link_job_index)),
        ))
        .saturating_add(count_build_shards(
            SourcePackBuildArtifactShardKind::LinkObjectBatches,
            limits,
            self.link_object_batches
                .batches
                .iter()
                .map(|batch| link_object_batch_shard_builder(batch, link_job_index)),
        ));

        SourcePackBuildArtifactShardIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
            target: self.target,
            limits,
            shard_count,
            job_count: self.job_schedule.jobs.len(),
            job_batch_count: self.job_batches.batches.len(),
            artifact_count: self.artifacts.artifacts.len(),
            link_interface_batch_count: self.link_interface_batches.batches.len(),
            link_object_batch_count: self.link_object_batches.batches.len(),
        }
    }

    /// Streams retained build artifact shards and returns the resulting shard index.
    pub fn try_for_each_build_artifact_shard<E, F>(
        &self,
        limits: SourcePackBuildShardLimits,
        mut visitor: F,
    ) -> Result<SourcePackBuildArtifactShardIndex, E>
    where
        F: FnMut(&SourcePackBuildArtifactShard) -> Result<(), E>,
    {
        let limits = limits.normalized();
        let link_job_index = self
            .job_schedule
            .jobs
            .iter()
            .find(|job| job.phase == SourcePackJobPhase::Link)
            .map(|job| job.job_index);
        let mut next_shard_index = 0usize;

        try_emit_build_shards(
            &mut next_shard_index,
            self.target,
            limits,
            SourcePackBuildArtifactShardKind::JobBatches,
            self.job_batches
                .batches
                .iter()
                .map(|batch| self.job_batch_shard_builder(batch)),
            &mut visitor,
        )?;
        try_emit_build_shards(
            &mut next_shard_index,
            self.target,
            limits,
            SourcePackBuildArtifactShardKind::LinkInterfaceBatches,
            self.link_interface_batches
                .batches
                .iter()
                .map(|batch| link_interface_batch_shard_builder(batch, link_job_index)),
            &mut visitor,
        )?;
        try_emit_build_shards(
            &mut next_shard_index,
            self.target,
            limits,
            SourcePackBuildArtifactShardKind::LinkObjectBatches,
            self.link_object_batches
                .batches
                .iter()
                .map(|batch| link_object_batch_shard_builder(batch, link_job_index)),
            &mut visitor,
        )?;

        Ok(SourcePackBuildArtifactShardIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
            target: self.target,
            limits,
            shard_count: next_shard_index,
            job_count: self.job_schedule.jobs.len(),
            job_batch_count: self.job_batches.batches.len(),
            artifact_count: self.artifacts.artifacts.len(),
            link_interface_batch_count: self.link_interface_batches.batches.len(),
            link_object_batch_count: self.link_object_batches.batches.len(),
        })
    }

    /// Builds and retains all artifact shards in memory.
    pub fn build_artifact_shard_plan(
        &self,
        limits: SourcePackBuildShardLimits,
    ) -> SourcePackBuildArtifactShardPlan {
        let limits = limits.normalized();
        let link_job_index = self
            .job_schedule
            .jobs
            .iter()
            .find(|job| job.phase == SourcePackJobPhase::Link)
            .map(|job| job.job_index);
        let mut shards = Vec::new();

        append_build_shards(
            &mut shards,
            self.target,
            limits,
            SourcePackBuildArtifactShardKind::JobBatches,
            self.job_batches
                .batches
                .iter()
                .map(|batch| self.job_batch_shard_builder(batch)),
        );
        append_build_shards(
            &mut shards,
            self.target,
            limits,
            SourcePackBuildArtifactShardKind::LinkInterfaceBatches,
            self.link_interface_batches
                .batches
                .iter()
                .map(|batch| link_interface_batch_shard_builder(batch, link_job_index)),
        );
        append_build_shards(
            &mut shards,
            self.target,
            limits,
            SourcePackBuildArtifactShardKind::LinkObjectBatches,
            self.link_object_batches
                .batches
                .iter()
                .map(|batch| link_object_batch_shard_builder(batch, link_job_index)),
        );

        let index = SourcePackBuildArtifactShardIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
            target: self.target,
            limits,
            shard_count: shards.len(),
            job_count: self.job_schedule.jobs.len(),
            job_batch_count: self.job_batches.batches.len(),
            artifact_count: self.artifacts.artifacts.len(),
            link_interface_batch_count: self.link_interface_batches.batches.len(),
            link_object_batch_count: self.link_object_batches.batches.len(),
        };
        SourcePackBuildArtifactShardPlan { index, shards }
    }

    fn job_batch_shard_builder(
        &self,
        batch: &SourcePackJobBatch,
    ) -> SourcePackBuildArtifactShardBuilder {
        let mut builder =
            SourcePackBuildArtifactShardBuilder::new(SourcePackBuildArtifactShardKind::JobBatches);
        builder.batch_indices.push(batch.batch_index);
        builder.oversized_batch = batch.oversized;
        builder.source_bytes = batch.source_bytes;
        builder.source_file_count = batch.source_file_count;
        builder.source_lines = batch.source_lines;

        for &job_index in &batch.job_indices {
            builder.job_indices.insert(job_index);
            let job_phase = self
                .job_schedule
                .jobs
                .get(job_index)
                .map(|job| job.phase)
                .unwrap_or(SourcePackJobPhase::Codegen);
            let Some(io) = self.job_artifact_io.jobs.get(job_index) else {
                continue;
            };
            if job_phase != SourcePackJobPhase::Link {
                builder
                    .input_artifact_indices
                    .extend(io.input_interface_artifact_indices.iter().copied());
                builder
                    .input_artifact_ranges
                    .extend(io.input_interface_artifact_ranges.iter().cloned());
                builder
                    .input_artifact_indices
                    .extend(io.input_object_artifact_indices.iter().copied());
                builder
                    .input_artifact_ranges
                    .extend(io.input_object_artifact_ranges.iter().cloned());
            }
            builder
                .output_artifact_indices
                .extend(io.output_artifact_indices.iter().copied());
        }
        builder
    }
}

/// Appends normalized build shards for a stream of same-kind shard builders.
pub(in crate::codegen::unit) fn append_build_shards<I>(
    shards: &mut Vec<SourcePackBuildArtifactShard>,
    target: SourcePackArtifactTarget,
    limits: SourcePackBuildShardLimits,
    kind: SourcePackBuildArtifactShardKind,
    items: I,
) where
    I: IntoIterator<Item = SourcePackBuildArtifactShardBuilder>,
{
    let mut current = SourcePackBuildArtifactShardBuilder::new(kind);
    for item in items {
        if current.would_exceed(&item, limits) {
            if let Some(shard) = current.finish(shards.len(), target, limits) {
                shards.push(shard);
            }
            current = SourcePackBuildArtifactShardBuilder::new(kind);
        }
        current.absorb(item);
    }
    if let Some(shard) = current.finish(shards.len(), target, limits) {
        shards.push(shard);
    }
}

/// Visits normalized build shards without retaining the shard records in memory.
pub(in crate::codegen::unit) fn try_emit_build_shards<I, F, E>(
    next_shard_index: &mut usize,
    target: SourcePackArtifactTarget,
    limits: SourcePackBuildShardLimits,
    kind: SourcePackBuildArtifactShardKind,
    items: I,
    visitor: &mut F,
) -> Result<(), E>
where
    I: IntoIterator<Item = SourcePackBuildArtifactShardBuilder>,
    F: FnMut(&SourcePackBuildArtifactShard) -> Result<(), E>,
{
    let mut current = SourcePackBuildArtifactShardBuilder::new(kind);
    for item in items {
        if current.would_exceed(&item, limits) {
            if let Some(shard) = current.finish(*next_shard_index, target, limits) {
                visitor(&shard)?;
                *next_shard_index = (*next_shard_index).saturating_add(1);
            }
            current = SourcePackBuildArtifactShardBuilder::new(kind);
        }
        current.absorb(item);
    }
    if let Some(shard) = current.finish(*next_shard_index, target, limits) {
        visitor(&shard)?;
        *next_shard_index = (*next_shard_index).saturating_add(1);
    }
    Ok(())
}

/// Counts the shards that would be emitted for a stream of same-kind shard builders.
pub(in crate::codegen::unit) fn count_build_shards<I>(
    kind: SourcePackBuildArtifactShardKind,
    limits: SourcePackBuildShardLimits,
    items: I,
) -> usize
where
    I: IntoIterator<Item = SourcePackBuildArtifactShardBuilder>,
{
    let mut shard_count = 0usize;
    let mut current = SourcePackBuildArtifactShardBuilder::new(kind);
    for item in items {
        if current.would_exceed(&item, limits) {
            if !current.is_empty() {
                shard_count = shard_count.saturating_add(1);
            }
            current = SourcePackBuildArtifactShardBuilder::new(kind);
        }
        current.absorb(item);
    }
    if !current.is_empty() {
        shard_count = shard_count.saturating_add(1);
    }
    shard_count
}

/// Builds a shard contribution record for one interface-link batch.
pub(in crate::codegen::unit) fn link_interface_batch_shard_builder(
    batch: &SourcePackLinkInterfaceBatch,
    link_job_index: Option<usize>,
) -> SourcePackBuildArtifactShardBuilder {
    let mut builder = SourcePackBuildArtifactShardBuilder::new(
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches,
    );
    builder.batch_indices.push(batch.batch_index);
    if let Some(link_job_index) = link_job_index {
        builder.job_indices.insert(link_job_index);
    }
    builder
        .input_artifact_indices
        .extend(batch.input_interface_artifact_indices.iter().copied());
    builder.source_bytes = batch.source_bytes;
    builder.source_file_count = batch.source_file_count;
    builder.source_lines = batch.source_lines;
    builder
}

/// Builds a shard contribution record for one object-link batch.
pub(in crate::codegen::unit) fn link_object_batch_shard_builder(
    batch: &SourcePackLinkObjectBatch,
    link_job_index: Option<usize>,
) -> SourcePackBuildArtifactShardBuilder {
    let mut builder = SourcePackBuildArtifactShardBuilder::new(
        SourcePackBuildArtifactShardKind::LinkObjectBatches,
    );
    builder.batch_indices.push(batch.batch_index);
    if let Some(link_job_index) = link_job_index {
        builder.job_indices.insert(link_job_index);
    }
    builder
        .input_artifact_indices
        .extend(batch.input_object_artifact_indices.iter().copied());
    builder.source_bytes = batch.source_bytes;
    builder.source_file_count = batch.source_file_count;
    builder.source_lines = batch.source_lines;
    builder
}

/// Counts the compact artifact record union of two shard builders.
pub(in crate::codegen::unit) fn build_shard_artifact_union_count(
    left: &SourcePackBuildArtifactShardBuilder,
    right: &SourcePackBuildArtifactShardBuilder,
) -> usize {
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

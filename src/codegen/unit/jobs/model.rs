use std::{collections::BTreeSet, ops::Range};

use serde::{Deserialize, Serialize};

use super::*;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackJobPlan {
    pub libraries: LibraryUnitPlan,
    pub frontend_units: FrontendUnitPlan,
    pub codegen_units: CodegenUnitPlan,
    pub library_dependencies: Vec<SourcePackLibraryDependency>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibraryDependency {
    pub library_id: u32,
    pub depends_on_library_id: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum SourcePackJobPhase {
    LibraryFrontend,
    Codegen,
    Link,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJob {
    pub job_index: usize,
    pub phase: SourcePackJobPhase,
    pub phase_unit_index: usize,
    pub library_job_index: Option<usize>,
    pub library_id: u32,
    pub first_source_index: usize,
    pub source_file_count: usize,
    pub source_bytes: usize,
    pub source_lines: usize,
    pub oversized_source_file: bool,
    pub dependency_job_indices: Vec<usize>,
}

impl SourcePackJob {
    pub fn source_range(&self) -> Range<usize> {
        self.first_source_index..self.first_source_index + self.source_file_count
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJobSchedule {
    pub jobs: Vec<SourcePackJob>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub dependency_job_ranges_by_job_index: Vec<Vec<SourcePackJobIndexRange>>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJobWave {
    pub wave_index: usize,
    pub job_indices: Vec<usize>,
    pub source_bytes: usize,
    pub source_file_count: usize,
    #[serde(default)]
    pub source_lines: usize,
}

impl SourcePackJobWave {
    pub fn job_count(&self) -> usize {
        self.job_indices.len()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJobBatchLimits {
    pub max_jobs_per_batch: usize,
    pub max_source_bytes_per_batch: usize,
    pub max_source_files_per_batch: usize,
}

impl Default for SourcePackJobBatchLimits {
    fn default() -> Self {
        Self::from_codegen_unit_limits(CodegenUnitLimits::default())
    }
}

impl SourcePackJobBatchLimits {
    pub fn from_codegen_unit_limits(limits: CodegenUnitLimits) -> Self {
        let limits = limits.normalized();
        Self {
            max_jobs_per_batch: limits.max_source_files,
            max_source_bytes_per_batch: limits.max_source_bytes,
            max_source_files_per_batch: limits.max_source_files,
        }
    }

    pub fn normalized(self) -> Self {
        let record_caps = Self::from_codegen_unit_limits(CodegenUnitLimits::default());
        Self {
            max_jobs_per_batch: self
                .max_jobs_per_batch
                .max(1)
                .min(record_caps.max_jobs_per_batch),
            max_source_bytes_per_batch: self
                .max_source_bytes_per_batch
                .max(1)
                .min(record_caps.max_source_bytes_per_batch),
            max_source_files_per_batch: self
                .max_source_files_per_batch
                .max(1)
                .min(record_caps.max_source_files_per_batch),
        }
    }
}

pub fn link_batch_input_limit(limits: SourcePackJobBatchLimits) -> usize {
    limits
        .normalized()
        .max_jobs_per_batch
        .min(SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE)
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJobBatch {
    pub batch_index: usize,
    pub wave_index: usize,
    pub job_indices: Vec<usize>,
    pub source_bytes: usize,
    pub source_file_count: usize,
    #[serde(default)]
    pub source_lines: usize,
    #[serde(default)]
    pub oversized: bool,
}

impl SourcePackJobBatch {
    pub fn job_count(&self) -> usize {
        self.job_indices.len()
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJobBatchSchedule {
    pub batches: Vec<SourcePackJobBatch>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SourcePackJobBatchSummary {
    pub batch_count: usize,
    pub oversized_batch_count: usize,
    pub max_batch_job_count: usize,
    pub max_batch_source_bytes: usize,
    pub max_batch_source_files: usize,
}

impl SourcePackJobBatchSummary {
    pub fn batch_count(&self) -> usize {
        self.batch_count
    }

    pub fn max_batch_job_count(&self) -> usize {
        self.max_batch_job_count
    }

    pub fn max_batch_source_bytes(&self) -> usize {
        self.max_batch_source_bytes
    }

    pub fn max_batch_source_files(&self) -> usize {
        self.max_batch_source_files
    }

    pub(super) fn record(&mut self, batch: &SourcePackJobBatch) {
        self.batch_count = self.batch_count.saturating_add(1);
        if batch.oversized {
            self.oversized_batch_count = self.oversized_batch_count.saturating_add(1);
        }
        self.max_batch_job_count = self.max_batch_job_count.max(batch.job_count());
        self.max_batch_source_bytes = self.max_batch_source_bytes.max(batch.source_bytes);
        self.max_batch_source_files = self.max_batch_source_files.max(batch.source_file_count);
    }
}

impl SourcePackJobBatchSchedule {
    pub fn batch_count(&self) -> usize {
        self.batches.len()
    }

    pub fn oversized_batch_count(&self) -> usize {
        self.batches.iter().filter(|batch| batch.oversized).count()
    }

    pub fn max_batch_job_count(&self) -> usize {
        self.batches
            .iter()
            .map(SourcePackJobBatch::job_count)
            .max()
            .unwrap_or(0)
    }

    pub fn max_batch_source_bytes(&self) -> usize {
        self.batches
            .iter()
            .map(|batch| batch.source_bytes)
            .max()
            .unwrap_or(0)
    }

    pub fn max_batch_source_files(&self) -> usize {
        self.batches
            .iter()
            .map(|batch| batch.source_file_count)
            .max()
            .unwrap_or(0)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJobIndexRange {
    pub first_job_index: usize,
    pub job_count: usize,
}

impl SourcePackJobIndexRange {
    pub fn end_job_index(&self) -> Option<usize> {
        self.first_job_index.checked_add(self.job_count)
    }

    pub fn is_empty(&self) -> bool {
        self.job_count == 0
    }

    pub fn contains(&self, job_index: usize) -> bool {
        self.end_job_index()
            .is_some_and(|end| self.first_job_index <= job_index && job_index < end)
    }

    pub fn iter(&self) -> Option<Range<usize>> {
        self.end_job_index().map(|end| self.first_job_index..end)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackArtifactIndexRange {
    pub first_artifact_index: usize,
    pub artifact_count: usize,
}

impl SourcePackArtifactIndexRange {
    pub fn end_artifact_index(&self) -> Option<usize> {
        self.first_artifact_index.checked_add(self.artifact_count)
    }

    pub fn is_empty(&self) -> bool {
        self.artifact_count == 0
    }

    pub fn contains(&self, artifact_index: usize) -> bool {
        self.end_artifact_index()
            .is_some_and(|end| self.first_artifact_index <= artifact_index && artifact_index < end)
    }

    pub fn iter(&self) -> Option<Range<usize>> {
        self.end_artifact_index()
            .map(|end| self.first_artifact_index..end)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJobBatchDependencyRange {
    pub first_batch_index: usize,
    pub batch_count: usize,
}

impl SourcePackJobBatchDependencyRange {
    pub fn end_batch_index(&self) -> Option<usize> {
        self.first_batch_index.checked_add(self.batch_count)
    }

    pub fn is_empty(&self) -> bool {
        self.batch_count == 0
    }

    pub fn contains(&self, batch_index: usize) -> bool {
        self.end_batch_index()
            .is_some_and(|end| self.first_batch_index <= batch_index && batch_index < end)
    }

    pub fn iter(&self) -> Option<Range<usize>> {
        self.end_batch_index()
            .map(|end| self.first_batch_index..end)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJobBatchDependency {
    pub batch_index: usize,
    #[serde(default)]
    pub dependency_batch_count: usize,
    #[serde(default)]
    pub dependency_page_count: usize,
    #[serde(default)]
    pub dependency_range_count: usize,
    #[serde(default)]
    pub dependency_range_page_count: usize,
    #[serde(default)]
    pub dependency_range_batch_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub dependency_batch_indices: Vec<usize>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub dependency_batch_ranges: Vec<SourcePackJobBatchDependencyRange>,
}

impl SourcePackJobBatchDependency {
    pub fn explicit_dependency_count(&self) -> usize {
        self.dependency_batch_count
            .max(self.dependency_batch_indices.len())
    }

    pub fn range_dependency_count(&self) -> usize {
        self.dependency_range_batch_count.max(
            self.dependency_batch_ranges
                .iter()
                .fold(0usize, |count, range| {
                    count.saturating_add(range.batch_count)
                }),
        )
    }

    pub fn dependency_count(&self) -> usize {
        self.explicit_dependency_count()
            .saturating_add(self.range_dependency_count())
    }

    pub fn has_dependencies(&self) -> bool {
        self.explicit_dependency_count() != 0 || self.range_dependency_count() != 0
    }

    pub fn dependencies_completed(&self, completed_batch_indices: &BTreeSet<usize>) -> bool {
        if self.dependency_batch_indices.len() != self.explicit_dependency_count() {
            return false;
        }
        if self.dependency_batch_ranges.is_empty() && self.dependency_range_count != 0 {
            return false;
        }
        self.dependency_batch_indices
            .iter()
            .all(|dependency_batch_index| completed_batch_indices.contains(dependency_batch_index))
            && self.dependency_batch_ranges.iter().all(|range| {
                range.iter().is_some_and(|mut indices| {
                    indices.all(|dependency_batch_index| {
                        completed_batch_indices.contains(&dependency_batch_index)
                    })
                })
            })
    }

    pub fn dependencies_completed_by_ranges(
        &self,
        completed_batch_ranges: &[SourcePackJobBatchDependencyRange],
    ) -> bool {
        if self.dependency_batch_indices.len() != self.explicit_dependency_count() {
            return false;
        }
        if self.dependency_batch_ranges.is_empty() && self.dependency_range_count != 0 {
            return false;
        }
        self.dependency_batch_indices.iter().all(|&batch_index| {
            job_batch_index_covered_by_ranges(batch_index, completed_batch_ranges)
        }) && self
            .dependency_batch_ranges
            .iter()
            .all(|range| job_batch_range_covered_by_ranges(range, completed_batch_ranges))
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJobBatchDependencyPlan {
    pub batches: Vec<SourcePackJobBatchDependency>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SourcePackJobBatchDependencySummary {
    pub batch_count: usize,
    pub dependency_edge_count: usize,
    pub max_dependency_count: usize,
    pub initial_ready_batch_count: usize,
}

impl SourcePackJobBatchDependencySummary {
    pub fn batch_count(&self) -> usize {
        self.batch_count
    }

    pub fn dependency_edge_count(&self) -> usize {
        self.dependency_edge_count
    }

    pub fn max_dependency_count(&self) -> usize {
        self.max_dependency_count
    }

    pub fn initial_ready_batch_count(&self) -> usize {
        self.initial_ready_batch_count
    }

    pub(super) fn record_dependency_count(&mut self, dependency_count: usize) {
        self.batch_count = self.batch_count.saturating_add(1);
        self.dependency_edge_count = self.dependency_edge_count.saturating_add(dependency_count);
        self.max_dependency_count = self.max_dependency_count.max(dependency_count);
        if dependency_count == 0 {
            self.initial_ready_batch_count = self.initial_ready_batch_count.saturating_add(1);
        }
    }
}

impl SourcePackJobBatchDependencyPlan {
    pub fn batch_count(&self) -> usize {
        self.batches.len()
    }

    pub fn dependency_edge_count(&self) -> usize {
        self.batches.iter().fold(0usize, |count, batch| {
            count.saturating_add(batch.dependency_count())
        })
    }

    pub fn max_dependency_count(&self) -> usize {
        self.batches
            .iter()
            .map(SourcePackJobBatchDependency::dependency_count)
            .max()
            .unwrap_or(0)
    }

    pub fn ready_batch_count(&self, completed_batch_indices: &[usize]) -> usize {
        let completed = completed_batch_indices
            .iter()
            .copied()
            .collect::<BTreeSet<_>>();
        self.batches
            .iter()
            .filter(|batch| {
                !completed.contains(&batch.batch_index) && batch.dependencies_completed(&completed)
            })
            .count()
    }

    pub fn ready_batch_count_with_completed_ranges(
        &self,
        completed_batch_ranges: &[SourcePackJobBatchDependencyRange],
    ) -> usize {
        self.batches
            .iter()
            .filter(|batch| {
                !job_batch_index_covered_by_ranges(batch.batch_index, completed_batch_ranges)
                    && batch.dependencies_completed_by_ranges(completed_batch_ranges)
            })
            .count()
    }

    pub fn ready_batch_indices_limited(
        &self,
        completed_batch_indices: &[usize],
        max_batches: Option<usize>,
    ) -> Vec<usize> {
        if max_batches == Some(0) {
            return Vec::new();
        }
        let completed = completed_batch_indices
            .iter()
            .copied()
            .collect::<BTreeSet<_>>();
        let mut ready_batch_indices = Vec::new();
        for batch in &self.batches {
            if completed.contains(&batch.batch_index) || !batch.dependencies_completed(&completed) {
                continue;
            }
            ready_batch_indices.push(batch.batch_index);
            if max_batches.is_some_and(|max_batches| ready_batch_indices.len() >= max_batches) {
                break;
            }
        }
        ready_batch_indices
    }

    pub fn ready_batch_indices_limited_with_completed_ranges(
        &self,
        completed_batch_ranges: &[SourcePackJobBatchDependencyRange],
        max_batches: Option<usize>,
    ) -> Vec<usize> {
        if max_batches == Some(0) {
            return Vec::new();
        }
        let mut ready_batch_indices = Vec::new();
        for batch in &self.batches {
            if job_batch_index_covered_by_ranges(batch.batch_index, completed_batch_ranges)
                || !batch.dependencies_completed_by_ranges(completed_batch_ranges)
            {
                continue;
            }
            ready_batch_indices.push(batch.batch_index);
            if max_batches.is_some_and(|max_batches| ready_batch_indices.len() >= max_batches) {
                break;
            }
        }
        ready_batch_indices
    }

    pub fn dependency_batch_indices(&self, batch_index: usize) -> Option<&[usize]> {
        self.batches
            .iter()
            .find(|batch| batch.batch_index == batch_index)
            .map(|batch| batch.dependency_batch_indices.as_slice())
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJobWaveSchedule {
    pub waves: Vec<SourcePackJobWave>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SourcePackJobWaveSummary {
    pub wave_count: usize,
    pub max_wave_job_count: usize,
    pub max_wave_source_bytes: usize,
    pub max_wave_source_files: usize,
}

impl SourcePackJobWaveSummary {
    pub fn wave_count(&self) -> usize {
        self.wave_count
    }

    pub fn max_wave_job_count(&self) -> usize {
        self.max_wave_job_count
    }

    pub fn max_wave_source_bytes(&self) -> usize {
        self.max_wave_source_bytes
    }

    pub fn max_wave_source_files(&self) -> usize {
        self.max_wave_source_files
    }

    pub(super) fn record_wave(
        &mut self,
        job_count: usize,
        source_bytes: usize,
        source_file_count: usize,
    ) {
        self.wave_count = self.wave_count.saturating_add(1);
        self.max_wave_job_count = self.max_wave_job_count.max(job_count);
        self.max_wave_source_bytes = self.max_wave_source_bytes.max(source_bytes);
        self.max_wave_source_files = self.max_wave_source_files.max(source_file_count);
    }
}

impl SourcePackJobWaveSchedule {
    pub fn wave_count(&self) -> usize {
        self.waves.len()
    }

    pub fn max_wave_job_count(&self) -> usize {
        self.waves
            .iter()
            .map(SourcePackJobWave::job_count)
            .max()
            .unwrap_or(0)
    }

    pub fn max_wave_source_bytes(&self) -> usize {
        self.waves
            .iter()
            .map(|wave| wave.source_bytes)
            .max()
            .unwrap_or(0)
    }

    pub fn max_wave_source_files(&self) -> usize {
        self.waves
            .iter()
            .map(|wave| wave.source_file_count)
            .max()
            .unwrap_or(0)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackScheduleError {
    pub unscheduled_job_indices: Vec<usize>,
}

#[derive(Clone, Debug, Default)]
pub(super) struct SourcePackJobBatchBuilder {
    wave_index: usize,
    job_indices: Vec<usize>,
    source_bytes: usize,
    source_file_count: usize,
    source_lines: usize,
}

impl SourcePackJobBatchBuilder {
    pub(super) fn new(wave_index: usize) -> Self {
        Self {
            wave_index,
            ..Self::default()
        }
    }

    fn is_empty(&self) -> bool {
        self.job_indices.is_empty()
    }

    pub(super) fn should_flush_before(
        &self,
        job: &SourcePackJob,
        limits: SourcePackJobBatchLimits,
    ) -> bool {
        !self.is_empty()
            && (self.job_indices.len() >= limits.max_jobs_per_batch
                || self.source_bytes.saturating_add(job.source_bytes)
                    > limits.max_source_bytes_per_batch
                || self.source_file_count.saturating_add(job.source_file_count)
                    > limits.max_source_files_per_batch)
    }

    pub(super) fn push(&mut self, job: &SourcePackJob) {
        self.job_indices.push(job.job_index);
        self.source_bytes = self.source_bytes.saturating_add(job.source_bytes);
        self.source_file_count = self.source_file_count.saturating_add(job.source_file_count);
        self.source_lines = self.source_lines.saturating_add(job.source_lines);
    }

    pub(super) fn take_batch(
        &mut self,
        batch_index: usize,
        limits: SourcePackJobBatchLimits,
    ) -> Option<SourcePackJobBatch> {
        if self.is_empty() {
            return None;
        }
        let limits = limits.normalized();
        let oversized = self.job_indices.len() > limits.max_jobs_per_batch
            || self.source_bytes > limits.max_source_bytes_per_batch
            || self.source_file_count > limits.max_source_files_per_batch;
        let batch = SourcePackJobBatch {
            batch_index,
            wave_index: self.wave_index,
            job_indices: std::mem::take(&mut self.job_indices),
            source_bytes: self.source_bytes,
            source_file_count: self.source_file_count,
            source_lines: self.source_lines,
            oversized,
        };
        self.source_bytes = 0;
        self.source_file_count = 0;
        self.source_lines = 0;
        Some(batch)
    }
}

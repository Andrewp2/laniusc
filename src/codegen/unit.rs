//! Bounded codegen-unit planning.
//!
//! A source pack can be arbitrarily large only if later compiler stages can
//! operate on bounded jobs. This module keeps that policy independent from the
//! current GPU backend implementation: it groups contiguous source files into
//! natural library/file-bounded units, never splits a file, and marks files that
//! exceed the unit budget so callers can route them to a separate large-file
//! strategy.

use std::{
    collections::{BTreeMap, BTreeSet},
    ops::Range,
};

use serde::{Deserialize, Serialize};

pub const DEFAULT_CODEGEN_UNIT_MAX_SOURCE_BYTES: usize = 512 * 1024;
pub const DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES: usize = 64;
pub const SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE: usize = 64;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CodegenUnitLimits {
    pub max_source_bytes: usize,
    pub max_source_files: usize,
}

impl Default for CodegenUnitLimits {
    fn default() -> Self {
        Self {
            max_source_bytes: DEFAULT_CODEGEN_UNIT_MAX_SOURCE_BYTES,
            max_source_files: DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES,
        }
    }
}

impl CodegenUnitLimits {
    pub fn normalized(self) -> Self {
        Self {
            max_source_bytes: self.max_source_bytes.max(1),
            max_source_files: self.max_source_files.max(1),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SourceFileUnitInput {
    pub library_id: u32,
    pub source_index: usize,
    pub byte_len: usize,
    pub line_count: usize,
}

impl SourceFileUnitInput {
    pub fn from_source(library_id: u32, source_index: usize, source: &str) -> Self {
        Self {
            library_id,
            source_index,
            byte_len: source.len(),
            line_count: source.lines().count(),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct FrontendUnit {
    pub unit_index: usize,
    pub library_id: u32,
    pub first_source_index: usize,
    pub source_file_count: usize,
    pub source_bytes: usize,
    pub source_lines: usize,
    pub oversized_source_file: bool,
}

impl FrontendUnit {
    pub fn source_range(&self) -> Range<usize> {
        self.first_source_index..self.first_source_index + self.source_file_count
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CodegenUnit {
    pub unit_index: usize,
    pub library_id: u32,
    pub first_source_index: usize,
    pub source_file_count: usize,
    pub source_bytes: usize,
    pub source_lines: usize,
    pub oversized_source_file: bool,
}

impl CodegenUnit {
    pub fn source_range(&self) -> Range<usize> {
        self.first_source_index..self.first_source_index + self.source_file_count
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LibraryUnit {
    pub library_index: usize,
    pub library_id: u32,
    pub first_source_index: usize,
    pub source_file_count: usize,
    pub source_bytes: usize,
    pub source_lines: usize,
}

impl LibraryUnit {
    pub fn source_range(&self) -> Range<usize> {
        self.first_source_index..self.first_source_index + self.source_file_count
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct LibraryUnitPlan {
    pub libraries: Vec<LibraryUnit>,
}

impl LibraryUnitPlan {
    pub fn from_source_pack<S: AsRef<str>>(sources: &[S]) -> Self {
        let mut libraries = Vec::new();
        Self::try_for_each_from_files(
            sources.iter().enumerate().map(|(source_index, source)| {
                SourceFileUnitInput::from_source(0, source_index, source.as_ref())
            }),
            |library| {
                libraries.push(library);
                Ok::<(), ()>(())
            },
        )
        .unwrap_or_else(|()| unreachable!("infallible library-unit collection failed"));
        Self { libraries }
    }

    pub fn from_source_pack_with_libraries<S, L>(sources: &[S], library_ids: &[L]) -> Self
    where
        S: AsRef<str>,
        L: Copy + Into<u32>,
    {
        assert_eq!(
            sources.len(),
            library_ids.len(),
            "source and library slices must have the same length"
        );
        let mut libraries = Vec::new();
        Self::try_for_each_from_files(
            sources
                .iter()
                .zip(library_ids.iter().copied())
                .enumerate()
                .map(|(source_index, (source, library_id))| {
                    SourceFileUnitInput::from_source(
                        library_id.into(),
                        source_index,
                        source.as_ref(),
                    )
                }),
            |library| {
                libraries.push(library);
                Ok::<(), ()>(())
            },
        )
        .unwrap_or_else(|()| unreachable!("infallible library-unit collection failed"));
        Self { libraries }
    }

    pub fn from_files(files: &[SourceFileUnitInput]) -> Self {
        let mut libraries = Vec::new();
        Self::try_for_each_from_files(files.iter().copied(), |library| {
            libraries.push(library);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible library-unit collection failed"));
        Self { libraries }
    }

    pub fn try_for_each_from_files<I, F, E>(files: I, visit: F) -> Result<usize, E>
    where
        I: IntoIterator<Item = SourceFileUnitInput>,
        F: FnMut(LibraryUnit) -> Result<(), E>,
    {
        Self::try_for_each_from_fallible_files(files.into_iter().map(Ok), visit)
    }

    pub fn try_for_each_from_fallible_files<I, F, E>(files: I, mut visit: F) -> Result<usize, E>
    where
        I: IntoIterator<Item = Result<SourceFileUnitInput, E>>,
        F: FnMut(LibraryUnit) -> Result<(), E>,
    {
        let mut current = LibraryBuilder::default();
        let mut library_count = 0usize;

        for file in files {
            let file = file?;
            if current.should_flush_before(file) {
                if let Some(library) = current.take(library_count) {
                    library_count += 1;
                    visit(library)?;
                }
            }
            current.push(file);
        }

        if let Some(library) = current.take(library_count) {
            library_count += 1;
            visit(library)?;
        }
        Ok(library_count)
    }

    pub fn library_count(&self) -> usize {
        self.libraries.len()
    }

    pub fn max_library_source_bytes(&self) -> usize {
        self.libraries
            .iter()
            .map(|library| library.source_bytes)
            .max()
            .unwrap_or(0)
    }

    pub fn max_library_source_files(&self) -> usize {
        self.libraries
            .iter()
            .map(|library| library.source_file_count)
            .max()
            .unwrap_or(0)
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct FrontendUnitPlan {
    pub units: Vec<FrontendUnit>,
}

impl FrontendUnitPlan {
    pub fn from_source_pack<S: AsRef<str>>(sources: &[S], limits: CodegenUnitLimits) -> Self {
        let mut units = Vec::new();
        Self::try_for_each_from_files(
            sources.iter().enumerate().map(|(source_index, source)| {
                SourceFileUnitInput::from_source(0, source_index, source.as_ref())
            }),
            limits,
            |unit| {
                units.push(unit);
                Ok::<(), ()>(())
            },
        )
        .unwrap_or_else(|()| unreachable!("infallible frontend-unit collection failed"));
        Self { units }
    }

    pub fn from_source_pack_with_libraries<S, L>(
        sources: &[S],
        library_ids: &[L],
        limits: CodegenUnitLimits,
    ) -> Self
    where
        S: AsRef<str>,
        L: Copy + Into<u32>,
    {
        assert_eq!(
            sources.len(),
            library_ids.len(),
            "source and library slices must have the same length"
        );
        let mut units = Vec::new();
        Self::try_for_each_from_files(
            sources
                .iter()
                .zip(library_ids.iter().copied())
                .enumerate()
                .map(|(source_index, (source, library_id))| {
                    SourceFileUnitInput::from_source(
                        library_id.into(),
                        source_index,
                        source.as_ref(),
                    )
                }),
            limits,
            |unit| {
                units.push(unit);
                Ok::<(), ()>(())
            },
        )
        .unwrap_or_else(|()| unreachable!("infallible frontend-unit collection failed"));
        Self { units }
    }

    pub fn from_files(files: &[SourceFileUnitInput], limits: CodegenUnitLimits) -> Self {
        let mut units = Vec::new();
        Self::try_for_each_from_files(files.iter().copied(), limits, |unit| {
            units.push(unit);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible frontend-unit collection failed"));
        Self { units }
    }

    pub fn try_for_each_from_files<I, F, E>(
        files: I,
        limits: CodegenUnitLimits,
        visit: F,
    ) -> Result<usize, E>
    where
        I: IntoIterator<Item = SourceFileUnitInput>,
        F: FnMut(FrontendUnit) -> Result<(), E>,
    {
        Self::try_for_each_from_fallible_files(files.into_iter().map(Ok), limits, visit)
    }

    pub fn try_for_each_from_fallible_files<I, F, E>(
        files: I,
        limits: CodegenUnitLimits,
        mut visit: F,
    ) -> Result<usize, E>
    where
        I: IntoIterator<Item = Result<SourceFileUnitInput, E>>,
        F: FnMut(FrontendUnit) -> Result<(), E>,
    {
        let limits = limits.normalized();
        let mut current = UnitBuilder::default();
        let mut unit_count = 0usize;

        for file in files {
            let file = file?;
            let oversized = file.byte_len > limits.max_source_bytes;
            if oversized {
                if let Some(unit) = current.take_frontend(unit_count, false) {
                    unit_count += 1;
                    visit(unit)?;
                }
                visit(FrontendUnit {
                    unit_index: unit_count,
                    library_id: file.library_id,
                    first_source_index: file.source_index,
                    source_file_count: 1,
                    source_bytes: file.byte_len,
                    source_lines: file.line_count,
                    oversized_source_file: true,
                })?;
                unit_count += 1;
                continue;
            }

            if current.should_flush_before(file, limits) {
                if let Some(unit) = current.take_frontend(unit_count, false) {
                    unit_count += 1;
                    visit(unit)?;
                }
            }
            current.push(file);
        }

        if let Some(unit) = current.take_frontend(unit_count, false) {
            unit_count += 1;
            visit(unit)?;
        }
        Ok(unit_count)
    }

    pub fn unit_count(&self) -> usize {
        self.units.len()
    }

    pub fn oversized_unit_count(&self) -> usize {
        self.units
            .iter()
            .filter(|unit| unit.oversized_source_file)
            .count()
    }

    pub fn max_unit_source_bytes(&self) -> usize {
        self.units
            .iter()
            .map(|unit| unit.source_bytes)
            .max()
            .unwrap_or(0)
    }

    pub fn max_unit_source_files(&self) -> usize {
        self.units
            .iter()
            .map(|unit| unit.source_file_count)
            .max()
            .unwrap_or(0)
    }
}

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

pub fn source_pack_link_batch_input_limit(limits: SourcePackJobBatchLimits) -> usize {
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

    fn record(&mut self, batch: &SourcePackJobBatch) {
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
            source_pack_job_batch_index_covered_by_ranges(batch_index, completed_batch_ranges)
        }) && self.dependency_batch_ranges.iter().all(|range| {
            source_pack_job_batch_range_covered_by_ranges(range, completed_batch_ranges)
        })
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

    fn record_dependency_count(&mut self, dependency_count: usize) {
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
                !source_pack_job_batch_index_covered_by_ranges(
                    batch.batch_index,
                    completed_batch_ranges,
                ) && batch.dependencies_completed_by_ranges(completed_batch_ranges)
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
            if source_pack_job_batch_index_covered_by_ranges(
                batch.batch_index,
                completed_batch_ranges,
            ) || !batch.dependencies_completed_by_ranges(completed_batch_ranges)
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

    fn record_wave(&mut self, job_count: usize, source_bytes: usize, source_file_count: usize) {
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
struct SourcePackJobBatchBuilder {
    wave_index: usize,
    job_indices: Vec<usize>,
    source_bytes: usize,
    source_file_count: usize,
    source_lines: usize,
}

impl SourcePackJobBatchBuilder {
    fn new(wave_index: usize) -> Self {
        Self {
            wave_index,
            ..Self::default()
        }
    }

    fn is_empty(&self) -> bool {
        self.job_indices.is_empty()
    }

    fn should_flush_before(&self, job: &SourcePackJob, limits: SourcePackJobBatchLimits) -> bool {
        !self.is_empty()
            && (self.job_indices.len() >= limits.max_jobs_per_batch
                || self.source_bytes.saturating_add(job.source_bytes)
                    > limits.max_source_bytes_per_batch
                || self.source_file_count.saturating_add(job.source_file_count)
                    > limits.max_source_files_per_batch)
    }

    fn push(&mut self, job: &SourcePackJob) {
        self.job_indices.push(job.job_index);
        self.source_bytes = self.source_bytes.saturating_add(job.source_bytes);
        self.source_file_count = self.source_file_count.saturating_add(job.source_file_count);
        self.source_lines = self.source_lines.saturating_add(job.source_lines);
    }

    fn take_batch(
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

impl SourcePackJobSchedule {
    pub fn dependency_job_ranges(&self, job_index: usize) -> &[SourcePackJobIndexRange] {
        self.dependency_job_ranges_by_job_index
            .get(job_index)
            .map(Vec::as_slice)
            .unwrap_or(&[])
    }

    pub fn dependency_job_ranges_for_job(&self, job: &SourcePackJob) -> &[SourcePackJobIndexRange] {
        self.dependency_job_ranges(job.job_index)
    }

    pub fn frontend_job_count(&self) -> usize {
        self.jobs
            .iter()
            .filter(|job| job.phase == SourcePackJobPhase::LibraryFrontend)
            .count()
    }

    pub fn codegen_job_count(&self) -> usize {
        self.jobs
            .iter()
            .filter(|job| job.phase == SourcePackJobPhase::Codegen)
            .count()
    }

    pub fn link_job_count(&self) -> usize {
        self.jobs
            .iter()
            .filter(|job| job.phase == SourcePackJobPhase::Link)
            .count()
    }

    pub fn max_job_source_bytes(&self) -> usize {
        self.jobs
            .iter()
            .map(|job| job.source_bytes)
            .max()
            .unwrap_or(0)
    }

    pub fn max_job_source_files(&self) -> usize {
        self.jobs
            .iter()
            .map(|job| job.source_file_count)
            .max()
            .unwrap_or(0)
    }

    pub fn dependency_edge_count(&self) -> usize {
        self.jobs
            .iter()
            .map(|job| self.effective_dependency_count(job))
            .sum()
    }

    pub fn max_job_dependency_count(&self) -> usize {
        self.jobs
            .iter()
            .map(|job| self.effective_dependency_count(job))
            .max()
            .unwrap_or(0)
    }

    fn effective_dependency_count(&self, job: &SourcePackJob) -> usize {
        let ranged_dependency_count =
            source_pack_job_index_range_dependency_count(self.dependency_job_ranges_for_job(job));
        if job.phase == SourcePackJobPhase::Link
            && job.dependency_job_indices.is_empty()
            && ranged_dependency_count == 0
        {
            self.codegen_job_count()
        } else {
            job.dependency_job_indices
                .len()
                .saturating_add(ranged_dependency_count)
        }
    }

    pub fn try_execution_waves(
        &self,
    ) -> Result<SourcePackJobWaveSchedule, SourcePackScheduleError> {
        let mut waves = Vec::new();
        self.try_for_each_execution_wave(
            |err| err,
            |wave| {
                waves.push(wave);
                Ok(())
            },
        )?;
        Ok(SourcePackJobWaveSchedule { waves })
    }

    pub fn try_execution_wave_summary(
        &self,
    ) -> Result<SourcePackJobWaveSummary, SourcePackScheduleError> {
        let mut summary = SourcePackJobWaveSummary::default();
        self.try_for_each_execution_wave_positions(
            |err| err,
            |_, ready_positions, source_bytes, source_file_count, _| {
                summary.record_wave(ready_positions.len(), source_bytes, source_file_count);
                Ok::<(), SourcePackScheduleError>(())
            },
        )?;
        Ok(summary)
    }

    pub fn try_for_each_execution_wave<F, E, M>(
        &self,
        map_schedule_error: M,
        mut visit: F,
    ) -> Result<usize, E>
    where
        F: FnMut(SourcePackJobWave) -> Result<(), E>,
        M: Fn(SourcePackScheduleError) -> E + Copy,
    {
        self.try_for_each_execution_wave_positions(
            map_schedule_error,
            |wave_index, ready_positions, source_bytes, source_file_count, source_lines| {
                let job_indices = ready_positions
                    .iter()
                    .map(|&position| self.jobs[position].job_index)
                    .collect::<Vec<_>>();
                visit(SourcePackJobWave {
                    wave_index,
                    job_indices,
                    source_bytes,
                    source_file_count,
                    source_lines,
                })
            },
        )
    }

    fn try_for_each_execution_wave_positions<F, E, M>(
        &self,
        map_schedule_error: M,
        mut visit: F,
    ) -> Result<usize, E>
    where
        F: FnMut(usize, &[usize], usize, usize, usize) -> Result<(), E>,
        M: Fn(SourcePackScheduleError) -> E + Copy,
    {
        let max_job_index = self.jobs.iter().map(|job| job.job_index).max().unwrap_or(0);
        let mut job_position_by_index = vec![None; max_job_index.saturating_add(1)];
        for (position, job) in self.jobs.iter().enumerate() {
            if let Some(slot) = job_position_by_index.get_mut(job.job_index) {
                *slot = Some(position);
            }
        }

        let codegen_job_count = self.codegen_job_count();
        let mut emitted_by_position = vec![false; self.jobs.len()];
        let mut completed_job_ranges = Vec::new();
        let mut emitted_codegen_count = 0usize;
        let mut ready_positions = self
            .jobs
            .iter()
            .enumerate()
            .filter_map(|(position, job)| {
                source_pack_job_ready_from_completed_ranges(
                    job,
                    self.dependency_job_ranges_for_job(job),
                    &job_position_by_index,
                    &emitted_by_position,
                    &completed_job_ranges,
                    emitted_codegen_count,
                    codegen_job_count,
                )
                .then_some(position)
            })
            .collect::<Vec<_>>();
        let mut emitted_count = 0usize;
        let mut wave_count = 0usize;

        while !ready_positions.is_empty() {
            ready_positions.sort_unstable();
            let mut source_bytes = 0usize;
            let mut source_file_count = 0usize;
            let mut source_lines = 0usize;

            for &position in &ready_positions {
                let job = &self.jobs[position];
                source_bytes = source_bytes.saturating_add(job.source_bytes);
                source_file_count = source_file_count.saturating_add(job.source_file_count);
                source_lines = source_lines.saturating_add(job.source_lines);
            }
            visit(
                wave_count,
                &ready_positions,
                source_bytes,
                source_file_count,
                source_lines,
            )?;
            wave_count += 1;

            let mut next_ready_positions = BTreeSet::new();
            for &position in &ready_positions {
                emitted_by_position[position] = true;
                emitted_count += 1;
                let job_index = self.jobs[position].job_index;
                source_pack_push_completed_job_index_as_range(&mut completed_job_ranges, job_index);
                if self.jobs[position].phase == SourcePackJobPhase::Codegen {
                    emitted_codegen_count = emitted_codegen_count.saturating_add(1);
                }
            }
            for (position, job) in self.jobs.iter().enumerate() {
                if emitted_by_position[position] {
                    continue;
                }
                if source_pack_job_ready_from_completed_ranges(
                    job,
                    self.dependency_job_ranges_for_job(job),
                    &job_position_by_index,
                    &emitted_by_position,
                    &completed_job_ranges,
                    emitted_codegen_count,
                    codegen_job_count,
                ) {
                    next_ready_positions.insert(position);
                }
            }
            ready_positions = next_ready_positions.into_iter().collect();
        }

        if emitted_count != self.jobs.len() {
            let unscheduled_job_indices = self
                .jobs
                .iter()
                .zip(emitted_by_position.iter().copied())
                .filter_map(|(job, emitted)| (!emitted).then_some(job.job_index))
                .collect();
            return Err(map_schedule_error(SourcePackScheduleError {
                unscheduled_job_indices,
            }));
        }

        Ok(wave_count)
    }

    pub fn try_execution_batches(
        &self,
        limits: SourcePackJobBatchLimits,
    ) -> Result<SourcePackJobBatchSchedule, SourcePackScheduleError> {
        let mut batches = Vec::new();
        self.try_for_each_execution_batch(
            limits,
            |err| err,
            |batch| {
                batches.push(batch);
                Ok(())
            },
        )?;

        Ok(SourcePackJobBatchSchedule { batches })
    }

    pub fn try_execution_batch_summary(
        &self,
        limits: SourcePackJobBatchLimits,
    ) -> Result<SourcePackJobBatchSummary, SourcePackScheduleError> {
        let mut summary = SourcePackJobBatchSummary::default();
        self.try_for_each_execution_batch(
            limits,
            |err| err,
            |batch| {
                summary.record(&batch);
                Ok::<(), SourcePackScheduleError>(())
            },
        )?;
        Ok(summary)
    }

    pub fn try_for_each_execution_batch<F, E, M>(
        &self,
        limits: SourcePackJobBatchLimits,
        map_schedule_error: M,
        mut visit: F,
    ) -> Result<usize, E>
    where
        F: FnMut(SourcePackJobBatch) -> Result<(), E>,
        M: Fn(SourcePackScheduleError) -> E + Copy,
    {
        let limits = limits.normalized();
        let mut batch_count = 0usize;
        self.try_for_each_execution_wave_positions(
            map_schedule_error,
            |wave_index, ready_positions, _, _, _| {
                let mut batch = SourcePackJobBatchBuilder::new(wave_index);
                for &position in ready_positions {
                    let job = &self.jobs[position];
                    if batch.should_flush_before(job, limits) {
                        if let Some(batch) = batch.take_batch(batch_count, limits) {
                            visit(batch)?;
                            batch_count += 1;
                        }
                    }
                    batch.push(job);
                }
                if let Some(batch) = batch.take_batch(batch_count, limits) {
                    visit(batch)?;
                    batch_count += 1;
                }
                Ok(())
            },
        )?;

        Ok(batch_count)
    }

    pub fn try_batch_dependency_plan(
        &self,
        batches: &SourcePackJobBatchSchedule,
    ) -> Result<SourcePackJobBatchDependencyPlan, SourcePackScheduleError> {
        let mut batch_dependencies = Vec::new();
        self.try_for_each_batch_dependency(
            batches,
            |err| err,
            |dependency| {
                batch_dependencies.push(dependency);
                Ok(())
            },
        )?;

        Ok(SourcePackJobBatchDependencyPlan {
            batches: batch_dependencies,
        })
    }

    pub fn try_execution_batch_dependency_summary(
        &self,
        limits: SourcePackJobBatchLimits,
    ) -> Result<SourcePackJobBatchDependencySummary, SourcePackScheduleError> {
        let max_job_index = self.jobs.iter().map(|job| job.job_index).max().unwrap_or(0);
        let mut job_position_by_index = vec![None; max_job_index.saturating_add(1)];
        for (position, job) in self.jobs.iter().enumerate() {
            if let Some(slot) = job_position_by_index.get_mut(job.job_index) {
                *slot = Some(position);
            }
        }

        let mut batch_index_by_job_index = vec![None; max_job_index.saturating_add(1)];
        let mut codegen_batch_ranges = Vec::new();
        let mut summary = SourcePackJobBatchDependencySummary::default();
        self.try_for_each_execution_batch(
            limits,
            |err| err,
            |batch| {
                let mut contains_codegen_job = false;
                for &job_index in &batch.job_indices {
                    let Some(position) = job_position_by_index
                        .get(job_index)
                        .and_then(|position| *position)
                    else {
                        return Err(SourcePackScheduleError {
                            unscheduled_job_indices: vec![job_index],
                        });
                    };
                    let Some(slot) = batch_index_by_job_index.get_mut(job_index) else {
                        return Err(SourcePackScheduleError {
                            unscheduled_job_indices: vec![job_index],
                        });
                    };
                    *slot = Some(batch.batch_index);
                    contains_codegen_job |=
                        self.jobs[position].phase == SourcePackJobPhase::Codegen;
                }
                if contains_codegen_job {
                    source_pack_push_dependency_batch_indices_as_ranges(
                        &mut codegen_batch_ranges,
                        std::iter::once(batch.batch_index),
                    );
                }

                let mut dependency_batch_indices = BTreeSet::new();
                let mut dependency_batch_ranges = Vec::new();
                for &job_index in &batch.job_indices {
                    let Some(position) = job_position_by_index
                        .get(job_index)
                        .and_then(|position| *position)
                    else {
                        return Err(SourcePackScheduleError {
                            unscheduled_job_indices: vec![job_index],
                        });
                    };
                    for &dependency_job_index in &self.jobs[position].dependency_job_indices {
                        let Some(dependency_batch_index) = batch_index_by_job_index
                            .get(dependency_job_index)
                            .and_then(|batch_index| *batch_index)
                        else {
                            return Err(SourcePackScheduleError {
                                unscheduled_job_indices: vec![dependency_job_index],
                            });
                        };
                        if dependency_batch_index != batch.batch_index {
                            dependency_batch_indices.insert(dependency_batch_index);
                        }
                    }
                    for dependency_job_range in
                        self.dependency_job_ranges_for_job(&self.jobs[position])
                    {
                        source_pack_push_dependency_batch_range_for_job_range(
                            &mut dependency_batch_ranges,
                            &dependency_batch_indices,
                            &batch_index_by_job_index,
                            dependency_job_range,
                            batch.batch_index,
                        )?;
                    }
                    if self.jobs[position].phase == SourcePackJobPhase::Link
                        && self.jobs[position].dependency_job_indices.is_empty()
                        && self
                            .dependency_job_ranges_for_job(&self.jobs[position])
                            .is_empty()
                    {
                        source_pack_push_dependency_batch_ranges_excluding_batch(
                            &mut dependency_batch_ranges,
                            &codegen_batch_ranges,
                            batch.batch_index,
                        );
                    }
                }
                let dependency_count = dependency_batch_indices.len().saturating_add(
                    dependency_batch_ranges.iter().fold(0usize, |count, range| {
                        count.saturating_add(range.batch_count)
                    }),
                );
                summary.record_dependency_count(dependency_count);
                Ok(())
            },
        )?;
        Ok(summary)
    }

    pub fn try_for_each_batch_dependency<F, E, M>(
        &self,
        batches: &SourcePackJobBatchSchedule,
        map_schedule_error: M,
        mut visit: F,
    ) -> Result<usize, E>
    where
        F: FnMut(SourcePackJobBatchDependency) -> Result<(), E>,
        M: Fn(SourcePackScheduleError) -> E + Copy,
    {
        let max_job_index = self.jobs.iter().map(|job| job.job_index).max().unwrap_or(0);
        let mut job_position_by_index = vec![None; max_job_index.saturating_add(1)];
        for (position, job) in self.jobs.iter().enumerate() {
            if let Some(slot) = job_position_by_index.get_mut(job.job_index) {
                *slot = Some(position);
            }
        }

        let mut batch_index_by_job_index = vec![None; max_job_index.saturating_add(1)];
        let mut codegen_batch_ranges = Vec::new();
        for batch in &batches.batches {
            let mut contains_codegen_job = false;
            for &job_index in &batch.job_indices {
                let Some(position) = job_position_by_index
                    .get(job_index)
                    .and_then(|position| *position)
                else {
                    return Err(map_schedule_error(SourcePackScheduleError {
                        unscheduled_job_indices: vec![job_index],
                    }));
                };
                let Some(slot) = batch_index_by_job_index.get_mut(job_index) else {
                    return Err(map_schedule_error(SourcePackScheduleError {
                        unscheduled_job_indices: vec![job_index],
                    }));
                };
                *slot = Some(batch.batch_index);
                contains_codegen_job |= self.jobs[position].phase == SourcePackJobPhase::Codegen;
            }
            if contains_codegen_job {
                source_pack_push_dependency_batch_indices_as_ranges(
                    &mut codegen_batch_ranges,
                    std::iter::once(batch.batch_index),
                );
            }
        }

        let mut batch_dependency_count = 0usize;
        for batch in &batches.batches {
            let mut dependency_batch_indices = BTreeSet::new();
            let mut dependency_batch_ranges = Vec::new();
            for &job_index in &batch.job_indices {
                let Some(position) = job_position_by_index
                    .get(job_index)
                    .and_then(|position| *position)
                else {
                    return Err(map_schedule_error(SourcePackScheduleError {
                        unscheduled_job_indices: vec![job_index],
                    }));
                };
                for &dependency_job_index in &self.jobs[position].dependency_job_indices {
                    let Some(dependency_batch_index) = batch_index_by_job_index
                        .get(dependency_job_index)
                        .and_then(|batch_index| *batch_index)
                    else {
                        return Err(map_schedule_error(SourcePackScheduleError {
                            unscheduled_job_indices: vec![dependency_job_index],
                        }));
                    };
                    if dependency_batch_index != batch.batch_index {
                        dependency_batch_indices.insert(dependency_batch_index);
                    }
                }
                for dependency_job_range in self.dependency_job_ranges_for_job(&self.jobs[position])
                {
                    source_pack_push_dependency_batch_range_for_job_range(
                        &mut dependency_batch_ranges,
                        &dependency_batch_indices,
                        &batch_index_by_job_index,
                        dependency_job_range,
                        batch.batch_index,
                    )
                    .map_err(map_schedule_error)?;
                }
                if self.jobs[position].phase == SourcePackJobPhase::Link
                    && self.jobs[position].dependency_job_indices.is_empty()
                    && self
                        .dependency_job_ranges_for_job(&self.jobs[position])
                        .is_empty()
                {
                    source_pack_push_dependency_batch_ranges_excluding_batch(
                        &mut dependency_batch_ranges,
                        &codegen_batch_ranges,
                        batch.batch_index,
                    );
                }
            }
            let dependency_range_count = dependency_batch_ranges.len();
            let dependency_range_batch_count =
                dependency_batch_ranges.iter().fold(0usize, |count, range| {
                    count.saturating_add(range.batch_count)
                });
            visit(SourcePackJobBatchDependency {
                batch_index: batch.batch_index,
                dependency_batch_count: 0,
                dependency_page_count: 0,
                dependency_range_count,
                dependency_range_page_count: 0,
                dependency_range_batch_count,
                dependency_batch_indices: dependency_batch_indices.into_iter().collect(),
                dependency_batch_ranges,
            })?;
            batch_dependency_count += 1;
        }

        Ok(batch_dependency_count)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum SourcePackArtifactKind {
    LibraryInterface,
    CodegenObject,
    LinkedOutput,
}

impl SourcePackArtifactKind {
    pub fn key_segment(self) -> &'static str {
        match self {
            Self::LibraryInterface => "library-interface",
            Self::CodegenObject => "codegen-object",
            Self::LinkedOutput => "linked-output",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackArtifactPlan {
    pub artifact_index: usize,
    pub producing_job_index: usize,
    pub kind: SourcePackArtifactKind,
    pub library_id: u32,
    pub first_source_index: usize,
    pub source_file_count: usize,
    pub source_bytes: usize,
    pub source_lines: usize,
}

impl SourcePackArtifactPlan {
    pub fn source_range(&self) -> Range<usize> {
        self.first_source_index..self.first_source_index + self.source_file_count
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackArtifactManifestEntry {
    pub artifact_index: usize,
    pub key: String,
    pub producing_job_index: usize,
    pub kind: SourcePackArtifactKind,
    pub library_id: u32,
    pub first_source_index: usize,
    pub source_file_count: usize,
    pub source_bytes: usize,
    pub source_lines: usize,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackArtifactManifest {
    pub artifacts: Vec<SourcePackArtifactManifestEntry>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SourcePackArtifactManifestSummary {
    pub artifact_count: usize,
    pub max_key_len: usize,
}

impl SourcePackArtifactManifestSummary {
    pub fn artifact_count(&self) -> usize {
        self.artifact_count
    }

    pub fn max_key_len(&self) -> usize {
        self.max_key_len
    }
}

impl SourcePackArtifactManifest {
    pub fn artifact_count(&self) -> usize {
        self.artifacts.len()
    }

    pub fn max_key_len(&self) -> usize {
        self.artifacts
            .iter()
            .map(|artifact| artifact.key.len())
            .max()
            .unwrap_or(0)
    }

    pub fn get(&self, artifact_index: usize) -> Option<&SourcePackArtifactManifestEntry> {
        self.artifacts.get(artifact_index)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackLinkPlan {
    pub link_job_index: usize,
    pub input_interface_artifact_count: usize,
    pub input_interface_artifact_ranges: Vec<SourcePackArtifactIndexRange>,
    pub input_interface_artifact_indices: Vec<usize>,
    pub input_object_artifact_count: usize,
    pub input_object_artifact_ranges: Vec<SourcePackArtifactIndexRange>,
    pub input_object_artifact_indices: Vec<usize>,
    pub output_artifact_index: usize,
}

impl SourcePackLinkPlan {
    pub fn input_interface_artifact_count(&self) -> usize {
        source_pack_artifact_index_count(
            self.input_interface_artifact_count,
            &self.input_interface_artifact_indices,
            &self.input_interface_artifact_ranges,
        )
    }

    pub fn input_object_artifact_count(&self) -> usize {
        source_pack_artifact_index_count(
            self.input_object_artifact_count,
            &self.input_object_artifact_indices,
            &self.input_object_artifact_ranges,
        )
    }

    pub fn try_for_each_input_interface_artifact_index<F, E>(&self, visit: F) -> Result<usize, E>
    where
        F: FnMut(usize) -> Result<(), E>,
    {
        source_pack_try_for_each_artifact_index(
            &self.input_interface_artifact_indices,
            &self.input_interface_artifact_ranges,
            visit,
        )
    }

    pub fn try_for_each_input_object_artifact_index<F, E>(&self, visit: F) -> Result<usize, E>
    where
        F: FnMut(usize) -> Result<(), E>,
    {
        source_pack_try_for_each_artifact_index(
            &self.input_object_artifact_indices,
            &self.input_object_artifact_ranges,
            visit,
        )
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackArtifactUse {
    pub artifact_index: usize,
    pub producing_job_index: usize,
    pub consumer_job_indices: Vec<usize>,
    pub last_consumer_job_index: Option<usize>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackArtifactUsePlan {
    pub uses: Vec<SourcePackArtifactUse>,
}

impl SourcePackArtifactUsePlan {
    pub fn max_consumer_count(&self) -> usize {
        self.uses
            .iter()
            .map(|artifact| artifact.consumer_job_indices.len())
            .max()
            .unwrap_or(0)
    }

    pub fn artifacts_without_consumers(&self) -> usize {
        self.uses
            .iter()
            .filter(|artifact| artifact.consumer_job_indices.is_empty())
            .count()
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackArtifactLastUse {
    pub artifact_index: usize,
    pub producing_job_index: usize,
    pub last_consumer_job_index: Option<usize>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackArtifactLastUsePlan {
    pub artifacts: Vec<SourcePackArtifactLastUse>,
}

impl SourcePackArtifactLastUsePlan {
    pub fn artifacts_without_consumers(&self) -> usize {
        self.artifacts
            .iter()
            .filter(|artifact| artifact.last_consumer_job_index.is_none())
            .count()
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackArtifactLastUseIndex {
    pub last_consumer_job_indices: Vec<Option<usize>>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SourcePackArtifactLifetimeSummary {
    pub artifact_count: usize,
    pub artifacts_without_consumers: usize,
}

impl SourcePackArtifactLastUseIndex {
    pub fn artifacts_without_consumers(&self) -> usize {
        self.last_consumer_job_indices
            .iter()
            .filter(|last_consumer_job_index| last_consumer_job_index.is_none())
            .count()
    }
}

impl SourcePackArtifactLifetimeSummary {
    pub fn artifacts_without_consumers(&self) -> usize {
        self.artifacts_without_consumers
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJobArtifactIo {
    pub job_index: usize,
    pub phase: SourcePackJobPhase,
    #[serde(default)]
    pub input_interface_artifact_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub input_interface_artifact_ranges: Vec<SourcePackArtifactIndexRange>,
    pub input_interface_artifact_indices: Vec<usize>,
    #[serde(default)]
    pub input_object_artifact_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub input_object_artifact_ranges: Vec<SourcePackArtifactIndexRange>,
    pub input_object_artifact_indices: Vec<usize>,
    pub output_artifact_indices: Vec<usize>,
}

impl SourcePackJobArtifactIo {
    pub fn input_interface_artifact_count(&self) -> usize {
        source_pack_artifact_index_count(
            self.input_interface_artifact_count,
            &self.input_interface_artifact_indices,
            &self.input_interface_artifact_ranges,
        )
    }

    pub fn input_object_artifact_count(&self) -> usize {
        source_pack_artifact_index_count(
            self.input_object_artifact_count,
            &self.input_object_artifact_indices,
            &self.input_object_artifact_ranges,
        )
    }

    pub fn input_artifact_count(&self) -> usize {
        self.input_interface_artifact_count()
            .saturating_add(self.input_object_artifact_count())
    }

    pub fn output_artifact_count(&self) -> usize {
        self.output_artifact_indices.len()
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJobArtifactIoPlan {
    pub jobs: Vec<SourcePackJobArtifactIo>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SourcePackJobArtifactIoSummary {
    pub job_count: usize,
    pub max_input_interface_count: usize,
    pub max_input_object_count: usize,
    pub max_input_artifact_count: usize,
    pub max_output_artifact_count: usize,
}

impl SourcePackJobArtifactIoSummary {
    pub fn max_input_interface_count(&self) -> usize {
        self.max_input_interface_count
    }

    pub fn max_input_object_count(&self) -> usize {
        self.max_input_object_count
    }

    pub fn max_input_artifact_count(&self) -> usize {
        self.max_input_artifact_count
    }

    pub fn max_output_artifact_count(&self) -> usize {
        self.max_output_artifact_count
    }

    fn record(&mut self, job: &SourcePackJobArtifactIo) {
        self.job_count = self.job_count.saturating_add(1);
        self.max_input_interface_count = self
            .max_input_interface_count
            .max(job.input_interface_artifact_count());
        self.max_input_object_count = self
            .max_input_object_count
            .max(job.input_object_artifact_count());
        self.max_input_artifact_count = self
            .max_input_artifact_count
            .max(job.input_artifact_count());
        self.max_output_artifact_count = self
            .max_output_artifact_count
            .max(job.output_artifact_count());
    }
}

impl SourcePackJobArtifactIoPlan {
    pub fn max_input_interface_count(&self) -> usize {
        self.jobs
            .iter()
            .map(SourcePackJobArtifactIo::input_interface_artifact_count)
            .max()
            .unwrap_or(0)
    }

    pub fn max_input_object_count(&self) -> usize {
        self.jobs
            .iter()
            .map(SourcePackJobArtifactIo::input_object_artifact_count)
            .max()
            .unwrap_or(0)
    }

    pub fn max_input_artifact_count(&self) -> usize {
        self.jobs
            .iter()
            .map(SourcePackJobArtifactIo::input_artifact_count)
            .max()
            .unwrap_or(0)
    }

    pub fn max_output_artifact_count(&self) -> usize {
        self.jobs
            .iter()
            .map(SourcePackJobArtifactIo::output_artifact_count)
            .max()
            .unwrap_or(0)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackArtifactRef {
    pub artifact_index: usize,
    pub key: String,
    pub producing_job_index: usize,
    pub kind: SourcePackArtifactKind,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJobArtifactManifest {
    pub job_index: usize,
    pub phase: SourcePackJobPhase,
    #[serde(default)]
    pub input_interface_count: usize,
    #[serde(default)]
    pub input_interface_page_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub input_interface_ranges: Vec<SourcePackJobIndexRange>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub input_interface_artifact_ranges: Vec<SourcePackArtifactIndexRange>,
    pub input_interfaces: Vec<SourcePackArtifactRef>,
    #[serde(default)]
    pub input_object_count: usize,
    #[serde(default)]
    pub input_object_page_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub input_object_artifact_ranges: Vec<SourcePackArtifactIndexRange>,
    pub input_objects: Vec<SourcePackArtifactRef>,
    pub outputs: Vec<SourcePackArtifactRef>,
}

impl SourcePackJobArtifactManifest {
    pub fn input_artifact_count(&self) -> usize {
        let input_interface_job_range_count = self
            .input_interface_ranges
            .iter()
            .map(|range| range.job_count)
            .sum::<usize>();
        let input_interface_artifact_range_count =
            source_pack_artifact_index_range_count(&self.input_interface_artifact_ranges);
        let input_object_artifact_range_count =
            source_pack_artifact_index_range_count(&self.input_object_artifact_ranges);
        self.input_interface_count
            .max(
                self.input_interfaces
                    .len()
                    .saturating_add(input_interface_job_range_count)
                    .saturating_add(input_interface_artifact_range_count),
            )
            .saturating_add(
                self.input_object_count.max(
                    self.input_objects
                        .len()
                        .saturating_add(input_object_artifact_range_count),
                ),
            )
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJobArtifactManifestPlan {
    pub jobs: Vec<SourcePackJobArtifactManifest>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SourcePackJobArtifactManifestSummary {
    pub job_count: usize,
    pub max_input_artifact_count: usize,
}

impl SourcePackJobArtifactManifestSummary {
    pub fn max_input_artifact_count(&self) -> usize {
        self.max_input_artifact_count
    }
}

impl SourcePackJobArtifactManifestPlan {
    pub fn max_input_artifact_count(&self) -> usize {
        self.jobs
            .iter()
            .map(SourcePackJobArtifactManifest::input_artifact_count)
            .max()
            .unwrap_or(0)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLinkObjectBatch {
    pub batch_index: usize,
    pub input_object_artifact_indices: Vec<usize>,
    pub source_bytes: usize,
    pub source_file_count: usize,
    #[serde(default)]
    pub source_lines: usize,
}

impl SourcePackLinkObjectBatch {
    pub fn object_count(&self) -> usize {
        self.input_object_artifact_indices.len()
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLinkInterfaceBatch {
    pub batch_index: usize,
    pub input_interface_artifact_indices: Vec<usize>,
    pub source_bytes: usize,
    pub source_file_count: usize,
    #[serde(default)]
    pub source_lines: usize,
}

impl SourcePackLinkInterfaceBatch {
    pub fn interface_count(&self) -> usize {
        self.input_interface_artifact_indices.len()
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLinkInterfaceBatchPlan {
    pub batches: Vec<SourcePackLinkInterfaceBatch>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SourcePackLinkInterfaceBatchSummary {
    pub batch_count: usize,
    pub max_batch_interface_count: usize,
    pub max_batch_source_bytes: usize,
    pub max_batch_source_files: usize,
}

impl SourcePackLinkInterfaceBatchSummary {
    pub fn batch_count(&self) -> usize {
        self.batch_count
    }

    pub fn max_batch_interface_count(&self) -> usize {
        self.max_batch_interface_count
    }

    pub fn max_batch_source_bytes(&self) -> usize {
        self.max_batch_source_bytes
    }

    pub fn max_batch_source_files(&self) -> usize {
        self.max_batch_source_files
    }

    fn record(&mut self, batch: &SourcePackLinkInterfaceBatch) {
        self.record_batch_counts(
            batch.interface_count(),
            batch.source_bytes,
            batch.source_file_count,
        );
    }

    fn record_batch_counts(
        &mut self,
        interface_count: usize,
        source_bytes: usize,
        source_file_count: usize,
    ) {
        self.batch_count = self.batch_count.saturating_add(1);
        self.max_batch_interface_count = self.max_batch_interface_count.max(interface_count);
        self.max_batch_source_bytes = self.max_batch_source_bytes.max(source_bytes);
        self.max_batch_source_files = self.max_batch_source_files.max(source_file_count);
    }
}

impl SourcePackLinkInterfaceBatchPlan {
    pub fn batch_count(&self) -> usize {
        self.batches.len()
    }

    pub fn max_batch_interface_count(&self) -> usize {
        self.batches
            .iter()
            .map(SourcePackLinkInterfaceBatch::interface_count)
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

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLinkObjectBatchPlan {
    pub batches: Vec<SourcePackLinkObjectBatch>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SourcePackLinkObjectBatchSummary {
    pub batch_count: usize,
    pub max_batch_object_count: usize,
    pub max_batch_source_bytes: usize,
    pub max_batch_source_files: usize,
}

impl SourcePackLinkObjectBatchSummary {
    pub fn batch_count(&self) -> usize {
        self.batch_count
    }

    pub fn max_batch_object_count(&self) -> usize {
        self.max_batch_object_count
    }

    pub fn max_batch_source_bytes(&self) -> usize {
        self.max_batch_source_bytes
    }

    pub fn max_batch_source_files(&self) -> usize {
        self.max_batch_source_files
    }

    fn record(&mut self, batch: &SourcePackLinkObjectBatch) {
        self.record_batch_counts(
            batch.object_count(),
            batch.source_bytes,
            batch.source_file_count,
        );
    }

    fn record_batch_counts(
        &mut self,
        object_count: usize,
        source_bytes: usize,
        source_file_count: usize,
    ) {
        self.batch_count = self.batch_count.saturating_add(1);
        self.max_batch_object_count = self.max_batch_object_count.max(object_count);
        self.max_batch_source_bytes = self.max_batch_source_bytes.max(source_bytes);
        self.max_batch_source_files = self.max_batch_source_files.max(source_file_count);
    }
}

impl SourcePackLinkObjectBatchPlan {
    pub fn batch_count(&self) -> usize {
        self.batches.len()
    }

    pub fn max_batch_object_count(&self) -> usize {
        self.batches
            .iter()
            .map(SourcePackLinkObjectBatch::object_count)
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

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackBuildPlan {
    pub schedule: SourcePackJobSchedule,
    pub artifacts: Vec<SourcePackArtifactPlan>,
    pub link: SourcePackLinkPlan,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SourcePackBuildArtifactEstimateSummary {
    pub artifact_manifest: SourcePackArtifactManifestSummary,
    pub artifact_lifetimes: SourcePackArtifactLifetimeSummary,
    pub job_artifacts: SourcePackJobArtifactIoSummary,
    pub job_artifact_manifest: SourcePackJobArtifactManifestSummary,
    pub link_interface_batches: SourcePackLinkInterfaceBatchSummary,
    pub link_object_batches: SourcePackLinkObjectBatchSummary,
    pub total_artifacts: usize,
    pub interface_artifacts: usize,
    pub object_artifacts: usize,
    pub linked_output_artifacts: usize,
    pub link_interface_inputs: usize,
    pub link_object_inputs: usize,
    pub artifact_use_count: usize,
}

pub const SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION: u32 = 1;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum SourcePackArtifactTarget {
    #[default]
    Generic,
    Wasm,
    X86_64,
}

impl SourcePackArtifactTarget {
    pub fn key_prefix(self) -> Option<&'static str> {
        match self {
            Self::Generic => None,
            Self::Wasm => Some("wasm"),
            Self::X86_64 => Some("x86_64"),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
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

pub const SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION: u32 = 1;

pub const DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES: usize = 64;
pub const DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_JOBS: usize = 256;
pub const DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_ARTIFACTS: usize = 512;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
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
pub enum SourcePackBuildArtifactShardKind {
    JobBatches,
    LinkInterfaceBatches,
    LinkObjectBatches,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
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
    pub fn batch_count(&self) -> usize {
        self.batch_indices.len()
    }

    pub fn job_count(&self) -> usize {
        self.job_indices.len()
    }

    pub fn artifact_count(&self) -> usize {
        self.input_artifact_indices
            .len()
            .saturating_add(source_pack_artifact_index_range_count(
                &self.input_artifact_ranges,
            ))
            .saturating_add(self.output_artifact_indices.len())
    }

    pub fn artifact_record_count(&self) -> usize {
        self.input_artifact_indices
            .len()
            .saturating_add(self.input_artifact_ranges.len())
            .saturating_add(self.output_artifact_indices.len())
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
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
    pub fn shard_count(&self) -> usize {
        self.shard_count
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackBuildArtifactShardPlan {
    pub index: SourcePackBuildArtifactShardIndex,
    pub shards: Vec<SourcePackBuildArtifactShard>,
}

impl SourcePackBuildArtifactShardPlan {
    pub fn shard_count(&self) -> usize {
        self.index.shard_count()
    }

    pub fn max_shard_batch_count(&self) -> usize {
        self.shards
            .iter()
            .map(SourcePackBuildArtifactShard::batch_count)
            .max()
            .unwrap_or(0)
    }

    pub fn max_shard_job_count(&self) -> usize {
        self.shards
            .iter()
            .map(SourcePackBuildArtifactShard::job_count)
            .max()
            .unwrap_or(0)
    }

    pub fn max_shard_artifact_count(&self) -> usize {
        self.shards
            .iter()
            .map(SourcePackBuildArtifactShard::artifact_record_count)
            .max()
            .unwrap_or(0)
    }

    pub fn oversized_shard_count(&self) -> usize {
        self.shards.iter().filter(|shard| shard.oversized).count()
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct SourcePackArtifactIndicesByKind {
    library_interfaces: Vec<usize>,
    codegen_objects: Vec<usize>,
    linked_outputs: Vec<usize>,
}

#[derive(Clone, Debug)]
struct SourcePackBuildArtifactShardBuilder {
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
        let job_count = source_pack_build_shard_union_count(&self.job_indices, &next.job_indices);
        let artifact_count = source_pack_build_shard_artifact_union_count(self, next);
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
        let input_artifact_ranges = source_pack_compact_artifact_index_ranges(std::mem::take(
            &mut self.input_artifact_ranges,
        ));
        let input_artifact_indices = self
            .input_artifact_indices
            .into_iter()
            .filter(|artifact_index| {
                !source_pack_artifact_index_covered_by_ranges(
                    *artifact_index,
                    &input_artifact_ranges,
                )
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

fn artifact_indices_for_job_kind(
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

fn source_pack_interface_artifact_range_for_job_range(
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

fn source_pack_push_interface_artifact_inputs_for_job_range(
    artifact_indices_by_job_and_kind: &[SourcePackArtifactIndicesByKind],
    dependency_job_range: &SourcePackJobIndexRange,
    input_interface_artifact_ranges: &mut Vec<SourcePackArtifactIndexRange>,
    input_interface_artifact_indices: &mut Vec<usize>,
) {
    if let Some(artifact_range) = source_pack_interface_artifact_range_for_job_range(
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
        let shard_count =
            count_source_pack_build_shards(
                SourcePackBuildArtifactShardKind::JobBatches,
                limits,
                self.job_batches
                    .batches
                    .iter()
                    .map(|batch| self.job_batch_shard_builder(batch)),
            )
            .saturating_add(count_source_pack_build_shards(
                SourcePackBuildArtifactShardKind::LinkInterfaceBatches,
                limits,
                self.link_interface_batches.batches.iter().map(|batch| {
                    source_pack_link_interface_batch_shard_builder(batch, link_job_index)
                }),
            ))
            .saturating_add(count_source_pack_build_shards(
                SourcePackBuildArtifactShardKind::LinkObjectBatches,
                limits,
                self.link_object_batches.batches.iter().map(|batch| {
                    source_pack_link_object_batch_shard_builder(batch, link_job_index)
                }),
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

        try_emit_source_pack_build_shards(
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
        try_emit_source_pack_build_shards(
            &mut next_shard_index,
            self.target,
            limits,
            SourcePackBuildArtifactShardKind::LinkInterfaceBatches,
            self.link_interface_batches
                .batches
                .iter()
                .map(|batch| source_pack_link_interface_batch_shard_builder(batch, link_job_index)),
            &mut visitor,
        )?;
        try_emit_source_pack_build_shards(
            &mut next_shard_index,
            self.target,
            limits,
            SourcePackBuildArtifactShardKind::LinkObjectBatches,
            self.link_object_batches
                .batches
                .iter()
                .map(|batch| source_pack_link_object_batch_shard_builder(batch, link_job_index)),
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

        append_source_pack_build_shards(
            &mut shards,
            self.target,
            limits,
            SourcePackBuildArtifactShardKind::JobBatches,
            self.job_batches
                .batches
                .iter()
                .map(|batch| self.job_batch_shard_builder(batch)),
        );
        append_source_pack_build_shards(
            &mut shards,
            self.target,
            limits,
            SourcePackBuildArtifactShardKind::LinkInterfaceBatches,
            self.link_interface_batches
                .batches
                .iter()
                .map(|batch| source_pack_link_interface_batch_shard_builder(batch, link_job_index)),
        );
        append_source_pack_build_shards(
            &mut shards,
            self.target,
            limits,
            SourcePackBuildArtifactShardKind::LinkObjectBatches,
            self.link_object_batches
                .batches
                .iter()
                .map(|batch| source_pack_link_object_batch_shard_builder(batch, link_job_index)),
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

fn append_source_pack_build_shards<I>(
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

fn try_emit_source_pack_build_shards<I, F, E>(
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

fn count_source_pack_build_shards<I>(
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

fn source_pack_link_interface_batch_shard_builder(
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

fn source_pack_link_object_batch_shard_builder(
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

fn source_pack_build_shard_union_count(left: &BTreeSet<usize>, right: &BTreeSet<usize>) -> usize {
    left.union(right).count()
}

fn source_pack_build_shard_artifact_union_count(
    left: &SourcePackBuildArtifactShardBuilder,
    right: &SourcePackBuildArtifactShardBuilder,
) -> usize {
    let input_artifact_ranges = source_pack_compact_artifact_index_ranges(
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
            !source_pack_artifact_index_covered_by_ranges(*artifact_index, &input_artifact_ranges)
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

impl SourcePackBuildPlan {
    pub fn interface_artifact_count(&self) -> usize {
        self.artifacts
            .iter()
            .filter(|artifact| artifact.kind == SourcePackArtifactKind::LibraryInterface)
            .count()
    }

    pub fn object_artifact_count(&self) -> usize {
        self.artifacts
            .iter()
            .filter(|artifact| artifact.kind == SourcePackArtifactKind::CodegenObject)
            .count()
    }

    pub fn linked_output_artifact_count(&self) -> usize {
        self.artifacts
            .iter()
            .filter(|artifact| artifact.kind == SourcePackArtifactKind::LinkedOutput)
            .count()
    }

    pub fn build_artifact_manifest(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> SourcePackBuildArtifactManifest {
        self.compact_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn build_artifact_manifest_for_target(
        &self,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> SourcePackBuildArtifactManifest {
        self.compact_build_artifact_manifest_for_target(batch_limits, target)
    }

    pub fn try_build_artifact_manifest(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        self.try_compact_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn retained_build_artifact_manifest(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> SourcePackBuildArtifactManifest {
        self.retained_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn retained_build_artifact_manifest_for_target(
        &self,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> SourcePackBuildArtifactManifest {
        self.try_retained_build_artifact_manifest_for_target(batch_limits, target)
            .expect("source-pack retained build artifact manifest schedule should be acyclic")
    }

    pub fn try_retained_build_artifact_manifest(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        self.try_retained_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn compact_build_artifact_manifest(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> SourcePackBuildArtifactManifest {
        self.compact_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn compact_build_artifact_manifest_for_target(
        &self,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> SourcePackBuildArtifactManifest {
        self.try_compact_build_artifact_manifest_for_target(batch_limits, target)
            .expect("source-pack compact build artifact manifest schedule should be acyclic")
    }

    pub fn try_compact_build_artifact_manifest(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        self.try_compact_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn try_compact_build_artifact_manifest_for_target(
        &self,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        let job_batch_count = self.schedule.try_for_each_execution_batch(
            batch_limits,
            |err| err,
            |_| Ok::<(), SourcePackScheduleError>(()),
        )?;
        let link_interface_batch_count = self
            .try_for_each_link_interface_batch(batch_limits, |_| {
                Ok::<(), SourcePackScheduleError>(())
            })?;
        let link_object_batch_count = self.try_for_each_link_object_batch(batch_limits, |_| {
            Ok::<(), SourcePackScheduleError>(())
        })?;
        Ok(SourcePackBuildArtifactManifest {
            version: SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION,
            target,
            job_count: self.schedule.jobs.len(),
            job_batch_count,
            batch_dependency_count: job_batch_count,
            artifact_count: self.artifacts.len(),
            job_artifact_count: self.schedule.jobs.len(),
            job_artifact_io_count: self.schedule.jobs.len(),
            artifact_use_count: self.artifacts.len(),
            link_interface_batch_count,
            link_object_batch_count,
            job_schedule: Default::default(),
            job_batches: Default::default(),
            batch_dependencies: Default::default(),
            artifacts: Default::default(),
            job_artifacts: Default::default(),
            job_artifact_io: Default::default(),
            artifact_uses: Default::default(),
            link_interface_batches: Default::default(),
            link_object_batches: Default::default(),
        })
    }

    pub fn try_build_artifact_manifest_for_target(
        &self,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        self.try_compact_build_artifact_manifest_for_target(batch_limits, target)
    }

    pub fn try_retained_build_artifact_manifest_for_target(
        &self,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        let job_batches = self.schedule.try_execution_batches(batch_limits)?;
        let batch_dependencies = self.schedule.try_batch_dependency_plan(&job_batches)?;
        let artifacts = self.artifact_manifest_for_target(target);
        let job_artifacts = self.job_artifact_manifest_plan_for_target(target);
        let job_artifact_io = self.job_artifact_io_plan();
        let artifact_uses = self.artifact_use_plan();
        let link_interface_batches = self.link_interface_batches(batch_limits);
        let link_object_batches = self.link_object_batches(batch_limits);
        Ok(SourcePackBuildArtifactManifest {
            version: SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION,
            target,
            job_count: self.schedule.jobs.len(),
            job_batch_count: job_batches.batches.len(),
            batch_dependency_count: batch_dependencies.batches.len(),
            artifact_count: artifacts.artifacts.len(),
            job_artifact_count: job_artifacts.jobs.len(),
            job_artifact_io_count: job_artifact_io.jobs.len(),
            artifact_use_count: artifact_uses.uses.len(),
            link_interface_batch_count: link_interface_batches.batches.len(),
            link_object_batch_count: link_object_batches.batches.len(),
            job_schedule: self.schedule.clone(),
            job_batches,
            batch_dependencies,
            artifacts,
            job_artifacts,
            job_artifact_io,
            artifact_uses,
            link_interface_batches,
            link_object_batches,
        })
    }

    pub fn artifact_use_plan(&self) -> SourcePackArtifactUsePlan {
        let mut uses = self
            .artifacts
            .iter()
            .map(|artifact| SourcePackArtifactUse {
                artifact_index: artifact.artifact_index,
                producing_job_index: artifact.producing_job_index,
                consumer_job_indices: Vec::new(),
                last_consumer_job_index: None,
            })
            .collect::<Vec<_>>();
        let artifact_indices_by_job = self.artifact_indices_by_producing_job();
        let artifact_indices_by_job_and_kind = self.artifact_indices_by_producing_job_and_kind();

        for job in &self.schedule.jobs {
            for &dependency_job_index in &job.dependency_job_indices {
                let Some(artifact_indices) = artifact_indices_by_job.get(dependency_job_index)
                else {
                    continue;
                };
                for &artifact_index in artifact_indices {
                    if let Some(artifact_use) = uses.get_mut(artifact_index) {
                        push_unique(&mut artifact_use.consumer_job_indices, job.job_index);
                    }
                }
            }
            for dependency_job_range in self.schedule.dependency_job_ranges_for_job(job) {
                if let Some(artifact_range) = source_pack_interface_artifact_range_for_job_range(
                    &artifact_indices_by_job_and_kind,
                    dependency_job_range,
                ) {
                    if let Some(artifact_indices) = artifact_range.iter() {
                        for artifact_index in artifact_indices {
                            if let Some(artifact_use) = uses.get_mut(artifact_index) {
                                push_unique(&mut artifact_use.consumer_job_indices, job.job_index);
                            }
                        }
                    }
                    continue;
                }
                let Some(dependency_job_indices) = dependency_job_range.iter() else {
                    continue;
                };
                for dependency_job_index in dependency_job_indices {
                    let Some(artifact_indices) = artifact_indices_by_job.get(dependency_job_index)
                    else {
                        continue;
                    };
                    for &artifact_index in artifact_indices {
                        if let Some(artifact_use) = uses.get_mut(artifact_index) {
                            push_unique(&mut artifact_use.consumer_job_indices, job.job_index);
                        }
                    }
                }
            }
        }

        self.link
            .try_for_each_input_interface_artifact_index(|artifact_index| {
                if let Some(artifact_use) = uses.get_mut(artifact_index) {
                    push_unique(
                        &mut artifact_use.consumer_job_indices,
                        self.link.link_job_index,
                    );
                }
                Ok::<(), ()>(())
            })
            .unwrap_or_else(|()| unreachable!("infallible interface artifact use visit failed"));
        self.link
            .try_for_each_input_object_artifact_index(|artifact_index| {
                if let Some(artifact_use) = uses.get_mut(artifact_index) {
                    push_unique(
                        &mut artifact_use.consumer_job_indices,
                        self.link.link_job_index,
                    );
                }
                Ok::<(), ()>(())
            })
            .unwrap_or_else(|()| unreachable!("infallible object artifact use visit failed"));

        for artifact_use in &mut uses {
            artifact_use.consumer_job_indices.sort_unstable();
            artifact_use.last_consumer_job_index =
                artifact_use.consumer_job_indices.iter().copied().max();
        }

        SourcePackArtifactUsePlan { uses }
    }

    pub fn artifact_last_use_plan(&self) -> SourcePackArtifactLastUsePlan {
        let index = self.artifact_last_use_index();
        let artifacts = self
            .artifacts
            .iter()
            .map(|artifact| SourcePackArtifactLastUse {
                artifact_index: artifact.artifact_index,
                producing_job_index: artifact.producing_job_index,
                last_consumer_job_index: index
                    .last_consumer_job_indices
                    .get(artifact.artifact_index)
                    .copied()
                    .flatten(),
            })
            .collect();
        SourcePackArtifactLastUsePlan { artifacts }
    }

    pub fn artifact_last_use_index(&self) -> SourcePackArtifactLastUseIndex {
        let mut last_consumer_job_indices = vec![None; self.artifacts.len()];
        let artifact_indices_by_job = self.artifact_indices_by_producing_job();
        let artifact_indices_by_job_and_kind = self.artifact_indices_by_producing_job_and_kind();

        for job in &self.schedule.jobs {
            for &dependency_job_index in &job.dependency_job_indices {
                let Some(artifact_indices) = artifact_indices_by_job.get(dependency_job_index)
                else {
                    continue;
                };
                for &artifact_index in artifact_indices {
                    record_artifact_last_consumer(
                        &mut last_consumer_job_indices,
                        artifact_index,
                        job.job_index,
                    );
                }
            }
            for dependency_job_range in self.schedule.dependency_job_ranges_for_job(job) {
                if let Some(artifact_range) = source_pack_interface_artifact_range_for_job_range(
                    &artifact_indices_by_job_and_kind,
                    dependency_job_range,
                ) {
                    if let Some(artifact_indices) = artifact_range.iter() {
                        for artifact_index in artifact_indices {
                            record_artifact_last_consumer(
                                &mut last_consumer_job_indices,
                                artifact_index,
                                job.job_index,
                            );
                        }
                    }
                    continue;
                }
                let Some(dependency_job_indices) = dependency_job_range.iter() else {
                    continue;
                };
                for dependency_job_index in dependency_job_indices {
                    let Some(artifact_indices) = artifact_indices_by_job.get(dependency_job_index)
                    else {
                        continue;
                    };
                    for &artifact_index in artifact_indices {
                        record_artifact_last_consumer(
                            &mut last_consumer_job_indices,
                            artifact_index,
                            job.job_index,
                        );
                    }
                }
            }
        }

        self.link
            .try_for_each_input_interface_artifact_index(|artifact_index| {
                record_artifact_last_consumer(
                    &mut last_consumer_job_indices,
                    artifact_index,
                    self.link.link_job_index,
                );
                Ok::<(), ()>(())
            })
            .unwrap_or_else(|()| {
                unreachable!("infallible interface artifact last-use visit failed")
            });
        self.link
            .try_for_each_input_object_artifact_index(|artifact_index| {
                record_artifact_last_consumer(
                    &mut last_consumer_job_indices,
                    artifact_index,
                    self.link.link_job_index,
                );
                Ok::<(), ()>(())
            })
            .unwrap_or_else(|()| unreachable!("infallible object artifact last-use visit failed"));

        SourcePackArtifactLastUseIndex {
            last_consumer_job_indices,
        }
    }

    pub fn artifact_lifetime_summary(&self) -> SourcePackArtifactLifetimeSummary {
        SourcePackArtifactLifetimeSummary {
            artifact_count: self.artifacts.len(),
            artifacts_without_consumers: self.artifacts.len().saturating_sub(
                self.link
                    .input_interface_artifact_count()
                    .saturating_add(self.link.input_object_artifact_count()),
            ),
        }
    }

    pub fn artifact_manifest(&self) -> SourcePackArtifactManifest {
        self.artifact_manifest_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn artifact_manifest_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> SourcePackArtifactManifest {
        SourcePackArtifactManifest {
            artifacts: self
                .artifacts
                .iter()
                .map(|artifact| SourcePackArtifactManifestEntry {
                    artifact_index: artifact.artifact_index,
                    key: source_pack_artifact_key_for_target(artifact, target),
                    producing_job_index: artifact.producing_job_index,
                    kind: artifact.kind,
                    library_id: artifact.library_id,
                    first_source_index: artifact.first_source_index,
                    source_file_count: artifact.source_file_count,
                    source_bytes: artifact.source_bytes,
                    source_lines: artifact.source_lines,
                })
                .collect(),
        }
    }

    pub fn artifact_manifest_summary(&self) -> SourcePackArtifactManifestSummary {
        self.artifact_manifest_summary_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn artifact_manifest_summary_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> SourcePackArtifactManifestSummary {
        let mut summary = SourcePackArtifactManifestSummary {
            artifact_count: self.artifacts.len(),
            max_key_len: 0,
        };
        for artifact in &self.artifacts {
            summary.max_key_len = summary
                .max_key_len
                .max(source_pack_artifact_key_for_target(artifact, target).len());
        }
        summary
    }

    pub fn job_artifact_io_plan(&self) -> SourcePackJobArtifactIoPlan {
        let mut jobs = Vec::new();
        self.try_for_each_job_artifact_io(|job| {
            jobs.push(job);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible job-artifact-io collection failed"));
        SourcePackJobArtifactIoPlan { jobs }
    }

    pub fn job_artifact_io_summary(&self) -> SourcePackJobArtifactIoSummary {
        let mut summary = SourcePackJobArtifactIoSummary::default();
        self.try_for_each_job_artifact_io(|job| {
            summary.record(&job);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible job-artifact-io summary failed"));
        summary
    }

    pub fn try_for_each_job_artifact_io<F, E>(&self, mut visit: F) -> Result<usize, E>
    where
        F: FnMut(SourcePackJobArtifactIo) -> Result<(), E>,
    {
        let artifact_indices_by_job_and_kind = self.artifact_indices_by_producing_job_and_kind();
        let artifact_indices_by_job = self.artifact_indices_by_producing_job();
        let mut job_count = 0usize;

        for job in &self.schedule.jobs {
            let mut input_interface_artifact_indices = Vec::new();
            let mut input_interface_artifact_ranges = Vec::new();
            let input_interface_artifact_count;
            let mut input_object_artifact_indices = Vec::new();
            let mut input_object_artifact_ranges = Vec::new();
            let mut input_object_artifact_count = 0usize;

            match job.phase {
                SourcePackJobPhase::LibraryFrontend | SourcePackJobPhase::Codegen => {
                    for &dependency_job_index in &job.dependency_job_indices {
                        for &artifact_index in artifact_indices_for_job_kind(
                            &artifact_indices_by_job_and_kind,
                            dependency_job_index,
                            SourcePackArtifactKind::LibraryInterface,
                        ) {
                            push_unique(&mut input_interface_artifact_indices, artifact_index);
                        }
                    }
                    for dependency_job_range in self.schedule.dependency_job_ranges_for_job(job) {
                        source_pack_push_interface_artifact_inputs_for_job_range(
                            &artifact_indices_by_job_and_kind,
                            dependency_job_range,
                            &mut input_interface_artifact_ranges,
                            &mut input_interface_artifact_indices,
                        );
                    }
                    input_interface_artifact_count = input_interface_artifact_indices
                        .len()
                        .saturating_add(source_pack_artifact_index_range_count(
                            &input_interface_artifact_ranges,
                        ));
                }
                SourcePackJobPhase::Link => {
                    input_interface_artifact_count = self.link.input_interface_artifact_count();
                    input_interface_artifact_ranges =
                        self.link.input_interface_artifact_ranges.clone();
                    input_interface_artifact_indices =
                        self.link.input_interface_artifact_indices.clone();
                    input_object_artifact_count = self.link.input_object_artifact_count();
                    input_object_artifact_ranges = self.link.input_object_artifact_ranges.clone();
                    input_object_artifact_indices = self.link.input_object_artifact_indices.clone();
                }
            }

            let output_artifact_indices = artifact_indices_by_job
                .get(job.job_index)
                .cloned()
                .unwrap_or_default();

            visit(SourcePackJobArtifactIo {
                job_index: job.job_index,
                phase: job.phase,
                input_interface_artifact_count,
                input_interface_artifact_ranges,
                input_interface_artifact_indices,
                input_object_artifact_count,
                input_object_artifact_ranges,
                input_object_artifact_indices,
                output_artifact_indices,
            })?;
            job_count += 1;
        }

        Ok(job_count)
    }

    pub fn job_artifact_manifest_plan(&self) -> SourcePackJobArtifactManifestPlan {
        self.job_artifact_manifest_plan_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn job_artifact_manifest_plan_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> SourcePackJobArtifactManifestPlan {
        let mut jobs = Vec::new();
        self.try_for_each_job_artifact_manifest_for_target(target, |job| {
            jobs.push(job);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible job-artifact-manifest collection failed"));
        SourcePackJobArtifactManifestPlan { jobs }
    }

    pub fn job_artifact_manifest_summary(&self) -> SourcePackJobArtifactManifestSummary {
        let io_summary = self.job_artifact_io_summary();
        SourcePackJobArtifactManifestSummary {
            job_count: io_summary.job_count,
            max_input_artifact_count: io_summary.max_input_artifact_count,
        }
    }

    pub fn try_for_each_job_artifact_manifest_for_target<F, E>(
        &self,
        target: SourcePackArtifactTarget,
        mut visit: F,
    ) -> Result<usize, E>
    where
        F: FnMut(SourcePackJobArtifactManifest) -> Result<(), E>,
    {
        let mut job_count = 0usize;
        let artifact_indices_by_job = self.artifact_indices_by_producing_job();
        let artifact_indices_by_job_and_kind = self.artifact_indices_by_producing_job_and_kind();

        for job in &self.schedule.jobs {
            let mut input_interface_artifact_indices = Vec::new();
            let mut input_interface_ranges = Vec::new();
            let mut input_interface_artifact_ranges = Vec::new();
            let input_interface_count;
            let mut input_object_artifact_indices = Vec::new();
            let mut input_object_artifact_ranges = Vec::new();
            let mut input_object_count = 0usize;

            match job.phase {
                SourcePackJobPhase::LibraryFrontend | SourcePackJobPhase::Codegen => {
                    for &dependency_job_index in &job.dependency_job_indices {
                        for &artifact_index in artifact_indices_for_job_kind(
                            &artifact_indices_by_job_and_kind,
                            dependency_job_index,
                            SourcePackArtifactKind::LibraryInterface,
                        ) {
                            push_unique(&mut input_interface_artifact_indices, artifact_index);
                        }
                    }
                    input_interface_ranges =
                        self.schedule.dependency_job_ranges_for_job(job).to_vec();
                    input_interface_count = input_interface_artifact_indices.len().saturating_add(
                        source_pack_job_index_range_dependency_count(&input_interface_ranges),
                    );
                }
                SourcePackJobPhase::Link => {
                    input_interface_count = self.link.input_interface_artifact_count();
                    input_interface_artifact_ranges =
                        self.link.input_interface_artifact_ranges.clone();
                    input_interface_artifact_indices =
                        self.link.input_interface_artifact_indices.clone();
                    input_object_count = self.link.input_object_artifact_count();
                    input_object_artifact_ranges = self.link.input_object_artifact_ranges.clone();
                    input_object_artifact_indices = self.link.input_object_artifact_indices.clone();
                }
            }

            let output_artifact_indices = artifact_indices_by_job
                .get(job.job_index)
                .cloned()
                .unwrap_or_default();
            visit(SourcePackJobArtifactManifest {
                job_index: job.job_index,
                phase: job.phase,
                input_interface_count,
                input_interface_page_count: 0,
                input_interface_ranges,
                input_interface_artifact_ranges,
                input_interfaces: artifact_refs_from_indices(
                    &self.artifacts,
                    &input_interface_artifact_indices,
                    target,
                ),
                input_object_count,
                input_object_page_count: 0,
                input_object_artifact_ranges,
                input_objects: artifact_refs_from_indices(
                    &self.artifacts,
                    &input_object_artifact_indices,
                    target,
                ),
                outputs: artifact_refs_from_indices(
                    &self.artifacts,
                    &output_artifact_indices,
                    target,
                ),
            })?;
            job_count += 1;
        }
        Ok(job_count)
    }

    fn artifact_indices_by_producing_job(&self) -> Vec<Vec<usize>> {
        let max_job_index = self
            .artifacts
            .iter()
            .map(|artifact| artifact.producing_job_index)
            .max()
            .unwrap_or(0);
        let mut artifact_indices_by_job = vec![Vec::new(); max_job_index.saturating_add(1)];
        for artifact in &self.artifacts {
            if let Some(artifact_indices) =
                artifact_indices_by_job.get_mut(artifact.producing_job_index)
            {
                artifact_indices.push(artifact.artifact_index);
            }
        }
        artifact_indices_by_job
    }

    fn artifact_indices_by_producing_job_and_kind(&self) -> Vec<SourcePackArtifactIndicesByKind> {
        let max_job_index = self
            .artifacts
            .iter()
            .map(|artifact| artifact.producing_job_index)
            .max()
            .unwrap_or(0);
        let mut artifact_indices_by_job =
            vec![SourcePackArtifactIndicesByKind::default(); max_job_index.saturating_add(1)];
        for artifact in &self.artifacts {
            let Some(artifact_indices) =
                artifact_indices_by_job.get_mut(artifact.producing_job_index)
            else {
                continue;
            };
            match artifact.kind {
                SourcePackArtifactKind::LibraryInterface => {
                    artifact_indices
                        .library_interfaces
                        .push(artifact.artifact_index);
                }
                SourcePackArtifactKind::CodegenObject => {
                    artifact_indices
                        .codegen_objects
                        .push(artifact.artifact_index);
                }
                SourcePackArtifactKind::LinkedOutput => {
                    artifact_indices
                        .linked_outputs
                        .push(artifact.artifact_index);
                }
            }
        }
        artifact_indices_by_job
    }

    pub fn link_interface_batches(
        &self,
        limits: SourcePackJobBatchLimits,
    ) -> SourcePackLinkInterfaceBatchPlan {
        let mut batches = Vec::new();
        self.try_for_each_link_interface_batch(limits, |batch| {
            batches.push(batch);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible link-interface batch collection failed"));
        SourcePackLinkInterfaceBatchPlan { batches }
    }

    pub fn link_interface_batch_summary(
        &self,
        limits: SourcePackJobBatchLimits,
    ) -> SourcePackLinkInterfaceBatchSummary {
        let mut summary = SourcePackLinkInterfaceBatchSummary::default();
        self.try_for_each_link_interface_batch(limits, |batch| {
            summary.record(&batch);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible link-interface batch summary failed"));
        summary
    }

    pub fn try_for_each_link_interface_batch<F, E>(
        &self,
        limits: SourcePackJobBatchLimits,
        mut visit: F,
    ) -> Result<usize, E>
    where
        F: FnMut(SourcePackLinkInterfaceBatch) -> Result<(), E>,
    {
        let limits = limits.normalized();
        let max_input_artifacts_per_batch = source_pack_link_batch_input_limit(limits);
        let mut current_artifacts = Vec::new();
        let mut current_source_bytes = 0usize;
        let mut current_source_file_count = 0usize;
        let mut current_source_lines = 0usize;
        let mut batch_count = 0usize;

        self.link
            .try_for_each_input_interface_artifact_index(|artifact_index| {
                let Some(artifact) = self.artifacts.get(artifact_index) else {
                    return Ok(());
                };
                let should_flush = !current_artifacts.is_empty()
                    && (current_artifacts.len() >= max_input_artifacts_per_batch
                        || current_source_bytes.saturating_add(artifact.source_bytes)
                            > limits.max_source_bytes_per_batch
                        || current_source_file_count.saturating_add(artifact.source_file_count)
                            > limits.max_source_files_per_batch);
                if should_flush {
                    visit(SourcePackLinkInterfaceBatch {
                        batch_index: batch_count,
                        input_interface_artifact_indices: std::mem::take(&mut current_artifacts),
                        source_bytes: current_source_bytes,
                        source_file_count: current_source_file_count,
                        source_lines: current_source_lines,
                    })?;
                    batch_count += 1;
                    current_source_bytes = 0;
                    current_source_file_count = 0;
                    current_source_lines = 0;
                }
                current_artifacts.push(artifact_index);
                current_source_bytes = current_source_bytes.saturating_add(artifact.source_bytes);
                current_source_file_count =
                    current_source_file_count.saturating_add(artifact.source_file_count);
                current_source_lines = current_source_lines.saturating_add(artifact.source_lines);
                Ok(())
            })?;

        if !current_artifacts.is_empty() {
            visit(SourcePackLinkInterfaceBatch {
                batch_index: batch_count,
                input_interface_artifact_indices: current_artifacts,
                source_bytes: current_source_bytes,
                source_file_count: current_source_file_count,
                source_lines: current_source_lines,
            })?;
            batch_count += 1;
        }

        Ok(batch_count)
    }

    pub fn link_object_batches(
        &self,
        limits: SourcePackJobBatchLimits,
    ) -> SourcePackLinkObjectBatchPlan {
        let mut batches = Vec::new();
        self.try_for_each_link_object_batch(limits, |batch| {
            batches.push(batch);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible link-object batch collection failed"));
        SourcePackLinkObjectBatchPlan { batches }
    }

    pub fn link_object_batch_summary(
        &self,
        limits: SourcePackJobBatchLimits,
    ) -> SourcePackLinkObjectBatchSummary {
        let mut summary = SourcePackLinkObjectBatchSummary::default();
        self.try_for_each_link_object_batch(limits, |batch| {
            summary.record(&batch);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible link-object batch summary failed"));
        summary
    }

    pub fn try_for_each_link_object_batch<F, E>(
        &self,
        limits: SourcePackJobBatchLimits,
        mut visit: F,
    ) -> Result<usize, E>
    where
        F: FnMut(SourcePackLinkObjectBatch) -> Result<(), E>,
    {
        let limits = limits.normalized();
        let max_input_artifacts_per_batch = source_pack_link_batch_input_limit(limits);
        let mut current_artifacts = Vec::new();
        let mut current_source_bytes = 0usize;
        let mut current_source_file_count = 0usize;
        let mut current_source_lines = 0usize;
        let mut batch_count = 0usize;

        self.link
            .try_for_each_input_object_artifact_index(|artifact_index| {
                let Some(artifact) = self.artifacts.get(artifact_index) else {
                    return Ok(());
                };
                let should_flush = !current_artifacts.is_empty()
                    && (current_artifacts.len() >= max_input_artifacts_per_batch
                        || current_source_bytes.saturating_add(artifact.source_bytes)
                            > limits.max_source_bytes_per_batch
                        || current_source_file_count.saturating_add(artifact.source_file_count)
                            > limits.max_source_files_per_batch);
                if should_flush {
                    visit(SourcePackLinkObjectBatch {
                        batch_index: batch_count,
                        input_object_artifact_indices: std::mem::take(&mut current_artifacts),
                        source_bytes: current_source_bytes,
                        source_file_count: current_source_file_count,
                        source_lines: current_source_lines,
                    })?;
                    batch_count += 1;
                    current_source_bytes = 0;
                    current_source_file_count = 0;
                    current_source_lines = 0;
                }
                current_artifacts.push(artifact_index);
                current_source_bytes = current_source_bytes.saturating_add(artifact.source_bytes);
                current_source_file_count =
                    current_source_file_count.saturating_add(artifact.source_file_count);
                current_source_lines = current_source_lines.saturating_add(artifact.source_lines);
                Ok(())
            })?;

        if !current_artifacts.is_empty() {
            visit(SourcePackLinkObjectBatch {
                batch_index: batch_count,
                input_object_artifact_indices: current_artifacts,
                source_bytes: current_source_bytes,
                source_file_count: current_source_file_count,
                source_lines: current_source_lines,
            })?;
            batch_count += 1;
        }

        Ok(batch_count)
    }
}

fn artifact_refs_from_indices(
    artifacts: &[SourcePackArtifactPlan],
    artifact_indices: &[usize],
    target: SourcePackArtifactTarget,
) -> Vec<SourcePackArtifactRef> {
    artifact_indices
        .iter()
        .filter_map(|&artifact_index| artifacts.get(artifact_index))
        .map(|artifact| source_pack_artifact_ref_for_plan(artifact, target))
        .collect()
}

fn source_pack_artifact_ref_for_plan(
    artifact: &SourcePackArtifactPlan,
    target: SourcePackArtifactTarget,
) -> SourcePackArtifactRef {
    SourcePackArtifactRef {
        artifact_index: artifact.artifact_index,
        key: source_pack_artifact_key_for_target(artifact, target),
        producing_job_index: artifact.producing_job_index,
        kind: artifact.kind,
    }
}

fn source_pack_artifact_plan_for_job(
    artifact_index: usize,
    job: &SourcePackJob,
    kind: SourcePackArtifactKind,
) -> SourcePackArtifactPlan {
    SourcePackArtifactPlan {
        artifact_index,
        producing_job_index: job.job_index,
        kind,
        library_id: job.library_id,
        first_source_index: job.first_source_index,
        source_file_count: job.source_file_count,
        source_bytes: job.source_bytes,
        source_lines: job.source_lines,
    }
}

fn record_source_pack_artifact_manifest_estimate(
    summary: &mut SourcePackArtifactManifestSummary,
    artifact: &SourcePackArtifactPlan,
    target: SourcePackArtifactTarget,
) {
    summary.artifact_count = summary.artifact_count.saturating_add(1);
    summary.max_key_len = summary
        .max_key_len
        .max(source_pack_artifact_key_for_target(artifact, target).len());
}

fn source_pack_job_phase_by_job_index(
    schedule: &SourcePackJobSchedule,
) -> Vec<Option<SourcePackJobPhase>> {
    let Some(max_job_index) = schedule.jobs.iter().map(|job| job.job_index).max() else {
        return Vec::new();
    };
    let mut phases = vec![None; max_job_index.saturating_add(1)];
    for job in &schedule.jobs {
        if let Some(phase) = phases.get_mut(job.job_index) {
            *phase = Some(job.phase);
        }
    }
    phases
}

fn record_source_pack_job_artifact_io_estimate(
    summary: &mut SourcePackJobArtifactIoSummary,
    input_interface_count: usize,
    input_object_count: usize,
    output_artifact_count: usize,
) {
    summary.job_count = summary.job_count.saturating_add(1);
    summary.max_input_interface_count =
        summary.max_input_interface_count.max(input_interface_count);
    summary.max_input_object_count = summary.max_input_object_count.max(input_object_count);
    summary.max_input_artifact_count = summary
        .max_input_artifact_count
        .max(input_interface_count.saturating_add(input_object_count));
    summary.max_output_artifact_count =
        summary.max_output_artifact_count.max(output_artifact_count);
}

fn source_pack_artifact_index_in_range(
    artifact_range: &Option<Range<usize>>,
    artifact_index: usize,
) -> bool {
    match artifact_range {
        Some(artifact_range) => artifact_range.contains(&artifact_index),
        None => false,
    }
}

fn record_source_pack_link_input_batch_summary<F>(
    current_artifact_count: &mut usize,
    current_source_bytes: &mut usize,
    current_source_file_count: &mut usize,
    source_bytes: usize,
    source_file_count: usize,
    limits: SourcePackJobBatchLimits,
    max_input_artifacts_per_batch: usize,
    mut record_batch: F,
) where
    F: FnMut(usize, usize, usize),
{
    let should_flush = *current_artifact_count != 0
        && (*current_artifact_count >= max_input_artifacts_per_batch
            || (*current_source_bytes).saturating_add(source_bytes)
                > limits.max_source_bytes_per_batch
            || (*current_source_file_count).saturating_add(source_file_count)
                > limits.max_source_files_per_batch);
    if should_flush {
        record_batch(
            *current_artifact_count,
            *current_source_bytes,
            *current_source_file_count,
        );
        *current_artifact_count = 0;
        *current_source_bytes = 0;
        *current_source_file_count = 0;
    }
    *current_artifact_count = (*current_artifact_count).saturating_add(1);
    *current_source_bytes = (*current_source_bytes).saturating_add(source_bytes);
    *current_source_file_count = (*current_source_file_count).saturating_add(source_file_count);
}

fn finish_source_pack_link_input_batch_summary<F>(
    current_artifact_count: &mut usize,
    current_source_bytes: &mut usize,
    current_source_file_count: &mut usize,
    mut record_batch: F,
) where
    F: FnMut(usize, usize, usize),
{
    if *current_artifact_count == 0 {
        return;
    }
    record_batch(
        *current_artifact_count,
        *current_source_bytes,
        *current_source_file_count,
    );
    *current_artifact_count = 0;
    *current_source_bytes = 0;
    *current_source_file_count = 0;
}

fn record_artifact_last_consumer(
    last_consumer_job_indices: &mut [Option<usize>],
    artifact_index: usize,
    consumer_job_index: usize,
) {
    if let Some(last_consumer_job_index) = last_consumer_job_indices.get_mut(artifact_index) {
        *last_consumer_job_index = last_consumer_job_index
            .map(|current| current.max(consumer_job_index))
            .or(Some(consumer_job_index));
    }
}

fn source_pack_artifact_key_for_target(
    artifact: &SourcePackArtifactPlan,
    target: SourcePackArtifactTarget,
) -> String {
    source_pack_artifact_key_for_output(
        target,
        artifact.kind,
        artifact.library_id,
        artifact.producing_job_index,
        artifact.first_source_index,
        artifact.source_file_count,
    )
}

pub fn source_pack_artifact_key_for_output(
    target: SourcePackArtifactTarget,
    kind: SourcePackArtifactKind,
    library_id: u32,
    producing_job_index: usize,
    first_source_index: usize,
    source_file_count: usize,
) -> String {
    let source_end = first_source_index.saturating_add(source_file_count);
    let base_key = if kind == SourcePackArtifactKind::LinkedOutput {
        format!(
            "{}/job-{}/src-{}-{}",
            kind.key_segment(),
            producing_job_index,
            first_source_index,
            source_end
        )
    } else {
        format!(
            "{}/lib-{}/job-{}/src-{}-{}",
            kind.key_segment(),
            library_id,
            producing_job_index,
            first_source_index,
            source_end
        )
    };
    match target.key_prefix() {
        Some(prefix) => format!("{prefix}/{base_key}"),
        None => base_key,
    }
}

impl SourcePackJobPlan {
    pub fn from_source_pack<S: AsRef<str>>(sources: &[S], limits: CodegenUnitLimits) -> Self {
        Self::from_file_stream_with_dependencies(
            sources.iter().enumerate().map(|(source_index, source)| {
                SourceFileUnitInput::from_source(0, source_index, source.as_ref())
            }),
            &[],
            limits,
        )
    }

    pub fn from_source_pack_with_libraries<S, L>(
        sources: &[S],
        library_ids: &[L],
        limits: CodegenUnitLimits,
    ) -> Self
    where
        S: AsRef<str>,
        L: Copy + Into<u32>,
    {
        Self::from_source_pack_with_libraries_and_dependencies(sources, library_ids, &[], limits)
    }

    pub fn from_source_pack_with_libraries_and_dependencies<S, L>(
        sources: &[S],
        library_ids: &[L],
        library_dependencies: &[SourcePackLibraryDependency],
        limits: CodegenUnitLimits,
    ) -> Self
    where
        S: AsRef<str>,
        L: Copy + Into<u32>,
    {
        assert_eq!(
            sources.len(),
            library_ids.len(),
            "source and library slices must have the same length"
        );
        Self::from_file_stream_with_dependencies(
            sources
                .iter()
                .zip(library_ids.iter().copied())
                .enumerate()
                .map(|(source_index, (source, library_id))| {
                    SourceFileUnitInput::from_source(
                        library_id.into(),
                        source_index,
                        source.as_ref(),
                    )
                }),
            library_dependencies,
            limits,
        )
    }

    pub fn from_files(files: &[SourceFileUnitInput], limits: CodegenUnitLimits) -> Self {
        Self::from_files_with_dependencies(files, &[], limits)
    }

    pub fn from_files_with_dependencies(
        files: &[SourceFileUnitInput],
        library_dependencies: &[SourcePackLibraryDependency],
        limits: CodegenUnitLimits,
    ) -> Self {
        Self::from_file_stream_with_dependencies(
            files.iter().copied(),
            library_dependencies,
            limits,
        )
    }

    pub fn from_file_stream_with_dependencies<I>(
        files: I,
        library_dependencies: &[SourcePackLibraryDependency],
        limits: CodegenUnitLimits,
    ) -> Self
    where
        I: IntoIterator<Item = SourceFileUnitInput>,
    {
        Self::try_from_fallible_file_stream_with_dependencies(
            files.into_iter().map(|file| Ok::<_, ()>(file)),
            library_dependencies,
            limits,
        )
        .unwrap_or_else(|()| unreachable!("infallible source-pack job-plan collection failed"))
    }

    pub fn try_from_fallible_file_stream_with_dependencies<I, E>(
        files: I,
        library_dependencies: &[SourcePackLibraryDependency],
        limits: CodegenUnitLimits,
    ) -> Result<Self, E>
    where
        I: IntoIterator<Item = Result<SourceFileUnitInput, E>>,
    {
        let mut builder = SourcePackJobPlanBuilder::new(limits);
        for file in files {
            builder.push(file?);
        }
        Ok(builder.finish(library_dependencies))
    }

    pub fn requires_multiple_codegen_jobs(&self) -> bool {
        self.codegen_units.unit_count() > 1
    }

    pub fn requires_multiple_frontend_jobs(&self) -> bool {
        self.frontend_units.unit_count() > self.libraries.library_count()
    }

    pub fn job_schedule(&self) -> SourcePackJobSchedule {
        let dependency_index = self.library_dependency_index();
        let library_order = self.topological_library_indices(&dependency_index);
        let mut frontend_job_index_by_library_index = vec![None; self.libraries.libraries.len()];
        for (frontend_job_index, &library_index) in library_order.iter().enumerate() {
            if let Some(slot) = frontend_job_index_by_library_index.get_mut(library_index) {
                *slot = Some(frontend_job_index);
            }
        }
        let mut jobs = Vec::with_capacity(
            self.libraries
                .library_count()
                .saturating_add(self.codegen_units.unit_count())
                .saturating_add(1),
        );

        for &library_index in &library_order {
            let library = &self.libraries.libraries[library_index];
            let dependency_job_indices = self
                .dependency_library_indices_for_library(library.library_id, &dependency_index)
                .iter()
                .filter_map(|&dependency_library_index| {
                    frontend_job_index_by_library_index
                        .get(dependency_library_index)
                        .and_then(|job_index| *job_index)
                })
                .collect::<Vec<_>>();
            jobs.push(SourcePackJob {
                job_index: jobs.len(),
                phase: SourcePackJobPhase::LibraryFrontend,
                phase_unit_index: library.library_index,
                library_job_index: None,
                library_id: library.library_id,
                first_source_index: library.first_source_index,
                source_file_count: library.source_file_count,
                source_bytes: library.source_bytes,
                source_lines: library.source_lines,
                oversized_source_file: false,
                dependency_job_indices,
            });
        }

        let mut library_index_cursor = 0usize;
        for unit in &self.codegen_units.units {
            let unit_range = unit.source_range();
            while self
                .libraries
                .libraries
                .get(library_index_cursor)
                .is_some_and(|library| library.source_range().end <= unit_range.start)
            {
                library_index_cursor += 1;
            }
            let library_index = self
                .libraries
                .libraries
                .get(library_index_cursor)
                .filter(|library| range_contains_range(library.source_range(), unit_range.clone()))
                .map(|library| library.library_index);
            let library_job_index = library_index
                .and_then(|index| frontend_job_index_by_library_index.get(index).copied())
                .flatten();
            let library_id = self
                .libraries
                .libraries
                .get(library_index_cursor)
                .filter(|library| range_contains_range(library.source_range(), unit_range))
                .map(|library| library.library_id)
                .unwrap_or(unit.library_id);
            let mut dependency_job_indices = Vec::new();
            if let Some(library_job_index) = library_job_index {
                push_unique(&mut dependency_job_indices, library_job_index);
            }
            for dependency_library_index in
                self.dependency_library_indices_for_library(library_id, &dependency_index)
            {
                if let Some(dependency_job_index) = frontend_job_index_by_library_index
                    .get(*dependency_library_index)
                    .and_then(|job_index| *job_index)
                {
                    push_unique(&mut dependency_job_indices, dependency_job_index);
                }
            }
            jobs.push(SourcePackJob {
                job_index: jobs.len(),
                phase: SourcePackJobPhase::Codegen,
                phase_unit_index: unit.unit_index,
                library_job_index,
                library_id: unit.library_id,
                first_source_index: unit.first_source_index,
                source_file_count: unit.source_file_count,
                source_bytes: unit.source_bytes,
                source_lines: unit.source_lines,
                oversized_source_file: unit.oversized_source_file,
                dependency_job_indices,
            });
        }

        jobs.push(SourcePackJob {
            job_index: jobs.len(),
            phase: SourcePackJobPhase::Link,
            phase_unit_index: 0,
            library_job_index: None,
            library_id: u32::MAX,
            first_source_index: 0,
            source_file_count: 0,
            source_bytes: 0,
            source_lines: 0,
            oversized_source_file: false,
            dependency_job_indices: Vec::new(),
        });

        SourcePackJobSchedule {
            jobs,
            dependency_job_ranges_by_job_index: Vec::new(),
        }
    }

    pub fn bounded_frontend_job_schedule(&self) -> SourcePackJobSchedule {
        let dependency_index = self.library_dependency_index();
        let library_order = self.topological_library_indices(&dependency_index);
        let mut frontend_job_ranges_by_library_index = vec![None; self.libraries.libraries.len()];
        let mut frontend_job_index_by_unit_index = vec![None; self.frontend_units.unit_count()];
        let mut jobs = Vec::with_capacity(
            self.frontend_units
                .unit_count()
                .saturating_add(self.codegen_units.unit_count())
                .saturating_add(1),
        );
        let mut dependency_job_ranges_by_job_index = Vec::with_capacity(jobs.capacity());

        for &library_index in &library_order {
            let library = &self.libraries.libraries[library_index];
            let dependency_job_ranges = self
                .dependency_library_indices_for_library(library.library_id, &dependency_index)
                .iter()
                .filter_map(|&dependency_library_index| {
                    frontend_job_ranges_by_library_index
                        .get(dependency_library_index)
                        .and_then(|range| range.clone())
                })
                .collect::<Vec<_>>();
            let first_frontend_job_index = jobs.len();
            let frontend_units = self.frontend_units_for_library(library);
            for frontend_unit in frontend_units {
                let job_index = jobs.len();
                jobs.push(SourcePackJob {
                    job_index,
                    phase: SourcePackJobPhase::LibraryFrontend,
                    phase_unit_index: frontend_unit.unit_index,
                    library_job_index: None,
                    library_id: frontend_unit.library_id,
                    first_source_index: frontend_unit.first_source_index,
                    source_file_count: frontend_unit.source_file_count,
                    source_bytes: frontend_unit.source_bytes,
                    source_lines: frontend_unit.source_lines,
                    oversized_source_file: frontend_unit.oversized_source_file,
                    dependency_job_indices: Vec::new(),
                });
                dependency_job_ranges_by_job_index.push(dependency_job_ranges.clone());
                if let Some(slot) =
                    frontend_job_index_by_unit_index.get_mut(frontend_unit.unit_index)
                {
                    *slot = Some(job_index);
                }
            }
            let frontend_job_count = jobs.len().saturating_sub(first_frontend_job_index);
            if frontend_job_count != 0 {
                frontend_job_ranges_by_library_index[library_index] =
                    Some(SourcePackJobIndexRange {
                        first_job_index: first_frontend_job_index,
                        job_count: frontend_job_count,
                    });
            }
        }

        let mut library_index_cursor = 0usize;
        let mut frontend_unit_cursor = 0usize;
        for unit in &self.codegen_units.units {
            let unit_range = unit.source_range();
            while self
                .libraries
                .libraries
                .get(library_index_cursor)
                .is_some_and(|library| library.source_range().end <= unit_range.start)
            {
                library_index_cursor += 1;
            }
            let library_index = self
                .libraries
                .libraries
                .get(library_index_cursor)
                .filter(|library| range_contains_range(library.source_range(), unit_range.clone()))
                .map(|library| library.library_index);
            let frontend_unit = library_index.and_then(|index| {
                self.frontend_unit_for_range_from_cursor(
                    index,
                    &mut frontend_unit_cursor,
                    unit.source_range(),
                )
            });
            let library_job_index = frontend_unit.and_then(|frontend_unit| {
                frontend_job_index_by_unit_index
                    .get(frontend_unit.unit_index)
                    .copied()
                    .flatten()
            });
            let mut dependency_job_indices = Vec::new();
            if let Some(library_job_index) = library_job_index {
                push_unique(&mut dependency_job_indices, library_job_index);
            }
            let mut dependency_job_ranges = Vec::new();
            if let (Some(library_index), Some(library_job_index)) =
                (library_index, library_job_index)
            {
                if let Some(Some(frontend_range)) =
                    frontend_job_ranges_by_library_index.get(library_index)
                {
                    if frontend_range.first_job_index < library_job_index {
                        dependency_job_ranges.push(SourcePackJobIndexRange {
                            first_job_index: frontend_range.first_job_index,
                            job_count: library_job_index - frontend_range.first_job_index,
                        });
                    }
                    let after_library_job_index = library_job_index.saturating_add(1);
                    if let Some(frontend_range_end) = frontend_range.end_job_index() {
                        if after_library_job_index < frontend_range_end {
                            dependency_job_ranges.push(SourcePackJobIndexRange {
                                first_job_index: after_library_job_index,
                                job_count: frontend_range_end - after_library_job_index,
                            });
                        }
                    }
                }
                let library_id = self
                    .libraries
                    .libraries
                    .get(library_index)
                    .map(|library| library.library_id)
                    .unwrap_or(unit.library_id);
                for dependency_library_index in
                    self.dependency_library_indices_for_library(library_id, &dependency_index)
                {
                    if let Some(Some(frontend_range)) =
                        frontend_job_ranges_by_library_index.get(*dependency_library_index)
                    {
                        dependency_job_ranges.push(frontend_range.clone());
                    }
                }
            }
            jobs.push(SourcePackJob {
                job_index: jobs.len(),
                phase: SourcePackJobPhase::Codegen,
                phase_unit_index: unit.unit_index,
                library_job_index,
                library_id: unit.library_id,
                first_source_index: unit.first_source_index,
                source_file_count: unit.source_file_count,
                source_bytes: unit.source_bytes,
                source_lines: unit.source_lines,
                oversized_source_file: unit.oversized_source_file,
                dependency_job_indices,
            });
            dependency_job_ranges_by_job_index.push(dependency_job_ranges);
        }

        jobs.push(SourcePackJob {
            job_index: jobs.len(),
            phase: SourcePackJobPhase::Link,
            phase_unit_index: 0,
            library_job_index: None,
            library_id: u32::MAX,
            first_source_index: 0,
            source_file_count: 0,
            source_bytes: 0,
            source_lines: 0,
            oversized_source_file: false,
            dependency_job_indices: Vec::new(),
        });
        dependency_job_ranges_by_job_index.push(Vec::new());

        SourcePackJobSchedule {
            jobs,
            dependency_job_ranges_by_job_index,
        }
    }

    pub fn compact_build_artifact_manifest(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> SourcePackBuildArtifactManifest {
        self.compact_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn compact_build_artifact_manifest_for_target(
        &self,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> SourcePackBuildArtifactManifest {
        self.try_compact_build_artifact_manifest_for_target(batch_limits, target)
            .expect("source-pack compact build artifact manifest schedule should be acyclic")
    }

    pub fn try_compact_build_artifact_manifest(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        self.try_compact_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn try_compact_build_artifact_manifest_for_target(
        &self,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        let schedule = self.job_schedule();
        self.try_compact_build_artifact_manifest_for_schedule(&schedule, batch_limits, target)
    }

    pub fn try_compact_build_artifact_manifest_for_schedule(
        &self,
        schedule: &SourcePackJobSchedule,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactManifest, SourcePackScheduleError> {
        let job_batches = schedule.try_execution_batch_summary(batch_limits)?;
        let batch_dependencies = schedule.try_execution_batch_dependency_summary(batch_limits)?;
        let artifact_estimate =
            self.build_artifact_estimate_summary_for_schedule(schedule, batch_limits, target);
        Ok(SourcePackBuildArtifactManifest {
            version: SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION,
            target,
            job_count: schedule.jobs.len(),
            job_batch_count: job_batches.batch_count(),
            batch_dependency_count: batch_dependencies.batch_count(),
            artifact_count: artifact_estimate.total_artifacts,
            job_artifact_count: artifact_estimate.job_artifacts.job_count,
            job_artifact_io_count: artifact_estimate.job_artifacts.job_count,
            artifact_use_count: artifact_estimate.artifact_use_count,
            link_interface_batch_count: artifact_estimate.link_interface_batches.batch_count(),
            link_object_batch_count: artifact_estimate.link_object_batches.batch_count(),
            job_schedule: Default::default(),
            job_batches: Default::default(),
            batch_dependencies: Default::default(),
            artifacts: Default::default(),
            job_artifacts: Default::default(),
            job_artifact_io: Default::default(),
            artifact_uses: Default::default(),
            link_interface_batches: Default::default(),
            link_object_batches: Default::default(),
        })
    }

    pub fn build_artifact_estimate_summary(
        &self,
        batch_limits: SourcePackJobBatchLimits,
    ) -> SourcePackBuildArtifactEstimateSummary {
        let schedule = self.job_schedule();
        self.build_artifact_estimate_summary_for_schedule(
            &schedule,
            batch_limits,
            SourcePackArtifactTarget::Generic,
        )
    }

    pub fn build_artifact_estimate_summary_for_schedule(
        &self,
        schedule: &SourcePackJobSchedule,
        batch_limits: SourcePackJobBatchLimits,
        target: SourcePackArtifactTarget,
    ) -> SourcePackBuildArtifactEstimateSummary {
        let mut estimate = SourcePackBuildArtifactEstimateSummary::default();
        let mut artifact_index = 0usize;
        let mut first_interface_artifact_index = None;
        let mut first_object_artifact_index = None;
        let total_source_file_count = self
            .libraries
            .libraries
            .iter()
            .map(|library| library.source_range().end)
            .max()
            .unwrap_or(0);
        let total_source_bytes = self
            .libraries
            .libraries
            .iter()
            .map(|library| library.source_bytes)
            .sum::<usize>();
        let total_source_lines = self
            .libraries
            .libraries
            .iter()
            .map(|library| library.source_lines)
            .sum::<usize>();

        for job in &schedule.jobs {
            let kind = match job.phase {
                SourcePackJobPhase::LibraryFrontend => {
                    first_interface_artifact_index.get_or_insert(artifact_index);
                    estimate.interface_artifacts = estimate.interface_artifacts.saturating_add(1);
                    SourcePackArtifactKind::LibraryInterface
                }
                SourcePackJobPhase::Codegen => {
                    first_object_artifact_index.get_or_insert(artifact_index);
                    estimate.object_artifacts = estimate.object_artifacts.saturating_add(1);
                    SourcePackArtifactKind::CodegenObject
                }
                SourcePackJobPhase::Link => continue,
            };
            let artifact = source_pack_artifact_plan_for_job(artifact_index, job, kind);
            record_source_pack_artifact_manifest_estimate(
                &mut estimate.artifact_manifest,
                &artifact,
                target,
            );
            artifact_index = artifact_index.saturating_add(1);
        }

        let link_job_index = schedule
            .jobs
            .iter()
            .find(|job| job.phase == SourcePackJobPhase::Link)
            .map(|job| job.job_index)
            .unwrap_or(schedule.jobs.len());
        let output_artifact = SourcePackArtifactPlan {
            artifact_index,
            producing_job_index: link_job_index,
            kind: SourcePackArtifactKind::LinkedOutput,
            library_id: u32::MAX,
            first_source_index: 0,
            source_file_count: total_source_file_count,
            source_bytes: total_source_bytes,
            source_lines: total_source_lines,
        };
        record_source_pack_artifact_manifest_estimate(
            &mut estimate.artifact_manifest,
            &output_artifact,
            target,
        );
        estimate.linked_output_artifacts = 1;
        estimate.total_artifacts = estimate.artifact_manifest.artifact_count;
        estimate.artifact_use_count = estimate.total_artifacts;
        estimate.link_interface_inputs = estimate.interface_artifacts;
        estimate.link_object_inputs = estimate.object_artifacts;
        estimate.artifact_lifetimes = SourcePackArtifactLifetimeSummary {
            artifact_count: estimate.total_artifacts,
            artifacts_without_consumers: estimate.total_artifacts.saturating_sub(
                estimate
                    .link_interface_inputs
                    .saturating_add(estimate.link_object_inputs),
            ),
        };

        let job_phase_by_index = source_pack_job_phase_by_job_index(schedule);
        for job in &schedule.jobs {
            let (input_interface_count, input_object_count) = match job.phase {
                SourcePackJobPhase::LibraryFrontend | SourcePackJobPhase::Codegen => {
                    let mut dependency_interface_jobs = Vec::new();
                    for &dependency_job_index in &job.dependency_job_indices {
                        if matches!(
                            job_phase_by_index.get(dependency_job_index),
                            Some(Some(SourcePackJobPhase::LibraryFrontend))
                        ) {
                            push_unique(&mut dependency_interface_jobs, dependency_job_index);
                        }
                    }
                    let ranged_dependency_interface_count = schedule
                        .dependency_job_ranges_for_job(job)
                        .iter()
                        .fold(0usize, |count, range| count.saturating_add(range.job_count));
                    (
                        dependency_interface_jobs
                            .len()
                            .saturating_add(ranged_dependency_interface_count),
                        0,
                    )
                }
                SourcePackJobPhase::Link => {
                    (estimate.interface_artifacts, estimate.object_artifacts)
                }
            };
            let output_artifact_count = match job.phase {
                SourcePackJobPhase::LibraryFrontend | SourcePackJobPhase::Codegen => 1,
                SourcePackJobPhase::Link => usize::from(job.job_index == link_job_index),
            };
            record_source_pack_job_artifact_io_estimate(
                &mut estimate.job_artifacts,
                input_interface_count,
                input_object_count,
                output_artifact_count,
            );
        }
        estimate.job_artifact_manifest = SourcePackJobArtifactManifestSummary {
            job_count: estimate.job_artifacts.job_count,
            max_input_artifact_count: estimate.job_artifacts.max_input_artifact_count,
        };

        let limits = batch_limits.normalized();
        let max_input_artifacts_per_batch = source_pack_link_batch_input_limit(limits);
        let interface_artifact_range = first_interface_artifact_index
            .filter(|_| estimate.interface_artifacts != 0)
            .map(|first| first..first.saturating_add(estimate.interface_artifacts));
        let object_artifact_range = first_object_artifact_index
            .filter(|_| estimate.object_artifacts != 0)
            .map(|first| first..first.saturating_add(estimate.object_artifacts));
        let mut interface_batch_artifact_count = 0usize;
        let mut interface_batch_source_bytes = 0usize;
        let mut interface_batch_source_files = 0usize;
        let mut object_batch_artifact_count = 0usize;
        let mut object_batch_source_bytes = 0usize;
        let mut object_batch_source_files = 0usize;
        let mut artifact_index = 0usize;
        for job in &schedule.jobs {
            let kind = match job.phase {
                SourcePackJobPhase::LibraryFrontend => SourcePackArtifactKind::LibraryInterface,
                SourcePackJobPhase::Codegen => SourcePackArtifactKind::CodegenObject,
                SourcePackJobPhase::Link => continue,
            };
            let artifact = source_pack_artifact_plan_for_job(artifact_index, job, kind);
            if source_pack_artifact_index_in_range(
                &interface_artifact_range,
                artifact.artifact_index,
            ) {
                record_source_pack_link_input_batch_summary(
                    &mut interface_batch_artifact_count,
                    &mut interface_batch_source_bytes,
                    &mut interface_batch_source_files,
                    artifact.source_bytes,
                    artifact.source_file_count,
                    limits,
                    max_input_artifacts_per_batch,
                    |artifact_count, source_bytes, source_file_count| {
                        estimate.link_interface_batches.record_batch_counts(
                            artifact_count,
                            source_bytes,
                            source_file_count,
                        );
                    },
                );
            }
            if source_pack_artifact_index_in_range(&object_artifact_range, artifact.artifact_index)
            {
                record_source_pack_link_input_batch_summary(
                    &mut object_batch_artifact_count,
                    &mut object_batch_source_bytes,
                    &mut object_batch_source_files,
                    artifact.source_bytes,
                    artifact.source_file_count,
                    limits,
                    max_input_artifacts_per_batch,
                    |artifact_count, source_bytes, source_file_count| {
                        estimate.link_object_batches.record_batch_counts(
                            artifact_count,
                            source_bytes,
                            source_file_count,
                        );
                    },
                );
            }
            artifact_index = artifact_index.saturating_add(1);
        }
        finish_source_pack_link_input_batch_summary(
            &mut interface_batch_artifact_count,
            &mut interface_batch_source_bytes,
            &mut interface_batch_source_files,
            |artifact_count, source_bytes, source_file_count| {
                estimate.link_interface_batches.record_batch_counts(
                    artifact_count,
                    source_bytes,
                    source_file_count,
                );
            },
        );
        finish_source_pack_link_input_batch_summary(
            &mut object_batch_artifact_count,
            &mut object_batch_source_bytes,
            &mut object_batch_source_files,
            |artifact_count, source_bytes, source_file_count| {
                estimate.link_object_batches.record_batch_counts(
                    artifact_count,
                    source_bytes,
                    source_file_count,
                );
            },
        );

        estimate
    }

    pub fn build_plan(&self) -> SourcePackBuildPlan {
        self.build_plan_for_schedule(self.job_schedule())
    }

    pub fn bounded_frontend_build_plan(&self) -> SourcePackBuildPlan {
        self.build_plan_for_schedule(self.bounded_frontend_job_schedule())
    }

    fn build_plan_for_schedule(&self, schedule: SourcePackJobSchedule) -> SourcePackBuildPlan {
        let mut artifacts = Vec::with_capacity(schedule.jobs.len());
        let mut first_interface_artifact_index = None;
        let mut interface_artifact_count = 0usize;
        let mut first_object_artifact_index = None;
        let mut object_artifact_count = 0usize;
        let total_source_file_count = self
            .libraries
            .libraries
            .iter()
            .map(|library| library.source_range().end)
            .max()
            .unwrap_or(0);
        let total_source_bytes = self
            .libraries
            .libraries
            .iter()
            .map(|library| library.source_bytes)
            .sum::<usize>();
        let total_source_lines = self
            .libraries
            .libraries
            .iter()
            .map(|library| library.source_lines)
            .sum::<usize>();

        for job in &schedule.jobs {
            match job.phase {
                SourcePackJobPhase::LibraryFrontend => {
                    first_interface_artifact_index.get_or_insert(artifacts.len());
                    interface_artifact_count = interface_artifact_count.saturating_add(1);
                    artifacts.push(SourcePackArtifactPlan {
                        artifact_index: artifacts.len(),
                        producing_job_index: job.job_index,
                        kind: SourcePackArtifactKind::LibraryInterface,
                        library_id: job.library_id,
                        first_source_index: job.first_source_index,
                        source_file_count: job.source_file_count,
                        source_bytes: job.source_bytes,
                        source_lines: job.source_lines,
                    });
                }
                SourcePackJobPhase::Codegen => {
                    first_object_artifact_index.get_or_insert(artifacts.len());
                    object_artifact_count = object_artifact_count.saturating_add(1);
                    artifacts.push(SourcePackArtifactPlan {
                        artifact_index: artifacts.len(),
                        producing_job_index: job.job_index,
                        kind: SourcePackArtifactKind::CodegenObject,
                        library_id: job.library_id,
                        first_source_index: job.first_source_index,
                        source_file_count: job.source_file_count,
                        source_bytes: job.source_bytes,
                        source_lines: job.source_lines,
                    });
                }
                SourcePackJobPhase::Link => {}
            }
        }

        let link_job_index = schedule
            .jobs
            .iter()
            .find(|job| job.phase == SourcePackJobPhase::Link)
            .map(|job| job.job_index)
            .unwrap_or(schedule.jobs.len());
        let output_artifact_index = artifacts.len();
        artifacts.push(SourcePackArtifactPlan {
            artifact_index: output_artifact_index,
            producing_job_index: link_job_index,
            kind: SourcePackArtifactKind::LinkedOutput,
            library_id: u32::MAX,
            first_source_index: 0,
            source_file_count: total_source_file_count,
            source_bytes: total_source_bytes,
            source_lines: total_source_lines,
        });

        SourcePackBuildPlan {
            schedule,
            artifacts,
            link: SourcePackLinkPlan {
                link_job_index,
                input_interface_artifact_count: interface_artifact_count,
                input_interface_artifact_ranges: source_pack_artifact_index_ranges_from_first_count(
                    first_interface_artifact_index,
                    interface_artifact_count,
                ),
                input_interface_artifact_indices: Vec::new(),
                input_object_artifact_count: object_artifact_count,
                input_object_artifact_ranges: source_pack_artifact_index_ranges_from_first_count(
                    first_object_artifact_index,
                    object_artifact_count,
                ),
                input_object_artifact_indices: Vec::new(),
                output_artifact_index,
            },
        }
    }

    fn library_dependency_index(&self) -> SourcePackLibraryDependencyIndex {
        let mut first_library_index_by_id = BTreeMap::new();
        for library in &self.libraries.libraries {
            first_library_index_by_id
                .entry(library.library_id)
                .or_insert(library.library_index);
        }

        let mut dependency_library_indices_by_library_id: BTreeMap<u32, Vec<usize>> =
            BTreeMap::new();
        for dependency in &self.library_dependencies {
            if let Some(&dependency_library_index) =
                first_library_index_by_id.get(&dependency.depends_on_library_id)
            {
                push_unique(
                    dependency_library_indices_by_library_id
                        .entry(dependency.library_id)
                        .or_default(),
                    dependency_library_index,
                );
            }
        }

        let mut dependency_library_indices_by_library_index =
            vec![Vec::new(); self.libraries.libraries.len()];
        for library in &self.libraries.libraries {
            if let Some(dependency_indices) =
                dependency_library_indices_by_library_id.get(&library.library_id)
            {
                if let Some(slot) =
                    dependency_library_indices_by_library_index.get_mut(library.library_index)
                {
                    *slot = dependency_indices.clone();
                }
            }
        }

        SourcePackLibraryDependencyIndex {
            dependency_library_indices_by_library_id,
            dependency_library_indices_by_library_index,
        }
    }

    fn dependency_library_indices_for_library<'a>(
        &self,
        library_id: u32,
        dependency_index: &'a SourcePackLibraryDependencyIndex,
    ) -> &'a [usize] {
        dependency_index
            .dependency_library_indices_by_library_id
            .get(&library_id)
            .map(Vec::as_slice)
            .unwrap_or(&[])
    }

    fn frontend_units_for_library<'a>(
        &'a self,
        library: &'a LibraryUnit,
    ) -> impl Iterator<Item = &'a FrontendUnit> + 'a {
        self.frontend_units.units.iter().filter(move |unit| {
            unit.library_id == library.library_id
                && range_contains_range(library.source_range(), unit.source_range())
        })
    }

    fn frontend_unit_for_range_from_cursor(
        &self,
        library_index: usize,
        frontend_unit_cursor: &mut usize,
        source_range: Range<usize>,
    ) -> Option<&FrontendUnit> {
        let library = self.libraries.libraries.get(library_index)?;
        while self
            .frontend_units
            .units
            .get(*frontend_unit_cursor)
            .is_some_and(|unit| unit.source_range().end <= source_range.start)
        {
            *frontend_unit_cursor += 1;
        }
        self.frontend_units
            .units
            .get(*frontend_unit_cursor)
            .filter(|unit| {
                unit.library_id == library.library_id
                    && range_contains_range(library.source_range(), unit.source_range())
                    && range_contains_range(unit.source_range(), source_range.clone())
            })
    }

    fn topological_library_indices(
        &self,
        dependency_index: &SourcePackLibraryDependencyIndex,
    ) -> Vec<usize> {
        let library_count = self.libraries.libraries.len();
        let mut sorted_indices = Vec::with_capacity(library_count);
        let mut emitted = vec![false; library_count];
        let mut remaining_dependency_counts = vec![0usize; library_count];
        let mut dependents_by_library_index = vec![Vec::new(); library_count];

        for (library_index, dependency_indices) in dependency_index
            .dependency_library_indices_by_library_index
            .iter()
            .enumerate()
        {
            for &dependency_library_index in dependency_indices {
                if dependency_library_index >= library_count {
                    continue;
                }
                remaining_dependency_counts[library_index] =
                    remaining_dependency_counts[library_index].saturating_add(1);
                push_unique(
                    &mut dependents_by_library_index[dependency_library_index],
                    library_index,
                );
            }
        }

        let mut ready_indices = remaining_dependency_counts
            .iter()
            .enumerate()
            .filter_map(|(library_index, &count)| (count == 0).then_some(library_index))
            .collect::<BTreeSet<_>>();

        while let Some(library_index) = ready_indices.iter().next().copied() {
            ready_indices.remove(&library_index);
            if emitted[library_index] {
                continue;
            }
            emitted[library_index] = true;
            sorted_indices.push(library_index);

            for &dependent_library_index in &dependents_by_library_index[library_index] {
                let Some(remaining_dependencies) =
                    remaining_dependency_counts.get_mut(dependent_library_index)
                else {
                    continue;
                };
                if *remaining_dependencies == 0 {
                    continue;
                }
                *remaining_dependencies -= 1;
                if *remaining_dependencies == 0 && !emitted[dependent_library_index] {
                    ready_indices.insert(dependent_library_index);
                }
            }
        }

        if sorted_indices.len() < library_count {
            for library_index in 0..library_count {
                if !emitted[library_index] {
                    sorted_indices.push(library_index);
                }
            }
        }

        sorted_indices
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct SourcePackLibraryDependencyIndex {
    dependency_library_indices_by_library_id: BTreeMap<u32, Vec<usize>>,
    dependency_library_indices_by_library_index: Vec<Vec<usize>>,
}

#[derive(Clone, Debug)]
pub struct SourcePackJobPlanBuilder {
    limits: CodegenUnitLimits,
    library_builder: LibraryBuilder,
    frontend_builder: UnitBuilder,
    unit_builder: UnitBuilder,
    libraries: Vec<LibraryUnit>,
    frontend_units: Vec<FrontendUnit>,
    codegen_units: Vec<CodegenUnit>,
}

impl SourcePackJobPlanBuilder {
    pub fn new(limits: CodegenUnitLimits) -> Self {
        Self {
            limits: limits.normalized(),
            library_builder: LibraryBuilder::default(),
            frontend_builder: UnitBuilder::default(),
            unit_builder: UnitBuilder::default(),
            libraries: Vec::new(),
            frontend_units: Vec::new(),
            codegen_units: Vec::new(),
        }
    }

    pub fn push(&mut self, file: SourceFileUnitInput) {
        self.push_library_file(file);
        self.push_frontend_file(file);
        self.push_codegen_file(file);
    }

    fn push_library_file(&mut self, file: SourceFileUnitInput) {
        if self.library_builder.should_flush_before(file) {
            self.flush_library();
        }
        self.library_builder.push(file);
    }

    fn push_frontend_file(&mut self, file: SourceFileUnitInput) {
        if file.byte_len > self.limits.max_source_bytes {
            self.flush_frontend_unit();
            self.frontend_units.push(FrontendUnit {
                unit_index: self.frontend_units.len(),
                library_id: file.library_id,
                first_source_index: file.source_index,
                source_file_count: 1,
                source_bytes: file.byte_len,
                source_lines: file.line_count,
                oversized_source_file: true,
            });
            return;
        }

        if self.frontend_builder.should_flush_before(file, self.limits) {
            self.flush_frontend_unit();
        }
        self.frontend_builder.push(file);
    }

    fn push_codegen_file(&mut self, file: SourceFileUnitInput) {
        if file.byte_len > self.limits.max_source_bytes {
            self.flush_codegen_unit();
            self.codegen_units.push(CodegenUnit {
                unit_index: self.codegen_units.len(),
                library_id: file.library_id,
                first_source_index: file.source_index,
                source_file_count: 1,
                source_bytes: file.byte_len,
                source_lines: file.line_count,
                oversized_source_file: true,
            });
            return;
        }

        if self.unit_builder.should_flush_before(file, self.limits) {
            self.flush_codegen_unit();
        }
        self.unit_builder.push(file);
    }

    fn flush_library(&mut self) {
        if let Some(library) = self.library_builder.take(self.libraries.len()) {
            self.libraries.push(library);
        }
    }

    fn flush_frontend_unit(&mut self) {
        if let Some(unit) = self
            .frontend_builder
            .take_frontend(self.frontend_units.len(), false)
        {
            self.frontend_units.push(unit);
        }
    }

    fn flush_codegen_unit(&mut self) {
        if let Some(unit) = self.unit_builder.take(self.codegen_units.len(), false) {
            self.codegen_units.push(unit);
        }
    }

    pub fn finish(
        mut self,
        library_dependencies: &[SourcePackLibraryDependency],
    ) -> SourcePackJobPlan {
        self.flush_library();
        self.flush_frontend_unit();
        self.flush_codegen_unit();
        SourcePackJobPlan {
            libraries: LibraryUnitPlan {
                libraries: self.libraries,
            },
            frontend_units: FrontendUnitPlan {
                units: self.frontend_units,
            },
            codegen_units: CodegenUnitPlan {
                units: self.codegen_units,
            },
            library_dependencies: library_dependencies.to_vec(),
        }
    }
}

fn range_contains_range(outer: Range<usize>, inner: Range<usize>) -> bool {
    outer.start <= inner.start && inner.end <= outer.end
}

fn source_pack_artifact_index_count(
    recorded_count: usize,
    explicit_indices: &[usize],
    ranges: &[SourcePackArtifactIndexRange],
) -> usize {
    recorded_count.max(
        explicit_indices
            .len()
            .saturating_add(source_pack_artifact_index_range_count(ranges)),
    )
}

fn source_pack_artifact_index_range_count(ranges: &[SourcePackArtifactIndexRange]) -> usize {
    ranges.iter().fold(0usize, |count, range| {
        count.saturating_add(range.artifact_count)
    })
}

fn source_pack_artifact_index_covered_by_ranges(
    artifact_index: usize,
    ranges: &[SourcePackArtifactIndexRange],
) -> bool {
    ranges.iter().any(|range| range.contains(artifact_index))
}

fn source_pack_compact_artifact_index_ranges(
    ranges: Vec<SourcePackArtifactIndexRange>,
) -> Vec<SourcePackArtifactIndexRange> {
    let mut ranges = ranges
        .into_iter()
        .filter(|range| range.artifact_count != 0)
        .collect::<Vec<_>>();
    ranges.sort_by_key(|range| range.first_artifact_index);
    let mut compact_ranges = Vec::<SourcePackArtifactIndexRange>::with_capacity(ranges.len());
    for range in ranges {
        let Some(range_end) = range.end_artifact_index() else {
            compact_ranges.push(range);
            continue;
        };
        if let Some(last) = compact_ranges.last_mut() {
            if let Some(last_end) = last.end_artifact_index() {
                if range.first_artifact_index <= last_end {
                    let compact_end = last_end.max(range_end);
                    last.artifact_count = compact_end - last.first_artifact_index;
                    continue;
                }
            }
        }
        compact_ranges.push(range);
    }
    compact_ranges
}

fn source_pack_job_index_range_dependency_count(ranges: &[SourcePackJobIndexRange]) -> usize {
    ranges
        .iter()
        .fold(0usize, |count, range| count.saturating_add(range.job_count))
}

fn source_pack_job_index_range_covered_by_ranges(
    dependency_range: &SourcePackJobIndexRange,
    completed_ranges: &[SourcePackJobIndexRange],
) -> bool {
    if dependency_range.is_empty() {
        return true;
    }

    let Some(required_end) = dependency_range.end_job_index() else {
        return false;
    };
    let mut covered_until = dependency_range.first_job_index;
    while covered_until < required_end {
        let mut next_covered_until = covered_until;
        for completed_range in completed_ranges {
            let Some(completed_end) = completed_range.end_job_index() else {
                continue;
            };
            if completed_range.first_job_index <= covered_until && covered_until < completed_end {
                next_covered_until = next_covered_until.max(completed_end.min(required_end));
            }
        }
        if next_covered_until == covered_until {
            return false;
        }
        covered_until = next_covered_until;
    }

    true
}

fn source_pack_push_completed_job_index_as_range(
    completed_ranges: &mut Vec<SourcePackJobIndexRange>,
    job_index: usize,
) {
    if let Some(last) = completed_ranges.last_mut() {
        if last.end_job_index() == Some(job_index) {
            last.job_count = last.job_count.saturating_add(1);
            return;
        }
    }
    completed_ranges.push(SourcePackJobIndexRange {
        first_job_index: job_index,
        job_count: 1,
    });
}

fn source_pack_job_ready_from_completed_ranges(
    job: &SourcePackJob,
    dependency_job_ranges: &[SourcePackJobIndexRange],
    job_position_by_index: &[Option<usize>],
    emitted_by_position: &[bool],
    completed_job_ranges: &[SourcePackJobIndexRange],
    emitted_codegen_count: usize,
    codegen_job_count: usize,
) -> bool {
    let has_explicit_dependencies = !job.dependency_job_indices.is_empty();
    let has_ranged_dependencies = !dependency_job_ranges.is_empty();
    if job.phase == SourcePackJobPhase::Link
        && !has_explicit_dependencies
        && !has_ranged_dependencies
    {
        return emitted_codegen_count == codegen_job_count;
    }

    job.dependency_job_indices
        .iter()
        .all(|&dependency_job_index| {
            job_position_by_index
                .get(dependency_job_index)
                .and_then(|position| *position)
                .and_then(|position| emitted_by_position.get(position).copied())
                .unwrap_or(false)
        })
        && dependency_job_ranges
            .iter()
            .all(|range| source_pack_job_index_range_covered_by_ranges(range, completed_job_ranges))
}

fn source_pack_artifact_index_ranges_from_first_count(
    first_artifact_index: Option<usize>,
    artifact_count: usize,
) -> Vec<SourcePackArtifactIndexRange> {
    match (first_artifact_index, artifact_count) {
        (Some(first_artifact_index), artifact_count) if artifact_count != 0 => {
            vec![SourcePackArtifactIndexRange {
                first_artifact_index,
                artifact_count,
            }]
        }
        _ => Vec::new(),
    }
}

fn source_pack_try_for_each_artifact_index<F, E>(
    explicit_indices: &[usize],
    ranges: &[SourcePackArtifactIndexRange],
    mut visit: F,
) -> Result<usize, E>
where
    F: FnMut(usize) -> Result<(), E>,
{
    let mut count = 0usize;
    for &artifact_index in explicit_indices {
        visit(artifact_index)?;
        count = count.saturating_add(1);
    }
    for range in ranges {
        if let Some(indices) = range.iter() {
            for artifact_index in indices {
                visit(artifact_index)?;
                count = count.saturating_add(1);
            }
        }
    }
    Ok(count)
}

fn push_unique(values: &mut Vec<usize>, value: usize) {
    if !values.contains(&value) {
        values.push(value);
    }
}

fn source_pack_push_dependency_batch_indices_as_ranges<I>(
    dependency_batch_ranges: &mut Vec<SourcePackJobBatchDependencyRange>,
    dependency_batch_indices: I,
) where
    I: IntoIterator<Item = usize>,
{
    for dependency_batch_index in dependency_batch_indices {
        if let Some(last) = dependency_batch_ranges.last_mut() {
            if last.end_batch_index() == Some(dependency_batch_index) {
                last.batch_count = last.batch_count.saturating_add(1);
                continue;
            }
        }
        dependency_batch_ranges.push(SourcePackJobBatchDependencyRange {
            first_batch_index: dependency_batch_index,
            batch_count: 1,
        });
    }
}

fn source_pack_push_dependency_batch_ranges_excluding_batch(
    dependency_batch_ranges: &mut Vec<SourcePackJobBatchDependencyRange>,
    ranges: &[SourcePackJobBatchDependencyRange],
    excluded_batch_index: usize,
) {
    for range in ranges {
        let Some(range_end) = range.end_batch_index() else {
            continue;
        };
        if !range.contains(excluded_batch_index) {
            dependency_batch_ranges.push(range.clone());
            continue;
        }
        if range.first_batch_index < excluded_batch_index {
            dependency_batch_ranges.push(SourcePackJobBatchDependencyRange {
                first_batch_index: range.first_batch_index,
                batch_count: excluded_batch_index - range.first_batch_index,
            });
        }
        let after_excluded = excluded_batch_index.saturating_add(1);
        if after_excluded < range_end {
            dependency_batch_ranges.push(SourcePackJobBatchDependencyRange {
                first_batch_index: after_excluded,
                batch_count: range_end - after_excluded,
            });
        }
    }
}

fn source_pack_push_dependency_batch_range_excluding_batches(
    dependency_batch_ranges: &mut Vec<SourcePackJobBatchDependencyRange>,
    first_batch_index: usize,
    batch_count: usize,
    excluded_batch_indices: &BTreeSet<usize>,
) {
    if batch_count == 0 {
        return;
    }
    let Some(end_batch_index) = first_batch_index.checked_add(batch_count) else {
        return;
    };
    let mut range_start = first_batch_index;
    for &excluded_batch_index in excluded_batch_indices.range(first_batch_index..end_batch_index) {
        if range_start < excluded_batch_index {
            dependency_batch_ranges.push(SourcePackJobBatchDependencyRange {
                first_batch_index: range_start,
                batch_count: excluded_batch_index - range_start,
            });
        }
        range_start = excluded_batch_index.saturating_add(1);
    }
    if range_start < end_batch_index {
        dependency_batch_ranges.push(SourcePackJobBatchDependencyRange {
            first_batch_index: range_start,
            batch_count: end_batch_index - range_start,
        });
    }
}

fn source_pack_push_dependency_batch_range_for_job_range(
    dependency_batch_ranges: &mut Vec<SourcePackJobBatchDependencyRange>,
    dependency_batch_indices: &BTreeSet<usize>,
    batch_index_by_job_index: &[Option<usize>],
    dependency_job_range: &SourcePackJobIndexRange,
    current_batch_index: usize,
) -> Result<(), SourcePackScheduleError> {
    if dependency_job_range.job_count == 0 {
        return Ok(());
    }
    let Some(end_job_index) = dependency_job_range.end_job_index() else {
        return Err(SourcePackScheduleError {
            unscheduled_job_indices: vec![dependency_job_range.first_job_index],
        });
    };
    let first_dependency_batch_index = batch_index_by_job_index
        .get(dependency_job_range.first_job_index)
        .and_then(|batch_index| *batch_index)
        .ok_or_else(|| SourcePackScheduleError {
            unscheduled_job_indices: vec![dependency_job_range.first_job_index],
        })?;
    let last_dependency_job_index = end_job_index - 1;
    let last_dependency_batch_index = batch_index_by_job_index
        .get(last_dependency_job_index)
        .and_then(|batch_index| *batch_index)
        .ok_or_else(|| SourcePackScheduleError {
            unscheduled_job_indices: vec![last_dependency_job_index],
        })?;
    let first_batch_index = first_dependency_batch_index.min(last_dependency_batch_index);
    let last_batch_index = first_dependency_batch_index.max(last_dependency_batch_index);
    let batch_count = last_batch_index
        .checked_sub(first_batch_index)
        .and_then(|count| count.checked_add(1))
        .ok_or_else(|| SourcePackScheduleError {
            unscheduled_job_indices: vec![dependency_job_range.first_job_index],
        })?;
    let mut excluded_batch_indices = dependency_batch_indices.clone();
    excluded_batch_indices.insert(current_batch_index);
    source_pack_push_dependency_batch_range_excluding_batches(
        dependency_batch_ranges,
        first_batch_index,
        batch_count,
        &excluded_batch_indices,
    );
    Ok(())
}

fn source_pack_job_batch_index_covered_by_ranges(
    batch_index: usize,
    ranges: &[SourcePackJobBatchDependencyRange],
) -> bool {
    ranges.iter().any(|range| range.contains(batch_index))
}

fn source_pack_job_batch_range_covered_by_ranges(
    dependency_range: &SourcePackJobBatchDependencyRange,
    completed_ranges: &[SourcePackJobBatchDependencyRange],
) -> bool {
    if dependency_range.is_empty() {
        return true;
    }

    let Some(required_end) = dependency_range.end_batch_index() else {
        return false;
    };
    let mut covered_until = dependency_range.first_batch_index;
    while covered_until < required_end {
        let mut next_covered_until = covered_until;
        for completed_range in completed_ranges {
            let Some(completed_end) = completed_range.end_batch_index() else {
                continue;
            };
            if completed_range.first_batch_index <= covered_until && covered_until < completed_end {
                next_covered_until = next_covered_until.max(completed_end.min(required_end));
            }
        }
        if next_covered_until == covered_until {
            return false;
        }
        covered_until = next_covered_until;
    }

    true
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct CodegenUnitPlan {
    pub units: Vec<CodegenUnit>,
}

impl CodegenUnitPlan {
    pub fn from_source_pack<S: AsRef<str>>(sources: &[S], limits: CodegenUnitLimits) -> Self {
        let mut units = Vec::new();
        Self::try_for_each_from_files(
            sources.iter().enumerate().map(|(source_index, source)| {
                SourceFileUnitInput::from_source(0, source_index, source.as_ref())
            }),
            limits,
            |unit| {
                units.push(unit);
                Ok::<(), ()>(())
            },
        )
        .unwrap_or_else(|()| unreachable!("infallible codegen-unit collection failed"));
        Self { units }
    }

    pub fn from_source_pack_with_libraries<S, L>(
        sources: &[S],
        library_ids: &[L],
        limits: CodegenUnitLimits,
    ) -> Self
    where
        S: AsRef<str>,
        L: Copy + Into<u32>,
    {
        assert_eq!(
            sources.len(),
            library_ids.len(),
            "source and library slices must have the same length"
        );
        let mut units = Vec::new();
        Self::try_for_each_from_files(
            sources
                .iter()
                .zip(library_ids.iter().copied())
                .enumerate()
                .map(|(source_index, (source, library_id))| {
                    SourceFileUnitInput::from_source(
                        library_id.into(),
                        source_index,
                        source.as_ref(),
                    )
                }),
            limits,
            |unit| {
                units.push(unit);
                Ok::<(), ()>(())
            },
        )
        .unwrap_or_else(|()| unreachable!("infallible codegen-unit collection failed"));
        Self { units }
    }

    pub fn from_files(files: &[SourceFileUnitInput], limits: CodegenUnitLimits) -> Self {
        let mut units = Vec::new();
        Self::try_for_each_from_files(files.iter().copied(), limits, |unit| {
            units.push(unit);
            Ok::<(), ()>(())
        })
        .unwrap_or_else(|()| unreachable!("infallible codegen-unit collection failed"));
        Self { units }
    }

    pub fn try_for_each_from_files<I, F, E>(
        files: I,
        limits: CodegenUnitLimits,
        visit: F,
    ) -> Result<usize, E>
    where
        I: IntoIterator<Item = SourceFileUnitInput>,
        F: FnMut(CodegenUnit) -> Result<(), E>,
    {
        Self::try_for_each_from_fallible_files(files.into_iter().map(Ok), limits, visit)
    }

    pub fn try_for_each_from_fallible_files<I, F, E>(
        files: I,
        limits: CodegenUnitLimits,
        mut visit: F,
    ) -> Result<usize, E>
    where
        I: IntoIterator<Item = Result<SourceFileUnitInput, E>>,
        F: FnMut(CodegenUnit) -> Result<(), E>,
    {
        let limits = limits.normalized();
        let mut current = UnitBuilder::default();
        let mut unit_count = 0usize;

        for file in files {
            let file = file?;
            let oversized = file.byte_len > limits.max_source_bytes;
            if oversized {
                if let Some(unit) = current.take(unit_count, false) {
                    unit_count += 1;
                    visit(unit)?;
                }
                visit(CodegenUnit {
                    unit_index: unit_count,
                    library_id: file.library_id,
                    first_source_index: file.source_index,
                    source_file_count: 1,
                    source_bytes: file.byte_len,
                    source_lines: file.line_count,
                    oversized_source_file: true,
                })?;
                unit_count += 1;
                continue;
            }

            if current.should_flush_before(file, limits) {
                if let Some(unit) = current.take(unit_count, false) {
                    unit_count += 1;
                    visit(unit)?;
                }
            }
            current.push(file);
        }

        if let Some(unit) = current.take(unit_count, false) {
            unit_count += 1;
            visit(unit)?;
        }
        Ok(unit_count)
    }

    pub fn unit_count(&self) -> usize {
        self.units.len()
    }

    pub fn oversized_unit_count(&self) -> usize {
        self.units
            .iter()
            .filter(|unit| unit.oversized_source_file)
            .count()
    }

    pub fn max_unit_source_bytes(&self) -> usize {
        self.units
            .iter()
            .map(|unit| unit.source_bytes)
            .max()
            .unwrap_or(0)
    }

    pub fn max_unit_source_files(&self) -> usize {
        self.units
            .iter()
            .map(|unit| unit.source_file_count)
            .max()
            .unwrap_or(0)
    }
}

#[derive(Clone, Copy, Debug, Default)]
struct UnitBuilder {
    library_id: u32,
    first_source_index: usize,
    source_file_count: usize,
    source_bytes: usize,
    source_lines: usize,
}

#[derive(Clone, Copy, Debug, Default)]
struct LibraryBuilder {
    library_id: u32,
    first_source_index: usize,
    source_file_count: usize,
    source_bytes: usize,
    source_lines: usize,
}

impl LibraryBuilder {
    fn is_empty(self) -> bool {
        self.source_file_count == 0
    }

    fn should_flush_before(self, file: SourceFileUnitInput) -> bool {
        !self.is_empty() && self.library_id != file.library_id
    }

    fn push(&mut self, file: SourceFileUnitInput) {
        if self.is_empty() {
            self.library_id = file.library_id;
            self.first_source_index = file.source_index;
        }
        self.source_file_count += 1;
        self.source_bytes = self.source_bytes.saturating_add(file.byte_len);
        self.source_lines = self.source_lines.saturating_add(file.line_count);
    }

    fn take(&mut self, library_index: usize) -> Option<LibraryUnit> {
        if self.is_empty() {
            return None;
        }
        let library = LibraryUnit {
            library_index,
            library_id: self.library_id,
            first_source_index: self.first_source_index,
            source_file_count: self.source_file_count,
            source_bytes: self.source_bytes,
            source_lines: self.source_lines,
        };
        *self = Self::default();
        Some(library)
    }
}

impl UnitBuilder {
    fn is_empty(self) -> bool {
        self.source_file_count == 0
    }

    fn should_flush_before(self, file: SourceFileUnitInput, limits: CodegenUnitLimits) -> bool {
        if self.is_empty() {
            return false;
        }
        self.library_id != file.library_id
            || self.source_file_count >= limits.max_source_files
            || self.source_bytes.saturating_add(file.byte_len) > limits.max_source_bytes
    }

    fn push(&mut self, file: SourceFileUnitInput) {
        if self.is_empty() {
            self.library_id = file.library_id;
            self.first_source_index = file.source_index;
        }
        self.source_file_count += 1;
        self.source_bytes = self.source_bytes.saturating_add(file.byte_len);
        self.source_lines = self.source_lines.saturating_add(file.line_count);
    }

    fn take(&mut self, unit_index: usize, oversized_source_file: bool) -> Option<CodegenUnit> {
        if self.is_empty() {
            return None;
        }
        let unit = CodegenUnit {
            unit_index,
            library_id: self.library_id,
            first_source_index: self.first_source_index,
            source_file_count: self.source_file_count,
            source_bytes: self.source_bytes,
            source_lines: self.source_lines,
            oversized_source_file,
        };
        *self = Self::default();
        Some(unit)
    }

    fn take_frontend(
        &mut self,
        unit_index: usize,
        oversized_source_file: bool,
    ) -> Option<FrontendUnit> {
        if self.is_empty() {
            return None;
        }
        let unit = FrontendUnit {
            unit_index,
            library_id: self.library_id,
            first_source_index: self.first_source_index,
            source_file_count: self.source_file_count,
            source_bytes: self.source_bytes,
            source_lines: self.source_lines,
            oversized_source_file,
        };
        *self = Self::default();
        Some(unit)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn limits(max_source_bytes: usize, max_source_files: usize) -> CodegenUnitLimits {
        CodegenUnitLimits {
            max_source_bytes,
            max_source_files,
        }
    }

    fn test_job(job_index: usize, dependency_job_indices: Vec<usize>) -> SourcePackJob {
        SourcePackJob {
            job_index,
            phase: SourcePackJobPhase::Codegen,
            phase_unit_index: job_index,
            library_job_index: None,
            library_id: 0,
            first_source_index: job_index,
            source_file_count: 1,
            source_bytes: 1,
            source_lines: 0,
            oversized_source_file: false,
            dependency_job_indices,
        }
    }

    #[test]
    fn source_pack_job_batch_limits_default_is_bounded_by_codegen_unit_defaults() {
        let default_limits = SourcePackJobBatchLimits::default();
        let expected_limits =
            SourcePackJobBatchLimits::from_codegen_unit_limits(CodegenUnitLimits::default());

        assert_eq!(default_limits, expected_limits);
        assert!(default_limits.max_jobs_per_batch < usize::MAX);
        assert!(default_limits.max_source_bytes_per_batch < usize::MAX);
        assert!(default_limits.max_source_files_per_batch < usize::MAX);
    }

    #[test]
    fn source_pack_job_batch_limits_normalize_to_record_caps() {
        let normalized = SourcePackJobBatchLimits {
            max_jobs_per_batch: usize::MAX,
            max_source_bytes_per_batch: usize::MAX,
            max_source_files_per_batch: usize::MAX,
        }
        .normalized();

        assert_eq!(normalized, SourcePackJobBatchLimits::default());
    }

    #[test]
    fn source_pack_execution_batches_cap_jobs_even_with_unbounded_caller_limits() {
        let schedule = SourcePackJobSchedule {
            jobs: (0..DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES + 1)
                .map(|job_index| test_job(job_index, Vec::new()))
                .collect(),
            dependency_job_ranges_by_job_index: Vec::new(),
        };

        let batches = schedule
            .try_execution_batches(SourcePackJobBatchLimits {
                max_jobs_per_batch: usize::MAX,
                max_source_bytes_per_batch: usize::MAX,
                max_source_files_per_batch: usize::MAX,
            })
            .expect("batch schedule");

        assert_eq!(batches.batch_count(), 2);
        assert_eq!(
            batches.max_batch_job_count(),
            DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES
        );
        assert_eq!(
            batches.batches[1].job_indices,
            vec![DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES]
        );
    }

    #[test]
    fn source_pack_build_shard_limits_normalize_to_record_caps() {
        let normalized = SourcePackBuildShardLimits {
            max_batches_per_shard: usize::MAX,
            max_jobs_per_shard: usize::MAX,
            max_artifacts_per_shard: usize::MAX,
        }
        .normalized();

        assert_eq!(normalized, SourcePackBuildShardLimits::default());
    }

    #[test]
    fn source_pack_units_group_adjacent_files_within_budget() {
        let sources = ["fn a() {}\n", "fn b() {}\n", "fn c() {}\n"];
        let plan = CodegenUnitPlan::from_source_pack(&sources, limits(64, 8));

        assert_eq!(plan.unit_count(), 1);
        assert_eq!(plan.units[0].first_source_index, 0);
        assert_eq!(plan.units[0].source_file_count, 3);
        assert_eq!(plan.units[0].source_range(), 0..3);
        assert_eq!(plan.oversized_unit_count(), 0);
    }

    #[test]
    fn source_pack_units_split_on_byte_budget_without_splitting_files() {
        let sources = ["aaaaaaaaaa", "bbbbbbbbbb", "cccccccccc"];
        let plan = CodegenUnitPlan::from_source_pack(&sources, limits(20, 8));

        assert_eq!(
            plan.units
                .iter()
                .map(|unit| (unit.first_source_index, unit.source_file_count))
                .collect::<Vec<_>>(),
            vec![(0, 2), (2, 1)]
        );
        assert_eq!(plan.max_unit_source_bytes(), 20);
    }

    #[test]
    fn source_pack_units_split_on_library_boundary() {
        let sources = ["a", "b", "c", "d"];
        let libraries = [0u32, 0, 1, 1];
        let plan =
            CodegenUnitPlan::from_source_pack_with_libraries(&sources, &libraries, limits(64, 8));

        assert_eq!(
            plan.units
                .iter()
                .map(|unit| (
                    unit.library_id,
                    unit.first_source_index,
                    unit.source_file_count
                ))
                .collect::<Vec<_>>(),
            vec![(0, 0, 2), (1, 2, 2)]
        );
    }

    #[test]
    fn frontend_units_split_large_library_without_splitting_files() {
        let sources = ["aaaa", "bbbb", "cccc"];
        let libraries = [5u32, 5, 5];
        let plan =
            FrontendUnitPlan::from_source_pack_with_libraries(&sources, &libraries, limits(4, 8));

        assert_eq!(plan.unit_count(), 3);
        assert_eq!(plan.max_unit_source_files(), 1);
        assert_eq!(plan.max_unit_source_bytes(), 4);
        assert_eq!(
            plan.units
                .iter()
                .map(|unit| (
                    unit.unit_index,
                    unit.library_id,
                    unit.source_range(),
                    unit.oversized_source_file
                ))
                .collect::<Vec<_>>(),
            vec![
                (0, 5, 0..1, false),
                (1, 5, 1..2, false),
                (2, 5, 2..3, false)
            ]
        );
    }

    #[test]
    fn codegen_units_stream_from_fallible_files_without_collecting_inputs() {
        let files = [
            SourceFileUnitInput {
                library_id: 0,
                source_index: 0,
                byte_len: 4,
                line_count: 1,
            },
            SourceFileUnitInput {
                library_id: 0,
                source_index: 1,
                byte_len: 4,
                line_count: 2,
            },
            SourceFileUnitInput {
                library_id: 1,
                source_index: 2,
                byte_len: 9,
                line_count: 3,
            },
        ];
        let mut streamed = Vec::new();

        let count = CodegenUnitPlan::try_for_each_from_fallible_files(
            files.into_iter().map(Ok::<_, ()>),
            limits(8, 8),
            |unit| {
                streamed.push((
                    unit.unit_index,
                    unit.library_id,
                    unit.source_range(),
                    unit.source_bytes,
                    unit.source_lines,
                    unit.oversized_source_file,
                ));
                Ok(())
            },
        )
        .expect("stream codegen units");

        assert_eq!(count, 2);
        assert_eq!(
            streamed,
            vec![(0, 0, 0..2, 8, 3, false), (1, 1, 2..3, 9, 3, true),]
        );
    }

    #[test]
    fn library_units_group_contiguous_files_by_library() {
        let sources = ["a", "b", "c", "d", "e"];
        let libraries = [0u32, 0, 1, 1, 0];
        let plan = LibraryUnitPlan::from_source_pack_with_libraries(&sources, &libraries);

        assert_eq!(plan.library_count(), 3);
        assert_eq!(
            plan.libraries
                .iter()
                .map(|library| (
                    library.library_id,
                    library.source_range(),
                    library.source_file_count
                ))
                .collect::<Vec<_>>(),
            vec![(0, 0..2, 2), (1, 2..4, 2), (0, 4..5, 1)]
        );
        assert_eq!(plan.max_library_source_files(), 2);
    }

    #[test]
    fn library_units_stream_from_fallible_files_without_collecting_inputs() {
        let files = [
            SourceFileUnitInput {
                library_id: 2,
                source_index: 0,
                byte_len: 3,
                line_count: 1,
            },
            SourceFileUnitInput {
                library_id: 2,
                source_index: 1,
                byte_len: 5,
                line_count: 2,
            },
            SourceFileUnitInput {
                library_id: 7,
                source_index: 2,
                byte_len: 11,
                line_count: 3,
            },
        ];
        let mut streamed = Vec::new();

        let count = LibraryUnitPlan::try_for_each_from_fallible_files(
            files.into_iter().map(Ok::<_, ()>),
            |library| {
                streamed.push((
                    library.library_index,
                    library.library_id,
                    library.source_range(),
                    library.source_bytes,
                    library.source_lines,
                ));
                Ok(())
            },
        )
        .expect("stream library units");

        assert_eq!(count, 2);
        assert_eq!(streamed, vec![(0, 2, 0..2, 8, 3), (1, 7, 2..3, 11, 3)]);
    }

    #[test]
    fn source_pack_job_plan_tracks_libraries_and_bounded_codegen_units() {
        let sources = ["aaaa", "bbbb", "cccc", "dddd"];
        let libraries = [0u32, 0, 1, 1];
        let plan =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(8, 8));

        assert_eq!(plan.libraries.library_count(), 2);
        assert_eq!(plan.frontend_units.unit_count(), 2);
        assert_eq!(plan.codegen_units.unit_count(), 2);
        assert!(plan.requires_multiple_codegen_jobs());
        assert_eq!(plan.codegen_units.units[0].source_range(), 0..2);
        assert_eq!(plan.codegen_units.units[1].source_range(), 2..4);
        let schedule = plan.job_schedule();
        assert_eq!(schedule.frontend_job_count(), 2);
        assert_eq!(schedule.codegen_job_count(), 2);
        assert_eq!(schedule.link_job_count(), 1);
        assert_eq!(
            schedule
                .jobs
                .iter()
                .map(|job| (
                    job.phase,
                    job.library_id,
                    job.library_job_index,
                    job.source_range()
                ))
                .collect::<Vec<_>>(),
            vec![
                (SourcePackJobPhase::LibraryFrontend, 0, None, 0..2),
                (SourcePackJobPhase::LibraryFrontend, 1, None, 2..4),
                (SourcePackJobPhase::Codegen, 0, Some(0), 0..2),
                (SourcePackJobPhase::Codegen, 1, Some(1), 2..4),
                (SourcePackJobPhase::Link, u32::MAX, None, 0..0),
            ]
        );
    }

    #[test]
    fn source_pack_job_plan_exposes_bounded_frontend_schedule() {
        let sources = ["aaaa", "bbbb", "cccc"];
        let libraries = [5u32, 5, 5];
        let plan =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(4, 8));
        let schedule = plan.bounded_frontend_job_schedule();

        assert!(plan.requires_multiple_frontend_jobs());
        assert_eq!(schedule.frontend_job_count(), 3);
        assert_eq!(schedule.codegen_job_count(), 3);
        assert_eq!(schedule.link_job_count(), 1);
        assert_eq!(
            schedule
                .jobs
                .iter()
                .filter(|job| job.phase == SourcePackJobPhase::LibraryFrontend)
                .map(|job| (
                    job.phase_unit_index,
                    job.library_id,
                    job.source_range(),
                    job.source_file_count,
                    job.source_bytes
                ))
                .collect::<Vec<_>>(),
            vec![(0, 5, 0..1, 1, 4), (1, 5, 1..2, 1, 4), (2, 5, 2..3, 1, 4),]
        );
        assert_eq!(
            schedule
                .jobs
                .iter()
                .filter(|job| job.phase == SourcePackJobPhase::Codegen)
                .map(|job| (
                    job.phase_unit_index,
                    job.library_job_index,
                    job.dependency_job_indices.clone(),
                    schedule.dependency_job_ranges_for_job(job).to_vec()
                ))
                .collect::<Vec<_>>(),
            vec![
                (
                    0,
                    Some(0),
                    vec![0],
                    vec![SourcePackJobIndexRange {
                        first_job_index: 1,
                        job_count: 2,
                    }],
                ),
                (
                    1,
                    Some(1),
                    vec![1],
                    vec![
                        SourcePackJobIndexRange {
                            first_job_index: 0,
                            job_count: 1,
                        },
                        SourcePackJobIndexRange {
                            first_job_index: 2,
                            job_count: 1,
                        },
                    ],
                ),
                (
                    2,
                    Some(2),
                    vec![2],
                    vec![SourcePackJobIndexRange {
                        first_job_index: 0,
                        job_count: 2,
                    }],
                ),
            ]
        );
        let build = plan.bounded_frontend_build_plan();
        assert_eq!(build.schedule.frontend_job_count(), 3);
        let io = build.job_artifact_io_plan();
        assert_eq!(
            io.jobs[3].input_interface_artifact_count(),
            3,
            "bounded codegen inputs must include owning and same-library frontend shards"
        );
        assert_eq!(io.jobs[3].input_interface_artifact_indices, vec![0]);
        assert_eq!(
            io.jobs[3].input_interface_artifact_ranges,
            vec![SourcePackArtifactIndexRange {
                first_artifact_index: 1,
                artifact_count: 2,
            }]
        );
        let artifacts = build.retained_build_artifact_manifest(SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        });
        let shard_plan = artifacts.build_artifact_shard_plan(SourcePackBuildShardLimits {
            max_batches_per_shard: 1,
            max_jobs_per_shard: 1,
            max_artifacts_per_shard: 3,
        });
        let first_codegen_shard = shard_plan
            .shards
            .iter()
            .find(|shard| shard.job_indices == vec![3])
            .expect("first bounded codegen shard");
        assert_eq!(first_codegen_shard.input_artifact_indices, vec![0]);
        assert_eq!(
            first_codegen_shard.input_artifact_ranges,
            vec![SourcePackArtifactIndexRange {
                first_artifact_index: 1,
                artifact_count: 2,
            }]
        );
        assert_eq!(
            first_codegen_shard.artifact_record_count(),
            3,
            "compact input ranges should count as retained shard records"
        );
        assert_eq!(
            first_codegen_shard.artifact_count(),
            4,
            "legacy materialized count still reports expanded dependency fan-in"
        );
        assert!(
            !first_codegen_shard.oversized,
            "compact input ranges must not make an otherwise bounded shard oversized"
        );
        assert_eq!(build.link.input_interface_artifact_count(), 3);
        assert_eq!(
            build.link.input_interface_artifact_ranges,
            vec![SourcePackArtifactIndexRange {
                first_artifact_index: 0,
                artifact_count: 3,
            }]
        );
        assert!(build.link.input_interface_artifact_indices.is_empty());
    }

    #[test]
    fn source_pack_bounded_frontend_manifest_preserves_input_job_ranges() {
        let sources = ["a", "b", "c", "d"];
        let libraries = [7u32, 7, 7, 7];
        let build =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(1, 1))
                .bounded_frontend_build_plan();
        let job_manifest = build.job_artifact_manifest_plan();

        assert_eq!(job_manifest.jobs.len(), 9);
        let first_codegen = &job_manifest.jobs[4];
        assert_eq!(first_codegen.job_index, 4);
        assert_eq!(first_codegen.phase, SourcePackJobPhase::Codegen);
        assert_eq!(first_codegen.input_interface_count, 4);
        assert_eq!(first_codegen.input_artifact_count(), 4);
        assert_eq!(
            first_codegen
                .input_interfaces
                .iter()
                .map(|artifact| artifact.artifact_index)
                .collect::<Vec<_>>(),
            vec![0]
        );
        assert_eq!(
            first_codegen.input_interface_ranges,
            vec![SourcePackJobIndexRange {
                first_job_index: 1,
                job_count: 3,
            }]
        );
        assert!(
            first_codegen.input_interface_artifact_ranges.is_empty(),
            "frontend dependency ranges should stay as job ranges in retained manifests"
        );
        assert_eq!(
            first_codegen
                .outputs
                .iter()
                .map(|artifact| artifact.artifact_index)
                .collect::<Vec<_>>(),
            vec![4]
        );

        let middle_codegen = &job_manifest.jobs[5];
        assert_eq!(middle_codegen.input_interface_count, 4);
        assert_eq!(
            middle_codegen
                .input_interfaces
                .iter()
                .map(|artifact| artifact.artifact_index)
                .collect::<Vec<_>>(),
            vec![1]
        );
        assert_eq!(
            middle_codegen.input_interface_ranges,
            vec![
                SourcePackJobIndexRange {
                    first_job_index: 0,
                    job_count: 1,
                },
                SourcePackJobIndexRange {
                    first_job_index: 2,
                    job_count: 2,
                },
            ]
        );
        assert!(middle_codegen.input_interface_artifact_ranges.is_empty());

        let link = &job_manifest.jobs[8];
        assert!(link.input_interface_ranges.is_empty());
        assert_eq!(
            link.input_interface_artifact_ranges,
            vec![SourcePackArtifactIndexRange {
                first_artifact_index: 0,
                artifact_count: 4,
            }]
        );
    }

    #[test]
    fn source_pack_bounded_frontend_schedule_maps_codegen_units_with_monotonic_cursor() {
        let sources = ["a", "b", "c", "d", "e", "f"];
        let libraries = [1u32, 1, 2, 2, 1, 1];
        let plan =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(1, 1));
        let schedule = plan.bounded_frontend_job_schedule();

        assert_eq!(plan.libraries.library_count(), 3);
        assert_eq!(schedule.frontend_job_count(), 6);
        assert_eq!(schedule.codegen_job_count(), 6);
        assert_eq!(
            schedule
                .jobs
                .iter()
                .filter(|job| job.phase == SourcePackJobPhase::Codegen)
                .map(|job| (job.source_range(), job.library_id, job.library_job_index))
                .collect::<Vec<_>>(),
            vec![
                (0..1, 1, Some(0)),
                (1..2, 1, Some(1)),
                (2..3, 2, Some(2)),
                (3..4, 2, Some(3)),
                (4..5, 1, Some(4)),
                (5..6, 1, Some(5)),
            ]
        );
    }

    #[test]
    fn source_pack_job_plan_streams_from_fallible_files_without_collecting_inputs() {
        let files = [
            SourceFileUnitInput {
                library_id: 0,
                source_index: 0,
                byte_len: 4,
                line_count: 1,
            },
            SourceFileUnitInput {
                library_id: 0,
                source_index: 1,
                byte_len: 4,
                line_count: 2,
            },
            SourceFileUnitInput {
                library_id: 1,
                source_index: 2,
                byte_len: 9,
                line_count: 3,
            },
        ];
        let dependencies = [SourcePackLibraryDependency {
            library_id: 1,
            depends_on_library_id: 0,
        }];

        let plan = SourcePackJobPlan::try_from_fallible_file_stream_with_dependencies(
            files.into_iter().map(Ok::<_, ()>),
            &dependencies,
            limits(8, 8),
        )
        .expect("stream source-pack job plan");

        assert_eq!(
            plan.libraries
                .libraries
                .iter()
                .map(|library| (
                    library.library_index,
                    library.library_id,
                    library.source_range(),
                    library.source_bytes,
                    library.source_lines
                ))
                .collect::<Vec<_>>(),
            vec![(0, 0, 0..2, 8, 3), (1, 1, 2..3, 9, 3)]
        );
        assert_eq!(
            plan.codegen_units
                .units
                .iter()
                .map(|unit| (
                    unit.unit_index,
                    unit.library_id,
                    unit.source_range(),
                    unit.source_bytes,
                    unit.source_lines,
                    unit.oversized_source_file
                ))
                .collect::<Vec<_>>(),
            vec![(0, 0, 0..2, 8, 3, false), (1, 1, 2..3, 9, 3, true)]
        );
        assert_eq!(plan.library_dependencies, dependencies);
    }

    #[test]
    fn source_pack_job_schedule_maps_many_codegen_units_to_one_library_job() {
        let sources = ["aaaa", "bbbb", "cccc"];
        let libraries = [5u32, 5, 5];
        let plan =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(4, 8));
        let schedule = plan.job_schedule();

        assert_eq!(schedule.frontend_job_count(), 1);
        assert_eq!(schedule.codegen_job_count(), 3);
        assert_eq!(schedule.link_job_count(), 1);
        assert_eq!(schedule.max_job_source_files(), 3);
        assert_eq!(
            schedule
                .jobs
                .iter()
                .filter(|job| job.phase == SourcePackJobPhase::Codegen)
                .map(|job| (
                    job.phase_unit_index,
                    job.library_id,
                    job.library_job_index,
                    job.source_range()
                ))
                .collect::<Vec<_>>(),
            vec![
                (0, 5, Some(0), 0..1),
                (1, 5, Some(0), 1..2),
                (2, 5, Some(0), 2..3),
            ]
        );
    }

    #[test]
    fn source_pack_job_batches_mark_large_library_frontend_batch_oversized() {
        let sources = ["aaaa", "bbbb", "cccc"];
        let libraries = [5u32, 5, 5];
        let build =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(4, 8))
                .build_plan();
        let batch_limits = SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        };
        let manifest = build.retained_build_artifact_manifest(batch_limits);

        assert_eq!(manifest.job_batches.oversized_batch_count(), 1);
        let oversized_batch = manifest
            .job_batches
            .batches
            .iter()
            .find(|batch| batch.oversized)
            .expect("large frontend batch should be marked oversized");
        assert_eq!(oversized_batch.job_indices, vec![0]);
        assert_eq!(oversized_batch.source_bytes, 12);
        assert_eq!(oversized_batch.source_file_count, 3);

        let shard_plan = manifest.build_artifact_shard_plan(SourcePackBuildShardLimits {
            max_batches_per_shard: 1,
            max_jobs_per_shard: 1,
            max_artifacts_per_shard: 4,
        });
        assert_eq!(shard_plan.oversized_shard_count(), 1);
    }

    #[test]
    fn source_pack_job_schedule_threads_library_dependencies() {
        let sources = ["core", "math", "app"];
        let libraries = [1u32, 2, 3];
        let dependencies = [
            SourcePackLibraryDependency {
                library_id: 2,
                depends_on_library_id: 1,
            },
            SourcePackLibraryDependency {
                library_id: 3,
                depends_on_library_id: 1,
            },
            SourcePackLibraryDependency {
                library_id: 3,
                depends_on_library_id: 2,
            },
        ];
        let plan = SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
            &sources,
            &libraries,
            &dependencies,
            limits(64, 8),
        );
        let schedule = plan.job_schedule();

        assert_eq!(schedule.dependency_edge_count(), 12);
        assert_eq!(schedule.max_job_dependency_count(), 3);
        assert_eq!(
            schedule
                .jobs
                .iter()
                .map(|job| (
                    job.phase,
                    job.library_id,
                    job.dependency_job_indices.clone()
                ))
                .collect::<Vec<_>>(),
            vec![
                (SourcePackJobPhase::LibraryFrontend, 1, vec![]),
                (SourcePackJobPhase::LibraryFrontend, 2, vec![0]),
                (SourcePackJobPhase::LibraryFrontend, 3, vec![0, 1]),
                (SourcePackJobPhase::Codegen, 1, vec![0]),
                (SourcePackJobPhase::Codegen, 2, vec![1, 0]),
                (SourcePackJobPhase::Codegen, 3, vec![2, 0, 1]),
                (SourcePackJobPhase::Link, u32::MAX, vec![]),
            ]
        );
    }

    #[test]
    fn source_pack_job_schedule_topologically_orders_frontend_jobs() {
        let sources = ["app", "core"];
        let libraries = [2u32, 1];
        let dependencies = [SourcePackLibraryDependency {
            library_id: 2,
            depends_on_library_id: 1,
        }];
        let plan = SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
            &sources,
            &libraries,
            &dependencies,
            limits(64, 8),
        );
        let schedule = plan.job_schedule();

        assert_eq!(
            schedule
                .jobs
                .iter()
                .filter(|job| job.phase == SourcePackJobPhase::LibraryFrontend)
                .map(|job| (
                    job.job_index,
                    job.library_id,
                    job.dependency_job_indices.clone()
                ))
                .collect::<Vec<_>>(),
            vec![(0, 1, vec![]), (1, 2, vec![0])]
        );
        assert_eq!(
            schedule
                .jobs
                .iter()
                .filter(|job| job.phase == SourcePackJobPhase::Codegen)
                .map(|job| (
                    job.library_id,
                    job.library_job_index,
                    job.dependency_job_indices.clone()
                ))
                .collect::<Vec<_>>(),
            vec![(2, Some(1), vec![1, 0]), (1, Some(0), vec![0])]
        );
    }

    #[test]
    fn source_pack_job_schedule_groups_dependency_ready_waves() {
        let sources = ["core", "math", "app"];
        let libraries = [1u32, 2, 3];
        let dependencies = [
            SourcePackLibraryDependency {
                library_id: 3,
                depends_on_library_id: 1,
            },
            SourcePackLibraryDependency {
                library_id: 3,
                depends_on_library_id: 2,
            },
        ];
        let plan = SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
            &sources,
            &libraries,
            &dependencies,
            limits(64, 8),
        );
        let waves = plan
            .job_schedule()
            .try_execution_waves()
            .expect("dependency-ready waves");
        let wave_summary = plan
            .job_schedule()
            .try_execution_wave_summary()
            .expect("dependency-ready wave summary");

        assert_eq!(
            waves
                .waves
                .iter()
                .map(|wave| wave.job_indices.clone())
                .collect::<Vec<_>>(),
            vec![vec![0, 1], vec![2, 3, 4], vec![5], vec![6]]
        );
        assert_eq!(waves.wave_count(), 4);
        assert_eq!(waves.max_wave_job_count(), 3);
        assert_eq!(waves.max_wave_source_files(), 3);
        assert_eq!(waves.max_wave_source_bytes(), 11);
        assert_eq!(wave_summary.wave_count(), waves.wave_count());
        assert_eq!(
            wave_summary.max_wave_job_count(),
            waves.max_wave_job_count()
        );
        assert_eq!(
            wave_summary.max_wave_source_files(),
            waves.max_wave_source_files()
        );
        assert_eq!(
            wave_summary.max_wave_source_bytes(),
            waves.max_wave_source_bytes()
        );
    }

    #[test]
    fn source_pack_job_schedule_streams_dependency_ready_waves() {
        let sources = ["core", "math", "app"];
        let libraries = [1u32, 2, 3];
        let dependencies = [
            SourcePackLibraryDependency {
                library_id: 3,
                depends_on_library_id: 1,
            },
            SourcePackLibraryDependency {
                library_id: 3,
                depends_on_library_id: 2,
            },
        ];
        let schedule = SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
            &sources,
            &libraries,
            &dependencies,
            limits(64, 8),
        )
        .job_schedule();
        let collected = schedule
            .try_execution_waves()
            .expect("collected dependency-ready waves");

        let mut streamed = Vec::new();
        let streamed_count = schedule
            .try_for_each_execution_wave(
                |err| err,
                |wave| {
                    streamed.push((
                        wave.wave_index,
                        wave.job_indices,
                        wave.source_bytes,
                        wave.source_file_count,
                    ));
                    Ok::<(), SourcePackScheduleError>(())
                },
            )
            .expect("streamed dependency-ready waves");

        assert_eq!(streamed_count, collected.wave_count());
        assert_eq!(
            streamed,
            collected
                .waves
                .iter()
                .map(|wave| (
                    wave.wave_index,
                    wave.job_indices.clone(),
                    wave.source_bytes,
                    wave.source_file_count
                ))
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn source_pack_bounded_frontend_schedule_ready_waves_consume_dependency_ranges() {
        let sources = ["a", "b", "c", "d"];
        let libraries = [5u32, 5, 5, 5];
        let schedule =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(1, 1))
                .bounded_frontend_job_schedule();

        assert_eq!(schedule.frontend_job_count(), 4);
        assert_eq!(schedule.codegen_job_count(), 4);
        assert!(
            schedule
                .jobs
                .iter()
                .filter(|job| job.phase == SourcePackJobPhase::Codegen)
                .all(|job| !schedule.dependency_job_ranges_for_job(job).is_empty()),
            "test must exercise compact ranged frontend dependencies"
        );

        let waves = schedule
            .try_execution_waves()
            .expect("bounded frontend dependency-range waves");
        assert_eq!(
            waves
                .waves
                .iter()
                .map(|wave| wave.job_indices.clone())
                .collect::<Vec<_>>(),
            vec![vec![0, 1, 2, 3], vec![4, 5, 6, 7], vec![8]]
        );
        let summary = schedule
            .try_execution_wave_summary()
            .expect("bounded frontend dependency-range wave summary");
        assert_eq!(summary.wave_count(), 3);
        assert_eq!(summary.max_wave_job_count(), 4);
    }

    #[test]
    fn source_pack_job_schedule_rejects_non_ready_cycles() {
        let schedule = SourcePackJobSchedule {
            jobs: vec![test_job(0, vec![1]), test_job(1, vec![0])],
            dependency_job_ranges_by_job_index: Vec::new(),
        };
        let err = schedule
            .try_execution_waves()
            .expect_err("cycle should not produce ready waves");

        assert_eq!(err.unscheduled_job_indices, vec![0, 1]);
    }

    #[test]
    fn source_pack_job_schedule_reports_missing_dependencies_as_unscheduled() {
        let schedule = SourcePackJobSchedule {
            jobs: vec![test_job(0, vec![99]), test_job(1, vec![0])],
            dependency_job_ranges_by_job_index: Vec::new(),
        };
        let err = schedule
            .try_execution_waves()
            .expect_err("missing dependency should not become ready");

        assert_eq!(err.unscheduled_job_indices, vec![0, 1]);
    }

    #[test]
    fn source_pack_job_schedule_preserves_order_for_dependency_chains() {
        let schedule = SourcePackJobSchedule {
            jobs: (0..16)
                .map(|job_index| {
                    let dependencies = if job_index == 0 {
                        Vec::new()
                    } else {
                        vec![job_index - 1]
                    };
                    test_job(job_index, dependencies)
                })
                .collect(),
            dependency_job_ranges_by_job_index: Vec::new(),
        };
        let waves = schedule
            .try_execution_waves()
            .expect("dependency chain should be schedulable");

        assert_eq!(waves.wave_count(), 16);
        assert_eq!(waves.max_wave_job_count(), 1);
        assert_eq!(
            waves
                .waves
                .iter()
                .map(|wave| wave.job_indices.clone())
                .collect::<Vec<_>>(),
            (0..16).map(|job_index| vec![job_index]).collect::<Vec<_>>()
        );
    }

    #[test]
    fn source_pack_job_plan_preserves_frontend_cycle_edges() {
        let sources = ["core", "app"];
        let libraries = [1u32, 2];
        let dependencies = [
            SourcePackLibraryDependency {
                library_id: 1,
                depends_on_library_id: 2,
            },
            SourcePackLibraryDependency {
                library_id: 2,
                depends_on_library_id: 1,
            },
        ];
        let schedule = SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
            &sources,
            &libraries,
            &dependencies,
            limits(64, 8),
        )
        .job_schedule();

        assert_eq!(
            schedule
                .jobs
                .iter()
                .filter(|job| job.phase == SourcePackJobPhase::LibraryFrontend)
                .map(|job| (
                    job.job_index,
                    job.library_id,
                    job.dependency_job_indices.clone()
                ))
                .collect::<Vec<_>>(),
            vec![(0, 1, vec![1]), (1, 2, vec![0])]
        );
        let err = schedule
            .try_execution_waves()
            .expect_err("cyclic library jobs should not become ready");
        assert_eq!(err.unscheduled_job_indices, vec![0, 1, 2, 3, 4]);
    }

    #[test]
    fn source_pack_job_schedule_batches_ready_waves_by_resource_limits() {
        let sources = ["aa", "bb", "cc", "dd"];
        let libraries = [1u32, 2, 3, 4];
        let plan =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(64, 8));
        let batches = plan
            .job_schedule()
            .try_execution_batches(SourcePackJobBatchLimits {
                max_jobs_per_batch: 2,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 8,
            })
            .expect("bounded ready-wave batches");
        let batch_summary = plan
            .job_schedule()
            .try_execution_batch_summary(SourcePackJobBatchLimits {
                max_jobs_per_batch: 2,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 8,
            })
            .expect("bounded ready-wave batch summary");

        assert_eq!(
            batches
                .batches
                .iter()
                .map(|batch| (batch.wave_index, batch.job_indices.clone()))
                .collect::<Vec<_>>(),
            vec![
                (0, vec![0, 1]),
                (0, vec![2, 3]),
                (1, vec![4, 5]),
                (1, vec![6, 7]),
                (2, vec![8]),
            ]
        );
        assert_eq!(batches.batch_count(), 5);
        assert_eq!(batches.max_batch_job_count(), 2);
        assert_eq!(batches.max_batch_source_bytes(), 4);
        assert_eq!(batches.max_batch_source_files(), 2);
        assert_eq!(batch_summary.batch_count(), batches.batch_count());
        assert_eq!(
            batch_summary.max_batch_job_count(),
            batches.max_batch_job_count()
        );
        assert_eq!(
            batch_summary.max_batch_source_bytes(),
            batches.max_batch_source_bytes()
        );
        assert_eq!(
            batch_summary.max_batch_source_files(),
            batches.max_batch_source_files()
        );
    }

    #[test]
    fn source_pack_job_schedule_streams_execution_batches_by_resource_limits() {
        let sources = ["aa", "bb", "cc", "dd"];
        let libraries = [1u32, 2, 3, 4];
        let schedule =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(64, 8))
                .job_schedule();
        let batch_limits = SourcePackJobBatchLimits {
            max_jobs_per_batch: 2,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 8,
        };
        let collected = schedule
            .try_execution_batches(batch_limits)
            .expect("collected execution batches");

        let mut streamed = Vec::new();
        let streamed_count = schedule
            .try_for_each_execution_batch(
                batch_limits,
                |err| err,
                |batch| {
                    streamed.push((batch.batch_index, batch.wave_index, batch.job_indices));
                    Ok::<(), SourcePackScheduleError>(())
                },
            )
            .expect("streamed execution batches");

        assert_eq!(streamed_count, collected.batch_count());
        assert_eq!(
            streamed,
            collected
                .batches
                .iter()
                .map(|batch| (
                    batch.batch_index,
                    batch.wave_index,
                    batch.job_indices.clone()
                ))
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn source_pack_job_schedule_records_batch_dependencies_and_ready_batches() {
        let sources = ["aa", "bb", "cc", "dd"];
        let libraries = [1u32, 2, 3, 4];
        let schedule =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(64, 8))
                .job_schedule();
        let batches = schedule
            .try_execution_batches(SourcePackJobBatchLimits {
                max_jobs_per_batch: 2,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 8,
            })
            .expect("bounded ready-wave batches");
        let dependencies = schedule
            .try_batch_dependency_plan(&batches)
            .expect("batch dependency plan");
        let dependency_summary = schedule
            .try_execution_batch_dependency_summary(SourcePackJobBatchLimits {
                max_jobs_per_batch: 2,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 8,
            })
            .expect("batch dependency summary");

        assert_eq!(dependencies.batch_count(), 5);
        assert_eq!(dependencies.dependency_edge_count(), 4);
        assert_eq!(dependencies.max_dependency_count(), 2);
        assert_eq!(dependency_summary.batch_count(), dependencies.batch_count());
        assert_eq!(
            dependency_summary.dependency_edge_count(),
            dependencies.dependency_edge_count()
        );
        assert_eq!(
            dependency_summary.max_dependency_count(),
            dependencies.max_dependency_count()
        );
        assert_eq!(
            dependency_summary.initial_ready_batch_count(),
            dependencies.ready_batch_count(&[])
        );
        assert_eq!(
            dependencies
                .batches
                .iter()
                .map(|batch| (
                    batch.batch_index,
                    batch.dependency_batch_indices.clone(),
                    batch.dependency_batch_ranges.clone()
                ))
                .collect::<Vec<_>>(),
            vec![
                (0, vec![], vec![]),
                (1, vec![], vec![]),
                (2, vec![0], vec![]),
                (3, vec![1], vec![]),
                (
                    4,
                    vec![],
                    vec![SourcePackJobBatchDependencyRange {
                        first_batch_index: 2,
                        batch_count: 2,
                    }],
                ),
            ]
        );
        assert_eq!(dependencies.ready_batch_count(&[]), 2);
        assert_eq!(
            dependencies.ready_batch_indices_limited(&[], Some(2)),
            vec![0, 1]
        );
        assert_eq!(
            dependencies.ready_batch_indices_limited(&[], Some(1)),
            vec![0]
        );
        assert_eq!(
            dependencies.ready_batch_indices_limited(&[], Some(0)),
            Vec::<usize>::new()
        );
        assert_eq!(dependencies.ready_batch_count(&[0]), 2);
        assert_eq!(
            dependencies.ready_batch_indices_limited(&[0], Some(2)),
            vec![1, 2]
        );
        assert_eq!(
            dependencies.ready_batch_indices_limited(&[0], Some(2)),
            vec![1, 2]
        );
        assert_eq!(
            dependencies.ready_batch_indices_limited(&[0, 1], Some(2)),
            vec![2, 3]
        );
        assert_eq!(
            dependencies.ready_batch_indices_limited(&[0, 1, 2, 3], Some(1)),
            vec![4]
        );
        assert_eq!(
            dependencies.ready_batch_indices_limited(&[0, 1, 2, 3, 4], Some(1)),
            Vec::<usize>::new()
        );

        let completed_codegen_batches = [SourcePackJobBatchDependencyRange {
            first_batch_index: 2,
            batch_count: 2,
        }];
        assert!(
            dependencies.batches[4].dependencies_completed_by_ranges(&completed_codegen_batches)
        );
        assert!(!dependencies.batches[4].dependencies_completed_by_ranges(&[
            SourcePackJobBatchDependencyRange {
                first_batch_index: 2,
                batch_count: 1,
            }
        ]));
        assert!(dependencies.batches[4].dependencies_completed_by_ranges(&[
            SourcePackJobBatchDependencyRange {
                first_batch_index: 3,
                batch_count: 1,
            },
            SourcePackJobBatchDependencyRange {
                first_batch_index: 2,
                batch_count: 1,
            },
        ]));

        let completed_first_four_batches = [SourcePackJobBatchDependencyRange {
            first_batch_index: 0,
            batch_count: 4,
        }];
        assert_eq!(
            dependencies.ready_batch_count_with_completed_ranges(&completed_first_four_batches),
            1
        );
        assert_eq!(
            dependencies.ready_batch_indices_limited_with_completed_ranges(
                &completed_first_four_batches,
                Some(1),
            ),
            vec![4]
        );
        let completed_first_three_batches = [SourcePackJobBatchDependencyRange {
            first_batch_index: 0,
            batch_count: 3,
        }];
        assert_eq!(
            dependencies.ready_batch_indices_limited_with_completed_ranges(
                &completed_first_three_batches,
                Some(2),
            ),
            vec![3]
        );
        assert_eq!(
            dependencies.ready_batch_indices_limited_with_completed_ranges(
                &completed_first_four_batches,
                Some(0),
            ),
            Vec::<usize>::new()
        );
    }

    #[test]
    fn source_pack_job_schedule_streams_batch_dependencies() {
        let sources = ["aa", "bb", "cc", "dd"];
        let libraries = [1u32, 2, 3, 4];
        let schedule =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(64, 8))
                .job_schedule();
        let batches = schedule
            .try_execution_batches(SourcePackJobBatchLimits {
                max_jobs_per_batch: 2,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 8,
            })
            .expect("bounded ready-wave batches");
        let collected = schedule
            .try_batch_dependency_plan(&batches)
            .expect("collected batch dependencies");

        let mut streamed = Vec::new();
        let streamed_count = schedule
            .try_for_each_batch_dependency(
                &batches,
                |err| err,
                |dependency| {
                    streamed.push(dependency);
                    Ok::<(), SourcePackScheduleError>(())
                },
            )
            .expect("streamed batch dependencies");

        assert_eq!(streamed_count, collected.batch_count());
        assert_eq!(streamed, collected.batches);
    }

    #[test]
    fn source_pack_job_schedule_keeps_oversized_jobs_as_single_batches() {
        let schedule = SourcePackJobSchedule {
            jobs: vec![
                test_job(0, Vec::new()),
                SourcePackJob {
                    source_bytes: 10,
                    source_file_count: 3,
                    ..test_job(1, Vec::new())
                },
            ],
            dependency_job_ranges_by_job_index: Vec::new(),
        };
        let batches = schedule
            .try_execution_batches(SourcePackJobBatchLimits {
                max_jobs_per_batch: 8,
                max_source_bytes_per_batch: 4,
                max_source_files_per_batch: 2,
            })
            .expect("oversized job should still be schedulable");

        assert_eq!(
            batches
                .batches
                .iter()
                .map(|batch| batch.job_indices.clone())
                .collect::<Vec<_>>(),
            vec![vec![0], vec![1]]
        );
        assert_eq!(batches.max_batch_source_bytes(), 10);
        assert_eq!(batches.max_batch_source_files(), 3);
        assert_eq!(batches.oversized_batch_count(), 1);
        assert_eq!(
            batches
                .batches
                .iter()
                .map(|batch| batch.oversized)
                .collect::<Vec<_>>(),
            vec![false, true]
        );
    }

    #[test]
    fn source_pack_build_plan_records_artifacts_and_link_inputs() {
        let sources = ["aaaa", "bbbb", "cccc"];
        let libraries = [5u32, 5, 9];
        let plan =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(4, 8));
        let build = plan.build_plan();

        assert_eq!(build.schedule.frontend_job_count(), 2);
        assert_eq!(build.schedule.codegen_job_count(), 3);
        assert_eq!(build.schedule.link_job_count(), 1);
        assert_eq!(build.interface_artifact_count(), 2);
        assert_eq!(build.object_artifact_count(), 3);
        assert_eq!(build.linked_output_artifact_count(), 1);
        assert_eq!(build.link.link_job_index, 5);
        assert_eq!(build.link.input_interface_artifact_count(), 2);
        assert_eq!(build.link.input_object_artifact_count(), 3);
        assert_eq!(
            build.link.input_interface_artifact_ranges,
            vec![SourcePackArtifactIndexRange {
                first_artifact_index: 0,
                artifact_count: 2,
            }]
        );
        assert_eq!(
            build.link.input_object_artifact_ranges,
            vec![SourcePackArtifactIndexRange {
                first_artifact_index: 2,
                artifact_count: 3,
            }]
        );
        assert!(build.link.input_interface_artifact_indices.is_empty());
        assert!(build.link.input_object_artifact_indices.is_empty());
        assert_eq!(build.link.output_artifact_index, 5);
        let artifact_manifest = build.artifact_manifest();
        let artifact_summary = build.artifact_manifest_summary();
        assert_eq!(
            artifact_summary.artifact_count(),
            artifact_manifest.artifact_count()
        );
        assert_eq!(
            artifact_summary.max_key_len(),
            artifact_manifest.max_key_len()
        );

        let job_artifacts = build.job_artifact_io_plan();
        let job_artifact_summary = build.job_artifact_io_summary();
        assert_eq!(
            job_artifact_summary.max_input_interface_count(),
            job_artifacts.max_input_interface_count()
        );
        assert_eq!(
            job_artifact_summary.max_input_object_count(),
            job_artifacts.max_input_object_count()
        );
        assert_eq!(
            job_artifact_summary.max_input_artifact_count(),
            job_artifacts.max_input_artifact_count()
        );
        assert_eq!(
            job_artifact_summary.max_output_artifact_count(),
            job_artifacts.max_output_artifact_count()
        );

        let job_manifest = build.job_artifact_manifest_plan();
        let job_manifest_summary = build.job_artifact_manifest_summary();
        assert_eq!(
            job_manifest_summary.max_input_artifact_count(),
            job_manifest.max_input_artifact_count()
        );

        let batch_limits = SourcePackJobBatchLimits {
            max_jobs_per_batch: 2,
            max_source_bytes_per_batch: 8,
            max_source_files_per_batch: 8,
        };
        let link_interface_batches = build.link_interface_batches(batch_limits);
        let link_interface_summary = build.link_interface_batch_summary(batch_limits);
        assert_eq!(
            link_interface_summary.batch_count(),
            link_interface_batches.batch_count()
        );
        assert_eq!(
            link_interface_summary.max_batch_interface_count(),
            link_interface_batches.max_batch_interface_count()
        );
        assert_eq!(
            link_interface_summary.max_batch_source_bytes(),
            link_interface_batches.max_batch_source_bytes()
        );
        assert_eq!(
            link_interface_summary.max_batch_source_files(),
            link_interface_batches.max_batch_source_files()
        );
        let link_object_batches = build.link_object_batches(batch_limits);
        let link_object_summary = build.link_object_batch_summary(batch_limits);
        assert_eq!(
            link_object_summary.batch_count(),
            link_object_batches.batch_count()
        );
        assert_eq!(
            link_object_summary.max_batch_object_count(),
            link_object_batches.max_batch_object_count()
        );
        assert_eq!(
            link_object_summary.max_batch_source_bytes(),
            link_object_batches.max_batch_source_bytes()
        );
        assert_eq!(
            link_object_summary.max_batch_source_files(),
            link_object_batches.max_batch_source_files()
        );
        let artifact_estimate = plan.build_artifact_estimate_summary_for_schedule(
            &build.schedule,
            batch_limits,
            SourcePackArtifactTarget::Generic,
        );
        assert_eq!(
            artifact_estimate.artifact_manifest.artifact_count(),
            artifact_summary.artifact_count()
        );
        assert_eq!(
            artifact_estimate.artifact_manifest.max_key_len(),
            artifact_summary.max_key_len()
        );
        assert_eq!(
            artifact_estimate
                .artifact_lifetimes
                .artifacts_without_consumers(),
            build
                .artifact_lifetime_summary()
                .artifacts_without_consumers()
        );
        assert_eq!(
            artifact_estimate.job_artifacts.max_input_interface_count(),
            job_artifact_summary.max_input_interface_count()
        );
        assert_eq!(
            artifact_estimate.job_artifacts.max_input_object_count(),
            job_artifact_summary.max_input_object_count()
        );
        assert_eq!(
            artifact_estimate.job_artifacts.max_input_artifact_count(),
            job_artifact_summary.max_input_artifact_count()
        );
        assert_eq!(
            artifact_estimate.job_artifacts.max_output_artifact_count(),
            job_artifact_summary.max_output_artifact_count()
        );
        assert_eq!(
            artifact_estimate
                .job_artifact_manifest
                .max_input_artifact_count(),
            job_manifest_summary.max_input_artifact_count()
        );
        assert_eq!(
            artifact_estimate.link_interface_batches.batch_count(),
            link_interface_summary.batch_count()
        );
        assert_eq!(
            artifact_estimate
                .link_interface_batches
                .max_batch_interface_count(),
            link_interface_summary.max_batch_interface_count()
        );
        assert_eq!(
            artifact_estimate
                .link_interface_batches
                .max_batch_source_bytes(),
            link_interface_summary.max_batch_source_bytes()
        );
        assert_eq!(
            artifact_estimate
                .link_interface_batches
                .max_batch_source_files(),
            link_interface_summary.max_batch_source_files()
        );
        assert_eq!(
            artifact_estimate.link_object_batches.batch_count(),
            link_object_summary.batch_count()
        );
        assert_eq!(
            artifact_estimate
                .link_object_batches
                .max_batch_object_count(),
            link_object_summary.max_batch_object_count()
        );
        assert_eq!(
            artifact_estimate
                .link_object_batches
                .max_batch_source_bytes(),
            link_object_summary.max_batch_source_bytes()
        );
        assert_eq!(
            artifact_estimate
                .link_object_batches
                .max_batch_source_files(),
            link_object_summary.max_batch_source_files()
        );
        assert_eq!(artifact_estimate.total_artifacts, build.artifacts.len());
        assert_eq!(
            artifact_estimate.interface_artifacts,
            build.interface_artifact_count()
        );
        assert_eq!(
            artifact_estimate.object_artifacts,
            build.object_artifact_count()
        );
        assert_eq!(
            artifact_estimate.linked_output_artifacts,
            build.linked_output_artifact_count()
        );
        assert_eq!(
            artifact_estimate.link_interface_inputs,
            build.link.input_interface_artifact_count()
        );
        assert_eq!(
            artifact_estimate.link_object_inputs,
            build.link.input_object_artifact_count()
        );
        assert_eq!(artifact_estimate.artifact_use_count, build.artifacts.len());
        assert_eq!(
            build
                .artifacts
                .iter()
                .map(|artifact| (
                    artifact.kind,
                    artifact.producing_job_index,
                    artifact.library_id,
                    artifact.source_range()
                ))
                .collect::<Vec<_>>(),
            vec![
                (SourcePackArtifactKind::LibraryInterface, 0, 5, 0..2),
                (SourcePackArtifactKind::LibraryInterface, 1, 9, 2..3),
                (SourcePackArtifactKind::CodegenObject, 2, 5, 0..1),
                (SourcePackArtifactKind::CodegenObject, 3, 5, 1..2),
                (SourcePackArtifactKind::CodegenObject, 4, 9, 2..3),
                (SourcePackArtifactKind::LinkedOutput, 5, u32::MAX, 0..3),
            ]
        );
    }

    #[test]
    fn source_pack_build_plan_records_artifact_consumers_and_last_use() {
        let sources = ["aaaa", "bbbb", "cccc"];
        let libraries = [5u32, 5, 9];
        let build =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(4, 8))
                .build_plan();
        let uses = build.artifact_use_plan();

        assert_eq!(uses.max_consumer_count(), 3);
        assert_eq!(uses.artifacts_without_consumers(), 1);
        assert_eq!(
            uses.uses
                .iter()
                .map(|artifact| (
                    artifact.artifact_index,
                    artifact.producing_job_index,
                    artifact.consumer_job_indices.clone(),
                    artifact.last_consumer_job_index
                ))
                .collect::<Vec<_>>(),
            vec![
                (0, 0, vec![2, 3, 5], Some(5)),
                (1, 1, vec![4, 5], Some(5)),
                (2, 2, vec![5], Some(5)),
                (3, 3, vec![5], Some(5)),
                (4, 4, vec![5], Some(5)),
                (5, 5, vec![], None),
            ]
        );
    }

    #[test]
    fn source_pack_build_plan_records_artifact_last_use_without_consumer_lists() {
        let sources = ["aaaa", "bbbb", "cccc"];
        let libraries = [5u32, 5, 9];
        let build =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(4, 8))
                .build_plan();
        let last_uses = build.artifact_last_use_plan();
        let last_use_index = build.artifact_last_use_index();
        let lifetime_summary = build.artifact_lifetime_summary();

        assert_eq!(last_uses.artifacts_without_consumers(), 1);
        assert_eq!(last_use_index.artifacts_without_consumers(), 1);
        assert_eq!(lifetime_summary.artifacts_without_consumers(), 1);
        assert_eq!(
            lifetime_summary.artifacts_without_consumers(),
            last_use_index.artifacts_without_consumers()
        );
        assert_eq!(
            last_use_index.last_consumer_job_indices,
            vec![Some(5), Some(5), Some(5), Some(5), Some(5), None]
        );
        assert_eq!(
            last_uses
                .artifacts
                .iter()
                .map(|artifact| (
                    artifact.artifact_index,
                    artifact.producing_job_index,
                    artifact.last_consumer_job_index
                ))
                .collect::<Vec<_>>(),
            vec![
                (0, 0, Some(5)),
                (1, 1, Some(5)),
                (2, 2, Some(5)),
                (3, 3, Some(5)),
                (4, 4, Some(5)),
                (5, 5, None),
            ]
        );
    }

    #[test]
    fn source_pack_build_plan_records_job_artifact_io() {
        let sources = ["core", "math", "app"];
        let libraries = [1u32, 2, 3];
        let dependencies = [
            SourcePackLibraryDependency {
                library_id: 2,
                depends_on_library_id: 1,
            },
            SourcePackLibraryDependency {
                library_id: 3,
                depends_on_library_id: 1,
            },
            SourcePackLibraryDependency {
                library_id: 3,
                depends_on_library_id: 2,
            },
        ];
        let build = SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
            &sources,
            &libraries,
            &dependencies,
            limits(64, 8),
        )
        .build_plan();
        let io = build.job_artifact_io_plan();

        assert_eq!(
            io.jobs
                .iter()
                .map(|job| {
                    (
                        job.job_index,
                        job.phase,
                        job.input_interface_artifact_count(),
                        job.input_interface_artifact_ranges.clone(),
                        job.input_interface_artifact_indices.clone(),
                        job.input_object_artifact_count(),
                        job.input_object_artifact_ranges.clone(),
                        job.input_object_artifact_indices.clone(),
                        job.output_artifact_indices.clone(),
                    )
                })
                .collect::<Vec<_>>(),
            vec![
                (
                    0,
                    SourcePackJobPhase::LibraryFrontend,
                    0,
                    vec![],
                    vec![],
                    0,
                    vec![],
                    vec![],
                    vec![0]
                ),
                (
                    1,
                    SourcePackJobPhase::LibraryFrontend,
                    1,
                    vec![],
                    vec![0],
                    0,
                    vec![],
                    vec![],
                    vec![1],
                ),
                (
                    2,
                    SourcePackJobPhase::LibraryFrontend,
                    2,
                    vec![],
                    vec![0, 1],
                    0,
                    vec![],
                    vec![],
                    vec![2],
                ),
                (
                    3,
                    SourcePackJobPhase::Codegen,
                    1,
                    vec![],
                    vec![0],
                    0,
                    vec![],
                    vec![],
                    vec![3],
                ),
                (
                    4,
                    SourcePackJobPhase::Codegen,
                    2,
                    vec![],
                    vec![1, 0],
                    0,
                    vec![],
                    vec![],
                    vec![4],
                ),
                (
                    5,
                    SourcePackJobPhase::Codegen,
                    3,
                    vec![],
                    vec![2, 0, 1],
                    0,
                    vec![],
                    vec![],
                    vec![5],
                ),
                (
                    6,
                    SourcePackJobPhase::Link,
                    3,
                    vec![SourcePackArtifactIndexRange {
                        first_artifact_index: 0,
                        artifact_count: 3,
                    }],
                    vec![],
                    3,
                    vec![SourcePackArtifactIndexRange {
                        first_artifact_index: 3,
                        artifact_count: 3,
                    }],
                    vec![],
                    vec![6],
                ),
            ]
        );
        assert_eq!(io.max_input_interface_count(), 3);
        assert_eq!(io.max_input_object_count(), 3);
        assert_eq!(io.max_input_artifact_count(), 6);
        assert_eq!(io.max_output_artifact_count(), 1);
    }

    #[test]
    fn source_pack_build_plan_streams_job_artifact_records() {
        let sources = ["core", "math", "app"];
        let libraries = [1u32, 2, 3];
        let dependencies = [
            SourcePackLibraryDependency {
                library_id: 2,
                depends_on_library_id: 1,
            },
            SourcePackLibraryDependency {
                library_id: 3,
                depends_on_library_id: 1,
            },
            SourcePackLibraryDependency {
                library_id: 3,
                depends_on_library_id: 2,
            },
        ];
        let build = SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
            &sources,
            &libraries,
            &dependencies,
            limits(64, 8),
        )
        .build_plan();

        let collected_io = build.job_artifact_io_plan();
        let mut streamed_io = Vec::new();
        let streamed_io_count = build
            .try_for_each_job_artifact_io(|job| {
                streamed_io.push(job);
                Ok::<(), ()>(())
            })
            .expect("stream job artifact io");
        assert_eq!(streamed_io_count, collected_io.jobs.len());
        assert_eq!(streamed_io, collected_io.jobs);

        let collected_manifest = build.job_artifact_manifest_plan();
        let mut streamed_manifest = Vec::new();
        let streamed_manifest_count = build
            .try_for_each_job_artifact_manifest_for_target(
                SourcePackArtifactTarget::Generic,
                |job| {
                    streamed_manifest.push(job);
                    Ok::<(), ()>(())
                },
            )
            .expect("stream job artifact manifests");
        assert_eq!(streamed_manifest_count, collected_manifest.jobs.len());
        assert_eq!(streamed_manifest, collected_manifest.jobs);

        let target_manifest = build.artifact_manifest_for_target(SourcePackArtifactTarget::Wasm);
        let mut streamed_target_manifest = Vec::new();
        build
            .try_for_each_job_artifact_manifest_for_target(SourcePackArtifactTarget::Wasm, |job| {
                streamed_target_manifest.push(job);
                Ok::<(), ()>(())
            })
            .expect("stream target-qualified job artifact manifests");
        for artifact in streamed_target_manifest.iter().flat_map(|job| {
            job.input_interfaces
                .iter()
                .chain(job.input_objects.iter())
                .chain(job.outputs.iter())
        }) {
            assert!(artifact.key.starts_with("wasm/"));
            assert_eq!(
                target_manifest
                    .get(artifact.artifact_index)
                    .map(|entry| entry.key.as_str()),
                Some(artifact.key.as_str())
            );
        }
    }

    #[test]
    fn source_pack_build_plan_records_stable_artifact_keys() {
        let sources = ["core", "math", "app"];
        let libraries = [1u32, 2, 3];
        let dependencies = [
            SourcePackLibraryDependency {
                library_id: 2,
                depends_on_library_id: 1,
            },
            SourcePackLibraryDependency {
                library_id: 3,
                depends_on_library_id: 2,
            },
        ];
        let build = SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
            &sources,
            &libraries,
            &dependencies,
            limits(64, 8),
        )
        .build_plan();
        let manifest = build.artifact_manifest();
        let job_manifest = build.job_artifact_manifest_plan();

        assert_eq!(manifest.artifact_count(), 7);
        assert_eq!(
            manifest
                .artifacts
                .iter()
                .map(|artifact| artifact.key.as_str())
                .collect::<Vec<_>>(),
            vec![
                "library-interface/lib-1/job-0/src-0-1",
                "library-interface/lib-2/job-1/src-1-2",
                "library-interface/lib-3/job-2/src-2-3",
                "codegen-object/lib-1/job-3/src-0-1",
                "codegen-object/lib-2/job-4/src-1-2",
                "codegen-object/lib-3/job-5/src-2-3",
                "linked-output/job-6/src-0-3",
            ]
        );
        assert_eq!(manifest.max_key_len(), 37);
        assert_eq!(job_manifest.max_input_artifact_count(), 6);
        assert_eq!(
            job_manifest.jobs[5]
                .input_interfaces
                .iter()
                .map(|artifact| artifact.key.as_str())
                .collect::<Vec<_>>(),
            vec![
                "library-interface/lib-3/job-2/src-2-3",
                "library-interface/lib-2/job-1/src-1-2",
            ]
        );
        assert_eq!(
            job_manifest.jobs[6].input_object_artifact_ranges,
            vec![SourcePackArtifactIndexRange {
                first_artifact_index: 3,
                artifact_count: 3,
            }]
        );
        assert!(job_manifest.jobs[6].input_objects.is_empty());
        assert_eq!(
            job_manifest.jobs[6].outputs[0].key,
            "linked-output/job-6/src-0-3"
        );
    }

    #[test]
    fn source_pack_build_plan_serializes_durable_artifact_manifest() {
        let sources = ["core", "math", "app"];
        let libraries = [1u32, 2, 3];
        let dependencies = [
            SourcePackLibraryDependency {
                library_id: 2,
                depends_on_library_id: 1,
            },
            SourcePackLibraryDependency {
                library_id: 3,
                depends_on_library_id: 2,
            },
        ];
        let build = SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
            &sources,
            &libraries,
            &dependencies,
            limits(64, 8),
        )
        .build_plan();
        let batch_limits = SourcePackJobBatchLimits {
            max_jobs_per_batch: 2,
            max_source_bytes_per_batch: 8,
            max_source_files_per_batch: 2,
        };
        let expected_job_batches = build
            .schedule
            .try_execution_batches(batch_limits)
            .expect("schedule source-pack job batches");
        let expected_batch_dependencies = build
            .schedule
            .try_batch_dependency_plan(&expected_job_batches)
            .expect("plan source-pack batch dependencies");
        let manifest = build.retained_build_artifact_manifest(batch_limits);
        let json = serde_json::to_string_pretty(&manifest)
            .expect("serialize source-pack build artifact manifest");
        let roundtrip = serde_json::from_str::<SourcePackBuildArtifactManifest>(&json)
            .expect("deserialize source-pack build artifact manifest");

        assert_eq!(roundtrip, manifest);
        assert_eq!(
            roundtrip.version,
            SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION
        );
        assert_eq!(roundtrip.job_schedule.jobs.len(), 7);
        assert_eq!(roundtrip.job_schedule.frontend_job_count(), 3);
        assert_eq!(roundtrip.job_schedule.codegen_job_count(), 3);
        assert_eq!(roundtrip.job_schedule.link_job_count(), 1);
        assert_eq!(roundtrip.target, SourcePackArtifactTarget::Generic);
        assert_eq!(roundtrip.job_batches, expected_job_batches);
        assert_eq!(roundtrip.batch_dependencies, expected_batch_dependencies);
        assert_eq!(
            roundtrip
                .batch_dependencies
                .ready_batch_indices_limited(&[], Some(1)),
            vec![0]
        );
        assert_eq!(roundtrip.artifacts.artifact_count(), 7);
        assert_eq!(roundtrip.job_artifacts.max_input_artifact_count(), 6);
        assert_eq!(roundtrip.job_artifact_io.max_input_artifact_count(), 6);
        assert_eq!(roundtrip.artifact_uses.max_consumer_count(), 4);
        assert_eq!(roundtrip.link_interface_batches.batch_count(), 2);
        assert_eq!(roundtrip.link_object_batches.batch_count(), 2);
        assert!(json.contains("dependency_batch_indices"));
        assert!(json.contains("library-interface/lib-1/job-0/src-0-1"));
        assert!(json.contains("linked-output/job-6/src-0-3"));
    }

    #[test]
    fn source_pack_build_plan_builds_compact_artifact_manifest_from_streamed_counts() {
        let sources = ["core", "math", "app"];
        let libraries = [1u32, 2, 3];
        let dependencies = [
            SourcePackLibraryDependency {
                library_id: 2,
                depends_on_library_id: 1,
            },
            SourcePackLibraryDependency {
                library_id: 3,
                depends_on_library_id: 2,
            },
        ];
        let plan = SourcePackJobPlan::from_source_pack_with_libraries_and_dependencies(
            &sources,
            &libraries,
            &dependencies,
            limits(64, 8),
        );
        let build = plan.build_plan();
        let batch_limits = SourcePackJobBatchLimits {
            max_jobs_per_batch: 2,
            max_source_bytes_per_batch: 8,
            max_source_files_per_batch: 2,
        };
        let full = build.retained_build_artifact_manifest(batch_limits);
        let compact = build.compact_build_artifact_manifest(batch_limits);
        let default_manifest = build.build_artifact_manifest(batch_limits);
        let try_default_manifest = build
            .try_build_artifact_manifest(batch_limits)
            .expect("default artifact manifest should use acyclic source-pack schedule");
        let direct_compact = plan
            .try_compact_build_artifact_manifest_for_schedule(
                &build.schedule,
                batch_limits,
                SourcePackArtifactTarget::Generic,
            )
            .expect("direct compact manifest should use acyclic source-pack schedule");

        assert_eq!(compact.version, full.version);
        assert_eq!(compact.target, full.target);
        assert_eq!(compact.job_count, full.job_count);
        assert_eq!(compact.job_batch_count, full.job_batch_count);
        assert_eq!(compact.batch_dependency_count, full.batch_dependency_count);
        assert_eq!(compact.artifact_count, full.artifact_count);
        assert_eq!(compact.job_artifact_count, full.job_artifact_count);
        assert_eq!(compact.job_artifact_io_count, full.job_artifact_io_count);
        assert_eq!(compact.artifact_use_count, full.artifact_use_count);
        assert_eq!(
            compact.link_interface_batch_count,
            full.link_interface_batch_count
        );
        assert_eq!(
            compact.link_object_batch_count,
            full.link_object_batch_count
        );
        assert_eq!(default_manifest, compact);
        assert_eq!(try_default_manifest, compact);
        assert_eq!(direct_compact.version, compact.version);
        assert_eq!(direct_compact.target, compact.target);
        assert_eq!(direct_compact.job_count, compact.job_count);
        assert_eq!(direct_compact.job_batch_count, compact.job_batch_count);
        assert_eq!(
            direct_compact.batch_dependency_count,
            compact.batch_dependency_count
        );
        assert_eq!(direct_compact.artifact_count, compact.artifact_count);
        assert_eq!(
            direct_compact.job_artifact_count,
            compact.job_artifact_count
        );
        assert_eq!(
            direct_compact.job_artifact_io_count,
            compact.job_artifact_io_count
        );
        assert_eq!(
            direct_compact.artifact_use_count,
            compact.artifact_use_count
        );
        assert_eq!(
            direct_compact.link_interface_batch_count,
            compact.link_interface_batch_count
        );
        assert_eq!(
            direct_compact.link_object_batch_count,
            compact.link_object_batch_count
        );
        assert!(compact.job_schedule.jobs.is_empty());
        assert!(compact.job_batches.batches.is_empty());
        assert!(compact.batch_dependencies.batches.is_empty());
        assert!(compact.artifacts.artifacts.is_empty());
        assert!(compact.job_artifacts.jobs.is_empty());
        assert!(compact.job_artifact_io.jobs.is_empty());
        assert!(compact.artifact_uses.uses.is_empty());
        assert!(compact.link_interface_batches.batches.is_empty());
        assert!(compact.link_object_batches.batches.is_empty());
        assert!(direct_compact.job_schedule.jobs.is_empty());
        assert!(direct_compact.job_batches.batches.is_empty());
        assert!(direct_compact.batch_dependencies.batches.is_empty());
        assert!(direct_compact.artifacts.artifacts.is_empty());
        assert!(direct_compact.job_artifacts.jobs.is_empty());
        assert!(direct_compact.job_artifact_io.jobs.is_empty());
        assert!(direct_compact.artifact_uses.uses.is_empty());
        assert!(direct_compact.link_interface_batches.batches.is_empty());
        assert!(direct_compact.link_object_batches.batches.is_empty());
    }

    #[test]
    fn source_pack_build_plan_target_qualifies_artifact_keys() {
        let sources = ["core", "app"];
        let libraries = [1u32, 2];
        let build =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(64, 8))
                .build_plan();
        let batch_limits = SourcePackJobBatchLimits {
            max_jobs_per_batch: 8,
            max_source_bytes_per_batch: 64,
            max_source_files_per_batch: 8,
        };
        let generic = build.retained_build_artifact_manifest(batch_limits);
        let wasm = build.retained_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::Wasm,
        );
        let x86 = build.retained_build_artifact_manifest_for_target(
            batch_limits,
            SourcePackArtifactTarget::X86_64,
        );

        assert_eq!(generic.target, SourcePackArtifactTarget::Generic);
        assert_eq!(wasm.target, SourcePackArtifactTarget::Wasm);
        assert_eq!(x86.target, SourcePackArtifactTarget::X86_64);
        assert_eq!(
            generic.artifacts.artifacts[0].key,
            "library-interface/lib-1/job-0/src-0-1"
        );
        assert_eq!(
            wasm.artifacts.artifacts[0].key,
            "wasm/library-interface/lib-1/job-0/src-0-1"
        );
        assert_eq!(
            x86.artifacts.artifacts[0].key,
            "x86_64/library-interface/lib-1/job-0/src-0-1"
        );
        assert_eq!(
            wasm.job_artifacts.jobs[0].outputs[0].key,
            wasm.artifacts.artifacts[0].key
        );
        assert_eq!(
            x86.job_artifacts.jobs[0].outputs[0].key,
            x86.artifacts.artifacts[0].key
        );
        assert_ne!(
            wasm.job_artifacts.jobs[0].outputs[0].key,
            x86.job_artifacts.jobs[0].outputs[0].key
        );
        assert!(
            wasm.artifacts
                .artifacts
                .iter()
                .all(|artifact| artifact.key.starts_with("wasm/"))
        );
        assert!(
            x86.artifacts
                .artifacts
                .iter()
                .all(|artifact| artifact.key.starts_with("x86_64/"))
        );
    }

    #[test]
    fn source_pack_build_artifact_manifest_shards_job_and_link_sections() {
        let sources = ["aaaa", "bbbb", "cccc", "dddd"];
        let libraries = [7u32, 7, 8, 8];
        let build =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(4, 8))
                .build_plan();
        let manifest = build.retained_build_artifact_manifest(SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 8,
            max_source_files_per_batch: 2,
        });
        let shard_limits = SourcePackBuildShardLimits {
            max_batches_per_shard: 2,
            max_jobs_per_shard: 2,
            max_artifacts_per_shard: 3,
        };
        let plan = manifest.build_artifact_shard_plan(shard_limits);
        let direct_index = manifest.build_artifact_shard_index(shard_limits);
        let mut streamed_shards = Vec::new();
        let streamed_index = manifest
            .try_for_each_build_artifact_shard(shard_limits, |shard| {
                streamed_shards.push(shard.clone());
                Ok::<(), ()>(())
            })
            .expect("stream build artifact shards");
        let index = &plan.index;

        assert_eq!(direct_index, plan.index);
        assert_eq!(streamed_index, plan.index);
        assert_eq!(streamed_shards, plan.shards);
        assert_eq!(
            index.version,
            SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION
        );
        assert_eq!(index.target, SourcePackArtifactTarget::Generic);
        assert_eq!(index.job_count, manifest.job_schedule.jobs.len());
        assert_eq!(index.job_batch_count, manifest.job_batches.batch_count());
        assert_eq!(index.artifact_count, manifest.artifacts.artifact_count());
        assert_eq!(
            index.link_interface_batch_count,
            manifest.link_interface_batches.batch_count()
        );
        assert_eq!(
            index.link_object_batch_count,
            manifest.link_object_batches.batch_count()
        );
        assert_eq!(plan.oversized_shard_count(), 0);
        assert!(plan.max_shard_batch_count() <= 2);
        assert!(plan.max_shard_job_count() <= 2);
        assert!(plan.max_shard_artifact_count() <= 3);

        let job_batch_indices = plan
            .shards
            .iter()
            .filter(|shard| shard.kind == SourcePackBuildArtifactShardKind::JobBatches)
            .flat_map(|shard| shard.batch_indices.iter().copied())
            .collect::<Vec<_>>();
        let link_interface_batch_indices = plan
            .shards
            .iter()
            .filter(|shard| shard.kind == SourcePackBuildArtifactShardKind::LinkInterfaceBatches)
            .flat_map(|shard| shard.batch_indices.iter().copied())
            .collect::<Vec<_>>();
        let link_object_batch_indices = plan
            .shards
            .iter()
            .filter(|shard| shard.kind == SourcePackBuildArtifactShardKind::LinkObjectBatches)
            .flat_map(|shard| shard.batch_indices.iter().copied())
            .collect::<Vec<_>>();

        assert_eq!(
            job_batch_indices,
            (0..manifest.job_batches.batch_count()).collect::<Vec<_>>()
        );
        assert_eq!(
            link_interface_batch_indices,
            (0..manifest.link_interface_batches.batch_count()).collect::<Vec<_>>()
        );
        assert_eq!(
            link_object_batch_indices,
            (0..manifest.link_object_batches.batch_count()).collect::<Vec<_>>()
        );

        let link_job_index = manifest
            .job_schedule
            .jobs
            .iter()
            .find(|job| job.phase == SourcePackJobPhase::Link)
            .expect("link job")
            .job_index;
        let link_job_shard = plan
            .shards
            .iter()
            .find(|shard| {
                shard.kind == SourcePackBuildArtifactShardKind::JobBatches
                    && shard.job_indices.contains(&link_job_index)
            })
            .expect("link job shard");
        assert!(link_job_shard.input_artifact_indices.is_empty());
        assert_eq!(link_job_shard.output_artifact_indices, vec![6]);
    }

    #[test]
    fn source_pack_build_artifact_manifest_caps_shards_with_unbounded_caller_limits() {
        let batch_count = DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES + 1;
        let manifest = SourcePackBuildArtifactManifest {
            version: SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION,
            target: SourcePackArtifactTarget::Generic,
            job_count: 0,
            job_batch_count: batch_count,
            batch_dependency_count: 0,
            artifact_count: 0,
            job_artifact_count: 0,
            job_artifact_io_count: 0,
            artifact_use_count: 0,
            link_interface_batch_count: 0,
            link_object_batch_count: 0,
            job_schedule: Default::default(),
            job_batches: SourcePackJobBatchSchedule {
                batches: (0..batch_count)
                    .map(|batch_index| SourcePackJobBatch {
                        batch_index,
                        wave_index: 0,
                        job_indices: Vec::new(),
                        source_bytes: 0,
                        source_file_count: 0,
                        source_lines: 0,
                        oversized: false,
                    })
                    .collect(),
            },
            batch_dependencies: Default::default(),
            artifacts: Default::default(),
            job_artifacts: Default::default(),
            job_artifact_io: Default::default(),
            artifact_uses: Default::default(),
            link_interface_batches: Default::default(),
            link_object_batches: Default::default(),
        };

        let plan = manifest.build_artifact_shard_plan(SourcePackBuildShardLimits {
            max_batches_per_shard: usize::MAX,
            max_jobs_per_shard: usize::MAX,
            max_artifacts_per_shard: usize::MAX,
        });

        assert_eq!(plan.index.limits, SourcePackBuildShardLimits::default());
        assert_eq!(
            plan.max_shard_batch_count(),
            DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES
        );
        assert_eq!(
            plan.shards
                .iter()
                .filter(|shard| shard.kind == SourcePackBuildArtifactShardKind::JobBatches)
                .count(),
            2
        );
    }

    #[test]
    fn source_pack_build_artifact_shard_index_serializes_roundtrip() {
        let sources = ["core", "math", "app"];
        let libraries = [1u32, 2, 3];
        let build =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(4, 8))
                .build_plan();
        let manifest = build.retained_build_artifact_manifest(SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 4,
            max_source_files_per_batch: 1,
        });
        let index = manifest.build_artifact_shard_index(SourcePackBuildShardLimits {
            max_batches_per_shard: 1,
            max_jobs_per_shard: 1,
            max_artifacts_per_shard: 2,
        });
        let json = serde_json::to_string_pretty(&index)
            .expect("serialize source-pack build artifact shard index");
        let roundtrip = serde_json::from_str::<SourcePackBuildArtifactShardIndex>(&json)
            .expect("deserialize source-pack build artifact shard index");

        assert_eq!(roundtrip, index);
        assert!(!json.contains("\"shards\""));
        assert_eq!(roundtrip.shard_count(), index.shard_count());
    }

    #[test]
    fn source_pack_build_plan_splits_link_object_inputs_into_batches() {
        let sources = ["aaaa", "bbbb", "cccc"];
        let libraries = [5u32, 5, 9];
        let build =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(4, 8))
                .build_plan();
        let batches = build.link_object_batches(SourcePackJobBatchLimits {
            max_jobs_per_batch: 2,
            max_source_bytes_per_batch: 8,
            max_source_files_per_batch: 8,
        });

        assert_eq!(batches.batch_count(), 2);
        assert_eq!(batches.max_batch_object_count(), 2);
        assert_eq!(batches.max_batch_source_bytes(), 8);
        assert_eq!(batches.max_batch_source_files(), 2);
        assert_eq!(
            batches
                .batches
                .iter()
                .map(|batch| {
                    (
                        batch.batch_index,
                        batch.input_object_artifact_indices.clone(),
                        batch.source_bytes,
                        batch.source_file_count,
                    )
                })
                .collect::<Vec<_>>(),
            vec![(0, vec![2, 3], 8, 2), (1, vec![4], 4, 1)]
        );
    }

    #[test]
    fn source_pack_build_plan_splits_link_interface_inputs_into_batches() {
        let sources = ["aaaa", "bbbb", "cccc"];
        let libraries = [5u32, 5, 9];
        let build =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(4, 8))
                .build_plan();
        let batches = build.link_interface_batches(SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 8,
            max_source_files_per_batch: 8,
        });

        assert_eq!(batches.batch_count(), 2);
        assert_eq!(batches.max_batch_interface_count(), 1);
        assert_eq!(batches.max_batch_source_bytes(), 8);
        assert_eq!(batches.max_batch_source_files(), 2);
        assert_eq!(
            batches
                .batches
                .iter()
                .map(|batch| {
                    (
                        batch.batch_index,
                        batch.input_interface_artifact_indices.clone(),
                        batch.source_bytes,
                        batch.source_file_count,
                    )
                })
                .collect::<Vec<_>>(),
            vec![(0, vec![0], 8, 2), (1, vec![1], 4, 1)]
        );
    }

    #[test]
    fn source_pack_build_plan_streams_link_batches_without_collecting_all_batches() {
        let sources = ["aaaa", "bbbb", "cccc"];
        let libraries = [5u32, 5, 9];
        let build =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(4, 8))
                .build_plan();
        let batch_limits = SourcePackJobBatchLimits {
            max_jobs_per_batch: 1,
            max_source_bytes_per_batch: 8,
            max_source_files_per_batch: 8,
        };
        let mut interface_batches = Vec::new();
        let mut object_batches = Vec::new();

        let interface_count = build
            .try_for_each_link_interface_batch(batch_limits, |batch| {
                interface_batches.push((
                    batch.batch_index,
                    batch.input_interface_artifact_indices,
                    batch.source_bytes,
                    batch.source_file_count,
                ));
                Ok::<(), ()>(())
            })
            .expect("stream interface link batches");
        let object_count = build
            .try_for_each_link_object_batch(batch_limits, |batch| {
                object_batches.push((
                    batch.batch_index,
                    batch.input_object_artifact_indices,
                    batch.source_bytes,
                    batch.source_file_count,
                ));
                Ok::<(), ()>(())
            })
            .expect("stream object link batches");

        assert_eq!(interface_count, 2);
        assert_eq!(object_count, 3);
        assert_eq!(
            interface_batches,
            vec![(0, vec![0], 8, 2), (1, vec![1], 4, 1)]
        );
        assert_eq!(
            object_batches,
            vec![(0, vec![2], 4, 1), (1, vec![3], 4, 1), (2, vec![4], 4, 1)]
        );
    }

    #[test]
    fn source_pack_build_plan_caps_link_batch_input_records() {
        let input_count = SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE + 1;
        let sources = (0..input_count)
            .map(|source_index| format!("source-{source_index}"))
            .collect::<Vec<_>>();
        let libraries = (0..input_count as u32).collect::<Vec<_>>();
        let build =
            SourcePackJobPlan::from_source_pack_with_libraries(&sources, &libraries, limits(64, 1))
                .build_plan();
        let batch_limits = SourcePackJobBatchLimits {
            max_jobs_per_batch: input_count,
            max_source_bytes_per_batch: usize::MAX,
            max_source_files_per_batch: usize::MAX,
        };

        let interface_batches = build.link_interface_batches(batch_limits);
        let object_batches = build.link_object_batches(batch_limits);

        assert_eq!(interface_batches.batch_count(), 2);
        assert_eq!(
            interface_batches.batches[0]
                .input_interface_artifact_indices
                .len(),
            SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
        );
        assert_eq!(
            interface_batches.batches[1]
                .input_interface_artifact_indices
                .len(),
            1
        );
        assert_eq!(object_batches.batch_count(), 2);
        assert_eq!(
            object_batches.batches[0]
                .input_object_artifact_indices
                .len(),
            SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE
        );
        assert_eq!(
            object_batches.batches[1]
                .input_object_artifact_indices
                .len(),
            1
        );
    }

    #[test]
    fn source_pack_units_mark_oversized_single_files() {
        let sources = ["small", "this file is too large", "tiny"];
        let plan = CodegenUnitPlan::from_source_pack(&sources, limits(8, 8));

        assert_eq!(plan.unit_count(), 3);
        assert_eq!(plan.oversized_unit_count(), 1);
        assert!(plan.units[1].oversized_source_file);
        assert_eq!(plan.units[1].first_source_index, 1);
    }

    #[test]
    fn source_pack_units_split_on_file_count_budget() {
        let sources = ["a", "b", "c", "d", "e"];
        let plan = CodegenUnitPlan::from_source_pack(&sources, limits(64, 2));

        assert_eq!(
            plan.units
                .iter()
                .map(|unit| unit.source_file_count)
                .collect::<Vec<_>>(),
            vec![2, 2, 1]
        );
    }
}

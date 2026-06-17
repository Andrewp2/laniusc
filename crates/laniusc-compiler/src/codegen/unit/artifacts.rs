use super::*;

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
        artifact_index_count(
            self.input_interface_artifact_count,
            &self.input_interface_artifact_indices,
            &self.input_interface_artifact_ranges,
        )
    }

    pub fn input_object_artifact_count(&self) -> usize {
        artifact_index_count(
            self.input_object_artifact_count,
            &self.input_object_artifact_indices,
            &self.input_object_artifact_ranges,
        )
    }

    pub fn try_for_each_input_interface_artifact_index<F, E>(&self, visit: F) -> Result<usize, E>
    where
        F: FnMut(usize) -> Result<(), E>,
    {
        try_for_each_artifact_index(
            &self.input_interface_artifact_indices,
            &self.input_interface_artifact_ranges,
            visit,
        )
    }

    pub fn try_for_each_input_object_artifact_index<F, E>(&self, visit: F) -> Result<usize, E>
    where
        F: FnMut(usize) -> Result<(), E>,
    {
        try_for_each_artifact_index(
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
        artifact_index_count(
            self.input_interface_artifact_count,
            &self.input_interface_artifact_indices,
            &self.input_interface_artifact_ranges,
        )
    }

    pub fn input_object_artifact_count(&self) -> usize {
        artifact_index_count(
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

    pub(in crate::codegen::unit) fn record(&mut self, job: &SourcePackJobArtifactIo) {
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
            artifact_index_range_count(&self.input_interface_artifact_ranges);
        let input_object_artifact_range_count =
            artifact_index_range_count(&self.input_object_artifact_ranges);
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

    pub(in crate::codegen::unit) fn record(&mut self, batch: &SourcePackLinkInterfaceBatch) {
        self.record_batch_counts(
            batch.interface_count(),
            batch.source_bytes,
            batch.source_file_count,
        );
    }

    pub(in crate::codegen::unit) fn record_batch_counts(
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

    pub(in crate::codegen::unit) fn record(&mut self, batch: &SourcePackLinkObjectBatch) {
        self.record_batch_counts(
            batch.object_count(),
            batch.source_bytes,
            batch.source_file_count,
        );
    }

    pub(in crate::codegen::unit) fn record_batch_counts(
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

use serde::{Deserialize, Serialize};

use super::SourcePackHierarchicalLinkExecutionPage;
use crate::codegen::unit::{SourcePackArtifactTarget, SourcePackJob, SourcePackJobPhase};

pub const GPU_SOURCE_PACK_ARTIFACT_DESCRIPTOR_VERSION: u32 = 1;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum GpuSourcePackArtifactStage {
    LibraryInterface,
    CodegenObject,
    PartialLink,
    LinkedOutput,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct GpuSourcePackRecordArrayDescriptor {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub element_count: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub byte_len: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub storage_key: Option<String>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct GpuSourcePackDependencyInterfaceSummary {
    pub interface_count: usize,
    pub batch_count: usize,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct GpuSourcePackArtifactDescriptor {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub stage: GpuSourcePackArtifactStage,
    pub job_index: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub group_index: Option<usize>,
    pub phase: SourcePackJobPhase,
    pub library_id: u32,
    pub first_source_index: usize,
    pub source_file_count: usize,
    pub source_bytes: usize,
    #[serde(default)]
    pub source_lines: usize,
    pub dependency_interface_count: usize,
    #[serde(default)]
    pub dependency_codegen_object_count: usize,
    #[serde(default)]
    pub dependency_partial_link_count: usize,
    #[serde(default)]
    pub dependency_interface_batch_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub input_record_arrays: Vec<GpuSourcePackRecordArrayDescriptor>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub output_record_arrays: Vec<GpuSourcePackRecordArrayDescriptor>,
    pub record_arrays: Vec<GpuSourcePackRecordArrayDescriptor>,
}

impl GpuSourcePackRecordArrayDescriptor {
    pub fn pending(name: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            element_count: None,
            byte_len: None,
            storage_key: None,
        }
    }

    pub fn bounded(name: impl Into<String>, element_count: usize, byte_len: usize) -> Self {
        Self {
            name: name.into(),
            element_count: Some(element_count),
            byte_len: Some(byte_len),
            storage_key: None,
        }
    }
}

impl GpuSourcePackDependencyInterfaceSummary {
    pub fn counted(interface_count: usize, batch_count: usize) -> Self {
        Self {
            interface_count,
            batch_count,
        }
    }

    pub fn add_batch(&mut self, interface_count: usize) {
        if interface_count == 0 {
            return;
        }
        self.interface_count = self.interface_count.saturating_add(interface_count);
        self.batch_count = self.batch_count.saturating_add(1);
    }
}

impl GpuSourcePackArtifactDescriptor {
    pub(super) fn combined_record_arrays(
        input_record_arrays: &[GpuSourcePackRecordArrayDescriptor],
        output_record_arrays: &[GpuSourcePackRecordArrayDescriptor],
    ) -> Vec<GpuSourcePackRecordArrayDescriptor> {
        input_record_arrays
            .iter()
            .chain(output_record_arrays.iter())
            .cloned()
            .collect()
    }

    pub fn library_interface_for_job(
        target: SourcePackArtifactTarget,
        job: &SourcePackJob,
        dependency_interfaces: GpuSourcePackDependencyInterfaceSummary,
    ) -> Self {
        let input_record_arrays = vec![
            GpuSourcePackRecordArrayDescriptor::bounded(
                "source_file_records",
                job.source_file_count,
                job.source_bytes,
            ),
            GpuSourcePackRecordArrayDescriptor::pending("dependency_semantic_interface_records"),
        ];
        let output_record_arrays = vec![
            GpuSourcePackRecordArrayDescriptor::pending("token_records"),
            GpuSourcePackRecordArrayDescriptor::pending("parse_tree_records"),
            GpuSourcePackRecordArrayDescriptor::pending("hir_node_records"),
            GpuSourcePackRecordArrayDescriptor::pending("resolver_records"),
            GpuSourcePackRecordArrayDescriptor::pending("type_instance_records"),
            GpuSourcePackRecordArrayDescriptor::pending("semantic_interface_records"),
        ];
        let record_arrays =
            Self::combined_record_arrays(&input_record_arrays, &output_record_arrays);
        Self {
            version: GPU_SOURCE_PACK_ARTIFACT_DESCRIPTOR_VERSION,
            target,
            stage: GpuSourcePackArtifactStage::LibraryInterface,
            job_index: job.job_index,
            group_index: None,
            phase: job.phase,
            library_id: job.library_id,
            first_source_index: job.first_source_index,
            source_file_count: job.source_file_count,
            source_bytes: job.source_bytes,
            source_lines: job.source_lines,
            dependency_interface_count: dependency_interfaces.interface_count,
            dependency_codegen_object_count: 0,
            dependency_partial_link_count: 0,
            dependency_interface_batch_count: dependency_interfaces.batch_count,
            input_record_arrays,
            output_record_arrays,
            record_arrays,
        }
    }

    pub fn codegen_object_contract_for_job(
        target: SourcePackArtifactTarget,
        job: &SourcePackJob,
        dependency_interfaces: GpuSourcePackDependencyInterfaceSummary,
    ) -> Self {
        let input_record_arrays = vec![
            GpuSourcePackRecordArrayDescriptor::pending("attributed_hir_records"),
            GpuSourcePackRecordArrayDescriptor::pending("resolver_records"),
            GpuSourcePackRecordArrayDescriptor::pending("type_instance_records"),
            GpuSourcePackRecordArrayDescriptor::pending("literal_records"),
            GpuSourcePackRecordArrayDescriptor::pending("dependency_semantic_interface_records"),
        ];
        let output_record_arrays = vec![
            GpuSourcePackRecordArrayDescriptor::pending("node_instruction_count_records"),
            GpuSourcePackRecordArrayDescriptor::pending("instruction_location_records"),
            GpuSourcePackRecordArrayDescriptor::pending("virtual_instruction_records"),
            GpuSourcePackRecordArrayDescriptor::pending("virtual_register_records"),
            GpuSourcePackRecordArrayDescriptor::pending("relocation_records"),
        ];
        let record_arrays =
            Self::combined_record_arrays(&input_record_arrays, &output_record_arrays);
        Self {
            version: GPU_SOURCE_PACK_ARTIFACT_DESCRIPTOR_VERSION,
            target,
            stage: GpuSourcePackArtifactStage::CodegenObject,
            job_index: job.job_index,
            group_index: None,
            phase: job.phase,
            library_id: job.library_id,
            first_source_index: job.first_source_index,
            source_file_count: job.source_file_count,
            source_bytes: job.source_bytes,
            source_lines: job.source_lines,
            dependency_interface_count: dependency_interfaces.interface_count,
            dependency_codegen_object_count: 0,
            dependency_partial_link_count: 0,
            dependency_interface_batch_count: dependency_interfaces.batch_count,
            input_record_arrays,
            output_record_arrays,
            record_arrays,
        }
    }

    pub fn linked_output_contract_for_job(
        target: SourcePackArtifactTarget,
        job: &SourcePackJob,
        dependency_interface_count: usize,
        dependency_codegen_object_count: usize,
    ) -> Self {
        let input_record_arrays = vec![
            GpuSourcePackRecordArrayDescriptor::pending("allocated_instruction_records"),
            GpuSourcePackRecordArrayDescriptor::pending("function_offset_records"),
            GpuSourcePackRecordArrayDescriptor::pending("link_relocation_records"),
        ];
        let output_record_arrays = vec![GpuSourcePackRecordArrayDescriptor::pending(
            "emitted_byte_records",
        )];
        let record_arrays =
            Self::combined_record_arrays(&input_record_arrays, &output_record_arrays);
        Self {
            version: GPU_SOURCE_PACK_ARTIFACT_DESCRIPTOR_VERSION,
            target,
            stage: GpuSourcePackArtifactStage::LinkedOutput,
            job_index: job.job_index,
            group_index: None,
            phase: job.phase,
            library_id: job.library_id,
            first_source_index: job.first_source_index,
            source_file_count: job.source_file_count,
            source_bytes: job.source_bytes,
            source_lines: job.source_lines,
            dependency_interface_count,
            dependency_codegen_object_count,
            dependency_partial_link_count: 0,
            dependency_interface_batch_count: 0,
            input_record_arrays,
            output_record_arrays,
            record_arrays,
        }
    }

    pub fn partial_link_contract_for_page(
        page: &SourcePackHierarchicalLinkExecutionPage,
        dependency_interface_count: usize,
        dependency_codegen_object_count: usize,
        dependency_partial_link_count: usize,
    ) -> Self {
        let input_record_arrays = vec![
            GpuSourcePackRecordArrayDescriptor::pending("allocated_instruction_records"),
            GpuSourcePackRecordArrayDescriptor::pending("function_offset_records"),
            GpuSourcePackRecordArrayDescriptor::pending("link_relocation_records"),
            GpuSourcePackRecordArrayDescriptor::pending("input_partial_link_relocation_records"),
        ];
        let output_record_arrays = vec![GpuSourcePackRecordArrayDescriptor::pending(
            "partial_link_relocation_records",
        )];
        let record_arrays =
            Self::combined_record_arrays(&input_record_arrays, &output_record_arrays);
        Self {
            version: GPU_SOURCE_PACK_ARTIFACT_DESCRIPTOR_VERSION,
            target: page.target,
            stage: GpuSourcePackArtifactStage::PartialLink,
            job_index: page.job_index,
            group_index: Some(page.group_index),
            phase: SourcePackJobPhase::Link,
            library_id: 0,
            first_source_index: 0,
            source_file_count: page.source_file_count,
            source_bytes: page.source_byte_count,
            source_lines: page.source_line_count,
            dependency_interface_count,
            dependency_codegen_object_count,
            dependency_partial_link_count,
            dependency_interface_batch_count: 0,
            input_record_arrays,
            output_record_arrays,
            record_arrays,
        }
    }

    pub fn hierarchical_linked_output_contract_for_page(
        page: &SourcePackHierarchicalLinkExecutionPage,
        dependency_interface_count: usize,
        dependency_codegen_object_count: usize,
        dependency_partial_link_count: usize,
    ) -> Self {
        let input_record_arrays = vec![
            GpuSourcePackRecordArrayDescriptor::pending("allocated_instruction_records"),
            GpuSourcePackRecordArrayDescriptor::pending("function_offset_records"),
            GpuSourcePackRecordArrayDescriptor::pending("link_relocation_records"),
            GpuSourcePackRecordArrayDescriptor::pending("partial_link_relocation_records"),
        ];
        let output_record_arrays = vec![GpuSourcePackRecordArrayDescriptor::pending(
            "emitted_byte_records",
        )];
        let record_arrays =
            Self::combined_record_arrays(&input_record_arrays, &output_record_arrays);
        Self {
            version: GPU_SOURCE_PACK_ARTIFACT_DESCRIPTOR_VERSION,
            target: page.target,
            stage: GpuSourcePackArtifactStage::LinkedOutput,
            job_index: page.job_index,
            group_index: Some(page.group_index),
            phase: SourcePackJobPhase::Link,
            library_id: 0,
            first_source_index: 0,
            source_file_count: page.source_file_count,
            source_bytes: page.source_byte_count,
            source_lines: page.source_line_count,
            dependency_interface_count,
            dependency_codegen_object_count,
            dependency_partial_link_count,
            dependency_interface_batch_count: 0,
            input_record_arrays,
            output_record_arrays,
            record_arrays,
        }
    }
}

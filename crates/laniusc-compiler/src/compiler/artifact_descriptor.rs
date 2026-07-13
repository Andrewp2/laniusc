use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};

use super::{SourcePackHierarchicalLinkExecutionPage, SourcePackLinkDescriptorSummary};
use crate::codegen::unit::{SourcePackArtifactTarget, SourcePackJob, SourcePackJobPhase};

/// Version of the persisted source-pack artifact descriptor JSON contract.
pub const GPU_SOURCE_PACK_ARTIFACT_DESCRIPTOR_VERSION: u32 = 1;
/// Version of runtime ABI metadata embedded in artifact descriptors.
pub const GPU_SOURCE_PACK_RUNTIME_ABI_METADATA_VERSION: u32 = 1;
/// Sentinel ABI version used when no runtime ABI has been selected.
pub const GPU_SOURCE_PACK_UNKNOWN_RUNTIME_ABI_VERSION: u32 = 0;
/// Current runtime ABI version required by runtime-bound artifact descriptors.
pub const GPU_SOURCE_PACK_RUNTIME_ABI_VERSION: u32 = 1;
/// Runtime service id for allocation APIs.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_ALLOCATOR_ID: u32 = 1;
/// Runtime service id for filesystem APIs.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_FILESYSTEM_ID: u32 = 2;
/// Runtime service id for standard input/output APIs.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID: u32 = 3;
/// Runtime service id for clock and time APIs.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_CLOCK_ID: u32 = 4;
/// Runtime service id for networking APIs.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_NETWORK_ID: u32 = 5;
/// Runtime service id for panic hook APIs.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_PANIC_HOOK_ID: u32 = 6;
/// Runtime service id for generic host-service APIs.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_HOST_SERVICES_ID: u32 = 7;
/// Runtime service id for threading APIs.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_THREADS_ID: u32 = 8;
/// Runtime service id for secure random-number APIs.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_SECURE_RNG_ID: u32 = 9;
/// Runtime service id for host GPU APIs.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_GPU_ID: u32 = 10;
/// Runtime service id for process APIs.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_PROCESS_ID: u32 = 11;
/// Runtime service id for environment-variable APIs.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_ENV_ID: u32 = 12;
/// Runtime service id for test-harness APIs.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_TEST_HARNESS_ID: u32 = 13;
/// Number of runtime services known by the descriptor contract.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_COUNT: usize = 13;
/// Runtime service status used when availability has not been determined.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_STATUS_UNKNOWN: u32 = 0;
/// Runtime service status used when a required service has no executable binding.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_STATUS_UNAVAILABLE: u32 = 1;
/// Runtime service status used when a required service has an executable binding.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_STATUS_AVAILABLE: u32 = 2;
/// First valid runtime service id in the contiguous service id range.
pub const GPU_SOURCE_PACK_FIRST_RUNTIME_SERVICE_ID: u32 =
    GPU_SOURCE_PACK_RUNTIME_SERVICE_ALLOCATOR_ID;
/// Last valid runtime service id in the contiguous service id range.
pub const GPU_SOURCE_PACK_LAST_RUNTIME_SERVICE_ID: u32 =
    GPU_SOURCE_PACK_RUNTIME_SERVICE_TEST_HARNESS_ID;
const GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_ROW_BYTE_LEN: usize = 12;
/// Ordered runtime service ids known by the source-pack descriptor contract.
pub const GPU_SOURCE_PACK_RUNTIME_SERVICE_IDS: [u32; GPU_SOURCE_PACK_RUNTIME_SERVICE_COUNT] = [
    GPU_SOURCE_PACK_RUNTIME_SERVICE_ALLOCATOR_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_FILESYSTEM_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_CLOCK_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_NETWORK_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_PANIC_HOOK_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_HOST_SERVICES_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_THREADS_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_SECURE_RNG_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_GPU_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_PROCESS_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_ENV_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_TEST_HARNESS_ID,
];

const GPU_SOURCE_PACK_TARGET_BYTE_RECORD_ARRAYS: &[&str] = &[
    "emitted_byte_records",
    "x86_file_bytes",
    "x86_packed_file_words",
    "wasm_module_bytes",
];
const GPU_SOURCE_PACK_LIBRARY_INTERFACE_OUTPUT_RECORD_ARRAYS: &[&str] = &[
    "token_records",
    "parse_tree_records",
    "hir_node_records",
    "resolver_records",
    "type_instance_records",
    "semantic_interface_records",
];
const GPU_SOURCE_PACK_OBJECT_OUTPUT_RECORD_ARRAYS: &[&str] = &[
    "object_section_records",
    "object_symbol_records",
    "node_instruction_count_records",
    "instruction_location_records",
    "virtual_instruction_records",
    "virtual_register_records",
    "relocation_records",
];
const GPU_SOURCE_PACK_PARTIAL_LINK_OUTPUT_RECORD_ARRAYS: &[&str] = &[
    "partial_link_section_records",
    "partial_link_symbol_records",
    "partial_link_unresolved_symbol_records",
    "partial_link_relocation_records",
];
const GPU_SOURCE_PACK_LINKED_OUTPUT_RECORD_ARRAYS: &[&str] =
    &["linked_section_records", "linked_symbol_records"];
const GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_RECORD_ARRAY: &str =
    "runtime_service_requirement_records";
const GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_DESCRIPTOR_RECORD: &str =
    "runtime_service_requirements";

/// Stage that produced or will consume a source-pack artifact descriptor.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum GpuSourcePackArtifactStage {
    /// Library frontend interface artifact.
    LibraryInterface,
    /// Target codegen object artifact.
    CodegenObject,
    /// Intermediate hierarchical-link artifact.
    PartialLink,
    /// Final linked output artifact.
    LinkedOutput,
}

impl GpuSourcePackArtifactStage {
    /// Returns the source-pack job phase that is valid for this artifact stage.
    pub fn expected_phase(self) -> SourcePackJobPhase {
        match self {
            Self::LibraryInterface => SourcePackJobPhase::LibraryFrontend,
            Self::CodegenObject => SourcePackJobPhase::Codegen,
            Self::PartialLink | Self::LinkedOutput => SourcePackJobPhase::Link,
        }
    }

    fn output_record_domain(self) -> GpuSourcePackDescriptorRecordDomain {
        match self {
            Self::LibraryInterface => GpuSourcePackDescriptorRecordDomain::Interface,
            Self::CodegenObject => GpuSourcePackDescriptorRecordDomain::Object,
            Self::PartialLink => GpuSourcePackDescriptorRecordDomain::PartialLink,
            Self::LinkedOutput => GpuSourcePackDescriptorRecordDomain::LinkedOutput,
        }
    }
}

/// Descriptor for one named record array carried by an artifact.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct GpuSourcePackRecordArrayDescriptor {
    /// Stable logical array name.
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    /// Number of records, if known when the descriptor is written.
    pub element_count: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    /// Number of bytes, if known when the descriptor is written.
    pub byte_len: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    /// Store key for arrays persisted separately from the descriptor.
    pub storage_key: Option<String>,
}

/// Semantic domain for a descriptor record.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum GpuSourcePackDescriptorRecordDomain {
    /// Library-interface symbol/metadata records.
    Interface,
    /// Codegen object records.
    Object,
    /// Intermediate hierarchical-link records.
    PartialLink,
    /// Final linked-output records.
    LinkedOutput,
}

/// Semantic kind for a descriptor record.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum GpuSourcePackDescriptorRecordKind {
    /// Section or segment record.
    Section,
    /// Symbol record.
    Symbol,
    /// Unresolved-symbol record.
    UnresolvedSymbol,
    /// Relocation record.
    Relocation,
    /// Runtime-service requirement record.
    RuntimeService,
}

/// Direction of a descriptor record relative to artifact execution.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum GpuSourcePackDescriptorRecordFlow {
    /// Record array consumed as an input.
    Input,
    /// Record array produced as an output.
    Output,
}

/// Semantic row that maps a record array to a domain/kind/flow contract.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct GpuSourcePackDescriptorRecord {
    /// Stable record name within the descriptor.
    pub name: String,
    /// Semantic record domain.
    pub domain: GpuSourcePackDescriptorRecordDomain,
    /// Semantic record kind.
    pub kind: GpuSourcePackDescriptorRecordKind,
    /// Input/output flow for artifact execution.
    pub flow: GpuSourcePackDescriptorRecordFlow,
    /// Name of the record array that stores this record family.
    pub record_array: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    /// Number of records for this semantic row, when known.
    pub element_count: Option<usize>,
}

/// Requirement row for one runtime service used by a source-pack artifact.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct GpuSourcePackRuntimeServiceRequirement {
    /// Stable runtime service id.
    pub service_id: u32,
    /// Runtime ABI version required by the artifact.
    pub required_abi_version: u32,
    /// Current service status encoded in the descriptor.
    pub service_status: u32,
}

/// Runtime ABI summary embedded when an artifact requires runtime services.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct GpuSourcePackRuntimeAbiMetadata {
    /// Runtime ABI metadata schema version.
    pub metadata_version: u32,
    /// Runtime ABI version required by the descriptor.
    pub abi_version: u32,
    /// Number of services known by this ABI.
    pub service_count: u32,
    /// First valid service id.
    pub first_service_id: u32,
    /// Last valid service id.
    pub last_service_id: u32,
}

/// Counts dependency library-interface inputs across direct descriptor batches.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct GpuSourcePackDependencyInterfaceSummary {
    /// Number of dependency interface artifacts.
    pub interface_count: usize,
    /// Number of batches that contributed those interfaces.
    pub batch_count: usize,
}

/// JSON descriptor for a source-pack artifact contract.
///
/// Descriptors are emitted for library-interface, codegen-object, partial-link,
/// and linked-output artifacts. They let CLI output validation, source-pack
/// workers, and downstream tools check the artifact shape without interpreting
/// backend-specific bytes directly.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct GpuSourcePackArtifactDescriptor {
    /// Descriptor schema version.
    pub version: u32,
    /// Artifact target.
    pub target: SourcePackArtifactTarget,
    /// Descriptor stage.
    pub stage: GpuSourcePackArtifactStage,
    /// Global source-pack job index.
    pub job_index: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    /// Hierarchical link group index, when this descriptor belongs to a group.
    pub group_index: Option<usize>,
    /// Source-pack job phase expected for `stage`.
    pub phase: SourcePackJobPhase,
    /// Owning library id for job-backed descriptors.
    pub library_id: u32,
    /// First source index covered by the artifact.
    pub first_source_index: usize,
    /// Number of source files covered by the artifact.
    pub source_file_count: usize,
    /// Number of source bytes covered by the artifact.
    pub source_bytes: usize,
    #[serde(default)]
    /// Number of source lines covered by the artifact.
    pub source_lines: usize,
    /// Number of dependency interface artifacts consumed.
    pub dependency_interface_count: usize,
    #[serde(default)]
    /// Number of dependency codegen-object artifacts consumed.
    pub dependency_codegen_object_count: usize,
    #[serde(default)]
    /// Number of dependency partial-link artifacts consumed.
    pub dependency_partial_link_count: usize,
    #[serde(default)]
    /// Number of interface-input batches consumed.
    pub dependency_interface_batch_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    /// Record arrays consumed by the artifact.
    pub input_record_arrays: Vec<GpuSourcePackRecordArrayDescriptor>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    /// Record arrays produced by the artifact.
    pub output_record_arrays: Vec<GpuSourcePackRecordArrayDescriptor>,
    /// Input arrays followed by output arrays.
    pub record_arrays: Vec<GpuSourcePackRecordArrayDescriptor>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    /// Semantic records that describe important arrays.
    pub descriptor_records: Vec<GpuSourcePackDescriptorRecord>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    /// Runtime ABI version required by this artifact, if any.
    pub required_runtime_abi_version: Option<u32>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    /// Sorted runtime service ids required by this artifact.
    pub required_runtime_service_ids: Vec<u32>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    /// Runtime service requirement rows required by this artifact.
    pub required_runtime_services: Vec<GpuSourcePackRuntimeServiceRequirement>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    /// Runtime ABI metadata, present only when runtime services are required.
    pub runtime_abi: Option<GpuSourcePackRuntimeAbiMetadata>,
}

impl GpuSourcePackRecordArrayDescriptor {
    /// Creates a descriptor for an array whose final size is not known yet.
    pub fn pending(name: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            element_count: None,
            byte_len: None,
            storage_key: None,
        }
    }

    /// Creates a descriptor for an array with a known element count and byte length.
    pub fn bounded(name: impl Into<String>, element_count: usize, byte_len: usize) -> Self {
        Self {
            name: name.into(),
            element_count: Some(element_count),
            byte_len: Some(byte_len),
            storage_key: None,
        }
    }
}

impl GpuSourcePackDescriptorRecord {
    /// Creates a descriptor-record row without an attached element count.
    pub fn new(
        name: impl Into<String>,
        domain: GpuSourcePackDescriptorRecordDomain,
        kind: GpuSourcePackDescriptorRecordKind,
        flow: GpuSourcePackDescriptorRecordFlow,
        record_array: impl Into<String>,
    ) -> Self {
        Self {
            name: name.into(),
            domain,
            kind,
            flow,
            record_array: record_array.into(),
            element_count: None,
        }
    }
}

impl GpuSourcePackRuntimeServiceRequirement {
    /// Creates a fail-closed runtime requirement for a known service id.
    ///
    /// The service starts as unavailable because the descriptor records the
    /// contract requirement, not proof that the runtime binding has been supplied.
    pub fn contract_only(service_id: u32) -> Self {
        Self {
            service_id,
            required_abi_version: GPU_SOURCE_PACK_RUNTIME_ABI_VERSION,
            service_status: GPU_SOURCE_PACK_RUNTIME_SERVICE_STATUS_UNAVAILABLE,
        }
    }

    /// Creates a requirement row using the compiler's current binding status.
    pub fn current(service_id: u32) -> Self {
        Self {
            service_id,
            required_abi_version: GPU_SOURCE_PACK_RUNTIME_ABI_VERSION,
            service_status: runtime_service_status(service_id),
        }
    }
}

const fn runtime_service_status(service_id: u32) -> u32 {
    if service_id == GPU_SOURCE_PACK_RUNTIME_SERVICE_ALLOCATOR_ID
        || service_id == GPU_SOURCE_PACK_RUNTIME_SERVICE_FILESYSTEM_ID
        || service_id == GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID
        || service_id == GPU_SOURCE_PACK_RUNTIME_SERVICE_CLOCK_ID
        || service_id == GPU_SOURCE_PACK_RUNTIME_SERVICE_SECURE_RNG_ID
        || service_id == GPU_SOURCE_PACK_RUNTIME_SERVICE_PROCESS_ID
        || service_id == GPU_SOURCE_PACK_RUNTIME_SERVICE_ENV_ID
    {
        GPU_SOURCE_PACK_RUNTIME_SERVICE_STATUS_AVAILABLE
    } else {
        GPU_SOURCE_PACK_RUNTIME_SERVICE_STATUS_UNAVAILABLE
    }
}

impl GpuSourcePackRuntimeAbiMetadata {
    /// Returns metadata for the runtime ABI version understood by this compiler.
    pub fn current() -> Self {
        Self {
            metadata_version: GPU_SOURCE_PACK_RUNTIME_ABI_METADATA_VERSION,
            abi_version: GPU_SOURCE_PACK_RUNTIME_ABI_VERSION,
            service_count: GPU_SOURCE_PACK_RUNTIME_SERVICE_COUNT as u32,
            first_service_id: GPU_SOURCE_PACK_FIRST_RUNTIME_SERVICE_ID,
            last_service_id: GPU_SOURCE_PACK_LAST_RUNTIME_SERVICE_ID,
        }
    }
}

impl GpuSourcePackDependencyInterfaceSummary {
    /// Creates a summary from explicit interface and batch counts.
    pub fn counted(interface_count: usize, batch_count: usize) -> Self {
        Self {
            interface_count,
            batch_count,
        }
    }

    /// Adds one nonempty dependency-interface batch to the summary.
    pub fn add_batch(&mut self, interface_count: usize) {
        if interface_count == 0 {
            return;
        }
        self.interface_count = self.interface_count.saturating_add(interface_count);
        self.batch_count = self.batch_count.saturating_add(1);
    }
}

impl GpuSourcePackArtifactDescriptor {
    /// Validates the internal consistency of this descriptor.
    ///
    /// This checks the descriptor version, stage/phase pairing, link-group
    /// requirements, record-array references, runtime-service rows, and linked
    /// output target-byte policy.
    pub fn validate_contract(&self) -> Result<(), String> {
        if self.version != GPU_SOURCE_PACK_ARTIFACT_DESCRIPTOR_VERSION {
            return Err(format!(
                "descriptor version {} is unsupported; expected {}",
                self.version, GPU_SOURCE_PACK_ARTIFACT_DESCRIPTOR_VERSION
            ));
        }

        let expected_phase = self.stage.expected_phase();
        if self.phase != expected_phase {
            return Err(format!(
                "descriptor stage {:?} has phase {:?}; expected {:?}",
                self.stage, self.phase, expected_phase
            ));
        }

        match self.stage {
            GpuSourcePackArtifactStage::LibraryInterface
            | GpuSourcePackArtifactStage::CodegenObject => {
                if self.group_index.is_some() {
                    return Err(format!(
                        "descriptor stage {:?} must not carry a hierarchical link group",
                        self.stage
                    ));
                }
                if self.dependency_codegen_object_count != 0 {
                    return Err(format!(
                        "descriptor stage {:?} records {} codegen-object dependencies",
                        self.stage, self.dependency_codegen_object_count
                    ));
                }
                if self.dependency_partial_link_count != 0 {
                    return Err(format!(
                        "descriptor stage {:?} records {} partial-link dependencies",
                        self.stage, self.dependency_partial_link_count
                    ));
                }
            }
            GpuSourcePackArtifactStage::PartialLink => {
                if self.group_index.is_none() {
                    return Err(
                        "partial-link descriptor must carry a hierarchical link group".into(),
                    );
                }
            }
            GpuSourcePackArtifactStage::LinkedOutput => {
                if self.dependency_partial_link_count != 0 && self.group_index.is_none() {
                    return Err(
                        "linked-output descriptor with partial-link dependencies must carry a hierarchical link group"
                            .into(),
                    );
                }
            }
        }

        if self.dependency_interface_batch_count > self.dependency_interface_count {
            return Err(format!(
                "descriptor records {} dependency interface batches for {} interfaces",
                self.dependency_interface_batch_count, self.dependency_interface_count
            ));
        }

        validate_record_array_descriptors("input", &self.input_record_arrays)?;
        validate_record_array_descriptors("output", &self.output_record_arrays)?;
        validate_record_array_descriptors("combined", &self.record_arrays)?;

        if !self.input_record_arrays.is_empty() || !self.output_record_arrays.is_empty() {
            let expected_record_arrays =
                Self::combined_record_arrays(&self.input_record_arrays, &self.output_record_arrays);
            if self.record_arrays != expected_record_arrays {
                return Err(
                    "descriptor combined record arrays must equal input arrays followed by output arrays"
                        .into(),
                );
            }
        }

        self.validate_input_record_array_domains()?;
        self.validate_descriptor_records()?;
        self.validate_required_runtime_services()?;
        self.validate_linked_output_target_byte_records()?;

        Ok(())
    }

    /// Replaces runtime-service requirements with a sorted, deduplicated service id list.
    pub fn set_required_runtime_services<I>(&mut self, service_ids: I)
    where
        I: IntoIterator<Item = u32>,
    {
        self.required_runtime_service_ids = service_ids.into_iter().collect();
        self.required_runtime_service_ids.sort_unstable();
        self.required_runtime_service_ids.dedup();
        self.required_runtime_services = self
            .required_runtime_service_ids
            .iter()
            .copied()
            .map(GpuSourcePackRuntimeServiceRequirement::current)
            .collect();
        self.required_runtime_abi_version = if self.required_runtime_service_ids.is_empty() {
            None
        } else {
            Some(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION)
        };
        self.runtime_abi = if self.required_runtime_service_ids.is_empty() {
            None
        } else {
            Some(GpuSourcePackRuntimeAbiMetadata::current())
        };
        self.sync_runtime_service_requirement_record_contract();
    }

    /// Returns this descriptor after setting runtime-service requirements.
    pub fn with_required_runtime_services<I>(mut self, service_ids: I) -> Self
    where
        I: IntoIterator<Item = u32>,
    {
        self.set_required_runtime_services(service_ids);
        self
    }

    /// Validates the descriptor and then checks the expected stage and target.
    pub fn validate_contract_for(
        &self,
        expected_stage: GpuSourcePackArtifactStage,
        expected_target: Option<SourcePackArtifactTarget>,
    ) -> Result<(), String> {
        self.validate_contract()?;
        if self.stage != expected_stage {
            return Err(format!(
                "descriptor stage {:?}; expected {:?}",
                self.stage, expected_stage
            ));
        }
        if let Some(expected_target) = expected_target
            && self.target != expected_target
        {
            return Err(format!(
                "descriptor target {:?}; expected {:?}",
                self.target, expected_target
            ));
        }
        Ok(())
    }

    /// Concatenates input record arrays followed by output record arrays.
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

    fn validate_descriptor_records(&self) -> Result<(), String> {
        validate_descriptor_record_refs(
            &self.record_arrays,
            &self.input_record_arrays,
            &self.output_record_arrays,
            &self.descriptor_records,
        )?;
        self.validate_dependency_input_records()?;
        match self.stage {
            GpuSourcePackArtifactStage::LibraryInterface => {
                require_descriptor_record(
                    self,
                    GpuSourcePackDescriptorRecordDomain::Interface,
                    GpuSourcePackDescriptorRecordKind::Symbol,
                    GpuSourcePackDescriptorRecordFlow::Output,
                    "library-interface descriptor must describe output interface symbols",
                )?;
                reject_descriptor_record_kind(
                    self,
                    GpuSourcePackDescriptorRecordKind::Section,
                    "library-interface descriptor must not describe object sections",
                )?;
                reject_descriptor_record_kind(
                    self,
                    GpuSourcePackDescriptorRecordKind::UnresolvedSymbol,
                    "library-interface descriptor must not describe unresolved symbols",
                )?;
                reject_descriptor_record_kind(
                    self,
                    GpuSourcePackDescriptorRecordKind::Relocation,
                    "library-interface descriptor must not describe relocations",
                )?;
                reject_descriptor_domain(
                    self,
                    GpuSourcePackDescriptorRecordDomain::Object,
                    "library-interface descriptor must not describe object records",
                )?;
                reject_descriptor_domain(
                    self,
                    GpuSourcePackDescriptorRecordDomain::PartialLink,
                    "library-interface descriptor must not describe partial-link records",
                )?;
                reject_descriptor_domain(
                    self,
                    GpuSourcePackDescriptorRecordDomain::LinkedOutput,
                    "library-interface descriptor must not describe linked-output records",
                )?;
            }
            GpuSourcePackArtifactStage::CodegenObject => {
                require_descriptor_record(
                    self,
                    GpuSourcePackDescriptorRecordDomain::Object,
                    GpuSourcePackDescriptorRecordKind::Section,
                    GpuSourcePackDescriptorRecordFlow::Output,
                    "codegen-object descriptor must describe output object sections",
                )?;
                require_descriptor_record(
                    self,
                    GpuSourcePackDescriptorRecordDomain::Object,
                    GpuSourcePackDescriptorRecordKind::Symbol,
                    GpuSourcePackDescriptorRecordFlow::Output,
                    "codegen-object descriptor must describe output object symbols",
                )?;
                require_descriptor_record(
                    self,
                    GpuSourcePackDescriptorRecordDomain::Object,
                    GpuSourcePackDescriptorRecordKind::Relocation,
                    GpuSourcePackDescriptorRecordFlow::Output,
                    "codegen-object descriptor must describe output object relocations",
                )?;
                reject_descriptor_record_kind(
                    self,
                    GpuSourcePackDescriptorRecordKind::UnresolvedSymbol,
                    "codegen-object descriptor must not describe unresolved symbols",
                )?;
                reject_descriptor_domain(
                    self,
                    GpuSourcePackDescriptorRecordDomain::PartialLink,
                    "codegen-object descriptor must not describe partial-link records",
                )?;
                reject_descriptor_domain(
                    self,
                    GpuSourcePackDescriptorRecordDomain::LinkedOutput,
                    "codegen-object descriptor must not describe linked-output records",
                )?;
            }
            GpuSourcePackArtifactStage::PartialLink => {
                if self.dependency_codegen_object_count == 0
                    && self.dependency_partial_link_count == 0
                {
                    return Err(
                        "partial-link descriptor must consume object or partial-link inputs".into(),
                    );
                }
                require_descriptor_record(
                    self,
                    GpuSourcePackDescriptorRecordDomain::PartialLink,
                    GpuSourcePackDescriptorRecordKind::Section,
                    GpuSourcePackDescriptorRecordFlow::Output,
                    "partial-link descriptor must describe output partial-link sections",
                )?;
                require_descriptor_record(
                    self,
                    GpuSourcePackDescriptorRecordDomain::PartialLink,
                    GpuSourcePackDescriptorRecordKind::Symbol,
                    GpuSourcePackDescriptorRecordFlow::Output,
                    "partial-link descriptor must describe output partial-link symbols",
                )?;
                require_descriptor_record(
                    self,
                    GpuSourcePackDescriptorRecordDomain::PartialLink,
                    GpuSourcePackDescriptorRecordKind::UnresolvedSymbol,
                    GpuSourcePackDescriptorRecordFlow::Output,
                    "partial-link descriptor must describe output unresolved symbols",
                )?;
                require_descriptor_record(
                    self,
                    GpuSourcePackDescriptorRecordDomain::PartialLink,
                    GpuSourcePackDescriptorRecordKind::Relocation,
                    GpuSourcePackDescriptorRecordFlow::Output,
                    "partial-link descriptor must describe output partial-link relocations",
                )?;
                reject_descriptor_domain(
                    self,
                    GpuSourcePackDescriptorRecordDomain::LinkedOutput,
                    "partial-link descriptor must not describe linked-output records",
                )?;
            }
            GpuSourcePackArtifactStage::LinkedOutput => {
                if self.dependency_codegen_object_count == 0
                    && self.dependency_partial_link_count == 0
                {
                    return Err(
                        "linked-output descriptor must consume object or partial-link inputs"
                            .into(),
                    );
                }
                require_descriptor_record(
                    self,
                    GpuSourcePackDescriptorRecordDomain::LinkedOutput,
                    GpuSourcePackDescriptorRecordKind::Section,
                    GpuSourcePackDescriptorRecordFlow::Output,
                    "linked-output descriptor must describe output image sections",
                )?;
                require_descriptor_record(
                    self,
                    GpuSourcePackDescriptorRecordDomain::LinkedOutput,
                    GpuSourcePackDescriptorRecordKind::Symbol,
                    GpuSourcePackDescriptorRecordFlow::Output,
                    "linked-output descriptor must describe output image symbols",
                )?;
                reject_descriptor_record(
                    self,
                    GpuSourcePackDescriptorRecordDomain::LinkedOutput,
                    GpuSourcePackDescriptorRecordKind::Relocation,
                    GpuSourcePackDescriptorRecordFlow::Output,
                    "linked-output descriptor must not emit unresolved relocation descriptors",
                )?;
                reject_descriptor_record(
                    self,
                    GpuSourcePackDescriptorRecordDomain::LinkedOutput,
                    GpuSourcePackDescriptorRecordKind::UnresolvedSymbol,
                    GpuSourcePackDescriptorRecordFlow::Output,
                    "linked-output descriptor must not emit unresolved symbol descriptors",
                )?;
            }
        }
        self.validate_output_record_domains()?;
        self.validate_output_record_array_domains()?;
        validate_reserved_record_array_coverage(&self.record_arrays, &self.descriptor_records)?;
        Ok(())
    }

    fn validate_dependency_input_records(&self) -> Result<(), String> {
        if self.dependency_interface_count != 0 {
            require_descriptor_record(
                self,
                GpuSourcePackDescriptorRecordDomain::Interface,
                GpuSourcePackDescriptorRecordKind::Symbol,
                GpuSourcePackDescriptorRecordFlow::Input,
                "descriptor with interface dependencies must describe input interface symbols",
            )?;
        }
        if self.dependency_codegen_object_count != 0 {
            require_descriptor_record(
                self,
                GpuSourcePackDescriptorRecordDomain::Object,
                GpuSourcePackDescriptorRecordKind::Section,
                GpuSourcePackDescriptorRecordFlow::Input,
                "descriptor with object dependencies must describe input object sections",
            )?;
            require_descriptor_record(
                self,
                GpuSourcePackDescriptorRecordDomain::Object,
                GpuSourcePackDescriptorRecordKind::Symbol,
                GpuSourcePackDescriptorRecordFlow::Input,
                "descriptor with object dependencies must describe input object symbols",
            )?;
            require_descriptor_record(
                self,
                GpuSourcePackDescriptorRecordDomain::Object,
                GpuSourcePackDescriptorRecordKind::Relocation,
                GpuSourcePackDescriptorRecordFlow::Input,
                "descriptor with object dependencies must describe input object relocations",
            )?;
        }
        if self.dependency_partial_link_count != 0 {
            require_descriptor_record(
                self,
                GpuSourcePackDescriptorRecordDomain::PartialLink,
                GpuSourcePackDescriptorRecordKind::Section,
                GpuSourcePackDescriptorRecordFlow::Input,
                "descriptor with partial-link dependencies must describe input partial-link sections",
            )?;
            require_descriptor_record(
                self,
                GpuSourcePackDescriptorRecordDomain::PartialLink,
                GpuSourcePackDescriptorRecordKind::Symbol,
                GpuSourcePackDescriptorRecordFlow::Input,
                "descriptor with partial-link dependencies must describe input partial-link symbols",
            )?;
            require_descriptor_record(
                self,
                GpuSourcePackDescriptorRecordDomain::PartialLink,
                GpuSourcePackDescriptorRecordKind::UnresolvedSymbol,
                GpuSourcePackDescriptorRecordFlow::Input,
                "descriptor with partial-link dependencies must describe input unresolved symbols",
            )?;
            require_descriptor_record(
                self,
                GpuSourcePackDescriptorRecordDomain::PartialLink,
                GpuSourcePackDescriptorRecordKind::Relocation,
                GpuSourcePackDescriptorRecordFlow::Input,
                "descriptor with partial-link dependencies must describe input partial-link relocations",
            )?;
        }
        Ok(())
    }

    fn validate_output_record_domains(&self) -> Result<(), String> {
        let expected_domain = self.stage.output_record_domain();
        for record in &self.descriptor_records {
            if record.flow == GpuSourcePackDescriptorRecordFlow::Output
                && record.domain != expected_domain
            {
                return Err(format!(
                    "descriptor stage {:?} must only output {:?} records; descriptor record {:?} outputs {:?} records",
                    self.stage, expected_domain, record.name, record.domain
                ));
            }
        }
        Ok(())
    }

    fn validate_output_record_array_domains(&self) -> Result<(), String> {
        let expected_domain = self.stage.output_record_domain();
        for array in &self.output_record_arrays {
            if let Some(domain) = output_record_array_domain(&array.name)
                && domain != expected_domain
            {
                return Err(format!(
                    "descriptor stage {:?} must only declare {:?} output record arrays; output record array {:?} belongs to {:?} records",
                    self.stage, expected_domain, array.name, domain
                ));
            }
        }
        Ok(())
    }

    fn validate_input_record_array_domains(&self) -> Result<(), String> {
        for array in &self.input_record_arrays {
            if let Some(domain) = output_only_record_array_domain(&array.name) {
                return Err(format!(
                    "descriptor stage {:?} must not declare output-only {:?} record array {:?} as an input",
                    self.stage, domain, array.name
                ));
            }
        }
        Ok(())
    }

    fn validate_required_runtime_services(&self) -> Result<(), String> {
        self.validate_runtime_abi_metadata()?;

        if self.required_runtime_service_ids.is_empty() {
            if let Some(runtime_abi_version) = self.required_runtime_abi_version {
                return Err(format!(
                    "descriptor declares runtime ABI version {runtime_abi_version} without required runtime service ids"
                ));
            }
            if !self.required_runtime_services.is_empty() {
                return Err(
                    "descriptor declares runtime service rows without required runtime service ids"
                        .into(),
                );
            }
            if self.runtime_abi.is_some() {
                return Err(
                    "descriptor declares runtime ABI metadata without required runtime service ids"
                        .into(),
                );
            }
            self.validate_runtime_service_requirement_record_contract()?;
            return Ok(());
        }

        let required_runtime_abi_version = match self.required_runtime_abi_version {
            Some(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION) => GPU_SOURCE_PACK_RUNTIME_ABI_VERSION,
            Some(GPU_SOURCE_PACK_UNKNOWN_RUNTIME_ABI_VERSION) => {
                return Err(format!(
                    "runtime-bound descriptor must not use unknown runtime ABI version {}; expected {}",
                    GPU_SOURCE_PACK_UNKNOWN_RUNTIME_ABI_VERSION,
                    GPU_SOURCE_PACK_RUNTIME_ABI_VERSION
                ));
            }
            Some(runtime_abi_version) => {
                return Err(format!(
                    "descriptor requires unsupported runtime ABI version {runtime_abi_version}; expected {}",
                    GPU_SOURCE_PACK_RUNTIME_ABI_VERSION
                ));
            }
            None => {
                return Err(format!(
                    "runtime-bound descriptor must declare runtime ABI version {}",
                    GPU_SOURCE_PACK_RUNTIME_ABI_VERSION
                ));
            }
        };

        let Some(runtime_abi) = self.runtime_abi.as_ref() else {
            return Err(
                "runtime-bound descriptor must persist runtime ABI metadata for the service inventory"
                    .into(),
            );
        };
        if runtime_abi.abi_version != required_runtime_abi_version {
            return Err(format!(
                "descriptor runtime ABI metadata version {} does not match required_runtime_abi_version {}",
                runtime_abi.abi_version, required_runtime_abi_version
            ));
        }

        let mut seen = BTreeSet::new();
        let mut previous_service_id = None;
        for service_id in self.required_runtime_service_ids.iter().copied() {
            if !is_known_runtime_service_id(service_id) {
                return Err(format!(
                    "descriptor requires unknown runtime service id {service_id}"
                ));
            }
            if !seen.insert(service_id) {
                return Err(format!(
                    "descriptor requires runtime service id {service_id} more than once"
                ));
            }
            if let Some(previous_service_id) = previous_service_id
                && service_id <= previous_service_id
            {
                return Err(format!(
                    "descriptor required runtime service ids must be listed in strictly ascending order; service id {service_id} follows {previous_service_id}"
                ));
            }
            previous_service_id = Some(service_id);
        }

        self.validate_required_runtime_service_rows()?;
        self.validate_runtime_service_requirement_record_contract()?;

        if let Some(record_array_name) = self.target_byte_output_record_array_name() {
            return Err(format!(
                "runtime-bound descriptor requires runtime service ids {:?} but declares target-byte output record array {:?}; descriptor contracts with unbound runtime services must not claim executable bytes",
                self.required_runtime_service_ids, record_array_name
            ));
        }

        Ok(())
    }

    fn validate_linked_output_target_byte_records(&self) -> Result<(), String> {
        if self.stage != GpuSourcePackArtifactStage::LinkedOutput
            || !self.required_runtime_service_ids.is_empty()
        {
            return Ok(());
        }

        let target_byte_arrays = self.target_byte_output_record_array_names();
        match target_byte_arrays.len() {
            1 => Ok(()),
            0 => Err(
                "linked-output descriptor without runtime service requirements must declare exactly one target-byte output record array"
                    .into(),
            ),
            count => Err(format!(
                "linked-output descriptor must declare exactly one target-byte output record array; found {count}: {:?}",
                target_byte_arrays
            )),
        }
    }

    fn sync_runtime_service_requirement_record_contract(&mut self) {
        self.input_record_arrays
            .retain(|array| array.name != GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_RECORD_ARRAY);
        self.output_record_arrays
            .retain(|array| array.name != GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_RECORD_ARRAY);
        self.descriptor_records.retain(|record| {
            record.name != GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_DESCRIPTOR_RECORD
                && record.record_array != GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_RECORD_ARRAY
        });

        if !self.required_runtime_service_ids.is_empty() {
            let row_count = self.required_runtime_service_ids.len();
            self.output_record_arrays
                .push(GpuSourcePackRecordArrayDescriptor::bounded(
                    GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_RECORD_ARRAY,
                    row_count,
                    row_count
                        .saturating_mul(GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_ROW_BYTE_LEN),
                ));
            let mut descriptor_record = descriptor_record(
                GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_DESCRIPTOR_RECORD,
                self.stage.output_record_domain(),
                GpuSourcePackDescriptorRecordKind::RuntimeService,
                GpuSourcePackDescriptorRecordFlow::Output,
                GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_RECORD_ARRAY,
            );
            descriptor_record.element_count = Some(row_count);
            self.descriptor_records.push(descriptor_record);
        }

        self.record_arrays =
            Self::combined_record_arrays(&self.input_record_arrays, &self.output_record_arrays);
    }

    fn validate_runtime_service_requirement_record_contract(&self) -> Result<(), String> {
        let runtime_input_arrays = self
            .input_record_arrays
            .iter()
            .filter(|array| array.name == GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_RECORD_ARRAY)
            .count();
        let runtime_output_arrays = self
            .output_record_arrays
            .iter()
            .filter(|array| array.name == GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_RECORD_ARRAY)
            .count();
        let runtime_records = self
            .descriptor_records
            .iter()
            .filter(|record| {
                record.kind == GpuSourcePackDescriptorRecordKind::RuntimeService
                    || record.record_array
                        == GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_RECORD_ARRAY
            })
            .collect::<Vec<_>>();

        if self.required_runtime_service_ids.is_empty() {
            if runtime_input_arrays != 0
                || runtime_output_arrays != 0
                || !runtime_records.is_empty()
            {
                return Err(
                    "descriptor declares runtime service requirement records without required runtime service ids"
                        .into(),
                );
            }
            return Ok(());
        }

        if runtime_input_arrays != 0 {
            return Err(
                "descriptor must not consume runtime service requirement records as input while services remain unbound"
                    .into(),
            );
        }
        if runtime_output_arrays != 1 {
            return Err(format!(
                "runtime-bound descriptor must declare exactly one output record array {:?}; found {}",
                GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_RECORD_ARRAY, runtime_output_arrays
            ));
        }
        if runtime_records.len() != 1 {
            return Err(format!(
                "runtime-bound descriptor must describe runtime service requirement records exactly once; found {}",
                runtime_records.len()
            ));
        }

        let expected_row_count = self.required_runtime_service_ids.len();
        let record_array = self
            .output_record_arrays
            .iter()
            .find(|array| array.name == GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_RECORD_ARRAY)
            .expect("runtime output array count was validated above");
        if record_array.element_count != Some(expected_row_count) {
            return Err(format!(
                "runtime service requirement record array {:?} declares element count {:?}; expected {}",
                record_array.name, record_array.element_count, expected_row_count
            ));
        }
        let expected_byte_len = expected_row_count
            .saturating_mul(GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_ROW_BYTE_LEN);
        if record_array.byte_len != Some(expected_byte_len) {
            return Err(format!(
                "runtime service requirement record array {:?} declares byte length {:?}; expected {}",
                record_array.name, record_array.byte_len, expected_byte_len
            ));
        }

        let record = runtime_records[0];
        let expected_domain = self.stage.output_record_domain();
        if record.name != GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_DESCRIPTOR_RECORD {
            return Err(format!(
                "runtime service requirement descriptor record is named {:?}; expected {:?}",
                record.name, GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_DESCRIPTOR_RECORD
            ));
        }
        if record.domain != expected_domain
            || record.kind != GpuSourcePackDescriptorRecordKind::RuntimeService
            || record.flow != GpuSourcePackDescriptorRecordFlow::Output
            || record.record_array != GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_RECORD_ARRAY
        {
            return Err(format!(
                "runtime service requirement descriptor record must be {:?} RuntimeService Output over {:?}; found {:?} {:?} {:?} over {:?}",
                expected_domain,
                GPU_SOURCE_PACK_RUNTIME_SERVICE_REQUIREMENT_RECORD_ARRAY,
                record.domain,
                record.kind,
                record.flow,
                record.record_array
            ));
        }
        if record.element_count != Some(expected_row_count) {
            return Err(format!(
                "runtime service requirement descriptor record declares element count {:?}; expected {}",
                record.element_count, expected_row_count
            ));
        }

        Ok(())
    }

    fn validate_required_runtime_service_rows(&self) -> Result<(), String> {
        if self.required_runtime_services.len() != self.required_runtime_service_ids.len() {
            return Err(format!(
                "descriptor runtime service rows must match required_runtime_service_ids length; rows={}, ids={}",
                self.required_runtime_services.len(),
                self.required_runtime_service_ids.len()
            ));
        }

        for (index, (service_id, row)) in self
            .required_runtime_service_ids
            .iter()
            .copied()
            .zip(self.required_runtime_services.iter())
            .enumerate()
        {
            if row.service_id != service_id {
                return Err(format!(
                    "descriptor runtime service row {index} records service id {} but required_runtime_service_ids[{index}] is {service_id}",
                    row.service_id
                ));
            }
            if row.required_abi_version != GPU_SOURCE_PACK_RUNTIME_ABI_VERSION {
                return Err(format!(
                    "descriptor runtime service row {index} for service id {service_id} requires ABI version {}; expected {}",
                    row.required_abi_version, GPU_SOURCE_PACK_RUNTIME_ABI_VERSION
                ));
            }
            if row.service_status == GPU_SOURCE_PACK_RUNTIME_SERVICE_STATUS_UNKNOWN {
                return Err(format!(
                    "descriptor runtime service row {index} for service id {service_id} uses unknown status {} for a known service",
                    GPU_SOURCE_PACK_RUNTIME_SERVICE_STATUS_UNKNOWN
                ));
            }
            let expected_status = runtime_service_status(service_id);
            if row.service_status != expected_status {
                return Err(format!(
                    "descriptor runtime service row {index} for service id {service_id} has status {}; expected current compiler/runtime status {expected_status}",
                    row.service_status
                ));
            }
        }

        Ok(())
    }

    fn validate_runtime_abi_metadata(&self) -> Result<(), String> {
        let Some(runtime_abi) = self.runtime_abi.as_ref() else {
            return Ok(());
        };
        if runtime_abi.metadata_version != GPU_SOURCE_PACK_RUNTIME_ABI_METADATA_VERSION {
            return Err(format!(
                "descriptor runtime ABI metadata version {} is unsupported; expected {}",
                runtime_abi.metadata_version, GPU_SOURCE_PACK_RUNTIME_ABI_METADATA_VERSION
            ));
        }
        if runtime_abi.abi_version == GPU_SOURCE_PACK_UNKNOWN_RUNTIME_ABI_VERSION {
            return Err(format!(
                "descriptor runtime ABI metadata must not use unknown runtime ABI version {}; expected {}",
                GPU_SOURCE_PACK_UNKNOWN_RUNTIME_ABI_VERSION, GPU_SOURCE_PACK_RUNTIME_ABI_VERSION
            ));
        }
        if runtime_abi.abi_version != GPU_SOURCE_PACK_RUNTIME_ABI_VERSION {
            return Err(format!(
                "descriptor runtime ABI metadata requires unsupported runtime ABI version {}; expected {}",
                runtime_abi.abi_version, GPU_SOURCE_PACK_RUNTIME_ABI_VERSION
            ));
        }
        if runtime_abi.service_count != GPU_SOURCE_PACK_RUNTIME_SERVICE_COUNT as u32 {
            return Err(format!(
                "descriptor runtime ABI metadata records service count {}; expected {}",
                runtime_abi.service_count, GPU_SOURCE_PACK_RUNTIME_SERVICE_COUNT
            ));
        }
        if runtime_abi.first_service_id != GPU_SOURCE_PACK_FIRST_RUNTIME_SERVICE_ID {
            return Err(format!(
                "descriptor runtime ABI metadata records first service id {}; expected {}",
                runtime_abi.first_service_id, GPU_SOURCE_PACK_FIRST_RUNTIME_SERVICE_ID
            ));
        }
        if runtime_abi.last_service_id != GPU_SOURCE_PACK_LAST_RUNTIME_SERVICE_ID {
            return Err(format!(
                "descriptor runtime ABI metadata records last service id {}; expected {}",
                runtime_abi.last_service_id, GPU_SOURCE_PACK_LAST_RUNTIME_SERVICE_ID
            ));
        }
        Ok(())
    }

    fn target_byte_output_record_array_name(&self) -> Option<&str> {
        for array in &self.output_record_arrays {
            if is_target_byte_record_array(&array.name) {
                return Some(array.name.as_str());
            }
        }
        if self.output_record_arrays.is_empty() {
            for array in &self.record_arrays {
                if is_target_byte_record_array(&array.name) {
                    return Some(array.name.as_str());
                }
            }
        }
        None
    }

    fn target_byte_output_record_array_names(&self) -> Vec<&str> {
        let arrays = if self.output_record_arrays.is_empty() {
            &self.record_arrays
        } else {
            &self.output_record_arrays
        };
        arrays
            .iter()
            .filter_map(|array| {
                is_target_byte_record_array(&array.name).then_some(array.name.as_str())
            })
            .collect()
    }

    /// Builds the expected descriptor for a library-interface artifact job.
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
        let descriptor_records = vec![
            descriptor_record(
                "dependency_interface_symbols",
                GpuSourcePackDescriptorRecordDomain::Interface,
                GpuSourcePackDescriptorRecordKind::Symbol,
                GpuSourcePackDescriptorRecordFlow::Input,
                "dependency_semantic_interface_records",
            ),
            descriptor_record(
                "semantic_interface_symbols",
                GpuSourcePackDescriptorRecordDomain::Interface,
                GpuSourcePackDescriptorRecordKind::Symbol,
                GpuSourcePackDescriptorRecordFlow::Output,
                "semantic_interface_records",
            ),
        ];
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
            descriptor_records,
            required_runtime_abi_version: None,
            required_runtime_service_ids: Vec::new(),
            required_runtime_services: Vec::new(),
            runtime_abi: None,
        }
    }

    /// Builds the expected descriptor for a codegen-object artifact job.
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
            GpuSourcePackRecordArrayDescriptor::pending("object_section_records"),
            GpuSourcePackRecordArrayDescriptor::pending("object_symbol_records"),
            GpuSourcePackRecordArrayDescriptor::pending("node_instruction_count_records"),
            GpuSourcePackRecordArrayDescriptor::pending("instruction_location_records"),
            GpuSourcePackRecordArrayDescriptor::pending("virtual_instruction_records"),
            GpuSourcePackRecordArrayDescriptor::pending("virtual_register_records"),
            GpuSourcePackRecordArrayDescriptor::pending("relocation_records"),
        ];
        let record_arrays =
            Self::combined_record_arrays(&input_record_arrays, &output_record_arrays);
        let descriptor_records = vec![
            descriptor_record(
                "dependency_interface_symbols",
                GpuSourcePackDescriptorRecordDomain::Interface,
                GpuSourcePackDescriptorRecordKind::Symbol,
                GpuSourcePackDescriptorRecordFlow::Input,
                "dependency_semantic_interface_records",
            ),
            descriptor_record(
                "object_sections",
                GpuSourcePackDescriptorRecordDomain::Object,
                GpuSourcePackDescriptorRecordKind::Section,
                GpuSourcePackDescriptorRecordFlow::Output,
                "object_section_records",
            ),
            descriptor_record(
                "object_symbols",
                GpuSourcePackDescriptorRecordDomain::Object,
                GpuSourcePackDescriptorRecordKind::Symbol,
                GpuSourcePackDescriptorRecordFlow::Output,
                "object_symbol_records",
            ),
            descriptor_record(
                "object_relocations",
                GpuSourcePackDescriptorRecordDomain::Object,
                GpuSourcePackDescriptorRecordKind::Relocation,
                GpuSourcePackDescriptorRecordFlow::Output,
                "relocation_records",
            ),
        ];
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
            descriptor_records,
            required_runtime_abi_version: None,
            required_runtime_service_ids: Vec::new(),
            required_runtime_services: Vec::new(),
            runtime_abi: None,
        }
    }

    /// Builds the expected descriptor for a direct linked-output artifact job.
    ///
    /// This form is used when link execution is represented by a source-pack
    /// job rather than a hierarchical link execution page.
    pub fn linked_output_contract_for_job(
        target: SourcePackArtifactTarget,
        job: &SourcePackJob,
        dependency_interface_count: usize,
        dependency_codegen_object_count: usize,
    ) -> Self {
        let mut input_record_arrays = Vec::new();
        let mut descriptor_records = Vec::new();
        append_interface_input_records(
            &mut input_record_arrays,
            &mut descriptor_records,
            dependency_interface_count,
        );
        append_object_input_records(
            &mut input_record_arrays,
            &mut descriptor_records,
            dependency_codegen_object_count,
        );
        let output_record_arrays = vec![
            GpuSourcePackRecordArrayDescriptor::pending("linked_section_records"),
            GpuSourcePackRecordArrayDescriptor::pending("linked_symbol_records"),
            GpuSourcePackRecordArrayDescriptor::pending("emitted_byte_records"),
        ];
        let record_arrays =
            Self::combined_record_arrays(&input_record_arrays, &output_record_arrays);
        descriptor_records.extend([
            descriptor_record(
                "linked_output_sections",
                GpuSourcePackDescriptorRecordDomain::LinkedOutput,
                GpuSourcePackDescriptorRecordKind::Section,
                GpuSourcePackDescriptorRecordFlow::Output,
                "linked_section_records",
            ),
            descriptor_record(
                "linked_output_symbols",
                GpuSourcePackDescriptorRecordDomain::LinkedOutput,
                GpuSourcePackDescriptorRecordKind::Symbol,
                GpuSourcePackDescriptorRecordFlow::Output,
                "linked_symbol_records",
            ),
        ]);
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
            descriptor_records,
            required_runtime_abi_version: None,
            required_runtime_service_ids: Vec::new(),
            required_runtime_services: Vec::new(),
            runtime_abi: None,
        }
    }

    /// Builds the expected descriptor for one hierarchical partial-link page.
    pub fn partial_link_contract_for_page(
        page: &SourcePackHierarchicalLinkExecutionPage,
        dependency_interface_count: usize,
        dependency_codegen_object_count: usize,
        dependency_partial_link_count: usize,
    ) -> Self {
        let mut input_record_arrays = Vec::new();
        let mut descriptor_records = Vec::new();
        append_interface_input_records(
            &mut input_record_arrays,
            &mut descriptor_records,
            dependency_interface_count,
        );
        append_object_input_records(
            &mut input_record_arrays,
            &mut descriptor_records,
            dependency_codegen_object_count,
        );
        append_partial_link_input_records(
            &mut input_record_arrays,
            &mut descriptor_records,
            dependency_partial_link_count,
        );
        let output_record_arrays = vec![
            GpuSourcePackRecordArrayDescriptor::pending("partial_link_section_records"),
            GpuSourcePackRecordArrayDescriptor::pending("partial_link_symbol_records"),
            GpuSourcePackRecordArrayDescriptor::pending("partial_link_unresolved_symbol_records"),
            GpuSourcePackRecordArrayDescriptor::pending("partial_link_relocation_records"),
        ];
        let record_arrays =
            Self::combined_record_arrays(&input_record_arrays, &output_record_arrays);
        descriptor_records.extend([
            descriptor_record(
                "partial_link_sections",
                GpuSourcePackDescriptorRecordDomain::PartialLink,
                GpuSourcePackDescriptorRecordKind::Section,
                GpuSourcePackDescriptorRecordFlow::Output,
                "partial_link_section_records",
            ),
            descriptor_record(
                "partial_link_symbols",
                GpuSourcePackDescriptorRecordDomain::PartialLink,
                GpuSourcePackDescriptorRecordKind::Symbol,
                GpuSourcePackDescriptorRecordFlow::Output,
                "partial_link_symbol_records",
            ),
            descriptor_record(
                "partial_link_unresolved_symbols",
                GpuSourcePackDescriptorRecordDomain::PartialLink,
                GpuSourcePackDescriptorRecordKind::UnresolvedSymbol,
                GpuSourcePackDescriptorRecordFlow::Output,
                "partial_link_unresolved_symbol_records",
            ),
            descriptor_record(
                "partial_link_relocations",
                GpuSourcePackDescriptorRecordDomain::PartialLink,
                GpuSourcePackDescriptorRecordKind::Relocation,
                GpuSourcePackDescriptorRecordFlow::Output,
                "partial_link_relocation_records",
            ),
        ]);
        let mut descriptor = Self {
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
            descriptor_records,
            required_runtime_abi_version: None,
            required_runtime_service_ids: Vec::new(),
            required_runtime_services: Vec::new(),
            runtime_abi: None,
        };
        descriptor.apply_runtime_requirements_from_link_summary(&page.descriptor_summary);
        descriptor
    }

    /// Builds the expected descriptor for one hierarchical linked-output page.
    ///
    /// The resulting descriptor carries the page's link group and any runtime
    /// service requirements propagated through the page descriptor summary.
    pub fn hierarchical_linked_output_contract_for_page(
        page: &SourcePackHierarchicalLinkExecutionPage,
        dependency_interface_count: usize,
        dependency_codegen_object_count: usize,
        dependency_partial_link_count: usize,
    ) -> Self {
        let mut input_record_arrays = Vec::new();
        let mut descriptor_records = Vec::new();
        append_interface_input_records(
            &mut input_record_arrays,
            &mut descriptor_records,
            dependency_interface_count,
        );
        append_object_input_records(
            &mut input_record_arrays,
            &mut descriptor_records,
            dependency_codegen_object_count,
        );
        append_partial_link_input_records(
            &mut input_record_arrays,
            &mut descriptor_records,
            dependency_partial_link_count,
        );
        let output_record_arrays = vec![
            GpuSourcePackRecordArrayDescriptor::pending("linked_section_records"),
            GpuSourcePackRecordArrayDescriptor::pending("linked_symbol_records"),
            GpuSourcePackRecordArrayDescriptor::pending("emitted_byte_records"),
        ];
        let record_arrays =
            Self::combined_record_arrays(&input_record_arrays, &output_record_arrays);
        descriptor_records.extend([
            descriptor_record(
                "linked_output_sections",
                GpuSourcePackDescriptorRecordDomain::LinkedOutput,
                GpuSourcePackDescriptorRecordKind::Section,
                GpuSourcePackDescriptorRecordFlow::Output,
                "linked_section_records",
            ),
            descriptor_record(
                "linked_output_symbols",
                GpuSourcePackDescriptorRecordDomain::LinkedOutput,
                GpuSourcePackDescriptorRecordKind::Symbol,
                GpuSourcePackDescriptorRecordFlow::Output,
                "linked_symbol_records",
            ),
        ]);
        let mut descriptor = Self {
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
            descriptor_records,
            required_runtime_abi_version: None,
            required_runtime_service_ids: Vec::new(),
            required_runtime_services: Vec::new(),
            runtime_abi: None,
        };
        descriptor.apply_runtime_requirements_from_link_summary(&page.descriptor_summary);
        descriptor
    }

    fn apply_runtime_requirements_from_link_summary(
        &mut self,
        summary: &SourcePackLinkDescriptorSummary,
    ) {
        self.set_required_runtime_services(summary.required_runtime_service_ids.iter().copied());
        self.required_runtime_abi_version = summary.required_runtime_abi_version;
        if let Some(required_runtime_abi_version) = summary.required_runtime_abi_version {
            for row in &mut self.required_runtime_services {
                row.required_abi_version = required_runtime_abi_version;
            }
        }
    }
}

fn is_known_runtime_service_id(service_id: u32) -> bool {
    GPU_SOURCE_PACK_RUNTIME_SERVICE_IDS.contains(&service_id)
}

fn is_target_byte_record_array(name: &str) -> bool {
    GPU_SOURCE_PACK_TARGET_BYTE_RECORD_ARRAYS.contains(&name)
}

fn output_record_array_domain(name: &str) -> Option<GpuSourcePackDescriptorRecordDomain> {
    if let Some((domain, _kind)) = descriptor_record_array_shape(name) {
        Some(domain)
    } else if GPU_SOURCE_PACK_LIBRARY_INTERFACE_OUTPUT_RECORD_ARRAYS.contains(&name) {
        Some(GpuSourcePackDescriptorRecordDomain::Interface)
    } else if GPU_SOURCE_PACK_OBJECT_OUTPUT_RECORD_ARRAYS.contains(&name) {
        Some(GpuSourcePackDescriptorRecordDomain::Object)
    } else if GPU_SOURCE_PACK_PARTIAL_LINK_OUTPUT_RECORD_ARRAYS.contains(&name) {
        Some(GpuSourcePackDescriptorRecordDomain::PartialLink)
    } else if GPU_SOURCE_PACK_LINKED_OUTPUT_RECORD_ARRAYS.contains(&name)
        || is_target_byte_record_array(name)
    {
        Some(GpuSourcePackDescriptorRecordDomain::LinkedOutput)
    } else {
        None
    }
}

fn output_only_record_array_domain(name: &str) -> Option<GpuSourcePackDescriptorRecordDomain> {
    if GPU_SOURCE_PACK_LIBRARY_INTERFACE_OUTPUT_RECORD_ARRAYS.contains(&name)
        && name != "dependency_semantic_interface_records"
        && name != "resolver_records"
        && name != "type_instance_records"
    {
        Some(GpuSourcePackDescriptorRecordDomain::Interface)
    } else if GPU_SOURCE_PACK_OBJECT_OUTPUT_RECORD_ARRAYS.contains(&name) {
        Some(GpuSourcePackDescriptorRecordDomain::Object)
    } else if GPU_SOURCE_PACK_PARTIAL_LINK_OUTPUT_RECORD_ARRAYS.contains(&name) {
        Some(GpuSourcePackDescriptorRecordDomain::PartialLink)
    } else if GPU_SOURCE_PACK_LINKED_OUTPUT_RECORD_ARRAYS.contains(&name)
        || is_target_byte_record_array(name)
    {
        Some(GpuSourcePackDescriptorRecordDomain::LinkedOutput)
    } else {
        None
    }
}

fn descriptor_record_array_shape(
    name: &str,
) -> Option<(
    GpuSourcePackDescriptorRecordDomain,
    GpuSourcePackDescriptorRecordKind,
)> {
    match name {
        "dependency_semantic_interface_records" | "semantic_interface_records" => Some((
            GpuSourcePackDescriptorRecordDomain::Interface,
            GpuSourcePackDescriptorRecordKind::Symbol,
        )),
        "allocated_instruction_records" | "object_section_records" => Some((
            GpuSourcePackDescriptorRecordDomain::Object,
            GpuSourcePackDescriptorRecordKind::Section,
        )),
        "function_offset_records" | "object_symbol_records" => Some((
            GpuSourcePackDescriptorRecordDomain::Object,
            GpuSourcePackDescriptorRecordKind::Symbol,
        )),
        "link_relocation_records" | "relocation_records" => Some((
            GpuSourcePackDescriptorRecordDomain::Object,
            GpuSourcePackDescriptorRecordKind::Relocation,
        )),
        "input_partial_link_section_records" | "partial_link_section_records" => Some((
            GpuSourcePackDescriptorRecordDomain::PartialLink,
            GpuSourcePackDescriptorRecordKind::Section,
        )),
        "input_partial_link_symbol_records" | "partial_link_symbol_records" => Some((
            GpuSourcePackDescriptorRecordDomain::PartialLink,
            GpuSourcePackDescriptorRecordKind::Symbol,
        )),
        "input_partial_link_unresolved_symbol_records"
        | "partial_link_unresolved_symbol_records" => Some((
            GpuSourcePackDescriptorRecordDomain::PartialLink,
            GpuSourcePackDescriptorRecordKind::UnresolvedSymbol,
        )),
        "input_partial_link_relocation_records" | "partial_link_relocation_records" => Some((
            GpuSourcePackDescriptorRecordDomain::PartialLink,
            GpuSourcePackDescriptorRecordKind::Relocation,
        )),
        "linked_section_records" => Some((
            GpuSourcePackDescriptorRecordDomain::LinkedOutput,
            GpuSourcePackDescriptorRecordKind::Section,
        )),
        "linked_symbol_records" => Some((
            GpuSourcePackDescriptorRecordDomain::LinkedOutput,
            GpuSourcePackDescriptorRecordKind::Symbol,
        )),
        _ => None,
    }
}

fn validate_reserved_record_array_shape(
    record: &GpuSourcePackDescriptorRecord,
) -> Result<(), String> {
    if let Some((expected_domain, expected_kind)) =
        descriptor_record_array_shape(record.record_array.as_str())
        && (record.domain != expected_domain || record.kind != expected_kind)
    {
        return Err(format!(
            "descriptor record {:?} describes reserved record array {:?} as {:?} {:?}; expected {:?} {:?}",
            record.name,
            record.record_array,
            record.domain,
            record.kind,
            expected_domain,
            expected_kind
        ));
    }
    Ok(())
}

fn descriptor_record(
    name: impl Into<String>,
    domain: GpuSourcePackDescriptorRecordDomain,
    kind: GpuSourcePackDescriptorRecordKind,
    flow: GpuSourcePackDescriptorRecordFlow,
    record_array: impl Into<String>,
) -> GpuSourcePackDescriptorRecord {
    GpuSourcePackDescriptorRecord::new(name, domain, kind, flow, record_array)
}

fn append_interface_input_records(
    input_record_arrays: &mut Vec<GpuSourcePackRecordArrayDescriptor>,
    descriptor_records: &mut Vec<GpuSourcePackDescriptorRecord>,
    dependency_count: usize,
) {
    if dependency_count == 0 {
        return;
    }
    input_record_arrays.push(GpuSourcePackRecordArrayDescriptor::pending(
        "dependency_semantic_interface_records",
    ));
    descriptor_records.push(descriptor_record(
        "dependency_interface_symbols",
        GpuSourcePackDescriptorRecordDomain::Interface,
        GpuSourcePackDescriptorRecordKind::Symbol,
        GpuSourcePackDescriptorRecordFlow::Input,
        "dependency_semantic_interface_records",
    ));
}

fn append_object_input_records(
    input_record_arrays: &mut Vec<GpuSourcePackRecordArrayDescriptor>,
    descriptor_records: &mut Vec<GpuSourcePackDescriptorRecord>,
    dependency_count: usize,
) {
    if dependency_count == 0 {
        return;
    }
    input_record_arrays.extend([
        GpuSourcePackRecordArrayDescriptor::pending("allocated_instruction_records"),
        GpuSourcePackRecordArrayDescriptor::pending("function_offset_records"),
        GpuSourcePackRecordArrayDescriptor::pending("link_relocation_records"),
    ]);
    descriptor_records.extend([
        descriptor_record(
            "object_sections",
            GpuSourcePackDescriptorRecordDomain::Object,
            GpuSourcePackDescriptorRecordKind::Section,
            GpuSourcePackDescriptorRecordFlow::Input,
            "allocated_instruction_records",
        ),
        descriptor_record(
            "object_symbols",
            GpuSourcePackDescriptorRecordDomain::Object,
            GpuSourcePackDescriptorRecordKind::Symbol,
            GpuSourcePackDescriptorRecordFlow::Input,
            "function_offset_records",
        ),
        descriptor_record(
            "object_relocations",
            GpuSourcePackDescriptorRecordDomain::Object,
            GpuSourcePackDescriptorRecordKind::Relocation,
            GpuSourcePackDescriptorRecordFlow::Input,
            "link_relocation_records",
        ),
    ]);
}

fn append_partial_link_input_records(
    input_record_arrays: &mut Vec<GpuSourcePackRecordArrayDescriptor>,
    descriptor_records: &mut Vec<GpuSourcePackDescriptorRecord>,
    dependency_count: usize,
) {
    if dependency_count == 0 {
        return;
    }
    input_record_arrays.extend([
        GpuSourcePackRecordArrayDescriptor::pending("input_partial_link_section_records"),
        GpuSourcePackRecordArrayDescriptor::pending("input_partial_link_symbol_records"),
        GpuSourcePackRecordArrayDescriptor::pending("input_partial_link_unresolved_symbol_records"),
        GpuSourcePackRecordArrayDescriptor::pending("input_partial_link_relocation_records"),
    ]);
    descriptor_records.extend([
        descriptor_record(
            "input_partial_link_sections",
            GpuSourcePackDescriptorRecordDomain::PartialLink,
            GpuSourcePackDescriptorRecordKind::Section,
            GpuSourcePackDescriptorRecordFlow::Input,
            "input_partial_link_section_records",
        ),
        descriptor_record(
            "input_partial_link_symbols",
            GpuSourcePackDescriptorRecordDomain::PartialLink,
            GpuSourcePackDescriptorRecordKind::Symbol,
            GpuSourcePackDescriptorRecordFlow::Input,
            "input_partial_link_symbol_records",
        ),
        descriptor_record(
            "input_partial_link_unresolved_symbols",
            GpuSourcePackDescriptorRecordDomain::PartialLink,
            GpuSourcePackDescriptorRecordKind::UnresolvedSymbol,
            GpuSourcePackDescriptorRecordFlow::Input,
            "input_partial_link_unresolved_symbol_records",
        ),
        descriptor_record(
            "input_partial_link_relocations",
            GpuSourcePackDescriptorRecordDomain::PartialLink,
            GpuSourcePackDescriptorRecordKind::Relocation,
            GpuSourcePackDescriptorRecordFlow::Input,
            "input_partial_link_relocation_records",
        ),
    ]);
}

fn validate_record_array_descriptors(
    label: &str,
    arrays: &[GpuSourcePackRecordArrayDescriptor],
) -> Result<(), String> {
    for (index, array) in arrays.iter().enumerate() {
        if array.name.trim().is_empty() {
            return Err(format!("{label} record array {index} has an empty name"));
        }
        if array.byte_len.is_some() && array.element_count.is_none() {
            return Err(format!(
                "{label} record array {:?} records a byte length without an element count",
                array.name
            ));
        }
        if array
            .storage_key
            .as_ref()
            .is_some_and(|storage_key| storage_key.is_empty())
        {
            return Err(format!(
                "{label} record array {:?} has an empty storage key",
                array.name
            ));
        }
        if arrays[..index]
            .iter()
            .any(|previous| previous.name == array.name)
        {
            return Err(format!(
                "{label} record array {:?} is listed more than once",
                array.name
            ));
        }
        if let Some(storage_key) = array.storage_key.as_ref()
            && let Some(previous) = arrays[..index]
                .iter()
                .find(|previous| previous.storage_key.as_ref() == Some(storage_key))
        {
            return Err(format!(
                "{label} record arrays {:?} and {:?} share storage key {:?}; flat record arrays must have distinct persisted storage",
                previous.name, array.name, storage_key
            ));
        }
    }
    Ok(())
}

fn validate_descriptor_record_refs(
    record_arrays: &[GpuSourcePackRecordArrayDescriptor],
    input_record_arrays: &[GpuSourcePackRecordArrayDescriptor],
    output_record_arrays: &[GpuSourcePackRecordArrayDescriptor],
    descriptor_records: &[GpuSourcePackDescriptorRecord],
) -> Result<(), String> {
    let record_array_names = record_arrays
        .iter()
        .map(|array| array.name.as_str())
        .collect::<BTreeSet<_>>();
    let input_record_array_names = input_record_arrays
        .iter()
        .map(|array| array.name.as_str())
        .collect::<BTreeSet<_>>();
    let output_record_array_names = output_record_arrays
        .iter()
        .map(|array| array.name.as_str())
        .collect::<BTreeSet<_>>();
    let validate_split_record_arrays =
        !input_record_array_names.is_empty() || !output_record_array_names.is_empty();
    let mut seen_record_names = BTreeSet::new();
    for (index, record) in descriptor_records.iter().enumerate() {
        if record.name.trim().is_empty() {
            return Err("descriptor record has an empty name".into());
        }
        if !seen_record_names.insert(record.name.as_str()) {
            return Err(format!(
                "descriptor record name {:?} is listed more than once; section/symbol/unresolved-symbol/relocation record names must be unique within an artifact descriptor",
                record.name
            ));
        }
        if record.record_array.trim().is_empty() {
            return Err(format!(
                "descriptor record {:?} has an empty record-array reference",
                record.name
            ));
        }
        if !record_array_names.contains(record.record_array.as_str()) {
            return Err(format!(
                "descriptor record {:?} references unknown record array {:?}",
                record.name, record.record_array
            ));
        }
        if let Some(record_element_count) = record.element_count {
            let record_array = record_arrays
                .iter()
                .find(|array| array.name == record.record_array)
                .expect("descriptor record array membership was validated above");
            let Some(array_element_count) = record_array.element_count else {
                return Err(format!(
                    "descriptor record {:?} declares element count {} but record array {:?} is unbounded; counted descriptor records must be backed by counted flat record arrays",
                    record.name, record_element_count, record.record_array
                ));
            };
            if record_element_count > array_element_count {
                return Err(format!(
                    "descriptor record {:?} declares element count {} exceeding record array {:?} element count {}",
                    record.name, record_element_count, record.record_array, array_element_count
                ));
            }
            if record_element_count < array_element_count {
                return Err(format!(
                    "descriptor record {:?} declares element count {} but record array {:?} declares {}; descriptor records must cover their backing flat record array exactly",
                    record.name, record_element_count, record.record_array, array_element_count
                ));
            }
        }
        if validate_split_record_arrays {
            let (expected_label, expected_record_array_names) = match record.flow {
                GpuSourcePackDescriptorRecordFlow::Input => ("input", &input_record_array_names),
                GpuSourcePackDescriptorRecordFlow::Output => ("output", &output_record_array_names),
            };
            if !expected_record_array_names.contains(record.record_array.as_str()) {
                return Err(format!(
                    "descriptor record {:?} has {:?} flow but references record array {:?} outside {expected_label} record arrays",
                    record.name, record.flow, record.record_array
                ));
            }
        }
        validate_reserved_record_array_shape(record)?;
        if let Some(previous) = descriptor_records[..index]
            .iter()
            .find(|previous| previous.record_array == record.record_array)
        {
            if previous.domain != record.domain
                || previous.kind != record.kind
                || previous.flow != record.flow
            {
                return Err(format!(
                    "descriptor record array {:?} is described as both {:?} {:?} {:?} by {:?} and {:?} {:?} {:?} by {:?}",
                    record.record_array,
                    previous.domain,
                    previous.kind,
                    previous.flow,
                    previous.name,
                    record.domain,
                    record.kind,
                    record.flow,
                    record.name
                ));
            }
            return Err(format!(
                "descriptor record array {:?} is described more than once by descriptor records {:?} and {:?}; flat link record arrays must have exactly one semantic descriptor",
                record.record_array, previous.name, record.name
            ));
        }
    }
    Ok(())
}

fn validate_reserved_record_array_coverage(
    record_arrays: &[GpuSourcePackRecordArrayDescriptor],
    descriptor_records: &[GpuSourcePackDescriptorRecord],
) -> Result<(), String> {
    for array in record_arrays {
        let Some((expected_domain, expected_kind)) =
            descriptor_record_array_shape(array.name.as_str())
        else {
            continue;
        };
        let matching_records = descriptor_records
            .iter()
            .filter(|record| record.record_array == array.name)
            .collect::<Vec<_>>();
        let descriptor_record_count = matching_records.len();
        if descriptor_record_count == 0 {
            return Err(format!(
                "reserved record array {:?} must be described by exactly one descriptor record as {:?} {:?}",
                array.name, expected_domain, expected_kind
            ));
        }
        if descriptor_record_count > 1 {
            return Err(format!(
                "reserved record array {:?} is described by {} descriptor records; reserved flat record arrays must have exactly one descriptor record",
                array.name, descriptor_record_count
            ));
        }
        let record = matching_records[0];
        if let Some(array_element_count) = array.element_count {
            match record.element_count {
                Some(record_element_count) if record_element_count == array_element_count => {}
                Some(record_element_count) => {
                    return Err(format!(
                        "reserved record array {:?} declares element count {} but descriptor record {:?} declares {}; bounded reserved arrays must be counted exactly once",
                        array.name, array_element_count, record.name, record_element_count
                    ));
                }
                None => {
                    return Err(format!(
                        "reserved record array {:?} declares element count {} but descriptor record {:?} does not declare an element count; bounded reserved arrays must be counted by their descriptor record",
                        array.name, array_element_count, record.name
                    ));
                }
            }
        }
    }
    Ok(())
}

fn require_descriptor_record(
    descriptor: &GpuSourcePackArtifactDescriptor,
    domain: GpuSourcePackDescriptorRecordDomain,
    kind: GpuSourcePackDescriptorRecordKind,
    flow: GpuSourcePackDescriptorRecordFlow,
    message: &'static str,
) -> Result<(), String> {
    descriptor
        .descriptor_records
        .iter()
        .any(|record| record.domain == domain && record.kind == kind && record.flow == flow)
        .then_some(())
        .ok_or_else(|| message.into())
}

fn reject_descriptor_record(
    descriptor: &GpuSourcePackArtifactDescriptor,
    domain: GpuSourcePackDescriptorRecordDomain,
    kind: GpuSourcePackDescriptorRecordKind,
    flow: GpuSourcePackDescriptorRecordFlow,
    message: &'static str,
) -> Result<(), String> {
    if descriptor
        .descriptor_records
        .iter()
        .any(|record| record.domain == domain && record.kind == kind && record.flow == flow)
    {
        return Err(message.into());
    }
    Ok(())
}

fn reject_descriptor_record_kind(
    descriptor: &GpuSourcePackArtifactDescriptor,
    kind: GpuSourcePackDescriptorRecordKind,
    message: &'static str,
) -> Result<(), String> {
    if descriptor
        .descriptor_records
        .iter()
        .any(|record| record.kind == kind)
    {
        return Err(message.into());
    }
    Ok(())
}

fn reject_descriptor_domain(
    descriptor: &GpuSourcePackArtifactDescriptor,
    domain: GpuSourcePackDescriptorRecordDomain,
    message: &'static str,
) -> Result<(), String> {
    if descriptor
        .descriptor_records
        .iter()
        .any(|record| record.domain == domain)
    {
        return Err(message.into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::compiler::SourcePackHierarchicalLinkGroupKind;

    fn job(phase: SourcePackJobPhase) -> SourcePackJob {
        SourcePackJob {
            job_index: match phase {
                SourcePackJobPhase::LibraryFrontend => 1,
                SourcePackJobPhase::Codegen => 2,
                SourcePackJobPhase::Link => 3,
            },
            phase,
            phase_unit_index: 0,
            library_job_index: Some(0),
            library_id: 7,
            first_source_index: 11,
            source_file_count: 2,
            source_bytes: 128,
            source_lines: 9,
            oversized_source_file: false,
            dependency_job_indices: Vec::new(),
        }
    }

    fn link_page(final_output: bool) -> SourcePackHierarchicalLinkExecutionPage {
        SourcePackHierarchicalLinkExecutionPage {
            version: 1,
            target: SourcePackArtifactTarget::Wasm,
            group_index: if final_output { 1 } else { 0 },
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: 90,
            input_interface_count: 1,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 1,
            input_object_page_count: 0,
            input_objects: Vec::new(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 128,
            source_file_count: 2,
            source_line_count: 9,
            output_key: if final_output {
                "wasm/linked-output/job-90/src-0-2".into()
            } else {
                "wasm/partial-link/group-00000000/job-00000090".into()
            },
            final_output,
            descriptor_summary: Default::default(),
        }
    }

    fn reduce_link_page(final_output: bool) -> SourcePackHierarchicalLinkExecutionPage {
        SourcePackHierarchicalLinkExecutionPage {
            version: 1,
            target: SourcePackArtifactTarget::Wasm,
            group_index: 2,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            job_index: 92,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: Vec::new(),
            input_group_count: 2,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 128,
            source_file_count: 2,
            source_line_count: 9,
            output_key: if final_output {
                "wasm/linked-output/job-92/src-0-2".into()
            } else {
                "wasm/partial-link/group-00000002/job-00000092".into()
            },
            final_output,
            descriptor_summary: Default::default(),
        }
    }

    fn descriptor_has_record(
        descriptor: &GpuSourcePackArtifactDescriptor,
        domain: GpuSourcePackDescriptorRecordDomain,
        kind: GpuSourcePackDescriptorRecordKind,
        flow: GpuSourcePackDescriptorRecordFlow,
    ) -> bool {
        descriptor
            .descriptor_records
            .iter()
            .any(|record| record.domain == domain && record.kind == kind && record.flow == flow)
    }

    #[test]
    fn artifact_descriptor_records_distinguish_stage_contracts() {
        let interface = GpuSourcePackArtifactDescriptor::library_interface_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::LibraryFrontend),
            GpuSourcePackDependencyInterfaceSummary::counted(1, 1),
        );
        interface
            .validate_contract()
            .expect("library interface descriptor is valid");

        let codegen = GpuSourcePackArtifactDescriptor::codegen_object_contract_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::Codegen),
            GpuSourcePackDependencyInterfaceSummary::counted(1, 1),
        );
        codegen
            .validate_contract()
            .expect("codegen object descriptor is valid");

        let partial = GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(
            &link_page(false),
            1,
            1,
            0,
        );
        partial
            .validate_contract()
            .expect("partial link descriptor is valid");

        let linked = GpuSourcePackArtifactDescriptor::hierarchical_linked_output_contract_for_page(
            &link_page(true),
            0,
            0,
            1,
        );
        linked
            .validate_contract()
            .expect("linked output descriptor is valid");
    }

    #[test]
    fn artifact_descriptor_link_input_records_follow_dependency_counts() {
        let partial_leaf = GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(
            &link_page(false),
            1,
            1,
            0,
        );
        partial_leaf
            .validate_contract()
            .expect("leaf partial link descriptor is valid");
        assert!(descriptor_has_record(
            &partial_leaf,
            GpuSourcePackDescriptorRecordDomain::Interface,
            GpuSourcePackDescriptorRecordKind::Symbol,
            GpuSourcePackDescriptorRecordFlow::Input
        ));
        assert!(descriptor_has_record(
            &partial_leaf,
            GpuSourcePackDescriptorRecordDomain::Object,
            GpuSourcePackDescriptorRecordKind::Relocation,
            GpuSourcePackDescriptorRecordFlow::Input
        ));
        assert!(!descriptor_has_record(
            &partial_leaf,
            GpuSourcePackDescriptorRecordDomain::PartialLink,
            GpuSourcePackDescriptorRecordKind::Relocation,
            GpuSourcePackDescriptorRecordFlow::Input
        ));

        let partial_reduce = GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(
            &reduce_link_page(false),
            0,
            0,
            2,
        );
        partial_reduce
            .validate_contract()
            .expect("reduce partial link descriptor is valid");
        assert!(descriptor_has_record(
            &partial_reduce,
            GpuSourcePackDescriptorRecordDomain::PartialLink,
            GpuSourcePackDescriptorRecordKind::Relocation,
            GpuSourcePackDescriptorRecordFlow::Input
        ));
        assert!(!descriptor_has_record(
            &partial_reduce,
            GpuSourcePackDescriptorRecordDomain::Object,
            GpuSourcePackDescriptorRecordKind::Relocation,
            GpuSourcePackDescriptorRecordFlow::Input
        ));

        let linked_leaf =
            GpuSourcePackArtifactDescriptor::hierarchical_linked_output_contract_for_page(
                &link_page(true),
                1,
                1,
                0,
            );
        linked_leaf
            .validate_contract()
            .expect("leaf linked output descriptor is valid");
        assert!(descriptor_has_record(
            &linked_leaf,
            GpuSourcePackDescriptorRecordDomain::Interface,
            GpuSourcePackDescriptorRecordKind::Symbol,
            GpuSourcePackDescriptorRecordFlow::Input
        ));
        assert!(descriptor_has_record(
            &linked_leaf,
            GpuSourcePackDescriptorRecordDomain::Object,
            GpuSourcePackDescriptorRecordKind::Relocation,
            GpuSourcePackDescriptorRecordFlow::Input
        ));
        assert!(!descriptor_has_record(
            &linked_leaf,
            GpuSourcePackDescriptorRecordDomain::PartialLink,
            GpuSourcePackDescriptorRecordKind::Relocation,
            GpuSourcePackDescriptorRecordFlow::Input
        ));

        let linked_reduce =
            GpuSourcePackArtifactDescriptor::hierarchical_linked_output_contract_for_page(
                &reduce_link_page(true),
                0,
                0,
                2,
            );
        linked_reduce
            .validate_contract()
            .expect("reduce linked output descriptor is valid");
        assert!(descriptor_has_record(
            &linked_reduce,
            GpuSourcePackDescriptorRecordDomain::PartialLink,
            GpuSourcePackDescriptorRecordKind::Relocation,
            GpuSourcePackDescriptorRecordFlow::Input
        ));
        assert!(!descriptor_has_record(
            &linked_reduce,
            GpuSourcePackDescriptorRecordDomain::Object,
            GpuSourcePackDescriptorRecordKind::Relocation,
            GpuSourcePackDescriptorRecordFlow::Input
        ));
    }

    #[test]
    fn artifact_descriptor_dependency_counts_require_input_records() {
        let mut linked = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::Link),
            1,
            1,
        );
        linked.descriptor_records.retain(|record| {
            record.domain != GpuSourcePackDescriptorRecordDomain::Interface
                || record.kind != GpuSourcePackDescriptorRecordKind::Symbol
                || record.flow != GpuSourcePackDescriptorRecordFlow::Input
        });
        let err = linked
            .validate_contract()
            .expect_err("interface dependencies require input interface records");
        assert!(err.contains("input interface symbols"));

        let mut linked = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::Link),
            0,
            1,
        );
        linked.descriptor_records.retain(|record| {
            record.domain != GpuSourcePackDescriptorRecordDomain::Object
                || record.kind != GpuSourcePackDescriptorRecordKind::Relocation
                || record.flow != GpuSourcePackDescriptorRecordFlow::Input
        });
        let err = linked
            .validate_contract()
            .expect_err("object dependencies require input relocation records");
        assert!(err.contains("input object relocations"));

        let mut partial = GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(
            &reduce_link_page(false),
            0,
            0,
            1,
        );
        partial.descriptor_records.retain(|record| {
            record.domain != GpuSourcePackDescriptorRecordDomain::PartialLink
                || record.kind != GpuSourcePackDescriptorRecordKind::Relocation
                || record.flow != GpuSourcePackDescriptorRecordFlow::Input
        });
        let err = partial
            .validate_contract()
            .expect_err("partial-link dependencies require input relocation records");
        assert!(err.contains("input partial-link relocations"));
    }

    #[test]
    fn artifact_descriptor_records_reject_cross_stage_shapes() {
        let mut interface = GpuSourcePackArtifactDescriptor::library_interface_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::LibraryFrontend),
            GpuSourcePackDependencyInterfaceSummary::default(),
        );
        let accidental_section_array =
            GpuSourcePackRecordArrayDescriptor::pending("accidental_object_section_records");
        interface
            .output_record_arrays
            .push(accidental_section_array.clone());
        interface.record_arrays.push(accidental_section_array);
        interface.descriptor_records.push(descriptor_record(
            "accidental_object_section",
            GpuSourcePackDescriptorRecordDomain::Object,
            GpuSourcePackDescriptorRecordKind::Section,
            GpuSourcePackDescriptorRecordFlow::Output,
            "accidental_object_section_records",
        ));
        let err = interface
            .validate_contract()
            .expect_err("library interface must reject object sections");
        assert!(err.contains("library-interface descriptor must not describe object sections"));

        let mut codegen = GpuSourcePackArtifactDescriptor::codegen_object_contract_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::Codegen),
            GpuSourcePackDependencyInterfaceSummary::default(),
        );
        codegen.descriptor_records.retain(|record| {
            record.kind != GpuSourcePackDescriptorRecordKind::Relocation
                || record.domain != GpuSourcePackDescriptorRecordDomain::Object
        });
        let err = codegen
            .validate_contract()
            .expect_err("codegen object must declare relocation records");
        assert!(err.contains("codegen-object descriptor must describe output object relocations"));

        let partial = GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(
            &link_page(false),
            0,
            0,
            0,
        );
        let err = partial
            .validate_contract()
            .expect_err("partial link must consume object or partial-link records");
        assert!(err.contains("partial-link descriptor must consume object or partial-link inputs"));

        let mut linked =
            GpuSourcePackArtifactDescriptor::hierarchical_linked_output_contract_for_page(
                &link_page(true),
                0,
                0,
                1,
            );
        let bad_relocation_array =
            GpuSourcePackRecordArrayDescriptor::pending("bad_final_relocation_records");
        linked
            .output_record_arrays
            .push(bad_relocation_array.clone());
        linked.record_arrays.push(bad_relocation_array);
        linked.descriptor_records.push(descriptor_record(
            "bad_final_relocations",
            GpuSourcePackDescriptorRecordDomain::LinkedOutput,
            GpuSourcePackDescriptorRecordKind::Relocation,
            GpuSourcePackDescriptorRecordFlow::Output,
            "bad_final_relocation_records",
        ));
        let err = linked
            .validate_contract()
            .expect_err("final linked output must not emit unresolved relocations");
        assert!(
            err.contains(
                "linked-output descriptor must not emit unresolved relocation descriptors"
            )
        );
    }

    #[test]
    fn artifact_descriptor_records_must_reference_declared_arrays() {
        let mut descriptor = GpuSourcePackArtifactDescriptor::codegen_object_contract_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::Codegen),
            GpuSourcePackDependencyInterfaceSummary::default(),
        );
        descriptor.descriptor_records.push(descriptor_record(
            "dangling_descriptor_record",
            GpuSourcePackDescriptorRecordDomain::Object,
            GpuSourcePackDescriptorRecordKind::Symbol,
            GpuSourcePackDescriptorRecordFlow::Output,
            "missing_symbol_records",
        ));
        let err = descriptor
            .validate_contract()
            .expect_err("descriptor records must point at a declared array");
        assert!(err.contains("references unknown record array"));
    }

    #[test]
    fn artifact_descriptor_record_arrays_have_one_semantic_descriptor() {
        let mut descriptor = GpuSourcePackArtifactDescriptor::codegen_object_contract_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::Codegen),
            GpuSourcePackDependencyInterfaceSummary::default(),
        );
        let array = GpuSourcePackRecordArrayDescriptor::pending("object_debug_symbol_records");
        descriptor.output_record_arrays.push(array.clone());
        descriptor.record_arrays.push(array);
        descriptor.descriptor_records.extend([
            descriptor_record(
                "debug_symbols_primary",
                GpuSourcePackDescriptorRecordDomain::Object,
                GpuSourcePackDescriptorRecordKind::Symbol,
                GpuSourcePackDescriptorRecordFlow::Output,
                "object_debug_symbol_records",
            ),
            descriptor_record(
                "debug_symbols_duplicate",
                GpuSourcePackDescriptorRecordDomain::Object,
                GpuSourcePackDescriptorRecordKind::Symbol,
                GpuSourcePackDescriptorRecordFlow::Output,
                "object_debug_symbol_records",
            ),
        ]);

        let err = descriptor
            .validate_contract()
            .expect_err("one flat record array must not have duplicate semantic descriptors");
        assert!(err.contains("object_debug_symbol_records"));
        assert!(err.contains("exactly one semantic descriptor"));
    }

    #[test]
    fn artifact_descriptor_record_arrays_require_distinct_storage_keys() {
        let mut descriptor = GpuSourcePackArtifactDescriptor::codegen_object_contract_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::Codegen),
            GpuSourcePackDependencyInterfaceSummary::default(),
        );
        let shared_storage_key = Some("object-record-storage".to_string());
        descriptor
            .output_record_arrays
            .iter_mut()
            .find(|array| array.name == "object_section_records")
            .expect("codegen descriptor has object sections")
            .storage_key = shared_storage_key.clone();
        descriptor
            .output_record_arrays
            .iter_mut()
            .find(|array| array.name == "object_symbol_records")
            .expect("codegen descriptor has object symbols")
            .storage_key = shared_storage_key;
        descriptor.record_arrays = GpuSourcePackArtifactDescriptor::combined_record_arrays(
            &descriptor.input_record_arrays,
            &descriptor.output_record_arrays,
        );

        let err = descriptor
            .validate_contract()
            .expect_err("distinct flat record arrays must not alias persisted storage");
        assert!(err.contains("object_section_records"));
        assert!(err.contains("object_symbol_records"));
        assert!(err.contains("distinct persisted storage"));
    }

    #[test]
    fn artifact_descriptor_reserved_record_arrays_pin_row_kind() {
        let descriptor = GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(
            &link_page(false),
            1,
            1,
            0,
        );
        descriptor
            .validate_contract()
            .expect("baseline partial-link descriptor is valid");
        let mut document =
            serde_json::to_value(&descriptor).expect("serialize partial-link descriptor as JSON");

        let descriptor_records = document
            .get_mut("descriptor_records")
            .and_then(serde_json::Value::as_array_mut)
            .expect("descriptor JSON should include descriptor records");
        let unresolved_record = descriptor_records
            .iter_mut()
            .find(|record| {
                record
                    .get("record_array")
                    .and_then(serde_json::Value::as_str)
                    == Some("partial_link_unresolved_symbol_records")
            })
            .expect("descriptor JSON should include partial-link unresolved symbols");
        unresolved_record["kind"] = serde_json::Value::String("Symbol".into());

        let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document)
            .expect("parse descriptor JSON with retyped unresolved-symbol rows");
        let parsed_unresolved_record = parsed
            .descriptor_records
            .iter()
            .find(|record| record.record_array == "partial_link_unresolved_symbol_records")
            .expect("parsed descriptor should retain the retyped unresolved row");
        assert_eq!(
            parsed_unresolved_record.kind,
            GpuSourcePackDescriptorRecordKind::Symbol
        );
        let err = parsed
            .validate_contract()
            .expect_err("reserved unresolved-symbol rows must keep their semantic row kind");
        assert!(err.contains("reserved record array"));
        assert!(err.contains("partial_link_unresolved_symbol_records"));
        assert!(err.contains("UnresolvedSymbol"));
    }

    #[test]
    fn artifact_descriptor_record_counts_cannot_exceed_array_counts() {
        let descriptor = GpuSourcePackArtifactDescriptor::codegen_object_contract_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::Codegen),
            GpuSourcePackDependencyInterfaceSummary::default(),
        );
        let mut document =
            serde_json::to_value(&descriptor).expect("serialize codegen descriptor as JSON value");

        for arrays_key in ["output_record_arrays", "record_arrays"] {
            let arrays = document
                .get_mut(arrays_key)
                .and_then(serde_json::Value::as_array_mut)
                .unwrap_or_else(|| panic!("descriptor JSON should include {arrays_key}"));
            let object_symbol_array = arrays
                .iter_mut()
                .find(|array| {
                    array.get("name").and_then(serde_json::Value::as_str)
                        == Some("object_symbol_records")
                })
                .unwrap_or_else(|| panic!("{arrays_key} should include object symbol records"));
            object_symbol_array["element_count"] = serde_json::Value::from(1);
        }

        let descriptor_records = document
            .get_mut("descriptor_records")
            .and_then(serde_json::Value::as_array_mut)
            .expect("descriptor JSON should include descriptor records");
        let object_symbol_record = descriptor_records
            .iter_mut()
            .find(|record| {
                record.get("name").and_then(serde_json::Value::as_str) == Some("object_symbols")
            })
            .expect("descriptor JSON should include object symbol descriptor record");
        object_symbol_record["element_count"] = serde_json::Value::from(2);

        let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document)
            .expect("parse descriptor JSON with mismatched record count");
        let err = parsed
            .validate_contract()
            .expect_err("descriptor records must not exceed their record array count");
        assert!(err.contains("exceeding record array"));
        assert!(err.contains("object_symbol_records"));
    }

    #[test]
    fn artifact_descriptor_record_counts_must_cover_bounded_arrays_exactly() {
        let descriptor = GpuSourcePackArtifactDescriptor::codegen_object_contract_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::Codegen),
            GpuSourcePackDependencyInterfaceSummary::default(),
        );
        let mut document =
            serde_json::to_value(&descriptor).expect("serialize codegen descriptor as JSON value");

        for arrays_key in ["output_record_arrays", "record_arrays"] {
            let arrays = document
                .get_mut(arrays_key)
                .and_then(serde_json::Value::as_array_mut)
                .unwrap_or_else(|| panic!("descriptor JSON should include {arrays_key}"));
            let object_symbol_array = arrays
                .iter_mut()
                .find(|array| {
                    array.get("name").and_then(serde_json::Value::as_str)
                        == Some("object_symbol_records")
                })
                .unwrap_or_else(|| panic!("{arrays_key} should include object symbol records"));
            object_symbol_array["element_count"] = serde_json::Value::from(2);
        }

        let descriptor_records = document
            .get_mut("descriptor_records")
            .and_then(serde_json::Value::as_array_mut)
            .expect("descriptor JSON should include descriptor records");
        let object_symbol_record = descriptor_records
            .iter_mut()
            .find(|record| {
                record.get("name").and_then(serde_json::Value::as_str) == Some("object_symbols")
            })
            .expect("descriptor JSON should include object symbol descriptor record");
        object_symbol_record["element_count"] = serde_json::Value::from(1);

        let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document)
            .expect("parse descriptor JSON with partial record count");
        assert_eq!(
            parsed
                .descriptor_records
                .iter()
                .find(|record| record.name == "object_symbols")
                .and_then(|record| record.element_count),
            Some(1),
            "parsed descriptor should retain the ambiguous record count"
        );
        let err = parsed
            .validate_contract()
            .expect_err("descriptor record counts must cover bounded arrays exactly");
        assert!(err.contains("cover their backing flat record array exactly"));
        assert!(err.contains("object_symbol_records"));
    }

    #[test]
    fn artifact_descriptor_runtime_service_ids_are_known_and_unique() {
        let mut descriptor = GpuSourcePackArtifactDescriptor::codegen_object_contract_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::Codegen),
            GpuSourcePackDependencyInterfaceSummary::default(),
        );
        descriptor.set_required_runtime_services([GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID, 99]);
        let err = descriptor
            .validate_contract()
            .expect_err("unknown runtime service ids must be rejected");
        assert!(err.contains("unknown runtime service id 99"));

        descriptor.required_runtime_service_ids = vec![
            GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
            GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        ];
        descriptor.required_runtime_abi_version = Some(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION);
        descriptor.runtime_abi = Some(GpuSourcePackRuntimeAbiMetadata::current());
        descriptor.required_runtime_services = vec![
            GpuSourcePackRuntimeServiceRequirement::contract_only(
                GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
            ),
            GpuSourcePackRuntimeServiceRequirement::contract_only(
                GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
            ),
        ];
        let err = descriptor
            .validate_contract()
            .expect_err("duplicate runtime service ids must be rejected");
        assert!(err.contains("runtime service id 3 more than once"));
    }

    #[test]
    fn artifact_descriptor_runtime_service_ids_are_canonicalized_and_validated() {
        let mut descriptor = GpuSourcePackArtifactDescriptor::codegen_object_contract_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::Codegen),
            GpuSourcePackDependencyInterfaceSummary::default(),
        );
        descriptor.set_required_runtime_services([
            GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
            GPU_SOURCE_PACK_RUNTIME_SERVICE_ALLOCATOR_ID,
            GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        ]);
        assert_eq!(
            descriptor.required_runtime_service_ids,
            vec![
                GPU_SOURCE_PACK_RUNTIME_SERVICE_ALLOCATOR_ID,
                GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
            ],
            "public descriptor builders should persist runtime service ids as a canonical set"
        );
        descriptor
            .validate_contract()
            .expect("canonical runtime service ids are valid metadata");

        let mut document =
            serde_json::to_value(&descriptor).expect("serialize runtime descriptor to JSON");
        document["required_runtime_service_ids"] = serde_json::json!([
            GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
            GPU_SOURCE_PACK_RUNTIME_SERVICE_ALLOCATOR_ID,
        ]);
        let parsed = serde_json::from_value::<GpuSourcePackArtifactDescriptor>(document)
            .expect("parse descriptor JSON with non-canonical runtime service ids");
        let err = parsed
            .validate_contract()
            .expect_err("persisted runtime service ids must be canonical");
        assert!(err.contains("strictly ascending order"));
        assert!(err.contains("service id 1 follows 3"));
    }

    #[test]
    fn artifact_descriptor_runtime_services_require_current_abi_version() {
        let mut descriptor = GpuSourcePackArtifactDescriptor::codegen_object_contract_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::Codegen),
            GpuSourcePackDependencyInterfaceSummary::default(),
        );
        descriptor
            .required_runtime_service_ids
            .push(GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID);
        let err = descriptor
            .validate_contract()
            .expect_err("runtime-bound descriptors must pin the ABI version");
        assert!(err.contains("must declare runtime ABI version 1"));

        descriptor.required_runtime_abi_version = Some(GPU_SOURCE_PACK_UNKNOWN_RUNTIME_ABI_VERSION);
        let err = descriptor
            .validate_contract()
            .expect_err("unknown runtime ABI version is not a runtime-bound contract");
        assert!(err.contains("unknown runtime ABI version 0"));

        descriptor.required_runtime_abi_version = Some(99);
        let err = descriptor
            .validate_contract()
            .expect_err("unsupported runtime ABI versions must be rejected");
        assert!(err.contains("unsupported runtime ABI version 99"));

        descriptor.required_runtime_service_ids.clear();
        descriptor.required_runtime_abi_version = Some(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION);
        let err = descriptor
            .validate_contract()
            .expect_err("runtime ABI version without services must be rejected");
        assert!(err.contains("without required runtime service ids"));

        descriptor.set_required_runtime_services([GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID]);
        descriptor
            .validate_contract()
            .expect("current runtime ABI version and known service id is valid metadata");
    }

    #[test]
    fn artifact_descriptor_linked_outputs_require_one_target_byte_array() {
        let mut descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::Link),
            0,
            1,
        );
        descriptor
            .validate_contract()
            .expect("baseline linked-output descriptor carries one target-byte array");

        descriptor
            .output_record_arrays
            .retain(|array| array.name != "emitted_byte_records");
        descriptor
            .record_arrays
            .retain(|array| array.name != "emitted_byte_records");
        let err = descriptor
            .validate_contract()
            .expect_err("non-runtime linked outputs must declare byte-stream evidence");
        assert!(err.contains("exactly one target-byte output record array"));

        let mut descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::Link),
            0,
            1,
        );
        let extra_target_bytes = GpuSourcePackRecordArrayDescriptor::pending("wasm_module_bytes");
        descriptor
            .output_record_arrays
            .push(extra_target_bytes.clone());
        descriptor.record_arrays.push(extra_target_bytes);
        let err = descriptor
            .validate_contract()
            .expect_err("linked outputs must not publish ambiguous target-byte streams");
        assert!(err.contains("found 2"));
        assert!(err.contains("emitted_byte_records"));
        assert!(err.contains("wasm_module_bytes"));
    }

    #[test]
    fn artifact_descriptor_runtime_bound_outputs_cannot_claim_target_bytes() {
        let mut descriptor = GpuSourcePackArtifactDescriptor::linked_output_contract_for_job(
            SourcePackArtifactTarget::Wasm,
            &job(SourcePackJobPhase::Link),
            0,
            1,
        );
        descriptor
            .validate_contract()
            .expect("plain descriptor contract remains valid");

        descriptor.set_required_runtime_services([GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID]);
        let err = descriptor
            .validate_contract()
            .expect_err("runtime-bound output must not declare target-byte records");
        assert!(err.contains("target-byte output record array"));
        assert!(err.contains("unbound runtime services"));

        descriptor
            .output_record_arrays
            .retain(|array| array.name != "emitted_byte_records");
        descriptor
            .record_arrays
            .retain(|array| array.name != "emitted_byte_records");
        descriptor
            .validate_contract()
            .expect("runtime-bound descriptor may remain a contract without emitted bytes");
    }
}

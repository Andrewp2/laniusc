use super::*;
use crate::compiler::{GpuSemanticInterfaceArtifact, GpuSemanticInterfaceDependencyBatch};

/// GPU-resident canonical interfaces imported by one bounded compilation unit.
/// The buffers are immutable except for the parallel module lookup table.
#[derive(Clone)]
pub(crate) struct GpuDependencyInterfaceState {
    pub(crate) module_count: u32,
    pub(crate) declaration_count: u32,
    pub(crate) type_count: u32,
    pub(crate) member_count: u32,
    pub(crate) module_lookup_capacity: u32,
    pub(crate) counts: LaniusBuffer<u32>,
    pub(crate) module_library_id: LaniusBuffer<u32>,
    pub(crate) module_unit_id: LaniusBuffer<u32>,
    pub(crate) module_local_index: LaniusBuffer<u32>,
    pub(crate) module_words: LaniusBuffer<u32>,
    pub(crate) module_segment_words: LaniusBuffer<u32>,
    pub(crate) declaration_library_id: LaniusBuffer<u32>,
    pub(crate) declaration_unit_id: LaniusBuffer<u32>,
    pub(crate) declaration_local_index: LaniusBuffer<u32>,
    pub(crate) declaration_words: LaniusBuffer<u32>,
    pub(crate) type_words: LaniusBuffer<u32>,
    pub(crate) type_edge_words: LaniusBuffer<u32>,
    pub(crate) member_words: LaniusBuffer<u32>,
    pub(crate) name_byte_words: LaniusBuffer<u32>,
    pub(crate) module_lookup: LaniusBuffer<u32>,
}

impl GpuDependencyInterfaceState {
    pub(crate) fn new(
        device: &wgpu::Device,
        current_library_id: u32,
        current_unit_id: u32,
        interfaces: &[GpuSemanticInterfaceArtifact],
    ) -> Result<Self> {
        let batch = GpuSemanticInterfaceDependencyBatch::from_interfaces(
            current_library_id,
            current_unit_id,
            interfaces,
        )
        .map_err(anyhow::Error::msg)?;
        let module_count = u32::try_from(batch.modules.len())
            .map_err(|_| anyhow::anyhow!("dependency module count exceeds u32"))?;
        let declaration_count = u32::try_from(batch.declarations.len())
            .map_err(|_| anyhow::anyhow!("dependency declaration count exceeds u32"))?;
        let type_count = u32::try_from(batch.types.len())
            .map_err(|_| anyhow::anyhow!("dependency type count exceeds u32"))?;
        let member_count = u32::try_from(batch.members.len())
            .map_err(|_| anyhow::anyhow!("dependency member count exceeds u32"))?;
        let module_lookup_capacity = module_count
            .checked_mul(2)
            .and_then(u32::checked_next_power_of_two)
            .unwrap_or(0)
            .max(1);
        if module_count != 0 && module_lookup_capacity == 1 {
            return Err(anyhow::anyhow!(
                "dependency module lookup capacity overflows u32"
            ));
        }
        let counts = [
            u32::try_from(batch.library_ids.len()).unwrap_or(u32::MAX),
            module_count,
            u32::try_from(batch.module_segments.len()).unwrap_or(u32::MAX),
            u32::try_from(batch.declarations.len()).unwrap_or(u32::MAX),
            u32::try_from(batch.types.len()).unwrap_or(u32::MAX),
            u32::try_from(batch.type_edges.len()).unwrap_or(u32::MAX),
            u32::try_from(batch.members.len()).unwrap_or(u32::MAX),
            u32::try_from(batch.name_bytes.len()).unwrap_or(u32::MAX),
        ];
        let module_words = batch
            .modules
            .iter()
            .flat_map(|module| [module.first_segment, module.segment_count])
            .collect::<Vec<_>>();
        let module_segment_words = batch
            .module_segments
            .iter()
            .flat_map(|segment| {
                [
                    segment.name_hash_lo,
                    segment.name_hash_hi,
                    segment.name_byte_start,
                    segment.name_byte_len,
                ]
            })
            .collect::<Vec<_>>();
        let declaration_words = batch
            .declarations
            .iter()
            .flat_map(|declaration| {
                [
                    declaration.module,
                    declaration.name_hash_lo,
                    declaration.name_hash_hi,
                    declaration.name_byte_start,
                    declaration.name_byte_len,
                    declaration.namespace,
                    declaration.kind,
                    declaration.signature_type,
                    declaration.first_member,
                    declaration.member_count,
                    declaration.owner_declaration,
                    declaration.flags,
                    declaration.value_lo,
                    declaration.value_hi,
                ]
            })
            .collect::<Vec<_>>();
        let type_words = batch
            .types
            .iter()
            .flat_map(|ty| {
                [
                    ty.kind,
                    ty.payload_lo,
                    ty.payload_hi,
                    ty.first_edge,
                    ty.edge_count,
                    ty.length_kind,
                    ty.length_lo,
                    ty.length_hi,
                    ty.nominal_unit_id,
                ]
            })
            .collect::<Vec<_>>();
        let type_edge_words = batch
            .type_edges
            .iter()
            .map(|edge| edge.type_index)
            .collect::<Vec<_>>();
        let member_words = batch
            .members
            .iter()
            .flat_map(|member| {
                [
                    member.owner_declaration,
                    member.kind,
                    member.ordinal,
                    member.name_hash_lo,
                    member.name_hash_hi,
                    member.name_byte_start,
                    member.name_byte_len,
                    member.type_index,
                    member.value_lo,
                    member.value_hi,
                ]
            })
            .collect::<Vec<_>>();
        let mut name_byte_words = Vec::with_capacity(batch.name_bytes.len().div_ceil(4));
        for bytes in batch.name_bytes.chunks(4) {
            let mut word = [0u8; 4];
            word[..bytes.len()].copy_from_slice(bytes);
            name_byte_words.push(u32::from_le_bytes(word));
        }

        Ok(Self {
            module_count,
            declaration_count,
            type_count,
            member_count,
            module_lookup_capacity,
            counts: upload_words(device, "type_check.dependencies.counts", &counts),
            module_library_id: upload_words(
                device,
                "type_check.dependencies.module_library_id",
                &batch.module_library_id,
            ),
            module_unit_id: upload_words(
                device,
                "type_check.dependencies.module_unit_id",
                &batch.module_unit_id,
            ),
            module_local_index: upload_words(
                device,
                "type_check.dependencies.module_local_index",
                &batch.module_local_index,
            ),
            module_words: upload_words(
                device,
                "type_check.dependencies.module_words",
                &module_words,
            ),
            module_segment_words: upload_words(
                device,
                "type_check.dependencies.module_segment_words",
                &module_segment_words,
            ),
            declaration_library_id: upload_words(
                device,
                "type_check.dependencies.declaration_library_id",
                &batch.declaration_library_id,
            ),
            declaration_unit_id: upload_words(
                device,
                "type_check.dependencies.declaration_unit_id",
                &batch.declaration_unit_id,
            ),
            declaration_local_index: upload_words(
                device,
                "type_check.dependencies.declaration_local_index",
                &batch.declaration_local_index,
            ),
            declaration_words: upload_words(
                device,
                "type_check.dependencies.declaration_words",
                &declaration_words,
            ),
            type_words: upload_words(device, "type_check.dependencies.type_words", &type_words),
            type_edge_words: upload_words(
                device,
                "type_check.dependencies.type_edge_words",
                &type_edge_words,
            ),
            member_words: upload_words(
                device,
                "type_check.dependencies.member_words",
                &member_words,
            ),
            name_byte_words: upload_words(
                device,
                "type_check.dependencies.name_byte_words",
                &name_byte_words,
            ),
            module_lookup: typed_storage_u32_fill_rw(
                device,
                "type_check.dependencies.module_lookup",
                module_lookup_capacity as usize,
                u32::MAX,
                wgpu::BufferUsages::empty(),
            ),
        })
    }
}

fn upload_words(device: &wgpu::Device, label: &str, words: &[u32]) -> LaniusBuffer<u32> {
    if words.is_empty() {
        storage_ro_from_u32s(device, label, &[0])
    } else {
        storage_ro_from_u32s(device, label, words)
    }
}

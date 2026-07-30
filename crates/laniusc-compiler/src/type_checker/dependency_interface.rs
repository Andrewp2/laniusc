use super::*;
use crate::compiler::{GpuSemanticInterfaceArtifact, GpuSemanticInterfaceDependencyBatch};

/// GPU-resident canonical interfaces imported by one bounded compilation unit.
/// The packed words are immutable except for the separate parallel module
/// lookup table. Keeping one shader-visible representation makes this state a
/// reusable page slot instead of a collection of independently bound arrays.
#[derive(Clone)]
pub(crate) struct GpuDependencyInterfaceState {
    pub(crate) module_count: u32,
    pub(crate) declaration_count: u32,
    pub(crate) type_count: u32,
    pub(crate) member_count: u32,
    pub(crate) module_lookup_capacity: u32,
    pub(crate) words: LaniusBuffer<u32>,
    pub(crate) module_lookup: LaniusBuffer<u32>,
}

/// One fixed GPU dependency slot plus the CPU-packed pages that are streamed
/// through it. Total project dependency data remains in ordinary host memory;
/// only the largest page contributes to resident GPU capacity.
pub(crate) struct GpuDependencyInterfacePages {
    state: GpuDependencyInterfaceState,
    pages: Vec<PackedGpuDependencyInterfacePage>,
}

/// CPU-packed contents of one dependency page. Packing is separate from GPU
/// allocation so several logical pages can share one physical words/lookup
/// slot once page recording is enabled.
pub(crate) struct PackedGpuDependencyInterfacePage {
    pub(crate) module_count: u32,
    pub(crate) declaration_count: u32,
    pub(crate) type_count: u32,
    pub(crate) member_count: u32,
    pub(crate) module_lookup_capacity: u32,
    pub(crate) words: Vec<u32>,
}

const HEADER_WORDS: usize = 25;
const PAGE_FLAGS_OFFSET: usize = 24;
const MODULE_LIBRARY_OFFSET: usize = 8;
const MODULE_UNIT_OFFSET: usize = 9;
const MODULE_LOCAL_OFFSET: usize = 10;
const MODULE_OFFSET: usize = 11;
const MODULE_SEGMENT_OFFSET: usize = 12;
const DECLARATION_LIBRARY_OFFSET: usize = 13;
const DECLARATION_UNIT_OFFSET: usize = 14;
const DECLARATION_LOCAL_OFFSET: usize = 15;
const DECLARATION_OFFSET: usize = 16;
const TYPE_OFFSET: usize = 17;
const TYPE_EDGE_OFFSET: usize = 18;
const MEMBER_OFFSET: usize = 19;
const NAME_BYTE_OFFSET: usize = 20;
const TYPE_LIBRARY_OFFSET: usize = 21;
const TYPE_UNIT_OFFSET: usize = 22;
const TYPE_LOCAL_OFFSET: usize = 23;

impl PackedGpuDependencyInterfacePage {
    pub(crate) fn new(
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
        let mut words = vec![0; HEADER_WORDS];
        words[..8].copy_from_slice(&[
            u32::try_from(batch.library_ids.len()).unwrap_or(u32::MAX),
            module_count,
            u32::try_from(batch.module_segments.len()).unwrap_or(u32::MAX),
            u32::try_from(batch.declarations.len()).unwrap_or(u32::MAX),
            u32::try_from(batch.types.len()).unwrap_or(u32::MAX),
            u32::try_from(batch.type_edges.len()).unwrap_or(u32::MAX),
            u32::try_from(batch.members.len()).unwrap_or(u32::MAX),
            u32::try_from(batch.name_bytes.len()).unwrap_or(u32::MAX),
        ]);
        append_table(&mut words, MODULE_LIBRARY_OFFSET, &batch.module_library_id)?;
        append_table(&mut words, MODULE_UNIT_OFFSET, &batch.module_unit_id)?;
        append_table(&mut words, MODULE_LOCAL_OFFSET, &batch.module_local_index)?;
        append_records(&mut words, MODULE_OFFSET, batch.modules.iter(), |module| {
            [module.first_segment, module.segment_count]
        })?;
        append_records(
            &mut words,
            MODULE_SEGMENT_OFFSET,
            batch.module_segments.iter(),
            |segment| {
                [
                    segment.name_hash_lo,
                    segment.name_hash_hi,
                    segment.name_byte_start,
                    segment.name_byte_len,
                ]
            },
        )?;
        append_table(
            &mut words,
            DECLARATION_LIBRARY_OFFSET,
            &batch.declaration_library_id,
        )?;
        append_table(
            &mut words,
            DECLARATION_UNIT_OFFSET,
            &batch.declaration_unit_id,
        )?;
        append_table(
            &mut words,
            DECLARATION_LOCAL_OFFSET,
            &batch.declaration_local_index,
        )?;
        append_records(
            &mut words,
            DECLARATION_OFFSET,
            batch.declarations.iter(),
            |declaration| {
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
            },
        )?;
        append_records(&mut words, TYPE_OFFSET, batch.types.iter(), |ty| {
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
        })?;
        append_table(&mut words, TYPE_LIBRARY_OFFSET, &batch.type_library_id)?;
        append_table(&mut words, TYPE_UNIT_OFFSET, &batch.type_unit_id)?;
        append_table(&mut words, TYPE_LOCAL_OFFSET, &batch.type_local_index)?;
        append_records(
            &mut words,
            TYPE_EDGE_OFFSET,
            batch.type_edges.iter(),
            |edge| [edge.type_index],
        )?;
        append_records(&mut words, MEMBER_OFFSET, batch.members.iter(), |member| {
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
        })?;
        let mut name_byte_words = Vec::with_capacity(batch.name_bytes.len().div_ceil(4));
        for bytes in batch.name_bytes.chunks(4) {
            let mut word = [0u8; 4];
            word[..bytes.len()].copy_from_slice(bytes);
            name_byte_words.push(u32::from_le_bytes(word));
        }
        append_table(&mut words, NAME_BYTE_OFFSET, &name_byte_words)?;
        Ok(Self {
            module_count,
            declaration_count,
            type_count,
            member_count,
            module_lookup_capacity,
            words,
        })
    }
}

impl GpuDependencyInterfacePages {
    pub(crate) fn new(
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        current_library_id: u32,
        current_unit_id: u32,
        interface_pages: &[&[GpuSemanticInterfaceArtifact]],
    ) -> Result<Self> {
        if interface_pages.is_empty() {
            anyhow::bail!("dependency page slot requires at least one page");
        }
        let mut pages = interface_pages
            .iter()
            .map(|interfaces| {
                PackedGpuDependencyInterfacePage::new(
                    current_library_id,
                    current_unit_id,
                    interfaces,
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let last = pages.len() - 1;
        for (index, page) in pages.iter_mut().enumerate() {
            page.words[PAGE_FLAGS_OFFSET] = u32::from(index == 0) | (u32::from(index == last) << 1);
        }
        let state = GpuDependencyInterfaceState::from_packed_pages(device, &pages)?;
        let pages = Self { state, pages };
        pages.write(queue, 0)?;
        Ok(pages)
    }

    pub(crate) fn state(&self) -> &GpuDependencyInterfaceState {
        &self.state
    }

    pub(crate) fn write(&self, queue: &wgpu::Queue, page: usize) -> Result<()> {
        let page = self
            .pages
            .get(page)
            .ok_or_else(|| anyhow::anyhow!("dependency page index {page} is out of bounds"))?;
        self.state.write_page(queue, page)
    }

    pub(crate) fn len(&self) -> usize {
        self.pages.len()
    }
}

impl GpuDependencyInterfaceState {
    pub(crate) fn from_packed_pages(
        device: &wgpu::Device,
        pages: &[PackedGpuDependencyInterfacePage],
    ) -> Result<Self> {
        if pages.is_empty() {
            anyhow::bail!("dependency page slot requires at least one page");
        }
        let word_capacity = pages
            .iter()
            .map(|page| page.words.len())
            .max()
            .unwrap_or(1)
            .max(1);
        let module_count = pages
            .iter()
            .map(|page| page.module_count)
            .max()
            .unwrap_or(0);
        let declaration_count = pages
            .iter()
            .map(|page| page.declaration_count)
            .max()
            .unwrap_or(0);
        let type_count = pages.iter().map(|page| page.type_count).max().unwrap_or(0);
        let member_count = pages
            .iter()
            .map(|page| page.member_count)
            .max()
            .unwrap_or(0);
        let module_lookup_capacity = pages
            .iter()
            .map(|page| page.module_lookup_capacity)
            .max()
            .unwrap_or(1)
            .max(1);
        let words = upload_words(
            device,
            "type_check.dependencies.words",
            &vec![0; word_capacity],
        );
        let module_lookup = typed_storage_u32_fill_rw(
            device,
            "type_check.dependencies.module_lookup",
            module_lookup_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );

        Ok(Self {
            module_count,
            declaration_count,
            type_count,
            member_count,
            module_lookup_capacity,
            words,
            module_lookup,
        })
    }

    pub(crate) fn write_page(
        &self,
        queue: &wgpu::Queue,
        page: &PackedGpuDependencyInterfacePage,
    ) -> Result<()> {
        if page.words.len() > self.words.count
            || page.module_lookup_capacity > self.module_lookup_capacity
            || page.module_count > self.module_count
            || page.declaration_count > self.declaration_count
            || page.type_count > self.type_count
            || page.member_count > self.member_count
        {
            anyhow::bail!("dependency page exceeds its fixed GPU slot capacity");
        }
        let bytes = page
            .words
            .iter()
            .copied()
            .flat_map(u32::to_le_bytes)
            .collect::<Vec<_>>();
        queue.write_buffer(&self.words.buffer, 0, &bytes);
        Ok(())
    }
}

fn append_table(words: &mut Vec<u32>, header: usize, table: &[u32]) -> Result<()> {
    words[header] = u32::try_from(words.len())
        .map_err(|_| anyhow::anyhow!("packed dependency interface exceeds u32 words"))?;
    words.extend_from_slice(table);
    Ok(())
}

fn append_records<'a, T: 'a, const N: usize>(
    words: &mut Vec<u32>,
    header: usize,
    records: impl Iterator<Item = &'a T>,
    encode: impl Fn(&T) -> [u32; N],
) -> Result<()> {
    words[header] = u32::try_from(words.len())
        .map_err(|_| anyhow::anyhow!("packed dependency interface exceeds u32 words"))?;
    words.extend(records.flat_map(encode));
    Ok(())
}

fn upload_words(device: &wgpu::Device, label: &str, words: &[u32]) -> LaniusBuffer<u32> {
    storage_ro_from_u32s(device, label, if words.is_empty() { &[0] } else { words })
}

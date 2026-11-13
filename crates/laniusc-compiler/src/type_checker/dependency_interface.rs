use super::*;
use std::sync::Arc;

use crate::compiler::{GpuSemanticInterfaceArtifact, IMPLEMENTATION_OWNER_TAG};

/// GPU-resident canonical interfaces imported by one bounded compilation unit.
/// The packed words are immutable except for the separate parallel module
/// lookup table. Keeping one shader-visible representation makes this state a
/// reusable page slot instead of a collection of independently bound arrays.
#[derive(Clone)]
pub(crate) struct GpuDependencyInterfaceState {
    pub(crate) module_count: u32,
    pub(crate) declaration_count: u32,
    pub(crate) type_count: u32,
    /// Retained immutable constant address span across all pages of the job.
    pub(crate) constant_type_rows: u32,
    pub(crate) member_count: u32,
    pub(crate) predicate_count: u32,
    pub(crate) predicate_argument_count: u32,
    pub(crate) implementation_count: u32,
    pub(crate) implementation_argument_count: u32,
    pub(crate) implementation_method_binding_count: u32,
    pub(crate) module_lookup_capacity: u32,
    pub(crate) words: LaniusBuffer<u32>,
    pub(crate) module_lookup: LaniusBuffer<u32>,
    /// The method index of the page in the slot: two open-address tables of
    /// member rows, rebuilt on the GPU for each page loaded into the slot
    /// (`method_lookup_rows`).
    pub(crate) method_lookup: LaniusBuffer<u32>,
    /// Every page of the job, back to back, resident for the whole job. A
    /// page enters the fixed slot by a GPU copy recorded in order with the
    /// passes that read it, so streaming pages needs neither a host upload
    /// nor a queue submission per page. Grown on demand; not part of the
    /// slot's capacities, so growing it leaves the workspace in place.
    pub(crate) page_store: Option<LaniusBuffer<u32>>,
    /// The packing kernels' inputs, grown on demand (`dependency_pack`).
    pub(crate) pack_buffers: super::dependency_pack::DependencyPackBuffers,
}

/// One fixed GPU dependency slot plus the GPU-packed pages that are streamed
/// through it. The host keeps only each page's layout. The largest page
/// bounds table capacity; retained constant atoms use a checked
/// disjoint span across every page so replay cannot overwrite earlier values.
pub(crate) struct GpuDependencyInterfacePages {
    state: GpuDependencyInterfaceState,
    pages: Vec<GpuDependencyPageLayout>,
    /// Byte offset of each page in the slot state's `page_store` (only with
    /// more than one page).
    page_store_offsets: Vec<u64>,
    current_library_id: u32,
    current_unit_id: u32,
    /// The dependencies' closure summaries (D1b), None without any.
    closure_summaries: Option<Arc<JobClosureSummaries>>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct GpuDependencyInterfaceCapacities {
    words: usize,
    modules: u32,
    declarations: u32,
    types: u32,
    constant_type_rows: u32,
    members: u32,
    predicates: u32,
    predicate_arguments: u32,
    implementations: u32,
    implementation_arguments: u32,
    implementation_method_bindings: u32,
    module_lookup: u32,
}

impl GpuDependencyInterfaceCapacities {
    fn for_pages(pages: &[GpuDependencyPageLayout]) -> Self {
        Self {
            words: pages
                .iter()
                .map(|page| page.word_count)
                .max()
                .unwrap_or(1)
                .max(1),
            modules: pages
                .iter()
                .map(|page| page.module_count)
                .max()
                .unwrap_or(0),
            declarations: pages
                .iter()
                .map(|page| page.declaration_count)
                .max()
                .unwrap_or(0),
            types: pages.iter().map(|page| page.type_count).max().unwrap_or(0),
            constant_type_rows: pages.iter().map(|page| page.header[CONSTANT_TYPE_ROWS]).max().unwrap_or(0),
            members: pages
                .iter()
                .map(|page| page.member_count)
                .max()
                .unwrap_or(0),
            predicates: pages.iter().map(|page| page.predicate_count).max().unwrap_or(0),
            predicate_arguments: pages.iter().map(|page| page.predicate_argument_count).max().unwrap_or(0),
            implementations: pages.iter().map(|page| page.implementation_count).max().unwrap_or(0),
            implementation_arguments: pages.iter().map(|page| page.implementation_argument_count).max().unwrap_or(0),
            implementation_method_bindings: pages.iter().map(|page| page.implementation_method_binding_count).max().unwrap_or(0),
            module_lookup: pages
                .iter()
                .map(|page| page.module_lookup_capacity)
                .max()
                .unwrap_or(1)
                .max(1),
        }
    }

    fn grow_to_cover(self, required: Self) -> Self {
        Self {
            words: self.words.max(required.words),
            modules: self.modules.max(required.modules),
            declarations: self.declarations.max(required.declarations),
            types: self.types.max(required.types),
            constant_type_rows: self.constant_type_rows.max(required.constant_type_rows),
            members: self.members.max(required.members),
            predicates: self.predicates.max(required.predicates),
            predicate_arguments: self.predicate_arguments.max(required.predicate_arguments),
            implementations: self.implementations.max(required.implementations),
            implementation_arguments: self.implementation_arguments.max(required.implementation_arguments),
            implementation_method_bindings: self.implementation_method_bindings.max(required.implementation_method_bindings),
            module_lookup: self.module_lookup.max(required.module_lookup),
        }
    }
}

/// The rows of the method index of a slot whose pages hold up to `members`
/// member rows: two tables, each a power of two of at least twice that many
/// slots. The kernels read the table size from the buffer.
fn method_lookup_rows(members: u32) -> usize {
    2 * (members.max(1) as usize * 2).next_power_of_two()
}

/// Layout of one dependency page, computed from the row counts of its
/// interfaces alone: its header, its size and the interfaces it holds in
/// (library, unit) order. The page's words are packed on the GPU from the
/// interfaces' encoded bytes (`dependency_pack`).
pub(crate) struct GpuDependencyPageLayout {
    pub(crate) module_count: u32,
    pub(crate) declaration_count: u32,
    pub(crate) type_count: u32,
    pub(crate) member_count: u32,
    pub(crate) predicate_count: u32,
    pub(crate) predicate_argument_count: u32,
    pub(crate) implementation_count: u32,
    pub(crate) implementation_argument_count: u32,
    pub(crate) implementation_method_binding_count: u32,
    pub(crate) module_lookup_capacity: u32,
    pub(super) header: [u32; HEADER_WORDS],
    pub(super) word_count: usize,
    pub(super) interfaces: Vec<DependencyPageInterface>,
    /// Rows of each section in the whole page.
    pub(super) totals: [u32; SECTIONS],
}

/// One interface of a page: its position in the slice the page was laid out
/// from, its identity and its rows of each section.
pub(super) struct DependencyPageInterface {
    pub(super) index: usize,
    pub(super) library_id: u32,
    pub(super) unit_id: u32,
    pub(super) rows: [u32; SECTIONS],
}

/// Sections of an encoded interface, in encoded order: modules, module
/// segments, declarations, types, type edges, members, predicates, predicate
/// arguments, implementations, implementation arguments and method
/// bindings, then name bytes.
pub(super) const SECTIONS: usize = 12;
pub(super) const NAME_SECTION: usize = 11;
/// Words of one record of each section, in an encoded interface and in a page.
pub(super) const SECTION_WORDS: [u32; NAME_SECTION] = [2, 4, 14, 9, 1, 12, 8, 1, 15, 1, 6];
const SECTION_LABELS: [&str; SECTIONS] = [
    "module", "module segment", "declaration", "type", "type edge", "member", "predicate",
    "predicate argument", "implementation", "implementation argument",
    "implementation method binding", "name byte",
];
const DECLARATION_SECTION: usize = 2;
const IMPLEMENTATION_SECTION: usize = 8;

pub(super) const HEADER_WORDS: usize = 46;
pub(super) const CONSTANT_TYPE_SPAN_BASE: usize = 44;
pub(super) const CONSTANT_TYPE_ROWS: usize = 45;
pub(super) const MODULE_LIBRARY_OFFSET: usize = 8;
pub(super) const MODULE_UNIT_OFFSET: usize = 9;
pub(super) const MODULE_LOCAL_OFFSET: usize = 10;
pub(super) const MODULE_OFFSET: usize = 11;
pub(super) const MODULE_SEGMENT_OFFSET: usize = 12;
pub(super) const DECLARATION_LIBRARY_OFFSET: usize = 13;
pub(super) const DECLARATION_UNIT_OFFSET: usize = 14;
pub(super) const DECLARATION_LOCAL_OFFSET: usize = 15;
pub(super) const DECLARATION_OFFSET: usize = 16;
pub(super) const TYPE_OFFSET: usize = 17;
pub(super) const TYPE_EDGE_OFFSET: usize = 18;
pub(super) const MEMBER_OFFSET: usize = 19;
pub(super) const NAME_BYTE_OFFSET: usize = 20;
pub(super) const TYPE_LIBRARY_OFFSET: usize = 21;
pub(super) const TYPE_UNIT_OFFSET: usize = 22;
pub(super) const TYPE_LOCAL_OFFSET: usize = 23;
pub(super) const MODULE_DECLARATION_START_OFFSET: usize = 24;
pub(super) const MODULE_DECLARATION_COUNT_OFFSET: usize = 25;
pub(super) const MODULE_DECLARATION_ORDER_OFFSET: usize = 26;
pub(super) const PAGE_FLAGS_OFFSET: usize = 27;
pub(super) const PREDICATE_COUNT: usize = 28;
pub(super) const PREDICATE_ARGUMENT_COUNT: usize = 29;
pub(super) const PREDICATE_LIBRARY_OFFSET: usize = 30;
pub(super) const PREDICATE_UNIT_OFFSET: usize = 31;
pub(super) const PREDICATE_LOCAL_OFFSET: usize = 32;
pub(super) const PREDICATE_OFFSET: usize = 33;
pub(super) const PREDICATE_ARGUMENT_OFFSET: usize = 34;
pub(super) const IMPLEMENTATION_COUNT: usize = 35;
pub(super) const IMPLEMENTATION_ARGUMENT_COUNT: usize = 36;
pub(super) const IMPLEMENTATION_METHOD_BINDING_COUNT: usize = 37;
pub(super) const IMPLEMENTATION_LIBRARY_OFFSET: usize = 38;
pub(super) const IMPLEMENTATION_UNIT_OFFSET: usize = 39;
pub(super) const IMPLEMENTATION_LOCAL_OFFSET: usize = 40;
pub(super) const IMPLEMENTATION_OFFSET: usize = 41;
pub(super) const IMPLEMENTATION_ARGUMENT_OFFSET: usize = 42;
pub(super) const IMPLEMENTATION_METHOD_BINDING_OFFSET: usize = 43;

impl GpuDependencyPageLayout {
    pub(crate) fn new(
        current_library_id: u32,
        current_unit_id: u32,
        interfaces: &[GpuSemanticInterfaceArtifact],
    ) -> Result<Self> {
        let mut order = (0..interfaces.len()).collect::<Vec<_>>();
        order.sort_unstable_by_key(|&index| (interfaces[index].library_id, interfaces[index].unit_id));
        let mut page_interfaces = Vec::<DependencyPageInterface>::with_capacity(order.len());
        let mut totals = [0u32; SECTIONS];
        for index in order {
            let interface = &interfaces[index];
            let (library_id, unit_id) = (interface.library_id, interface.unit_id);
            if library_id == current_library_id && unit_id == current_unit_id {
                anyhow::bail!(
                    "library {current_library_id} unit {current_unit_id} cannot consume its own semantic interface as a dependency"
                );
            }
            if page_interfaces
                .last()
                .is_some_and(|previous| (previous.library_id, previous.unit_id) == (library_id, unit_id))
            {
                anyhow::bail!(
                    "dependency semantic interface ({library_id}, {unit_id}) occurs more than once"
                );
            }
            let lens = [
                interface.modules.len(),
                interface.module_segments.len(),
                interface.declarations.len(),
                interface.types.len(),
                interface.type_edges.len(),
                interface.members.len(),
                interface.predicates.len(),
                interface.predicate_arguments.len(),
                interface.implementations.len(),
                interface.implementation_arguments.len(),
                interface.implementation_method_bindings.len(),
                interface.name_bytes.len(),
            ];
            let mut rows = [0u32; SECTIONS];
            for section in 0..SECTIONS {
                let label = SECTION_LABELS[section];
                rows[section] = u32::try_from(lens[section])
                    .map_err(|_| anyhow::anyhow!("dependency {label} count does not fit in u32"))?;
                totals[section] = totals[section]
                    .checked_add(rows[section])
                    .ok_or_else(|| anyhow::anyhow!("dependency {label} count exceeds u32"))?;
            }
            page_interfaces.push(DependencyPageInterface { index, library_id, unit_id, rows });
        }
        // Rebased contract owners keep the implementation tag bit free.
        for section in [DECLARATION_SECTION, IMPLEMENTATION_SECTION] {
            if totals[section] >= IMPLEMENTATION_OWNER_TAG {
                anyhow::bail!(
                    "semantic-interface dependency {} count exceeds contract owner domain",
                    SECTION_LABELS[section]
                );
            }
        }
        let [modules, segments, declarations, types, edges, members, predicates,
            predicate_arguments, implementations, implementation_arguments, bindings, name_bytes] =
            totals;
        let module_lookup_capacity = modules
            .checked_mul(2)
            .and_then(u32::checked_next_power_of_two)
            .unwrap_or(0)
            .max(1);
        if modules != 0 && module_lookup_capacity == 1 {
            anyhow::bail!("dependency module lookup capacity overflows u32");
        }
        let mut header = [0u32; HEADER_WORDS];
        header[..8].copy_from_slice(&[
            u32::try_from(page_interfaces.len()).unwrap_or(u32::MAX),
            modules,
            segments,
            declarations,
            types,
            edges,
            members,
            name_bytes,
        ]);
        // A standalone page is also a valid one-page address plan.
        header[CONSTANT_TYPE_ROWS] = types;
        header[PREDICATE_COUNT] = predicates;
        header[PREDICATE_ARGUMENT_COUNT] = predicate_arguments;
        header[IMPLEMENTATION_COUNT] = implementations;
        header[IMPLEMENTATION_ARGUMENT_COUNT] = implementation_arguments;
        header[IMPLEMENTATION_METHOD_BINDING_COUNT] = bindings;
        // Tables in page order (shaders/type_checker/dependency_pack/rows.slang).
        let words = |rows: u32, width: u64| u64::from(rows) * width;
        let tables = [
            (MODULE_LIBRARY_OFFSET, words(modules, 1)),
            (MODULE_UNIT_OFFSET, words(modules, 1)),
            (MODULE_LOCAL_OFFSET, words(modules, 1)),
            (MODULE_OFFSET, words(modules, 2)),
            (MODULE_SEGMENT_OFFSET, words(segments, 4)),
            (DECLARATION_LIBRARY_OFFSET, words(declarations, 1)),
            (DECLARATION_UNIT_OFFSET, words(declarations, 1)),
            (DECLARATION_LOCAL_OFFSET, words(declarations, 1)),
            (DECLARATION_OFFSET, words(declarations, 14)),
            (TYPE_OFFSET, words(types, 9)),
            (TYPE_LIBRARY_OFFSET, words(types, 1)),
            (TYPE_UNIT_OFFSET, words(types, 1)),
            (TYPE_LOCAL_OFFSET, words(types, 1)),
            (MODULE_DECLARATION_START_OFFSET, words(modules, 1)),
            (MODULE_DECLARATION_COUNT_OFFSET, words(modules, 1)),
            (MODULE_DECLARATION_ORDER_OFFSET, words(declarations, 1)),
            (TYPE_EDGE_OFFSET, words(edges, 1)),
            (MEMBER_OFFSET, words(members, 12)),
            (PREDICATE_LIBRARY_OFFSET, words(predicates, 1)),
            (PREDICATE_UNIT_OFFSET, words(predicates, 1)),
            (PREDICATE_LOCAL_OFFSET, words(predicates, 1)),
            (PREDICATE_OFFSET, words(predicates, 8)),
            (PREDICATE_ARGUMENT_OFFSET, words(predicate_arguments, 1)),
            (IMPLEMENTATION_LIBRARY_OFFSET, words(implementations, 1)),
            (IMPLEMENTATION_UNIT_OFFSET, words(implementations, 1)),
            (IMPLEMENTATION_LOCAL_OFFSET, words(implementations, 1)),
            (IMPLEMENTATION_OFFSET, words(implementations, 15)),
            (IMPLEMENTATION_ARGUMENT_OFFSET, words(implementation_arguments, 1)),
            (IMPLEMENTATION_METHOD_BINDING_OFFSET, words(bindings, 6)),
            (NAME_BYTE_OFFSET, u64::from(name_bytes.div_ceil(4))),
        ];
        let mut word_count = HEADER_WORDS as u64;
        for (slot, table_words) in tables {
            header[slot] = word_count as u32;
            word_count += table_words;
        }
        if word_count > u64::from(u32::MAX) {
            anyhow::bail!("packed dependency interface exceeds u32 words");
        }
        Ok(Self {
            module_count: modules,
            declaration_count: declarations,
            type_count: types,
            member_count: members,
            predicate_count: predicates,
            predicate_argument_count: predicate_arguments,
            implementation_count: implementations,
            implementation_argument_count: implementation_arguments,
            implementation_method_binding_count: bindings,
            module_lookup_capacity,
            header,
            word_count: word_count as usize,
            interfaces: page_interfaces,
            totals,
        })
    }
}

/// Address planning only: rows retain their page identity across every replay.
/// Compute the complete checked plan before publishing any header changes.
fn assign_constant_type_spans(pages: &mut [GpuDependencyPageLayout]) -> Result<()> {
    let mut total = 0u32;
    let mut bases = Vec::with_capacity(pages.len());
    for page in pages.iter() {
        bases.push(total);
        total = total.checked_add(page.type_count)
            .ok_or_else(|| anyhow::anyhow!("dependency constant type span exceeds u32 rows"))?;
    }
    for (page, base) in pages.iter_mut().zip(bases) {
        page.header[CONSTANT_TYPE_SPAN_BASE] = base;
        page.header[CONSTANT_TYPE_ROWS] = total;
    }
    Ok(())
}

impl GpuDependencyInterfacePages {
    pub(crate) fn new_reusing(
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        current_library_id: u32,
        current_unit_id: u32,
        interface_pages: &[&[GpuSemanticInterfaceArtifact]],
        resident_state: &mut Option<GpuDependencyInterfaceState>,
    ) -> Result<Self> {
        let _span = crate::gpu::trace::HostSpan::new("host.compiler", "typecheck.dependency_pages");
        let empty_page: &[GpuSemanticInterfaceArtifact] = &[];
        let interface_pages = if interface_pages.is_empty() {
            std::slice::from_ref(&empty_page)
        } else {
            interface_pages
        };
        let mut pages = interface_pages
            .iter()
            .map(|interfaces| {
                GpuDependencyPageLayout::new(
                    current_library_id,
                    current_unit_id,
                    interfaces,
                )
            })
            .collect::<Result<Vec<_>>>()?;
        assign_constant_type_spans(&mut pages)?;
        let last = pages.len() - 1;
        for (index, page) in pages.iter_mut().enumerate() {
            page.header[PAGE_FLAGS_OFFSET] = u32::from(index == 0) | (u32::from(index == last) << 1);
        }
        let required = GpuDependencyInterfaceCapacities::for_pages(&pages);
        let allocation = resident_state
            .as_ref()
            .map(GpuDependencyInterfaceState::capacities)
            .map(|capacity| capacity.grow_to_cover(required))
            .unwrap_or(required);
        if resident_state
            .as_ref()
            .is_none_or(|state| state.capacities() != allocation)
        {
            // A new allocation changes the type-check workspace's input
            // fingerprint, so the whole resident workspace is rebuilt.
            if crate::options::get().report.host_timing {
                eprintln!(
                    "[gpu_compile_host_timer] typecheck.dependency_interfaces.allocate: previous={:?} required={required:?} pages={}",
                    resident_state.as_ref().map(GpuDependencyInterfaceState::capacities),
                    pages.len(),
                );
            }
            *resident_state = Some(GpuDependencyInterfaceState::with_capacities(
                device, allocation,
            ));
        }
        // With one page the GPU packs it straight into the slot. With
        // several, it packs all of them into the page store, which stays
        // resident for the job, and `record_page` streams them through the
        // slot; the first page enters the slot here.
        let resident = resident_state
            .as_mut()
            .expect("dependency resident state allocated");
        let mut page_store_offsets = Vec::new();
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("type_check.dependencies.pack"),
        });
        if pages.len() > 1 {
            let mut offset = 0u64;
            for page in &pages {
                page_store_offsets.push(offset);
                offset += page.word_count as u64 * 4;
            }
            let store_words = (offset / 4) as usize;
            if resident
                .page_store
                .as_ref()
                .is_none_or(|store| store.count < store_words)
            {
                let capacity = store_words.next_power_of_two().max(1024);
                resident.page_store = Some(upload_words(
                    device,
                    "type_check.dependencies.page_store",
                    &vec![0; capacity],
                ));
            }
            let store = resident.page_store.as_ref().expect("page store allocated");
            let page_words = page_store_offsets.iter().map(|offset| offset / 4).collect::<Vec<_>>();
            super::dependency_pack::record_pack(
                device,
                queue,
                &mut encoder,
                &mut resident.pack_buffers,
                &pages,
                interface_pages,
                store,
                &page_words,
            )?;
            encoder.copy_buffer_to_buffer(
                &store.buffer,
                store.absolute_offset(0),
                &resident.words.buffer,
                resident.words.absolute_offset(0),
                pages[0].word_count as u64 * 4,
            );
        } else {
            super::dependency_pack::record_pack(
                device,
                queue,
                &mut encoder,
                &mut resident.pack_buffers,
                &pages,
                interface_pages,
                &resident.words,
                &[0],
            )?;
        }
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "type_check.dependencies.pack",
            encoder.finish(),
        );
        let state = resident_state
            .as_ref()
            .expect("dependency resident state allocated")
            .clone();
        let interfaces = interface_pages.iter().flat_map(|page| page.iter());
        let closure_summaries = JobClosureSummaries::new(
            [current_library_id, current_unit_id],
            interfaces.filter_map(|interface| interface.closure_summary.clone()),
        )
        .map(Arc::new);
        let pages = Self {
            state,
            pages,
            page_store_offsets,
            current_library_id,
            current_unit_id,
            closure_summaries,
        };
        Ok(pages)
    }

    pub(crate) fn closure_summaries(&self) -> Option<&Arc<JobClosureSummaries>> {
        self.closure_summaries.as_ref()
    }

    pub(crate) fn state(&self) -> &GpuDependencyInterfaceState {
        &self.state
    }

    /// Records the GPU copy that makes `page` the slot's contents for the
    /// passes recorded after it.
    pub(crate) fn record_page(&self, encoder: &mut wgpu::CommandEncoder, page: usize) -> Result<()> {
        let packed = self
            .pages
            .get(page)
            .ok_or_else(|| anyhow::anyhow!("dependency page index {page} is out of bounds"))?;
        self.state.check_page_fits(packed)?;
        let store = self
            .state
            .page_store
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("dependency pages have no resident page store"))?;
        let offset = self.page_store_offsets[page];
        let bytes = packed.word_count as u64 * 4;
        crate::gpu::passes_core::flush_deferred_compute(encoder);
        encoder.copy_buffer_to_buffer(
            &store.buffer,
            store.absolute_offset(offset),
            &self.state.words.buffer,
            self.state.words.absolute_offset(0),
            bytes,
        );
        Ok(())
    }

    pub(crate) fn len(&self) -> usize {
        self.pages.len()
    }

    /// The (library, unit) of the job these pages were prepared for.
    pub(crate) fn current_library_id(&self) -> u32 {
        self.current_library_id
    }

    pub(crate) fn current_unit_id(&self) -> u32 {
        self.current_unit_id
    }

    /// Empty pages still carry the owning unit identity. Test the current
    /// contents, not the resident slot's capacity left by an earlier job.
    pub(crate) fn has_type_references(&self) -> bool {
        self.pages.iter().any(|page| page.type_count != 0)
    }
}

impl GpuDependencyInterfaceState {
    fn capacities(&self) -> GpuDependencyInterfaceCapacities {
        GpuDependencyInterfaceCapacities {
            words: self.words.count,
            modules: self.module_count,
            declarations: self.declaration_count,
            types: self.type_count,
            constant_type_rows: self.constant_type_rows,
            members: self.member_count,
            predicates: self.predicate_count,
            predicate_arguments: self.predicate_argument_count,
            implementations: self.implementation_count,
            implementation_arguments: self.implementation_argument_count,
            implementation_method_bindings: self.implementation_method_binding_count,
            module_lookup: self.module_lookup_capacity,
        }
    }

    fn with_capacities(
        device: &wgpu::Device,
        capacities: GpuDependencyInterfaceCapacities,
    ) -> Self {
        let words = upload_words(
            device,
            "type_check.dependencies.words",
            &vec![0; capacities.words],
        );
        let module_lookup = typed_storage_u32_fill_rw(
            device,
            "type_check.dependencies.module_lookup",
            capacities.module_lookup as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );

        let method_lookup = typed_storage_u32_fill_rw(
            device,
            "type_check.dependencies.method_lookup",
            method_lookup_rows(capacities.members),
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );

        Self {
            module_count: capacities.modules,
            declaration_count: capacities.declarations,
            type_count: capacities.types,
            constant_type_rows: capacities.constant_type_rows,
            member_count: capacities.members,
            predicate_count: capacities.predicates,
            predicate_argument_count: capacities.predicate_arguments,
            implementation_count: capacities.implementations,
            implementation_argument_count: capacities.implementation_arguments,
            implementation_method_binding_count: capacities.implementation_method_bindings,
            module_lookup_capacity: capacities.module_lookup,
            words,
            module_lookup,
            method_lookup,
            page_store: None,
            pack_buffers: Default::default(),
        }
    }

    fn check_page_fits(&self, page: &GpuDependencyPageLayout) -> Result<()> {
        if page.word_count > self.words.count
            || page.module_lookup_capacity > self.module_lookup_capacity
            || page.module_count > self.module_count
            || page.declaration_count > self.declaration_count
            || page.type_count > self.type_count
            || page.header[CONSTANT_TYPE_ROWS] > self.constant_type_rows
            || page.header[CONSTANT_TYPE_SPAN_BASE]
                .checked_add(page.type_count)
                .is_none_or(|end| end > page.header[CONSTANT_TYPE_ROWS])
            || page.member_count > self.member_count
            || page.predicate_count > self.predicate_count
            || page.predicate_argument_count > self.predicate_argument_count
            || page.implementation_count > self.implementation_count
            || page.implementation_argument_count > self.implementation_argument_count
            || page.implementation_method_binding_count > self.implementation_method_binding_count
        {
            anyhow::bail!("dependency page exceeds its fixed GPU slot capacity");
        }
        Ok(())
    }
}

fn upload_words(device: &wgpu::Device, label: &str, words: &[u32]) -> LaniusBuffer<u32> {
    storage_ro_from_u32s(device, label, if words.is_empty() { &[0] } else { words })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::compiler::GpuCompiler;

    #[test]
    fn dependency_page_preserves_callable_predicate_identity_and_graph_roots() {
        pollster::block_on(async {
            let compiler = GpuCompiler::new().await.expect("GPU compiler");
            let source = "module contracts::left; pub trait Rel<T>{} pub impl Rel<[i32;2]> for bool{} pub fn keep<T,U>(v:T)->T where T:Rel<[U;2]>{return v;}";
            let first = compiler.semantic_interface_for_source_pack(
                7, &[source]).await.expect("first callable contract");
            let second = compiler.semantic_interface_for_source_pack(
                8, &[source.replace("contracts::left", "contracts::right")])
                .await.expect("second library's distinct callable contract");
            let packed = crate::type_checker::gpu_packed_dependency_page(9, 0,
                &[second.clone(), first.clone()]).unwrap();
            assert_eq!(packed.predicates.len(), 2);
            assert_eq!(packed.predicate_arguments.len(), 2);
            assert_eq!(packed.implementations.len(), 2);
            assert_eq!(packed.implementation_arguments.len(), 2);
            assert_eq!(packed.words[IMPLEMENTATION_COUNT], 2);
            assert_eq!(packed.words[PREDICATE_COUNT], 2);
            assert_eq!(packed.words[PREDICATE_ARGUMENT_COUNT], 2);
            let table = |header: usize, index: usize| {
                packed.words[packed.words[header] as usize + index]
            };
            let mut declaration_base = 0;
            let mut type_base = 0;
            let mut argument_base = 0;
            for (row, interface) in [first, second].iter().enumerate() {
                assert_eq!(interface.predicates.len(), 1);
                let predicate = interface.predicates[0];
                assert_eq!(table(PREDICATE_LIBRARY_OFFSET, row), interface.library_id);
                assert_eq!(table(PREDICATE_UNIT_OFFSET, row), interface.unit_id);
                assert_eq!(table(PREDICATE_LOCAL_OFFSET, row), 0);
                let expected = [predicate.owner_ref + declaration_base,
                    predicate.owner_scope_symbol, predicate.subject_type + type_base,
                    predicate.trait_library_id, predicate.trait_unit_id,
                    predicate.trait_declaration_index, predicate.first_argument + argument_base,
                    predicate.argument_count];
                for (word, expected) in expected.iter().enumerate() {
                    assert_eq!(table(PREDICATE_OFFSET, row * 8 + word), *expected);
                }
                for (index, root) in interface.predicate_arguments.iter().enumerate() {
                    assert_eq!(table(PREDICATE_ARGUMENT_OFFSET, argument_base as usize + index),
                        root + type_base);
                }
                let implementation = interface.implementations[0];
                assert_eq!(table(IMPLEMENTATION_LIBRARY_OFFSET, row), interface.library_id);
                assert_eq!(table(IMPLEMENTATION_UNIT_OFFSET, row), interface.unit_id);
                assert_eq!(table(IMPLEMENTATION_LOCAL_OFFSET, row), 0);
                assert_eq!(table(IMPLEMENTATION_OFFSET, row * crate::compiler::IMPLEMENTATION_U32S + 5), implementation.subject_type + type_base);
                assert_eq!(table(IMPLEMENTATION_OFFSET, row * crate::compiler::IMPLEMENTATION_U32S + 2), implementation.trait_library_id);
                assert_eq!(table(IMPLEMENTATION_OFFSET, row * crate::compiler::IMPLEMENTATION_U32S + 4), implementation.trait_declaration_index);
                assert_eq!(table(IMPLEMENTATION_OFFSET, row * crate::compiler::IMPLEMENTATION_U32S + 14), implementation.kind);
                assert_eq!(table(IMPLEMENTATION_ARGUMENT_OFFSET, row), interface.implementation_arguments[0] + type_base);
                declaration_base += interface.declarations.len() as u32;
                type_base += interface.types.len() as u32;
                argument_base += interface.predicate_arguments.len() as u32;
            }
        });
    }

    #[test]
    fn constant_page_addresses_are_disjoint_stable_and_overflow_checked() {
        let mut pages = [3u32, 0, 5].into_iter().map(|count| {
            let mut page = GpuDependencyPageLayout::new(7, 0, &[]).unwrap();
            // Only address-domain sizes matter to this host planner.
            page.type_count = count;
            page
        }).collect::<Vec<_>>();
        assign_constant_type_spans(&mut pages).unwrap();
        let plan = pages.iter().map(|page|
            (page.header[CONSTANT_TYPE_SPAN_BASE], page.header[CONSTANT_TYPE_ROWS]))
            .collect::<Vec<_>>();
        assert_eq!(plan, [(0, 8), (3, 8), (3, 8)]);
        assert_ne!(pages[0].header[CONSTANT_TYPE_SPAN_BASE], pages[2].header[CONSTANT_TYPE_SPAN_BASE]);
        let capacity = GpuDependencyInterfaceCapacities::for_pages(&pages);
        assert_eq!((capacity.types, capacity.constant_type_rows), (5, 8));
        // The same logical page may be streamed several times in one job.
        assign_constant_type_spans(&mut pages).unwrap();
        assert_eq!(plan, pages.iter().map(|page|
            (page.header[CONSTANT_TYPE_SPAN_BASE], page.header[CONSTANT_TYPE_ROWS]))
            .collect::<Vec<_>>());
        pages[0].type_count = u32::MAX;
        assert!(assign_constant_type_spans(&mut pages).is_err());
        assert_eq!(pages[0].header[CONSTANT_TYPE_ROWS], 8);
        assert_eq!(pages[2].header[CONSTANT_TYPE_SPAN_BASE], 3);
    }

    #[test]
    fn resident_dependency_slot_grows_without_shrinking_other_domains() {
        let resident = GpuDependencyInterfaceCapacities {
            words: 100,
            modules: 8,
            declarations: 20,
            types: 30,
            constant_type_rows: 80,
            members: 40,
            predicates: 12,
            predicate_arguments: 16,
            implementations: 3,
            implementation_arguments: 7,
            implementation_method_bindings: 5,
            module_lookup: 16,
        };
        let required = GpuDependencyInterfaceCapacities {
            words: 120,
            modules: 4,
            declarations: 24,
            types: 12,
            constant_type_rows: 100,
            members: 50,
            predicates: 7,
            predicate_arguments: 20,
            implementations: 4,
            implementation_arguments: 6,
            implementation_method_bindings: 8,
            module_lookup: 8,
        };
        assert_eq!(
            resident.grow_to_cover(required),
            GpuDependencyInterfaceCapacities {
                words: 120,
                modules: 8,
                declarations: 24,
                types: 30,
                constant_type_rows: 100,
                members: 50,
                predicates: 12,
                predicate_arguments: 20,
                implementations: 4,
                implementation_arguments: 7,
                implementation_method_bindings: 8,
                module_lookup: 16,
            }
        );
    }
}

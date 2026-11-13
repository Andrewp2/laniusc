//! Packs a job's dependency pages on the GPU.
//!
//! The dependency interfaces' encoded bytes are copied back to back into
//! one source buffer: an interface exported by an earlier job of the build
//! is copied on the GPU from the buffer its export left it in, and one read
//! from disk is uploaded once. The host writes only a small plan, computed
//! from row counts: each page's header and, per interface, its identity, its
//! first row in each flattened table and where its sections start among the
//! sources. Two kernels then write the pages
//! (shaders/type_checker/dependency_pack): `rows` writes every word but the
//! module declaration index, rebasing references into flattened storage,
//! and `module_index` writes the index.

use super::*;
use super::dependency_interface::{
    GpuDependencyPageLayout,
    HEADER_WORDS,
    NAME_SECTION,
    SECTIONS,
    SECTION_WORDS,
};
use crate::compiler::{ENCODED_RECORDS_WORD, GpuSemanticInterfaceArtifact};
use crate::gpu::passes_core::{self, DispatchDim, InputElements};

const ROWS_SHADER: &str = "type_checker/dependency_pack/rows";
const MODULE_INDEX_SHADER: &str = "type_checker/dependency_pack/module_index";
const LABEL: &str = "type_check.dependencies.pack";
/// Plan layout (shaders/type_checker/dependency_pack/plan.slang).
const PLAN_PAGES: usize = 4;
const PAGE_STRIDE: usize = 8;
const DESCRIPTOR_STRIDE: usize = 28;
const DESCRIPTOR_SECTIONS: usize = 4;

/// The packing kernels' input buffers, kept across jobs and grown on demand.
#[derive(Clone, Default)]
pub(crate) struct DependencyPackBuffers {
    sources: Option<LaniusBuffer<u32>>,
    plan: Option<LaniusBuffer<u32>>,
}

/// Records the packing of `pages` into `output`, page `p` at word
/// `page_words[p]`. `interface_pages[p]` is the slice page `p` was laid out
/// from. Source uploads go through `queue` and reach the commands of the
/// next submission.
#[allow(clippy::too_many_arguments)]
pub(super) fn record_pack(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
    buffers: &mut DependencyPackBuffers,
    pages: &[GpuDependencyPageLayout],
    interface_pages: &[&[GpuSemanticInterfaceArtifact]],
    output: &LaniusBuffer<u32>,
    page_words: &[u64],
) -> Result<()> {
    // Where each interface's encoded bytes start among the sources.
    let mut source_words = Vec::with_capacity(pages.len());
    let mut total_source_words = 0u64;
    for page in pages {
        let mut words = Vec::with_capacity(page.interfaces.len());
        for interface in &page.interfaces {
            words.push(total_source_words);
            total_source_words += encoded_byte_len(&interface.rows).div_ceil(4);
        }
        source_words.push(words);
    }
    let sources = grown(device, &mut buffers.sources, "type_check.dependencies.pack_sources",
        total_source_words)?;
    for ((page, interfaces), words) in pages.iter().zip(interface_pages).zip(&source_words) {
        for (interface, &word) in page.interfaces.iter().zip(words) {
            let artifact = &interfaces[interface.index];
            let byte_len = encoded_byte_len(&interface.rows);
            let offset = sources.absolute_offset(word * 4);
            match artifact.resident_bytes.get() {
                Some((buffer, resident_len)) => {
                    if resident_len as u64 != byte_len {
                        anyhow::bail!(
                            "dependency interface ({}, {}) has {resident_len} resident bytes but its rows encode {byte_len}",
                            interface.library_id,
                            interface.unit_id,
                        );
                    }
                    encoder.copy_buffer_to_buffer(buffer, 0, &sources.buffer, offset,
                        byte_len.next_multiple_of(4));
                }
                None => {
                    let mut bytes = artifact.to_bytes().map_err(|reason| {
                        anyhow::anyhow!(
                            "dependency semantic interface for library {} is invalid: {reason}",
                            interface.library_id
                        )
                    })?;
                    bytes.resize(bytes.len().next_multiple_of(4), 0);
                    queue.write_buffer(&sources.buffer, offset, &bytes);
                }
            }
        }
    }

    let plan_words = plan_words(pages, page_words, &source_words)?;
    let plan = grown(device, &mut buffers.plan, "type_check.dependencies.pack_plan",
        plan_words.len() as u64)?;
    plan.write(queue, 0, &plan_words.iter().flat_map(|word| word.to_le_bytes()).collect::<Vec<_>>());

    let rows = passes_core::make_pass_data_from_shader_key(device, LABEL, "main", ROWS_SHADER)?;
    let module_index =
        passes_core::make_pass_data_from_shader_key(device, LABEL, "main", MODULE_INDEX_SHADER)?;
    let bindings = [
        ("pack_plan", plan.as_entire_binding()),
        ("pack_sources", sources.as_entire_binding()),
        ("pack_output", output.as_entire_binding()),
    ];
    let row_threads = plan_words[1];
    let module_threads = plan_words[2];
    let mut dispatches = Vec::with_capacity(2);
    for (pass, threads) in [(&rows, row_threads), (&module_index, module_threads)] {
        if threads == 0 {
            continue;
        }
        let bind_group = passes_core::bind_group::create_bind_group_from_bindings(
            device,
            Some(LABEL),
            pass,
            0,
            &bindings,
        )?;
        let workgroups = passes_core::plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(threads),
            pass.thread_group_size,
        )?;
        dispatches.push((pass, bind_group, workgroups));
    }
    let descriptor = wgpu::ComputePassDescriptor {
        label: Some(LABEL),
        timestamp_writes: None,
    };
    // The kernels write disjoint words, so one pass holds both unless the
    // timer can stamp only between passes.
    if crate::gpu::timer::operation_capture_requires_split_passes() {
        for (pass, bind_group, (x, y, z)) in &dispatches {
            {
                let mut compute = passes_core::begin_counted_compute_pass(encoder, &descriptor);
                compute.set_pipeline(&pass.pipeline);
                compute.set_bind_group(0, Some(bind_group), &[]);
                passes_core::record_compute_dispatch();
                compute.dispatch_workgroups(*x, *y, *z);
            }
            crate::gpu::timer::stamp_active_operation(encoder, LABEL);
        }
    } else {
        let timed = crate::gpu::timer::operation_capture_active();
        let mut compute = passes_core::begin_counted_compute_pass(encoder, &descriptor);
        for (pass, bind_group, (x, y, z)) in &dispatches {
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, Some(bind_group), &[]);
            passes_core::record_compute_dispatch();
            compute.dispatch_workgroups(*x, *y, *z);
            if timed {
                crate::gpu::timer::stamp_active_operation_in_pass(&mut compute, LABEL);
            }
        }
    }
    Ok(())
}

/// Bytes of an encoded interface with these section rows.
fn encoded_byte_len(rows: &[u32; SECTIONS]) -> u64 {
    record_words_before(rows, NAME_SECTION) * 4 + u64::from(rows[NAME_SECTION])
}

/// The word of an encoded interface where `section` starts.
fn record_words_before(rows: &[u32; SECTIONS], section: usize) -> u64 {
    u64::from(ENCODED_RECORDS_WORD)
        + (0..section)
            .map(|before| u64::from(rows[before]) * u64::from(SECTION_WORDS[before]))
            .sum::<u64>()
}

/// The plan words (plan.slang): totals, page records, then each page's
/// header and interface descriptors, the last descriptor holding the page
/// totals.
fn plan_words(
    pages: &[GpuDependencyPageLayout],
    page_words: &[u64],
    source_words: &[Vec<u64>],
) -> Result<Vec<u32>> {
    let word = |value: u64, what: &str| {
        u32::try_from(value).map_err(|_| anyhow::anyhow!("dependency pack {what} exceeds u32"))
    };
    let mut plan = vec![0u32; PLAN_PAGES + PAGE_STRIDE * pages.len()];
    let mut row_threads = 0u64;
    let mut module_threads = 0u64;
    for (page_index, page) in pages.iter().enumerate() {
        let header_word = plan.len();
        plan.extend_from_slice(&page.header);
        debug_assert_eq!(page.header.len(), HEADER_WORDS);
        let descriptor_word = plan.len();
        let mut bases = [0u32; SECTIONS];
        for (interface, &source) in page.interfaces.iter().zip(&source_words[page_index]) {
            let mut descriptor = [0u32; DESCRIPTOR_STRIDE];
            descriptor[0] = interface.library_id;
            descriptor[1] = interface.unit_id;
            for section in 0..SECTIONS {
                descriptor[DESCRIPTOR_SECTIONS + 2 * section] = bases[section];
                descriptor[DESCRIPTOR_SECTIONS + 2 * section + 1] = word(
                    source + record_words_before(&interface.rows, section),
                    "source word",
                )?;
                bases[section] += interface.rows[section];
            }
            plan.extend_from_slice(&descriptor);
        }
        debug_assert_eq!(bases, page.totals);
        let mut sentinel = [0u32; DESCRIPTOR_STRIDE];
        for section in 0..SECTIONS {
            sentinel[DESCRIPTOR_SECTIONS + 2 * section] = page.totals[section];
        }
        plan.extend_from_slice(&sentinel);
        let record = PLAN_PAGES + PAGE_STRIDE * page_index;
        plan[record..record + PAGE_STRIDE].copy_from_slice(&[
            word(page_words[page_index], "output word")?,
            word(page.word_count as u64, "page word count")?,
            word(row_threads, "page words")?,
            word(module_threads, "page modules")?,
            page.module_count,
            word(page.interfaces.len() as u64, "interface count")?,
            word(descriptor_word as u64, "plan word")?,
            word(header_word as u64, "plan word")?,
        ]);
        row_threads += page.word_count as u64;
        module_threads += u64::from(page.module_count);
    }
    plan[0] = word(pages.len() as u64, "page count")?;
    plan[1] = word(row_threads, "page words")?;
    plan[2] = word(module_threads, "page modules")?;
    Ok(plan)
}

/// The retained buffer in `slot`, replaced by a larger one when it holds
/// fewer than `words` words.
fn grown<'a>(
    device: &wgpu::Device,
    slot: &'a mut Option<LaniusBuffer<u32>>,
    label: &str,
    words: u64,
) -> Result<&'a LaniusBuffer<u32>> {
    let words = usize::try_from(words.max(1))
        .map_err(|_| anyhow::anyhow!("{label} exceeds the address space"))?;
    if slot.as_ref().is_none_or(|buffer| buffer.count < words) {
        let capacity = words.next_power_of_two().max(1024);
        *slot = Some(storage_ro_from_u32s(device, label, &vec![0; capacity]));
    }
    Ok(slot.as_ref().expect("pack buffer allocated"))
}

/// A GPU-packed dependency page read back into its tables, for tests.
#[cfg(test)]
#[derive(Clone, Debug, Default)]
pub(crate) struct DecodedDependencyPage {
    /// The page's interfaces in page order (from its layout).
    pub(crate) library_ids: Vec<u32>,
    pub(crate) unit_ids: Vec<u32>,
    pub(crate) module_library_id: Vec<u32>,
    pub(crate) module_unit_id: Vec<u32>,
    pub(crate) module_local_index: Vec<u32>,
    pub(crate) modules: Vec<crate::compiler::GpuSemanticInterfaceModuleRecord>,
    pub(crate) module_segments: Vec<crate::compiler::GpuSemanticInterfaceModuleSegmentRecord>,
    pub(crate) declaration_library_id: Vec<u32>,
    pub(crate) declaration_unit_id: Vec<u32>,
    pub(crate) declaration_local_index: Vec<u32>,
    pub(crate) declarations: Vec<crate::compiler::GpuSemanticInterfaceDeclarationRecord>,
    pub(crate) type_library_id: Vec<u32>,
    pub(crate) type_unit_id: Vec<u32>,
    pub(crate) type_local_index: Vec<u32>,
    pub(crate) types: Vec<crate::compiler::GpuSemanticInterfaceTypeRecord>,
    pub(crate) module_declaration_start: Vec<u32>,
    pub(crate) module_declaration_count: Vec<u32>,
    pub(crate) module_declaration_order: Vec<u32>,
    pub(crate) type_edges: Vec<crate::compiler::GpuSemanticInterfaceTypeEdge>,
    pub(crate) members: Vec<crate::compiler::GpuSemanticInterfaceMemberRecord>,
    pub(crate) predicate_library_id: Vec<u32>,
    pub(crate) predicate_unit_id: Vec<u32>,
    pub(crate) predicate_local_index: Vec<u32>,
    pub(crate) predicates: Vec<crate::compiler::GpuSemanticInterfacePredicateRecord>,
    pub(crate) predicate_arguments: Vec<u32>,
    pub(crate) implementation_library_id: Vec<u32>,
    pub(crate) implementation_unit_id: Vec<u32>,
    pub(crate) implementation_local_index: Vec<u32>,
    pub(crate) implementations: Vec<crate::compiler::GpuSemanticInterfaceImplementationRecord>,
    pub(crate) implementation_arguments: Vec<u32>,
    pub(crate) implementation_method_bindings:
        Vec<crate::compiler::GpuSemanticInterfaceImplementationMethodBindingRecord>,
    pub(crate) name_bytes: Vec<u8>,
    /// The page's words as packed.
    pub(crate) words: Vec<u32>,
}

/// Lays out one page of `interfaces` for the job of (library, unit), packs
/// it on the GPU and reads it back.
#[cfg(test)]
pub(crate) fn gpu_packed_dependency_page(
    current_library_id: u32,
    current_unit_id: u32,
    interfaces: &[GpuSemanticInterfaceArtifact],
) -> Result<DecodedDependencyPage, String> {
    use super::dependency_interface::*;
    use crate::compiler::*;
    let gpu = crate::gpu::device::global();
    let page = GpuDependencyPageLayout::new(current_library_id, current_unit_id, interfaces)
        .map_err(|err| err.to_string())?;
    let output = storage_ro_from_u32s(&gpu.device, "test.dependency_page", &vec![0; page.word_count]);
    let mut encoder = gpu.device.create_command_encoder(&Default::default());
    record_pack(&gpu.device, &gpu.queue, &mut encoder, &mut DependencyPackBuffers::default(),
        std::slice::from_ref(&page), &[interfaces], &output, &[0])
        .map_err(|err| err.to_string())?;
    let bytes = page.word_count as u64 * 4;
    let readback = gpu.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("test.dependency_page.readback"),
        size: bytes,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    encoder.copy_buffer_to_buffer(&output.buffer, output.absolute_offset(0), &readback, 0, bytes);
    gpu.queue.submit(Some(encoder.finish()));
    let slice = readback.slice(..);
    passes_core::map_readback_blocking(&gpu.device, &slice, "dependency page")
        .map_err(|err| err.to_string())?;
    let words = slice
        .get_mapped_range()
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().expect("word")))
        .collect::<Vec<_>>();
    let table = |slot: usize, rows: usize| {
        let start = words[slot] as usize;
        words[start..start + rows].to_vec()
    };
    let records = |slot: usize, rows: usize, width: usize| -> Vec<Vec<u32>> {
        table(slot, rows * width).chunks_exact(width.max(1)).map(<[u32]>::to_vec).collect()
    };
    let [modules, segments, declarations, types, edges, members, predicates,
        predicate_arguments, implementations, implementation_arguments, bindings, name_bytes] =
        page.totals.map(|rows| rows as usize);
    let mut names = table(NAME_BYTE_OFFSET, name_bytes.div_ceil(4))
        .into_iter()
        .flat_map(u32::to_le_bytes)
        .collect::<Vec<_>>();
    names.truncate(name_bytes);
    let decoded = DecodedDependencyPage {
        library_ids: page.interfaces.iter().map(|interface| interface.library_id).collect(),
        unit_ids: page.interfaces.iter().map(|interface| interface.unit_id).collect(),
        module_library_id: table(MODULE_LIBRARY_OFFSET, modules),
        module_unit_id: table(MODULE_UNIT_OFFSET, modules),
        module_local_index: table(MODULE_LOCAL_OFFSET, modules),
        modules: records(MODULE_OFFSET, modules, 2).into_iter().map(|w| GpuSemanticInterfaceModuleRecord {
            first_segment: w[0], segment_count: w[1],
        }).collect(),
        module_segments: records(MODULE_SEGMENT_OFFSET, segments, 4).into_iter().map(|w| {
            GpuSemanticInterfaceModuleSegmentRecord {
                name_hash_lo: w[0], name_hash_hi: w[1], name_byte_start: w[2], name_byte_len: w[3],
            }
        }).collect(),
        declaration_library_id: table(DECLARATION_LIBRARY_OFFSET, declarations),
        declaration_unit_id: table(DECLARATION_UNIT_OFFSET, declarations),
        declaration_local_index: table(DECLARATION_LOCAL_OFFSET, declarations),
        declarations: records(DECLARATION_OFFSET, declarations, 14).into_iter().map(|w| {
            GpuSemanticInterfaceDeclarationRecord {
                module: w[0], name_hash_lo: w[1], name_hash_hi: w[2], name_byte_start: w[3],
                name_byte_len: w[4], namespace: w[5], kind: w[6], signature_type: w[7],
                first_member: w[8], member_count: w[9], owner_declaration: w[10], flags: w[11],
                value_lo: w[12], value_hi: w[13],
            }
        }).collect(),
        type_library_id: table(TYPE_LIBRARY_OFFSET, types),
        type_unit_id: table(TYPE_UNIT_OFFSET, types),
        type_local_index: table(TYPE_LOCAL_OFFSET, types),
        types: records(TYPE_OFFSET, types, 9).into_iter().map(|w| GpuSemanticInterfaceTypeRecord {
            kind: w[0], payload_lo: w[1], payload_hi: w[2], first_edge: w[3], edge_count: w[4],
            length_kind: w[5], length_lo: w[6], length_hi: w[7], nominal_unit_id: w[8],
        }).collect(),
        module_declaration_start: table(MODULE_DECLARATION_START_OFFSET, modules),
        module_declaration_count: table(MODULE_DECLARATION_COUNT_OFFSET, modules),
        module_declaration_order: table(MODULE_DECLARATION_ORDER_OFFSET, declarations),
        type_edges: table(TYPE_EDGE_OFFSET, edges).into_iter()
            .map(|type_index| GpuSemanticInterfaceTypeEdge { type_index }).collect(),
        members: records(MEMBER_OFFSET, members, 12).into_iter().map(|w| GpuSemanticInterfaceMemberRecord {
            owner_ref: w[0], kind: w[1], ordinal: w[2], name_hash_lo: w[3], name_hash_hi: w[4],
            name_byte_start: w[5], name_byte_len: w[6], type_index: w[7], value_lo: w[8],
            value_hi: w[9], receiver_type_index: w[10], generic_parameter_ordinal: w[11],
        }).collect(),
        predicate_library_id: table(PREDICATE_LIBRARY_OFFSET, predicates),
        predicate_unit_id: table(PREDICATE_UNIT_OFFSET, predicates),
        predicate_local_index: table(PREDICATE_LOCAL_OFFSET, predicates),
        predicates: records(PREDICATE_OFFSET, predicates, 8).into_iter().map(|w| {
            GpuSemanticInterfacePredicateRecord {
                owner_ref: w[0], owner_scope_symbol: w[1], subject_type: w[2],
                trait_library_id: w[3], trait_unit_id: w[4], trait_declaration_index: w[5],
                first_argument: w[6], argument_count: w[7],
            }
        }).collect(),
        predicate_arguments: table(PREDICATE_ARGUMENT_OFFSET, predicate_arguments),
        implementation_library_id: table(IMPLEMENTATION_LIBRARY_OFFSET, implementations),
        implementation_unit_id: table(IMPLEMENTATION_UNIT_OFFSET, implementations),
        implementation_local_index: table(IMPLEMENTATION_LOCAL_OFFSET, implementations),
        implementations: records(IMPLEMENTATION_OFFSET, implementations, 15).into_iter().map(|w| {
            GpuSemanticInterfaceImplementationRecord {
                module: w[0], visibility: w[1], trait_library_id: w[2], trait_unit_id: w[3],
                trait_declaration_index: w[4], subject_type: w[5], first_argument: w[6],
                argument_count: w[7], first_member: w[8], member_count: w[9],
                first_prerequisite: w[10], prerequisite_count: w[11], first_method_binding: w[12],
                method_binding_count: w[13], kind: w[14],
            }
        }).collect(),
        implementation_arguments: table(IMPLEMENTATION_ARGUMENT_OFFSET, implementation_arguments),
        implementation_method_bindings: records(IMPLEMENTATION_METHOD_BINDING_OFFSET, bindings, 6)
            .into_iter()
            .map(|w| GpuSemanticInterfaceImplementationMethodBindingRecord {
                implementation_index: w[0], required_method_symbol: w[1],
                implementation_method_member: w[2], target_library_id: w[3],
                target_unit_id: w[4], target_symbol: w[5],
            })
            .collect(),
        name_bytes: names,
        words: Vec::new(),
    };
    Ok(DecodedDependencyPage { words, ..decoded })
}

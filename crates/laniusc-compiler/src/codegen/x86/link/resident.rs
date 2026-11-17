//! The resident x86 link of a native C build.
//!
//! The object projection parks each lowered object on the GPU when its
//! projection is recorded ([`park`]): the metadata words, relocation and
//! symbol rows, text and rodata are copied into a store the linker keeps.
//! The retained build's original-call rewrite adds the rewritten undefined
//! identities ([`park_identities`]). When the object is published
//! (`GpuX86ObjectStage::finish`) its slot is committed under the object's
//! `(library, unit)`. The link then runs in two submissions
//! (`shaders/codegen/x86/link/resident/`):
//!
//! 1. Before the host finalizes: plan the text copies and section bases,
//!    place every symbol (applying the discovery routes to provisional uses,
//!    as the finalizer does), index the definitions and C bindings, and mark
//!    the C names the program references. A worker thread reads the totals
//!    and those names, resolves the names against the shared libraries and
//!    packs the dynamic rows while the host finalizes.
//! 2. After finalization: write the Lanius dynamic symbol rows, gather the
//!    section bytes, write the ELF dynamic parts and apply the relocations.
//!    The host reads the finished image.
//!
//! Every check the host link makes has a GPU counterpart that sets an error
//! bit. Any error, a C driver link, or a store that does not hold the build's
//! objects returns `None`, and the caller links on the host, which also
//! reports the exact diagnostic.

use std::sync::{Arc, Mutex};

use anyhow::{Context, Result};

use super::super::{GpuX86Linker, TailSpan, native};
use super::dynamic::{X86DynamicImage, X86DynamicMain};
use crate::{
    compiler::NativeCFunction,
    gpu::{
        buffers::LaniusBuffer,
        passes_core::{PassData, bind_group, flush_deferred_compute, record_or_defer_compute_direct},
    },
};

const SLOT_WORDS: usize = 20;
const META_WORDS: u64 = 32;
const OBJECT_WORDS: usize = 24;
const SYMBOL_WORDS: usize = 8;
const STATUS_WORDS: usize = 64;
const ST_TEXT_LEN: usize = 0;
const ST_RODATA_LEN: usize = 1;
const ST_DEF_COUNT: usize = 2;
const ST_NAME_STRIDE: usize = 3;
const ST_ENTRY_OBJECT: usize = 4;
const ST_MAIN_OFFSET: usize = 5;
const ST_ERRORS: usize = 16;
const ST_EMIT_ERRORS: usize = 17;

/// Store regions, in words: metadata, relocation rows (semantic then native
/// runtime), undefined rows, definition rows, text, rodata, and the
/// undefined identities after the retained build's call rewrite.
const REGIONS: usize = 7;
const INITIAL_WORDS: [u64; REGIONS] = [64 * 32, 1 << 20, 1 << 18, 1 << 18, 1 << 20, 1 << 18, 1 << 18];

struct Chunk {
    buffers: [LaniusBuffer<u32>; REGIONS],
    capacity: [u64; REGIONS],
    cursor: [u64; REGIONS],
}

impl Chunk {
    fn new(device: &wgpu::Device, capacity: [u64; REGIONS]) -> Self {
        let buffers = std::array::from_fn(|region| {
            let bytes = capacity[region].max(1) * 4;
            let buffer = device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("codegen.x86.link.resident.store"),
                size: bytes,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            });
            LaniusBuffer::new((buffer, bytes), capacity[region].max(1) as usize)
        });
        Self { buffers, capacity, cursor: [0; REGIONS] }
    }

    fn fits(&self, need: &[u64; REGIONS]) -> bool {
        (0..REGIONS).all(|region| self.cursor[region] + need[region] <= self.capacity[region])
    }
}

/// One parked object: its chunk and the word base of each region.
#[derive(Clone, Copy)]
struct Slot {
    chunk: usize,
    base: [u64; REGIONS],
    /// Row and byte capacities: relocations, runtime relocations, undefined
    /// rows, definitions, text bytes, rodata bytes.
    caps: [u32; 6],
    key: Option<(u32, u32)>,
    /// Whether region 6 holds the rewritten undefined identities.
    identities: bool,
}

struct StoreState {
    generation: u64,
    chunks: Vec<Chunk>,
    slots: Vec<Slot>,
}

/// Lowered objects of the current native build, parked on the GPU.
pub(crate) struct GpuX86LinkStore {
    device: wgpu::Device,
    queue: wgpu::Queue,
    state: Mutex<StoreState>,
}

static ACTIVE: Mutex<Option<Arc<GpuX86LinkStore>>> = Mutex::new(None);

/// Keeps a store active (parking objects) until dropped.
pub(crate) struct ActiveLinkStore {
    store: Option<Arc<GpuX86LinkStore>>,
}

impl Drop for ActiveLinkStore {
    fn drop(&mut self) {
        if let Some(store) = self.store.take() {
            let mut active = ACTIVE.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            if active.as_ref().is_some_and(|current| Arc::ptr_eq(current, &store)) {
                *active = None;
            }
        }
    }
}

impl ActiveLinkStore {
    pub(crate) fn is_active(&self) -> bool {
        self.store.is_some()
    }
}

/// A source range of one object region, in its graph workspace buffer.
pub(crate) struct ParkRegion<'a> {
    pub buffer: &'a wgpu::Buffer,
    pub offset: u64,
    pub bytes: u64,
}

/// What `park` copies: the five metadata copies as (buffer, offset, bytes,
/// destination word), then the payload regions in store order with
/// relocations split into semantic and runtime rows. Region byte counts are
/// the job's bounds; `caps` gives the same bounds in rows and bytes.
pub(crate) struct ParkSources<'a> {
    pub meta: [(&'a wgpu::Buffer, u64, u64, u64); 5],
    pub relocations: ParkRegion<'a>,
    pub runtime_relocations: ParkRegion<'a>,
    pub undefined: ParkRegion<'a>,
    pub definitions: ParkRegion<'a>,
    pub text: ParkRegion<'a>,
    pub rodata: ParkRegion<'a>,
}

/// A parked object that `commit` publishes when its projection succeeded.
pub(crate) struct ParkTicket {
    store: Arc<GpuX86LinkStore>,
    generation: u64,
    slot: usize,
}

impl ParkTicket {
    /// The parked object's text and rodata, which the host reads only if it
    /// links the object itself ([`ResidentSections::read`]).
    pub(crate) fn sections(&self, text_len: u32, rodata_len: u32) -> ResidentSections {
        ResidentSections {
            store: self.store.clone(),
            generation: self.generation,
            slot: self.slot,
            text_len,
            rodata_len,
        }
    }

    /// Whether the object parked in `store`.
    pub(crate) fn is_in(&self, store: &Arc<GpuX86LinkStore>) -> bool {
        Arc::ptr_eq(&self.store, store)
    }

    pub(crate) fn commit(self, library_id: u32, unit_id: u32) {
        let mut state = self.store.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.generation == self.generation
            && let Some(slot) = state.slots.get_mut(self.slot)
        {
            slot.key = Some((library_id, unit_id));
        }
    }
}

/// The text and rodata of an object parked in the store. A resident link
/// reads them on the GPU; a host link of the same build reads them back.
pub(crate) struct ResidentSections {
    store: Arc<GpuX86LinkStore>,
    generation: u64,
    slot: usize,
    pub(crate) text_len: u32,
    pub(crate) rodata_len: u32,
}

impl std::fmt::Debug for ResidentSections {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ResidentSections")
            .field("generation", &self.generation)
            .field("slot", &self.slot)
            .field("text_len", &self.text_len)
            .field("rodata_len", &self.rodata_len)
            .finish()
    }
}

impl ResidentSections {
    /// Text then rodata, read from the store while it still holds this
    /// build's objects.
    pub(crate) fn read(&self) -> Result<Vec<u8>, String> {
        let store = &self.store;
        let (text, rodata) = (u64::from(self.text_len), u64::from(self.rodata_len));
        let readback = store.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.codegen.x86.link.resident.sections"),
            size: (text.next_multiple_of(4) + rodata.next_multiple_of(4)).max(4),
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        {
            let state = store.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            let slot = state
                .slots
                .get(self.slot)
                .filter(|_| state.generation == self.generation)
                .ok_or("the parked native object belongs to an earlier build")?;
            if u64::from(slot.caps[4]) < text || u64::from(slot.caps[5]) < rodata {
                return Err("the parked native object is shorter than its sections".into());
            }
            let chunk = &state.chunks[slot.chunk];
            let mut encoder = store.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("codegen.x86.link.resident.sections"),
            });
            if text != 0 {
                encoder.copy_buffer_to_buffer(&chunk.buffers[4].buffer, slot.base[4] * 4, &readback, 0, text.next_multiple_of(4));
            }
            if rodata != 0 {
                encoder.copy_buffer_to_buffer(
                    &chunk.buffers[5].buffer,
                    slot.base[5] * 4,
                    &readback,
                    text.next_multiple_of(4),
                    rodata.next_multiple_of(4),
                );
            }
            store.queue.submit(Some(encoder.finish()));
        }
        let slice = readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(&store.device, &slice, "codegen.x86.link.resident.sections")
            .map_err(|error| format!("read parked native object sections: {error:#}"))?;
        let mapped = slice.get_mapped_range();
        let mut bytes = Vec::with_capacity((text + rodata) as usize);
        bytes.extend_from_slice(&mapped[..text as usize]);
        let rodata_at = text.next_multiple_of(4) as usize;
        bytes.extend_from_slice(&mapped[rodata_at..rodata_at + rodata as usize]);
        Ok(bytes)
    }
}

/// Copies one object's projection into the active store, if any. Recorded
/// after the projection in the same encoder.
pub(crate) fn park(encoder: &mut wgpu::CommandEncoder, sources: &ParkSources<'_>) -> Option<ParkTicket> {
    let store = ACTIVE.lock().unwrap_or_else(std::sync::PoisonError::into_inner).clone()?;
    let regions = [
        &sources.relocations,
        &sources.runtime_relocations,
        &sources.undefined,
        &sources.definitions,
        &sources.text,
        &sources.rodata,
    ];
    let words = |region: &ParkRegion<'_>| region.bytes.div_ceil(4);
    let need = [
        META_WORDS,
        words(regions[0]) + words(regions[1]),
        words(regions[2]),
        words(regions[3]),
        words(regions[4]),
        words(regions[5]),
        regions[2].bytes / 16 * 3,
    ];
    let caps = [
        (regions[0].bytes / 32) as u32,
        (regions[1].bytes / 32) as u32,
        (regions[2].bytes / 16) as u32,
        (regions[3].bytes / 32) as u32,
        regions[4].bytes as u32,
        regions[5].bytes as u32,
    ];
    let mut state = store.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
    if state.chunks.last().is_none_or(|chunk| !chunk.fits(&need)) {
        let previous = state.chunks.last().map_or(INITIAL_WORDS, |chunk| chunk.capacity);
        let capacity = std::array::from_fn(|region| need[region].max(previous[region] * 2));
        state.chunks.push(Chunk::new(&store.device, capacity));
    }
    let chunk_index = state.chunks.len() - 1;
    let chunk = &mut state.chunks[chunk_index];
    let base = chunk.cursor;
    for region in 0..REGIONS {
        chunk.cursor[region] += need[region];
    }
    flush_deferred_compute(encoder);
    let meta = &chunk.buffers[0];
    for (buffer, offset, bytes, word) in sources.meta {
        encoder.copy_buffer_to_buffer(buffer, offset, &meta.buffer, (base[0] + word) * 4, bytes);
    }
    let mut copy = |region: &ParkRegion<'_>, store_region: usize, word: u64| {
        if region.bytes != 0 {
            encoder.copy_buffer_to_buffer(
                region.buffer,
                region.offset,
                &chunk.buffers[store_region].buffer,
                word * 4,
                region.bytes.next_multiple_of(4),
            );
        }
    };
    copy(regions[0], 1, base[1]);
    copy(regions[1], 1, base[1] + words(regions[0]));
    copy(regions[2], 2, base[2]);
    copy(regions[3], 3, base[3]);
    copy(regions[4], 4, base[4]);
    copy(regions[5], 5, base[5]);
    let slot = state.slots.len();
    state.slots.push(Slot { chunk: chunk_index, base, caps, key: None, identities: false });
    Some(ParkTicket { store: store.clone(), generation: state.generation, slot })
}

/// Records the identities of the first `undefined` symbols of the published
/// unit `(library_id, unit_id)` after the retained build rewrote its generic
/// calls (`program_retention/native_calls.rs`): `identity` holds the
/// object's identity column, twelve bytes per symbol.
pub(crate) fn park_identities(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    library_id: u32,
    unit_id: u32,
    identity: &wgpu::Buffer,
    undefined: u32,
) {
    let Some(store) = ACTIVE.lock().unwrap_or_else(std::sync::PoisonError::into_inner).clone() else {
        return;
    };
    let mut state = store.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
    let Some(slot) = state.slots.iter_mut().rev().find(|slot| slot.key == Some((library_id, unit_id))) else {
        return;
    };
    let bytes = u64::from(undefined) * 12;
    if undefined > slot.caps[2] || bytes > identity.size() {
        return;
    }
    slot.identities = true;
    let (chunk, base) = (slot.chunk, slot.base[6]);
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("codegen.x86.link.resident.identities"),
    });
    if bytes != 0 {
        encoder.copy_buffer_to_buffer(identity, 0, &state.chunks[chunk].buffers[6].buffer, base * 4, bytes);
    }
    crate::gpu::passes_core::submit_with_progress(queue, "codegen.x86.link.resident.identities", encoder.finish());
}

impl GpuX86LinkStore {
    fn new(device: &wgpu::Device, queue: &wgpu::Queue) -> Self {
        Self {
            device: device.clone(),
            queue: queue.clone(),
            state: Mutex::new(StoreState { generation: 0, chunks: Vec::new(), slots: Vec::new() }),
        }
    }

    /// Empties the store and makes it the one objects park into, unless
    /// another build's store is active.
    fn activate(self: &Arc<Self>) -> ActiveLinkStore {
        let mut active = ACTIVE.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if active.is_some() {
            return ActiveLinkStore { store: None };
        }
        let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        state.generation += 1;
        state.slots.clear();
        // Keep the largest chunk; a build that needed several leaves one
        // chunk holding them all after its link (`consolidate`).
        if let Some(largest) = (0..state.chunks.len())
            .max_by_key(|&index| state.chunks[index].capacity.iter().sum::<u64>())
        {
            let mut chunk = state.chunks.swap_remove(largest);
            chunk.cursor = [0; REGIONS];
            state.chunks = vec![chunk];
        }
        drop(state);
        *active = Some(self.clone());
        ActiveLinkStore { store: Some(self.clone()) }
    }

    /// Moves every chunk's contents into one chunk, rebasing the slots.
    fn consolidate(&self, state: &mut StoreState, encoder: &mut wgpu::CommandEncoder) {
        if state.chunks.len() <= 1 {
            return;
        }
        let mut capacity = [0u64; REGIONS];
        for chunk in &state.chunks {
            for region in 0..REGIONS {
                capacity[region] += chunk.cursor[region];
            }
        }
        let capacity = std::array::from_fn(|region| capacity[region] + capacity[region] / 4);
        let mut merged = Chunk::new(&self.device, capacity);
        let mut rebase = Vec::with_capacity(state.chunks.len());
        for chunk in &state.chunks {
            rebase.push(merged.cursor);
            for region in 0..REGIONS {
                if chunk.cursor[region] != 0 {
                    encoder.copy_buffer_to_buffer(
                        &chunk.buffers[region].buffer,
                        0,
                        &merged.buffers[region].buffer,
                        merged.cursor[region] * 4,
                        chunk.cursor[region] * 4,
                    );
                }
                merged.cursor[region] += chunk.cursor[region];
            }
        }
        for slot in &mut state.slots {
            for region in 0..REGIONS {
                slot.base[region] += rebase[slot.chunk][region];
            }
            slot.chunk = 0;
        }
        state.chunks = vec![merged];
    }
}

/// The host's view of one object the link reads from the store, in link
/// order: its unit and the counts its published columns have.
#[derive(Clone, Copy, Debug)]
pub(crate) struct ResidentObjectKey {
    pub library_id: u32,
    pub unit_id: u32,
    pub text_len: u32,
    pub rodata_len: u32,
    pub relocation_count: u32,
    pub symbol_count: u32,
}

/// The discovery routes the finalizer applied to provisional uses.
pub(crate) struct ResidentRoutes<'a> {
    pub routes: &'a LaniusBuffer<u32>,
    pub route_capacity: u32,
}

/// The finished executable in a mapped readback buffer.
pub(crate) struct ResidentImage {
    device: wgpu::Device,
    /// The image in order; each chunk's copy has its own submission.
    chunks: Vec<ImageChunk>,
    len: usize,
}

struct ImageChunk {
    buffer: LaniusBuffer<u8>,
    len: usize,
    /// Until the chunk is mapped.
    map: Option<crate::gpu::passes_core::PendingReadbackMap>,
}

/// Chunks of the image readback (`ResidentImage`).
const IMAGE_CHUNKS: u64 = 4;
const IMAGE_CHUNK_LABELS: [&str; IMAGE_CHUNKS as usize] = [
    "rb.codegen.x86.link.resident.image.0",
    "rb.codegen.x86.link.resident.image.1",
    "rb.codegen.x86.link.resident.image.2",
    "rb.codegen.x86.link.resident.image.3",
];

impl ResidentImage {
    pub(crate) fn len(&self) -> usize {
        self.len
    }

    /// Hands each chunk to `consume` in order as soon as it is mapped.
    pub(crate) fn for_each_chunk<E>(
        &mut self,
        mut consume: impl FnMut(&[u8]) -> std::result::Result<(), E>,
    ) -> Result<std::result::Result<(), E>> {
        for chunk in &mut self.chunks {
            if let Some(map) = chunk.map.take() {
                crate::gpu::passes_core::finish_readback_map(&self.device, map, std::time::Duration::from_secs(30))?;
            }
            let view = chunk.buffer.buffer.slice(..chunk.len as u64).get_mapped_range();
            if let Err(error) = consume(&view) {
                return Ok(Err(error));
            }
        }
        Ok(Ok(()))
    }

    pub(crate) fn to_vec(&mut self) -> Result<Vec<u8>> {
        let mut bytes = Vec::with_capacity(self.len);
        self.for_each_chunk(|chunk| {
            bytes.extend_from_slice(chunk);
            Ok::<(), std::convert::Infallible>(())
        })?
        .unwrap_or_else(|never| match never {});
        Ok(bytes)
    }
}

impl Drop for ResidentImage {
    fn drop(&mut self) {
        for chunk in &mut self.chunks {
            if let Some(map) = chunk.map.take() {
                // A chunk nobody read: finish its map so the buffer can be
                // unmapped and reused.
                let _ = crate::gpu::passes_core::finish_readback_map(
                    &self.device,
                    map,
                    std::time::Duration::from_secs(30),
                );
            }
            chunk.buffer.buffer.unmap();
        }
    }
}

fn groups(lanes: u32) -> (u32, u32, u32) {
    let groups = lanes.div_ceil(256).max(1);
    if groups <= 65_535 { (groups, 1, 1) } else { (65_535, groups.div_ceil(65_535), 1) }
}

fn checked_u32(value: u64, what: &str) -> Result<u32> {
    u32::try_from(value).with_context(|| format!("resident x86 link {what} exceeds u32"))
}

fn words_of(bytes: &[u8]) -> Vec<u32> {
    bytes.chunks_exact(4).map(|word| u32::from_le_bytes(word.try_into().unwrap())).collect()
}

/// The link's GPU buffers, bound by name in every resident link kernel.
struct LinkBuffers {
    store: [LaniusBuffer<u32>; REGIONS],
    routes: LaniusBuffer<u32>,
    slots: LaniusBuffer<u32>,
    bindings: LaniusBuffer<u32>,
    objects: LaniusBuffer<u32>,
    symbols: LaniusBuffer<u32>,
    sym_hash: LaniusBuffer<u32>,
    small_hash: LaniusBuffer<u32>,
    bind_hash: LaniusBuffer<u32>,
    status: LaniusBuffer<u32>,
    name_ref: LaniusBuffer<u32>,
    import_of_name: LaniusBuffer<u32>,
}

impl LinkBuffers {
    fn resources<'a>(
        &'a self,
        params: &'a LaniusBuffer<u32>,
        dyn_words: &'a LaniusBuffer<u32>,
        output: &'a LaniusBuffer<u32>,
    ) -> Vec<(&'static str, wgpu::BindingResource<'a>)> {
        vec![
            ("gRL", params.as_entire_binding()),
            ("rl_slots", self.slots.as_entire_binding()),
            ("st_meta", self.store[0].as_entire_binding()),
            ("st_reloc", self.store[1].as_entire_binding()),
            ("st_undef", self.store[2].as_entire_binding()),
            ("st_def", self.store[3].as_entire_binding()),
            ("st_text", self.store[4].as_entire_binding()),
            ("st_rodata", self.store[5].as_entire_binding()),
            ("st_ident", self.store[6].as_entire_binding()),
            ("rl_routes", self.routes.as_entire_binding()),
            ("rl_bindings", self.bindings.as_entire_binding()),
            ("rl_import_of_name", self.import_of_name.as_entire_binding()),
            ("rl_objects", self.objects.as_entire_binding()),
            ("rl_symbols", self.symbols.as_entire_binding()),
            ("rl_sym_hash", self.sym_hash.as_entire_binding()),
            ("rl_small_hash", self.small_hash.as_entire_binding()),
            ("rl_bind_hash", self.bind_hash.as_entire_binding()),
            ("rl_status", self.status.as_entire_binding()),
            ("rl_name_ref", self.name_ref.as_entire_binding()),
            ("rl_dyn_words", dyn_words.as_entire_binding()),
            ("rl_out", output.as_entire_binding()),
        ]
    }
}

fn dispatch(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    label: &'static str,
    lanes: u32,
    resources: &[(&str, wgpu::BindingResource<'_>)],
) -> Result<()> {
    let group = bind_group::create_bind_group_from_bindings(device, Some(label), pass, 0, resources)?;
    record_or_defer_compute_direct(encoder, pass, &group, label, groups(lanes));
    Ok(())
}

/// What the host derives from the plan readback: the plan words, the import
/// index of each C name slot, the dynamic writer's rows and the image length.
struct Prepared {
    words: Vec<u32>,
    import_count: u32,
    import_of_name: Vec<u32>,
    rows: super::dynamic::X86DynamicRows,
    total: u32,
}

/// A link whose first submission is in flight (`begin_resident_dynamic`). A
/// worker waits for the plan readback and resolves the referenced C names
/// while the host finalizes.
pub(crate) struct ResidentPlan {
    params: [u32; 16],
    symbol_cap_total: u32,
    reloc_cap_total: u32,
    buffers: LinkBuffers,
    prepared: Option<std::thread::JoinHandle<Result<Option<Prepared>>>>,
}

impl Drop for ResidentPlan {
    /// An abandoned plan still leaves its readback unmapped for the next link.
    fn drop(&mut self) {
        if let Some(worker) = self.prepared.take() {
            let _ = worker.join();
        }
    }
}

/// The worker of a `ResidentPlan`.
fn prepare(
    device: wgpu::Device,
    first: LaniusBuffer<u8>,
    first_bytes: usize,
    pending: crate::gpu::passes_core::PendingReadbackMap,
    names: Vec<String>,
    options: native::NativeLinkOptions,
    object_count: u32,
) -> Result<Option<Prepared>> {
    crate::gpu::passes_core::finish_readback_map(&device, pending, std::time::Duration::from_secs(30))?;
    let words = words_of(&first.buffer.slice(..first_bytes as u64).get_mapped_range());
    first.buffer.unmap();
    let _span = TailSpan::new("tail.native.resident.prepare");
    if words[ST_ERRORS] != 0 {
        log::debug!("resident x86 link plan failed: error bits {:#x}", words[ST_ERRORS]);
        return Ok(None);
    }
    let referenced = names
        .iter()
        .zip(&words[STATUS_WORDS..])
        .filter(|(_, flag)| **flag != 0)
        .map(|(name, _)| name.as_str())
        .collect::<Vec<_>>();
    let imports = match native::resolve::resolve_native_imports(&referenced, &options) {
        Ok(native::NativeResolution::Dynamic(imports)) => imports,
        _ => return Ok(None),
    };
    let import_index = imports
        .imports
        .iter()
        .enumerate()
        .map(|(index, import)| (import.name.as_str(), index as u32))
        .collect::<std::collections::HashMap<_, _>>();
    let import_of_name = names
        .iter()
        .map(|name| import_index.get(name.as_str()).copied().unwrap_or(u32::MAX))
        .collect::<Vec<_>>();
    let image = X86DynamicImage::new(
        &imports,
        object_count,
        X86DynamicMain {
            object_index: words[ST_ENTRY_OBJECT],
            text_offset: words[ST_MAIN_OFFSET],
            byte_len: crate::codegen::x86::GPU_X86_CRT_MAIN_BRIDGE_BYTES,
        },
    )?;
    let (rows, total) = image.resident_rows(
        words[ST_TEXT_LEN],
        words[ST_RODATA_LEN],
        words[ST_DEF_COUNT],
        words[ST_NAME_STRIDE],
        words[ST_MAIN_OFFSET],
    )?;
    if total as usize > options.max_output_bytes {
        return Ok(None);
    }
    Ok(Some(Prepared {
        words,
        import_count: imports.imports.len() as u32,
        import_of_name,
        rows,
        total,
    }))
}

impl GpuX86Linker {
    fn resident_store(&self, device: &wgpu::Device, queue: &wgpu::Queue) -> Arc<GpuX86LinkStore> {
        self.resident_store
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get_or_insert_with(|| Arc::new(GpuX86LinkStore::new(device, queue)))
            .clone()
    }

    /// This linker's store while it is the one objects park into. The
    /// active store is process-wide, so a build checks that an object it
    /// lowered parked in its own linker's store before it relies on it.
    pub(crate) fn parking_store(&self) -> Option<Arc<GpuX86LinkStore>> {
        let own = self.resident_store.lock().unwrap_or_else(std::sync::PoisonError::into_inner).clone()?;
        let active = ACTIVE.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        active.as_ref().is_some_and(|store| Arc::ptr_eq(store, &own)).then_some(own)
    }

    /// Parks the objects lowered until the returned guard drops.
    pub(crate) fn activate_resident_store(&self, device: &wgpu::Device, queue: &wgpu::Queue) -> ActiveLinkStore {
        self.resident_store(device, queue).activate()
    }

    fn link_storage(&self, device: &wgpu::Device, label: &str, words: usize) -> LaniusBuffer<u32> {
        self.reusable_storage_u32(device, label, words, wgpu::BufferUsages::empty())
    }

    /// Submits the first half of the link of the parked objects `objects`
    /// (in link order): the plan, symbol placement and the C name marks.
    /// It needs only the discovery routes, so it runs while the host
    /// finalizes. `None` when the host link has to run instead.
    pub(crate) fn begin_resident_dynamic(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        objects: &[ResidentObjectKey],
        bindings: &[NativeCFunction],
        options: &native::NativeLinkOptions,
        routes: ResidentRoutes<'_>,
    ) -> Result<Option<ResidentPlan>> {
        if !cfg!(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu"))
            || objects.is_empty()
        {
            return Ok(None);
        }
        let Ok(foreign) = native::validate_bindings(bindings) else {
            return Ok(None);
        };
        let _span = TailSpan::new("tail.native.resident.record");
        let store = self.resident_store(device, queue);
        let mut state = store.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        // The committed slot of each object, by unit.
        let mut by_key = std::collections::HashMap::with_capacity(state.slots.len());
        for (index, slot) in state.slots.iter().enumerate() {
            if let Some(key) = slot.key
                && by_key.insert(key, index).is_some()
            {
                return Ok(None);
            }
        }
        let mut chosen = Vec::with_capacity(objects.len());
        for object in objects {
            match by_key.get(&(object.library_id, object.unit_id)) {
                Some(&slot) => chosen.push(slot),
                None => return Ok(None),
            }
        }
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.x86.link.resident.plan.encoder"),
        });
        store.consolidate(&mut state, &mut encoder);

        // Slot table (rl_common.slang).
        let mut slot_words = Vec::with_capacity(objects.len() * SLOT_WORDS);
        let (mut symbol_cap_total, mut reloc_cap_total, mut text_cap_max) = (0u64, 0u64, 0u32);
        for (object, &index) in objects.iter().zip(&chosen) {
            let slot = &state.slots[index];
            let [reloc, runtime, undefined, definitions, text, rodata] = slot.caps;
            let reloc_row = slot.base[1] / 8;
            slot_words.extend_from_slice(&[
                checked_u32(reloc_row, "relocation row")?,
                reloc,
                checked_u32(reloc_row + u64::from(reloc), "relocation row")?,
                runtime,
                checked_u32(slot.base[2] / 4, "undefined row")?,
                undefined,
                checked_u32(slot.base[3] / 8, "definition row")?,
                definitions,
                checked_u32(slot.base[4] * 4, "text byte")?,
                checked_u32(slot.base[5] * 4, "rodata byte")?,
                checked_u32(symbol_cap_total, "symbol capacity")?,
                checked_u32(reloc_cap_total, "relocation capacity")?,
                text,
                rodata,
                object.text_len,
                object.rodata_len,
                object.relocation_count,
                object.symbol_count,
                checked_u32(slot.base[6], "identity word")?,
                u32::from(slot.identities),
            ]);
            symbol_cap_total += u64::from(undefined) + u64::from(definitions);
            reloc_cap_total += u64::from(reloc) + u64::from(runtime);
            text_cap_max = text_cap_max.max(text);
        }
        let symbol_cap_total = checked_u32(symbol_cap_total, "symbol capacity")?;
        let reloc_cap_total = checked_u32(reloc_cap_total, "relocation capacity")?;
        let object_count = checked_u32(objects.len() as u64, "object count")?;

        // C names, sorted, and one row per bound identity.
        let mut names = foreign.values().map(|binding| binding.name.as_str()).collect::<Vec<_>>();
        names.sort_unstable();
        names.dedup();
        let mut binding_rows = Vec::with_capacity(foreign.len() * 4);
        for (identity, binding) in &foreign {
            let name = names.binary_search(&binding.name.as_str()).expect("bound name is listed");
            binding_rows.extend_from_slice(&[identity[0], identity[1], identity[2], name as u32]);
        }
        let binding_count = (binding_rows.len() / 4) as u32;
        let hash_size = (2 * symbol_cap_total.max(binding_count)).max(64).next_power_of_two();
        let small_size = (2 * symbol_cap_total).max(64).next_power_of_two();
        let compare_lanes = object_count
            .checked_mul(text_cap_max.max(1))
            .context("resident x86 link runtime comparison exceeds u32 lanes")?;
        let params = [
            object_count,
            symbol_cap_total,
            reloc_cap_total,
            binding_count,
            hash_size - 1,
            small_size - 1,
            routes.route_capacity,
            text_cap_max,
            0,
            0,
            0,
            0,
            names.len() as u32,
            0,
            0,
            0,
        ];

        let buffers = LinkBuffers {
            store: state.chunks[0].buffers.clone(),
            routes: routes.routes.clone(),
            slots: self.reusable_input_u32(device, queue, "codegen.x86.link.resident.slots", &slot_words),
            bindings: self.reusable_input_u32(device, queue, "codegen.x86.link.resident.bindings", &binding_rows),
            objects: self.link_storage(device, "codegen.x86.link.resident.objects", objects.len() * OBJECT_WORDS),
            symbols: self.link_storage(
                device,
                "codegen.x86.link.resident.symbols",
                symbol_cap_total as usize * SYMBOL_WORDS,
            ),
            sym_hash: self.link_storage(device, "codegen.x86.link.resident.sym_hash", hash_size as usize),
            small_hash: self.link_storage(device, "codegen.x86.link.resident.small_hash", small_size as usize * 2),
            bind_hash: self.link_storage(device, "codegen.x86.link.resident.bind_hash", hash_size as usize),
            status: self.link_storage(device, "codegen.x86.link.resident.status", STATUS_WORDS),
            name_ref: self.link_storage(device, "codegen.x86.link.resident.name_ref", names.len()),
            import_of_name: self.link_storage(device, "codegen.x86.link.resident.import_of_name", names.len()),
        };
        drop(state);
        let mut status_init = [0u32; STATUS_WORDS];
        status_init[ST_NAME_STRIDE] = 1;
        queue.write_buffer(
            &buffers.status.buffer,
            buffers.status.byte_offset,
            super::super::support::u32_words_bytes(&status_init),
        );
        for (buffer, words) in [
            (&buffers.objects, objects.len() * OBJECT_WORDS),
            (&buffers.sym_hash, hash_size as usize),
            (&buffers.small_hash, small_size as usize * 2),
            (&buffers.bind_hash, hash_size as usize),
            (&buffers.name_ref, names.len().max(1)),
        ] {
            encoder.clear_buffer(&buffer.buffer, buffer.byte_offset, Some(words as u64 * 4));
        }
        let gparams = self.reusable_uniform_u32(device, queue, "codegen.x86.link.resident.params", &params);
        // The dynamic writer's buffers are sized after the plan; the first
        // submission binds them at their retained capacity.
        let dyn_words = self.link_storage(device, "codegen.x86.link.resident.dyn_words", 1);
        let output = self.link_storage(device, "codegen.x86.link.resident.output", 1);
        let resources = buffers.resources(&gparams, &dyn_words, &output);
        for (pass, label, lanes) in [
            (&self.rl_bind_pass, "codegen.x86.link.resident.bind", binding_count),
            (&self.rl_compare_pass, "codegen.x86.link.resident.compare", compare_lanes),
            (&self.rl_plan_pass, "codegen.x86.link.resident.plan", 1),
            (&self.rl_define_pass, "codegen.x86.link.resident.define", symbol_cap_total),
            (&self.rl_insert_pass, "codegen.x86.link.resident.insert", symbol_cap_total),
            (&self.rl_undefined_pass, "codegen.x86.link.resident.undefined", symbol_cap_total),
        ] {
            dispatch(device, &mut encoder, pass, label, lanes, &resources)?;
        }
        drop(resources);
        flush_deferred_compute(&mut encoder);
        let first_bytes = (STATUS_WORDS + names.len()) * 4;
        let first = self.reusable_readback(device, "rb.codegen.x86.link.resident.plan", first_bytes);
        encoder.copy_buffer_to_buffer(
            &buffers.status.buffer,
            buffers.status.byte_offset,
            &first.buffer,
            0,
            STATUS_WORDS as u64 * 4,
        );
        if !names.is_empty() {
            encoder.copy_buffer_to_buffer(
                &buffers.name_ref.buffer,
                buffers.name_ref.byte_offset,
                &first.buffer,
                STATUS_WORDS as u64 * 4,
                names.len() as u64 * 4,
            );
        }
        crate::gpu::passes_core::submit_with_progress(queue, "codegen.x86.link.resident.plan", encoder.finish());
        let pending = crate::gpu::passes_core::begin_readback_map(
            &first.buffer.slice(..first_bytes as u64),
            "codegen.x86.link.resident.plan",
        );
        let worker = {
            let device = device.clone();
            let names = names.iter().map(|name| (*name).to_owned()).collect();
            let options = options.clone();
            std::thread::Builder::new()
                .name("laniusc-resident-link".into())
                .spawn(move || prepare(device, first, first_bytes, pending, names, options, object_count))
                .context("spawn the resident x86 link worker")?
        };
        Ok(Some(ResidentPlan {
            params,
            symbol_cap_total,
            reloc_cap_total,
            buffers,
            prepared: Some(worker),
        }))
    }

    /// Completes a link `begin_resident_dynamic` started: writes the image
    /// from the worker's rows and reads it back.
    pub(crate) fn finish_resident_dynamic(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        mut plan: ResidentPlan,
    ) -> Result<Option<ResidentImage>> {
        let wait = TailSpan::new("tail.native.resident.wait_plan");
        let worker = plan.prepared.take().expect("the plan worker is running");
        let prepared = worker
            .join()
            .map_err(|_| anyhow::anyhow!("the resident x86 link worker panicked"))??;
        drop(wait);
        let Some(Prepared { words, import_count, import_of_name, rows, total }) = prepared else {
            return Ok(None);
        };
        let rodata_len = words[ST_RODATA_LEN];
        let text_len_total = rows.params[12];
        let output_words = total.div_ceil(4);
        let mut params = plan.params;
        params[8] = import_count;
        params[9] = text_len_total;
        params[10] = total;
        params[11] = rows.params[19];
        params[13] = 0x78 / 4;
        params[14] = (0x78 + text_len_total + rodata_len).div_ceil(4);

        let span = TailSpan::new("tail.native.resident.record_emit");
        let buffers = &plan.buffers;
        let gparams = self.reusable_uniform_u32(device, queue, "codegen.x86.link.resident.params", &params);
        if !import_of_name.is_empty() {
            queue.write_buffer(
                &buffers.import_of_name.buffer,
                buffers.import_of_name.byte_offset,
                super::super::support::u32_words_bytes(&import_of_name),
            );
        }
        let dyn_word_count = rows.words.len() + words[ST_DEF_COUNT] as usize * SYMBOL_WORDS;
        let dyn_words = self.link_storage(device, "codegen.x86.link.resident.dyn_words", dyn_word_count);
        queue.write_buffer(
            &dyn_words.buffer,
            dyn_words.byte_offset,
            super::super::support::u32_words_bytes(&rows.words),
        );
        let output = self.link_storage(device, "codegen.x86.link.resident.output", output_words as usize);
        let strings = self.reusable_input_bytes_with_capacity(
            device,
            queue,
            "codegen.x86.link.resident.strings",
            &rows.strings,
            4,
        );
        let gdyn = self.reusable_uniform_u32(device, queue, "codegen.x86.link.resident.dyn_params", &rows.params);
        let dyn_status = self.link_storage(device, "codegen.x86.link.resident.dyn_status", 4);
        queue.write_buffer(
            &dyn_status.buffer,
            dyn_status.byte_offset,
            super::super::support::u32_words_bytes(&[1, 0, u32::MAX, 0]),
        );
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.x86.link.resident.emit.encoder"),
        });
        encoder.clear_buffer(&output.buffer, output.byte_offset, Some(u64::from(output_words) * 4));
        {
            let resources = buffers.resources(&gparams, &dyn_words, &output);
            dispatch(
                device,
                &mut encoder,
                &self.rl_dynsym_pass,
                "codegen.x86.link.resident.dynsym",
                plan.symbol_cap_total,
                &resources,
            )?;
            dispatch(
                device,
                &mut encoder,
                &self.rl_gather_pass,
                "codegen.x86.link.resident.gather",
                params[14] - params[13],
                &resources,
            )?;
            let dynamic = [
                ("gDyn", gdyn.as_entire_binding()),
                ("dynamic_words", dyn_words.as_entire_binding()),
                ("dynamic_strings", strings.as_entire_binding()),
                ("out_words", output.as_entire_binding()),
                ("link_relocation_status", dyn_status.as_entire_binding()),
            ];
            dispatch(
                device,
                &mut encoder,
                &self.elf_dynamic_write_pass,
                "codegen.x86.link.resident.dynamic_write",
                rows.element_count,
                &dynamic,
            )?;
            dispatch(
                device,
                &mut encoder,
                &self.rl_reloc_pass,
                "codegen.x86.link.resident.reloc",
                plan.reloc_cap_total,
                &resources,
            )?;
        }
        flush_deferred_compute(&mut encoder);
        // The status in one small readback with the emit, then the image in
        // chunks of their own submissions: the host writes one chunk while
        // the GPU copies the next.
        let image_bytes = u64::from(output_words) * 4;
        let status_bytes = (STATUS_WORDS + 4) * 4;
        let status = self.reusable_readback(device, "rb.codegen.x86.link.resident.status", status_bytes);
        encoder.copy_buffer_to_buffer(
            &buffers.status.buffer,
            buffers.status.byte_offset,
            &status.buffer,
            0,
            STATUS_WORDS as u64 * 4,
        );
        encoder.copy_buffer_to_buffer(
            &dyn_status.buffer,
            dyn_status.byte_offset,
            &status.buffer,
            STATUS_WORDS as u64 * 4,
            16,
        );
        crate::gpu::passes_core::submit_with_progress(queue, "codegen.x86.link.resident.emit", encoder.finish());
        let status_slice = status.buffer.slice(..status_bytes as u64);
        let status_map = crate::gpu::passes_core::begin_readback_map(&status_slice, "codegen.x86.link.resident.emit");
        let chunk_bytes = image_bytes.div_ceil(IMAGE_CHUNKS).next_multiple_of(4).max(4);
        let mut chunks = Vec::with_capacity(IMAGE_CHUNKS as usize);
        let mut at = 0;
        while at < u64::from(total) {
            let bytes = chunk_bytes.min(image_bytes - at);
            let buffer = self.reusable_readback(
                device,
                IMAGE_CHUNK_LABELS[chunks.len()],
                bytes as usize,
            );
            let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("codegen.x86.link.resident.image.encoder"),
            });
            encoder.copy_buffer_to_buffer(&output.buffer, output.byte_offset + at, &buffer.buffer, 0, bytes);
            crate::gpu::passes_core::submit_with_progress(queue, "codegen.x86.link.resident.image", encoder.finish());
            let len = (u64::from(total) - at).min(bytes);
            let map = crate::gpu::passes_core::begin_readback_map(
                &buffer.buffer.slice(..len),
                "codegen.x86.link.resident.image",
            );
            chunks.push(ImageChunk { buffer, len: len as usize, map: Some(map) });
            at += bytes;
        }
        drop(span);

        let wait = TailSpan::new("tail.native.resident.wait_emit");
        crate::gpu::passes_core::finish_readback_map(device, status_map, std::time::Duration::from_secs(30))?;
        drop(wait);
        let tail = words_of(&status_slice.get_mapped_range());
        status.buffer.unmap();
        // Dropping the image on a failed emit finishes the chunk maps.
        let image = ResidentImage { device: device.clone(), chunks, len: total as usize };
        if tail[ST_ERRORS] != 0
            || tail[ST_EMIT_ERRORS] != 0
            || tail[STATUS_WORDS] != 1
            || tail[STATUS_WORDS + 1] != 0
        {
            log::debug!(
                "resident x86 link emit failed: errors {:#x}, emit errors {:#x}, dynamic status {:?}",
                tail[ST_ERRORS],
                tail[ST_EMIT_ERRORS],
                &tail[STATUS_WORDS..],
            );
            return Ok(None);
        }
        Ok(Some(image))
    }
}

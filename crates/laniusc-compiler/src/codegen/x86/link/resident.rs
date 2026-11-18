//! The resident x86 link of a native C build.
//!
//! The object projection parks each lowered object on the GPU when its
//! projection is recorded ([`park`]): the metadata words, relocation and
//! symbol rows, text and rodata are copied into a store the linker keeps.
//! The retained build's original-call rewrite adds the rewritten undefined
//! identities ([`ParkedSlot::record_identities`]). When the object is published
//! (`GpuX86ObjectStage::finish`) its slot is committed under the object's
//! `(library, unit)`. The link then runs in two submissions
//! (`shaders/codegen/x86/link/resident/`):
//!
//! 1. Before the host finalizes, in one submission: plan the text copies
//!    and section bases, place every symbol (applying the discovery routes to
//!    provisional uses, as the finalizer does), index the definitions and C
//!    bindings and mark the C names the program references; resolve those
//!    names against the exports of the link's libraries, which the host
//!    lists and uploads as system inputs, and write the dynamic writer's rows
//!    (`rl_cnames.slang`); then emit: write the Lanius dynamic symbol rows,
//!    gather the section bytes, write the ELF dynamic parts and apply the
//!    relocations, with dispatches the GPU sizes. The host reads the status
//!    of all of it in one readback.
//! 2. After finalization: copy the image, at its exact length, to a
//!    readback. The host writes it out.
//!
//! Every check the host link makes has a GPU counterpart that sets an error
//! bit. Any error, a C driver link, or a store that does not hold the build's
//! objects returns `None`, and the caller links on the host, which also
//! reports the exact diagnostic.

use crate::gpu::copies::{CountedCommands, CountedWrites};
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result};

use super::super::{GpuX86Linker, TailSpan, native};
use super::dynamic::{DynamicCounts, MAX_NAME_STRIDE, X86DynamicImage, dynamic_layout};
use crate::{
    compiler::NativeCFunction,
    gpu::{
        buffers::LaniusBuffer,
        passes_core::{
            PassData,
            PendingReadbackMap,
            bind_group,
            flush_deferred_compute,
            record_or_defer_compute_direct,
            record_or_defer_compute_indirect_offset,
        },
    },
};

const SLOT_WORDS: usize = 21;
const META_WORDS: u64 = 32;
const OBJECT_WORDS: usize = 24;
const SYMBOL_WORDS: usize = 8;
const STATUS_WORDS: usize = 64;
const ST_NAME_STRIDE: usize = 3;
const ST_ERRORS: usize = 16;
// Object plan words (rl_common.slang `OB_*`) the host checks.
const OB_TEXT_LEN: usize = 0;
const OB_RODATA_LEN: usize = 1;
const OB_UNDEF_COUNT: usize = 15;
const OB_DEF_COUNT: usize = 16;
const OB_RELOC_COUNT: usize = 17;
const OB_RT_COUNT: usize = 18;
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
    /// One `rl_park.slang` parameter block per slot index, rewritten by
    /// each build's park into that slot.
    park_params: Vec<wgpu::Buffer>,
}

/// Lowered objects of the current native build, parked on the GPU.
pub(crate) struct GpuX86LinkStore {
    device: wgpu::Device,
    queue: wgpu::Queue,
    /// `rl_park.slang`: copies an object's used rows and bytes into a slot.
    park_pass: PassData,
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

    /// The slot this object parked in, for a link planned before the host
    /// read the object back ([`GpuX86Linker::begin_resident_dynamic`]).
    pub(crate) fn parked_slot(&self) -> ParkedSlot {
        ParkedSlot { store: self.store.clone(), generation: self.generation, slot: self.slot }
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

/// The slot of a parked object the host has not read back yet.
pub(crate) struct ParkedSlot {
    store: Arc<GpuX86LinkStore>,
    generation: u64,
    slot: usize,
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
                encoder.copy_buffer_counted(&chunk.buffers[4].buffer, slot.base[4] * 4, &readback, 0, text.next_multiple_of(4));
            }
            if rodata != 0 {
                encoder.copy_buffer_counted(
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
        crate::gpu::passes_core::map_readback_blocking(&store.device, &slice, crate::readback_label!("codegen.x86.link.resident.sections"))
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
        encoder.copy_buffer_counted(buffer, offset, &meta.buffer, (base[0] + word) * 4, bytes);
    }
    // The regions' rows and bytes as far as the object's metadata counts
    // them (`rl_park.slang`); `need` and `caps` keep the job's bounds, which
    // the plan checks the counts against.
    let dst = [base[1], base[1] + words(regions[0]), base[2], base[3], base[4], base[5]];
    // `ParkParams`: four header words, then source offsets, store bases and
    // store capacities in words, each as rows (four regions) then bytes
    // (text, rodata) in one uint4 pair.
    let mut params = [0u32; 28];
    let mut words_total = 0u64;
    for (index, region) in regions.iter().enumerate() {
        let (src, dst, cap) = (region.offset / 4, dst[index], words(*region));
        words_total = words_total.max(cap);
        let (Ok(src), Ok(dst), Ok(cap)) = (u32::try_from(src), u32::try_from(dst), u32::try_from(cap)) else {
            return None;
        };
        params[4 + index] = src;
        params[12 + index] = dst;
        params[20 + index] = cap;
    }
    let workgroups = u32::try_from(words_total.div_ceil(256).clamp(1, 1024)).unwrap_or(1024);
    params[0] = u32::try_from(base[0]).ok()?;
    params[1] = workgroups * 256;
    let slot = state.slots.len();
    while state.park_params.len() <= slot {
        state.park_params.push(store.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("codegen.x86.link.resident.park.params"),
            size: std::mem::size_of_val(&params) as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        }));
    }
    let params_buffer = state.park_params[slot].clone();
    let bytes: Vec<u8> = params.iter().flat_map(|word| word.to_le_bytes()).collect();
    store.queue.write_buffer_counted(&params_buffer, 0, &bytes);
    let chunk = &state.chunks[chunk_index];
    let meta = &chunk.buffers[0];
    let resources = [
        ("gPK", params_buffer.as_entire_binding()),
        ("pk_meta", meta.as_entire_binding()),
        ("pk_src_reloc", regions[0].buffer.as_entire_binding()),
        ("pk_src_runtime", regions[1].buffer.as_entire_binding()),
        ("pk_src_undef", regions[2].buffer.as_entire_binding()),
        ("pk_src_def", regions[3].buffer.as_entire_binding()),
        ("pk_src_text", regions[4].buffer.as_entire_binding()),
        ("pk_src_rodata", regions[5].buffer.as_entire_binding()),
        ("pk_reloc", chunk.buffers[1].as_entire_binding()),
        ("pk_undef", chunk.buffers[2].as_entire_binding()),
        ("pk_def", chunk.buffers[3].as_entire_binding()),
        ("pk_text", chunk.buffers[4].as_entire_binding()),
        ("pk_rodata", chunk.buffers[5].as_entire_binding()),
    ];
    let label = "codegen.x86.link.resident.park";
    let group = bind_group::create_bind_group_from_bindings(&store.device, Some(label), &store.park_pass, 0, &resources).ok()?;
    record_or_defer_compute_direct(encoder, &store.park_pass, &group, label, (workgroups, 1, 1));
    state.slots.push(Slot { chunk: chunk_index, base, caps, key: None, identities: false });
    Some(ParkTicket { store: store.clone(), generation: state.generation, slot })
}

impl ParkedSlot {
    /// Records the copy of the object's undefined identities after the
    /// retained build rewrote its generic calls
    /// (`program_retention/native_calls.rs`): `identity` holds three words
    /// per undefined symbol, for every row the slot can hold.
    pub(crate) fn record_identities(&self, encoder: &mut wgpu::CommandEncoder, identity: &wgpu::Buffer) {
        let mut state = self.store.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.generation != self.generation {
            return;
        }
        let Some(slot) = state.slots.get_mut(self.slot) else {
            return;
        };
        let bytes = (u64::from(slot.caps[2]) * 12).min(identity.size()) / 4 * 4;
        slot.identities = true;
        let (chunk, base) = (slot.chunk, slot.base[6]);
        if bytes != 0 {
            encoder.copy_buffer_counted(identity, 0, &state.chunks[chunk].buffers[6].buffer, base * 4, bytes);
        }
    }
}

impl GpuX86LinkStore {
    fn new(device: &wgpu::Device, queue: &wgpu::Queue, park_pass: PassData) -> Self {
        Self {
            device: device.clone(),
            queue: queue.clone(),
            park_pass,
            state: Mutex::new(StoreState { generation: 0, chunks: Vec::new(), slots: Vec::new(), park_params: Vec::new() }),
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
                    encoder.copy_buffer_counted(
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

/// The finished executable in a readback of its exact length. The emit
/// status came with the plan readback (`finish_resident_dynamic`).
pub(crate) struct ResidentImage {
    device: wgpu::Device,
    buffer: LaniusBuffer<u8>,
    len: usize,
    /// Until the readback is mapped.
    map: Option<PendingReadbackMap>,
}

impl ResidentImage {
    pub(crate) fn len(&self) -> usize {
        self.len
    }

    /// Waits for the image readback. Always true: the emit status was read
    /// with the plan.
    pub(crate) fn finish(&mut self) -> Result<bool> {
        if let Some(map) = self.map.take() {
            let _wait = TailSpan::new("tail.native.resident.wait_emit");
            crate::gpu::passes_core::finish_readback_map(&self.device, map, std::time::Duration::from_secs(30))?;
        }
        Ok(true)
    }

    /// Hands the image to `consume`; `finish` must have returned true.
    pub(crate) fn with_bytes<R>(&self, consume: impl FnOnce(&[u8]) -> R) -> R {
        assert!(self.map.is_none(), "the resident image is read after finish");
        let view = self.buffer.buffer.slice(..self.len as u64).get_mapped_range();
        consume(&view)
    }
}

impl Drop for ResidentImage {
    fn drop(&mut self) {
        if let Some(map) = self.map.take() {
            // Nobody waited: finish the map so the buffer can be unmapped and
            // reused.
            let _ = crate::gpu::passes_core::finish_readback_map(
                &self.device,
                map,
                std::time::Duration::from_secs(30),
            );
        }
        self.buffer.buffer.unmap();
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

/// The plan readback: the link status words, the C-name status words
/// (`rl_dynamic_rows.slang`, from `CN_BITS`), the dynamic writer's status,
/// then the pending object's plan words.
const RB_NAMES: usize = STATUS_WORDS;
const RB_DYNAMIC: usize = RB_NAMES + NAME_STATUS_WORDS;
const RB_PENDING: usize = RB_DYNAMIC + 4;
const NAME_STATUS_WORDS: usize = 8;
const NAMES_BITS: usize = 0;
const NAMES_TOTAL: usize = 1;
const NAMES_NEED_DYN: usize = 2;
const NAMES_NEED_STRINGS: usize = 3;
const NAMES_NEED_OUTPUT: usize = 4;
const BIT_CAPACITY: u32 = 16;
/// `cn_out` (`rl_dynamic_rows.slang`): gRL words 8 to 15, gDyn, four
/// indirect dispatches, then the status words.
const CN_OUT_WORDS: usize = 52;
const CN_DYN: u64 = 8;
const CN_ARGS: u64 = 32;
const CN_BITS: u64 = 44;
const CN_INPUT_WORDS: usize = 8;
const CN_MAX_INPUTS: usize = 64;
const GATE_ON: u32 = 1;
const GATE_FORCE_FAIL: u32 = 2;
const DYN_PARAMS: usize = 24;

/// A fault the tests force on the resident emit.
#[doc(hidden)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ResidentEmitFault {
    #[default]
    None,
    /// The C-name step's gate fails, so the host links.
    Gate,
    /// The first emit's output is one word long, so the host records it again.
    Capacity,
}

/// What the emit may write: output words, dynamic row words, string bytes.
#[derive(Clone, Copy, Debug)]
struct TailCaps {
    output_words: u32,
    dyn_words: u32,
    string_bytes: u32,
}

/// The C-name match's inputs and results (`rl_cnames.slang`).
struct NameBuffers {
    params: [u32; 16],
    bytes: LaniusBuffer<u8>,
    rows: LaniusBuffer<u32>,
    versions: LaniusBuffer<u32>,
    inputs: LaniusBuffer<u32>,
    names: LaniusBuffer<u32>,
    name_hash: LaniusBuffer<u32>,
    matches: LaniusBuffer<u32>,
    scratch: LaniusBuffer<u32>,
    out: LaniusBuffer<u32>,
}

/// The emit's buffers, sized by `TailCaps`.
struct TailBuffers {
    gdyn: LaniusBuffer<u32>,
    dyn_words: LaniusBuffer<u32>,
    output: LaniusBuffer<u32>,
    strings: LaniusBuffer<u32>,
    dyn_status: LaniusBuffer<u32>,
}

/// A link whose plan, C-name resolution and emit are in flight
/// (`begin_resident_dynamic`).
pub(crate) struct ResidentPlan {
    device: wgpu::Device,
    params: [u32; 16],
    buffers: LinkBuffers,
    names: NameBuffers,
    tail: TailBuffers,
    readback: LaniusBuffer<u8>,
    read_bytes: u64,
    /// Until the plan readback is mapped.
    map: Option<PendingReadbackMap>,
    pending: Option<PendingObject>,
    max_output_bytes: usize,
}

/// The last object of a plan recorded before the host read it back: its
/// slot and its lengths once the host has them
/// ([`ResidentPlan::confirm_pending`]).
struct PendingObject {
    store: Arc<GpuX86LinkStore>,
    generation: u64,
    slot: usize,
    expected: Option<[u32; 4]>,
}

impl ResidentPlan {
    /// Whether the plan's pending object is `key`: the host committed the
    /// object to the slot the plan read. The plan then checks the object's
    /// lengths against the ones the plan derived from the parked metadata,
    /// as `rl_plan.slang` does for the objects the host read before it.
    pub(crate) fn confirm_pending(&mut self, key: &ResidentObjectKey) -> bool {
        let Some(pending) = &mut self.pending else {
            return false;
        };
        let state = pending.store.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        let committed = state.generation == pending.generation
            && state.slots.get(pending.slot).is_some_and(|slot| slot.key == Some((key.library_id, key.unit_id)));
        drop(state);
        if committed {
            pending.expected = Some([key.text_len, key.rodata_len, key.relocation_count, key.symbol_count]);
        }
        committed
    }

    /// Waits for the plan readback and returns its words.
    fn read(&mut self) -> Result<Vec<u32>> {
        if let Some(map) = self.map.take() {
            crate::gpu::passes_core::finish_readback_map(&self.device, map, std::time::Duration::from_secs(30))?;
        }
        let words = words_of(&self.readback.buffer.slice(..self.read_bytes).get_mapped_range());
        self.readback.buffer.unmap();
        Ok(words)
    }
}

impl Drop for ResidentPlan {
    /// An abandoned plan still leaves its readback unmapped for the next link.
    fn drop(&mut self) {
        if let Some(map) = self.map.take() {
            let _ = crate::gpu::passes_core::finish_readback_map(
                &self.device,
                map,
                std::time::Duration::from_secs(30),
            );
            self.readback.buffer.unmap();
        }
    }
}

fn dispatch_indirect(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    label: &'static str,
    args: &LaniusBuffer<u32>,
    offset: u64,
    resources: &[(&str, wgpu::BindingResource<'_>)],
) -> Result<()> {
    let group = bind_group::create_bind_group_from_bindings(device, Some(label), pass, 0, resources)?;
    record_or_defer_compute_indirect_offset(encoder, pass, &group, label, args, offset);
    Ok(())
}

impl GpuX86Linker {
    fn resident_store(&self, device: &wgpu::Device, queue: &wgpu::Queue) -> Arc<GpuX86LinkStore> {
        self.resident_store
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get_or_insert_with(|| Arc::new(GpuX86LinkStore::new(device, queue, self.rl_park_pass.clone())))
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
        pending: Option<&ParkedSlot>,
        bindings: &[NativeCFunction],
        options: &native::NativeLinkOptions,
        routes: ResidentRoutes<'_>,
        fault: ResidentEmitFault,
    ) -> Result<Option<ResidentPlan>> {
        if !cfg!(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu"))
            || objects.len() + usize::from(pending.is_some()) == 0
        {
            return Ok(None);
        }
        let Ok(foreign) = native::validate_bindings(bindings) else {
            return Ok(None);
        };
        // The libraries the link reads, as the GNU linker finds them.
        let inputs_span = TailSpan::new("tail.native.resident.inputs");
        let inputs = match native::resolve::packed_link_inputs(options) {
            Ok(native::resolve::PackedInputs::Inputs(inputs)) if inputs.len() <= CN_MAX_INPUTS => inputs,
            Ok(native::resolve::PackedInputs::Inputs(inputs)) => {
                log::debug!("resident x86 link: {} inputs exceed the GPU name match", inputs.len());
                return Ok(None);
            }
            Ok(native::resolve::PackedInputs::Driver(reason)) => {
                log::debug!("resident x86 link: the C driver links: {reason}");
                return Ok(None);
            }
            Err(error) => {
                log::debug!("resident x86 link inputs: {error:#}");
                return Ok(None);
            }
        };
        drop(inputs_span);
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
        let mut chosen = Vec::with_capacity(objects.len() + 1);
        for object in objects {
            match by_key.get(&(object.library_id, object.unit_id)) {
                Some(&slot) => chosen.push(slot),
                None => return Ok(None),
            }
        }
        // An object the host has not read back is the plan's last; its slot
        // is uncommitted until the host has read it.
        if let Some(pending) = pending {
            let parked = Arc::ptr_eq(&pending.store, &store)
                && pending.generation == state.generation
                && state.slots.get(pending.slot).is_some_and(|slot| slot.key.is_none());
            if !parked {
                return Ok(None);
            }
            chosen.push(pending.slot);
        }
        // Lengths of an object the host has not read: `rl_plan.slang` skips
        // the comparison and `finish_resident_dynamic` makes it.
        const UNREAD: ResidentObjectKey = ResidentObjectKey {
            library_id: u32::MAX,
            unit_id: u32::MAX,
            text_len: u32::MAX,
            rodata_len: u32::MAX,
            relocation_count: u32::MAX,
            symbol_count: u32::MAX,
        };
        let objects = objects.iter().chain(pending.map(|_| &UNREAD)).collect::<Vec<_>>();
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.x86.link.resident.plan.encoder"),
        });
        store.consolidate(&mut state, &mut encoder);

        // Slot table (rl_common.slang).
        let mut slot_words = Vec::with_capacity(objects.len() * SLOT_WORDS);
        let (mut symbol_cap_total, mut reloc_cap_total, mut text_cap_max) = (0u64, 0u64, 0u32);
        let (mut text_cap_sum, mut rodata_cap_sum) = (0u64, 0u64);
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
                checked_u32(slot.base[0], "metadata word")?,
            ]);
            symbol_cap_total += u64::from(undefined) + u64::from(definitions);
            reloc_cap_total += u64::from(reloc) + u64::from(runtime);
            text_cap_max = text_cap_max.max(text);
            text_cap_sum += u64::from(text);
            rodata_cap_sum += u64::from(rodata);
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

        // The candidate imports: __libc_start_main, then the bound names in
        // byte order, as `resolve_native_imports` orders them, with the name
        // slot `rl_undefined` marks.
        let start_main = native::resolve::LIBC_START_MAIN;
        let mut candidates = Vec::with_capacity(names.len() + 1);
        candidates.push((start_main, names.binary_search(&start_main).ok()));
        candidates.extend(names.iter().enumerate().filter(|(_, name)| **name != start_main).map(|(slot, name)| (*name, Some(slot))));
        if candidates.iter().any(|(name, _)| name.as_bytes().contains(&0)) {
            return Ok(None);
        }
        // Every input's exports and versions, then the candidates and the
        // sonames, in one byte buffer (rl_cnames.slang).
        let mut name_bytes = Vec::new();
        let (mut rows, mut versions, mut input_words) = (Vec::new(), Vec::new(), Vec::with_capacity(inputs.len() * CN_INPUT_WORDS));
        let mut wild_row = u32::MAX;
        let mut string_bound = 1u64;
        for input in &inputs {
            let table = &input.table;
            let row_base = rows.len() / 3;
            if wild_row == u32::MAX
                && let Some(row) = table.rows.chunks_exact(3).position(|row| row[1] == u32::MAX)
            {
                wild_row = checked_u32((row_base + row) as u64, "name row")?;
            }
            input_words.extend_from_slice(&[
                checked_u32(row_base as u64, "name row")?,
                checked_u32(table.rows.len() as u64 / 3, "name row")?,
                checked_u32(name_bytes.len() as u64, "name byte")?,
                checked_u32(versions.len() as u64 / 2, "version")?,
                checked_u32(table.versions.len() as u64 / 2, "version")?,
                0,
                input.soname.as_ref().map_or(0, |soname| soname.len() as u32),
                u32::from(input.soname.is_none()),
            ]);
            string_bound += table.versions.chunks_exact(2).map(|version| u64::from(version[1]) + 1).sum::<u64>();
            rows.extend_from_slice(&table.rows);
            versions.extend_from_slice(&table.versions);
            name_bytes.extend_from_slice(&table.bytes);
        }
        let mut candidate_rows = Vec::with_capacity(candidates.len() * 3);
        for (name, slot) in &candidates {
            candidate_rows.extend_from_slice(&[
                checked_u32(name_bytes.len() as u64, "name byte")?,
                name.len() as u32,
                slot.map_or(u32::MAX, |slot| slot as u32),
            ]);
            string_bound += name.len() as u64 + 1;
            name_bytes.extend_from_slice(name.as_bytes());
        }
        for (index, input) in inputs.iter().enumerate() {
            if let Some(soname) = &input.soname {
                input_words[index * CN_INPUT_WORDS + 5] = checked_u32(name_bytes.len() as u64, "name byte")?;
                string_bound += soname.len() as u64 + 1;
                name_bytes.extend_from_slice(soname.as_bytes());
            }
        }
        checked_u32(name_bytes.len() as u64, "name byte")?;
        let candidate_count = candidates.len() as u32;
        let input_count = inputs.len() as u32;
        let row_count = checked_u32(rows.len() as u64 / 3, "name row")?;
        let version_count = checked_u32(versions.len() as u64 / 2, "version")?;
        let name_size = (2 * candidate_count).max(64).next_power_of_two();
        // What the emit can write, from the capacities: every output length
        // grows with each count.
        let import_text_bound = u64::from(X86DynamicImage::import_text_len(candidates.len())?);
        let (_, output_bound) = dynamic_layout(DynamicCounts {
            imports: candidates.len() as u64,
            strings: string_bound,
            verneed_rows: u64::from(input_count + version_count),
            needed: u64::from(input_count),
            text_len: text_cap_sum + import_text_bound,
            rodata_len: rodata_cap_sum,
            symbols: u64::from(symbol_cap_total),
            stride: MAX_NAME_STRIDE,
        });
        let output_limit = (options.max_output_bytes as u64)
            .min(device.limits().max_storage_buffer_binding_size as u64)
            .div_ceil(4);
        let caps = TailCaps {
            output_words: if fault == ResidentEmitFault::Capacity {
                1
            } else {
                checked_u32(output_bound.div_ceil(4).min(output_limit), "output")?
            },
            dyn_words: checked_u32(
                2 * u64::from(candidate_count)
                    + u64::from(input_count)
                    + 4 * u64::from(input_count + version_count)
                    + u64::from(symbol_cap_total) * SYMBOL_WORDS as u64,
                "dynamic rows",
            )?,
            string_bytes: checked_u32(string_bound, "string table")?,
        };
        let gate = if fault == ResidentEmitFault::Gate { GATE_FORCE_FAIL } else { GATE_ON };
        let names_buffers = NameBuffers {
            params: [
                candidate_count,
                input_count,
                row_count,
                version_count,
                name_size - 1,
                wild_row,
                gate,
                0,
                0,
                0,
                symbol_cap_total,
                reloc_cap_total,
                names.len() as u32,
                crate::codegen::x86::GPU_X86_CRT_MAIN_BRIDGE_BYTES,
                0,
                0,
            ],
            bytes: self.reusable_input_bytes_with_capacity(device, queue, "codegen.x86.link.resident.cn_bytes", &name_bytes, 4),
            rows: self.reusable_input_u32(device, queue, "codegen.x86.link.resident.cn_rows", &rows),
            versions: self.reusable_input_u32(device, queue, "codegen.x86.link.resident.cn_versions", &versions),
            inputs: self.reusable_input_u32(device, queue, "codegen.x86.link.resident.cn_inputs", &input_words),
            names: self.reusable_input_u32(device, queue, "codegen.x86.link.resident.cn_names", &candidate_rows),
            name_hash: self.link_storage(device, "codegen.x86.link.resident.cn_name_hash", name_size as usize),
            matches: self.link_storage(device, "codegen.x86.link.resident.cn_match", candidates.len() * 3),
            scratch: self.link_storage(
                device,
                "codegen.x86.link.resident.cn_scratch",
                candidates.len() * 2 + versions.len() / 2 * 3,
            ),
            out: self.reusable_storage_u32(
                device,
                "codegen.x86.link.resident.cn_out",
                CN_OUT_WORDS,
                wgpu::BufferUsages::INDIRECT,
            ),
        };

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
        queue.write_buffer_counted(
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
            (&names_buffers.name_hash, name_size as usize),
            (&names_buffers.matches, candidates.len() * 3),
            (&names_buffers.scratch, candidates.len() * 2 + versions.len() / 2 * 3),
            (&names_buffers.out, CN_OUT_WORDS),
        ] {
            encoder.clear_buffer_counted(&buffer.buffer, buffer.byte_offset, Some(words as u64 * 4));
        }
        let gparams = self.reusable_uniform_u32(device, queue, "codegen.x86.link.resident.params", &params);
        {
            // The plan's kernels bind the emit's buffers at their retained
            // capacity; the emit binds them again at its own.
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
        }
        let gcn = self.name_params(device, queue, &names_buffers, caps, gate);
        {
            let resources = name_resources(&names_buffers, &gcn, &buffers, None);
            dispatch(device, &mut encoder, &self.rl_name_hash_pass, "codegen.x86.link.resident.name_hash", candidate_count, &resources)?;
            dispatch(device, &mut encoder, &self.rl_import_match_pass, "codegen.x86.link.resident.import_match", row_count, &resources)?;
        }
        let read_bytes = ((RB_PENDING + if pending.is_some() { OBJECT_WORDS } else { 0 }) * 4) as u64;
        let readback = self.reusable_readback(device, "rb.codegen.x86.link.resident.plan", read_bytes as usize);
        let pending_object = pending.map(|_| objects.len() - 1);
        let tail = self.record_tail(
            device,
            queue,
            &mut encoder,
            TailRecord { buffers: &buffers, names: &names_buffers, gparams: &gparams, readback: &readback },
            caps,
            gate,
            pending_object,
        )?;
        crate::gpu::passes_core::submit_with_progress(queue, "codegen.x86.link.resident.plan", encoder.finish());
        let map = crate::gpu::passes_core::begin_readback_map(
            &readback.buffer.slice(..read_bytes),
            crate::readback_label!("codegen.x86.link.resident.plan"),
        );
        Ok(Some(ResidentPlan {
            device: device.clone(),
            params,
            buffers,
            names: names_buffers,
            tail,
            readback,
            read_bytes,
            map: Some(map),
            pending: pending.map(|pending| PendingObject {
                store: pending.store.clone(),
                generation: pending.generation,
                slot: pending.slot,
                expected: None,
            }),
            max_output_bytes: options.max_output_bytes,
        }))
    }

    /// The C-name step's parameters with the emit's capacities and gate.
    fn name_params(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        names: &NameBuffers,
        caps: TailCaps,
        gate: u32,
    ) -> LaniusBuffer<u32> {
        let mut params = names.params;
        params[6] = gate;
        params[7] = caps.output_words;
        params[8] = caps.dyn_words;
        params[9] = caps.string_bytes;
        self.reusable_uniform_u32(device, queue, "codegen.x86.link.resident.cn_params", &params)
    }

    /// Records the dynamic rows (`rl_dynamic_rows.slang`), the emit behind
    /// them with the dispatches they size, and the copies of every status
    /// word (and of the pending object's plan words) to the plan readback.
    fn record_tail(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        record: TailRecord<'_>,
        caps: TailCaps,
        gate: u32,
        pending_object: Option<usize>,
    ) -> Result<TailBuffers> {
        let TailRecord { buffers, names, gparams, readback } = record;
        let gcn = self.name_params(device, queue, names, caps, gate);
        let string_words = caps.string_bytes.div_ceil(4).max(1) as usize;
        let tail = TailBuffers {
            gdyn: self.reusable_uniform_u32(device, queue, "codegen.x86.link.resident.dyn_params", &[0; DYN_PARAMS]),
            dyn_words: self.link_storage(device, "codegen.x86.link.resident.dyn_words", caps.dyn_words as usize),
            output: self.link_storage(device, "codegen.x86.link.resident.output", caps.output_words as usize),
            strings: self.link_storage(device, "codegen.x86.link.resident.strings", string_words),
            dyn_status: self.link_storage(device, "codegen.x86.link.resident.dyn_status", 4),
        };
        queue.write_buffer_counted(
            &tail.dyn_status.buffer,
            tail.dyn_status.byte_offset,
            super::super::support::u32_words_bytes(&[1, 0, u32::MAX, 0]),
        );
        encoder.clear_buffer_counted(&tail.strings.buffer, tail.strings.byte_offset, Some(string_words as u64 * 4));
        {
            let resources = name_resources(names, &gcn, buffers, Some(&tail));
            dispatch(device, encoder, &self.rl_dynamic_rows_pass, "codegen.x86.link.resident.dynamic_rows", 1, &resources)?;
        }
        flush_deferred_compute(encoder);
        // gRL words 8 to 15 and gDyn, as the GPU wrote them.
        encoder.copy_buffer_counted(&names.out.buffer, names.out.byte_offset, &gparams.buffer, gparams.byte_offset + 32, 32);
        encoder.copy_buffer_counted(
            &names.out.buffer,
            names.out.byte_offset + CN_DYN * 4,
            &tail.gdyn.buffer,
            tail.gdyn.byte_offset,
            DYN_PARAMS as u64 * 4,
        );
        {
            let resources = buffers.resources(gparams, &tail.dyn_words, &tail.output);
            let args = &names.out;
            dispatch_indirect(device, encoder, &self.rl_dynsym_pass, "codegen.x86.link.resident.dynsym", args, CN_ARGS * 4, &resources)?;
            dispatch_indirect(device, encoder, &self.rl_gather_pass, "codegen.x86.link.resident.gather", args, CN_ARGS * 4 + 12, &resources)?;
            let dynamic = [
                ("gDyn", tail.gdyn.as_entire_binding()),
                ("dynamic_words", tail.dyn_words.as_entire_binding()),
                ("dynamic_strings", tail.strings.as_entire_binding()),
                ("out_words", tail.output.as_entire_binding()),
                ("link_relocation_status", tail.dyn_status.as_entire_binding()),
            ];
            dispatch_indirect(
                device,
                encoder,
                &self.elf_dynamic_write_pass,
                "codegen.x86.link.resident.dynamic_write",
                args,
                CN_ARGS * 4 + 24,
                &dynamic,
            )?;
            dispatch_indirect(device, encoder, &self.rl_reloc_pass, "codegen.x86.link.resident.reloc", args, CN_ARGS * 4 + 36, &resources)?;
        }
        flush_deferred_compute(encoder);
        encoder.copy_buffer_counted(&buffers.status.buffer, buffers.status.byte_offset, &readback.buffer, 0, STATUS_WORDS as u64 * 4);
        encoder.copy_buffer_counted(
            &names.out.buffer,
            names.out.byte_offset + CN_BITS * 4,
            &readback.buffer,
            RB_NAMES as u64 * 4,
            NAME_STATUS_WORDS as u64 * 4,
        );
        encoder.copy_buffer_counted(&tail.dyn_status.buffer, tail.dyn_status.byte_offset, &readback.buffer, RB_DYNAMIC as u64 * 4, 16);
        if let Some(object) = pending_object {
            encoder.copy_buffer_counted(
                &buffers.objects.buffer,
                buffers.objects.byte_offset + (object * OBJECT_WORDS * 4) as u64,
                &readback.buffer,
                RB_PENDING as u64 * 4,
                OBJECT_WORDS as u64 * 4,
            );
        }
        Ok(tail)
    }

    /// Completes a link `begin_resident_dynamic` started: reads the status
    /// of the plan, the C-name step and the emit, records the emit again
    /// when only its capacity was short, and copies the image at its exact
    /// length to a readback. `ResidentImage::finish` waits for it. `None`
    /// when the host has to link.
    pub(crate) fn finish_resident_dynamic(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        mut plan: ResidentPlan,
    ) -> Result<Option<ResidentImage>> {
        let wait = TailSpan::new("tail.native.resident.wait_plan");
        let first = plan.read()?;
        drop(wait);
        let mut words = first.clone();
        let names_word = |words: &[u32], word: usize| words[RB_NAMES + word];
        if words[ST_ERRORS] == 0 && names_word(&words, NAMES_BITS) == BIT_CAPACITY {
            let _span = TailSpan::new("tail.native.resident.retry");
            let caps = TailCaps {
                output_words: names_word(&words, NAMES_NEED_OUTPUT),
                dyn_words: names_word(&words, NAMES_NEED_DYN),
                string_bytes: names_word(&words, NAMES_NEED_STRINGS),
            };
            if u64::from(caps.output_words) * 4 > plan.max_output_bytes.next_multiple_of(4) as u64 {
                return Ok(None);
            }
            let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("codegen.x86.link.resident.retry.encoder"),
            });
            encoder.clear_buffer_counted(&plan.names.out.buffer, plan.names.out.byte_offset, Some(CN_OUT_WORDS as u64 * 4));
            let gparams = self.reusable_uniform_u32(device, queue, "codegen.x86.link.resident.params", &plan.params);
            plan.tail = self.record_tail(
                device,
                queue,
                &mut encoder,
                TailRecord { buffers: &plan.buffers, names: &plan.names, gparams: &gparams, readback: &plan.readback },
                caps,
                GATE_ON,
                None,
            )?;
            crate::gpu::passes_core::submit_with_progress(queue, "codegen.x86.link.resident.retry", encoder.finish());
            plan.map = Some(crate::gpu::passes_core::begin_readback_map(
                &plan.readback.buffer.slice(..plan.read_bytes),
                crate::readback_label!("codegen.x86.link.resident.plan"),
            ));
            words = plan.read()?;
        }
        let failed = words[ST_ERRORS] != 0
            || names_word(&words, NAMES_BITS) != 0
            || words[ST_EMIT_ERRORS] != 0
            || words[RB_DYNAMIC] != 1
            || words[RB_DYNAMIC + 1] != 0;
        if failed {
            log::debug!(
                "resident x86 link failed: errors {:#x}, C names {:#x}, emit errors {:#x}, dynamic status {:?}",
                words[ST_ERRORS],
                names_word(&words, NAMES_BITS),
                words[ST_EMIT_ERRORS],
                &words[RB_DYNAMIC..RB_DYNAMIC + 4],
            );
            return Ok(None);
        }
        // The slot holds the object the host published for the pending unit
        // (rl_plan.slang checks the other objects).
        if let Some(pending) = &plan.pending {
            let Some([text_len, rodata_len, relocations, symbols]) = pending.expected else {
                return Ok(None);
            };
            let Some(object) = first.get(RB_PENDING..RB_PENDING + OBJECT_WORDS) else {
                return Ok(None);
            };
            let word = |index: usize| u64::from(object[index]);
            if word(OB_TEXT_LEN) != u64::from(text_len)
                || word(OB_RODATA_LEN) != u64::from(rodata_len)
                || word(OB_RELOC_COUNT) + word(OB_RT_COUNT) != u64::from(relocations)
                || word(OB_UNDEF_COUNT) + word(OB_DEF_COUNT) != u64::from(symbols)
            {
                log::debug!("resident x86 link plan: the pending object's lengths differ from its readback");
                return Ok(None);
            }
        }
        let total = names_word(&words, NAMES_TOTAL);
        if total as usize > plan.max_output_bytes {
            return Ok(None);
        }
        let span = TailSpan::new("tail.native.resident.record_image");
        let image_bytes = u64::from(total.div_ceil(4)) * 4;
        let readback = self.reusable_readback(device, "rb.codegen.x86.link.resident.image", image_bytes as usize);
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.x86.link.resident.image.encoder"),
        });
        encoder.copy_buffer_counted(&plan.tail.output.buffer, plan.tail.output.byte_offset, &readback.buffer, 0, image_bytes);
        crate::gpu::passes_core::submit_with_progress(queue, "codegen.x86.link.resident.image", encoder.finish());
        let map = crate::gpu::passes_core::begin_readback_map(
            &readback.buffer.slice(..image_bytes),
            crate::readback_label!("codegen.x86.link.resident.image"),
        );
        drop(span);
        // The caller waits (`ResidentImage::finish`) after it prepares the
        // output file.
        Ok(Some(ResidentImage { device: device.clone(), buffer: readback, len: total as usize, map: Some(map) }))
    }
}

/// The buffers `record_tail` binds and copies into.
struct TailRecord<'a> {
    buffers: &'a LinkBuffers,
    names: &'a NameBuffers,
    gparams: &'a LaniusBuffer<u32>,
    readback: &'a LaniusBuffer<u8>,
}

/// Bindings of the C-name kernels; the dynamic rows also bind the emit's
/// row, string and status buffers.
fn name_resources<'a>(
    names: &'a NameBuffers,
    gcn: &'a LaniusBuffer<u32>,
    buffers: &'a LinkBuffers,
    tail: Option<&'a TailBuffers>,
) -> Vec<(&'static str, wgpu::BindingResource<'a>)> {
    let mut resources = vec![
        ("gCN", gcn.as_entire_binding()),
        ("cn_bytes", names.bytes.as_entire_binding()),
        ("cn_rows", names.rows.as_entire_binding()),
        ("cn_versions", names.versions.as_entire_binding()),
        ("cn_inputs", names.inputs.as_entire_binding()),
        ("cn_names", names.names.as_entire_binding()),
        ("cn_name_hash", names.name_hash.as_entire_binding()),
        ("cn_match", names.matches.as_entire_binding()),
        ("cn_out", names.out.as_entire_binding()),
        ("rl_status", buffers.status.as_entire_binding()),
        ("rl_name_ref", buffers.name_ref.as_entire_binding()),
        ("cn_scratch", names.scratch.as_entire_binding()),
        ("cn_import_of_name", buffers.import_of_name.as_entire_binding()),
    ];
    if let Some(tail) = tail {
        resources.push(("cn_dyn_words", tail.dyn_words.as_entire_binding()));
        resources.push(("cn_strings", tail.strings.as_entire_binding()));
    }
    resources
}

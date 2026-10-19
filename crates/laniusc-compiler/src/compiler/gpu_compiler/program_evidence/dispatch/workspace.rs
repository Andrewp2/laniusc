//! Reusable physical storage, with exclusive ownership for one program session.
//!
//! The pool retains capacities and handles only. Catalogs, packets, proof
//! identities, accepted prefixes and receipts are constructed afresh by their
//! existing owners. A lease outlives every arena that can still use its bytes.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};

use anyhow::{Result, anyhow, ensure};

use crate::gpu::buffers::{CapacityBufferCache, LaniusBuffer};

#[derive(Default)]
struct PhysicalWorkspace {
    buffers: CapacityBufferCache,
    next_slots: HashMap<String, u64>,
    params: ParamsRing,
}

/// Records of one params-ring page.
const PARAMS_PAGE_RECORDS: u64 = 256;
/// Bytes of one dispatch parameter block (8 words).
const PARAMS_BLOCK_BYTES: u64 = 32;

/// The session's dispatch parameter blocks, one aligned record each, bound
/// through a dynamic uniform offset. Pages never move or shrink, so one bind
/// group per page serves every record in it; a session that records more
/// blocks adds pages (sized from the blocks pushed). A record is written when
/// it is pushed, so the next submit applies it before any command that reads
/// it, and no record is reused within a session.
#[derive(Default)]
struct ParamsRing {
    pages: Vec<wgpu::Buffer>,
    stride: u64,
    next: u64,
}

#[derive(Default)]
struct IdleWorkspace {
    generation: u64,
    workspace: Option<PhysicalWorkspace>,
}

struct PoolOwner {
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    idle: Mutex<IdleWorkspace>,
}

/// One bounded idle workspace per compiler/device. Simultaneous sessions get
/// distinct leases; they never share mutable evidence storage. Source frontend
/// resets and replay jobs do not affect a checked-out workspace.
pub(in crate::compiler::gpu_compiler) struct EvidenceWorkspacePool {
    owner: Arc<PoolOwner>,
}

impl EvidenceWorkspacePool {
    pub fn new(device: Arc<wgpu::Device>, queue: Arc<wgpu::Queue>) -> Self {
        Self {
            owner: Arc::new(PoolOwner {
                device,
                queue,
                idle: Mutex::default(),
            }),
        }
    }

    pub fn checkout(&self) -> WorkspaceLease {
        let mut idle = self
            .owner
            .idle
            .lock()
            .expect("evidence workspace pool poisoned");
        let mut workspace = idle.workspace.take().unwrap_or_default();
        workspace.next_slots.clear();
        workspace.params.next = 0;
        WorkspaceLease {
            owner: Arc::new(LeaseOwner {
                pool: self.owner.clone(),
                generation: idle.generation,
                workspace: Mutex::new(Some(workspace)),
            }),
        }
    }

    /// Discard idle capacity, including capacity returned by a lease that was
    /// already active at this trim. Active session ownership is not revoked.
    pub fn release(&self) {
        let mut idle = self
            .owner
            .idle
            .lock()
            .expect("evidence workspace pool poisoned");
        idle.generation = idle
            .generation
            .checked_add(1)
            .expect("evidence workspace trim generation exhausted");
        idle.workspace = None;
    }
}

struct LeaseOwner {
    pool: Arc<PoolOwner>,
    generation: u64,
    workspace: Mutex<Option<PhysicalWorkspace>>,
}

impl Drop for LeaseOwner {
    fn drop(&mut self) {
        let workspace = self
            .workspace
            .get_mut()
            .expect("evidence workspace poisoned")
            .take();
        let mut idle = self
            .pool
            .idle
            .lock()
            .expect("evidence workspace pool poisoned");
        if idle.generation == self.generation && idle.workspace.is_none() {
            idle.workspace = workspace;
        }
    }
}

/// Clone only to retain ownership of the same session. It does not create a
/// second independent writable session or any semantic acceptance capability.
#[derive(Clone)]
pub(in crate::compiler::gpu_compiler) struct WorkspaceLease {
    owner: Arc<LeaseOwner>,
}

impl WorkspaceLease {
    pub fn device(&self) -> &Arc<wgpu::Device> {
        &self.owner.pool.device
    }
    pub fn queue(&self) -> &Arc<wgpu::Queue> {
        &self.owner.pool.queue
    }

    /// Reserve a unique physical role for this session. Repeated labels (for
    /// uploads, dispatch parameters, layout roots, or multiple packets) never
    /// alias. Ordinals restart only after all arenas release the previous lease.
    pub(super) fn reserve(&self, label: &str) -> Result<WorkspaceSlot> {
        let mut owner = self
            .owner
            .workspace
            .lock()
            .expect("evidence workspace poisoned");
        let workspace = owner.as_mut().expect("live evidence workspace lease");
        let next = workspace.next_slots.entry(label.to_owned()).or_default();
        let ordinal = *next;
        *next = next
            .checked_add(1)
            .ok_or_else(|| anyhow!("evidence workspace slot count overflow"))?;
        Ok(WorkspaceSlot {
            lease: self.clone(),
            key: format!("{label}.{ordinal}"),
        })
    }

    /// One fixed physical role that every dispatch of the session shares, for
    /// dispatch-transient tables no dispatch reads from an earlier one. Its
    /// retained capacity, and so its binding identity, stays stable.
    pub(super) fn shared(&self, label: &str) -> WorkspaceSlot {
        WorkspaceSlot {
            lease: self.clone(),
            key: label.to_owned(),
        }
    }

    /// Writes one 8-word parameter block into this session's params ring and
    /// returns its page and the record's dynamic offset. Bind the page at
    /// offset 0 with size [`params_block_size`].
    pub(super) fn push_params(&self, words: &[u32; 8]) -> Result<(wgpu::Buffer, u32)> {
        let device = self.device();
        let mut owner = self
            .owner
            .workspace
            .lock()
            .expect("evidence workspace poisoned");
        let ring = &mut owner.as_mut().expect("live evidence workspace lease").params;
        if ring.stride == 0 {
            let alignment = u64::from(device.limits().min_uniform_buffer_offset_alignment.max(1));
            ring.stride = PARAMS_BLOCK_BYTES.next_multiple_of(alignment);
        }
        let page = usize::try_from(ring.next / PARAMS_PAGE_RECORDS)?;
        let offset = (ring.next % PARAMS_PAGE_RECORDS) * ring.stride;
        if page == ring.pages.len() {
            ring.pages.push(device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("program_evidence.params_ring"),
                size: PARAMS_PAGE_RECORDS * ring.stride,
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            }));
        }
        let mut bytes = [0u8; PARAMS_BLOCK_BYTES as usize];
        for (chunk, word) in bytes.chunks_exact_mut(4).zip(words) {
            chunk.copy_from_slice(&word.to_le_bytes());
        }
        self.queue().write_buffer(&ring.pages[page], offset, &bytes);
        ring.next += 1;
        Ok((ring.pages[page].clone(), u32::try_from(offset)?))
    }

    pub(super) fn initialized(
        &self,
        label: &str,
        words: u32,
        usage: wgpu::BufferUsages,
        contents: Option<&[u32]>,
    ) -> Result<LaniusBuffer<u32>> {
        self.reserve(label)?.buffer(words, usage, contents)
    }
}

/// The bound size of one params-ring record.
pub(super) fn params_block_size() -> std::num::NonZeroU64 {
    std::num::NonZeroU64::new(PARAMS_BLOCK_BYTES).expect("nonzero parameter block")
}

/// A persistent physical role within a session. Arena growth replaces this
/// slot's capacity while the arena keeps the old source handle for ordered
/// prefix/relocation copies. It does not reserve a different role on growth.
pub(super) struct WorkspaceSlot {
    lease: WorkspaceLease,
    key: String,
}

impl WorkspaceSlot {
    pub(super) fn lease(&self) -> &WorkspaceLease {
        &self.lease
    }

    pub(super) fn buffer(
        &self,
        words: u32,
        usage: wgpu::BufferUsages,
        contents: Option<&[u32]>,
    ) -> Result<LaniusBuffer<u32>> {
        let device = self.lease.device();
        let bytes = super::arena::byte_len(words.max(1))?;
        let limits = device.limits();
        ensure!(
            bytes as u64 <= limits.max_buffer_size,
            "evidence allocation {bytes} exceeds device max_buffer_size {}",
            limits.max_buffer_size
        );
        if usage.contains(wgpu::BufferUsages::STORAGE) {
            ensure!(
                bytes as u64 <= limits.max_storage_buffer_binding_size,
                "evidence allocation exceeds device storage binding limit"
            );
        }
        if let Some(data) = contents {
            ensure!(
                data.len() <= words as usize,
                "initial evidence data exceeds allocation"
            );
        }
        let usage = if contents.is_some() {
            usage | wgpu::BufferUsages::COPY_DST
        } else {
            usage
        };
        let buffer = {
            let owner = self
                .lease
                .owner
                .workspace
                .lock()
                .expect("evidence workspace poisoned");
            owner
                .as_ref()
                .expect("live evidence workspace lease")
                .buffers
                .binding_capacity(device, &self.key, bytes, usage)
        };
        if let Some(data) = contents {
            if !data.is_empty() {
                let mut encoded = Vec::with_capacity(data.len() * 4);
                for word in data {
                    encoded.extend_from_slice(&word.to_le_bytes());
                }
                buffer.write(self.lease.queue(), 0, &encoded);
            }
        }
        Ok(buffer)
    }
}

//! Session-owned evidence contents in reusable exclusive physical storage.
use anyhow::{Result, anyhow, ensure};

use super::super::abi::{ArenaCopy, ArenaWrite};
use crate::gpu::{buffers::LaniusBuffer, passes_core};
use super::workspace::{WorkspaceLease, WorkspaceSlot};

pub(super) fn byte_len(words: u32) -> Result<usize> {
    usize::try_from(
        u64::from(words)
            .checked_mul(4)
            .ok_or_else(|| anyhow!("evidence byte size overflow"))?,
    )
    .map_err(|_| anyhow!("evidence byte size exceeds host address space"))
}
fn byte_offset(words: u32) -> u64 {
    u64::from(words) * 4
}

pub(super) struct Arena {
    pub buffer: LaniusBuffer<u32>,
    pub logical_words: u32,
    capacity_words: u32,
    slot: WorkspaceSlot,
}
impl Arena {
    pub fn empty(workspace: &WorkspaceLease, label: &str) -> Result<Self> {
        Self::from_words(workspace, label, &[])
    }

    pub fn from_words(workspace: &WorkspaceLease, label: &str, words: &[u32]) -> Result<Self> {
        let logical_words = u32::try_from(words.len())?;
        let slot = workspace.reserve(label)?;
        let buffer = slot.buffer(logical_words, storage_usage(), Some(words))?;
        let capacity_words = u32::try_from(buffer.byte_size / 4)?;
        Ok(Self { buffer, logical_words, capacity_words, slot })
    }

    pub(super) fn workspace(&self) -> &WorkspaceLease { self.slot.lease() }

    /// Recipe/layout wire formats require an exact logical binding extent.
    /// Retained allocation capacity remains invisible to those validators.
    pub(super) fn logical_binding(&self) -> wgpu::BindingResource<'_> {
        wgpu::BindingResource::Buffer(wgpu::BufferBinding {
            buffer: &self.buffer.buffer,
            offset: self.buffer.byte_offset,
            size: std::num::NonZeroU64::new(byte_offset(self.logical_words.max(1))),
        })
    }

    /// Preserve the old logical prefix before moving table slices. A rare
    /// physical growth copies that prefix once; ordinary submissions copy only
    /// the serializer's relocated ranges, never the entire history.
    pub fn prepare(
        &mut self,
        encoder: &mut wgpu::CommandEncoder,
        logical_words: u32,
        moves: &[ArenaCopy],
    ) -> Result<()> {
        ensure!(
            logical_words >= self.logical_words,
            "persistent evidence arena shrank"
        );
        let device = self.workspace().device().clone();
        let limits = device.limits();
        ensure!(u64::from(logical_words) * 4 <= limits.max_buffer_size
            && u64::from(logical_words) * 4 <= limits.max_storage_buffer_binding_size,
            "evidence logical arena exceeds device storage limits");
        for movement in moves {
            ensure!(
                movement.from_word <= self.logical_words
                    && movement.word_count <= self.logical_words - movement.from_word,
                "evidence relocation reads outside old logical arena"
            );
            ensure!(
                movement.to_word <= logical_words
                    && movement.word_count <= logical_words - movement.to_word,
                "evidence relocation writes outside new logical arena"
            );
        }
        passes_core::flush_deferred_compute(encoder);
        // Reused capacity may still contain another program's bytes. Clear
        // every newly exposed logical range BEFORE relocation writes into it.
        // A real physical growth receives WGPU's fresh zeroed allocation.
        if logical_words <= self.capacity_words && logical_words > self.logical_words {
            self.buffer.clear(encoder, byte_offset(self.logical_words),
                Some(byte_offset(logical_words - self.logical_words)));
        }
        if logical_words > self.capacity_words {
            let limit_words = (device
                .limits()
                .max_buffer_size
                .min(u64::from(device.limits().max_storage_buffer_binding_size))
                / 4)
            .min(u64::from(u32::MAX)) as u32;
            let capacity = logical_words
                .checked_next_power_of_two()
                .filter(|&capacity| capacity <= limit_words)
                .unwrap_or(logical_words);
            let replacement = self.slot.buffer(
                capacity,
                wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::COPY_SRC
                    | wgpu::BufferUsages::COPY_DST,
                None,
            )?;
            if self.logical_words != 0 {
                self.buffer
                    .copy_to(encoder, 0, &replacement, 0, byte_offset(self.logical_words));
            }
            // Read old locations from the old allocation, not the relocated one.
            for movement in moves.iter().filter(|m| m.word_count != 0) {
                self.buffer.copy_to(
                    encoder,
                    byte_offset(movement.from_word),
                    &replacement,
                    byte_offset(movement.to_word),
                    byte_offset(movement.word_count),
                );
            }
            self.buffer = replacement;
            self.capacity_words = u32::try_from(self.buffer.byte_size / 4)?;
        } else if moves.iter().any(|m| m.word_count != 0) {
            // WGPU forbids same-buffer transfer copies even for disjoint spans.
            // Snapshot all move sources before any destination is changed.
            let total = moves.iter().try_fold(0u32, |sum, m| {
                sum.checked_add(m.word_count)
                    .ok_or_else(|| anyhow!("evidence relocation scratch overflow"))
            })?;
            let staging = self.workspace().initialized(
                "program_evidence.relocation",
                total,
                wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
                None,
            )?;
            let mut first = 0;
            for movement in moves.iter().filter(|m| m.word_count != 0) {
                self.buffer.copy_to(
                    encoder,
                    byte_offset(movement.from_word),
                    &staging,
                    byte_offset(first),
                    byte_offset(movement.word_count),
                );
                first += movement.word_count;
            }
            first = 0;
            for movement in moves.iter().filter(|m| m.word_count != 0) {
                staging.copy_to(
                    encoder,
                    byte_offset(first),
                    &self.buffer,
                    byte_offset(movement.to_word),
                    byte_offset(movement.word_count),
                );
                first += movement.word_count;
            }
        }
        self.logical_words = logical_words;
        Ok(())
    }

    /// Staged encoder copies are ordered AFTER relocations. queue.write_buffer
    /// on a destination would instead execute before this encoder's commands.
    pub fn upload(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        writes: &[ArenaWrite],
    ) -> Result<()> {
        passes_core::flush_deferred_compute(encoder);
        let mut words = Vec::new();
        let mut offsets = Vec::with_capacity(writes.len());
        for write in writes {
            let count = u32::try_from(write.words.len())?;
            ensure!(
                write.first_word <= self.logical_words
                    && count <= self.logical_words - write.first_word,
                "evidence upload exceeds logical arena"
            );
            offsets.push(u32::try_from(words.len())?);
            words.try_reserve(write.words.len())?;
            words.extend_from_slice(&write.words);
        }
        if words.is_empty() {
            return Ok(());
        }
        let staging = self.workspace().initialized(
            "program_evidence.upload",
            u32::try_from(words.len())?,
            wgpu::BufferUsages::COPY_SRC,
            Some(&words),
        )?;
        for (write, source) in writes
            .iter()
            .zip(offsets)
            .filter(|(w, _)| !w.words.is_empty())
        {
            staging.copy_to(
                encoder,
                byte_offset(source),
                &self.buffer,
                byte_offset(write.first_word),
                u64::try_from(write.words.len())? * 4,
            );
        }
        Ok(())
    }
}

fn storage_usage() -> wgpu::BufferUsages {
    wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST
}

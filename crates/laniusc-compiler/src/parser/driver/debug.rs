use anyhow::Result;

use super::{GpuParser, Ll1AcceptResult, ParserFailure, support::read_u32_words};
use crate::parser::tables::PrecomputedParseTables;

impl GpuParser {
    /// Builds a structured parser failure from the current resident parser buffers.
    pub(crate) fn current_resident_parser_failure_for_ll1_rejection(
        &self,
        token_capacity: u32,
        tables: &PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
        ll1: Ll1AcceptResult,
    ) -> ParserFailure {
        let semantic_token_kinds = self
            .read_current_resident_semantic_token_kinds(
                token_capacity,
                tables,
                tree_capacity_override,
            )
            .ok();
        ParserFailure::from_ll1_rejection(ll1, tables, semantic_token_kinds)
    }

    /// Reads the semantic parser token-kind stream currently resident in parser buffers.
    ///
    /// This is intended for diagnostics after a parser rejection. It copies the
    /// already-classified stream instead of rerunning token classification on the
    /// hot successful path.
    pub(crate) fn read_current_resident_semantic_token_kinds(
        &self,
        token_capacity: u32,
        tables: &PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
    ) -> Result<Vec<u32>> {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for_with_tree_capacity(
            &mut resident_guard,
            token_capacity,
            tables,
            tree_capacity_override,
        );

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.semantic_token_kinds.current.encoder"),
            });
        let count_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.semantic_token_kinds.current.count"),
            size: 4,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let kinds_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.semantic_token_kinds.current"),
            size: bufs.semantic_token_kinds.byte_size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&bufs.token_count, 0, &count_readback, 0, 4);
        encoder.copy_buffer_to_buffer(
            &bufs.semantic_token_kinds,
            0,
            &kinds_readback,
            0,
            bufs.semantic_token_kinds.byte_size as u64,
        );

        crate::gpu::passes_core::submit_with_progress(
            &self.queue,
            "parser.semantic-token-kinds.current",
            encoder.finish(),
        );

        let count_slice = count_readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &count_slice,
            "parser.semantic_token_kinds.current.count",
        )?;
        let count_mapped = count_slice.get_mapped_range();
        let count_words = read_u32_words(&count_mapped, 1)?;
        drop(count_mapped);
        count_readback.unmap();

        let out_count = count_words[0].saturating_add(2) as usize;
        let read_count = out_count.min(bufs.semantic_token_kinds.count);
        let byte_len = (read_count * 4) as u64;
        let kinds_slice = kinds_readback.slice(0..byte_len);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &kinds_slice,
            "parser.semantic_token_kinds.current",
        )?;
        let kinds_mapped = kinds_slice.get_mapped_range();
        let words = read_u32_words(&kinds_mapped, read_count)?;
        drop(kinds_mapped);
        kinds_readback.unmap();
        Ok(words)
    }

    /// Reads semantic token-kind words after resident token classification for debug checks.
    #[doc(hidden)]
    pub fn debug_semantic_token_kinds_for_resident_tokens(
        &self,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
    ) -> Result<Vec<u32>> {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for(&mut resident_guard, token_capacity, tables);

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.semantic_token_kinds.debug.encoder"),
            });
        self.record_tokens_to_kinds(
            &mut encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            bufs,
        )?;

        let count_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.semantic_token_kinds.count"),
            size: 4,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let kinds_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.semantic_token_kinds"),
            size: bufs.semantic_token_kinds.byte_size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&bufs.token_count, 0, &count_readback, 0, 4);
        encoder.copy_buffer_to_buffer(
            &bufs.semantic_token_kinds,
            0,
            &kinds_readback,
            0,
            bufs.semantic_token_kinds.byte_size as u64,
        );

        crate::gpu::passes_core::submit_with_progress(
            &self.queue,
            "parser.semantic-token-kinds.debug",
            encoder.finish(),
        );

        let count_slice = count_readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &count_slice,
            "parser.semantic_token_kinds.count",
        )?;
        let count_mapped = count_slice.get_mapped_range();
        let count_words = read_u32_words(&count_mapped, 1)?;
        drop(count_mapped);
        count_readback.unmap();

        let out_count = count_words[0].saturating_add(2) as usize;
        let read_count = out_count.min(bufs.semantic_token_kinds.count);
        let byte_len = (read_count * 4) as u64;
        let kinds_slice = kinds_readback.slice(0..byte_len);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &kinds_slice,
            "parser.semantic_token_kinds",
        )?;
        let kinds_mapped = kinds_slice.get_mapped_range();
        let words = read_u32_words(&kinds_mapped, read_count)?;
        drop(kinds_mapped);
        kinds_readback.unmap();
        Ok(words)
    }

    /// Reads parser token feature flags after resident token classification for debug checks.
    #[doc(hidden)]
    pub fn debug_token_feature_flags_for_resident_tokens(
        &self,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
    ) -> Result<u32> {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for(&mut resident_guard, token_capacity, tables);

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.token_feature_flags.debug.encoder"),
            });
        self.record_tokens_to_kinds(
            &mut encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            bufs,
        )?;

        let flags_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.token_feature_flags"),
            size: 4,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&bufs.token_feature_flags, 0, &flags_readback, 0, 4);

        crate::gpu::passes_core::submit_with_progress(
            &self.queue,
            "parser.token-feature-flags.debug",
            encoder.finish(),
        );

        let flags_slice = flags_readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &flags_slice,
            "parser.token_feature_flags",
        )?;
        let flags_mapped = flags_slice.get_mapped_range();
        let words = read_u32_words(&flags_mapped, 1)?;
        drop(flags_mapped);
        flags_readback.unmap();
        Ok(words[0])
    }
}

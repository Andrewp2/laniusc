use anyhow::Result;

use super::{
    GpuParser,
    Ll1AcceptResult,
    RecordedHirSemanticCount,
    RecordedResidentLl1HirCheck,
    support::{bool_from_env, read_u32_words, stamp_timer},
};
use crate::{
    gpu::timer::GpuTimer,
    parser::{buffers::ParserBuffers, tables::PrecomputedParseTables},
};

impl GpuParser {
    /// Records readback of semantic-HIR block counts for later capacity planning.
    pub fn record_hir_semantic_count_readback(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
        timer_ref: &mut Option<&mut GpuTimer>,
    ) -> Result<RecordedHirSemanticCount> {
        stamp_timer(timer_ref, encoder, "parser.hir_semantic_count_readback");
        let byte_size = bufs.hir_semantic_count.byte_size as u64;
        let block_count_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.hir_semantic_count"),
            size: byte_size,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(
            &bufs.hir_semantic_count,
            0,
            &block_count_readback,
            0,
            byte_size,
        );

        Ok(RecordedHirSemanticCount {
            block_count_readback,
            block_count_words: bufs.hir_semantic_count.count,
        })
    }

    /// Finishes a recorded semantic-HIR count readback.
    pub fn finish_recorded_hir_semantic_count(
        &self,
        recorded: &RecordedHirSemanticCount,
    ) -> Result<u32> {
        let slice = recorded.block_count_readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &slice,
            "parser.hir_semantic_count",
        )?;
        let mapped = slice.get_mapped_range();
        let words = read_u32_words(&mapped, recorded.block_count_words)?;
        drop(mapped);
        recorded.block_count_readback.unmap();
        Ok(words.into_iter().fold(0u32, u32::saturating_add))
    }

    /// Records parser/HIR work plus caller work, submits it, then checks parser status.
    pub fn with_recorded_checked_resident_ll1_hir_artifacts<S, R, E>(
        &self,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
        record_more: impl FnOnce(&ParserBuffers, &mut wgpu::CommandEncoder) -> std::result::Result<S, E>,
        consume_after_submit: impl FnOnce(&ParserBuffers, S) -> std::result::Result<R, E>,
    ) -> Result<std::result::Result<R, E>> {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_debug_buffers_for(&mut resident_guard, token_capacity, tables);

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.resident_ll1_hir.recorded.encoder"),
            });

        self.record_tokens_to_kinds(
            &mut encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            &bufs,
        )?;
        let mut timer_ref: Option<&mut GpuTimer> = None;
        self.record_ll1_resident_passes(&mut encoder, &bufs, true, true, None, &mut timer_ref)?;

        let status_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.recorded_ll1_hir.status"),
            size: 24,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&bufs.ll1_status, 0, &status_readback, 0, 24);

        let recorded_parser = RecordedResidentLl1HirCheck { status_readback };
        let recorded_more = match record_more(bufs, &mut encoder) {
            Ok(recorded) => recorded,
            Err(err) => return Ok(Err(err)),
        };

        let use_scopes = bool_from_env("LANIUS_VALIDATION_SCOPES", false);
        crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "parser.recorded-ll1-hir",
            encoder.finish(),
            use_scopes,
            "recorded LL(1) HIR batch",
        );

        self.finish_recorded_resident_ll1_hir_check(&recorded_parser)?;
        Ok(consume_after_submit(bufs, recorded_more))
    }

    /// Finishes deferred LL/HIR parser status and returns an error on rejection.
    pub fn finish_recorded_resident_ll1_hir_check(
        &self,
        recorded: &RecordedResidentLl1HirCheck,
    ) -> Result<()> {
        self.finish_recorded_resident_ll1_hir_check_result(recorded)
            .map(|_| ())
    }

    /// Finishes deferred LL/HIR parser status and returns the decoded status.
    pub fn finish_recorded_resident_ll1_hir_check_result(
        &self,
        recorded: &RecordedResidentLl1HirCheck,
    ) -> Result<Ll1AcceptResult> {
        let slice = recorded.status_readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &slice,
            "parser.recorded-ll1-hir.status",
        )?;
        let mapped = slice.get_mapped_range();
        let words = read_u32_words(&mapped, 6)?;
        drop(mapped);
        recorded.status_readback.unmap();

        let result = Ll1AcceptResult {
            accepted: words[0] != 0,
            error_pos: words[1],
            error_code: words[2],
            detail: words[3],
            steps: words[4],
            emit_len: words[5],
        };

        if !result.accepted {
            anyhow::bail!(
                "GPU LL(1) parser rejected token {}: error {} ({}) after {} steps",
                result.error_pos,
                result.error_code,
                result.detail,
                result.steps
            );
        }

        Ok(result)
    }
}

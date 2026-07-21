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
        const WORDS: u64 = 30;
        let count_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.hir_counts"),
            size: WORDS * 4,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&bufs.hir_semantic_count, 0, &count_readback, 0, 4);
        encoder.copy_buffer_to_buffer(&bufs.hir_canonical_count, 0, &count_readback, 4, 4);
        encoder.copy_buffer_to_buffer(&bufs.hir_canonical_status, 0, &count_readback, 8, 52);
        encoder.copy_buffer_to_buffer(&bufs.hir_call_arg_table_count, 0, &count_readback, 60, 4);
        encoder.copy_buffer_to_buffer(&bufs.hir_param_table_count, 0, &count_readback, 64, 4);
        encoder.copy_buffer_to_buffer(&bufs.hir_type_arg_table_count, 0, &count_readback, 68, 4);
        encoder.copy_buffer_to_buffer(
            &bufs.hir_generic_param_table_count,
            0,
            &count_readback,
            72,
            4,
        );
        encoder.copy_buffer_to_buffer(&bufs.hir_path_table_count, 0, &count_readback, 76, 4);
        encoder.copy_buffer_to_buffer(
            &bufs.hir_path_segment_table_count,
            0,
            &count_readback,
            80,
            4,
        );
        encoder.copy_buffer_to_buffer(&bufs.hir_field_table_count, 0, &count_readback, 84, 4);
        encoder.copy_buffer_to_buffer(&bufs.hir_variant_table_count, 0, &count_readback, 88, 4);
        encoder.copy_buffer_to_buffer(
            &bufs.hir_variant_payload_table_count,
            0,
            &count_readback,
            92,
            4,
        );
        encoder.copy_buffer_to_buffer(&bufs.hir_match_arm_table_count, 0, &count_readback, 96, 4);
        encoder.copy_buffer_to_buffer(
            &bufs.hir_match_payload_table_count,
            0,
            &count_readback,
            100,
            4,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_array_element_table_count,
            0,
            &count_readback,
            104,
            4,
        );
        encoder.copy_buffer_to_buffer(&bufs.hir_string_count, 0, &count_readback, 108, 4);
        encoder.copy_buffer_to_buffer(&bufs.hir_method_table_count, 0, &count_readback, 112, 4);
        encoder.copy_buffer_to_buffer(&bufs.hir_predicate_table_count, 0, &count_readback, 116, 4);

        Ok(RecordedHirSemanticCount { count_readback })
    }

    /// Finishes a recorded semantic-HIR count readback.
    pub fn finish_recorded_hir_semantic_count(
        &self,
        recorded: &RecordedHirSemanticCount,
    ) -> Result<u32> {
        Ok(self.finish_recorded_hir_counts(recorded)?.0)
    }

    /// Finishes semantic and canonical HIR count readback and enforces the
    /// token-anchor capacity boundary.
    pub fn finish_recorded_hir_counts(
        &self,
        recorded: &RecordedHirSemanticCount,
    ) -> Result<(u32, u32)> {
        let slice = recorded.count_readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &slice,
            "parser.hir_semantic_count",
        )?;
        let mapped = slice.get_mapped_range();
        let words = read_u32_words(&mapped, 30)?;
        drop(mapped);
        recorded.count_readback.unmap();
        if crate::gpu::env::env_bool_truthy("LANIUS_GPU_BUFFER_BREAKDOWN", false) {
            eprintln!(
                "gpu_hir_rows semantic={} canonical={} candidates={} unique_anchors={} call_args={} params={} type_args={} generic_params={} paths={} path_segments={} fields={} variants={} variant_payloads={} match_arms={} match_payloads={} array_elements={} strings={} methods={} predicates={} max_anchor={} anchor_sum={} capacity={} status={} detail_row={} reason_bits={} bad_ref_raw_plus_one={} bad_ref_input_plus_one={} bad_ref_anchor_plus_one={} bad_ref_winner_plus_one={}",
                words[0],
                words[1],
                words[6],
                words[8],
                words[15],
                words[16],
                words[17],
                words[18],
                words[19],
                words[20],
                words[21],
                words[22],
                words[23],
                words[24],
                words[25],
                words[26],
                words[27],
                words[28],
                words[29],
                words[7],
                words[9],
                words[4],
                words[2],
                words[5].saturating_sub(1),
                words[10],
                words[11],
                words[12],
                words[13],
                words[14],
            );
        }
        if words[2] == 1 {
            anyhow::bail!(
                "canonical HIR capacity exceeded: required {} rows, capacity {}, first overflow raw node {}; every durable HIR row must have a unique token or file anchor",
                words[3],
                words[4],
                words[5].saturating_sub(1),
            );
        }
        if words[2] == 2 {
            anyhow::bail!(
                "canonical HIR structural invariant failed at or before dense row {} (reason mask {:#010x})",
                words[5].saturating_sub(1),
                words[10],
            );
        }
        if words[2] == 3 {
            anyhow::bail!(
                "compact HIR family side-table capacity exceeded at or before raw row {}",
                words[5].saturating_sub(1),
            );
        }
        Ok((words[0], words[1]))
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

        let result = Ll1AcceptResult::from_status_words(&words);

        if !result.accepted {
            anyhow::bail!("{}", result.rejection_message());
        }

        Ok(result)
    }
}

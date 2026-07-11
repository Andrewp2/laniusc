// src/compiler/gpu_compiler/benchmarks.rs

use super::*;

fn benchmark_parser_execution_error(src: &str, err: impl std::fmt::Display) -> CompileError {
    if crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false) {
        eprintln!("[gpu_compile_host_timer] benchmark.parser.error: {err}");
    }
    parser_execution_failed_for_source(Path::new("<benchmark>"), src, err)
}

impl<'gpu> GpuCompiler<'gpu> {
    /// Record and run the lexer pipeline for a source string without recording
    /// parser, type-check, or backend work.
    pub async fn benchmark_lex_source(&self, src: &str) -> Result<(), CompileError> {
        let src = prepare_source_for_gpu(src)?;
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_tokens(
                &src,
                |_device, _queue, _bufs, _encoder, _timer| Ok::<_, CompileError>(()),
                |_device, _queue, _bufs, ()| Ok::<_, CompileError>(()),
            )
            .await
            .map_err(|err| {
                source_tokenization_failed_for_source(Path::new("<benchmark>"), &src, err)
            })?
    }
    /// Estimate the live frontend capacities produced by lexing and parsing a
    /// source string.
    pub async fn benchmark_live_capacity_estimate(
        &self,
        src: &str,
    ) -> Result<GpuLiveCapacityEstimateResult, CompileError> {
        let parse = self.benchmark_parse_source(src).await?;
        Ok(GpuLiveCapacityEstimateResult {
            token_count: parse.token_count,
            parser_tree_capacity: parse.parser_tree_capacity,
            parser_feature_flags: parse.parser_feature_flags,
            parser_emit_len: parse.ll1.emit_len,
            semantic_hir_count: parse.semantic_hir_count,
        })
    }
    /// Record and run lexing plus parser LL/HIR construction for a source
    /// string and return the parser status and emitted capacity counts.
    pub async fn benchmark_parse_source(
        &self,
        src: &str,
    ) -> Result<GpuParseBenchmarkResult, CompileError> {
        let src = prepare_source_for_gpu(src)?;
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_parser_inputs_after_count_releasing_lexer(
                &src,
                |_, _, bufs, token_count, encoder, mut timer| {
                    let token_capacity = token_count.max(1);
                    let parser_capacity = self
                        .parser
                        .measure_resident_partial_parse_capacity(
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            &self.parse_tables,
                        )
                        .map_err(|err| benchmark_parser_execution_error(&src, err))?;
                    let parser_tree_capacity = parser_capacity.tree_capacity;
                    let (parser_check, parse_result) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity_and_features(
                            encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.source_len,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            parser_capacity.parser_feature_flags,
                            &mut timer,
                            |parse_bufs, encoder, timer| {
                                self.parser
                                    .record_hir_semantic_count_readback(encoder, parse_bufs, timer)
                                    .map_err(|err| benchmark_parser_execution_error(&src, err))
                            },
                        )
                        .map_err(|err| benchmark_parser_execution_error(&src, err))?;
                    let semantic_count = parse_result?;
                    Ok((
                        parser_check,
                        semantic_count,
                        token_count,
                        parser_tree_capacity,
                        parser_capacity.parser_feature_flags,
                    ))
                },
                |device,
                 _,
                 _bufs: &ResidentLexerParserInputs,
                 (
                    parser_check,
                    semantic_count,
                    token_count,
                    parser_tree_capacity,
                    parser_feature_flags,
                )| {
                    let ll1 = parser_check
                        .read_status_result(device)
                        .map_err(|err| benchmark_parser_execution_error(&src, err))?;
                    if !ll1.accepted {
                        if crate::gpu::env::env_bool_truthy(
                            "LANIUS_GPU_COMPILE_HOST_TIMING",
                            false,
                        ) {
                            eprintln!(
                                "[gpu_compile_host_timer] benchmark.parser.status: accepted={} error_pos={} error_code={} detail={} steps={} emit_len={}",
                                ll1.accepted,
                                ll1.error_pos,
                                ll1.error_code,
                                ll1.detail,
                                ll1.steps,
                                ll1.emit_len,
                            );
                        }
                        return Err(benchmark_parser_execution_error(
                            &src,
                            ll1.rejection_message(),
                        ));
                    }
                    let semantic_hir_count = self
                        .parser
                        .finish_recorded_hir_semantic_count(&semantic_count)
                        .map_err(|err| benchmark_parser_execution_error(&src, err))?;
                    Ok(GpuParseBenchmarkResult {
                        ll1,
                        token_count,
                        parser_tree_capacity,
                        parser_feature_flags,
                        semantic_hir_count,
                    })
                },
            )
            .await
            .map_err(|err| {
                source_tokenization_failed_for_source(Path::new("<benchmark>"), &src, err)
            })?
    }
}

// src/compiler/gpu_compiler/benchmarks.rs

use super::*;

impl<'gpu> GpuCompiler<'gpu> {
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
            .map_err(|err| CompileError::GpuFrontend(format!("lex benchmark: {err}")))?
    }
    pub async fn benchmark_live_capacity_estimate(
        &self,
        src: &str,
    ) -> Result<GpuLiveCapacityEstimateResult, CompileError> {
        let parse = self.benchmark_parse_source(src).await?;
        Ok(GpuLiveCapacityEstimateResult {
            token_count: parse.token_count,
            parser_tree_capacity: parse.parser_tree_capacity,
            parser_emit_len: parse.ll1.emit_len,
            semantic_hir_count: parse.semantic_hir_count,
        })
    }
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
                    let parser_tree_capacity = self
                        .parser
                        .read_resident_projected_tree_capacity(
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            &self.parse_tables,
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let (parser_check, parse_result) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.source_len,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut timer,
                            |parse_bufs, encoder, timer| {
                                self.parser
                                    .record_hir_semantic_count_readback(encoder, parse_bufs, timer)
                                    .map_err(|err| CompileError::GpuSyntax(err.to_string()))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let semantic_count = parse_result?;
                    Ok((
                        parser_check,
                        semantic_count,
                        token_count,
                        parser_tree_capacity,
                    ))
                },
                |_,
                 _,
                 _bufs: &ResidentLexerParserInputs,
                 (parser_check, semantic_count, token_count, parser_tree_capacity)| {
                    let ll1 = self
                        .parser
                        .finish_recorded_resident_ll1_hir_check_result(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let semantic_hir_count = self
                        .parser
                        .finish_recorded_hir_semantic_count(&semantic_count)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    Ok(GpuParseBenchmarkResult {
                        ll1,
                        token_count,
                        parser_tree_capacity,
                        semantic_hir_count,
                    })
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("parse benchmark: {err}")))?
    }
}

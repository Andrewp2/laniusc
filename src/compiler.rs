use std::{fs, path::Path, sync::OnceLock};

use futures_intrusive::sync::Mutex;

use crate::{
    codegen::{wasm, x86},
    gpu::{
        device::{self, GpuDevice},
        timer::GpuTimer,
    },
    lexer::driver::GpuLexer,
    parser::{
        buffers::ParserBuffers,
        driver::{GpuParser, Ll1AcceptResult},
        tables::PrecomputedParseTables,
    },
    type_checker as gpu_type_checker,
};

#[derive(Debug)]
pub enum CompileError {
    GpuFrontend(String),
    GpuSyntax(String),
    GpuTypeCheck(String),
    GpuCodegen(String),
}

impl std::fmt::Display for CompileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CompileError::GpuFrontend(err) => write!(f, "GPU frontend error: {err}"),
            CompileError::GpuSyntax(err) => write!(f, "GPU syntax error: {err}"),
            CompileError::GpuTypeCheck(err) => write!(f, "GPU type check error: {err}"),
            CompileError::GpuCodegen(err) => write!(f, "GPU codegen error: {err}"),
        }
    }
}

impl std::error::Error for CompileError {}

pub struct GpuParseBenchmarkResult {
    pub ll1: Ll1AcceptResult,
    pub token_count: u32,
    pub parser_tree_capacity: u32,
    pub semantic_hir_count: u32,
}

pub struct GpuLiveCapacityEstimateResult {
    pub token_count: u32,
    pub parser_tree_capacity: u32,
    pub parser_emit_len: u32,
    pub semantic_hir_count: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct GpuCompilerBackends {
    pub wasm: bool,
    pub x86: bool,
}

impl GpuCompilerBackends {
    pub const fn all() -> Self {
        Self {
            wasm: true,
            x86: true,
        }
    }

    pub const fn frontend_only() -> Self {
        Self {
            wasm: false,
            x86: false,
        }
    }

    pub const fn wasm_only() -> Self {
        Self {
            wasm: true,
            x86: false,
        }
    }

    pub const fn x86_only() -> Self {
        Self {
            wasm: false,
            x86: true,
        }
    }
}

pub struct GpuCompiler<'gpu> {
    gpu: &'gpu GpuDevice,
    lexer: GpuLexer,
    parser: GpuParser,
    parse_tables: PrecomputedParseTables,
    type_checker: gpu_type_checker::GpuTypeChecker,
    resident_pipeline_lock: Mutex<()>,
    wasm_generator: Result<Box<wasm::GpuWasmCodeGenerator>, String>,
    x86_generator: Result<Box<x86::GpuX86CodeGenerator>, String>,
}

impl GpuCompiler<'static> {
    pub async fn new() -> Result<Self, CompileError> {
        Self::new_with_device(device::global()).await
    }
}

impl<'gpu> GpuCompiler<'gpu> {
    pub async fn new_with_device(gpu: &'gpu GpuDevice) -> Result<Self, CompileError> {
        Self::new_with_device_and_backends(gpu, GpuCompilerBackends::all()).await
    }

    pub async fn new_with_device_and_backends(
        gpu: &'gpu GpuDevice,
        backends: GpuCompilerBackends,
    ) -> Result<Self, CompileError> {
        let mut host_timer = CompilerHostTimer::new("compiler.init");
        host_timer.pipeline_cache_size(gpu, "start");
        let lexer = GpuLexer::new_with_device(gpu)
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("initialize GPU lexer: {err}")))?;
        host_timer.stamp("lexer");
        host_timer.pipeline_cache_size(gpu, "after_lexer");
        let parser = GpuParser::new_with_device(gpu)
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("initialize GPU parser: {err}")))?;
        host_timer.stamp("parser");
        host_timer.pipeline_cache_size(gpu, "after_parser");
        let parse_tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .map_err(|err| {
                    CompileError::GpuFrontend(format!("load GPU parse tables: {err}"))
                })?;
        host_timer.stamp("parse_tables");
        let type_checker =
            gpu_type_checker::GpuTypeChecker::new_with_device(gpu).map_err(|err| {
                CompileError::GpuFrontend(format!("initialize GPU type checker: {err}"))
            })?;
        host_timer.stamp("type_checker");
        host_timer.pipeline_cache_size(gpu, "after_type_checker");
        let wasm_generator = if backends.wasm {
            let generator = wasm::GpuWasmCodeGenerator::new_with_device(gpu)
                .map(Box::new)
                .map_err(|err| err.to_string());
            if let Err(err) = &generator {
                log::warn!(
                    "preinitializing GPU WASM code generator failed; WASM compilation will report this error when used: {err}"
                );
            }
            host_timer.stamp("wasm_generator");
            host_timer.pipeline_cache_size(gpu, "after_wasm_generator");
            generator
        } else {
            host_timer.stamp("wasm_generator.skipped");
            Err("GPU WASM code generator was not initialized for this compiler".into())
        };
        let x86_generator = if backends.x86 {
            let generator = x86::GpuX86CodeGenerator::new_with_device(gpu)
                .map(Box::new)
                .map_err(|err| err.to_string());
            if let Err(err) = &generator {
                log::warn!(
                    "preinitializing GPU x86 code generator failed; x86 compilation will report this error when used: {err}"
                );
            }
            host_timer.stamp("x86_generator");
            host_timer.pipeline_cache_size(gpu, "after_x86_generator");
            generator
        } else {
            host_timer.stamp("x86_generator.skipped");
            Err("GPU x86 code generator was not initialized for this compiler".into())
        };
        Ok(Self {
            gpu,
            lexer,
            parser,
            parse_tables,
            type_checker,
            resident_pipeline_lock: Mutex::new((), false),
            wasm_generator,
            x86_generator,
        })
    }

    pub fn gpu(&self) -> &'gpu GpuDevice {
        self.gpu
    }

    pub async fn type_check_source(&self, src: &str) -> Result<(), CompileError> {
        let src = prepare_source_for_gpu_type_check(src)?;
        self.type_check_expanded_source(&src).await
    }

    pub async fn benchmark_lex_source(&self, src: &str) -> Result<(), CompileError> {
        let src = prepare_source_for_gpu_type_check(src)?;
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
        let src = prepare_source_for_gpu_type_check(src)?;
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_tokens_after_count(
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
                            bufs.n,
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
                |_, _, _bufs, (parser_check, semantic_count, token_count, parser_tree_capacity)| {
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

    pub async fn type_check_source_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<(), CompileError> {
        let src = prepare_source_for_gpu_type_check_from_path(path)?;
        self.type_check_expanded_source(&src).await
    }

    pub async fn type_check_source_pack<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<(), CompileError> {
        self.type_check_explicit_source_pack(sources).await
    }

    async fn type_check_expanded_source(&self, src: &str) -> Result<(), CompileError> {
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_tokens_after_count(
                src,
                |device, queue, bufs, token_count, encoder, mut timer| {
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
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut timer,
                            |parse_bufs, encoder, timer| {
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                let recorded = self
                                    .type_checker
                                    .record_resident_token_buffer_with_hir_items_on_gpu(
                                        device,
                                        queue,
                                        encoder,
                                        bufs.n,
                                        bufs.source_file_start.count as u32,
                                        token_capacity,
                                        &bufs.tokens_out,
                                        &bufs.token_count,
                                        &bufs.token_file_id,
                                        &bufs.in_bytes,
                                        parse_bufs.tree_capacity,
                                        &parse_bufs.hir_kind,
                                        &parse_bufs.hir_token_pos,
                                        &parse_bufs.hir_token_end,
                                        &parse_bufs.hir_token_file_id,
                                        &parse_bufs.ll1_status,
                                        gpu_type_checker::GpuTypeCheckHirItemBuffers {
                                            node_kind: &parse_bufs.node_kind,
                                            parent: &parse_bufs.parent,
                                            first_child: &parse_bufs.first_child,
                                            next_sibling: &parse_bufs.next_sibling,
                                            subtree_end: &parse_bufs.subtree_end,
                                            kind: &parse_bufs.hir_item_kind,
                                            name_token: &parse_bufs.hir_item_name_token,
                                            type_form: &parse_bufs.hir_type_form,
                                            type_value_node: &parse_bufs.hir_type_value_node,
                                            type_len_token: &parse_bufs.hir_type_len_token,
                                            type_len_value: &parse_bufs.hir_type_len_value,
                                            type_path_leaf_node: &parse_bufs
                                                .hir_type_path_leaf_node,
                                            type_arg_start: &parse_bufs.hir_type_arg_start,
                                            type_arg_count: &parse_bufs.hir_type_arg_count,
                                            type_arg_next: &parse_bufs.hir_type_arg_next,
                                            type_alias_target_node: &parse_bufs
                                                .hir_type_alias_target_node,
                                            fn_return_type_node: &parse_bufs
                                                .hir_fn_return_type_node,
                                            param_record: &parse_bufs.hir_param_record,
                                            expr_record: &parse_bufs.hir_expr_record,
                                            expr_int_value: &parse_bufs.hir_expr_int_value,
                                            member_receiver_node: &parse_bufs
                                                .hir_member_receiver_node,
                                            member_receiver_token: &parse_bufs
                                                .hir_member_receiver_token,
                                            member_name_token: &parse_bufs.hir_member_name_token,
                                            stmt_record: &parse_bufs.hir_stmt_record,
                                            array_lit_first_element: &parse_bufs
                                                .hir_array_lit_first_element,
                                            array_lit_element_count: &parse_bufs
                                                .hir_array_lit_element_count,
                                            array_element_next: &parse_bufs.hir_array_element_next,
                                            namespace: &parse_bufs.hir_item_namespace,
                                            visibility: &parse_bufs.hir_item_visibility,
                                            path_start: &parse_bufs.hir_item_path_start,
                                            path_end: &parse_bufs.hir_item_path_end,
                                            file_id: &parse_bufs.hir_item_file_id,
                                            import_target_kind: &parse_bufs
                                                .hir_item_import_target_kind,
                                            call_callee_node: &parse_bufs.hir_call_callee_node,
                                            call_arg_start: &parse_bufs.hir_call_arg_start,
                                            call_arg_end: &parse_bufs.hir_call_arg_end,
                                            call_arg_count: &parse_bufs.hir_call_arg_count,
                                            call_arg_parent_call: &parse_bufs
                                                .hir_call_arg_parent_call,
                                            call_arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                            variant_parent_enum: &parse_bufs
                                                .hir_variant_parent_enum,
                                            variant_payload_start: &parse_bufs
                                                .hir_variant_payload_start,
                                            variant_payload_count: &parse_bufs
                                                .hir_variant_payload_count,
                                            match_scrutinee_node: &parse_bufs
                                                .hir_match_scrutinee_node,
                                            match_arm_start: &parse_bufs.hir_match_arm_start,
                                            match_arm_count: &parse_bufs.hir_match_arm_count,
                                            match_arm_next: &parse_bufs.hir_match_arm_next,
                                            match_arm_pattern_node: &parse_bufs
                                                .hir_match_arm_pattern_node,
                                            match_arm_payload_start: &parse_bufs
                                                .hir_match_arm_payload_start,
                                            match_arm_payload_count: &parse_bufs
                                                .hir_match_arm_payload_count,
                                            match_arm_result_node: &parse_bufs
                                                .hir_match_arm_result_node,
                                            match_payload_owner_arm: &parse_bufs
                                                .hir_match_payload_owner_arm,
                                            match_payload_match_node: &parse_bufs
                                                .hir_match_payload_match_node,
                                            match_payload_ordinal: &parse_bufs
                                                .hir_match_payload_ordinal,
                                            struct_field_parent_struct: &parse_bufs
                                                .hir_struct_field_parent_struct,
                                            struct_field_ordinal: &parse_bufs
                                                .hir_struct_field_ordinal,
                                            struct_field_type_node: &parse_bufs
                                                .hir_struct_field_type_node,
                                            struct_decl_field_start: &parse_bufs
                                                .hir_struct_decl_field_start,
                                            struct_decl_field_count: &parse_bufs
                                                .hir_struct_decl_field_count,
                                            struct_lit_head_node: &parse_bufs
                                                .hir_struct_lit_head_node,
                                            struct_lit_field_start: &parse_bufs
                                                .hir_struct_lit_field_start,
                                            struct_lit_field_count: &parse_bufs
                                                .hir_struct_lit_field_count,
                                            struct_lit_field_parent_lit: &parse_bufs
                                                .hir_struct_lit_field_parent_lit,
                                            struct_lit_field_value_node: &parse_bufs
                                                .hir_struct_lit_field_value_node,
                                            semantic_dense_node: &parse_bufs
                                                .hir_semantic_dense_node,
                                            semantic_count: &parse_bufs.hir_semantic_count,
                                        },
                                        timer.as_deref_mut(),
                                    )
                                    .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "typecheck.done");
                                }
                                Ok::<_, CompileError>(recorded)
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let type_check = type_check?;
                    Ok((parser_check, type_check))
                },
                |device, _queue, _bufs, (parser_check, type_check)| {
                    self.parser
                        .finish_recorded_resident_ll1_hir_check(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source: {err}")))?
    }

    async fn type_check_explicit_source_pack<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<(), CompileError> {
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_source_pack_tokens_after_count(
                sources,
                |device, queue, bufs, token_count, encoder, mut timer| {
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
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut timer,
                            |parse_bufs, encoder, timer| {
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                let recorded = self
                                    .type_checker
                                    .record_resident_token_buffer_with_hir_items_on_gpu(
                                        device,
                                        queue,
                                        encoder,
                                        bufs.n,
                                        bufs.source_file_start.count as u32,
                                        token_capacity,
                                        &bufs.tokens_out,
                                        &bufs.token_count,
                                        &bufs.token_file_id,
                                        &bufs.in_bytes,
                                        parse_bufs.tree_capacity,
                                        &parse_bufs.hir_kind,
                                        &parse_bufs.hir_token_pos,
                                        &parse_bufs.hir_token_end,
                                        &parse_bufs.hir_token_file_id,
                                        &parse_bufs.ll1_status,
                                        gpu_type_checker::GpuTypeCheckHirItemBuffers {
                                            node_kind: &parse_bufs.node_kind,
                                            parent: &parse_bufs.parent,
                                            first_child: &parse_bufs.first_child,
                                            next_sibling: &parse_bufs.next_sibling,
                                            subtree_end: &parse_bufs.subtree_end,
                                            kind: &parse_bufs.hir_item_kind,
                                            name_token: &parse_bufs.hir_item_name_token,
                                            type_form: &parse_bufs.hir_type_form,
                                            type_value_node: &parse_bufs.hir_type_value_node,
                                            type_len_token: &parse_bufs.hir_type_len_token,
                                            type_len_value: &parse_bufs.hir_type_len_value,
                                            type_path_leaf_node: &parse_bufs
                                                .hir_type_path_leaf_node,
                                            type_arg_start: &parse_bufs.hir_type_arg_start,
                                            type_arg_count: &parse_bufs.hir_type_arg_count,
                                            type_arg_next: &parse_bufs.hir_type_arg_next,
                                            type_alias_target_node: &parse_bufs
                                                .hir_type_alias_target_node,
                                            fn_return_type_node: &parse_bufs
                                                .hir_fn_return_type_node,
                                            param_record: &parse_bufs.hir_param_record,
                                            expr_record: &parse_bufs.hir_expr_record,
                                            expr_int_value: &parse_bufs.hir_expr_int_value,
                                            member_receiver_node: &parse_bufs
                                                .hir_member_receiver_node,
                                            member_receiver_token: &parse_bufs
                                                .hir_member_receiver_token,
                                            member_name_token: &parse_bufs.hir_member_name_token,
                                            stmt_record: &parse_bufs.hir_stmt_record,
                                            array_lit_first_element: &parse_bufs
                                                .hir_array_lit_first_element,
                                            array_lit_element_count: &parse_bufs
                                                .hir_array_lit_element_count,
                                            array_element_next: &parse_bufs.hir_array_element_next,
                                            namespace: &parse_bufs.hir_item_namespace,
                                            visibility: &parse_bufs.hir_item_visibility,
                                            path_start: &parse_bufs.hir_item_path_start,
                                            path_end: &parse_bufs.hir_item_path_end,
                                            file_id: &parse_bufs.hir_item_file_id,
                                            import_target_kind: &parse_bufs
                                                .hir_item_import_target_kind,
                                            call_callee_node: &parse_bufs.hir_call_callee_node,
                                            call_arg_start: &parse_bufs.hir_call_arg_start,
                                            call_arg_end: &parse_bufs.hir_call_arg_end,
                                            call_arg_count: &parse_bufs.hir_call_arg_count,
                                            call_arg_parent_call: &parse_bufs
                                                .hir_call_arg_parent_call,
                                            call_arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                            variant_parent_enum: &parse_bufs
                                                .hir_variant_parent_enum,
                                            variant_payload_start: &parse_bufs
                                                .hir_variant_payload_start,
                                            variant_payload_count: &parse_bufs
                                                .hir_variant_payload_count,
                                            match_scrutinee_node: &parse_bufs
                                                .hir_match_scrutinee_node,
                                            match_arm_start: &parse_bufs.hir_match_arm_start,
                                            match_arm_count: &parse_bufs.hir_match_arm_count,
                                            match_arm_next: &parse_bufs.hir_match_arm_next,
                                            match_arm_pattern_node: &parse_bufs
                                                .hir_match_arm_pattern_node,
                                            match_arm_payload_start: &parse_bufs
                                                .hir_match_arm_payload_start,
                                            match_arm_payload_count: &parse_bufs
                                                .hir_match_arm_payload_count,
                                            match_arm_result_node: &parse_bufs
                                                .hir_match_arm_result_node,
                                            match_payload_owner_arm: &parse_bufs
                                                .hir_match_payload_owner_arm,
                                            match_payload_match_node: &parse_bufs
                                                .hir_match_payload_match_node,
                                            match_payload_ordinal: &parse_bufs
                                                .hir_match_payload_ordinal,
                                            struct_field_parent_struct: &parse_bufs
                                                .hir_struct_field_parent_struct,
                                            struct_field_ordinal: &parse_bufs
                                                .hir_struct_field_ordinal,
                                            struct_field_type_node: &parse_bufs
                                                .hir_struct_field_type_node,
                                            struct_decl_field_start: &parse_bufs
                                                .hir_struct_decl_field_start,
                                            struct_decl_field_count: &parse_bufs
                                                .hir_struct_decl_field_count,
                                            struct_lit_head_node: &parse_bufs
                                                .hir_struct_lit_head_node,
                                            struct_lit_field_start: &parse_bufs
                                                .hir_struct_lit_field_start,
                                            struct_lit_field_count: &parse_bufs
                                                .hir_struct_lit_field_count,
                                            struct_lit_field_parent_lit: &parse_bufs
                                                .hir_struct_lit_field_parent_lit,
                                            struct_lit_field_value_node: &parse_bufs
                                                .hir_struct_lit_field_value_node,
                                            semantic_dense_node: &parse_bufs
                                                .hir_semantic_dense_node,
                                            semantic_count: &parse_bufs.hir_semantic_count,
                                        },
                                        timer.as_deref_mut(),
                                    )
                                    .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "typecheck.done");
                                }
                                Ok::<_, CompileError>(recorded)
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let type_check = type_check?;
                    Ok((parser_check, type_check))
                },
                |device, _queue, _bufs, (parser_check, type_check)| {
                    self.parser
                        .finish_recorded_resident_ll1_hir_check(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source pack: {err}")))?
    }

    pub async fn compile_source_to_wasm(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu_codegen(src)?;
        self.compile_expanded_source_to_wasm(&src).await
    }

    pub async fn compile_source_to_wasm_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu_codegen_from_path(path)?;
        self.compile_expanded_source_to_wasm(&src).await
    }

    pub async fn compile_source_pack_to_wasm<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<Vec<u8>, CompileError> {
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        trace_wasm_compile("source_pack.compile.start");
        self.lexer
            .with_recorded_resident_source_pack_tokens_after_count(
                sources,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    trace_wasm_compile("source_pack.lex.recorded");
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
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut timer,
                            |parse_bufs, encoder, timer| {
                                trace_wasm_compile("source_pack.parser.recorded");
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                let hir_status = &parse_bufs.ll1_status;
                                let recorded = self
                                    .type_checker
                                    .record_resident_token_buffer_with_hir_items_on_gpu(
                                        device,
                                        queue,
                                        encoder,
                                        bufs.n,
                                        bufs.source_file_start.count as u32,
                                        token_capacity,
                                        &bufs.tokens_out,
                                        &bufs.token_count,
                                        &bufs.token_file_id,
                                        &bufs.in_bytes,
                                        parse_bufs.tree_capacity,
                                        &parse_bufs.hir_kind,
                                        &parse_bufs.hir_token_pos,
                                        &parse_bufs.hir_token_end,
                                        &parse_bufs.hir_token_file_id,
                                        hir_status,
                                        gpu_type_checker::GpuTypeCheckHirItemBuffers {
                                            node_kind: &parse_bufs.node_kind,
                                            parent: &parse_bufs.parent,
                                            first_child: &parse_bufs.first_child,
                                            next_sibling: &parse_bufs.next_sibling,
                                            subtree_end: &parse_bufs.subtree_end,
                                            kind: &parse_bufs.hir_item_kind,
                                            name_token: &parse_bufs.hir_item_name_token,
                                            type_form: &parse_bufs.hir_type_form,
                                            type_value_node: &parse_bufs.hir_type_value_node,
                                            type_len_token: &parse_bufs.hir_type_len_token,
                                            type_len_value: &parse_bufs.hir_type_len_value,
                                            type_path_leaf_node: &parse_bufs
                                                .hir_type_path_leaf_node,
                                            type_arg_start: &parse_bufs.hir_type_arg_start,
                                            type_arg_count: &parse_bufs.hir_type_arg_count,
                                            type_arg_next: &parse_bufs.hir_type_arg_next,
                                            type_alias_target_node: &parse_bufs
                                                .hir_type_alias_target_node,
                                            fn_return_type_node: &parse_bufs
                                                .hir_fn_return_type_node,
                                            param_record: &parse_bufs.hir_param_record,
                                            expr_record: &parse_bufs.hir_expr_record,
                                            expr_int_value: &parse_bufs.hir_expr_int_value,
                                            member_receiver_node: &parse_bufs
                                                .hir_member_receiver_node,
                                            member_receiver_token: &parse_bufs
                                                .hir_member_receiver_token,
                                            member_name_token: &parse_bufs.hir_member_name_token,
                                            stmt_record: &parse_bufs.hir_stmt_record,
                                            array_lit_first_element: &parse_bufs
                                                .hir_array_lit_first_element,
                                            array_lit_element_count: &parse_bufs
                                                .hir_array_lit_element_count,
                                            array_element_next: &parse_bufs.hir_array_element_next,
                                            namespace: &parse_bufs.hir_item_namespace,
                                            visibility: &parse_bufs.hir_item_visibility,
                                            path_start: &parse_bufs.hir_item_path_start,
                                            path_end: &parse_bufs.hir_item_path_end,
                                            file_id: &parse_bufs.hir_item_file_id,
                                            import_target_kind: &parse_bufs
                                                .hir_item_import_target_kind,
                                            call_callee_node: &parse_bufs.hir_call_callee_node,
                                            call_arg_start: &parse_bufs.hir_call_arg_start,
                                            call_arg_end: &parse_bufs.hir_call_arg_end,
                                            call_arg_count: &parse_bufs.hir_call_arg_count,
                                            call_arg_parent_call: &parse_bufs
                                                .hir_call_arg_parent_call,
                                            call_arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                            variant_parent_enum: &parse_bufs
                                                .hir_variant_parent_enum,
                                            variant_payload_start: &parse_bufs
                                                .hir_variant_payload_start,
                                            variant_payload_count: &parse_bufs
                                                .hir_variant_payload_count,
                                            match_scrutinee_node: &parse_bufs
                                                .hir_match_scrutinee_node,
                                            match_arm_start: &parse_bufs.hir_match_arm_start,
                                            match_arm_count: &parse_bufs.hir_match_arm_count,
                                            match_arm_next: &parse_bufs.hir_match_arm_next,
                                            match_arm_pattern_node: &parse_bufs
                                                .hir_match_arm_pattern_node,
                                            match_arm_payload_start: &parse_bufs
                                                .hir_match_arm_payload_start,
                                            match_arm_payload_count: &parse_bufs
                                                .hir_match_arm_payload_count,
                                            match_arm_result_node: &parse_bufs
                                                .hir_match_arm_result_node,
                                            match_payload_owner_arm: &parse_bufs
                                                .hir_match_payload_owner_arm,
                                            match_payload_match_node: &parse_bufs
                                                .hir_match_payload_match_node,
                                            match_payload_ordinal: &parse_bufs
                                                .hir_match_payload_ordinal,
                                            struct_field_parent_struct: &parse_bufs
                                                .hir_struct_field_parent_struct,
                                            struct_field_ordinal: &parse_bufs
                                                .hir_struct_field_ordinal,
                                            struct_field_type_node: &parse_bufs
                                                .hir_struct_field_type_node,
                                            struct_decl_field_start: &parse_bufs
                                                .hir_struct_decl_field_start,
                                            struct_decl_field_count: &parse_bufs
                                                .hir_struct_decl_field_count,
                                            struct_lit_head_node: &parse_bufs
                                                .hir_struct_lit_head_node,
                                            struct_lit_field_start: &parse_bufs
                                                .hir_struct_lit_field_start,
                                            struct_lit_field_count: &parse_bufs
                                                .hir_struct_lit_field_count,
                                            struct_lit_field_parent_lit: &parse_bufs
                                                .hir_struct_lit_field_parent_lit,
                                            struct_lit_field_value_node: &parse_bufs
                                                .hir_struct_lit_field_value_node,
                                            semantic_dense_node: &parse_bufs
                                                .hir_semantic_dense_node,
                                            semantic_count: &parse_bufs.hir_semantic_count,
                                        },
                                        timer.as_deref_mut(),
                                    )
                                    .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                                trace_wasm_compile("source_pack.typecheck.recorded");
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "typecheck.done");
                                }
                                let wasm_check = self
                                    .type_checker
                                    .with_codegen_buffers(|codegen| {
                                        self.wasm_generator()?
                                            .record_wasm_from_gpu_token_buffer(
                                                device,
                                                queue,
                                                encoder,
                                                bufs.n,
                                                token_capacity,
                                                &bufs.tokens_out,
                                                &bufs.token_count,
                                                &bufs.in_bytes,
                                                parse_bufs.tree_capacity,
                                                &parse_bufs.node_kind,
                                                &parse_bufs.parent,
                                                &parse_bufs.first_child,
                                                &parse_bufs.next_sibling,
                                                &parse_bufs.hir_kind,
                                                &parse_bufs.hir_token_pos,
                                                &parse_bufs.hir_token_end,
                                                hir_status,
                                                codegen.visible_decl,
                                                codegen.visible_type,
                                                codegen.name_id_by_token,
                                                wasm::GpuWasmStructMetadataBuffers {
                                                    field_parent_struct: &parse_bufs
                                                        .hir_struct_field_parent_struct,
                                                    field_ordinal: &parse_bufs
                                                        .hir_struct_field_ordinal,
                                                    lit_field_parent_lit: &parse_bufs
                                                        .hir_struct_lit_field_parent_lit,
                                                },
                                                wasm::GpuWasmEnumMatchMetadataBuffers {
                                                    variant_ordinal: &parse_bufs
                                                        .hir_variant_ordinal,
                                                    match_scrutinee_node: &parse_bufs
                                                        .hir_match_scrutinee_node,
                                                    match_arm_start: &parse_bufs
                                                        .hir_match_arm_start,
                                                    match_arm_count: &parse_bufs
                                                        .hir_match_arm_count,
                                                    match_arm_pattern_node: &parse_bufs
                                                        .hir_match_arm_pattern_node,
                                                    match_arm_payload_start: &parse_bufs
                                                        .hir_match_arm_payload_start,
                                                    match_arm_payload_count: &parse_bufs
                                                        .hir_match_arm_payload_count,
                                                    match_arm_result_node: &parse_bufs
                                                        .hir_match_arm_result_node,
                                                },
                                                wasm::GpuWasmCallMetadataBuffers {
                                                    callee_node: &parse_bufs.hir_call_callee_node,
                                                    arg_start: &parse_bufs.hir_call_arg_start,
                                                    arg_parent_call: &parse_bufs
                                                        .hir_call_arg_parent_call,
                                                    arg_end: &parse_bufs.hir_call_arg_end,
                                                    arg_count: &parse_bufs.hir_call_arg_count,
                                                    arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                                },
                                                wasm::GpuWasmExprMetadataBuffers {
                                                    record: &parse_bufs.hir_expr_record,
                                                    int_value: &parse_bufs.hir_expr_int_value,
                                                    stmt_record: &parse_bufs.hir_stmt_record,
                                                },
                                                &parse_bufs.hir_param_record,
                                                codegen.type_expr_ref_tag,
                                                codegen.type_expr_ref_payload,
                                                codegen.module_value_path_call_head,
                                                codegen.module_value_path_call_open,
                                                codegen.module_value_path_const_head,
                                                codegen.module_value_path_const_end,
                                                codegen.call_fn_index,
                                                codegen.call_intrinsic_tag,
                                                codegen.fn_entrypoint_tag,
                                                codegen.call_return_type,
                                                codegen.call_return_type_token,
                                                codegen.call_param_count,
                                                codegen.call_param_type,
                                                codegen.method_decl_receiver_ref_tag,
                                                codegen.method_decl_receiver_ref_payload,
                                                codegen.method_decl_param_offset,
                                                codegen.method_decl_receiver_mode,
                                                codegen.method_call_receiver_ref_tag,
                                                codegen.method_call_receiver_ref_payload,
                                                codegen.type_instance_decl_token,
                                                codegen.type_instance_arg_start,
                                                codegen.type_instance_arg_count,
                                                codegen.type_instance_arg_ref_tag,
                                                codegen.type_instance_arg_ref_payload,
                                                codegen.fn_return_ref_tag,
                                                codegen.fn_return_ref_payload,
                                                codegen.member_result_ref_tag,
                                                codegen.member_result_ref_payload,
                                                codegen.struct_init_field_expected_ref_tag,
                                                codegen.struct_init_field_expected_ref_payload,
                                            )
                                            .map_err(|err| {
                                                CompileError::GpuCodegen(err.to_string())
                                            })
                                    })
                                    .ok_or_else(|| {
                                        CompileError::GpuCodegen(
                                            "GPU type metadata buffers missing".into(),
                                        )
                                    })??;
                                trace_wasm_compile("source_pack.wasm.recorded");
                                Ok::<_, CompileError>((recorded, wasm_check))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    trace_wasm_compile("source_pack.parser.typecheck.recorded");
                    let (type_check, wasm_check) = type_check?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "wasm.codegen.done");
                    }
                    Ok((parser_check, type_check, wasm_check))
                },
                |device, queue, _bufs, (parser_check, type_check, wasm_check)| {
                    trace_wasm_compile("source_pack.finish.parser.start");
                    self.parser
                        .finish_recorded_resident_ll1_hir_check(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    trace_wasm_compile("source_pack.finish.typecheck.start");
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                    trace_wasm_compile("source_pack.finish.wasm.start");
                    self.wasm_generator()?
                        .finish_recorded_wasm(device, queue, &wasm_check)
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()))
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source pack: {err}")))?
    }

    pub async fn compile_explicit_source_pack_paths_to_wasm<SP, UP>(
        &self,
        stdlib_paths: &[SP],
        user_paths: &[UP],
    ) -> Result<Vec<u8>, CompileError>
    where
        SP: AsRef<Path>,
        UP: AsRef<Path>,
    {
        let sources = load_explicit_source_pack_from_paths(stdlib_paths, user_paths)?;
        self.compile_source_pack_to_wasm(&sources).await
    }

    async fn compile_expanded_source_to_wasm(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        trace_wasm_compile("compile.start");
        self.lexer
            .with_recorded_resident_tokens_after_count(
                src,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    trace_wasm_compile("lex.recorded");
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
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut timer,
                            |parse_bufs, encoder, timer| {
                                trace_wasm_compile("parser.recorded");
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                let hir_status = &parse_bufs.ll1_status;
                                let recorded = self
                                    .type_checker
                                    .record_resident_token_buffer_with_hir_items_on_gpu(
                                        device,
                                        queue,
                                        encoder,
                                        bufs.n,
                                        bufs.source_file_start.count as u32,
                                        token_capacity,
                                        &bufs.tokens_out,
                                        &bufs.token_count,
                                        &bufs.token_file_id,
                                        &bufs.in_bytes,
                                        parse_bufs.tree_capacity,
                                        &parse_bufs.hir_kind,
                                        &parse_bufs.hir_token_pos,
                                        &parse_bufs.hir_token_end,
                                        &parse_bufs.hir_token_file_id,
                                        hir_status,
                                        gpu_type_checker::GpuTypeCheckHirItemBuffers {
                                            node_kind: &parse_bufs.node_kind,
                                            parent: &parse_bufs.parent,
                                            first_child: &parse_bufs.first_child,
                                            next_sibling: &parse_bufs.next_sibling,
                                            subtree_end: &parse_bufs.subtree_end,
                                            kind: &parse_bufs.hir_item_kind,
                                            name_token: &parse_bufs.hir_item_name_token,
                                            type_form: &parse_bufs.hir_type_form,
                                            type_value_node: &parse_bufs.hir_type_value_node,
                                            type_len_token: &parse_bufs.hir_type_len_token,
                                            type_len_value: &parse_bufs.hir_type_len_value,
                                            type_path_leaf_node: &parse_bufs
                                                .hir_type_path_leaf_node,
                                            type_arg_start: &parse_bufs.hir_type_arg_start,
                                            type_arg_count: &parse_bufs.hir_type_arg_count,
                                            type_arg_next: &parse_bufs.hir_type_arg_next,
                                            type_alias_target_node: &parse_bufs
                                                .hir_type_alias_target_node,
                                            fn_return_type_node: &parse_bufs
                                                .hir_fn_return_type_node,
                                            param_record: &parse_bufs.hir_param_record,
                                            expr_record: &parse_bufs.hir_expr_record,
                                            expr_int_value: &parse_bufs.hir_expr_int_value,
                                            member_receiver_node: &parse_bufs
                                                .hir_member_receiver_node,
                                            member_receiver_token: &parse_bufs
                                                .hir_member_receiver_token,
                                            member_name_token: &parse_bufs.hir_member_name_token,
                                            stmt_record: &parse_bufs.hir_stmt_record,
                                            array_lit_first_element: &parse_bufs
                                                .hir_array_lit_first_element,
                                            array_lit_element_count: &parse_bufs
                                                .hir_array_lit_element_count,
                                            array_element_next: &parse_bufs.hir_array_element_next,
                                            namespace: &parse_bufs.hir_item_namespace,
                                            visibility: &parse_bufs.hir_item_visibility,
                                            path_start: &parse_bufs.hir_item_path_start,
                                            path_end: &parse_bufs.hir_item_path_end,
                                            file_id: &parse_bufs.hir_item_file_id,
                                            import_target_kind: &parse_bufs
                                                .hir_item_import_target_kind,
                                            call_callee_node: &parse_bufs.hir_call_callee_node,
                                            call_arg_start: &parse_bufs.hir_call_arg_start,
                                            call_arg_end: &parse_bufs.hir_call_arg_end,
                                            call_arg_count: &parse_bufs.hir_call_arg_count,
                                            call_arg_parent_call: &parse_bufs
                                                .hir_call_arg_parent_call,
                                            call_arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                            variant_parent_enum: &parse_bufs
                                                .hir_variant_parent_enum,
                                            variant_payload_start: &parse_bufs
                                                .hir_variant_payload_start,
                                            variant_payload_count: &parse_bufs
                                                .hir_variant_payload_count,
                                            match_scrutinee_node: &parse_bufs
                                                .hir_match_scrutinee_node,
                                            match_arm_start: &parse_bufs.hir_match_arm_start,
                                            match_arm_count: &parse_bufs.hir_match_arm_count,
                                            match_arm_next: &parse_bufs.hir_match_arm_next,
                                            match_arm_pattern_node: &parse_bufs
                                                .hir_match_arm_pattern_node,
                                            match_arm_payload_start: &parse_bufs
                                                .hir_match_arm_payload_start,
                                            match_arm_payload_count: &parse_bufs
                                                .hir_match_arm_payload_count,
                                            match_arm_result_node: &parse_bufs
                                                .hir_match_arm_result_node,
                                            match_payload_owner_arm: &parse_bufs
                                                .hir_match_payload_owner_arm,
                                            match_payload_match_node: &parse_bufs
                                                .hir_match_payload_match_node,
                                            match_payload_ordinal: &parse_bufs
                                                .hir_match_payload_ordinal,
                                            struct_field_parent_struct: &parse_bufs
                                                .hir_struct_field_parent_struct,
                                            struct_field_ordinal: &parse_bufs
                                                .hir_struct_field_ordinal,
                                            struct_field_type_node: &parse_bufs
                                                .hir_struct_field_type_node,
                                            struct_decl_field_start: &parse_bufs
                                                .hir_struct_decl_field_start,
                                            struct_decl_field_count: &parse_bufs
                                                .hir_struct_decl_field_count,
                                            struct_lit_head_node: &parse_bufs
                                                .hir_struct_lit_head_node,
                                            struct_lit_field_start: &parse_bufs
                                                .hir_struct_lit_field_start,
                                            struct_lit_field_count: &parse_bufs
                                                .hir_struct_lit_field_count,
                                            struct_lit_field_parent_lit: &parse_bufs
                                                .hir_struct_lit_field_parent_lit,
                                            struct_lit_field_value_node: &parse_bufs
                                                .hir_struct_lit_field_value_node,
                                            semantic_dense_node: &parse_bufs
                                                .hir_semantic_dense_node,
                                            semantic_count: &parse_bufs.hir_semantic_count,
                                        },
                                        timer.as_deref_mut(),
                                    )
                                    .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                                trace_wasm_compile("typecheck.recorded");
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "typecheck.done");
                                }
                                let wasm_check = self
                                    .type_checker
                                    .with_codegen_buffers(|codegen| {
                                        self.wasm_generator()?
                                            .record_wasm_from_gpu_token_buffer(
                                                device,
                                                queue,
                                                encoder,
                                                bufs.n,
                                                token_capacity,
                                                &bufs.tokens_out,
                                                &bufs.token_count,
                                                &bufs.in_bytes,
                                                parse_bufs.tree_capacity,
                                                &parse_bufs.node_kind,
                                                &parse_bufs.parent,
                                                &parse_bufs.first_child,
                                                &parse_bufs.next_sibling,
                                                &parse_bufs.hir_kind,
                                                &parse_bufs.hir_token_pos,
                                                &parse_bufs.hir_token_end,
                                                hir_status,
                                                codegen.visible_decl,
                                                codegen.visible_type,
                                                codegen.name_id_by_token,
                                                wasm::GpuWasmStructMetadataBuffers {
                                                    field_parent_struct: &parse_bufs
                                                        .hir_struct_field_parent_struct,
                                                    field_ordinal: &parse_bufs
                                                        .hir_struct_field_ordinal,
                                                    lit_field_parent_lit: &parse_bufs
                                                        .hir_struct_lit_field_parent_lit,
                                                },
                                                wasm::GpuWasmEnumMatchMetadataBuffers {
                                                    variant_ordinal: &parse_bufs
                                                        .hir_variant_ordinal,
                                                    match_scrutinee_node: &parse_bufs
                                                        .hir_match_scrutinee_node,
                                                    match_arm_start: &parse_bufs
                                                        .hir_match_arm_start,
                                                    match_arm_count: &parse_bufs
                                                        .hir_match_arm_count,
                                                    match_arm_pattern_node: &parse_bufs
                                                        .hir_match_arm_pattern_node,
                                                    match_arm_payload_start: &parse_bufs
                                                        .hir_match_arm_payload_start,
                                                    match_arm_payload_count: &parse_bufs
                                                        .hir_match_arm_payload_count,
                                                    match_arm_result_node: &parse_bufs
                                                        .hir_match_arm_result_node,
                                                },
                                                wasm::GpuWasmCallMetadataBuffers {
                                                    callee_node: &parse_bufs.hir_call_callee_node,
                                                    arg_start: &parse_bufs.hir_call_arg_start,
                                                    arg_parent_call: &parse_bufs
                                                        .hir_call_arg_parent_call,
                                                    arg_end: &parse_bufs.hir_call_arg_end,
                                                    arg_count: &parse_bufs.hir_call_arg_count,
                                                    arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                                },
                                                wasm::GpuWasmExprMetadataBuffers {
                                                    record: &parse_bufs.hir_expr_record,
                                                    int_value: &parse_bufs.hir_expr_int_value,
                                                    stmt_record: &parse_bufs.hir_stmt_record,
                                                },
                                                &parse_bufs.hir_param_record,
                                                codegen.type_expr_ref_tag,
                                                codegen.type_expr_ref_payload,
                                                codegen.module_value_path_call_head,
                                                codegen.module_value_path_call_open,
                                                codegen.module_value_path_const_head,
                                                codegen.module_value_path_const_end,
                                                codegen.call_fn_index,
                                                codegen.call_intrinsic_tag,
                                                codegen.fn_entrypoint_tag,
                                                codegen.call_return_type,
                                                codegen.call_return_type_token,
                                                codegen.call_param_count,
                                                codegen.call_param_type,
                                                codegen.method_decl_receiver_ref_tag,
                                                codegen.method_decl_receiver_ref_payload,
                                                codegen.method_decl_param_offset,
                                                codegen.method_decl_receiver_mode,
                                                codegen.method_call_receiver_ref_tag,
                                                codegen.method_call_receiver_ref_payload,
                                                codegen.type_instance_decl_token,
                                                codegen.type_instance_arg_start,
                                                codegen.type_instance_arg_count,
                                                codegen.type_instance_arg_ref_tag,
                                                codegen.type_instance_arg_ref_payload,
                                                codegen.fn_return_ref_tag,
                                                codegen.fn_return_ref_payload,
                                                codegen.member_result_ref_tag,
                                                codegen.member_result_ref_payload,
                                                codegen.struct_init_field_expected_ref_tag,
                                                codegen.struct_init_field_expected_ref_payload,
                                            )
                                            .map_err(|err| {
                                                CompileError::GpuCodegen(err.to_string())
                                            })
                                    })
                                    .ok_or_else(|| {
                                        CompileError::GpuCodegen(
                                            "GPU type metadata buffers missing".into(),
                                        )
                                    })??;
                                trace_wasm_compile("wasm.recorded");
                                Ok::<_, CompileError>((recorded, wasm_check))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    trace_wasm_compile("parser.typecheck.recorded");
                    let (type_check, wasm_check) = type_check?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "wasm.codegen.done");
                    }
                    Ok((parser_check, type_check, wasm_check))
                },
                |device, queue, _bufs, (parser_check, type_check, wasm_check)| {
                    trace_wasm_compile("finish.parser.start");
                    self.parser
                        .finish_recorded_resident_ll1_hir_check(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    trace_wasm_compile("finish.typecheck.start");
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                    trace_wasm_compile("finish.wasm.start");
                    self.wasm_generator()?
                        .finish_recorded_wasm(device, queue, &wasm_check)
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()))
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source: {err}")))?
    }

    fn wasm_generator(&self) -> Result<&wasm::GpuWasmCodeGenerator, CompileError> {
        trace_wasm_compile("wasm.generator");
        self.wasm_generator.as_deref().map_err(|err| {
            CompileError::GpuCodegen(format!("initialize GPU WASM code generator: {err}"))
        })
    }

    fn x86_generator(&self) -> Result<&x86::GpuX86CodeGenerator, CompileError> {
        self.x86_generator.as_deref().map_err(|err| {
            CompileError::GpuCodegen(format!("initialize GPU x86 code generator: {err}"))
        })
    }

    #[allow(clippy::too_many_arguments)]
    fn record_x86_from_parse_buffers(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        token_capacity: u32,
        x86_hir_node_count: u32,
        x86_inst_hir_node_count: u32,
        parse_bufs: &ParserBuffers,
        mut timer: Option<&mut GpuTimer>,
    ) -> Result<x86::RecordedX86Codegen, CompileError> {
        let hir_status = &parse_bufs.ll1_status;
        self.type_checker
            .with_codegen_buffers(|codegen| {
                self.x86_generator()?
                    .record_x86_elf_from_gpu_hir(
                        device,
                        queue,
                        encoder,
                        source_len,
                        token_capacity,
                        x86_hir_node_count,
                        x86_inst_hir_node_count,
                        hir_status,
                        &parse_bufs.tree_active_dispatch_args,
                        &parse_bufs.hir_kind,
                        &parse_bufs.parent,
                        &parse_bufs.first_child,
                        &parse_bufs.next_sibling,
                        &parse_bufs.subtree_end,
                        x86::GpuX86FunctionMetadataBuffers {
                            node_decl_token: &parse_bufs.hir_item_decl_token,
                            node_name_token: &parse_bufs.hir_item_name_token,
                            hir_token_pos: &parse_bufs.hir_token_pos,
                            param_record: &parse_bufs.hir_param_record,
                            enclosing_fn: codegen.enclosing_fn,
                            method_decl_param_offset: codegen.method_decl_param_offset,
                            method_decl_receiver_ref_tag: codegen.method_decl_receiver_ref_tag,
                            method_decl_receiver_ref_payload: codegen
                                .method_decl_receiver_ref_payload,
                        },
                        x86::GpuX86ExprMetadataBuffers {
                            record: &parse_bufs.hir_expr_record,
                            int_value: &parse_bufs.hir_expr_int_value,
                            stmt_record: &parse_bufs.hir_stmt_record,
                        },
                        x86::GpuX86CallMetadataBuffers {
                            callee_node: &parse_bufs.hir_call_callee_node,
                            arg_start: &parse_bufs.hir_call_arg_start,
                            arg_end: &parse_bufs.hir_call_arg_end,
                            arg_count: &parse_bufs.hir_call_arg_count,
                            arg_parent_call: &parse_bufs.hir_call_arg_parent_call,
                            arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                            member_receiver_node: &parse_bufs.hir_member_receiver_node,
                            member_name_token: &parse_bufs.hir_member_name_token,
                            call_fn_index: codegen.call_fn_index,
                            call_intrinsic_tag: codegen.call_intrinsic_tag,
                            call_return_type: codegen.call_return_type,
                            call_return_type_token: codegen.call_return_type_token,
                            call_param_type: codegen.call_param_type,
                        },
                        x86::GpuX86ArrayMetadataBuffers {
                            lit_first_element: &parse_bufs.hir_array_lit_first_element,
                            lit_element_count: &parse_bufs.hir_array_lit_element_count,
                            element_parent_lit: &parse_bufs.hir_array_element_parent_lit,
                            element_ordinal: &parse_bufs.hir_array_element_ordinal,
                            element_next: &parse_bufs.hir_array_element_next,
                        },
                        x86::GpuX86EnumMetadataBuffers {
                            item_decl_token: &parse_bufs.hir_item_decl_token,
                            variant_parent_enum: &parse_bufs.hir_variant_parent_enum,
                            variant_ordinal: &parse_bufs.hir_variant_ordinal,
                            variant_payload_count: &parse_bufs.hir_variant_payload_count,
                            match_scrutinee_node: &parse_bufs.hir_match_scrutinee_node,
                            match_arm_start: &parse_bufs.hir_match_arm_start,
                            match_arm_count: &parse_bufs.hir_match_arm_count,
                            match_arm_next: &parse_bufs.hir_match_arm_next,
                            match_arm_pattern_node: &parse_bufs.hir_match_arm_pattern_node,
                            match_arm_payload_start: &parse_bufs.hir_match_arm_payload_start,
                            match_arm_payload_count: &parse_bufs.hir_match_arm_payload_count,
                            match_arm_result_node: &parse_bufs.hir_match_arm_result_node,
                            hir_token_pos: &parse_bufs.hir_token_pos,
                            path_count_out: codegen.path_count_out,
                            path_id_by_owner_hir: codegen.path_id_by_owner_hir,
                            resolved_value_decl: codegen.resolved_value_decl,
                            resolved_value_status: codegen.resolved_value_status,
                            decl_count_out: codegen.decl_count_out,
                            decl_kind: codegen.decl_kind,
                            decl_name_token: codegen.decl_name_token,
                            decl_id_by_name_token: codegen.decl_id_by_name_token,
                            decl_hir_node: codegen.decl_hir_node,
                            decl_parent_type_decl: codegen.decl_parent_type_decl,
                        },
                        x86::GpuX86StructMetadataBuffers {
                            item_name_token: &parse_bufs.hir_item_name_token,
                            decl_hir_node: codegen.decl_hir_node,
                            struct_decl_field_count: &parse_bufs.hir_struct_decl_field_count,
                            struct_lit_field_parent_lit: &parse_bufs
                                .hir_struct_lit_field_parent_lit,
                            struct_lit_field_start: &parse_bufs.hir_struct_lit_field_start,
                            struct_lit_field_count: &parse_bufs.hir_struct_lit_field_count,
                            struct_lit_field_value_node: &parse_bufs
                                .hir_struct_lit_field_value_node,
                            struct_lit_field_next: &parse_bufs.hir_struct_lit_field_next,
                            member_result_field_ordinal: codegen.member_result_field_ordinal,
                            struct_init_field_ordinal: codegen.struct_init_field_ordinal,
                            struct_init_field_ordinal_by_node: codegen
                                .struct_init_field_ordinal_by_node,
                        },
                        x86::GpuX86TypeMetadataBuffers {
                            decl_type_ref_tag: codegen.decl_type_ref_tag,
                            decl_type_ref_payload: codegen.decl_type_ref_payload,
                            visible_type: codegen.visible_type,
                            type_instance_kind: codegen.type_instance_kind,
                            type_instance_decl_token: codegen.type_instance_decl_token,
                            type_instance_len_kind: codegen.type_instance_len_kind,
                            type_instance_len_payload: codegen.type_instance_len_payload,
                        },
                        codegen.visible_decl,
                        codegen.fn_entrypoint_tag,
                        timer.as_deref_mut(),
                    )
                    .map_err(|err| CompileError::GpuCodegen(err.to_string()))
            })
            .ok_or_else(|| CompileError::GpuCodegen("GPU type metadata buffers missing".into()))?
    }

    pub async fn compile_source_to_x86_64(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu_codegen(src)?;
        self.compile_expanded_source_to_x86_64(&src).await
    }

    pub async fn compile_source_to_x86_64_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu_codegen_from_path(path)?;
        self.compile_expanded_source_to_x86_64(&src).await
    }

    pub async fn compile_source_pack_to_x86_64<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<Vec<u8>, CompileError> {
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_source_pack_tokens_after_count(
                sources,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    let mut host_timer = CompilerHostTimer::new("compiler.x86.source_pack.record");
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
                    host_timer.stamp("projected_tree_capacity");
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut timer,
                            |parse_bufs, encoder, timer| {
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                host_timer.stamp("parser_recorded");
                                let hir_status = &parse_bufs.ll1_status;
                                let recorded = self
                                    .type_checker
                                    .record_resident_token_buffer_with_hir_items_on_gpu(
                                        device,
                                        queue,
                                        encoder,
                                        bufs.n,
                                        bufs.source_file_start.count as u32,
                                        token_capacity,
                                        &bufs.tokens_out,
                                        &bufs.token_count,
                                        &bufs.token_file_id,
                                        &bufs.in_bytes,
                                        parse_bufs.tree_capacity,
                                        &parse_bufs.hir_kind,
                                        &parse_bufs.hir_token_pos,
                                        &parse_bufs.hir_token_end,
                                        &parse_bufs.hir_token_file_id,
                                        hir_status,
                                        gpu_type_checker::GpuTypeCheckHirItemBuffers {
                                            node_kind: &parse_bufs.node_kind,
                                            parent: &parse_bufs.parent,
                                            first_child: &parse_bufs.first_child,
                                            next_sibling: &parse_bufs.next_sibling,
                                            subtree_end: &parse_bufs.subtree_end,
                                            kind: &parse_bufs.hir_item_kind,
                                            name_token: &parse_bufs.hir_item_name_token,
                                            type_form: &parse_bufs.hir_type_form,
                                            type_value_node: &parse_bufs.hir_type_value_node,
                                            type_len_token: &parse_bufs.hir_type_len_token,
                                            type_len_value: &parse_bufs.hir_type_len_value,
                                            type_path_leaf_node: &parse_bufs
                                                .hir_type_path_leaf_node,
                                            type_arg_start: &parse_bufs.hir_type_arg_start,
                                            type_arg_count: &parse_bufs.hir_type_arg_count,
                                            type_arg_next: &parse_bufs.hir_type_arg_next,
                                            type_alias_target_node: &parse_bufs
                                                .hir_type_alias_target_node,
                                            fn_return_type_node: &parse_bufs
                                                .hir_fn_return_type_node,
                                            param_record: &parse_bufs.hir_param_record,
                                            expr_record: &parse_bufs.hir_expr_record,
                                            expr_int_value: &parse_bufs.hir_expr_int_value,
                                            member_receiver_node: &parse_bufs
                                                .hir_member_receiver_node,
                                            member_receiver_token: &parse_bufs
                                                .hir_member_receiver_token,
                                            member_name_token: &parse_bufs.hir_member_name_token,
                                            stmt_record: &parse_bufs.hir_stmt_record,
                                            array_lit_first_element: &parse_bufs
                                                .hir_array_lit_first_element,
                                            array_lit_element_count: &parse_bufs
                                                .hir_array_lit_element_count,
                                            array_element_next: &parse_bufs.hir_array_element_next,
                                            namespace: &parse_bufs.hir_item_namespace,
                                            visibility: &parse_bufs.hir_item_visibility,
                                            path_start: &parse_bufs.hir_item_path_start,
                                            path_end: &parse_bufs.hir_item_path_end,
                                            file_id: &parse_bufs.hir_item_file_id,
                                            import_target_kind: &parse_bufs
                                                .hir_item_import_target_kind,
                                            call_callee_node: &parse_bufs.hir_call_callee_node,
                                            call_arg_start: &parse_bufs.hir_call_arg_start,
                                            call_arg_end: &parse_bufs.hir_call_arg_end,
                                            call_arg_count: &parse_bufs.hir_call_arg_count,
                                            call_arg_parent_call: &parse_bufs
                                                .hir_call_arg_parent_call,
                                            call_arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                            variant_parent_enum: &parse_bufs
                                                .hir_variant_parent_enum,
                                            variant_payload_start: &parse_bufs
                                                .hir_variant_payload_start,
                                            variant_payload_count: &parse_bufs
                                                .hir_variant_payload_count,
                                            match_scrutinee_node: &parse_bufs
                                                .hir_match_scrutinee_node,
                                            match_arm_start: &parse_bufs.hir_match_arm_start,
                                            match_arm_count: &parse_bufs.hir_match_arm_count,
                                            match_arm_next: &parse_bufs.hir_match_arm_next,
                                            match_arm_pattern_node: &parse_bufs
                                                .hir_match_arm_pattern_node,
                                            match_arm_payload_start: &parse_bufs
                                                .hir_match_arm_payload_start,
                                            match_arm_payload_count: &parse_bufs
                                                .hir_match_arm_payload_count,
                                            match_arm_result_node: &parse_bufs
                                                .hir_match_arm_result_node,
                                            match_payload_owner_arm: &parse_bufs
                                                .hir_match_payload_owner_arm,
                                            match_payload_match_node: &parse_bufs
                                                .hir_match_payload_match_node,
                                            match_payload_ordinal: &parse_bufs
                                                .hir_match_payload_ordinal,
                                            struct_field_parent_struct: &parse_bufs
                                                .hir_struct_field_parent_struct,
                                            struct_field_ordinal: &parse_bufs
                                                .hir_struct_field_ordinal,
                                            struct_field_type_node: &parse_bufs
                                                .hir_struct_field_type_node,
                                            struct_decl_field_start: &parse_bufs
                                                .hir_struct_decl_field_start,
                                            struct_decl_field_count: &parse_bufs
                                                .hir_struct_decl_field_count,
                                            struct_lit_head_node: &parse_bufs
                                                .hir_struct_lit_head_node,
                                            struct_lit_field_start: &parse_bufs
                                                .hir_struct_lit_field_start,
                                            struct_lit_field_count: &parse_bufs
                                                .hir_struct_lit_field_count,
                                            struct_lit_field_parent_lit: &parse_bufs
                                                .hir_struct_lit_field_parent_lit,
                                            struct_lit_field_value_node: &parse_bufs
                                                .hir_struct_lit_field_value_node,
                                            semantic_dense_node: &parse_bufs
                                                .hir_semantic_dense_node,
                                            semantic_count: &parse_bufs.hir_semantic_count,
                                        },
                                        timer.as_deref_mut(),
                                    )
                                    .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                                host_timer.stamp("typecheck_recorded");
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "typecheck.done");
                                }
                                let x86_hir_node_count = parser_tree_capacity.max(1);
                                let x86_check = self.record_x86_from_parse_buffers(
                                    device,
                                    queue,
                                    encoder,
                                    bufs.n,
                                    token_capacity,
                                    x86_hir_node_count,
                                    x86_hir_node_count,
                                    parse_bufs,
                                    timer.as_deref_mut(),
                                )?;
                                host_timer.stamp("x86_recorded");
                                Ok::<_, CompileError>((recorded, x86_check))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    host_timer.stamp("parser_typecheck_recorded");
                    let (type_check, x86_check) = type_check?;
                    Ok((parser_check, type_check, x86_check))
                },
                |device, queue, _bufs, (parser_check, type_check, x86_check)| {
                    let mut host_timer = CompilerHostTimer::new("compiler.x86.source_pack.finish");
                    self.x86_generator()?;
                    host_timer.stamp("x86_generator_ready");
                    self.parser
                        .finish_recorded_resident_ll1_hir_check_result(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    host_timer.stamp("parser_finish");
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                    host_timer.stamp("typecheck_finish");
                    let result = self
                        .x86_generator()?
                        .finish_recorded_x86(device, queue, &x86_check)
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()));
                    host_timer.stamp("x86_finish");
                    result
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source pack: {err}")))?
    }

    pub async fn compile_explicit_source_pack_paths_to_x86_64<SP, UP>(
        &self,
        stdlib_paths: &[SP],
        user_paths: &[UP],
    ) -> Result<Vec<u8>, CompileError>
    where
        SP: AsRef<Path>,
        UP: AsRef<Path>,
    {
        let sources = load_explicit_source_pack_from_paths(stdlib_paths, user_paths)?;
        self.compile_source_pack_to_x86_64(&sources).await
    }

    async fn compile_expanded_source_to_x86_64(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_tokens_after_count(
                src,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    let mut host_timer = CompilerHostTimer::new("compiler.x86.record");
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
                    host_timer.stamp("projected_tree_capacity");
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut timer,
                            |parse_bufs, encoder, timer| {
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                host_timer.stamp("parser_recorded");
                                let hir_status = &parse_bufs.ll1_status;
                                let recorded = self
                                    .type_checker
                                    .record_resident_token_buffer_with_hir_items_on_gpu(
                                        device,
                                        queue,
                                        encoder,
                                        bufs.n,
                                        bufs.source_file_start.count as u32,
                                        token_capacity,
                                        &bufs.tokens_out,
                                        &bufs.token_count,
                                        &bufs.token_file_id,
                                        &bufs.in_bytes,
                                        parse_bufs.tree_capacity,
                                        &parse_bufs.hir_kind,
                                        &parse_bufs.hir_token_pos,
                                        &parse_bufs.hir_token_end,
                                        &parse_bufs.hir_token_file_id,
                                        hir_status,
                                        gpu_type_checker::GpuTypeCheckHirItemBuffers {
                                            node_kind: &parse_bufs.node_kind,
                                            parent: &parse_bufs.parent,
                                            first_child: &parse_bufs.first_child,
                                            next_sibling: &parse_bufs.next_sibling,
                                            subtree_end: &parse_bufs.subtree_end,
                                            kind: &parse_bufs.hir_item_kind,
                                            name_token: &parse_bufs.hir_item_name_token,
                                            type_form: &parse_bufs.hir_type_form,
                                            type_value_node: &parse_bufs.hir_type_value_node,
                                            type_len_token: &parse_bufs.hir_type_len_token,
                                            type_len_value: &parse_bufs.hir_type_len_value,
                                            type_path_leaf_node: &parse_bufs
                                                .hir_type_path_leaf_node,
                                            type_arg_start: &parse_bufs.hir_type_arg_start,
                                            type_arg_count: &parse_bufs.hir_type_arg_count,
                                            type_arg_next: &parse_bufs.hir_type_arg_next,
                                            type_alias_target_node: &parse_bufs
                                                .hir_type_alias_target_node,
                                            fn_return_type_node: &parse_bufs
                                                .hir_fn_return_type_node,
                                            param_record: &parse_bufs.hir_param_record,
                                            expr_record: &parse_bufs.hir_expr_record,
                                            expr_int_value: &parse_bufs.hir_expr_int_value,
                                            member_receiver_node: &parse_bufs
                                                .hir_member_receiver_node,
                                            member_receiver_token: &parse_bufs
                                                .hir_member_receiver_token,
                                            member_name_token: &parse_bufs.hir_member_name_token,
                                            stmt_record: &parse_bufs.hir_stmt_record,
                                            array_lit_first_element: &parse_bufs
                                                .hir_array_lit_first_element,
                                            array_lit_element_count: &parse_bufs
                                                .hir_array_lit_element_count,
                                            array_element_next: &parse_bufs.hir_array_element_next,
                                            namespace: &parse_bufs.hir_item_namespace,
                                            visibility: &parse_bufs.hir_item_visibility,
                                            path_start: &parse_bufs.hir_item_path_start,
                                            path_end: &parse_bufs.hir_item_path_end,
                                            file_id: &parse_bufs.hir_item_file_id,
                                            import_target_kind: &parse_bufs
                                                .hir_item_import_target_kind,
                                            call_callee_node: &parse_bufs.hir_call_callee_node,
                                            call_arg_start: &parse_bufs.hir_call_arg_start,
                                            call_arg_end: &parse_bufs.hir_call_arg_end,
                                            call_arg_count: &parse_bufs.hir_call_arg_count,
                                            call_arg_parent_call: &parse_bufs
                                                .hir_call_arg_parent_call,
                                            call_arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                            variant_parent_enum: &parse_bufs
                                                .hir_variant_parent_enum,
                                            variant_payload_start: &parse_bufs
                                                .hir_variant_payload_start,
                                            variant_payload_count: &parse_bufs
                                                .hir_variant_payload_count,
                                            match_scrutinee_node: &parse_bufs
                                                .hir_match_scrutinee_node,
                                            match_arm_start: &parse_bufs.hir_match_arm_start,
                                            match_arm_count: &parse_bufs.hir_match_arm_count,
                                            match_arm_next: &parse_bufs.hir_match_arm_next,
                                            match_arm_pattern_node: &parse_bufs
                                                .hir_match_arm_pattern_node,
                                            match_arm_payload_start: &parse_bufs
                                                .hir_match_arm_payload_start,
                                            match_arm_payload_count: &parse_bufs
                                                .hir_match_arm_payload_count,
                                            match_arm_result_node: &parse_bufs
                                                .hir_match_arm_result_node,
                                            match_payload_owner_arm: &parse_bufs
                                                .hir_match_payload_owner_arm,
                                            match_payload_match_node: &parse_bufs
                                                .hir_match_payload_match_node,
                                            match_payload_ordinal: &parse_bufs
                                                .hir_match_payload_ordinal,
                                            struct_field_parent_struct: &parse_bufs
                                                .hir_struct_field_parent_struct,
                                            struct_field_ordinal: &parse_bufs
                                                .hir_struct_field_ordinal,
                                            struct_field_type_node: &parse_bufs
                                                .hir_struct_field_type_node,
                                            struct_decl_field_start: &parse_bufs
                                                .hir_struct_decl_field_start,
                                            struct_decl_field_count: &parse_bufs
                                                .hir_struct_decl_field_count,
                                            struct_lit_head_node: &parse_bufs
                                                .hir_struct_lit_head_node,
                                            struct_lit_field_start: &parse_bufs
                                                .hir_struct_lit_field_start,
                                            struct_lit_field_count: &parse_bufs
                                                .hir_struct_lit_field_count,
                                            struct_lit_field_parent_lit: &parse_bufs
                                                .hir_struct_lit_field_parent_lit,
                                            struct_lit_field_value_node: &parse_bufs
                                                .hir_struct_lit_field_value_node,
                                            semantic_dense_node: &parse_bufs
                                                .hir_semantic_dense_node,
                                            semantic_count: &parse_bufs.hir_semantic_count,
                                        },
                                        timer.as_deref_mut(),
                                    )
                                    .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                                host_timer.stamp("typecheck_recorded");
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "typecheck.done");
                                }
                                let x86_hir_node_count = parser_tree_capacity.max(1);
                                let x86_check = self.record_x86_from_parse_buffers(
                                    device,
                                    queue,
                                    encoder,
                                    bufs.n,
                                    token_capacity,
                                    x86_hir_node_count,
                                    x86_hir_node_count,
                                    parse_bufs,
                                    timer.as_deref_mut(),
                                )?;
                                host_timer.stamp("x86_recorded");
                                Ok::<_, CompileError>((recorded, x86_check))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    host_timer.stamp("parser_typecheck_recorded");
                    let (type_check, x86_check) = type_check?;
                    Ok((parser_check, type_check, x86_check))
                },
                |device, queue, _bufs, (parser_check, type_check, x86_check)| {
                    let mut host_timer = CompilerHostTimer::new("compiler.x86.finish");
                    self.x86_generator()?;
                    host_timer.stamp("x86_generator_ready");
                    self.parser
                        .finish_recorded_resident_ll1_hir_check_result(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    host_timer.stamp("parser_finish");
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                    host_timer.stamp("typecheck_finish");
                    let result = self
                        .x86_generator()?
                        .finish_recorded_x86(device, queue, &x86_check)
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()));
                    host_timer.stamp("x86_finish");
                    result
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source: {err}")))?
    }
}

fn trace_wasm_compile(stage: &str) {
    if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
        eprintln!("[laniusc][wasm] {stage}");
    }
}

struct CompilerHostTimer {
    label: &'static str,
    print_enabled: bool,
    trace_enabled: bool,
    start: std::time::Instant,
    last: std::time::Instant,
}

impl CompilerHostTimer {
    fn new(label: &'static str) -> Self {
        let now = std::time::Instant::now();
        Self {
            label,
            print_enabled: crate::gpu::env::env_bool_truthy(
                "LANIUS_GPU_COMPILE_HOST_TIMING",
                false,
            ),
            trace_enabled: crate::gpu::trace::enabled(),
            start: now,
            last: now,
        }
    }

    fn stamp(&mut self, stage: &str) {
        if !self.print_enabled && !self.trace_enabled {
            return;
        }
        let now = std::time::Instant::now();
        let dt_ms = now.duration_since(self.last).as_secs_f64() * 1000.0;
        let total_ms = now.duration_since(self.start).as_secs_f64() * 1000.0;
        let name = format!("{}.{stage}", self.label);
        if self.print_enabled {
            println!("[gpu_compile_host_timer] {name}: {dt_ms:.3}ms (total {total_ms:.3}ms)");
        }
        if self.trace_enabled {
            crate::gpu::trace::record_host_span("host.compiler", &name, self.last, now);
        }
        self.last = now;
    }

    fn pipeline_cache_size(&self, gpu: &GpuDevice, stage: &str) {
        if !crate::gpu::env::env_bool_truthy("LANIUS_PIPELINE_CACHE_BREAKDOWN", false) {
            return;
        }
        let start = std::time::Instant::now();
        let size = gpu.pipeline_cache_data_len();
        let end = std::time::Instant::now();
        let sample_ms = end.duration_since(start).as_secs_f64() * 1000.0;
        match size {
            Some(bytes) => {
                eprintln!(
                    "[pipeline_cache_breakdown] stage={stage} bytes={bytes} sample_ms={sample_ms:.3}"
                );
                if self.trace_enabled {
                    crate::gpu::trace::record_host_span(
                        "host.pipeline_cache",
                        &format!("pipeline_cache.sample.{stage}"),
                        start,
                        end,
                    );
                    crate::gpu::trace::record_counter(
                        "host.pipeline_cache.size",
                        "pipeline_cache_bytes",
                        end,
                        bytes as f64,
                    );
                }
            }
            None => {
                eprintln!(
                    "[pipeline_cache_breakdown] stage={stage} bytes=unavailable sample_ms={sample_ms:.3}"
                );
            }
        }
    }
}

fn prepare_source_for_gpu(src: &str) -> Result<String, CompileError> {
    Ok(src.to_string())
}

fn prepare_source_for_gpu_from_path(path: impl AsRef<Path>) -> Result<String, CompileError> {
    fs::read_to_string(path.as_ref()).map_err(|err| {
        CompileError::GpuFrontend(format!("read {}: {err}", path.as_ref().display()))
    })
}

pub fn load_explicit_source_pack_from_paths<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
) -> Result<Vec<String>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    let mut sources = Vec::with_capacity(stdlib_paths.len() + user_paths.len());
    read_explicit_source_paths("stdlib", stdlib_paths, &mut sources)?;
    read_explicit_source_paths("user", user_paths, &mut sources)?;
    if sources.is_empty() {
        return Err(CompileError::GpuFrontend(
            "explicit source pack has no source files".to_string(),
        ));
    }
    Ok(sources)
}

fn read_explicit_source_paths<P: AsRef<Path>>(
    label: &str,
    paths: &[P],
    sources: &mut Vec<String>,
) -> Result<(), CompileError> {
    for (i, path) in paths.iter().enumerate() {
        let path = path.as_ref();
        let source = fs::read_to_string(path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read explicit {label} source file {i} ({}): {err}",
                path.display()
            ))
        })?;
        sources.push(source);
    }
    Ok(())
}

fn prepare_source_for_gpu_codegen(src: &str) -> Result<String, CompileError> {
    prepare_source_for_gpu(src)
}

fn prepare_source_for_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<String, CompileError> {
    prepare_source_for_gpu_from_path(path)
}

fn prepare_source_for_gpu_type_check(src: &str) -> Result<String, CompileError> {
    prepare_source_for_gpu(src)
}

fn prepare_source_for_gpu_type_check_from_path(
    path: impl AsRef<Path>,
) -> Result<String, CompileError> {
    prepare_source_for_gpu_from_path(path)
}

fn global_gpu_compiler_for(
    compiler: &'static OnceLock<Result<GpuCompiler<'static>, String>>,
    backends: GpuCompilerBackends,
    label: &'static str,
) -> Result<&'static GpuCompiler<'static>, CompileError> {
    compiler
        .get_or_init(|| {
            pollster::block_on(GpuCompiler::new_with_device_and_backends(
                device::global(),
                backends,
            ))
            .map_err(|err| err.to_string())
        })
        .as_ref()
        .map_err(|err| CompileError::GpuFrontend(format!("initialize {label} GPU compiler: {err}")))
}

fn global_frontend_gpu_compiler() -> Result<&'static GpuCompiler<'static>, CompileError> {
    static GPU_FRONTEND_COMPILER: OnceLock<Result<GpuCompiler<'static>, String>> = OnceLock::new();
    global_gpu_compiler_for(
        &GPU_FRONTEND_COMPILER,
        GpuCompilerBackends::frontend_only(),
        "frontend",
    )
}

fn global_wasm_gpu_compiler() -> Result<&'static GpuCompiler<'static>, CompileError> {
    static GPU_WASM_COMPILER: OnceLock<Result<GpuCompiler<'static>, String>> = OnceLock::new();
    global_gpu_compiler_for(&GPU_WASM_COMPILER, GpuCompilerBackends::wasm_only(), "WASM")
}

fn global_x86_gpu_compiler() -> Result<&'static GpuCompiler<'static>, CompileError> {
    static GPU_X86_COMPILER: OnceLock<Result<GpuCompiler<'static>, String>> = OnceLock::new();
    global_gpu_compiler_for(&GPU_X86_COMPILER, GpuCompilerBackends::x86_only(), "x86")
}

pub async fn compile_source_to_wasm_with_gpu_codegen(src: &str) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen(src)?;
    global_wasm_gpu_compiler()?
        .compile_expanded_source_to_wasm(&src)
        .await
}

pub async fn type_check_source_with_gpu(src: &str) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check(src)?;
    global_frontend_gpu_compiler()?
        .type_check_expanded_source(&src)
        .await
}

pub async fn type_check_source_pack_with_gpu<S: AsRef<str>>(
    sources: &[S],
) -> Result<(), CompileError> {
    global_frontend_gpu_compiler()?
        .type_check_explicit_source_pack(sources)
        .await
}

pub async fn type_check_source_with_gpu_from_path(
    path: impl AsRef<Path>,
) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check_from_path(path)?;
    global_frontend_gpu_compiler()?
        .type_check_expanded_source(&src)
        .await
}

pub async fn type_check_source_with_gpu_using(
    src: &str,
    compiler: &GpuCompiler<'_>,
) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check(src)?;
    compiler.type_check_expanded_source(&src).await
}

pub async fn type_check_source_pack_with_gpu_using<S: AsRef<str>>(
    sources: &[S],
    compiler: &GpuCompiler<'_>,
) -> Result<(), CompileError> {
    compiler.type_check_explicit_source_pack(sources).await
}

pub async fn compile_source_pack_to_wasm_with_gpu_codegen<S: AsRef<str>>(
    sources: &[S],
) -> Result<Vec<u8>, CompileError> {
    global_wasm_gpu_compiler()?
        .compile_source_pack_to_wasm(sources)
        .await
}

pub async fn compile_source_pack_to_wasm_with_gpu_codegen_using<S: AsRef<str>>(
    sources: &[S],
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    compiler.compile_source_pack_to_wasm(sources).await
}

pub async fn compile_explicit_source_pack_paths_to_wasm_with_gpu_codegen<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
) -> Result<Vec<u8>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    let sources = load_explicit_source_pack_from_paths(stdlib_paths, user_paths)?;
    global_wasm_gpu_compiler()?
        .compile_source_pack_to_wasm(&sources)
        .await
}

pub async fn compile_explicit_source_pack_paths_to_wasm_with_gpu_codegen_using<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    compiler
        .compile_explicit_source_pack_paths_to_wasm(stdlib_paths, user_paths)
        .await
}

pub async fn type_check_source_with_gpu_using_path(
    path: impl AsRef<Path>,
    compiler: &GpuCompiler<'_>,
) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check_from_path(path)?;
    compiler.type_check_expanded_source(&src).await
}

pub async fn compile_source_to_wasm_with_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    global_wasm_gpu_compiler()?
        .compile_expanded_source_to_wasm(&src)
        .await
}

pub async fn compile_source_to_wasm_with_gpu_codegen_using(
    src: &str,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen(src)?;
    compiler.compile_expanded_source_to_wasm(&src).await
}

pub async fn compile_source_to_wasm_with_gpu_codegen_using_path(
    path: impl AsRef<Path>,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    compiler.compile_expanded_source_to_wasm(&src).await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen(src: &str) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen(src)?;
    global_x86_gpu_compiler()?
        .compile_expanded_source_to_x86_64(&src)
        .await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    global_x86_gpu_compiler()?
        .compile_expanded_source_to_x86_64(&src)
        .await
}

pub async fn compile_source_pack_to_x86_64_with_gpu_codegen<S: AsRef<str>>(
    sources: &[S],
) -> Result<Vec<u8>, CompileError> {
    global_x86_gpu_compiler()?
        .compile_source_pack_to_x86_64(sources)
        .await
}

pub async fn compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
) -> Result<Vec<u8>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    let sources = load_explicit_source_pack_from_paths(stdlib_paths, user_paths)?;
    global_x86_gpu_compiler()?
        .compile_source_pack_to_x86_64(&sources)
        .await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_using(
    src: &str,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen(src)?;
    compiler.compile_expanded_source_to_x86_64(&src).await
}

pub async fn compile_source_pack_to_x86_64_with_gpu_codegen_using<S: AsRef<str>>(
    sources: &[S],
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    compiler.compile_source_pack_to_x86_64(sources).await
}

pub async fn compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen_using<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    compiler
        .compile_explicit_source_pack_paths_to_x86_64(stdlib_paths, user_paths)
        .await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_using_path(
    path: impl AsRef<Path>,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    compiler.compile_expanded_source_to_x86_64(&src).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn x86_only_compiler_does_not_initialize_wasm_backend() {
        let compiler = pollster::block_on(GpuCompiler::new_with_device_and_backends(
            device::global(),
            GpuCompilerBackends::x86_only(),
        ))
        .expect("initialize x86-only GPU compiler");

        assert!(
            compiler.wasm_generator.is_err(),
            "x86-only global compiler path must not initialize legacy WASM backend pipelines"
        );
        assert!(
            compiler.x86_generator.is_ok(),
            "x86-only global compiler path should initialize x86 backend pipelines"
        );
    }
}

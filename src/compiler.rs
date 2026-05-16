use std::{fs, path::Path, sync::OnceLock};

use futures_intrusive::sync::Mutex;

use crate::{
    codegen::{wasm, x86},
    gpu::device::{self, GpuDevice},
    lexer::driver::GpuLexer,
    parser::{driver::GpuParser, tables::PrecomputedParseTables},
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

pub struct GpuCompiler<'gpu> {
    gpu: &'gpu GpuDevice,
    lexer: GpuLexer,
    parser: GpuParser,
    parse_tables: PrecomputedParseTables,
    type_checker: gpu_type_checker::GpuTypeChecker,
    resident_pipeline_lock: Mutex<()>,
    wasm_generator: OnceLock<Result<wasm::GpuWasmCodeGenerator, String>>,
    x86_generator: OnceLock<Result<x86::GpuX86CodeGenerator, String>>,
}

impl GpuCompiler<'static> {
    pub async fn new() -> Result<Self, CompileError> {
        Self::new_with_device(device::global()).await
    }
}

impl<'gpu> GpuCompiler<'gpu> {
    pub async fn new_with_device(gpu: &'gpu GpuDevice) -> Result<Self, CompileError> {
        let lexer = GpuLexer::new_with_device(gpu)
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("initialize GPU lexer: {err}")))?;
        let parser = GpuParser::new_with_device(gpu)
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("initialize GPU parser: {err}")))?;
        let parse_tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .map_err(|err| {
                    CompileError::GpuFrontend(format!("load GPU parse tables: {err}"))
                })?;
        let type_checker =
            gpu_type_checker::GpuTypeChecker::new_with_device(gpu).map_err(|err| {
                CompileError::GpuFrontend(format!("initialize GPU type checker: {err}"))
            })?;
        gpu.persist_pipeline_cache();
        Ok(Self {
            gpu,
            lexer,
            parser,
            parse_tables,
            type_checker,
            resident_pipeline_lock: Mutex::new((), false),
            wasm_generator: OnceLock::new(),
            x86_generator: OnceLock::new(),
        })
    }

    pub fn gpu(&self) -> &'gpu GpuDevice {
        self.gpu
    }

    pub async fn type_check_source(&self, src: &str) -> Result<(), CompileError> {
        let src = prepare_source_for_gpu_type_check(src)?;
        self.type_check_expanded_source(&src).await
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
            .with_recorded_resident_tokens(
                src,
                |device, queue, bufs, encoder, mut timer| {
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts(
                            encoder,
                            bufs.n,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
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
                                        bufs.n,
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
                                            kind: &parse_bufs.hir_item_kind,
                                            name_token: &parse_bufs.hir_item_name_token,
                                            type_form: &parse_bufs.hir_type_form,
                                            type_value_node: &parse_bufs.hir_type_value_node,
                                            type_len_token: &parse_bufs.hir_type_len_token,
                                            type_len_value: &parse_bufs.hir_type_len_value,
                                            param_record: &parse_bufs.hir_param_record,
                                            expr_form: &parse_bufs.hir_expr_form,
                                            expr_left_node: &parse_bufs.hir_expr_left_node,
                                            expr_right_node: &parse_bufs.hir_expr_right_node,
                                            expr_value_token: &parse_bufs.hir_expr_value_token,
                                            expr_record: &parse_bufs.hir_expr_record,
                                            expr_int_value: &parse_bufs.hir_expr_int_value,
                                            member_receiver_node: &parse_bufs
                                                .hir_member_receiver_node,
                                            member_receiver_token: &parse_bufs
                                                .hir_member_receiver_token,
                                            member_name_token: &parse_bufs.hir_member_name_token,
                                            stmt_record: &parse_bufs.hir_stmt_record,
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
                                            variant_payload_count: &parse_bufs
                                                .hir_variant_payload_count,
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
            .with_recorded_resident_source_pack_tokens(
                sources,
                |device, queue, bufs, encoder, mut timer| {
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts(
                            encoder,
                            bufs.n,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
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
                                        bufs.n,
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
                                            kind: &parse_bufs.hir_item_kind,
                                            name_token: &parse_bufs.hir_item_name_token,
                                            type_form: &parse_bufs.hir_type_form,
                                            type_value_node: &parse_bufs.hir_type_value_node,
                                            type_len_token: &parse_bufs.hir_type_len_token,
                                            type_len_value: &parse_bufs.hir_type_len_value,
                                            param_record: &parse_bufs.hir_param_record,
                                            expr_form: &parse_bufs.hir_expr_form,
                                            expr_left_node: &parse_bufs.hir_expr_left_node,
                                            expr_right_node: &parse_bufs.hir_expr_right_node,
                                            expr_value_token: &parse_bufs.hir_expr_value_token,
                                            expr_record: &parse_bufs.hir_expr_record,
                                            expr_int_value: &parse_bufs.hir_expr_int_value,
                                            member_receiver_node: &parse_bufs
                                                .hir_member_receiver_node,
                                            member_receiver_token: &parse_bufs
                                                .hir_member_receiver_token,
                                            member_name_token: &parse_bufs.hir_member_name_token,
                                            stmt_record: &parse_bufs.hir_stmt_record,
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
                                            variant_payload_count: &parse_bufs
                                                .hir_variant_payload_count,
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
            .with_recorded_resident_source_pack_tokens(
                sources,
                |device, queue, bufs, encoder, mut timer| {
                    trace_wasm_compile("source_pack.lex.recorded");
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts(
                            encoder,
                            bufs.n,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
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
                                        bufs.n,
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
                                            kind: &parse_bufs.hir_item_kind,
                                            name_token: &parse_bufs.hir_item_name_token,
                                            type_form: &parse_bufs.hir_type_form,
                                            type_value_node: &parse_bufs.hir_type_value_node,
                                            type_len_token: &parse_bufs.hir_type_len_token,
                                            type_len_value: &parse_bufs.hir_type_len_value,
                                            param_record: &parse_bufs.hir_param_record,
                                            expr_form: &parse_bufs.hir_expr_form,
                                            expr_left_node: &parse_bufs.hir_expr_left_node,
                                            expr_right_node: &parse_bufs.hir_expr_right_node,
                                            expr_value_token: &parse_bufs.hir_expr_value_token,
                                            expr_record: &parse_bufs.hir_expr_record,
                                            expr_int_value: &parse_bufs.hir_expr_int_value,
                                            member_receiver_node: &parse_bufs
                                                .hir_member_receiver_node,
                                            member_receiver_token: &parse_bufs
                                                .hir_member_receiver_token,
                                            member_name_token: &parse_bufs.hir_member_name_token,
                                            stmt_record: &parse_bufs.hir_stmt_record,
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
                                            variant_payload_count: &parse_bufs
                                                .hir_variant_payload_count,
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
                                                bufs.n,
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
                                                    form: &parse_bufs.hir_expr_form,
                                                    left_node: &parse_bufs.hir_expr_left_node,
                                                    right_node: &parse_bufs.hir_expr_right_node,
                                                    value_token: &parse_bufs.hir_expr_value_token,
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
            .with_recorded_resident_tokens(
                src,
                |device, queue, bufs, encoder, mut timer| {
                    trace_wasm_compile("lex.recorded");
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts(
                            encoder,
                            bufs.n,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
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
                                        bufs.n,
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
                                            kind: &parse_bufs.hir_item_kind,
                                            name_token: &parse_bufs.hir_item_name_token,
                                            type_form: &parse_bufs.hir_type_form,
                                            type_value_node: &parse_bufs.hir_type_value_node,
                                            type_len_token: &parse_bufs.hir_type_len_token,
                                            type_len_value: &parse_bufs.hir_type_len_value,
                                            param_record: &parse_bufs.hir_param_record,
                                            expr_form: &parse_bufs.hir_expr_form,
                                            expr_left_node: &parse_bufs.hir_expr_left_node,
                                            expr_right_node: &parse_bufs.hir_expr_right_node,
                                            expr_value_token: &parse_bufs.hir_expr_value_token,
                                            expr_record: &parse_bufs.hir_expr_record,
                                            expr_int_value: &parse_bufs.hir_expr_int_value,
                                            member_receiver_node: &parse_bufs
                                                .hir_member_receiver_node,
                                            member_receiver_token: &parse_bufs
                                                .hir_member_receiver_token,
                                            member_name_token: &parse_bufs.hir_member_name_token,
                                            stmt_record: &parse_bufs.hir_stmt_record,
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
                                            variant_payload_count: &parse_bufs
                                                .hir_variant_payload_count,
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
                                                bufs.n,
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
                                                    form: &parse_bufs.hir_expr_form,
                                                    left_node: &parse_bufs.hir_expr_left_node,
                                                    right_node: &parse_bufs.hir_expr_right_node,
                                                    value_token: &parse_bufs.hir_expr_value_token,
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
        self.wasm_generator
            .get_or_init(|| {
                let generator = wasm::GpuWasmCodeGenerator::new_with_device(self.gpu)
                    .map_err(|err| err.to_string())?;
                self.gpu.persist_pipeline_cache();
                Ok(generator)
            })
            .as_ref()
            .map_err(|err| {
                CompileError::GpuCodegen(format!("initialize GPU WASM code generator: {err}"))
            })
    }

    fn x86_generator(&self) -> Result<&x86::GpuX86CodeGenerator, CompileError> {
        self.x86_generator
            .get_or_init(|| {
                let generator = x86::GpuX86CodeGenerator::new_with_device(self.gpu)
                    .map_err(|err| err.to_string())?;
                self.gpu.persist_pipeline_cache();
                Ok(generator)
            })
            .as_ref()
            .map_err(|err| {
                CompileError::GpuCodegen(format!("initialize GPU x86 code generator: {err}"))
            })
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
            .with_recorded_resident_source_pack_tokens(
                sources,
                |device, queue, bufs, encoder, mut timer| {
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts(
                            encoder,
                            bufs.n,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            &mut timer,
                            |parse_bufs, encoder, timer| {
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
                                        bufs.n,
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
                                            kind: &parse_bufs.hir_item_kind,
                                            name_token: &parse_bufs.hir_item_name_token,
                                            type_form: &parse_bufs.hir_type_form,
                                            type_value_node: &parse_bufs.hir_type_value_node,
                                            type_len_token: &parse_bufs.hir_type_len_token,
                                            type_len_value: &parse_bufs.hir_type_len_value,
                                            param_record: &parse_bufs.hir_param_record,
                                            expr_form: &parse_bufs.hir_expr_form,
                                            expr_left_node: &parse_bufs.hir_expr_left_node,
                                            expr_right_node: &parse_bufs.hir_expr_right_node,
                                            expr_value_token: &parse_bufs.hir_expr_value_token,
                                            expr_record: &parse_bufs.hir_expr_record,
                                            expr_int_value: &parse_bufs.hir_expr_int_value,
                                            member_receiver_node: &parse_bufs
                                                .hir_member_receiver_node,
                                            member_receiver_token: &parse_bufs
                                                .hir_member_receiver_token,
                                            member_name_token: &parse_bufs.hir_member_name_token,
                                            stmt_record: &parse_bufs.hir_stmt_record,
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
                                            variant_payload_count: &parse_bufs
                                                .hir_variant_payload_count,
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
                                        },
                                        timer.as_deref_mut(),
                                    )
                                    .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "typecheck.done");
                                }
                                let x86_check = self
                                    .type_checker
                                    .with_codegen_buffers(|codegen| {
                                        self.x86_generator()?
                                            .record_x86_elf_from_gpu_hir(
                                                device,
                                                queue,
                                                encoder,
                                                bufs.n,
                                                bufs.n,
                                                parse_bufs.tree_capacity,
                                                hir_status,
                                                &parse_bufs.hir_kind,
                                                &parse_bufs.parent,
                                                &parse_bufs.first_child,
                                                &parse_bufs.next_sibling,
                                                &parse_bufs.subtree_end,
                                                x86::GpuX86FunctionMetadataBuffers {
                                                    item_kind: &parse_bufs.hir_item_kind,
                                                    item_decl_token: &parse_bufs
                                                        .hir_item_decl_token,
                                                    param_record: &parse_bufs.hir_param_record,
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
                                                    arg_parent_call: &parse_bufs
                                                        .hir_call_arg_parent_call,
                                                    arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                                    call_fn_index: codegen.call_fn_index,
                                                    call_intrinsic_tag: codegen.call_intrinsic_tag,
                                                    call_return_type: codegen.call_return_type,
                                                    call_return_type_token: codegen
                                                        .call_return_type_token,
                                                    call_param_type: codegen.call_param_type,
                                                },
                                                codegen.visible_decl,
                                                codegen.fn_entrypoint_tag,
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
                                Ok::<_, CompileError>((recorded, x86_check))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let (type_check, x86_check) = type_check?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "x86.codegen.done");
                    }
                    Ok((parser_check, type_check, x86_check))
                },
                |device, queue, _bufs, (parser_check, type_check, x86_check)| {
                    self.parser
                        .finish_recorded_resident_ll1_hir_check(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                    self.x86_generator()?
                        .finish_recorded_x86(device, queue, &x86_check)
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()))
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
            .with_recorded_resident_tokens(
                src,
                |device, queue, bufs, encoder, mut timer| {
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts(
                            encoder,
                            bufs.n,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            &mut timer,
                            |parse_bufs, encoder, timer| {
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
                                        bufs.n,
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
                                            kind: &parse_bufs.hir_item_kind,
                                            name_token: &parse_bufs.hir_item_name_token,
                                            type_form: &parse_bufs.hir_type_form,
                                            type_value_node: &parse_bufs.hir_type_value_node,
                                            type_len_token: &parse_bufs.hir_type_len_token,
                                            type_len_value: &parse_bufs.hir_type_len_value,
                                            param_record: &parse_bufs.hir_param_record,
                                            expr_form: &parse_bufs.hir_expr_form,
                                            expr_left_node: &parse_bufs.hir_expr_left_node,
                                            expr_right_node: &parse_bufs.hir_expr_right_node,
                                            expr_value_token: &parse_bufs.hir_expr_value_token,
                                            expr_record: &parse_bufs.hir_expr_record,
                                            expr_int_value: &parse_bufs.hir_expr_int_value,
                                            member_receiver_node: &parse_bufs
                                                .hir_member_receiver_node,
                                            member_receiver_token: &parse_bufs
                                                .hir_member_receiver_token,
                                            member_name_token: &parse_bufs.hir_member_name_token,
                                            stmt_record: &parse_bufs.hir_stmt_record,
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
                                            variant_payload_count: &parse_bufs
                                                .hir_variant_payload_count,
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
                                        },
                                        timer.as_deref_mut(),
                                    )
                                    .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "typecheck.done");
                                }
                                let x86_check = self
                                    .type_checker
                                    .with_codegen_buffers(|codegen| {
                                        self.x86_generator()?
                                            .record_x86_elf_from_gpu_hir(
                                                device,
                                                queue,
                                                encoder,
                                                bufs.n,
                                                bufs.n,
                                                parse_bufs.tree_capacity,
                                                hir_status,
                                                &parse_bufs.hir_kind,
                                                &parse_bufs.parent,
                                                &parse_bufs.first_child,
                                                &parse_bufs.next_sibling,
                                                &parse_bufs.subtree_end,
                                                x86::GpuX86FunctionMetadataBuffers {
                                                    item_kind: &parse_bufs.hir_item_kind,
                                                    item_decl_token: &parse_bufs
                                                        .hir_item_decl_token,
                                                    param_record: &parse_bufs.hir_param_record,
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
                                                    arg_parent_call: &parse_bufs
                                                        .hir_call_arg_parent_call,
                                                    arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                                    call_fn_index: codegen.call_fn_index,
                                                    call_intrinsic_tag: codegen.call_intrinsic_tag,
                                                    call_return_type: codegen.call_return_type,
                                                    call_return_type_token: codegen
                                                        .call_return_type_token,
                                                    call_param_type: codegen.call_param_type,
                                                },
                                                codegen.visible_decl,
                                                codegen.fn_entrypoint_tag,
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
                                Ok::<_, CompileError>((recorded, x86_check))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let (type_check, x86_check) = type_check?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "x86.codegen.done");
                    }
                    Ok((parser_check, type_check, x86_check))
                },
                |device, queue, _bufs, (parser_check, type_check, x86_check)| {
                    self.parser
                        .finish_recorded_resident_ll1_hir_check(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                    self.x86_generator()?
                        .finish_recorded_x86(device, queue, &x86_check)
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()))
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

fn global_gpu_compiler() -> Result<&'static GpuCompiler<'static>, CompileError> {
    static GPU_COMPILER: OnceLock<Result<GpuCompiler<'static>, String>> = OnceLock::new();
    GPU_COMPILER
        .get_or_init(|| pollster::block_on(GpuCompiler::new()).map_err(|err| err.to_string()))
        .as_ref()
        .map_err(|err| CompileError::GpuFrontend(format!("initialize GPU compiler: {err}")))
}

pub async fn compile_source_to_wasm_with_gpu_codegen(src: &str) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen(src)?;
    global_gpu_compiler()?
        .compile_expanded_source_to_wasm(&src)
        .await
}

pub async fn type_check_source_with_gpu(src: &str) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check(src)?;
    global_gpu_compiler()?
        .type_check_expanded_source(&src)
        .await
}

pub async fn type_check_source_pack_with_gpu<S: AsRef<str>>(
    sources: &[S],
) -> Result<(), CompileError> {
    global_gpu_compiler()?
        .type_check_explicit_source_pack(sources)
        .await
}

pub async fn type_check_source_with_gpu_from_path(
    path: impl AsRef<Path>,
) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check_from_path(path)?;
    global_gpu_compiler()?
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
    global_gpu_compiler()?
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
    global_gpu_compiler()?
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
    global_gpu_compiler()?
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
    global_gpu_compiler()?
        .compile_expanded_source_to_x86_64(&src)
        .await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    global_gpu_compiler()?
        .compile_expanded_source_to_x86_64(&src)
        .await
}

pub async fn compile_source_pack_to_x86_64_with_gpu_codegen<S: AsRef<str>>(
    sources: &[S],
) -> Result<Vec<u8>, CompileError> {
    global_gpu_compiler()?
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
    global_gpu_compiler()?
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

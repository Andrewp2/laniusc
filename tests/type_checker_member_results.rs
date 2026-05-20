mod common;

use laniusc::{
    gpu::device,
    lexer::{driver::GpuLexer, test_cpu::lex_on_test_cpu},
    parser::{driver::GpuParser, tables::PrecomputedParseTables},
    type_checker::{GpuCodegenBuffers, GpuTypeCheckHirItemBuffers, GpuTypeChecker},
};

struct MemberResultReadbacks {
    tag: wgpu::Buffer,
    payload: wgpu::Buffer,
    ordinal: wgpu::Buffer,
    instance_kind: wgpu::Buffer,
    instance_decl_token: wgpu::Buffer,
    instance_arg_count: wgpu::Buffer,
    visible_decl: wgpu::Buffer,
    visible_type: wgpu::Buffer,
    call_return_type: wgpu::Buffer,
    call_fn_index: wgpu::Buffer,
    instance_arg_start: wgpu::Buffer,
    instance_arg_ref_tag: wgpu::Buffer,
    instance_arg_ref_payload: wgpu::Buffer,
    method_decl_module_id: wgpu::Buffer,
    method_decl_name_token: wgpu::Buffer,
    method_decl_name_id: wgpu::Buffer,
    method_receiver_tag: wgpu::Buffer,
    method_receiver_payload: wgpu::Buffer,
    method_param_offset: wgpu::Buffer,
    method_visibility: wgpu::Buffer,
    method_key_status: wgpu::Buffer,
    method_call_receiver_tag: wgpu::Buffer,
    method_call_receiver_payload: wgpu::Buffer,
    method_call_name_id: wgpu::Buffer,
    method_call_site_module_id: wgpu::Buffer,
    type_expr_ref_tag: wgpu::Buffer,
    type_expr_ref_payload: wgpu::Buffer,
    fn_return_ref_tag: wgpu::Buffer,
    fn_return_ref_payload: wgpu::Buffer,
    struct_init_field_expected_ref_tag: wgpu::Buffer,
    struct_init_field_expected_ref_payload: wgpu::Buffer,
    struct_init_field_ordinal: wgpu::Buffer,
}

struct MemberResultSnapshot {
    tag: Vec<u32>,
    payload: Vec<u32>,
    ordinal: Vec<u32>,
    instance_kind: Vec<u32>,
    instance_decl_token: Vec<u32>,
    instance_arg_count: Vec<u32>,
    visible_decl: Vec<u32>,
    visible_type: Vec<u32>,
    call_return_type: Vec<u32>,
    call_fn_index: Vec<u32>,
    instance_arg_start: Vec<u32>,
    instance_arg_ref_tag: Vec<u32>,
    instance_arg_ref_payload: Vec<u32>,
    method_decl_module_id: Vec<u32>,
    method_decl_name_token: Vec<u32>,
    method_decl_name_id: Vec<u32>,
    method_receiver_tag: Vec<u32>,
    method_receiver_payload: Vec<u32>,
    method_param_offset: Vec<u32>,
    method_visibility: Vec<u32>,
    method_key_status: Vec<u32>,
    method_call_receiver_tag: Vec<u32>,
    method_call_receiver_payload: Vec<u32>,
    method_call_name_id: Vec<u32>,
    method_call_site_module_id: Vec<u32>,
    type_expr_ref_tag: Vec<u32>,
    type_expr_ref_payload: Vec<u32>,
    fn_return_ref_tag: Vec<u32>,
    fn_return_ref_payload: Vec<u32>,
    struct_init_field_expected_ref_tag: Vec<u32>,
    struct_init_field_expected_ref_payload: Vec<u32>,
    struct_init_field_ordinal: Vec<u32>,
    type_error: Option<String>,
}

fn token_texts(src: &str) -> Vec<String> {
    lex_on_test_cpu(src)
        .expect("test CPU oracle lex fixture")
        .into_iter()
        .map(|token| src[token.start..token.start + token.len].to_string())
        .collect()
}

fn member_token(texts: &[String], receiver: &str, member: &str) -> usize {
    texts
        .windows(3)
        .position(|window| window[0] == receiver && window[1] == "." && window[2] == member)
        .map(|index| index + 2)
        .unwrap_or_else(|| panic!("missing member token {receiver}.{member}: {texts:?}"))
}

fn last_member_token(texts: &[String], receiver: &str, member: &str) -> usize {
    texts
        .windows(3)
        .enumerate()
        .filter(|(_, window)| window[0] == receiver && window[1] == "." && window[2] == member)
        .map(|(index, _)| index + 2)
        .last()
        .unwrap_or_else(|| panic!("missing member token {receiver}.{member}: {texts:?}"))
}

fn call_result_member_token(texts: &[String], member: &str) -> usize {
    texts
        .windows(3)
        .enumerate()
        .filter(|(_, window)| window[0] == ")" && window[1] == "." && window[2] == member)
        .map(|(index, _)| index + 2)
        .last()
        .unwrap_or_else(|| panic!("missing call-result member token .{member}: {texts:?}"))
}

fn fn_token(texts: &[String], name: &str) -> usize {
    texts
        .windows(2)
        .position(|window| window[0] == "fn" && window[1] == name)
        .unwrap_or_else(|| panic!("missing function token fn {name}: {texts:?}"))
}

fn last_call_name_token(texts: &[String], name: &str) -> usize {
    texts
        .windows(2)
        .enumerate()
        .filter(|(_, window)| window[0] == name && window[1] == "(")
        .map(|(index, _)| index)
        .last()
        .unwrap_or_else(|| panic!("missing call token {name}(: {texts:?}"))
}

fn struct_name_token(texts: &[String], name: &str) -> usize {
    texts
        .windows(2)
        .position(|window| window[0] == "struct" && window[1] == name)
        .map(|index| index + 1)
        .unwrap_or_else(|| panic!("missing struct token struct {name}: {texts:?}"))
}

fn qualified_range_type_tokens(texts: &[String]) -> (usize, usize) {
    texts
        .windows(8)
        .position(|window| {
            window[0] == "core"
                && window[1] == ":"
                && window[2] == ":"
                && window[3] == "range"
                && window[4] == ":"
                && window[5] == ":"
                && window[6] == "Range"
                && window[7] == "<"
        })
        .map(|index| (index, index + 6))
        .unwrap_or_else(|| panic!("missing qualified core::range::Range type: {texts:?}"))
}

fn snapshot_word(words: &[u32], index: u32) -> u32 {
    words.get(index as usize).copied().unwrap_or(u32::MAX)
}

fn read_words(device: &wgpu::Device, buffer: &wgpu::Buffer, count: usize) -> Vec<u32> {
    let slice = buffer.slice(0..(count * 4) as u64);
    slice.map_async(wgpu::MapMode::Read, |_| {});
    let _ = device.poll(wgpu::PollType::Wait);
    let bytes = slice.get_mapped_range();
    let words = bytes
        .chunks_exact(4)
        .map(|chunk| u32::from_le_bytes(chunk.try_into().unwrap()))
        .collect::<Vec<_>>();
    drop(bytes);
    buffer.unmap();
    words
}

fn copy_member_result_readbacks(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    codegen: GpuCodegenBuffers<'_>,
    size: u64,
) -> MemberResultReadbacks {
    let mk = |label| {
        device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        })
    };
    let tag = mk("rb.test.member_result.tag");
    let payload = mk("rb.test.member_result.payload");
    let ordinal = mk("rb.test.member_result.ordinal");
    let instance_kind = mk("rb.test.type_instance.kind");
    let instance_decl_token = mk("rb.test.type_instance.decl_token");
    let instance_arg_count = mk("rb.test.type_instance.arg_count");
    let visible_decl = mk("rb.test.visible_decl");
    let visible_type = mk("rb.test.visible_type");
    let call_return_type = mk("rb.test.call_return_type");
    let call_fn_index = mk("rb.test.call_fn_index");
    let instance_arg_start = mk("rb.test.type_instance.arg_start");
    let instance_arg_ref_tag = mk("rb.test.type_instance.arg_ref_tag");
    let instance_arg_ref_payload = mk("rb.test.type_instance.arg_ref_payload");
    let method_decl_module_id = mk("rb.test.method_decl_module_id");
    let method_decl_name_token = mk("rb.test.method_decl_name_token");
    let method_decl_name_id = mk("rb.test.method_decl_name_id");
    let method_receiver_tag = mk("rb.test.method_receiver.tag");
    let method_receiver_payload = mk("rb.test.method_receiver.payload");
    let method_param_offset = mk("rb.test.method_param_offset");
    let method_visibility = mk("rb.test.method_visibility");
    let method_key_status = mk("rb.test.method_key_status");
    let method_call_receiver_tag = mk("rb.test.method_call_receiver.tag");
    let method_call_receiver_payload = mk("rb.test.method_call_receiver.payload");
    let method_call_name_id = mk("rb.test.method_call_name_id");
    let method_call_site_module_id = mk("rb.test.method_call_site_module_id");
    let type_expr_ref_tag = mk("rb.test.type_expr_ref_tag");
    let type_expr_ref_payload = mk("rb.test.type_expr_ref_payload");
    let fn_return_ref_tag = mk("rb.test.fn_return_ref_tag");
    let fn_return_ref_payload = mk("rb.test.fn_return_ref_payload");
    let struct_init_field_expected_ref_tag = mk("rb.test.struct_init.expected_ref_tag");
    let struct_init_field_expected_ref_payload = mk("rb.test.struct_init.expected_ref_payload");
    let struct_init_field_ordinal = mk("rb.test.struct_init.ordinal");

    for (src, dst) in [
        (codegen.member_result_ref_tag, &tag),
        (codegen.member_result_ref_payload, &payload),
        (codegen.member_result_field_ordinal, &ordinal),
        (codegen.type_instance_kind, &instance_kind),
        (codegen.type_instance_decl_token, &instance_decl_token),
        (codegen.type_instance_arg_count, &instance_arg_count),
        (codegen.visible_decl, &visible_decl),
        (codegen.visible_type, &visible_type),
        (codegen.call_return_type, &call_return_type),
        (codegen.call_fn_index, &call_fn_index),
        (codegen.type_instance_arg_start, &instance_arg_start),
        (codegen.type_instance_arg_ref_tag, &instance_arg_ref_tag),
        (
            codegen.type_instance_arg_ref_payload,
            &instance_arg_ref_payload,
        ),
        (codegen.method_decl_module_id, &method_decl_module_id),
        (codegen.method_decl_name_token, &method_decl_name_token),
        (codegen.method_decl_name_id, &method_decl_name_id),
        (codegen.method_decl_receiver_ref_tag, &method_receiver_tag),
        (
            codegen.method_decl_receiver_ref_payload,
            &method_receiver_payload,
        ),
        (codegen.method_decl_param_offset, &method_param_offset),
        (codegen.method_decl_visibility, &method_visibility),
        (codegen.method_key_status, &method_key_status),
        (
            codegen.method_call_receiver_ref_tag,
            &method_call_receiver_tag,
        ),
        (
            codegen.method_call_receiver_ref_payload,
            &method_call_receiver_payload,
        ),
        (codegen.method_call_name_id, &method_call_name_id),
        (
            codegen.method_call_site_module_id,
            &method_call_site_module_id,
        ),
        (codegen.type_expr_ref_tag, &type_expr_ref_tag),
        (codegen.type_expr_ref_payload, &type_expr_ref_payload),
        (codegen.fn_return_ref_tag, &fn_return_ref_tag),
        (codegen.fn_return_ref_payload, &fn_return_ref_payload),
        (
            codegen.struct_init_field_expected_ref_tag,
            &struct_init_field_expected_ref_tag,
        ),
        (
            codegen.struct_init_field_expected_ref_payload,
            &struct_init_field_expected_ref_payload,
        ),
        (
            codegen.struct_init_field_ordinal,
            &struct_init_field_ordinal,
        ),
    ] {
        encoder.copy_buffer_to_buffer(src, 0, dst, 0, size);
    }

    MemberResultReadbacks {
        tag,
        payload,
        ordinal,
        instance_kind,
        instance_decl_token,
        instance_arg_count,
        visible_decl,
        visible_type,
        call_return_type,
        call_fn_index,
        instance_arg_start,
        instance_arg_ref_tag,
        instance_arg_ref_payload,
        method_decl_module_id,
        method_decl_name_token,
        method_decl_name_id,
        method_receiver_tag,
        method_receiver_payload,
        method_param_offset,
        method_visibility,
        method_key_status,
        method_call_receiver_tag,
        method_call_receiver_payload,
        method_call_name_id,
        method_call_site_module_id,
        type_expr_ref_tag,
        type_expr_ref_payload,
        fn_return_ref_tag,
        fn_return_ref_payload,
        struct_init_field_expected_ref_tag,
        struct_init_field_expected_ref_payload,
        struct_init_field_ordinal,
    }
}

fn read_snapshot(
    device: &wgpu::Device,
    readbacks: MemberResultReadbacks,
    count: usize,
    type_error: Option<String>,
) -> MemberResultSnapshot {
    MemberResultSnapshot {
        tag: read_words(device, &readbacks.tag, count),
        payload: read_words(device, &readbacks.payload, count),
        ordinal: read_words(device, &readbacks.ordinal, count),
        instance_kind: read_words(device, &readbacks.instance_kind, count),
        instance_decl_token: read_words(device, &readbacks.instance_decl_token, count),
        instance_arg_count: read_words(device, &readbacks.instance_arg_count, count),
        visible_decl: read_words(device, &readbacks.visible_decl, count),
        visible_type: read_words(device, &readbacks.visible_type, count),
        call_return_type: read_words(device, &readbacks.call_return_type, count),
        call_fn_index: read_words(device, &readbacks.call_fn_index, count),
        instance_arg_start: read_words(device, &readbacks.instance_arg_start, count),
        instance_arg_ref_tag: read_words(device, &readbacks.instance_arg_ref_tag, count),
        instance_arg_ref_payload: read_words(device, &readbacks.instance_arg_ref_payload, count),
        method_decl_module_id: read_words(device, &readbacks.method_decl_module_id, count),
        method_decl_name_token: read_words(device, &readbacks.method_decl_name_token, count),
        method_decl_name_id: read_words(device, &readbacks.method_decl_name_id, count),
        method_receiver_tag: read_words(device, &readbacks.method_receiver_tag, count),
        method_receiver_payload: read_words(device, &readbacks.method_receiver_payload, count),
        method_param_offset: read_words(device, &readbacks.method_param_offset, count),
        method_visibility: read_words(device, &readbacks.method_visibility, count),
        method_key_status: read_words(device, &readbacks.method_key_status, count),
        method_call_receiver_tag: read_words(device, &readbacks.method_call_receiver_tag, count),
        method_call_receiver_payload: read_words(
            device,
            &readbacks.method_call_receiver_payload,
            count,
        ),
        method_call_name_id: read_words(device, &readbacks.method_call_name_id, count),
        method_call_site_module_id: read_words(
            device,
            &readbacks.method_call_site_module_id,
            count,
        ),
        type_expr_ref_tag: read_words(device, &readbacks.type_expr_ref_tag, count),
        type_expr_ref_payload: read_words(device, &readbacks.type_expr_ref_payload, count),
        fn_return_ref_tag: read_words(device, &readbacks.fn_return_ref_tag, count),
        fn_return_ref_payload: read_words(device, &readbacks.fn_return_ref_payload, count),
        struct_init_field_expected_ref_tag: read_words(
            device,
            &readbacks.struct_init_field_expected_ref_tag,
            count,
        ),
        struct_init_field_expected_ref_payload: read_words(
            device,
            &readbacks.struct_init_field_expected_ref_payload,
            count,
        ),
        struct_init_field_ordinal: read_words(device, &readbacks.struct_init_field_ordinal, count),
        type_error,
    }
}

fn gpu_member_result_snapshot(src: &'static str, count: usize) -> MemberResultSnapshot {
    common::block_on_gpu_with_timeout("GPU member result metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let type_checker =
            GpuTypeChecker::new_with_device(device::global()).expect("GPU type checker init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        lexer
            .with_recorded_resident_tokens_after_count(
                src,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    let token_capacity = token_count.max(1);
                    let parser_tree_capacity = parser
                        .read_resident_projected_tree_capacity(
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            &tables,
                        )
                        .map_err(|err| err.to_string())?;
                    let (parser_check, type_check_and_readbacks) = parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &tables,
                            Some(parser_tree_capacity),
                            &mut timer,
                            |parse_bufs, encoder, timer| {
                                let recorded = type_checker
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
                                        GpuTypeCheckHirItemBuffers {
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
                                    .map_err(|err| err.to_string())?;

                                let readbacks = type_checker
                                    .with_codegen_buffers(|codegen| {
                                        let size = (token_capacity as u64).saturating_mul(4);
                                        copy_member_result_readbacks(device, encoder, codegen, size)
                                    })
                                    .expect("type checker buffers allocated");

                                Ok::<_, String>((recorded, readbacks))
                            },
                        )
                        .map_err(|err| err.to_string())?;
                    let type_check_and_readbacks = type_check_and_readbacks?;
                    Ok::<_, String>((parser_check, type_check_and_readbacks))
                },
                |device, _queue, _bufs, (parser_check, (type_check, readbacks))| {
                    parser
                        .finish_recorded_resident_ll1_hir_check(&parser_check)
                        .map_err(|err| err.to_string())?;
                    let type_error = type_checker
                        .finish_recorded_check(device, &type_check)
                        .err()
                        .map(|err| err.to_string());
                    Ok::<_, String>(read_snapshot(device, readbacks, count, type_error))
                },
            )
            .await
            .expect("resident GPU lex")
            .expect("record/read member results")
    })
}

fn gpu_member_result_source_pack_snapshot(
    sources: Vec<String>,
    count: usize,
) -> MemberResultSnapshot {
    common::block_on_gpu_with_timeout("GPU source-pack member metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let type_checker =
            GpuTypeChecker::new_with_device(device::global()).expect("GPU type checker init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        lexer
            .with_recorded_resident_source_pack_tokens(
                &sources,
                |device, queue, bufs, encoder, mut timer| {
                    let (parser_check, type_check_and_readbacks) = parser
                        .record_checked_resident_ll1_hir_artifacts(
                            encoder,
                            bufs.n,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &tables,
                            &mut timer,
                            |parse_bufs, encoder, timer| {
                                let recorded = type_checker
                                    .record_resident_token_buffer_with_hir_items_on_gpu(
                                        device,
                                        queue,
                                        encoder,
                                        bufs.n,
                                        bufs.source_file_start.count as u32,
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
                                        GpuTypeCheckHirItemBuffers {
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
                                    .map_err(|err| err.to_string())?;

                                let readbacks = type_checker
                                    .with_codegen_buffers(|codegen| {
                                        copy_member_result_readbacks(
                                            device,
                                            encoder,
                                            codegen,
                                            (bufs.n as u64).saturating_mul(4),
                                        )
                                    })
                                    .expect("type checker buffers allocated");

                                Ok::<_, String>((recorded, readbacks))
                            },
                        )
                        .map_err(|err| err.to_string())?;
                    let type_check_and_readbacks = type_check_and_readbacks?;
                    Ok::<_, String>((parser_check, type_check_and_readbacks))
                },
                |device, _queue, _bufs, (parser_check, (type_check, readbacks))| {
                    parser
                        .finish_recorded_resident_ll1_hir_check(&parser_check)
                        .map_err(|err| err.to_string())?;
                    let type_error = type_checker
                        .finish_recorded_check(device, &type_check)
                        .err()
                        .map(|err| err.to_string());
                    Ok::<_, String>(read_snapshot(device, readbacks, count, type_error))
                },
            )
            .await
            .expect("resident GPU source-pack lex")
            .expect("record/read source-pack member results")
    })
}

#[test]
fn gpu_member_result_records_project_impl_receiver_fields() {
    let src = r#"
struct Range {
    start: i32,
    end: i32,
}

impl Range {
    fn contains(receiver: Range, value: i32) -> bool {
        return value >= receiver.start && value < receiver.end;
    }
}

fn make_range() -> Range {
    return Range { start: 1, end: 4 };
}

fn read_direct() -> i32 {
    if (make_range().contains(2)) {
        return 1;
    }
    return 0;
}

fn main() {
    let range: Range = Range { start: 1, end: 4 };
    if (range.contains(2)) {
        return 1;
    }
    return 0;
}
"#;
    let texts = token_texts(src);
    let start_token = member_token(&texts, "receiver", "start");
    let end_token = member_token(&texts, "receiver", "end");

    let snapshot = gpu_member_result_snapshot(src, texts.len());

    assert_eq!(
        snapshot.ordinal[start_token], 0,
        "receiver.start should project field ordinal 0; tag={} payload={}",
        snapshot.tag[start_token], snapshot.payload[start_token]
    );
    assert_eq!(
        snapshot.ordinal[end_token], 1,
        "receiver.end should project field ordinal 1; tag={} payload={}",
        snapshot.tag[end_token], snapshot.payload[end_token]
    );
    assert!(
        snapshot.type_error.is_none(),
        "type checker rejected fixture after member result projection: {:?}",
        snapshot.type_error
    );
}

#[test]
fn gpu_member_result_records_generic_impl_receiver_fields() {
    let src = r#"
struct Range<T> {
    start: T,
    end: T,
}

impl Range<i32> {
    fn start(self) -> i32 {
        return self.start;
    }

    fn end(self: Range<i32>) -> i32 {
        return self.end;
    }

    fn contains(&self, value: i32) -> bool {
        return value >= self.start && value < self.end;
    }
}

fn read(range: Range<i32>) -> i32 {
    if (range.contains(2)) {
        return range.start();
    }
    return range.end();
}

fn main() {
    return 0;
}
"#;
    let texts = token_texts(src);
    let start_token = member_token(&texts, "self", "start");
    let end_token = member_token(&texts, "self", "end");
    let start_fn_token = fn_token(&texts, "start");

    let snapshot = gpu_member_result_snapshot(src, texts.len());

    assert_eq!(
        snapshot.ordinal[start_token],
        0,
        "self.start should project field ordinal 0; tag={} payload={} decl={} visible_decl={} method_receiver={}:{} method_param={}",
        snapshot.tag[start_token],
        snapshot.payload[start_token],
        snapshot_word(&snapshot.instance_decl_token, snapshot.payload[start_token]),
        snapshot.visible_decl[start_token - 2],
        snapshot.method_receiver_tag[start_fn_token],
        snapshot.method_receiver_payload[start_fn_token],
        snapshot.method_param_offset[start_fn_token],
    );
    assert_eq!(
        snapshot.ordinal[end_token],
        1,
        "self.end should project field ordinal 1; tag={} payload={} decl={}",
        snapshot.tag[end_token],
        snapshot.payload[end_token],
        snapshot_word(&snapshot.instance_decl_token, snapshot.payload[end_token])
    );
    assert!(
        snapshot.type_error.is_none(),
        "type checker rejected generic fixture after member result projection: {:?}",
        snapshot.type_error
    );
}

#[test]
fn gpu_visible_decl_resolves_struct_literal_field_values_to_scope_decls() {
    let src = r#"
struct Pair {
    left: i32,
    right: i32,
}

fn make_pair(alpha: i32, beta: i32) -> Pair {
    return Pair { left: alpha, right: beta, };
}

fn main() {
    return 0;
}
"#;
    let texts = token_texts(src);
    let alpha_param = texts
        .windows(2)
        .position(|window| window[0] == "(" && window[1] == "alpha")
        .map(|index| index + 1)
        .expect("alpha parameter token");
    let beta_param = texts
        .windows(2)
        .position(|window| window[0] == "," && window[1] == "beta")
        .map(|index| index + 1)
        .expect("beta parameter token");
    let alpha_value = texts
        .windows(3)
        .position(|window| window[0] == "left" && window[1] == ":" && window[2] == "alpha")
        .map(|index| index + 2)
        .expect("alpha struct-literal value token");
    let alpha_field = alpha_value - 2;
    let i32_field_type = texts
        .windows(3)
        .position(|window| window[0] == "left" && window[1] == ":" && window[2] == "i32")
        .map(|index| index + 2)
        .expect("left field type token");
    let beta_value = texts
        .windows(3)
        .position(|window| window[0] == "right" && window[1] == ":" && window[2] == "beta")
        .map(|index| index + 2)
        .expect("beta struct-literal value token");

    let snapshot = gpu_member_result_snapshot(src, texts.len());

    assert_eq!(
        snapshot.visible_decl[alpha_value], alpha_param as u32,
        "struct literal field value alpha should resolve through the HIR visible-decl table; value={} got={} expected={}",
        alpha_value, snapshot.visible_decl[alpha_value], alpha_param,
    );
    assert_eq!(
        snapshot.visible_decl[beta_value], beta_param as u32,
        "struct literal field value beta should resolve through the HIR visible-decl table; value={} got={} expected={}",
        beta_value, snapshot.visible_decl[beta_value], beta_param,
    );
    assert!(
        snapshot.type_error.is_none(),
        "type checker rejected struct-literal value resolver fixture: {:?}; left_field={} visible_type={} expected_tag={} expected_payload={} ordinal={} field_type_token={} type_expr={}:{}",
        snapshot.type_error,
        alpha_field,
        snapshot.visible_type[alpha_field],
        snapshot.struct_init_field_expected_ref_tag[alpha_field],
        snapshot.struct_init_field_expected_ref_payload[alpha_field],
        snapshot.struct_init_field_ordinal[alpha_field],
        i32_field_type,
        snapshot.type_expr_ref_tag[i32_field_type],
        snapshot.type_expr_ref_payload[i32_field_type],
    );
}

#[test]
fn gpu_member_result_records_source_pack_public_generic_methods() {
    let sources = vec![
        include_str!("../stdlib/core/range.lani").to_owned(),
        r#"
module app::main;

import core::range;

fn main() {
    let range: core::range::Range<i32> = core::range::range_i32(1, 4);
    let start: i32 = range.start();
    let direct_start: i32 = core::range::range_i32(1, 4).start();
    return start + direct_start;
}
"#
        .to_owned(),
    ];
    let joined = sources.concat();
    let texts = token_texts(&joined);
    let range_decl_token = struct_name_token(&texts, "Range");
    let range_i32_fn_token = fn_token(&texts, "range_i32");
    let range_i32_start_param = texts[range_i32_fn_token..]
        .windows(2)
        .position(|window| window[0] == "(" && window[1] == "start")
        .map(|index| range_i32_fn_token + index + 1)
        .expect("range_i32 start parameter token");
    let range_i32_end_param = texts[range_i32_fn_token..]
        .windows(2)
        .position(|window| window[0] == "," && window[1] == "end")
        .map(|index| range_i32_fn_token + index + 1)
        .expect("range_i32 end parameter token");
    let range_i32_start_value = texts[range_i32_fn_token..]
        .windows(3)
        .position(|window| window[0] == "start" && window[1] == ":" && window[2] == "start")
        .map(|index| range_i32_fn_token + index + 2)
        .expect("range_i32 start struct-literal value token");
    let range_i32_end_value = texts[range_i32_fn_token..]
        .windows(3)
        .position(|window| window[0] == "end" && window[1] == ":" && window[2] == "end")
        .map(|index| range_i32_fn_token + index + 2)
        .expect("range_i32 end struct-literal value token");
    let range_i32_call_token = last_call_name_token(&texts, "range_i32");
    let start_fn_token = fn_token(&texts, "start");
    let call_start_token = last_member_token(&texts, "range", "start");
    let direct_start_token = call_result_member_token(&texts, "start");
    let (qualified_type_head, qualified_type_leaf) = qualified_range_type_tokens(&texts);

    let snapshot = gpu_member_result_source_pack_snapshot(sources, texts.len());
    let decl_receiver_payload = snapshot.method_receiver_payload[start_fn_token];
    let call_receiver_payload = snapshot.method_call_receiver_payload[call_start_token];

    assert_eq!(
        snapshot.visible_decl[range_i32_start_value], range_i32_start_param as u32,
        "source-pack struct-literal start value should resolve to range_i32 parameter; value={} got={} expected={}",
        range_i32_start_value, snapshot.visible_decl[range_i32_start_value], range_i32_start_param,
    );
    assert_eq!(
        snapshot.visible_decl[range_i32_end_value], range_i32_end_param as u32,
        "source-pack struct-literal end value should resolve to range_i32 parameter; value={} got={} expected={}",
        range_i32_end_value, snapshot.visible_decl[range_i32_end_value], range_i32_end_param,
    );
    assert_eq!(
        snapshot_word(&snapshot.instance_decl_token, decl_receiver_payload),
        range_decl_token as u32,
        "method receiver instance should bind to the public Range declaration; fn={} payload={} tag={} state_decl={}",
        start_fn_token,
        decl_receiver_payload,
        snapshot.method_receiver_tag[start_fn_token],
        snapshot_word(&snapshot.instance_decl_token, decl_receiver_payload),
    );
    assert_eq!(
        snapshot.type_expr_ref_tag[qualified_type_leaf],
        3,
        "qualified generic type leaf should carry an instance ref; head={} head_ref={}:{} head_kind={} head_args={} leaf={} leaf_ref={}:{} leaf_kind={} leaf_args={} leaf_decl={}",
        qualified_type_head,
        snapshot.type_expr_ref_tag[qualified_type_head],
        snapshot.type_expr_ref_payload[qualified_type_head],
        snapshot.instance_kind[qualified_type_head],
        snapshot.instance_arg_count[qualified_type_head],
        qualified_type_leaf,
        snapshot.type_expr_ref_tag[qualified_type_leaf],
        snapshot.type_expr_ref_payload[qualified_type_leaf],
        snapshot.instance_kind[qualified_type_leaf],
        snapshot.instance_arg_count[qualified_type_leaf],
        snapshot_word(
            &snapshot.instance_decl_token,
            snapshot.type_expr_ref_payload[qualified_type_leaf],
        ),
    );
    assert_eq!(
        snapshot.instance_kind[qualified_type_leaf],
        1,
        "qualified generic type leaf should be a named instance; head_kind={} head_args={} leaf_kind={} leaf_args={}",
        snapshot.instance_kind[qualified_type_head],
        snapshot.instance_arg_count[qualified_type_head],
        snapshot.instance_kind[qualified_type_leaf],
        snapshot.instance_arg_count[qualified_type_leaf],
    );
    assert_eq!(
        snapshot_word(&snapshot.instance_decl_token, call_receiver_payload),
        range_decl_token as u32,
        "call receiver instance should bind to the same Range declaration; call={} payload={} tag={}",
        call_start_token,
        call_receiver_payload,
        snapshot.method_call_receiver_tag[call_start_token],
    );
    assert_eq!(
        snapshot.method_visibility[start_fn_token], 1,
        "imported method must be marked public from the parser method record"
    );
    assert_eq!(
        snapshot.method_decl_name_token[start_fn_token],
        (start_fn_token + 1) as u32,
        "method declaration should publish the parser-owned function name token"
    );
    assert_eq!(
        snapshot.method_call_name_id[call_start_token],
        snapshot.method_decl_name_id[start_fn_token],
        "call method name id should match declaration name id"
    );
    assert_eq!(
        snapshot.fn_return_ref_tag[start_fn_token], 1,
        "impl method return type should be projected from the parser-owned return type record"
    );
    assert_eq!(
        snapshot.fn_return_ref_payload[start_fn_token], 3,
        "Range<i32>.start return ref should resolve to scalar i32"
    );
    assert_eq!(
        snapshot.call_return_type[start_fn_token], 3,
        "impl method declaration should publish its scalar return type"
    );
    assert_eq!(
        snapshot.call_fn_index[call_start_token],
        start_fn_token as u32,
        "source-pack range.start() should resolve through the sorted method table; call_site_module={} decl_module={} key_status={} type_error={:?}",
        snapshot.method_call_site_module_id[call_start_token],
        snapshot.method_decl_module_id[start_fn_token],
        snapshot.method_key_status[start_fn_token],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.call_fn_index[range_i32_call_token], range_i32_fn_token as u32,
        "qualified range_i32 call should resolve before call-result method marking"
    );
    assert_eq!(
        snapshot_word(
            &snapshot.instance_decl_token,
            snapshot.fn_return_ref_payload[range_i32_fn_token],
        ),
        range_decl_token as u32,
        "range_i32 return ref should preserve the Range<i32> instance; tag={} payload={}",
        snapshot.fn_return_ref_tag[range_i32_fn_token],
        snapshot.fn_return_ref_payload[range_i32_fn_token],
    );
    assert_eq!(
        snapshot_word(
            &snapshot.instance_decl_token,
            snapshot.method_call_receiver_payload[direct_start_token],
        ),
        range_decl_token as u32,
        "call-result receiver should use the resolved callee return type ref; method_tag={} method_payload={}",
        snapshot.method_call_receiver_tag[direct_start_token],
        snapshot.method_call_receiver_payload[direct_start_token],
    );
    assert_eq!(
        snapshot.call_fn_index[direct_start_token], start_fn_token as u32,
        "source-pack range_i32(...).start() should resolve through the sorted method table; call_site_module={} type_error={:?}",
        snapshot.method_call_site_module_id[direct_start_token], snapshot.type_error,
    );
    assert_eq!(
        snapshot.call_return_type[direct_start_token], 3,
        "call-result method invocation should publish the method return type"
    );
    assert!(
        snapshot.type_error.is_none(),
        "source-pack method metadata should type-check: {:?}",
        snapshot.type_error
    );
}

#[test]
fn gpu_source_pack_generic_match_payloads_keep_generic_type_records() {
    let src = include_str!("../stdlib/core/option.lani");
    let texts = token_texts(src);
    let unwrap_fn_token = fn_token(&texts, "unwrap_or");
    let option_type_token = texts[unwrap_fn_token..]
        .windows(4)
        .position(|window| window[0] == "Option" && window[1] == "<" && window[2] == "T")
        .map(|index| unwrap_fn_token + index)
        .expect("unwrap_or Option<T> parameter type");
    let fallback_result_token = texts[unwrap_fn_token..]
        .windows(3)
        .position(|window| window[0] == "None" && window[1] == "->" && window[2] == "fallback")
        .map(|index| unwrap_fn_token + index + 2)
        .expect("unwrap_or fallback result token");
    let inner_result_token = texts[unwrap_fn_token..]
        .windows(3)
        .position(|window| window[0] == "Some" && window[1] == "(" && window[2] == "inner")
        .and_then(|pattern_index| {
            texts[unwrap_fn_token + pattern_index..]
                .windows(3)
                .position(|window| window[0] == "->" && window[1] == "inner")
                .map(|result_index| unwrap_fn_token + pattern_index + result_index + 1)
        })
        .expect("unwrap_or inner result token");
    let inner_binder_token = texts[unwrap_fn_token..]
        .windows(3)
        .position(|window| window[0] == "Some" && window[1] == "(" && window[2] == "inner")
        .map(|index| unwrap_fn_token + index + 2)
        .expect("unwrap_or inner pattern binder token");
    let match_token = texts[unwrap_fn_token..]
        .iter()
        .position(|text| text == "match")
        .map(|index| unwrap_fn_token + index)
        .expect("unwrap_or match token");

    let snapshot = gpu_member_result_source_pack_snapshot(vec![src.to_owned()], src.len());
    let option_instance = snapshot.type_expr_ref_payload[option_type_token] as usize;
    let option_arg_start = snapshot_word(&snapshot.instance_arg_start, option_instance as u32);
    let option_arg_tag = snapshot_word(&snapshot.instance_arg_ref_tag, option_arg_start);
    let option_arg_payload = snapshot_word(&snapshot.instance_arg_ref_payload, option_arg_start);

    assert_eq!(
        option_arg_tag,
        2,
        "Option<T> argument should stay a generic-param type ref; option_type={} instance={} arg_start={} arg_tag={} arg_payload={} type_error={:?}",
        option_type_token,
        option_instance,
        option_arg_start,
        option_arg_tag,
        option_arg_payload,
        snapshot.type_error,
    );
    assert!(
        snapshot.visible_type[inner_result_token] >= 8192,
        "match payload binder should carry a generic type, not a scalar; inner={} visible_type={} option_arg_payload={} type_error={:?}",
        inner_result_token,
        snapshot.visible_type[inner_result_token],
        option_arg_payload,
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.visible_decl[inner_result_token],
        inner_binder_token as u32,
        "match payload result use should resolve through the HIR visible-decl table; use={} decl={} expected={} type_error={:?}",
        inner_result_token,
        snapshot.visible_decl[inner_result_token],
        inner_binder_token,
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.call_return_type[match_token],
        snapshot.visible_type[inner_result_token],
        "match result type should be derived from HIR arm value records; match={} ret={} inner={} inner_ty={} fallback={} fallback_ty={} type_error={:?}",
        match_token,
        snapshot.call_return_type[match_token],
        inner_result_token,
        snapshot.visible_type[inner_result_token],
        fallback_result_token,
        snapshot.visible_type[fallback_result_token],
        snapshot.type_error,
    );
    assert!(
        snapshot.type_error.is_none(),
        "source-pack generic match fixture should type-check; match={} ret={} inner={} inner_ty={} fallback={} fallback_ty={} type_error={:?}",
        match_token,
        snapshot.call_return_type[match_token],
        inner_result_token,
        snapshot.visible_type[inner_result_token],
        fallback_result_token,
        snapshot.visible_type[fallback_result_token],
        snapshot.type_error,
    );
}

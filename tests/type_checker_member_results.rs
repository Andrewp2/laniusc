mod common;

use laniusc::{
    gpu::device,
    lexer::{driver::GpuLexer, test_cpu::lex_on_test_cpu},
    parser::{driver::GpuParser, tables::PrecomputedParseTables},
    type_checker::{GpuCodegenBuffers, GpuTypeCheckHirItemBuffers, GpuTypeChecker},
};

struct MemberResultReadbacks {
    name_id_by_token: wgpu::Buffer,
    tag: wgpu::Buffer,
    payload: wgpu::Buffer,
    ordinal: wgpu::Buffer,
    instance_kind: wgpu::Buffer,
    instance_decl_token: wgpu::Buffer,
    instance_arg_count: wgpu::Buffer,
    instance_len_kind: wgpu::Buffer,
    instance_len_payload: wgpu::Buffer,
    visible_decl: wgpu::Buffer,
    visible_type: wgpu::Buffer,
    call_return_type: wgpu::Buffer,
    call_fn_index: wgpu::Buffer,
    call_param_count: wgpu::Buffer,
    call_param_type: wgpu::Buffer,
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
    decl_type_ref_tag: wgpu::Buffer,
    decl_type_ref_payload: wgpu::Buffer,
    struct_init_field_expected_ref_tag: wgpu::Buffer,
    struct_init_field_expected_ref_payload: wgpu::Buffer,
    struct_init_field_ordinal: wgpu::Buffer,
}

struct MemberResultSnapshot {
    name_id_by_token: Vec<u32>,
    tag: Vec<u32>,
    payload: Vec<u32>,
    ordinal: Vec<u32>,
    instance_kind: Vec<u32>,
    instance_decl_token: Vec<u32>,
    instance_arg_count: Vec<u32>,
    instance_len_kind: Vec<u32>,
    instance_len_payload: Vec<u32>,
    visible_decl: Vec<u32>,
    visible_type: Vec<u32>,
    call_return_type: Vec<u32>,
    call_fn_index: Vec<u32>,
    call_param_count: Vec<u32>,
    call_param_type: Vec<u32>,
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
    decl_type_ref_tag: Vec<u32>,
    decl_type_ref_payload: Vec<u32>,
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

fn fn_token_after(texts: &[String], name: &str, after_token: usize) -> usize {
    texts[after_token..]
        .windows(2)
        .position(|window| window[0] == "fn" && window[1] == name)
        .map(|index| after_token + index)
        .unwrap_or_else(|| {
            panic!("missing function token fn {name} after {after_token}: {texts:?}")
        })
}

fn impl_token(texts: &[String], name: &str) -> usize {
    texts
        .windows(2)
        .position(|window| window[0] == "impl" && window[1] == name)
        .map(|index| index + 1)
        .unwrap_or_else(|| panic!("missing impl token impl {name}: {texts:?}"))
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

fn qualified_path_leaf_token(texts: &[String], segments: &[&str]) -> usize {
    texts
        .windows(segments.len() * 3 - 2)
        .position(|window| {
            segments.iter().enumerate().all(|(index, segment)| {
                let base = index * 3;
                if window[base] != *segment {
                    return false;
                }
                index + 1 == segments.len() || (window[base + 1] == ":" && window[base + 2] == ":")
            })
        })
        .map(|index| index + (segments.len() - 1) * 3)
        .unwrap_or_else(|| panic!("missing qualified path {segments:?}: {texts:?}"))
}

fn snapshot_word(words: &[u32], index: u32) -> u32 {
    words.get(index as usize).copied().unwrap_or(u32::MAX)
}

fn read_words(device: &wgpu::Device, buffer: &wgpu::Buffer, count: usize) -> Vec<u32> {
    let slice = buffer.slice(0..(count * 4) as u64);
    slice.map_async(wgpu::MapMode::Read, |_| {});
    let _ = device.poll(wgpu::PollType::wait_indefinitely());
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
    let name_id_by_token = mk("rb.test.name_id_by_token");
    let tag = mk("rb.test.member_result.tag");
    let payload = mk("rb.test.member_result.payload");
    let ordinal = mk("rb.test.member_result.ordinal");
    let instance_kind = mk("rb.test.type_instance.kind");
    let instance_decl_token = mk("rb.test.type_instance.decl_token");
    let instance_arg_count = mk("rb.test.type_instance.arg_count");
    let instance_len_kind = mk("rb.test.type_instance.len_kind");
    let instance_len_payload = mk("rb.test.type_instance.len_payload");
    let visible_decl = mk("rb.test.visible_decl");
    let visible_type = mk("rb.test.visible_type");
    let call_return_type = mk("rb.test.call_return_type");
    let call_fn_index = mk("rb.test.call_fn_index");
    let call_param_count = mk("rb.test.call_param_count");
    let call_param_type = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("rb.test.call_param_type"),
        size: size.saturating_mul(4),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let instance_arg_start = mk("rb.test.type_instance.arg_start");
    let mk_arg_ref = |label| {
        device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: size.saturating_mul(4),
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        })
    };
    let instance_arg_ref_tag = mk_arg_ref("rb.test.type_instance.arg_ref_tag");
    let instance_arg_ref_payload = mk_arg_ref("rb.test.type_instance.arg_ref_payload");
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
    let decl_type_ref_tag = mk("rb.test.decl_type_ref_tag");
    let decl_type_ref_payload = mk("rb.test.decl_type_ref_payload");
    let struct_init_field_expected_ref_tag = mk("rb.test.struct_init.expected_ref_tag");
    let struct_init_field_expected_ref_payload = mk("rb.test.struct_init.expected_ref_payload");
    let struct_init_field_ordinal = mk("rb.test.struct_init.ordinal");

    for (src, dst) in [
        (codegen.name_id_by_token, &name_id_by_token),
        (codegen.member_result_ref_tag, &tag),
        (codegen.member_result_ref_payload, &payload),
        (codegen.member_result_field_ordinal, &ordinal),
        (codegen.type_instance_kind, &instance_kind),
        (codegen.type_instance_decl_token, &instance_decl_token),
        (codegen.type_instance_arg_count, &instance_arg_count),
        (codegen.type_instance_len_kind, &instance_len_kind),
        (codegen.type_instance_len_payload, &instance_len_payload),
        (codegen.visible_decl, &visible_decl),
        (codegen.visible_type, &visible_type),
        (codegen.call_return_type, &call_return_type),
        (codegen.call_fn_index, &call_fn_index),
        (codegen.call_param_count, &call_param_count),
        (codegen.type_instance_arg_start, &instance_arg_start),
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
        (codegen.decl_type_ref_tag, &decl_type_ref_tag),
        (codegen.decl_type_ref_payload, &decl_type_ref_payload),
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
    encoder.copy_buffer_to_buffer(
        codegen.type_instance_arg_ref_tag,
        0,
        &instance_arg_ref_tag,
        0,
        size.saturating_mul(4),
    );
    encoder.copy_buffer_to_buffer(
        codegen.type_instance_arg_ref_payload,
        0,
        &instance_arg_ref_payload,
        0,
        size.saturating_mul(4),
    );
    encoder.copy_buffer_to_buffer(
        codegen.call_param_type,
        0,
        &call_param_type,
        0,
        size.saturating_mul(4),
    );

    MemberResultReadbacks {
        name_id_by_token,
        tag,
        payload,
        ordinal,
        instance_kind,
        instance_decl_token,
        instance_arg_count,
        instance_len_kind,
        instance_len_payload,
        visible_decl,
        visible_type,
        call_return_type,
        call_fn_index,
        call_param_count,
        call_param_type,
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
        decl_type_ref_tag,
        decl_type_ref_payload,
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
        name_id_by_token: read_words(device, &readbacks.name_id_by_token, count),
        tag: read_words(device, &readbacks.tag, count),
        payload: read_words(device, &readbacks.payload, count),
        ordinal: read_words(device, &readbacks.ordinal, count),
        instance_kind: read_words(device, &readbacks.instance_kind, count),
        instance_decl_token: read_words(device, &readbacks.instance_decl_token, count),
        instance_arg_count: read_words(device, &readbacks.instance_arg_count, count),
        instance_len_kind: read_words(device, &readbacks.instance_len_kind, count),
        instance_len_payload: read_words(device, &readbacks.instance_len_payload, count),
        visible_decl: read_words(device, &readbacks.visible_decl, count),
        visible_type: read_words(device, &readbacks.visible_type, count),
        call_return_type: read_words(device, &readbacks.call_return_type, count),
        call_fn_index: read_words(device, &readbacks.call_fn_index, count),
        call_param_count: read_words(device, &readbacks.call_param_count, count),
        call_param_type: read_words(device, &readbacks.call_param_type, count * 4),
        instance_arg_start: read_words(device, &readbacks.instance_arg_start, count),
        instance_arg_ref_tag: read_words(device, &readbacks.instance_arg_ref_tag, count * 4),
        instance_arg_ref_payload: read_words(
            device,
            &readbacks.instance_arg_ref_payload,
            count * 4,
        ),
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
        decl_type_ref_tag: read_words(device, &readbacks.decl_type_ref_tag, count),
        decl_type_ref_payload: read_words(device, &readbacks.decl_type_ref_payload, count),
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
fn gpu_member_result_records_same_module_qualified_param_fields() {
    let src = r#"
module app::main;

struct Point {
    x: i32,
}

fn x_of(point: app::main::Point) -> i32 {
    return point.x;
}

fn main() {
    return 0;
}
"#;
    let texts = token_texts(src);
    let point_decl_token = struct_name_token(&texts, "Point");
    let point_param_token = texts
        .windows(2)
        .position(|window| window[0] == "(" && window[1] == "point")
        .map(|index| index + 1)
        .expect("point parameter token");
    let qualified_point_leaf = qualified_path_leaf_token(&texts, &["app", "main", "Point"]);
    let qualified_point_head = qualified_point_leaf - 6;
    let member_x_token = member_token(&texts, "point", "x");
    let x_of_fn_token = fn_token(&texts, "x_of");

    let snapshot = gpu_member_result_snapshot(src, texts.len());
    let expected_point_type = 4096 + point_decl_token as u32;

    assert_eq!(
        snapshot.type_expr_ref_payload[qualified_point_head],
        expected_point_type,
        "qualified same-module type head should resolve to the struct declaration; head={} head_ref={}:{} leaf={} leaf_ref={}:{} expected={} decl_token={} param_visible={} fn_ret_ref={}:{} fn_ret={} member_tag={} member_payload={} member_ordinal={} type_error={:?}",
        qualified_point_head,
        snapshot.type_expr_ref_tag[qualified_point_head],
        snapshot.type_expr_ref_payload[qualified_point_head],
        qualified_point_leaf,
        snapshot.type_expr_ref_tag[qualified_point_leaf],
        snapshot.type_expr_ref_payload[qualified_point_leaf],
        expected_point_type,
        point_decl_token,
        snapshot.visible_type[point_param_token],
        snapshot.fn_return_ref_tag[x_of_fn_token],
        snapshot.fn_return_ref_payload[x_of_fn_token],
        snapshot.call_return_type[x_of_fn_token],
        snapshot.tag[member_x_token],
        snapshot.payload[member_x_token],
        snapshot.ordinal[member_x_token],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.visible_type[point_param_token], expected_point_type,
        "qualified parameter type should publish a visible struct type"
    );
    assert_eq!(
        snapshot.call_return_type[x_of_fn_token],
        3,
        "x_of function declaration should publish its i32 return type; fn_ret_ref={}:{} type_error={:?}",
        snapshot.fn_return_ref_tag[x_of_fn_token],
        snapshot.fn_return_ref_payload[x_of_fn_token],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.ordinal[member_x_token], 0,
        "point.x should project field ordinal 0"
    );
    assert_eq!(
        snapshot.visible_type[member_x_token], 3,
        "point.x should publish i32 as the visible member type"
    );
    assert!(
        snapshot.type_error.is_none(),
        "type checker rejected same-module qualified member fixture: {:?}",
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
fn gpu_call_records_resolve_zero_arg_direct_calls_from_hir_call_records() {
    let src = r#"
fn value() -> i32 {
    return 7;
}

fn main() {
    return value();
}
"#;
    let texts = token_texts(src);
    let value_fn_token = fn_token(&texts, "value");
    let value_call_token = last_call_name_token(&texts, "value");

    let snapshot = gpu_member_result_snapshot(src, texts.len());

    assert_eq!(
        snapshot.name_id_by_token[value_fn_token + 1],
        snapshot.name_id_by_token[value_call_token],
        "name interning should assign duplicate identifier lexemes the same semantic name id"
    );
    assert_eq!(
        snapshot.call_return_type[value_fn_token],
        3,
        "zero-arg function declaration should publish its return type; fn={} call={} fn_index_at_fn={} fn_name_id={} call_name_id={}",
        value_fn_token,
        value_call_token,
        snapshot.call_fn_index[value_fn_token],
        snapshot.name_id_by_token[value_fn_token + 1],
        snapshot.name_id_by_token[value_call_token],
    );
    assert_eq!(
        snapshot.call_fn_index[value_call_token],
        value_fn_token as u32,
        "zero-arg direct calls should resolve through parser-owned HIR call records; call={} fn={} return_ty={} fn_name_id={} call_name_id={} visible_decl={} type_error={:?}",
        value_call_token,
        value_fn_token,
        snapshot.call_return_type[value_call_token],
        snapshot.name_id_by_token[value_fn_token + 1],
        snapshot.name_id_by_token[value_call_token],
        snapshot.visible_decl[value_call_token],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.call_return_type[value_call_token], 3,
        "zero-arg direct call should publish the callee return type"
    );
    assert!(
        snapshot.type_error.is_none(),
        "type checker rejected zero-arg direct call fixture: {:?}",
        snapshot.type_error
    );
}

#[test]
fn gpu_source_pack_constant_paths_publish_visible_decl_records() {
    let sources = vec![
        r#"
module core::limits;

pub const MIN: i32 = -2147483648;
"#
        .to_owned(),
        r#"
module app::main;

import core::limits;

fn main() {
    let imported: i32 = MIN;
    let qualified: i32 = core::limits::MIN;
    return imported + qualified;
}
"#
        .to_owned(),
    ];
    let joined = sources.concat();
    let texts = token_texts(&joined);
    let const_min_token = texts
        .windows(3)
        .position(|window| window[0] == "const" && window[1] == "MIN" && window[2] == ":")
        .map(|index| index + 1)
        .expect("core::limits MIN declaration token");
    let imported_min_token = texts
        .windows(4)
        .position(|window| {
            window[0] == ":" && window[1] == "i32" && window[2] == "=" && window[3] == "MIN"
        })
        .map(|index| index + 3)
        .expect("imported MIN use token");
    let qualified_min_head = texts
        .windows(7)
        .position(|window| {
            window[0] == "core"
                && window[1] == ":"
                && window[2] == ":"
                && window[3] == "limits"
                && window[4] == ":"
                && window[5] == ":"
                && window[6] == "MIN"
        })
        .expect("qualified core::limits::MIN path head");

    let snapshot = gpu_member_result_source_pack_snapshot(sources, texts.len());

    assert_eq!(
        snapshot.visible_decl[imported_min_token],
        const_min_token as u32,
        "imported one-segment const should resolve through source-pack visibility records; use={} decl={} expected={} type_error={:?}",
        imported_min_token,
        snapshot.visible_decl[imported_min_token],
        const_min_token,
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.visible_type[imported_min_token], 3,
        "imported one-segment const should publish i32 visible_type"
    );
    assert_eq!(
        snapshot.visible_decl[qualified_min_head],
        const_min_token as u32,
        "qualified const path head should consume resolver records; head={} decl={} expected={} type_error={:?}",
        qualified_min_head,
        snapshot.visible_decl[qualified_min_head],
        const_min_token,
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.visible_type[qualified_min_head], 3,
        "qualified const path head should publish i32 visible_type"
    );
    assert!(
        snapshot.type_error.is_none(),
        "source-pack const path fixture should type-check: {:?}",
        snapshot.type_error
    );
}

#[test]
fn gpu_source_pack_unit_enum_variants_publish_visible_decl_records() {
    let sources = vec![
        include_str!("../stdlib/core/ordering.lani").to_owned(),
        r#"
module app::main;

import core::ordering;

fn main() {
    let less: core::ordering::Ordering = core::ordering::Less;
    return 0;
}
"#
        .to_owned(),
    ];
    let joined = sources.concat();
    let texts = token_texts(&joined);
    let ordering_enum_token = texts
        .windows(2)
        .position(|window| window[0] == "enum" && window[1] == "Ordering")
        .map(|index| index + 1)
        .expect("Ordering enum declaration token");
    let less_variant_token = texts
        .windows(2)
        .position(|window| window[0] == "Ordering" && window[1] == "{")
        .and_then(|enum_index| {
            texts[enum_index..]
                .iter()
                .position(|text| text == "Less")
                .map(|variant_index| enum_index + variant_index)
        })
        .expect("Ordering::Less variant token");
    let local_less_return_token = texts
        .windows(2)
        .position(|window| window[0] == "return" && window[1] == "Less")
        .map(|index| index + 1)
        .expect("local Less return token");
    let qualified_less_head = texts
        .windows(7)
        .position(|window| {
            window[0] == "core"
                && window[1] == ":"
                && window[2] == ":"
                && window[3] == "ordering"
                && window[4] == ":"
                && window[5] == ":"
                && window[6] == "Less"
        })
        .expect("qualified core::ordering::Less path head");
    let ordering_type = 6144 + ordering_enum_token as u32;

    let snapshot = gpu_member_result_source_pack_snapshot(sources, texts.len());

    assert_eq!(
        snapshot.visible_decl[local_less_return_token],
        less_variant_token as u32,
        "local unit enum variant should resolve to its variant declaration; use={} decl={} expected={} type_error={:?}",
        local_less_return_token,
        snapshot.visible_decl[local_less_return_token],
        less_variant_token,
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.visible_type[local_less_return_token], ordering_type,
        "local unit enum variant should publish the parent enum type"
    );
    assert_eq!(
        snapshot.visible_decl[qualified_less_head],
        less_variant_token as u32,
        "qualified unit enum variant path head should consume resolver records; head={} decl={} expected={} type_error={:?}",
        qualified_less_head,
        snapshot.visible_decl[qualified_less_head],
        less_variant_token,
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.visible_type[qualified_less_head], ordering_type,
        "qualified unit enum variant path head should publish the parent enum type"
    );
    assert!(
        snapshot.type_error.is_none(),
        "source-pack unit enum variant fixture should type-check: {:?}",
        snapshot.type_error
    );
}

#[test]
fn gpu_call_records_infer_generic_array_element_returns_from_decl_refs() {
    let src = r#"
fn first<T, const N: usize>(values: [T; N]) -> T {
    return values[0];
}

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let value: i32 = first(values);
    return value;
}
"#;
    let texts = token_texts(src);
    let first_fn_token = fn_token(&texts, "first");
    let first_call_token = last_call_name_token(&texts, "first");
    let first_arg_token = first_call_token + 2;

    let snapshot = gpu_member_result_snapshot(src, texts.len());
    let first_arg_decl = snapshot.visible_decl[first_arg_token] as usize;
    let (arg_decl_tag, arg_decl_payload) = if first_arg_decl < snapshot.decl_type_ref_tag.len() {
        (
            snapshot.decl_type_ref_tag[first_arg_decl],
            snapshot.decl_type_ref_payload[first_arg_decl],
        )
    } else {
        (u32::MAX, u32::MAX)
    };

    assert_eq!(
        snapshot.call_fn_index[first_call_token], first_fn_token as u32,
        "generic array helper call should resolve through HIR call records"
    );
    assert_eq!(
        snapshot.call_return_type[first_call_token],
        3,
        "generic array helper call should infer T=i32 from the argument declaration type refs; fn={} fn_ret={} fn_ret_ref=({}, {}) call={} call_ret={} fn_param_count={} fn_param0={} arg_token={} visible_decl={} decl_ref=({}, {})",
        first_fn_token,
        snapshot.call_return_type[first_fn_token],
        snapshot.fn_return_ref_tag[first_fn_token],
        snapshot.fn_return_ref_payload[first_fn_token],
        first_call_token,
        snapshot.call_return_type[first_call_token],
        snapshot.call_param_count[first_fn_token],
        snapshot.call_param_type[first_fn_token * 4],
        first_arg_token,
        snapshot.visible_decl[first_arg_token],
        arg_decl_tag,
        arg_decl_payload,
    );
    assert!(
        snapshot.type_error.is_none(),
        "type checker rejected generic array helper call fixture: {:?}",
        snapshot.type_error
    );
}

#[test]
fn gpu_array_return_records_accept_generic_identifier_returns_from_type_refs() {
    let src = r#"
fn copy<T, const N: usize>(values: [T; N]) -> [T; N] {
    return values;
}

fn main() {
    return 0;
}
"#;
    let texts = token_texts(src);
    let copy_fn_token = fn_token(&texts, "copy");
    let values_param_token = texts
        .windows(3)
        .position(|window| window[0] == "values" && window[1] == ":" && window[2] == "[")
        .expect("values parameter token");
    let return_token = texts
        .iter()
        .position(|text| text == "return")
        .expect("return token");

    let snapshot = gpu_member_result_snapshot(src, texts.len());

    assert_eq!(
        snapshot.fn_return_ref_tag[copy_fn_token],
        3,
        "generic array return signature should publish an instance ref; fn={} tag={} payload={} type_error={:?}",
        copy_fn_token,
        snapshot.fn_return_ref_tag[copy_fn_token],
        snapshot.fn_return_ref_payload[copy_fn_token],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.decl_type_ref_tag[values_param_token],
        3,
        "generic array parameter should publish an instance ref; param={} tag={} payload={} visible_type={} type_error={:?}",
        values_param_token,
        snapshot.decl_type_ref_tag[values_param_token],
        snapshot.decl_type_ref_payload[values_param_token],
        snapshot.visible_type[values_param_token],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.call_return_type[return_token],
        0xfffffffe,
        "generic array identifier return should be accepted by the array-return record pass; return={} fn_ref=({}, {}) decl_ref=({}, {}) type_error={:?}",
        return_token,
        snapshot.fn_return_ref_tag[copy_fn_token],
        snapshot.fn_return_ref_payload[copy_fn_token],
        snapshot.decl_type_ref_tag[values_param_token],
        snapshot.decl_type_ref_payload[values_param_token],
        snapshot.type_error,
    );
    assert!(
        snapshot.type_error.is_none(),
        "type checker rejected generic array identifier return fixture: {:?}",
        snapshot.type_error
    );
}

#[test]
fn gpu_call_records_infer_generic_array_call_results_from_decl_refs() {
    let src = r#"
fn copy<T, const N: usize>(values: [T; N]) -> [T; N] {
    return values;
}

fn main() {
    let values: [i32; 4] = [3, 1, 4, 1];
    let copied: [i32; 4] = copy(values);
    return copied[0];
}
"#;
    let texts = token_texts(src);
    let copy_fn_token = fn_token(&texts, "copy");
    let copy_call_token = last_call_name_token(&texts, "copy");
    let copy_arg_token = copy_call_token + 2;

    let snapshot = gpu_member_result_snapshot(src, texts.len());
    let arg_decl = snapshot.visible_decl[copy_arg_token] as usize;
    let (arg_decl_tag, arg_decl_payload) = if arg_decl < snapshot.decl_type_ref_tag.len() {
        (
            snapshot.decl_type_ref_tag[arg_decl],
            snapshot.decl_type_ref_payload[arg_decl],
        )
    } else {
        (u32::MAX, u32::MAX)
    };

    assert_eq!(
        snapshot.call_fn_index[copy_call_token], copy_fn_token as u32,
        "generic array copy call should resolve through HIR call records"
    );
    assert_eq!(
        snapshot.call_return_type[copy_call_token],
        128 + 3,
        "generic array copy call should infer [i32; _] from the declaration-backed array argument; call={} arg={} visible_decl={} decl_ref=({}, {}) type_error={:?}",
        copy_call_token,
        copy_arg_token,
        snapshot.visible_decl[copy_arg_token],
        arg_decl_tag,
        arg_decl_payload,
        snapshot.type_error,
    );
    assert!(
        snapshot.type_error.is_none(),
        "type checker rejected generic array copy call fixture: {:?}",
        snapshot.type_error
    );
}

#[test]
fn gpu_array_return_records_accept_generic_array_call_returns_from_type_refs() {
    let src = r#"
fn copy<T, const N: usize>(values: [T; N]) -> [T; N] {
    return values;
}

fn copy_i32(values: [i32; 4]) -> [i32; 4] {
    return copy(values);
}

fn main() {
    return 0;
}
"#;
    let texts = token_texts(src);
    let copy_call_token = last_call_name_token(&texts, "copy");
    let return_token = texts
        .windows(2)
        .position(|window| window[0] == "return" && window[1] == "copy")
        .expect("return copy token");

    let snapshot = gpu_member_result_snapshot(src, texts.len());

    assert_eq!(
        snapshot.call_return_type[copy_call_token],
        128 + 3,
        "generic array copy call should infer the concrete array element type before return validation; call={} return_token={} type_error={:?}",
        copy_call_token,
        return_token,
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.call_return_type[return_token],
        0xfffffffe,
        "array-return pass should accept returning the declaration-backed generic array call result; return={} call={} call_ty={} type_error={:?}",
        return_token,
        copy_call_token,
        snapshot.call_return_type[copy_call_token],
        snapshot.type_error,
    );
    assert!(
        snapshot.type_error.is_none(),
        "type checker rejected generic array call return fixture: {:?}",
        snapshot.type_error
    );
}

#[test]
fn gpu_array_return_records_reject_mismatched_generic_array_call_lengths() {
    let src = r#"
fn copy<T, const N: usize>(values: [T; N]) -> [T; N] {
    return values;
}

fn copy_wrong(values: [i32; 4]) -> [i32; 5] {
    return copy(values);
}

fn main() {
    return 0;
}
"#;
    let texts = token_texts(src);
    let copy_wrong_fn_token = fn_token(&texts, "copy_wrong");
    let copy_call_token = last_call_name_token(&texts, "copy");
    let copy_arg_token = copy_call_token + 2;
    let return_token = texts
        .windows(2)
        .position(|window| window[0] == "return" && window[1] == "copy")
        .expect("return copy token");

    let snapshot = gpu_member_result_snapshot(src, texts.len());
    let fn_ret_instance = snapshot.fn_return_ref_payload[copy_wrong_fn_token] as usize;
    let actual_decl = snapshot.visible_decl[copy_arg_token] as usize;
    let actual_instance = snapshot
        .decl_type_ref_payload
        .get(actual_decl)
        .copied()
        .unwrap_or(u32::MAX) as usize;

    assert!(
        snapshot.type_error.is_some(),
        "mismatched array call return should reject; return={} return_marker={} call={} call_ty={} arg={} visible_decl={} actual_ref=({}, {}) actual_len=({}, {}) fn_ref=({}, {}) fn_len=({}, {})",
        return_token,
        snapshot.call_return_type[return_token],
        copy_call_token,
        snapshot.call_return_type[copy_call_token],
        copy_arg_token,
        snapshot.visible_decl[copy_arg_token],
        snapshot
            .decl_type_ref_tag
            .get(actual_decl)
            .copied()
            .unwrap_or(u32::MAX),
        snapshot
            .decl_type_ref_payload
            .get(actual_decl)
            .copied()
            .unwrap_or(u32::MAX),
        snapshot
            .instance_len_kind
            .get(actual_instance)
            .copied()
            .unwrap_or(u32::MAX),
        snapshot
            .instance_len_payload
            .get(actual_instance)
            .copied()
            .unwrap_or(u32::MAX),
        snapshot.fn_return_ref_tag[copy_wrong_fn_token],
        snapshot.fn_return_ref_payload[copy_wrong_fn_token],
        snapshot
            .instance_len_kind
            .get(fn_ret_instance)
            .copied()
            .unwrap_or(u32::MAX),
        snapshot
            .instance_len_payload
            .get(fn_ret_instance)
            .copied()
            .unwrap_or(u32::MAX),
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
fn gpu_member_result_records_source_pack_public_range_inclusive_methods() {
    let sources = vec![
        include_str!("../stdlib/core/range.lani").to_owned(),
        r#"
module app::main;

import core::range;

fn main() {
    let range: core::range::RangeInclusive<i32> = core::range::range_inclusive_i32(1, 4);
    let end: i32 = range.end();
    let local_empty: bool = range.is_empty();
    let direct_contains: bool = core::range::range_inclusive_i32(1, 4).contains(4);
    let direct_empty: bool = core::range::range_inclusive_i32(5, 4).is_empty();
    if (direct_contains && !local_empty && !direct_empty) {
        return end;
    }
    return range.start();
}
"#
        .to_owned(),
    ];
    let joined = sources.concat();
    let texts = token_texts(&joined);
    let range_inclusive_decl_token = struct_name_token(&texts, "RangeInclusive");
    let range_inclusive_impl_token = impl_token(&texts, "RangeInclusive");
    let range_inclusive_fn_token = fn_token(&texts, "range_inclusive_i32");
    let end_fn_token = fn_token_after(&texts, "end", range_inclusive_impl_token);
    let is_empty_fn_token = fn_token_after(&texts, "is_empty", range_inclusive_impl_token);
    let contains_fn_token = fn_token_after(&texts, "contains", range_inclusive_impl_token);
    let range_end_call_token = last_member_token(&texts, "range", "end");
    let local_empty_token = last_member_token(&texts, "range", "is_empty");
    let direct_contains_token = call_result_member_token(&texts, "contains");
    let direct_empty_token = call_result_member_token(&texts, "is_empty");
    let direct_constructor_call_token = last_call_name_token(&texts, "range_inclusive_i32");

    let snapshot = gpu_member_result_source_pack_snapshot(sources, texts.len());
    let decl_receiver_payload = snapshot.method_receiver_payload[end_fn_token];
    let local_call_receiver_payload = snapshot.method_call_receiver_payload[range_end_call_token];
    let direct_call_receiver_payload = snapshot.method_call_receiver_payload[direct_contains_token];

    assert_eq!(
        snapshot_word(&snapshot.instance_decl_token, decl_receiver_payload),
        range_inclusive_decl_token as u32,
        "RangeInclusive<i32>.end declaration should publish a receiver instance for RangeInclusive; fn={} payload={} tag={} state_decl={}",
        end_fn_token,
        decl_receiver_payload,
        snapshot.method_receiver_tag[end_fn_token],
        snapshot_word(&snapshot.instance_decl_token, decl_receiver_payload),
    );
    assert_eq!(
        snapshot_word(&snapshot.instance_decl_token, local_call_receiver_payload),
        range_inclusive_decl_token as u32,
        "range.end() should consume the annotated RangeInclusive receiver type ref; call={} payload={} tag={}",
        range_end_call_token,
        local_call_receiver_payload,
        snapshot.method_call_receiver_tag[range_end_call_token],
    );
    assert_eq!(
        snapshot.call_fn_index[range_end_call_token],
        end_fn_token as u32,
        "source-pack range.end() should resolve through the sorted RangeInclusive method table; call_site_module={} decl_module={} key_status={} type_error={:?}",
        snapshot.method_call_site_module_id[range_end_call_token],
        snapshot.method_decl_module_id[end_fn_token],
        snapshot.method_key_status[end_fn_token],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.call_fn_index[direct_constructor_call_token], range_inclusive_fn_token as u32,
        "qualified range_inclusive_i32 call should resolve before call-result method marking"
    );
    assert_eq!(
        snapshot_word(
            &snapshot.instance_decl_token,
            snapshot.fn_return_ref_payload[range_inclusive_fn_token],
        ),
        range_inclusive_decl_token as u32,
        "range_inclusive_i32 return ref should preserve the RangeInclusive<i32> instance; tag={} payload={}",
        snapshot.fn_return_ref_tag[range_inclusive_fn_token],
        snapshot.fn_return_ref_payload[range_inclusive_fn_token],
    );
    assert_eq!(
        snapshot_word(&snapshot.instance_decl_token, direct_call_receiver_payload),
        range_inclusive_decl_token as u32,
        "call-result contains receiver should use the resolved RangeInclusive return ref; method_tag={} method_payload={}",
        snapshot.method_call_receiver_tag[direct_contains_token],
        direct_call_receiver_payload,
    );
    assert_eq!(
        snapshot.call_fn_index[direct_contains_token], contains_fn_token as u32,
        "source-pack range_inclusive_i32(...).contains() should resolve through the sorted method table; call_site_module={} type_error={:?}",
        snapshot.method_call_site_module_id[direct_contains_token], snapshot.type_error,
    );
    assert_eq!(
        snapshot.call_fn_index[local_empty_token], is_empty_fn_token as u32,
        "source-pack range.is_empty() should resolve through the sorted RangeInclusive method table; call_site_module={} type_error={:?}",
        snapshot.method_call_site_module_id[local_empty_token], snapshot.type_error,
    );
    assert_eq!(
        snapshot.call_fn_index[direct_empty_token], is_empty_fn_token as u32,
        "source-pack range_inclusive_i32(...).is_empty() should resolve through the sorted method table; call_site_module={} type_error={:?}",
        snapshot.method_call_site_module_id[direct_empty_token], snapshot.type_error,
    );
    assert_eq!(
        snapshot.call_return_type[range_end_call_token], 3,
        "RangeInclusive<i32>.end call should publish i32"
    );
    assert_eq!(
        snapshot.call_return_type[direct_contains_token], 2,
        "RangeInclusive<i32>.contains call should publish bool"
    );
    assert_eq!(
        snapshot.call_return_type[local_empty_token], 2,
        "RangeInclusive<i32>.is_empty local receiver call should publish bool"
    );
    assert_eq!(
        snapshot.call_return_type[direct_empty_token], 2,
        "RangeInclusive<i32>.is_empty call-result receiver call should publish bool"
    );
    assert!(
        snapshot.type_error.is_none(),
        "source-pack RangeInclusive method metadata should type-check: {:?}",
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

#[test]
fn gpu_source_pack_generic_match_payloads_survive_neighbor_modules() {
    let sources = vec![
        include_str!("../stdlib/core/option.lani").to_owned(),
        include_str!("../stdlib/core/result.lani").to_owned(),
        include_str!("../sample_programs/option_result_helpers.lani").to_owned(),
    ];
    let joined = sources.concat();
    let texts = token_texts(&joined);
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

    let snapshot = gpu_member_result_source_pack_snapshot(sources, texts.len());
    let option_instance = snapshot.type_expr_ref_payload[option_type_token] as usize;
    let option_arg_start = snapshot_word(&snapshot.instance_arg_start, option_instance as u32);
    let option_arg_tag = snapshot_word(&snapshot.instance_arg_ref_tag, option_arg_start);
    let option_arg_payload = snapshot_word(&snapshot.instance_arg_ref_payload, option_arg_start);

    assert_eq!(
        option_arg_tag,
        2,
        "Option<T> argument should stay a generic-param type ref across neighboring source modules; option_type={} instance={} arg_start={} arg_tag={} arg_payload={} type_error={:?}",
        option_type_token,
        option_instance,
        option_arg_start,
        option_arg_tag,
        option_arg_payload,
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.visible_decl[inner_result_token],
        inner_binder_token as u32,
        "match payload result use should resolve to its arm-local binder in a multi-file source pack; use={} decl={} expected={} type_error={:?}",
        inner_result_token,
        snapshot.visible_decl[inner_result_token],
        inner_binder_token,
        snapshot.type_error,
    );
    assert!(
        snapshot.visible_type[inner_result_token] >= 8192,
        "match payload result use should keep the generic payload type in a multi-file source pack; inner={} visible_type={} binder={} binder_ty={} option_arg_payload={} fallback={} fallback_ty={} match_ret={} type_error={:?}",
        inner_result_token,
        snapshot.visible_type[inner_result_token],
        inner_binder_token,
        snapshot.visible_type[inner_binder_token],
        option_arg_payload,
        fallback_result_token,
        snapshot.visible_type[fallback_result_token],
        snapshot.call_return_type[match_token],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.call_return_type[match_token],
        snapshot.visible_type[inner_result_token],
        "match result type should be derived from HIR arm value records in the multi-file source pack; match={} ret={} inner={} inner_ty={} fallback={} fallback_ty={} type_error={:?}",
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
        "multi-file source-pack generic match fixture should type-check; match={} ret={} inner={} inner_ty={} fallback={} fallback_ty={} type_error={:?}",
        match_token,
        snapshot.call_return_type[match_token],
        inner_result_token,
        snapshot.visible_type[inner_result_token],
        fallback_result_token,
        snapshot.visible_type[fallback_result_token],
        snapshot.type_error,
    );
}

#[test]
fn gpu_source_pack_qualified_generic_calls_bind_type_instance_args() {
    let sources = vec![
        include_str!("../stdlib/core/option.lani").to_owned(),
        r#"
module app::main;

import core::option;

fn main() {
    let value: core::option::Option<i32> = core::option::Some(1);
    let fallback: i32 = 2;
    let output: i32 = core::option::unwrap_or(value, fallback);
    return output;
}
"#
        .to_owned(),
    ];
    let joined = sources.concat();
    let texts = token_texts(&joined);
    let unwrap_fn_token = fn_token(&texts, "unwrap_or");
    let unwrap_call_head = texts
        .windows(8)
        .enumerate()
        .filter(|(_, window)| {
            window[0] == "core"
                && window[1] == ":"
                && window[2] == ":"
                && window[3] == "option"
                && window[4] == ":"
                && window[5] == ":"
                && window[6] == "unwrap_or"
                && window[7] == "("
        })
        .map(|(index, _)| index)
        .last()
        .expect("qualified core::option::unwrap_or call");
    let unwrap_call_leaf = unwrap_call_head + 6;
    let unwrap_value_arg = unwrap_call_leaf + 2;
    let unwrap_fallback_arg = unwrap_call_leaf + 4;
    let unwrap_value_param = texts[unwrap_fn_token..]
        .windows(3)
        .position(|window| window[0] == "(" && window[1] == "value" && window[2] == ":")
        .map(|index| unwrap_fn_token + index + 1)
        .expect("unwrap_or value parameter token");
    let unwrap_fallback_param = texts[unwrap_fn_token..]
        .windows(3)
        .position(|window| window[0] == "," && window[1] == "fallback" && window[2] == ":")
        .map(|index| unwrap_fn_token + index + 1)
        .expect("unwrap_or fallback parameter token");
    let value_decl = texts
        .windows(3)
        .enumerate()
        .filter(|(_, window)| window[0] == "let" && window[1] == "value" && window[2] == ":")
        .map(|(index, _)| index + 1)
        .last()
        .expect("app value declaration token");
    let fallback_decl = texts
        .windows(3)
        .enumerate()
        .filter(|(_, window)| window[0] == "let" && window[1] == "fallback" && window[2] == ":")
        .map(|(index, _)| index + 1)
        .last()
        .expect("app fallback declaration token");

    let snapshot = gpu_member_result_source_pack_snapshot(sources, texts.len());
    let option_instance = snapshot.decl_type_ref_payload[value_decl] as usize;
    let option_arg_start = snapshot_word(&snapshot.instance_arg_start, option_instance as u32);

    assert_eq!(
        snapshot.call_fn_index[unwrap_call_head],
        unwrap_fn_token as u32,
        "qualified unwrap_or call should resolve through source-pack value records; call={} fn={} got={} type_error={:?}",
        unwrap_call_head,
        unwrap_fn_token,
        snapshot.call_fn_index[unwrap_call_head],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.decl_type_ref_tag[value_decl],
        3,
        "annotated Option<i32> local should publish a type-instance ref; token={} tag={} payload={} type_error={:?}",
        value_decl,
        snapshot.decl_type_ref_tag[value_decl],
        snapshot.decl_type_ref_payload[value_decl],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot_word(&snapshot.instance_arg_ref_tag, option_arg_start),
        1,
        "qualified call generic binding should consume the concrete Option<i32> instance argument records; instance={} arg_start={} arg_tag={} arg_payload={} type_error={:?}",
        option_instance,
        option_arg_start,
        snapshot_word(&snapshot.instance_arg_ref_tag, option_arg_start),
        snapshot_word(&snapshot.instance_arg_ref_payload, option_arg_start),
        snapshot.type_error,
    );
    assert_eq!(
        snapshot_word(&snapshot.instance_arg_ref_payload, option_arg_start),
        3,
        "Option<i32> instance argument should carry scalar i32 for qualified call inference"
    );
    assert_eq!(
        snapshot.decl_type_ref_tag[unwrap_value_param],
        3,
        "unwrap_or value parameter should publish Option<T> instance ref; param={} tag={} payload={} call_param0={} fallback_param_ref={}:{} type_error={:?}",
        unwrap_value_param,
        snapshot.decl_type_ref_tag[unwrap_value_param],
        snapshot.decl_type_ref_payload[unwrap_value_param],
        snapshot.call_param_type[unwrap_fn_token * 4],
        snapshot.decl_type_ref_tag[unwrap_fallback_param],
        snapshot.decl_type_ref_payload[unwrap_fallback_param],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.call_return_type[unwrap_call_head],
        3,
        "qualified generic unwrap_or call should publish i32 after binding T from call argument records; call={} call_ret={} fn={} fn_ret={} fn_ret_ref={}:{} value_arg={} value_arg_visible={} fallback_arg={} fallback_arg_visible={} value_decl={} value_visible={} value_ref={}:{} fallback_decl={} fallback_visible={} fallback_ref={}:{} option_instance={} arg_start={} arg_ref={}:{} type_error={:?}",
        unwrap_call_head,
        snapshot.call_return_type[unwrap_call_head],
        unwrap_fn_token,
        snapshot.call_return_type[unwrap_fn_token],
        snapshot.fn_return_ref_tag[unwrap_fn_token],
        snapshot.fn_return_ref_payload[unwrap_fn_token],
        unwrap_value_arg,
        snapshot.visible_decl[unwrap_value_arg],
        unwrap_fallback_arg,
        snapshot.visible_decl[unwrap_fallback_arg],
        value_decl,
        snapshot.visible_decl[value_decl],
        snapshot.decl_type_ref_tag[value_decl],
        snapshot.decl_type_ref_payload[value_decl],
        fallback_decl,
        snapshot.visible_decl[fallback_decl],
        snapshot.decl_type_ref_tag[fallback_decl],
        snapshot.decl_type_ref_payload[fallback_decl],
        option_instance,
        option_arg_start,
        snapshot_word(&snapshot.instance_arg_ref_tag, option_arg_start),
        snapshot_word(&snapshot.instance_arg_ref_payload, option_arg_start),
        snapshot.type_error,
    );
    assert!(
        snapshot.type_error.is_none(),
        "qualified generic call fixture should type-check: {:?}",
        snapshot.type_error
    );
}

#[test]
fn gpu_source_pack_qualified_result_call_binds_all_type_instance_args() {
    let sources = vec![
        include_str!("../stdlib/core/result.lani").to_owned(),
        r#"
module app::main;

import core::result;

fn main() {
    let value: core::result::Result<i32, bool> = core::result::Ok(1);
    let fallback: i32 = 3;
    let output: i32 = core::result::unwrap_or(value, fallback);
    return output;
}
"#
        .to_owned(),
    ];
    let joined = sources.concat();
    let texts = token_texts(&joined);
    let unwrap_fn_token = fn_token(&texts, "unwrap_or");
    let unwrap_call_head = texts
        .windows(8)
        .enumerate()
        .filter(|(_, window)| {
            window[0] == "core"
                && window[1] == ":"
                && window[2] == ":"
                && window[3] == "result"
                && window[4] == ":"
                && window[5] == ":"
                && window[6] == "unwrap_or"
                && window[7] == "("
        })
        .map(|(index, _)| index)
        .last()
        .expect("qualified core::result::unwrap_or call");
    let unwrap_call_leaf = unwrap_call_head + 6;
    let unwrap_value_arg = unwrap_call_leaf + 2;
    let unwrap_fallback_arg = unwrap_call_leaf + 4;
    let unwrap_value_param = texts[unwrap_fn_token..]
        .windows(3)
        .position(|window| window[0] == "(" && window[1] == "value" && window[2] == ":")
        .map(|index| unwrap_fn_token + index + 1)
        .expect("unwrap_or value parameter token");
    let unwrap_fallback_param = texts[unwrap_fn_token..]
        .windows(3)
        .position(|window| window[0] == "," && window[1] == "fallback" && window[2] == ":")
        .map(|index| unwrap_fn_token + index + 1)
        .expect("unwrap_or fallback parameter token");
    let value_decl = texts
        .windows(3)
        .enumerate()
        .filter(|(_, window)| window[0] == "let" && window[1] == "value" && window[2] == ":")
        .map(|(index, _)| index + 1)
        .last()
        .expect("app value declaration token");
    let fallback_decl = texts
        .windows(3)
        .enumerate()
        .filter(|(_, window)| window[0] == "let" && window[1] == "fallback" && window[2] == ":")
        .map(|(index, _)| index + 1)
        .last()
        .expect("app fallback declaration token");

    let snapshot = gpu_member_result_source_pack_snapshot(sources, texts.len());
    let result_instance = snapshot.decl_type_ref_payload[value_decl] as usize;
    let result_arg_start = snapshot_word(&snapshot.instance_arg_start, result_instance as u32);
    let result_param_instance = snapshot.decl_type_ref_payload[unwrap_value_param] as usize;
    let result_param_arg_start =
        snapshot_word(&snapshot.instance_arg_start, result_param_instance as u32);

    assert_eq!(
        snapshot.call_fn_index[unwrap_call_head],
        unwrap_fn_token as u32,
        "qualified result unwrap_or call should resolve through source-pack value records; call={} fn={} got={} type_error={:?}",
        unwrap_call_head,
        unwrap_fn_token,
        snapshot.call_fn_index[unwrap_call_head],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.decl_type_ref_tag[value_decl],
        3,
        "annotated Result<i32,bool> local should publish a type-instance ref; token={} tag={} payload={} type_error={:?}",
        value_decl,
        snapshot.decl_type_ref_tag[value_decl],
        snapshot.decl_type_ref_payload[value_decl],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot_word(&snapshot.instance_arg_count, result_instance as u32),
        2,
        "Result<i32,bool> instance should publish both T and E arguments; instance={} type_error={:?}",
        result_instance,
        snapshot.type_error,
    );
    assert_eq!(
        snapshot_word(&snapshot.instance_arg_ref_tag, result_arg_start),
        1,
        "Result<T,E> T argument should be a scalar ref; instance={} arg_start={} arg_tag={} arg_payload={}",
        result_instance,
        result_arg_start,
        snapshot_word(&snapshot.instance_arg_ref_tag, result_arg_start),
        snapshot_word(&snapshot.instance_arg_ref_payload, result_arg_start),
    );
    assert_eq!(
        snapshot_word(&snapshot.instance_arg_ref_payload, result_arg_start),
        3,
        "Result<i32,bool> T argument should carry scalar i32"
    );
    assert_eq!(
        snapshot_word(&snapshot.instance_arg_ref_tag, result_arg_start + 1),
        1,
        "Result<T,E> E argument should be a scalar ref; instance={} arg_start={} arg_tag={} arg_payload={}",
        result_instance,
        result_arg_start,
        snapshot_word(&snapshot.instance_arg_ref_tag, result_arg_start + 1),
        snapshot_word(&snapshot.instance_arg_ref_payload, result_arg_start + 1),
    );
    assert_eq!(
        snapshot_word(&snapshot.instance_arg_ref_payload, result_arg_start + 1),
        2,
        "Result<i32,bool> E argument should carry scalar bool"
    );
    assert_eq!(
        snapshot.decl_type_ref_tag[unwrap_value_param],
        3,
        "unwrap_or value parameter should publish Result<T,E> instance ref; param={} tag={} payload={} call_param0={} fallback_param_ref={}:{} type_error={:?}",
        unwrap_value_param,
        snapshot.decl_type_ref_tag[unwrap_value_param],
        snapshot.decl_type_ref_payload[unwrap_value_param],
        snapshot.call_param_type[unwrap_fn_token * 4],
        snapshot.decl_type_ref_tag[unwrap_fallback_param],
        snapshot.decl_type_ref_payload[unwrap_fallback_param],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot_word(&snapshot.instance_arg_ref_tag, result_param_arg_start),
        2,
        "formal Result<T,E> T argument should stay generic before call-site binding"
    );
    assert_eq!(
        snapshot_word(&snapshot.instance_arg_ref_tag, result_param_arg_start + 1),
        2,
        "formal Result<T,E> E argument should stay generic before call-site binding"
    );
    assert_eq!(
        snapshot.call_return_type[unwrap_call_head],
        3,
        "qualified generic result unwrap_or call should publish i32 after binding T from call argument records; call={} call_ret={} fn={} fn_ret={} fn_ret_ref={}:{} value_arg={} value_arg_visible={} fallback_arg={} fallback_arg_visible={} value_decl={} value_visible={} value_ref={}:{} fallback_decl={} fallback_visible={} fallback_ref={}:{} result_instance={} arg_start={} arg0={}:{} arg1={}:{} type_error={:?}",
        unwrap_call_head,
        snapshot.call_return_type[unwrap_call_head],
        unwrap_fn_token,
        snapshot.call_return_type[unwrap_fn_token],
        snapshot.fn_return_ref_tag[unwrap_fn_token],
        snapshot.fn_return_ref_payload[unwrap_fn_token],
        unwrap_value_arg,
        snapshot.visible_decl[unwrap_value_arg],
        unwrap_fallback_arg,
        snapshot.visible_decl[unwrap_fallback_arg],
        value_decl,
        snapshot.visible_decl[value_decl],
        snapshot.decl_type_ref_tag[value_decl],
        snapshot.decl_type_ref_payload[value_decl],
        fallback_decl,
        snapshot.visible_decl[fallback_decl],
        snapshot.decl_type_ref_tag[fallback_decl],
        snapshot.decl_type_ref_payload[fallback_decl],
        result_instance,
        result_arg_start,
        snapshot_word(&snapshot.instance_arg_ref_tag, result_arg_start),
        snapshot_word(&snapshot.instance_arg_ref_payload, result_arg_start),
        snapshot_word(&snapshot.instance_arg_ref_tag, result_arg_start + 1),
        snapshot_word(&snapshot.instance_arg_ref_payload, result_arg_start + 1),
        snapshot.type_error,
    );
    assert!(
        snapshot.type_error.is_none(),
        "qualified result generic call fixture should type-check: {:?}",
        snapshot.type_error
    );
}

#[test]
fn gpu_array_type_alias_target_publishes_element_type_ref_records() {
    let src = r#"
type Four = [i32; 4];

fn first(values: Four) -> i32 {
    return values[0];
}

fn main(values: Four) {
    let value: i32 = first(values);
    return value;
}
"#;
    let texts = token_texts(src);
    let alias_element_token = texts
        .windows(4)
        .position(|window| window[0] == "[" && window[1] == "i32" && window[2] == ";")
        .map(|index| index + 1)
        .expect("array alias element token");
    let alias_name_use = texts
        .windows(3)
        .position(|window| window[0] == "values" && window[1] == ":" && window[2] == "Four")
        .map(|index| index + 2)
        .expect("array alias parameter type token");

    let snapshot = gpu_member_result_snapshot(src, texts.len());

    assert_eq!(
        snapshot.type_expr_ref_tag[alias_element_token],
        1,
        "array alias element should resolve through language type records; token={} text={} tag={} payload={} name_id={} alias_use={} alias_use_ref={}:{} type_error={:?}",
        alias_element_token,
        texts[alias_element_token],
        snapshot.type_expr_ref_tag[alias_element_token],
        snapshot.type_expr_ref_payload[alias_element_token],
        snapshot.name_id_by_token[alias_element_token],
        alias_name_use,
        snapshot.type_expr_ref_tag[alias_name_use],
        snapshot.type_expr_ref_payload[alias_name_use],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.type_expr_ref_tag[alias_name_use],
        3,
        "array alias use should preserve the target array instance ref; token={} text={} tag={} payload={} type_error={:?}",
        alias_name_use,
        texts[alias_name_use],
        snapshot.type_expr_ref_tag[alias_name_use],
        snapshot.type_expr_ref_payload[alias_name_use],
        snapshot.type_error,
    );
    assert!(
        snapshot.type_error.is_none(),
        "array type alias fixture should type-check: {:?}",
        snapshot.type_error
    );
}

#[test]
fn gpu_scalar_type_alias_chain_consumes_projected_alias_records() {
    let src = r#"
type Raw = i32;
type Base = Raw;
type Count = Base;

fn main() {
    let value: Count = 7;
    return value;
}
"#;
    let texts = token_texts(src);
    let alias_target = texts
        .windows(3)
        .position(|window| window[0] == "Count" && window[1] == "=" && window[2] == "Base")
        .map(|index| index + 2)
        .expect("Count alias target token");
    let count_decl = texts
        .windows(3)
        .position(|window| window[0] == "type" && window[1] == "Count" && window[2] == "=")
        .map(|index| index + 1)
        .expect("Count alias declaration token");
    let count_use = texts
        .windows(3)
        .position(|window| window[0] == "value" && window[1] == ":" && window[2] == "Count")
        .map(|index| index + 2)
        .expect("Count alias use token");
    let value_decl = texts
        .windows(3)
        .position(|window| window[0] == "let" && window[1] == "value" && window[2] == ":")
        .map(|index| index + 1)
        .expect("value declaration token");

    let snapshot = gpu_member_result_snapshot(src, texts.len());

    assert_eq!(
        snapshot.type_expr_ref_tag[alias_target],
        1,
        "alias-chain target should be rewritten from the sorted type-path declaration record; token={} text={} tag={} payload={} type_error={:?}",
        alias_target,
        texts[alias_target],
        snapshot.type_expr_ref_tag[alias_target],
        snapshot.type_expr_ref_payload[alias_target],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.type_expr_ref_tag[count_decl],
        1,
        "chained alias declaration should publish the resolved scalar target ref; token={} text={} tag={} payload={} type_error={:?}",
        count_decl,
        texts[count_decl],
        snapshot.type_expr_ref_tag[count_decl],
        snapshot.type_expr_ref_payload[count_decl],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.type_expr_ref_tag[count_use],
        1,
        "chained alias use should consume the projected declaration ref; token={} text={} tag={} payload={} type_error={:?}",
        count_use,
        texts[count_use],
        snapshot.type_expr_ref_tag[count_use],
        snapshot.type_expr_ref_payload[count_use],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.visible_type[value_decl], 3,
        "let declaration should receive i32 from the chained alias records; token={} text={} visible_type={} type_error={:?}",
        value_decl, texts[value_decl], snapshot.visible_type[value_decl], snapshot.type_error,
    );
    assert!(
        snapshot.type_error.is_none(),
        "scalar alias chain fixture should type-check: {:?}",
        snapshot.type_error
    );
}

#[test]
fn gpu_generic_type_alias_instance_consumes_type_instance_arg_records() {
    let src = r#"
type Alias<T> = T;

fn main() {
    let value: Alias<i32> = 7;
    return value;
}
"#;
    let texts = token_texts(src);
    let alias_decl = texts
        .windows(3)
        .position(|window| window[0] == "type" && window[1] == "Alias" && window[2] == "<")
        .map(|index| index + 1)
        .expect("alias declaration token");
    let alias_use = texts
        .windows(5)
        .position(|window| {
            window[0] == "value"
                && window[1] == ":"
                && window[2] == "Alias"
                && window[3] == "<"
                && window[4] == "i32"
        })
        .map(|index| index + 2)
        .expect("alias use token");
    let value_decl = texts
        .windows(3)
        .position(|window| window[0] == "let" && window[1] == "value" && window[2] == ":")
        .map(|index| index + 1)
        .expect("value declaration token");

    let snapshot = gpu_member_result_snapshot(src, texts.len());
    let alias_instance = snapshot.type_expr_ref_payload[alias_use] as usize;
    let first_arg_ref = (alias_instance * 4) as u32;

    assert_eq!(
        snapshot.type_expr_ref_tag[alias_decl],
        2,
        "generic alias declaration should publish its target generic-param ref; token={} text={} tag={} payload={} type_error={:?}",
        alias_decl,
        texts[alias_decl],
        snapshot.type_expr_ref_tag[alias_decl],
        snapshot.type_expr_ref_payload[alias_decl],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.type_expr_ref_tag[alias_use],
        3,
        "generic alias use should be a named type-instance ref; token={} text={} tag={} payload={} type_error={:?}",
        alias_use,
        texts[alias_use],
        snapshot.type_expr_ref_tag[alias_use],
        snapshot.type_expr_ref_payload[alias_use],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot_word(&snapshot.instance_arg_ref_tag, first_arg_ref),
        1,
        "generic alias instance should consume HIR type-arg ref records; instance={} arg_tag={} arg_payload={} type_error={:?}",
        alias_instance,
        snapshot_word(&snapshot.instance_arg_ref_tag, first_arg_ref),
        snapshot_word(&snapshot.instance_arg_ref_payload, first_arg_ref),
        snapshot.type_error,
    );
    assert_eq!(
        snapshot_word(&snapshot.instance_arg_ref_payload, first_arg_ref),
        3,
        "generic alias instance argument should resolve to i32 scalar records"
    );
    assert_eq!(
        snapshot.visible_type[value_decl], 3,
        "let declaration should receive the substituted alias type from records; token={} text={} visible_type={} type_error={:?}",
        value_decl, texts[value_decl], snapshot.visible_type[value_decl], snapshot.type_error,
    );
    assert!(
        snapshot.type_error.is_none(),
        "generic alias substitution fixture should type-check: {:?}",
        snapshot.type_error
    );
}

#[test]
fn gpu_generic_type_alias_chain_substitutes_through_target_instance_records() {
    let src = r#"
type Alias<T> = T;
type Id<T> = Alias<T>;

fn main() {
    let value: Id<i32> = 7;
    return value;
}
"#;
    let texts = token_texts(src);
    let alias_target = texts
        .windows(5)
        .position(|window| {
            window[0] == "Id"
                && window[1] == "<"
                && window[2] == "T"
                && window[3] == ">"
                && window[4] == "="
        })
        .map(|index| index + 5)
        .expect("Id alias target token");
    let id_use = texts
        .windows(5)
        .position(|window| {
            window[0] == "value"
                && window[1] == ":"
                && window[2] == "Id"
                && window[3] == "<"
                && window[4] == "i32"
        })
        .map(|index| index + 2)
        .expect("Id alias use token");
    let value_decl = texts
        .windows(3)
        .position(|window| window[0] == "let" && window[1] == "value" && window[2] == ":")
        .map(|index| index + 1)
        .expect("value declaration token");

    let snapshot = gpu_member_result_snapshot(src, texts.len());
    let id_instance = snapshot.type_expr_ref_payload[id_use] as usize;
    let first_arg_ref = (id_instance * 4) as u32;

    assert_eq!(
        snapshot.type_expr_ref_tag[alias_target],
        2,
        "generic alias-chain target should project to the target alias generic-param ref; token={} text={} tag={} payload={} type_error={:?}",
        alias_target,
        texts[alias_target],
        snapshot.type_expr_ref_tag[alias_target],
        snapshot.type_expr_ref_payload[alias_target],
        snapshot.type_error,
    );
    assert_eq!(
        snapshot_word(&snapshot.instance_arg_ref_tag, first_arg_ref),
        1,
        "outer generic alias instance should consume concrete type argument records; instance={} arg_tag={} arg_payload={} type_error={:?}",
        id_instance,
        snapshot_word(&snapshot.instance_arg_ref_tag, first_arg_ref),
        snapshot_word(&snapshot.instance_arg_ref_payload, first_arg_ref),
        snapshot.type_error,
    );
    assert_eq!(
        snapshot.visible_type[value_decl], 3,
        "let declaration should receive i32 through the generic alias-chain target instance; token={} text={} visible_type={} type_error={:?}",
        value_decl, texts[value_decl], snapshot.visible_type[value_decl], snapshot.type_error,
    );
    assert!(
        snapshot.type_error.is_none(),
        "generic alias-chain substitution fixture should type-check: {:?}",
        snapshot.type_error
    );
}

mod common;

use laniusc::{
    gpu::device,
    lexer::{driver::GpuLexer, test_cpu::lex_on_test_cpu},
    parser::{driver::GpuParser, tables::PrecomputedParseTables},
    type_checker::{GpuTypeCheckHirItemBuffers, GpuTypeChecker},
};

struct MemberResultReadbacks {
    tag: wgpu::Buffer,
    payload: wgpu::Buffer,
    ordinal: wgpu::Buffer,
    instance_decl_token: wgpu::Buffer,
    visible_decl: wgpu::Buffer,
    type_expr_tag: wgpu::Buffer,
    type_expr_payload: wgpu::Buffer,
    method_receiver_tag: wgpu::Buffer,
    method_receiver_payload: wgpu::Buffer,
    method_param_offset: wgpu::Buffer,
}

struct MemberResultSnapshot {
    tag: Vec<u32>,
    payload: Vec<u32>,
    ordinal: Vec<u32>,
    instance_decl_token: Vec<u32>,
    visible_decl: Vec<u32>,
    type_expr_tag: Vec<u32>,
    type_expr_payload: Vec<u32>,
    method_receiver_tag: Vec<u32>,
    method_receiver_payload: Vec<u32>,
    method_param_offset: Vec<u32>,
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

fn fn_token(texts: &[String], name: &str) -> usize {
    texts
        .windows(2)
        .position(|window| window[0] == "fn" && window[1] == name)
        .unwrap_or_else(|| panic!("missing function token fn {name}: {texts:?}"))
}

fn token_after(texts: &[String], before: &str, token: &str) -> usize {
    texts
        .windows(2)
        .position(|window| window[0] == before && window[1] == token)
        .map(|index| index + 1)
        .unwrap_or_else(|| panic!("missing token {token} after {before}: {texts:?}"))
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
        instance_decl_token: read_words(device, &readbacks.instance_decl_token, count),
        visible_decl: read_words(device, &readbacks.visible_decl, count),
        type_expr_tag: read_words(device, &readbacks.type_expr_tag, count),
        type_expr_payload: read_words(device, &readbacks.type_expr_payload, count),
        method_receiver_tag: read_words(device, &readbacks.method_receiver_tag, count),
        method_receiver_payload: read_words(device, &readbacks.method_receiver_payload, count),
        method_param_offset: read_words(device, &readbacks.method_param_offset, count),
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
            .with_recorded_resident_tokens(
                src,
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
                                    .map_err(|err| err.to_string())?;

                                let readbacks = type_checker
                                    .with_codegen_buffers(|codegen| {
                                        let size = (bufs.n as u64).saturating_mul(4);
                                        let mk = |label| {
                                            device.create_buffer(&wgpu::BufferDescriptor {
                                                label: Some(label),
                                                size,
                                                usage: wgpu::BufferUsages::COPY_DST
                                                    | wgpu::BufferUsages::MAP_READ,
                                                mapped_at_creation: false,
                                            })
                                        };
                                        let tag = mk("rb.test.member_result.tag");
                                        let payload = mk("rb.test.member_result.payload");
                                        let ordinal = mk("rb.test.member_result.ordinal");
                                        let instance_decl_token =
                                            mk("rb.test.type_instance.decl_token");
                                        let visible_decl = mk("rb.test.visible_decl");
                                        let type_expr_tag = mk("rb.test.type_expr.tag");
                                        let type_expr_payload = mk("rb.test.type_expr.payload");
                                        let method_receiver_tag = mk("rb.test.method_receiver.tag");
                                        let method_receiver_payload =
                                            mk("rb.test.method_receiver.payload");
                                        let method_param_offset = mk("rb.test.method_param_offset");
                                        encoder.copy_buffer_to_buffer(
                                            codegen.member_result_ref_tag,
                                            0,
                                            &tag,
                                            0,
                                            size,
                                        );
                                        encoder.copy_buffer_to_buffer(
                                            codegen.member_result_ref_payload,
                                            0,
                                            &payload,
                                            0,
                                            size,
                                        );
                                        encoder.copy_buffer_to_buffer(
                                            codegen.member_result_field_ordinal,
                                            0,
                                            &ordinal,
                                            0,
                                            size,
                                        );
                                        encoder.copy_buffer_to_buffer(
                                            codegen.type_instance_decl_token,
                                            0,
                                            &instance_decl_token,
                                            0,
                                            size,
                                        );
                                        encoder.copy_buffer_to_buffer(
                                            codegen.visible_decl,
                                            0,
                                            &visible_decl,
                                            0,
                                            size,
                                        );
                                        encoder.copy_buffer_to_buffer(
                                            codegen.type_expr_ref_tag,
                                            0,
                                            &type_expr_tag,
                                            0,
                                            size,
                                        );
                                        encoder.copy_buffer_to_buffer(
                                            codegen.type_expr_ref_payload,
                                            0,
                                            &type_expr_payload,
                                            0,
                                            size,
                                        );
                                        encoder.copy_buffer_to_buffer(
                                            codegen.method_decl_receiver_ref_tag,
                                            0,
                                            &method_receiver_tag,
                                            0,
                                            size,
                                        );
                                        encoder.copy_buffer_to_buffer(
                                            codegen.method_decl_receiver_ref_payload,
                                            0,
                                            &method_receiver_payload,
                                            0,
                                            size,
                                        );
                                        encoder.copy_buffer_to_buffer(
                                            codegen.method_decl_param_offset,
                                            0,
                                            &method_param_offset,
                                            0,
                                            size,
                                        );
                                        MemberResultReadbacks {
                                            tag,
                                            payload,
                                            ordinal,
                                            instance_decl_token,
                                            visible_decl,
                                            type_expr_tag,
                                            type_expr_payload,
                                            method_receiver_tag,
                                            method_receiver_payload,
                                            method_param_offset,
                                        }
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
    let impl_range_token = token_after(&texts, "impl", "Range");

    let snapshot = gpu_member_result_snapshot(src, texts.len());

    assert_eq!(
        snapshot.ordinal[start_token],
        0,
        "self.start should project field ordinal 0; tag={} payload={} decl={} visible_decl={} method_receiver={}:{} method_param={} impl_type_ref={}:{} impl_decl={}",
        snapshot.tag[start_token],
        snapshot.payload[start_token],
        snapshot_word(&snapshot.instance_decl_token, snapshot.payload[start_token]),
        snapshot.visible_decl[start_token - 2],
        snapshot.method_receiver_tag[start_fn_token],
        snapshot.method_receiver_payload[start_fn_token],
        snapshot.method_param_offset[start_fn_token],
        snapshot.type_expr_tag[impl_range_token],
        snapshot.type_expr_payload[impl_range_token],
        snapshot_word(
            &snapshot.instance_decl_token,
            snapshot.type_expr_payload[impl_range_token]
        )
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

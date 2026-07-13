use super::{super::*, scan::create_counted_u32_scan_bind_groups_from_passes};

/// Builds bind groups for compacting source lexemes into stable name ids.
#[allow(clippy::too_many_arguments)]
pub(in crate::type_checker) fn create_name_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    input: NameInput<'_>,
) -> Result<NameBindGroups> {
    let params = input.params;
    let source_len = input.source_len;
    let name_capacity = input.cap;
    let token_scan_n_blocks = input.token_blocks;
    let name_n_blocks = input.name_blocks;
    let scan_steps = input.steps;
    let token_buf = input.token_words;
    let token_count_buf = input.token_count;
    let source_buf = input.source_bytes;
    let status_buf = input.status;
    let name_lexeme_flag = input.lexemes.flag;
    let name_lexeme_kind = input.lexemes.kind;
    let name_lexeme_prefix = input.lexemes.prefix;
    let name_scan_local_prefix = input.scan.local_prefix;
    let name_scan_block_sum = input.scan.block_sum;
    let name_scan_prefix_a = input.scan.prefix_a;
    let name_scan_prefix_b = input.scan.prefix_b;
    let name_scan_total = input.total;
    let name_max_len = input.max_len;
    let name_spans = input.spans;
    let name_order_in = input.order_in;
    let name_order_tmp = input.order_tmp;
    let language_symbol_bytes = input.symbols.bytes;
    let language_symbol_start = input.symbols.start;
    let language_symbol_len = input.symbols.len;
    let name_id_by_token = input.ids.by_token;
    let language_name_id = input.ids.language;
    let radix_block_histogram = input.radix.histogram;
    let radix_block_bucket_prefix = input.radix.bucket_prefix;
    let sorted_name_id = input.ids.sorted;
    let name_id_by_input = input.ids.by_input;
    let unique_name_count = input.ids.unique_count;

    let mark = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_names_00_mark_lexemes"),
        &passes.names_mark_lexemes,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("token_words", token_buf.as_entire_binding()),
            ("token_count", token_count_buf.as_entire_binding()),
            ("name_lexeme_flag", name_lexeme_flag.as_entire_binding()),
            ("name_lexeme_kind", name_lexeme_kind.as_entire_binding()),
        ],
    )?;

    let name_lexeme_scan = create_counted_u32_scan_bind_groups_from_passes(
        &passes.counted_scan_local,
        &passes.counted_scan_hierarchy_up,
        &passes.counted_scan_hierarchy_down,
        &passes.counted_scan_apply,
        device,
        "type_check.names.lexeme_scan",
        scan_steps,
        token_count_buf,
        name_lexeme_flag,
        name_lexeme_prefix,
        name_scan_total,
        name_scan_local_prefix,
        name_scan_block_sum,
        name_scan_prefix_a,
        name_scan_prefix_b,
    )?;

    let scatter = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_names_01_scatter_lexemes"),
        &passes.names_scatter_lexemes,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("token_words", token_buf.as_entire_binding()),
            ("token_count", token_count_buf.as_entire_binding()),
            ("name_lexeme_flag", name_lexeme_flag.as_entire_binding()),
            ("name_lexeme_kind", name_lexeme_kind.as_entire_binding()),
            ("name_lexeme_prefix", name_lexeme_prefix.as_entire_binding()),
            (
                "language_symbol_start",
                language_symbol_start.as_entire_binding(),
            ),
            (
                "language_symbol_len",
                language_symbol_len.as_entire_binding(),
            ),
            ("name_spans", name_spans.as_entire_binding()),
            ("name_order_in", name_order_in.as_entire_binding()),
            ("name_order_tmp", name_order_tmp.as_entire_binding()),
            ("name_id_by_token", name_id_by_token.as_entire_binding()),
            ("name_count_out", name_scan_total.as_entire_binding()),
            ("name_max_len_out", name_max_len.as_entire_binding()),
            ("status", status_buf.as_entire_binding()),
        ],
    )?;

    let hash_work_items = name_n_blocks.max(1).saturating_mul(NAME_RADIX_BUCKETS);
    let hash_params = uniform_from_val(
        device,
        "type_check.names.hash.params",
        &NameRadixParams {
            name_count: name_capacity,
            source_len,
            n_blocks: hash_work_items,
            radix_byte_offset: 0,
        },
    );
    let hash_bindings = [
        ("gParams", hash_params.as_entire_binding()),
        ("name_spans", name_spans.as_entire_binding()),
        ("name_count_in", name_scan_total.as_entire_binding()),
        ("source_bytes", source_buf.as_entire_binding()),
        (
            "language_symbol_bytes",
            language_symbol_bytes.as_entire_binding(),
        ),
        ("name_hash_lo", name_order_in.as_entire_binding()),
        ("name_hash_hi", name_order_tmp.as_entire_binding()),
        (
            "name_hash_table_a",
            radix_block_histogram.as_entire_binding(),
        ),
        (
            "name_hash_table_b",
            radix_block_bucket_prefix.as_entire_binding(),
        ),
        ("status", status_buf.as_entire_binding()),
        ("sorted_name_id", sorted_name_id.as_entire_binding()),
        ("name_id_by_input", name_id_by_input.as_entire_binding()),
        ("name_id_by_token", name_id_by_token.as_entire_binding()),
        ("language_name_id", language_name_id.as_entire_binding()),
        ("unique_name_count", unique_name_count.as_entire_binding()),
    ];
    let hash_prepare = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_names_hash_00_prepare"),
        &passes.names_hash_prepare,
        0,
        &hash_bindings,
    )?;
    let hash_insert = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_names_hash_01_insert"),
        &passes.names_hash_insert,
        0,
        &hash_bindings,
    )?;
    let hash_assign_ids = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_names_hash_02_assign_ids"),
        &passes.names_hash_assign_ids,
        0,
        &hash_bindings,
    )?;

    Ok(NameBindGroups {
        token_scan_n_blocks,
        name_max_len: (*name_max_len).clone(),
        mark,
        scan: name_lexeme_scan,
        scatter,
        hash_work_items,
        _hash_params: hash_params,
        hash_prepare,
        hash_insert,
        hash_assign_ids,
    })
}

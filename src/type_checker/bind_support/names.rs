use super::{
    super::*,
    scan::{create_counted_u32_scan_bind_groups_from_passes, make_name_scan_steps},
};

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
    let radix_bucket_total = input.radix.bucket_total;
    let radix_bucket_base = input.radix.bucket_base;
    let radix_dispatch_args = input.radix_args;
    let run_head_mask = input.run_head;
    let adjacent_equal_mask = input.adjacent_equal;
    let run_head_prefix = input.run_prefix;
    let sorted_name_id = input.ids.sorted;
    let name_id_by_input = input.ids.by_input;
    let unique_name_count = input.ids.unique_count;

    let run_head_scan_params = NameScanParams {
        n_items: name_capacity,
        n_blocks: name_n_blocks,
        scan_step: 0,
    };
    let run_head_scan_steps = make_name_scan_steps(device, run_head_scan_params);

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
        &passes.counted_scan_blocks,
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

    let mut radix_steps = Vec::with_capacity(NAME_RADIX_MAX_BYTES as usize + 2);
    let mut radix_histogram = Vec::with_capacity(NAME_RADIX_MAX_BYTES as usize);
    let mut radix_bucket_prefix = Vec::with_capacity(NAME_RADIX_MAX_BYTES as usize);
    let mut radix_bucket_bases = Vec::with_capacity(NAME_RADIX_MAX_BYTES as usize);
    let mut radix_scatter = Vec::with_capacity(NAME_RADIX_MAX_BYTES as usize);

    let radix_dispatch_params = uniform_from_val(
        device,
        "type_check.names.radix.dispatch.params",
        &NameRadixParams {
            name_count: name_capacity,
            source_len,
            n_blocks: name_n_blocks,
            radix_byte_offset: 0,
        },
    );
    let radix_dispatch = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_names_radix_byte_dispatch_args"),
        &passes.names_radix_byte_dispatch_args,
        0,
        &[
            ("gParams", radix_dispatch_params.as_entire_binding()),
            ("name_count_in", name_scan_total.as_entire_binding()),
            ("name_max_len_in", name_max_len.as_entire_binding()),
            (
                "radix_dispatch_args",
                radix_dispatch_args.as_entire_binding(),
            ),
        ],
    )?;
    radix_steps.push(NameRadixStep {
        _params: radix_dispatch_params,
    });

    for pass_i in 0..NAME_RADIX_MAX_BYTES {
        let byte_offset = NAME_RADIX_MAX_BYTES - 1 - pass_i;
        let step_params = uniform_from_val(
            device,
            &format!("type_check.names.radix.params.{byte_offset}"),
            &NameRadixParams {
                name_count: name_capacity,
                source_len,
                n_blocks: name_n_blocks,
                radix_byte_offset: byte_offset,
            },
        );
        let read_order = if pass_i % 2 == 0 {
            name_order_in
        } else {
            name_order_tmp
        };
        let write_order = if pass_i % 2 == 0 {
            name_order_tmp
        } else {
            name_order_in
        };

        radix_histogram.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_names_radix_00_histogram"),
            &passes.names_radix_histogram,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                ("name_spans", name_spans.as_entire_binding()),
                ("name_count_in", name_scan_total.as_entire_binding()),
                ("name_max_len_in", name_max_len.as_entire_binding()),
                ("name_order_in", read_order.as_entire_binding()),
                ("source_bytes", source_buf.as_entire_binding()),
                (
                    "language_symbol_bytes",
                    language_symbol_bytes.as_entire_binding(),
                ),
                (
                    "radix_block_histogram",
                    radix_block_histogram.as_entire_binding(),
                ),
            ],
        )?);

        radix_bucket_prefix.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_names_radix_00b_bucket_prefix_active"),
            &passes.names_radix_bucket_prefix_active,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                ("name_count_in", name_scan_total.as_entire_binding()),
                ("name_max_len_in", name_max_len.as_entire_binding()),
                (
                    "radix_block_histogram",
                    radix_block_histogram.as_entire_binding(),
                ),
                (
                    "radix_block_bucket_prefix",
                    radix_block_bucket_prefix.as_entire_binding(),
                ),
                ("radix_bucket_total", radix_bucket_total.as_entire_binding()),
            ],
        )?);

        radix_bucket_bases.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_names_radix_00c_bucket_bases_active"),
            &passes.names_radix_bucket_bases_active,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                ("name_max_len_in", name_max_len.as_entire_binding()),
                ("radix_bucket_total", radix_bucket_total.as_entire_binding()),
                ("radix_bucket_base", radix_bucket_base.as_entire_binding()),
            ],
        )?);

        radix_scatter.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_names_radix_01_scatter"),
            &passes.names_radix_scatter,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                ("name_spans", name_spans.as_entire_binding()),
                ("name_count_in", name_scan_total.as_entire_binding()),
                ("name_max_len_in", name_max_len.as_entire_binding()),
                ("name_order_in", read_order.as_entire_binding()),
                ("radix_bucket_base", radix_bucket_base.as_entire_binding()),
                (
                    "radix_block_bucket_prefix",
                    radix_block_bucket_prefix.as_entire_binding(),
                ),
                ("source_bytes", source_buf.as_entire_binding()),
                (
                    "language_symbol_bytes",
                    language_symbol_bytes.as_entire_binding(),
                ),
                ("name_order_out", write_order.as_entire_binding()),
            ],
        )?);
        radix_steps.push(NameRadixStep {
            _params: step_params,
        });
    }

    let sorted_name_order = if NAME_RADIX_MAX_BYTES % 2 == 0 {
        name_order_in
    } else {
        name_order_tmp
    };
    let final_params = uniform_from_val(
        device,
        "type_check.names.radix.params.final",
        &NameRadixParams {
            name_count: name_capacity,
            source_len,
            n_blocks: name_n_blocks,
            radix_byte_offset: 0,
        },
    );
    let dedup = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_names_radix_02_adjacent_dedup"),
        &passes.names_radix_dedup,
        0,
        &[
            ("gParams", final_params.as_entire_binding()),
            ("name_spans", name_spans.as_entire_binding()),
            ("name_count_in", name_scan_total.as_entire_binding()),
            ("sorted_name_order", sorted_name_order.as_entire_binding()),
            ("source_bytes", source_buf.as_entire_binding()),
            (
                "language_symbol_bytes",
                language_symbol_bytes.as_entire_binding(),
            ),
            ("run_head_mask", run_head_mask.as_entire_binding()),
            (
                "adjacent_equal_mask",
                adjacent_equal_mask.as_entire_binding(),
            ),
        ],
    )?;

    let run_head_scan = create_counted_u32_scan_bind_groups_from_passes(
        &passes.counted_scan_local,
        &passes.counted_scan_blocks,
        &passes.counted_scan_apply,
        device,
        "type_check.names.run_head_scan",
        &run_head_scan_steps,
        name_scan_total,
        run_head_mask,
        run_head_prefix,
        unique_name_count,
        name_scan_local_prefix,
        name_scan_block_sum,
        name_scan_prefix_a,
        name_scan_prefix_b,
    )?;

    let assign_ids = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_names_radix_03_assign_ids"),
        &passes.names_radix_assign_ids,
        0,
        &[
            ("gParams", final_params.as_entire_binding()),
            ("name_spans", name_spans.as_entire_binding()),
            ("name_count_in", name_scan_total.as_entire_binding()),
            ("sorted_name_order", sorted_name_order.as_entire_binding()),
            ("run_head_mask", run_head_mask.as_entire_binding()),
            ("run_head_prefix", run_head_prefix.as_entire_binding()),
            ("sorted_name_id", sorted_name_id.as_entire_binding()),
            ("name_id_by_input", name_id_by_input.as_entire_binding()),
            ("name_id_by_token", name_id_by_token.as_entire_binding()),
            ("language_name_id", language_name_id.as_entire_binding()),
            ("unique_name_count", unique_name_count.as_entire_binding()),
        ],
    )?;
    radix_steps.push(NameRadixStep {
        _params: final_params,
    });

    Ok(NameBindGroups {
        token_scan_n_blocks,
        radix_n_blocks: name_n_blocks,
        radix_dispatch_args: radix_dispatch_args.clone(),
        name_max_len: name_max_len.clone(),
        mark,
        scan_local: name_lexeme_scan.local,
        scan_blocks: name_lexeme_scan.blocks,
        scan_apply: name_lexeme_scan.apply,
        scatter,
        radix_dispatch,
        _radix_steps: radix_steps,
        radix_histogram,
        radix_bucket_prefix,
        radix_bucket_bases,
        radix_scatter,
        dedup,
        _run_head_scan_steps: run_head_scan_steps,
        run_head_scan_local: run_head_scan.local,
        run_head_scan_blocks: run_head_scan.blocks,
        run_head_scan_apply: run_head_scan.apply,
        assign_ids,
    })
}

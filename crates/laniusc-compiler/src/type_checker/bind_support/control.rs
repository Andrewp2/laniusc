use super::super::*;

#[allow(clippy::too_many_arguments)]
fn create_fixed_scan_hierarchy_bind_groups(
    device: &wgpu::Device,
    label: &'static str,
    hierarchy_up_pass: &PassData,
    hierarchy_down_pass: &PassData,
    n_items: u32,
    n_blocks: u32,
    block_sum: &wgpu::Buffer,
    scan_prefix: &wgpu::Buffer,
    scan_hierarchy: &wgpu::Buffer,
    block_prefix: &wgpu::Buffer,
) -> Result<(Vec<ScanHierarchyStep>, Vec<ScanHierarchyStep>)> {
    let levels = crate::gpu::scan::hierarchical_scan_levels(n_blocks);
    let mut hierarchy_up = Vec::with_capacity(levels.len());
    for (index, level) in levels.iter().copied().enumerate() {
        let parent = levels.get(index + 1).copied();
        let params = uniform_from_val(
            device,
            &format!("{label}.hierarchy_up.{index}"),
            &CountedScanHierarchyParams {
                n_items,
                n_blocks,
                level_divisor: level.divisor,
                level_offset: level.offset,
                parent_divisor: parent.map_or(0, |parent| parent.divisor),
                parent_offset: parent.map_or(0, |parent| parent.offset),
            },
        );
        let bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some(&format!("{label}.hierarchy_up")),
            hierarchy_up_pass,
            0,
            &[
                ("gHierarchy", params.as_entire_binding()),
                ("block_sum", block_sum.as_entire_binding()),
                ("block_prefix", block_prefix.as_entire_binding()),
                ("scan_prefix", scan_prefix.as_entire_binding()),
                ("scan_hierarchy", scan_hierarchy.as_entire_binding()),
            ],
        )?;
        hierarchy_up.push(ScanHierarchyStep {
            bind_group,
            work_items: level.count,
        });
    }

    let mut hierarchy_down = Vec::with_capacity(levels.len().saturating_sub(1));
    for child_index in (0..levels.len().saturating_sub(1)).rev() {
        let child = levels[child_index];
        let parent = levels[child_index + 1];
        let params = uniform_from_val(
            device,
            &format!("{label}.hierarchy_down.{child_index}"),
            &CountedScanHierarchyParams {
                n_items,
                n_blocks,
                level_divisor: child.divisor,
                level_offset: child.offset,
                parent_divisor: parent.divisor,
                parent_offset: parent.offset,
            },
        );
        let bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some(&format!("{label}.hierarchy_down")),
            hierarchy_down_pass,
            0,
            &[
                ("gHierarchy", params.as_entire_binding()),
                ("block_prefix", block_prefix.as_entire_binding()),
                ("scan_prefix", scan_prefix.as_entire_binding()),
                ("scan_hierarchy", scan_hierarchy.as_entire_binding()),
            ],
        )?;
        hierarchy_down.push(ScanHierarchyStep {
            bind_group,
            work_items: child.count,
        });
    }
    Ok((hierarchy_up, hierarchy_down))
}

/// Builds enclosing-function context bind groups from loaded type-check passes.
#[allow(clippy::too_many_arguments)]
pub(in crate::type_checker) fn create_fn_context_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    params: &LaniusBuffer<FnContextParams>,
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    enclosing_fn: &wgpu::Buffer,
    enclosing_fn_end: &wgpu::Buffer,
    fn_event_value: &wgpu::Buffer,
    fn_event_end: &wgpu::Buffer,
    fn_event_index: &wgpu::Buffer,
    fn_event_inblock: &wgpu::Buffer,
    fn_block_sum: &wgpu::Buffer,
    fn_prefix_a: &wgpu::Buffer,
    fn_prefix_b: &wgpu::Buffer,
    fn_block_prefix: &wgpu::Buffer,
) -> Result<FnContextBindGroups> {
    create_fn_context_bind_groups_from_passes(
        device,
        &passes.fn_context_clear,
        &passes.fn_context_mark,
        &passes.fn_context_local,
        &passes.fn_context_hierarchy_up,
        &passes.fn_context_hierarchy_down,
        &passes.fn_context_apply,
        params,
        hir_kind_buf,
        hir_token_pos_buf,
        hir_token_end_buf,
        hir_status_buf,
        enclosing_fn,
        enclosing_fn_end,
        fn_event_value,
        fn_event_end,
        fn_event_index,
        fn_event_inblock,
        fn_block_sum,
        fn_prefix_a,
        fn_prefix_b,
        fn_block_prefix,
    )
}

/// Builds enclosing-function context bind groups from explicit pass handles.
#[allow(clippy::too_many_arguments)]
pub(in crate::type_checker) fn create_fn_context_bind_groups_from_passes(
    device: &wgpu::Device,
    clear_pass: &PassData,
    mark_pass: &PassData,
    local_pass: &PassData,
    hierarchy_up_pass: &PassData,
    hierarchy_down_pass: &PassData,
    apply_pass: &PassData,
    params: &LaniusBuffer<FnContextParams>,
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    enclosing_fn: &wgpu::Buffer,
    enclosing_fn_end: &wgpu::Buffer,
    fn_event_value: &wgpu::Buffer,
    fn_event_end: &wgpu::Buffer,
    fn_event_index: &wgpu::Buffer,
    fn_event_inblock: &wgpu::Buffer,
    fn_block_sum: &wgpu::Buffer,
    fn_prefix_a: &wgpu::Buffer,
    fn_prefix_b: &wgpu::Buffer,
    fn_block_prefix: &wgpu::Buffer,
) -> Result<FnContextBindGroups> {
    let clear = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_fn_context_01_clear"),
        clear_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("enclosing_fn", enclosing_fn.as_entire_binding()),
            ("enclosing_fn_end", enclosing_fn_end.as_entire_binding()),
            ("fn_event_value", fn_event_value.as_entire_binding()),
            ("fn_event_end", fn_event_end.as_entire_binding()),
            ("fn_event_index", fn_event_index.as_entire_binding()),
            ("fn_event_inblock", fn_event_inblock.as_entire_binding()),
            ("block_sum", fn_block_sum.as_entire_binding()),
            ("block_prefix", fn_block_prefix.as_entire_binding()),
        ],
    )?;

    let mark = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_fn_context_02_mark"),
        mark_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            ("hir_token_end", hir_token_end_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("fn_event_value", fn_event_value.as_entire_binding()),
            ("fn_event_end", fn_event_end.as_entire_binding()),
            ("fn_event_index", fn_event_index.as_entire_binding()),
        ],
    )?;

    let local = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_fn_context_03_local"),
        local_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("fn_event_index", fn_event_index.as_entire_binding()),
            ("fn_event_inblock", fn_event_inblock.as_entire_binding()),
            ("block_sum", fn_block_sum.as_entire_binding()),
        ],
    )?;

    let n_blocks = (fn_block_sum.size() / 4).min(u32::MAX as u64) as u32;
    let n_items = n_blocks.saturating_mul(256);
    let (hierarchy_up, hierarchy_down) = create_fixed_scan_hierarchy_bind_groups(
        device,
        "type_check.fn_context",
        hierarchy_up_pass,
        hierarchy_down_pass,
        n_items,
        n_blocks,
        fn_block_sum,
        fn_prefix_a,
        fn_prefix_b,
        fn_block_prefix,
    )?;

    let apply = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_fn_context_05_apply"),
        apply_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("fn_event_value", fn_event_value.as_entire_binding()),
            ("fn_event_end", fn_event_end.as_entire_binding()),
            ("fn_event_inblock", fn_event_inblock.as_entire_binding()),
            ("block_prefix", fn_block_prefix.as_entire_binding()),
            ("enclosing_fn", enclosing_fn.as_entire_binding()),
            ("enclosing_fn_end", enclosing_fn_end.as_entire_binding()),
        ],
    )?;

    Ok(FnContextBindGroups {
        clear,
        mark,
        local,
        hierarchy_up,
        hierarchy_down,
        apply,
    })
}

/// Builds enclosing-`if` depth bind groups from loaded type-check passes.
#[allow(clippy::too_many_arguments)]
pub(in crate::type_checker) fn create_if_depth_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    params: &LaniusBuffer<IfDepthParams>,
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    if_delta: &wgpu::Buffer,
    if_depth_inblock: &wgpu::Buffer,
    if_block_sum: &wgpu::Buffer,
    if_prefix_a: &wgpu::Buffer,
    if_prefix_b: &wgpu::Buffer,
    if_block_prefix: &wgpu::Buffer,
    if_depth: &wgpu::Buffer,
) -> Result<IfDepthBindGroups> {
    create_if_depth_bind_groups_from_passes(
        device,
        &passes.if_depth_clear,
        &passes.if_depth_mark,
        &passes.if_depth_local,
        &passes.if_depth_hierarchy_up,
        &passes.if_depth_hierarchy_down,
        &passes.if_depth_apply,
        params,
        token_buf,
        token_count_buf,
        hir_kind_buf,
        hir_token_pos_buf,
        hir_token_end_buf,
        hir_status_buf,
        if_delta,
        if_depth_inblock,
        if_block_sum,
        if_prefix_a,
        if_prefix_b,
        if_block_prefix,
        if_depth,
    )
}

/// Builds enclosing-`if` depth bind groups from explicit pass handles.
#[allow(clippy::too_many_arguments)]
pub(in crate::type_checker) fn create_if_depth_bind_groups_from_passes(
    device: &wgpu::Device,
    clear_pass: &PassData,
    mark_pass: &PassData,
    local_pass: &PassData,
    hierarchy_up_pass: &PassData,
    hierarchy_down_pass: &PassData,
    apply_pass: &PassData,
    params: &LaniusBuffer<IfDepthParams>,
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    if_delta: &wgpu::Buffer,
    if_depth_inblock: &wgpu::Buffer,
    if_block_sum: &wgpu::Buffer,
    if_prefix_a: &wgpu::Buffer,
    if_prefix_b: &wgpu::Buffer,
    if_block_prefix: &wgpu::Buffer,
    if_depth: &wgpu::Buffer,
) -> Result<IfDepthBindGroups> {
    let clear = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_if_depth_01_clear"),
        clear_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("if_delta", if_delta.as_entire_binding()),
        ],
    )?;

    let mark = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_if_depth_02_mark"),
        mark_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            ("hir_token_end", hir_token_end_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("token_words", token_buf.as_entire_binding()),
            ("token_count", token_count_buf.as_entire_binding()),
            ("if_delta", if_delta.as_entire_binding()),
        ],
    )?;

    let local = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_if_depth_03_local"),
        local_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("if_delta", if_delta.as_entire_binding()),
            ("if_depth_inblock", if_depth_inblock.as_entire_binding()),
            ("block_sum", if_block_sum.as_entire_binding()),
        ],
    )?;

    let n_blocks = (if_block_sum.size() / 4).min(u32::MAX as u64) as u32;
    let n_items = n_blocks.saturating_mul(256);
    let (hierarchy_up, hierarchy_down) = create_fixed_scan_hierarchy_bind_groups(
        device,
        "type_check.if_depth",
        hierarchy_up_pass,
        hierarchy_down_pass,
        n_items,
        n_blocks,
        if_block_sum,
        if_prefix_a,
        if_prefix_b,
        if_block_prefix,
    )?;

    let apply = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_if_depth_05_apply"),
        apply_pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("if_depth_inblock", if_depth_inblock.as_entire_binding()),
            ("block_prefix", if_block_prefix.as_entire_binding()),
            ("if_depth", if_depth.as_entire_binding()),
        ],
    )?;

    Ok(IfDepthBindGroups {
        clear,
        mark,
        local,
        hierarchy_up,
        hierarchy_down,
        apply,
    })
}

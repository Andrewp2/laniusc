use super::super::*;

/// Builds the reflected source-name schedule. All buffer relations come from
/// the compiler graph; only capacity-dependent hash parameters are local.
pub(in crate::type_checker) fn create_name_bind_groups(
    passes: &TypeCheckPasses,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    device: &wgpu::Device,
    source_len: u32,
    name_capacity: u32,
    name_blocks: u32,
    resources: &ResourceMap<'_>,
) -> Result<NameBindGroups> {
    let mut compaction_resources = resources.clone();
    for (binding, resource) in [
        ("name_order_in", "name_hash_lo"),
        ("name_order_tmp", "name_hash_hi"),
        ("name_count_out", "name_scan_total"),
        ("name_max_len_out", "name_max_len"),
    ] {
        compaction_resources.alias(binding, resource)?;
    }
    let compaction = CompactionOperation::indirect(
        device,
        graph,
        &compaction_resources,
        passes,
        NAME_COMPACTION,
        &typed_buffer_from_resources(resources, "token_active_dispatch_args")?,
    )?;

    let mut name_resources = compaction_resources.to_binding_map();

    let hash_work_items = name_blocks
        .max(1)
        .saturating_mul(NAME_HASH_TABLE_ROWS_PER_BLOCK);
    let hash_params = uniform_from_val(
        device,
        "type_check.names.hash.params",
        &NameHashParams {
            name_count: name_capacity,
            source_len,
            table_half_capacity: hash_work_items,
            reserved: 0,
        },
    );
    name_resources.insert("gParams".into(), hash_params.as_entire_binding());
    name_resources.insert("name_count_in".into(), resources["name_scan_total"].clone());
    let hash = |label, kernel| {
        reflected_bind_group_from_resources(device, label, &passes.kernel(kernel), &name_resources)
    };
    let hash_prepare = hash(
        "type_check_names_hash_00_prepare",
        "type_checker/names/hash/00_prepare",
    )?;
    let hash_insert = hash(
        "type_check_names_hash_01_insert",
        "type_checker/names/hash/01_insert",
    )?;
    let hash_assign_ids = hash(
        "type_check_names_hash_02_assign_ids",
        "type_checker/names/hash/02_assign_ids",
    )?;

    Ok(NameBindGroups {
        compaction,
        hash_work_items,
        _hash_params: hash_params,
        hash_prepare,
        hash_insert,
        hash_assign_ids,
    })
}

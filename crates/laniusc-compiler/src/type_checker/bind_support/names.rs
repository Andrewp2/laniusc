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
    let mut hash_resources = resources.clone();
    hash_resources.buffer("gParams", &hash_params);
    let hash = |name, kernel| {
        ComputeOperation::direct(
            device,
            graph,
            &hash_resources,
            name,
            &passes.kernel(kernel),
            hash_work_items,
        )
    };
    let hash_prepare = hash(
        compiler_graph::NAMES_HASH_PREPARE_PASS,
        "type_checker/names/hash/00_prepare",
    )?;
    let hash_insert = hash(
        compiler_graph::NAMES_HASH_INSERT_PASS,
        "type_checker/names/hash/01_insert",
    )?;
    let hash_assign_ids = hash(
        compiler_graph::NAMES_HASH_ASSIGN_PASS,
        "type_checker/names/hash/02_assign_ids",
    )?;

    Ok(NameBindGroups {
        compaction,
        _hash_params: hash_params,
        hash_prepare,
        hash_insert,
        hash_assign_ids,
    })
}

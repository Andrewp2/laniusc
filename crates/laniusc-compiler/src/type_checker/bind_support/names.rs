use super::super::*;

/// Builds the reflected source-name schedule. All buffer relations come from
/// the compiler graph; only capacity-dependent hash parameters are local.
pub(in crate::type_checker) fn create_name_bind_groups(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    source_len: u32,
    name_capacity: u32,
    name_blocks: u32,
    resources: &ResourceMap<'_>,
) -> Result<NameBindGroups> {
    let mark = reflected_bind_group_from_resources(
        device,
        "type_check_names_00_mark_lexemes",
        &passes.kernel("type_checker/names/00_mark_lexemes"),
        resources,
    )?;
    let scan =
        PrefixScanOperation::from_spec(device, passes, resources, compiler_graph::NAMES_SCAN)?;

    let mut name_resources = resources.to_binding_map();
    for (binding, resource) in [
        ("name_order_in", "name_hash_lo"),
        ("name_order_tmp", "name_hash_hi"),
        ("name_count_out", "name_scan_total"),
        ("name_max_len_out", "name_max_len"),
    ] {
        name_resources.insert(binding.into(), resources[resource].clone());
    }
    let scatter = reflected_bind_group_from_resources(
        device,
        "type_check_names_01_scatter_lexemes",
        &passes.kernel("type_checker/names/01_scatter_lexemes"),
        &name_resources,
    )?;

    let hash_work_items = name_blocks.max(1).saturating_mul(NAME_RADIX_BUCKETS);
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
        mark,
        scan,
        scatter,
        hash_work_items,
        _hash_params: hash_params,
        hash_prepare,
        hash_insert,
        hash_assign_ids,
    })
}

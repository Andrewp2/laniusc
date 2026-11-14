// Export step 10: one lane per declaration row. Stages the declaration's
// directory entry (RT_DIR_WORDS uint4, see docs/compiler-program-retention.md):
// its kind and parent, its binder map, its signature block, its nominal
// schema block, its body segment and its range of use records.
//
// Binder maps compose the chain's parameters by domain: an impl's type
// parameters before its method's, then the impl's constant parameters before
// the method's, including unused ones. A trait and its required members end
// the type domain with the trait's implicit Self.
import hir_records;
import primitive_types;
import type_checker.canonical.canonical_api;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.common;
import type_checker.retention.export.side_tables;
import type_checker.retention.export.type_rows;

StructuredBuffer<uint> compact_fn_return_type;

uint2 domain_counts(uint owner)
{
    if (!valid_row(owner)) return uint2(0u, 0u);
    HirRange range = compact_generic_param_ranges[owner];
    uint2 counts = uint2(0u, 0u);
    for (uint index = range.start; index < range.start + range.count; index++)
    {
        uint kind = compact_generic_params[index].kind;
        if (kind == GENERIC_PARAM_KIND_TYPE) counts.x++;
        else if (kind == GENERIC_PARAM_KIND_CONST) counts.y++;
    }
    return counts;
}

// Writes an owner's parameters at the domain cursors; false when one has no
// ParamId (an owner that step 1 could not identify).
bool write_owner(uint owner, uint base, uint type_count, inout uint2 cursor)
{
    if (!valid_row(owner)) return true;
    HirRange range = compact_generic_param_ranges[owner];
    bool complete = true;
    for (uint index = range.start; index < range.start + range.count; index++)
    {
        HirGenericParam param = compact_generic_params[index];
        uint id = param_map_find(param.name_token);
        if (id == RT_INVALID) complete = false;
        if (param.kind == GENERIC_PARAM_KIND_TYPE) rt_binders[base + cursor.x++] = id;
        else if (param.kind == GENERIC_PARAM_KIND_CONST) rt_binders[base + type_count + cursor.y++] = id;
    }
    return complete;
}

uint token_rows()
{
    uint count; uint stride;
    decl_id_by_name_token.GetDimensions(count, stride);
    return count;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = export_lane(dtid);
    if (row >= hir_count() || rt_x_flags[row].z == 0u) return;
    uint dir_base = rt_x_counts[RT_X_BASE + RT_A_DIR];
    if (dir_base == RT_INVALID) return;
    uint4 scan = rt_x_scan[row];
    uint entry = dir_base + scan.z;
    uint decl = rt_x_row[row].x;
    HirCore core = compact_hir_core[row];
    HirLinks links = compact_hir_links[row];
    HirPayload payload = compact_hir_payload[row];

    uint container = core.kind == HIR_FN ? container_of(row) : 0xffffffffu;
    bool in_trait = is_trait_row(container);
    uint kind = 0u;
    if (core.kind == HIR_FN)
    {
        if (in_trait) kind = RT_DECL_REQUIRED_MEMBER;
        else if (valid_row(container)) kind = RT_DECL_METHOD;
        else if (payload.a == HIR_ITEM_KIND_EXTERN_FN) kind = RT_DECL_EXTERN_FN;
        else kind = RT_DECL_FREE_FN;
    }
    else if (core.kind == HIR_STRUCT_ITEM) kind = RT_DECL_STRUCT;
    else if (core.kind == HIR_ENUM_ITEM) kind = RT_DECL_ENUM;
    else if (core.kind == HIR_IMPL) kind = RT_DECL_IMPL;
    else kind = RT_DECL_TRAIT;
    uint parent = valid_row(container) ? rt_x_row[container].x : 0u;
    if (parent == RT_INVALID) parent = 0u;

    // Binder map.
    uint outer = valid_row(container) ? container : 0xffffffffu;
    uint self_trait = kind == RT_DECL_TRAIT ? row : (in_trait ? container : 0xffffffffu);
    uint2 counts = domain_counts(outer) + domain_counts(row);
    uint type_count = counts.x + (self_trait != 0xffffffffu ? 1u : 0u);
    uint binder_base = rt_alloc(RT_A_BINDERS, type_count + counts.y);
    if (binder_base != RT_INVALID)
    {
        uint2 cursor = uint2(0u, 0u);
        bool complete = write_owner(outer, binder_base, type_count, cursor);
        complete = write_owner(row, binder_base, type_count, cursor) && complete;
        if (self_trait != 0xffffffffu)
        {
            uint owner_token = hir_generic_owner_token(compact_hir_core[self_trait], compact_hir_payload[self_trait], token_rows());
            uint self_param = owner_token == 0xffffffffu ? RT_INVALID : param_map_find(owner_token);
            if (self_param == RT_INVALID) complete = false;
            rt_binders[binder_base + cursor.x] = self_param;
        }
        if (!complete)
        {
            rt_invariant(RT_INV_PARAM_OWNER);
            stat_add(row, RT_STAT_UNTRANSLATED, 1u);
        }
    }

    // Signature: the result term, then one term per parameter (step 13).
    uint sig_base = RT_INVALID;
    uint param_count = 0u;
    uint schema_base = RT_INVALID;
    uint schema_count = 0u;
    if (core.kind == HIR_FN)
    {
        param_count = side_lower_bound(RT_SIDE_PARAMS, row + 1u) - side_lower_bound(RT_SIDE_PARAMS, row);
        sig_base = rt_alloc(RT_A_SIGS, 1u + param_count);
        if (sig_base != RT_INVALID)
        {
            uint result_row = compact_fn_return_type[row];
            uint result = valid_row(result_row) ? type_row_term(result_row) : SCALAR_UNIT;
            if (!rt_is_resolved(result)) stat_add(row, RT_STAT_UNTRANSLATED, 1u);
            else if (!owned_by(result, decl, parent)) { stat_add(row, RT_STAT_OWNERSHIP, 1u); rt_invariant(RT_INV_OWNERSHIP); }
            rt_sigs[sig_base] = result;
        }
    }
    else if (core.kind == HIR_STRUCT_ITEM)
    {
        schema_count = side_lower_bound(RT_SIDE_FIELDS, row + 1u) - side_lower_bound(RT_SIDE_FIELDS, row);
        schema_base = rt_alloc(RT_A_SCHEMA, schema_count);
    }
    else if (core.kind == HIR_ENUM_ITEM)
    {
        uint first = payload_lower_bound(variant_lower_bound(row));
        schema_count = payload_lower_bound(variant_lower_bound(row + 1u)) - first;
        schema_base = rt_alloc(RT_A_SCHEMA, schema_count);
    }

    // Body segment.
    uint segment = RT_INVALID;
    if (rt_x_flags[row].w != 0u && rt_x_counts[RT_X_BASE + RT_A_SEGMENTS] != RT_INVALID &&
        rt_x_counts[RT_X_BASE + RT_A_SEG_ROWS] != RT_INVALID)
    {
        segment = rt_x_counts[RT_X_BASE + RT_A_SEGMENTS] + scan.w;
        uint count = links.subtree_end - row;
        uint retained_rows = scan_at(links.subtree_end).x - scan.x;
        if (retained_rows != count)
        {
            rt_invariant(RT_INV_SEGMENT);
            stat_add(row, RT_STAT_FOREIGN, 1u);
        }
        uint4 low = uint4(0u, 0u, 0u, 0u);
        uint4 high = uint4(0u, 0u, 0u, 0u);
        uint side_total = 0u;
        for (uint k = 0u; k < RT_SIDE_TABLES; k++)
        {
            uint len = side_lower_bound(k, row + count) - side_lower_bound(k, row);
            side_total += len;
            if (k == 0u) low.x = len; else if (k == 1u) low.y = len; else if (k == 2u) low.z = len;
            else if (k == 3u) low.w = len; else if (k == 4u) high.x = len; else if (k == 5u) high.y = len;
            else high.z = len;
        }
        high.w = rt_x_span[row] > core.token_start ? rt_x_span[row] - core.token_start : 0u;
        uint side_base = rt_alloc(RT_A_SEG_SIDE, RT_SIDE_WORDS * side_total);
        rt_segments[segment * RT_SEG_WORDS + 0u] =
            uint4(decl, rt_x_counts[RT_X_BASE + RT_A_SEG_ROWS] + scan.x, count, side_base);
        rt_segments[segment * RT_SEG_WORDS + 1u] = low;
        rt_segments[segment * RT_SEG_WORDS + 2u] = high;
        rt_segments[segment * RT_SEG_WORDS + 3u] = uint4(0u, 0u, 0u, 0u);
    }

    uint use_base = rt_x_counts[RT_X_BASE + RT_A_USES];
    uint use_start = use_base == RT_INVALID ? RT_INVALID : use_base + scan.y;
    uint use_count = core.kind == HIR_FN ? scan_at(links.subtree_end).y - scan.y : 0u;
    rt_dir[entry * RT_DIR_WORDS + 0u] = uint4(decl, kind, parent, 1u);
    rt_dir[entry * RT_DIR_WORDS + 1u] = uint4(binder_base, type_count | (counts.y << 16u), sig_base, param_count);
    rt_dir[entry * RT_DIR_WORDS + 2u] = uint4(segment, schema_base, schema_count, use_start);
    rt_dir[entry * RT_DIR_WORDS + 3u] = uint4(use_count, links.file_id, rt_counts[RT_C_JOBS], 0u);
    rt_x_row[row] = uint4(decl, entry, segment, core.kind == HIR_FN ? sig_base : schema_base);
}

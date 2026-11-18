// Export step 10: one lane per declaration row. Stages the declaration's
// directory entry (RT_DIR_WORDS uint4, see docs/compiler-program-retention.md):
// its kind and parent, its binder map, its signature block, its nominal
// schema block, its body segment and its range of use records.
//
// Binder maps compose the chain's parameters by domain: an impl's type
// parameters before its method's, then the impl's constant parameters before
// the method's, including unused ones. A trait and its required members end
// the type domain with the trait's implicit Self.
import shared.syntax.hir_records;
import shared.semantics.primitive_types;
import type_checker.canonicalization.canonical_api;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.export_lane_index;
import type_checker.retention.export_rows.retained_body_side_tables;
import type_checker.retention.export_types.retained_export_type_rows;
import type_checker.retention.export_rows.retained_body_source_tables;
import type_checker.retention.retained_row_classes;

StructuredBuffer<uint> compact_fn_return_type;
StructuredBuffer<uint> compact_const_type;
StructuredBuffer<uint> compact_const_value;
StructuredBuffer<uint> semantic_function_native_abi_by_hir;

void check_term(uint row, uint term, uint decl, uint parent)
{
    if (!rt_is_resolved(term)) stat_add(row, RT_STAT_UNTRANSLATED, 1u);
    else if (!owned_by(term, decl, parent)) { stat_add(row, RT_STAT_OWNERSHIP, 1u); rt_invariant(RT_INV_OWNERSHIP); }
}

// Canonical impl payloads store the self type in c for both inherent and
// trait impls. No method or sibling scan is needed.
uint impl_self_row(uint row)
{
    uint self_row = compact_hir_payload[row].c;
    return valid_row(self_row) && compact_hir_core[self_row].kind == HIR_TYPE
        ? self_row : 0xffffffffu;
}

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
    else if (core.kind == HIR_CONST_ITEM) kind = RT_DECL_CONST;
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

    // Signature block: a function's result term, then one term per
    // parameter (step 13); an impl's self type, then its trait term or
    // RT_NONE; a constant's type. Schema block: a struct's fields, an
    // enum's variants then their payloads (step 13), a constant's value.
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
            check_term(row, result, decl, parent);
            rt_sigs[sig_base] = result;
        }
        if (kind == RT_DECL_EXTERN_FN)
        {
            schema_count = 1u;
            schema_base = rt_alloc(RT_A_SCHEMA, 1u);
            if (schema_base != RT_INVALID)
                rt_schema[schema_base] = uint4(decl, RT_SCHEMA_NATIVE_ABI,
                    semantic_function_native_abi_by_hir[row], 0u);
        }
    }
    else if (core.kind == HIR_IMPL)
    {
        param_count = 1u;
        sig_base = rt_alloc(RT_A_SIGS, 2u);
        if (sig_base != RT_INVALID)
        {
            uint self_term = type_row_term(impl_self_row(row));
            check_term(row, self_term, decl, 0u);
            // The checker publishes no type for a trait reference row. Step
            // write_retained_trait_facts interns a trait impl's trait term from its accepted trait
            // reference and checks it; RT_UNKNOWN until then.
            uint trait_term = valid_row(payload.b) ? RT_UNKNOWN : RT_NONE;
            rt_sigs[sig_base] = self_term;
            rt_sigs[sig_base + 1u] = trait_term;
        }
    }
    else if (core.kind == HIR_CONST_ITEM)
    {
        sig_base = rt_alloc(RT_A_SIGS, 1u);
        if (sig_base != RT_INVALID)
        {
            uint type_row = compact_const_type[row];
            uint term = valid_row(type_row) ? type_row_term(type_row)
                : translate_checked(semantic_expr_ref_tag_by_hir[row], semantic_expr_ref_payload_by_hir[row]);
            check_term(row, term, decl, 0u);
            rt_sigs[sig_base] = term;
        }
        // Folding publishes on the initializer expression, not the item.
        uint initializer = compact_const_value[row];
        uint present = valid_row(initializer) ? semantic_value_const_present_by_hir[initializer] : 0u;
        bool concrete = (present & RT_CONST_CONCRETE) != 0u;
        if (!concrete) stat_add(row, RT_STAT_UNTRANSLATED, 1u);
        schema_count = 1u;
        schema_base = rt_alloc(RT_A_SCHEMA, 1u);
        if (schema_base != RT_INVALID)
        {
            uint2 value = concrete ? semantic_value_const_by_hir[initializer] : uint2(0u, 0u);
            rt_schema[schema_base] = uint4(decl, RT_SCHEMA_CONST | (concrete ? 0x100u : 0u),
                value.x, value.y);
        }
    }
    else if (core.kind == HIR_STRUCT_ITEM)
    {
        schema_count = side_lower_bound(RT_SIDE_FIELDS, row + 1u) - side_lower_bound(RT_SIDE_FIELDS, row);
        param_count = schema_count;
        schema_base = rt_alloc(RT_A_SCHEMA, schema_count);
    }
    else if (core.kind == HIR_ENUM_ITEM)
    {
        uint first_variant = variant_lower_bound(row);
        uint variants = variant_lower_bound(row + 1u) - first_variant;
        uint first = payload_lower_bound(first_variant);
        param_count = variants;
        schema_count = variants + payload_lower_bound(first_variant + variants) - first;
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
        uint first_token = core.token_start;
        uint tokens = rt_x_span[row] > first_token ? rt_x_span[row] - first_token : 0u;
        high.w = tokens;
        uint side_base = rt_alloc(RT_A_SEG_SIDE, RT_SIDE_WORDS * side_total);
        // Source provenance: the body's text and one record per token,
        // filled by steps 12b/12c; the file key is (library, unit, file).
        uint2 text = body_text_range(first_token, tokens);
        uint text_words = (text.y - text.x + 3u) >> 2u;
        uint text_base = rt_alloc(RT_A_SEG_BYTES, text_words);
        uint token_base = rt_alloc(RT_A_SEG_TOKENS, tokens);
        uint file_start = job_file_start(links.file_id);
        rt_segments[segment * RT_SEG_WORDS + 0u] =
            uint4(decl, rt_x_counts[RT_X_BASE + RT_A_SEG_ROWS] + scan.x, count, side_base);
        rt_segments[segment * RT_SEG_WORDS + 1u] = low;
        rt_segments[segment * RT_SEG_WORDS + 2u] = high;
        rt_segments[segment * RT_SEG_WORDS + 3u] = uint4(0u, 0u, 0u, 0u);
        rt_segments[segment * RT_SEG_WORDS + 4u] =
            uint4(links.file_id, text.x >= file_start ? text.x - file_start : 0u, text.y - text.x, token_base);
        rt_segments[segment * RT_SEG_WORDS + 5u] = uint4(text_base, 0u, 0u, 0u);
        rt_x_seg_token[scan.w] = first_token;
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

// Export step 13: one lane per index of the parameter, field and variant-
// payload tables. Fills the signature and schema blocks step 10 reserved:
//   rt_sigs[sig base + 1 + ordinal]   a function parameter's declared term
//   rt_schema[schema base + i]        (nominal DeclId, kind | ordinal << 8,
//                                      variant ordinal, declared term)
// with kind RT_SCHEMA_FIELD or RT_SCHEMA_PAYLOAD. Every term must be owned
// by the declaration's binder chain.
import hir_records;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.export_lane_index;
import type_checker.retention.export_rows.retained_body_side_tables;
import type_checker.retention.export_types.retained_export_type_rows;

StructuredBuffer<uint> semantic_param_ref_tag_by_row;
StructuredBuffer<uint> semantic_param_ref_payload_by_row;


// A required trait member's `self` or `&self` receiver: the checker
// publishes no term for it. It is the trait's implicit Self, or a reference
// to it, by the method's receiver mode.
uint required_receiver_term(uint function, uint ordinal)
{
    uint trait_row, self_leaf;
    uint mode = required_receiver(function, ordinal, trait_row, self_leaf);
    if (mode == RECEIVER_SELF) return self_leaf;
    if (mode != RECEIVER_REF_SELF) return RT_UNKNOWN;
    uint term = rt_x_ref_self[trait_row].y;
    return rt_is_stored_term(term) ? term : RT_UNKNOWN;
}

void check(uint row, uint term, uint decl, uint parent)
{
    if (!rt_is_resolved(term)) stat_add(row, RT_STAT_UNTRANSLATED, 1u);
    else if (!owned_by(term, decl, parent))
    {
        stat_add(row, RT_STAT_OWNERSHIP, 1u);
        rt_invariant(RT_INV_OWNERSHIP);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = export_lane(dtid);
    if (lane < side_rows(RT_SIDE_PARAMS))
    {
        HirParam param = compact_params[lane];
        uint owner = param.owner;
        if (valid_row(owner) && compact_hir_core[owner].kind == HIR_FN && rt_x_row[owner].y != RT_INVALID)
        {
            uint4 info = rt_x_row[owner];
            uint4 d0 = rt_dir[info.y * RT_DIR_WORDS + 0u];
            uint4 d1 = rt_dir[info.y * RT_DIR_WORDS + 1u];
            uint ordinal = lane - side_lower_bound(RT_SIDE_PARAMS, owner);
            if (d1.z != RT_INVALID && ordinal < d1.w)
            {
                uint term = translate_checked(semantic_param_ref_tag_by_row[lane], semantic_param_ref_payload_by_row[lane]);
                if (term == RT_NONE || term == RT_UNKNOWN)
                {
                    uint receiver = required_receiver_term(owner, ordinal);
                    if (receiver != RT_UNKNOWN) term = receiver;
                }
                check(owner, term, d0.x, d0.z);
                rt_sigs[d1.z + 1u + ordinal] = term;
            }
        }
    }
    if (lane < side_rows(RT_SIDE_FIELDS))
    {
        HirField field = compact_fields[lane];
        uint owner = field.owner;
        if (valid_row(owner) && compact_hir_core[owner].kind == HIR_STRUCT_ITEM && rt_x_row[owner].y != RT_INVALID)
        {
            uint entry = rt_x_row[owner].y;
            uint4 d0 = rt_dir[entry * RT_DIR_WORDS + 0u];
            uint4 d2 = rt_dir[entry * RT_DIR_WORDS + 2u];
            uint ordinal = lane - side_lower_bound(RT_SIDE_FIELDS, owner);
            if (d2.y != RT_INVALID && ordinal < d2.z)
            {
                uint term = type_row_term(field.value);
                check(owner, term, d0.x, d0.z);
                rt_schema[d2.y + ordinal] = uint4(d0.x, RT_SCHEMA_FIELD | (field.ordinal << 8u), 0u, term);
            }
        }
    }
    if (lane < variant_payload_rows())
    {
        HirVariantPayload payload = compact_variant_payloads[lane];
        if (payload.variant < variant_rows())
        {
            HirVariant variant = compact_variants[payload.variant];
            uint owner = variant.owner;
            if (valid_row(owner) && compact_hir_core[owner].kind == HIR_ENUM_ITEM && rt_x_row[owner].y != RT_INVALID)
            {
                uint entry = rt_x_row[owner].y;
                uint4 d0 = rt_dir[entry * RT_DIR_WORDS + 0u];
                uint4 d2 = rt_dir[entry * RT_DIR_WORDS + 2u];
                uint4 d1 = rt_dir[entry * RT_DIR_WORDS + 1u];
                uint ordinal = d1.w + lane - payload_lower_bound(variant_lower_bound(owner));
                if (d2.y != RT_INVALID && ordinal < d2.z)
                {
                    uint term = type_row_term(payload.type_node);
                    check(owner, term, d0.x, d0.z);
                    rt_schema[d2.y + ordinal] = uint4(d0.x, RT_SCHEMA_PAYLOAD | (payload.ordinal << 8u), variant.ordinal, term);
                }
            }
        }
    }
    // One record per variant, payloadless ones included: its payload count
    // and the block-relative index of its first payload record.
    if (lane < variant_rows())
    {
        HirVariant variant = compact_variants[lane];
        uint owner = variant.owner;
        if (valid_row(owner) && compact_hir_core[owner].kind == HIR_ENUM_ITEM && rt_x_row[owner].y != RT_INVALID)
        {
            uint entry = rt_x_row[owner].y;
            uint4 d0 = rt_dir[entry * RT_DIR_WORDS + 0u];
            uint4 d1 = rt_dir[entry * RT_DIR_WORDS + 1u];
            uint4 d2 = rt_dir[entry * RT_DIR_WORDS + 2u];
            uint first_variant = variant_lower_bound(owner);
            uint index = lane - first_variant;
            uint first_payload = payload_lower_bound(lane);
            uint payloads = payload_lower_bound(lane + 1u) - first_payload;
            if (d2.y != RT_INVALID && index < d1.w)
                rt_schema[d2.y + index] = uint4(d0.x, RT_SCHEMA_VARIANT | (variant.ordinal << 8u), payloads,
                    d1.w + first_payload - payload_lower_bound(first_variant));
        }
    }
}

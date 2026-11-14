// The checked type a type row (a field, a payload, a declared result)
// denotes, translated into the store.
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;

public StructuredBuffer<uint> semantic_type_ref_tag_by_hir;
public StructuredBuffer<uint> semantic_type_ref_payload_by_hir;
public StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
public StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;

public uint type_row_term(uint row)
{
    if (!valid_row(row)) return RT_NONE;
    uint term = translate_checked(semantic_type_ref_tag_by_hir[row], semantic_type_ref_payload_by_hir[row]);
    if (term == RT_NONE || term == RT_UNKNOWN)
    {
        uint fallback = translate_checked(semantic_expr_ref_tag_by_hir[row], semantic_expr_ref_payload_by_hir[row]);
        if (fallback != RT_NONE) term = fallback;
    }
    return term;
}

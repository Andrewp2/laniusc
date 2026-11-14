// Export step 1b: one lane per HIR row and per enum variant. Maps each
// declaration's name token to its row (row + 1) and each variant's name
// token to RT_X_VARIANT_BIT | variant index, so a checked value binding
// (semantic_value_decl_by_hir, a declaration token) resolves to a
// declaration identity instead of a job-local token. Marks each call's
// callee row.
import hir_records;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.common;
import type_checker.retention.export.side_tables;

void map_token(uint token, uint value)
{
    uint count; uint stride;
    rt_x_decl_by_token.GetDimensions(count, stride);
    if (token < count) rt_x_decl_by_token[token] = value;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = export_lane(dtid);
    if (lane < hir_count() && decl_row(lane) && compact_hir_core[lane].kind != HIR_IMPL)
        map_token(compact_hir_payload[lane].b, lane + 1u);
    if (lane < hir_count() && compact_hir_core[lane].kind == HIR_CALL_EXPR)
    {
        uint callee = compact_hir_payload[lane].a;
        uint count; uint stride;
        rt_x_callee.GetDimensions(count, stride);
        if (callee < count) rt_x_callee[callee] = 1u;
    }
    if (lane < variant_rows()) map_token(compact_variants[lane].name_token, RT_X_VARIANT_BIT | lane);
}

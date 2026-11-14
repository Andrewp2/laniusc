// Export step 2: one lane per HIR row. Interns each declaration row's
// DeclId, the implicit `Self` parameter of each trait (owner = the trait,
// synthetic ordinal RT_SELF_ORDINAL, mapped from the trait's owner token),
// and writes the four scan flags (retention_job.slang). A row of a retained
// body raises its function's token end, so the body's token span is known
// without walking the body.
import hir_records;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.common;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = export_lane(dtid);
    if (row >= hir_count()) return;
    HirCore core = compact_hir_core[row];
    uint decl = RT_INVALID;
    bool declares = decl_row(row);
    if (declares)
    {
        decl = intern_row_decl(row);
        if (is_trait_row(row) && decl != RT_INVALID)
        {
            uint tokens; uint stride;
            decl_id_by_name_token.GetDimensions(tokens, stride);
            uint owner_token = hir_generic_owner_token(core, compact_hir_payload[row], tokens);
            uint self_param = rt_intern_param(decl, RT_DOMAIN_TYPE, RT_SELF_ORDINAL, 0u);
            if (owner_token != 0xffffffffu && self_param != RT_INVALID) param_map_insert(owner_token, self_param);
        }
    }
    rt_x_row[row] = uint4(decl, RT_INVALID, RT_INVALID, RT_INVALID);
    if (core.kind == HIR_FN && core.token_start < token_capacity()) rt_x_fn_by_token[core.token_start] = row + 1u;
    uint function = body_function(row);
    bool retained = function != 0xffffffffu && retained_body(function);
    uint4 flags = uint4(retained ? 1u : 0u,
        core.kind == HIR_CALL_EXPR && function != 0xffffffffu ? 1u : 0u,
        declares && decl != RT_INVALID ? 1u : 0u,
        retained && function == row ? 1u : 0u);
    rt_x_flags[row] = flags;
    if (retained && core.token_end != 0xffffffffu) InterlockedMax(rt_x_span[function], core.token_end);
}

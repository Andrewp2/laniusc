// Export step 1: one lane per generic parameter row. Interns the owner's
// DeclId and the ParamId (owner, domain, declared ordinal) with its declared
// scalar, and maps the parameter's declaration token to it. The ordinal
// counts the owner's own parameters of the same domain; an impl's
// parameters are never confused with its methods' because their owners
// differ. Type-alias parameters have no identity: aliases are normalized
// before any canonical term names them.
import hir_records;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.export_lane_index;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint index = export_lane(dtid);
    uint params; uint stride;
    compact_generic_params.GetDimensions(params, stride);
    if (index >= min(compact_generic_param_count[0u], params)) return;
    HirGenericParam param = compact_generic_params[index];
    if (!valid_row(param.owner)) return;
    if (compact_hir_core[param.owner].kind == HIR_TYPE_ALIAS_ITEM) return;
    bool constant = param.kind == GENERIC_PARAM_KIND_CONST;
    if (!constant && param.kind != GENERIC_PARAM_KIND_TYPE) return;
    uint owner = intern_row_decl(param.owner);
    if (owner == RT_INVALID)
    {
        rt_invariant(RT_INV_PARAM_OWNER);
        return;
    }
    HirRange range = compact_generic_param_ranges[param.owner];
    uint ordinal = 0u;
    for (uint other = range.start; other < index && other < range.start + range.count; other++)
        if (compact_generic_params[other].kind == param.kind) ordinal++;
    uint scalar = 0u;
    if (constant)
    {
        uint count; uint scalar_stride;
        type_const_param_scalar_by_token.GetDimensions(count, scalar_stride);
        scalar = param.name_token < count ? type_const_param_scalar_by_token[param.name_token] : 0u;
    }
    uint id = rt_intern_param(owner, constant ? RT_DOMAIN_CONST : RT_DOMAIN_TYPE, ordinal, scalar);
    if (id != RT_INVALID) param_map_insert(param.name_token, id);
}

// Dispatch after canonical primitive/path type refs exist and before either
// imported or local explicit argument binding. Repeat after alias normalization
// if it refines annotations. Final declaration checking rejects unresolved or
// non-scalar annotations; this pass never guesses from source spelling.
import hir_records;
import constant_value;
struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_generic_param_count;
StructuredBuffer<HirGenericParam> compact_generic_params;
StructuredBuffer<uint> compact_generic_param_types;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> type_const_param_scalar_by_token_out;
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 65535u * 256u;
    if (row >= min(compact_generic_param_count[0u], gParams.n_tokens)) return;
    HirGenericParam parameter = compact_generic_params[row];
    if (parameter.kind != 2u || parameter.name_token >= gParams.n_tokens) return;
    uint scalar = 0u;
    uint annotation = compact_generic_param_types[row];
    if (annotation < min(compact_hir_count[0u], gParams.n_hir_nodes))
    {
        uint token = compact_hir_core[annotation].token_start;
        if (token < gParams.n_tokens && type_expr_ref_tag[token] == 1u &&
            constant_scalar_is_supported(type_expr_ref_payload[token]))
            scalar = type_expr_ref_payload[token];
    }
    type_const_param_scalar_by_token_out[parameter.name_token] = scalar;
}

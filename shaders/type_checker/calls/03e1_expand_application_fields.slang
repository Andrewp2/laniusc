import type_checker.dependencies.constant_view;
// Expand accepted call returns and argument contexts after substitution.
// Field patterns use complete nominal receiver environments in caller scope.
#include "../type/instances/materialize_application_inputs.slang"
#include "../type/instances/materialize_application.slang"
#include "../type/instances/expand_materialized_instance.slang"
import type_checker.argument_context;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
StructuredBuffer<uint> argument_expected_ref_tag;
StructuredBuffer<uint> argument_expected_ref_payload;
StructuredBuffer<uint> call_arg_row_count_out;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_call_node;

uint call_token(uint call)
{
    if (call >= hir_count()) return INVALID;
    if (compact_hir_core[call].kind == 28u || compact_hir_core[call].kind == 33u)
        return compact_hir_core[call].token_start;
    if (compact_hir_core[call].kind != 19u) return INVALID;
    uint callee = compact_hir_payload[call].a;
    if (callee >= hir_count()) return INVALID;
    uint kind = compact_hir_core[callee].kind;
    if (kind != 21u && kind != 22u && kind != 33u) return INVALID;
    uint token = kind == 21u ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    return token < gParams.n_tokens ? token : compact_hir_core[callee].token_start;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    if (row >= hir_count()) return;
    for (uint family = 0u; family < 2u; family++)
    {
        uint root; uint token;
        if (family == 0u)
        {
            if (call_inference_result_tag[row] != 3u) continue;
            token = call_token(row);
            root = call_inference_result_payload[row];
        }
        else
        {
            if (row >= min(call_arg_row_count_out[0u], gParams.n_hir_nodes)) continue;
            uint node = argument_context_root(call_arg_row_node[row], hir_count(),
                compact_hir_core, compact_hir_payload);
            if (node >= hir_count() || argument_expected_ref_tag[node] != 3u) continue;
            token = call_token(call_arg_row_call_node[row]);
            root = argument_expected_ref_payload[node];
        }
        if (token >= gParams.n_tokens || root >= mutable_type_capacity()) continue;
        uint created[DEPTH_LIMIT]; uint count = 0u; uint failure;
        if (!expand_materialized_instance<MutableCheckedTypeGraph>(root, created, count, failure) &&
            (family == 0u || failure == 1u || failure == 2u))
            record_min_token_error(status, token, 6u, 0x474e0000u | failure);
    }
}

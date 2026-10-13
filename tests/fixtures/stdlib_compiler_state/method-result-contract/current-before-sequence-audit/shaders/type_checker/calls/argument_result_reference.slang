// A completed expression result is an argument value in caller scope. Preserve its
// whole reference before following identity-call argument shortcuts or reading
// declaration-only references. Legacy scalar codes cannot describe a wrapper.
import type_checker.concrete_type_closure;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;

bool argument_result_reference(uint node, out uint tag, out uint payload)
{
    tag = 0u; payload = 0xffffffffu;
    if (!valid_node(node)) return false;
    tag = call_inference_result_tag[node];
    payload = call_inference_result_payload[node];
    if ((tag == 1u && payload != 0u && payload != 0xffffffffu) ||
        (tag == 2u && payload < gParams.n_tokens && type_generic_param_slot_by_token[payload] != 0xffffffffu) ||
        (tag == 3u && payload < parameter_type_capacity() && type_instance_kind[payload] != 0u)) return true;
    if (compact_hir_core[node].kind != HIR_CALL_EXPR)
    { tag = 0u; payload = 0xffffffffu; return false; }
    uint instance = call_result_instance[node];
    if (concrete_instance_is_closed<ParameterTypeGraph>(instance, parameter_type_capacity()))
    { tag = 3u; payload = instance; return true; }
    tag = 0u; payload = 0xffffffffu; return false;
}

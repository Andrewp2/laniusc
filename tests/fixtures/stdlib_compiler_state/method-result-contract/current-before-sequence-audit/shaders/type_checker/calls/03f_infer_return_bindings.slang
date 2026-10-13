// Carry an expression's accepted complete type into an unannotated declaration.
// Initializers and result rows are immutable here; each statement owns its
// declaration, so name/index/member readers need no source-text inference.
import hir_records;
import type_checker.checked_scoped_types;
import type_checker.checked_type_graph;
import type_checker.scoped_type_equality;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_result_instance;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;
RWStructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> call_inference_state;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = dtid.x + dtid.y * 16776960u;
    uint count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (node >= count) return;
    uint kind = compact_hir_core[node].kind;
    HirPayload statement = compact_hir_payload[node];
    if ((kind != 7u && kind != 8u) || statement.a != 1u ||
        statement.b >= gParams.n_tokens || statement.d < count) return;
    uint initializer = statement.c;
    for (uint depth = 0u; depth < 64u && initializer < count; depth++)
    {
        uint kind = compact_hir_core[initializer].kind;
        HirPayload value = compact_hir_payload[initializer];
        if ((kind == 14u || kind == 16u || kind == 17u) && value.a == 1u)
            initializer = value.b;
        else break;
    }
    if (initializer >= count) return;
    uint initializer_kind = compact_hir_core[initializer].kind;
    uint tag = call_inference_result_tag[initializer];
    uint payload = call_inference_result_payload[initializer];
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    if (tag == 0u && initializer_kind == 19u)
    {
        payload = call_result_instance[initializer];
        if (!checked_instance_is_closed(payload)) return;
        tag = 3u;
    }
    if (tag != 1u && tag != 2u && tag != 3u) return;
    if ((tag == 1u && (payload == 0u || payload == 0xffffffffu)) ||
        (tag == 2u && (payload >= gParams.n_tokens || type_generic_param_slot_by_token[payload] == 0xffffffffu)) ||
        (tag == 3u && (payload >= capacity || type_instance_kind[payload] == 0u))) return;
    if (decl_type_ref_tag[statement.b] != tag || decl_type_ref_payload[statement.b] != payload)
    {
        uint previous_tag = decl_type_ref_tag[statement.b];
        uint previous_payload = decl_type_ref_payload[statement.b];
        bool changed = !scoped_type_refs_equal<ScopedCheckedTypeGraph>(
            previous_tag, previous_payload, 0xffffffffu, tag, payload, 0xffffffffu,
            checked_type_capacity(), gParams.n_tokens);
        decl_type_ref_tag[statement.b] = tag;
        decl_type_ref_payload[statement.b] = payload;
        if (changed)
        {
            uint ignored;
            InterlockedAdd(call_inference_state[1u], 1u, ignored);
        }
    }
    if (tag == 1u) visible_type[statement.b] = payload;
    if (initializer_kind != 19u) return;
    uint callee = compact_hir_payload[initializer].a;
    if (callee >= count) return;
    uint token = compact_hir_core[callee].kind == 21u
        ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    if (token >= gParams.n_tokens) token = compact_hir_core[callee].token_start;
    if (token < gParams.n_tokens && call_return_type[token] != 0u && call_return_type[token] != 0xffffffffu)
        visible_type[statement.b] = call_return_type[token];
}

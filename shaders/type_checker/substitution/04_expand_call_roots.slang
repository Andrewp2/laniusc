// Queue accepted call results and argument contexts as field-closure roots
// (ct_expand.slang), and re-queue deferred imported IDs whose declaration
// page is now resident. Runs at the start of each closure in the inference
// rounds, once per resident page.
import hir_records;
import status;
import dependency_interface;
import type_checker.argument_context;
import type_checker.mutable_checked_type_graph;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_mutable_rows;
import type_checker.substitution.ct_checked;
import type_checker.substitution.ct_expand;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
StructuredBuffer<uint> argument_expected_ref_tag;
StructuredBuffer<uint> argument_expected_ref_payload;
StructuredBuffer<uint> call_arg_row_count_out;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_call_node;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }

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

// The root of family 0 (call results) or 1 (argument contexts) at `row`, as
// (instance row, token), or INVALID.
uint2 root_of(uint row, uint family)
{
    if (family == 0u)
    {
        if (call_inference_result_tag[row] != 3u) return uint2(INVALID, INVALID);
        return uint2(call_inference_result_payload[row], call_token(row));
    }
    if (row >= min(call_arg_row_count_out[0u], gParams.n_hir_nodes)) return uint2(INVALID, INVALID);
    uint node = argument_context_root(call_arg_row_node[row], hir_count(),
        compact_hir_core, compact_hir_payload);
    if (node >= hir_count() || argument_expected_ref_tag[node] != 3u) return uint2(INVALID, INVALID);
    return uint2(argument_expected_ref_payload[node], call_token(call_arg_row_call_node[row]));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    ct_expand_begin_run(lane, 1u);
    uint lanes = max(hir_count(), 1u);
    if (lane >= lanes) return;
    // Deferred imported IDs: one lane per entry, striding over the HIR lanes.
    uint deferred = ct_expand_counts[CT_EXPAND_DEFERRED];
    for (uint entry = lane; entry < deferred; entry += lanes)
    {
        uint2 item = ct_expand_deferred[entry];
        uint3 words = ct_words(item.x);
        if (item.x == CT_NONE || dependency_find_declaration(words.x, words.y, words.z) == INVALID)
            continue;
        ct_expand_deferred[entry].x = CT_NONE;
        if (!ct_expand_append(item.x, item.y))
            record_min_token_error(status, ct_expand_token(item.y), 6u, 0x474e0001u);
    }
    if (lane >= hir_count()) return;
    uint spare = CT_NONE;
    for (uint family = 0u; family < 2u; family++)
    {
        uint2 root = root_of(lane, family);
        if (root.y >= gParams.n_tokens || root.x >= mutable_type_capacity()) continue;
        uint id = ct_intern_checked<CtMutableRows>(3u, root.x, spare);
        if (!ct_is_resolved(id)) continue;
        if (!ct_expand_push(id, ct_expand_word(root.y, 0u, family == 1u)))
            record_min_token_error(status, root.y, 6u, 0x474e0001u);
    }
}

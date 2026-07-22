// Mark dense compact-HIR call argument segments for semantic rows.
//
// This pass keeps argument discovery in the HIR record layer. It clears the
// dense row outputs and writes each call node's argument count as the scan
// input; the following scan/scatter passes publish compact per-call argument
// rows where row_start[call] + ordinal is stable even when nested call rows
// interleave in source/HIR order.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;

RWStructuredBuffer<uint> call_arg_row_scan_input;
RWStructuredBuffer<uint> call_arg_row_node;
RWStructuredBuffer<uint> call_arg_row_call_node;
RWStructuredBuffer<uint> call_arg_row_ordinal;
RWStructuredBuffer<uint> call_arg_row_start;
RWStructuredBuffer<uint> call_arg_row_count;
RWStructuredBuffer<uint> call_generic_return_arg_node;

static const uint INVALID = 0xffffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    uint n = active_hir_node_count();
    if (node >= n)
        return;

    call_arg_row_scan_input[node] =
        compact_hir_core[node].kind == HIR_CALL_EXPR
            ? compact_hir_payload[node].c
            : 0u;
    call_arg_row_start[node] = INVALID;
    call_arg_row_count[node] = 0u;
    call_generic_return_arg_node[node] = INVALID;
}

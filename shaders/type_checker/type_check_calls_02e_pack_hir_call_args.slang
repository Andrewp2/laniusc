// Pack parser-owned HIR call argument records into a token-indexed table.
//
// Input records come from `hir_call_fields.slang`, which is derived from
// production ids and inverted tree arrays. This pass preserves that structure
// for type checking without requiring call resolvers to scan comma/parens.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_start;
StructuredBuffer<uint> hir_call_arg_end;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> hir_call_arg_ordinal;

RWStructuredBuffer<uint4> call_arg_record;

static const uint INVALID = 0xffffffffu;
static const uint PARAM_CACHE_STRIDE = 16u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint call_arg_count_for_call(uint call_node)
{
    uint cached = hir_call_arg_count[call_node];
    if (cached != 0u)
        return cached;

    uint count = 0u;
    uint n = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < n; i += 1u)
    {
        if (hir_call_arg_parent_call[i] == call_node)
            count += 1u;
    }
    return count;
}

void publish_arg_record(uint callee_token, uint call_node, uint arg_node, uint arg_count)
{
    uint ordinal = hir_call_arg_ordinal[arg_node];
    if (ordinal >= PARAM_CACHE_STRIDE)
        return;

    uint arg_start = hir_token_pos[arg_node];
    uint arg_end = hir_call_arg_end[arg_node];
    uint row = callee_token * PARAM_CACHE_STRIDE + ordinal;
    if (arg_start == INVALID || arg_end == INVALID || arg_start >= arg_end)
        call_arg_record[row] = uint4(INVALID, INVALID, call_node, arg_count);
    else
        call_arg_record[row] = uint4(arg_start, arg_end, call_node, arg_count);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call_node = linear_thread_id(dtid);
    uint n = active_hir_node_count();
    if (call_node >= n)
        return;

    uint callee_node = hir_call_callee_node[call_node];
    if (callee_node == INVALID || callee_node >= n)
        return;

    uint callee_token = hir_token_pos[callee_node];
    if (callee_token == INVALID || callee_token >= gParams.n_tokens)
        return;

    uint arg_count = min(call_arg_count_for_call(call_node), PARAM_CACHE_STRIDE);
    uint base = callee_token * PARAM_CACHE_STRIDE;
    call_arg_record[base] = uint4(INVALID, INVALID, call_node, arg_count);

    uint first = hir_call_arg_start[call_node];
    if (first != INVALID && first < n && hir_call_arg_parent_call[first] == call_node)
    {
        uint scan = first;
        [loop]
        for (uint guard = 0u; guard < 256u && scan < n; guard += 1u)
        {
            if (hir_call_arg_parent_call[scan] == call_node)
                publish_arg_record(callee_token, call_node, scan, arg_count);
            scan += 1u;
        }
        return;
    }

    [loop]
    for (uint arg_node = 0u; arg_node < n; arg_node += 1u)
    {
        if (hir_call_arg_parent_call[arg_node] == call_node)
            publish_arg_record(callee_token, call_node, arg_node, arg_count);
    }
}

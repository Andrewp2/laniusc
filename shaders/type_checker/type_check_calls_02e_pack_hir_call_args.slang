// Pack parser-owned HIR call argument records into GPU call caches.
//
// Input records come from `hir_call_fields.slang`, which is derived from
// production ids and inverted tree arrays. This pass preserves that structure
// for type checking without requiring call resolvers to scan comma/parens. The
// summary record is keyed by callee token; argument nodes are scattered into a
// call-node/ordinal slot table for O(1) consumers.

import gpu_index;
import hir_records;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_call_arg_end;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_call_arg_parent_call;

RWStructuredBuffer<uint4> call_arg_record;
RWStructuredBuffer<uint> call_arg_node;

static const uint INVALID = 0xffffffffu;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes;
}

bool valid_node(uint node, uint n)
{
    return node != INVALID && node < n;
}

uint callee_token_for_call(uint call_node, uint n)
{
    if (!valid_node(call_node, n))
        return INVALID;

    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node, n))
        return INVALID;

    uint callee_token = hir_kind[callee_node] == HIR_MEMBER_EXPR
        ? hir_member_name_token[callee_node]
        : hir_token_pos[callee_node];
    return callee_token != INVALID && callee_token < gParams.n_tokens ? callee_token : INVALID;
}

void publish_zero_arg_call(uint call_node, uint n)
{
    uint callee_token = callee_token_for_call(call_node, n);
    if (callee_token == INVALID || hir_call_arg_count[call_node] != 0u)
        return;

    call_arg_record[callee_token] = uint4(INVALID, INVALID, call_node, 0u);
}

void publish_arg_record(uint callee_token, uint call_node, uint arg_node, uint arg_count)
{
    uint ordinal = hir_node_ordinal_ordinal(hir_call_arg_parent_call[arg_node]);
    call_arg_record[callee_token].z = call_node;
    call_arg_record[callee_token].w = arg_count;

    if (ordinal >= PARAM_CACHE_STRIDE)
        return;

    uint arg_start = hir_token_pos[arg_node];
    uint arg_end = hir_call_arg_end[arg_node];
    if (valid_node(call_node, gParams.n_hir_nodes))
        call_arg_node[call_node * PARAM_CACHE_STRIDE + ordinal] = arg_node;
    if (ordinal == 0u)
    {
        if (arg_start == INVALID || arg_end == INVALID || arg_start >= arg_end)
            call_arg_record[callee_token] = uint4(INVALID, INVALID, call_node, arg_count);
        else
            call_arg_record[callee_token] = uint4(arg_start, arg_end, call_node, arg_count);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    uint n = active_hir_node_count();
    if (node >= n)
        return;

    publish_zero_arg_call(node, n);

    uint call_node = hir_node_ordinal_node(hir_call_arg_parent_call[node]);
    if (!valid_node(call_node, n))
        return;

    uint callee_token = callee_token_for_call(call_node, n);
    if (callee_token == INVALID)
        return;

    uint arg_count = hir_call_arg_count[call_node];
    publish_arg_record(callee_token, call_node, node, arg_count);
}

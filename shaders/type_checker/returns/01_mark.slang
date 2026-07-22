// Mark compact-HIR direct return facts for enclosing functions and blocks.

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
StructuredBuffer<uint> compact_hir_nearest_block;
StructuredBuffer<uint> compact_hir_nearest_control;
StructuredBuffer<uint> compact_hir_nearest_fn;

RWStructuredBuffer<uint> return_fn_flags;
RWStructuredBuffer<uint> return_block_flags;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_BLOCK = 6u;
static const uint HIR_FN = 3u;
static const uint HIR_RETURN_STMT = 9u;
static const uint STMT_RECORD_KIND_RETURN = 2u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool return_statement_node(uint node)
{
    return valid_node(node) &&
           compact_hir_core[node].kind == HIR_RETURN_STMT &&
           compact_hir_payload[node].a == STMT_RECORD_KIND_RETURN;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!return_statement_node(node))
        return;

    uint block = compact_hir_nearest_block[node];
    if (valid_node(block) && compact_hir_core[block].kind == HIR_BLOCK)
        InterlockedMax(return_block_flags[block], 1u);

    uint fn_node = compact_hir_nearest_fn[node];
    if (!valid_node(fn_node) || compact_hir_core[fn_node].kind != HIR_FN)
        return;

    if (compact_hir_nearest_control[node] == INVALID)
        InterlockedMax(return_fn_flags[fn_node], 1u);
}

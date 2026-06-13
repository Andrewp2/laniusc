// Lift direct if/else return facts into the enclosing block and function rows.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_nearest_block_node;
StructuredBuffer<uint> hir_nearest_fn_node;
StructuredBuffer<uint> hir_stmt_record;
RWStructuredBuffer<uint> return_block_flags;

RWStructuredBuffer<uint> return_fn_flags;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_BLOCK = 6u;
static const uint HIR_FN = 3u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint STMT_RECORD_KIND_IF = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

bool return_statement_node(uint node)
{
    return valid_node(node) &&
           hir_stmt_record[stmt_slot(node, 0u)] == STMT_RECORD_KIND_RETURN;
}

bool returning_block(uint node)
{
    return valid_node(node) &&
           hir_kind[node] == HIR_BLOCK &&
           return_block_flags[node] != 0u;
}

bool returning_arm(uint node)
{
    return return_statement_node(node) || returning_block(node);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node) ||
        hir_stmt_record[stmt_slot(node, 0u)] != STMT_RECORD_KIND_IF)
        return;

    uint then_arm = hir_stmt_record[stmt_slot(node, 2u)];
    uint else_arm = hir_stmt_record[stmt_slot(node, 3u)];
    if (!returning_arm(then_arm) || !returning_arm(else_arm))
        return;

    uint block = hir_nearest_block_node[node];
    uint fn_node = hir_nearest_fn_node[node];
    if (!valid_node(block) || hir_kind[block] != HIR_BLOCK)
        return;

    InterlockedMax(return_block_flags[block], 1u);

    if (valid_node(fn_node) && hir_kind[fn_node] == HIR_FN && parent[block] == fn_node)
        InterlockedMax(return_fn_flags[fn_node], 1u);
}

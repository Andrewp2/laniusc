// Finalize parser-owned declaration scope ends from context relations.
//
// Statement records are identified before context propagation because context
// seeding uses those records. Once nearest-block context is available, this
// pass derives local declaration visibility from that parser-owned relation
// instead of from bounded parse-tree shape checks.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirStmtScope;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_nearest_block_node;
StructuredBuffer<uint> hir_token_end;

RWStructuredBuffer<uint> hir_stmt_scope_end;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_CONST = 4u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirStmtScope.uses_status_count != 0u
               ? min(gHirStmtScope.n, tree_count_status[5u])
               : gHirStmtScope.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    uint kind = hir_stmt_record[stmt_slot(node, 0u)];
    if (kind != STMT_RECORD_KIND_LET && kind != STMT_RECORD_KIND_CONST)
        return;

    uint block = hir_nearest_block_node[node];
    if (!valid_node(block))
        return;

    uint scope_end = hir_token_end[block];
    if (scope_end == 0u || scope_end == INVALID)
        return;

    hir_stmt_scope_end[node] = scope_end;
}

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

StructuredBuffer<uint> canonical_count;
StructuredBuffer<uint> canonical_dense_to_raw;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_canonical_nearest_block;
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint count = canonical_count[0u];
    if (row >= count)
        return;

    uint kind = hir_stmt_record[row * STMT_RECORD_STRIDE];
    if (kind != STMT_RECORD_KIND_LET && kind != STMT_RECORD_KIND_CONST)
        return;

    uint block = hir_canonical_nearest_block[row];
    if (block == INVALID || block >= count)
        return;

    uint node = canonical_dense_to_raw[row];
    uint block_node = canonical_dense_to_raw[block];
    if (node == INVALID || node >= gHirStmtScope.n ||
        block_node == INVALID || block_node >= gHirStmtScope.n)
        return;
    uint scope_end = hir_token_end[block_node];
    if (scope_end == 0u || scope_end == INVALID)
        return;

    hir_stmt_scope_end[node] = scope_end;
}

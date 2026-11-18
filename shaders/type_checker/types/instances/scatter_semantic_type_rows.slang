// Materialize the inverse of the compact-HIR type-node prefix relation. This
// turns a compact type ordinal into a dense HIR row in O(1).

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> type_semantic_scan_input;
StructuredBuffer<uint> type_semantic_prefix;
StructuredBuffer<uint> type_semantic_count_out;
RWStructuredBuffer<uint> type_semantic_row_by_ordinal;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    uint semantic_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (row >= semantic_count || type_semantic_scan_input[row] == 0u)
        return;

    uint ordinal = type_semantic_prefix[row];
    if (ordinal < type_semantic_count_out[0u])
        type_semantic_row_by_ordinal[ordinal] = row;
}

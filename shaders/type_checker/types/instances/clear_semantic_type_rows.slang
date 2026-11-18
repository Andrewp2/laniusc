// Clear the token-to-semantic-row map and type-row scan flags. The following
// mark pass projects parser-owned dense semantic preorder into this relation.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> type_semantic_row_by_token;
RWStructuredBuffer<uint> type_semantic_scan_input;
RWStructuredBuffer<uint> member_next_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (i < gParams.n_tokens)
        type_semantic_row_by_token[i] = INVALID;
    if (i < gParams.n_hir_nodes)
    {
        type_semantic_scan_input[i] = 0u;
        member_next_node[i] = INVALID;
    }
}

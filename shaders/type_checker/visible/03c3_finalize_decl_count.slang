// Publish the combined raw-HIR and compact match-payload declaration count.
// This is separate from payload scatter so every payload thread observes the
// unmodified raw scan total as its destination base.

import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_match_payload_row_count;
RWStructuredBuffer<uint> hir_visible_decl_count_out;
RWStructuredBuffer<uint> status;

static const uint ERR_NAME_LIMIT = 11u;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u || dtid.y != 0u || dtid.z != 0u)
        return;
    uint raw_count = min(hir_visible_decl_count_out[0u], gParams.n_tokens);
    uint payload_count = min(compact_match_payload_row_count[0u], gParams.n_hir_nodes);
    uint total = raw_count + payload_count;
    if (total < raw_count || total > gParams.n_tokens)
        record_min_token_error(status, 0u, ERR_NAME_LIMIT, total);
    hir_visible_decl_count_out[0u] = min(total, gParams.n_tokens);
}

// Select an alias-owned generic parameter when it belongs to the alias output
// component. The compact generic-parameter table supplies one independent lane
// per candidate.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_node;
StructuredBuffer<uint> generic_param_token;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> alias_equiv_parent;
RWStructuredBuffer<uint> alias_normalized_source;

static const uint INVALID = 0xffffffffu;
static const uint GENERIC_PARAM_KIND_TYPE = 1u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    uint count = min(generic_param_count_out[0u], gParams.n_tokens);
    if (row >= count || generic_param_kind[row] != GENERIC_PARAM_KIND_TYPE)
        return;
    uint owner = generic_param_owner_node[row];
    uint token = generic_param_token[row];
    if (owner >= gParams.n_hir_nodes || token >= gParams.n_tokens)
        return;
    uint output_node = gParams.n_tokens + owner;
    if (alias_equiv_parent[token] == alias_equiv_parent[output_node])
        atomic_u32_min(alias_normalized_source, owner, token);
}

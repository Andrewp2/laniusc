// Scatter parser-owned path segment rows into compact typechecker path storage.

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_path_segment_owner;
StructuredBuffer<uint> hir_path_segment_rank;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> name_id_by_token;
RWStructuredBuffer<uint> path_segment_name_id;
RWStructuredBuffer<uint> path_segment_token;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_hir_node_count() { return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]); }
uint active_path_count() { return min(path_count_out[0], gParams.n_hir_nodes); }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint segment = linear_thread_id(dtid);
    if (segment >= active_hir_node_count())
        return;

    uint owner = hir_path_segment_owner[segment];
    if (owner >= active_hir_node_count())
        return;
    uint path_slot = path_id_by_owner_hir[owner];
    if (path_slot >= active_path_count())
        return;
    uint ordinal = hir_path_segment_rank[segment];
    if (ordinal >= path_segment_count[path_slot])
        return;

    uint token = hir_token_pos[segment];
    if (token >= gParams.n_tokens || name_id_by_token[token] == INVALID)
        return;
    uint dst = path_segment_base[path_slot] + ordinal;
    if (dst >= gParams.n_tokens)
        return;
    path_segment_name_id[dst] = name_id_by_token[token];
    path_segment_token[dst] = token;
}

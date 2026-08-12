// Follow bounded runs in the canonical-root and reverse-subtree relations.

import gpu_index;

struct Params
{
    uint type_count;
    uint declaration_count;
    uint member_count;
    uint path_capacity;
    uint token_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> canonical_type_roots_in;
RWStructuredBuffer<uint> canonical_type_roots_out;
StructuredBuffer<uint> canonical_type_subtree_start_in;
RWStructuredBuffer<uint> canonical_type_subtree_start_out;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LINKS_PER_STEP = 16u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint type_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (type_i >= gParams.type_count)
        return;
    uint root = canonical_type_roots_in[type_i];
    uint subtree = canonical_type_subtree_start_in[type_i];
    bool root_done = root >= gParams.type_count;
    bool subtree_done = subtree >= gParams.type_count;
    if (root_done)
        root = type_i;
    if (subtree_done)
        subtree = type_i;
    for (uint hop = 0u; hop < LINKS_PER_STEP; ++hop)
    {
        if (!root_done)
        {
            uint next_root = canonical_type_roots_in[root];
            root_done = next_root == root || next_root >= gParams.type_count;
            if (next_root < gParams.type_count)
                root = next_root;
        }
        if (!subtree_done)
        {
            uint next_subtree = canonical_type_subtree_start_in[subtree];
            subtree_done = next_subtree == subtree || next_subtree >= gParams.type_count;
            if (next_subtree < gParams.type_count)
                subtree = next_subtree;
        }
    }
    canonical_type_roots_out[type_i] = root;
    canonical_type_subtree_start_out[type_i] = subtree;
}

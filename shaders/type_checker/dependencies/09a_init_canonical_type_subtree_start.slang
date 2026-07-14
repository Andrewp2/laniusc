// Seed the last-descendant relation for reverse-preorder canonical interface
// types. Interface construction guarantees that every direct child precedes
// its parent, so repeatedly following the final child reaches the first row of
// the parent's contiguous subtree.

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
StructuredBuffer<uint> dependency_type_words;
StructuredBuffer<uint> dependency_type_edge_words;
RWStructuredBuffer<uint> canonical_type_subtree_start;

static const uint TYPE_WORDS = 9u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint type_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (type_i >= gParams.type_count)
        return;
    uint base = type_i * TYPE_WORDS;
    uint first_edge = dependency_type_words[base + 3u];
    uint edge_count = dependency_type_words[base + 4u];
    uint last = edge_count == 0u
        ? type_i
        : dependency_type_edge_words[first_edge + edge_count - 1u];
    canonical_type_subtree_start[type_i] = last < gParams.type_count ? last : type_i;
}

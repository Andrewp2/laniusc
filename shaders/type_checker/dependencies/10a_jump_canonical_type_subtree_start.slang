// One pointer-doubling round over canonical last-child links. After
// ceil(log2(type_count)) rounds every row points at its deepest final child,
// which is the inclusive start of its reverse-preorder subtree.

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
StructuredBuffer<uint> canonical_type_subtree_start_in;
RWStructuredBuffer<uint> canonical_type_subtree_start_out;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint type_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (type_i >= gParams.type_count)
        return;
    uint next = canonical_type_subtree_start_in[type_i];
    canonical_type_subtree_start_out[type_i] = next < gParams.type_count
        ? canonical_type_subtree_start_in[next]
        : type_i;
}

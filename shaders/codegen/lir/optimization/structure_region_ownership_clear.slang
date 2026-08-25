// Clears the phase-local interval-stabbing tree. Leaves begin at
// `semantic_capacity`, so the standard iterative segment-tree representation
// uses exactly twice the node capacity and does not require power-of-two
// padding.

import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint hir_capacity;
    uint block_capacity;
    uint edge_capacity;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> opt_ir_region_ownership_tree;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint capacity = gParams.semantic_capacity * 2u;
    if (row < capacity) opt_ir_region_ownership_tree[row] = 0u;
}

// Seed compact HIR declaration key order.
//
// Scheduling contract:
// - Dispatch after compact HIR value-declaration records have been scattered.
// - Initializes the dense row order consumed by the radix passes.
// - This pass only touches compact declaration-table records; it does not
//   inspect source text, token spelling, helper names, or function bodies.

struct Params
{
    uint decl_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_visible_decl_count_out;

RWStructuredBuffer<uint> hir_visible_decl_key_order;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_decl_count()
{
    return min(hir_visible_decl_count_out[0], gParams.decl_capacity);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.decl_capacity)
        return;

    hir_visible_decl_key_order[i] = i < active_decl_count() ? i : INVALID;
}

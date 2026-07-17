// Seed pointer-doubling links for the generalized signature type forest.

struct Params { uint hir_capacity; uint decl_capacity; };
ConstantBuffer<Params> gParams;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> interface_type_parent;
RWStructuredBuffer<uint> interface_type_root_link;
RWStructuredBuffer<uint> interface_type_root_owner;

static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_hir_count() { return min(compact_hir_count[0u], gParams.hir_capacity); }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gParams.hir_capacity)
        return;
    if (node >= active_hir_count() || compact_hir_core[node].kind != HIR_TYPE)
    {
        interface_type_root_link[node] = INVALID;
        interface_type_root_owner[node] = INVALID;
        return;
    }
    uint parent = interface_type_parent[node];
    interface_type_root_link[node] = parent < active_hir_count() ? parent : INVALID;
    interface_type_root_owner[node] = parent < active_hir_count() ? INVALID : node;
}

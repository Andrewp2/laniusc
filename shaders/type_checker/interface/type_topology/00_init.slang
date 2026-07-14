// Initialize the public-signature type forest. Generic argument ownership is
// already a parser-produced direct parent relation; unary aggregate operands
// are attached by the following pass.

struct Params { uint hir_capacity; uint decl_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_type_arg_owner;
StructuredBuffer<uint> hir_type_arg_rank;
RWStructuredBuffer<uint> interface_type_parent;
RWStructuredBuffer<uint> interface_type_child_ordinal;
RWStructuredBuffer<uint> interface_type_seed_owner;
RWStructuredBuffer<uint> interface_type_index_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_hir_count() { return min(hir_status[5u], gParams.hir_capacity); }
bool type_node(uint node) { return node < active_hir_count() && hir_kind[node] == HIR_TYPE; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gParams.hir_capacity)
        return;
    uint owner = type_node(node) ? hir_type_arg_owner[node] : INVALID;
    interface_type_parent[node] = type_node(owner) ? owner : INVALID;
    interface_type_child_ordinal[node] = type_node(owner) ? hir_type_arg_rank[node] : INVALID;
    interface_type_seed_owner[node] = INVALID;
    interface_type_index_by_hir[node] = INVALID;
}

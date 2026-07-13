// Pointer-double type-root links. After ceil(log2(n)) parallel steps every
// type node owns the same topmost root as its entire generic-argument chain.

struct Params { uint n; uint uses_status_count; };
ConstantBuffer<Params> gHirType;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_type_root_link_in;
StructuredBuffer<uint> hir_type_root_owner_in;
RWStructuredBuffer<uint> hir_type_root_link_out;
RWStructuredBuffer<uint> hir_type_root_owner_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_node_count()
{
    return gHirType.uses_status_count != 0u
        ? min(gHirType.n, tree_count_status[5u]) : gHirType.n;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = tid.x + tid.y * MAX_GROUPS_X * WG_SIZE;
    uint active = active_node_count();
    if (node >= gHirType.n) return;
    uint link = node < active ? hir_type_root_link_in[node] : INVALID;
    uint owner = node < active ? hir_type_root_owner_in[node] : INVALID;
    if (link < active)
    {
        uint ancestor_owner = hir_type_root_owner_in[link];
        if (ancestor_owner < active) owner = ancestor_owner;
        uint ancestor_link = hir_type_root_link_in[link];
        link = ancestor_link < active ? ancestor_link : INVALID;
    }
    hir_type_root_link_out[node] = link;
    hir_type_root_owner_out[node] = owner;
}

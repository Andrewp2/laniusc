// Seed topmost type-root ownership. Nested generic argument types link to
// their direct parser-owned type owner; other HIR type nodes are roots.
//
// The record is written to both ping-pong buffers. The walk then steps only
// over the compacted type nodes, and every link target is itself a type node,
// so the other nodes keep their seeded records in either buffer.

struct Params { uint n; uint uses_status_count; };
ConstantBuffer<Params> gHirType;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_type_arg_owner;
StructuredBuffer<uint> hir_type_arg_application_owner;
RWStructuredBuffer<uint> hir_type_root_link_a;
RWStructuredBuffer<uint> hir_type_root_owner_a;
RWStructuredBuffer<uint> hir_type_root_link_b;
RWStructuredBuffer<uint> hir_type_root_owner_b;

static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
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
    uint link = INVALID;
    uint owner = INVALID;
    if (node < active && hir_kind[node] == HIR_TYPE)
    {
        uint seed = hir_type_arg_owner[node];
        uint parent_type = seed < active ? hir_type_arg_application_owner[seed] : INVALID;
        bool nested = parent_type < active && hir_kind[parent_type] == HIR_TYPE;
        link = nested ? parent_type : INVALID;
        owner = nested ? INVALID : node;
    }
    hir_type_root_link_a[node] = link;
    hir_type_root_owner_a[node] = owner;
    hir_type_root_link_b[node] = link;
    hir_type_root_owner_b[node] = owner;
}

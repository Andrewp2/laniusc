// Seed the canonical HIR path root -> semantic owner relation.

struct Params { uint n; uint uses_status_count; };
ConstantBuffer<Params> gHirPath;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_type_value_node;
StructuredBuffer<uint> hir_item_path_node;

RWStructuredBuffer<uint> hir_path_root_owner;
RWStructuredBuffer<uint> hir_path_segment_owner_a;
RWStructuredBuffer<uint> hir_path_segment_rank_a;
RWStructuredBuffer<uint> hir_path_segment_count;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_TYPE = 5u;
static const uint HIR_MODULE_ITEM = 31u;
static const uint HIR_IMPORT_ITEM = 32u;
static const uint HIR_PATH_EXPR = 33u;

uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_node_count() { return gHirPath.uses_status_count != 0u ? min(gHirPath.n, tree_count_status[5u]) : gHirPath.n; }
bool valid_node(uint node) { return node != INVALID && node < active_node_count(); }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirPath.n)
        return;

    hir_path_root_owner[node] = INVALID;
    hir_path_segment_owner_a[node] = INVALID;
    hir_path_segment_rank_a[node] = 0u;
    hir_path_segment_count[node] = 0u;
    if (!valid_node(node))
        return;

    uint kind = hir_kind[node];
    uint root = INVALID;
    if (kind == HIR_PATH_EXPR)
        root = node;
    else if (kind == HIR_TYPE)
        root = hir_type_value_node[node];
    else if (kind == HIR_MODULE_ITEM || kind == HIR_IMPORT_ITEM)
        root = hir_item_path_node[node];

    if (valid_node(root))
        hir_path_root_owner[root] = node;
}

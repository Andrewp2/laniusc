import prefix_scan;
import generated_parse_production_ids;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
struct HirPath { uint owner; uint segment_start; uint segment_count; uint kind; };
struct HirPathSegment { uint path; uint name_token; uint ordinal; uint file_id; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_flag;
StructuredBuffer<uint> family_local_prefix;
StructuredBuffer<uint> family_block_prefix;
StructuredBuffer<uint> segment_table_count;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> segment_count_by_raw_owner;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_item_kind;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirPath> paths;
RWStructuredBuffer<HirPathSegment> path_segments;
RWStructuredBuffer<uint> canonical_status;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_TYPE = 5u;
static const uint HIR_MODULE_ITEM = 31u;
static const uint HIR_IMPORT_ITEM = 32u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_ITEM_KIND_MODULE = 1u;
static const uint HIR_ITEM_KIND_IMPORT = 2u;
static const uint PATH_KIND_MODULE_DECL = 1u;
static const uint PATH_KIND_IMPORT = 2u;
static const uint PATH_KIND_VALUE = 3u;
static const uint PATH_KIND_TYPE = 4u;
static const uint PATH_KIND_BOUND_TYPE = 5u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.raw_capacity + 255u) / 256u; }

uint semantic_path_kind(uint raw)
{
    uint item_kind = hir_item_kind[raw];
    uint kind = hir_kind[raw];
    if (item_kind == HIR_ITEM_KIND_MODULE || kind == HIR_MODULE_ITEM)
        return PATH_KIND_MODULE_DECL;
    if (item_kind == HIR_ITEM_KIND_IMPORT || kind == HIR_IMPORT_ITEM)
        return PATH_KIND_IMPORT;
    if (kind == HIR_PATH_EXPR)
        return PATH_KIND_VALUE;
    if (node_kind[raw] == PROD_BOUND_TYPE_IDENT)
        return PATH_KIND_BOUND_TYPE;
    return kind == HIR_TYPE ? PATH_KIND_TYPE : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID) {
    uint segment_row = tid(dtid);
    uint total = inclusive_scan_total(block_count(), family_block_prefix);
    if (segment_row == 0u) family_count[0u] = total;
    uint segment_count = min(segment_table_count[0u], gCanonical.canonical_capacity);
    if (segment_row >= segment_count) return;

    uint block = segment_row / 256u;
    uint base = block == 0u ? 0u : family_block_prefix[block - 1u];
    uint before = base + family_local_prefix[segment_row];
    uint inclusive = before + family_flag[segment_row];
    if (inclusive == 0u) {
        uint ignored;
        InterlockedMax(canonical_status[0u], 2u, ignored);
        InterlockedMax(canonical_status[3u], segment_row + 1u, ignored);
        return;
    }
    uint path_row = inclusive - 1u;
    if (path_row >= gCanonical.canonical_capacity) {
        uint ignored;
        InterlockedMax(canonical_status[0u], 3u, ignored);
        InterlockedMax(canonical_status[3u], segment_row + 1u, ignored);
        return;
    }

    HirPathSegment segment = path_segments[segment_row];
    uint raw_owner = segment.path;
    segment.path = path_row;
    path_segments[segment_row] = segment;

    if (family_flag[segment_row] == 0u) return;
    HirPath path;
    path.owner = raw_owner < gCanonical.raw_capacity ? raw_to_hir[raw_owner] : INVALID;
    path.segment_start = segment_row;
    path.segment_count = raw_owner < gCanonical.raw_capacity ? segment_count_by_raw_owner[raw_owner] : 0u;
    path.kind = semantic_path_kind(raw_owner);
    paths[path_row] = path;
}

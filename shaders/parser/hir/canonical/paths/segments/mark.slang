import generated_parse_production_ids;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> path_segment_owner;
StructuredBuffer<uint> raw_to_hir;
RWStructuredBuffer<uint> family_flag;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint active_count() { return gCanonical.uses_status_count != 0u ? min(gCanonical.raw_capacity, tree_count_status[5u]) : gCanonical.raw_capacity; }
bool path_segment(uint production) {
    return production == PROD_PATH_IDENT || production == PROD_PATH_IDENT_ARGS ||
           production == PROD_TYPE_PATH_IDENT || production == PROD_BOUND_TYPE_PATH_IDENT;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID) {
    uint raw = tid(dtid);
    if (raw >= gCanonical.raw_capacity) return;
    family_flag[raw] = 0u;
    if (raw >= active_count() || !path_segment(node_kind[raw])) return;
    uint owner = path_segment_owner[raw];
    family_flag[raw] = owner < gCanonical.raw_capacity && raw_to_hir[owner] != INVALID ? 1u : 0u;
}

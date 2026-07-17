struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_type_arg_owner;
StructuredBuffer<uint> hir_type_arg_rank;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_type_arg_start;
StructuredBuffer<uint> hir_type_arg_count;
RWStructuredBuffer<uint> family_flag;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint active_count() { return gCanonical.uses_status_count != 0u ? min(gCanonical.raw_capacity, tree_count_status[5u]) : gCanonical.raw_capacity; }
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID) {
    uint raw = tid(dtid);
    if (raw >= gCanonical.raw_capacity) return;
    uint owner = hir_type_arg_owner[raw];
    bool valid_owner = owner < active_count() && hir_kind[owner] == 5u &&
                       hir_type_arg_start[owner] != INVALID && hir_type_arg_count[owner] != 0u;
    family_flag[raw] = raw < active_count() && hir_kind[raw] == 5u && valid_owner &&
                       owner != raw && hir_type_arg_rank[raw] < hir_type_arg_count[owner] ? 1u : 0u;
}

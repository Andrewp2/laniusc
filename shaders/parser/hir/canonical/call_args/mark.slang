struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> canonical_raw_to_dense;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_call_arg_count;
RWStructuredBuffer<uint> family_flag;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_CALL_EXPR = 19u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint active_count() { return gCanonical.uses_status_count != 0u ? min(gCanonical.raw_capacity, tree_count_status[5u]) : gCanonical.raw_capacity; }
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID) {
    uint raw = tid(dtid);
    if (raw >= gCanonical.raw_capacity) return;
    bool canonical_call = raw < active_count() &&
                          canonical_raw_to_dense[raw] != INVALID &&
                          hir_kind[raw] == HIR_CALL_EXPR;
    family_flag[raw] = canonical_call ? hir_call_arg_count[raw] : 0u;
}

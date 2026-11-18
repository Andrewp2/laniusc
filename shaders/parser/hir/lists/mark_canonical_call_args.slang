struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> canonical_count;
StructuredBuffer<uint> canonical_dense_to_raw;
StructuredBuffer<uint> canonical_raw_to_dense;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_call_arg_count;
RWStructuredBuffer<uint> family_flag;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_CALL_EXPR = 19u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID) {
    uint dense = tid(dtid);
    if (dense >= gCanonical.canonical_capacity) return;
    uint raw = dense < min(canonical_count[0u], gCanonical.canonical_capacity)
        ? canonical_dense_to_raw[dense]
        : INVALID;
    bool canonical_call = raw < gCanonical.raw_capacity &&
                          canonical_raw_to_dense[raw] == dense &&
                          hir_kind[raw] == HIR_CALL_EXPR;
    family_flag[dense] = canonical_call ? hir_call_arg_count[raw] : 0u;
}

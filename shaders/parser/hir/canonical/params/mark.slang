struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> canonical_count;
StructuredBuffer<uint> canonical_dense_to_raw;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint4> hir_param_record;
RWStructuredBuffer<uint> family_flag;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint dense = tid(dtid);
    if (dense >= gCanonical.canonical_capacity) return;
    uint raw = dense < min(canonical_count[0u], gCanonical.canonical_capacity)
        ? canonical_dense_to_raw[dense]
        : INVALID;
    uint anchor = raw < gCanonical.raw_capacity ? hir_token_pos[raw] : INVALID;
    uint4 parameter = anchor < gCanonical.canonical_capacity
        ? hir_param_record[anchor]
        : uint4(INVALID, INVALID, INVALID, INVALID);
    family_flag[dense] = parameter.x != INVALID && parameter.w == raw ? 1u : 0u;
}

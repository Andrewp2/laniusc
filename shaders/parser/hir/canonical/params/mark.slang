struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint4> hir_param_record;
RWStructuredBuffer<uint> family_flag;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint active_count() { return gCanonical.uses_status_count != 0u ? min(gCanonical.raw_capacity, tree_count_status[5u]) : gCanonical.raw_capacity; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint raw = tid(dtid);
    if (raw >= gCanonical.raw_capacity) return;
    uint anchor = raw < active_count() ? hir_token_pos[raw] : INVALID;
    uint4 parameter = anchor < gCanonical.canonical_capacity
        ? hir_param_record[anchor]
        : uint4(INVALID, INVALID, INVALID, INVALID);
    family_flag[raw] = parameter.x != INVALID && parameter.w == raw ? 1u : 0u;
}

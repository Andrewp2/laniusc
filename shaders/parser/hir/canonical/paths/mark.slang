struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
struct HirPathSegment { uint path; uint name_token; uint ordinal; uint file_id; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> segment_count;
StructuredBuffer<HirPathSegment> path_segments;
RWStructuredBuffer<uint> family_flag;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID) {
    uint row = tid(dtid);
    if (row >= gCanonical.raw_capacity) return;
    uint count = min(segment_count[0u], gCanonical.canonical_capacity);
    family_flag[row] = row < count && path_segments[row].ordinal == 0u ? 1u : 0u;
}

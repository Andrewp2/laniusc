// Project compact HIR path segments into name-resolution storage.

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirPath { uint owner; uint segment_start; uint segment_count; uint kind; };
struct HirPathSegment { uint path; uint name_token; uint ordinal; uint file_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<HirPath> compact_paths;
StructuredBuffer<uint> compact_path_segment_count;
StructuredBuffer<HirPathSegment> compact_path_segments;
StructuredBuffer<uint> name_id_by_token;
RWStructuredBuffer<uint> path_segment_name_id;
RWStructuredBuffer<uint> path_segment_token;
RWStructuredBuffer<uint> path_prefix_base;
RWStructuredBuffer<uint> path_prefix_id_a;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = tid(dtid);
    uint segment_count = min(compact_path_segment_count[0u], gParams.n_tokens);
    if (row >= segment_count)
        return;
    HirPathSegment segment = compact_path_segments[row];
    if (segment.path >= compact_path_count[0u])
        return;
    HirPath path = compact_paths[segment.path];
    if (segment.ordinal >= path.segment_count || path.segment_start + segment.ordinal != row)
        return;
    uint token = segment.name_token;
    if (token >= gParams.n_tokens || name_id_by_token[token] == INVALID)
        return;
    path_segment_name_id[row] = name_id_by_token[token];
    path_segment_token[row] = token;
    path_prefix_base[row] = path.segment_start;
    path_prefix_id_a[row] = name_id_by_token[token];
}

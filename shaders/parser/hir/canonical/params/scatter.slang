import prefix_scan;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
struct HirParam { uint owner; uint name_token; uint type_node; uint ordinal; };
struct HirRange { uint start; uint count; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_flag;
StructuredBuffer<uint> family_local_prefix;
StructuredBuffer<uint> family_block_prefix;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> hir_param_type_node;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirParam> hir_params;
RWStructuredBuffer<HirRange> param_ranges;
RWStructuredBuffer<uint> canonical_status;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.raw_capacity + 255u) / 256u; }
uint mapped(uint raw) { return raw < gCanonical.raw_capacity ? raw_to_hir[raw] : INVALID; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint raw = tid(dtid);
    uint total = inclusive_scan_total(block_count(), family_block_prefix);
    if (raw == 0u) family_count[0u] = total;
    if (raw >= gCanonical.raw_capacity || family_flag[raw] == 0u) return;
    uint block = raw / 256u;
    uint base = block == 0u ? 0u : family_block_prefix[block - 1u];
    uint row = base + family_local_prefix[raw];
    if (row >= gCanonical.canonical_capacity)
    {
        uint ignored;
        InterlockedMax(canonical_status[0u], 3u, ignored);
        InterlockedMax(canonical_status[3u], raw + 1u, ignored);
        return;
    }
    uint4 source = hir_param_record[raw];
    HirParam parameter;
    parameter.owner = mapped(source.x);
    parameter.name_token = source.z;
    parameter.type_node = mapped(hir_param_type_node[raw]);
    parameter.ordinal = source.y;
    hir_params[row] = parameter;
    if (parameter.owner < gCanonical.canonical_capacity)
    {
        uint ignored;
        InterlockedMin(param_ranges[parameter.owner].start, row, ignored);
        InterlockedMax(param_ranges[parameter.owner].count, parameter.ordinal + 1u, ignored);
    }
}

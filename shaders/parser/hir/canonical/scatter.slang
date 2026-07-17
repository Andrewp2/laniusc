import prefix_scan;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
struct HirRange { uint start; uint count; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> canonical_flag;
StructuredBuffer<uint> canonical_local_prefix;
StructuredBuffer<uint> canonical_block_prefix;
RWStructuredBuffer<uint> canonical_prefix_before_raw;
RWStructuredBuffer<uint> canonical_dense_to_raw;
RWStructuredBuffer<uint> canonical_raw_to_dense;
RWStructuredBuffer<uint> canonical_count;
RWStructuredBuffer<uint> canonical_status;
RWStructuredBuffer<uint> array_element_start;
RWStructuredBuffer<uint> array_element_count;
RWStructuredBuffer<HirRange> param_ranges;
RWStructuredBuffer<HirRange> type_arg_ranges;
RWStructuredBuffer<HirRange> generic_param_ranges;

static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.raw_capacity + 255u) / 256u; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = tid(dtid);
    uint total = inclusive_scan_total(block_count(), canonical_block_prefix);
    if (node == 0u)
    {
        canonical_count[0u] = total;
        canonical_status[1u] = total;
        canonical_status[2u] = gCanonical.canonical_capacity;
        if (total > gCanonical.canonical_capacity) canonical_status[0u] = 1u;
    }
    if (node >= gCanonical.raw_capacity) return;
    uint block = node / 256u;
    uint base = block == 0u ? 0u : canonical_block_prefix[block - 1u];
    uint dense = base + canonical_local_prefix[node];
    canonical_prefix_before_raw[node] = dense;
    canonical_raw_to_dense[node] = canonical_flag[node] != 0u ? dense : 0xffffffffu;
    if (canonical_flag[node] != 0u)
    {
        if (dense < gCanonical.canonical_capacity)
        {
            canonical_dense_to_raw[dense] = node;
            array_element_start[dense] = 0xffffffffu;
            array_element_count[dense] = 0u;
            HirRange empty_range;
            empty_range.start = 0xffffffffu;
            empty_range.count = 0u;
            param_ranges[dense] = empty_range;
            type_arg_ranges[dense] = empty_range;
            generic_param_ranges[dense] = empty_range;
        }
        else InterlockedMax(canonical_status[3u], node + 1u);
    }
}

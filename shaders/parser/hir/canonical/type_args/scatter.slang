import prefix_scan;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
struct HirTypeArg { uint owner; uint value; uint ordinal; uint file_id; };
struct HirRange { uint start; uint count; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_flag;
StructuredBuffer<uint> family_local_prefix;
StructuredBuffer<uint> family_block_prefix;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> hir_token_file_id;
StructuredBuffer<uint> hir_type_arg_owner;
StructuredBuffer<uint> hir_type_arg_rank;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirTypeArg> hir_type_args;
RWStructuredBuffer<HirRange> type_arg_ranges;
RWStructuredBuffer<uint> canonical_status;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.raw_capacity + 255u) / 256u; }
uint mapped(uint raw) { return raw < gCanonical.raw_capacity ? raw_to_hir[raw] : INVALID; }
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID) {
    uint raw = tid(dtid);
    uint total = inclusive_scan_total(block_count(), family_block_prefix);
    if (raw == 0u) family_count[0u] = total;
    if (raw >= gCanonical.raw_capacity || family_flag[raw] == 0u) return;
    uint block = raw / 256u;
    uint base = block == 0u ? 0u : family_block_prefix[block - 1u];
    uint row = base + family_local_prefix[raw];
    if (row >= gCanonical.canonical_capacity) {
        uint ignored;
        InterlockedMax(canonical_status[0u], 3u, ignored);
        InterlockedMax(canonical_status[3u], raw + 1u, ignored);
        return;
    }
    HirTypeArg arg;
    arg.owner = mapped(hir_type_arg_owner[raw]);
    arg.value = mapped(raw);
    arg.ordinal = hir_type_arg_rank[raw];
    arg.file_id = hir_token_file_id[raw];
    hir_type_args[row] = arg;
    if (arg.owner < gCanonical.canonical_capacity) {
        uint ignored;
        InterlockedMin(type_arg_ranges[arg.owner].start, row, ignored);
        InterlockedMax(type_arg_ranges[arg.owner].count, arg.ordinal + 1u, ignored);
    }
}

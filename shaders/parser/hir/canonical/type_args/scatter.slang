import hir_records;
import prefix_scan;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_flag;
StructuredBuffer<uint> family_local_prefix;
StructuredBuffer<uint> family_block_prefix;
StructuredBuffer<uint> canonical_count;
StructuredBuffer<uint> canonical_dense_to_raw;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> hir_type_arg_owner;
StructuredBuffer<uint> hir_type_arg_application_owner;
StructuredBuffer<uint> hir_type_arg_application_token;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_type_arg_rank;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirTypeArg> hir_type_args;
RWStructuredBuffer<HirRange> type_arg_ranges;
RWStructuredBuffer<HirRange> path_type_arg_ranges;
RWStructuredBuffer<uint> canonical_status;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.canonical_capacity + 255u) / 256u; }
uint mapped(uint raw) { return raw < gCanonical.raw_capacity ? raw_to_hir[raw] : INVALID; }
uint file_for_raw(uint raw) {
    uint token = raw < gCanonical.raw_capacity ? hir_token_pos[raw] : INVALID;
    return token < gCanonical.canonical_capacity ? token_file_id[token] : INVALID;
}
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID) {
    uint dense = tid(dtid);
    uint total = inclusive_scan_total(block_count(), family_block_prefix);
    if (dense == 0u) family_count[0u] = total;
    if (dense >= min(canonical_count[0u], gCanonical.canonical_capacity)) return;
    uint raw = canonical_dense_to_raw[dense];
    uint seed = hir_type_arg_owner[raw];
    uint owner = seed < gCanonical.raw_capacity ? hir_type_arg_application_owner[seed] : INVALID;
    uint head = mapped(seed);
    if ((hir_kind[raw] != 5u && hir_kind[raw] != 23u) || owner >= gCanonical.raw_capacity || owner == raw ||
        head >= gCanonical.canonical_capacity || hir_type_arg_rank[raw] >= family_flag[head]) return;
    uint block = head / 256u;
    uint base = block == 0u ? 0u : family_block_prefix[block - 1u];
    uint row = base + family_local_prefix[head] + hir_type_arg_rank[raw];
    if (row >= gCanonical.canonical_capacity) {
        uint ignored;
        InterlockedMax(canonical_status[0u], 3u, ignored);
        InterlockedMax(canonical_status[3u], raw + 1u, ignored);
        return;
    }
    HirTypeArg arg;
    arg.owner = mapped(owner);
    arg.application_token = seed < gCanonical.raw_capacity ? hir_type_arg_application_token[seed] : INVALID;
    arg.value = mapped(raw);
    arg.ordinal = hir_type_arg_rank[raw];
    arg.file_id = file_for_raw(raw);
    hir_type_args[row] = arg;
    if (arg.application_token < gCanonical.canonical_capacity) {
        uint ignored;
        InterlockedMin(path_type_arg_ranges[arg.application_token].start, row, ignored);
        InterlockedMax(path_type_arg_ranges[arg.application_token].count, arg.ordinal + 1u, ignored);
    }
    if (arg.owner < gCanonical.canonical_capacity && owner < gCanonical.raw_capacity && hir_kind[owner] == 5u) {
        uint ignored;
        InterlockedMin(type_arg_ranges[arg.owner].start, row, ignored);
        InterlockedMax(type_arg_ranges[arg.owner].count, arg.ordinal + 1u, ignored);
    }
}

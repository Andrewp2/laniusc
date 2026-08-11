import hir_records;
import prefix_scan;
import canonical_hir_identity;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_local_prefix;
StructuredBuffer<uint> family_block_prefix;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_token_file_id;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> hir_call_arg_ordinal;
StructuredBuffer<uint> hir_call_arg_end;
StructuredBuffer<uint> hir_call_arg_count;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirCallArg> hir_call_args;
RWStructuredBuffer<HirRange> hir_call_arg_ranges;
RWStructuredBuffer<uint> canonical_status;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_FILE = 1u;
static const uint HIR_EXPR = 14u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_POSTFIX_EXPR = 18u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.canonical_capacity + 255u) / 256u; }
uint mapped(uint raw) {
    return raw < gCanonical.raw_capacity ? raw_to_hir[raw] : INVALID;
}
uint expression(uint raw) {
    if (raw >= gCanonical.raw_capacity) return INVALID;
    uint root = hir_expr_result_root_node[raw];
    uint value = mapped(root);
    return value != INVALID ? value : mapped(raw);
}
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID) {
    uint raw = tid(dtid);
    uint total = inclusive_scan_total(block_count(), family_block_prefix);
    if (raw == 0u) family_count[0u] = total;
    if (raw >= gCanonical.raw_capacity || hir_call_arg_end[raw] == INVALID) return;
    uint call_raw = hir_call_arg_parent_call[raw];
    if (call_raw >= gCanonical.raw_capacity) return;
    uint ordinal = hir_call_arg_ordinal[raw];
    uint call_count = hir_call_arg_count[call_raw];
    if (ordinal >= call_count) return;
    uint call = mapped(call_raw);
    if (call >= gCanonical.canonical_capacity) return;
    uint call_block = call / 256u;
    uint call_base = call_block == 0u ? 0u : family_block_prefix[call_block - 1u];
    uint call_start = call_base + family_local_prefix[call];
    uint row = call_start + ordinal;
    if (row >= gCanonical.canonical_capacity) {
        uint ignored;
        InterlockedMax(canonical_status[0u], 3u, ignored);
        InterlockedMax(canonical_status[3u], raw + 1u, ignored);
        return;
    }
    HirCallArg arg;
    arg.call = call;
    arg.value = expression(raw);
    arg.ordinal = ordinal;
    arg.file_id = hir_token_file_id[raw];
    hir_call_args[row] = arg;
    if (arg.ordinal == 0u && call != INVALID) {
        HirRange range;
        range.start = call_start;
        range.count = call_count;
        hir_call_arg_ranges[call] = range;
    }
}

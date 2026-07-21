import prefix_scan;
import canonical_hir_identity;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirCallArg { uint call; uint value; uint ordinal; uint file_id; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_local_prefix;
StructuredBuffer<uint> family_block_prefix;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> canonical_anchor_owner;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_token_file_id;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> hir_call_arg_ordinal;
StructuredBuffer<uint> hir_call_arg_end;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_context_stmt_node;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirCallArg> hir_call_args;
RWStructuredBuffer<HirPayload> hir_payload;
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
static const uint HIR_STMT = 7u;
static const uint HIR_CALL_CONTEXT_STMT_BIT = 0x80000000u;
static const uint HIR_CALL_CONTEXT_ID_MASK = 0x7fffffffu;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.raw_capacity + 255u) / 256u; }
uint semantic_anchor(uint raw) {
    uint kind = hir_kind[raw];
    uint expr_form = hir_expr_record[raw * 4u];
    uint identity_kind = canonical_hir_identity_kind(kind, expr_form, false);
    uint callee = hir_call_callee_node[raw];
    uint open = callee < gCanonical.raw_capacity ? hir_token_end[callee] : INVALID;
    uint right = hir_expr_record[raw * 4u + 2u];
    uint right_start = right < gCanonical.raw_capacity ? hir_token_pos[right] : INVALID;
    uint operator_token = canonical_hir_operator_anchor(
        identity_kind, right_start, gCanonical.canonical_capacity);
    uint value_token = hir_expr_record[raw * 4u + 3u];
    return canonical_hir_anchor(identity_kind, hir_token_pos[raw], hir_token_end[raw], open, value_token,
                                operator_token, gCanonical.canonical_capacity);
}
uint mapped(uint raw) {
    if (raw >= gCanonical.raw_capacity) return INVALID;
    uint direct = raw_to_hir[raw];
    if (direct != INVALID) return direct;
    uint anchor = semantic_anchor(raw);
    if (anchor >= gCanonical.canonical_capacity) return INVALID;
    uint winner_plus_one = canonical_anchor_owner[anchor] & 0x0fffffffu;
    return winner_plus_one == 0u ? INVALID : raw_to_hir[winner_plus_one - 1u];
}
uint expression(uint raw) {
    if (raw >= gCanonical.raw_capacity) return INVALID;
    uint root = hir_expr_result_root_node[raw];
    uint value = mapped(root);
    return value != INVALID ? value : mapped(raw);
}
uint encoded_call_context(uint raw_context) {
    uint context = mapped(raw_context);
    uint encoded = context == INVALID ? HIR_CALL_CONTEXT_ID_MASK : context;
    if (raw_context < gCanonical.raw_capacity && hir_kind[raw_context] == HIR_STMT)
        encoded |= HIR_CALL_CONTEXT_STMT_BIT;
    return encoded;
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
    uint call_block = call_raw / 256u;
    uint call_base = call_block == 0u ? 0u : family_block_prefix[call_block - 1u];
    uint call_start = call_base + family_local_prefix[call_raw];
    uint row = call_start + ordinal;
    if (row >= gCanonical.canonical_capacity) {
        uint ignored;
        InterlockedMax(canonical_status[0u], 3u, ignored);
        InterlockedMax(canonical_status[3u], raw + 1u, ignored);
        return;
    }
    uint call = mapped(call_raw);
    HirCallArg arg;
    arg.call = call;
    arg.value = expression(raw);
    arg.ordinal = ordinal;
    arg.file_id = hir_token_file_id[raw];
    hir_call_args[row] = arg;
    if (arg.ordinal == 0u && call != INVALID) {
        HirPayload payload;
        payload.a = expression(hir_call_callee_node[call_raw]);
        payload.b = call_start;
        payload.c = call_count;
        payload.d = encoded_call_context(hir_call_context_stmt_node[call_raw]);
        hir_payload[call] = payload;
    }
}

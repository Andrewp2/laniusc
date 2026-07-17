import prefix_scan;
import canonical_hir_identity;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
RWStructuredBuffer<uint> canonical_flag;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> canonical_anchor_owner;
RWStructuredBuffer<uint> canonical_local_prefix;
RWStructuredBuffer<uint> canonical_block_sum;
RWStructuredBuffer<uint> canonical_status;

static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_FILE = 1u;
static const uint HIR_PARAM = 4u;
static const uint HIR_TYPE = 5u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_MATCH_EXPR = 34u;
uint group_id(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }
static const uint INVALID = 0xffffffffu;
uint anchor_for(uint node) {
    uint kind = hir_kind[node];
    uint callee = hir_call_callee_node[node];
    uint open = callee < gCanonical.raw_capacity ? hir_token_end[callee] : INVALID;
    uint right = hir_expr_record[node * 4u + 2u];
    uint right_start = right < gCanonical.raw_capacity ? hir_token_pos[right] : INVALID;
    uint operator_token = canonical_hir_operator_anchor(
        kind, right_start, gCanonical.canonical_capacity);
    uint value_token = hir_expr_record[node * 4u + 3u];
    return canonical_hir_anchor(
        kind, hir_token_pos[node], hir_token_end[node], open, value_token,
        operator_token, gCanonical.canonical_capacity);
}
uint encoded_winner(uint node) { return (canonical_hir_priority(hir_kind[node]) << 28u) | (node + 1u); }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block = group_id(gid);
    uint lane = ltid.x;
    uint node = block * 256u + lane;
    uint flag = 0u;
    if (node < gCanonical.raw_capacity && canonical_flag[node] != 0u)
    {
        uint anchor = anchor_for(node);
        flag = canonical_anchor_owner[anchor] == encoded_winner(node) ? 1u : 0u;
        canonical_flag[node] = flag;
        if (flag != 0u)
        {
            uint ignored;
            InterlockedAdd(canonical_status[6u], 1u, ignored);
        }
    }
    uint inclusive = prefix_scan_u32_256(lane, flag);
    if (node < gCanonical.raw_capacity) canonical_local_prefix[node] = inclusive - flag;
    if (lane == 255u) canonical_block_sum[block] = inclusive;
}

// Project every raw semantic wrapper to its winning canonical HIR id while
// raw expression/statement classification is still resident.

import canonical_hir_identity;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> canonical_flag;
StructuredBuffer<uint> canonical_local_prefix;
StructuredBuffer<uint> canonical_block_prefix;
StructuredBuffer<uint> canonical_anchor_owner;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_call_callee_node;
RWStructuredBuffer<uint> raw_to_hir;

static const uint INVALID = 0xffffffffu;
static const uint STMT_ASSIGN = 5u;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint active_count() { return gCanonical.uses_status_count != 0u ? min(gCanonical.raw_capacity, tree_count_status[5u]) : gCanonical.raw_capacity; }
bool valid(uint node) { return node != INVALID && node < active_count(); }
uint dense_winner(uint winner) {
    if (!valid(winner) || canonical_flag[winner] == 0u) return INVALID;
    uint block = winner / 256u;
    uint base = block == 0u ? 0u : canonical_block_prefix[block - 1u];
    uint dense = base + canonical_local_prefix[winner];
    return dense < gCanonical.canonical_capacity ? dense : INVALID;
}
uint semantic_anchor(uint node) {
    bool assignment = hir_stmt_record[node * 4u] == STMT_ASSIGN;
    uint expr_form = hir_expr_record[node * 4u];
    uint identity_kind = canonical_hir_identity_kind(hir_kind[node], expr_form, assignment);
    uint callee = hir_call_callee_node[node];
    uint open = valid(callee) ? hir_token_end[callee] : INVALID;
    uint right = assignment ? hir_stmt_record[node * 4u + 2u] : hir_expr_record[node * 4u + 2u];
    uint right_start = valid(right) ? hir_token_pos[right] : INVALID;
    uint operator_token = canonical_hir_operator_anchor(identity_kind, right_start, gCanonical.canonical_capacity);
    return canonical_hir_anchor(identity_kind, hir_token_pos[node], hir_token_end[node], open,
        hir_expr_record[node * 4u + 3u], operator_token, gCanonical.canonical_capacity);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint raw = tid(dtid);
    if (raw >= gCanonical.raw_capacity) return;
    if (!valid(raw)) { raw_to_hir[raw] = INVALID; return; }
    if (canonical_flag[raw] != 0u) { raw_to_hir[raw] = dense_winner(raw); return; }
    uint anchor = semantic_anchor(raw);
    if (anchor >= gCanonical.canonical_capacity) { raw_to_hir[raw] = INVALID; return; }
    uint winner_plus_one = canonical_anchor_owner[anchor] & 0x0fffffffu;
    raw_to_hir[raw] = winner_plus_one == 0u ? INVALID : dense_winner(winner_plus_one - 1u);
}

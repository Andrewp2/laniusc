import canonical_hir_identity;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> canonical_flag;
StructuredBuffer<uint> canonical_prefix_before_raw;
StructuredBuffer<uint> canonical_anchor_owner;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_call_callee_node;
RWStructuredBuffer<uint> parent_link_a;
RWStructuredBuffer<uint> parent_value_a;
RWStructuredBuffer<uint> raw_to_hir;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint STMT_ASSIGN = 5u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint active_count() { return gCanonical.uses_status_count != 0u ? min(gCanonical.raw_capacity, tree_count_status[5u]) : gCanonical.raw_capacity; }
bool valid(uint node) { return node != INVALID && node < active_count(); }

uint semantic_anchor(uint node)
{
    bool assignment_stmt = hir_stmt_record[node * 4u] == STMT_ASSIGN;
    uint callee = hir_call_callee_node[node];
    uint open = valid(callee) ? hir_token_end[callee] : INVALID;
    uint right = assignment_stmt
        ? hir_stmt_record[node * 4u + 2u]
        : hir_expr_record[node * 4u + 2u];
    uint right_start = valid(right) ? hir_token_pos[right] : INVALID;
    uint kind = hir_kind[node];
    uint expr_form = hir_expr_record[node * 4u];
    uint identity_kind = canonical_hir_identity_kind(kind, expr_form, assignment_stmt);
    uint operator_token = canonical_hir_operator_anchor(
        identity_kind, right_start, gCanonical.canonical_capacity);
    uint value_token = hir_expr_record[node * 4u + 3u];
    return canonical_hir_anchor(identity_kind, hir_token_pos[node], hir_token_end[node],
                                open, value_token, operator_token,
                                gCanonical.canonical_capacity);
}

uint dense_id(uint node)
{
    if (!valid(node)) return INVALID;
    if (canonical_flag[node] != 0u) return canonical_prefix_before_raw[node];
    uint anchor = semantic_anchor(node);
    if (anchor >= gCanonical.canonical_capacity) return INVALID;
    uint winner_plus_one = canonical_anchor_owner[anchor] & 0x0fffffffu;
    if (winner_plus_one == 0u) return INVALID;
    uint winner = winner_plus_one - 1u;
    return valid(winner) && canonical_flag[winner] != 0u
        ? canonical_prefix_before_raw[winner]
        : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = tid(dtid);
    if (node >= gCanonical.raw_capacity) return;
    parent_link_a[node] = INVALID;
    parent_value_a[node] = INVALID;
    raw_to_hir[node] = dense_id(node);
    if (!valid(node)) return;
    uint ancestor = parent[node];
    uint span = max(1u, gCanonical.local_ancestor_span);
    for (uint hop = 0u; hop < span; ++hop)
    {
        if (!valid(ancestor) || ancestor == node) return;
        if (canonical_flag[ancestor] != 0u)
        {
            parent_value_a[node] = canonical_prefix_before_raw[ancestor];
            return;
        }
        if (hop + 1u == span) { parent_link_a[node] = ancestor; return; }
        uint next = parent[ancestor];
        if (!valid(next) || next == ancestor) return;
        ancestor = next;
    }
}

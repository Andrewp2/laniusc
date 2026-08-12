// Scatter token-indexed visible declarations into source order.
//
// Ordinary HIR declarations and match-payload binders publish a descriptor at
// their distinct declaration token. The prefix of the token flag is therefore
// both the compact destination and the declaration's source-order rank.

import hir_records;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_scope_end;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> hir_visible_decl_flag;
StructuredBuffer<uint> hir_visible_decl_prefix;
RWStructuredBuffer<uint> hir_visible_decl_source_by_token;

RWStructuredBuffer<uint> hir_visible_decl_owner_fn;
RWStructuredBuffer<uint> hir_visible_decl_name_id;
RWStructuredBuffer<uint> hir_visible_decl_token;
RWStructuredBuffer<uint> hir_visible_decl_scope_end;
RWStructuredBuffer<uint> hir_visible_decl_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LANGUAGE_SYMBOL_COUNT = 68u;
static const uint MATCH_PAYLOAD_BIT = 0x80000000u;

static const uint HIR_FN = 3u;
static const uint HIR_PARAM = 4u;
static const uint HIR_CONST_ITEM = 25u;

static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint STMT_RECORD_KIND_FOR = 7u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0u], gParams.n_tokens);
}

uint active_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool valid_hir(uint node)
{
    return node != INVALID && node < active_hir_count();
}

uint normalized_hir_end(uint node)
{
    if (!valid_hir(node))
        return active_token_count();
    uint end = compact_hir_core[node].token_end;
    return end == INVALID || end == 0u ? active_token_count()
                                       : min(end, active_token_count());
}

uint compact_stmt_scope_end_or_zero(uint node)
{
    if (!valid_hir(node))
        return 0u;
    uint end = compact_hir_scope_end[node];
    return end == INVALID || end == 0u ? 0u : min(end, active_token_count());
}

uint scope_end_for_hir_decl(uint node)
{
    if (!valid_hir(node))
        return active_token_count();
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    if (core.kind == HIR_PARAM)
    {
        uint owner = payload.a;
        if (valid_hir(owner) && compact_hir_core[owner].kind == HIR_FN)
            return normalized_hir_end(owner);
    }

    uint stmt_kind = payload.a;
    if (stmt_kind == STMT_RECORD_KIND_FOR)
    {
        uint scope_end = compact_stmt_scope_end_or_zero(node);
        if (scope_end != 0u)
            return scope_end;
        return valid_hir(payload.d) ? normalized_hir_end(payload.d) : 0u;
    }
    if (stmt_kind == STMT_RECORD_KIND_LET || stmt_kind == STMT_RECORD_KIND_CONST)
    {
        if (core.kind == HIR_CONST_ITEM)
            return active_token_count();
        return compact_stmt_scope_end_or_zero(node);
    }
    if (core.kind == HIR_FN)
        return normalized_hir_end(node);
    return active_token_count();
}

uint match_payload_scope_end(uint payload_row)
{
    uint payload_count = min(compact_match_payload_row_count[0u], gParams.n_hir_nodes);
    uint arm_count = min(compact_match_arm_count[0u], gParams.n_hir_nodes);
    if (payload_row >= payload_count)
        return active_token_count();
    HirMatchPayload payload = compact_match_payloads[payload_row];
    if (payload.arm >= arm_count)
        return active_token_count();
    HirMatchArm arm = compact_match_arms[payload.arm];
    uint scope_end = normalized_hir_end(arm.result);
    // The next arm is an independent lexical scope. Bound by its pattern
    // anchor as well as the result span so a broad expression span can never
    // make this arm's binders visible in a following arm.
    uint next_arm_row = payload.arm + 1u;
    if (next_arm_row < arm_count)
    {
        HirMatchArm next_arm = compact_match_arms[next_arm_row];
        if (next_arm.owner == arm.owner && valid_hir(next_arm.pattern))
            scope_end = min(scope_end, compact_hir_core[next_arm.pattern].token_start);
    }
    return scope_end;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = linear_thread_id(dtid);
    if (token >= active_token_count() || hir_visible_decl_flag[token] == 0u)
        return;

    uint descriptor = hir_visible_decl_source_by_token[token];
    if (descriptor == 0u)
        return;
    // This storage aliases radix temporary order after compaction. Consume the
    // token descriptor now so small-sort jobs cannot leak descriptor bits into
    // a later graph-colored occupant.
    hir_visible_decl_source_by_token[token] = 0u;
    uint dst = hir_visible_decl_prefix[token];
    if (dst >= gParams.n_tokens)
        return;

    uint name_id = name_id_by_token[token];
    if (name_id == INVALID || name_id >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        return;

    bool is_match_payload = (descriptor & MATCH_PAYLOAD_BIT) != 0u;
    uint source_row = (descriptor & ~MATCH_PAYLOAD_BIT) - 1u;
    hir_visible_decl_owner_fn[dst] = enclosing_fn[token];
    hir_visible_decl_name_id[dst] = name_id;
    hir_visible_decl_token[dst] = token;
    hir_visible_decl_scope_end[dst] = is_match_payload
        ? match_payload_scope_end(source_row)
        : scope_end_for_hir_decl(source_row);
    // Match binders have no local-initializer exclusion relation.
    hir_visible_decl_node[dst] = is_match_payload ? INVALID : source_row;
}

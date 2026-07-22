// Scatter compact HIR value-declaration records.
//
// Scheduling contract:
// - Dispatch after type_check_visible_03b_mark_hir_decl_names and a counted
//   prefix scan over hir_visible_decl_flag.
// - Each active HIR declaration row writes one compact record keyed by
//   (enclosing function, interned name id, declaration token), carrying the
//   declaration HIR node for later record-based local-initializer checks.
// - This pass consumes dense lexical-scope, compact parameter, function-context,
//   and interned-name records. It does not inspect source text, token spelling,
//   helper names, or function body shapes.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_scope_end;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> hir_visible_decl_flag;
StructuredBuffer<uint> hir_visible_decl_prefix;

RWStructuredBuffer<uint> hir_visible_decl_owner_fn;
RWStructuredBuffer<uint> hir_visible_decl_name_id;
RWStructuredBuffer<uint> hir_visible_decl_token;
RWStructuredBuffer<uint> hir_visible_decl_scope_end;
RWStructuredBuffer<uint> hir_visible_decl_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LANGUAGE_SYMBOL_COUNT = 63u;

static const uint HIR_FN = 3u;
static const uint HIR_PARAM = 4u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_CONST_ITEM = 25u;
static const uint HIR_FOR_STMT = 30u;

static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint STMT_RECORD_KIND_FOR = 7u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool valid_dense(uint dense)
{
    return dense != INVALID && dense < active_compact_hir_count();
}

uint decl_token_for_hir_node(uint node)
{
    if (!valid_dense(node))
        return INVALID;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    if (core.kind == HIR_PARAM)
    {
        if (valid_dense(payload.a) && compact_hir_core[payload.a].kind == HIR_FN)
            return payload.c;
    }

    uint stmt_kind = payload.a;
    if ((core.kind == HIR_STMT ||
         core.kind == HIR_LET_STMT ||
         core.kind == HIR_FOR_STMT) &&
        (stmt_kind == STMT_RECORD_KIND_LET ||
         stmt_kind == STMT_RECORD_KIND_CONST ||
         stmt_kind == STMT_RECORD_KIND_FOR))
        return payload.b;

    return INVALID;
}

uint owner_for_decl_token(uint token)
{
    return valid_token(token) ? enclosing_fn[token] : 0u;
}

uint normalized_hir_end(uint node)
{
    if (!valid_dense(node))
        return active_token_count();
    uint end = compact_hir_core[node].token_end;
    return end == INVALID || end == 0u ? active_token_count()
                                       : min(end, active_token_count());
}

uint compact_stmt_scope_end_or_zero(uint node)
{
    if (!valid_dense(node))
        return 0u;
    uint end = compact_hir_scope_end[node];
    return end == INVALID || end == 0u ? 0u : min(end, active_token_count());
}

uint scope_end_for_hir_decl_node(uint node)
{
    if (!valid_dense(node))
        return active_token_count();
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    if (core.kind == HIR_PARAM)
    {
        uint owner = payload.a;
        if (valid_dense(owner) && compact_hir_core[owner].kind == HIR_FN)
        {
            uint end = compact_hir_core[owner].token_end;
            return end == INVALID || end == 0u ? active_token_count()
                                               : min(end, active_token_count());
        }
    }

    uint stmt_kind = payload.a;
    if (stmt_kind == STMT_RECORD_KIND_FOR)
    {
        uint scope_end = compact_stmt_scope_end_or_zero(node);
        if (scope_end != 0u)
            return scope_end;
        return valid_dense(payload.d) ? normalized_hir_end(payload.d) : 0u;
    }
    if (stmt_kind == STMT_RECORD_KIND_LET ||
        stmt_kind == STMT_RECORD_KIND_CONST)
    {
        if (core.kind == HIR_CONST_ITEM)
            return active_token_count();
        return compact_stmt_scope_end_or_zero(node);
    }

    if (core.kind == HIR_FN)
        return normalized_hir_end(node);
    return active_token_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (!valid_dense(row) || hir_visible_decl_flag[row] == 0u)
        return;

    uint dst = hir_visible_decl_prefix[row];
    if (dst >= gParams.n_tokens)
        return;

    uint decl_token = decl_token_for_hir_node(row);
    if (!valid_token(decl_token))
        return;

    uint name_id = name_id_by_token[decl_token];
    if (name_id == INVALID || name_id >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        return;

    hir_visible_decl_owner_fn[dst] = owner_for_decl_token(decl_token);
    hir_visible_decl_name_id[dst] = name_id;
    hir_visible_decl_token[dst] = decl_token;
    hir_visible_decl_scope_end[dst] = scope_end_for_hir_decl_node(row);
    hir_visible_decl_node[dst] = row;
}

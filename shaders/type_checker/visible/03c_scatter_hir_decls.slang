// Scatter compact HIR value-declaration records.
//
// Scheduling contract:
// - Dispatch after type_check_visible_03b_mark_hir_decl_names and a counted
//   prefix scan over hir_visible_decl_flag.
// - Each active HIR declaration row writes one compact record keyed by
//   (enclosing function, interned name id, declaration token), carrying the
//   declaration HIR node for later record-based local-initializer checks.
// - This pass consumes HIR statement-scope, compact parameter, function
//   context records, and interned name ids. It does not inspect source text,
//   token spelling, helper names, or function body shapes.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_stmt_scope_end;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> raw_to_compact_hir;
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

static const uint STMT_RECORD_STRIDE = 4u;
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

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint active_semantic_hir_count()
{
    return min(hir_semantic_count[0], gParams.n_hir_nodes);
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool valid_dense(uint dense)
{
    return dense != INVALID && dense < active_compact_hir_count();
}

uint compact_param_dense(uint node)
{
    if (!valid_node(node) || hir_kind[node] != HIR_PARAM)
        return INVALID;
    uint dense = raw_to_compact_hir[node];
    return valid_dense(dense) && compact_hir_core[dense].kind == HIR_PARAM
               ? dense
               : INVALID;
}

uint stmt_slot(uint node, uint slot)
{
    return hir_stmt_record[node * STMT_RECORD_STRIDE + slot];
}

uint decl_token_for_hir_node(uint node)
{
    uint dense = compact_param_dense(node);
    if (valid_dense(dense))
    {
        HirPayload param = compact_hir_payload[dense];
        if (valid_dense(param.a) && compact_hir_core[param.a].kind == HIR_FN)
            return param.c;
    }

    uint stmt_kind = stmt_slot(node, 0u);
    if ((hir_kind[node] == HIR_STMT ||
         hir_kind[node] == HIR_LET_STMT ||
         hir_kind[node] == HIR_FOR_STMT) &&
        (stmt_kind == STMT_RECORD_KIND_LET ||
         stmt_kind == STMT_RECORD_KIND_CONST ||
         stmt_kind == STMT_RECORD_KIND_FOR))
        return stmt_slot(node, 1u);

    return INVALID;
}

uint owner_for_decl_token(uint token)
{
    return valid_token(token) ? enclosing_fn[token] : 0u;
}

uint normalized_hir_end(uint node)
{
    if (!valid_node(node))
        return active_token_count();
    uint end = hir_token_end[node];
    return end == INVALID || end == 0u ? active_token_count()
                                       : min(end, active_token_count());
}

uint parser_stmt_scope_end_or_zero(uint node)
{
    if (!valid_node(node))
        return 0u;
    uint end = hir_stmt_scope_end[node];
    return end == INVALID || end == 0u ? 0u : min(end, active_token_count());
}

uint scope_end_for_hir_decl_node(uint node)
{
    uint dense = compact_param_dense(node);
    if (valid_dense(dense))
    {
        uint owner = compact_hir_payload[dense].a;
        if (valid_dense(owner) && compact_hir_core[owner].kind == HIR_FN)
        {
            uint end = compact_hir_core[owner].token_end;
            return end == INVALID || end == 0u ? active_token_count()
                                               : min(end, active_token_count());
        }
    }

    uint stmt_kind = stmt_slot(node, 0u);
    if (stmt_kind == STMT_RECORD_KIND_FOR)
    {
        uint scope_end = parser_stmt_scope_end_or_zero(node);
        if (scope_end != 0u)
            return scope_end;
        uint body = stmt_slot(node, 3u);
        return valid_node(body) ? normalized_hir_end(body) : 0u;
    }
    if (stmt_kind == STMT_RECORD_KIND_LET ||
        stmt_kind == STMT_RECORD_KIND_CONST)
    {
        if (hir_kind[node] == HIR_CONST_ITEM)
            return active_token_count();
        return parser_stmt_scope_end_or_zero(node);
    }

    if (hir_kind[node] == HIR_FN)
        return normalized_hir_end(node);
    return active_token_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= active_semantic_hir_count())
        return;

    uint node = hir_semantic_dense_node[row];
    if (!valid_node(node) || hir_visible_decl_flag[row] == 0u)
        return;

    uint dst = hir_visible_decl_prefix[row];
    if (dst >= gParams.n_tokens)
        return;

    uint decl_token = decl_token_for_hir_node(node);
    if (!valid_token(decl_token))
        return;

    uint name_id = name_id_by_token[decl_token];
    if (name_id == INVALID || name_id >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        return;

    hir_visible_decl_owner_fn[dst] = owner_for_decl_token(decl_token);
    hir_visible_decl_name_id[dst] = name_id;
    hir_visible_decl_token[dst] = decl_token;
    hir_visible_decl_scope_end[dst] = scope_end_for_hir_decl_node(node);
    hir_visible_decl_node[dst] = node;
}

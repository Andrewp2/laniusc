// Mark interned names and compact-table flags for HIR value declarations.
//
// The following HIR-name passes use this as GPU-resident input for declaration
// table compaction. This stage consumes parser-owned HIR statement, parameter,
// and match-payload records plus interned name ids; it does not inspect source
// text or token spelling.

import atomics;

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
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> hir_match_payload_owner_arm;
StructuredBuffer<uint> name_id_by_token;

RWStructuredBuffer<uint> hir_value_decl_name_present;
RWStructuredBuffer<uint> hir_visible_decl_flag;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LANGUAGE_SYMBOL_COUNT = 19u;

static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_FOR_STMT = 30u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint STMT_RECORD_KIND_FOR = 7u;

static const uint HIR_PARAM_RECORD_FN = 0u;
static const uint HIR_PARAM_RECORD_NAME_TOKEN = 2u;

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

uint stmt_slot(uint node, uint slot)
{
    return hir_stmt_record[node * STMT_RECORD_STRIDE + slot];
}

bool valid_decl_name_token(uint token)
{
    if (!valid_token(token))
        return false;

    uint name_id = name_id_by_token[token];
    if (name_id == INVALID || name_id >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        return false;

    atomic_u32_or(hir_value_decl_name_present, name_id, 1u);
    return true;
}

uint decl_token_for_hir_node(uint node)
{
    uint4 param = hir_param_record[node];
    if (valid_node(param[HIR_PARAM_RECORD_FN]))
        return param[HIR_PARAM_RECORD_NAME_TOKEN];

    if (valid_node(hir_match_payload_owner_arm[node]))
        return node < gParams.n_hir_nodes ? hir_token_pos[node] : INVALID;

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= active_semantic_hir_count())
        return;
    uint node = hir_semantic_dense_node[row];
    if (!valid_node(node))
    {
        hir_visible_decl_flag[row] = 0u;
        return;
    }

    uint decl_token = decl_token_for_hir_node(node);
    hir_visible_decl_flag[row] = valid_decl_name_token(decl_token) ? 1u : 0u;
}

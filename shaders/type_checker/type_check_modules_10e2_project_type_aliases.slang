// GPU type-alias projection from HIR type-reference records.
//
// This pass runs after parser/HIR type metadata and type-expression refs have
// been built. It projects each type alias declaration by consuming the parser's
// explicit alias-target type record and the semantic type-ref record on that
// node. It does not inspect source bytes, token spellings, token kinds, token
// neighborhoods, or parse-tree child/sibling walks.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_alias_target_node;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_type_decl;
RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;

RWStructuredBuffer<uint> module_type_path_type;
RWStructuredBuffer<uint> module_type_path_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_UNSUPPORTED_ALIAS = 8u;

static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_ERROR = 4u;

static const uint TY_UNKNOWN = 0u;
static const uint MAX_ALIAS_CHAIN = 8u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint active_decl_count()
{
    return min(decl_count_out[0], gParams.n_hir_nodes);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint alias_target_type_node(uint alias_node)
{
    if (!valid_node(alias_node))
        return INVALID;
    uint target = hir_type_alias_target_node[alias_node];
    return valid_node(target) ? target : INVALID;
}

bool alias_target_type_ref(uint alias_node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;

    uint current_alias_node = alias_node;
    [loop]
    for (uint step = 0u; step < MAX_ALIAS_CHAIN; step += 1u)
    {
        uint type_node = alias_target_type_node(current_alias_node);
        if (!valid_node(type_node))
            return false;

        uint type_token = hir_token_pos[type_node];
        if (!valid_token(type_token))
            return false;

        tag = type_expr_ref_tag[type_token];
        payload = type_expr_ref_payload[type_token];
        if (tag == TYPE_REF_INVALID || tag == TYPE_REF_ERROR)
            return false;

        if (tag == TYPE_REF_GENERIC_PARAM)
        {
            uint path_i = path_id_by_owner_hir[type_node];
            uint decl_i = path_i < gParams.n_hir_nodes ? resolved_type_decl[path_i] : INVALID;
            if (decl_i < active_decl_count() &&
                decl_namespace[decl_i] == HIR_ITEM_NAMESPACE_TYPE &&
                decl_kind[decl_i] == HIR_ITEM_KIND_TYPE_ALIAS)
            {
                uint next_alias_node = decl_hir_node[decl_i];
                if (!valid_node(next_alias_node) || next_alias_node == current_alias_node ||
                    next_alias_node == alias_node)
                    return false;
                current_alias_node = next_alias_node;
                continue;
            }
        }

        return true;
    }

    tag = TYPE_REF_INVALID;
    payload = INVALID;
    return false;
}

uint type_code_for_ref(uint tag, uint payload)
{
    return tag == TYPE_REF_SCALAR ? payload : TY_UNKNOWN;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint decl_i = linear_thread_id(dtid);
    if (decl_i >= active_decl_count())
        return;
    if (decl_kind[decl_i] != HIR_ITEM_KIND_TYPE_ALIAS ||
        decl_namespace[decl_i] != HIR_ITEM_NAMESPACE_TYPE)
        return;

    uint name_token = decl_name_token[decl_i];
    if (!valid_token(name_token))
        return;

    uint tag = TYPE_REF_INVALID;
    uint payload = INVALID;
    if (!alias_target_type_ref(decl_hir_node[decl_i], tag, payload))
    {
        module_type_path_status[name_token] = PATH_RESOLVE_STATUS_UNSUPPORTED_ALIAS;
        return;
    }

    type_expr_ref_tag[name_token] = tag;
    type_expr_ref_payload[name_token] = payload;

    uint ty = type_code_for_ref(tag, payload);
    if (ty != TY_UNKNOWN)
        module_type_path_type[name_token] = ty;
    module_type_path_status[name_token] = PATH_RESOLVE_STATUS_OK;
}

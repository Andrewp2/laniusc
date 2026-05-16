// GPU type-alias projection from HIR type-reference records.
//
// This pass runs after parser/HIR type metadata and type-expression refs have
// been built. It projects each type alias declaration by reading the alias
// item's target type child from the parse tree and consuming the semantic
// type-ref record on that child. It does not inspect source bytes, token
// spellings, token kinds, or token neighborhoods.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;

RWStructuredBuffer<uint> module_type_path_type;
RWStructuredBuffer<uint> module_type_path_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_UNSUPPORTED_ALIAS = 8u;

static const uint HIR_TYPE = 5u;

static const uint HIR_TYPE_FORM_NONE = 0u;

static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;

static const uint TY_UNKNOWN = 0u;

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

uint next_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint sibling = next_sibling[node];
    return valid_node(sibling) ? sibling : INVALID;
}

uint alias_target_type_node(uint alias_node)
{
    if (!valid_node(alias_node))
        return INVALID;

    uint child = first_child[alias_node];
    [loop]
    for (uint guard = 0u; guard < 16u && valid_node(child); guard += 1u)
    {
        if (hir_kind[child] == HIR_TYPE && hir_type_form[child] != HIR_TYPE_FORM_NONE)
            return child;
        child = next_sibling_node(child);
    }
    return INVALID;
}

uint alias_target_type_code(uint alias_node)
{
    uint type_node = alias_target_type_node(alias_node);
    if (!valid_node(type_node))
        return TY_UNKNOWN;

    uint type_token = hir_token_pos[type_node];
    if (!valid_token(type_token))
        return TY_UNKNOWN;

    uint tag = type_expr_ref_tag[type_token];
    uint payload = type_expr_ref_payload[type_token];
    if (tag == TYPE_REF_SCALAR)
        return payload;
    return TY_UNKNOWN;
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

    uint ty = alias_target_type_code(decl_hir_node[decl_i]);
    if (ty == TY_UNKNOWN)
    {
        module_type_path_status[name_token] = PATH_RESOLVE_STATUS_UNSUPPORTED_ALIAS;
        return;
    }

    module_type_path_type[name_token] = ty;
    module_type_path_status[name_token] = PATH_RESOLVE_STATUS_OK;
}

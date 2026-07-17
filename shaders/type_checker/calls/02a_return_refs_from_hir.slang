// Compact-HIR function return type-reference projection.
//
// The canonical parser artifact owns the dense function -> dense return-type
// relation. This pass publishes declaration-token keyed semantic references
// without indexing raw parse nodes or re-deriving type syntax from tokens.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_fn_return_type;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_type_code_by_name_id;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> visible_type;

RWStructuredBuffer<uint> fn_return_ref_tag;
RWStructuredBuffer<uint> fn_return_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint HIR_FN = 3u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool valid_hir(uint node)
{
    return node != INVALID && node < active_hir_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint scalar_type_for_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;
    uint ty = module_type_path_type[token];
    if (ty != TY_UNKNOWN)
        return ty;
    ty = visible_type[token];
    if (ty != TY_UNKNOWN)
        return ty;
    uint name_id = name_id_by_token[token];
    return name_id == INVALID ? TY_UNKNOWN : language_type_code_by_name_id[name_id];
}

uint semantic_type_token(uint type_node)
{
    if (!valid_hir(type_node))
        return INVALID;
    uint path_i = path_id_by_owner_hir[type_node];
    uint path_count = min(path_count_out[0u], gParams.n_hir_nodes);
    if (path_i != INVALID && path_i < path_count)
    {
        uint token = path_owner_token[path_i];
        if (valid_token(token))
            return token;
    }
    return compact_hir_core[type_node].token_start;
}

uint resolved_type_for_type_node(uint type_node, uint type_token)
{
    if (!valid_hir(type_node))
        return scalar_type_for_token(type_token);
    uint path_i = path_id_by_owner_hir[type_node];
    uint path_count = min(path_count_out[0u], gParams.n_hir_nodes);
    if (path_i == INVALID || path_i >= path_count)
        return scalar_type_for_token(type_token);
    uint decl_i = resolved_type_decl[path_i];
    if (decl_i == INVALID || decl_i >= gParams.n_hir_nodes)
        return scalar_type_for_token(type_token);
    uint decl_token = decl_name_token[decl_i];
    if (!valid_token(decl_token))
        return scalar_type_for_token(type_token);
    if (decl_kind[decl_i] == HIR_ITEM_KIND_STRUCT)
        return TY_STRUCT_BASE + decl_token;
    if (decl_kind[decl_i] == HIR_ITEM_KIND_ENUM)
        return TY_ENUM_BASE + decl_token;
    uint projected = module_type_path_type[decl_token];
    return projected != TY_UNKNOWN ? projected : scalar_type_for_token(type_token);
}

void publish_function_return_ref(uint fn_node)
{
    // Function semantic tables are keyed by the declaration-name token.  The
    // core span starts at the function syntax anchor (normally `fn`), while
    // payload.b is the canonical name token shared by module resolution,
    // parameter metadata, calls, and backend ABI lowering.
    uint decl_token = compact_hir_payload[fn_node].b;
    if (!valid_token(decl_token))
        return;

    fn_return_ref_tag[decl_token] = TYPE_REF_INVALID;
    fn_return_ref_payload[decl_token] = INVALID;

    uint type_node = compact_fn_return_type[fn_node];
    if (!valid_hir(type_node))
        return;
    uint type_token = semantic_type_token(type_node);
    if (!valid_token(type_token))
        return;

    uint tag = type_expr_ref_tag[type_token];
    uint payload = type_expr_ref_payload[type_token];
    uint resolved_ty = resolved_type_for_type_node(type_node, type_token);
    if (resolved_ty != TY_UNKNOWN &&
        (tag != TYPE_REF_INSTANCE || payload == INVALID))
    {
        tag = TYPE_REF_SCALAR;
        payload = resolved_ty;
    }
    else if (tag == TYPE_REF_INVALID || payload == INVALID)
    {
        if (resolved_ty != TY_UNKNOWN)
        {
            tag = TYPE_REF_SCALAR;
            payload = resolved_ty;
        }
    }
    fn_return_ref_tag[decl_token] = tag;
    fn_return_ref_payload[decl_token] = payload;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_hir(node) || compact_hir_core[node].kind != HIR_FN)
        return;
    publish_function_return_ref(node);
}

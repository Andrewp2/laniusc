// HIR-driven scalar/path type-reference collection.
//
// This pass consumes parser-owned HIR type-form records plus resolver-produced
// module type-path codes. It does not read token spellings, source bytes, or
// token-neighborhood syntax. Named generic instances, arrays, slices, and
// references are layered by later HIR passes to stay under the storage binding
// limit while preserving the paper-style array pipeline.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_decl_name_id;
StructuredBuffer<uint> language_decl_kind;
StructuredBuffer<uint> language_decl_tag;

RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;

static const uint HIR_TYPE_FORM_NONE = 0u;
static const uint HIR_TYPE_FORM_PATH = 1u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_ERROR = 4u;

static const uint TY_UNKNOWN = 0u;
static const uint LANGUAGE_DECL_COUNT = 18u;
static const uint LANGUAGE_DECL_KIND_PRIMITIVE_TYPE = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool is_hir_path_type_node(uint node)
{
    return valid_node(node) && hir_kind[node] == HIR_TYPE &&
           hir_type_form[node] == HIR_TYPE_FORM_PATH;
}

uint language_type_code_for_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;
    uint name_id = name_id_by_token[token];
    if (name_id == INVALID)
        return TY_UNKNOWN;

    [loop]
    for (uint decl_i = 0u; decl_i < LANGUAGE_DECL_COUNT; decl_i += 1u)
    {
        if (language_decl_kind[decl_i] == LANGUAGE_DECL_KIND_PRIMITIVE_TYPE &&
            language_decl_name_id[decl_i] == name_id)
            return language_decl_tag[decl_i];
    }
    return TY_UNKNOWN;
}

void publish_path_ref(uint token)
{
    uint resolved = module_type_path_type[token];
    if (resolved == TY_UNKNOWN)
        resolved = language_type_code_for_token(token);
    if (resolved != TY_UNKNOWN)
    {
        type_expr_ref_tag[token] = TYPE_REF_SCALAR;
        type_expr_ref_payload[token] = resolved;
    }
    else
    {
        type_expr_ref_tag[token] = TYPE_REF_GENERIC_PARAM;
        type_expr_ref_payload[token] = token;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!is_hir_path_type_node(node))
        return;

    uint token = hir_token_pos[node];
    if (!valid_token(token))
    {
        if (valid_node(node))
        {
            uint fallback = min(hir_token_pos[node], gParams.n_tokens);
            if (fallback < gParams.n_tokens)
            {
                type_expr_ref_tag[fallback] = TYPE_REF_ERROR;
                type_expr_ref_payload[fallback] = fallback;
            }
        }
        return;
    }

    publish_path_ref(token);
}

import hir_records;

// HIR-driven scalar/path type-reference collection.
//
// This pass consumes compact HIR type-form records plus resolver-produced
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

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_type_code_by_name_id;

RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_TYPE = 5u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;

static const uint HIR_TYPE_FORM_NONE = 0u;
static const uint HIR_TYPE_FORM_PATH = 1u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_ERROR = 4u;

static const uint TY_UNKNOWN = 0u;
static const uint LANGUAGE_SYMBOL_COUNT = 68u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_compact_hir_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint language_type_code_for_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;
    uint name_id = name_id_by_token[token];
    if (name_id == INVALID || name_id >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        return TY_UNKNOWN;

    return language_type_code_by_name_id[name_id];
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
    else if (type_expr_ref_tag[token] != TYPE_REF_INVALID)
    {
        return;
    }
    else
    {
        type_expr_ref_tag[token] = TYPE_REF_GENERIC_PARAM;
        type_expr_ref_payload[token] = token;
    }
}

uint path_leaf_token_for_type_node(uint node)
{
    uint path = path_id_by_owner_hir[node];
    uint path_count = min(path_count_out[0u], gParams.n_hir_nodes);
    if (path == INVALID || path >= path_count)
        return INVALID;
    uint count = path_segment_count[path];
    if (count == 0u)
        return INVALID;
    uint row = path_segment_base[path] + count - 1u;
    return row < gParams.n_tokens ? path_segment_token[row] : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    uint compact_count = active_compact_hir_count();
    if (node < compact_count &&
        ((compact_hir_core[node].kind == HIR_TYPE &&
          compact_hir_payload[node].a == HIR_TYPE_FORM_PATH) ||
         compact_hir_core[node].kind == HIR_STRUCT_LITERAL_EXPR))
    {
        uint compact_token = compact_hir_core[node].token_start;
        uint leaf_token = path_leaf_token_for_type_node(node);
        if (valid_token(compact_token))
            publish_path_ref(compact_token);
        if (valid_token(leaf_token) && leaf_token != compact_token)
            publish_path_ref(leaf_token);
    }

    // Variant payload rows are the authoritative declaration-family relation;
    // consume their dense type ids directly instead of depending on a raw
    // parser node having the same index or wrapper shape.
    uint variant_payload_count =
        min(compact_variant_payload_row_count[0u], gParams.n_hir_nodes);
    if (node < variant_payload_count)
    {
        uint type_node = compact_variant_payloads[node].type_node;
        if (type_node < compact_count)
        {
            uint type_token = compact_hir_core[type_node].token_start;
            if (valid_token(type_token))
                publish_path_ref(type_token);
        }
    }
}

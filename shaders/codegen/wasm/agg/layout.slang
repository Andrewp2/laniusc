// Project aggregate field ordinals for HIR-driven WASM lowering.
//
// Type checking already resolves member and struct-literal field ordinals with
// sorted HIR/type records. This active WASM boundary only copies those records
// into the token-keyed buffers that the aggregate layout clear pass owns.
// Unsupported or unresolved aggregate shapes remain INVALID from the clear pass.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> member_result_field_ordinal;
StructuredBuffer<uint> type_decl_hir_node_by_token;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirField { uint owner; uint name_token; uint value; uint ordinal; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> struct_init_field_ordinal_by_row;

RWStructuredBuffer<uint> struct_init_field_index;
RWStructuredBuffer<uint> member_result_field_index;
RWStructuredBuffer<uint> wasm_agg_local_width_by_token;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint HIR_STRUCT_ITEM = 27u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint visible_type_for_token(uint token)
{
    if (token >= gParams.n_tokens)
        return TY_UNKNOWN;
    uint ty = visible_type[token];
    return ty == INVALID ? TY_UNKNOWN : ty;
}

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

uint active_compact_field_count()
{
    return min(compact_field_count[0u], gParams.n_tokens);
}

bool valid_compact_node(uint node)
{
    return node != INVALID && node < active_compact_hir_count();
}

uint struct_width_for_dense_node(uint struct_node)
{
    uint hir_count = active_compact_hir_count();
    if (struct_node >= hir_count || compact_hir_core[struct_node].kind != HIR_STRUCT_ITEM)
        return 0u;

    uint field_count = active_compact_field_count();
    uint lo = 0u;
    uint hi = field_count;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_fields[mid].owner < struct_node)
            lo = mid + 1u;
        else
            hi = mid;
    }
    uint begin = lo;
    hi = field_count;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_fields[mid].owner <= struct_node)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo - begin;
}

uint struct_width_for_type(uint ty)
{
    if (ty < TY_STRUCT_BASE || ty >= TY_ENUM_BASE)
        return 0u;

    uint decl_token = ty - TY_STRUCT_BASE;
    if (decl_token >= gParams.n_tokens)
        return 0u;

    return struct_width_for_dense_node(type_decl_hir_node_by_token[decl_token]);
}

uint struct_width_for_decl_ref(uint decl_token)
{
    if (decl_token >= gParams.n_tokens ||
        decl_type_ref_tag[decl_token] != TYPE_REF_INSTANCE)
        return 0u;

    uint instance = decl_type_ref_payload[decl_token];
    if (instance >= gParams.n_tokens)
        return 0u;
    uint struct_decl = type_instance_decl_token[instance];
    if (struct_decl >= gParams.n_tokens)
        return 0u;
    return struct_width_for_dense_node(type_decl_hir_node_by_token[struct_decl]);
}

uint call_return_width(uint call_node)
{
    if (!valid_compact_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return 0u;

    uint call_token = compact_hir_core[call_node].token_start;
    if (call_token >= gParams.n_tokens)
        return 0u;

    return struct_width_for_type(call_return_type[call_token]);
}

void publish_member_projection(uint token_i)
{
    uint index = member_result_field_ordinal[token_i];
    if (index != INVALID)
        member_result_field_index[token_i] = index;
}

void publish_struct_init_projection(uint field_row)
{
    HirField field = compact_fields[field_row];
    if (!valid_compact_node(field.owner) ||
        compact_hir_core[field.owner].kind != HIR_STRUCT_LITERAL_EXPR ||
        field.name_token >= gParams.n_tokens)
        return;

    uint index = struct_init_field_ordinal_by_row[field_row];
    if (index != INVALID)
        struct_init_field_index[field.name_token] = index;
}

void publish_aggregate_local_width(uint lit_node)
{
    HirCore literal = compact_hir_core[lit_node];
    if (literal.kind != HIR_STRUCT_LITERAL_EXPR)
        return;

    HirPayload literal_payload = compact_hir_payload[lit_node];
    uint let_node = literal_payload.d;
    if (!valid_compact_node(let_node) || compact_hir_core[let_node].kind != HIR_LET_STMT)
        return;
    uint decl_token = compact_hir_payload[let_node].b;
    if (decl_token >= gParams.n_tokens)
        return;

    uint width = literal_payload.c;
    if (width != 0u && width != INVALID)
        wasm_agg_local_width_by_token[decl_token] = width;
}

void publish_return_aggregate_width(uint lit_node)
{
    HirCore literal = compact_hir_core[lit_node];
    if (literal.kind != HIR_STRUCT_LITERAL_EXPR)
        return;

    HirPayload literal_payload = compact_hir_payload[lit_node];
    uint return_node = literal_payload.d;
    if (!valid_compact_node(return_node) || compact_hir_core[return_node].kind != HIR_RETURN_STMT)
        return;

    uint return_token = compact_hir_core[return_node].token_start;
    if (return_token >= gParams.n_tokens)
        return;

    uint width = literal_payload.c;
    if (width != 0u && width != INVALID)
        wasm_agg_local_width_by_token[return_token] = width;
}

void publish_let_aggregate_local_width(uint let_node)
{
    if (!valid_compact_node(let_node) || compact_hir_core[let_node].kind != HIR_LET_STMT)
        return;

    HirPayload let_payload = compact_hir_payload[let_node];
    uint decl_token = let_payload.b;
    if (decl_token >= gParams.n_tokens)
        return;

    uint width = struct_width_for_decl_ref(decl_token);
    if (width == 0u)
        width = struct_width_for_type(visible_type_for_token(decl_token));
    if (width == 0u)
        width = call_return_width(let_payload.c);

    if (width != 0u)
        wasm_agg_local_width_by_token[decl_token] = width;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_id(tid);
    if (i < gParams.n_tokens)
        publish_member_projection(i);
    if (i < active_compact_field_count())
        publish_struct_init_projection(i);
    if (i < active_compact_hir_count())
    {
        publish_aggregate_local_width(i);
        publish_return_aggregate_width(i);
        publish_let_aggregate_local_width(i);
    }
}

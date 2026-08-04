// Publish struct-literal contextual type records from parser-owned statement HIR.
//
// This pass records the nearest let/return statement context for struct literals.
// Field typing consumes these literal-keyed rows instead of walking ancestors per
// field. Broader nested context propagation should be added as another explicit
// relation, not by restoring per-consumer tree walks.

import hir_records;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
    uint parser_feature_flags;
};

ConstantBuffer<Params> gParams;


StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_array_element_start;
StructuredBuffer<uint> compact_array_element_count;
StructuredBuffer<HirArrayElement> compact_array_elements;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_len;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;

RWStructuredBuffer<uint> struct_lit_context_decl_token;
RWStructuredBuffer<uint> struct_lit_context_instance;

static const uint INVALID = 0xffffffffu;
static const uint PARSER_FEATURE_STRUCTS = 0x00000010u;

static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return gParams.n_tokens;
}

uint active_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_token(uint i)
{
    return i != INVALID && i < active_token_count();
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_node_count();
}

uint enclosing_function_decl_token(uint token)
{
    uint encoded_fn = valid_token(token) ? enclosing_fn[token] : 0u;
    uint fn_node = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (fn_node == INVALID || fn_node >= count)
        return INVALID;
    uint fn_token = compact_hir_payload[fn_node].b;
    return valid_token(fn_token) ? fn_token : INVALID;
}

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

HirPayload stmt_payload(uint node)
{
    HirPayload payload;
    payload.a = 0u;
    payload.b = INVALID;
    payload.c = INVALID;
    payload.d = INVALID;
    return node < active_compact_hir_count() ? compact_hir_payload[node] : payload;
}

bool context_for_type_ref(uint tag, uint payload, out uint decl_token, out uint instance_i)
{
    decl_token = INVALID;
    instance_i = INVALID;
    if (tag == TYPE_REF_INSTANCE && valid_token(payload))
    {
        uint instance_decl = type_instance_decl_token[payload];
        if (!valid_token(instance_decl))
            return false;
        decl_token = instance_decl;
        instance_i = payload;
        return true;
    }
    if (tag == TYPE_REF_SCALAR && payload >= TY_STRUCT_BASE && payload < TY_ENUM_BASE)
    {
        decl_token = payload - TY_STRUCT_BASE;
        return valid_token(decl_token);
    }
    return false;
}

uint bounded_array_instance_from_ref(uint tag, uint payload)
{
    if (tag != TYPE_REF_INSTANCE || !valid_token(payload))
        return INVALID;
    return type_instance_kind[payload] == TYPE_INSTANCE_ARRAY ? payload : INVALID;
}

uint type_head_token_for_compact_node(uint type_node)
{
    if (type_node >= active_compact_hir_count())
        return INVALID;
    uint path = path_id_by_owner_hir[type_node];
    if (path < gParams.n_hir_nodes)
    {
        uint count = path_len[path];
        uint base = path_segment_base[path];
        uint row = count == 0u ? INVALID : base + count - 1u;
        if (row < gParams.n_tokens && row >= base)
        {
            uint token = path_segment_token[row];
            if (valid_token(token))
                return token;
        }
    }
    uint token = compact_hir_core[type_node].token_start;
    return valid_token(token) ? token : INVALID;
}

bool context_for_compact_type_node(uint type_node, out uint decl_token, out uint instance_i)
{
    decl_token = INVALID;
    instance_i = INVALID;
    uint type_head = type_head_token_for_compact_node(type_node);
    if (!valid_token(type_head))
        return false;
    return context_for_type_ref(
        type_expr_ref_tag[type_head],
        type_expr_ref_payload[type_head],
        decl_token,
        instance_i);
}

bool is_struct_literal(uint node)
{
    return node < active_compact_hir_count() &&
           compact_hir_core[node].kind == HIR_STRUCT_LITERAL_EXPR;
}

void publish_context(uint literal_node, uint decl_token, uint instance_i)
{
    if (!is_struct_literal(literal_node) || !valid_token(decl_token))
        return;
    struct_lit_context_decl_token[literal_node] = decl_token;
    struct_lit_context_instance[literal_node] = instance_i;
}

void publish_let_context(uint literal_node, uint stmt_node)
{
    uint decl_token = INVALID;
    uint instance_i = INVALID;
    HirPayload stmt = stmt_payload(stmt_node);
    uint decl = stmt.b;
    if (valid_token(decl) &&
        context_for_type_ref(decl_type_ref_tag[decl], decl_type_ref_payload[decl], decl_token, instance_i))
    {
        publish_context(literal_node, decl_token, instance_i);
        return;
    }

    if (context_for_compact_type_node(stmt.d, decl_token, instance_i))
        publish_context(literal_node, decl_token, instance_i);
}

void publish_return_context(uint literal_node, uint stmt_node)
{
    uint return_token = stmt_node < active_compact_hir_count()
        ? compact_hir_core[stmt_node].token_start
        : INVALID;
    if (!valid_token(return_token))
        return;

    uint fn_token = enclosing_function_decl_token(return_token);
    if (!valid_token(fn_token))
        return;

    uint decl_token = INVALID;
    uint instance_i = INVALID;
    if (context_for_type_ref(fn_return_ref_tag[fn_token], fn_return_ref_payload[fn_token], decl_token, instance_i))
        publish_context(literal_node, decl_token, instance_i);
}

uint function_return_array_instance(uint return_node)
{
    uint return_token = return_node < active_compact_hir_count()
        ? compact_hir_core[return_node].token_start
        : INVALID;
    if (!valid_token(return_token))
        return INVALID;

    uint fn_token = enclosing_function_decl_token(return_token);
    if (!valid_token(fn_token))
        return INVALID;

    return bounded_array_instance_from_ref(
        fn_return_ref_tag[fn_token],
        fn_return_ref_payload[fn_token]);
}

uint let_array_instance(uint let_node)
{
    HirPayload stmt = stmt_payload(let_node);
    if (let_node >= active_compact_hir_count() || stmt.a != STMT_RECORD_KIND_LET)
        return INVALID;

    uint decl = stmt.b;
    if (!valid_token(decl))
        return INVALID;

    return bounded_array_instance_from_ref(
        decl_type_ref_tag[decl],
        decl_type_ref_payload[decl]);
}

uint array_instance_for_context_stmt(uint stmt_node)
{
    if (stmt_node >= active_compact_hir_count())
        return INVALID;

    uint kind = stmt_payload(stmt_node).a;
    if (kind == STMT_RECORD_KIND_LET)
        return let_array_instance(stmt_node);
    if (kind == STMT_RECORD_KIND_RETURN)
        return function_return_array_instance(stmt_node);
    return INVALID;
}

bool enclosing_array_element_node(uint literal_node, out uint array_node)
{
    array_node = INVALID;
    if (!valid_node(literal_node))
        return false;
    uint node = literal_node;
    for (uint step = 0u; step < 256u; step += 1u)
    {
        if (!valid_node(node))
            return false;
        uint parent = compact_hir_core[node].parent;
        if (!valid_node(parent))
            return false;
        if (compact_hir_core[parent].kind == 24u)
        {
            uint start = compact_array_element_start[parent];
            uint count = compact_array_element_count[parent];
            uint total = min(gParams.n_hir_nodes, compact_hir_count[0u]);
            if (start != INVALID && start < total && count <= total - start)
            {
                for (uint ordinal = 0u; ordinal < count; ordinal += 1u)
                {
                    HirArrayElement element = compact_array_elements[start + ordinal];
                    if (element.value == literal_node)
                    {
                        array_node = parent;
                        return true;
                    }
                }
            }
        }
        node = parent;
    }
    return false;
}

bool publish_array_element_context(uint literal_node, uint stmt_node)
{
    uint array_node;
    if (!enclosing_array_element_node(literal_node, array_node))
        return false;
    uint array_stmt = array_node < active_compact_hir_count()
        ? compact_hir_payload[array_node].d
        : INVALID;
    if (!valid_node(array_node) || array_stmt != stmt_node)
        return false;

    uint array_instance = array_instance_for_context_stmt(stmt_node);
    if (!valid_token(array_instance))
        return false;

    uint decl_token = INVALID;
    uint instance_i = INVALID;
    if (!context_for_type_ref(
        type_instance_elem_ref_tag[array_instance],
        type_instance_elem_ref_payload[array_instance],
        decl_token,
        instance_i))
        return false;

    publish_context(literal_node, decl_token, instance_i);
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if ((gParams.parser_feature_flags & PARSER_FEATURE_STRUCTS) == 0u)
        return;
    uint i = linear_thread_id(dtid);
    if (!valid_node(i))
        return;
    if (!is_struct_literal(i))
        return;

    uint literal = i;
    uint stmt_node = literal < active_compact_hir_count()
        ? compact_hir_payload[literal].d
        : INVALID;
    if (stmt_node >= active_compact_hir_count())
        return;

    if (publish_array_element_context(i, stmt_node))
        return;

    uint kind = stmt_payload(stmt_node).a;
    if (kind == STMT_RECORD_KIND_LET)
        publish_let_context(i, stmt_node);
    else if (kind == STMT_RECORD_KIND_RETURN)
        publish_return_context(i, stmt_node);
}

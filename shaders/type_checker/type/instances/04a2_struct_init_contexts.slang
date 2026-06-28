// Publish struct-literal contextual type records from parser-owned statement HIR.
//
// This pass records the nearest let/return statement context for struct literals.
// Field typing consumes these literal-keyed rows instead of walking ancestors per
// field. Broader nested context propagation should be added as another explicit
// relation, not by restoring per-consumer tree walks.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_type_value_node;
StructuredBuffer<uint> hir_type_path_leaf_node;
StructuredBuffer<uint> hir_array_lit_context_stmt_node;
StructuredBuffer<uint> hir_array_element_parent_lit;
StructuredBuffer<uint> hir_struct_lit_head_node;
StructuredBuffer<uint> hir_struct_lit_context_stmt_node;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;

RWStructuredBuffer<uint> struct_lit_context_decl_token;
RWStructuredBuffer<uint> struct_lit_context_instance;

static const uint INVALID = 0xffffffffu;

static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;

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
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_token(uint i)
{
    return i != INVALID && i < active_token_count();
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_node_count();
}

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

uint type_head_token_for_node(uint type_node)
{
    if (!valid_node(type_node))
        return INVALID;

    uint leaf_node = hir_type_path_leaf_node[type_node];
    if (valid_node(leaf_node))
    {
        uint leaf = hir_token_pos[leaf_node];
        if (valid_token(leaf))
            return leaf;
    }

    uint value_node = hir_type_value_node[type_node];
    if (valid_node(value_node))
    {
        uint value_head = hir_token_pos[value_node];
        if (valid_token(value_head))
            return value_head;
    }

    uint type_head = hir_token_pos[type_node];
    return valid_token(type_head) ? type_head : INVALID;
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

bool context_for_type_node(uint type_node, out uint decl_token, out uint instance_i)
{
    decl_token = INVALID;
    instance_i = INVALID;
    uint type_head = type_head_token_for_node(type_node);
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
    return valid_node(node) && valid_node(hir_struct_lit_head_node[node]);
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
    uint decl = hir_stmt_record[stmt_slot(stmt_node, 1u)];
    if (valid_token(decl) &&
        context_for_type_ref(decl_type_ref_tag[decl], decl_type_ref_payload[decl], decl_token, instance_i))
    {
        publish_context(literal_node, decl_token, instance_i);
        return;
    }

    uint type_node = hir_stmt_record[stmt_slot(stmt_node, 3u)];
    if (context_for_type_node(type_node, decl_token, instance_i))
        publish_context(literal_node, decl_token, instance_i);
}

void publish_return_context(uint literal_node, uint stmt_node)
{
    uint return_token = hir_token_pos[stmt_node];
    if (!valid_token(return_token))
        return;

    uint encoded_fn = enclosing_fn[return_token];
    uint fn_token = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    if (!valid_token(fn_token))
        return;

    uint decl_token = INVALID;
    uint instance_i = INVALID;
    if (context_for_type_ref(fn_return_ref_tag[fn_token], fn_return_ref_payload[fn_token], decl_token, instance_i))
        publish_context(literal_node, decl_token, instance_i);
}

uint function_return_array_instance(uint return_node)
{
    uint return_token = hir_token_pos[return_node];
    if (!valid_token(return_token))
        return INVALID;

    uint encoded_fn = enclosing_fn[return_token];
    uint fn_token = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    if (!valid_token(fn_token))
        return INVALID;

    return bounded_array_instance_from_ref(
        fn_return_ref_tag[fn_token],
        fn_return_ref_payload[fn_token]);
}

uint let_array_instance(uint let_node)
{
    if (!valid_node(let_node) ||
        hir_stmt_record[stmt_slot(let_node, 0u)] != STMT_RECORD_KIND_LET)
        return INVALID;

    uint decl = hir_stmt_record[stmt_slot(let_node, 1u)];
    if (!valid_token(decl))
        return INVALID;

    return bounded_array_instance_from_ref(
        decl_type_ref_tag[decl],
        decl_type_ref_payload[decl]);
}

uint array_instance_for_context_stmt(uint stmt_node)
{
    if (!valid_node(stmt_node))
        return INVALID;

    uint kind = hir_stmt_record[stmt_slot(stmt_node, 0u)];
    if (kind == STMT_RECORD_KIND_LET)
        return let_array_instance(stmt_node);
    if (kind == STMT_RECORD_KIND_RETURN)
        return function_return_array_instance(stmt_node);
    return INVALID;
}

uint enclosing_array_element_node(uint literal_node)
{
    if (!valid_node(literal_node))
        return INVALID;

    uint found = INVALID;
    [loop]
    for (uint node = 0u; node < literal_node; node += 1u)
    {
        uint array_node = hir_array_element_parent_lit[node];
        if (!valid_node(array_node))
            continue;

        uint end = subtree_end[node];
        if (end != INVALID && end > literal_node && end <= active_node_count())
            found = node;
    }
    return found;
}

bool publish_array_element_context(uint literal_node, uint stmt_node)
{
    uint element_node = enclosing_array_element_node(literal_node);
    if (!valid_node(element_node))
        return false;

    uint array_node = hir_array_element_parent_lit[element_node];
    if (!valid_node(array_node) ||
        hir_array_lit_context_stmt_node[array_node] != stmt_node)
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
    uint i = linear_thread_id(dtid);
    if (!valid_node(i))
        return;
    if (!is_struct_literal(i))
        return;

    uint stmt_node = hir_struct_lit_context_stmt_node[i];
    if (!valid_node(stmt_node))
        return;

    if (publish_array_element_context(i, stmt_node))
        return;

    uint kind = hir_stmt_record[stmt_slot(stmt_node, 0u)];
    if (kind == STMT_RECORD_KIND_LET)
        publish_let_context(i, stmt_node);
    else if (kind == STMT_RECORD_KIND_RETURN)
        publish_return_context(i, stmt_node);
}

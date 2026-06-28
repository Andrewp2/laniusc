// x86_64 struct projection records.
//
// This pass compresses parser/type-checker struct metadata into two backend
// record arrays consumed by node instruction planning. Later x86 passes use
// these records instead of binding the full HIR aggregate surface.

import gpu_index;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_struct_lit_head_node;
StructuredBuffer<uint> hir_struct_lit_context_stmt_node;
StructuredBuffer<uint> hir_struct_lit_field_parent_lit;
StructuredBuffer<uint> hir_struct_lit_field_start;
StructuredBuffer<uint> hir_struct_lit_field_count;
StructuredBuffer<uint> hir_struct_decl_field_count;
StructuredBuffer<uint> hir_struct_lit_field_value_node;
StructuredBuffer<uint> hir_struct_lit_field_next;
StructuredBuffer<uint> hir_array_lit_first_element;
StructuredBuffer<uint> hir_array_lit_element_count;
StructuredBuffer<uint> hir_array_element_parent_lit;
StructuredBuffer<uint> hir_array_element_ordinal;
StructuredBuffer<uint> hir_array_element_next;
StructuredBuffer<uint> member_result_field_ordinal;
StructuredBuffer<uint> struct_init_field_ordinal_by_node;
StructuredBuffer<uint> x86_tree_parent;
StructuredBuffer<uint> x86_node_tree_status;
StructuredBuffer<uint> x86_enclosing_let_node;

RWStructuredBuffer<uint> x86_struct_type_record;
RWStructuredBuffer<uint> x86_struct_access_record;
RWStructuredBuffer<uint4> x86_struct_store_record;
RWStructuredBuffer<uint> x86_struct_record_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

static const uint X86_NODE_TREE_OK = 1u;
static const uint X86_STRUCT_RECORDS_OK = 1u;
static const uint X86_ERR_STRUCT_RECORDS = 28u;

static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint X86_STRUCT_ACCESS_NONE = 0u;
static const uint X86_STRUCT_ACCESS_MEMBER = 1u;
static const uint X86_STRUCT_ACCESS_LITERAL = 2u;
static const uint X86_AGG_STORE_ARRAY = 2u;
static const uint X86_STRUCT_ACCESS_STRIDE = 3u;
static const uint X86_STRUCT_ACCESS_KIND_BITS = 4u;
static const uint X86_STRUCT_ACCESS_KIND_MASK = 0x0fu;
static const uint X86_STRUCT_ACCESS_PAYLOAD_MAX = 0x0fffffffu;
static const uint MAX_STRUCT_LITERAL_ROOT_WALK = 64u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
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

bool upstream_ok()
{
    return x86_node_tree_status[0u] == X86_NODE_TREE_OK &&
           x86_node_tree_status[1u] == 0u;
}

uint stmt_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_value_token(uint node)
{
    return valid_node(node)
               ? row_major_load<uint>(
                     hir_expr_record,
                     node,
                     EXPR_RECORD_STRIDE,
                     EXPR_RECORD_VALUE_TOKEN,
                     INVALID)
               : INVALID;
}

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

void publish_error(uint detail)
{
    publish_stage_error_min_detail4(
        x86_struct_record_status,
        X86_ERR_STRUCT_RECORDS,
        detail);
}

uint pack_struct_access_info(uint kind, uint payload)
{
    if (kind > X86_STRUCT_ACCESS_KIND_MASK || payload > X86_STRUCT_ACCESS_PAYLOAD_MAX)
        return INVALID;
    return (payload << X86_STRUCT_ACCESS_KIND_BITS) | kind;
}

bool write_struct_access_record(
    uint row,
    uint kind,
    uint payload0,
    uint payload1,
    uint payload2)
{
    uint info = pack_struct_access_info(kind, payload2);
    if (info == INVALID)
    {
        publish_error(row);
        return false;
    }
    row_major_store<uint>(x86_struct_access_record, row, X86_STRUCT_ACCESS_STRIDE, 0u, payload0);
    row_major_store<uint>(x86_struct_access_record, row, X86_STRUCT_ACCESS_STRIDE, 1u, payload1);
    row_major_store<uint>(x86_struct_access_record, row, X86_STRUCT_ACCESS_STRIDE, 2u, info);
    return true;
}

void publish_member_access_record(uint node)
{
    uint member_token = hir_member_name_token[node];
    if (!valid_token(member_token))
        return;
    uint ordinal = member_result_field_ordinal[member_token];
    if (ordinal == INVALID)
        return;
    uint receiver_node = hir_member_receiver_node[node];
    if (!valid_node(receiver_node))
        return;

    write_struct_access_record(
        node,
        X86_STRUCT_ACCESS_MEMBER,
        receiver_node,
        ordinal,
        member_token);
}

void publish_struct_type_record(uint node)
{
    uint decl_token = hir_item_name_token[node];
    uint width = hir_struct_decl_field_count[node];
    if (!valid_token(decl_token) || width == 0u)
        return;
    x86_struct_type_record[decl_token] = width;
}

void publish_literal_access_record(uint node)
{
    uint width = hir_struct_lit_field_count[node];
    if (width == 0u)
        return;
    uint first_field = hir_struct_lit_field_start[node];
    if (!write_struct_access_record(
            node,
            X86_STRUCT_ACCESS_LITERAL,
            width,
            first_field,
            0u))
        return;

    uint head_node = hir_struct_lit_head_node[node];
    if (valid_node(head_node) && head_node != node && hir_kind[head_node] != HIR_MEMBER_EXPR)
    {
        write_struct_access_record(
            head_node,
            X86_STRUCT_ACCESS_LITERAL,
            width,
            first_field,
            0u);
        uint head_token = expr_value_token(head_node);
        if (valid_token(head_token))
            x86_struct_type_record[head_token] = width;
    }

    uint context_stmt = hir_struct_lit_context_stmt_node[node];
    uint context_kind = valid_node(context_stmt) ? stmt_slot(context_stmt, 0u) : 0u;
    uint context_expr = context_kind == STMT_RECORD_KIND_RETURN
                            ? stmt_slot(context_stmt, 1u)
                            : context_kind == STMT_RECORD_KIND_LET
                                  ? stmt_slot(context_stmt, 2u)
                                  : INVALID;
    if (valid_node(context_expr) && context_expr != node && context_expr != head_node)
    {
        write_struct_access_record(
            context_expr,
            X86_STRUCT_ACCESS_LITERAL,
            width,
            first_field,
            0u);
    }
}

void publish_store_record_for_value(uint value_node, uint decl_token, uint ordinal, uint literal_node)
{
    if (!valid_node(value_node) || !valid_token(decl_token) || ordinal == INVALID)
        return;
    x86_struct_store_record[value_node] = uint4(decl_token, ordinal, literal_node, 0u);
}

bool let_initializer_is_struct_literal(uint let_node, uint literal_node)
{
    if (!valid_node(let_node) || !valid_node(literal_node))
        return false;
    // Nested aggregate ownership needs an explicit owner/path record; do not
    // infer it from subtree spans in this backend projection.
    uint init_expr = stmt_slot(let_node, 2u);
    uint resolved_init = resolve_expr(init_expr);
    if (init_expr == literal_node || resolved_init == literal_node)
        return true;

    uint head_node = hir_struct_lit_head_node[literal_node];
    return valid_node(head_node) &&
           (init_expr == head_node || resolved_init == head_node);
}

bool struct_literal_context_matches_let(uint literal_node, uint let_node)
{
    return valid_node(literal_node) &&
           valid_node(let_node) &&
           hir_struct_lit_context_stmt_node[literal_node] == let_node;
}

bool array_element_record_for_candidate(uint candidate, out uint array_node, out uint element_ordinal)
{
    array_node = INVALID;
    element_ordinal = INVALID;
    if (!valid_node(candidate))
        return false;

    uint owner = hir_array_element_parent_lit[candidate];
    uint ordinal = hir_array_element_ordinal[candidate];
    if (!valid_node(owner) || ordinal == INVALID)
        return false;

    array_node = owner;
    element_ordinal = ordinal;
    return true;
}

bool array_element_expr_matches_struct_literal(uint element_node, uint literal_node, uint head_node)
{
    if (!valid_node(element_node))
        return false;
    if (element_node == literal_node || element_node == head_node)
        return true;

    uint resolved = resolve_expr(element_node);
    if (!valid_node(resolved))
        return false;
    if (resolved == literal_node || resolved == head_node)
        return true;

    uint literal_cursor = literal_node;
    uint head_cursor = head_node;
    [loop]
    for (uint depth = 0u; depth < MAX_STRUCT_LITERAL_ROOT_WALK; depth += 1u)
    {
        if (literal_cursor == resolved || head_cursor == resolved)
            return true;
        literal_cursor = valid_node(literal_cursor) ? x86_tree_parent[literal_cursor] : INVALID;
        head_cursor = valid_node(head_cursor) ? x86_tree_parent[head_cursor] : INVALID;
        if (!valid_node(literal_cursor) && !valid_node(head_cursor))
            return false;
    }
    return false;
}

bool array_element_record_for_struct_literal(
    uint literal_node,
    out uint array_node,
    out uint element_ordinal)
{
    array_node = INVALID;
    element_ordinal = INVALID;
    if (!valid_node(literal_node))
        return false;

    uint head_node = hir_struct_lit_head_node[literal_node];
    if (array_element_record_for_candidate(literal_node, array_node, element_ordinal) ||
        array_element_record_for_candidate(head_node, array_node, element_ordinal) ||
        array_element_record_for_candidate(resolve_expr(head_node), array_node, element_ordinal))
        return true;

    uint context_stmt = hir_struct_lit_context_stmt_node[literal_node];
    if (!valid_node(context_stmt) || stmt_slot(context_stmt, 0u) != STMT_RECORD_KIND_LET)
        return false;

    uint init_expr = stmt_slot(context_stmt, 2u);
    uint literal_array = resolve_expr(init_expr);
    if (!valid_node(literal_array) || hir_kind[literal_array] != HIR_ARRAY_EXPR)
        return false;

    uint count = hir_array_lit_element_count[literal_array];
    uint element = hir_array_lit_first_element[literal_array];
    [loop]
    for (uint i = 0u; i < count && i < gParams.n_hir_nodes && valid_node(element); i += 1u)
    {
        if (array_element_expr_matches_struct_literal(element, literal_node, head_node))
        {
            array_node = literal_array;
            element_ordinal = hir_array_element_ordinal[element];
            if (element_ordinal == INVALID)
                element_ordinal = i;
            return true;
        }
        element = hir_array_element_next[element];
    }
    return false;
}

bool struct_literal_is_array_element(uint literal_node)
{
    uint array_node = INVALID;
    uint element_ordinal = INVALID;
    return array_element_record_for_struct_literal(literal_node, array_node, element_ordinal);
}

bool let_initializer_is_array_literal(uint let_node, uint array_node)
{
    if (!valid_node(let_node) || !valid_node(array_node))
        return false;
    uint init_expr = stmt_slot(let_node, 2u);
    return resolve_expr(init_expr) == array_node;
}

void publish_array_struct_field_store_record(
    uint literal_node,
    uint value_node,
    uint field_ordinal)
{
    uint array_node = INVALID;
    uint element_ordinal = INVALID;
    uint element_width = hir_struct_lit_field_count[literal_node];
    if (!array_element_record_for_struct_literal(literal_node, array_node, element_ordinal) ||
        !valid_node(array_node) || element_ordinal == INVALID ||
        field_ordinal == INVALID || element_width == 0u)
        return;

    uint let_node = x86_enclosing_let_node[array_node];
    if (!valid_node(let_node) ||
        stmt_slot(let_node, 0u) != STMT_RECORD_KIND_LET ||
        !let_initializer_is_array_literal(let_node, array_node))
        return;

    uint decl_token = stmt_slot(let_node, 1u);
    uint storage_ordinal = element_ordinal * element_width + field_ordinal;
    if (!valid_node(value_node) || !valid_token(decl_token))
        return;
    x86_struct_store_record[value_node] = uint4(
        decl_token,
        storage_ordinal,
        array_node,
        X86_AGG_STORE_ARRAY);

    uint resolved = resolve_expr(value_node);
    if (valid_node(resolved))
    {
        x86_struct_store_record[resolved] = uint4(
            decl_token,
            storage_ordinal,
            array_node,
            X86_AGG_STORE_ARRAY);
    }
}

uint context_let_node(uint node)
{
    if (!valid_node(node))
        return INVALID;

    uint let_node = x86_enclosing_let_node[node];
    return valid_node(let_node) && stmt_slot(let_node, 0u) == STMT_RECORD_KIND_LET
               ? let_node
               : INVALID;
}

uint struct_literal_context_let(uint literal_node, uint field_node, uint value_node)
{
    uint let_node = context_let_node(literal_node);
    if (valid_node(let_node))
        return let_node;

    let_node = context_let_node(field_node);
    if (valid_node(let_node))
        return let_node;

    let_node = context_let_node(value_node);
    if (valid_node(let_node))
        return let_node;

    let_node = context_let_node(resolve_expr(value_node));
    if (valid_node(let_node))
        return let_node;

    let_node = hir_struct_lit_context_stmt_node[literal_node];
    return valid_node(let_node) && stmt_slot(let_node, 0u) == STMT_RECORD_KIND_LET
               ? let_node
               : INVALID;
}

void publish_struct_field_store_record(uint field_node)
{
    uint literal_node = hir_struct_lit_field_parent_lit[field_node];
    if (!valid_node(literal_node))
        return;

    uint value_node = hir_struct_lit_field_value_node[field_node];
    if (!valid_node(value_node))
        return;

    uint ordinal = struct_init_field_ordinal_by_node[field_node];
    if (ordinal != INVALID)
    {
        uint next_field = hir_struct_lit_field_next[field_node];
        x86_struct_store_record[field_node] = uint4(value_node, ordinal, literal_node, next_field);
        publish_array_struct_field_store_record(literal_node, value_node, ordinal);
    }
    if (struct_literal_is_array_element(literal_node))
        return;

    uint let_node = struct_literal_context_let(literal_node, field_node, value_node);
    if (!valid_node(let_node))
        return;

    if (!let_initializer_is_struct_literal(let_node, literal_node) &&
        !struct_literal_context_matches_let(literal_node, let_node))
        return;

    uint decl_token = stmt_slot(let_node, 1u);
    publish_store_record_for_value(value_node, decl_token, ordinal, literal_node);
    publish_store_record_for_value(resolve_expr(value_node), decl_token, ordinal, literal_node);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    bool ok = upstream_ok();
    if (node == 0u)
    {
        x86_struct_record_status[0u] = ok ? X86_STRUCT_RECORDS_OK : 0u;
        x86_struct_record_status[1u] = ok ? 0u : x86_node_tree_status[1u];
        x86_struct_record_status[2u] = ok ? INVALID : x86_node_tree_status[2u];
        x86_struct_record_status[3u] = 0u;
    }

    if (!ok || !valid_node(node))
        return;

    if (hir_kind[node] == HIR_STRUCT_ITEM)
        publish_struct_type_record(node);
    if (hir_kind[node] == HIR_MEMBER_EXPR)
        publish_member_access_record(node);
    if (hir_kind[node] == HIR_STRUCT_LITERAL_EXPR)
        publish_literal_access_record(node);
    if (hir_struct_lit_field_parent_lit[node] != INVALID)
        publish_struct_field_store_record(node);
}

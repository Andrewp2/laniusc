// x86_64 array literal projection records.
//
// This pass compresses parser-owned array literal metadata into backend
// aggregate records consumed by instruction counting/generation. It does not
// inspect parse productions, source bytes, token spelling, helper names, or
// body shapes.

import gpu_index;

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
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> hir_array_lit_first_element;
StructuredBuffer<uint> hir_array_lit_element_count;
StructuredBuffer<uint> hir_array_element_parent_lit;
StructuredBuffer<uint> hir_array_element_ordinal;
StructuredBuffer<uint> hir_array_element_next;
StructuredBuffer<uint> x86_node_tree_status;
StructuredBuffer<uint> x86_enclosing_let_node;

RWStructuredBuffer<uint> x86_struct_access_record;
RWStructuredBuffer<uint4> x86_struct_store_record;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

static const uint X86_NODE_TREE_OK = 1u;
static const uint HIR_ARRAY_EXPR = 24u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;

static const uint EXPR_RECORD_STRIDE = 4u;

static const uint X86_STRUCT_ACCESS_ARRAY_LITERAL = 3u;
static const uint X86_STRUCT_ACCESS_ARRAY_ELEMENT = 4u;
static const uint X86_AGG_STORE_ARRAY = 2u;
static const uint X86_STRUCT_ACCESS_STRIDE = 3u;
static const uint X86_STRUCT_ACCESS_KIND_BITS = 4u;
static const uint X86_STRUCT_ACCESS_KIND_MASK = 0x0fu;
static const uint X86_STRUCT_ACCESS_PAYLOAD_MAX = 0x0fffffffu;

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

uint expr_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_expr_record,
        node,
        EXPR_RECORD_STRIDE,
        slot,
        INVALID);
}

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
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
        return false;
    row_major_store<uint>(x86_struct_access_record, row, X86_STRUCT_ACCESS_STRIDE, 0u, payload0);
    row_major_store<uint>(x86_struct_access_record, row, X86_STRUCT_ACCESS_STRIDE, 1u, payload1);
    row_major_store<uint>(x86_struct_access_record, row, X86_STRUCT_ACCESS_STRIDE, 2u, info);
    return true;
}

void publish_literal_record(uint node)
{
    uint first_element = hir_array_lit_first_element[node];
    uint count = hir_array_lit_element_count[node];
    write_struct_access_record(
        node,
        X86_STRUCT_ACCESS_ARRAY_LITERAL,
        count,
        first_element,
        0u);
}

void publish_element_record(uint node)
{
    uint array_node = hir_array_element_parent_lit[node];
    uint ordinal = hir_array_element_ordinal[node];
    if (!valid_node(array_node) || ordinal == INVALID)
        return;
    uint next_element = hir_array_element_next[node];
    write_struct_access_record(
        node,
        X86_STRUCT_ACCESS_ARRAY_ELEMENT,
        array_node,
        ordinal,
        valid_node(next_element) ? next_element : 0u);
}

void publish_store_record_for_value(uint value_node, uint decl_token, uint ordinal, uint array_node)
{
    if (!valid_node(value_node) || !valid_token(decl_token) || ordinal == INVALID)
        return;
    uint4 existing = x86_struct_store_record[value_node];
    if (existing.x != INVALID)
        return;
    x86_struct_store_record[value_node] = uint4(
        decl_token,
        ordinal,
        array_node,
        X86_AGG_STORE_ARRAY);
}

bool let_initializer_is_array_literal(uint let_node, uint array_node)
{
    if (!valid_node(let_node) || !valid_node(array_node))
        return false;
    // Nested aggregate ownership needs an explicit owner/path record; do not
    // infer it from subtree spans in this backend projection.
    uint init_expr = stmt_slot(let_node, 2u);
    return resolve_expr(init_expr) == array_node;
}

void publish_element_store_record(uint node)
{
    uint array_node = hir_array_element_parent_lit[node];
    uint ordinal = hir_array_element_ordinal[node];
    if (!valid_node(array_node) || ordinal == INVALID)
        return;

    uint let_node = valid_node(array_node) ? x86_enclosing_let_node[array_node] : INVALID;
    if (!valid_node(let_node) || stmt_slot(let_node, 0u) != STMT_RECORD_KIND_LET)
        return;

    if (!let_initializer_is_array_literal(let_node, array_node))
        return;

    uint decl_token = stmt_slot(let_node, 1u);
    publish_store_record_for_value(node, decl_token, ordinal, array_node);
    publish_store_record_for_value(resolve_expr(node), decl_token, ordinal, array_node);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    bool ok = upstream_ok();
    if (!ok || !valid_node(node))
        return;

    if (hir_kind[node] == HIR_ARRAY_EXPR)
        publish_literal_record(node);
    if (valid_node(hir_array_element_parent_lit[node]))
    {
        publish_element_record(node);
        publish_element_store_record(node);
    }
}

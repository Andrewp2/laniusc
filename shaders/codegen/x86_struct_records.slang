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
StructuredBuffer<uint> hir_struct_lit_field_parent_lit;
StructuredBuffer<uint> hir_struct_lit_field_start;
StructuredBuffer<uint> hir_struct_lit_field_count;
StructuredBuffer<uint> hir_struct_decl_field_count;
StructuredBuffer<uint> hir_struct_lit_field_value_node;
StructuredBuffer<uint> hir_struct_lit_field_next;
StructuredBuffer<uint> member_result_field_ordinal;
StructuredBuffer<uint> struct_init_field_ordinal_by_node;
StructuredBuffer<uint> x86_tree_parent;
StructuredBuffer<uint> x86_tree_subtree_end;
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

static const uint HIR_EXPR = 14u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;

static const uint EXPR_RECORD_STRIDE = 4u;

static const uint X86_STRUCT_ACCESS_NONE = 0u;
static const uint X86_STRUCT_ACCESS_MEMBER = 1u;
static const uint X86_STRUCT_ACCESS_LITERAL = 2u;
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

bool node_span_contains(uint ancestor, uint node)
{
    if (!valid_node(ancestor) || !valid_node(node))
        return false;
    uint end = x86_tree_subtree_end[ancestor];
    return end != INVALID && ancestor <= node && node < end;
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
    write_struct_access_record(
        node,
        X86_STRUCT_ACCESS_LITERAL,
        width,
        first_field,
        0u);
}

void publish_store_record_for_value(uint value_node, uint decl_token, uint ordinal, uint literal_node)
{
    if (!valid_node(value_node) || !valid_token(decl_token) || ordinal == INVALID)
        return;
    x86_struct_store_record[value_node] = uint4(decl_token, ordinal, literal_node, 0u);
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
    }

    uint let_node = valid_node(literal_node) ? x86_enclosing_let_node[literal_node] : INVALID;
    if (!valid_node(let_node) || stmt_slot(let_node, 0u) != STMT_RECORD_KIND_LET)
        return;

    uint init_expr = stmt_slot(let_node, 2u);
    if (!node_span_contains(init_expr, literal_node))
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

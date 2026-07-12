// x86_64 struct projection records.
//
// This pass compresses parser/type-checker struct metadata into two backend
// record arrays consumed by node instruction planning. Later x86 passes use
// these records instead of binding the full HIR aggregate surface.

import gpu_index;
import prefix_scan;
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
StructuredBuffer<uint> hir_struct_field_parent_struct;
StructuredBuffer<uint> hir_struct_field_ordinal;
StructuredBuffer<uint> hir_struct_decl_field_start;
StructuredBuffer<uint> hir_struct_lit_head_node;
StructuredBuffer<uint> hir_struct_lit_context_stmt_node;
StructuredBuffer<uint> hir_struct_lit_field_parent_lit;
StructuredBuffer<uint> hir_struct_lit_field_start;
StructuredBuffer<uint> hir_struct_lit_field_count;
StructuredBuffer<uint> hir_struct_decl_field_count;
StructuredBuffer<uint> hir_struct_lit_field_value_node;
StructuredBuffer<uint> hir_struct_lit_field_next;
StructuredBuffer<uint> hir_array_element_parent_lit;
StructuredBuffer<uint> hir_array_element_ordinal;
StructuredBuffer<uint> hir_nearest_array_element_node;
StructuredBuffer<uint> member_result_field_ordinal;
StructuredBuffer<uint> member_result_field_node;
StructuredBuffer<uint> struct_init_field_ordinal_by_node;
StructuredBuffer<uint> struct_init_field_decl_node_by_node;
StructuredBuffer<uint> x86_struct_field_width_by_node;
StructuredBuffer<uint> x86_struct_field_stream_width;
StructuredBuffer<uint> x86_struct_field_stream_index_by_node;
StructuredBuffer<uint> x86_struct_field_scan_local_prefix;
StructuredBuffer<uint> x86_struct_field_scan_block_prefix;
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
static const uint WG_SIZE = 256u;

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

uint scanned_field_prefix(uint stream_i)
{
    return global_exclusive_prefix(
        stream_i,
        WG_SIZE,
        x86_struct_field_scan_local_prefix,
        x86_struct_field_scan_block_prefix);
}

uint field_scalar_width(uint field_node)
{
    return valid_node(field_node) ? x86_struct_field_width_by_node[field_node] : 0u;
}

uint field_scalar_offset(uint decl_field_node)
{
    if (!valid_node(decl_field_node))
        return INVALID;
    uint stream_i = x86_struct_field_stream_index_by_node[decl_field_node];
    uint ordinal = hir_struct_field_ordinal[decl_field_node];
    if (stream_i == INVALID || ordinal == INVALID || stream_i < ordinal)
        return INVALID;
    uint base_i = stream_i - ordinal;
    uint field_prefix = scanned_field_prefix(stream_i);
    uint base_prefix = scanned_field_prefix(base_i);
    return field_prefix >= base_prefix ? field_prefix - base_prefix : INVALID;
}

uint struct_scalar_width(uint struct_node)
{
    if (!valid_node(struct_node))
        return 0u;
    uint count = hir_struct_decl_field_count[struct_node];
    if (count == 0u)
        return 0u;
    uint first_field = hir_struct_decl_field_start[struct_node];
    if (!valid_node(first_field))
        return 0u;
    uint first_stream = x86_struct_field_stream_index_by_node[first_field];
    uint first_ordinal = hir_struct_field_ordinal[first_field];
    if (first_stream == INVALID || first_ordinal == INVALID || first_stream < first_ordinal)
        return 0u;
    uint base_i = first_stream - first_ordinal;
    uint last_i = base_i + count - 1u;
    if (!valid_node(last_i))
        return 0u;
    uint base_prefix = scanned_field_prefix(base_i);
    uint last_prefix = scanned_field_prefix(last_i);
    uint last_width = x86_struct_field_stream_width[last_i];
    return last_prefix >= base_prefix ? last_prefix - base_prefix + last_width : 0u;
}

uint literal_scalar_width(uint literal_node)
{
    if (!valid_node(literal_node))
        return 0u;
    uint first_field = hir_struct_lit_field_start[literal_node];
    uint decl_field = valid_node(first_field)
                          ? struct_init_field_decl_node_by_node[first_field]
                          : INVALID;
    uint struct_node = valid_node(decl_field)
                           ? hir_struct_field_parent_struct[decl_field]
                           : INVALID;
    uint width = struct_scalar_width(struct_node);
    return width != 0u ? width : hir_struct_lit_field_count[literal_node];
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
    uint field_node = member_result_field_node[member_token];
    uint offset = field_scalar_offset(field_node);
    if (offset == INVALID)
        return;
    uint receiver_node = hir_member_receiver_node[node];
    if (!valid_node(receiver_node))
        return;

    write_struct_access_record(
        node,
        X86_STRUCT_ACCESS_MEMBER,
        receiver_node,
        offset,
        member_token);
}

void publish_struct_type_record(uint node)
{
    uint decl_token = hir_item_name_token[node];
    uint width = struct_scalar_width(node);
    if (!valid_token(decl_token) || width == 0u)
        return;
    x86_struct_type_record[decl_token] = width;
}

void publish_literal_access_record(uint node)
{
    uint width = literal_scalar_width(node);
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

        // A struct literal's parser-owned head is the path immediately before
        // the literal (`Vec3` in `Vec3 { ... }`). Expression resolution may
        // canonicalize to the path wrapper's parent, so publish the same
        // literal record there instead of making every consumer rediscover a
        // sibling relationship.
        uint head_expr = x86_tree_parent[head_node];
        if (valid_node(head_expr) && head_expr != node &&
            hir_kind[head_expr] != HIR_MEMBER_EXPR)
        {
            write_struct_access_record(
                head_expr,
                X86_STRUCT_ACCESS_LITERAL,
                width,
                first_field,
                0u);
        }
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
    if (!valid_node(owner) || hir_kind[owner] != HIR_ARRAY_EXPR || ordinal == INVALID)
        return false;

    array_node = owner;
    element_ordinal = ordinal;
    return true;
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

    uint element = hir_nearest_array_element_node[literal_node];
    return array_element_record_for_candidate(element, array_node, element_ordinal);
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
    uint field_offset)
{
    uint array_node = INVALID;
    uint element_ordinal = INVALID;
    uint element_width = literal_scalar_width(literal_node);
    if (!array_element_record_for_struct_literal(literal_node, array_node, element_ordinal) ||
        !valid_node(array_node) || element_ordinal == INVALID ||
        field_offset == INVALID || element_width == 0u)
        return;

    uint let_node = x86_enclosing_let_node[array_node];
    if (!valid_node(let_node) ||
        stmt_slot(let_node, 0u) != STMT_RECORD_KIND_LET ||
        !let_initializer_is_array_literal(let_node, array_node))
        return;

    uint decl_token = stmt_slot(let_node, 1u);
    uint storage_ordinal = element_ordinal * element_width + field_offset;
    if (!valid_node(value_node) || !valid_token(decl_token))
        return;
    x86_struct_store_record[value_node] = uint4(
        decl_token,
        storage_ordinal,
        array_node,
        X86_AGG_STORE_ARRAY);

    uint resolved = resolve_expr(value_node);
    uint literal_head = hir_struct_lit_head_node[literal_node];
    if (valid_node(resolved) && resolved != literal_node && resolved != literal_head)
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

    uint decl_field_node = struct_init_field_decl_node_by_node[field_node];
    uint offset = field_scalar_offset(decl_field_node);
    if (offset != INVALID)
    {
        uint next_field = hir_struct_lit_field_next[field_node];
        x86_struct_store_record[field_node] = uint4(value_node, offset, literal_node, next_field);
        publish_array_struct_field_store_record(literal_node, value_node, offset);
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
    publish_store_record_for_value(value_node, decl_token, offset, literal_node);
    uint resolved = resolve_expr(value_node);
    uint literal_head = hir_struct_lit_head_node[literal_node];
    if (resolved != literal_node && resolved != literal_head)
        publish_store_record_for_value(resolved, decl_token, offset, literal_node);
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

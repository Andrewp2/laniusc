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
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirArrayElement { uint array; uint value; uint ordinal; uint file_id; };

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_array_element_start;
StructuredBuffer<uint> compact_array_element_count;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<HirArrayElement> compact_array_elements;
StructuredBuffer<uint> x86_compact_executable_raw;
StructuredBuffer<uint> x86_compact_expr_wrapper;
StructuredBuffer<uint> x86_node_tree_status;

RWStructuredBuffer<uint> x86_struct_access_record;
RWStructuredBuffer<uint4> x86_struct_store_record;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

static const uint X86_NODE_TREE_OK = 1u;
static const uint HIR_ARRAY_EXPR = 24u;

static const uint STMT_RECORD_KIND_LET = 1u;

static const uint X86_STRUCT_ACCESS_ARRAY_LITERAL = 3u;
static const uint X86_STRUCT_ACCESS_ARRAY_ELEMENT = 4u;
static const uint X86_STRUCT_ACCESS_LITERAL = 2u;
static const uint X86_AGG_STORE_ARRAY = 2u;
static const uint X86_STRUCT_ACCESS_STRIDE = 3u;
static const uint X86_STRUCT_ACCESS_KIND_BITS = 4u;
static const uint X86_STRUCT_ACCESS_KIND_MASK = 0x0fu;
static const uint X86_STRUCT_ACCESS_PAYLOAD_MAX = 0x0fffffffu;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_compact_hir_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_dense(uint node)
{
    return node != INVALID && node < active_compact_hir_count();
}

bool valid_raw(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

uint active_array_element_count()
{
    return min(gParams.n_hir_nodes, compact_array_element_row_count[0u]);
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

uint resolve_expr(uint node)
{
    return valid_raw(node) ? x86_expr_resolved_node[node] : INVALID;
}

uint compact_expr_raw(uint dense)
{
    if (!valid_dense(dense))
        return INVALID;
    uint raw = x86_compact_expr_wrapper[dense];
    return valid_raw(raw) ? raw : x86_compact_executable_raw[dense];
}

uint pack_struct_access_info(uint kind, uint payload)
{
    if (kind > X86_STRUCT_ACCESS_KIND_MASK || payload > X86_STRUCT_ACCESS_PAYLOAD_MAX)
        return INVALID;
    return (payload << X86_STRUCT_ACCESS_KIND_BITS) | kind;
}

uint struct_access_kind(uint node)
{
    if (!valid_raw(node))
        return 0u;
    uint info = x86_struct_access_record[node * X86_STRUCT_ACCESS_STRIDE + 2u];
    return info == INVALID ? 0u : info & X86_STRUCT_ACCESS_KIND_MASK;
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

void publish_literal_record(uint array_dense)
{
    uint array_node = x86_compact_executable_raw[array_dense];
    if (!valid_raw(array_node))
        return;
    uint start = compact_array_element_start[array_dense];
    uint count = compact_array_element_count[array_dense];
    uint first_element = INVALID;
    if (count != 0u && start < active_array_element_count())
        first_element = compact_expr_raw(compact_array_elements[start].value);
    write_struct_access_record(
        array_node,
        X86_STRUCT_ACCESS_ARRAY_LITERAL,
        count,
        first_element,
        0u);
}

bool valid_array_element(uint row, HirArrayElement element)
{
    return row < active_array_element_count() &&
           valid_dense(element.array) &&
           compact_hir_core[element.array].kind == HIR_ARRAY_EXPR &&
           valid_dense(element.value) &&
           element.ordinal != INVALID;
}

uint next_element_raw(uint row, HirArrayElement element)
{
    uint next = row + 1u;
    if (next >= active_array_element_count())
        return 0u;
    HirArrayElement candidate = compact_array_elements[next];
    return candidate.array == element.array && candidate.ordinal == element.ordinal + 1u
               ? compact_expr_raw(candidate.value)
               : 0u;
}

void publish_element_record(uint row, HirArrayElement element)
{
    uint array_node = x86_compact_executable_raw[element.array];
    uint expr_node = compact_expr_raw(element.value);
    if (!valid_raw(array_node) || !valid_raw(expr_node))
        return;
    write_struct_access_record(
        expr_node,
        X86_STRUCT_ACCESS_ARRAY_ELEMENT,
        array_node,
        element.ordinal,
        next_element_raw(row, element));
}

void publish_store_record_for_value(uint value_node, uint decl_token, uint ordinal, uint array_node)
{
    if (!valid_raw(value_node) || !valid_token(decl_token) || ordinal == INVALID)
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

bool let_initializer_is_array_literal(uint let_dense, uint array_dense)
{
    if (!valid_dense(let_dense) || !valid_dense(array_dense))
        return false;
    HirPayload array_payload = compact_hir_payload[array_dense];
    HirPayload let_payload = compact_hir_payload[let_dense];
    return array_payload.d == let_dense &&
           let_payload.a == STMT_RECORD_KIND_LET &&
           let_payload.c == array_dense;
}

void publish_element_store_record(uint row, HirArrayElement element)
{
    uint array_node = x86_compact_executable_raw[element.array];
    // The compact family row already names the semantic value. Preserve its
    // backend projection as a store owner, then mirror the record to the
    // legacy resolved row while the raw-node planner is still being removed.
    // Resolving first can skip the value-producing binary row entirely.
    uint value_node = compact_expr_raw(element.value);
    uint let_dense = compact_hir_payload[element.array].d;
    uint let_node = valid_dense(let_dense) ? x86_compact_executable_raw[let_dense] : INVALID;
    if (!valid_raw(array_node) || !valid_raw(value_node) || !valid_raw(let_node))
        return;
    if (!let_initializer_is_array_literal(let_dense, element.array))
        return;

    uint decl_token = compact_hir_payload[let_dense].b;
    uint resolved = resolve_expr(value_node);
    // Struct-array elements are lowered through their independently parallel
    // field-store records. Publishing a scalar element store on the resolved
    // type-name row would make instruction generation treat that name as a
    // runtime local.
    if (struct_access_kind(resolved) == X86_STRUCT_ACCESS_LITERAL ||
        struct_access_kind(value_node) == X86_STRUCT_ACCESS_LITERAL)
        return;
    publish_store_record_for_value(value_node, decl_token, element.ordinal, array_node);
    publish_store_record_for_value(resolved, decl_token, element.ordinal, array_node);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    bool ok = upstream_ok();
    if (!ok)
        return;

    if (row < active_compact_hir_count() &&
        compact_hir_core[row].kind == HIR_ARRAY_EXPR)
        publish_literal_record(row);
    if (row < active_array_element_count())
    {
        HirArrayElement element = compact_array_elements[row];
        if (valid_array_element(row, element))
        {
            publish_element_record(row, element);
            publish_element_store_record(row, element);
        }
    }
}

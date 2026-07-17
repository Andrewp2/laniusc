// Flag HIR nodes that may emit aggregate-literal return copies.
//
// These are not exactly the semantic-HIR rows: array elements and struct
// literal fields can be helper nodes that still scatter return-copy
// instructions. The later copy pass keeps the full validation; this pass only
// builds the compact candidate worklist with a prefix scan.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> x86_compact_expr_wrapper;
StructuredBuffer<uint> x86_compact_executable_raw;
StructuredBuffer<uint> x86_array_element_row_by_hir;
StructuredBuffer<uint> x86_struct_literal_field_row_by_hir;
StructuredBuffer<uint> x86_enclosing_return_node;

RWStructuredBuffer<uint> x86_node_inst_gen_flag;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

uint projected_value_node(uint dense, uint compact_count)
{
    if (dense >= compact_count)
        return INVALID;
    uint wrapper = x86_compact_expr_wrapper[dense];
    return valid_node(wrapper) ? wrapper : x86_compact_executable_raw[dense];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (node >= gParams.n_hir_nodes)
        return;

    uint return_node = x86_enclosing_return_node[node];
    uint compact_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint dense = raw_to_compact_hir[node];
    uint value_node = projected_value_node(dense, compact_count);
    bool is_array_element = value_node == node &&
                            x86_array_element_row_by_hir[dense] != INVALID;
    bool is_struct_field = value_node == node &&
                           x86_struct_literal_field_row_by_hir[dense] != INVALID;
    x86_node_inst_gen_flag[node] =
        valid_node(return_node) && (is_array_element || is_struct_field) ? 1u : 0u;
}

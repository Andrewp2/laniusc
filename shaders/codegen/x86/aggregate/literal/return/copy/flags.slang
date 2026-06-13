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

StructuredBuffer<uint> hir_array_element_parent_lit;
StructuredBuffer<uint> hir_struct_lit_field_parent_lit;
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (node >= gParams.n_hir_nodes)
        return;

    uint return_node = x86_enclosing_return_node[node];
    bool is_array_element = hir_array_element_parent_lit[node] != INVALID;
    bool is_struct_field = hir_struct_lit_field_parent_lit[node] != INVALID;
    x86_node_inst_gen_flag[node] =
        valid_node(return_node) && (is_array_element || is_struct_field) ? 1u : 0u;
}

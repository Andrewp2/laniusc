// Join persisted public declarations to reachable Wasm function slots.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> interface_public_decl_count;
StructuredBuffer<uint> interface_public_decl_local_id;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> wasm_func_slot_by_token;
StructuredBuffer<uint> object_body_len_by_slot;
RWStructuredBuffer<uint4> object_symbol_record;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint SYMBOL_UNDEFINED = 0u;
static const uint SYMBOL_FUNCTION = 1u;
static const uint SYMBOL_EXPORTED = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint persisted_decl = linear_dispatch_id(tid);
    uint public_count = min(interface_public_decl_count[0u], gParams.n_tokens);
    if (persisted_decl >= public_count)
        return;

    object_symbol_record[persisted_decl] = uint4(SYMBOL_UNDEFINED, INVALID, 0u, SYMBOL_EXPORTED);
    uint local_decl = interface_public_decl_local_id[persisted_decl];
    if (local_decl >= gParams.n_tokens)
        return;
    uint hir = decl_hir_node[local_decl];
    if (hir >= gParams.n_hir_nodes)
        return;
    uint fn_token = hir_token_pos[hir];
    if (fn_token >= gParams.n_tokens)
        return;
    uint slot = wasm_func_slot_by_token[fn_token];
    if (slot >= gParams.n_tokens || object_body_len_by_slot[slot] == 0u)
        return;
    object_symbol_record[persisted_decl] = uint4(
        SYMBOL_FUNCTION,
        slot,
        object_body_len_by_slot[slot],
        SYMBOL_EXPORTED);
}

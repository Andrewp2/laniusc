// Mark HIR function records for deterministic function-slot compaction.
//
// Function discovery materializes per-node records. This pass turns executable
// free-function and impl-method records into a compact-scan input so the slot
// index list is built by prefix rank rather than by an atomic append order.
// Trait method signatures may be HIR_FN rows, but they do not have parser
// impl owners and must not occupy backend function slots.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
    uint virtual_next_call_step_count;
    uint regalloc_rows_per_chunk;
    uint regalloc_chunk_count;
    uint function_slot_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> method_decl_param_offset;

RWStructuredBuffer<uint> x86_func_slot_flags;

static const uint HIR_FN = 3u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

bool valid_token(uint token_i)
{
    return token_i != INVALID && token_i < gParams.n_tokens;
}

uint canonical_function_token(uint node_i)
{
    if (node_i >= active_hir_node_count())
        return INVALID;
    uint dense = raw_to_compact_hir[node_i];
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (dense == INVALID || dense >= count || compact_hir_core[dense].kind != HIR_FN)
        return INVALID;
    uint token = compact_hir_payload[dense].b;
    return valid_token(token) ? token : INVALID;
}

uint canonical_function_item_kind(uint node_i)
{
    if (node_i >= active_hir_node_count())
        return 0u;
    uint dense = raw_to_compact_hir[node_i];
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    return dense < count && compact_hir_core[dense].kind == HIR_FN
               ? compact_hir_payload[dense].a
               : 0u;
}

bool is_compiled_function_node(uint node_i)
{
    if (node_i >= active_hir_node_count() || hir_kind[node_i] != HIR_FN)
        return false;
    if (canonical_function_item_kind(node_i) == HIR_ITEM_KIND_FN)
        return true;

    uint fn_token = canonical_function_token(node_i);
    return valid_token(fn_token) && method_decl_param_offset[fn_token] != INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint active = active_hir_node_count();
    if (row > active)
        return;

    x86_func_slot_flags[row] = is_compiled_function_node(row) ? 1u : 0u;
}

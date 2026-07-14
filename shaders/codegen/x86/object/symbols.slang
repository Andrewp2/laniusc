// Dense public-declaration symbol projection for relocatable x86 objects.
//
// The semantic-interface pass owns persisted declaration ordering. This pass
// joins that ordering to GPU-produced function slots and selected instruction
// byte ranges; it does not rediscover declarations from tokens or source.

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

StructuredBuffer<uint> interface_public_decl_count;
StructuredBuffer<uint> interface_public_decl_local_id;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> x86_func_slot_by_node;
StructuredBuffer<uint> x86_func_first_virtual_row;
StructuredBuffer<uint> x86_func_last_virtual_row;
StructuredBuffer<uint> select_status;
StructuredBuffer<uint> size_status;
StructuredBuffer<uint> text_status;
StructuredBuffer<uint> x86_inst_size;
StructuredBuffer<uint> x86_inst_byte_offset;

RWStructuredBuffer<uint4> x86_object_symbol_record;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_SELECT_OK = 1u;
static const uint X86_SIZE_OK = 1u;
static const uint X86_TEXT_OK = 1u;
static const uint X86_OBJECT_SECTION_UNDEFINED = 0u;
static const uint X86_OBJECT_SECTION_TEXT = 1u;
static const uint X86_OBJECT_SYMBOL_EXPORTED = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool upstream_ok()
{
    return select_status[0u] == X86_SELECT_OK &&
           select_status[1u] == 0u &&
           select_status[3u] <= gParams.inst_capacity &&
           size_status[0u] == X86_SIZE_OK &&
           size_status[1u] == 0u &&
           size_status[3u] == select_status[3u] &&
           text_status[0u] == X86_TEXT_OK &&
           text_status[1u] == 0u &&
           text_status[3u] == select_status[3u];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint persisted_decl = linear_dispatch_id(tid);
    uint public_count = min(interface_public_decl_count[0u], gParams.n_tokens);
    if (persisted_decl >= public_count)
        return;

    x86_object_symbol_record[persisted_decl] = uint4(
        X86_OBJECT_SECTION_UNDEFINED,
        0u,
        0u,
        X86_OBJECT_SYMBOL_EXPORTED);
    if (!upstream_ok())
        return;

    uint local_decl = interface_public_decl_local_id[persisted_decl];
    if (local_decl >= gParams.n_tokens)
        return;
    uint hir = decl_hir_node[local_decl];
    if (hir >= gParams.n_hir_nodes)
        return;
    uint slot = x86_func_slot_by_node[hir];
    if (slot >= gParams.function_slot_capacity)
        return;

    uint first_virtual = x86_func_first_virtual_row[slot];
    uint last_virtual = x86_func_last_virtual_row[slot];
    if (first_virtual == INVALID || last_virtual < first_virtual)
        return;
    uint first = first_virtual + 1u;
    uint last = last_virtual + 1u;
    uint selected_count = select_status[3u];
    if (first >= selected_count || last >= selected_count)
        return;

    uint offset = x86_inst_byte_offset[first];
    uint last_offset = x86_inst_byte_offset[last];
    uint last_size = x86_inst_size[last];
    if (last_offset < offset || last_size > 0xffffffffu - last_offset)
        return;
    uint end = last_offset + last_size;
    x86_object_symbol_record[persisted_decl] = uint4(
        X86_OBJECT_SECTION_TEXT,
        offset,
        end - offset,
        X86_OBJECT_SYMBOL_EXPORTED);
}

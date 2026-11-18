// Records, once per job before the inference rounds, the HIR rows and tokens
// of each function (inference_block_layout.slang, inference_blocks.slang).
// One lane per HIR row and token; inference_block_tables was cleared before.
import hir_records;
#include "../inference_block_layout.slang"

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> call_inference_fn_stamp;
// Lists start unused (word 0 is 0): list_inference_blocks writes them each round.
RWStructuredBuffer<uint> inference_hir_blocks;
RWStructuredBuffer<uint> inference_token_blocks;
RWStructuredBuffer<uint> inference_block_tables;

void mark_always(InferenceBlockLayout layout, uint domain, uint row)
{
    uint block = row / 256u;
    uint mark = (domain == 0u ? layout.hir_marks : layout.token_marks) + block;
    uint old;
    InterlockedCompareExchange(inference_block_tables[mark], 0u, 0xffffffffu, old);
    if (old != 0u) return;
    uint slot;
    InterlockedAdd(inference_block_tables[INFERENCE_BLOCK_ALWAYS + domain], 1u, slot);
    inference_block_tables[(domain == 0u ? layout.hir_always : layout.token_always) + slot] = block;
}

void note_row(InferenceBlockLayout layout, uint domain, uint row, uint token)
{
    uint tokens; uint stride;
    enclosing_fn.GetDimensions(tokens, stride);
    if (token >= tokens) { mark_always(layout, domain, row); return; }
    uint group = enclosing_fn[token];
    // Outside every function only a change without an owning function
    // recomputes an item, and then every row is visited.
    if (group == 0u) return;
    if (group >= layout.groups) { mark_always(layout, domain, row); return; }
    uint word = INFERENCE_BLOCK_HEADER + group * 4u + domain * 2u;
    uint old;
    InterlockedMax(inference_block_tables[word], ~row, old);
    InterlockedMax(inference_block_tables[word + 1u], row + 1u, old);
    // Every function with a HIR row has its tokens, so the token lanes list
    // every function once.
    if (domain == 1u && old == 0u)
    {
        uint slot;
        InterlockedAdd(inference_block_tables[INFERENCE_BLOCK_FUNCTIONS], 1u, slot);
        inference_block_tables[layout.functions + slot] = group;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    uint stamps; uint hir_list; uint token_list; uint hir_rows; uint stride;
    call_inference_fn_stamp.GetDimensions(stamps, stride);
    inference_hir_blocks.GetDimensions(hir_list, stride);
    inference_token_blocks.GetDimensions(token_list, stride);
    InferenceBlockLayout layout = inference_block_layout(stamps, hir_list, token_list);
    compact_hir_core.GetDimensions(hir_rows, stride);
    uint hir = min(min(gParams.n_hir_nodes, compact_hir_count[0u]), min(hir_rows, layout.hir_blocks * 256u));
    uint tokens = min(min(gParams.n_tokens, token_count[0u]), layout.token_blocks * 256u);
    if (lane == 0u) { inference_hir_blocks[0u] = 0u; inference_token_blocks[0u] = 0u; }
    if (lane < hir) note_row(layout, 0u, lane, compact_hir_core[lane].token_start);
    if (lane < tokens) note_row(layout, 1u, lane, lane);
}

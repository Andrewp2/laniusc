// Lists, at the start of each round's passes, the blocks of 256 HIR rows and
// of 256 tokens that hold an item of a function active in the round, and
// writes the listed passes' dispatch arguments (inference_blocks.slang). One
// lane per listed function, then one per always-active HIR and token block
// (write_inference_list_dispatch_args sized the dispatch). A block is listed once per round: its mark holds
// the last round that listed it.
//
// In round r a function is active when its stamp is r - 1 or later
// (inference_activity.slang). Every function is active outside the rounds
// (round 0, the final pass), in round 1 and in a round after a change without
// an owning function: the passes then visit every row.
#include "../inference_block_layout.slang"

StructuredBuffer<uint> call_inference_round;
StructuredBuffer<uint> call_inference_fn_stamp;
StructuredBuffer<uint> hir_active_dispatch_args;
StructuredBuffer<uint> token_active_dispatch_args;
RWStructuredBuffer<uint> inference_block_tables;
RWStructuredBuffer<uint> inference_hir_blocks;
RWStructuredBuffer<uint> inference_token_blocks;
RWStructuredBuffer<uint> inference_hir_list_args;
RWStructuredBuffer<uint> inference_token_list_args;
// The canonical counters: word 0 is the next record, word 13 the frozen
// bound (canonical_api.slang's CT_COUNT_NEXT_RECORD and CT_COUNT_FROZEN).
globallycoherent RWStructuredBuffer<uint> ct_counts;

void list_block(uint domain, uint block)
{
    uint slot;
    InterlockedAdd(inference_block_tables[INFERENCE_BLOCK_LISTED + domain], 1u, slot);
    if (domain == 0u) inference_hir_blocks[2u + slot] = block;
    else inference_token_blocks[2u + slot] = block;
}

// Lists the blocks of rows [first, end) that this round has not listed yet.
void list_range(uint domain, uint marks, uint first, uint end, uint round)
{
    if (end == 0u) return;
    for (uint block = first / 256u; block <= (end - 1u) / 256u; block++)
    {
        uint old;
        InterlockedMax(inference_block_tables[marks + block], round, old);
        if (old < round) list_block(domain, block);
    }
}

void copy_full_grid()
{
    [unroll]
    for (uint i = 0u; i < 3u; i++)
    {
        inference_hir_list_args[i] = hir_active_dispatch_args[i];
        inference_token_list_args[i] = token_active_dispatch_args[i];
    }
    inference_hir_blocks[0u] = 0u;
    inference_token_blocks[0u] = 0u;
}

void write_listed_args(RWStructuredBuffer<uint> args, RWStructuredBuffer<uint> blocks,
    StructuredBuffer<uint> full, uint listed)
{
    // A list longer than one grid row visits every row instead.
    bool fits = listed <= 65535u;
    args[0u] = fits ? listed : full[0u];
    args[1u] = fits ? 1u : full[1u];
    args[2u] = fits ? 1u : full[2u];
    blocks[0u] = fits ? 1u : 0u;
    blocks[1u] = listed;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID, uint3 ltid: SV_GroupThreadID)
{
    // Every record allocated so far was written by an earlier dispatch, so
    // the passes after this one read those records through L1.
    if (dtid.x == 0u)
    {
        uint records;
        InterlockedAdd(ct_counts[0u], 0u, records);
        ct_counts[13u] = records;
    }
    uint round = call_inference_round[0u];
    if (round <= 1u || call_inference_round[1u] + 1u >= round)
    {
        if (dtid.x == 0u) copy_full_grid();
        return;
    }
    uint stamps; uint hir_list; uint token_list; uint stride;
    call_inference_fn_stamp.GetDimensions(stamps, stride);
    inference_hir_blocks.GetDimensions(hir_list, stride);
    inference_token_blocks.GetDimensions(token_list, stride);
    InferenceBlockLayout layout = inference_block_layout(stamps, hir_list, token_list);
    uint lane = dtid.x;
    uint functions = min(inference_block_tables[INFERENCE_BLOCK_FUNCTIONS], layout.groups);
    uint always_hir = min(inference_block_tables[INFERENCE_BLOCK_ALWAYS], layout.hir_blocks);
    uint always_tokens = min(inference_block_tables[INFERENCE_BLOCK_ALWAYS + 1u], layout.token_blocks);
    if (lane < functions)
    {
        uint group = inference_block_tables[layout.functions + lane];
        if (group < layout.groups && call_inference_fn_stamp[group] + 1u >= round)
        {
            uint word = INFERENCE_BLOCK_HEADER + group * 4u;
            list_range(0u, layout.hir_marks, ~inference_block_tables[word], inference_block_tables[word + 1u], round);
            list_range(1u, layout.token_marks, ~inference_block_tables[word + 2u], inference_block_tables[word + 3u], round);
        }
    }
    else if (lane < functions + always_hir)
        list_block(0u, inference_block_tables[layout.hir_always + lane - functions]);
    else if (lane < functions + always_hir + always_tokens)
        list_block(1u, inference_block_tables[layout.token_always + lane - functions - always_hir]);
    // The last workgroup to finish writes the grids and clears the counts for
    // the next round.
    AllMemoryBarrierWithGroupSync();
    if (ltid.x != 0u) return;
    uint groups = inference_block_tables[INFERENCE_BLOCK_GROUPS];
    uint done;
    InterlockedAdd(inference_block_tables[INFERENCE_BLOCK_DONE], 1u, done);
    if (done + 1u != groups) return;
    DeviceMemoryBarrier();
    uint listed_hir; uint listed_tokens;
    InterlockedAdd(inference_block_tables[INFERENCE_BLOCK_LISTED], 0u, listed_hir);
    InterlockedAdd(inference_block_tables[INFERENCE_BLOCK_LISTED + 1u], 0u, listed_tokens);
    inference_block_tables[INFERENCE_BLOCK_DONE] = 0u;
    inference_block_tables[INFERENCE_BLOCK_LISTED] = 0u;
    inference_block_tables[INFERENCE_BLOCK_LISTED + 1u] = 0u;
    write_listed_args(inference_hir_list_args, inference_hir_blocks, hir_active_dispatch_args, listed_hir);
    write_listed_args(inference_token_list_args, inference_token_blocks, token_active_dispatch_args, listed_tokens);
}

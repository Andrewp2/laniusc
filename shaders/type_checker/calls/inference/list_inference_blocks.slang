// Lists the blocks of HIR rows, tokens, and arguments owned by active functions, and
// writes the listed passes' dispatch arguments (inference_blocks.slang). One
// lane per listed function, then one per always-active block
// (write_inference_list_dispatch_args sized the dispatch). A block is listed once per round: its mark holds
// the last round that listed it.
//
// In round r a function is active when its stamp is r - 1 or later
// (inference_activity.slang). Every function is active outside the rounds
// (round 0, the final pass), in round 1 and in a round after a change without
// an owning function: the passes then visit every row.
#include "../inference_block_layout.slang"

struct ProgramLimits
{
    uint field_groups;
};

ConstantBuffer<ProgramLimits> inference_program_limits;
RWStructuredBuffer<uint> inference_field_program_args;
RWStructuredBuffer<uint> inference_index_program_args;

void write_program_grid(uint hir_tiles)
{
    // Large rounds need more resident lanes to queue the field closure.
    // An empty or small round keeps a single group.
    uint groups = hir_tiles <= 16u ? 1u :
        min((hir_tiles + 1u) / 2u, inference_program_limits.field_groups);
    inference_field_program_args[0u] = groups;
    inference_field_program_args[1u] = 1u;
    inference_field_program_args[2u] = 1u;

    // Indexing visits compact claim rows even in rounds where every HIR row
    // is active. Keep enough lanes to rebuild those indexes in later rounds.
    inference_index_program_args[0u] = hir_tiles <= 16u ? 1u :
        clamp((hir_tiles + 7u) / 8u, 16u, 32u);
    inference_index_program_args[1u] = 1u;
    inference_index_program_args[2u] = 1u;
}

StructuredBuffer<uint> call_inference_round;
StructuredBuffer<uint> call_inference_fn_stamp;
StructuredBuffer<uint> hir_active_dispatch_args;
StructuredBuffer<uint> token_active_dispatch_args;
StructuredBuffer<uint> call_arg_row_count_out;
StructuredBuffer<uint> hir_active_count;
StructuredBuffer<uint> method_token_hir_dispatch_args;
StructuredBuffer<uint> explicit_application_dispatch_args;
RWStructuredBuffer<uint> inference_method_key_args;
RWStructuredBuffer<uint> inference_explicit_args;
RWStructuredBuffer<uint> inference_full_arg_args;
RWStructuredBuffer<uint> inference_arg_blocks;
RWStructuredBuffer<uint> inference_arg_list_args;
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
    else if (domain == 1u) inference_token_blocks[2u + slot] = block;
    else inference_arg_blocks[2u + slot] = block;
}

// Lists the blocks of rows [first, end) that this round has not listed yet.
void list_range(uint domain, uint marks, uint first, uint end, uint round, uint tile)
{
    if (end == 0u) return;
    for (uint block = first / tile; block <= (end - 1u) / tile; block++)
    {
        uint old;
        InterlockedMax(inference_block_tables[marks + block], round, old);
        if (old < round) list_block(domain, block);
    }
}

uint3 full_argument_grid()
{
    uint rows = min(call_arg_row_count_out[0u], hir_active_count[0u]);
    uint groups = max((rows + 255u) / 256u, 1u);
    return uint3(min(groups, 65535u), (groups + 65534u) / 65535u, 1u);
}

void copy_full_grid(uint3 argument_grid)
{
    [unroll]
    for (uint i = 0u; i < 3u; i++)
    {
        inference_hir_list_args[i] = hir_active_dispatch_args[i];
        inference_token_list_args[i] = token_active_dispatch_args[i];
        inference_arg_list_args[i] = argument_grid[i];
        inference_method_key_args[i] = method_token_hir_dispatch_args[i];
        inference_explicit_args[i] = explicit_application_dispatch_args[i];
    }
    inference_hir_blocks[0u] = 0u;
    inference_token_blocks[0u] = 0u;
    inference_arg_blocks[0u] = 0u;
}

uint3 listed_grid(RWStructuredBuffer<uint> blocks, uint3 full, uint listed, uint tiles_per_group)
{
    uint groups = (listed + tiles_per_group - 1u) / tiles_per_group;
    // A list longer than one grid row visits every row instead.
    bool fits = groups <= 65535u;
    blocks[0u] = fits ? 1u : 0u;
    blocks[1u] = listed;
    return fits ? uint3(groups, 1u, 1u) : full;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID, uint3 ltid: SV_GroupThreadID)
{
    // Every record allocated so far was written by an earlier dispatch, so
    // the passes after this one read those records through L1.
    uint lane = dtid.x + dtid.y * 16776960u;
    if (lane == 0u)
    {
        uint records;
        InterlockedAdd(ct_counts[0u], 0u, records);
        ct_counts[13u] = records;
        uint3 grid = full_argument_grid();
        [unroll]
        for (uint i = 0u; i < 3u; i++)
            inference_full_arg_args[i] = grid[i];
    }
    uint round = call_inference_round[0u];
    if (round <= 1u || call_inference_round[1u] + 1u >= round)
    {
        if (lane == 0u)
        {
            copy_full_grid(full_argument_grid());
            write_program_grid(hir_active_dispatch_args[0u] * hir_active_dispatch_args[1u]);
        }
        return;
    }
    uint stamps; uint hir_list; uint token_list; uint arg_list; uint stride;
    call_inference_fn_stamp.GetDimensions(stamps, stride);
    inference_hir_blocks.GetDimensions(hir_list, stride);
    inference_token_blocks.GetDimensions(token_list, stride);
    inference_arg_blocks.GetDimensions(arg_list, stride);
    InferenceBlockLayout layout = inference_block_layout(stamps, uint3(hir_list, token_list, arg_list));
    uint functions = min(inference_block_tables[INFERENCE_BLOCK_FUNCTIONS], layout.groups);

    if (lane < functions)
    {
        uint group = inference_block_tables[layout.functions + lane];
        if (group < layout.groups && call_inference_fn_stamp[group] + 1u >= round)
        {
            uint word = INFERENCE_BLOCK_HEADER + group * (INFERENCE_BLOCK_DOMAINS * 2u);
            [unroll]
            for (uint domain = 0u; domain < INFERENCE_BLOCK_DOMAINS; domain++)
            {
                uint start = word + domain * 2u;
                list_range(domain, layout.marks[domain], ~inference_block_tables[start],
                    inference_block_tables[start + 1u], round, domain == 2u ? INFERENCE_ARGUMENT_TILE : 256u);
            }
        }
    }
    else
    {
        uint index = lane - functions;
        [unroll]
        for (uint domain = 0u; domain < INFERENCE_BLOCK_DOMAINS; domain++)
        {
            uint count = min(inference_block_tables[INFERENCE_BLOCK_ALWAYS + domain], layout.blocks[domain]);
            if (index < count)
                list_block(domain, inference_block_tables[layout.always[domain] + index]);
            index -= count;
        }
    }
    // The last workgroup to finish writes the grids and clears the counts for
    // the next round.
    AllMemoryBarrierWithGroupSync();
    if (ltid.x != 0u) return;
    uint groups = inference_block_tables[INFERENCE_BLOCK_GROUPS];
    uint done;
    InterlockedAdd(inference_block_tables[INFERENCE_BLOCK_DONE], 1u, done);
    if (done + 1u != groups) return;
    DeviceMemoryBarrier();
    uint listed_hir; uint listed_tokens; uint listed_args;
    InterlockedAdd(inference_block_tables[INFERENCE_BLOCK_LISTED], 0u, listed_hir);
    InterlockedAdd(inference_block_tables[INFERENCE_BLOCK_LISTED + 1u], 0u, listed_tokens);
    InterlockedAdd(inference_block_tables[INFERENCE_BLOCK_LISTED + 2u], 0u, listed_args);
    inference_block_tables[INFERENCE_BLOCK_DONE] = 0u;
    inference_block_tables[INFERENCE_BLOCK_LISTED] = 0u;
    inference_block_tables[INFERENCE_BLOCK_LISTED + 1u] = 0u;
    inference_block_tables[INFERENCE_BLOCK_LISTED + 2u] = 0u;
    uint3 full_hir = uint3(hir_active_dispatch_args[0u], hir_active_dispatch_args[1u], 1u);
    uint3 full_tokens = uint3(token_active_dispatch_args[0u], token_active_dispatch_args[1u], 1u);
    // The key producer visits both domains, including when one needs the
    // two-dimensional fallback. Each listed index is bounds checked.
    uint3 hir = listed_grid(inference_hir_blocks, full_hir, listed_hir, 1u);
    uint3 tokens = listed_grid(inference_token_blocks, full_tokens, listed_tokens, 1u);
    uint3 args = listed_grid(inference_arg_blocks, full_argument_grid(), listed_args, 8u);
    write_program_grid(hir.x * hir.y);
    bool method_keys = method_token_hir_dispatch_args[0u] != 0u;
    bool explicit_apps = explicit_application_dispatch_args[0u] != 0u;
    [unroll]
    for (uint i = 0u; i < 3u; i++)
    {
        inference_hir_list_args[i] = hir[i];
        inference_token_list_args[i] = tokens[i];
        inference_arg_list_args[i] = args[i];
        inference_method_key_args[i] = method_keys ? max(hir[i], tokens[i]) : 0u;
        inference_explicit_args[i] = explicit_apps ? hir[i] : 0u;
    }
}

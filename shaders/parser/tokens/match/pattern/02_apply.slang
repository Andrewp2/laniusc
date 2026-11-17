// Apply prefix-scanned match-pattern context rows.
//
// 01_local.slang stored each token's own match-pattern event in
// token_match_pattern_context_event. This pass replaces it, at the same row,
// with the latest event before the token.

import prefix_scan;
import parser.tokens.context.before_block;

struct Params
{
    uint n_tokens;
    uint n_blocks;
    uint scan_step;
    uint match_tree_leaf_base;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> lexer_token_count;
StructuredBuffer<uint> statement_event_block;
RWStructuredBuffer<uint> token_match_pattern_context_event;

groupshared uint match_pattern_prefix_values[256];

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    if (block_idx >= gParams.n_blocks)
        return;

    uint lane = ltid.x;
    uint token_i = block_idx * WG_SIZE + lane;
    uint count = min(lexer_token_count[0], gParams.n_tokens);
    uint event = token_i < count ? token_match_pattern_context_event[token_i] : 0u;
    uint block_before = context_event_before_block(
        statement_event_block, block_idx, lane, WG_SIZE);
    prefix_scan_inclusive<uint, PrefixScanU32Max, 256>(
        lane,
        event,
        match_pattern_prefix_values);

    uint local_before = lane == 0u ? 0u : match_pattern_prefix_values[lane - 1u];
    uint before = max(block_before, local_before);
    if (token_i < gParams.n_tokens)
        token_match_pattern_context_event[token_i] = before;
}

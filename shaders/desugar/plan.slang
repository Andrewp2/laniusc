// One thread: the sizes, indirect dispatches and kernel parameters of the
// next stage of the desugaring, from the counts the stage before it wrote
// (desugar_common.slang). Each mode runs once per build, in order.
import desugar_common;

struct PlanParams
{
    uint mode;
    uint piece_cap;
    uint token_cap; // rows of the per-token buffers
    uint out_cap;   // rows of the spliced token buffers
};

struct LexParams
{
    uint n;
    uint m;
    uint start_state;
    uint skip0;
    uint skip1;
    uint skip2;
    uint skip3;
    uint extent;
};

ConstantBuffer<PlanParams> gPlan;
ConstantBuffer<LexParams> gLex;
RWStructuredBuffer<uint> token_count;
RWStructuredBuffer<uint> parser_feature_flags;
StructuredBuffer<uint> lex_error_offset;
RWStructuredBuffer<uint> sizes;
RWStructuredBuffer<uint> args;
RWStructuredBuffer<uint> blocks;
StructuredBuffer<uint4> scan_a;
StructuredBuffer<uint4> count_scan0;
StructuredBuffer<uint4> count_scan1;
StructuredBuffer<uint> status;
StructuredBuffer<uint4> piece_scan;
StructuredBuffer<uint4> region_scan;
StructuredBuffer<uint4> splice_scan;

static const uint INFO_WORDS = 3u;
static const uint STATE_ROW_WORDS = 8u;
static const uint REC_WORDS = 6u;

void set_groups(uint triple, uint groups)
{
    uint x = min(groups, DESUGAR_MAX_GROUPS_X);
    uint y = groups == 0u ? 0u : (groups + DESUGAR_MAX_GROUPS_X - 1u) / DESUGAR_MAX_GROUPS_X;
    args[triple * 3u] = groups == 0u ? 0u : x;
    args[triple * 3u + 1u] = groups == 0u ? 0u : y;
    args[triple * 3u + 2u] = groups == 0u ? 0u : 1u;
}

// One lane per element, 256 lanes a workgroup.
void set_lanes(uint triple, uint lanes)
{
    set_groups(triple, (lanes + 255u) / 256u);
}

void block(uint index, uint a, uint b, uint c, uint d)
{
    blocks[index * BLOCK_WORDS] = a;
    blocks[index * BLOCK_WORDS + 1u] = b;
    blocks[index * BLOCK_WORDS + 2u] = c;
    blocks[index * BLOCK_WORDS + 3u] = d;
}

// The three dispatches of closures/scan.slang over `count` rows.
void scan(uint first_block, uint triple, uint one_triple, uint count)
{
    uint tiles = (count + DESUGAR_SCAN_TILE_ROWS - 1u) / DESUGAR_SCAN_TILE_ROWS;
    block(first_block, count, 0u, tiles, 0u);
    block(first_block + 1u, count, 1u, tiles, 0u);
    block(first_block + 2u, count, 2u, tiles, 0u);
    set_groups(triple, tiles);
    set_groups(one_triple, count == 0u ? 0u : 1u);
}

uint sum4(uint4 v)
{
    return v.x + v.y + v.z + v.w;
}

void raise_flag(uint flag)
{
    parser_feature_flags[0] = parser_feature_flags[0] | flag;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    uint mode = gPlan.mode;
    if (mode == PLAN_TOKENS)
    {
        for (uint i = 0u; i < SIZE_WORDS; i += 1u)
            sizes[i] = 0u;
        for (uint i = 0u; i < ARG_TRIPLES * 3u; i += 1u)
            args[i] = 0u;
        for (uint i = 0u; i < BLOCKS; i += 1u)
            block(i, 0u, 0u, 0u, 0u);
        // Four bytes past the padded source (desugar.rs).
        uint base = ((gLex.n + 3u) & ~3u) + 4u;
        uint cap = gLex.extent > base ? gLex.extent - base : 0u;
        sizes[S_REGION_BASE] = base;
        sizes[S_REGION_CAP] = cap;
        sizes[S_PIECE_CAP] = gPlan.piece_cap;
        bool machines = (parser_feature_flags[0] & FEATURE_MACHINES) != 0u && lex_error_offset[0] == 0u;
        if (!machines)
            return;
        uint tokens = token_count[0];
        // Without a region the run cannot write its text; the host runs the
        // build again with one.
        if (cap == 0u || tokens > gPlan.token_cap)
        {
            sizes[S_NEED_TOKENS] = tokens;
            raise_flag(DESUGAR_REGION_OVERFLOW);
            return;
        }
        sizes[S_TOKENS] = tokens;
        block(P_TOKENS, tokens, 0u, 0u, 0u);
        block(P_CLEAR_RECORDS, tokens * REC_WORDS, 0u, 0u, 0u);
        set_lanes(A_TOKENS, tokens);
        set_lanes(A_RECORD_WORDS, tokens * REC_WORDS);
        scan(P_SCAN_TOKENS_0, A_TOKEN_SCAN, A_TOKEN_SCAN_ONE, tokens);
        return;
    }
    if (mode == PLAN_MACHINES)
    {
        uint tokens = sizes[S_TOKENS];
        if (tokens == 0u)
            return;
        uint4 last = scan_a[tokens - 1u];
        uint machine_count = last.x;
        uint state_count = last.y;
        uint transition_count = last.z;
        // A transition outside a machine is an error the rules report.
        uint live = machine_count > 0u || transition_count > 0u ? tokens : 0u;
        if (live == 0u)
            return;
        // The machine and state rows hold a quarter of the token rows.
        uint machine_cap = gPlan.token_cap / 4u + 1u;
        if (machine_count > machine_cap || state_count > machine_cap)
        {
            sizes[S_NEED_TOKENS] = max(machine_count, state_count) * 4u;
            raise_flag(DESUGAR_REGION_OVERFLOW);
            return;
        }
        sizes[S_MACHINES] = machine_count;
        sizes[S_STATES] = state_count;
        sizes[S_TRANSITIONS] = transition_count;
        sizes[S_LIVE] = live;
        block(P_LIVE, live, 0u, 0u, 0u);
        block(P_LISTS_A, live, 0u, 0u, 0u);
        block(P_LISTS_B, live, 1u, 0u, 0u);
        block(P_CLEAR_INFO, max(machine_count, 1u) * INFO_WORDS, 0u, 0u, 0u);
        block(P_CLEAR_STATES, max(state_count, 1u) * STATE_ROW_WORDS, 0u, 0u, 0u);
        block(P_RESOLVE, live, machine_count, DESUGAR_NO_ERROR, DESUGAR_NO_ERROR);
        block(P_CHECK, live, 0u, DESUGAR_NO_ERROR, DESUGAR_NO_ERROR);
        block(P_STATES, state_count, 0u, 0u, 0u);
        block(P_STATE_CHECK, state_count, 0u, DESUGAR_NO_ERROR, DESUGAR_NO_ERROR);
        block(P_COUNT, live, 0u, 0u, 0u);
        set_lanes(A_LIVE, live);
        set_lanes(A_INFO_WORDS, max(machine_count, 1u) * INFO_WORDS);
        set_lanes(A_STATES, state_count);
        set_lanes(A_STATE_WORDS, max(state_count, 1u) * STATE_ROW_WORDS);
        scan(P_SCAN_LIVE_0, A_LIVE_SCAN, A_LIVE_SCAN_ONE, live);
        return;
    }
    if (mode == PLAN_PIECES)
    {
        uint live = sizes[S_LIVE];
        if (live == 0u)
            return;
        for (uint w = 0u; w < DESUGAR_STATUS_WORDS; w += 1u)
        {
            if (status[w] != DESUGAR_NO_ERROR)
            {
                raise_flag(DESUGAR_RULE_ERROR);
                return;
            }
        }
        uint pieces = sum4(count_scan0[live - 1u]) + sum4(count_scan1[live - 1u]);
        if (pieces > sizes[S_PIECE_CAP])
        {
            sizes[S_NEED_PIECES] = pieces;
            raise_flag(DESUGAR_REGION_OVERFLOW);
            return;
        }
        if (pieces == 0u)
            return;
        sizes[S_PIECES] = pieces;
        block(P_WRITE, live, 1u, 0u, 0u);
        set_lanes(A_WRITE, live);
        scan(P_SCAN_PIECES_0, A_PIECE_SCAN, A_PIECE_SCAN_ONE, pieces);
        return;
    }
    if (mode == PLAN_REGION)
    {
        uint pieces = sizes[S_PIECES];
        if (pieces == 0u)
            return;
        uint region = piece_scan[pieces - 1u].x;
        if (region > sizes[S_REGION_CAP])
        {
            sizes[S_NEED_REGION] = region;
            raise_flag(DESUGAR_REGION_OVERFLOW);
            return;
        }
        if (region == 0u)
            return;
        sizes[S_REGION] = region;
        block(P_EMIT, region, pieces, sizes[S_REGION_BASE], sizes[S_TOKENS]);
        set_lanes(A_REGION_WORDS, (region + 3u) / 4u);
        set_lanes(A_REGION_BYTES, region);
        scan(P_SCAN_REGION_0, A_REGION_SCAN, A_REGION_SCAN_ONE, region);
        return;
    }
    if (mode == PLAN_SPLICE)
    {
        uint region = sizes[S_REGION];
        if (region == 0u)
            return;
        uint generated = region_scan[region - 1u].x;
        uint tokens = sizes[S_TOKENS];
        sizes[S_GENERATED] = generated;
        sizes[S_SPLICED] = tokens;
        set_lanes(A_GENERATED, generated);
        set_lanes(A_SPLICE, tokens);
        scan(P_SCAN_SPLICE_0, A_SPLICE_SCAN, A_SPLICE_SCAN_ONE, tokens);
        return;
    }
    if (mode == PLAN_FINISH)
    {
        uint tokens = sizes[S_SPLICED];
        if (tokens == 0u)
            return;
        uint out = splice_scan[tokens - 1u].x;
        if (out > gPlan.out_cap)
        {
            sizes[S_NEED_OUT] = out;
            raise_flag(DESUGAR_REGION_OVERFLOW);
            sizes[S_SPLICED] = 0u;
            set_lanes(A_SPLICE, 0u);
            set_lanes(A_GENERATED, 0u);
            return;
        }
        sizes[S_OUT] = out;
        set_lanes(A_OUT, out);
        token_count[0] = out;
    }
}

// One thread: the sizes, indirect dispatches and kernel parameters of the
// next stage of one round of the desugaring, from the counts the stage
// before it wrote (desugar_common.slang). The host records each mode once
// per round, in order, with the round's slices of `sizes`, `args` and
// `blocks`.
import generated_token_ids;
import desugar_common;

struct PlanParams
{
    uint mode;
    uint feature;   // the feature bit of the round
    uint first;     // 1 for the first round the host recorded
    uint token_cap; // rows of the per-token buffers
    uint piece_cap; // rows of the piece buffers
    uint out_cap;   // rows of the spliced token buffers
    uint slot;      // the round's slice of `sizes`
    uint previous;  // the slice of the round before it
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
StructuredBuffer<uint> source_file_count;
// The sizes of every round: the round's own slice at `gPlan.slot`, the
// round before it at `gPlan.previous`.
RWStructuredBuffer<uint> sizes;
RWStructuredBuffer<uint> args;
RWStructuredBuffer<uint> blocks;
StructuredBuffer<uint> status;
// Prefix sums of the round's feature, by mode.
StructuredBuffer<uint4> feat_a;
StructuredBuffer<uint4> feat_b;
StructuredBuffer<uint4> feat_c;
StructuredBuffer<uint4> fpiece_scan;
StructuredBuffer<uint4> piece_scan;
StructuredBuffer<uint4> region_scan;
StructuredBuffer<uint4> splice_scan;

// Modes shared by every round.
static const uint PLAN_START = 0u;
static const uint PLAN_PLACE = 1u;
static const uint PLAN_REGION = 2u;
static const uint PLAN_SPLICE = 3u;
static const uint PLAN_FINISH = 4u;
// Machines.
static const uint PLAN_M_MACHINES = 8u;
static const uint PLAN_M_PIECES = 9u;
// Generators.
static const uint PLAN_G_PIECES = 10u;
// Closures.
static const uint PLAN_C_PIECES = 11u;

// Machine layout: dispatches and parameter blocks from A_FEATURE and
// P_FEATURE (desugar.rs mirrors them).
static const uint MA_TOKENS = 16u;
static const uint MA_TOKEN_SCAN = 17u;
static const uint MA_TOKEN_SCAN_ONE = 18u;
static const uint MA_RECORD_WORDS = 19u;
static const uint MA_LIVE = 20u;
static const uint MA_LIVE_SCAN = 21u;
static const uint MA_LIVE_SCAN_ONE = 22u;
static const uint MA_INFO_WORDS = 23u;
static const uint MA_STATES = 24u;
static const uint MA_STATE_WORDS = 25u;
static const uint MA_WRITE = 26u;
static const uint MP_TOKENS = 16u;
static const uint MP_CLEAR_RECORDS = 17u;
static const uint MP_SCAN_TOKENS = 18u;
static const uint MP_LIVE = 21u;
static const uint MP_LISTS_A = 22u;
static const uint MP_LISTS_B = 23u;
static const uint MP_SCAN_LIVE = 24u;
static const uint MP_CLEAR_INFO = 27u;
static const uint MP_CLEAR_STATES = 28u;
static const uint MP_RESOLVE = 29u;
static const uint MP_CHECK = 30u;
static const uint MP_STATES = 31u;
static const uint MP_STATE_CHECK = 32u;
static const uint MP_COUNT = 33u;
static const uint MP_WRITE = 34u;
// Generator layout (desugar/generators.rs mirrors it).
static const uint GA_TOKENS = 16u;
static const uint GA_RECORD_WORDS = 17u;
static const uint GA_SCAN = 18u;
static const uint GA_SCAN_ONE = 19u;
static const uint GA_FILES = 20u;
static const uint GA_PAIRS = 21u;
static const uint GA_WRITE = 22u;
static const uint GP_TOKENS = 16u;
static const uint GP_CLEAR_RECORDS = 17u;
static const uint GP_SCAN = 18u;
static const uint GP_CHECK = 21u;
static const uint GP_FILES = 22u;
static const uint GP_SCOPE = 23u;
static const uint GP_WRITE = 24u;
// Closure layout (desugar/closures.rs mirrors it).
static const uint CA_TOKENS = 16u;
static const uint CA_SCAN = 17u;
static const uint CA_SCAN_ONE = 18u;
static const uint CA_TREE = 19u; // one per level of the depth heap
static const uint CA_WRITE = 22u;
static const uint CP_TOKENS = 16u;
static const uint CP_SCAN = 17u;
static const uint CP_TREE = 20u; // one per level of the depth heap
static const uint CP_WRITE = 23u;
static const uint C_TREE_STEPS = 3u;
static const uint C_STATUS_WORDS = 1u;
static const uint G_REC_WORDS = 7u;
static const uint G_STATUS_WORDS = 1u;
static const uint M_STATUS_WORDS = 4u;
static const uint M_INFO_WORDS = 3u;
static const uint M_STATE_ROW_WORDS = 8u;
static const uint M_REC_WORDS = 6u;

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

bool status_failed(uint words)
{
    for (uint w = 0u; w < words; w += 1u)
    {
        if (status[w] != DESUGAR_NO_ERROR)
            return true;
    }
    return false;
}

// The run asks for more room: the host grows `need` and runs it again.
void overflow(uint need_word, uint need)
{
    sizes[gPlan.slot * SIZE_WORDS + need_word] = need;
    raise_flag(DESUGAR_REGION_OVERFLOW);
}

// The round's pieces are written: the expansion of their token ranges.
void expand(uint fpieces)
{
    if (fpieces == 0u)
        return;
    if (fpieces > gPlan.piece_cap)
    {
        overflow(S_NEED_PIECES, fpieces);
        return;
    }
    sizes[gPlan.slot * SIZE_WORDS + S_FPIECES] = fpieces;
    scan(P_EXPAND_SCAN_0, A_EXPAND_SCAN, A_EXPAND_SCAN_ONE, fpieces);
}

// Common start of a round: its region follows the region of the round
// before it. False when the round has nothing to do.
bool start_round()
{
    for (uint i = 0u; i < SIZE_WORDS; i += 1u)
        sizes[gPlan.slot * SIZE_WORDS + i] = 0u;
    for (uint i = 0u; i < ARG_TRIPLES * 3u; i += 1u)
        args[i] = 0u;
    for (uint i = 0u; i < BLOCKS; i += 1u)
        block(i, 0u, 0u, 0u, 0u);
    // Four bytes past the padded source (desugar.rs).
    uint first_base = ((gLex.n + 3u) & ~3u) + 4u;
    uint base = first_base;
    if (gPlan.first == 0u)
        base = (sizes[gPlan.previous * SIZE_WORDS + S_REGION_BASE] + sizes[gPlan.previous * SIZE_WORDS + S_REGION] + 3u) & ~3u;
    uint cap = gLex.extent > base ? gLex.extent - base : 0u;
    sizes[gPlan.slot * SIZE_WORDS + S_REGION_BASE] = base;
    sizes[gPlan.slot * SIZE_WORDS + S_REGION_CAP] = cap;
    sizes[gPlan.slot * SIZE_WORDS + S_ANCHOR_BASE] = base - first_base;
    uint flags = parser_feature_flags[0];
    if ((flags & gPlan.feature) == 0u || (flags & DESUGAR_STOPS) != 0u || lex_error_offset[0] != 0u)
        return false;
    uint tokens = token_count[0];
    // Without a region the run cannot write its text; the host runs the
    // build again with one. The splice has a row past the last token.
    if (cap == 0u || tokens + 1u > gPlan.token_cap)
    {
        overflow(S_NEED_TOKENS, tokens + 1u);
        return false;
    }
    sizes[gPlan.slot * SIZE_WORDS + S_TOKENS] = tokens;
    return true;
}

void start_machines()
{
    uint tokens = sizes[gPlan.slot * SIZE_WORDS + S_TOKENS];
    block(MP_TOKENS, tokens, 0u, 0u, 0u);
    block(MP_CLEAR_RECORDS, tokens * M_REC_WORDS, 0u, 0u, 0u);
    set_lanes(MA_TOKENS, tokens);
    set_lanes(MA_RECORD_WORDS, tokens * M_REC_WORDS);
    scan(MP_SCAN_TOKENS, MA_TOKEN_SCAN, MA_TOKEN_SCAN_ONE, tokens);
}

// The leaves of the minimum heap over the depth of each block of 256
// tokens: a power of two that covers the blocks of `token_cap` tokens
// (desugar/closures.rs computes the same).
uint closure_leaf_base()
{
    uint blocks = max((gPlan.token_cap + 255u) / 256u, 1u);
    uint leaves = 1u;
    while (leaves < blocks)
        leaves <<= 1u;
    return leaves;
}

// Every per-token kernel of a closure round reads all the tokens: the round
// runs only when a closure starts in the stream. The heap over the depths is
// built in the steps of crate::gpu::scan::heap_build_levels for the leaves
// of the token rows; each step reads the blocks of the round's tokens.
void start_closures()
{
    uint tokens = sizes[gPlan.slot * SIZE_WORDS + S_TOKENS];
    sizes[gPlan.slot * SIZE_WORDS + S_LIVE] = tokens;
    block(CP_TOKENS, tokens, 0u, 0u, 0u);
    set_lanes(CA_TOKENS, tokens);
    scan(CP_SCAN, CA_SCAN, CA_SCAN_ONE, tokens);
    uint n_blocks = (tokens + 255u) / 256u;
    uint leaf_base = closure_leaf_base();
    uint level_start = leaf_base;
    uint mode = 0u;
    for (uint step = 0u; step < C_TREE_STEPS; step += 1u)
    {
        uint levels = min(firstbitlow(level_start), 8u);
        uint at = (CP_TREE + step) * BLOCK_WORDS;
        blocks[at] = n_blocks;
        blocks[at + 1u] = leaf_base;
        blocks[at + 2u] = level_start;
        blocks[at + 3u] = level_start;
        blocks[at + 4u] = mode;
        blocks[at + 5u] = levels;
        set_lanes(CA_TREE + step, level_start);
        level_start >>= levels;
        mode = 1u;
        if (level_start <= 1u)
            break;
    }
}

// feat_a: the inclusive prefix sums of depth and closure starts. feat_b: of
// the piece counts.
void plan_closure_pieces()
{
    uint live = sizes[gPlan.slot * SIZE_WORDS + S_LIVE];
    if (live == 0u)
        return;
    if (status_failed(C_STATUS_WORDS))
    {
        raise_flag(DESUGAR_RULE_ERROR);
        return;
    }
    uint closures = feat_a[live - 1u].y;
    uint fpieces = feat_b[live - 1u].x;
    if (closures == 0u || fpieces == 0u)
        return;
    if (fpieces > gPlan.piece_cap)
    {
        overflow(S_NEED_PIECES, fpieces);
        return;
    }
    sizes[gPlan.slot * SIZE_WORDS + S_F0] = closures;
    block(CP_WRITE, live, 1u, fpieces, 0u);
    set_lanes(CA_WRITE, fpieces);
    expand(fpieces);
}

// Every per-token kernel of a generator round reads all the tokens: the
// round runs only when the stream has a `gen` or `yield` token.
void start_generators()
{
    uint tokens = sizes[gPlan.slot * SIZE_WORDS + S_TOKENS];
    uint files = source_file_count[0];
    sizes[gPlan.slot * SIZE_WORDS + S_LIVE] = tokens;
    block(GP_TOKENS, tokens, 0u, 0u, 0u);
    block(GP_CLEAR_RECORDS, tokens * G_REC_WORDS, 0u, 0u, 0u);
    block(GP_CHECK, tokens, 0u, DESUGAR_NO_ERROR, DESUGAR_NO_ERROR);
    block(GP_FILES, files, 0u, 0u, 0u);
    set_lanes(GA_TOKENS, tokens);
    set_lanes(GA_RECORD_WORDS, tokens * G_REC_WORDS);
    set_lanes(GA_FILES, files);
    scan(GP_SCAN, GA_SCAN, GA_SCAN_ONE, tokens);
}

// feat_a: the inclusive prefix sums of generators and yields. feat_b: of
// the slots of yields and the pairs of locals and yields. feat_c: of the
// piece counts.
void plan_generator_pieces()
{
    uint live = sizes[gPlan.slot * SIZE_WORDS + S_LIVE];
    if (live == 0u)
        return;
    if (status_failed(G_STATUS_WORDS))
    {
        raise_flag(DESUGAR_RULE_ERROR);
        return;
    }
    uint gens = feat_a[live - 1u].x;
    uint slots = feat_b[live - 1u].x;
    uint pairs = feat_b[live - 1u].y;
    uint fpieces = feat_c[live - 1u].x;
    if (gens == 0u || fpieces == 0u)
        return;
    // The slots of every yield are rows of the scope list.
    if (slots > gPlan.token_cap)
    {
        overflow(S_NEED_TOKENS, slots);
        return;
    }
    if (fpieces > gPlan.piece_cap)
    {
        overflow(S_NEED_PIECES, fpieces);
        return;
    }
    sizes[gPlan.slot * SIZE_WORDS + S_F0] = gens;
    sizes[gPlan.slot * SIZE_WORDS + S_F1] = pairs;
    block(GP_SCOPE, live, pairs, 0u, 0u);
    block(GP_WRITE, live, 1u, fpieces, gens);
    set_lanes(GA_PAIRS, pairs);
    set_lanes(GA_WRITE, fpieces);
    expand(fpieces);
}

// feat_a: the inclusive prefix sums of machines, states, transitions and
// bracket depth.
void plan_machines()
{
    uint tokens = sizes[gPlan.slot * SIZE_WORDS + S_TOKENS];
    if (tokens == 0u)
        return;
    uint4 last = feat_a[tokens - 1u];
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
        overflow(S_NEED_TOKENS, max(machine_count, state_count) * 4u);
        return;
    }
    sizes[gPlan.slot * SIZE_WORDS + S_F0] = machine_count;
    sizes[gPlan.slot * SIZE_WORDS + S_F1] = state_count;
    sizes[gPlan.slot * SIZE_WORDS + S_F2] = transition_count;
    sizes[gPlan.slot * SIZE_WORDS + S_LIVE] = live;
    block(MP_LIVE, live, 0u, 0u, 0u);
    block(MP_LISTS_A, live, 0u, 0u, 0u);
    block(MP_LISTS_B, live, 1u, 0u, 0u);
    block(MP_CLEAR_INFO, max(machine_count, 1u) * M_INFO_WORDS, 0u, 0u, 0u);
    block(MP_CLEAR_STATES, max(state_count, 1u) * M_STATE_ROW_WORDS, 0u, 0u, 0u);
    block(MP_RESOLVE, live, machine_count, DESUGAR_NO_ERROR, DESUGAR_NO_ERROR);
    block(MP_CHECK, live, 0u, DESUGAR_NO_ERROR, DESUGAR_NO_ERROR);
    block(MP_STATES, state_count, 0u, 0u, 0u);
    block(MP_STATE_CHECK, state_count, 0u, DESUGAR_NO_ERROR, DESUGAR_NO_ERROR);
    block(MP_COUNT, live, 0u, 0u, 0u);
    set_lanes(MA_LIVE, live);
    set_lanes(MA_INFO_WORDS, max(machine_count, 1u) * M_INFO_WORDS);
    set_lanes(MA_STATES, state_count);
    set_lanes(MA_STATE_WORDS, max(state_count, 1u) * M_STATE_ROW_WORDS);
    scan(MP_SCAN_LIVE, MA_LIVE_SCAN, MA_LIVE_SCAN_ONE, live);
}

// feat_b and feat_c: the inclusive prefix sums of the piece counts.
void plan_machine_pieces()
{
    uint live = sizes[gPlan.slot * SIZE_WORDS + S_LIVE];
    if (live == 0u)
        return;
    if (status_failed(M_STATUS_WORDS))
    {
        raise_flag(DESUGAR_RULE_ERROR);
        return;
    }
    uint fpieces = sum4(feat_b[live - 1u]) + sum4(feat_c[live - 1u]);
    block(MP_WRITE, live, 1u, 0u, 0u);
    set_lanes(MA_WRITE, fpieces == 0u || fpieces > gPlan.piece_cap ? 0u : live);
    expand(fpieces);
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    uint mode = gPlan.mode;
    if (mode == PLAN_START)
    {
        if (!start_round())
            return;
        if (gPlan.feature == FEATURE_MACHINES)
            start_machines();
        else if (gPlan.feature == FEATURE_CLOSURES)
            start_closures();
        else if (gPlan.feature == FEATURE_GENERATORS)
            start_generators();
        return;
    }
    if (mode == PLAN_C_PIECES)
    {
        plan_closure_pieces();
        return;
    }
    if (mode == PLAN_G_PIECES)
    {
        plan_generator_pieces();
        return;
    }
    if (mode == PLAN_M_MACHINES)
    {
        plan_machines();
        return;
    }
    if (mode == PLAN_M_PIECES)
    {
        plan_machine_pieces();
        return;
    }
    if (mode == PLAN_PLACE)
    {
        uint fpieces = sizes[gPlan.slot * SIZE_WORDS + S_FPIECES];
        if (fpieces == 0u)
            return;
        uint pieces = fpiece_scan[fpieces - 1u].x;
        if (pieces > gPlan.piece_cap)
        {
            overflow(S_NEED_PIECES, pieces);
            return;
        }
        if (pieces == 0u)
            return;
        sizes[gPlan.slot * SIZE_WORDS + S_PIECES] = pieces;
        set_lanes(A_PIECES, pieces);
        scan(P_PIECE_SCAN_0, A_PIECE_SCAN, A_PIECE_SCAN_ONE, pieces);
        return;
    }
    if (mode == PLAN_REGION)
    {
        uint pieces = sizes[gPlan.slot * SIZE_WORDS + S_PIECES];
        if (pieces == 0u)
            return;
        uint region = piece_scan[pieces - 1u].x;
        if (region > sizes[gPlan.slot * SIZE_WORDS + S_REGION_CAP])
        {
            overflow(S_NEED_REGION, sizes[gPlan.slot * SIZE_WORDS + S_ANCHOR_BASE] + region);
            return;
        }
        if (region == 0u)
            return;
        sizes[gPlan.slot * SIZE_WORDS + S_REGION] = region;
        set_lanes(A_REGION_WORDS, (region + 3u) / 4u);
        set_lanes(A_REGION_BYTES, region);
        scan(P_REGION_SCAN_0, A_REGION_SCAN, A_REGION_SCAN_ONE, region);
        return;
    }
    if (mode == PLAN_SPLICE)
    {
        uint region = sizes[gPlan.slot * SIZE_WORDS + S_REGION];
        if (region == 0u)
            return;
        uint generated = region_scan[region - 1u].x;
        uint tokens = sizes[gPlan.slot * SIZE_WORDS + S_TOKENS];
        sizes[gPlan.slot * SIZE_WORDS + S_GENERATED] = generated;
        sizes[gPlan.slot * SIZE_WORDS + S_SPLICED] = tokens;
        set_lanes(A_GENERATED, generated);
        set_lanes(A_SPLICE, tokens + 1u);
        set_lanes(A_KEPT, tokens);
        scan(P_SPLICE_SCAN_0, A_SPLICE_SCAN, A_SPLICE_SCAN_ONE, tokens + 1u);
        return;
    }
    if (mode == PLAN_FINISH)
    {
        uint tokens = sizes[gPlan.slot * SIZE_WORDS + S_SPLICED];
        if (sizes[gPlan.slot * SIZE_WORDS + S_GENERATED] == 0u)
            return;
        uint4 through = splice_scan[tokens];
        uint out = through.x + through.y;
        if (out > gPlan.out_cap)
        {
            overflow(S_NEED_OUT, out);
            sizes[gPlan.slot * SIZE_WORDS + S_SPLICED] = 0u;
            set_lanes(A_KEPT, 0u);
            set_lanes(A_GENERATED, 0u);
            return;
        }
        sizes[gPlan.slot * SIZE_WORDS + S_OUT] = out;
        set_lanes(A_OUT, out);
        token_count[0] = out;
    }
}

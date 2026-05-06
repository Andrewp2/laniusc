// LL(1) seeded block-local production summaries.
//
// Each workgroup starts from one precomputed parser stack seed. The LL(1)
// decisions remain sequential, but the wave follows them uniformly and
// partitions fixed-width stack/status/output writes across lanes.

struct Params
{
    uint n_tokens;
    uint n_kinds;
    uint n_nonterminals;
    uint n_productions;
    uint start_nonterminal;
    uint first_input;
    uint input_end;
    uint n_blocks;
    uint block_size;
    uint stack_capacity;
    uint emit_stride;
    uint max_steps;
    uint fill_production;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_kinds;
StructuredBuffer<uint> ll1_predict;
StructuredBuffer<uint> prod_rhs_off;
StructuredBuffer<uint> prod_rhs_len;
StructuredBuffer<uint> prod_rhs;
StructuredBuffer<uint> block_seed_len;

RWStructuredBuffer<uint> block_seed_stack;
RWStructuredBuffer<uint> seeded_status;
RWStructuredBuffer<uint> seeded_emit;
RWStructuredBuffer<uint> seeded_emit_pos;

static const uint INVALID = 0xFFFFFFFFu;

static const uint STATUS_DISABLED = 0u;
static const uint STATUS_BOUNDARY = 1u;
static const uint STATUS_ACCEPTED = 2u;
static const uint STATUS_TRAILING = 3u;
static const uint STATUS_ERROR = 4u;

static const uint ERR_NONE = 0u;
static const uint ERR_TERMINAL_MISMATCH = 1u;
static const uint ERR_NO_PREDICTION = 2u;
static const uint ERR_STACK_OVERFLOW = 3u;
static const uint ERR_TRAILING_INPUT = 4u;
static const uint ERR_BAD_SYMBOL = 5u;
static const uint ERR_STEP_LIMIT = 6u;

static const uint STATUS_WORDS = 10u;
static const uint LOCAL_STACK_CAP = 2048u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint token_at(uint pos)
{
    return pos < gParams.input_end ? token_kinds[pos] : 0u;
}

void fill_emit(uint block_idx, uint fill_prod, uint lane)
{
    uint base = block_idx * gParams.emit_stride;
    [loop]
    for (uint i = lane; i < gParams.emit_stride; i += WG_SIZE)
    {
        seeded_emit[base + i] = fill_prod;
        seeded_emit_pos[base + i] = INVALID;
    }
}

uint output_pos(uint pos)
{
    return pos >= gParams.first_input ? pos - gParams.first_input : 0u;
}

void write_status(
    uint block_idx,
    uint status,
    uint begin,
    uint end,
    uint pos,
    uint steps,
    uint emit_len,
    uint stack_depth,
    uint error_code,
    uint detail,
    uint first_production,
    uint lane)
{
    uint base = block_idx * STATUS_WORDS;
    if (lane == 0u)
        seeded_status[base + 0u] = status;
    if (lane == 1u)
        seeded_status[base + 1u] = begin;
    if (lane == 2u)
        seeded_status[base + 2u] = end;
    if (lane == 3u)
        seeded_status[base + 3u] = pos;
    if (lane == 4u)
        seeded_status[base + 4u] = steps;
    if (lane == 5u)
        seeded_status[base + 5u] = emit_len;
    if (lane == 6u)
        seeded_status[base + 6u] = stack_depth;
    if (lane == 7u)
        seeded_status[base + 7u] = error_code;
    if (lane == 8u)
        seeded_status[base + 8u] = detail;
    if (lane == 9u)
        seeded_status[base + 9u] = first_production;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint lane = ltid.x;
    if (block_idx >= gParams.n_blocks)
        return;

    uint fill_prod = (gParams.fill_production < gParams.n_productions) ? gParams.fill_production : 0u;
    fill_emit(block_idx, fill_prod, lane);
    GroupMemoryBarrierWithGroupSync();

    uint begin = gParams.first_input + block_idx * gParams.block_size;
    bool has_next_seed = block_idx + 1u < gParams.n_blocks && block_seed_len[block_idx + 1u] != INVALID;
    uint end = min(gParams.input_end, begin + gParams.block_size);

    if (gParams.n_nonterminals == 0u || gParams.n_productions == 0u || gParams.n_kinds == 0u)
    {
        write_status(block_idx, STATUS_DISABLED, begin, end, begin, 0u, 0u, 0u, ERR_NONE, 0u, INVALID, lane);
        return;
    }

    uint stack_limit = min(gParams.stack_capacity, LOCAL_STACK_CAP);
    uint seed_len = block_seed_len[block_idx];
    if (seed_len == INVALID)
    {
        write_status(block_idx, STATUS_DISABLED, begin, end, begin, 0u, 0u, 0u, ERR_NONE, 0u, INVALID, lane);
        return;
    }
    if (seed_len > stack_limit)
    {
        write_status(block_idx, STATUS_ERROR, begin, end, begin, 0u, 0u, 0u, ERR_STACK_OVERFLOW, seed_len, INVALID, lane);
        return;
    }

    uint stack_base = block_idx * gParams.stack_capacity;
    uint pos = begin;
    uint top = seed_len;
    uint steps = 0u;
    uint emit_len = 0u;
    uint first_prod = INVALID;
    uint emit_base = block_idx * gParams.emit_stride;

    [loop]
    while (top > 0u && steps < gParams.max_steps)
    {
        if (has_next_seed && pos >= end)
        {
            write_status(block_idx, STATUS_BOUNDARY, begin, end, pos, steps, emit_len, top, ERR_NONE, 0u, first_prod, lane);
            return;
        }

        steps++;
        top--;
        uint sym = block_seed_stack[stack_base + top];
        uint lookahead = token_at(pos);

        if (sym < gParams.n_kinds)
        {
            if (sym != lookahead)
            {
                write_status(block_idx, STATUS_ERROR, begin, end, pos, steps, emit_len, top, ERR_TERMINAL_MISMATCH, sym, first_prod, lane);
                return;
            }
            pos++;
            continue;
        }

        uint nt = sym - gParams.n_kinds;
        if (nt >= gParams.n_nonterminals || lookahead >= gParams.n_kinds)
        {
            write_status(block_idx, STATUS_ERROR, begin, end, pos, steps, emit_len, top, ERR_BAD_SYMBOL, sym, first_prod, lane);
            return;
        }

        uint pred_idx = nt * gParams.n_kinds + lookahead;
        uint prod = ll1_predict[pred_idx];
        if (prod == INVALID || prod >= gParams.n_productions)
        {
            write_status(block_idx, STATUS_ERROR, begin, end, pos, steps, emit_len, top, ERR_NO_PREDICTION, nt, first_prod, lane);
            return;
        }

        if (emit_len >= gParams.emit_stride)
        {
            write_status(block_idx, STATUS_ERROR, begin, end, pos, steps, emit_len, top, ERR_STACK_OVERFLOW, prod, first_prod, lane);
            return;
        }
        if (first_prod == INVALID)
            first_prod = prod;
        if (lane == 0u)
        {
            seeded_emit[emit_base + emit_len] = prod;
            seeded_emit_pos[emit_base + emit_len] = output_pos(pos);
        }
        emit_len++;

        uint rhs_off = prod_rhs_off[prod];
        uint rhs_len = prod_rhs_len[prod];
        if (top + rhs_len > stack_limit)
        {
            write_status(block_idx, STATUS_ERROR, begin, end, pos, steps, emit_len, top, ERR_STACK_OVERFLOW, prod, first_prod, lane);
            return;
        }

        [loop]
        for (uint i = lane; i < rhs_len; i += WG_SIZE)
        {
            block_seed_stack[stack_base + top + i] = prod_rhs[rhs_off + rhs_len - 1u - i];
        }
        GroupMemoryBarrierWithGroupSync();
        top += rhs_len;
    }

    if (top > 0u)
    {
        write_status(block_idx, STATUS_ERROR, begin, end, pos, steps, emit_len, top, ERR_STEP_LIMIT, top, first_prod, lane);
        return;
    }

    if (has_next_seed && pos != end)
    {
        uint code = (pos < end) ? ERR_TRAILING_INPUT : ERR_NONE;
        write_status(block_idx, STATUS_TRAILING, begin, end, pos, steps, emit_len, 0u, code, token_at(pos), first_prod, lane);
        return;
    }

    if (!has_next_seed && token_at(pos) != 0u)
    {
        write_status(block_idx, STATUS_TRAILING, begin, pos, pos, steps, emit_len, 0u, ERR_TRAILING_INPUT, token_at(pos), first_prod, lane);
        return;
    }

    uint accepted_end = has_next_seed ? end : pos;
    write_status(block_idx, STATUS_ACCEPTED, begin, accepted_end, pos, steps, emit_len, 0u, ERR_NONE, 0u, first_prod, lane);
}

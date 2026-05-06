// LL(1) block seed planning.
//
// Each workgroup computes the parser stack seed for one token block by
// replaying the LL(1) stream up to that block boundary. The replay is still
// transitional, but the wave follows it uniformly and partitions stack writes
// across lanes.

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
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> ll1_predict;
StructuredBuffer<uint> prod_rhs_off;
StructuredBuffer<uint> prod_rhs_len;
StructuredBuffer<uint> prod_rhs;

RWStructuredBuffer<uint> block_seed_len;
RWStructuredBuffer<uint> block_seed_stack;

static const uint INVALID = 0xFFFFFFFFu;
static const uint LOCAL_STACK_CAP = 2048u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint input_end()
{
    return min(gParams.input_end, gParams.first_input + token_count[0]);
}

void push_rhs(uint stack_base, inout uint top, uint rhs_off, uint rhs_len, uint lane)
{
    [loop]
    for (uint i = lane; i < rhs_len; i += WG_SIZE)
    {
        block_seed_stack[stack_base + top + i] = prod_rhs[rhs_off + rhs_len - 1u - i];
    }
    GroupMemoryBarrierWithGroupSync();
    top += rhs_len;
}

void compute_seed(uint block_idx, uint lane)
{
    if (lane == 0u)
        block_seed_len[block_idx] = INVALID;
    GroupMemoryBarrierWithGroupSync();

    if (gParams.n_nonterminals == 0u || gParams.n_productions == 0u || gParams.n_kinds == 0u)
        return;

    uint stack_limit = min(gParams.stack_capacity, LOCAL_STACK_CAP);
    if (stack_limit == 0u)
        return;

    uint target = gParams.first_input + block_idx * gParams.block_size;
    uint actual_input_end = input_end();
    if (target > actual_input_end)
        return;

    if (block_idx == 0u)
    {
        if (lane == 0u)
        {
            uint stack_base_zero = block_idx * gParams.stack_capacity;
            block_seed_stack[stack_base_zero] = gParams.n_kinds + gParams.start_nonterminal;
            block_seed_len[block_idx] = 1u;
        }
        return;
    }

    uint stack_base = block_idx * gParams.stack_capacity;
    uint top = 0u;
    if (lane == 0u)
        block_seed_stack[stack_base + top] = gParams.n_kinds + gParams.start_nonterminal;
    top++;
    GroupMemoryBarrierWithGroupSync();

    uint pos = gParams.first_input;
    uint steps = 0u;

    [loop]
    while (top > 0u && steps < gParams.max_steps)
    {
        if (pos == target)
        {
            if (lane == 0u)
                block_seed_len[block_idx] = top;
            return;
        }
        if (pos > target)
            return;

        steps++;
        top--;
        uint sym = block_seed_stack[stack_base + top];
        uint lookahead = (pos < actual_input_end) ? token_kinds[pos] : 0u;

        if (sym < gParams.n_kinds)
        {
            if (sym != lookahead)
                return;
            pos++;
            continue;
        }

        uint nt = sym - gParams.n_kinds;
        if (nt >= gParams.n_nonterminals || lookahead >= gParams.n_kinds)
            return;

        uint pred_idx = nt * gParams.n_kinds + lookahead;
        uint prod = ll1_predict[pred_idx];
        if (prod == INVALID || prod >= gParams.n_productions)
            return;

        uint rhs_off = prod_rhs_off[prod];
        uint rhs_len = prod_rhs_len[prod];
        if (top + rhs_len > stack_limit)
            return;
        push_rhs(stack_base, top, rhs_off, rhs_len, lane);
    }

    if (pos == target)
    {
        if (lane == 0u)
            block_seed_len[block_idx] = top;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint idx = linear_group_id(gid);
    if (idx < gParams.n_blocks)
        compute_seed(idx, ltid.x);
}

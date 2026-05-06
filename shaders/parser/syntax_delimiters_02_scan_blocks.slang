// Parallel scan of syntax delimiter block sums.

struct Params
{
    uint n_tokens;
    uint n_blocks;
    uint scan_step;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<int> block_sum_paren;
StructuredBuffer<int> block_sum_bracket;
StructuredBuffer<int> block_sum_brace;
StructuredBuffer<int> prefix_paren_in;
StructuredBuffer<int> prefix_bracket_in;
StructuredBuffer<int> prefix_brace_in;

RWStructuredBuffer<int> prefix_paren_out;
RWStructuredBuffer<int> prefix_bracket_out;
RWStructuredBuffer<int> prefix_brace_out;
RWStructuredBuffer<int> block_prefix_paren;
RWStructuredBuffer<int> block_prefix_bracket;
RWStructuredBuffer<int> block_prefix_brace;
RWStructuredBuffer<int> counters;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n_blocks = gParams.n_blocks;
    if (i >= n_blocks)
        return;

    if (gParams.scan_step == 0u)
    {
        prefix_paren_out[i] = block_sum_paren[i];
        prefix_bracket_out[i] = block_sum_bracket[i];
        prefix_brace_out[i] = block_sum_brace[i];
        return;
    }

    if (gParams.scan_step < n_blocks)
    {
        int paren = prefix_paren_in[i];
        int bracket = prefix_bracket_in[i];
        int brace = prefix_brace_in[i];
        if (i >= gParams.scan_step)
        {
            paren += prefix_paren_in[i - gParams.scan_step];
            bracket += prefix_bracket_in[i - gParams.scan_step];
            brace += prefix_brace_in[i - gParams.scan_step];
        }
        prefix_paren_out[i] = paren;
        prefix_bracket_out[i] = bracket;
        prefix_brace_out[i] = brace;
        return;
    }

    block_prefix_paren[i] = i == 0u ? 0 : prefix_paren_in[i - 1u];
    block_prefix_bracket[i] = i == 0u ? 0 : prefix_bracket_in[i - 1u];
    block_prefix_brace[i] = i == 0u ? 0 : prefix_brace_in[i - 1u];

    int final_paren = prefix_paren_in[n_blocks - 1u];
    int final_bracket = prefix_bracket_in[n_blocks - 1u];
    int final_brace = prefix_brace_in[n_blocks - 1u];
    counters[0] = final_paren;
    counters[1] = final_bracket;
    counters[2] = final_brace;
}

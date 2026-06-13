// Parallel scan of syntax delimiter block sums.

import gpu_index;
import prefix_scan;

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
StructuredBuffer<int> block_sum_angle;
StructuredBuffer<int> prefix_paren_in;
StructuredBuffer<int> prefix_bracket_in;
StructuredBuffer<int> prefix_brace_in;
StructuredBuffer<int> prefix_angle_in;

RWStructuredBuffer<int> prefix_paren_out;
RWStructuredBuffer<int> prefix_bracket_out;
RWStructuredBuffer<int> prefix_brace_out;
RWStructuredBuffer<int> prefix_angle_out;
RWStructuredBuffer<int> block_prefix_paren;
RWStructuredBuffer<int> block_prefix_bracket;
RWStructuredBuffer<int> block_prefix_brace;
RWStructuredBuffer<int> block_prefix_angle;
RWStructuredBuffer<int> counters;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
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
        prefix_angle_out[i] = block_sum_angle[i];
        return;
    }

    if (gParams.scan_step < n_blocks)
    {
        prefix_paren_out[i] = block_prefix_scan_step<int, PrefixScanI32Add>(
            i,
            gParams.scan_step,
            block_sum_paren,
            prefix_paren_in);
        prefix_bracket_out[i] = block_prefix_scan_step<int, PrefixScanI32Add>(
            i,
            gParams.scan_step,
            block_sum_bracket,
            prefix_bracket_in);
        prefix_brace_out[i] = block_prefix_scan_step<int, PrefixScanI32Add>(
            i,
            gParams.scan_step,
            block_sum_brace,
            prefix_brace_in);
        prefix_angle_out[i] = block_prefix_scan_step<int, PrefixScanI32Add>(
            i,
            gParams.scan_step,
            block_sum_angle,
            prefix_angle_in);
        return;
    }

    block_prefix_paren[i] = exclusive_block_prefix<int, PrefixScanI32Add>(i, prefix_paren_in);
    block_prefix_bracket[i] =
        exclusive_block_prefix<int, PrefixScanI32Add>(i, prefix_bracket_in);
    block_prefix_brace[i] = exclusive_block_prefix<int, PrefixScanI32Add>(i, prefix_brace_in);
    block_prefix_angle[i] = exclusive_block_prefix<int, PrefixScanI32Add>(i, prefix_angle_in);

    int final_paren = prefix_paren_in[n_blocks - 1u];
    int final_bracket = prefix_bracket_in[n_blocks - 1u];
    int final_brace = prefix_brace_in[n_blocks - 1u];
    counters[0] = final_paren;
    counters[1] = final_bracket;
    counters[2] = final_brace;
}

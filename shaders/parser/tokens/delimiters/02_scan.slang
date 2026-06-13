// Block scan for token delimiter metadata.

import gpu_index;
import prefix_scan;

struct Params
{
    uint n_tokens;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<int> block_sum_brace;
StructuredBuffer<int> block_sum_bracket;
StructuredBuffer<int> block_sum_paren;
StructuredBuffer<int> block_sum_angle;
StructuredBuffer<int> prefix_brace_in;
StructuredBuffer<int> prefix_bracket_in;
StructuredBuffer<int> prefix_paren_in;
StructuredBuffer<int> prefix_angle_in;
StructuredBuffer<uint> top_brace_owner_block;
StructuredBuffer<uint> top_brace_owner_prefix_in;
StructuredBuffer<uint> statement_event_block;
StructuredBuffer<uint> statement_event_prefix_in;

RWStructuredBuffer<int> prefix_brace_out;
RWStructuredBuffer<int> prefix_bracket_out;
RWStructuredBuffer<int> prefix_paren_out;
RWStructuredBuffer<int> prefix_angle_out;
RWStructuredBuffer<int> block_prefix_brace;
RWStructuredBuffer<int> block_prefix_bracket;
RWStructuredBuffer<int> block_prefix_paren;
RWStructuredBuffer<int> block_prefix_angle;
RWStructuredBuffer<uint> top_brace_owner_prefix_out;
RWStructuredBuffer<uint> top_brace_owner_block_prefix;
RWStructuredBuffer<uint> statement_event_prefix_out;
RWStructuredBuffer<uint> statement_event_block_prefix;

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
    if (i >= gParams.n_blocks)
        return;

    if (gParams.scan_step == 0u)
    {
        prefix_brace_out[i] = block_sum_brace[i];
        prefix_bracket_out[i] = block_sum_bracket[i];
        prefix_paren_out[i] = block_sum_paren[i];
        prefix_angle_out[i] = block_sum_angle[i];
        top_brace_owner_prefix_out[i] = top_brace_owner_block[i];
        statement_event_prefix_out[i] = statement_event_block[i];
        return;
    }

    if (gParams.scan_step < gParams.n_blocks)
    {
        prefix_brace_out[i] = block_prefix_scan_step<int, PrefixScanI32Add>(
            i,
            gParams.scan_step,
            block_sum_brace,
            prefix_brace_in);
        prefix_bracket_out[i] = block_prefix_scan_step<int, PrefixScanI32Add>(
            i,
            gParams.scan_step,
            block_sum_bracket,
            prefix_bracket_in);
        prefix_paren_out[i] = block_prefix_scan_step<int, PrefixScanI32Add>(
            i,
            gParams.scan_step,
            block_sum_paren,
            prefix_paren_in);
        prefix_angle_out[i] = block_prefix_scan_step<int, PrefixScanI32Add>(
            i,
            gParams.scan_step,
            block_sum_angle,
            prefix_angle_in);
        top_brace_owner_prefix_out[i] = block_prefix_scan_step<uint, PrefixScanU32Max>(
            i,
            gParams.scan_step,
            top_brace_owner_block,
            top_brace_owner_prefix_in);
        statement_event_prefix_out[i] = block_prefix_scan_step<uint, PrefixScanU32Max>(
            i,
            gParams.scan_step,
            statement_event_block,
            statement_event_prefix_in);
        return;
    }

    block_prefix_brace[i] = exclusive_block_prefix<int, PrefixScanI32Add>(
        i,
        prefix_brace_in);
    block_prefix_bracket[i] = exclusive_block_prefix<int, PrefixScanI32Add>(
        i,
        prefix_bracket_in);
    block_prefix_paren[i] = exclusive_block_prefix<int, PrefixScanI32Add>(
        i,
        prefix_paren_in);
    block_prefix_angle[i] = exclusive_block_prefix<int, PrefixScanI32Add>(
        i,
        prefix_angle_in);
    top_brace_owner_block_prefix[i] = exclusive_block_prefix<uint, PrefixScanU32Max>(
        i,
        top_brace_owner_prefix_in);
    statement_event_block_prefix[i] = exclusive_block_prefix<uint, PrefixScanU32Max>(
        i,
        statement_event_prefix_in);
}

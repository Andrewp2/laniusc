import prefix_scan;

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
    uint emit_scan_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> seeded_status;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> prefix_in;
RWStructuredBuffer<uint> prefix_out;
StructuredBuffer<uint> status_summary_in;
RWStructuredBuffer<uint> status_summary_out;

static const uint STATUS_WORDS = 10u;
static const uint SUMMARY_WORDS = 4u;
static const uint INVALID = 0xFFFFFFFFu;

static const uint STATUS_DISABLED = 0u;
static const uint STATUS_BOUNDARY = 1u;
static const uint STATUS_ACCEPTED = 2u;

uint actual_input_end()
{
    return min(gParams.input_end, gParams.first_input + token_count[0]);
}

uint active_block_count()
{
    uint end = actual_input_end();
    uint n_input_tokens = end > gParams.first_input ? end - gParams.first_input : 0u;
    return min(gParams.n_blocks, max(1u, (n_input_tokens + gParams.block_size - 1u) / gParams.block_size));
}

bool block_ok(uint block_idx, uint status, uint active_blocks)
{
    if (block_idx + 1u == active_blocks)
        return status == STATUS_ACCEPTED;
    return status == STATUS_BOUNDARY;
}

void write_summary(uint i, uint4 summary)
{
    store_u32x4_flat(status_summary_out, i * SUMMARY_WORDS, summary);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n_blocks)
        return;

    uint value;
    uint4 summary_seed;
    if (gParams.emit_scan_step == 0u)
    {
        value = seeded_status[i * STATUS_WORDS + 5u];
        uint active_blocks = active_block_count();
        if (i >= active_blocks)
        {
            summary_seed = uint4(0u, 0u, 0u, INVALID);
        }
        else
        {
            uint base = i * STATUS_WORDS;
            uint status = seeded_status[base + 0u];
            uint first_error = block_ok(i, status, active_blocks) ? INVALID : i;
            summary_seed = uint4(
                seeded_status[base + 4u],
                status != STATUS_DISABLED ? 1u : 0u,
                seeded_status[base + 6u],
                first_error);
        }
    }
    else
    {
        value = prefix_in[i];
        summary_seed = uint4(0u, 0u, 0u, INVALID);
    }

    prefix_out[i] = parallel_scan_step_value<uint, PrefixScanU32Add>(
        i,
        gParams.emit_scan_step,
        value,
        prefix_in);
    write_summary(
        i,
        parallel_scan_step_u32x4_flat<PrefixScanU32x4SumSumMaxMin>(
            i,
            gParams.emit_scan_step,
            summary_seed,
            status_summary_in,
            SUMMARY_WORDS));
}

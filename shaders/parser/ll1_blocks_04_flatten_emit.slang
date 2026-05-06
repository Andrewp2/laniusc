// Flatten seeded LL(1) block emits into the canonical contiguous LL(1) stream.
//
// The seeded parser stores emissions in fixed-size per-block slices. This pass
// lets all lanes in each block copy that slice into ll1_emit and derives the
// compatibility ll1_status/seed_plan_status words from block-local results.

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

StructuredBuffer<uint> seeded_status;
StructuredBuffer<uint> seeded_emit;
StructuredBuffer<uint> seeded_emit_pos;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> block_emit_prefix;
StructuredBuffer<uint> block_status_summary_prefix;

RWStructuredBuffer<uint> ll1_emit;
RWStructuredBuffer<uint> ll1_emit_pos;
RWStructuredBuffer<uint> ll1_status;
RWStructuredBuffer<uint> seed_plan_status;

static const uint STATUS_WORDS = 10u;
static const uint SUMMARY_WORDS = 4u;
static const uint INVALID = 0xFFFFFFFFu;

static const uint ERR_NONE = 0u;

uint block_emit_len(uint block_idx)
{
    return seeded_status[block_idx * STATUS_WORDS + 5u];
}

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

uint block_emit_offset(uint block_idx)
{
    return block_idx == 0u ? 0u : block_emit_prefix[block_idx - 1u];
}

uint total_emit_len(uint active_blocks)
{
    return active_blocks == 0u ? 0u : block_emit_prefix[active_blocks - 1u];
}

void write_compat_status(uint lane)
{
    uint active_blocks = active_block_count();
    uint emit_len = total_emit_len(active_blocks);
    uint summary_base = (active_blocks - 1u) * SUMMARY_WORDS;
    uint steps = block_status_summary_prefix[summary_base + 0u];
    uint seed_count = block_status_summary_prefix[summary_base + 1u];
    uint max_depth = block_status_summary_prefix[summary_base + 2u];
    uint first_error = block_status_summary_prefix[summary_base + 3u];

    uint accepted = first_error == INVALID ? 1u : 0u;
    uint pos = actual_input_end();
    uint code = ERR_NONE;
    uint detail = 0u;
    if (accepted == 0u)
    {
        uint base = first_error * STATUS_WORDS;
        pos = seeded_status[base + 3u];
        code = seeded_status[base + 7u];
        detail = seeded_status[base + 8u];
    }

    if (lane == 0u)
    {
        ll1_status[0u] = accepted;
        seed_plan_status[0u] = accepted;
    }
    if (lane == 1u)
    {
        ll1_status[1u] = pos;
        seed_plan_status[1u] = pos;
    }
    if (lane == 2u)
    {
        ll1_status[2u] = code;
        seed_plan_status[2u] = code;
    }
    if (lane == 3u)
    {
        ll1_status[3u] = detail;
        seed_plan_status[3u] = detail;
    }
    if (lane == 4u)
    {
        ll1_status[4u] = steps;
        seed_plan_status[4u] = steps;
    }
    if (lane == 5u)
    {
        ll1_status[5u] = emit_len;
        seed_plan_status[5u] = seed_count;
    }
    if (lane == 6u)
        seed_plan_status[6u] = max_depth;
    if (lane == 7u)
        seed_plan_status[7u] = emit_len;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = gid.x;
    uint lane = ltid.x;

    uint active_blocks = active_block_count();
    if (block_idx >= active_blocks)
        return;

    if (block_idx == 0u)
        write_compat_status(lane);

    uint src_base = block_idx * gParams.emit_stride;
    uint dst_base = block_emit_offset(block_idx);
    uint emit_len = block_emit_len(block_idx);
    uint total_len = total_emit_len(active_blocks);

    [loop]
    for (uint i = lane; i < emit_len; i += 256u)
    {
        uint dst = dst_base + i;
        if (dst < total_len)
        {
            ll1_emit[dst] = seeded_emit[src_base + i];
            ll1_emit_pos[dst] = seeded_emit_pos[src_base + i];
        }
    }
}

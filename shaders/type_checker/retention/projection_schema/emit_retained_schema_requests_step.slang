// One lane per nominal term. The lane reserves its whole schema block and
// emits its substitution requests in schema order.
import type_checker.retention.projection_schema.retained_schema_workspace;
import type_checker.retention.projection_schema.retained_schema_round_state;
import type_checker.retention.substitution.retained_substitution_layout;

public RWStructuredBuffer<uint4> sb_requests;

uint reserve_schema_block(uint count)
{
    uint start = ps_round[3u];
    for (;;)
    {
        if (start > RT_INVALID - count)
        {
            InterlockedOr(ps_status[PS_ERROR], 2u);
            return RT_INVALID;
        }
        uint prior;
        InterlockedCompareExchange(ps_round[3u], start, start + count, prior);
        if (prior == start) return start;
        start = prior;
    }
}

public void emit_retained_schema_requests(uint term)
{
    uint entry = ps_entry(term);
    if (entry == RT_INVALID) return;
    uint4 d2 = rt_dir[entry*RT_DIR_WORDS+2u];
    if (d2.z == 0u) return;
    if (d2.z > 0xffffffu)
    {
        InterlockedOr(ps_status[PS_ERROR], 2u);
        return;
    }
    // The active lanes reserve once, then divide the block by their counts.
    uint offset = WavePrefixSum(d2.z);
    uint wave_count = WaveActiveSum(d2.z);
    uint wave_start = 0u;
    if (WaveIsFirstLane()) wave_start = reserve_schema_block(wave_count);
    wave_start = WaveReadLaneFirst(wave_start);
    if (wave_start == RT_INVALID) return;
    uint start = wave_start + offset;
    uint end = start + d2.z;
    uint base = ps_round_base();
    if (end > ps_config[PS_CFG_REQUEST_CAPACITY] || base > RT_INVALID - end ||
        base + end > ps_config[PS_CFG_FIELD_CAPACITY]) return;
    uint decl = rt_term_words(term).x;
    for (uint ordinal = 0u; ordinal < d2.z; ++ordinal)
    {
        uint4 field = rt_schema[d2.y + ordinal];
        uint kind = field.y & 0xffu;
        uint value = kind == RT_SCHEMA_FIELD || kind == RT_SCHEMA_PAYLOAD ? field.w : 1u;
        uint request = start + ordinal;
        sb_requests[request] = uint4(decl, term, value, request);
        // Consumers can run before the host handles a capacity stop.
        pj_schema_fields[base + request] = uint2(RT_INVALID, SB_INVARIANT);
    }
    pj_schema_ranges[term] = uint2(base + start, d2.z);
}

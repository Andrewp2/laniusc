// One lane, first in a chained closed solve (closed_obligations.rs record_chained):
// the gate and the workgroup counts of the producer passes after it.
//
// The host records a chained solve before it reads the status of the wave
// before. The wave's frontier (cw_wave words 0 and 1) and the discovery
// status come from the GPU. The solve runs when discovery has no failure or
// overflow, the frontier is not empty and the wave inserted instances with
// closed predicates (discovery status 11 differs from cw_wave word 3, the
// count before this wave). Otherwise every producer pass after this one
// dispatches no workgroups and the fault word says CW_SKIPPED: the batch
// counts are zero, the publication passes do nothing, and discovery's
// receipt check (05_publish mode 4) skips the wave's method routes.
//
// A solve that runs takes the store's term count and its frontier into
// cw_config, then sizes each pass from them. cw_indirect holds one
// (x, y, 1) triple per producer dispatch, in recording order (closed_obligations.rs
// CW_ARG_*).
import type_checker.retention.retention_store;
RWStructuredBuffer<uint> cw_config;
RWStructuredBuffer<uint> cw_state;
RWStructuredBuffer<uint> cw_indirect;
RWStructuredBuffer<uint> cw_wave;
StructuredBuffer<uint> cw_discovery;

static const uint CW_FAULT = 53u;
static const uint CW_STATE_WORDS = 64u;
static const uint CW_SKIPPED = 16u;
static const uint CW_ARG_SLOTS = 13u;
// cw_config words the host writes for this kernel: lanes of the catalog
// pass, the obligation bound of the publication pass, and the cw_wave word
// that counts the waves whose solve ran.
static const uint CW_CFG_CATALOG_LANES = 21u;
static const uint CW_CFG_OBLIGATIONS = 20u;
static const uint CW_CFG_RAN_WORD = 22u;

void write_lanes(uint slot, uint lanes)
{
    uint groups = max((lanes + 255u) / 256u, 1u);
    cw_indirect[slot * 3u] = min(groups, 65535u);
    cw_indirect[slot * 3u + 1u] = (groups + 65534u) / 65535u;
    cw_indirect[slot * 3u + 2u] = 1u;
}

[shader("compute")]
[numthreads(1,1,1)]
void main(uint3 id: SV_DispatchThreadID)
{
    uint lo = cw_wave[0];
    uint hi = cw_wave[1];
    bool clean = cw_discovery[3] == 0u && cw_discovery[6] == RT_INVALID
        && cw_discovery[10] == 0u && cw_discovery[12] == 0u;
    bool run = clean && hi > lo && cw_discovery[11] != cw_wave[3];
    cw_wave[3] = cw_discovery[11];
    if (!run)
    {
        for (uint w = 0u; w < CW_ARG_SLOTS * 3u; w++) cw_indirect[w] = 0u;
        for (uint s = 0u; s < CW_STATE_WORDS; s++) cw_state[s] = 0u;
        cw_state[CW_FAULT] = CW_SKIPPED;
        return;
    }
    cw_wave[cw_config[CW_CFG_RAN_WORD]] += 1u;
    uint terms = rt_counts[RT_A_TERMS];
    cw_config[0] = terms;
    cw_config[3] = lo;
    cw_config[4] = hi;
    uint lanes = terms + hi - lo;
    write_lanes(0u, max(max(cw_config[6], terms), max(max(cw_config[1], cw_config[2]), CW_STATE_WORDS)));
    write_lanes(1u, cw_config[CW_CFG_CATALOG_LANES]);
    write_lanes(2u, hi - lo);
    write_lanes(3u, 1u);
    write_lanes(4u, terms);
    write_lanes(5u, lanes);
    write_lanes(6u, lanes);
    write_lanes(7u, 1u);
    write_lanes(8u, lanes);
    write_lanes(9u, 1u);
    write_lanes(10u, lanes);
    write_lanes(11u, hi + cw_config[CW_CFG_OBLIGATIONS]);
    write_lanes(12u, 1u);
}

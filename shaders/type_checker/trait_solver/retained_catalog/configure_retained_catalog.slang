// Retained trait catalog producer: the configuration that depends on the
// store's counters, written on the GPU so the host records the count passes
// before it has read them. One lane.
import type_checker.retention.retention_store;
import type_checker.trait_solver.retained_catalog.retained_catalog_configuration;

public RWStructuredBuffer<uint> rc_config;
public globallycoherent RWStructuredBuffer<uint> rc_state;
public RWStructuredBuffer<uint> rc_dispatch;
public StructuredBuffer<uint> rc_stages; // (k, j) of each step, 64 words apart

uint pow2(uint n) { return n <= 1u ? 1u : 1u << (firstbithigh(n - 1u) + 1u); }
void groups(uint entry, uint lanes, bool run)
{
    uint g = max((lanes + 255u) / 256u, 1u);
    rc_dispatch[entry * 3u] = run ? min(g, 65535u) : 0u;
    rc_dispatch[entry * 3u + 1u] = (g + 65534u) / 65535u;
    rc_dispatch[entry * 3u + 2u] = 1u;
}

// Records of lane region r (retained_catalog_producer.slang RC_R_*): declarations and
// parameters from handle 1, terms from RT_FIRST_TERM.
uint region_size(uint r)
{
    if (r == 0u) return rt_counts[RT_A_DECLS] > 0u ? rt_counts[RT_A_DECLS] - 1u : 0u;
    if (r == 1u) return rt_counts[RT_A_PARAMS] > 0u ? rt_counts[RT_A_PARAMS] - 1u : 0u;
    if (r == 2u) return rt_counts[RT_A_TERMS] > RT_FIRST_TERM ? rt_counts[RT_A_TERMS] - RT_FIRST_TERM : 0u;
    if (r == 3u) return rt_counts[RT_A_DIR];
    if (r == 4u) return rt_counts[RT_A_TRAITS];
    if (r == 5u) return rt_counts[RT_A_USES];
    return rt_counts[RT_C_JOBS];
}
[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    for (uint w = 0u; w < RT_C_WORDS; w++) rc_state[RC_S_WORDS + w] = rt_counts[w];
    rc_config[RC_CFG_DECLS] = rt_counts[RT_A_DECLS];
    rc_config[RC_CFG_PARAMS] = rt_counts[RT_A_PARAMS];
    rc_config[RC_CFG_TERMS] = rt_counts[RT_A_TERMS];
    rc_config[RC_CFG_DIR] = rt_counts[RT_A_DIR];
    rc_config[RC_CFG_TRAITS] = rt_counts[RT_A_TRAITS];
    rc_config[RC_CFG_USES] = rt_counts[RT_A_USES];
    uint jobs = rt_counts[RT_C_JOBS];
    rc_config[RC_CFG_JOBS] = jobs;
    bool fits = true;
    uint first = 0u;
    for (uint r = 0u; r < 7u; r++)
    {
        rc_config[RC_CFG_BASE + r] = first;
        uint size = region_size(r);
        fits = fits && size <= rc_config[RC_CFG_REGION_CAP + r] && size < (1u << 24u);
        first += min(size, 1u << 24u);
    }
    // Failure words carry a 24-bit lane.
    fits = fits && first < (1u << 24u);
    uint request = rc_config[RC_CFG_UNIT_REQUEST];
    uint slots = request != 0u ? request : pow2(max(jobs * 2u, 1u));
    uint width = pow2(max(rt_counts[RT_A_TRAITS], 1u));
    fits = fits && jobs < (1u << 30u) && slots <= rc_config[RC_CFG_UNIT_CAP] && width <= rc_config[RC_CFG_SORT_CAP];
    rc_config[RC_CFG_UNIT_SLOTS] = slots;
    rc_config[RC_CFG_SORT] = width;
    rc_config[RC_CFG_LANES] = fits ? first : 0u;
    if (!fits) rc_state[RC_S_CONFIG_FAULT] = 1u;
    groups(RC_D_LANES, first, fits);
    groups(RC_D_ROOTS, region_size(3u) + region_size(4u) + region_size(5u), fits);
    groups(RC_D_SORT, width, fits);
    for (uint i = 0u; i < rc_config[RC_CFG_STEPS]; i++)
    {
        uint k = rc_stages[i * 64u];
        uint j = rc_stages[i * 64u + 1u];
        groups(RC_D_STEP + i, j == 0u ? width / 2u : width, fits && k <= width);
    }
}

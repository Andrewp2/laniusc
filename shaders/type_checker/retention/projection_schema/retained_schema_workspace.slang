__exported import type_checker.retention.retention_store;
// Schema rounds (docs/compiler-retained-projection.md, "Schema rounds").
// ps_config is written by the host per dispatch: mode, the substitution run
// a consumer reads, the run a round gate checks (0: none), the store
// generation, the request capacity and the field capacity.
public StructuredBuffer<uint> ps_config;
// Written by one-lane kernels; read by the round's one-lane kernels.
public globallycoherent RWStructuredBuffer<uint> ps_status;
public RWStructuredBuffer<uint2> pj_schema_ranges;
public RWStructuredBuffer<uint2> pj_schema_fields;
public static const uint PS_CFG_MODE = 0u;
public static const uint PS_CFG_RUN = 1u;
public static const uint PS_CFG_GATE_RUN = 2u;
public static const uint PS_CFG_GENERATION = 3u;
public static const uint PS_CFG_REQUEST_CAPACITY = 4u;
public static const uint PS_CFG_FIELD_CAPACITY = 5u;
// ps_status words. The host writes them once per projection (lo 32).
public static const uint PS_LO = 1u;            // first term of the next round
public static const uint PS_ERROR = 2u;         // 1: store not ready, 2: request count overflow
public static const uint PS_STOP = 3u;          // PS_STOP_* below
public static const uint PS_BASE = 4u;          // fields written by committed rounds
public static const uint PS_DEMAND_REQUESTS = 5u;
public static const uint PS_DEMAND_FIELDS = 6u;
public static const uint PS_ROUNDS = 7u;        // committed rounds
public static const uint PS_PREPARE_FAILED = 9u;
public static const uint PS_PUBLISH_FAILED = 10u;
public static const uint PS_TERMS = 8u;         // store terms at the last close
public static const uint PS_STOP_RUNNING = 0u;
public static const uint PS_STOP_CONVERGED = 1u;
public static const uint PS_STOP_UNPUBLISHED = 2u;
public static const uint PS_STOP_CAPACITY = 3u;
public static const uint PS_STOP_FAILED = 4u;
public uint ps_entry(uint term)
{
    if (term < RT_FIRST_TERM || term >= rt_counts[RT_A_TERMS] ||
        rt_term_kind(term) != RT_KIND_NAMED || !rt_term_closed(term)) return RT_INVALID;
    uint decl = rt_term_words(term).x;
    if (decl == 0u || decl >= rt_counts[RT_A_DECLS]) return RT_INVALID;
    uint def = rt_decl_def[decl];
    if (def == 0u || def > rt_counts[RT_A_DIR]) return RT_INVALID;
    uint4 d0 = rt_dir[(def-1u)*RT_DIR_WORDS];
    uint4 d3 = rt_dir[(def-1u)*RT_DIR_WORDS+3u];
    return d0.x == decl && (d0.y == 5u || d0.y == 6u) &&
        d0.w == RT_DIR_COMMITTED && d3.w == 0u ? def-1u : RT_INVALID;
}

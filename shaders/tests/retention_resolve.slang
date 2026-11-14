// Acceptance probe for program retention: reads only the build store. One
// lane per committed use. A use whose callee is defined by another
// (library, unit) and whose environment is closed resolves the callee's
// committed definition, substitutes the environment into the callee's
// declared result, parameters, every typed row of its body segment and the
// environments of the body's own uses, and validates the segment's relative
// references. Results go to rt_test_out (RT_PROBE_WORDS per use).
import type_checker.retention.retention_store;
import type_checker.retention.retention_subst;

RWStructuredBuffer<uint> rt_test_out;

static const uint RT_PROBE_WORDS = 20u;
static const uint LANE_WORDS = 256u;

static const uint P_ELIGIBLE = 0u;      // 1 eligible; 2+ reasons it is not
static const uint P_CALLEE = 1u;
static const uint P_RESULT = 2u;        // substituted declared result
static const uint P_EXPECTED = 3u;      // the use's own checked result
static const uint P_RESULT_STATUS = 4u;
static const uint P_ROWS = 5u;          // segment rows
static const uint P_TYPED = 6u;         // typed rows substituted to closed terms
static const uint P_FAILED = 7u;        // typed rows whose substitution failed
static const uint P_FIRST_FAILURE = 8u; // status of the first failure
static const uint P_BAD_REFS = 9u;      // relative references out of the segment
static const uint P_USES = 10u;         // the callee body's uses
static const uint P_USES_CLOSED = 11u;  // ... whose environments substitute to closed terms
static const uint P_HASH = 12u;         // + 2: structural hash of substituted row terms
static const uint P_PARAMS_CLOSED = 14u;
static const uint P_NESTED_CALLEE = 15u; // callee DeclId of the body's first use
static const uint P_DIR_FLAGS = 16u;
static const uint P_EXPECTED_CLOSED = 17u;
static const uint P_PARAM_COUNT = 18u;
static const uint P_REJECTION_CHECKS = 19u;

bool rel_ok(uint word, uint limit)
{
    if (word == 0xffffffffu) return true;
    return word != 0xc0000000u && word <= limit;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint use = dtid.x;
    if (use >= rt_counts[RT_A_USES]) return;
    uint o = use * RT_PROBE_WORDS;
    for (uint i = 0u; i < RT_PROBE_WORDS; i++) rt_test_out[o + i] = 0u;
    uint4 u0 = rt_uses[use * RT_USE_WORDS + 0u];
    uint4 u1 = rt_uses[use * RT_USE_WORDS + 1u];
    uint callee = u0.w;
    rt_test_out[o + P_CALLEE] = callee;
    rt_test_out[o + P_EXPECTED] = u1.y;
    if (callee == 0u) { rt_test_out[o + P_ELIGIBLE] = 2u; return; }
    uint def = rt_decl_def[callee];
    if (def == 0u) { rt_test_out[o + P_ELIGIBLE] = 3u; return; }
    if (rt_counts[RT_C_READY] == 0u)
    {
        RtBinding blocked = rt_binding(def - 1u, u1.x);
        rt_test_out[o + P_RESULT_STATUS] = blocked.status;
        rt_test_out[o + P_ELIGIBLE] = 6u;
        return;
    }
    if (all(rt_decl_key[callee].xy == rt_decl_key[u0.x].xy)) { rt_test_out[o + P_ELIGIBLE] = 4u; return; }
    if (!rt_term_closed(u1.x)) { rt_test_out[o + P_ELIGIBLE] = 5u; return; }
    rt_test_out[o + P_ELIGIBLE] = 1u;

    uint entry = def - 1u;
    uint4 d1 = rt_dir[entry * RT_DIR_WORDS + 1u];
    uint4 d2 = rt_dir[entry * RT_DIR_WORDS + 2u];
    uint4 d3 = rt_dir[entry * RT_DIR_WORDS + 3u];
    rt_test_out[o + P_DIR_FLAGS] = d3.w;
    rt_test_out[o + P_EXPECTED_CLOSED] = rt_is_resolved(u1.y) && rt_term_closed(u1.y) ? 1u : 0u;
    rt_test_out[o + P_PARAM_COUNT] = d1.w;
    if (d3.w != 0u) return;
    RtBinding b = rt_binding(entry, u1.x);
    uint scratch = use * LANE_WORDS;

    // Exercise failure results on the actual retained environment. Neither
    // unresolved references nor another declaration's binder may look valid.
    uint rejected = 0u;
    for (uint i = 0u; i < 4u; i++)
    {
        uint term = i == 0u ? 0u : (i == 1u ? RT_UNKNOWN : (i == 2u ? RT_NONE : RT_FIT_FAILED));
        uint2 value = rt_subst(b, term, scratch, LANE_WORDS);
        uint wanted = i == 3u ? RT_SUBST_FIT_FAILED : RT_SUBST_UNRESOLVED;
        if (value.y == wanted) rejected |= 1u << i;
    }
    // Keep the entry, masks, arity and all arguments identical. Only changing
    // the environment owner can distinguish this from the valid binding.
    uint4 original_env = rt_term_head[u1.x];
    RtTermKey other_key = rt_key_begin(RT_KIND_ENV, rt_term_arity(u1.x), original_env.x >> 16u,
        uint3(u0.x, original_env.z, original_env.w));
    RtStoredArgs other_args;
    other_args.base = rt_term_meta[u1.x].x;
    for (uint i = 0u; i < rt_term_arity(u1.x); i++) rt_key_fold(other_key, other_args.arg(i));
    uint other_env = rt_intern_term(other_key, other_args);
    if (rt_is_stored_term(other_env) && rt_binding(entry, other_env).status == RT_SUBST_ENV) rejected |= 16u;
    rt_test_out[o + P_REJECTION_CHECKS] = rejected;

    uint2 result = rt_subst(b, rt_sigs[d1.z], scratch, LANE_WORDS);
    rt_test_out[o + P_RESULT] = result.x;
    rt_test_out[o + P_RESULT_STATUS] = result.y;
    uint params_closed = 0u;
    for (uint p = 0u; p < d1.w; p++)
    {
        uint2 t = rt_subst(b, rt_sigs[d1.z + 1u + p], scratch, LANE_WORDS);
        if (t.y == RT_SUBST_OK && rt_term_closed(t.x)) params_closed++;
    }
    rt_test_out[o + P_PARAMS_CLOSED] = params_closed;

    uint segment = d2.x;
    if (segment == RT_INVALID) return;
    uint4 s0 = rt_segments[segment * RT_SEG_WORDS + 0u];
    uint rows = s0.z;
    rt_test_out[o + P_ROWS] = rows;
    uint typed = 0u;
    uint failed = 0u;
    uint first = 0u;
    uint bad = 0u;
    uint2 hash = uint2(0x9e3779b9u, 0x7f4a7c15u);
    for (uint r = 0u; r < rows; r++)
    {
        uint at = (s0.y + r) * RT_ROW_WORDS;
        uint4 r0 = rt_seg_rows[at + 0u];
        uint4 r1 = rt_seg_rows[at + 1u];
        uint4 r3 = rt_seg_rows[at + 3u];
        if (!rel_ok(r0.y, rows - 1u) || !rel_ok(r1.x, rows - 1u) || !rel_ok(r1.y, rows - 1u) || !rel_ok(r1.z, rows))
            bad++;
        if (!rt_is_resolved(r3.x)) continue;
        uint2 t = rt_subst(b, r3.x, scratch, LANE_WORDS);
        if (t.y == RT_SUBST_OK && rt_term_closed(t.x))
        {
            typed++;
            uint2 h = rt_ref_hash(t.x);
            hash = rt_mix2(rt_mix2(rt_mix2(hash, r), h.x), h.y);
        }
        else
        {
            if (failed == 0u) first = t.y == RT_SUBST_OK ? 0xffu : t.y;
            failed++;
        }
    }
    rt_test_out[o + P_TYPED] = typed;
    rt_test_out[o + P_FAILED] = failed;
    rt_test_out[o + P_FIRST_FAILURE] = first;
    rt_test_out[o + P_BAD_REFS] = bad;
    rt_test_out[o + P_HASH] = hash.x;
    rt_test_out[o + P_HASH + 1u] = hash.y;

    uint closed = 0u;
    for (uint k = 0u; k < d3.x; k++)
    {
        uint inner = d2.w + k;
        uint4 i0 = rt_uses[inner * RT_USE_WORDS + 0u];
        uint4 i1 = rt_uses[inner * RT_USE_WORDS + 1u];
        if (k == 0u) rt_test_out[o + P_NESTED_CALLEE] = i0.w;
        if (!rt_is_resolved(i1.x)) continue;
        uint2 t = rt_subst(b, i1.x, scratch, LANE_WORDS);
        if (t.y == RT_SUBST_OK && rt_term_closed(t.x)) closed++;
    }
    rt_test_out[o + P_USES] = d3.x;
    rt_test_out[o + P_USES_CLOSED] = closed;
}

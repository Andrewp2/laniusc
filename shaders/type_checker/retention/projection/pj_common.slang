// Retained instance projection (docs/compiler-retained-projection.md).
//
// Closed instances of retained templates become the compact HIR and
// semantic columns the existing lowering reads, with no frontend. The
// producer's records name each instance by rank:
//   pj_instances  two uint4 per rank: q0 (DeclId, ENV, generation, flags),
//                 q1 (first route row, route count, 0, 0)
//   pj_routes     one uint4 per (rank, use ordinal): (library, namespace or
//                 unit, local, generation)
//   pj_readiness  (generation, flags, instance count, route count)
// A global row is base_rows[rank] + relative row; its order is the
// lexicographic (rank, row) order, which also orders the errors.
__exported import primitive_types;
__exported import type_checker.retention.retention_store;
__exported import type_checker.retention.row_classes;
__exported import type_checker.retention.projection.pj_layout;
__exported import type_checker.retention.substitution.sb_consumer;

public StructuredBuffer<uint4> pj_instances;
public StructuredBuffer<uint4> pj_routes;
public StructuredBuffer<uint4> pj_readiness;
public StructuredBuffer<uint> pj_config;
public globallycoherent RWStructuredBuffer<uint> pj_status;
// Per rank: PJ_INFO_WORDS uint4 (00_plan):
//   i0 (DeclId, ENV, directory entry, segment)
//   i1 (rows, tokens, parameters, uses)
//   i2 side lengths 0..3
//   i3 (side lengths 4..6, signature start)
//   i4 (first segment row, first side record, first use, flags)
//   i5 (file id, file-relative byte start, text length, first token record)
public RWStructuredBuffer<uint4> pj_info;
// PJ_COLUMNS words per rank: exclusive scan of the rank counts; the totals
// follow the last rank.
public RWStructuredBuffer<uint> pj_base;
// Per rank: the plan's error (code, detail, 0, 0).
public RWStructuredBuffer<uint4> pj_errors;
// Per global row: the check's error (code, detail).
public RWStructuredBuffer<uint2> pj_row_errors;
// Per global row: (reference tag, reference payload, native words, scalar).
public RWStructuredBuffer<uint4> pj_g_facts;
// Per global row: (expression parent global row, member word offset, member
// word count, 0).
public RWStructuredBuffer<uint4> pj_g_aux;
// Closed-type layout per TermId: (native words or RT_INVALID, lowering
// instance kind, field count, 0).
public globallycoherent RWStructuredBuffer<uint4> pj_layout;

public uint pj_lane(uint3 dtid) { return dtid.x + dtid.y * 16776960u; }

public uint pj_instance_count()
{
    uint n; uint s;
    pj_instances.GetDimensions(n, s);
    return min(pj_readiness[0u].z, n / PJ_INSTANCE_WORDS);
}

public uint pj_route_count()
{
    uint n; uint s;
    pj_routes.GetDimensions(n, s);
    return min(pj_readiness[0u].w, n);
}

public uint pj_base_at(uint rank, uint column) { return pj_base[rank * PJ_COLUMNS + column]; }
public uint pj_total(uint column) { return pj_base[pj_instance_count() * PJ_COLUMNS + column]; }
public uint4 pj_inf(uint rank, uint word) { return pj_info[rank * PJ_INFO_WORDS + word]; }

public uint pj_side_len(uint rank, uint k)
{
    uint4 a = pj_inf(rank, 2u);
    uint4 b = pj_inf(rank, 3u);
    if (k < 4u) return k == 0u ? a.x : (k == 1u ? a.y : (k == 2u ? a.z : a.w));
    return k == 4u ? b.x : (k == 5u ? b.y : b.z);
}

// The rank whose block of column `column` holds global index `g`: the last
// rank in [lo, hi) whose base is at most g (ranks with empty blocks share
// a base; the last of them owns the next index).
public uint pj_rank_of(uint column, uint g, uint lo, uint hi)
{
    while (lo + 1u < hi)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (pj_base_at(mid, column) <= g) lo = mid;
        else hi = mid;
    }
    return lo;
}

// Request indices of a rank: result, parameters, rows, use environments,
// use results.
public uint pj_req_result(uint rank) { return pj_base_at(rank, PJ_C_REQUESTS); }
public uint pj_req_param(uint rank, uint p) { return pj_req_result(rank) + 1u + p; }
public uint pj_req_row(uint rank, uint row) { return pj_req_result(rank) + 1u + pj_inf(rank, 1u).z + row; }
public uint pj_req_use_env(uint rank, uint use)
{
    uint4 i1 = pj_inf(rank, 1u);
    return pj_req_result(rank) + 1u + i1.z + i1.x + use;
}
public uint pj_req_use_result(uint rank, uint use)
{
    uint4 i1 = pj_inf(rank, 1u);
    return pj_req_result(rank) + 1u + i1.z + i1.x + i1.w + use;
}
public uint pj_requests_of(uint rank)
{
    uint4 i1 = pj_inf(rank, 1u);
    return 1u + i1.z + i1.x + 2u * i1.w;
}

// A substitution result: the closed TermId, or RT_INVALID with `status`.
public uint pj_result(uint request, out uint status)
{
    if (!sb_result_current(pj_config[PJ_CFG_RUN], request))
    {
        status = 0xffffu;
        return RT_INVALID;
    }
    uint4 r0 = sb_results[request * SB_RESULT_WORDS];
    status = r0.y;
    return r0.y == SB_OK ? r0.x : RT_INVALID;
}

// The segment row record word `word` of rank's relative row.
public uint4 pj_row(uint rank, uint row, uint word)
{
    return rt_seg_rows[(pj_inf(rank, 4u).x + row) * RT_ROW_WORDS + word];
}

public uint4 pj_side(uint rank, uint k, uint index, uint word)
{
    uint offset = 0u;
    for (uint j = 0u; j < k; j++) offset += pj_side_len(rank, j);
    return rt_seg_side[pj_inf(rank, 4u).y + PJ_SIDE_WORDS * (offset + index) + word];
}

public uint4 pj_use(uint rank, uint use, uint word)
{
    return rt_uses[(pj_inf(rank, 4u).z + use) * RT_USE_WORDS + word];
}

public uint pj_dir_entry(uint decl)
{
    uint n; uint s;
    rt_decl_def.GetDimensions(n, s);
    if (decl == 0u || decl >= n || rt_decl_def[decl] == 0u) return RT_INVALID;
    return rt_decl_def[decl] - 1u;
}

public void pj_row_fail(uint g, uint code, uint detail)
{
    uint n; uint s;
    pj_row_errors.GetDimensions(n, s);
    if (g < n) pj_row_errors[g] = uint2(code, detail);
    InterlockedAdd(pj_status[PJ_S_ERRORS], 1u);
    InterlockedMin(pj_status[PJ_S_ERROR_ROW], g);
}

// The lowering type reference of a closed term.
public uint2 pj_ref_of(uint term)
{
    if (!rt_is_term(term)) return uint2(0u, RT_INVALID);
    if (term < RT_FIRST_TERM) return uint2(PJ_REF_SCALAR, term);
    return uint2(PJ_REF_INSTANCE, term);
}

// Native words of a closed term, RT_INVALID when it has no complete layout.
public uint pj_words(uint term)
{
    if (!rt_is_term(term)) return RT_INVALID;
    if (term < RT_FIRST_TERM)
    {
        if (term == SCALAR_STR) return 2u;
        if (term == SCALAR_UNIT || term == SCALAR_NEVER) return 0u;
        return 1u;
    }
    uint n; uint s;
    pj_layout.GetDimensions(n, s);
    return term < n ? pj_layout[term].x : RT_INVALID;
}

// References retain pointer storage while a member/index reads the terminal
// referent. The checked type graph has at most 64 levels.
public uint pj_referent(uint term)
{
    for (uint level = 0u; level < 64u; level++)
    {
        if (!rt_is_stored_term(term) || rt_term_kind(term) != RT_KIND_REF) return term;
        if (rt_term_arity(term) != 1u) return RT_INVALID;
        term = rt_term_arg(term, 0u);
    }
    return RT_INVALID;
}

public uint pj_array_count(uint term)
{
    if (!rt_is_stored_term(term) || rt_term_kind(term) != RT_KIND_ARRAY || rt_term_arity(term) != 2u)
        return RT_INVALID;
    uint length = rt_term_arg(term, 1u);
    if (!rt_is_stored_term(length) || rt_term_kind(length) != RT_KIND_CC_COUNT) return RT_INVALID;
    uint count = rt_term_words(length).x;
    // The two top words are native unknown/runtime-length markers.
    return count < 0xfffffffeu ? count : RT_INVALID;
}

// Argument mode 2 is the frontend's checked array-to-slice borrow. It
// changes the ABI to a descriptor, preserving the exact element identity.
// Other argument modes never authorize a type conversion.
public bool pj_argument_compatible(uint expected, uint actual, uint mode)
{
    if (expected == actual) return true;
    return mode == 2u && rt_is_stored_term(expected) && rt_is_stored_term(actual) &&
        rt_term_kind(expected) == RT_KIND_SLICE && rt_term_kind(actual) == RT_KIND_ARRAY &&
        rt_term_arg(expected, 0u) == rt_term_arg(actual, 0u);
}

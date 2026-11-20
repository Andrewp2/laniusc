// Root ABI certification (docs/compiler-retained-projection.md, "Native
// compilation"). Runs after validate_projected_semantic_rows accepted every instance. One lane per
// build-global use. A use whose caller ABI row (nc_use_abi, written by
// project_provisional_native_call_symbols.slang when the original object's call symbol became
// provisional) belongs to this build is a call from an original object.
// Its root route (rr_routes) must be current and name:
//   - an instance whose DeclId is the use's callee and whose ENV is the
//     use's closed ENV, whose parameter count is the call's argument count,
//     whose substituted result equals the accepted call result, and whose
//     substituted parameter types equal the caller's argument terms; or
//   - the callee's own DeclNative identity with a closed signature equal to
//     the caller's facts.
// Every compared type must have a complete native layout. A failing use
// counts in nc_cert[0], the lowest failing use goes to nc_cert[1], and the
// failure bit to nc_cert[2]. finalize_retained_native_abi sets READY_ABI.
import type_checker.retention.projection.retained_projection_results;
import type_checker.retention.projection.retained_projection_workspace;

public StructuredBuffer<uint4> nc_use_abi;
StructuredBuffer<uint2> nc_use_args;
StructuredBuffer<uint4> rr_routes;
public RWStructuredBuffer<uint4> rr_readiness;
public RWStructuredBuffer<uint> nc_cert;

static const uint USE_DIRECT = 1u;

static const uint C_FLAGS = 1u;        // argument overflow or untranslated argument
static const uint C_ROUTE = 2u;        // missing or stale route
static const uint C_TARGET = 4u;       // the instance is not the callee at this ENV
static const uint C_ARITY = 8u;
static const uint C_RESULT = 16u;
static const uint C_PARAM = 32u;
static const uint C_LAYOUT = 64u;
static const uint C_USE = 128u;        // not a direct call with a stored result

void reject(uint use, uint bit)
{
    InterlockedAdd(nc_cert[0], 1u);
    InterlockedMin(nc_cert[1], use);
    InterlockedOr(nc_cert[2], bit);
}

bool laid_out(uint t) { return pj_words(t) != RT_INVALID; }

bool compatible_argument(uint expected, uint2 argument)
{
    // Checked pointer parameters accept the integer zero literal. Its i32
    // producer writes zero to the whole native argument slot.
    return (expected == SCALAR_PTR && (argument.y & RT_CALL_ARG_NULL_LITERAL) != 0u) ||
        pj_argument_compatible(expected, argument.x, argument.y & ~RT_CALL_ARG_NULL_LITERAL);
}

public void certify_retained_native_abi(uint use)
{
    uint n; uint s;
    nc_use_abi.GetDimensions(n, s);
    uint routes; rr_routes.GetDimensions(routes, s);
    if (use >= min(n / 2u, rt_counts[RT_A_USES])) return;
    uint generation = rt_counts[RT_C_GENERATION];
    uint4 abi = nc_use_abi[use * 2u];
    if (abi.w != generation) return;
    if ((abi.z & 0xffu) != 0u) { reject(use, C_FLAGS); return; }
    uint4 u0 = rt_uses[use * RT_USE_WORDS];
    uint4 u1 = rt_uses[use * RT_USE_WORDS + 1u];
    uint form = u0.z & 0xffu;
    if ((form != USE_DIRECT && form != 2u) || (form == USE_DIRECT && (u0.z >> 8u) != 0u) || !rt_is_term(abi.x) ||
        !rt_term_closed(abi.x))
    {
        reject(use, C_USE);
        return;
    }
    if (use >= routes || rr_routes[use].w != generation) { reject(use, C_ROUTE); return; }
    uint4 route = rr_routes[use];
    uint args = abi.y;
    uint base = nc_use_abi[use * 2u + 1u].x;
    uint capacity; nc_use_args.GetDimensions(capacity,s);
    if (base > capacity || args > capacity-base) { reject(use,C_FLAGS); return; }
    if (!laid_out(abi.x)) { reject(use, C_LAYOUT); return; }
    for (uint k = 0u; k < args; k++)
        if (!laid_out(nc_use_args[base + k].x)) { reject(use, C_LAYOUT); return; }

    if (route.x == PJ_NATIVE_LIBRARY && route.y == PJ_NATIVE_NS_INSTANCE)
    {
        uint target = route.z;
        if (target >= pj_instance_count() || pj_instances[target * PJ_INSTANCE_WORDS].x != u0.w ||
            pj_instances[target * PJ_INSTANCE_WORDS].y != u1.x || pj_errors[target].x != 0u)
        {
            reject(use, C_TARGET);
            return;
        }
        if (pj_inf(target, 1u).z != args) { reject(use, C_ARITY); return; }
        uint status;
        if (pj_result(pj_req_result(target), status) != abi.x) { reject(use, C_RESULT); return; }
        for (uint k = 0u; k < args; k++)
            if (!compatible_argument(pj_result(pj_req_param(target, k), status),
                nc_use_args[base + k]))
            {
                reject(use, C_PARAM);
                return;
            }
        return;
    }
    uint4 key = rt_decl_key[u0.w];
    uint entry = pj_dir_entry(u0.w);
    if (entry == RT_INVALID || any(route.xyz != uint3(key.x, key.y, key.w)))
    {
        reject(use, C_TARGET);
        return;
    }
    uint4 d1 = rt_dir[entry * RT_DIR_WORDS + 1u];
    if (d1.y != 0u || d1.w != args) { reject(use, C_ARITY); return; }
    if (rt_sigs[d1.z] != abi.x) { reject(use, C_RESULT); return; }
    for (uint k = 0u; k < args; k++)
        if (!compatible_argument(rt_sigs[d1.z + 1u + k], nc_use_args[base + k]))
        { reject(use, C_PARAM); return; }
}

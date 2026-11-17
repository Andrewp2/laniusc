// Provisional call symbols of a retained build's original object
// (docs/compiler-retained-projection.md, "Native compilation"). Runs after
// the job's export commits, while the export scratch still maps the job's HIR rows
// to their retained uses. One lane per undefined symbol of the object: the
// k-th undefined symbol is the call at nc_call_hirs[k]
// (x86_object_artifact.rs). A call whose retained use is DIRECT and whose
// callee has a retained body (a generic template the original object does
// not define) gets the provisional identity (RESERVED_LIB, NS_USE, global
// use index) and its identity hash; every other symbol is copied unchanged.
// The lane also records the caller's ABI facts of that use for the
// certification (projection/10_certify.slang): the accepted result term and
// the translated term of every argument, as the caller's job checked them.
import hir_records;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import codegen.x86.finalize.symbol_identity;

// (symbol count, undefined count, generation, argument capacity)
StructuredBuffer<uint> nc_config;
StructuredBuffer<uint> nc_call_hirs;
// GPU_X86_SYMBOL_ROW_BYTES / 4 words per symbol, as the object stores them.
RWStructuredBuffer<uint> nc_symbols;
RWStructuredBuffer<uint> nc_identity;
// Two rows per global use: (accepted result, count, flags, generation),
// then (argument base, 0, 0, 0).
RWStructuredBuffer<uint4> nc_use_abi;
// Compact argument pool: (checked term, passing mode).
RWStructuredBuffer<uint2> nc_use_args;
RWStructuredBuffer<uint> nc_status;

StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<uint> semantic_argument_mode_by_hir;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;

static const uint NC_FLAG_ARG_UNTRANSLATED = 2u;
// nc_status[0] bits: 1 use table too small, 2 malformed symbol, 4 argument
// pool too small, 8 the job's export did not commit.
static const uint NC_STATUS_EXPORT_PENDING = 8u;
static const uint DIR_FREE_FN = 1u;
static const uint USE_DIRECT = 1u;
static const uint HIR_CALL = 19u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint k = finalize_lane(dtid);
    if (k >= nc_config[1]) return;
    // The host submits this kernel right behind the job's export and reads
    // both at once; an export that did not commit maps no call yet.
    if (rt_counts[RT_C_JOB_STATE] != RT_JOB_COMMITTED)
    {
        if (k == 0u) InterlockedOr(nc_status[0], NC_STATUS_EXPORT_PENDING);
        return;
    }
    uint row = k * SYMBOL_WORDS;
    uint call = nc_call_hirs[k];
    if (call >= hir_count() || compact_hir_core[call].kind != HIR_CALL || rt_x_flags[call].y == 0u) return;
    uint use_base = rt_x_counts[RT_X_BASE + RT_A_USES];
    if (use_base == RT_INVALID) return;
    uint use = use_base + rt_x_scan[call].y;
    uint uses; uint stride;
    nc_use_abi.GetDimensions(uses, stride);
    if (use >= uses / 2u)
    {
        InterlockedOr(nc_status[0], 1u);
        return;
    }
    uint4 u0 = rt_uses[use * RT_USE_WORDS];
    uint4 u1 = rt_uses[use * RT_USE_WORDS + 1u];
    bool method = (u0.z & 0xffu) == 2u;
    if ((u0.z & 0xffu) != USE_DIRECT && !method) return;
    uint callee = u0.w;
    uint n; uint s;
    rt_decl_def.GetDimensions(n, s);
    if (callee == 0u || callee >= n || rt_decl_def[callee] == 0u) return;
    uint entry = rt_decl_def[callee] - 1u;
    uint4 d0 = rt_dir[entry * RT_DIR_WORDS];
    uint4 d2 = rt_dir[entry * RT_DIR_WORDS + 2u];
    // Only a generic template is withheld from the original objects; a
    // nongeneric callee keeps its ordinary native symbol.
    if ((d0.y != DIR_FREE_FN && d0.y != 2u) || d2.x == RT_INVALID) return;

    HirPayload p = compact_hir_payload[call];
    uint count = p.c + (method ? 1u : 0u);
    uint arg_base;
    InterlockedAdd(nc_status[1], count, arg_base);
    if (arg_base > nc_config[3] || count > nc_config[3] - arg_base)
    {
        InterlockedOr(nc_status[0], 4u);
        return;
    }

    // The identity words of this undefined symbol: three aligned words.
    uint start = nc_symbols[row + 2u];
    if (nc_symbols[row + 3u] != PROVISIONAL_IDENTITY_BYTES || (start & 3u) != 0u ||
        nc_symbols[row + 4u] != SECTION_UNDEFINED)
    {
        InterlockedOr(nc_status[0], 2u);
        return;
    }
    uint3 identity = uint3(RESERVED_LIB, NS_USE, use);
    uint w = start >> 2u;
    nc_identity[w] = identity.x;
    nc_identity[w + 1u] = identity.y;
    nc_identity[w + 2u] = identity.z;
    uint2 hash = identity_hash(identity);
    nc_symbols[row] = hash.x;
    nc_symbols[row + 1u] = hash.y;

    // Caller ABI facts.
    uint flags = 0u;
    uint total = compact_call_arg_count[0u];
    for (uint i = 0u; i < count; i++)
    {
        uint term = RT_NONE;
        uint mode = 0u;
        if (method && i == 0u) term = u1.w;
        else if (p.b + i - (method ? 1u : 0u) < total)
        {
            uint value = compact_call_args[p.b + i - (method ? 1u : 0u)].value;
            if (value < hir_count())
            {
                term = translate_checked(semantic_expr_ref_tag_by_hir[value], semantic_expr_ref_payload_by_hir[value]);
                mode = semantic_argument_mode_by_hir[value];
                if (mode > 3u) flags |= NC_FLAG_ARG_UNTRANSLATED;
            }
        }
        if (!rt_is_term(term) || !rt_term_closed(term)) flags |= NC_FLAG_ARG_UNTRANSLATED;
        nc_use_args[arg_base + i] = uint2(term,mode);
    }
    nc_use_abi[use * 2u] = uint4(u1.y, count, flags, nc_config[2]);
    nc_use_abi[use * 2u + 1u] = uint4(arg_base,0u,0u,0u);
}

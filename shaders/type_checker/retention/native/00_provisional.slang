// Provisional call symbols of a retained build's original object
// (docs/compiler-retained-projection.md, "Native compilation"). Runs after
// the job's export, while the export scratch still maps the job's HIR rows
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

// (symbol count, undefined count, generation, 0)
StructuredBuffer<uint> nc_config;
StructuredBuffer<uint> nc_call_hirs;
// GPU_X86_SYMBOL_ROW_BYTES / 4 words per symbol, as the object stores them.
RWStructuredBuffer<uint> nc_symbols;
RWStructuredBuffer<uint> nc_identity;
// Per global use: (accepted result term, argument count, flags | modes<<8,
// generation). Eight two-bit checked argument modes follow the low flags.
RWStructuredBuffer<uint4> nc_use_abi;
// Per global use: NC_ARGS argument terms.
RWStructuredBuffer<uint> nc_use_args;
RWStructuredBuffer<uint> nc_status;

StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<uint> semantic_argument_mode_by_hir;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;

static const uint NC_ARGS = 8u;
static const uint NC_FLAG_ARGS_OVER = 1u;
static const uint NC_FLAG_ARG_UNTRANSLATED = 2u;
static const uint DIR_FREE_FN = 1u;
static const uint USE_DIRECT = 1u;
static const uint HIR_CALL = 19u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint k = finalize_lane(dtid);
    if (k >= nc_config[1]) return;
    uint row = k * SYMBOL_WORDS;
    uint call = nc_call_hirs[k];
    if (call >= hir_count() || compact_hir_core[call].kind != HIR_CALL || rt_x_flags[call].y == 0u) return;
    uint use_base = rt_x_counts[RT_X_BASE + RT_A_USES];
    if (use_base == RT_INVALID) return;
    uint use = use_base + rt_x_scan[call].y;
    uint uses; uint stride;
    nc_use_abi.GetDimensions(uses, stride);
    if (use >= uses)
    {
        InterlockedOr(nc_status[0], 1u);
        return;
    }
    uint4 u0 = rt_uses[use * RT_USE_WORDS];
    uint4 u1 = rt_uses[use * RT_USE_WORDS + 1u];
    if ((u0.z & 0xffu) != USE_DIRECT) return;
    uint callee = u0.w;
    uint n; uint s;
    rt_decl_def.GetDimensions(n, s);
    if (callee == 0u || callee >= n || rt_decl_def[callee] == 0u) return;
    uint entry = rt_decl_def[callee] - 1u;
    uint4 d0 = rt_dir[entry * RT_DIR_WORDS];
    uint4 d2 = rt_dir[entry * RT_DIR_WORDS + 2u];
    // Only a generic template is withheld from the original objects; a
    // nongeneric callee keeps its ordinary native symbol.
    if (d0.y != DIR_FREE_FN || d2.x == RT_INVALID) return;

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
    HirPayload p = compact_hir_payload[call];
    uint count = p.c;
    uint flags = count > NC_ARGS ? NC_FLAG_ARGS_OVER : 0u;
    uint total = compact_call_arg_count[0u];
    for (uint i = 0u; i < min(count, NC_ARGS); i++)
    {
        uint term = RT_NONE;
        if (p.b + i < total)
        {
            uint value = compact_call_args[p.b + i].value;
            if (value < hir_count())
            {
                term = translate_checked(semantic_expr_ref_tag_by_hir[value], semantic_expr_ref_payload_by_hir[value]);
                uint mode = semantic_argument_mode_by_hir[value];
                if (mode > 3u) flags |= NC_FLAG_ARG_UNTRANSLATED;
                else flags |= mode << (8u + 2u * i);
            }
        }
        if (!rt_is_term(term) || !rt_term_closed(term)) flags |= NC_FLAG_ARG_UNTRANSLATED;
        nc_use_args[use * NC_ARGS + i] = term;
    }
    nc_use_abi[use] = uint4(u1.y, count, flags, nc_config[2]);
}

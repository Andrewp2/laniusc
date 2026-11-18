// Provisional call symbols of a retained build's original object
// (docs/compiler-retained-projection.md, "Native compilation"). Runs on the
// GPU right behind the job's export, before the object is read: it rewrites
// the object's own undefined-symbol rows in place, while the export scratch
// still maps the job's HIR rows to their retained uses.
//
// Mode 0 (x86): one lane per undefined symbol k < nc_config[4]; nc_rows holds
// four words per symbol (library, unit, local, 0) and nc_call_hirs[k] is the
// call HIR of symbol k (x86_object_artifact.rs). nc_identity receives the
// symbol's final identity words, three per symbol, which the resident link
// parks for the object (link/resident.rs, region 6).
// Mode 1 (Wasm): one lane per relocation row r < nc_config[4]; nc_rows holds
// eight words per row, and a symbol row (word 1 is 2) carries the identity in
// words 4 to 6 and the call HIR in word 7 (wasm_object_artifact.rs).
//
// A call whose retained use is DIRECT and whose callee has a retained body
// (a generic template the original object does not define) gets the
// provisional identity (RESERVED_LIB, NS_USE, global use index); every other
// symbol keeps its identity. The host hashes the identity words when it reads
// the object. The lane also records the caller's ABI facts of that use for
// the certification (projection/10_certify.slang): the accepted result term
// and the translated term of every argument, as the caller's job checked
// them.
import shared.syntax.hir_records;
import shared.syntax.hir_expr_semantics;
import shared.semantics.primitive_types;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import codegen.x86.symbol_finalization.read_retained_symbol_identities;

// (mode, lanes, generation, argument capacity, row count). The row count
// is copied from the object's own total.
StructuredBuffer<uint> nc_config;
StructuredBuffer<uint> nc_call_hirs;
RWStructuredBuffer<uint> nc_rows;
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
// nc_status[0] bits: 1 use table too small, 4 argument pool too small, 8
// the job's export did not commit. nc_status[1] is the build's argument
// cursor.
static const uint NC_STATUS_EXPORT_PENDING = 8u;
static const uint DIR_FREE_FN = 1u;
static const uint USE_DIRECT = 1u;
static const uint HIR_CALL = 19u;

bool pointer_null_literal(uint row)
{
    for (uint depth = 0u; row < hir_count() && depth < hir_count(); depth++)
    {
        HirCore core = compact_hir_core[row];
        HirPayload payload = compact_hir_payload[row];
        if (!hir_is_forward_expression(core.kind, payload.a))
            return core.kind == HIR_SEM_KIND_LITERAL_EXPR &&
                payload.a == HIR_SEM_EXPR_INT && payload.b == 0u && payload.c == 0u;
        row = payload.b;
    }
    return false;
}

// The provisional identity of `call`, or none; records the use's ABI facts.
bool provisional_use(uint call, out uint use)
{
    use = 0u;
    if (call >= hir_count() || compact_hir_core[call].kind != HIR_CALL || rt_x_flags[call].y == 0u) return false;
    uint use_base = rt_x_counts[RT_X_BASE + RT_A_USES];
    if (use_base == RT_INVALID) return false;
    use = use_base + rt_x_scan[call].y;
    uint uses; uint stride;
    nc_use_abi.GetDimensions(uses, stride);
    if (use >= uses / 2u)
    {
        InterlockedOr(nc_status[0], 1u);
        return false;
    }
    uint4 u0 = rt_uses[use * RT_USE_WORDS];
    uint4 u1 = rt_uses[use * RT_USE_WORDS + 1u];
    bool method = (u0.z & 0xffu) == 2u;
    if ((u0.z & 0xffu) != USE_DIRECT && !method) return false;
    uint callee = u0.w;
    uint n; uint s;
    rt_decl_def.GetDimensions(n, s);
    if (callee == 0u || callee >= n || rt_decl_def[callee] == 0u) return false;
    uint entry = rt_decl_def[callee] - 1u;
    uint4 d0 = rt_dir[entry * RT_DIR_WORDS];
    uint4 d2 = rt_dir[entry * RT_DIR_WORDS + 2u];
    // Only a generic template is withheld from the original objects; a
    // nongeneric callee keeps its ordinary native symbol.
    if ((d0.y != DIR_FREE_FN && d0.y != 2u) || d2.x == RT_INVALID) return false;

    HirPayload p = compact_hir_payload[call];
    uint count = p.c + (method ? 1u : 0u);
    uint arg_base;
    InterlockedAdd(nc_status[1], count, arg_base);
    if (arg_base > nc_config[3] || count > nc_config[3] - arg_base)
    {
        InterlockedOr(nc_status[0], 4u);
        return false;
    }

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
                if (term == SCALAR_I32 && pointer_null_literal(value))
                    mode |= RT_CALL_ARG_NULL_LITERAL;
            }
        }
        if (!rt_is_term(term) || !rt_term_closed(term)) flags |= NC_FLAG_ARG_UNTRANSLATED;
        nc_use_args[arg_base + i] = uint2(term,mode);
    }
    nc_use_abi[use * 2u] = uint4(u1.y, count, flags, nc_config[2]);
    nc_use_abi[use * 2u + 1u] = uint4(arg_base,0u,0u,0u);
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = finalize_lane(dtid);
    if (lane >= nc_config[1] || lane >= nc_config[4]) return;
    // An export that did not commit maps no call; the host reruns the job.
    if (rt_counts[RT_C_JOB_STATE] != RT_JOB_COMMITTED)
    {
        if (lane == 0u) InterlockedOr(nc_status[0], NC_STATUS_EXPORT_PENDING);
        return;
    }
    bool wasm = nc_config[0] == 1u;
    uint at = wasm ? lane * 8u + 4u : lane * 4u;
    if (wasm && nc_rows[lane * 8u + 1u] != 2u) return;
    uint call = wasm ? nc_rows[lane * 8u + 7u] : nc_call_hirs[lane];
    uint use;
    if (provisional_use(call, use))
    {
        nc_rows[at] = RESERVED_LIB;
        nc_rows[at + 1u] = NS_USE;
        nc_rows[at + 2u] = use;
    }
    if (!wasm)
    {
        nc_identity[lane * 3u] = nc_rows[at];
        nc_identity[lane * 3u + 1u] = nc_rows[at + 1u];
        nc_identity[lane * 3u + 2u] = nc_rows[at + 2u];
    }
}

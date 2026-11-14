// Export step 14: one lane per call row inside a function. Writes the use
// record (RT_USE_WORDS uint4) at the function's use range:
//   u0 (owner DeclId, call row relative to the owner, form | adjust << 8 |
//       deref << 16, callee DeclId or 0)
//   u1 (environment term, result term, matched receiver term, receiver
//       parameter term)
//   u2 (enum variant ordinal or intrinsic tag, generic requirements of a
//       dependency callee, file id, callee token relative to the owner)
// The environment is the call's value environment re-keyed to the callee:
// its owner word is the callee's DeclId and its bound slots are terms of the
// caller's scope (owned by the caller's binder chain), so a consumer
// substitutes the caller's environment into them before binding the
// callee's parameters. Callee identity is never a row or token: a local
// function or method is its declaration key, a dependency function its
// (library, unit, local) triple, an enum constructor its enum's DeclId.
import hir_records;
import checked_semantic_artifact;
import type_checker.canonical.canonical_api;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.common;

StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
StructuredBuffer<uint2> call_env_ct;

public static const uint RT_USE_DIRECT = 1u;
public static const uint RT_USE_METHOD = 2u;
public static const uint RT_USE_CONSTRUCTOR = 4u;
public static const uint RT_USE_INTRINSIC = 5u;
public static const uint RT_USE_HOST = 6u;
public static const uint RT_USE_UNRESOLVED = 7u;

uint call_token(uint call)
{
    uint callee = compact_hir_payload[call].a;
    if (!valid_row(callee)) return 0xffffffffu;
    bool dotted = compact_hir_core[callee].kind == HIR_MEMBER_EXPR;
    uint token = dotted ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    return token < token_capacity() ? token : compact_hir_core[callee].token_start;
}

// The value environment re-keyed so its owner is the callee.
uint callee_env(uint env, uint callee)
{
    if (!rt_is_stored_term(env) || rt_term_kind(env) != RT_KIND_ENV) return env;
    uint4 head = rt_term_head[env];
    if (head.y == callee) return env;
    uint arity = (head.x >> 8u) & 0xffu;
    RtTermKey key = rt_key_begin(RT_KIND_ENV, arity, head.x >> 16u, uint3(callee, head.z, head.w));
    RtStoredArgs args;
    args.base = rt_term_meta[env].x;
    for (uint i = 0u; i < arity; i++) rt_key_fold(key, args.arg(i));
    return rt_intern_term(key, args);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = export_lane(dtid);
    if (row >= hir_count() || rt_x_flags[row].y == 0u) return;
    uint use_base = rt_x_counts[RT_X_BASE + RT_A_USES];
    if (use_base == RT_INVALID) return;
    uint owner_row = body_function(row);
    if (owner_row == 0xffffffffu) return;
    uint owner = rt_x_row[owner_row].x;
    uint entry = rt_x_row[owner_row].y;
    uint owner_parent = entry != RT_INVALID ? rt_dir[entry * RT_DIR_WORDS].z : 0u;

    CheckedCallArtifact call = semantic_calls_by_hir[row];
    uint form = RT_USE_UNRESOLVED;
    uint callee = 0u;
    uint aux = 0u;
    // A local function is named by its span's first token (target_token).
    uint callee_row = valid_row(call.callable_hir) ? call.callable_hir : function_at_token(call.target_token);
    if (call.callable_kind == 1u && valid_row(callee_row))
    {
        callee = intern_row_decl(callee_row);
        form = call.receiver_hir != 0xffffffffu ? RT_USE_METHOD : RT_USE_DIRECT;
    }
    else if (call.callable_kind == 3u && call.dependency_local_index != 0xffffffffu)
    {
        callee = rt_intern_decl(uint4(call.dependency_library_id, call.dependency_unit_id, RT_NS_CALLABLE,
            call.dependency_local_index));
        form = call.dependency_host_service != 0u && call.dependency_host_service != 0xffffffffu
            ? RT_USE_HOST
            : (call.receiver_hir != 0xffffffffu ? RT_USE_METHOD : RT_USE_DIRECT);
    }
    else if (call.callable_kind == 4u)
    {
        // The enum's DeclId through the constructor's checked result.
        uint result = translate_checked(call.return_ref_tag, call.return_ref_payload);
        if (rt_is_stored_term(result) && rt_term_kind(result) == RT_KIND_NAMED) callee = rt_term_head[result].y;
        form = RT_USE_CONSTRUCTOR;
        aux = call.callable_ordinal;
    }
    else if (call.callable_kind == 2u)
    {
        form = RT_USE_INTRINSIC;
        aux = call.intrinsic_tag;
    }
    if (callee == RT_INVALID) { callee = 0u; form = RT_USE_UNRESOLVED; }

    uint token = call_token(row);
    uint env = token != 0xffffffffu ? translate_ref(call_env_ct[token].x) : RT_NONE;
    if (callee != 0u && form != RT_USE_CONSTRUCTOR) env = callee_env(env, callee);
    uint result = translate_checked(call.return_ref_tag, call.return_ref_payload);
    uint matched = translate_checked(call.receiver_matched_ref_tag, call.receiver_matched_ref_payload);
    uint receiver = translate_checked(call.receiver_parameter_ref_tag, call.receiver_parameter_ref_payload);

    // Every term of the record lives in the caller's scope. (The receiver
    // parameter term is the callee's declared receiver, so it is checked
    // against the callee's chain only when the callee is local; a
    // dependency's declared receiver keeps its slot leaves.)
    uint untranslated = 0u;
    uint unowned = 0u;
    for (uint i = 0u; i < 3u; i++)
    {
        uint t = i == 0u ? env : (i == 1u ? result : matched);
        if (t == RT_UNKNOWN) untranslated++;
        else if (!owned_by(t, owner, owner_parent)) unowned++;
    }
    stat_add(owner_row, RT_STAT_UNTRANSLATED, untranslated);
    stat_add(owner_row, RT_STAT_OWNERSHIP, unowned);
    if (unowned != 0u) rt_invariant(RT_INV_OWNERSHIP);

    BodySpan span;
    span.function = owner_row;
    span.count = compact_hir_links[owner_row].subtree_end - owner_row;
    span.token = compact_hir_core[owner_row].token_start;
    span.token_end = max(max(rt_x_span[owner_row], compact_hir_core[owner_row].token_end), span.token);
    uint foreign = 0u;
    uint rel = rel_row(span, row, foreign);
    uint rel_callee_token = rel_token(span, token, foreign);
    uint index = use_base + rt_x_scan[row].y;
    uint adjust = call.receiver_adjustment_kind & 0xffu;
    uint deref = min(call.receiver_deref_count, 0xffffu);
    rt_uses[index * RT_USE_WORDS + 0u] = uint4(owner, rel, form | (adjust << 8u) | (deref << 16u), callee);
    rt_uses[index * RT_USE_WORDS + 1u] = uint4(env, result, matched, receiver);
    rt_uses[index * RT_USE_WORDS + 2u] = uint4(aux, call.generic_requirements, compact_hir_links[row].file_id, rel_callee_token);
}

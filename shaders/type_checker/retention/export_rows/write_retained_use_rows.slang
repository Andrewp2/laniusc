// Export step 14: one lane per use row inside a function (type_checker/retention/export_types/collect_retained_body_metadata.slang
// use_row: calls, struct literals, unit-variant values and function
// references). Writes the use
// record (RT_USE_WORDS uint4) at the function's use range:
//   u0 (owner DeclId, call row relative to the owner, form | adjust << 8 |
//       deref << 16, callee DeclId or 0)
//   u1 (environment term, result term, matched receiver term, receiver
//       parameter term), all in the caller's scope
//   u2 (enum variant ordinal or intrinsic tag, generic requirements of a
//       dependency callee, file id, callee token relative to the owner)
// The environment is the call's value environment re-keyed to the callee:
// its owner word is the callee's DeclId and its bound slots are terms of the
// caller's scope (owned by the caller's binder chain), so a consumer
// substitutes the caller's environment into them before binding the
// callee's parameters. Callee identity is never a row or token: a local
// function or method is its declaration key, a dependency function its
// (library, unit, local) triple, an enum constructor its enum's DeclId.
import shared.syntax.hir_records;
import shared.semantics.primitive_types;
import shared.semantics.checked_semantic_artifact;
import type_checker.canonicalization.canonical_api;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.export_lane_index;
import type_checker.retention.retained_row_classes;
import type_checker.retention.export_rows.retained_body_source_tables;

StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
StructuredBuffer<uint> semantic_call_native_abi_by_hir;
StructuredBuffer<uint> semantic_function_native_abi_by_hir;
StructuredBuffer<uint> semantic_function_host_service_by_hir;
StructuredBuffer<uint2> call_env_ct;
StructuredBuffer<uint> semantic_value_decl_by_hir;
StructuredBuffer<uint2> semantic_value_const_by_hir;
StructuredBuffer<uint> semantic_value_const_present_by_hir;
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;

public static const uint RT_USE_DIRECT = 1u;
public static const uint RT_USE_METHOD = 2u;
public static const uint RT_USE_RECORD = 3u;     // a struct literal: callee is the struct
public static const uint RT_USE_FN_REF = 8u;     // an ordinary function named as a value
public static const uint RT_USE_CONSTRUCTOR = 4u;
public static const uint RT_USE_INTRINSIC = 5u;
public static const uint RT_USE_HOST = 6u;
public static const uint RT_USE_UNRESOLVED = 7u;

uint call_token(uint call)
{
    // A struct literal or path keys its environment by its first token
    // (publish_canonical_call_environments.slang).
    uint kind = compact_hir_core[call].kind;
    if (kind != HIR_CALL_EXPR) return compact_hir_core[call].token_start;
    uint callee = compact_hir_payload[call].a;
    if (!valid_row(callee)) return 0xffffffffu;
    bool dotted = compact_hir_core[callee].kind == HIR_MEMBER_EXPR;
    uint token = dotted ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    return token < token_capacity() ? token : compact_hir_core[callee].token_start;
}

uint intern_callee_env(uint4 head, uint env, uint callee)
{
    uint arity = (head.x >> 8u) & 0xffu;
    RtTermKey key = rt_key_begin(RT_KIND_ENV, arity, head.x >> 16u, uint3(callee, head.z, head.w));
    RtStoredArgs args;
    args.base = rt_term_meta[env].x;
    for (uint i = 0u; i < arity; i++) rt_key_fold(key, args.arg(i));
    return rt_intern_term(key, args);
}

// Only the lane that claims (callee, env) interns the re-keyed term.
// Until classify_retained_trait_facts replaces it, the source environment supplies the same
// parameter owners for the scope check below.
uint stage_callee_env(uint env, uint callee, uint row)
{
    if (!rt_is_stored_term(env) || rt_term_kind(env) != RT_KIND_ENV) return env;
    uint4 head = rt_term_head[env];
    if (head.y == callee) return env;
    if (head.y != 0u)
    {
        rt_invariant(RT_INV_ENV_OWNER);
        return RT_UNKNOWN;
    }
    uint slots; uint stride;
    rt_x_use_envs.GetDimensions(slots, stride);
    uint mask = slots - 1u;
    uint slot = rt_probe_start(rt_mix(callee, env), slots);
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint prior_callee = rt_x_use_envs[slot].callee;
        if (prior_callee == 0u)
            InterlockedCompareExchange(rt_x_use_envs[slot].callee, 0u, callee, prior_callee);
        if (prior_callee == 0u || prior_callee == callee)
        {
            uint prior_env = rt_x_use_envs[slot].env;
            if (prior_env == 0u)
                InterlockedCompareExchange(rt_x_use_envs[slot].env, 0u, env, prior_env);
            if (prior_env == 0u) rt_x_use_envs[slot].term = intern_callee_env(head, env, callee);
            if (prior_env == 0u || prior_env == env)
            {
                rt_x_use_env_slot[row] = slot + 1u;
                return env;
            }
        }
        slot = (slot + 1u) & mask;
    }
    rt_invariant(RT_INV_TERM);
    return RT_UNKNOWN;
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
    uint callee_row = 0xffffffffu;
    uint kind = compact_hir_core[row].kind;
    uint row_term = translate_checked(semantic_expr_ref_tag_by_hir[row], semantic_expr_ref_payload_by_hir[row]);
    if (kind == HIR_CALL_EXPR)
    {
        // A local function is named by its span's first token (target_token).
        callee_row = valid_row(call.callable_hir) ? call.callable_hir : function_at_token(call.target_token);
        if (call.callable_kind == 1u && valid_row(callee_row))
        {
            callee = intern_row_decl(callee_row);
            form = call.receiver_hir != 0xffffffffu ? RT_USE_METHOD : RT_USE_DIRECT;
            aux = semantic_function_native_abi_by_hir[callee_row];
            uint service = semantic_function_host_service_by_hir[callee_row];
            if (service != 0u && service != 0xffffffffu)
            { form = RT_USE_HOST; aux = service; }
        }
        else if (call.callable_kind == 3u && call.dependency_local_index != 0xffffffffu)
        {
            callee_row = 0xffffffffu;
            callee = rt_intern_decl(uint4(call.dependency_library_id, call.dependency_unit_id, RT_NS_CALLABLE,
                call.dependency_local_index));
            form = call.dependency_host_service != 0u && call.dependency_host_service != 0xffffffffu
                ? RT_USE_HOST
                : (call.receiver_hir != 0xffffffffu ? RT_USE_METHOD : RT_USE_DIRECT);
            aux = form == RT_USE_HOST ? call.dependency_host_service : semantic_call_native_abi_by_hir[row];
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
        if (form != RT_USE_DIRECT && form != RT_USE_METHOD) callee_row = 0xffffffffu;
    }
    else if (kind == RT_HIR_STRUCT_LITERAL_EXPR)
    {
        // A record constructor requests the struct's layout under the
        // literal's checked application.
        if (rt_is_stored_term(row_term) && rt_term_kind(row_term) == RT_KIND_NAMED) callee = rt_term_head[row_term].y;
        form = RT_USE_RECORD;
    }
    else
    {
        // A name or path value (type_checker/retention/export_types/collect_retained_body_metadata.slang use_row): a unit variant or
        // an ordinary function reference.
        uint target = binding_target(semantic_value_decl_by_hir[row]);
        if ((target & RT_X_VARIANT_BIT) != 0u)
        {
            uint variant = target & ~RT_X_VARIANT_BIT;
            uint owner = compact_variants[variant].owner;
            callee = valid_row(owner) ? intern_row_decl(owner) : RT_INVALID;
            aux = compact_variants[variant].ordinal;
            form = RT_USE_CONSTRUCTOR;
        }
        else if (target != 0u && valid_row(target - 1u) && compact_hir_core[target - 1u].kind == HIR_FN)
        {
            callee = intern_row_decl(target - 1u);
            form = RT_USE_FN_REF;
        }
        else if ((semantic_value_const_present_by_hir[row] & RT_CONST_VARIANT) != 0u)
        {
            if (rt_is_stored_term(row_term) && rt_term_kind(row_term) == RT_KIND_NAMED)
                callee = rt_term_head[row_term].y;
            aux = semantic_value_const_by_hir[row].x;
            form = RT_USE_CONSTRUCTOR;
        }
    }
    if (callee == RT_INVALID) { callee = 0u; form = RT_USE_UNRESOLVED; }

    uint token = call_token(row);
    uint env_count; uint env_stride;
    call_env_ct.GetDimensions(env_count, env_stride);
    uint env = token < env_count && form != RT_USE_FN_REF ? translate_ref(call_env_ct[token].x) : RT_NONE;
    if (callee != 0u) env = stage_callee_env(env, callee, row);
    bool call_row = kind == HIR_CALL_EXPR;
    // A call whose artifact publishes no result (a unit method statement,
    // `assert`) may take the row's unit or never type. Value-returning
    // calls require their accepted call result: a scalar-cache nominal
    // code can name the declaration without its generic arguments.
    uint result = call_row ? translate_checked(call.return_ref_tag, call.return_ref_payload) : row_term;
    if (call_row && result == RT_NONE && (row_term == SCALAR_UNIT || row_term == SCALAR_NEVER)) result = row_term;
    uint matched = call_row ? translate_checked(call.receiver_matched_ref_tag, call.receiver_matched_ref_payload) : RT_NONE;
    uint receiver = call_row ? translate_checked(call.receiver_parameter_ref_tag, call.receiver_parameter_ref_payload) : RT_NONE;
    // The receiver parameter is the accepted plan of methods/08_finalize_
    // candidates.slang, built from the caller's checked receiver: the
    // matched receiver itself (adjustment 1, by value or an existing
    // reference), or a reference to it (adjustment 2: the last dereferenced
    // reference, or a fresh `&matched`). It is a term of the caller's scope
    // for every callee kind (local, dependency, bound trait member), like
    // the matched receiver, and must have exactly that shape.
    // Only a receiver call has a receiver plan. A path call's matched
    // receiver is its qualifier, which a bare generic qualifier
    // (`W::get(w)`, `Option::is_some(o)`) types with its declaration's own
    // application, not a type of this body. The arguments carry the
    // receiver, so the record keeps no such term. A caller-scoped one stays:
    // a required member's route matches its bound on it (method_routes/01).
    bool receiver_plan = form == RT_USE_METHOD || (form == RT_USE_HOST && call.receiver_hir != 0xffffffffu);
    if (!receiver_plan && !owned_by(matched, owner, owner_parent)) matched = RT_NONE;
    if (!receiver_plan && !owned_by(receiver, owner, owner_parent)) receiver = RT_NONE;
    uint untranslated = form == RT_USE_UNRESOLVED || (form == RT_USE_CONSTRUCTOR && callee == 0u) ? 1u : 0u;
    uint adjust = call_row ? call.receiver_adjustment_kind & 0xffu : 0u;
    if (receiver_plan)
    {
        // A missing plan is untranslated here; an untranslatable term is
        // counted by the loop below.
        if (receiver == RT_NONE || matched == RT_NONE) untranslated++;
        else if (rt_is_resolved(receiver) && rt_is_resolved(matched))
        {
            bool shaped = adjust == 1u ? receiver == matched
                : adjust == 2u && rt_term_kind(receiver) == RT_KIND_REF && rt_term_arg(receiver, 0u) == matched;
            if (!shaped)
            {
                rt_invariant(RT_INV_RECEIVER_SCOPE);
                stat_add_at(owner_row, row, RT_STAT_OWNERSHIP, 1u);
            }
        }
    }

    // Every term of the record is in the caller's scope.
    uint unowned = 0u;
    for (uint i = 0u; i < 4u; i++)
    {
        uint t = i == 0u ? env : (i == 1u ? result : (i == 2u ? matched : receiver));
        if (t == RT_UNKNOWN || t == RT_FIT_FAILED || (i == 1u && !rt_is_resolved(t))) untranslated++;
        else if (!owned_by(t, owner, owner_parent)) unowned++;
    }
    stat_add_at(owner_row, row, RT_STAT_UNTRANSLATED, untranslated);
    stat_add_at(owner_row, row, RT_STAT_OWNERSHIP, unowned);
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
    uint deref = call_row ? min(call.receiver_deref_count, 0xffffu) : 0u;
    stat_add_at(owner_row, row, RT_STAT_FOREIGN, foreign);
    rt_uses[index * RT_USE_WORDS + 0u] = uint4(owner, rel, form | (adjust << 8u) | (deref << 16u), callee);
    rt_uses[index * RT_USE_WORDS + 1u] = uint4(env, result, matched, receiver);
    rt_uses[index * RT_USE_WORDS + 2u] = uint4(aux, call_row ? call.generic_requirements : 0u, compact_hir_links[row].file_id,
        rel_callee_token);
    RtJobToken source_token = job_token(token);
    uint file = compact_hir_links[row].file_id;
    rt_use_spans[index] = uint4(rt_counts[RT_C_JOBS], file,
        source_token.start - job_file_start(file), source_token.len);
}

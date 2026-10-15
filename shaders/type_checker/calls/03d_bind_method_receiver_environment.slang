// Bind a method receiver to its declaration-owned type and constant domains.
// This producer publishes accepted call facts before the independent return
// materializer reads them.
//
// Phase 0 matches the receiver against the impl root (ct_match over canonical
// IDs); phase 1 matches the self parameter against its accepted parameter
// under the bindings of phase 0. Each phase publishes the bindings it adds to
// the call's context environment (ct_context_publish), in the same tables
// ordinary argument and result inference reads, never in positional type
// slots. Explicit and contextual types must agree with the bindings, and
// constants merge with the call's constant binding.
import hir_records;
import status;
import dependency_interface;
import semantic_interface_layout;
import type_checker.methods.candidate;
import type_checker.mutable_checked_type_graph;
import type_checker.calls.explicit_call_environment;
import type_checker.calls.checked_constant_environment;
import type_checker.calls.contextual_call_environment;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_candidates;
import type_checker.canonical.canonical_mutable_rows;
import type_checker.canonical.canonical_dependency;
import type_checker.substitution.ct_spare;
import type_checker.substitution.ct_checked;
import type_checker.substitution.ct_rows;
import type_checker.substitution.ct_realize;
import type_checker.substitution.source_slots;
import type_checker.match.ct_match;
import type_checker.match.ct_context_publish;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> call_dependency_unit_id;
StructuredBuffer<uint> call_dependency_local_index;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> method_call_receiver_ref_tag;
StructuredBuffer<uint> method_call_receiver_ref_payload;
StructuredBuffer<MethodCandidate> method_candidate;
StructuredBuffer<uint> method_call_parameter_ref_tag;
StructuredBuffer<uint> method_call_parameter_ref_payload;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_ref_tag;
StructuredBuffer<uint> call_param_row_ref_payload;
StructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }

// The canonical type of dependency node `t` of the resident page (its alias
// root's), or CT_UNKNOWN.
uint dependency_type(uint t)
{
    uint count = dependency_type_count();
    uint root = t < count ? canonical_type_roots[t] : INVALID;
    return root < count ? ct_dependency_state(root) : CT_UNKNOWN;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = dtid.x + dtid.y * 16776960u;
    if (call >= hir_count() || compact_hir_core[call].kind != 19u) return;
    uint callee = compact_hir_payload[call].a;
    if (callee >= hir_count()) return;
    uint kind = compact_hir_core[callee].kind;
    if (kind != 21u && kind != 22u && kind != 33u) return;
    uint token = kind == 21u ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    if (token >= gParams.n_tokens) token = compact_hir_core[callee].token_start;
    if (token >= gParams.n_tokens) return;
    uint owner = checked_call_application_owner(token);
    bool library = call_dependency_library_id[token] != INVALID;
    uint method = INVALID;
    if (library)
    {
        method = dependency_find_method(call_dependency_library_id[token],
            call_dependency_unit_id[token], call_dependency_local_index[token]);
        if (method >= dependency_member_count()) return;
    }
    SourceSlots slots;
    CtSpare spare = ct_spare_none();
    uint env = CT_NONE;
    // One call site per matcher, interner and publisher keeps one inlined
    // copy of each.
    [loop]
    for (uint phase = 0u; phase < 2u; phase++)
    {
        bool run = false;
        // A dependency pattern is a signature node of the resident page; a
        // local one is a checked row, interned below since the method
        // metadata can produce it after the canonical stage.
        uint pattern = CT_UNKNOWN;
        uint2 local_pattern = uint2(0u, INVALID);
        uint2 actual = uint2(0u, INVALID);
        if (phase == 0u)
        {
            if (library)
            {
                uint receiver_tag = method_call_receiver_ref_tag[owner];
                uint receiver = method_call_receiver_ref_payload[owner];
                if (receiver_tag == 0u || receiver == INVALID ||
                    (receiver_tag == 3u && receiver >= mutable_type_capacity())) return;
                pattern = dependency_type(dependency_member_word(method * SEMANTIC_INTERFACE_MEMBER_WORDS + 10u));
                actual = uint2(receiver_tag, receiver);
            }
            else
            {
                uint declaration = call_fn_index[token];
                if (declaration >= gParams.n_tokens || method_decl_receiver_ref_tag[declaration] == 0u ||
                    method_call_receiver_ref_tag[owner] == 0u) return;
                local_pattern = uint2(method_decl_receiver_ref_tag[declaration],
                    method_decl_receiver_ref_payload[declaration]);
                actual = uint2(method_call_receiver_ref_tag[owner], method_call_receiver_ref_payload[owner]);
            }
            run = true;
        }
        else
        {
            MethodCandidate candidate = method_candidate[owner];
            if (candidate.state != METHOD_CANDIDATE_UNIQUE || candidate.receiver_mode == 0u) return;
            actual = uint2(method_call_parameter_ref_tag[owner], method_call_parameter_ref_payload[owner]);
            if (library)
            {
                uint base = method * SEMANTIC_INTERFACE_MEMBER_WORDS;
                uint mode = (dependency_member_word(base + 8u) >> 28u) & 3u;
                uint first = INVALID;
                if (mode == 1u || mode == 2u)
                {
                    // Portable parameter rows omit syntactic self. Its declared
                    // type is the full impl root, with one wrapper for &self.
                    // Remove exactly that wrapper from the accepted parameter,
                    // retaining any references that are part of the impl root.
                    if (mode == 2u)
                    {
                        if (actual.x == 3u && actual.y < mutable_type_capacity() &&
                            type_instance_kind[actual.y] == 4u)
                            actual = uint2(type_instance_elem_ref_tag[actual.y],
                                type_instance_elem_ref_payload[actual.y]);
                        else actual = uint2(0u, INVALID);
                    }
                    first = dependency_member_word(base + 10u);
                }
                else if (mode == 3u) first = dependency_method_parameter_type(method, 0u);
                run = first < dependency_type_count() && actual.x != 0u && actual.y != INVALID;
                if (run) pattern = dependency_type(first);
            }
            else
            {
                uint declaration = call_fn_index[token];
                uint2 row = uint2(0u, INVALID);
                if (declaration < gParams.n_tokens)
                {
                    uint mode = method_decl_receiver_mode[declaration];
                    if (mode == 1u)
                        row = uint2(method_decl_receiver_ref_tag[declaration],
                            method_decl_receiver_ref_payload[declaration]);
                    else if (mode == 2u)
                    {
                        // The method metadata producer owns this complete &ImplRoot
                        // graph. The unannotated self parameter row has no written
                        // type and is not an independent signature authority.
                        uint self_decl = method_decl_param_offset[declaration];
                        if (self_decl < gParams.n_tokens) row = uint2(3u, self_decl);
                    }
                    else if (mode == 3u)
                    {
                        uint first_param = call_param_row_start[declaration];
                        if (first_param < call_param_row_count_out[0u])
                            row = uint2(call_param_row_ref_tag[first_param],
                                call_param_row_ref_payload[first_param]);
                    }
                }
                run = row.x != 0u && row.y != INVALID;
                if (run) local_pattern = row;
            }
        }
        uint outcome = CT_PUBLISH_REJECTED;
        if (run)
        {
            // One interning site serves a local pattern, the actual (a
            // signature node of the resident page, or a checked row interned
            // here when inference produced it) and then each prior operand
            // the publisher asks for.
            bool pattern_pending = local_pattern.x != 0u;
            bool matching = true;
            uint2 operand = pattern_pending ? local_pattern : actual;
            uint matched = CT_MATCH_FAILED;
            uint count_mask = 0u;
            uint3 interned = uint3(0u, INVALID, CT_NONE);
            [loop]
            for (uint work = 0u; work <= CT_PUBLISH_REQUEST_LIMIT + 1u; work++)
            {
                uint id = operand.x == 5u ? dependency_type(operand.y)
                    : ct_intern_checked<CtMutableRows>(operand.x, operand.y, spare.record);
                if (pattern_pending)
                {
                    pattern = id;
                    pattern_pending = false;
                    operand = actual;
                    continue;
                }
                if (matching)
                {
                    matching = false;
                    matched = ct_is_resolved(pattern) && ct_is_resolved(id)
                        ? ct_match<SourceSlots>(slots, pattern, id, CT_NONE, CT_NONE, env, 0u, true, spare, count_mask)
                        : CT_MATCH_FAILED;
                    if (matched == CT_MATCH_OVERFLOW) { outcome = CT_PUBLISH_BUSY; break; }
                    if (!ct_is_record(matched)) break;
                }
                // A prior that has no ID agrees with no binding.
                else if (!ct_is_resolved(id)) { outcome = CT_PUBLISH_REJECTED; break; }
                else interned = uint3(operand, id);
                // Phase 1 publishes only the slots phase 0 left unbound.
                uint3 words = ct_words(matched);
                uint3 prior = env != CT_NONE ? ct_words(env) : uint3(0u, 0u, 0u);
                outcome = ct_publish_context<CtNoClaims>(call, token, matched, words.y & ~prior.y,
                    words.z & ~prior.z, count_mask,
                    CT_PUBLISH_TYPE_PRIORS | CT_PUBLISH_ENV_CONSTANTS | CT_PUBLISH_ADMIT, interned, operand);
                if (outcome != CT_PUBLISH_INTERN) break;
            }
            if (outcome == CT_PUBLISH_INTERN) outcome = CT_PUBLISH_BUSY;
            if (outcome == CT_PUBLISHED) call_context_owner_by_token[token] = call;
            if (phase == 0u && ct_is_record(matched)) env = matched;
        }
        if (outcome == CT_PUBLISH_BUSY) return;
        if (outcome == CT_PUBLISH_CAPACITY) record_min_token_error(status, token, 6u, 0x474e0001u);
        if (phase == 0u)
        {
            if (outcome != CT_PUBLISHED) { record_min_token_error(status, token, 3u, 0u); return; }
        }
        else if (outcome != CT_PUBLISHED && call_inference_state[0u] == 0u)
            record_min_token_error(status, token, 3u, 0u);
    }
}

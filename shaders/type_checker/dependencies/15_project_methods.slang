// Second dependency-page visit: publish only the shared finalized winner.
// No candidate is selected here and no page-local signature escapes as a key.
#include "method_candidates.slang"
import dependency_return_layout;
import type_checker.calls.explicit_dependency_binding;
import type_checker.calls.explicit_constant_operand;

StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
// Constant operands read checked type references through this kernel's binding.
struct KernelTypeRefs : IExplicitOperandTypeRefs
{
    uint type_ref_tag(uint token) { return type_expr_ref_tag[token]; }
    uint type_ref_payload(uint token) { return type_expr_ref_payload[token]; }
}

StructuredBuffer<uint> declaration_field_count;
RWStructuredBuffer<uint> semantic_argument_mode_by_hir;
RWStructuredBuffer<uint> method_call_receiver_ref_tag;
RWStructuredBuffer<uint> method_call_receiver_ref_payload;
RWStructuredBuffer<uint> method_call_parameter_ref_tag;
RWStructuredBuffer<uint> method_call_parameter_ref_payload;
RWStructuredBuffer<uint> call_dependency_library_id;
RWStructuredBuffer<uint> call_dependency_generic_requirements;
RWStructuredBuffer<uint> call_dependency_unit_id;
RWStructuredBuffer<uint> call_dependency_local_index;
RWStructuredBuffer<uint> call_dependency_host_service;
RWStructuredBuffer<uint> call_dependency_native_abi;
RWStructuredBuffer<uint> call_param_count;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> call_return_aggregate_word_count;
RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;

static const uint TYPE_KIND_SCALAR = 1u;
static const uint TYPE_KIND_DECLARATION = 3u;

void publish_method_result(
    uint method_token,
    uint member_i,
    uint owner_ref,
    bool dotted_call)
{
    uint member_base = member_i * MEMBER_WORDS;
    // The callable identity and arity do not depend on return-type
    // canonicalization. Publish them first so a malformed return record cannot
    // turn an otherwise resolved dependency method into a local lookup miss.
    uint method_local_index = dependency_member_word(member_base + 9u);
    if (method_local_index == INVALID)
        return;
    uint library; uint unit; uint owner_local;
    if (!dependency_contract_owner_identity(owner_ref, library, unit, owner_local)) return;
    call_dependency_library_id[method_token] = library;
    call_dependency_unit_id[method_token] = unit;
    call_dependency_local_index[method_token] = method_local_index;
    call_dependency_host_service[method_token] = INVALID;
    call_dependency_native_abi[method_token] = 0u;
    call_dependency_generic_requirements[method_token] =
        dependency_method_type_count(member_i) |
        (dependency_method_constant_count(member_i) << 16u);
    call_param_count[method_token] = dependency_method_parameter_count(member_i);
    if (dotted_call && call_param_count[method_token] != 0u &&
        dependency_method_parameter_type(member_i, 0u) != INVALID)
        call_param_count[method_token] -= 1u;

    uint return_type_i = dependency_member_word(member_base + 7u);
    uint type_count = dependency_type_count();
    if (return_type_i >= type_count)
        return;
    uint return_root = canonical_type_roots[return_type_i];
    if (return_root >= type_count)
        return;
    uint return_base = return_root * TYPE_WORDS;
    uint return_kind = dependency_type_word(return_base + 0u);
    call_return_aggregate_word_count[method_token] = dependency_aggregate_word_count(
        return_root, canonical_type_roots, declaration_field_count);

    if (return_kind == TYPE_KIND_SCALAR)
    {
        uint scalar = dependency_type_word(return_base + 1u);
        call_return_type[method_token] = scalar;
        call_return_type_token[method_token] = INVALID;
        decl_type_ref_tag[method_token] = TYPE_REF_SCALAR;
        decl_type_ref_payload[method_token] = scalar;
    }
    else
    {
        call_return_type[method_token] = 0u;
        call_return_type_token[method_token] = method_token;
        // This page-local signature is provisional. The complete call
        // materializer applies accepted type/constant bindings in caller scope.
        decl_type_ref_tag[method_token] = TYPE_REF_EXTERNAL_CANONICAL;
        decl_type_ref_payload[method_token] = return_root;
        if (return_kind == TYPE_KIND_DECLARATION)
        {
            external_type_library_id[method_token] =
                dependency_type_word(return_base + 1u);
            external_type_local_index[method_token] =
                dependency_type_word(return_base + 2u);
            external_type_unit_id[method_token] =
                dependency_type_word(return_base + 8u);
        }
        if (dependency_empty_struct_result(return_root, canonical_type_roots))
            call_return_type[method_token] = 1u;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint token; uint owner_token; uint receiver; bool dotted;
    if (!imported_method_call(call, token, owner_token, receiver, dotted)) return;
    MethodCandidate winner = method_candidate[token];
    if (winner.state != METHOD_CANDIDATE_UNIQUE ||
        winner.callable_kind != METHOD_CALLABLE_DEPENDENCY) return;
    // A trait's required member is the winner of a call through a bound
    // (15b); its signature, in the bound's context, types the call.
    uint member = dependency_find_method(winner.library_id, winner.unit_id, winner.local_index);
    if (member == INVALID) return;
    uint owner = dependency_member_word(member * MEMBER_WORDS);
    bind_dependency_explicit_application(KernelTypeRefs(), token, owner, winner.local_index);
    publish_method_result(token, member, owner, dotted);
    if (dotted && valid_hir(receiver) && winner.receiver_mode != 0u)
        semantic_argument_mode_by_hir[receiver] = winner.receiver_mode == 2u ? 3u : 1u;
    if (valid_token(owner_token) && owner_token != token)
    {
        // Checked call retention can read the qualified owner token, while
        // source argument metadata and lookup use the final method segment.
        method_candidate[owner_token] = winner;
        method_call_receiver_ref_tag[owner_token] = method_call_receiver_ref_tag[token];
        method_call_receiver_ref_payload[owner_token] = method_call_receiver_ref_payload[token];
        method_call_parameter_ref_tag[owner_token] = method_call_parameter_ref_tag[token];
        method_call_parameter_ref_payload[owner_token] = method_call_parameter_ref_payload[token];
        publish_method_result(owner_token, member, owner, dotted);
    }
}

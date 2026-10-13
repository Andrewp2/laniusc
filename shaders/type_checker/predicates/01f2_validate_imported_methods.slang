// Validate caller-owned implementations against the defining interface page.
// Only source-owned validation rows survive this pass; canonical member/type
// indices belong to the page and are never published as persistent evidence.

#include "method_validation_common.slang"
import semantic_interface_layout;
import dependency_interface;
import type_checker.dependencies.canonical_field_types;
import byte_packing;

struct NameSpan { uint start; uint len; uint kind; uint token_index; };
StructuredBuffer<NameSpan> name_spans;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
ByteAddressBuffer source_bytes;
ByteAddressBuffer language_symbol_bytes;
RWStructuredBuffer<uint> predicate_method_validation_owner_node;
RWStructuredBuffer<uint> predicate_method_validation_peer_node;
RWStructuredBuffer<uint> predicate_method_validation_status;
RWStructuredBuffer<uint> predicate_method_validation_detail_token;
RWStructuredBuffer<uint> predicate_method_validation_required_symbol;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint SIGNATURE_MISMATCH = 8u;
static const uint ARITY_MISMATCH = 7u;
static const uint UNSUPPORTED_METHOD_GENERIC = 16u;
static const uint DUPLICATE_TRAIT_METHOD = 20u;
static const uint EXTRA_IMPL_METHOD = 23u;
static const uint DUPLICATE_IMPL_METHOD = 24u;
static const uint VISIBILITY_MISMATCH = 26u;

void publish(uint method, uint owner, uint status)
{
    predicate_method_validation_owner_node[method] = owner;
    predicate_method_validation_peer_node[method] = INVALID;
    predicate_method_validation_status[method] = status;
    predicate_method_validation_detail_token[method] = method_contract_diagnostic_token(method);
    predicate_method_validation_required_symbol[method] = INVALID;
}

bool member_name_equal(uint name, uint member)
{
    uint base = member * SEMANTIC_INTERFACE_MEMBER_WORDS;
    if (dependency_member_word(base + 3u) != name_hash_lo[name] ||
        dependency_member_word(base + 4u) != name_hash_hi[name]) return false;
    NameSpan span = name_spans[name];
    uint start = dependency_member_word(base + 5u);
    uint length = dependency_member_word(base + 6u);
    if (span.len != length || length > 64u) return false;
    for (uint byte = 0u; byte < length; byte++)
    {
        uint local = span.kind == 3u
            ? byte_address_load_u8(language_symbol_bytes, span.start + byte)
            : byte_address_load_u8_bounded(source_bytes, span.start + byte, gParams.source_len);
        uint offset = start + byte;
        uint expected = (dependency_name_byte_word(offset >> 2u) >> ((offset & 3u) * 8u)) & 255u;
        if (local != expected) return false;
    }
    return true;
}

bool signature_matches(uint expected, uint actual_hir, uint owner, bool implicit_void)
{
    uint2 actual;
    if (!type_node_ref(actual_hir, actual.x, actual.y))
    {
        if (!implicit_void || valid_hir(actual_hir)) return false;
        actual = uint2(TYPE_REF_SCALAR, 1u);
    }
    return canonical_type_reference_matches<TraitMethodContractGraph>(owner,
        expected, actual, checked_type_capacity(), gParams.n_tokens);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    if (row >= active_method_count()) return;
    uint method = compact_method_cores[row].node;
    if (!method_contract_lookup_row_valid(method)) return;
    uint owner = predicate_method_contract_owner_hir[method];
    if (!trait_impl_owner_hir(owner)) return;
    uint reference = predicate_bound_reference[owner];
    if (!trait_reference_is_dependency(reference)) return;
    uint4 identity = trait_reference_identity(reference);
    uint declaration = dependency_find_declaration(identity.y, identity.z, identity.w);
    if (declaration >= dependency_declaration_count()) return;
    uint base = declaration * 14u;
    if (dependency_declaration_word(base + 6u) != 10u) return;
    uint start = dependency_declaration_word(base + 8u);
    uint count = dependency_declaration_word(base + 9u);
    uint members = dependency_member_count();
    if (start > members || count > members - start) return;

    uint status = method_unsupported_contract_status(method);
    if (status != PREDICATE_STATUS_OK) { publish(method, owner, status); return; }
    uint name = method_contract_name_id(method);
    uint contract = INVALID;
    for (uint ordinal = 0u; ordinal < count; ordinal++)
    {
        uint member = start + ordinal;
        if (dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 1u) != 7u ||
            !member_name_equal(name, member)) continue;
        if (contract != INVALID) { publish(method, owner, DUPLICATE_TRAIT_METHOD); return; }
        contract = member;
    }
    if (contract == INVALID) { publish(method, owner, EXTRA_IMPL_METHOD); return; }
    if (duplicate_method_contract_for_owner_name(owner, name) &&
        first_method_contract_for_owner_name(owner, name) != method)
    { publish(method, owner, DUPLICATE_IMPL_METHOD); return; }

    uint method_base = contract * SEMANTIC_INTERFACE_MEMBER_WORDS;
    uint requirements = dependency_member_word(method_base + 8u);
    uint symbol = dependency_member_word(method_base + 9u);
    uint receiver = (requirements >> 28u) & 3u;
    bool implicit_self = receiver == 1u || receiver == 2u;
    uint parameter_count = requirements & 65535u;
    if (((requirements >> 16u) & 4095u) != 0u)
    { publish(method, owner, UNSUPPORTED_METHOD_GENERIC); return; }
    if (((requirements >> 30u) & 1u) != uint(method_contract_is_public(method)))
    { publish(method, owner, VISIBILITY_MISMATCH); return; }
    if (method_param_count(method) != parameter_count + uint(implicit_self))
    { publish(method, owner, ARITY_MISMATCH); return; }
    if (method_receiver_mode(method) != receiver)
    { publish(method, owner, SIGNATURE_MISMATCH); return; }
    if (!signature_matches(dependency_member_word(method_base + 7u),
        method_return_type(method), owner, true))
    { publish(method, owner, SIGNATURE_MISMATCH); return; }

    uint checked = 0u;
    for (uint ordinal = 0u; ordinal < count; ordinal++)
    {
        uint member = (start + ordinal) * SEMANTIC_INTERFACE_MEMBER_WORDS;
        if (dependency_member_word(member + 1u) != 1u ||
            dependency_member_word(member + 9u) != symbol) continue;
        uint parameter = method_param_for_ordinal(method, dependency_member_word(member + 8u));
        if (!method_param_lookup_row_valid(parameter) ||
            !signature_matches(dependency_member_word(member + 7u),
                method_param_type(parameter), owner, false))
        { publish(method, owner, SIGNATURE_MISMATCH); return; }
        checked++;
    }
    if (checked != parameter_count)
    { publish(method, owner, ARITY_MISMATCH); return; }
    publish(method, owner, PREDICATE_STATUS_OK);
    // Capture the defining page's portable symbol while its member is active;
    // neither its page-local member index nor canonical graph roots survive.
    predicate_method_validation_required_symbol[method] = symbol;
}

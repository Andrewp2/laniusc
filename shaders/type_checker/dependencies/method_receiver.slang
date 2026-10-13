// Imported parameter references name exact owned interface members. Read the
// accepted callable environment; receiver shape and nominal argument position
// cannot establish lexical bindings and are never a fallback here.
import dependency_interface;
import semantic_interface_layout;
import type_checker.calls.checked_call_environment;
import type_checker.calls.contextual_call_environment;

public bool dependency_method_bound_parameter_ref(uint method, uint generic_root,
    uint callee, out uint tag, out uint payload)
{
    static const uint INVALID = 0xffffffffu;
    tag = 0u; payload = INVALID;
    if (method >= dependency_member_count() || generic_root >= dependency_type_count() ||
        callee == INVALID || dependency_type_word(generic_root * 9u) != 2u) return false;
    uint method_base = method * SEMANTIC_INTERFACE_MEMBER_WORDS;
    if (dependency_member_word(method_base + 1u) != 8u) return false;
    uint owner = dependency_member_word(method_base);
    uint member = dependency_type_word(generic_root * 9u + 1u);
    uint start; uint count;
    if (!dependency_contract_owner_members(owner, start, count) ||
        member < start || member - start >= count) return false;
    uint base = member * SEMANTIC_INTERFACE_MEMBER_WORDS;
    uint scope = dependency_member_word(base + 9u);
    if (dependency_member_word(base) != owner || dependency_member_word(base + 1u) != 2u ||
        (scope != dependency_member_word(method_base + 9u) &&
         (scope & 0xc0000000u) != 0xc0000000u)) return false;
    uint slot = dependency_generic_type_slot(generic_root);
    if (slot >= dependency_method_type_count(method) || slot >= 32u) return false;
    uint environment = 0x80000000u | callee;
    return checked_call_environment_argument(environment, slot, tag, payload) ||
        checked_context_environment_argument(environment, slot, tag, payload);
}

import hir_records;
import semantic_interface_layout;
// Retain source-order to lexical-slot mappings while the callable's exporting
// page is resident. Receiver/impl headers have different lexical scope IDs.
import dependency_interface;
import type_checker.calls.explicit_binding_metadata;
import type_checker.calls.explicit_constant_operand;

public void bind_dependency_explicit_application<TypeRefs : IExplicitOperandTypeRefs>(
    TypeRefs type_refs, uint token, uint owner, uint scope)
{
    HirRange arguments;
    if (!explicit_application_range(token, arguments)) return;
    // A variant's nominal parent owns its header. Method scopes instead use
    // their tagged implementation owner; never reinterpret that tag as a row.
    if (owner != 0xffffffffu && (owner & SEMANTIC_INTERFACE_IMPLEMENTATION_OWNER) == 0u)
    {
        if (owner >= dependency_declaration_count())
        { call_explicit_application_status[token] = 4u; return; }
        if (dependency_declaration_word(owner * 14u + 6u) == 9u)
            owner = dependency_declaration_word(owner * 14u + 10u);
    }
    uint start; uint count;
    if (!dependency_contract_owner_members(owner, start, count))
    { call_explicit_application_status[token] = 4u; return; }
    uint parameters = 0u; uint type_count = 0u;
    for (uint i = 0u; i < count; i++)
    {
        uint base = (start + i) * SEMANTIC_INTERFACE_MEMBER_WORDS;
        uint kind = dependency_member_word(base + 1u);
        if (dependency_member_word(base) != owner ||
            dependency_member_word(base + 9u) != scope || (kind != 2u && kind != 3u)) continue;
        parameters++;
        if (kind == 2u) type_count++;
    }
    if (arguments.count != parameters)
    { call_explicit_application_status[token] = 2u; return; }
    uint seen = 0u; uint constant_seen = 0u;
    for (uint i = 0u; i < count; i++)
    {
        uint row = start + i;
        uint base = row * SEMANTIC_INTERFACE_MEMBER_WORDS;
        uint kind = dependency_member_word(base + 1u);
        if (dependency_member_word(base) != owner ||
            dependency_member_word(base + 9u) != scope || (kind != 2u && kind != 3u)) continue;
        bool constant = kind == 3u;
        uint ordinal = dependency_generic_parameter_ordinal(row);
        uint slot = scope == 0u ? dependency_member_word(base + 2u) : dependency_member_word(base + 8u);
        // Free constant member positions follow the complete type domain.
        // Method flags already retain independent lexical slot offsets.
        if (constant && scope == 0u) slot = slot >= type_count ? slot - type_count : 0xffffffffu;
        if (ordinal >= arguments.count || slot >= 32u || ((constant ? constant_seen : seen) & (1u << slot)) != 0u)
        { call_explicit_application_status[token] = 4u; return; }
        if (constant)
        {
            if (!bind_explicit_constant_operand(type_refs, arguments.start + ordinal,
                dependency_const_member_scalar(row)))
            { call_explicit_application_status[token] = 3u; return; }
            constant_seen |= 1u << slot;
        }
        else seen |= 1u << slot;
        call_explicit_arg_slot[arguments.start + ordinal] = slot | (constant ? EXPLICIT_CONSTANT_SLOT : 0u);
    }
    call_explicit_application_status[token] = 1u;
}

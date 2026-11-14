import type_checker.interface.validate.implementation_common;

// Implementation records, one thread per implementation: inherent headers,
// trait implementation heads, their lexical scopes and prerequisites, in
// the host's check order. The per-member and per-binding steps come from
// the row pass (04a_implementation_rows), read here in that order.

// Returns the failing check, or 0.
uint check_inherent(uint index)
{
    if (impl(index, I_VISIBILITY) != 1u || impl(index, I_TRAIT_LIBRARY) != INVALID ||
        impl(index, I_TRAIT_UNIT) != INVALID || impl(index, I_TRAIT_DECL) != INVALID ||
        impl(index, I_ARG_COUNT) != 0u || impl(index, I_BINDING_COUNT) != 0u)
        return 10u;
    uint subject = impl(index, I_SUBJECT);
    if (is_constant_kind(ty(subject, Y_KIND)))
        return 11u;
    uint first = impl(index, I_FIRST_MEMBER);
    uint count = impl(index, I_MEMBER_COUNT);
    bool any_method = false;
    for (uint row = first; row < first + count; ++row)
        if (mem(row, B_KIND) == M_IMPL_METHOD)
            any_method = true;
    if (!any_method)
        return 12u;
    uint code;
    uint scope = parameter_scope(index, code);
    if (code != 0u)
        return code;
    code = graph_of_root(index, subject, scope);
    if (code != 0u)
        return code;
    for (uint row = first; row < first + count; ++row)
        if (is_generic_member(mem(row, B_KIND)) && member_result(row, 0u) != 0u)
            return member_result(row, 0u);
    for (uint domain = 0u; domain < 2u; ++domain)
    {
        uint kind = domain == 0u ? M_GENERIC_TYPE : M_GENERIC_CONST;
        uint n = scope == NO_SCOPE ? 0u : count_generic(first, count, scope, kind);
        if (n > 32u || (n != 0u && !generic_slots_exact(first, count, scope, kind, 0u, n)))
            return 18u;
    }
    for (uint row = first; row < first + count; ++row)
        if (mem(row, B_KIND) == M_IMPL_METHOD && member_result(row, 1u) != 0u)
            return member_result(row, 1u);
    if (!prerequisites_owned(index, scope))
        return 23u;
    return 0u;
}

uint check_trait(uint index)
{
    uint owner = OWNER_TAG | index;
    if (impl(index, I_VISIBILITY) > 1u || impl(index, I_TRAIT_LIBRARY) == INVALID ||
        impl(index, I_TRAIT_UNIT) == INVALID || impl(index, I_TRAIT_DECL) == INVALID)
        return 2u;
    uint argument_count = impl(index, I_ARG_COUNT);
    if (argument_count > 32u)
        return 3u;
    uint subject = impl(index, I_SUBJECT);
    if (is_constant_kind(ty(subject, Y_KIND)))
        return 4u;
    uint arguments = impl(index, I_FIRST_ARG);
    for (uint k = 0u; k < argument_count; ++k)
        if (iarg_owner(arguments + k) != index)
            return 5u;
    // validate_trait_implementation_header
    uint code;
    uint scope = parameter_scope(index, code);
    if (code != 0u)
        return code;
    uint first = impl(index, I_FIRST_MEMBER);
    uint count = impl(index, I_MEMBER_COUNT);
    for (uint row = first; row < first + count; ++row)
        if (is_generic_member(mem(row, B_KIND)) && !(scope != NO_SCOPE && mem(row, B_VALUE_HI) == scope))
            return 6u;
    for (uint domain = 0u; domain < 2u; ++domain)
    {
        uint kind = domain == 0u ? M_GENERIC_TYPE : M_GENERIC_CONST;
        uint n = 0u;
        for (uint row = first; row < first + count; ++row)
            if (mem(row, B_KIND) == kind)
                n += 1u;
        if (n > 32u || (n != 0u && !generic_slots_exact(first, count, scope, kind, 0u, n)))
            return 7u;
    }
    {
        TypeWalk walk;
        walk.init();
        walk.push(subject);
        for (uint k = 0u; k < argument_count; ++k)
            walk.push(iarg(arguments + k));
        code = graph_failure(walk, index, scope != NO_SCOPE, scope, false, 0u);
        if (code != 0u)
            return code;
    }
    for (uint row = first; row < first + count; ++row)
        if (is_generic_member(mem(row, B_KIND)) && member_result(row, 0u) != 0u)
            return member_result(row, 0u);
    if (!prerequisites_owned(index, scope))
        return 23u;
    for (uint row = first; row < first + count; ++row)
        if (!is_generic_member(mem(row, B_KIND)) && member_result(row, 1u) != 0u)
            return member_result(row, 1u);
    bool local_trait = impl(index, I_TRAIT_LIBRARY) == library_id() && impl(index, I_TRAIT_UNIT) == unit_id();
    uint trait_decl = impl(index, I_TRAIT_DECL);
    uint header_edges = 0u;
    uint trait_first = 0u;
    uint trait_count = 0u;
    uint required_methods = 0u;
    if (local_trait)
    {
        if (trait_decl >= count_of(S_DECL))
            return 26u;
        if (decl(trait_decl, D_KIND) != 10u || decl(trait_decl, D_NAMESPACE) != 3u)
            return 27u;
        uint header = decl(trait_decl, D_SIGNATURE);
        if (ty(header, Y_EDGE_COUNT) != argument_count)
            return 28u;
        header_edges = ty(header, Y_FIRST_EDGE);
        for (uint ordinal = 0u; ordinal < argument_count; ++ordinal)
            if (!parameter_operand_domain_matches(ty(edge(header_edges + ordinal), Y_PAYLOAD_LO),
                    iarg(arguments + ordinal)))
                return 29u;
        trait_first = decl(trait_decl, D_FIRST_MEMBER);
        trait_count = decl(trait_decl, D_MEMBER_COUNT);
        for (uint row = trait_first; row < trait_first + trait_count; ++row)
            if (mem(row, B_KIND) == M_TRAIT_METHOD)
                required_methods += 1u;
    }
    uint bindings = impl(index, I_FIRST_BINDING);
    uint binding_count = impl(index, I_BINDING_COUNT);
    for (uint b = bindings; b < bindings + binding_count; ++b)
    {
        if (bind_owner(b) != index)
            return 30u;
        if (binding_result(b) != 0u)
            return binding_result(b);
    }
    uint methods = 0u;
    for (uint row = first; row < first + count; ++row)
        if (mem(row, B_KIND) == M_IMPL_METHOD)
            methods += 1u;
    if (binding_count != methods || (local_trait && required_methods != binding_count))
        return 37u;
    return 0u;
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint index = walk_thread_index(gid, ltid);
    if (!framed() || validate_state[STATE_KEY] != INVALID || index >= count_of(S_IMPL))
        return;
    if (library_id() == INVALID || unit_id() == INVALID)
    {
        if (index == 0u)
            fail(PH_IMPLEMENTATIONS, 0u, 0u);
        return;
    }
    uint kind = impl(index, I_KIND);
    uint code = kind == IMPL_INHERENT ? check_inherent(index) : kind == IMPL_TRAIT ? check_trait(index) : 1u;
    if (code != 0u)
        fail(PH_IMPLEMENTATIONS, index, code);
}

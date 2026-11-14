import type_checker.interface.validate.implementation_common;

// The per-row steps of the implementation checks, one thread per member and
// per method binding. Each row's first failing check is stored for the
// implementation pass, which reads the rows in check order; a row alone
// scans its implementation's member range, so no thread scans it once per
// row. Results are computed whatever the implementation's earlier checks
// found: the implementation pass returns before it reads them when one of
// those failed.

// Inherent implementation, generic member: its scope is the impl scope or
// one of the implementation's methods.
uint inherent_generic_step(uint index, uint row, uint scope)
{
    uint value = mem(row, B_VALUE_HI);
    if (!(scope != NO_SCOPE && value == scope) &&
        !has_method_symbol(impl(index, I_FIRST_MEMBER), impl(index, I_MEMBER_COUNT), value))
        return 17u;
    return 0u;
}

// Inherent implementation, method: its public target, receiver, generic
// slots and signature graph.
uint inherent_method_step(uint index, uint row, uint scope)
{
    uint first = impl(index, I_FIRST_MEMBER);
    uint count = impl(index, I_MEMBER_COUNT);
    if (!method_is_public(row))
        return 20u;
    uint matched = types_match(impl(index, I_SUBJECT), mem(row, B_RECEIVER), 0u, 0u, 0u);
    if (matched == 2u)
        return CODE_WORK_LIMIT;
    if (matched == 0u)
        return 21u;
    uint symbol = mem(row, B_VALUE_HI);
    for (uint domain = 0u; domain < 2u; ++domain)
    {
        uint kind = domain == 0u ? M_GENERIC_TYPE : M_GENERIC_CONST;
        uint inherited = inherited_count(index, scope, kind);
        uint required = domain == 0u ? method_type_count(row) : method_constant_count(row);
        uint own = count_generic(first, count, symbol, kind);
        if (required != inherited + own || !generic_slots_exact(first, count, symbol, kind, inherited, own))
            return 22u;
    }
    TypeWalk walk;
    walk.init();
    walk.push(mem(row, B_TYPE));
    for (uint other = first; other < first + count; ++other)
        if (mem(other, B_KIND) == M_PARAMETER && mem(other, B_VALUE_HI) == symbol)
            walk.push(mem(other, B_TYPE));
    return graph_failure(walk, index, scope != NO_SCOPE, scope, true, symbol);
}

// Trait implementation, generic member: the subject or an argument reaches
// it.
uint trait_generic_step(uint index, uint row)
{
    bool overflow = false;
    if (!parameter_reached(index, row, overflow))
        return overflow ? CODE_WORK_LIMIT : 8u;
    return 0u;
}

// Trait implementation, other member: its method, inherited header,
// prerequisites, receiver and signature graph.
uint trait_member_step(uint index, uint row, uint scope)
{
    uint first = impl(index, I_FIRST_MEMBER);
    uint count = impl(index, I_MEMBER_COUNT);
    uint kind = mem(row, B_KIND);
    uint symbol = mem(row, B_VALUE_HI);
    if (kind == M_PARAMETER && !has_method_symbol(first, count, symbol))
        return 9u;
    if (kind == M_IMPL_METHOD)
    {
        if (method_type_count(row) != inherited_count(index, scope, M_GENERIC_TYPE) ||
            method_constant_count(row) != inherited_count(index, scope, M_GENERIC_CONST))
            return 24u;
        if (member_has_owner_predicate(row))
            return 25u;
        uint matched = types_match(impl(index, I_SUBJECT), mem(row, B_RECEIVER), 0u, 0u, 0u);
        if (matched == 2u)
            return CODE_WORK_LIMIT;
        if (matched == 0u)
            return 21u;
    }
    return graph_of_root(index, mem(row, B_TYPE), scope);
}

void member_steps(uint row)
{
    uint owner = mem(row, B_OWNER);
    uint index = owner & ~OWNER_TAG;
    if ((owner & OWNER_TAG) == 0u || index >= count_of(S_IMPL))
        return;
    uint kind = mem(row, B_KIND);
    uint scope_code;
    uint scope = parameter_scope(index, scope_code);
    uint generic_step = 0u;
    uint member_step = 0u;
    if (impl(index, I_KIND) == IMPL_INHERENT)
    {
        if (is_generic_member(kind))
            generic_step = inherent_generic_step(index, row, scope);
        else if (kind == M_IMPL_METHOD)
            member_step = inherent_method_step(index, row, scope);
    }
    else if (impl(index, I_KIND) == IMPL_TRAIT)
    {
        if (is_generic_member(kind))
            generic_step = trait_generic_step(index, row);
        else
            member_step = trait_member_step(index, row, scope);
    }
    set_member_result(row, 0u, generic_step);
    set_member_result(row, 1u, member_step);
}

// Trait implementation method binding after its owner check: ownership,
// target and, for a trait of this unit, the bound signature against the
// trait's required method. Skipped when the binding has no owner or the
// trait checks before the bindings fail; the implementation pass reports
// those first.
uint binding_step(uint b, uint index)
{
    uint owner = OWNER_TAG | index;
    uint first = impl(index, I_FIRST_MEMBER);
    uint count = impl(index, I_MEMBER_COUNT);
    uint bindings = impl(index, I_FIRST_BINDING);
    uint member = bind(b, N_MEMBER);
    uint required = bind(b, N_REQUIRED);
    bool repeated = false;
    for (uint before = bindings; before < b; ++before)
        if (bind(before, N_MEMBER) == member || bind(before, N_REQUIRED) == required)
            repeated = true;
    if (bind(b, N_IMPL) != index || mem(member, B_OWNER) != owner || member < first ||
        member - first >= count || mem(member, B_KIND) != M_IMPL_METHOD || repeated ||
        required == INVALID || (required & SCOPE_MASK) != SCOPE_METHOD)
        return 31u;
    uint target = bind(b, N_TARGET_SYMBOL);
    bool target_matches = method_is_public(member)
        ? target == mem(member, B_VALUE_HI)
        : target != INVALID && (target & SCOPE_MASK) == SCOPE_PRIVATE_TARGET;
    if (bind(b, N_TARGET_LIBRARY) != library_id() || bind(b, N_TARGET_UNIT) != unit_id() || !target_matches)
        return 32u;
    if (impl(index, I_TRAIT_LIBRARY) != library_id() || impl(index, I_TRAIT_UNIT) != unit_id())
        return 0u;
    uint trait_decl = impl(index, I_TRAIT_DECL);
    uint arguments = impl(index, I_FIRST_ARG);
    uint argument_count = impl(index, I_ARG_COUNT);
    if (trait_decl >= count_of(S_DECL) || decl(trait_decl, D_KIND) != 10u || decl(trait_decl, D_NAMESPACE) != 3u)
        return 0u;
    uint header = decl(trait_decl, D_SIGNATURE);
    if (ty(header, Y_EDGE_COUNT) != argument_count)
        return 0u;
    uint header_edges = ty(header, Y_FIRST_EDGE);
    uint trait_first = decl(trait_decl, D_FIRST_MEMBER);
    uint trait_count = decl(trait_decl, D_MEMBER_COUNT);
    uint expected = INVALID;
    for (uint row = trait_first; row < trait_first + trait_count; ++row)
        if (mem(row, B_KIND) == M_TRAIT_METHOD && mem(row, B_VALUE_HI) == required)
            expected = row;
    if (expected == INVALID)
        return 33u;
    const uint generic_count_bits = 0x0fff0000u;
    if (method_type_count(expected) != 0u || method_constant_count(expected) != 0u ||
        (mem(expected, B_VALUE_LO) & ~generic_count_bits) != (mem(member, B_VALUE_LO) & ~generic_count_bits))
        return 34u;
    uint matched = types_match(mem(expected, B_TYPE), mem(member, B_TYPE), header_edges, arguments, argument_count);
    if (matched == 2u)
        return CODE_WORK_LIMIT;
    if (matched == 0u)
        return 34u;
    uint expected_symbol = mem(expected, B_VALUE_HI);
    uint method_symbol = mem(member, B_VALUE_HI);
    for (uint parameter = trait_first; parameter < trait_first + trait_count; ++parameter)
    {
        if (mem(parameter, B_KIND) != M_PARAMETER || mem(parameter, B_VALUE_HI) != expected_symbol)
            continue;
        uint actual = INVALID;
        for (uint row = first; row < first + count && actual == INVALID; ++row)
            if (mem(row, B_KIND) == M_PARAMETER && mem(row, B_VALUE_HI) == method_symbol &&
                mem(row, B_VALUE_LO) == mem(parameter, B_VALUE_LO))
                actual = row;
        if (actual == INVALID)
            return 35u;
        matched = types_match(mem(parameter, B_TYPE), mem(actual, B_TYPE), header_edges, arguments, argument_count);
        if (matched == 2u)
            return CODE_WORK_LIMIT;
        if (matched == 0u)
            return 36u;
    }
    return 0u;
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint row = walk_thread_index(gid, ltid);
    if (!framed() || validate_state[STATE_KEY] != INVALID)
        return;
    if (row < count_of(S_MEMBER))
        member_steps(row);
    if (row < count_of(S_BIND))
    {
        uint index = bind_owner(row);
        if (index < count_of(S_IMPL))
            set_binding_result(row, binding_step(row, index));
    }
}

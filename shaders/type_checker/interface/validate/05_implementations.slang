import type_checker.interface.validate.common;

// Implementation records, one thread per implementation: inherent headers
// and their public methods, trait implementation heads, their lexical
// scopes, prerequisites, method bindings and, for a trait of this unit, the
// bound signatures against the trait's required methods.

static const uint NO_SCOPE = 0u;

// The exact lexical impl scope of implementation `index`: NO_SCOPE when it
// has none, or a failing check (13, 14) in `code`.
uint parameter_scope(uint index, out uint code)
{
    code = 0u;
    uint owner = OWNER_TAG | index;
    uint first = impl(index, I_FIRST_MEMBER);
    uint count = impl(index, I_MEMBER_COUNT);
    uint scope = NO_SCOPE;
    bool mixed = false;
    for (uint row = first; row < first + count; ++row)
    {
        uint value = mem(row, B_VALUE_HI);
        if (is_generic_member(mem(row, B_KIND)) && (value & SCOPE_MASK) == SCOPE_IMPL)
        {
            if (scope != NO_SCOPE && scope != value)
                mixed = true;
            scope = value;
        }
    }
    uint prerequisites = impl(index, I_FIRST_PREREQ);
    uint prerequisite_count = impl(index, I_PREREQ_COUNT);
    for (uint row = prerequisites; row < prerequisites + prerequisite_count; ++row)
    {
        uint symbol = pred(row, P_SCOPE);
        if (pred(row, P_OWNER) != owner || symbol == INVALID || (symbol & SCOPE_MASK) != SCOPE_IMPL)
        {
            code = 13u;
            return NO_SCOPE;
        }
        if (scope != NO_SCOPE && scope != symbol)
            mixed = true;
        scope = symbol;
    }
    // Every scope has the impl tag, so none is NO_SCOPE; INVALID is one.
    if (mixed || scope == INVALID)
        code = 14u;
    return scope;
}

// The graph checks of validate_implementation_graph over the nodes the
// walk reaches: 0, 15 (unresolved identity), 16 (foreign parameter) or
// CODE_WORK_LIMIT. A parameter's scope must be one of the two given.
uint graph_failure(inout TypeWalk walk, uint index, bool has_a, uint scope_a, bool has_b, uint scope_b)
{
    uint owner = OWNER_TAG | index;
    for (uint node = walk.next(); node != INVALID; node = walk.next())
    {
        uint kind = ty(node, Y_KIND);
        if ((kind == T_SCALAR && !scalar_is_known(ty(node, Y_PAYLOAD_LO))) ||
            (kind == T_DECL && (ty(node, Y_PAYLOAD_LO) == INVALID || ty(node, Y_NOMINAL_UNIT) == INVALID ||
                ty(node, Y_PAYLOAD_HI) == INVALID)))
            return 15u;
        if (is_parameter_leaf(kind))
        {
            uint member = ty(node, Y_PAYLOAD_LO);
            uint scope = mem(member, B_VALUE_HI);
            if (mem(member, B_OWNER) != owner || !((has_a && scope == scope_a) || (has_b && scope == scope_b)))
                return 16u;
        }
    }
    return walk.overflow ? CODE_WORK_LIMIT : 0u;
}

uint graph_of_root(uint index, uint root, uint scope)
{
    TypeWalk walk;
    walk.init();
    walk.push(root);
    return graph_failure(walk, index, scope != NO_SCOPE, scope, false, 0u);
}

// validate_implementation_prerequisites: a predicate of this owner in the
// impl scope lies in the prerequisite range and has the impl's own scope.
bool prerequisites_owned(uint index, uint scope)
{
    uint owner = OWNER_TAG | index;
    uint first = impl(index, I_FIRST_PREREQ);
    uint count = impl(index, I_PREREQ_COUNT);
    for (uint row = 0u; row < count_of(S_PRED); ++row)
    {
        uint symbol = pred(row, P_SCOPE);
        if (pred(row, P_OWNER) == owner && (symbol & SCOPE_MASK) == SCOPE_IMPL &&
            (row < first || row - first >= count || scope == NO_SCOPE || symbol != scope))
            return false;
    }
    return true;
}

bool has_method_symbol(uint first, uint count, uint symbol)
{
    for (uint row = first; row < first + count; ++row)
        if (mem(row, B_KIND) == M_IMPL_METHOD && mem(row, B_VALUE_HI) == symbol)
            return true;
    return false;
}

uint count_generic(uint first, uint count, uint scope, uint kind)
{
    uint n = 0u;
    for (uint row = first; row < first + count; ++row)
        if (mem(row, B_KIND) == kind && mem(row, B_VALUE_HI) == scope)
            n += 1u;
    return n;
}

bool generic_slots_exact(uint first, uint count, uint scope, uint kind, uint first_slot, uint n)
{
    for (uint row = first; row < first + count; ++row)
    {
        if (mem(row, B_KIND) != kind || mem(row, B_VALUE_HI) != scope)
            continue;
        uint slot = member_slot(row);
        if (slot < first_slot || slot - first_slot >= n)
            return false;
        for (uint other = first; other < row; ++other)
            if (mem(other, B_KIND) == kind && mem(other, B_VALUE_HI) == scope && member_slot(other) == slot)
                return false;
    }
    return true;
}

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
        if (is_generic_member(mem(row, B_KIND)))
        {
            uint value = mem(row, B_VALUE_HI);
            if (!(scope != NO_SCOPE && value == scope) && !has_method_symbol(first, count, value))
                return 17u;
        }
    uint inherited_types = 0u;
    uint inherited_constants = 0u;
    for (uint domain = 0u; domain < 2u; ++domain)
    {
        uint kind = domain == 0u ? M_GENERIC_TYPE : M_GENERIC_CONST;
        uint n = scope == NO_SCOPE ? 0u : count_generic(first, count, scope, kind);
        if (n > 32u || (n != 0u && !generic_slots_exact(first, count, scope, kind, 0u, n)))
            return 18u;
        if (domain == 0u)
            inherited_types = n;
        else
            inherited_constants = n;
    }
    for (uint row = first; row < first + count; ++row)
    {
        if (mem(row, B_KIND) != M_IMPL_METHOD)
            continue;
        // implementation_method_target on an inherent owner: the identity
        // checks repeat earlier phases; the public target contract remains.
        if (!method_is_public(row))
            return 20u;
        uint matched = types_match(subject, mem(row, B_RECEIVER), 0u, 0u, 0u);
        if (matched == 2u)
            return CODE_WORK_LIMIT;
        if (matched == 0u)
            return 21u;
        uint symbol = mem(row, B_VALUE_HI);
        for (uint domain = 0u; domain < 2u; ++domain)
        {
            uint kind = domain == 0u ? M_GENERIC_TYPE : M_GENERIC_CONST;
            uint required = domain == 0u ? method_type_count(row) : method_constant_count(row);
            uint own = count_generic(first, count, symbol, kind);
            if (required != (domain == 0u ? inherited_types : inherited_constants) + own ||
                !generic_slots_exact(first, count, symbol, kind, (domain == 0u ? inherited_types : inherited_constants), own))
                return 22u;
        }
        TypeWalk walk;
        walk.init();
        walk.push(mem(row, B_TYPE));
        for (uint other = first; other < first + count; ++other)
            if (mem(other, B_KIND) == M_PARAMETER && mem(other, B_VALUE_HI) == symbol)
                walk.push(mem(other, B_TYPE));
        code = graph_failure(walk, index, scope != NO_SCOPE, scope, true, symbol);
        if (code != 0u)
            return code;
    }
    if (!prerequisites_owned(index, scope))
        return 23u;
    return 0u;
}

// Whether the generic parameter member `parameter` is reached from the
// implementation's subject and argument roots.
bool parameter_reached(uint index, uint parameter, out bool overflow)
{
    overflow = false;
    TypeWalk walk;
    walk.init();
    walk.push(impl(index, I_SUBJECT));
    uint first = impl(index, I_FIRST_ARG);
    uint count = impl(index, I_ARG_COUNT);
    for (uint k = 0u; k < count; ++k)
        walk.push(iarg(first + k));
    for (uint node = walk.next(); node != INVALID; node = walk.next())
        if (is_parameter_leaf(ty(node, Y_KIND)) && ty(node, Y_PAYLOAD_LO) == parameter)
            return true;
    overflow = walk.overflow;
    return false;
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
    uint inherited_types = 0u;
    uint inherited_constants = 0u;
    for (uint domain = 0u; domain < 2u; ++domain)
    {
        uint kind = domain == 0u ? M_GENERIC_TYPE : M_GENERIC_CONST;
        uint n = 0u;
        for (uint row = first; row < first + count; ++row)
            if (mem(row, B_KIND) == kind)
                n += 1u;
        if (n > 32u || (n != 0u && !generic_slots_exact(first, count, scope, kind, 0u, n)))
            return 7u;
        if (domain == 0u)
            inherited_types = n;
        else
            inherited_constants = n;
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
    {
        if (!is_generic_member(mem(row, B_KIND)))
            continue;
        bool overflow = false;
        if (!parameter_reached(index, row, overflow))
            return overflow ? CODE_WORK_LIMIT : 8u;
    }
    if (!prerequisites_owned(index, scope))
        return 23u;
    for (uint row = first; row < first + count; ++row)
    {
        uint kind = mem(row, B_KIND);
        if (is_generic_member(kind))
            continue;
        uint symbol = mem(row, B_VALUE_HI);
        if (kind == M_PARAMETER && !has_method_symbol(first, count, symbol))
            return 9u;
        if (kind == M_IMPL_METHOD)
        {
            if (method_type_count(row) != inherited_types || method_constant_count(row) != inherited_constants)
                return 24u;
            for (uint p = 0u; p < count_of(S_PRED); ++p)
                if (pred(p, P_OWNER) == owner && pred(p, P_SCOPE) == symbol)
                    return 25u;
            uint matched = types_match(subject, mem(row, B_RECEIVER), 0u, 0u, 0u);
            if (matched == 2u)
                return CODE_WORK_LIMIT;
            if (matched == 0u)
                return 21u;
        }
        code = graph_of_root(index, mem(row, B_TYPE), scope);
        if (code != 0u)
            return code;
    }
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
        if (!local_trait)
            continue;
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

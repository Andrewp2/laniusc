import type_checker.interface.validate.common;

// Checks over each owner's member inventory: the operand domains of local
// nominal applications, trait headers, method identities, the lexical
// ownership and declaration order of generic parameters, and every method's
// parameter, requirement and signature-graph contract. One thread per type,
// declaration and member row.
//
// Members of one owner lie in that owner's member range (checked before
// these kernels run), so a per-owner set is a scan of that range.

uint count_scoped(uint first, uint count, uint scope, uint kind)
{
    uint n = 0u;
    for (uint row = first; row < first + count; ++row)
        if (mem(row, B_VALUE_HI) == scope && mem(row, B_KIND) == kind)
            n += 1u;
    return n;
}

// Whether the slots of the owner's (scope, kind) members are exactly
// first_slot .. first_slot + n without repeats.
bool slots_exact(uint first, uint count, uint scope, uint kind, uint first_slot, uint n)
{
    for (uint row = first; row < first + count; ++row)
    {
        if (mem(row, B_VALUE_HI) != scope || mem(row, B_KIND) != kind)
            continue;
        uint slot = member_slot(row);
        if (slot < first_slot || slot - first_slot >= n)
            return false;
        for (uint other = first; other < row; ++other)
            if (mem(other, B_VALUE_HI) == scope && mem(other, B_KIND) == kind && member_slot(other) == slot)
                return false;
    }
    return true;
}

bool has_method(uint first, uint count, uint symbol)
{
    for (uint row = first; row < first + count; ++row)
    {
        uint kind = mem(row, B_KIND);
        if ((kind == M_TRAIT_METHOD || kind == M_IMPL_METHOD) && mem(row, B_VALUE_HI) == symbol)
            return true;
    }
    return false;
}

void check_nominal(uint row)
{
    if (ty(row, Y_KIND) != T_DECL || ty(row, Y_PAYLOAD_LO) != library_id() || ty(row, Y_NOMINAL_UNIT) != unit_id())
        return;
    uint declaration = ty(row, Y_PAYLOAD_HI);
    uint first = decl(declaration, D_FIRST_MEMBER);
    uint count = decl(declaration, D_MEMBER_COUNT);
    if (!range_ok(first, count, count_of(S_MEMBER)))
    {
        fail(PH_NOMINAL, row, 1u);
        return;
    }
    uint arity = ty(row, Y_EDGE_COUNT);
    if (header_parameter_count(first, count) != arity)
    {
        fail(PH_NOMINAL, row, 2u);
        return;
    }
    uint edges = ty(row, Y_FIRST_EDGE);
    for (uint ordinal = 0u; ordinal < arity; ++ordinal)
        if (!parameter_operand_domain_matches(header_parameter_at(first, count, ordinal), edge(edges + ordinal)))
        {
            fail(PH_NOMINAL, row, 3u);
            return;
        }
}

void check_trait_header(uint row)
{
    if (decl(row, D_KIND) != 10u)
        return;
    uint signature = decl(row, D_SIGNATURE);
    uint first = decl(row, D_FIRST_MEMBER);
    uint count = decl(row, D_MEMBER_COUNT);
    uint parameters = header_parameter_count(first, count);
    if (ty(signature, Y_KIND) != T_DECL || ty(signature, Y_PAYLOAD_LO) != library_id() ||
        ty(signature, Y_NOMINAL_UNIT) != unit_id() || ty(signature, Y_PAYLOAD_HI) != row ||
        parameters > 32u || ty(signature, Y_EDGE_COUNT) != parameters)
    {
        fail(PH_TRAIT_HEADERS, row, 1u);
        return;
    }
    uint edges = ty(signature, Y_FIRST_EDGE);
    for (uint ordinal = 0u; ordinal < parameters; ++ordinal)
    {
        uint member = header_parameter_at(first, count, ordinal);
        uint leaf = edge(edges + ordinal);
        uint expected = mem(member, B_KIND) == M_GENERIC_TYPE ? T_GENERIC : T_CONST_PARAM;
        if (mem(member, B_GENERIC_ORDINAL) != ordinal || ty(leaf, Y_KIND) != expected ||
            ty(leaf, Y_PAYLOAD_LO) != member)
        {
            fail(PH_TRAIT_HEADERS, row, 2u);
            return;
        }
    }
}

void check_method_identity(uint row)
{
    uint symbol = mem(row, B_VALUE_HI);
    if ((symbol & SCOPE_MASK) != SCOPE_METHOD || (mem(row, B_VALUE_LO) >> 31u) != 0u ||
        method_type_count(row) > 32u || method_constant_count(row) > 32u ||
        symbol_first_row(symbol) != row)
        fail(PH_METHODS, row, 1u);
}

void check_generic_parameter(uint row, uint first, uint count)
{
    uint owner = mem(row, B_OWNER);
    uint scope = mem(row, B_VALUE_HI);
    uint scope_kind = scope & SCOPE_MASK;
    if (scope_kind == SCOPE_IMPL)
    {
        bool implementation = (owner & OWNER_TAG) != 0u;
        uint kind = implementation ? impl(owner & ~OWNER_TAG, I_KIND) : 0u;
        if (!implementation || (kind != IMPL_INHERENT && kind != IMPL_TRAIT))
        {
            fail(PH_GENERIC_PARAMS, row, 1u);
            return;
        }
    }
    bool duplicate = false;
    uint kind = mem(row, B_KIND);
    uint slot = member_slot(row);
    for (uint other = first; other < row; ++other)
        if (mem(other, B_KIND) == kind && mem(other, B_VALUE_HI) == scope && member_slot(other) == slot)
            duplicate = true;
    if ((scope != 0u && (scope_kind == 0u || scope_kind == SCOPE_PRIVATE_TARGET)) || scope == INVALID ||
        (scope_kind == SCOPE_METHOD && !has_method(first, count, scope)) || duplicate)
    {
        fail(PH_GENERIC_PARAMS, row, 2u);
        return;
    }
}

// The generic declaration order of one (owner, scope) group is exactly
// 0 .. n.
void check_parameter_order(uint row, uint first, uint count)
{
    uint scope = mem(row, B_VALUE_HI);
    uint ordinal = mem(row, B_GENERIC_ORDINAL);
    uint n = 0u;
    bool repeated = false;
    for (uint other = first; other < first + count; ++other)
    {
        if (!is_generic_member(mem(other, B_KIND)) || mem(other, B_VALUE_HI) != scope)
            continue;
        n += 1u;
        if (other != row && mem(other, B_GENERIC_ORDINAL) == ordinal)
            repeated = true;
    }
    if (ordinal >= n || repeated)
        fail(PH_PARAM_ORDERS, row, 1u);
}

void check_method_signature(uint row, uint first, uint count)
{
    uint owner = mem(row, B_OWNER);
    uint symbol = mem(row, B_VALUE_HI);
    bool trait_method = mem(row, B_KIND) == M_TRAIT_METHOD;
    uint parameters = count_scoped(first, count, symbol, M_PARAMETER);
    if (parameters != method_parameter_count(row))
    {
        fail(PH_METHOD_SIGNATURES, row, 1u);
        return;
    }
    if (parameters != 0u)
    {
        uint least = INVALID;
        for (uint other = first; other < first + count; ++other)
            if (mem(other, B_VALUE_HI) == symbol && mem(other, B_KIND) == M_PARAMETER)
                least = min(least, mem(other, B_VALUE_LO));
        uint mode = method_receiver_mode(row);
        uint expected_first = (mode == 1u || mode == 2u) ? 1u : 0u;
        bool complete = least == expected_first;
        for (uint other = first; complete && other < first + count; ++other)
        {
            if (mem(other, B_VALUE_HI) != symbol || mem(other, B_KIND) != M_PARAMETER)
                continue;
            uint value = mem(other, B_VALUE_LO);
            if (value - least >= parameters)
                complete = false;
            for (uint before = first; complete && before < other; ++before)
                if (mem(before, B_VALUE_HI) == symbol && mem(before, B_KIND) == M_PARAMETER &&
                    mem(before, B_VALUE_LO) == value)
                    complete = false;
        }
        if (!complete)
        {
            fail(PH_METHOD_SIGNATURES, row, 2u);
            return;
        }
    }
    for (uint domain = 0u; domain < 2u; ++domain)
    {
        uint kind = domain == 0u ? M_GENERIC_TYPE : M_GENERIC_CONST;
        uint required = domain == 0u ? method_type_count(row) : method_constant_count(row);
        uint n = count_scoped(first, count, symbol, kind);
        if ((trait_method && n != required) || n > required ||
            !slots_exact(first, count, symbol, kind, required - n, n))
        {
            fail(PH_METHOD_SIGNATURES, row, 3u);
            return;
        }
    }
    TypeWalk walk;
    walk.init();
    walk.push(mem(row, B_TYPE));
    if (mem(row, B_RECEIVER) != INVALID)
        walk.push(mem(row, B_RECEIVER));
    for (uint other = first; other < first + count; ++other)
        if (mem(other, B_VALUE_HI) == symbol && mem(other, B_KIND) == M_PARAMETER)
            walk.push(mem(other, B_TYPE));
    uint impl_scope = INVALID;
    for (uint node = walk.next(); node != INVALID; node = walk.next())
    {
        if (!is_parameter_leaf(ty(node, Y_KIND)))
            continue;
        uint member = ty(node, Y_PAYLOAD_LO);
        uint scope = mem(member, B_VALUE_HI);
        uint required = mem(member, B_KIND) == M_GENERIC_TYPE ? method_type_count(row) : method_constant_count(row);
        bool trait_parameter = trait_method && scope == 0u;
        if (mem(member, B_OWNER) != owner ||
            (!trait_parameter && (scope == 0u || member_slot(member) >= required ||
                ((scope & SCOPE_MASK) == SCOPE_METHOD && scope != symbol))) ||
            (trait_method && (scope & SCOPE_MASK) == SCOPE_IMPL))
        {
            fail(PH_METHOD_SIGNATURES, row, 4u);
            return;
        }
        if ((scope & SCOPE_MASK) == SCOPE_IMPL)
        {
            if (impl_scope != INVALID && impl_scope != scope)
            {
                fail(PH_METHOD_SIGNATURES, row, 5u);
                return;
            }
            impl_scope = scope;
        }
    }
    if (walk.overflow)
        fail(PH_METHOD_SIGNATURES, row, CODE_WORK_LIMIT);
}

void check_member_scopes(uint row)
{
    uint owner = mem(row, B_OWNER);
    uint first;
    uint count;
    owner_member_range(owner, first, count);
    uint kind = mem(row, B_KIND);
    uint scope = mem(row, B_VALUE_HI);
    bool method = kind == M_TRAIT_METHOD || kind == M_IMPL_METHOD;
    if (method)
        check_method_identity(row);
    if (scope != 0u && kind == M_PARAMETER && !has_method(first, count, scope))
        fail(PH_SCOPED_PARAMS, row, 1u);
    if (is_generic_member(kind))
    {
        check_generic_parameter(row, first, count);
        check_parameter_order(row, first, count);
    }
    if (method)
        check_method_signature(row, first, count);
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint row = walk_thread_index(gid, ltid);
    // Every record passed its own checks before these run; a failed record
    // check already holds a smaller key.
    if (!framed() || validate_state[STATE_KEY] != INVALID)
        return;
    if (row < count_of(S_TYPE))
        check_nominal(row);
    if (row < count_of(S_DECL))
        check_trait_header(row);
    if (row < count_of(S_MEMBER))
        check_member_scopes(row);
}

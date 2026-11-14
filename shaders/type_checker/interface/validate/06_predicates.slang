import type_checker.interface.validate.common;

// Callable predicates (one thread per predicate), checked C declarations
// (one per declaration), and the ownership of every implementation
// argument, method binding and predicate argument row (one per row).

static const uint NATIVE_ABI_C = 1u;
static const uint DECL_FLAG_NATIVE_C = 2u;
static const uint NATIVE_C_MAX_PARAMETERS = 32u;

// The implementation's lexical impl scope, or 0. The implementation checks
// already passed, so the scope is well formed.
uint implementation_scope(uint index)
{
    uint scope = 0u;
    uint first = impl(index, I_FIRST_MEMBER);
    uint count = impl(index, I_MEMBER_COUNT);
    for (uint row = first; row < first + count; ++row)
        if (is_generic_member(mem(row, B_KIND)) && (mem(row, B_VALUE_HI) & SCOPE_MASK) == SCOPE_IMPL)
            scope = mem(row, B_VALUE_HI);
    uint prerequisites = impl(index, I_FIRST_PREREQ);
    uint prerequisite_count = impl(index, I_PREREQ_COUNT);
    for (uint row = prerequisites; row < prerequisites + prerequisite_count; ++row)
        scope = pred(row, P_SCOPE);
    return scope;
}

// One declaration scope of a callable predicate: the scope's type slots
// start at type_start and its constant slots at constant_start, each
// complete and without repeats.
bool declaration_scope_complete(uint first, uint count, uint scope, uint method)
{
    uint types = 0u;
    uint constants = 0u;
    for (uint row = first; row < first + count; ++row)
    {
        if (mem(row, B_VALUE_HI) != scope)
            continue;
        if (mem(row, B_KIND) == M_GENERIC_TYPE)
            types += 1u;
        else if (mem(row, B_KIND) == M_GENERIC_CONST)
            constants += 1u;
    }
    if (types > 32u || constants > 32u)
        return false;
    uint type_start = 0u;
    uint constant_start = types;
    if (scope != 0u)
    {
        uint type_count = method_type_count(method);
        uint constant_count = method_constant_count(method);
        type_start = type_count > types ? type_count - types : 0u;
        constant_start = constant_count > constants ? constant_count - constants : 0u;
    }
    for (uint domain = 0u; domain < 2u; ++domain)
    {
        uint kind = domain == 0u ? M_GENERIC_TYPE : M_GENERIC_CONST;
        uint start = domain == 0u ? type_start : constant_start;
        uint n = domain == 0u ? types : constants;
        for (uint row = first; row < first + count; ++row)
        {
            if (mem(row, B_VALUE_HI) != scope || mem(row, B_KIND) != kind)
                continue;
            uint slot = member_slot(row);
            if (slot < start || slot - start >= n)
                return false;
            for (uint other = first; other < row; ++other)
                if (mem(other, B_VALUE_HI) == scope && mem(other, B_KIND) == kind && member_slot(other) == slot)
                    return false;
        }
    }
    return true;
}

uint check_predicate(uint index)
{
    uint owner = pred(index, P_OWNER);
    if (!owner_valid(owner))
        return 1u;
    uint first;
    uint count;
    owner_member_range(owner, first, count);
    uint symbol = pred(index, P_SCOPE);
    // predicate_callable_scopes: up to two scopes.
    bool has_a = false;
    uint scope_a = 0u;
    bool has_b = false;
    uint scope_b = 0u;
    if ((owner & OWNER_TAG) == 0u)
    {
        uint method = INVALID;
        if (symbol == 0u)
        {
            if (decl(owner, D_KIND) != 4u || decl(owner, D_NAMESPACE) != 2u ||
                ty(decl(owner, D_SIGNATURE), Y_KIND) != T_FUNCTION)
                return 2u;
        }
        else
        {
            for (uint row = first; row < first + count && method == INVALID; ++row)
                if (mem(row, B_KIND) == M_TRAIT_METHOD && mem(row, B_VALUE_HI) == symbol)
                    method = row;
            if (method == INVALID)
                return 3u;
        }
        has_a = true;
        scope_a = 0u;
        if (method != INVALID)
        {
            has_b = true;
            scope_b = mem(method, B_VALUE_HI);
        }
        if (!declaration_scope_complete(first, count, 0u, method) ||
            (has_b && scope_b != 0u && !declaration_scope_complete(first, count, scope_b, method)))
            return 10u;
    }
    else
    {
        uint implementation = owner & ~OWNER_TAG;
        uint scope = implementation_scope(implementation);
        if (scope != 0u)
        {
            has_a = true;
            scope_a = scope;
        }
        if (scope != 0u && symbol == scope)
        {
            uint prerequisites = impl(implementation, I_FIRST_PREREQ);
            if (index < prerequisites || index - prerequisites >= impl(implementation, I_PREREQ_COUNT))
                return 7u;
        }
        else
        {
            if (impl(implementation, I_KIND) != IMPL_INHERENT)
                return 8u;
            uint method = INVALID;
            for (uint row = first; row < first + count && method == INVALID; ++row)
                if (mem(row, B_KIND) == M_IMPL_METHOD && mem(row, B_VALUE_HI) == symbol)
                    method = row;
            if (method == INVALID)
                return 9u;
            has_b = true;
            scope_b = mem(method, B_VALUE_HI);
        }
    }
    uint subject = pred(index, P_SUBJECT);
    if (subject >= count_of(S_TYPE))
        return 11u;
    if (is_constant_kind(ty(subject, Y_KIND)))
        return 12u;
    if (pred(index, P_TRAIT_LIBRARY) == INVALID || pred(index, P_TRAIT_UNIT) == INVALID ||
        pred(index, P_TRAIT_DECL) == INVALID)
        return 13u;
    uint argument_count = pred(index, P_ARG_COUNT);
    if (argument_count > 32u)
        return 14u;
    uint arguments = pred(index, P_FIRST_ARG);
    if (!range_ok(arguments, argument_count, count_of(S_PARG)))
        return 15u;
    for (uint row = arguments; row < arguments + argument_count; ++row)
    {
        if (parg_owner(row) != index)
            return 16u;
        if (parg(row) >= count_of(S_TYPE))
            return 17u;
    }
    if (pred(index, P_TRAIT_LIBRARY) == library_id() && pred(index, P_TRAIT_UNIT) == unit_id())
    {
        uint trait_decl = pred(index, P_TRAIT_DECL);
        if (trait_decl >= count_of(S_DECL))
            return 18u;
        if (decl(trait_decl, D_KIND) != 10u || decl(trait_decl, D_NAMESPACE) != 3u)
            return 19u;
        uint header = decl(trait_decl, D_SIGNATURE);
        if (ty(header, Y_EDGE_COUNT) != argument_count)
            return 20u;
        uint header_edges = ty(header, Y_FIRST_EDGE);
        for (uint ordinal = 0u; ordinal < argument_count; ++ordinal)
            if (!parameter_operand_domain_matches(ty(edge(header_edges + ordinal), Y_PAYLOAD_LO),
                    parg(arguments + ordinal)))
                return 21u;
    }
    TypeWalk walk;
    walk.init();
    walk.push(subject);
    for (uint row = arguments; row < arguments + argument_count; ++row)
        walk.push(parg(row));
    for (uint node = walk.next(); node != INVALID; node = walk.next())
    {
        uint kind = ty(node, Y_KIND);
        if ((kind == T_SCALAR && !scalar_is_known(ty(node, Y_PAYLOAD_LO))) ||
            (kind == T_DECL && (ty(node, Y_PAYLOAD_LO) == INVALID || ty(node, Y_NOMINAL_UNIT) == INVALID ||
                ty(node, Y_PAYLOAD_HI) == INVALID)))
            return 22u;
        if (is_parameter_leaf(kind))
        {
            uint member = ty(node, Y_PAYLOAD_LO);
            uint scope = mem(member, B_VALUE_HI);
            if (mem(member, B_OWNER) != owner || !((has_a && scope == scope_a) || (has_b && scope == scope_b)))
                return 23u;
        }
    }
    return walk.overflow ? CODE_WORK_LIMIT : 0u;
}

bool native_c_scalar(uint scalar)
{
    return scalar == SCALAR_UNIT || scalar == SCALAR_I32 || scalar == SCALAR_U32 || scalar == SCALAR_I64 ||
        scalar == SCALAR_U64 || scalar == SCALAR_ISIZE || scalar == SCALAR_USIZE || scalar == SCALAR_PTR ||
        scalar == SCALAR_F32 || scalar == SCALAR_F64;
}

// The C type of one signature leaf as native_c_type sees it: a supported
// scalar (returned), a one-field record of this unit passed as its integer
// or pointer field (that field's scalar), or INVALID.
uint native_c_type(uint leaf)
{
    if (leaf >= count_of(S_TYPE))
        return INVALID;
    uint kind = ty(leaf, Y_KIND);
    if (kind == T_SCALAR)
        return native_c_scalar(ty(leaf, Y_PAYLOAD_LO)) ? ty(leaf, Y_PAYLOAD_LO) : INVALID;
    if (kind != T_DECL || ty(leaf, Y_PAYLOAD_LO) != library_id() || ty(leaf, Y_NOMINAL_UNIT) != unit_id() ||
        ty(leaf, Y_EDGE_COUNT) != 0u)
        return INVALID;
    uint record = ty(leaf, Y_PAYLOAD_HI);
    if (record >= count_of(S_DECL) || decl(record, D_MEMBER_COUNT) != 1u)
        return INVALID;
    uint field_row = decl(record, D_FIRST_MEMBER);
    if (field_row >= count_of(S_MEMBER) || mem(field_row, B_KIND) != M_FIELD)
        return INVALID;
    uint field_type = mem(field_row, B_TYPE);
    if (field_type >= count_of(S_TYPE) || ty(field_type, Y_KIND) != T_SCALAR)
        return INVALID;
    uint scalar = ty(field_type, Y_PAYLOAD_LO);
    if (!native_c_scalar(scalar) || scalar == SCALAR_UNIT || scalar == SCALAR_F32 || scalar == SCALAR_F64)
        return INVALID;
    return scalar;
}

bool native_c_valid(uint row)
{
    if (decl(row, D_KIND) != 5u || decl(row, D_NAMESPACE) != 2u || decl(row, D_VALUE_HI) != NATIVE_ABI_C ||
        decl(row, D_VALUE_LO) != INVALID || decl(row, D_OWNER) != INVALID)
        return false;
    uint signature = decl(row, D_SIGNATURE);
    uint edges = ty(signature, Y_EDGE_COUNT);
    if (ty(signature, Y_KIND) != T_FUNCTION || edges == 0u || edges > NATIVE_C_MAX_PARAMETERS + 1u)
        return false;
    uint first = ty(signature, Y_FIRST_EDGE);
    for (uint k = 0u; k < edges; ++k)
    {
        uint scalar = native_c_type(edge(first + k));
        if (scalar == INVALID || (k + 1u < edges && scalar == SCALAR_UNIT))
            return false;
    }
    uint members = decl(row, D_FIRST_MEMBER);
    if (decl(row, D_MEMBER_COUNT) != edges - 1u)
        return false;
    for (uint k = 0u; k < edges - 1u; ++k)
        if (mem(members + k, B_KIND) != M_PARAMETER)
            return false;
    uint name = decl(row, D_NAME_START);
    uint len = decl(row, D_NAME_LEN);
    if (len == 0u)
        return false;
    for (uint k = 0u; k < len; ++k)
        if (name_byte(name + k) == 0u)
            return false;
    return true;
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint row = walk_thread_index(gid, ltid);
    if (!framed() || validate_state[STATE_KEY] != INVALID)
        return;
    // Unowned rows fail after every implementation and every predicate.
    if (row < count_of(S_IARG) && iarg_owner(row) == INVALID)
        fail(PH_IMPLEMENTATIONS, ROW_LIMIT, 38u);
    if (row < count_of(S_BIND) && bind_owner(row) == INVALID)
        fail(PH_IMPLEMENTATIONS, ROW_LIMIT, 38u);
    if (row < count_of(S_PARG) && parg_owner(row) == INVALID)
        fail(PH_PREDICATES, ROW_LIMIT, 24u);
    if (row < count_of(S_PRED))
    {
        uint code = check_predicate(row);
        if (code != 0u)
            fail(PH_PREDICATES, row, code);
    }
    if (row < count_of(S_DECL) && (decl(row, D_FLAGS) & DECL_FLAG_NATIVE_C) != 0u && !native_c_valid(row))
        fail(PH_NATIVE_C, row, 1u);
}

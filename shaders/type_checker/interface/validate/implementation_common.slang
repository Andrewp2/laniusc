__exported import type_checker.interface.validate.common;

// Implementation checks shared by the implementation row pass
// (04a_implementation_rows) and the implementation pass
// (05_implementations).

public static const uint NO_SCOPE = 0u;

// The exact lexical impl scope of implementation `index`: NO_SCOPE when it
// has none, or a failing check (13, 14) in `code`.
public uint parameter_scope(uint index, out uint code)
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
public uint graph_failure(inout TypeWalk walk, uint index, bool has_a, uint scope_a, bool has_b, uint scope_b)
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

public uint graph_of_root(uint index, uint root, uint scope)
{
    TypeWalk walk;
    walk.init();
    walk.push(root);
    return graph_failure(walk, index, scope != NO_SCOPE, scope, false, 0u);
}

// validate_implementation_prerequisites: a predicate of this owner in the
// impl scope lies in the prerequisite range and has the impl's own scope.
public bool prerequisites_owned(uint index, uint scope)
{
    uint least_row = impl_predicate_summary(index, 0u);
    if (least_row == INVALID)
        return true;
    uint greatest_row = ~impl_predicate_summary(index, 1u);
    uint first = impl(index, I_FIRST_PREREQ);
    uint count = impl(index, I_PREREQ_COUNT);
    return least_row >= first && greatest_row - first < count && scope != NO_SCOPE &&
        impl_predicate_summary(index, 2u) == scope && ~impl_predicate_summary(index, 3u) == scope;
}

public bool has_method_symbol(uint first, uint count, uint symbol)
{
    for (uint row = first; row < first + count; ++row)
        if (mem(row, B_KIND) == M_IMPL_METHOD && mem(row, B_VALUE_HI) == symbol)
            return true;
    return false;
}

public uint count_generic(uint first, uint count, uint scope, uint kind)
{
    uint n = 0u;
    for (uint row = first; row < first + count; ++row)
        if (mem(row, B_KIND) == kind && mem(row, B_VALUE_HI) == scope)
            n += 1u;
    return n;
}

public bool generic_slots_exact(uint first, uint count, uint scope, uint kind, uint first_slot, uint n)
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

// Whether the generic parameter member `parameter` is reached from the
// implementation's subject and argument roots.
public bool parameter_reached(uint index, uint parameter, out bool overflow)
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

// The impl-scoped generic members an implementation's methods inherit, in
// one domain: an inherent implementation counts those of its own scope, a
// trait implementation every generic member of that kind.
public uint inherited_count(uint index, uint scope, uint kind)
{
    uint first = impl(index, I_FIRST_MEMBER);
    uint count = impl(index, I_MEMBER_COUNT);
    if (impl(index, I_KIND) == IMPL_TRAIT)
    {
        uint n = 0u;
        for (uint row = first; row < first + count; ++row)
            if (mem(row, B_KIND) == kind)
                n += 1u;
        return n;
    }
    return scope == NO_SCOPE ? 0u : count_generic(first, count, scope, kind);
}

// Row results of the implementation row pass: the first failing check of a
// member's generic-parameter step (0) and of its member step (1), and of a
// method binding. Zero when the row passed its step.
public uint member_result(uint row, uint step)
{ return validate_scratch[validate_state[STATE_MEMBER_RESULTS] + 2u * row + step]; }

public void set_member_result(uint row, uint step, uint code)
{ validate_scratch[validate_state[STATE_MEMBER_RESULTS] + 2u * row + step] = code; }

public uint binding_result(uint row)
{ return validate_scratch[validate_state[STATE_BINDING_RESULTS] + row]; }

public void set_binding_result(uint row, uint code)
{ validate_scratch[validate_state[STATE_BINDING_RESULTS] + row] = code; }

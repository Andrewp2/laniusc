import type_checker.interface.validation.interface_validation_tables;

// Checks over each owner's member inventory: the operand domains of local
// nominal applications, trait headers, method identities, the lexical
// ownership and declaration order of generic parameters, and every method's
// parameter, requirement and signature-graph contract. One workgroup of
// SCOPE_LANES lanes per type, declaration and member row.
//
// Members of one owner lie in that owner's member range (checked before
// these kernels run), so a per-owner set is a scan of that range. The lanes
// of a row's workgroup split each scan and combine their results, so a row
// of a large owner takes a few steps per scan instead of one per member.
// Every lane runs the row's checks in the same order and reaches the same
// result, so the workgroup takes each branch together; lane 0 reports.
// Only lane 0 walks a method's signature graph.

static const uint SCOPE_LANES = 32u;
static const uint OP_ADD = 0u;
static const uint OP_MIN = 1u;
static const uint OP_OR = 2u;

static uint g_lane = 0u;
groupshared uint g_reduce[SCOPE_LANES];
// The signature walk's stack (lane 0, after the lanes place the pushes).
groupshared uint g_stack[STACK_LIMIT];

// Combines one value per lane; every lane gets the result.
uint group_reduce(uint value, uint op)
{
    g_reduce[g_lane] = value;
    GroupMemoryBarrierWithGroupSync();
    uint result = g_reduce[0u];
    for (uint i = 1u; i < SCOPE_LANES; ++i)
    {
        uint other = g_reduce[i];
        result = op == OP_ADD ? result + other : (op == OP_MIN ? min(result, other) : (result | other));
    }
    GroupMemoryBarrierWithGroupSync();
    return result;
}

bool group_any(bool value)
{
    return group_reduce(value ? 1u : 0u, OP_OR) != 0u;
}

void report(uint phase, uint row, uint code)
{
    if (g_lane == 0u)
        fail(phase, row, code);
}

// A bit per value below 64: `bits` x for 0 .. 31, y for 32 .. 63.
void set_bit(inout uint2 bits, uint value)
{
    if (value < 32u)
        bits.x |= 1u << value;
    else
        bits.y |= 1u << (value - 32u);
}

// The number of distinct values below 64 the lanes marked.
uint group_distinct(uint2 bits)
{
    uint lo = group_reduce(bits.x, OP_OR);
    uint hi = group_reduce(bits.y, OP_OR);
    return countbits(lo) + countbits(hi);
}

uint count_scoped(uint first, uint count, uint scope, uint kind)
{
    uint n = 0u;
    for (uint row = first + g_lane; row < first + count; row += SCOPE_LANES)
        if (mem(row, B_VALUE_HI) == scope && mem(row, B_KIND) == kind)
            n += 1u;
    return group_reduce(n, OP_ADD);
}

// Whether the slots of the owner's n (scope, kind) members are exactly
// first_slot .. first_slot + n without repeats. n is below 64 (a method's
// generic counts have six bits).
bool slots_exact(uint first, uint count, uint scope, uint kind, uint first_slot, uint n)
{
    bool outside = false;
    uint2 bits = uint2(0u, 0u);
    for (uint row = first + g_lane; row < first + count; row += SCOPE_LANES)
    {
        if (mem(row, B_VALUE_HI) != scope || mem(row, B_KIND) != kind)
            continue;
        uint slot = member_slot(row);
        if (slot < first_slot || slot - first_slot >= n)
            outside = true;
        else
            set_bit(bits, slot - first_slot);
    }
    if (group_any(outside))
        return false;
    // The n members are in range; they repeat a slot exactly when they
    // cover fewer than n.
    return group_distinct(bits) == n;
}

bool has_method(uint first, uint count, uint symbol)
{
    bool found = false;
    for (uint row = first + g_lane; row < first + count; row += SCOPE_LANES)
    {
        uint kind = mem(row, B_KIND);
        if ((kind == M_TRAIT_METHOD || kind == M_IMPL_METHOD) && mem(row, B_VALUE_HI) == symbol)
            found = true;
    }
    return group_any(found);
}

// An owner's own generic header: its value_hi == 0 generic parameters,
// ranked by generic ordinal (ties by row), as header_parameter_at orders
// them.
bool is_header_parameter(uint row)
{
    return mem(row, B_VALUE_HI) == 0u && is_generic_member(mem(row, B_KIND));
}

uint header_count(uint first, uint count)
{
    uint n = 0u;
    for (uint row = first + g_lane; row < first + count; row += SCOPE_LANES)
        if (is_header_parameter(row))
            n += 1u;
    return group_reduce(n, OP_ADD);
}

// The ordinal header_parameter_at gives header parameter `row`.
uint header_rank(uint first, uint count, uint row)
{
    uint key = mem(row, B_GENERIC_ORDINAL);
    uint rank = 0u;
    for (uint other = first; other < first + count; ++other)
    {
        if (other == row || !is_header_parameter(other))
            continue;
        uint other_key = mem(other, B_GENERIC_ORDINAL);
        if (other_key < key || (other_key == key && other < row))
            rank += 1u;
    }
    return rank;
}

// The header has arity parameters, so their ranks are exactly
// 0 .. arity - 1 and each lane checks the ordinals of its own rows.
void check_nominal(uint row)
{
    if (ty(row, Y_KIND) != T_DECL || ty(row, Y_PAYLOAD_LO) != library_id() || ty(row, Y_NOMINAL_UNIT) != unit_id())
        return;
    uint declaration = ty(row, Y_PAYLOAD_HI);
    uint first = decl(declaration, D_FIRST_MEMBER);
    uint count = decl(declaration, D_MEMBER_COUNT);
    if (!range_ok(first, count, count_of(S_MEMBER)))
    {
        report(PH_NOMINAL, row, 1u);
        return;
    }
    uint arity = ty(row, Y_EDGE_COUNT);
    if (header_count(first, count) != arity)
    {
        report(PH_NOMINAL, row, 2u);
        return;
    }
    uint edges = ty(row, Y_FIRST_EDGE);
    bool mismatch = false;
    for (uint member = first + g_lane; member < first + count; member += SCOPE_LANES)
    {
        if (!is_header_parameter(member))
            continue;
        uint ordinal = header_rank(first, count, member);
        if (!parameter_operand_domain_matches(member, edge(edges + ordinal)))
            mismatch = true;
    }
    if (group_any(mismatch))
        report(PH_NOMINAL, row, 3u);
}

void check_trait_header(uint row)
{
    if (decl(row, D_KIND) != 10u)
        return;
    uint signature = decl(row, D_SIGNATURE);
    uint first = decl(row, D_FIRST_MEMBER);
    uint count = decl(row, D_MEMBER_COUNT);
    uint parameters = header_count(first, count);
    if (ty(signature, Y_KIND) != T_DECL || ty(signature, Y_PAYLOAD_LO) != library_id() ||
        ty(signature, Y_NOMINAL_UNIT) != unit_id() || ty(signature, Y_PAYLOAD_HI) != row ||
        parameters > 32u || ty(signature, Y_EDGE_COUNT) != parameters)
    {
        report(PH_TRAIT_HEADERS, row, 1u);
        return;
    }
    uint edges = ty(signature, Y_FIRST_EDGE);
    bool mismatch = false;
    for (uint member = first + g_lane; member < first + count; member += SCOPE_LANES)
    {
        if (!is_header_parameter(member))
            continue;
        uint ordinal = header_rank(first, count, member);
        uint leaf = edge(edges + ordinal);
        uint expected = mem(member, B_KIND) == M_GENERIC_TYPE ? T_GENERIC : T_CONST_PARAM;
        if (mem(member, B_GENERIC_ORDINAL) != ordinal || ty(leaf, Y_KIND) != expected ||
            ty(leaf, Y_PAYLOAD_LO) != member)
            mismatch = true;
    }
    if (group_any(mismatch))
        report(PH_TRAIT_HEADERS, row, 2u);
}

void check_method_identity(uint row)
{
    uint symbol = mem(row, B_VALUE_HI);
    if ((symbol & SCOPE_MASK) != SCOPE_METHOD || (mem(row, B_VALUE_LO) >> 31u) != 0u ||
        method_type_count(row) > 32u || method_constant_count(row) > 32u ||
        symbol_first_row(symbol) != row)
        report(PH_METHODS, row, 1u);
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
            report(PH_GENERIC_PARAMS, row, 1u);
            return;
        }
    }
    bool repeated = false;
    uint kind = mem(row, B_KIND);
    uint slot = member_slot(row);
    for (uint other = first + g_lane; other < row; other += SCOPE_LANES)
        if (mem(other, B_KIND) == kind && mem(other, B_VALUE_HI) == scope && member_slot(other) == slot)
            repeated = true;
    bool duplicate = group_any(repeated);
    bool unowned = scope_kind == SCOPE_METHOD && !has_method(first, count, scope);
    if ((scope != 0u && (scope_kind == 0u || scope_kind == SCOPE_PRIVATE_TARGET)) || scope == INVALID ||
        unowned || duplicate)
    {
        report(PH_GENERIC_PARAMS, row, 2u);
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
    for (uint other = first + g_lane; other < first + count; other += SCOPE_LANES)
    {
        if (!is_generic_member(mem(other, B_KIND)) || mem(other, B_VALUE_HI) != scope)
            continue;
        n += 1u;
        if (other != row && mem(other, B_GENERIC_ORDINAL) == ordinal)
            repeated = true;
    }
    n = group_reduce(n, OP_ADD);
    if (group_any(repeated) || ordinal >= n)
        report(PH_PARAM_ORDERS, row, 1u);
}

// The method's parameter positions are exactly least .. least + n with
// least the first position its receiver mode allows.
bool parameters_complete(uint row, uint first, uint count, uint symbol, uint parameters)
{
    uint least = INVALID;
    for (uint other = first + g_lane; other < first + count; other += SCOPE_LANES)
        if (mem(other, B_VALUE_HI) == symbol && mem(other, B_KIND) == M_PARAMETER)
            least = min(least, mem(other, B_VALUE_LO));
    least = group_reduce(least, OP_MIN);
    uint mode = method_receiver_mode(row);
    uint expected_first = (mode == 1u || mode == 2u) ? 1u : 0u;
    if (least != expected_first)
        return false;
    bool outside = false;
    bool repeated = false;
    uint2 bits = uint2(0u, 0u);
    for (uint other = first + g_lane; other < first + count; other += SCOPE_LANES)
    {
        if (mem(other, B_VALUE_HI) != symbol || mem(other, B_KIND) != M_PARAMETER)
            continue;
        uint value = mem(other, B_VALUE_LO);
        if (value - least >= parameters)
            outside = true;
        else if (parameters <= 64u)
            set_bit(bits, value - least);
        else
            for (uint before = first; before < other; ++before)
                if (mem(before, B_VALUE_HI) == symbol && mem(before, B_KIND) == M_PARAMETER &&
                    mem(before, B_VALUE_LO) == value)
                    repeated = true;
    }
    if (group_any(outside))
        return false;
    // The n parameters are in range; at most 64 repeat a position exactly
    // when they cover fewer than n.
    if (parameters <= 64u)
        return group_distinct(bits) == parameters;
    return !group_any(repeated);
}

void check_method_signature(uint row, uint first, uint count)
{
    uint owner = mem(row, B_OWNER);
    uint symbol = mem(row, B_VALUE_HI);
    bool trait_method = mem(row, B_KIND) == M_TRAIT_METHOD;
    uint parameters = count_scoped(first, count, symbol, M_PARAMETER);
    if (parameters != method_parameter_count(row))
    {
        report(PH_METHOD_SIGNATURES, row, 1u);
        return;
    }
    if (parameters != 0u && !parameters_complete(row, first, count, symbol, parameters))
    {
        report(PH_METHOD_SIGNATURES, row, 2u);
        return;
    }
    for (uint domain = 0u; domain < 2u; ++domain)
    {
        uint kind = domain == 0u ? M_GENERIC_TYPE : M_GENERIC_CONST;
        uint required = domain == 0u ? method_type_count(row) : method_constant_count(row);
        uint n = count_scoped(first, count, symbol, kind);
        if ((trait_method && n != required) || n > required ||
            !slots_exact(first, count, symbol, kind, required - n, n))
        {
            report(PH_METHOD_SIGNATURES, row, 3u);
            return;
        }
    }
    // The walk's pushes, in TypeWalk order: the method's type, its
    // receiver, then its parameters' types by row. A walk that pushes more
    // than the stack holds stops before its first node.
    uint depth = 1u;
    if (g_lane == 0u)
        g_stack[0u] = mem(row, B_TYPE);
    if (mem(row, B_RECEIVER) != INVALID)
    {
        if (g_lane == 0u)
            g_stack[1u] = mem(row, B_RECEIVER);
        depth = 2u;
    }
    for (uint chunk = first; chunk < first + count; chunk += SCOPE_LANES)
    {
        uint other = chunk + g_lane;
        bool pushed = other < first + count && mem(other, B_VALUE_HI) == symbol &&
            mem(other, B_KIND) == M_PARAMETER;
        g_reduce[g_lane] = pushed ? 1u : 0u;
        GroupMemoryBarrierWithGroupSync();
        uint before = 0u;
        uint total = 0u;
        for (uint i = 0u; i < SCOPE_LANES; ++i)
        {
            uint flag = g_reduce[i];
            if (i < g_lane)
                before += flag;
            total += flag;
        }
        GroupMemoryBarrierWithGroupSync();
        if (pushed && depth + before < STACK_LIMIT)
            g_stack[depth + before] = mem(other, B_TYPE);
        depth += total;
    }
    GroupMemoryBarrierWithGroupSync();
    if (depth > STACK_LIMIT)
    {
        report(PH_METHOD_SIGNATURES, row, CODE_WORK_LIMIT);
        return;
    }
    if (g_lane != 0u)
        return;
    uint visits = 0u;
    uint impl_scope = INVALID;
    while (depth != 0u)
    {
        visits += 1u;
        if (visits > VISIT_LIMIT)
        {
            fail(PH_METHOD_SIGNATURES, row, CODE_WORK_LIMIT);
            return;
        }
        depth -= 1u;
        uint node = g_stack[depth];
        uint edge_first = ty(node, Y_FIRST_EDGE);
        uint edge_count = ty(node, Y_EDGE_COUNT);
        // A push past the stack ends the walk after this node's own check,
        // as TypeWalk returns the node before it stops.
        bool overflow = false;
        for (uint k = 0u; k < edge_count && !overflow; ++k)
        {
            if (depth >= STACK_LIMIT)
                overflow = true;
            else
            {
                g_stack[depth] = edge(edge_first + k);
                depth += 1u;
            }
        }
        if (!is_parameter_leaf(ty(node, Y_KIND)))
        {
            if (overflow)
            {
                fail(PH_METHOD_SIGNATURES, row, CODE_WORK_LIMIT);
                return;
            }
            continue;
        }
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
        if (overflow)
        {
            fail(PH_METHOD_SIGNATURES, row, CODE_WORK_LIMIT);
            return;
        }
    }
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
        report(PH_SCOPED_PARAMS, row, 1u);
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
    g_lane = ltid.x;
    uint row = gid.x + gid.y * MAX_ROW_GROUPS_X;
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

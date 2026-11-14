import type_checker.interface.validate.common;

// Per-row checks of every record table, one thread per row of each table:
// module segment ranges, canonical names, declaration identities and
// signatures, implementation and method binding ranges, type records and
// their reverse-preorder topology, and member records.

static const uint DECL_FLAG_NATIVE_C = 2u;
static const uint DECL_FLAG_NATIVE_C_VARIADIC = 4u;

void check_module(uint row)
{
    if (!range_ok(word(start_of(S_MODULE) + 2u * row), word(start_of(S_MODULE) + 2u * row + 1u),
            count_of(S_SEGMENT)))
        fail(PH_MODULES, row, 1u);
}

void check_segment(uint row)
{
    uint at = start_of(S_SEGMENT) + 4u * row;
    uint failure = name_failure(word(at), word(at + 1u), word(at + 2u), word(at + 3u));
    if (failure != 0u)
        fail(PH_SEGMENTS, row, failure);
}

void check_declaration_identity(uint row)
{
    if (decl(row, D_MODULE) >= count_of(S_MODULE))
    {
        fail(PH_DECL_IDENTITY, row, 1u);
        return;
    }
    uint failure = name_failure(decl(row, D_HASH_LO), decl(row, D_HASH_HI), decl(row, D_NAME_START),
        decl(row, D_NAME_LEN));
    if (failure != 0u)
    {
        fail(PH_DECL_IDENTITY, row, 1u + failure);
        return;
    }
    if (!optional_index_ok(decl(row, D_OWNER), count_of(S_DECL)))
        fail(PH_DECL_IDENTITY, row, 5u);
}

void check_declaration(uint row)
{
    uint flags = decl(row, D_FLAGS);
    bool native = (flags & DECL_FLAG_NATIVE_C) != 0u;
    bool variadic = (flags & DECL_FLAG_NATIVE_C_VARIADIC) != 0u;
    if ((flags & ~7u) != 0u || (variadic && !native) ||
        (decl(row, D_KIND) != 3u && !native && decl(row, D_VALUE_HI) != 0u))
    {
        fail(PH_DECLARATIONS, row, 1u);
        return;
    }
    uint signature = decl(row, D_SIGNATURE);
    if (!optional_index_ok(signature, count_of(S_TYPE)))
    {
        fail(PH_DECLARATIONS, row, 2u);
        return;
    }
    if (signature == INVALID)
    {
        fail(PH_DECLARATIONS, row, 3u);
        return;
    }
    if (is_constant_kind(ty(signature, Y_KIND)))
    {
        fail(PH_DECLARATIONS, row, 4u);
        return;
    }
    uint first = decl(row, D_FIRST_MEMBER);
    uint count = decl(row, D_MEMBER_COUNT);
    if (!range_ok(first, count, count_of(S_MEMBER)))
    {
        fail(PH_DECLARATIONS, row, 5u);
        return;
    }
    for (uint member = first; member < first + count; ++member)
        if (mem(member, B_OWNER) != row)
        {
            fail(PH_DECLARATIONS, row, 6u);
            return;
        }
}

void check_implementation_ranges(uint row)
{
    if (impl(row, I_MODULE) >= count_of(S_MODULE))
    {
        fail(PH_IMPL_RANGES, row, 1u);
        return;
    }
    if (impl(row, I_SUBJECT) >= count_of(S_TYPE))
    {
        fail(PH_IMPL_RANGES, row, 2u);
        return;
    }
    uint first = impl(row, I_FIRST_MEMBER);
    uint count = impl(row, I_MEMBER_COUNT);
    if (!range_ok(first, count, count_of(S_MEMBER)))
    {
        fail(PH_IMPL_RANGES, row, 3u);
        return;
    }
    for (uint member = first; member < first + count; ++member)
        if (mem(member, B_OWNER) != (OWNER_TAG | row))
        {
            fail(PH_IMPL_RANGES, row, 4u);
            return;
        }
    first = impl(row, I_FIRST_ARG);
    count = impl(row, I_ARG_COUNT);
    if (!range_ok(first, count, count_of(S_IARG)))
    {
        fail(PH_IMPL_RANGES, row, 5u);
        return;
    }
    for (uint argument = first; argument < first + count; ++argument)
        if (iarg(argument) >= count_of(S_TYPE))
        {
            fail(PH_IMPL_RANGES, row, 6u);
            return;
        }
    if (!range_ok(impl(row, I_FIRST_PREREQ), impl(row, I_PREREQ_COUNT), count_of(S_PRED)))
    {
        fail(PH_IMPL_RANGES, row, 7u);
        return;
    }
    if (!range_ok(impl(row, I_FIRST_BINDING), impl(row, I_BINDING_COUNT), count_of(S_BIND)))
        fail(PH_IMPL_RANGES, row, 8u);
}

void check_binding_row(uint row)
{
    if (bind(row, N_IMPL) >= count_of(S_IMPL))
        fail(PH_BINDING_ROWS, row, 1u);
    else if (bind(row, N_MEMBER) >= count_of(S_MEMBER))
        fail(PH_BINDING_ROWS, row, 2u);
}

// The start of a validated node's reverse-preorder subtree: a node other
// than a function starts where its last child's subtree starts. Each step
// moves to an earlier node; a node whose own edges are malformed reports
// that failure at its smaller row.
uint subtree_start(uint node)
{
    for (uint step = 0u; step < count_of(S_TYPE); ++step)
    {
        if (ty(node, Y_KIND) == T_FUNCTION || ty(node, Y_EDGE_COUNT) == 0u)
            return node;
        uint last = edge(ty(node, Y_FIRST_EDGE) + ty(node, Y_EDGE_COUNT) - 1u);
        if (last >= node)
            return node;
        node = last;
    }
    return node;
}

void check_type(uint row)
{
    uint kind = ty(row, Y_KIND);
    if (kind < T_SCALAR || kind > T_COUNT)
    {
        fail(PH_TYPES, row, 1u);
        return;
    }
    uint first = ty(row, Y_FIRST_EDGE);
    uint count = ty(row, Y_EDGE_COUNT);
    if (!range_ok(first, count, count_of(S_EDGE)))
    {
        fail(PH_TYPES, row, 2u);
        return;
    }
    for (uint offset = 0u; offset < count; ++offset)
    {
        uint target = edge(first + offset);
        if (target >= count_of(S_TYPE))
        {
            fail(PH_TYPES, row, 3u);
            return;
        }
        if (is_constant_kind(ty(target, Y_KIND)) &&
            !(kind == T_DECL || (kind == T_ARRAY && offset == 1u) || kind == T_COUNT))
        {
            fail(PH_TYPES, row, 4u);
            return;
        }
        if (target >= row)
        {
            fail(PH_TYPES, row, 5u);
            return;
        }
    }
    if (kind != T_FUNCTION)
    {
        uint start = row;
        for (uint offset = 0u; offset < count; ++offset)
        {
            if (start == 0u)
            {
                fail(PH_TYPES, row, 6u);
                return;
            }
            uint expected = start - 1u;
            if (edge(first + offset) != expected)
            {
                fail(PH_TYPES, row, 7u);
                return;
            }
            start = subtree_start(expected);
        }
    }
    uint payload = ty(row, Y_PAYLOAD_LO);
    if (kind == T_SCALAR && !scalar_is_identity(payload))
    {
        fail(PH_TYPES, row, 8u);
        return;
    }
    if ((kind == T_SCALAR || kind == T_GENERIC || kind == T_CONST_PARAM || kind == T_CONST_VALUE) && count != 0u)
    {
        fail(PH_TYPES, row, 9u);
        return;
    }
    if (kind == T_ARRAY && count != 2u)
    {
        fail(PH_TYPES, row, 10u);
        return;
    }
    if ((kind == T_COUNT || kind == T_SLICE || kind == T_REF) && count != 1u)
    {
        fail(PH_TYPES, row, 11u);
        return;
    }
    if (kind == T_FUNCTION && count == 0u)
    {
        fail(PH_TYPES, row, 12u);
        return;
    }
    if (kind == T_CONST_VALUE)
    {
        if (ty(row, Y_PAYLOAD_HI) != 0u || first != 0u || ty(row, Y_LENGTH_KIND) != 0u ||
            ty(row, Y_NOMINAL_UNIT) != 0u ||
            !constant_value_is_valid(uint3(payload, ty(row, Y_LENGTH_LO), ty(row, Y_LENGTH_HI))))
            fail(PH_TYPES, row, 13u);
    }
    else if (kind == T_COUNT)
    {
        if (scalar_integer_bits(payload) == 0u || ty(row, Y_PAYLOAD_HI) != 0u ||
            ty(row, Y_LENGTH_KIND) != 0u || ty(row, Y_LENGTH_LO) != 0u || ty(row, Y_LENGTH_HI) != 0u ||
            ty(row, Y_NOMINAL_UNIT) != 0u)
        {
            fail(PH_TYPES, row, 14u);
            return;
        }
        uint source = constant_scalar(edge(first));
        if (source == INVALID || scalar_integer_bits(source) == 0u)
            fail(PH_TYPES, row, 15u);
    }
    else if (kind == T_DECL)
    {
        if (payload == library_id() && ty(row, Y_NOMINAL_UNIT) == unit_id() &&
            ty(row, Y_PAYLOAD_HI) >= count_of(S_DECL))
            fail(PH_TYPES, row, 16u);
    }
    else if (kind == T_GENERIC || kind == T_CONST_PARAM)
    {
        if (payload >= count_of(S_MEMBER))
            fail(PH_TYPES, row, 17u);
        else if (mem(payload, B_KIND) != (kind == T_GENERIC ? M_GENERIC_TYPE : M_GENERIC_CONST))
            fail(PH_TYPES, row, 18u);
    }
    else if (kind == T_ARRAY)
    {
        if (ty(row, Y_LENGTH_KIND) != 0u || ty(row, Y_LENGTH_LO) != 0u || ty(row, Y_LENGTH_HI) != 0u)
        {
            fail(PH_TYPES, row, 19u);
            return;
        }
        uint length = constant_scalar(edge(first + 1u));
        if (length == INVALID || scalar_integer_bits(length) == 0u)
            fail(PH_TYPES, row, 20u);
    }
}

void check_member(uint row)
{
    uint kind = mem(row, B_KIND);
    if (!member_kind_known(kind))
    {
        fail(PH_MEMBERS, row, 1u);
        return;
    }
    uint owner = mem(row, B_OWNER);
    if (!owner_valid(owner))
    {
        fail(PH_MEMBERS, row, 2u);
        return;
    }
    uint first;
    uint count;
    if (!owner_member_range(owner, first, count))
    {
        fail(PH_MEMBERS, row, 3u);
        return;
    }
    if (row < first || row - first >= count)
    {
        fail(PH_MEMBERS, row, 4u);
        return;
    }
    uint failure = name_failure(mem(row, B_HASH_LO), mem(row, B_HASH_HI), mem(row, B_NAME_START),
        mem(row, B_NAME_LEN));
    if (failure != 0u)
    {
        fail(PH_MEMBERS, row, 4u + failure);
        return;
    }
    uint type_index = mem(row, B_TYPE);
    if (!optional_index_ok(type_index, count_of(S_TYPE)))
    {
        fail(PH_MEMBERS, row, 8u);
        return;
    }
    if (type_index != INVALID && is_constant_kind(ty(type_index, Y_KIND)))
    {
        fail(PH_MEMBERS, row, 9u);
        return;
    }
    bool implementation_owner = (owner & OWNER_TAG) != 0u;
    if (implementation_owner && !(kind == M_IMPL_METHOD || kind == M_PARAMETER || is_generic_member(kind)))
    {
        fail(PH_MEMBERS, row, 10u);
        return;
    }
    if (kind == M_GENERIC_CONST && constant_parameter_scalar(row) == INVALID)
    {
        fail(PH_MEMBERS, row, 11u);
        return;
    }
    uint receiver = mem(row, B_RECEIVER);
    if (kind == M_IMPL_METHOD)
    {
        if (!implementation_owner)
        {
            fail(PH_MEMBERS, row, 12u);
            return;
        }
        if (receiver >= count_of(S_TYPE))
        {
            fail(PH_MEMBERS, row, 13u);
            return;
        }
        if (is_constant_kind(ty(receiver, Y_KIND)))
        {
            fail(PH_MEMBERS, row, 14u);
            return;
        }
    }
    else if (receiver != INVALID)
    {
        fail(PH_MEMBERS, row, 15u);
        return;
    }
    if (kind == M_TRAIT_METHOD && (implementation_owner || decl(owner, D_KIND) != 10u))
    {
        fail(PH_MEMBERS, row, 16u);
        return;
    }
    if (is_generic_member(kind) == (mem(row, B_GENERIC_ORDINAL) == INVALID))
    {
        fail(PH_MEMBERS, row, 17u);
        return;
    }
    if (type_index == INVALID && kind != M_VARIANT && kind != M_GENERIC_TYPE)
        fail(PH_MEMBERS, row, 18u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint row = thread_index(gid, ltid);
    if (!framed())
        return;
    if (row < count_of(S_MODULE))
        check_module(row);
    if (row < count_of(S_SEGMENT))
        check_segment(row);
    if (row < count_of(S_DECL))
    {
        check_declaration_identity(row);
        check_declaration(row);
    }
    if (row < count_of(S_IMPL))
        check_implementation_ranges(row);
    if (row < count_of(S_BIND))
        check_binding_row(row);
    if (row < count_of(S_TYPE))
        check_type(row);
    if (row < count_of(S_MEMBER))
        check_member(row);
}

import type_checker.interface.validate.common;

// Fills the tables later checks read across rows:
// - each predicate argument row's least owning predicate;
// - each argument and method binding row's least owning trait
//   implementation (inherent implementations own none);
// - each method symbol's least member row;
// - per implementation, the extent of its impl-scoped predicates, and per
//   implementation member, whether one of its owner's predicates has the
//   member's symbol as its scope.
// Only well-formed ranges and method identities are recorded; a malformed
// row fails its own earlier check.

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint row = thread_index(gid, ltid);
    if (!framed())
        return;
    if (row < count_of(S_PRED))
    {
        uint first = pred(row, P_FIRST_ARG);
        uint count = pred(row, P_ARG_COUNT);
        if (range_ok(first, count, count_of(S_PARG)))
            for (uint k = 0u; k < count; ++k)
                atomic_u32_min(validate_scratch, validate_state[STATE_PARG_OWNERS] + first + k, row);
        uint owner = pred(row, P_OWNER);
        uint index = owner & ~OWNER_TAG;
        if ((owner & OWNER_TAG) != 0u && index < count_of(S_IMPL))
        {
            uint symbol = pred(row, P_SCOPE);
            if ((symbol & SCOPE_MASK) == SCOPE_IMPL)
            {
                uint base = validate_state[STATE_IMPL_PREDICATES] + 4u * index;
                atomic_u32_min(validate_scratch, base, row);
                atomic_u32_min(validate_scratch, base + 1u, ~row);
                atomic_u32_min(validate_scratch, base + 2u, symbol);
                atomic_u32_min(validate_scratch, base + 3u, ~symbol);
            }
            uint members = impl(index, I_FIRST_MEMBER);
            uint member_count = impl(index, I_MEMBER_COUNT);
            if (range_ok(members, member_count, count_of(S_MEMBER)))
                for (uint member = members; member < members + member_count; ++member)
                    if (mem(member, B_VALUE_HI) == symbol)
                        validate_scratch[validate_state[STATE_MEMBER_PREDICATES] + member] = 0u;
        }
    }
    if (row < count_of(S_IMPL) && impl(row, I_KIND) == IMPL_TRAIT)
    {
        uint first = impl(row, I_FIRST_ARG);
        uint count = impl(row, I_ARG_COUNT);
        if (range_ok(first, count, count_of(S_IARG)))
            for (uint k = 0u; k < count; ++k)
                atomic_u32_min(validate_scratch, validate_state[STATE_IARG_OWNERS] + first + k, row);
        first = impl(row, I_FIRST_BINDING);
        count = impl(row, I_BINDING_COUNT);
        if (range_ok(first, count, count_of(S_BIND)))
            for (uint k = 0u; k < count; ++k)
                atomic_u32_min(validate_scratch, validate_state[STATE_BIND_OWNERS] + first + k, row);
    }
    if (row < count_of(S_MEMBER))
    {
        uint kind = mem(row, B_KIND);
        uint symbol = mem(row, B_VALUE_HI);
        if ((kind == M_TRAIT_METHOD || kind == M_IMPL_METHOD) && (symbol & SCOPE_MASK) == SCOPE_METHOD)
            symbol_insert(symbol, row);
    }
}

import type_checker.interface.validate.common;

// Fills the tables later checks read across rows:
// - each predicate argument row's least owning predicate;
// - each argument and method binding row's least owning trait
//   implementation (inherent implementations own none);
// - each method symbol's least member row.
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

// Publication predicate shared by the output kernels. Every failure was
// recorded by an earlier dispatch, so all output lanes see the same decision.

import codegen.x86.symbol_finalization.symbol_finalization_layout;

bool finalize_publishable(RWStructuredBuffer<uint> status)
{
    for (uint code = 0u; code < FAIL_CODE_COUNT; code += 1u)
    {
        if (status[failure_slot(code)] != INVALID)
            return false;
    }
    return status[STATUS_SYMBOL_DEMAND] <= gFinalize.symbol_capacity &&
        status[STATUS_IDENTITY_DEMAND] <= gFinalize.identity_word_capacity;
}

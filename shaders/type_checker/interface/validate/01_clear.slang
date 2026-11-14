import type_checker.interface.validate.common;

// Sets every scratch word the plan laid out to INVALID: no argument or
// binding has an owner and the symbol table is empty.

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint thread = thread_index(gid, ltid);
    if (thread < validate_state[STATE_SCRATCH_WORDS])
        validate_scratch[thread] = INVALID;
}

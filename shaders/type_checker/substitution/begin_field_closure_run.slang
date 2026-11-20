// Open a field-closure run's first level round (one lane, field_closure.slang):
// the entries the roots queued become its input, and the level kernel's
// indirect dispatch arguments are written. Each level round's last
// workgroup then advances the run itself.
import type_checker.substitution.field_closure;
import type_checker.substitution.field_closure_progress;

RWStructuredBuffer<uint> ct_expand_args;
// The other level rounds' arguments, written only for a run without input.
RWStructuredBuffer<uint> ct_expand_args_b;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    // A run whose roots queued nothing would expand nothing, report no
    // progress and leave START = END = the queue length with the round count
    // at 0. Close it here, and dispatch none of its level rounds.
    if (ct_expand_run_empty())
    {
        ct_expand_close_empty_run();
        uint3 none = ct_expand_level_args(0u);
        [unroll]
        for (uint i = 0u; i < 3u; i++) { ct_expand_args[i] = none[i]; ct_expand_args_b[i] = none[i]; }
        return;
    }
    uint3 args = advance_field_closure();
    ct_expand_args[0u] = args.x;
    ct_expand_args[1u] = args.y;
    ct_expand_args[2u] = args.z;
}

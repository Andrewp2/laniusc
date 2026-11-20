import type_checker.substitution.field_closure;
import type_checker.calls.inference_activity;

RWStructuredBuffer<uint> call_inference_state;

// Each run advances once after queueing roots and once after every level.
public uint3 advance_field_closure()
{
    bool progress;
    uint3 args = ct_expand_advance(progress);
    if (progress)
    {
        uint ignored;
        InterlockedAdd(call_inference_state[1u], 1u, ignored);
        inference_note_global_change();
    }
    return args;
}

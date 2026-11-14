// Open a field-closure run's first level round (one lane, ct_expand.slang):
// the entries the roots queued become its input, and the level kernel's
// indirect dispatch arguments are written. Each level round's last
// workgroup then advances the run itself.
import type_checker.substitution.ct_expand;

RWStructuredBuffer<uint> ct_expand_args;
RWStructuredBuffer<uint> call_inference_state;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    bool progress;
    uint3 args = ct_expand_advance(progress);
    if (progress)
    {
        uint ignored;
        InterlockedAdd(call_inference_state[1u], 1u, ignored);
    }
    ct_expand_args[0u] = args.x;
    ct_expand_args[1u] = args.y;
    ct_expand_args[2u] = args.z;
}

// Open a call inference round (one lane): zero the round's change count and
// count the round (inference_activity.slang).
RWStructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> call_inference_round;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    call_inference_state[1u] = 0u;
    call_inference_round[0u] += 1u;
}

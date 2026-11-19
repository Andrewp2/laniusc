import shared.collectives.step_program;
import shared.collectives.program_prefix_scan;

struct Params { uint groups; uint rows; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> input_words;
RWStructuredBuffer<uint> prefix;
RWStructuredBuffer<uint> total;
RWStructuredBuffer<uint> sums;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, gParams.groups, 0u);
    if (!step_program_prefix_scan(program, gParams.rows, input_words, prefix, total, sums))
        return;
    step_program_end(program);
}

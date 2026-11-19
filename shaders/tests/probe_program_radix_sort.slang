import radix.radix_digits;
import shared.collectives.step_program;
import shared.collectives.program_radix_sort;

struct Params { uint groups; uint rows; uint digits; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> keys;
RWStructuredBuffer<uint> order;
RWStructuredBuffer<uint> temporary;
RWStructuredBuffer<uint> histogram;
RWStructuredBuffer<uint> bucket_total;

struct WordKey : IStepProgramRadixKey
{
    static uint digit(uint row, uint step)
    {
        return radix_byte_key(keys[row], step);
    }
};

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, gParams.groups, 0u);
    if (!step_program_radix_sort<WordKey>(
            program, gParams.rows, gParams.digits, order, temporary, histogram, bucket_total))
        return;
    step_program_end(program);
}

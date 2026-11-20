import codegen.lir.lowering_ir;
import codegen.lir.scheduling.target_schedule_layout;
import shared.collectives.program_radix_sort;
import shared.collectives.step_program;

struct Params { uint capacity; uint digits; };
struct Launch { uint groups; uint slot; uint options; uint reserved; };

ConstantBuffer<Params> gParams;
ConstantBuffer<Launch> program_launch;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<TargetScheduleKey> target_schedule_key;
RWStructuredBuffer<uint> target_schedule_order;
RWStructuredBuffer<uint> target_schedule_temporary;
RWStructuredBuffer<uint> target_schedule_histogram;
RWStructuredBuffer<uint> target_schedule_bucket_total;

struct ScheduleKey : IStepProgramRadixKey
{
    static uint digit(uint row, uint step)
    {
        return target_schedule_radix_key(target_schedule_key[row], step, 0u);
    }
};

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint rows = min(gParams.capacity, target_lir_total[0u]);
    if (!step_program_radix_sort<ScheduleKey>(program, rows, gParams.digits,
            target_schedule_order, target_schedule_temporary,
            target_schedule_histogram, target_schedule_bucket_total, true)) return;
    step_program_end(program);
}

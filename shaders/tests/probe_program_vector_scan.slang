import shared.collectives.program_prefix_scan;
import shared.collectives.step_program;

struct ScanParams
{
    uint groups;
    uint rows;
};

ConstantBuffer<ScanParams> gParams;
RWStructuredBuffer<uint4> scan_input;
RWStructuredBuffer<uint4> scan_prefix;
RWStructuredBuffer<uint4> scan_sums;
RWStructuredBuffer<uint> scan_total;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, gParams.groups, 0u);
    if (!step_program_prefix_scan_u32x4(
            program, gParams.rows, scan_input, scan_prefix, scan_total, 1u, scan_sums))
        return;
    step_program_end(program);
}

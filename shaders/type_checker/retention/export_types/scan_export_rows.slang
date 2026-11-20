import shared.collectives.step_program;
import shared.collectives.program_prefix_scan;

RWStructuredBuffer<uint4> rt_x_scan_group_sums;

public bool scan_export_rows(
    inout StepProgram program,
    uint rows,
    RWStructuredBuffer<uint4> flags,
    RWStructuredBuffer<uint4> prefix,
    RWStructuredBuffer<uint> counts,
    uint total_offset)
{
    return step_program_prefix_scan_u32x4(
        program, rows, flags, prefix, counts, total_offset, rt_x_scan_group_sums);
}

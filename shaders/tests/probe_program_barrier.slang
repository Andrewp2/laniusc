// Runs `rounds` steps of a step program. A step writes the round number to
// each of the lane's own cells and checks cells that another lane wrote in the
// step before. A wrong value means the reader did not see the earlier step.
// The reads are plain: the build marks the buffers of a step program coherent.

import shared.collectives.step_program;

struct Params { uint groups; uint rounds; uint rows_per_lane; uint slot; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> cells;
RWStructuredBuffer<uint> wrong_cells;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, gParams.groups, gParams.slot);
    uint side_cells = program.lanes * gParams.rows_per_lane;
    for (uint round = 0u; round < gParams.rounds; round += 1u)
    {
        uint side = (round & 1u) * side_cells;
        uint other = (program.lane * 7919u + round * 13u + 1u) % program.lanes;
        uint wrong = 0u;
        for (uint row = 0u; row < gParams.rows_per_lane; row += 1u)
        {
            uint written = cells[(side_cells - side) + other + row * program.lanes];
            if (round != 0u && written != round) wrong += 1u;
            cells[side + program.lane + row * program.lanes] = round + 1u;
        }
        if (wrong != 0u)
        {
            uint prior;
            InterlockedAdd(wrong_cells[0u], wrong, prior);
        }
        if (!step_barrier(program)) return;
    }
    step_program_end(program);
}

import shared.collectives.step_program;

struct Launch
{
    uint groups;
    uint slot;
    uint options;
    uint reserved;
};

ConstantBuffer<Launch> program_launch;
StructuredBuffer<uint> inference_program_args;

public StepProgram begin_call_inference_program(uint3 group, uint3 local)
{
    return step_program_begin(group, local, inference_program_args[0u], program_launch.slot);
}

// Keep failures until the job's status readback. Each launch clears its own
// sync slot, so a later round must not overwrite this word.
public void call_inference_note_barrier_failure(StepProgram program, RWStructuredBuffer<uint> status)
{
    if (program.leader)
        InterlockedOr(status[4u], step_program_sync[program.sync_base + STEP_SYNC_FAILED]);
}

public bool call_inference_barrier(inout StepProgram program, RWStructuredBuffer<uint> status)
{
    if (step_barrier(program)) return true;
    call_inference_note_barrier_failure(program, status);
    return false;
}

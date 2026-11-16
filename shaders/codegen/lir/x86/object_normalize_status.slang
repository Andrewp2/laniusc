import codegen.lowering_ir;

StructuredBuffer<uint> x86_entrypoint_state;
RWStructuredBuffer<X86ArtifactLayout> x86_artifact_layout;
RWStructuredBuffer<LoweringStatus> lowering_status;

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    X86ArtifactLayout layout = x86_artifact_layout[0u];
    if (x86_entrypoint_state[0u] == 0u && layout.status == 1u)
    {
        lowering_status[0u].flags &= ~LOWERING_STATUS_MISSING_ENTRYPOINT;
        // The layout publishes this reason with the flag. Left behind, it
        // would read as a diagnostic and stop a capacity retry.
        if (lowering_status[0u].diagnostic_reason == LOWERING_DIAGNOSTIC_MISSING_ENTRYPOINT)
            lowering_status[0u].diagnostic_reason = LOWERING_DIAGNOSTIC_NONE;
        layout.status = 0u;
        x86_artifact_layout[0u] = layout;
    }
}

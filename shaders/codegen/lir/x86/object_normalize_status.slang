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
        layout.status = 0u;
        x86_artifact_layout[0u] = layout;
    }
}

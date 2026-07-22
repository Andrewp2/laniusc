import codegen.lowering_ir;
import codegen.lir.x86.runtime_abi;

struct Params { uint target_capacity; uint token_capacity; uint function_capacity; uint artifact_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> x86_body_length;
StructuredBuffer<uint> x86_entrypoint_state;
StructuredBuffer<uint> target_function_count;
StructuredBuffer<TargetLirFunction> target_functions;
StructuredBuffer<uint> target_function_index_by_semantic;
StructuredBuffer<uint> target_byte_offset;
StructuredBuffer<uint> semantic_lir_string_pool_len;
RWStructuredBuffer<X86ArtifactLayout> x86_artifact_layout;
RWStructuredBuffer<uint> x86_artifact_length;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint ELF_TEXT_OFFSET = 0x78u;
static const uint ENTRY_WRAPPER_BYTES = 17u;

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    X86ArtifactLayout layout;
    layout.body_length = x86_body_length[0u];
    layout.entrypoint_count = x86_entrypoint_state[0u];
    layout.entrypoint_function = x86_entrypoint_state[1u];
    layout.text_offset = ELF_TEXT_OFFSET;
    layout.body_offset = ELF_TEXT_OFFSET + ENTRY_WRAPPER_BYTES;
    layout.runtime_offset = layout.body_offset + layout.body_length;
    layout.runtime_length = X86_RUNTIME_LENGTH;
    layout.rodata_offset = layout.runtime_offset + layout.runtime_length;
    layout.rodata_length = semantic_lir_string_pool_len[0u];
    layout.file_length = layout.rodata_offset + layout.rodata_length;
    layout.entrypoint_body_offset = 0xffffffffu;
    layout.status = 0u;

    uint function_count = min(gParams.function_capacity, target_function_count[0u]);
    uint entrypoint_index = layout.entrypoint_function < gParams.function_capacity
        ? target_function_index_by_semantic[layout.entrypoint_function] : 0xffffffffu;
    if (layout.entrypoint_count == 0u)
    {
        layout.status = 1u;
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_MISSING_ENTRYPOINT);
    }
    else if (layout.entrypoint_count > 1u)
    {
        layout.status = 2u;
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_MULTIPLE_ENTRYPOINTS);
    }
    else if (entrypoint_index >= function_count)
    {
        layout.status = 3u;
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
    }
    else
    {
        uint row = target_functions[entrypoint_index].instruction_start;
        if (row < gParams.target_capacity)
            layout.entrypoint_body_offset = target_byte_offset[row];
        else
        {
            layout.status = 3u;
            InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        }
    }

    if (layout.file_length > gParams.artifact_capacity)
    {
        layout.status = 4u;
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_ARTIFACT_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity, layout.file_length);
        InterlockedMin(lowering_status[0u].available_capacity, gParams.artifact_capacity);
    }
    x86_artifact_layout[0u] = layout;
    x86_artifact_length[0u] = layout.file_length;
}

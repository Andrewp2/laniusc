import codegen.lir.lowering_ir;
import codegen.lir.x86.runtime.native_runtime_abi;
import codegen.lir.x86.runtime.crt_entry;

public struct Params { public uint target_capacity; public uint token_capacity; public uint function_capacity; public uint artifact_capacity; };
public ConstantBuffer<Params> gParams;
public RWStructuredBuffer<uint> x86_entrypoint_state;
public StructuredBuffer<uint> semantic_lir_function_total;
public StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
public RWStructuredBuffer<uint> x86_body_length;
public StructuredBuffer<uint> target_function_count;
public StructuredBuffer<TargetLirFunction> target_functions;
public StructuredBuffer<uint> target_function_index_by_semantic;
public RWStructuredBuffer<uint> target_byte_offset;
public StructuredBuffer<uint> semantic_lir_string_pool_len;
public RWStructuredBuffer<X86ArtifactLayout> x86_artifact_layout;
public RWStructuredBuffer<uint> x86_artifact_length;
public RWStructuredBuffer<LoweringStatus> lowering_status;
public StructuredBuffer<uint> target_byte_length;
public StructuredBuffer<uint> target_lir_total;
public RWStructuredBuffer<uint> scan_group_sums;

static const uint FUNCTION_ENTRYPOINT = 1u;
static const uint ELF_TEXT_OFFSET = 0x78u;
static const uint ENTRY_WRAPPER_BYTES = 17u;

public void clear_entrypoint()
{
    x86_entrypoint_state[0u] = 0u;
    x86_entrypoint_state[1u] = 0xffffffffu;
    x86_entrypoint_state[2u] = 0u;
}

public void select_entrypoint(uint function_id)
{
    if ((semantic_lir_functions[function_id].flags & FUNCTION_ENTRYPOINT) != 0u)
    {
        InterlockedAdd(x86_entrypoint_state[0u], 1u);
        InterlockedMin(x86_entrypoint_state[1u], function_id);
        InterlockedMax(x86_entrypoint_state[2u], function_id);
    }
}

public void plan_layout()
{
    X86ArtifactLayout layout;
    layout.body_length = x86_body_length[0u];
    layout.entrypoint_count = x86_entrypoint_state[0u];
    layout.entrypoint_function = x86_entrypoint_state[1u];
    layout.text_offset = ELF_TEXT_OFFSET;
    layout.body_offset = ELF_TEXT_OFFSET + ENTRY_WRAPPER_BYTES;
    layout.runtime_offset = layout.body_offset + layout.body_length;
    layout.runtime_length = X86_CRT_RUNTIME_LENGTH;
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
        uint prior_flags;
        InterlockedOr(lowering_status[0u].flags,
            LOWERING_STATUS_MISSING_ENTRYPOINT, prior_flags);
        if (prior_flags == 0u)
            lowering_status[0u].diagnostic_reason =
                LOWERING_DIAGNOSTIC_MISSING_ENTRYPOINT;
    }
    else if (layout.entrypoint_count > 1u)
    {
        layout.status = 2u;
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_MULTIPLE_ENTRYPOINTS);
        lowering_status[0u].diagnostic_reason = LOWERING_DIAGNOSTIC_MULTIPLE_ENTRYPOINTS;
        uint duplicate_function = x86_entrypoint_state[2u];
        if (duplicate_function < gParams.function_capacity)
        {
            lowering_status[0u].diagnostic_detail_kind = LOWERING_DIAGNOSTIC_DETAIL_TOKEN;
            lowering_status[0u].diagnostic_detail =
                semantic_lir_functions[duplicate_function].name_token;
        }
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

public void normalize_object_status()
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

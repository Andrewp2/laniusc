import codegen.lir.lowering_ir;

public struct SpillParams
{
    public uint semantic_capacity;
    public uint call_arg_capacity;
    public uint aggregate_capacity;
    public uint function_capacity;
    public uint token_capacity;
    public uint reserved0;
    public uint reserved1;
    public uint reserved2;
};
public struct PlaceParams
{
    public uint token_capacity;
    public uint parameter_capacity;
    public uint local_capacity;
    public uint function_capacity;
};
public ConstantBuffer<SpillParams> gParams;
public ConstantBuffer<PlaceParams> place_params;
public StructuredBuffer<uint> opt_ir_total;
public StructuredBuffer<uint> semantic_schedule_order;
public StructuredBuffer<uint> opt_ir_source_hir;
public StructuredBuffer<uint> semantic_function_id_by_hir;
public StructuredBuffer<uint> x86_function_start;
public StructuredBuffer<uint> x86_stack_words_by_position;
public RWStructuredBuffer<uint> x86_stack_prefix_by_position;
public RWStructuredBuffer<uint> x86_location_by_semantic;
public StructuredBuffer<uint> semantic_lir_function_total;
public StructuredBuffer<uint> x86_function_end;
public RWStructuredBuffer<X86FunctionRegisterAnalysis> x86_register_analysis_by_function;
public RWStructuredBuffer<uint> x86_stack_slot_count_by_function;
public RWStructuredBuffer<uint> x86_frame_slot_count_by_function;
public StructuredBuffer<uint> semantic_lir_local_total;
public StructuredBuffer<SemanticLirLocal> semantic_lir_locals;
public StructuredBuffer<uint4> semantic_place_storage_by_token;
public RWStructuredBuffer<uint> x86_place_words_by_local;
public RWStructuredBuffer<uint> x86_stack_word_total;
public RWStructuredBuffer<uint> x86_place_prefix_by_local;
public RWStructuredBuffer<uint> x86_place_word_total;
public RWStructuredBuffer<uint> scan_group_sums;

static const uint INVALID = 0xffffffffu;

public void place_spill(uint position, uint total)
{
    uint row = semantic_schedule_order[position];
    if (row >= total || x86_stack_words_by_position[position] == 0u ||
        x86_location_by_semantic[row] != INVALID) return;
    uint owner = opt_ir_source_hir[row];
    if (owner >= gParams.function_capacity) return;
    uint function_id = semantic_function_id_by_hir[owner];
    if (function_id >= gParams.function_capacity) return;
    uint start = x86_function_start[function_id];
    if (start > position || start >= total) return;
    uint base = x86_stack_prefix_by_position[start];
    uint prefix = x86_stack_prefix_by_position[position];
    x86_location_by_semantic[row] = prefix >= base ? prefix - base : INVALID;
}

public void summarize_spills(uint function_id)
{
    uint start = x86_function_start[function_id];
    uint end = min(x86_function_end[function_id],
        gParams.semantic_capacity);
    uint words = 0u;
    if (start < end)
    {
        uint last = end - 1u;
        uint base = x86_stack_prefix_by_position[start];
        uint limit = x86_stack_prefix_by_position[last] +
            x86_stack_words_by_position[last];
        words = limit >= base ? limit - base : 0u;
    }
    x86_stack_slot_count_by_function[function_id] = words;
    x86_frame_slot_count_by_function[function_id] = words;

    X86FunctionRegisterAnalysis analysis =
        x86_register_analysis_by_function[function_id];
    if (analysis.first_call == INVALID)
    {
        analysis.first_call = 0u;
        analysis.flags = 0u;
    }
    else
    {
        // Conservatively retain declaration homes across calls. A later
        // parallel interval allocator can refine this without changing the
        // spill-layout contract.
        analysis.flags = X86_FUNCTION_REGISTER_CALL_WITH_LOOP;
    }
    analysis.first_rdx_clobber = 0u;
    analysis.first_rcx_clobber = 0u;
    x86_register_analysis_by_function[function_id] = analysis;
}

public void count_local_words(uint row)
{
    uint token = semantic_lir_locals[row].declaration_id;
    uint4 storage = token < place_params.token_capacity
        ? semantic_place_storage_by_token[token] : uint4(0u, 0u, 0u, 0u);
    // Empty addressable objects still have a unique, stable anchor.
    x86_place_words_by_local[row] = storage.x == 3u ? max(storage.y, 1u) : 0u;
}

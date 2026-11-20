import codegen.lir.lowering_ir;
import codegen.lir.optimization_ir;
import codegen.lir.x86.instructions.native_instruction_lowering;
import codegen.lir.x86.allocation.native_value_location_rules;
import codegen.lir.x86.allocation.native_frame_layout;
import codegen.lir.x86.emission.native_c_callback_stubs;

public struct Params
{
    public uint target_capacity;
    public uint function_capacity;
    public uint artifact_capacity;
    public uint semantic_capacity;
};
struct ObjectIdentity { uint library_id; uint unit_id; uint reserved0; uint reserved1; };

public ConstantBuffer<Params> gParams;
ConstantBuffer<ObjectIdentity> gIdentity;
public StructuredBuffer<uint> opt_ir_total;
public StructuredBuffer<uint> semantic_schedule_order;
public StructuredBuffer<OptIrNodeCore> opt_ir_core;
public StructuredBuffer<uint> target_lir_count;
public RWStructuredBuffer<uint> x86_object_relocation_flag;
public RWStructuredBuffer<uint> x86_object_symbol_flag;
public StructuredBuffer<uint> semantic_lir_function_total;
public StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
public StructuredBuffer<uint> target_function_count;
public StructuredBuffer<uint> target_function_index_by_semantic;
public RWStructuredBuffer<uint> x86_object_definition_flag;
public StructuredBuffer<uint> target_lir_total;
public StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
public StructuredBuffer<uint> opt_ir_source_hir;
public StructuredBuffer<uint> semantic_function_id_by_hir;
public StructuredBuffer<uint> semantic_to_target_start;
public StructuredBuffer<X86LirCore> target_lir_core;
public StructuredBuffer<X86LirOperands> target_lir_operands;
public StructuredBuffer<X86LirLocations> target_lir_locations;
public StructuredBuffer<TargetLirFunction> target_functions;
public StructuredBuffer<uint> x86_saved_gpr_mask_by_function;
public StructuredBuffer<uint> target_byte_length;
public StructuredBuffer<uint> target_byte_offset;
public StructuredBuffer<X86ArtifactLayout> x86_artifact_layout;
public StructuredBuffer<uint> semantic_lir_string_total;
public StructuredBuffer<SemanticLirString> semantic_lir_strings;
public RWStructuredBuffer<uint> x86_object_relocation_prefix;
public RWStructuredBuffer<uint> x86_object_symbol_prefix;
public RWStructuredBuffer<X86ObjectRelocationRow> x86_object_relocations;
public RWStructuredBuffer<X86ObjectUndefinedRow> x86_object_undefined_symbols;
public RWStructuredBuffer<uint> x86_object_call_hir_by_symbol;
public StructuredBuffer<uint2> x86_runtime_reference;
public RWStructuredBuffer<uint> x86_runtime_relocation_prefix;
public RWStructuredBuffer<X86ObjectRelocationRow> x86_object_runtime_relocations;
public RWStructuredBuffer<uint> x86_object_definition_prefix;
public RWStructuredBuffer<X86ObjectDefinitionRow> x86_object_definitions;
public StructuredBuffer<uint> x86_runtime_reference_flag;
public RWStructuredBuffer<uint> x86_object_relocation_total;
public RWStructuredBuffer<uint> x86_object_symbol_total;
public RWStructuredBuffer<uint> x86_object_definition_total;
public RWStructuredBuffer<uint> x86_object_runtime_relocation_total;
public RWStructuredBuffer<uint> scan_group_sums;

static const uint INVALID = 0xffffffffu;
static const uint SECTION_TEXT = 1u;
static const uint SECTION_RODATA = 2u;
static const uint RELOCATION_CALL_REL32 = 2u;
static const uint RELOCATION_ABS32 = 3u;
static const uint TARGET_SECTION_OFFSET = 1u;
static const uint TARGET_SYMBOL = 2u;
static const uint RELOCATION_RAW_REL32 = 4u;

public void mark_relocations(uint row)
{
    // Eliminated calls and calls inside removed inline bodies have no machine
    // instruction to relocate. A placeholder here would patch the next row.
    uint op = target_lir_count[row] != 0u
        ? opt_ir_op(opt_ir_core[semantic_schedule_order[row]]) : SEMANTIC_LIR_OP_NOP;
    x86_object_relocation_flag[row] =
        op == SEMANTIC_LIR_OP_CALL_SYMBOL || op == SEMANTIC_LIR_OP_CONST_STRING ? 1u : 0u;
    x86_object_symbol_flag[row] = op == SEMANTIC_LIR_OP_CALL_SYMBOL ? 1u : 0u;
}

public void mark_definitions(uint function_id, uint target_count)
{
    uint target_index = target_function_index_by_semantic[function_id];
    x86_object_definition_flag[function_id] = semantic_lir_functions[function_id].symbol_local_index != INVALID &&
        target_index != INVALID && target_index < target_count ? 1u : 0u;
}

public void write_relocations(uint row, uint target_total, uint function_count)
{
    if (x86_object_relocation_flag[row] == 0u) return;

    uint semantic_row = semantic_schedule_order[row];
    uint target_row = semantic_to_target_start[semantic_row];
    if (target_row >= target_total) return;

    OptIrNodeCore core = opt_ir_core[semantic_row];
    OptIrNodeOperands operands = opt_ir_operands[semantic_row];
    uint function_id =
        semantic_function_id_by_hir[opt_ir_source_hir[semantic_row]];
    uint function_index = function_id < gParams.function_capacity
        ? target_function_index_by_semantic[function_id] : INVALID;
    if (function_index >= function_count) return;
    TargetLirFunction function = target_functions[function_index];

    X86LirOperands target_operands = target_lir_operands[target_row];
    X86LirCore target_core = target_lir_core[target_row];
    X86LirLocations locations = target_lir_locations[target_row];
    uint aggregate_words = x86_symbol_call_result_words(target_core.local_ordinal);
    bool symbol_entry = target_core.op == X86_LIR_OP_FUNCTION_ADDRESS_SYMBOL;
    uint instruction_bytes = symbol_entry ? X86_C_ENTRY_PREFIX_BYTES + X86_C_ENTRY_BYTES +
        x86_move64_from_fixed_bytes(0u, locations.result) : opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL
        ? x86_call_result_instruction_bytes(
            target_operands.metadata, aggregate_words, locations.result) +
            (x86_symbol_call_stack_bytes(target_core.local_ordinal) != 0u
                ? 7u : 0u) +
            (x86_symbol_call_padded(target_operands.metadata,
                x86_symbol_call_stack_bytes(target_core.local_ordinal)) ? 4u : 0u)
        // STRING_ADDR is the first target row of a semantic string constant.
        // Its destination-dependent spill is not a fixed 17 bytes. Using the
        // exact row width keeps the ABS32 relocation after any prologue and at
        // the movabs immediate rather than overwriting saved-register stores.
        : 10u + x86_move64_from_fixed_bytes(0u, locations.result);
    uint footer_bytes = target_row + 1u == function.instruction_start + function.instruction_count
        ? implicit_footer_bytes(function, semantic_lir_functions[function_id],
            x86_saved_gpr_mask_by_function[function_id]) : 0u;
    uint row_bytes = target_byte_length[target_row];
    uint prefix_bytes = row_bytes >= instruction_bytes + footer_bytes
        ? row_bytes - instruction_bytes - footer_bytes : 0u;

    X86ObjectRelocationRow relocation;
    relocation.site_section = SECTION_TEXT;
    X86ArtifactLayout layout = x86_artifact_layout[0u];
    uint wrapper_length = layout.body_offset - layout.text_offset;
    relocation.site_offset = wrapper_length + target_byte_offset[target_row] + prefix_bytes +
        (symbol_entry ? X86_C_ENTRY_REL32_OFFSET : opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL
            ? (target_operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u &&
              aggregate_words > 2u
                ? x86_stack64_operand_bytes(
                    x86_location_payload(locations.result) + 1u) + 1u
                : 1u
            : 2u);
    relocation.addend_lo = opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL ? 0xfffffffcu : 0u;
    relocation.addend_hi = opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL ? 0xffffffffu : 0u;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL)
    {
        uint symbol_index = x86_object_symbol_prefix[row];
        relocation.kind = RELOCATION_CALL_REL32;
        relocation.target_kind = TARGET_SYMBOL;
        relocation.target_index = symbol_index;
        relocation.target_offset = 0u;
        X86ObjectUndefinedRow symbol;
        bool local = operands.a == INVALID && operands.b == INVALID;
        symbol.library_id = local ? gIdentity.library_id : operands.a;
        symbol.unit_id = local ? gIdentity.unit_id : operands.b;
        symbol.local_index = operands.c;
        symbol.reserved = 0u;
        x86_object_undefined_symbols[symbol_index] = symbol;
        x86_object_call_hir_by_symbol[symbol_index] = opt_ir_source_hir[semantic_row];
    }
    else
    {
        uint string_count = min(semantic_lir_string_total[0u], gParams.target_capacity);
        if (operands.a >= string_count) return;
        relocation.kind = RELOCATION_ABS32;
        relocation.target_kind = TARGET_SECTION_OFFSET;
        relocation.target_index = SECTION_RODATA;
        relocation.target_offset = semantic_lir_strings[operands.a].data_offset;
    }
    x86_object_relocations[x86_object_relocation_prefix[row]] = relocation;
}

public void write_runtime_relocations(uint row)
{
    uint2 reference = x86_runtime_reference[row];
    if (reference.x == 0u) return;
    X86ArtifactLayout layout = x86_artifact_layout[0u];
    X86ObjectRelocationRow relocation;
    relocation.kind = reference.y >> 16u;
    relocation.site_section = SECTION_TEXT;
    relocation.site_offset = reference.x - 1u;
    relocation.target_kind = TARGET_SECTION_OFFSET;
    relocation.target_index = SECTION_TEXT;
    // A raw-only rel32 jumps `reference.y & 0xffff` bytes past its own end.
    relocation.target_offset = relocation.kind == RELOCATION_RAW_REL32
        ? relocation.site_offset + 4u + (reference.y & 0xffffu)
        : layout.runtime_offset - layout.text_offset + (reference.y & 0xffffu);
    relocation.addend_lo = 0xfffffffcu; // rel32 is relative to the next byte
    relocation.addend_hi = 0xffffffffu;
    x86_object_runtime_relocations[x86_runtime_relocation_prefix[row]] = relocation;
}

public void write_definitions(uint function_id, uint function_count)
{
    if (x86_object_definition_flag[function_id] == 0u) return;
    uint function_index = target_function_index_by_semantic[function_id];
    if (function_index >= function_count) return;
    TargetLirFunction target = target_functions[function_index];
    if (target.instruction_count == 0u) return;
    uint first = target.instruction_start;
    uint last = first + target.instruction_count - 1u;
    X86ArtifactLayout layout = x86_artifact_layout[0u];
    uint wrapper_length = layout.body_offset - layout.text_offset;
    uint start = wrapper_length + target_byte_offset[first];
    uint end = wrapper_length + target_byte_offset[last] + target_byte_length[last];
    SemanticLirFunction semantic = semantic_lir_functions[function_id];

    X86ObjectDefinitionRow definition;
    definition.library_id = gIdentity.library_id;
    definition.unit_id = gIdentity.unit_id;
    definition.local_index = semantic.symbol_local_index;
    definition.section = SECTION_TEXT;
    definition.offset = start;
    definition.size = end - start;
    definition.flags = semantic.symbol_flags;
    definition.reserved = 0u;
    x86_object_definitions[x86_object_definition_prefix[function_id]] = definition;
}

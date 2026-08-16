import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint function_capacity; uint artifact_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
StructuredBuffer<SemanticLirOperands> semantic_lir_operands;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> semantic_owner_by_instruction;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> semantic_to_target_start;
StructuredBuffer<uint> target_function_count;
StructuredBuffer<TargetLirFunction> target_functions;
StructuredBuffer<uint> target_function_index_by_semantic;
StructuredBuffer<uint> target_byte_length;
StructuredBuffer<uint> target_byte_offset;
StructuredBuffer<X86ArtifactLayout> x86_artifact_layout;
StructuredBuffer<uint> semantic_lir_string_total;
StructuredBuffer<SemanticLirString> semantic_lir_strings;
StructuredBuffer<uint> x86_object_relocation_flag;
StructuredBuffer<uint> x86_object_relocation_prefix;
StructuredBuffer<uint> x86_object_symbol_prefix;
RWStructuredBuffer<X86ObjectRelocationRow> x86_object_relocations;
RWStructuredBuffer<X86ObjectUndefinedRow> x86_object_undefined_symbols;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint SECTION_TEXT = 1u;
static const uint SECTION_RODATA = 2u;
static const uint RELOCATION_CALL_REL32 = 2u;
static const uint RELOCATION_ABS32 = 3u;
static const uint TARGET_SECTION_OFFSET = 1u;
static const uint TARGET_SYMBOL = 2u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint semantic_count = semantic_lir_total[0u];
    if (row >= semantic_count || x86_object_relocation_flag[row] == 0u) return;

    uint semantic_row = semantic_schedule_order[row];
    uint target_row = semantic_to_target_start[semantic_row];
    uint target_total = min(target_lir_total[0u], gParams.target_capacity);
    if (target_row >= target_total) return;

    SemanticLirCore core = semantic_lir_core[semantic_row];
    SemanticLirOperands operands = semantic_lir_operands[semantic_row];
    uint function_id =
        semantic_function_id_by_hir[semantic_owner_by_instruction[semantic_row]];
    uint function_index = function_id < gParams.function_capacity
        ? target_function_index_by_semantic[function_id] : INVALID;
    uint function_count = min(target_function_count[0u], gParams.function_capacity);
    if (function_index >= function_count) return;
    TargetLirFunction function = target_functions[function_index];

    uint type_ref_tag = semantic_lir_type_ref_tag(core);
    bool aggregate_symbol = semantic_lir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL &&
        (type_ref_tag == SEMANTIC_TYPE_REF_INSTANCE ||
         (type_ref_tag == SEMANTIC_TYPE_REF_SCALAR && core.type_ref_payload >= 128u) ||
         (type_ref_tag == SEMANTIC_TYPE_REF_INVALID && core.type_id >= 128u));
    uint aggregate_words = core.value_word_count;
    uint instruction_bytes = semantic_lir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL
        ? (aggregate_symbol
            ? aggregate_words > 2u ? 19u : 19u + aggregate_words * 7u
            : 11u) : 17u;
    uint footer_bytes = target_row + 1u == function.instruction_start + function.instruction_count
        ? 4u : 0u;
    uint row_bytes = target_byte_length[target_row];
    uint prefix_bytes = row_bytes >= instruction_bytes + footer_bytes
        ? row_bytes - instruction_bytes - footer_bytes : 0u;

    X86ObjectRelocationRow relocation;
    relocation.site_section = SECTION_TEXT;
    X86ArtifactLayout layout = x86_artifact_layout[0u];
    uint wrapper_length = layout.body_offset - layout.text_offset;
    relocation.site_offset = wrapper_length + target_byte_offset[target_row] + prefix_bytes +
        (semantic_lir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL
            ? aggregate_symbol && aggregate_words > 2u ? 8u : 1u
            : 2u);
    relocation.addend_lo = semantic_lir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL ? 0xfffffffcu : 0u;
    relocation.addend_hi = semantic_lir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL ? 0xffffffffu : 0u;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL)
    {
        uint symbol_index = x86_object_symbol_prefix[row];
        relocation.kind = RELOCATION_CALL_REL32;
        relocation.target_kind = TARGET_SYMBOL;
        relocation.target_index = symbol_index;
        relocation.target_offset = 0u;
        X86ObjectUndefinedRow symbol;
        symbol.library_id = operands.a;
        symbol.unit_id = operands.b;
        symbol.local_index = operands.c;
        symbol.reserved = 0u;
        x86_object_undefined_symbols[symbol_index] = symbol;
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

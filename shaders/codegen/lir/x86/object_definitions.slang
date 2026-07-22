import codegen.lowering_ir;
import gpu_index;

struct ObjectIdentity { uint library_id; uint unit_id; uint reserved0; uint reserved1; };
struct Params { uint target_capacity; uint function_capacity; uint artifact_capacity; uint reserved; };
ConstantBuffer<ObjectIdentity> gIdentity;
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> target_function_count;
StructuredBuffer<TargetLirFunction> target_functions;
StructuredBuffer<uint> target_function_index_by_semantic;
StructuredBuffer<uint> target_byte_length;
StructuredBuffer<uint> target_byte_offset;
StructuredBuffer<X86ArtifactLayout> x86_artifact_layout;
StructuredBuffer<uint> x86_object_definition_flag;
StructuredBuffer<uint> x86_object_definition_prefix;
RWStructuredBuffer<X86ObjectDefinitionRow> x86_object_definitions;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint SECTION_TEXT = 1u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint function_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint semantic_count = min(semantic_lir_function_total[0u], gParams.function_capacity);
    if (function_id >= semantic_count || x86_object_definition_flag[function_id] == 0u) return;
    uint function_index = target_function_index_by_semantic[function_id];
    uint function_count = min(target_function_count[0u], gParams.function_capacity);
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

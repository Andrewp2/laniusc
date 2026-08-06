import hir_records;
import codegen.lir.semantic.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirRange> compact_param_ranges;
StructuredBuffer<uint> compact_const_value;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<uint> semantic_function_flag;
StructuredBuffer<uint> semantic_function_prefix;
StructuredBuffer<uint> semantic_local_prefix;
StructuredBuffer<uint> semantic_local_total;
StructuredBuffer<uint> semantic_function_return_type_by_hir;
StructuredBuffer<uint> semantic_function_result_word_count_by_hir;
StructuredBuffer<uint> semantic_function_entrypoint_by_hir;
StructuredBuffer<uint> semantic_function_host_service_by_hir;
StructuredBuffer<uint> public_decl_index_by_hir;
StructuredBuffer<uint> semantic_value_type_by_hir;
StructuredBuffer<uint> semantic_struct_hir_by_name_token;
StructuredBuffer<uint> semantic_struct_word_count_by_hir;
RWStructuredBuffer<SemanticLirFunction> semantic_lir_functions;
RWStructuredBuffer<uint> semantic_function_id_by_token;
RWStructuredBuffer<uint> semantic_const_function_by_root;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 1048576u;

bool valid_token(uint token) { return token != LIR_INVALID && token < gParams.n_tokens; }

uint public_impl_method_symbol(uint hir, uint hir_count)
{
    uint method_count = min(compact_method_count[0u], hir_count);
    for (uint row = 0u; row < method_count; row += 1u)
    {
        HirMethodCore method = compact_method_cores[row];
        HirMethodSignature signature = compact_method_signatures[row];
        // Method symbols share the object identity namespace with public
        // declarations, using a disjoint high-bit namespace.  Trait contracts
        // have no implementation node and therefore produce no definition.
        if (method.node == hir && method.impl_node != LIR_INVALID &&
            (signature.metadata & 0xffffu) == 1u)
            return 0x80000000u | hir;
    }
    return LIR_INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint hir = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (hir >= hir_count || semantic_function_flag[hir] == 0u) return;

    uint function_id = semantic_function_prefix[hir];
    HirCore core = compact_hir_core[hir];
    HirPayload payload = compact_hir_payload[hir];
    bool constant = core.kind == HIR_CONST_ITEM;
    HirRange range = compact_param_ranges[hir];
    SemanticLirFunction result;
    result.hir_function = hir;
    result.name_token = payload.b;
    result.param_start = range.count == 0u ? LIR_INVALID : range.start;
    result.param_count = range.count;
    result.result_type = constant ? semantic_value_type_by_hir[hir]
        : semantic_function_return_type_by_hir[hir];
    result.result_word_count = semantic_function_result_word_count_by_hir[hir];
    if (result.result_word_count == 0u &&
        result.result_type >= TY_STRUCT_BASE && result.result_type < TY_ENUM_BASE)
    {
        uint name_token = result.result_type - TY_STRUCT_BASE;
        uint struct_hir = valid_token(name_token)
            ? semantic_struct_hir_by_name_token[name_token] : LIR_INVALID;
        if (struct_hir < hir_count)
            result.result_word_count = semantic_struct_word_count_by_hir[struct_hir];
    }
    result.flags = !constant && semantic_function_entrypoint_by_hir[hir] != 0u
        ? SEMANTIC_FUNCTION_FLAG_ENTRYPOINT : 0u;
    result.file_id = compact_hir_links[hir].file_id;
    uint local_start = semantic_local_prefix[hir];
    uint local_end = compact_hir_links[hir].subtree_end < hir_count
        ? semantic_local_prefix[compact_hir_links[hir].subtree_end]
        : semantic_local_total[0u];
    result.local_start = local_start;
    result.local_count = local_end - local_start;
    uint symbol_local_index = constant ? LIR_INVALID : public_decl_index_by_hir[hir];
    if (!constant && symbol_local_index == LIR_INVALID)
        symbol_local_index = public_impl_method_symbol(hir, hir_count);
    result.symbol_local_index = symbol_local_index;
    result.symbol_flags = 0u;
    result.host_service = semantic_function_host_service_by_hir[hir];
    semantic_lir_functions[function_id] = result;

    // Type checking deliberately exposes backend call targets in the
    // function-start-token domain. Translate that boundary once, here, so all
    // downstream LIR uses compact function IDs.
    if (valid_token(core.token_start)) semantic_function_id_by_token[core.token_start] = function_id;
    if (valid_token(payload.b)) semantic_function_id_by_token[payload.b] = function_id;
    if (constant && compact_const_value[hir] < hir_count)
        semantic_const_function_by_root[compact_const_value[hir]] = function_id;
}

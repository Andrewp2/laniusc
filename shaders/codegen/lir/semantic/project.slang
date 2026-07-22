import gpu_index;
import codegen.lowering_ir;

struct Params { uint n_tokens; uint n_hir_nodes; uint reserved0; uint reserved1; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct CheckedCallArtifact
{
    uint target_token;
    uint dependency_decl;
    uint intrinsic_tag;
    uint return_type;
    uint receiver_hir;
    uint arg_count;
    uint return_ref_tag;
    uint return_ref_payload;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_expr_root;
StructuredBuffer<uint> semantic_value_decl_by_hir;
StructuredBuffer<uint> semantic_value_type_by_hir;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;
StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
StructuredBuffer<uint> dependency_counts;
StructuredBuffer<uint> dependency_declaration_library_id;
StructuredBuffer<uint> dependency_declaration_unit_id;
StructuredBuffer<uint> dependency_declaration_local_index;
StructuredBuffer<uint> semantic_enclosing_fn_by_hir;
StructuredBuffer<uint> semantic_function_flag;
StructuredBuffer<uint> semantic_function_prefix;
StructuredBuffer<uint> semantic_function_id_by_token;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> semantic_const_function_by_root;
RWStructuredBuffer<uint> semantic_value_id;
RWStructuredBuffer<uint> semantic_value_type;
RWStructuredBuffer<uint> semantic_call_target;
RWStructuredBuffer<uint> semantic_call_kind;
RWStructuredBuffer<uint> semantic_call_result_type;
RWStructuredBuffer<uint> semantic_call_receiver;
RWStructuredBuffer<uint> semantic_call_symbol_library_id;
RWStructuredBuffer<uint> semantic_call_symbol_unit_id;
RWStructuredBuffer<uint> semantic_call_symbol_local_index;
RWStructuredBuffer<uint> semantic_call_arg_count_by_hir;
RWStructuredBuffer<uint> semantic_function_id;

static const uint INVALID = 0xffffffffu;
static const uint SEMANTIC_CALL_NONE = 0u;
static const uint SEMANTIC_CALL_FUNCTION = 1u;
static const uint SEMANTIC_CALL_INTRINSIC = 2u;
static const uint SEMANTIC_CALL_HOST = 3u;
static const uint SEMANTIC_CALL_SYMBOL = 4u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_CONST_ITEM = 25u;
static const uint HIR_EXPR_NAME = 2u;
static const uint DISPATCH_X_STRIDE = 16776960u;

bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

uint host_service_for_name_token(uint token)
{
    if (!valid_token(token)) return INVALID;
    uint name_id = name_id_by_token[token];
    // Slot 52 is compiler-only array data projection. Numeric conversion at
    // slot 28 intentionally crosses this ABI classifier, then target lowering
    // selects a native instruction instead of an imported/runtime call.
    for (uint symbol = HOST_SERVICE_FIRST; symbol < HOST_SERVICE_END; ++symbol)
    {
        if (symbol == HOST_SERVICE_I32_ARRAY_DATA_PTR) continue;
        if (language_name_id[symbol] == name_id) return symbol;
    }
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (node >= gParams.n_hir_nodes) return;
    semantic_value_id[node] = semantic_value_decl_by_hir[node];
    semantic_value_type[node] = semantic_value_type_by_hir[node];
    semantic_call_target[node] = INVALID;
    semantic_call_kind[node] = SEMANTIC_CALL_NONE;
    semantic_call_result_type[node] = INVALID;
    semantic_call_receiver[node] = INVALID;
    semantic_call_symbol_library_id[node] = INVALID;
    semantic_call_symbol_unit_id[node] = INVALID;
    semantic_call_symbol_local_index[node] = INVALID;
    semantic_call_arg_count_by_hir[node] = 0u;
    semantic_function_id[node] = INVALID;
    uint count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (node >= count) return;

    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    // Type checking uses zero as the interval-scan sentinel and stores dense
    // HIR function identity plus one. Semantic LIR owns decoded identities;
    // top-level executable rows must not form a fake fn 0.
    uint encoded_fn = semantic_enclosing_fn_by_hir[node];
    uint hir_function = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    semantic_function_id[node] = hir_function < gParams.n_hir_nodes &&
        semantic_function_flag[hir_function] != 0u
        ? semantic_function_prefix[hir_function] : INVALID;
    if (semantic_function_flag[node] != 0u && core.kind == HIR_CONST_ITEM)
        semantic_function_id[node] = semantic_function_prefix[node];
    if (semantic_function_id[node] == INVALID)
    {
        uint root = compact_expr_root[node];
        if (root < count) semantic_function_id[node] = semantic_const_function_by_root[root];
    }
    if (core.kind == HIR_CALL_EXPR && valid_token(core.token_start))
    {
        CheckedCallArtifact checked = semantic_calls_by_hir[node];
        if (checked.intrinsic_tag != 0u)
        {
            semantic_call_kind[node] = SEMANTIC_CALL_INTRINSIC;
            semantic_call_target[node] = checked.intrinsic_tag;
        }
        else
        {
            uint target = valid_token(checked.target_token)
                ? semantic_function_id_by_token[checked.target_token] : INVALID;
            if (target != INVALID)
            {
                SemanticLirFunction function = semantic_lir_functions[target];
                uint target_hir = function.hir_function;
                bool external = target_hir < count &&
                    compact_hir_payload[target_hir].a == 5u;
                uint service = external
                    ? host_service_for_name_token(function.name_token) : INVALID;
                semantic_call_kind[node] = service != INVALID
                    ? SEMANTIC_CALL_HOST : SEMANTIC_CALL_FUNCTION;
                semantic_call_target[node] = service != INVALID ? service : target;
                semantic_call_result_type[node] = function.result_type;
                semantic_call_receiver[node] = checked.receiver_hir;
            }
            else
            {
                uint dependency = checked.dependency_decl;
                uint dependency_count = dependency_counts[3u];
                if (dependency < dependency_count)
                {
                    semantic_call_kind[node] = SEMANTIC_CALL_SYMBOL;
                    semantic_call_symbol_library_id[node] =
                        dependency_declaration_library_id[dependency];
                    semantic_call_symbol_unit_id[node] =
                        dependency_declaration_unit_id[dependency];
                    semantic_call_symbol_local_index[node] =
                        dependency_declaration_local_index[dependency];
                    semantic_call_result_type[node] = checked.return_type;
                    semantic_call_receiver[node] = checked.receiver_hir;
                }
            }
        }
        semantic_call_arg_count_by_hir[node] = checked.arg_count +
            (semantic_call_receiver[node] != INVALID ? 1u : 0u);
    }
    else if ((core.kind == HIR_NAME_EXPR || payload.a == HIR_EXPR_NAME) &&
             semantic_value_id[node] < gParams.n_tokens)
    {
        uint target = semantic_function_id_by_token[semantic_value_id[node]];
        if (target < count)
        {
            uint target_hir = semantic_lir_functions[target].hir_function;
            if (target_hir < count && compact_hir_core[target_hir].kind == HIR_CONST_ITEM)
            {
                semantic_call_kind[node] = SEMANTIC_CALL_FUNCTION;
                semantic_call_target[node] = target;
                semantic_call_result_type[node] = semantic_value_type[node];
            }
        }
    }
}

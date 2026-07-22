// Scatter dependency parameter rows from compact call-argument rows.

import gpu_index;

struct Params
{
    uint declaration_count;
    uint import_capacity;
    uint visible_capacity;
    uint lookup_capacity;
    uint source_len;
    uint path_capacity;
    uint namespace;
    uint hir_capacity;
};
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirCallArg { uint call; uint value; uint ordinal; uint file_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> call_dependency_decl;
StructuredBuffer<uint> dependency_declaration_words;
StructuredBuffer<uint> dependency_type_words;
StructuredBuffer<uint> dependency_type_edge_words;
StructuredBuffer<uint> canonical_type_roots;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
RWStructuredBuffer<uint> call_param_row_node;
RWStructuredBuffer<uint> call_param_row_fn_token;
RWStructuredBuffer<uint> call_param_row_ordinal;
RWStructuredBuffer<uint> call_param_row_type;
RWStructuredBuffer<uint> call_param_row_ref_tag;
RWStructuredBuffer<uint> call_param_row_ref_payload;
RWStructuredBuffer<uint> call_param_row_start;
RWStructuredBuffer<uint> call_param_row_count;

static const uint INVALID = 0xffffffffu;
static const uint DECL_WORDS = 14u;
static const uint TYPE_WORDS = 9u;
static const uint INTERFACE_TYPE_SCALAR = 1u;
static const uint INTERFACE_TYPE_GENERIC_PARAMETER = 2u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint TYPE_REF_EXTERNAL_GENERIC = 6u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint hir_count() { return min(gParams.hir_capacity, compact_hir_count[0u]); }
uint arg_count() { return min(gParams.hir_capacity, compact_call_arg_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < hir_count(); }
uint callee_token(uint call)
{
    if (!valid_hir(call) || compact_hir_core[call].kind != HIR_CALL_EXPR) return INVALID;
    uint callee = compact_hir_payload[call].a;
    if (!valid_hir(callee)) return INVALID;
    HirCore core = compact_hir_core[callee];
    HirPayload payload = compact_hir_payload[callee];
    uint token = core.kind == HIR_MEMBER_EXPR ? payload.c : payload.d;
    if (token >= gParams.visible_capacity) token = core.token_start;
    return token < gParams.visible_capacity ? token : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint arg_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (arg_row >= arg_count()) return;
    HirCallArg arg = compact_call_args[arg_row];
    if (!valid_hir(arg.call) || !valid_hir(arg.value)) return;
    uint token = callee_token(arg.call);
    if (token == INVALID) return;
    uint declaration_i = call_dependency_decl[token];
    if (declaration_i == INVALID || declaration_i >= gParams.declaration_count) return;
    uint count = call_param_count[token];
    uint start = call_param_row_start[token];
    uint row = start + arg.ordinal;
    if (start == INVALID || arg.ordinal >= count || row < start ||
        row >= call_param_row_count_out[0u] || row >= gParams.hir_capacity) return;

    uint signature_i = dependency_declaration_words[declaration_i * DECL_WORDS + 7u];
    uint signature_base = signature_i * TYPE_WORDS;
    uint edge_start = dependency_type_words[signature_base + 3u];
    uint type_i = canonical_type_roots[dependency_type_edge_words[edge_start + arg.ordinal]];
    uint type_base = type_i * TYPE_WORDS;
    uint kind = dependency_type_words[type_base];
    uint tag = TYPE_REF_EXTERNAL_CANONICAL;
    uint payload = type_i;
    uint type_code = TY_UNKNOWN;
    if (kind == INTERFACE_TYPE_SCALAR)
    {
        tag = TYPE_REF_SCALAR;
        payload = dependency_type_words[type_base + 1u];
        type_code = payload;
    }
    else if (kind == INTERFACE_TYPE_GENERIC_PARAMETER)
    {
        tag = TYPE_REF_EXTERNAL_GENERIC;
        payload = dependency_type_words[type_base + 1u];
        type_code = TY_GENERIC_BASE;
    }
    call_param_row_node[row] = arg.value;
    call_param_row_fn_token[row] = token;
    call_param_row_ordinal[row] = arg.ordinal;
    call_param_row_type[row] = type_code;
    call_param_row_ref_tag[row] = tag;
    call_param_row_ref_payload[row] = payload;
    if (arg.ordinal == 0u) call_param_row_count[token] = count;
}

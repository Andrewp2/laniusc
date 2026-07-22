// Publish imported function parameter counts from compact call-argument rows.

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
RWStructuredBuffer<uint> call_param_count;

static const uint INVALID = 0xffffffffu;
static const uint DECL_WORDS = 14u;
static const uint TYPE_WORDS = 9u;
static const uint INTERFACE_TYPE_FUNCTION = 7u;
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
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= arg_count()) return;
    HirCallArg arg = compact_call_args[row];
    uint token = callee_token(arg.call);
    if (token == INVALID) return;
    uint declaration_i = call_dependency_decl[token];
    if (declaration_i == INVALID || declaration_i >= gParams.declaration_count) return;
    uint signature_i = dependency_declaration_words[declaration_i * DECL_WORDS + 7u];
    uint signature_base = signature_i * TYPE_WORDS;
    if (dependency_type_words[signature_base] != INTERFACE_TYPE_FUNCTION) return;
    uint edge_count = dependency_type_words[signature_base + 4u];
    uint param_count = edge_count == 0u ? 0u : edge_count - 1u;
    if (arg.ordinal < param_count) call_param_count[token] = param_count;
}

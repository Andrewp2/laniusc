// Check imported call arity once per call HIR row. Argument-row validation
// cannot detect missing arguments because a zero-argument call has no rows.

import dependency_interface;
import hir_records;
import gpu_index;
import status;

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
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> call_dependency_unit_id;
StructuredBuffer<uint> call_dependency_local_index;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint INTERFACE_TYPE_FUNCTION = 7u;
static const uint TYPE_WORDS = 9u;
static const uint DECL_WORDS = 14u;
static const uint ERR_CALL_MISMATCH = 10u;
static const uint CALL_MISMATCH_ARITY = 0xffffff05u;
static const uint DISPATCH_X_STRIDE = 16776960u;

bool valid_hir(uint node)
{
    return node != INVALID && node < min(compact_hir_count[0u], gParams.hir_capacity);
}

uint callee_token(uint call)
{
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
    uint call = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(call) || compact_hir_core[call].kind != HIR_CALL_EXPR)
        return;
    uint token = callee_token(call);
    if (token == INVALID) return;
    uint declaration = dependency_find_declaration(
        call_dependency_library_id[token],
        call_dependency_unit_id[token],
        call_dependency_local_index[token]);
    if (declaration >= dependency_declaration_count()) return;
    uint signature = dependency_declaration_word(declaration * DECL_WORDS + 7u);
    if (signature >= dependency_type_count()) return;
    uint signature_base = signature * TYPE_WORDS;
    if (dependency_type_word(signature_base) != INTERFACE_TYPE_FUNCTION) return;
    uint edge_count = dependency_type_word(signature_base + 4u);
    if (edge_count == 0u) return;
    uint actual = max(compact_hir_payload[call].c, call_arg_row_count[call]);
    if (actual != edge_count - 1u)
        record_min_token_error(
            status, token, ERR_CALL_MISMATCH, CALL_MISMATCH_ARITY);
}

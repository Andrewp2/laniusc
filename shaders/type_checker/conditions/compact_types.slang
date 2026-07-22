// Validate resolved type references from dense compact HIR. Method-contract
// generic failures are classified through the compact method family rather
// than raw production IDs or raw ancestor links.

import fixed.compact_method;
import gpu_index;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct TokenIn { uint kind; uint start; uint len; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<CompactMethodCore> compact_method_cores;
StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> predicate_syntax_token;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_const_param_slot_by_token;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint TK_BOUND_TYPE_IDENT = 174u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_ERROR = 4u;
static const uint TYPE_LEN_CONST_PARAM = 2u;
static const uint ERR_UNKNOWN_TYPE = 1u;
static const uint ERR_UNRESOLVED_IDENT = 2u;
static const uint ERR_BAD_HIR = 6u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC = 16u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
uint active_method_count() { return min(gParams.n_hir_nodes, compact_method_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

uint enclosing_method_row(uint token)
{
    if (!valid_token(token)) return INVALID;
    uint encoded = enclosing_fn[token];
    uint fn = encoded == 0u ? INVALID : encoded - 1u;
    if (!valid_hir(fn)) return INVALID;
    return compact_method_row_for_hir(
        compact_method_cores,
        active_method_count(),
        fn);
}

bool record_method_generic_error(uint token)
{
    uint row = enclosing_method_row(token);
    uint count = active_method_count();
    if (row >= count) return false;
    uint error_token = compact_method_cores[row].name_token;
    record_min_token_error(
        status,
        valid_token(error_token) ? error_token : token,
        ERR_BAD_HIR,
        PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC);
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(node) || compact_hir_core[node].kind != HIR_TYPE) return;

    uint token = compact_hir_core[node].token_start;
    if (!valid_token(token) || predicate_syntax_token[token] != 0u ||
        token_words[token].kind == TK_BOUND_TYPE_IDENT)
        return;

    uint tag = type_expr_ref_tag[token];
    uint payload = type_expr_ref_payload[token];
    if (tag == TYPE_REF_ERROR)
    {
        record_min_token_error(status, token, ERR_UNKNOWN_TYPE, payload);
        return;
    }

    if (tag == TYPE_REF_GENERIC_PARAM &&
        (!valid_token(payload) || type_generic_param_slot_by_token[payload] == INVALID))
    {
        if (!record_method_generic_error(token))
            record_min_token_error(status, token, ERR_UNRESOLVED_IDENT, 0u);
    }

    if (compact_hir_payload[node].a == HIR_TYPE_FORM_ARRAY &&
        type_instance_len_kind[token] == TYPE_LEN_CONST_PARAM)
    {
        uint len_token = type_instance_len_payload[token];
        if (!valid_token(len_token) || type_const_param_slot_by_token[len_token] == INVALID)
            record_min_token_error(status, token, ERR_UNRESOLVED_IDENT, len_token);
    }
}

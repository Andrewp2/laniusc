// Diagnose unsupported method-signature forms from the compact method family.
// One lane owns one dense method row; no raw production or ancestor lookup is
// needed after canonical HIR has published the signature metadata.

import fixed.compact_method;
import gpu_index;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirMethodSignature
{
    uint first_param_token;
    uint impl_receiver_type;
    uint receiver_mode;
    uint metadata;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<CompactMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint METHOD_SIGNATURE_HAS_GENERICS = 1u;
static const uint METHOD_SIGNATURE_HAS_WHERE = 2u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC = 16u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE = 17u;
static const uint ERR_BAD_HIR = 6u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_method_count()
{
    return min(gParams.n_hir_nodes, compact_method_count[0u]);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= active_method_count()) return;

    uint flags = compact_method_signatures[row].metadata >> 16u;
    uint detail = (flags & METHOD_SIGNATURE_HAS_GENERICS) != 0u
                      ? PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC
                      : ((flags & METHOD_SIGNATURE_HAS_WHERE) != 0u
                             ? PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE
                             : 0u);
    if (detail == 0u) return;

    uint token = compact_method_cores[row].name_token;
    record_min_token_error(status, valid_token(token) ? token : 0u, ERR_BAD_HIR, detail);
}

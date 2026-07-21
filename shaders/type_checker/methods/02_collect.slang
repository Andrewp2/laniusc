// Project compact inherent-method rows into token-keyed lookup metadata.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct HirMethodCore { uint node; uint owner; uint impl_node; uint name_token; };
struct HirMethodSignature
{
    uint first_param_token;
    uint impl_receiver_type;
    uint receiver_mode;
    uint metadata;
};
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;

RWStructuredBuffer<uint> method_decl_method_row;
RWStructuredBuffer<uint> method_decl_name_token;
RWStructuredBuffer<uint> method_decl_param_offset;
RWStructuredBuffer<uint> method_decl_receiver_mode;
RWStructuredBuffer<uint> method_decl_visibility;
RWStructuredBuffer<uint> method_decl_signature_flags;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint METHOD_SIGNATURE_INHERENT_IMPL = 4u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_method_count()
{
    return min(compact_method_count[0u], gParams.n_hir_nodes);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= active_method_count())
        return;

    HirMethodCore core = compact_method_cores[row];
    HirMethodSignature signature = compact_method_signatures[row];
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint flags = signature.metadata >> 16u;
    if (core.node >= hir_count || core.impl_node >= hir_count ||
        (flags & METHOD_SIGNATURE_INHERENT_IMPL) == 0u)
        return;

    // Method metadata shares the canonical declaration-name token domain with
    // compact function HIR, enclosing-function context, call resolution, and
    // backend ABI records. The function span anchor is not an identity.
    uint fn_token = core.name_token;
    if (!valid_token(fn_token))
        return;

    method_decl_method_row[fn_token] = row;
    method_decl_name_token[fn_token] = core.name_token;
    method_decl_param_offset[fn_token] = signature.first_param_token;
    method_decl_receiver_mode[fn_token] = signature.receiver_mode;
    method_decl_visibility[fn_token] = signature.metadata & 0xffffu;
    method_decl_signature_flags[fn_token] = flags;
}

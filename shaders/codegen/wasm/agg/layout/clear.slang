// Clear aggregate-layout metadata for the HIR/type-driven WASM aggregate path.
//
// This pass is deliberately metadata-only. It does not inspect source bytes,
// compare token spelling, or accept/reject programs.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> struct_field_count_by_decl_token;
RWStructuredBuffer<uint> struct_field_index_by_token;
RWStructuredBuffer<uint> struct_field_decl_by_token;
RWStructuredBuffer<uint> struct_field_name_id;
RWStructuredBuffer<uint> struct_field_ref_tag;
RWStructuredBuffer<uint> struct_field_ref_payload;
RWStructuredBuffer<uint> struct_field_scalar_offset;
RWStructuredBuffer<uint> struct_field_scalar_width;
RWStructuredBuffer<uint> struct_init_field_index;
RWStructuredBuffer<uint> member_result_field_index;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_id(tid);
    if (i >= gParams.n_tokens)
        return;

    struct_field_count_by_decl_token[i] = 0u;
    struct_field_index_by_token[i] = INVALID;
    struct_field_decl_by_token[i] = INVALID;
    struct_field_name_id[i] = INVALID;
    struct_field_ref_tag[i] = TYPE_REF_INVALID;
    struct_field_ref_payload[i] = INVALID;
    struct_field_scalar_offset[i] = INVALID;
    struct_field_scalar_width[i] = 0u;
    struct_init_field_index[i] = INVALID;
    member_result_field_index[i] = INVALID;
}

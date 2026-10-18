struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> canonical_count;
StructuredBuffer<uint> canonical_dense_to_raw;
StructuredBuffer<uint> hir_type_arg_owner;
StructuredBuffer<uint> hir_type_arg_application_owner;
StructuredBuffer<uint> hir_type_arg_rank;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> hir_kind;
RWStructuredBuffer<uint> family_flag;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_TYPE = 5u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_PATH_EXPR = 33u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
// An argument row is a type, a literal, or a negated literal (`-5`, `-0.0`);
// the links pass seeds owners only for those argument roots.
bool argument_value_kind(uint kind)
{ return kind == HIR_TYPE || kind == HIR_LITERAL_EXPR || kind == HIR_UNARY_EXPR; }
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID) {
    uint dense = tid(dtid);
    if (dense >= gCanonical.canonical_capacity) return;
    uint raw = dense < min(canonical_count[0u], gCanonical.canonical_capacity)
        ? canonical_dense_to_raw[dense]
        : INVALID;
    if (raw >= gCanonical.raw_capacity) return;
    uint seed = hir_type_arg_owner[raw];
    uint owner = seed < gCanonical.raw_capacity ? hir_type_arg_application_owner[seed] : INVALID;
    bool valid_owner = owner < gCanonical.raw_capacity &&
                       (hir_kind[owner] == HIR_TYPE || hir_kind[owner] == HIR_PATH_EXPR ||
                        hir_kind[owner] == HIR_MEMBER_EXPR);
    if (!argument_value_kind(hir_kind[raw]) || !valid_owner || owner == raw ||
        hir_type_arg_rank[raw] >= gCanonical.canonical_capacity) return;
    uint head = raw_to_hir[seed];
    if (head >= min(canonical_count[0u], gCanonical.canonical_capacity)) return;
    // Allocate one contiguous span per application. Nested arguments may
    // interleave in semantic HIR; source ordinals place them in their own span.
    uint ignored;
    InterlockedMax(family_flag[head], hir_type_arg_rank[raw] + 1u, ignored);
}

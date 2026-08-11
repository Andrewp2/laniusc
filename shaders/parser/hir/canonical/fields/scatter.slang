import hir_records;
import prefix_scan;
import canonical_hir_identity;
import generated_parse_production_ids;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_flag;
StructuredBuffer<uint> family_local_prefix;
StructuredBuffer<uint> family_block_prefix;
StructuredBuffer<uint> candidate_raw_by_anchor;
StructuredBuffer<uint> alias_to_hir;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> decl_owner;
StructuredBuffer<uint> decl_ordinal;
StructuredBuffer<uint> decl_type;
StructuredBuffer<uint> literal_owner;
StructuredBuffer<uint> literal_ordinal;
StructuredBuffer<uint> literal_value;
StructuredBuffer<uint> expr_result_root;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirField> hir_fields;
RWStructuredBuffer<uint> field_range_words;
RWStructuredBuffer<uint> canonical_status;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_FILE = 1u;
static const uint HIR_EXPR = 14u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_POSTFIX_EXPR = 18u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.canonical_capacity + 255u) / 256u; }
uint mapped(uint raw)
{
    return raw < gCanonical.raw_capacity ? alias_to_hir[raw] : INVALID;
}
uint mapped_expression(uint raw)
{
    if (raw >= gCanonical.raw_capacity) return INVALID;
    uint root = expr_result_root[raw];
    uint dense = mapped(root);
    return dense != INVALID ? dense : mapped(raw);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint anchor = tid(dtid);
    uint total = inclusive_scan_total(block_count(), family_block_prefix);
    if (anchor == 0u) family_count[0u] = total;
    if (anchor >= gCanonical.canonical_capacity || family_flag[anchor] == 0u) return;
    uint encoded = candidate_raw_by_anchor[anchor];
    uint raw = encoded == 0u ? INVALID : encoded - 1u;
    if (raw >= gCanonical.raw_capacity) return;
    uint block = anchor / 256u;
    uint base = block == 0u ? 0u : family_block_prefix[block - 1u];
    uint row = base + family_local_prefix[anchor];
    if (row >= gCanonical.canonical_capacity)
    {
        uint ignored;
        InterlockedMax(canonical_status[0u], 3u, ignored);
        InterlockedMax(canonical_status[3u], raw + 1u, ignored);
        return;
    }
    bool declaration = node_kind[raw] == PROD_STRUCT_FIELD;
    HirField field;
    uint raw_owner = declaration ? decl_owner[raw] : literal_owner[raw];
    field.owner = mapped(raw_owner);
    field.name_token = hir_token_pos[raw];
    uint raw_value = declaration ? decl_type[raw] : literal_value[raw];
    field.value = declaration ? mapped(raw_value) : mapped_expression(raw_value);
    field.ordinal = declaration ? decl_ordinal[raw] : literal_ordinal[raw];
    hir_fields[row] = field;
    if (!declaration && field.owner != INVALID &&
        field.owner < gCanonical.canonical_capacity && field.ordinal != INVALID)
    {
        uint ignored;
        InterlockedMin(field_range_words[field.owner * 2u], row, ignored);
        InterlockedMax(field_range_words[field.owner * 2u + 1u], field.ordinal + 1u, ignored);
    }
}

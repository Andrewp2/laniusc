// Export private types that an exported type's layout needs as hidden
// declarations.
//
// A field or enum-variant payload of an exported struct or enum may name a
// private struct, enum or alias of this unit. Such a type gets an interface
// index after the public partition, so an importer can size, copy and store
// values and read their fields. The identity record marks it
// DECL_FLAG_HIDDEN, and importers leave it out of name lookup.
//
// This pass marks the hidden declarations; 03_hidden_count and
// 04_hidden_publish give them their indices. One lane per field row and per
// variant payload row of a public declaration walks that type tree. A private
// nominal it names is claimed with a compare-exchange on its local index, so
// every hidden declaration is claimed by exactly one lane, and that lane walks
// the declaration's own fields, payloads and alias target in turn. A lane
// keeps its claimed, unwalked declarations as a stack linked through
// interface_public_decl_index_by_hir (MARK | next local), which publishing
// overwrites. Every declaration is walked at most once, all in one dispatch.
//
// Dispatch after module paths have resolved and type instances have been
// projected, and before the canonical early stage: canonical keys name a
// local nominal by this index, and only hidden locals change, from INVALID.
import hir_records;
import native_c_abi;

StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
StructuredBuffer<uint> compact_type_alias_target;
StructuredBuffer<uint> compact_fn_return_type;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<HirRange> compact_param_ranges;
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<HirPath> compact_paths;
StructuredBuffer<uint> compact_path_segment_count;
StructuredBuffer<HirPathSegment> compact_path_segments;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_id_by_owner_token;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<NativeAbiToken> token_words;
ByteAddressBuffer source_bytes;
globallycoherent RWStructuredBuffer<uint> interface_public_decl_index_by_local;
globallycoherent RWStructuredBuffer<uint> interface_public_decl_index_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint MARK = 0x80000000u;
static const uint HIR_TYPE = 5u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint KIND_STRUCT = 6u;
static const uint KIND_ENUM = 7u;
static const uint KIND_TYPE_ALIAS = 8u;
static const uint KIND_FUNCTION = 5u;
static const uint STACK_END = 0x7fffffffu;
static const uint MAX_GROUPS_X = 65535u;

uint decl_capacity()
{
    uint count; uint stride;
    interface_public_decl_index_by_local.GetDimensions(count, stride);
    return count;
}

uint token_capacity()
{
    uint count; uint stride;
    type_expr_ref_tag.GetDimensions(count, stride);
    return count;
}

uint hir_capacity()
{
    uint count; uint stride;
    compact_hir_core.GetDimensions(count, stride);
    return count;
}

uint active_hir() { return min(compact_hir_count[0u], hir_capacity()); }
uint active_decls() { return min(decl_count_out[0u], decl_capacity()); }

uint instance_local(uint token)
{
    uint tokens = token_capacity();
    if (token >= tokens || type_expr_ref_tag[token] != TYPE_REF_INSTANCE) return INVALID;
    uint instance = type_expr_ref_payload[token];
    uint declaration = instance < tokens ? type_instance_decl_token[instance] : INVALID;
    return declaration < tokens ? decl_id_by_name_token[declaration] : INVALID;
}

uint path_local(uint token)
{
    if (token >= token_capacity()) return INVALID;
    uint path = path_id_by_owner_token[token];
    return path < hir_capacity() ? resolved_type_decl[path] : INVALID;
}

// The local declaration a HIR type node names (type_topology
// 10_resolve_local_decl): its resolved path, else its checked instance, then
// the same for the leaf segment of a qualified path.
uint type_node_local(uint node)
{
    uint token = compact_hir_core[node].token_start;
    uint local = path_local(token);
    if (local >= decl_capacity()) local = instance_local(token);
    if (local < decl_capacity()) return local;
    uint paths = min(compact_path_count[0u], hir_capacity());
    uint path = path_id_by_owner_hir[node];
    if (path >= paths)
    {
        uint owner = compact_hir_payload[node].b;
        path = owner < hir_capacity() ? path_id_by_owner_hir[owner] : INVALID;
    }
    if (path >= paths) return INVALID;
    HirPath record = compact_paths[path];
    uint segments = min(compact_path_segment_count[0u], token_capacity());
    if (record.segment_count == 0u || record.segment_start >= segments ||
        record.segment_count > segments - record.segment_start)
        return INVALID;
    uint leaf = compact_path_segments[record.segment_start + record.segment_count - 1u].name_token;
    local = path_local(leaf);
    if (local >= decl_capacity()) local = instance_local(leaf);
    return local;
}

// Claim a private nominal for the hidden partition and push it on this
// lane's stack.
void claim(uint local, inout uint top)
{
    if (local >= active_decls()) return;
    uint kind = decl_kind[local];
    if (kind != KIND_STRUCT && kind != KIND_ENUM && kind != KIND_TYPE_ALIAS) return;
    uint prior;
    InterlockedCompareExchange(interface_public_decl_index_by_local[local], INVALID, MARK, prior);
    if (prior != INVALID) return;
    uint hir = decl_hir_node[local];
    // Without its HIR row the declaration has no fields, payloads or alias
    // target to walk.
    if (hir >= active_hir()) return;
    interface_public_decl_index_by_hir[hir] = MARK | top;
    top = local;
}

// Claim every private nominal named in the type tree at `root`.
void walk(uint root, inout uint top)
{
    uint active = active_hir();
    if (root >= active || compact_hir_core[root].kind != HIR_TYPE) return;
    uint end = min(max(compact_hir_links[root].subtree_end, root + 1u), active);
    [loop]
    for (uint node = root; node < end; node++)
        if (compact_hir_core[node].kind == HIR_TYPE) claim(type_node_local(node), top);
}

uint by_hir(uint hir) { return hir < hir_capacity() ? interface_public_decl_index_by_hir[hir] : INVALID; }

// Whether a declaration's fields and payloads are roots: it is public.
bool public_owner(uint hir) { return by_hir(hir) < decl_capacity(); }

uint first_field_row(uint owner, uint fields)
{
    uint lo = 0u;
    uint hi = fields;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_fields[mid].owner < owner) lo = mid + 1u;
        else hi = mid;
    }
    return lo;
}

uint first_variant_row(uint owner, uint variants)
{
    uint lo = 0u;
    uint hi = variants;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_variants[mid].owner < owner) lo = mid + 1u;
        else hi = mid;
    }
    return lo;
}

uint first_payload_row(uint variant, uint payloads)
{
    uint lo = 0u;
    uint hi = payloads;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_variant_payloads[mid].variant < variant) lo = mid + 1u;
        else hi = mid;
    }
    return lo;
}

// Walk the fields, payloads and alias target of a claimed declaration. Field,
// variant and payload rows are ordered by their owner's HIR row.
void walk_declaration(uint local, inout uint top)
{
    uint hir = decl_hir_node[local];
    uint hirs = hir_capacity();
    uint fields = min(compact_field_count[0u], hirs);
    [loop]
    for (uint row = first_field_row(hir, fields);
         row < fields && compact_fields[row].owner == hir; row += 1u)
        walk(compact_fields[row].value, top);
    uint variants = min(compact_variant_count[0u], hirs);
    uint payloads = min(compact_variant_payload_row_count[0u], hirs);
    [loop]
    for (uint variant = first_variant_row(hir, variants);
         variant < variants && compact_variants[variant].owner == hir; variant += 1u)
    {
        [loop]
        for (uint row = first_payload_row(variant, payloads);
             row < payloads && compact_variant_payloads[row].variant == variant; row += 1u)
            walk(compact_variant_payloads[row].type_node, top);
    }
    // A public alias's target is a signature root (LNC0075), not layout; a
    // hidden alias's target is layout.
    if (decl_kind[local] == KIND_TYPE_ALIAS)
        walk(compact_type_alias_target[hir], top);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * MAX_GROUPS_X * 256u;
    uint decls = active_decls();
    uint top = STACK_END;
    // A private C declaration still needs a stable symbol/name/signature for
    // native linking. Keep it in the hidden partition; dependency name lookup
    // continues to exclude it. It is admitted later by the checked C profile.
    // Its signature may name a private record, which that profile reads, so
    // the parameter and result types are roots here too.
    if (row < decls)
    {
        uint hir = decl_hir_node[row];
        uint source_len; source_bytes.GetDimensions(source_len);
        uint tokens; uint token_stride; token_words.GetDimensions(tokens, token_stride);
        if (decl_kind[row] == KIND_FUNCTION && hir < active_hir() &&
            interface_public_decl_index_by_local[row] == INVALID &&
            native_extern_source_abi(compact_hir_core[hir], compact_hir_payload[hir],
                token_words, source_bytes, tokens, source_len) == NATIVE_ABI_C)
        {
            interface_public_decl_index_by_local[row] = MARK;
            interface_public_decl_index_by_hir[hir] = MARK;
            walk(compact_fn_return_type[hir], top);
            HirRange range = compact_param_ranges[hir];
            uint parameters = min(compact_param_count[0u], hir_capacity());
            uint count = range.start < parameters
                ? min(min(range.count, parameters - range.start), NATIVE_C_MAX_PARAMETERS) : 0u;
            [loop]
            for (uint ordinal = 0u; ordinal < count; ordinal += 1u)
                walk(compact_params[range.start + ordinal].type_node, top);
        }
    }

    uint hirs = hir_capacity();
    if (row < min(compact_field_count[0u], hirs))
    {
        HirField field = compact_fields[row];
        if (public_owner(field.owner)) walk(field.value, top);
    }
    uint variants = min(compact_variant_count[0u], hirs);
    if (row < min(compact_variant_payload_row_count[0u], hirs))
    {
        HirVariantPayload payload = compact_variant_payloads[row];
        if (payload.variant < variants && public_owner(compact_variants[payload.variant].owner))
            walk(payload.type_node, top);
    }
    [loop]
    while (top != STACK_END)
    {
        uint local = top;
        top = interface_public_decl_index_by_hir[decl_hir_node[local]] & ~MARK;
        walk_declaration(local, top);
    }
}

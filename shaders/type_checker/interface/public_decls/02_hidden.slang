// Export private types that an exported type's layout needs as hidden
// declarations.
//
// A field or enum-variant payload of an exported struct or enum may name a
// private struct, enum or alias of this unit. Such a type gets an interface
// index after the public partition, so an importer can size, copy and store
// values and read their fields. The identity record marks it
// DECL_FLAG_HIDDEN, and importers leave it out of name lookup.
//
// One workgroup runs the closure to its fixed point. Round 0 walks the
// fields and payloads of public declarations; round r walks the fields,
// payloads and alias targets of the types round r - 1 marked. So each
// declaration's type roots are walked once, and the round count is the
// depth of the private chain. Every round before the last marks at least
// one declaration, so active declarations + 1 rounds always reach the
// fixed point; the bound is sized from the job, and a miss fails closed.
//
// Dispatch after module paths have resolved and type instances have been
// projected, and before the canonical early stage: canonical keys name a
// local nominal by this index, and only hidden locals change, from INVALID.
import hir_records;
import status;

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
globallycoherent RWStructuredBuffer<uint> interface_public_decl_count;
globallycoherent RWStructuredBuffer<uint> interface_public_decl_local_id;
globallycoherent RWStructuredBuffer<uint> interface_public_decl_index_by_local;
globallycoherent RWStructuredBuffer<uint> interface_public_decl_index_by_hir;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint LANES = 256u;
static const uint MARK = 0x80000000u;
static const uint HIR_TYPE = 5u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint KIND_STRUCT = 6u;
static const uint KIND_ENUM = 7u;
static const uint KIND_TYPE_ALIAS = 8u;
static const uint KIND_ENUM_VARIANT = 9u;
static const uint ERR_NAME_LIMIT = 11u;
// "HIDE": the closure did not converge, or hidden indices overflowed.
static const uint HIDDEN_LIMIT_DETAIL = 0x48494445u;

// Three words, so lane 0 clears the next round's word while every lane has
// already read the word it reuses (last read two rounds before).
groupshared uint g_changed[3];
groupshared uint g_marked;
groupshared uint g_scan[LANES];

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

// Whether a declaration's type roots are walked in `round`: public ones in
// round 0, hidden ones in the round after the one that marked them.
bool walks(uint persisted, uint round)
{
    return round == 0u ? persisted < decl_capacity() : persisted == (MARK | (round - 1u));
}

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

void mark(uint local, uint round)
{
    if (local >= active_decls()) return;
    uint kind = decl_kind[local];
    if (kind != KIND_STRUCT && kind != KIND_ENUM && kind != KIND_TYPE_ALIAS) return;
    uint prior;
    InterlockedCompareExchange(interface_public_decl_index_by_local[local], INVALID, MARK | round, prior);
    if (prior != INVALID) return;
    uint hir = decl_hir_node[local];
    if (hir < hir_capacity()) interface_public_decl_index_by_hir[hir] = MARK | round;
    InterlockedOr(g_changed[round % 3u], 1u);
    InterlockedAdd(g_marked, 1u);
}

// Mark every private nominal named in the type tree at `root`.
void walk(uint root, uint round)
{
    uint active = active_hir();
    if (root >= active || compact_hir_core[root].kind != HIR_TYPE) return;
    uint end = min(max(compact_hir_links[root].subtree_end, root + 1u), active);
    [loop]
    for (uint node = root; node < end; node++)
        if (compact_hir_core[node].kind == HIR_TYPE) mark(type_node_local(node), round);
}

uint by_hir(uint hir) { return hir < hir_capacity() ? interface_public_decl_index_by_hir[hir] : INVALID; }

void walk_round(uint lane, uint round)
{
    uint hirs = hir_capacity();
    uint fields = min(compact_field_count[0u], hirs);
    [loop]
    for (uint row = lane; row < fields; row += LANES)
    {
        HirField field = compact_fields[row];
        if (walks(by_hir(field.owner), round)) walk(field.value, round);
    }
    uint variants = min(compact_variant_count[0u], hirs);
    uint payloads = min(compact_variant_payload_row_count[0u], hirs);
    [loop]
    for (uint row = lane; row < payloads; row += LANES)
    {
        HirVariantPayload payload = compact_variant_payloads[row];
        if (payload.variant < variants && walks(by_hir(compact_variants[payload.variant].owner), round))
            walk(payload.type_node, round);
    }
    uint decls = active_decls();
    [loop]
    for (uint local = lane; local < decls; local += LANES)
    {
        uint hir = decl_hir_node[local];
        // A public alias's target is a signature root (LNC0075), not layout.
        if (round != 0u && decl_kind[local] == KIND_TYPE_ALIAS && hir < hirs &&
            walks(interface_public_decl_index_by_local[local], round))
            walk(compact_type_alias_target[hir], round);
    }
}

bool marked(uint persisted) { return persisted != INVALID && persisted >= MARK; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 group: SV_GroupID, uint lane: SV_GroupIndex)
{
    if (any(group != uint3(0u, 0u, 0u))) return;
    if (lane == 0u) { g_changed[0u] = 0u; g_changed[1u] = 0u; g_changed[2u] = 0u; g_marked = 0u; }
    GroupMemoryBarrierWithGroupSync();
    uint decls = active_decls();
    uint rounds = decls + 1u;
    bool converged = false;
    [loop]
    for (uint round = 0u; round < rounds; round++)
    {
        if (lane == 0u) g_changed[(round + 1u) % 3u] = 0u;
        walk_round(lane, round);
        AllMemoryBarrierWithGroupSync();
        if (g_changed[round % 3u] == 0u) { converged = true; break; }
    }
    if (!converged)
    {
        if (lane == 0u) record_min_token_error(status, 0u, ERR_NAME_LIMIT, HIDDEN_LIMIT_DETAIL);
        return;
    }
    if (g_marked == 0u) return;
    // The variants of a hidden enum are hidden with it.
    [loop]
    for (uint local = lane; local < decls; local += LANES)
    {
        uint parent = decl_parent_type_decl[local];
        if (decl_kind[local] == KIND_ENUM_VARIANT && parent < decls &&
            marked(interface_public_decl_index_by_local[parent]) &&
            interface_public_decl_index_by_local[local] == INVALID)
            interface_public_decl_index_by_local[local] = MARK;
    }
    AllMemoryBarrierWithGroupSync();
    // Hidden indices follow the public partition in local declaration order.
    uint next = interface_public_decl_count[0u];
    uint capacity = decl_capacity();
    [loop]
    for (uint base = 0u; base < decls; base += LANES)
    {
        uint local = base + lane;
        uint flag = local < decls && marked(interface_public_decl_index_by_local[local]) ? 1u : 0u;
        g_scan[lane] = flag;
        GroupMemoryBarrierWithGroupSync();
        [loop]
        for (uint step = 1u; step < LANES; step <<= 1u)
        {
            uint add = lane >= step ? g_scan[lane - step] : 0u;
            GroupMemoryBarrierWithGroupSync();
            g_scan[lane] += add;
            GroupMemoryBarrierWithGroupSync();
        }
        uint persisted = next + g_scan[lane] - flag;
        if (flag != 0u)
        {
            if (persisted < capacity)
            {
                interface_public_decl_local_id[persisted] = local;
                interface_public_decl_index_by_local[local] = persisted;
                uint hir = decl_hir_node[local];
                if (decl_kind[local] != KIND_ENUM_VARIANT && hir < hir_capacity())
                    interface_public_decl_index_by_hir[hir] = persisted;
            }
            else
            {
                interface_public_decl_index_by_local[local] = INVALID;
                record_min_token_error(status, 0u, ERR_NAME_LIMIT, HIDDEN_LIMIT_DETAIL);
            }
        }
        next += g_scan[LANES - 1u];
        GroupMemoryBarrierWithGroupSync();
    }
    if (lane == 0u) interface_public_decl_count[0u] = min(next, capacity);
}

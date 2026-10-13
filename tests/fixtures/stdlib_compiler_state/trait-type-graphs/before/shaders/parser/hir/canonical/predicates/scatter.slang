import hir_records;
import generated_parse_production_ids;
import prefix_scan;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_flag;
StructuredBuffer<uint> family_local_prefix;
StructuredBuffer<uint> family_block_prefix;
StructuredBuffer<uint> canonical_count;
StructuredBuffer<uint> canonical_dense_to_raw;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> subject_anchor;
StructuredBuffer<uint> owner_value;
StructuredBuffer<HirLinks> hir_links;
RWStructuredBuffer<HirPayload> hir_payload;
RWStructuredBuffer<HirSemanticFacts> hir_canonical_semantic_facts;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirPredicate> predicates;
RWStructuredBuffer<uint> canonical_status;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint PREDICATE_GENERIC_BOUND = 1u;
static const uint PREDICATE_TRAIT_IMPL = 2u;
static const uint HIR_IMPL_TRAIT = 2u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.canonical_capacity + 255u) / 256u; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint dense = tid(dtid);
    uint total = inclusive_scan_total(block_count(), family_block_prefix);
    if (dense == 0u) family_count[0u] = total;
    if (dense >= min(canonical_count[0u], gCanonical.canonical_capacity) ||
        family_flag[dense] == 0u) return;
    uint raw = canonical_dense_to_raw[dense];
    uint block = dense / 256u;
    uint row = (block == 0u ? 0u : family_block_prefix[block - 1u]) + family_local_prefix[dense];
    if (row >= gCanonical.canonical_capacity)
    {
        uint ignored;
        InterlockedMax(canonical_status[0u], 3u, ignored);
        InterlockedMax(canonical_status[3u], raw + 1u, ignored);
        return;
    }

    HirPredicate predicate;
    uint bound = raw_to_hir[raw];
    uint kind = PREDICATE_GENERIC_BOUND;
    predicate.bound = bound;
    uint owner_raw = owner_value[dense];
    predicate.owner = owner_raw < gCanonical.raw_capacity ? raw_to_hir[owner_raw] : INVALID;

    uint raw_owner = parent[raw];
    if (node_kind[raw] == PROD_TYPE_IDENT && raw_owner < gCanonical.raw_capacity &&
        node_kind[raw_owner] == PROD_IMPL_TRAIT)
    {
        uint target = next_sibling[raw];
        kind = PREDICATE_TRAIT_IMPL;
        predicate.owner = raw_to_hir[raw_owner];
        predicate.subject = raw_to_hir[target];
    }
    else
    {
        uint anchor = subject_anchor[dense];
        predicate.subject = hir_token_pos[anchor];
    }

    predicate.metadata = (hir_links[predicate.owner].file_id << 8u) | kind;
    predicates[row] = predicate;

    if (predicate.bound < gCanonical.canonical_capacity)
    {
        HirSemanticFacts facts = hir_canonical_semantic_facts[predicate.bound];
        facts.predicate_owner = predicate.owner;
        facts.predicate_subject = predicate.subject;
        hir_canonical_semantic_facts[predicate.bound] = facts;
    }

    if (kind == PREDICATE_TRAIT_IMPL &&
        predicate.owner < gCanonical.canonical_capacity)
    {
        HirPayload payload = hir_payload[predicate.owner];
        payload.a = HIR_IMPL_TRAIT;
        payload.b = predicate.bound;
        payload.c = predicate.subject;
        hir_payload[predicate.owner] = payload;
    }
}

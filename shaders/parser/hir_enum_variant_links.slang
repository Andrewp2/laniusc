// Seed enum variant and variant-payload links from grammar tree records.
//
// Enum variant and tuple-payload lists are right-recursive. First list entries
// seed the owning enum/variant, and later entries point at their previous
// sibling. A separate pointer-jump pass computes owners and ordinals.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirEnum;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;

RWStructuredBuffer<uint> hir_variant_owner_a;
RWStructuredBuffer<uint> hir_variant_link_a;
RWStructuredBuffer<uint> hir_variant_rank_a;
RWStructuredBuffer<uint> hir_variant_payload_owner_a;
RWStructuredBuffer<uint> hir_variant_payload_link_a;
RWStructuredBuffer<uint> hir_variant_payload_rank_a;
RWStructuredBuffer<uint> hir_variant_owner_b;
RWStructuredBuffer<uint> hir_variant_link_b;
RWStructuredBuffer<uint> hir_variant_rank_b;
RWStructuredBuffer<uint> hir_variant_payload_owner_b;
RWStructuredBuffer<uint> hir_variant_payload_link_b;
RWStructuredBuffer<uint> hir_variant_payload_rank_b;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirEnum.uses_ll1 != 0u ? min(gHirEnum.n, ll1_status[5u])
                                   : gHirEnum.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint parent_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint p = parent[node];
    return valid_node(p) ? p : INVALID;
}

uint first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = first_child[node];
    return valid_node(child) ? child : INVALID;
}

bool is_variant_container(uint prod)
{
    return prod == PROD_ENUM_VARIANTS_SOME ||
           prod == PROD_ENUM_VARIANTS_AFTER_COMMA_MORE;
}

uint variant_from_container(uint container)
{
    if (!valid_node(container) || !is_variant_container(node_kind[container]))
        return INVALID;
    uint variant = first_child_node(container);
    return valid_node(variant) && node_kind[variant] == PROD_ENUM_VARIANT
        ? variant
        : INVALID;
}

uint previous_variant_for_after_comma(uint container)
{
    if (!valid_node(container) ||
        node_kind[container] != PROD_ENUM_VARIANTS_AFTER_COMMA_MORE)
        return INVALID;
    uint more = parent_node(container);
    uint previous_container = parent_node(more);
    return variant_from_container(previous_container);
}

uint owner_seed_for_variant_container(uint container)
{
    if (!valid_node(container) || node_kind[container] != PROD_ENUM_VARIANTS_SOME)
        return INVALID;
    uint owner = parent_node(container);
    return valid_node(owner) && node_kind[owner] == PROD_ENUM ? owner : INVALID;
}

bool is_variant_payload_container(uint prod)
{
    return prod == PROD_ENUM_VARIANT_FIELDS_SOME ||
           prod == PROD_ENUM_VARIANT_FIELDS_AFTER_COMMA_MORE;
}

uint payload_type_from_container(uint container)
{
    if (!valid_node(container) || !is_variant_payload_container(node_kind[container]))
        return INVALID;
    uint ty = first_child_node(container);
    return valid_node(ty) && hir_kind[ty] == HIR_TYPE ? ty : INVALID;
}

uint previous_payload_for_after_comma(uint container)
{
    if (!valid_node(container) ||
        node_kind[container] != PROD_ENUM_VARIANT_FIELDS_AFTER_COMMA_MORE)
        return INVALID;
    uint more = parent_node(container);
    uint previous_container = parent_node(more);
    return payload_type_from_container(previous_container);
}

uint owner_seed_for_payload_container(uint container)
{
    if (!valid_node(container) ||
        node_kind[container] != PROD_ENUM_VARIANT_FIELDS_SOME)
        return INVALID;
    uint tuple_payload = parent_node(container);
    uint owner = parent_node(tuple_payload);
    return valid_node(owner) && node_kind[owner] == PROD_ENUM_VARIANT
        ? owner
        : INVALID;
}

void seed_variant(uint node)
{
    uint container = parent_node(node);
    uint prod = valid_node(container) ? node_kind[container] : INVALID;

    if (prod == PROD_ENUM_VARIANTS_SOME)
    {
        hir_variant_owner_a[node] = owner_seed_for_variant_container(container);
        return;
    }

    if (prod == PROD_ENUM_VARIANTS_AFTER_COMMA_MORE)
    {
        uint previous = previous_variant_for_after_comma(container);
        if (valid_node(previous))
        {
            hir_variant_link_a[node] = previous;
            hir_variant_rank_a[node] = 1u;
        }
    }
}

void seed_payload_type(uint node)
{
    uint container = parent_node(node);
    uint prod = valid_node(container) ? node_kind[container] : INVALID;

    if (prod == PROD_ENUM_VARIANT_FIELDS_SOME)
    {
        hir_variant_payload_owner_a[node] =
            owner_seed_for_payload_container(container);
        return;
    }

    if (prod == PROD_ENUM_VARIANT_FIELDS_AFTER_COMMA_MORE)
    {
        uint previous = previous_payload_for_after_comma(container);
        if (valid_node(previous))
        {
            hir_variant_payload_link_a[node] = previous;
            hir_variant_payload_rank_a[node] = 1u;
        }
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirEnum.n)
        return;

    hir_variant_owner_a[node] = INVALID;
    hir_variant_link_a[node] = INVALID;
    hir_variant_rank_a[node] = 0u;
    hir_variant_payload_owner_a[node] = INVALID;
    hir_variant_payload_link_a[node] = INVALID;
    hir_variant_payload_rank_a[node] = 0u;
    hir_variant_owner_b[node] = INVALID;
    hir_variant_link_b[node] = INVALID;
    hir_variant_rank_b[node] = 0u;
    hir_variant_payload_owner_b[node] = INVALID;
    hir_variant_payload_link_b[node] = INVALID;
    hir_variant_payload_rank_b[node] = 0u;

    if (!valid_node(node))
        return;

    if (node_kind[node] == PROD_ENUM_VARIANT)
    {
        seed_variant(node);
        return;
    }

    if (hir_kind[node] == HIR_TYPE)
        seed_payload_type(node);
}

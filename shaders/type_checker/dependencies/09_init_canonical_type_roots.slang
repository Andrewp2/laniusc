// Initialize one parent pointer per canonical dependency type. Type aliases
// point at their checked signature type; all other nodes are roots. Later
// parallel pointer-jumping rounds flatten arbitrary alias chains.

import gpu_index;

struct Params
{
    uint type_count;
    uint declaration_count;
    uint member_count;
    uint path_capacity;
    uint token_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> dependency_declaration_library_id;
StructuredBuffer<uint> dependency_declaration_unit_id;
StructuredBuffer<uint> dependency_declaration_local_index;
StructuredBuffer<uint> dependency_declaration_words;
StructuredBuffer<uint> dependency_type_words;
RWStructuredBuffer<uint> canonical_type_roots;

static const uint INVALID = 0xffffffffu;
static const uint DECL_WORDS = 14u;
static const uint TYPE_WORDS = 9u;
static const uint INTERFACE_TYPE_DECLARATION = 3u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

bool identity_less(
    uint library_id,
    uint unit_id,
    uint local_index,
    uint target_library,
    uint target_unit,
    uint target_local)
{
    return library_id < target_library ||
           (library_id == target_library &&
            (unit_id < target_unit ||
             (unit_id == target_unit && local_index < target_local)));
}

uint find_declaration(uint library_id, uint unit_id, uint local_index)
{
    uint lo = 0u;
    uint hi = gParams.declaration_count;
    while (lo < hi)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint mid_library = dependency_declaration_library_id[mid];
        uint mid_unit = dependency_declaration_unit_id[mid];
        uint mid_local = dependency_declaration_local_index[mid];
        if (identity_less(mid_library, mid_unit, mid_local, library_id, unit_id, local_index))
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo < gParams.declaration_count &&
        dependency_declaration_library_id[lo] == library_id &&
        dependency_declaration_unit_id[lo] == unit_id &&
        dependency_declaration_local_index[lo] == local_index)
        return lo;
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint type_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (type_i >= gParams.type_count)
        return;
    uint root = type_i;
    uint base = type_i * TYPE_WORDS;
    if (dependency_type_words[base] == INTERFACE_TYPE_DECLARATION)
    {
        uint declaration_i = find_declaration(
            dependency_type_words[base + 1u],
            dependency_type_words[base + 8u],
            dependency_type_words[base + 2u]);
        if (declaration_i != INVALID)
        {
            uint declaration_base = declaration_i * DECL_WORDS;
            // A declaration-shaped use such as Boxed<i32> owns its generic
            // edges and must remain its own canonical node. Only a true type
            // alias redirects to the declaration's checked target signature.
            if (dependency_declaration_words[declaration_base + 6u] ==
                HIR_ITEM_KIND_TYPE_ALIAS)
            {
                uint signature = dependency_declaration_words[declaration_base + 7u];
                if (signature < gParams.type_count && signature != type_i)
                    root = signature;
            }
        }
    }
    canonical_type_roots[type_i] = root;
}

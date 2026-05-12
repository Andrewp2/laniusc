// Derive parser-owned item metadata from HIR/tree arrays.
//
// This pass is intentionally fed by production ids and tree ancestry. It does
// not rediscover declarations by scanning token neighborhoods.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirItem;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_token_file_id;

RWStructuredBuffer<uint> hir_item_kind;
RWStructuredBuffer<uint> hir_item_name_token;
RWStructuredBuffer<uint> hir_item_namespace;
RWStructuredBuffer<uint> hir_item_visibility;
RWStructuredBuffer<uint> hir_item_path_start;
RWStructuredBuffer<uint> hir_item_path_end;
RWStructuredBuffer<uint> hir_item_file_id;
RWStructuredBuffer<uint> hir_item_import_target_kind;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ITEM_KIND_NONE = 0u;
static const uint HIR_ITEM_KIND_MODULE = 1u;
static const uint HIR_ITEM_KIND_IMPORT = 2u;
static const uint HIR_ITEM_KIND_CONST = 3u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;

static const uint HIR_ITEM_NAMESPACE_NONE = 0u;
static const uint HIR_ITEM_NAMESPACE_MODULE = 1u;
static const uint HIR_ITEM_NAMESPACE_VALUE = 2u;
static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;

static const uint HIR_ITEM_VIS_PRIVATE = 0u;
static const uint HIR_ITEM_VIS_PUBLIC = 1u;

static const uint HIR_ITEM_IMPORT_TARGET_NONE = 0u;
static const uint HIR_ITEM_IMPORT_TARGET_PATH = 1u;
static const uint HIR_ITEM_IMPORT_TARGET_STRING = 2u;

static const uint HIR_CONST_ITEM = 25u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_TYPE_ALIAS_ITEM = 29u;
static const uint HIR_MODULE_ITEM = 31u;
static const uint HIR_IMPORT_ITEM = 32u;

static const uint PROD_ITEM_PUB = 3u;
static const uint PROD_ITEM_FN = 4u;
static const uint PROD_ITEM_EXTERN_FN = 5u;
static const uint PROD_ITEM_IMPORT = 6u;
static const uint PROD_ITEM_MODULE = 7u;
static const uint PROD_ITEM_TYPE_ALIAS = 8u;
static const uint PROD_FN_ITEM = 12u;
static const uint PROD_EXTERN_FN_ITEM = 13u;
static const uint PROD_TYPE_ALIAS_ITEM = 14u;
static const uint PROD_EXTERN_ABI = 31u;
static const uint PROD_IMPORT_ITEM = 42u;
static const uint PROD_IMPORT_PATH = 43u;
static const uint PROD_IMPORT_STRING = 44u;
static const uint PROD_MODULE_ITEM = 45u;
static const uint PROD_PATH = 46u;
static const uint PROD_ITEM_CONST = 191u;
static const uint PROD_CONST_ITEM = 192u;
static const uint PROD_ITEM_ENUM = 193u;
static const uint PROD_ENUM_ITEM = 194u;
static const uint PROD_ITEM_STRUCT = 231u;
static const uint PROD_STRUCT_ITEM = 232u;
static const uint PROD_PUB_FN = 240u;
static const uint PROD_PUB_EXTERN_FN = 241u;
static const uint PROD_PUB_CONST = 242u;
static const uint PROD_PUB_TYPE_ALIAS = 243u;
static const uint PROD_PUB_ENUM = 244u;
static const uint PROD_PUB_STRUCT = 245u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirItem.uses_ll1 != 0u ? min(gHirItem.n, ll1_status[5u]) : gHirItem.n;
}

uint parent_kind(uint i)
{
    uint p = parent[i];
    return p == INVALID || p >= active_node_count() ? INVALID : node_kind[p];
}

uint grandparent_kind(uint i)
{
    uint p = parent[i];
    if (p == INVALID || p >= active_node_count())
        return INVALID;
    uint gp = parent[p];
    return gp == INVALID || gp >= active_node_count() ? INVALID : node_kind[gp];
}

bool is_public_wrapper(uint kind)
{
    return kind == PROD_PUB_FN || kind == PROD_PUB_EXTERN_FN || kind == PROD_PUB_CONST ||
           kind == PROD_PUB_TYPE_ALIAS || kind == PROD_PUB_ENUM || kind == PROD_PUB_STRUCT;
}

uint expected_hir_kind_for_item_production(uint prod)
{
    if (prod == PROD_MODULE_ITEM)
        return HIR_MODULE_ITEM;
    if (prod == PROD_IMPORT_ITEM)
        return HIR_IMPORT_ITEM;
    if (prod == PROD_CONST_ITEM)
        return HIR_CONST_ITEM;
    if (prod == PROD_STRUCT_ITEM)
        return HIR_STRUCT_ITEM;
    if (prod == PROD_ENUM_ITEM)
        return HIR_ENUM_ITEM;
    if (prod == PROD_TYPE_ALIAS_ITEM)
        return HIR_TYPE_ALIAS_ITEM;
    return 0u;
}

bool hir_kind_matches_item_production(uint i, uint prod)
{
    uint expected = expected_hir_kind_for_item_production(prod);
    return expected == 0u || hir_kind[i] == expected;
}

bool is_private_top_level_child(uint kind, uint parent_prod)
{
    if (kind == PROD_FN_ITEM)
        return parent_prod == PROD_ITEM_FN;
    if (kind == PROD_EXTERN_FN_ITEM)
        return parent_prod == PROD_ITEM_EXTERN_FN;
    if (kind == PROD_CONST_ITEM)
        return parent_prod == PROD_ITEM_CONST;
    if (kind == PROD_TYPE_ALIAS_ITEM)
        return parent_prod == PROD_ITEM_TYPE_ALIAS;
    if (kind == PROD_ENUM_ITEM)
        return parent_prod == PROD_ITEM_ENUM;
    if (kind == PROD_STRUCT_ITEM)
        return parent_prod == PROD_ITEM_STRUCT;
    return false;
}

bool is_public_top_level_child(uint kind, uint parent_prod, uint grandparent_prod)
{
    if (grandparent_prod != PROD_ITEM_PUB || !is_public_wrapper(parent_prod))
        return false;
    if (kind == PROD_FN_ITEM)
        return parent_prod == PROD_PUB_FN;
    if (kind == PROD_EXTERN_FN_ITEM)
        return parent_prod == PROD_PUB_EXTERN_FN;
    if (kind == PROD_CONST_ITEM)
        return parent_prod == PROD_PUB_CONST;
    if (kind == PROD_TYPE_ALIAS_ITEM)
        return parent_prod == PROD_PUB_TYPE_ALIAS;
    if (kind == PROD_ENUM_ITEM)
        return parent_prod == PROD_PUB_ENUM;
    if (kind == PROD_STRUCT_ITEM)
        return parent_prod == PROD_PUB_STRUCT;
    return false;
}

uint item_kind_for_production(uint prod)
{
    if (prod == PROD_MODULE_ITEM)
        return HIR_ITEM_KIND_MODULE;
    if (prod == PROD_IMPORT_ITEM)
        return HIR_ITEM_KIND_IMPORT;
    if (prod == PROD_CONST_ITEM)
        return HIR_ITEM_KIND_CONST;
    if (prod == PROD_FN_ITEM)
        return HIR_ITEM_KIND_FN;
    if (prod == PROD_EXTERN_FN_ITEM)
        return HIR_ITEM_KIND_EXTERN_FN;
    if (prod == PROD_STRUCT_ITEM)
        return HIR_ITEM_KIND_STRUCT;
    if (prod == PROD_ENUM_ITEM)
        return HIR_ITEM_KIND_ENUM;
    if (prod == PROD_TYPE_ALIAS_ITEM)
        return HIR_ITEM_KIND_TYPE_ALIAS;
    return HIR_ITEM_KIND_NONE;
}

uint namespace_for_item(uint item_kind)
{
    if (item_kind == HIR_ITEM_KIND_MODULE || item_kind == HIR_ITEM_KIND_IMPORT)
        return HIR_ITEM_NAMESPACE_MODULE;
    if (item_kind == HIR_ITEM_KIND_CONST || item_kind == HIR_ITEM_KIND_FN ||
        item_kind == HIR_ITEM_KIND_EXTERN_FN)
        return HIR_ITEM_NAMESPACE_VALUE;
    if (item_kind == HIR_ITEM_KIND_STRUCT || item_kind == HIR_ITEM_KIND_ENUM ||
        item_kind == HIR_ITEM_KIND_TYPE_ALIAS)
        return HIR_ITEM_NAMESPACE_TYPE;
    return HIR_ITEM_NAMESPACE_NONE;
}

uint extern_fn_name_token(uint i, uint start)
{
    uint child = first_child[i];
    bool has_abi = child != INVALID && child < active_node_count() &&
                   node_kind[child] == PROD_EXTERN_ABI && hir_token_pos[child] == start + 1u;
    return has_abi ? start + 3u : start + 2u;
}

uint name_token_for_item(uint i, uint prod, uint start)
{
    if (start == INVALID)
        return INVALID;
    if (prod == PROD_FN_ITEM || prod == PROD_CONST_ITEM || prod == PROD_STRUCT_ITEM ||
        prod == PROD_ENUM_ITEM || prod == PROD_TYPE_ALIAS_ITEM)
        return start + 1u;
    if (prod == PROD_EXTERN_FN_ITEM)
        return extern_fn_name_token(i, start);
    return INVALID;
}

void clear_item(uint i)
{
    hir_item_kind[i] = HIR_ITEM_KIND_NONE;
    hir_item_name_token[i] = INVALID;
    hir_item_namespace[i] = HIR_ITEM_NAMESPACE_NONE;
    hir_item_visibility[i] = HIR_ITEM_VIS_PRIVATE;
    hir_item_path_start[i] = INVALID;
    hir_item_path_end[i] = INVALID;
    hir_item_file_id[i] = hir_token_file_id[i];
    hir_item_import_target_kind[i] = HIR_ITEM_IMPORT_TARGET_NONE;
}

uint import_target_kind(uint i)
{
    if (node_kind[i] != PROD_IMPORT_ITEM)
        return HIR_ITEM_IMPORT_TARGET_NONE;
    uint child = first_child[i];
    if (child == INVALID || child >= active_node_count())
        return HIR_ITEM_IMPORT_TARGET_NONE;
    uint child_prod = node_kind[child];
    if (child_prod == PROD_IMPORT_PATH)
        return HIR_ITEM_IMPORT_TARGET_PATH;
    if (child_prod == PROD_IMPORT_STRING)
        return HIR_ITEM_IMPORT_TARGET_STRING;
    return HIR_ITEM_IMPORT_TARGET_NONE;
}

uint first_child_node(uint i)
{
    uint child = first_child[i];
    return child == INVALID || child >= active_node_count() ? INVALID : child;
}

uint module_or_import_path_node(uint i, uint prod, uint target_kind)
{
    uint child = first_child_node(i);
    if (child == INVALID)
        return INVALID;
    if (prod == PROD_MODULE_ITEM)
        return node_kind[child] == PROD_PATH ? child : INVALID;
    if (prod != PROD_IMPORT_ITEM || target_kind != HIR_ITEM_IMPORT_TARGET_PATH)
        return INVALID;
    return node_kind[child] == PROD_IMPORT_PATH ? first_child_node(child) : INVALID;
}

uint module_or_import_path_start(uint i, uint prod, uint target_kind)
{
    if (prod == PROD_IMPORT_ITEM && target_kind == HIR_ITEM_IMPORT_TARGET_STRING)
    {
        uint tail = first_child_node(i);
        return tail == INVALID || node_kind[tail] != PROD_IMPORT_STRING ? INVALID
                                                                        : hir_token_pos[tail];
    }

    uint path_node = module_or_import_path_node(i, prod, target_kind);
    return path_node == INVALID ? INVALID : hir_token_pos[path_node];
}

uint module_or_import_path_end(uint i, uint prod, uint target_kind)
{
    if (prod == PROD_IMPORT_ITEM && target_kind == HIR_ITEM_IMPORT_TARGET_STRING)
    {
        uint tail = first_child_node(i);
        if (tail == INVALID || node_kind[tail] != PROD_IMPORT_STRING ||
            hir_token_pos[tail] == INVALID)
            return INVALID;
        return hir_token_pos[tail] + 1u;
    }

    uint path_node = module_or_import_path_node(i, prod, target_kind);
    return path_node == INVALID ? INVALID : hir_token_end[path_node];
}

void publish_module_or_import(uint i, uint prod)
{
    uint item_kind = item_kind_for_production(prod);
    uint target_kind = import_target_kind(i);
    hir_item_kind[i] = item_kind;
    hir_item_namespace[i] = namespace_for_item(item_kind);
    hir_item_visibility[i] = HIR_ITEM_VIS_PRIVATE;
    hir_item_name_token[i] = INVALID;
    hir_item_path_start[i] = module_or_import_path_start(i, prod, target_kind);
    hir_item_path_end[i] = module_or_import_path_end(i, prod, target_kind);
    hir_item_import_target_kind[i] = target_kind;
}

void publish_decl(uint i, uint prod, uint start, uint visibility)
{
    uint item_kind = item_kind_for_production(prod);
    hir_item_kind[i] = item_kind;
    hir_item_namespace[i] = namespace_for_item(item_kind);
    hir_item_visibility[i] = visibility;
    hir_item_name_token[i] = name_token_for_item(i, prod, start);
    hir_item_path_start[i] = INVALID;
    hir_item_path_end[i] = INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gHirItem.n)
        return;

    clear_item(i);

    if (i >= active_node_count())
        return;

    uint prod = node_kind[i];
    if (!hir_kind_matches_item_production(i, prod))
        return;

    uint start = hir_token_pos[i];
    uint end_exclusive = hir_token_end[i];

    if (prod == PROD_MODULE_ITEM || prod == PROD_IMPORT_ITEM)
    {
        uint p = parent_kind(i);
        if ((prod == PROD_MODULE_ITEM && p == PROD_ITEM_MODULE) ||
            (prod == PROD_IMPORT_ITEM && p == PROD_ITEM_IMPORT))
            publish_module_or_import(i, prod);
        return;
    }

    uint p_kind = parent_kind(i);
    uint gp_kind = grandparent_kind(i);
    if (is_private_top_level_child(prod, p_kind))
        publish_decl(i, prod, start, HIR_ITEM_VIS_PRIVATE);
    else if (is_public_top_level_child(prod, p_kind, gp_kind))
        publish_decl(i, prod, start, HIR_ITEM_VIS_PUBLIC);
}

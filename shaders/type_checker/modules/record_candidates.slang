// Shared semantic classification for compact module/import/declaration/path rows.

static const uint MODULE_RECORD_INVALID = 0xffffffffu;

static const uint MODULE_HIR_TYPE = 5u;
static const uint MODULE_HIR_PATH_EXPR = 33u;
static const uint MODULE_PROD_PATH = 47u;

static const uint MODULE_ITEM_MODULE = 1u;
static const uint MODULE_ITEM_IMPORT = 2u;
static const uint MODULE_ITEM_CONST = 3u;
static const uint MODULE_ITEM_FN = 4u;
static const uint MODULE_ITEM_EXTERN_FN = 5u;
static const uint MODULE_ITEM_STRUCT = 6u;
static const uint MODULE_ITEM_ENUM = 7u;
static const uint MODULE_ITEM_TYPE_ALIAS = 8u;
static const uint MODULE_ITEM_ENUM_VARIANT = 9u;
static const uint MODULE_ITEM_TRAIT = 10u;

static const uint MODULE_NAMESPACE_VALUE = 2u;
static const uint MODULE_NAMESPACE_TYPE = 3u;
static const uint MODULE_IMPORT_TARGET_NONE = 0u;
static const uint MODULE_IMPORT_TARGET_PATH = 1u;

static const uint MODULE_PATH_NONE = 0u;
static const uint MODULE_PATH_MODULE_DECL = 1u;
static const uint MODULE_PATH_IMPORT = 2u;
static const uint MODULE_PATH_VALUE = 3u;
static const uint MODULE_PATH_TYPE = 4u;

public static const uint MODULE_RECORD_FLAG_MODULE = 1u << 0u;
public static const uint MODULE_RECORD_FLAG_IMPORT = 1u << 1u;
public static const uint MODULE_RECORD_FLAG_DECL = 1u << 2u;
public static const uint MODULE_RECORD_FLAG_PATH = 1u << 3u;
public static const uint MODULE_RECORD_PATH_KIND_SHIFT = 8u;

public struct ModuleRecordCandidate
{
    public uint candidate_node_kind;
    public uint candidate_hir_kind;
    public uint candidate_token_pos;
    public uint candidate_token_end;
    public uint candidate_item_kind;
    public uint candidate_item_name_token;
    public uint candidate_item_namespace;
    public uint candidate_item_path_start;
    public uint candidate_item_path_end;
    public uint candidate_import_target_kind;
};

bool module_valid_span(uint start, uint end_exclusive, uint n_tokens)
{
    return start != MODULE_RECORD_INVALID && end_exclusive != MODULE_RECORD_INVALID &&
           start < end_exclusive && end_exclusive <= n_tokens;
}

bool module_top_level_decl(uint kind)
{
    return kind == MODULE_ITEM_CONST || kind == MODULE_ITEM_FN ||
           kind == MODULE_ITEM_EXTERN_FN || kind == MODULE_ITEM_STRUCT ||
           kind == MODULE_ITEM_ENUM || kind == MODULE_ITEM_TYPE_ALIAS ||
           kind == MODULE_ITEM_ENUM_VARIANT || kind == MODULE_ITEM_TRAIT;
}

bool module_decl_namespace(uint namespace)
{
    return namespace == MODULE_NAMESPACE_VALUE || namespace == MODULE_NAMESPACE_TYPE;
}

uint module_candidate_path_kind(ModuleRecordCandidate row, uint n_tokens)
{
    if (row.candidate_item_kind == MODULE_ITEM_MODULE &&
        module_valid_span(row.candidate_item_path_start, row.candidate_item_path_end, n_tokens))
        return MODULE_PATH_MODULE_DECL;
    if (row.candidate_item_kind == MODULE_ITEM_IMPORT &&
        row.candidate_import_target_kind == MODULE_IMPORT_TARGET_PATH &&
        module_valid_span(row.candidate_item_path_start, row.candidate_item_path_end, n_tokens))
        return MODULE_PATH_IMPORT;
    if (row.candidate_hir_kind == MODULE_HIR_PATH_EXPR &&
        row.candidate_node_kind == MODULE_PROD_PATH &&
        module_valid_span(row.candidate_token_pos, row.candidate_token_end, n_tokens))
        return MODULE_PATH_VALUE;
    if (row.candidate_hir_kind == MODULE_HIR_TYPE &&
        module_valid_span(row.candidate_token_pos, row.candidate_token_end, n_tokens))
        return MODULE_PATH_TYPE;
    return MODULE_PATH_NONE;
}

public uint module_record_candidate_bits(ModuleRecordCandidate row, uint n_tokens)
{
    uint bits = 0u;
    if (row.candidate_item_kind == MODULE_ITEM_MODULE &&
        module_valid_span(row.candidate_item_path_start, row.candidate_item_path_end, n_tokens))
        bits |= MODULE_RECORD_FLAG_MODULE;
    if (row.candidate_item_kind == MODULE_ITEM_IMPORT &&
        row.candidate_import_target_kind != MODULE_IMPORT_TARGET_NONE)
        bits |= MODULE_RECORD_FLAG_IMPORT;
    if (module_top_level_decl(row.candidate_item_kind) &&
        module_decl_namespace(row.candidate_item_namespace) &&
        row.candidate_item_name_token != MODULE_RECORD_INVALID)
        bits |= MODULE_RECORD_FLAG_DECL;
    uint path_kind = module_candidate_path_kind(row, n_tokens);
    if (path_kind != MODULE_PATH_NONE)
        bits |= MODULE_RECORD_FLAG_PATH | (path_kind << MODULE_RECORD_PATH_KIND_SHIFT);
    return bits;
}

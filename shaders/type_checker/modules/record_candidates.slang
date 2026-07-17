// Shared semantic classification for dense canonical HIR item rows.

static const uint MODULE_RECORD_INVALID = 0xffffffffu;

static const uint MODULE_HIR_ITEM = 2u;
static const uint MODULE_HIR_FN = 3u;
static const uint MODULE_HIR_CONST_ITEM = 25u;
static const uint MODULE_HIR_ENUM_ITEM = 26u;
static const uint MODULE_HIR_STRUCT_ITEM = 27u;
static const uint MODULE_HIR_TYPE_ALIAS_ITEM = 29u;
static const uint MODULE_HIR_MODULE_ITEM = 31u;
static const uint MODULE_HIR_IMPORT_ITEM = 32u;

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

public static const uint MODULE_RECORD_FLAG_MODULE = 1u << 0u;
public static const uint MODULE_RECORD_FLAG_IMPORT = 1u << 1u;
public static const uint MODULE_RECORD_FLAG_DECL = 1u << 2u;

public struct ModuleRecordCandidate
{
    public uint hir_kind;
    public uint item_kind;
    public uint name_token;
    public uint namespace_kind;
};

bool module_item_kind_matches_hir_kind(uint hir_kind, uint item_kind)
{
    if (hir_kind == MODULE_HIR_MODULE_ITEM) return item_kind == MODULE_ITEM_MODULE;
    if (hir_kind == MODULE_HIR_IMPORT_ITEM) return item_kind == MODULE_ITEM_IMPORT;
    if (hir_kind == MODULE_HIR_CONST_ITEM) return item_kind == MODULE_ITEM_CONST;
    if (hir_kind == MODULE_HIR_FN)
        return item_kind == MODULE_ITEM_FN || item_kind == MODULE_ITEM_EXTERN_FN;
    if (hir_kind == MODULE_HIR_STRUCT_ITEM) return item_kind == MODULE_ITEM_STRUCT;
    if (hir_kind == MODULE_HIR_ENUM_ITEM) return item_kind == MODULE_ITEM_ENUM;
    if (hir_kind == MODULE_HIR_TYPE_ALIAS_ITEM) return item_kind == MODULE_ITEM_TYPE_ALIAS;
    // Enum variants are emitted from the compact variant side table. Keeping
    // them out of this core-row classifier prevents grammar winners at the
    // same token anchor from deciding whether a variant exists.
    if (hir_kind == MODULE_HIR_ITEM)
        return item_kind == MODULE_ITEM_TRAIT;
    return false;
}

bool module_top_level_decl(uint kind)
{
    return kind == MODULE_ITEM_CONST || kind == MODULE_ITEM_FN ||
           kind == MODULE_ITEM_EXTERN_FN || kind == MODULE_ITEM_STRUCT ||
           kind == MODULE_ITEM_ENUM || kind == MODULE_ITEM_TYPE_ALIAS ||
           kind == MODULE_ITEM_TRAIT;
}

bool module_decl_namespace(uint namespace_kind)
{
    return namespace_kind == MODULE_NAMESPACE_VALUE || namespace_kind == MODULE_NAMESPACE_TYPE;
}

public uint module_record_candidate_bits(ModuleRecordCandidate row, uint n_tokens)
{
    if (!module_item_kind_matches_hir_kind(row.hir_kind, row.item_kind))
        return 0u;

    uint bits = 0u;
    if (row.item_kind == MODULE_ITEM_MODULE)
        bits |= MODULE_RECORD_FLAG_MODULE;
    if (row.item_kind == MODULE_ITEM_IMPORT)
        bits |= MODULE_RECORD_FLAG_IMPORT;
    if (module_top_level_decl(row.item_kind) &&
        module_decl_namespace(row.namespace_kind) && row.name_token < n_tokens)
        bits |= MODULE_RECORD_FLAG_DECL;
    return bits;
}

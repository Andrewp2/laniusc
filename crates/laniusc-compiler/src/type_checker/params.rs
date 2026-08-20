use encase::ShaderType;

/// Top-level uniform shared by most resident type-check shaders.
///
/// These counts describe the live input slice for the current recording. They
/// are kept separate from allocation capacity so cached resident buffers can be
/// larger than the source currently being checked.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct TypeCheckParams {
    pub(in crate::type_checker) n_tokens: u32,
    pub(in crate::type_checker) source_len: u32,
    pub(in crate::type_checker) n_hir_nodes: u32,
    pub(in crate::type_checker) n_source_files: u32,
    pub(in crate::type_checker) parser_feature_flags: u32,
    /// Whether dependency-value metadata is produced for this job.
    pub(in crate::type_checker) dependency_interfaces_present: u32,
}

/// Uniform for the enclosing-`if` depth prefix-scan passes.
///
/// The pass family marks `if` entry/exit deltas, scans them in token order,
/// and exposes exact nesting depth to control-flow lowering.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct IfDepthParams {
    pub(in crate::type_checker) n_tokens: u32,
    pub(in crate::type_checker) n_hir_nodes: u32,
    pub(in crate::type_checker) n_blocks: u32,
    pub(in crate::type_checker) scan_step: u32,
}

/// Uniform for the enclosing-function prefix-scan passes.
///
/// Function context is represented as events over the linear token/HIR stream
/// so later return and backend passes can ask which function owns a node.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct FnContextParams {
    pub(in crate::type_checker) n_tokens: u32,
    pub(in crate::type_checker) n_hir_nodes: u32,
    pub(in crate::type_checker) n_blocks: u32,
    pub(in crate::type_checker) scan_step: u32,
}

/// Capacity packet for GPU-produced exact path-prefix dispatches.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct PathPrefixDispatchParams {
    pub(in crate::type_checker) segment_capacity: u32,
    pub(in crate::type_checker) round_count: u32,
    pub(in crate::type_checker) reserved0: u32,
    pub(in crate::type_checker) reserved1: u32,
}

/// One exact path-prefix doubling round.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct PathPrefixRoundParams {
    pub(in crate::type_checker) segment_capacity: u32,
    pub(in crate::type_checker) step: u32,
    pub(in crate::type_checker) reserved0: u32,
    pub(in crate::type_checker) reserved1: u32,
}

/// Capacities for the direct canonical-path-id to module-row table.
///
/// Canonical path ids are slots in the prefix interner, whose table contains
/// two slots per possible path segment.  Keeping that domain distinct from
/// path records and module rows prevents consumers from accidentally bounding
/// a canonical id by an unrelated compact-record capacity.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct ModuleLookupParams {
    pub(in crate::type_checker) path_capacity: u32,
    pub(in crate::type_checker) path_segment_capacity: u32,
    pub(in crate::type_checker) module_capacity: u32,
    pub(in crate::type_checker) reserved: u32,
}

/// Capacities and feature state used while resolving imports.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct ImportResolveParams {
    pub(in crate::type_checker) import_capacity: u32,
    pub(in crate::type_checker) path_capacity: u32,
    pub(in crate::type_checker) path_segment_capacity: u32,
    pub(in crate::type_checker) module_capacity: u32,
    pub(in crate::type_checker) dependency_interfaces_present: u32,
    pub(in crate::type_checker) reserved0: u32,
    pub(in crate::type_checker) reserved1: u32,
    pub(in crate::type_checker) reserved2: u32,
}

/// Capacities for resolving multi-segment value and type paths.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct QualifiedPathResolveParams {
    pub(in crate::type_checker) record_capacity: u32,
    pub(in crate::type_checker) path_segment_capacity: u32,
    pub(in crate::type_checker) module_capacity: u32,
    pub(in crate::type_checker) reserved: u32,
}

/// Capacity packet for semantic-interface identity sizing.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct SemanticInterfaceIdentitySizeParams {
    pub(in crate::type_checker) name_capacity: u32,
    pub(in crate::type_checker) module_capacity: u32,
    pub(in crate::type_checker) decl_capacity: u32,
    pub(in crate::type_checker) module_segment_capacity: u32,
    pub(in crate::type_checker) module_index_capacity: u32,
    pub(in crate::type_checker) member_capacity: u32,
}

/// Capacity packet for public-signature type reachability and ordering.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct SemanticInterfaceTypeTopologyParams {
    pub(in crate::type_checker) hir_capacity: u32,
    pub(in crate::type_checker) decl_capacity: u32,
    pub(in crate::type_checker) token_capacity: u32,
    pub(in crate::type_checker) library_id: u32,
    pub(in crate::type_checker) unit_id: u32,
}

/// Capacity and producer identity packet for interface record scatter.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct SemanticInterfaceIdentityRecordParams {
    pub(in crate::type_checker) library_id: u32,
    pub(in crate::type_checker) name_capacity: u32,
    pub(in crate::type_checker) module_capacity: u32,
    pub(in crate::type_checker) decl_capacity: u32,
    pub(in crate::type_checker) module_segment_capacity: u32,
    pub(in crate::type_checker) module_index_capacity: u32,
    pub(in crate::type_checker) name_byte_capacity: u32,
    pub(in crate::type_checker) member_capacity: u32,
    pub(in crate::type_checker) hir_capacity: u32,
}

/// Capacity packet for canonical interface-name byte scatter.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct SemanticInterfaceIdentityByteParams {
    pub(in crate::type_checker) name_capacity: u32,
    pub(in crate::type_checker) source_len: u32,
    pub(in crate::type_checker) name_ref_count: u32,
    pub(in crate::type_checker) module_segment_capacity: u32,
    pub(in crate::type_checker) module_index_capacity: u32,
    pub(in crate::type_checker) decl_capacity: u32,
    pub(in crate::type_checker) member_capacity: u32,
}

/// Capacities and stable identity used to materialize one persisted interface.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct SemanticInterfaceArtifactParams {
    pub(in crate::type_checker) module_capacity: u32,
    pub(in crate::type_checker) module_segment_capacity: u32,
    pub(in crate::type_checker) declaration_capacity: u32,
    pub(in crate::type_checker) type_capacity: u32,
    pub(in crate::type_checker) edge_capacity: u32,
    pub(in crate::type_checker) member_capacity: u32,
    pub(in crate::type_checker) name_byte_capacity: u32,
    pub(in crate::type_checker) artifact_word_capacity: u32,
    pub(in crate::type_checker) unit_id: u32,
    pub(in crate::type_checker) version: u32,
}

/// Capacities for dependency semantic-interface module indexing.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct DependencyInterfaceModuleParams {
    pub(in crate::type_checker) module_count: u32,
    pub(in crate::type_checker) lookup_capacity: u32,
    pub(in crate::type_checker) import_capacity: u32,
    pub(in crate::type_checker) source_len: u32,
}

/// Capacities for projecting dependency declarations into one unit's import
/// visibility relation and resolving local paths against that relation.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct DependencyInterfaceVisibilityParams {
    pub(in crate::type_checker) declaration_count: u32,
    pub(in crate::type_checker) import_capacity: u32,
    pub(in crate::type_checker) visible_capacity: u32,
    pub(in crate::type_checker) lookup_capacity: u32,
    pub(in crate::type_checker) source_len: u32,
    pub(in crate::type_checker) path_capacity: u32,
    pub(in crate::type_checker) namespace: u32,
    pub(in crate::type_checker) hir_capacity: u32,
}

/// Capacity packet for parallel canonical dependency-type normalization.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct DependencyCanonicalTypeParams {
    pub(in crate::type_checker) type_count: u32,
    pub(in crate::type_checker) declaration_count: u32,
    pub(in crate::type_checker) member_count: u32,
    pub(in crate::type_checker) path_capacity: u32,
    pub(in crate::type_checker) token_capacity: u32,
}

/// Uniform for one visible-declaration scope-tree construction level.
///
/// Visible HIR declarations are compacted into rows and then reduced into a
/// block tree so lookup shaders can query the declarations in an enclosing
/// lexical range without walking source syntax.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct VisibleDeclTreeParams {
    pub(in crate::type_checker) decl_capacity: u32,
    pub(in crate::type_checker) row_block_size: u32,
    pub(in crate::type_checker) leaf_base: u32,
    pub(in crate::type_checker) level_start: u32,
    pub(in crate::type_checker) level_count: u32,
    pub(in crate::type_checker) reserved0: u32,
    pub(in crate::type_checker) reserved1: u32,
    pub(in crate::type_checker) reserved2: u32,
}

/// Uniform for exact source-name hashing.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct NameHashParams {
    pub(in crate::type_checker) name_count: u32,
    pub(in crate::type_checker) source_len: u32,
    pub(in crate::type_checker) table_half_capacity: u32,
    pub(in crate::type_checker) reserved: u32,
}

/// Uniform for shaders that turn a counted row total into dispatch arguments.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct CountDispatchParams {
    pub(in crate::type_checker) capacity: u32,
    pub(in crate::type_checker) multiplier: u32,
    pub(in crate::type_checker) reserved0: u32,
    pub(in crate::type_checker) reserved1: u32,
}

/// Uniform for dispatches whose work count is the max of two counted ranges.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct CountPairMaxDispatchParams {
    pub(in crate::type_checker) left_capacity: u32,
    pub(in crate::type_checker) right_capacity: u32,
    pub(in crate::type_checker) multiplier: u32,
    pub(in crate::type_checker) reserved: u32,
}

/// Uniform for extracting one semantic record family from HIR records.
///
/// `family_bit` selects the path, module, import, declaration, or related
/// record family that a subsequent counted scan will compact.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct RecordFamilyFlagParams {
    pub(in crate::type_checker) n_hir_nodes: u32,
    pub(in crate::type_checker) family_bit: u32,
    pub(in crate::type_checker) reserved0: u32,
    pub(in crate::type_checker) reserved1: u32,
}

/// Uniform shared by declaration-grouping and visible-declaration radix sorts.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct ModuleKeyRadixParams {
    pub(in crate::type_checker) module_capacity: u32,
    pub(in crate::type_checker) reserved: u32,
    pub(in crate::type_checker) n_blocks: u32,
    pub(in crate::type_checker) key_step: u32,
}

/// Number of cached words reserved per compacted call-parameter row.
pub(in crate::type_checker) const CALL_PARAM_CACHE_STRIDE: usize = 4;
/// Number of words reserved per type-instance argument reference.
///
/// Each argument reference carries a tag/payload pair plus reserved slots used
/// by projection and hashing passes. This is a row stride, not a semantic limit
/// on how many type arguments an item may have.
/// Upper bound multiplier for generic claim scratch relative to call rows.
pub(in crate::type_checker) const GENERIC_CLAIM_CAPACITY_MULTIPLIER: u32 = 32;

/// Conservative generic-claim capacity for one source token stream.
///
/// Claims are emitted only from compacted call-argument rows. Every argument
/// row originates in source syntax and therefore consumes at least one token,
/// even when parser expansion produces more HIR rows than source tokens. Keep
/// this bound tied to tokens so expanded HIR cannot inflate each claim buffer
/// past the device's maximum single-buffer size.
pub(in crate::type_checker) fn generic_claim_capacity(token_capacity: u32) -> u32 {
    token_capacity
        .saturating_mul(GENERIC_CLAIM_CAPACITY_MULTIPLIER)
        .max(1)
}

pub(in crate::type_checker) fn generic_claim_capacity_for_features(
    token_capacity: u32,
    parser_feature_flags: u32,
) -> u32 {
    if parser_feature_flags & crate::lexer::features::PARSER_FEATURE_TYPE_ARGS == 0 {
        1
    } else {
        generic_claim_capacity(token_capacity)
    }
}

pub(in crate::type_checker) fn generic_claim_capacity_for_job(
    token_capacity: u32,
    parser_feature_flags: u32,
    has_dependency_interfaces: bool,
) -> u32 {
    if has_dependency_interfaces {
        generic_claim_capacity(token_capacity)
    } else {
        generic_claim_capacity_for_features(token_capacity, parser_feature_flags)
    }
}

pub(in crate::type_checker) fn predicate_capacity_for_features(
    hir_node_capacity: u32,
    parser_feature_flags: u32,
) -> u32 {
    use crate::lexer::features::{PARSER_FEATURE_PREDICATES, PARSER_FEATURE_TYPE_ARGS};
    if parser_feature_flags & (PARSER_FEATURE_TYPE_ARGS | PARSER_FEATURE_PREDICATES) == 0 {
        1
    } else {
        hir_node_capacity.max(1)
    }
}

pub(in crate::type_checker) fn type_alias_passes_required(parser_feature_flags: u32) -> bool {
    parser_feature_flags & crate::lexer::features::PARSER_FEATURE_TYPE_ALIASES != 0
}

/// Whether aggregate field lookup needs its exact struct-field index.
pub(in crate::type_checker) fn struct_field_index_passes_required(
    parser_feature_flags: u32,
) -> bool {
    parser_feature_flags & crate::lexer::features::PARSER_FEATURE_STRUCTS != 0
}

/// Whether generic rows or struct declaration-node lookups must be materialized.
pub(in crate::type_checker) fn generic_param_record_passes_required(
    parser_feature_flags: u32,
) -> bool {
    use crate::lexer::features::{
        PARSER_FEATURE_PREDICATES,
        PARSER_FEATURE_STRUCTS,
        PARSER_FEATURE_TYPE_ARGS,
    };
    parser_feature_flags
        & (PARSER_FEATURE_TYPE_ARGS | PARSER_FEATURE_PREDICATES | PARSER_FEATURE_STRUCTS)
        != 0
}

/// Whether method declarations or member-call sites can exist in this source pack.
pub(in crate::type_checker) fn method_passes_required(parser_feature_flags: u32) -> bool {
    use crate::lexer::features::{PARSER_FEATURE_MEMBERS, PARSER_FEATURE_PREDICATES};
    parser_feature_flags & (PARSER_FEATURE_MEMBERS | PARSER_FEATURE_PREDICATES) != 0
}

/// Whether call rows can emit generic or const-generic consistency claims.
pub(in crate::type_checker) fn generic_call_claim_passes_required(
    parser_feature_flags: u32,
) -> bool {
    parser_feature_flags & crate::lexer::features::PARSER_FEATURE_TYPE_ARGS != 0
}

/// Whether array construction, indexing, or array-result propagation can occur.
pub(in crate::type_checker) fn array_passes_required(parser_feature_flags: u32) -> bool {
    parser_feature_flags & crate::lexer::features::PARSER_FEATURE_ARRAYS != 0
}

/// Whether struct declaration/literal initialization metadata can occur.
pub(in crate::type_checker) fn struct_init_passes_required(parser_feature_flags: u32) -> bool {
    parser_feature_flags & crate::lexer::features::PARSER_FEATURE_STRUCTS != 0
}

/// Whether field/member receiver and result propagation can occur.
pub(in crate::type_checker) fn member_passes_required(parser_feature_flags: u32) -> bool {
    parser_feature_flags & crate::lexer::features::PARSER_FEATURE_MEMBERS != 0
}

/// Whether enum constructor resolution can occur.
pub(in crate::type_checker) fn enum_passes_required(parser_feature_flags: u32) -> bool {
    parser_feature_flags & crate::lexer::features::PARSER_FEATURE_ENUMS != 0
}

/// Whether match-pattern binding and match-result typing can occur.
pub(in crate::type_checker) fn match_passes_required(parser_feature_flags: u32) -> bool {
    parser_feature_flags & crate::lexer::features::PARSER_FEATURE_MATCHES != 0
}

/// Whether aggregate comparison/access validation needs compact aggregate rows.
pub(in crate::type_checker) fn aggregate_passes_required(parser_feature_flags: u32) -> bool {
    use crate::lexer::features::{
        PARSER_FEATURE_ARRAYS,
        PARSER_FEATURE_ENUMS,
        PARSER_FEATURE_MEMBERS,
        PARSER_FEATURE_STRUCTS,
        PARSER_FEATURE_TYPE_ARGS,
    };
    parser_feature_flags
        & (PARSER_FEATURE_ARRAYS
            | PARSER_FEATURE_ENUMS
            | PARSER_FEATURE_MEMBERS
            | PARSER_FEATURE_STRUCTS
            | PARSER_FEATURE_TYPE_ARGS)
        != 0
}

/// Globally materialized bucket count for byte-wise radix sorting. The
/// inactive-row sentinel exists only in workgroup-local scatter storage.
pub(in crate::type_checker) const RADIX_U8_BUCKET_COUNT: u32 = 256;
/// Exact-name hash slots allocated per 256-row source-name block, per table half.
pub(in crate::type_checker) const NAME_HASH_TABLE_ROWS_PER_BLOCK: u32 = 257;
/// Number of builtin symbols materialized before user names are resolved.
pub(in crate::type_checker) const LANGUAGE_SYMBOL_COUNT: u32 = 68;
/// Concatenated builtin symbol spelling table.
pub(in crate::type_checker) const LANGUAGE_SYMBOL_BYTES: &[u8] =
    b"mainassertprintbooli8i16i32i64isizeu8u16u32u64usizef32f64charstrprint_i32_open_read_pathopen_write_pathread_i32write_textwrite_i32write_bytewrite_newlineclose_filei32_to_f32exitsecure_u32allocdeallocargcarg_lenarg_readunix_secondscurrent_dir_readvar_countvar_key_lenvar_key_readvar_lenvar_readclosereadwriteopen_readopen_writeopen_appendwrite_stdoutwrite_stderrread_stdini32_array_data_ptrfill_secure_bytesremove_filecreate_dirremove_dirrenamemonotonic_readsystem_readsleep_ms_i32reallocalloc_failedcorerangeRangeRangeInclusiveptr";
/// Start offsets into `LANGUAGE_SYMBOL_BYTES` for each builtin symbol.
pub(in crate::type_checker) const LANGUAGE_SYMBOL_STARTS: &[u32] = &[
    0, 4, 10, 15, 19, 21, 24, 27, 30, 35, 37, 40, 43, 46, 51, 54, 57, 61, 64, 73, 74, 88, 103, 111,
    121, 130, 140, 153, 163, 173, 177, 187, 192, 199, 203, 210, 218, 230, 246, 255, 266, 278, 285,
    293, 298, 302, 307, 316, 326, 337, 349, 361, 371, 389, 406, 417, 427, 437, 443, 457, 468, 480,
    487, 499, 503, 508, 513, 527,
];
/// Byte lengths for each builtin symbol spelling.
pub(in crate::type_checker) const LANGUAGE_SYMBOL_LENS: &[u32] = &[
    4, 6, 5, 4, 2, 3, 3, 3, 5, 2, 3, 3, 3, 5, 3, 3, 4, 3, 9, 1, 14, 15, 8, 10, 9, 10, 13, 10, 10,
    4, 10, 5, 7, 4, 7, 8, 12, 16, 9, 11, 12, 7, 8, 5, 4, 5, 9, 10, 11, 12, 12, 10, 18, 17, 11, 10,
    10, 6, 14, 11, 12, 7, 12, 4, 5, 5, 14, 3,
];
/// Number of language declarations materialized from builtin symbols.
pub(in crate::type_checker) const LANGUAGE_DECL_COUNT: u32 = 21;
const LANGUAGE_DECL_KIND_ENTRYPOINT: u32 = 1;
const LANGUAGE_DECL_KIND_INTRINSIC: u32 = 2;
const LANGUAGE_DECL_KIND_PRIMITIVE_TYPE: u32 = 3;
const LANGUAGE_DECL_TAG_MAIN: u32 = 1;
const LANGUAGE_DECL_TAG_PRINT: u32 = 1;
const LANGUAGE_DECL_TAG_ASSERT: u32 = 2;
/// Compiler intrinsic projecting an i32 aggregate value to its data pointer.
/// Intrinsic tags describe compiler semantics; they are deliberately
/// independent from the host-service symbol slots below.
const LANGUAGE_DECL_TAG_I32_ARRAY_DATA_PTR: u32 = 3;
/// Builtin symbol slots that become materialized language declarations.
pub(in crate::type_checker) const LANGUAGE_DECL_SYMBOL_SLOTS: &[u32] = &[
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 52, 67,
];
/// Declaration kind table parallel to `LANGUAGE_DECL_SYMBOL_SLOTS`.
pub(in crate::type_checker) const LANGUAGE_DECL_KINDS: &[u32] = &[
    LANGUAGE_DECL_KIND_ENTRYPOINT,
    LANGUAGE_DECL_KIND_INTRINSIC,
    LANGUAGE_DECL_KIND_INTRINSIC,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
    LANGUAGE_DECL_KIND_INTRINSIC,
    LANGUAGE_DECL_KIND_INTRINSIC,
    LANGUAGE_DECL_KIND_PRIMITIVE_TYPE,
];
/// Declaration tag table parallel to `LANGUAGE_DECL_SYMBOL_SLOTS`.
pub(in crate::type_checker) const LANGUAGE_DECL_TAGS: &[u32] = &[
    LANGUAGE_DECL_TAG_MAIN,
    LANGUAGE_DECL_TAG_ASSERT,
    LANGUAGE_DECL_TAG_PRINT,
    2, // bool
    3, // i8
    3, // i16
    3, // i32
    3, // i64
    3, // isize
    4, // u8
    4, // u16
    4, // u32
    4, // u64
    4, // usize
    5, // f32
    5, // f64
    6, // char
    7, // str
    LANGUAGE_DECL_TAG_PRINT,
    LANGUAGE_DECL_TAG_I32_ARRAY_DATA_PTR,
    8, // ptr
];
/// Returns the byte width and byte-step count for stable declaration grouping.
///
/// Declaration lookup is exact and hash-indexed. Sorting is retained only to
/// group declarations by module for deterministic interface/import traversal,
/// so the radix key contains `module_id` alone.
pub(in crate::type_checker) fn decl_key_radix_layout(
    _token_capacity: u32,
    module_capacity: u32,
) -> (u32, u32) {
    let module_bytes = radix_bytes_for_max_key(module_capacity.saturating_add(1));
    (module_bytes, module_bytes)
}

fn radix_bytes_for_max_key(max_key: u32) -> u32 {
    if max_key <= 0xff {
        1
    } else if max_key <= 0xffff {
        2
    } else if max_key <= 0x00ff_ffff {
        3
    } else {
        4
    }
}

/// Largest compact module relation sorted by one cooperative 256-lane workgroup.
pub(in crate::type_checker) const MODULE_RELATION_SMALL_SORT_CAPACITY: u32 = 2048;
/// Largest compact visible-declaration table sorted by one cooperative workgroup.
pub(in crate::type_checker) const VISIBLE_DECL_SMALL_SORT_CAPACITY: u32 = 2048;
const VISIBLE_DECL_KEY_MAX_RADIX_STEPS: u32 = 8;
/// Number of visible-declaration rows summarized into one scope-tree leaf.
pub(in crate::type_checker) const HIR_VISIBLE_DECL_ROW_BLOCK_SIZE: u32 = 64;

/// Returns the significant bit width of each visible-declaration key field.
pub(in crate::type_checker) fn visible_decl_key_radix_bits(decl_capacity: u32) -> u32 {
    let max_key = decl_capacity
        .saturating_add(LANGUAGE_SYMBOL_COUNT)
        .saturating_add(1)
        .max(1);
    (u32::BITS - max_key.leading_zeros()).max(1)
}

/// Returns the radix-step count used for visible-declaration key sorting.
/// Lookup compares `(owner, name, token)`. Visible rows are compacted in token
/// order and the radix scatter is stable, so sorting `(owner, name)` preserves
/// token as the implicit final tie-breaker. The two bounded fields are
/// bit-packed before byte extraction so capacity rounding cannot add an
/// otherwise useless byte pass per field.
pub(in crate::type_checker) fn visible_decl_key_radix_steps(decl_capacity: u32) -> u32 {
    let bits = visible_decl_key_radix_bits(decl_capacity).saturating_mul(2);
    let steps = bits.div_ceil(8);
    steps.min(VISIBLE_DECL_KEY_MAX_RADIX_STEPS)
}

#[cfg(test)]
mod tests {
    use super::{
        aggregate_passes_required,
        array_passes_required,
        decl_key_radix_layout,
        enum_passes_required,
        generic_call_claim_passes_required,
        generic_claim_capacity,
        generic_claim_capacity_for_job,
        generic_param_record_passes_required,
        match_passes_required,
        member_passes_required,
        method_passes_required,
        struct_field_index_passes_required,
        struct_init_passes_required,
        type_alias_passes_required,
        visible_decl_key_radix_bits,
        visible_decl_key_radix_steps,
    };
    use crate::lexer::features::{
        PARSER_FEATURE_ARRAYS,
        PARSER_FEATURE_ENUMS,
        PARSER_FEATURE_IMPORTS,
        PARSER_FEATURE_MATCHES,
        PARSER_FEATURE_MEMBERS,
        PARSER_FEATURE_PREDICATES,
        PARSER_FEATURE_STRUCTS,
        PARSER_FEATURE_TYPE_ALIASES,
        PARSER_FEATURE_TYPE_ARGS,
    };

    #[test]
    fn declaration_radix_layout_groups_only_by_module() {
        assert_eq!(decl_key_radix_layout(0, 0), (1, 1));
        assert_eq!(decl_key_radix_layout(312_822, 69_510), (3, 3));
        assert_eq!(decl_key_radix_layout(u32::MAX, u32::MAX), (4, 4));
    }

    #[test]
    fn visible_declaration_radix_matches_owner_name_token_lookup_order() {
        assert_eq!(visible_decl_key_radix_bits(128), 8);
        assert_eq!(visible_decl_key_radix_steps(128), 2);
        assert_eq!(visible_decl_key_radix_bits(4_096), 13);
        assert_eq!(visible_decl_key_radix_steps(4_096), 4);
        assert_eq!(visible_decl_key_radix_bits(100_000), 17);
        assert_eq!(visible_decl_key_radix_steps(100_000), 5);
        assert_eq!(visible_decl_key_radix_steps(u32::MAX), 8);
    }

    #[test]
    fn struct_field_key_passes_follow_the_parser_struct_feature() {
        assert!(!struct_field_index_passes_required(0));
        assert!(!struct_field_index_passes_required(PARSER_FEATURE_ARRAYS));
        assert!(struct_field_index_passes_required(PARSER_FEATURE_STRUCTS));
        assert!(struct_field_index_passes_required(u32::MAX));
    }

    #[test]
    fn generic_param_record_passes_follow_generic_and_struct_features() {
        assert!(!generic_param_record_passes_required(0));
        assert!(!generic_param_record_passes_required(PARSER_FEATURE_ARRAYS));
        assert!(!generic_param_record_passes_required(
            PARSER_FEATURE_IMPORTS
        ));
        assert!(generic_param_record_passes_required(
            PARSER_FEATURE_TYPE_ARGS
        ));
        assert!(generic_param_record_passes_required(
            PARSER_FEATURE_PREDICATES
        ));
        assert!(generic_param_record_passes_required(PARSER_FEATURE_STRUCTS));
        assert!(generic_param_record_passes_required(u32::MAX));
    }

    #[test]
    fn method_passes_follow_member_and_predicate_features() {
        assert!(!method_passes_required(0));
        assert!(!method_passes_required(PARSER_FEATURE_ARRAYS));
        assert!(!method_passes_required(PARSER_FEATURE_IMPORTS));
        assert!(method_passes_required(PARSER_FEATURE_MEMBERS));
        assert!(method_passes_required(PARSER_FEATURE_PREDICATES));
        assert!(method_passes_required(u32::MAX));
    }

    #[test]
    fn type_alias_passes_follow_the_type_alias_feature() {
        assert!(!type_alias_passes_required(0));
        assert!(!type_alias_passes_required(PARSER_FEATURE_TYPE_ARGS));
        assert!(type_alias_passes_required(PARSER_FEATURE_TYPE_ALIASES));
        assert!(type_alias_passes_required(u32::MAX));
    }

    #[test]
    fn generic_call_claim_passes_follow_type_argument_features() {
        assert!(!generic_call_claim_passes_required(0));
        assert!(!generic_call_claim_passes_required(PARSER_FEATURE_ARRAYS));
        assert!(!generic_call_claim_passes_required(PARSER_FEATURE_IMPORTS));
        assert!(!generic_call_claim_passes_required(
            PARSER_FEATURE_PREDICATES
        ));
        assert!(generic_call_claim_passes_required(PARSER_FEATURE_TYPE_ARGS));
        assert!(generic_call_claim_passes_required(u32::MAX));
    }

    #[test]
    fn dependency_interfaces_reserve_generic_claim_rows_without_local_type_arguments() {
        assert_eq!(generic_claim_capacity_for_job(64, 0, false), 1);
        assert_eq!(
            generic_claim_capacity_for_job(64, 0, true),
            generic_claim_capacity(64)
        );
    }

    #[test]
    fn semantic_family_passes_follow_their_parser_features() {
        assert!(!array_passes_required(PARSER_FEATURE_IMPORTS));
        assert!(array_passes_required(PARSER_FEATURE_ARRAYS));
        assert!(!struct_init_passes_required(PARSER_FEATURE_IMPORTS));
        assert!(struct_init_passes_required(PARSER_FEATURE_STRUCTS));
        assert!(!member_passes_required(PARSER_FEATURE_IMPORTS));
        assert!(member_passes_required(PARSER_FEATURE_MEMBERS));
        assert!(!enum_passes_required(PARSER_FEATURE_IMPORTS));
        assert!(enum_passes_required(PARSER_FEATURE_ENUMS));
        assert!(!match_passes_required(PARSER_FEATURE_IMPORTS));
        assert!(match_passes_required(PARSER_FEATURE_MATCHES));
        assert!(!aggregate_passes_required(PARSER_FEATURE_IMPORTS));
        for feature in [
            PARSER_FEATURE_ARRAYS,
            PARSER_FEATURE_ENUMS,
            PARSER_FEATURE_MEMBERS,
            PARSER_FEATURE_STRUCTS,
            PARSER_FEATURE_TYPE_ARGS,
        ] {
            assert!(aggregate_passes_required(feature));
        }
        assert!(aggregate_passes_required(u32::MAX));
    }
}

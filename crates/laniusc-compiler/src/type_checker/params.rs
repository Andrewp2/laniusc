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
}

/// Uniform for the loop-depth prefix-scan passes.
///
/// The pass family marks loop entry/exit deltas, scans them by token or HIR
/// order, and exposes the resulting nesting depth to control-flow validation.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct LoopDepthParams {
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

/// Uniform for counted scans used while compacting name-like rows.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct NameScanParams {
    pub(in crate::type_checker) n_items: u32,
    pub(in crate::type_checker) n_blocks: u32,
    pub(in crate::type_checker) scan_step: u32,
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

/// Uniform for one byte pass of name radix sorting.
///
/// Names are sorted by source bytes plus kind; `radix_byte_offset` selects the
/// byte currently being histogrammed/scattered.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct NameRadixParams {
    pub(in crate::type_checker) name_count: u32,
    pub(in crate::type_checker) source_len: u32,
    pub(in crate::type_checker) n_blocks: u32,
    pub(in crate::type_checker) radix_byte_offset: u32,
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

/// Uniform for predicate-obligation collection and validation phases.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct PredicateObligationParams {
    pub(in crate::type_checker) stage: u32,
    pub(in crate::type_checker) reserved0: u32,
    pub(in crate::type_checker) reserved1: u32,
    pub(in crate::type_checker) reserved2: u32,
}

/// Predicate-obligation stage that counts emitted obligation pairs.
pub(in crate::type_checker) const PREDICATE_OBLIGATION_STAGE_COUNT: u32 = 0;
/// Predicate-obligation stage that validates previously counted pairs.
pub(in crate::type_checker) const PREDICATE_OBLIGATION_STAGE_VALIDATE: u32 = 1;

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

/// Uniform for radix-sorting module, declaration, import, and visible keys.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct ModuleKeyRadixParams {
    pub(in crate::type_checker) module_capacity: u32,
    pub(in crate::type_checker) reserved: u32,
    pub(in crate::type_checker) n_blocks: u32,
    pub(in crate::type_checker) key_step: u32,
}

/// Uniform for radix-sorting predicate keys.
///
/// `mode` selects the predicate key shape: owner, impl, method contract, or
/// method parameter.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct PredicateKeyParams {
    pub(in crate::type_checker) predicate_capacity: u32,
    pub(in crate::type_checker) token_capacity: u32,
    pub(in crate::type_checker) n_blocks: u32,
    pub(in crate::type_checker) key_step: u32,
    pub(in crate::type_checker) mode: u32,
    pub(in crate::type_checker) reserved: u32,
}

/// Uniform for radix-sorting struct-field keys and generic field lookups.
#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct StructFieldKeyRadixParams {
    pub(in crate::type_checker) hir_node_capacity: u32,
    pub(in crate::type_checker) token_capacity: u32,
    pub(in crate::type_checker) n_blocks: u32,
    pub(in crate::type_checker) key_step: u32,
    pub(in crate::type_checker) radix_bytes: u32,
    pub(in crate::type_checker) reserved0: u32,
    pub(in crate::type_checker) reserved1: u32,
    pub(in crate::type_checker) reserved2: u32,
}

/// Number of cached words reserved per compacted call-parameter row.
pub(in crate::type_checker) const CALL_PARAM_CACHE_STRIDE: usize = 4;
/// Number of words reserved per type-instance argument reference.
///
/// Each argument reference carries a tag/payload pair plus reserved slots used
/// by projection and hashing passes. This is a row stride, not a semantic limit
/// on how many type arguments an item may have.
pub const TYPE_INSTANCE_ARG_REF_STRIDE: usize = 4;
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

pub(in crate::type_checker) fn aggregate_compare_capacity_for_features(
    hir_node_capacity: u32,
    parser_feature_flags: u32,
) -> u32 {
    use crate::lexer::features::{
        PARSER_FEATURE_ARRAYS,
        PARSER_FEATURE_ENUMS,
        PARSER_FEATURE_STRUCTS,
        PARSER_FEATURE_TYPE_ARGS,
    };
    const AGGREGATE_FEATURES: u32 = PARSER_FEATURE_TYPE_ARGS
        | PARSER_FEATURE_ARRAYS
        | PARSER_FEATURE_ENUMS
        | PARSER_FEATURE_STRUCTS;
    if parser_feature_flags & AGGREGATE_FEATURES == 0 {
        1
    } else {
        hir_node_capacity.max(1)
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

pub(in crate::type_checker) fn member_capacity_for_features(
    token_capacity: u32,
    parser_feature_flags: u32,
) -> u32 {
    if parser_feature_flags & crate::lexer::features::PARSER_FEATURE_MEMBERS == 0 {
        1
    } else {
        token_capacity.max(1)
    }
}

/// Bucket count for byte-wise radix sorting plus an end-of-name bucket.
pub(in crate::type_checker) const NAME_RADIX_BUCKETS: u32 = 257;
/// Number of builtin symbols materialized before user names are resolved.
pub(in crate::type_checker) const LANGUAGE_SYMBOL_COUNT: u32 = 53;
/// Concatenated builtin symbol spelling table.
pub(in crate::type_checker) const LANGUAGE_SYMBOL_BYTES: &[u8] =
    b"mainassertprintbooli8i16i32i64isizeu8u16u32u64usizef32f64charstrprint_i32_open_read_pathopen_write_pathread_i32write_textwrite_i32write_bytewrite_newlineclose_filei32_to_f32exitsecure_u32allocdeallocargcarg_lenarg_readunix_secondscurrent_dir_readvar_countvar_key_lenvar_key_readvar_lenvar_readclosereadwriteopen_readopen_writeopen_appendwrite_stdoutwrite_stderrread_stdini32_array_data_ptr";
/// Start offsets into `LANGUAGE_SYMBOL_BYTES` for each builtin symbol.
pub(in crate::type_checker) const LANGUAGE_SYMBOL_STARTS: &[u32] = &[
    0, 4, 10, 15, 19, 21, 24, 27, 30, 35, 37, 40, 43, 46, 51, 54, 57, 61, 64, 73, 74, 88, 103, 111,
    121, 130, 140, 153, 163, 173, 177, 187, 192, 199, 203, 210, 218, 230, 246, 255, 266, 278, 285,
    293, 298, 302, 307, 316, 326, 337, 349, 361, 371,
];
/// Byte lengths for each builtin symbol spelling.
pub(in crate::type_checker) const LANGUAGE_SYMBOL_LENS: &[u32] = &[
    4, 6, 5, 4, 2, 3, 3, 3, 5, 2, 3, 3, 3, 5, 3, 3, 4, 3, 9, 1, 14, 15, 8, 10, 9, 10, 13, 10, 10,
    4, 10, 5, 7, 4, 7, 8, 12, 16, 9, 11, 12, 7, 8, 5, 4, 5, 9, 10, 11, 12, 12, 10, 18,
];
/// Number of language declarations materialized from builtin symbols.
pub(in crate::type_checker) const LANGUAGE_DECL_COUNT: u32 = 19;
const LANGUAGE_DECL_KIND_ENTRYPOINT: u32 = 1;
const LANGUAGE_DECL_KIND_INTRINSIC: u32 = 2;
const LANGUAGE_DECL_KIND_PRIMITIVE_TYPE: u32 = 3;
const LANGUAGE_DECL_TAG_MAIN: u32 = 1;
const LANGUAGE_DECL_TAG_PRINT: u32 = 1;
const LANGUAGE_DECL_TAG_ASSERT: u32 = 2;
/// Builtin symbol slots that become materialized language declarations.
pub(in crate::type_checker) const LANGUAGE_DECL_SYMBOL_SLOTS: &[u32] = &[
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
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
];
/// Number of key segments used when sorting module identities.
pub(in crate::type_checker) const MODULE_KEY_SORT_SEGMENTS: u32 = 8;
/// Row width of one module-key sort entry.
pub(in crate::type_checker) const MODULE_KEY_SEGMENT_ROW_WIDTH: usize =
    MODULE_KEY_SORT_SEGMENTS as usize;
/// Full byte-step count for module-key sorting.
pub(in crate::type_checker) const MODULE_KEY_RADIX_STEPS: u32 = MODULE_KEY_SORT_SEGMENTS * 4;
/// Largest source-file table sorted cooperatively by one 256-lane workgroup.
pub(in crate::type_checker) const MODULE_KEY_SMALL_SORT_CAPACITY: u32 = 256;
/// Byte-step count for declaration-key sorting.
pub(in crate::type_checker) const DECL_KEY_RADIX_STEPS: u32 = 12;
/// Largest compact module relation sorted by one cooperative 256-lane workgroup.
pub(in crate::type_checker) const MODULE_RELATION_SMALL_SORT_CAPACITY: u32 = 2048;
/// Byte-step count for import-edge sorting.
pub(in crate::type_checker) const IMPORT_EDGE_KEY_RADIX_STEPS: u32 = 8;
/// Byte-step count for visible-import sorting.
pub(in crate::type_checker) const IMPORT_VISIBLE_KEY_RADIX_STEPS: u32 = 8;
/// Byte-step count for method-key sorting.
pub(in crate::type_checker) const METHOD_KEY_RADIX_STEPS: u32 = 24;
/// Largest token-indexed method table sorted cooperatively by one 256-lane workgroup.
pub(in crate::type_checker) const METHOD_KEY_SMALL_SORT_CAPACITY: u32 = 2048;
/// Largest compact generic-parameter table sorted cooperatively in one dispatch.
pub(in crate::type_checker) const GENERIC_PARAM_SMALL_SORT_CAPACITY: u32 = 2048;
/// Largest compact visible-declaration table sorted by one cooperative workgroup.
pub(in crate::type_checker) const VISIBLE_DECL_SMALL_SORT_CAPACITY: u32 = 2048;
/// Largest sparse predicate table sorted by one 32 KiB cooperative workgroup.
pub(in crate::type_checker) const PREDICATE_KEY_SMALL_SORT_CAPACITY: u32 = 8192;
/// Predicate key mode for grouping predicates by owner.
pub(in crate::type_checker) const PREDICATE_KEY_MODE_OWNER: u32 = 0;
/// Predicate key mode for impl lookup.
pub(in crate::type_checker) const PREDICATE_KEY_MODE_IMPL: u32 = 1;
/// Predicate key mode for method-contract lookup.
pub(in crate::type_checker) const PREDICATE_KEY_MODE_METHOD_CONTRACT: u32 = 2;
/// Predicate key mode for method-parameter lookup.
pub(in crate::type_checker) const PREDICATE_KEY_MODE_METHOD_PARAM: u32 = 3;
/// Byte-step count for predicate-owner keys.
pub(in crate::type_checker) const PREDICATE_OWNER_KEY_RADIX_STEPS: u32 = 8;
/// Byte-step count for predicate-impl keys.
pub(in crate::type_checker) const PREDICATE_IMPL_KEY_RADIX_STEPS: u32 = 20;
/// Byte-step count for predicate method-contract keys.
pub(in crate::type_checker) const PREDICATE_METHOD_CONTRACT_KEY_RADIX_STEPS: u32 = 12;
/// Byte-step count for predicate method-parameter keys.
pub(in crate::type_checker) const PREDICATE_METHOD_PARAM_KEY_RADIX_STEPS: u32 = 12;
const VISIBLE_DECL_KEY_FIELD_COUNT: u32 = 3;
const VISIBLE_DECL_KEY_MAX_RADIX_STEPS: u32 = 12;
/// Number of visible-declaration rows summarized into one scope-tree leaf.
pub(in crate::type_checker) const HIR_VISIBLE_DECL_ROW_BLOCK_SIZE: u32 = 64;

/// Returns the number of bytes needed to sort visible-declaration keys.
pub(in crate::type_checker) fn visible_decl_key_radix_bytes(decl_capacity: u32) -> u32 {
    let max_key = decl_capacity
        .saturating_add(LANGUAGE_SYMBOL_COUNT)
        .saturating_add(1)
        .max(1);
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

/// Returns the even radix-step count used for visible-declaration key sorting.
pub(in crate::type_checker) fn visible_decl_key_radix_steps(decl_capacity: u32) -> u32 {
    let steps = visible_decl_key_radix_bytes(decl_capacity) * VISIBLE_DECL_KEY_FIELD_COUNT;
    let even_steps = if steps % 2 == 0 { steps } else { steps + 1 };
    even_steps.min(VISIBLE_DECL_KEY_MAX_RADIX_STEPS)
}

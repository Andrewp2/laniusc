use encase::ShaderType;

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct TypeCheckParams {
    pub(in crate::type_checker) n_tokens: u32,
    pub(in crate::type_checker) source_len: u32,
    pub(in crate::type_checker) n_hir_nodes: u32,
    pub(in crate::type_checker) n_source_files: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct LoopDepthParams {
    pub(in crate::type_checker) n_tokens: u32,
    pub(in crate::type_checker) n_hir_nodes: u32,
    pub(in crate::type_checker) n_blocks: u32,
    pub(in crate::type_checker) scan_step: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct FnContextParams {
    pub(in crate::type_checker) n_tokens: u32,
    pub(in crate::type_checker) n_hir_nodes: u32,
    pub(in crate::type_checker) n_blocks: u32,
    pub(in crate::type_checker) scan_step: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct NameScanParams {
    pub(in crate::type_checker) n_items: u32,
    pub(in crate::type_checker) n_blocks: u32,
    pub(in crate::type_checker) scan_step: u32,
}

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

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct NameRadixParams {
    pub(in crate::type_checker) name_count: u32,
    pub(in crate::type_checker) source_len: u32,
    pub(in crate::type_checker) n_blocks: u32,
    pub(in crate::type_checker) radix_byte_offset: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct CountDispatchParams {
    pub(in crate::type_checker) capacity: u32,
    pub(in crate::type_checker) multiplier: u32,
    pub(in crate::type_checker) reserved0: u32,
    pub(in crate::type_checker) reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct CountPairMaxDispatchParams {
    pub(in crate::type_checker) left_capacity: u32,
    pub(in crate::type_checker) right_capacity: u32,
    pub(in crate::type_checker) multiplier: u32,
    pub(in crate::type_checker) reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct RecordFamilyFlagParams {
    pub(in crate::type_checker) n_hir_nodes: u32,
    pub(in crate::type_checker) family_bit: u32,
    pub(in crate::type_checker) reserved0: u32,
    pub(in crate::type_checker) reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(in crate::type_checker) struct ModuleKeyRadixParams {
    pub(in crate::type_checker) module_capacity: u32,
    pub(in crate::type_checker) reserved: u32,
    pub(in crate::type_checker) n_blocks: u32,
    pub(in crate::type_checker) key_step: u32,
}

pub(in crate::type_checker) const CALL_PARAM_CACHE_STRIDE: usize = 4;
pub(in crate::type_checker) const CALL_ARG_NODE_CAPACITY_WORDS: usize = 1;
pub const TYPE_INSTANCE_ARG_REF_STRIDE: usize = 4;

pub(in crate::type_checker) const NAME_RADIX_BUCKETS: u32 = 257;
pub(in crate::type_checker) const NAME_RADIX_MAX_BYTES: u32 = 64;
pub(in crate::type_checker) const LANGUAGE_SYMBOL_COUNT: u32 = 19;
pub(in crate::type_checker) const LANGUAGE_SYMBOL_BYTES: &[u8] =
    b"mainassertprintbooli8i16i32i64isizeu8u16u32u64usizef32f64charstr_";
pub(in crate::type_checker) const LANGUAGE_SYMBOL_STARTS: &[u32] = &[
    0, 4, 10, 15, 19, 21, 24, 27, 30, 35, 37, 40, 43, 46, 51, 54, 57, 61, 64,
];
pub(in crate::type_checker) const LANGUAGE_SYMBOL_LENS: &[u32] =
    &[4, 6, 5, 4, 2, 3, 3, 3, 5, 2, 3, 3, 3, 5, 3, 3, 4, 3, 1];
pub(in crate::type_checker) const LANGUAGE_DECL_COUNT: u32 = 18;
const LANGUAGE_DECL_KIND_ENTRYPOINT: u32 = 1;
const LANGUAGE_DECL_KIND_INTRINSIC: u32 = 2;
const LANGUAGE_DECL_KIND_PRIMITIVE_TYPE: u32 = 3;
const LANGUAGE_DECL_TAG_MAIN: u32 = 1;
const LANGUAGE_DECL_TAG_PRINT: u32 = 1;
const LANGUAGE_DECL_TAG_ASSERT: u32 = 2;
pub(in crate::type_checker) const LANGUAGE_DECL_SYMBOL_SLOTS: &[u32] =
    &[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17];
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
];
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
];
pub(in crate::type_checker) const MODULE_KEY_SORT_SEGMENTS: u32 = 8;
pub(in crate::type_checker) const MODULE_KEY_SEGMENT_ROW_WIDTH: usize =
    MODULE_KEY_SORT_SEGMENTS as usize;
pub(in crate::type_checker) const PATH_SEGMENT_ROW_WIDTH: usize =
    MODULE_KEY_SORT_SEGMENTS as usize + 1;
pub(in crate::type_checker) const MODULE_KEY_RADIX_STEPS: u32 = MODULE_KEY_SORT_SEGMENTS * 4;
pub(in crate::type_checker) const DECL_KEY_RADIX_STEPS: u32 = 12;
pub(in crate::type_checker) const IMPORT_VISIBLE_KEY_RADIX_STEPS: u32 = 8;
pub(in crate::type_checker) const METHOD_KEY_RADIX_STEPS: u32 = 16;
const VISIBLE_DECL_KEY_FIELD_COUNT: u32 = 3;
const VISIBLE_DECL_KEY_MAX_RADIX_STEPS: u32 = 12;
pub(in crate::type_checker) const HIR_VISIBLE_DECL_ROW_BLOCK_SIZE: u32 = 64;

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

pub(in crate::type_checker) fn visible_decl_key_radix_steps(decl_capacity: u32) -> u32 {
    let steps = visible_decl_key_radix_bytes(decl_capacity) * VISIBLE_DECL_KEY_FIELD_COUNT;
    let even_steps = if steps % 2 == 0 { steps } else { steps + 1 };
    even_steps.min(VISIBLE_DECL_KEY_MAX_RADIX_STEPS)
}

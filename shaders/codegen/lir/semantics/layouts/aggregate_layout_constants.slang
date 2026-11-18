// Constants shared by the aggregate layout kernels (function_layout_*.slang).
#ifndef FUNCTION_LAYOUT_CONSTANTS
#define FUNCTION_LAYOUT_CONSTANTS
static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint HIR_TYPE_FORM_SLICE = 3u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint MAX_LAYOUT_DEPTH = 64u;
#endif

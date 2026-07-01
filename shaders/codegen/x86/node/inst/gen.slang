// x86_64 node-local virtual instruction generation.
//
// This is the Pareas-style instruction generation counterpart to
// x86_node_inst_counts: instruction rows are assigned by prefix ranges, and
// x86_node_inst_location_record carries corrected branch/loop slots. This pass
// walks the compact node-generation worklist and fills the virtual instruction
// rows from attributed HIR/backend records only.

import gpu_index;
import byte_packing;
import bit_packing;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

struct FeatureParams
{
    uint mask;
    uint enum_count;
    uint match_count;
    uint aggregate_count;
};

ConstantBuffer<FeatureParams> gX86Features;

StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> x86_tree_parent;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_expr_float_bits;
StructuredBuffer<uint> hir_expr_string_len;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> x86_struct_type_record;
StructuredBuffer<uint> x86_decl_layout_record;
StructuredBuffer<uint2> x86_const_value_record;
StructuredBuffer<uint> x86_local_literal_record;
StructuredBuffer<uint> x86_param_reg_record;
StructuredBuffer<uint2> x86_call_abi_record;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> x86_intrinsic_call_record;
StructuredBuffer<uint2> x86_enum_value_record;
StructuredBuffer<uint4> x86_match_record;
StructuredBuffer<uint> x86_match_arm_owner;
StructuredBuffer<uint> x86_match_result_value_owner;
StructuredBuffer<uint> x86_struct_access_record;
StructuredBuffer<uint4> x86_struct_store_record;
StructuredBuffer<uint> x86_node_inst_range_info;
StructuredBuffer<uint4> x86_node_inst_location_record;
StructuredBuffer<uint> x86_node_inst_subtree_bound_start;
StructuredBuffer<uint> x86_node_inst_subtree_bound_end;
StructuredBuffer<uint> x86_expr_semantic_type;
StructuredBuffer<uint> x86_node_inst_gen_input_status;
StructuredBuffer<uint2> x86_node_inst_gen_node_record;
StructuredBuffer<uint> x86_enclosing_loop_node;
StructuredBuffer<uint> x86_short_circuit_rhs_node;
StructuredBuffer<uint> x86_index_source_owner;
StructuredBuffer<uint> x86_match_return_node;
StructuredBuffer<uint> x86_enclosing_let_node;
StructuredBuffer<uint> x86_enclosing_return_node;
StructuredBuffer<uint> x86_node_func;
StructuredBuffer<uint> x86_func_slot_by_node;

RWStructuredBuffer<uint4> x86_virtual_inst_record;
RWStructuredBuffer<uint4> x86_virtual_inst_args;
RWStructuredBuffer<uint> x86_virtual_inst_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_INST_GEN_INPUTS_OK = 1u;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_STRUCT_ACCESS_ARRAY_LITERAL = 3u;
static const uint X86_STRUCT_ACCESS_ARRAY_ELEMENT = 4u;
static const uint X86_AGG_STORE_ARRAY = 2u;
static const uint X86_ERR_NODE_VIRTUAL_INST = 11u;
static const uint X86_ERR_INDEX_ASSIGNMENT = 31u;
static const uint X86_ERR_LOOP_CONTAINED_CALL = 29u;
static const uint X86_ERR_ZERO_DIVISOR = 32u;
static const uint X86_ERR_SHORT_CIRCUIT_CALL = 35u;
static const uint X86_ERR_PARAM_AGG_ASSIGN = 37u;
static const uint X86_ERR_PARAM_AGG_INDEX_ASSIGN = 38u;
static const uint X86_ERR_INDEX_BOUNDS = 40u;
static const uint X86_ERR_DYNAMIC_DIVISOR = 41u;
static const uint X86_ERR_SHORT_CIRCUIT_TRAP = 42u;
static const uint X86_ERR_AGGREGATE_TEMPORARY_INDEX = 45u;
static const uint X86_ERR_DYNAMIC_INDEX = 47u;
static const uint X86_ERR_AGGREGATE_RETURN_CALL = 52u;
static const uint X86_ERR_LOOP_CONTROL_OUTSIDE_LOOP = 55u;
static const uint X86_ERR_SIGNED_DIV_OVERFLOW = 59u;
static const uint X86_ERR_NESTED_AGGREGATE_MEMBER = 61u;
static const uint X86_VINST_ERROR_INDEX_OPERAND = 2001u;
static const uint X86_VINST_ERROR_INDEX_SOURCE = 2002u;
static const uint X86_VINST_ERROR_INDEX_VREG = 2003u;
static const uint X86_VINST_ERROR_CALL_INTRINSIC = 2101u;
static const uint X86_VINST_ERROR_CALL_INTRINSIC_ARG = 2102u;
static const uint X86_VINST_ERROR_CALL_RECORD = 2103u;
static const uint X86_VINST_ERROR_CALL_TARGET = 2104u;
static const uint X86_VINST_ERROR_CALL_ARG_COUNT = 2105u;
static const uint X86_VINST_ERROR_CALL_ARG0_NODE = 2106u;
static const uint X86_VINST_ERROR_CALL_ARG1_NODE = 2107u;
static const uint X86_VINST_ERROR_CALL_ARG0_OPERAND = 2108u;
static const uint X86_VINST_ERROR_CALL_ARG1_OPERAND = 2109u;
static const uint X86_VINST_ERROR_CALL_AGG_DEST = 2110u;
static const uint X86_VINST_ERROR_CALL_AGG_DEST_NO_LET = 2111u;
static const uint X86_VINST_ERROR_CALL_AGG_DEST_NOT_INIT = 2112u;
static const uint X86_VINST_ERROR_CALL_AGG_DEST_WIDTH = 2113u;
static const uint X86_VINST_ERROR_CALL_AGG_DEST_SLOT = 2114u;
static const uint X86_VINST_ERROR_CALL_ARG2_NODE = 2115u;
static const uint X86_VINST_ERROR_CALL_ARG3_NODE = 2116u;
static const uint X86_VINST_ERROR_CALL_ARG2_OPERAND = 2117u;
static const uint X86_VINST_ERROR_CALL_ARG3_OPERAND = 2118u;
static const uint X86_VINST_ERROR_CALL_ARG_PACK = 2119u;
static const uint X86_VINST_ERROR_CALL_IN_LOOP = 2120u;
static const uint X86_VINST_ERROR_CALL_ARG4_NODE = 2121u;
static const uint X86_VINST_ERROR_CALL_ARG5_NODE = 2122u;
static const uint X86_VINST_ERROR_CALL_ARG4_OPERAND = 2123u;
static const uint X86_VINST_ERROR_CALL_ARG5_OPERAND = 2124u;
static const uint X86_CALL_ABI_ARG_COUNT_BITS = 8u;
static const uint X86_CALL_ABI_ARG_COUNT_MASK = 0xffu;
static const uint X86_CALL_ABI_RETURN_WIDTH_MAX = 0x00ffffffu;
static const uint X86_CALL_TARGET_HOST_TEXT_WRITE = 0xfffffffeu;
static const uint X86_CALL_TARGET_HOST_ARG_READ = 0xffffffefu;
static const uint X86_CALL_TARGET_HOST_UNIX_SECONDS = 0xffffffeeu;
static const uint X86_CALL_TARGET_HOST_CURRENT_DIR_READ = 0xffffffedu;
static const uint X86_CALL_TARGET_HOST_VAR_KEY_READ = 0xffffffeau;
static const uint X86_CALL_TARGET_HOST_VAR_READ = 0xffffffe8u;
static const uint X86_CALL_TARGET_HOST_FS_WRITE = 0xffffffe6u;
static const uint X86_CALL_TARGET_HOST_FS_OPEN_APPEND = 0xffffffe3u;
static const uint X86_CALL_TARGET_HOST_STDERR_WRITE = 0xffffffe0u;
static const uint X86_BACKEND_MAX_PACKED_CALL_ARGS = 6u;
static const uint X86_VINST_ERROR_MATCH_ARMS = 2201u;
static const uint X86_VINST_ERROR_MATCH_PATTERN = 2202u;
static const uint X86_VINST_ERROR_MATCH_SOURCE = 2203u;
static const uint X86_VINST_ERROR_MATCH_LOCATION = 2204u;
static const uint X86_VINST_ERROR_MATCH_TARGET = 2205u;
static const uint X86_VINST_ERROR_MATCH_RESULT = 2206u;
static const uint X86_VINST_ERROR_MATCH_PATTERN_UNRESOLVED = 2207u;
static const uint X86_VINST_ERROR_MATCH_PATTERN_NO_USE_TOKEN = 2208u;
static const uint X86_VINST_ERROR_MATCH_PATTERN_NO_VARIANT = 2209u;
static const uint X86_VINST_ERROR_NAME_MATCH_PAYLOAD_COUNT = 2301u;
static const uint X86_VINST_ERROR_NAME_MATCH_PAYLOAD_BINDING = 2302u;
static const uint X86_VINST_ERROR_NAME_MATCH_PAYLOAD_SOURCE = 2303u;
static const uint X86_VINST_ERROR_NAME_MATCH_PAYLOAD_WIDTH = 2304u;
static const uint X86_VINST_ERROR_MEMBER_RECORD = 2401u;
static const uint X86_VINST_ERROR_MEMBER_ORDINAL = 2402u;
static const uint X86_VINST_ERROR_MEMBER_SOURCE = 2403u;
static const uint X86_VINST_ERROR_MEMBER_WIDTH = 2404u;
static const uint X86_VINST_ERROR_MEMBER_SOURCE_BAD_NODE = 2410u;
static const uint X86_VINST_ERROR_MEMBER_SOURCE_NOT_NAME = 2411u;
static const uint X86_VINST_ERROR_MEMBER_SOURCE_TOKEN = 2412u;
static const uint X86_VINST_ERROR_MEMBER_SOURCE_DECL = 2413u;
static const uint X86_VINST_ERROR_MEMBER_SOURCE_LOCAL_OWNER = 2414u;
static const uint X86_VINST_ERROR_MEMBER_SOURCE_LOCAL_WIDTH = 2415u;
static const uint X86_VINST_ERROR_MEMBER_SOURCE_NO_PARAM = 2416u;
static const uint X86_VINST_ERROR_MEMBER_SOURCE_PARAM_OWNER = 2417u;
static const uint X86_VINST_ERROR_MEMBER_SOURCE_PARAM_REG = 2418u;
static const uint X86_VINST_ERROR_MEMBER_SOURCE_PARAM_WIDTH = 2419u;
static const uint X86_VINST_ERROR_BINARY_LEFT = 2501u;
static const uint X86_VINST_ERROR_BINARY_RIGHT = 2502u;
static const uint X86_VINST_ERROR_AGG_RET_STRUCT_WIDTH = 2601u;
static const uint X86_VINST_ERROR_AGG_RET_STRUCT_FIELD = 2602u;
static const uint X86_VINST_ERROR_AGG_RET_STRUCT_VALUE = 2603u;
static const uint X86_VINST_ERROR_AGG_RET_STRUCT_LOCATION = 2604u;
static const uint X86_VINST_ERROR_AGG_RET_ARRAY_WIDTH = 2611u;
static const uint X86_VINST_ERROR_AGG_RET_ARRAY_FIELD = 2612u;
static const uint X86_VINST_ERROR_AGG_RET_ARRAY_VALUE = 2613u;
static const uint X86_VINST_ERROR_AGG_RET_ARRAY_LOCATION = 2614u;
static const uint X86_VINST_ERROR_AGG_RET_SOURCE = 2621u;
static const uint X86_VINST_ERROR_AGG_RET_SOURCE_LOCATION = 2622u;
static const uint X86_VINST_ERROR_AGG_RET_RETURN_LOCATION = 2631u;
static const uint X86_VINST_ERROR_NAME_NODE = 2701u;
static const uint X86_VINST_ERROR_NAME_TOKEN = 2702u;
static const uint X86_VINST_ERROR_NAME_DECL = 2703u;
static const uint X86_VINST_ERROR_NAME_VALUE = 2704u;
static const uint X86_VINST_ERROR_ASSIGN_TARGET = 2901u;
static const uint X86_VINST_ERROR_ASSIGN_RHS = 2902u;
static const uint X86_VINST_ERROR_ASSIGN_LHS = 2903u;
static const uint X86_VINST_ERROR_ASSIGN_LOCATION = 2904u;
static const uint X86_VINST_ERROR_LET_INIT_VALUE = 3001u;
static const uint X86_VINST_ERROR_LET_SLOT = 3002u;
static const uint X86_VINST_ERROR_RETURN_LOCATION = 3003u;
static const uint X86_VINST_ERROR_AGG_COPY_WIDTH = 3011u;
static const uint X86_VINST_ERROR_ROW_OUTSIDE_SUBTREE = 3021u;
static const uint X86_AGG_COPY_MAX_WIDTH = 65535u;
static const uint X86_VINST_ERROR_AGG_RET_COPY_WIDTH = 2623u;

static const uint HIR_FN = 3u;
static const uint HIR_STMT = 7u;
static const uint HIR_PARAM = 4u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_BREAK_STMT = 12u;
static const uint HIR_CONTINUE_STMT = 13u;
static const uint HIR_EXPR = 14u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_POSTFIX_EXPR = 18u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_MATCH_EXPR = 34u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint STMT_RECORD_KIND_ASSIGN = 5u;
static const uint STMT_RECORD_KIND_WHILE = 6u;
static const uint STMT_RECORD_KIND_FOR = 7u;

static const uint X86_DECL_LAYOUT_STRIDE = 4u;
static const uint X86_DECL_LAYOUT_KIND_MASK = 0x0fu;
static const uint X86_DECL_LAYOUT_KIND_BITS = 4u;
static const uint X86_DECL_AGG_ARRAY = 1u;
static const uint X86_DECL_AGG_STRUCT = 3u;
static const uint X86_STRUCT_ACCESS_STRIDE = 3u;
static const uint X86_STRUCT_ACCESS_KIND_BITS = 4u;
static const uint X86_STRUCT_ACCESS_KIND_MASK = 0x0fu;
static const uint X86_PARAM_REG_STRIDE = 6u;
static const uint X86_PARAM_REG_ARG_REG_MASK = 0x0fu;
static const uint X86_PARAM_REG_KIND_BITS = 4u;
static const uint X86_LOCAL_LITERAL_STRIDE = 3u;

static const uint ASSIGN_OP_SET = 1u;
static const uint ASSIGN_OP_ADD = 2u;
static const uint ASSIGN_OP_SUB = 3u;
static const uint ASSIGN_OP_MUL = 4u;
static const uint ASSIGN_OP_DIV = 5u;
static const uint ASSIGN_OP_MOD = 6u;
static const uint ASSIGN_OP_XOR = 7u;
static const uint ASSIGN_OP_SHL = 8u;
static const uint ASSIGN_OP_SHR = 9u;
static const uint ASSIGN_OP_BAND = 10u;
static const uint ASSIGN_OP_BOR = 11u;

static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SUB = 15u;
static const uint HIR_EXPR_MUL = 16u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint HIR_EXPR_INDEX = 26u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_STRING = 28u;
static const uint HIR_EXPR_RANGE = 30u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint X86_CONST_VALUE_LITERAL = 1u;

static const uint X86_NODE_VALUE_NONE = 0u;
static const uint X86_NODE_VALUE_VREG = 1u;
static const uint X86_NODE_VALUE_IMM_I32 = 2u;
static const uint X86_NODE_VALUE_PARAM = 3u;

static const uint X86_VINST_NONE = 0u;
static const uint X86_VINST_IMM_I32 = 1u;
static const uint X86_VINST_PARAM = 2u;
static const uint X86_VINST_UNARY = 3u;
static const uint X86_VINST_BINARY = 4u;
static const uint X86_VINST_COMPARE = 5u;
static const uint X86_VINST_INTRINSIC = 7u;
static const uint X86_VINST_ALIAS = 8u;
static const uint X86_VINST_RETURN = 9u;
static const uint X86_VINST_BRANCH = 10u;
static const uint X86_VINST_LOOP = 11u;
static const uint X86_VINST_TRANSFER = 12u;
static const uint X86_VINST_LOAD_LOCAL = 13u;
static const uint X86_VINST_STORE_LOCAL = 14u;
static const uint X86_VINST_LOAD_LOCAL_INDEX = 15u;
static const uint X86_VINST_STORE_LOCAL_IMM = 16u;
static const uint X86_VINST_CALL_MIXED = 20u;
static const uint X86_VINST_LOAD_PARAM_INDEX = 21u;
static const uint X86_VINST_STORE_RET_PTR = 22u;
static const uint X86_VINST_COPY_AGG_RET = 23u;
static const uint X86_VINST_RETURN_VOID = 24u;
static const uint X86_VINST_STORE_RET_PTR_IMM = 25u;
static const uint X86_VINST_LOAD_PARAM_SLOT = 26u;
static const uint X86_VINST_MATCH_TAG_BRANCH = 27u;
static const uint X86_VINST_COPY_LOCAL = 29u;
static const uint X86_VINST_STORE_LOCAL_INDEX = 30u;
static const uint X86_VINST_STORE_PARAM_INDEX = 32u;
static const uint X86_VINST_STORE_LOCAL_RODATA_PTR = 33u;
static const uint X86_ARG_SCALAR = 1u;
static const uint X86_ARG_LOCAL_PTR = 2u;
static const uint X86_ARG_PARAM_PTR = 3u;
static const uint X86_AGG_SOURCE_LOCAL = 1u;
static const uint X86_AGG_SOURCE_PARAM = 2u;
static const uint X86_AGG_RETURN_DEST_RET_PTR = 0xffu;
static const uint X86_NODE_INST_PADDING = 7u;
static const uint X86_NODE_INST_RANGE_KIND_SHIFT = 28u;
static const uint X86_NODE_INST_RANGE_COUNT_MASK = 0x0fffffffu;
static const uint MATCH_ARM_VARIANT_UNKNOWN = 0xffffu;
static const uint MATCH_ARM_VARIANT_UNRESOLVED = 0xfffeu;
static const uint MATCH_ARM_VARIANT_NO_USE_TOKEN = 0xfffdu;
static const uint MATCH_ARM_VARIANT_NO_VARIANT = 0xfffcu;
static const uint X86_INTRINSIC_TEXT_WRITE = 1u;
static const uint X86_INTRINSIC_TAG_BITS = 4u;
static const uint X86_INTRINSIC_TAG_MASK = 0x0fu;
static const uint X86_ENUM_VALUE_CALL_CTOR = 1u;
static const uint X86_ENUM_VALUE_UNIT_CTOR = 2u;
static const uint X86_ENUM_VALUE_VARIANT_REF = 3u;
static const uint X86_ENUM_VALUE_KIND_BITS = 4u;
static const uint X86_ENUM_VALUE_KIND_MASK = 0x0fu;
static const uint X86_FEATURE_ENUM = 1u << 0u;
static const uint X86_FEATURE_MATCH = 1u << 1u;
static const uint X86_FEATURE_AGGREGATE = 1u << 2u;
static const uint X86_STRUCT_ACCESS_MEMBER = 1u;
static const uint X86_STRUCT_ACCESS_LITERAL = 2u;

static const uint X86_OP_NEG_I32 = 1u;
static const uint X86_OP_NOT_BOOL = 2u;
static const uint X86_OP_NEG_F32 = 3u;
static const uint X86_OP_ADD_I32 = 1u;
static const uint X86_OP_SUB_I32 = 2u;
static const uint X86_OP_MUL_I32 = 3u;
static const uint X86_OP_AND_BOOL = 4u;
static const uint X86_OP_OR_BOOL = 5u;
static const uint X86_OP_MOD_I32 = 6u;
static const uint X86_OP_DIV_I32 = 7u;
static const uint X86_OP_BIT_AND_I32 = 8u;
static const uint X86_OP_BIT_OR_I32 = 9u;
static const uint X86_OP_BIT_XOR = 10u;
static const uint X86_OP_SHL_I32 = 11u;
static const uint X86_OP_SHR_I32 = 12u;
static const uint X86_OP_MOD_U32 = 13u;
static const uint X86_OP_DIV_U32 = 14u;
static const uint X86_OP_SHR_U32 = 15u;
static const uint X86_OP_ADD_F32 = 16u;
static const uint X86_OP_SUB_F32 = 17u;
static const uint X86_OP_MUL_F32 = 18u;
static const uint X86_OP_DIV_F32 = 19u;
static const uint X86_CMP_LT = 1u;
static const uint X86_CMP_GT = 2u;
static const uint X86_CMP_LE = 3u;
static const uint X86_CMP_GE = 4u;
static const uint X86_CMP_EQ = 5u;
static const uint X86_CMP_NE = 6u;
static const uint X86_CMP_UNSIGNED_FLAG = 0x80u;
static const uint X86_CMP_FLOAT_FLAG = 0x40u;
static const uint X86_LOCATION_META_KIND_MASK = 0xf0000000u;
static const uint X86_LOCATION_META_EXPR_SEMANTIC_TYPE = 0xe0000000u;
static const uint X86_LOCATION_META_PARAM_DECL = 0xd0000000u;
static const uint X86_LOCATION_META_PAYLOAD_MASK = 0x0fffffffu;
static const uint EXPR_SEMANTIC_UINT_FLAG = 0x40000000u;
static const uint EXPR_SEMANTIC_FLOAT_FLAG = 0x80000000u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint I32_MIN = 0x80000000u;
static const uint I32_NEG_ONE = 0xffffffffu;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes;
}

uint active_path_count()
{
    return min(path_count_out[0u], gParams.n_hir_nodes);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool has_enum_feature()
{
    return (gX86Features.mask & X86_FEATURE_ENUM) != 0u;
}

bool has_match_feature()
{
    return (gX86Features.mask & X86_FEATURE_MATCH) != 0u;
}

bool has_aggregate_feature()
{
    return (gX86Features.mask & X86_FEATURE_AGGREGATE) != 0u;
}

uint call_record_slot(uint call_node)
{
    if (!valid_node(call_node))
        return INVALID;
    uint projection = x86_intrinsic_call_record[call_node];
    uint slot = projection == INVALID ? INVALID : projection >> X86_INTRINSIC_TAG_BITS;
    return valid_token(slot) ? slot : INVALID;
}

uint intrinsic_call_tag(uint call_node)
{
    if (!valid_node(call_node))
        return 0u;
    uint projection = x86_intrinsic_call_record[call_node];
    return projection == INVALID ? 0u : projection & X86_INTRINSIC_TAG_MASK;
}

bool upstream_ok()
{
    return x86_node_inst_gen_input_status[0u] == X86_NODE_INST_GEN_INPUTS_OK &&
           x86_node_inst_gen_input_status[1u] == 0u &&
           x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
           x86_virtual_inst_status[1u] == 0u;
}

uint gen_worklist_count()
{
    return min(
        x86_node_inst_gen_input_status[4u],
        min(gParams.n_hir_nodes, gParams.inst_capacity));
}

uint gen_worklist_node(uint order_row)
{
    return x86_node_inst_gen_node_record[order_row].x;
}

uint virtual_inst_count()
{
    return min(x86_virtual_inst_status[3u], gParams.inst_capacity);
}

bool virtual_row_in_stream(uint row)
{
    return row != INVALID && row < virtual_inst_count();
}

uint stmt_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

uint decl_layout_word(uint row, uint slot)
{
    return row_major_load<uint>(
        x86_decl_layout_record,
        row,
        X86_DECL_LAYOUT_STRIDE,
        slot,
        INVALID);
}

uint decl_layout_base(uint row)
{
    return decl_layout_word(row, 0u);
}

uint decl_layout_width(uint row)
{
    return decl_layout_word(row, 1u);
}

uint decl_layout_info(uint row)
{
    return decl_layout_word(row, 2u);
}

uint decl_layout_type(uint row)
{
    return decl_layout_word(row, 3u);
}

uint decl_layout_kind(uint row)
{
    uint info = decl_layout_info(row);
    return info == INVALID ? 0u : info & X86_DECL_LAYOUT_KIND_MASK;
}

uint decl_layout_node(uint row)
{
    uint info = decl_layout_info(row);
    return info == INVALID ? INVALID : info >> X86_DECL_LAYOUT_KIND_BITS;
}

uint struct_access_word(uint row, uint slot)
{
    if (!has_aggregate_feature())
        return INVALID;
    return row_major_load<uint>(
        x86_struct_access_record,
        row,
        X86_STRUCT_ACCESS_STRIDE,
        slot,
        INVALID);
}

uint struct_access_kind(uint row)
{
    uint info = struct_access_word(row, 2u);
    return info == INVALID ? 0u : info & X86_STRUCT_ACCESS_KIND_MASK;
}

uint struct_access_payload0(uint row)
{
    return struct_access_word(row, 0u);
}

uint struct_access_payload1(uint row)
{
    return struct_access_word(row, 1u);
}

uint struct_access_payload2(uint row)
{
    uint info = struct_access_word(row, 2u);
    return info == INVALID ? INVALID : info >> X86_STRUCT_ACCESS_KIND_BITS;
}

uint param_reg_word(uint decl_token, uint slot)
{
    return row_major_load<uint>(
        x86_param_reg_record,
        decl_token,
        X86_PARAM_REG_STRIDE,
        slot,
        INVALID);
}

uint param_node_decl_token(uint param_node)
{
    if (!valid_node(param_node))
        return INVALID;
    uint meta = x86_node_inst_location_record[param_node].w;
    uint decl_token =
        (meta & X86_LOCATION_META_KIND_MASK) == X86_LOCATION_META_PARAM_DECL
            ? (meta & X86_LOCATION_META_PAYLOAD_MASK)
            : INVALID;
    return valid_token(decl_token) ? decl_token : INVALID;
}

uint param_node_reg_word(uint param_node, uint slot)
{
    uint decl_token = param_node_decl_token(param_node);
    return valid_token(decl_token) ? param_reg_word(decl_token, slot) : INVALID;
}

uint param_reg_owner(uint decl_token)
{
    return param_reg_word(decl_token, 0u);
}

uint param_node_reg_owner(uint param_node)
{
    return param_node_reg_word(param_node, 0u);
}

uint param_reg_width(uint decl_token)
{
    return param_reg_word(decl_token, 1u);
}

uint param_node_reg_width(uint param_node)
{
    return param_node_reg_word(param_node, 1u);
}

uint param_reg_info(uint decl_token)
{
    return param_reg_word(decl_token, 2u);
}

uint param_node_reg_info(uint param_node)
{
    return param_node_reg_word(param_node, 2u);
}

uint param_reg_ordinal(uint decl_token)
{
    return param_reg_word(decl_token, 3u);
}

uint param_node_reg_ordinal(uint param_node)
{
    return param_node_reg_word(param_node, 3u);
}

uint param_reg_arg_reg(uint decl_token)
{
    uint info = param_reg_info(decl_token);
    return info == INVALID
               ? INVALID
               : info & X86_PARAM_REG_ARG_REG_MASK;
}

uint param_reg_aggregate_kind(uint decl_token)
{
    uint info = param_reg_info(decl_token);
    return info == INVALID ? 0u : info >> X86_PARAM_REG_KIND_BITS;
}

uint param_node_reg_arg_reg(uint param_node)
{
    uint info = param_node_reg_info(param_node);
    return info == INVALID
               ? INVALID
               : info & X86_PARAM_REG_ARG_REG_MASK;
}

uint param_reg_type(uint decl_token)
{
    return param_reg_word(decl_token, 4u);
}

uint param_reg_link(uint decl_token)
{
    return param_reg_word(decl_token, 5u);
}

uint param_node_reg_link(uint param_node)
{
    return param_node_decl_token(param_node);
}

uint local_literal_word(uint decl_token, uint slot)
{
    return row_major_load<uint>(
        x86_local_literal_record,
        decl_token,
        X86_LOCAL_LITERAL_STRIDE,
        slot,
        INVALID);
}

uint local_literal_let_node(uint decl_token)
{
    return local_literal_word(decl_token, 1u);
}

uint local_literal_value(uint decl_token)
{
    return local_literal_word(decl_token, 2u);
}

uint4 param_reg_record(uint decl_token)
{
    return uint4(
        param_reg_owner(decl_token),
        param_reg_ordinal(decl_token),
        param_reg_arg_reg(decl_token),
        param_reg_width(decl_token));
}

uint4 param_node_reg_record(uint param_node)
{
    return uint4(
        param_node_reg_owner(param_node),
        param_node_reg_ordinal(param_node),
        param_node_reg_arg_reg(param_node),
        param_node_reg_width(param_node));
}

uint expr_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_expr_record,
        node,
        EXPR_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_FORM) : 0u;
}

bool is_index_expr_node(uint node)
{
    if (!valid_node(node))
        return false;
    if (hir_kind[node] == HIR_INDEX_EXPR)
        return true;
    return hir_kind[node] == HIR_EXPR && expr_form(node) == HIR_EXPR_INDEX;
}

uint expr_left(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_LEFT) : INVALID;
}

uint expr_right(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_RIGHT) : INVALID;
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

uint expr_result_root(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : resolve_expr(node);
}

bool range_for_node(uint node, out uint2 range)
{
    range = uint2(INVALID, 0u);
    if (!valid_node(node))
        return false;
    range = uint2(x86_node_inst_location_record[node].x, x86_node_inst_range_info[node]);
    return range.x != INVALID && range.y != INVALID;
}

uint range_count(uint2 range)
{
    return range.y & X86_NODE_INST_RANGE_COUNT_MASK;
}

uint range_kind(uint2 range)
{
    return range.y >> X86_NODE_INST_RANGE_KIND_SHIFT;
}

bool location_for_node_local(uint node, uint local_i, out uint location)
{
    location = INVALID;
    if (!valid_node(node))
        return false;
    if (!upstream_ok())
        return false;

    if (local_i < 4u)
    {
        uint4 locations = x86_node_inst_location_record[node];
        if (local_i == 0u) location = locations.x;
        else if (local_i == 1u) location = locations.y;
        else if (local_i == 2u) location = locations.z;
        else location = locations.w;
        if (virtual_row_in_stream(location))
            return true;
    }

    uint2 range = uint2(INVALID, 0u);
    if (!range_for_node(node, range) ||
        local_i >= range_count(range))
        return false;

    uint range_row = range.x + local_i;
    if (range_row < range.x ||
        !virtual_row_in_stream(range_row))
        return false;

    location = range_row;
    return true;
}

bool has_location_for_node_local(uint node, uint local_i)
{
    uint location = INVALID;
    return location_for_node_local(node, local_i, location);
}

bool subtree_instruction_bounds(uint root, out uint first_row, out uint after_row)
{
    first_row = INVALID;
    after_row = INVALID;
    if (!valid_node(root))
        return false;

    uint start = x86_node_inst_subtree_bound_start[root];
    uint end = x86_node_inst_subtree_bound_end[root];
    if (start == INVALID ||
        end == INVALID ||
        start >= end ||
        end > x86_virtual_inst_status[3u])
        return false;

    first_row = start;
    after_row = end;
    return true;
}

bool virtual_row_belongs_to_node_subtree(uint node, uint row)
{
    uint first_row = INVALID;
    uint after_row = INVALID;
    return subtree_instruction_bounds(node, first_row, after_row) &&
           row >= first_row &&
           row < after_row;
}

bool virtual_row_can_be_written_by_node(uint node, uint local_i, uint row)
{
    if (virtual_row_belongs_to_node_subtree(node, row))
        return true;

    // Binary expression rows may be relocated within their same-end bucket by
    // x86_node_inst_locations to preserve value-production order.
    if (local_i == 0u && valid_node(node) && hir_kind[node] == HIR_BINARY_EXPR)
        return virtual_row_in_stream(row) && x86_node_inst_location_record[node].x == row;

    return false;
}

bool first_instruction_row_in_subtree(uint root, out uint row)
{
    row = INVALID;
    uint after_row = INVALID;
    return subtree_instruction_bounds(root, row, after_row);
}

bool row_after_subtree(uint root, out uint row)
{
    row = INVALID;
    uint first_row = INVALID;
    return subtree_instruction_bounds(root, first_row, row);
}

bool enclosing_while_for_node(uint node, out uint loop_node)
{
    loop_node = valid_node(node) ? x86_enclosing_loop_node[node] : INVALID;
    return valid_node(loop_node);
}

uint array_literal_node_for_expr(uint expr_node)
{
    uint node = expr_result_root(expr_node);
    if (valid_node(node) && hir_kind[node] == HIR_ARRAY_EXPR)
        return node;
    return INVALID;
}

uint struct_literal_record_node_for_expr(uint expr_node)
{
    if (valid_node(expr_node) && struct_access_kind(expr_node) == X86_STRUCT_ACCESS_LITERAL)
        return expr_node;
    uint resolved = resolve_expr(expr_node);
    if (valid_node(resolved) && struct_access_kind(resolved) == X86_STRUCT_ACCESS_LITERAL)
        return resolved;
    uint root = expr_result_root(expr_node);
    if (valid_node(root) && struct_access_kind(root) == X86_STRUCT_ACCESS_LITERAL)
        return root;
    uint parent = valid_node(expr_node) ? x86_tree_parent[expr_node] : INVALID;
    if (valid_node(parent) && struct_access_kind(parent) == X86_STRUCT_ACCESS_LITERAL)
        return parent;
    parent = valid_node(resolved) ? x86_tree_parent[resolved] : INVALID;
    if (valid_node(parent) && struct_access_kind(parent) == X86_STRUCT_ACCESS_LITERAL)
        return parent;
    parent = valid_node(root) ? x86_tree_parent[root] : INVALID;
    return valid_node(parent) && struct_access_kind(parent) == X86_STRUCT_ACCESS_LITERAL
        ? parent
        : INVALID;
}

uint name_token_for_expr(uint root)
{
    uint node = resolve_expr(root);
    return valid_node(node) && hir_kind[node] == HIR_NAME_EXPR ? expr_value_token(node) : INVALID;
}

uint base_node_for_index(uint index_node)
{
    return expr_slot(index_node, EXPR_RECORD_LEFT);
}

bool is_struct_literal_head_node(uint node)
{
    if (!valid_node(node))
        return false;
    if (struct_access_kind(node) == X86_STRUCT_ACCESS_LITERAL)
        return true;
    uint resolved = resolve_expr(node);
    return valid_node(resolved) && struct_access_kind(resolved) == X86_STRUCT_ACCESS_LITERAL;
}

bool is_struct_literal_head_or_path_child(uint node)
{
    if (is_struct_literal_head_node(node))
        return true;
    uint token = expr_value_token(node);
    if (valid_token(token) && x86_struct_type_record[token] != 0u)
        return true;
    return false;
}

bool decl_array_len(uint decl_token, out uint len)
{
    len = 0u;
    if (!valid_token(decl_token))
        return false;
    len = decl_layout_width(decl_token);
    return decl_layout_base(decl_token) != INVALID &&
           decl_layout_kind(decl_token) == X86_DECL_AGG_ARRAY &&
           len != 0u;
}

bool decl_aggregate_width(uint decl_token, out uint width)
{
    width = 0u;
    if (valid_token(decl_token))
    {
        uint width_candidate = decl_layout_width(decl_token);
        if (decl_layout_base(decl_token) != INVALID &&
            decl_layout_kind(decl_token) != 0u &&
            width_candidate > 1u)
        {
            width = width_candidate;
            return true;
        }
        uint4 param = param_reg_record(decl_token);
        if (param.x != INVALID && param.w > 1u)
        {
            width = param.w;
            return true;
        }
    }
    return false;
}

bool decl_storage_aggregate_width(uint decl_token, out uint width)
{
    width = 0u;
    if (!valid_token(decl_token))
        return false;

    uint width_candidate = decl_layout_width(decl_token);
    if (decl_layout_base(decl_token) != INVALID &&
        decl_layout_kind(decl_token) != 0u &&
        width_candidate > 0u)
    {
        width = width_candidate;
        return true;
    }

    uint4 param = param_reg_record(decl_token);
    if (param.x != INVALID &&
        param_reg_aggregate_kind(decl_token) != 0u &&
        param.w > 0u)
    {
        width = param.w;
        return true;
    }
    return false;
}

uint local_width_for_decl(uint decl_token)
{
    if (!valid_token(decl_token))
        return 1u;
    uint width = decl_layout_width(decl_token);
    return decl_layout_base(decl_token) != INVALID && width != 0u ? width : 1u;
}

bool array_element_store_for_value_node(uint node, out uint decl_token, out uint ordinal)
{
    decl_token = INVALID;
    ordinal = INVALID;

    if (!has_aggregate_feature() || !valid_node(node))
        return false;

    uint4 record = x86_struct_store_record[node];
    if (record.x == INVALID || record.y == INVALID)
    {
        uint value_node = resolve_expr(node);
        if (!valid_node(value_node))
            return false;
        record = x86_struct_store_record[value_node];
    }
    decl_token = record.x;
    ordinal = record.y;
    uint len = 0u;
    if (!decl_array_len(decl_token, len))
        return false;

    return record.w == X86_AGG_STORE_ARRAY &&
           valid_node(record.z) &&
           ordinal != INVALID &&
           ordinal < len;
}

bool struct_field_store_for_value_node(uint node, out uint decl_token, out uint ordinal)
{
    decl_token = INVALID;
    ordinal = INVALID;

    if (!has_aggregate_feature() || !valid_node(node))
        return false;

    uint4 record = x86_struct_store_record[node];
    if (record.x == INVALID || record.y == INVALID)
    {
        uint value_node = resolve_expr(node);
        if (!valid_node(value_node))
            return false;
        record = x86_struct_store_record[value_node];
    }
    if (record.w != 0u)
        return false;

    decl_token = record.x;
    ordinal = record.y;
    uint width = 0u;
    return valid_token(decl_token) &&
           ordinal != INVALID &&
           decl_storage_aggregate_width(decl_token, width) &&
           ordinal < width;
}

bool resolved_decl_token_for_name_node(uint name_node, out uint decl_token)
{
    decl_token = INVALID;
    if (!valid_node(name_node) || expr_form(name_node) != HIR_EXPR_NAME)
        return false;

    uint path_i = path_id_by_owner_hir[name_node];
    if (path_i < active_path_count() &&
        resolved_value_status[path_i] == PATH_RESOLVE_STATUS_OK)
    {
        uint decl_i = resolved_value_decl[path_i];
        if (decl_i < active_hir_node_count())
        {
            uint resolved_token = decl_name_token[decl_i];
            if (valid_token(resolved_token))
            {
                decl_token = resolved_token;
                return true;
            }
        }
    }

    uint name_token = expr_value_token(name_node);
    if (!valid_token(name_token))
        return false;
    decl_token = visible_decl[name_token];
    return valid_token(decl_token);
}

bool decl_token_for_name_expr(uint node, out uint decl_token)
{
    decl_token = INVALID;
    uint resolved = resolve_expr(node);
    if (valid_node(resolved) &&
        expr_form(resolved) == HIR_EXPR_NAME &&
        resolved_decl_token_for_name_node(resolved, decl_token))
        return true;
    return valid_node(node) &&
           expr_form(node) == HIR_EXPR_NAME &&
           resolved_decl_token_for_name_node(node, decl_token);
}

bool name_expr_aggregate_width(uint node, out uint width)
{
    width = 0u;
    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(node, decl_token))
        return false;
    return decl_aggregate_width(decl_token, width);
}

bool array_literal_width(uint expr_node, out uint width)
{
    width = 0u;
    uint array_node = array_literal_node_for_expr(expr_node);
    if (!valid_node(array_node))
        return false;

    if (struct_access_kind(array_node) != X86_STRUCT_ACCESS_ARRAY_LITERAL)
        return false;
    width = struct_access_payload0(array_node);
    return width > 1u;
}

bool struct_literal_width(uint expr_node, out uint width)
{
    width = 0u;
    uint record_node = struct_literal_record_node_for_expr(expr_node);
    if (!valid_node(record_node))
        return false;
    width = struct_access_payload0(record_node);
    return width > 1u;
}

bool struct_literal_storage_width(uint expr_node, out uint width)
{
    width = 0u;
    uint record_node = struct_literal_record_node_for_expr(expr_node);
    if (!valid_node(record_node))
        return false;
    width = struct_access_payload0(record_node);
    return width > 0u;
}

uint enum_value_kind(uint2 record)
{
    return record.x & X86_ENUM_VALUE_KIND_MASK;
}

uint enum_value_payload_count(uint2 record)
{
    return record.x >> X86_ENUM_VALUE_KIND_BITS;
}

uint enum_value_ordinal(uint2 record)
{
    return record.y;
}

bool enum_value_record_is_supported(uint2 record)
{
    if (record.x == INVALID || record.y == INVALID)
        return false;

    uint kind = enum_value_kind(record);
    uint payload_count = enum_value_payload_count(record);
    return (kind == X86_ENUM_VALUE_UNIT_CTOR && payload_count == 0u) ||
           (kind == X86_ENUM_VALUE_CALL_CTOR && payload_count == 1u);
}

bool has_enum_value_record(uint node)
{
    if (!has_enum_feature() || !valid_node(node))
        return false;
    return enum_value_record_is_supported(x86_enum_value_record[node]);
}

bool enum_value_node_for_expr(uint expr_node, out uint value_node, out uint width)
{
    value_node = INVALID;
    width = 0u;
    if (!valid_node(expr_node))
        return false;

    uint resolved = resolve_expr(expr_node);
    if (has_enum_value_record(resolved))
    {
        value_node = resolved;
        width = 2u;
        return true;
    }
    if (has_enum_value_record(expr_node))
    {
        value_node = expr_node;
        width = 2u;
        return true;
    }

    return false;
}

bool aggregate_return_width(uint return_node, out uint width)
{
    width = 0u;
    uint expr_node = stmt_slot(return_node, 1u);
    if (!valid_node(expr_node))
        return false;
    uint enum_node = INVALID;
    if (enum_value_node_for_expr(expr_node, enum_node, width))
        return true;
    if (struct_literal_width(expr_node, width))
        return true;
    if (array_literal_width(expr_node, width))
        return true;
    return name_expr_aggregate_width(expr_node, width);
}

bool validate_array_literal_to_ret_ptr(uint expr_node, uint width)
{
    if (width == 0u || width > 32u)
        return false;

    uint array_node = array_literal_node_for_expr(expr_node);
    if (!valid_node(array_node))
        return false;

    if (struct_access_kind(array_node) != X86_STRUCT_ACCESS_ARRAY_LITERAL ||
        struct_access_payload0(array_node) != width)
        return false;

    return true;
}

void write_mixed_arg_payloads(
    uint payload_row,
    uint payload_row_hi,
    uint call_row,
    uint node,
    uint arg_count,
    uint arg0,
    uint arg1,
    uint arg2,
    uint arg3,
    uint arg4,
    uint arg5)
{
    x86_virtual_inst_record[payload_row] = uint4(node, 1u, 0u, payload_row_hi);
    x86_virtual_inst_args[payload_row] = uint4(
        arg_count >= 1u ? arg0 : INVALID,
        arg_count >= 2u ? arg1 : INVALID,
        arg_count >= 3u ? arg2 : INVALID,
        call_row);
    if (payload_row_hi != INVALID)
    {
        x86_virtual_inst_record[payload_row_hi] = uint4(node, 2u, 0u, INVALID);
        x86_virtual_inst_args[payload_row_hi] = uint4(
            arg_count >= 4u ? arg3 : INVALID,
            arg_count >= 5u ? arg4 : INVALID,
            arg_count >= 6u ? arg5 : INVALID,
            call_row);
    }
}

bool value_vreg_for_candidate(uint node, out uint vreg)
{
    vreg = INVALID;
    uint2 range = uint2(INVALID, 0u);
    if (!range_for_node(node, range) || range_count(range) == 0u)
        return false;
    return location_for_node_local(node, 0u, vreg);
}

bool value_vreg_for_node(uint node, out uint vreg)
{
    uint resolved = resolve_expr(node);
    if (value_vreg_for_candidate(resolved, vreg))
        return true;

    uint root = expr_result_root(node);
    if (root != resolved && value_vreg_for_candidate(root, vreg))
        return true;

    if (valid_node(node) &&
        hir_kind[node] == HIR_PATH_EXPR &&
        node != resolved &&
        node != root &&
        value_vreg_for_candidate(node, vreg))
        return true;

    vreg = INVALID;
    return false;
}

bool result_vreg_for_node(uint node, out uint vreg)
{
    uint root = expr_result_root(node);
    if (value_vreg_for_candidate(root, vreg))
        return true;
    return value_vreg_for_node(node, vreg);
}

bool index_operand_expr_node(uint index_node, out uint operand_node)
{
    operand_node = INVALID;
    if (!is_index_expr_node(index_node))
        return false;

    operand_node = expr_right(index_node);
    return valid_node(operand_node);
}

bool literal_value(uint node, out uint value)
{
    value = 0u;
    node = expr_result_root(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    if (form == HIR_EXPR_INT)
    {
        value = hir_expr_int_value[node];
        return true;
    }
    if (form == HIR_EXPR_FLOAT)
    {
        value = hir_expr_float_bits[node];
        return true;
    }
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
    {
        value = form == HIR_EXPR_TRUE ? 1u : 0u;
        return true;
    }
    return false;
}

bool literal_scalar_value(uint node, out uint value)
{
    value = 0u;
    if (literal_value(node, value))
        return true;

    node = resolve_expr(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    if (form != HIR_EXPR_NEG && form != HIR_EXPR_NOT)
        return false;

    uint inner = 0u;
    uint inner_node = expr_left(node);
    if (!literal_value(inner_node, inner))
        return false;

    if (form == HIR_EXPR_NEG)
    {
        uint inner_root = expr_result_root(inner_node);
        bool inner_is_float = expr_form(inner_root) == HIR_EXPR_FLOAT;
        value = inner_is_float ? (inner ^ 0x80000000u) : (0u - inner);
    }
    else
        value = inner == 0u ? 1u : 0u;
    return true;
}

bool const_literal_value_for_token(uint token, out uint value)
{
    value = 0u;
    if (!valid_token(token))
        return false;
    uint decl_token = visible_decl[token];
    if (!valid_token(decl_token))
        return false;

    uint2 const_record = x86_const_value_record[decl_token];
    if (const_record.x == X86_CONST_VALUE_LITERAL)
    {
        value = const_record.y;
        return true;
    }

    if (local_literal_let_node(decl_token) != INVALID)
    {
        value = local_literal_value(decl_token);
        return true;
    }
    return false;
}

bool const_literal_value_for_name(uint name_node, out uint value)
{
    value = 0u;
    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(name_node, decl_token))
        return false;

    uint2 const_record = x86_const_value_record[decl_token];
    if (const_record.x == X86_CONST_VALUE_LITERAL)
    {
        value = const_record.y;
        return true;
    }

    if (local_literal_let_node(decl_token) != INVALID)
    {
        value = local_literal_value(decl_token);
        return true;
    }
    return false;
}

bool decl_literal_value(uint name_node, out uint value)
{
    value = 0u;
    uint resolved = resolve_expr(name_node);
    uint query = valid_node(resolved) && expr_form(resolved) == HIR_EXPR_NAME
                     ? resolved
                     : name_node;
    if (!valid_node(query) || expr_form(query) != HIR_EXPR_NAME)
        return false;

    if (const_literal_value_for_name(query, value))
        return true;

    uint name_token = expr_value_token(query);
    uint head_token = hir_token_pos[query];
    return head_token != name_token && const_literal_value_for_token(head_token, value);
}

bool const_decl_value_for_token(uint token, out uint value)
{
    value = 0u;
    if (!valid_token(token))
        return false;
    uint decl_token = visible_decl[token];
    if (!valid_token(decl_token))
        return false;
    uint2 const_record = x86_const_value_record[decl_token];
    if (const_record.x != X86_CONST_VALUE_LITERAL)
        return false;

    value = const_record.y;
    return true;
}

bool decl_const_literal_value(uint name_node, out uint value)
{
    value = 0u;
    name_node = resolve_expr(name_node);
    if (!valid_node(name_node) || expr_form(name_node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_value_token(name_node);
    if (const_decl_value_for_token(name_token, value))
        return true;

    uint head_token = hir_token_pos[name_node];
    return head_token != name_token && const_decl_value_for_token(head_token, value);
}

bool source_head_const_literal_value(uint node, out uint value)
{
    value = 0u;
    if (!valid_node(node))
        return false;
    return const_decl_value_for_token(hir_token_pos[node], value);
}

bool path_literal_value_candidate(uint path_node, out uint value)
{
    value = 0u;
    if (!valid_node(path_node))
        return false;

    uint path_i = path_id_by_owner_hir[path_node];
    if (path_i >= active_path_count() ||
        resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return false;

    uint decl_i = resolved_value_decl[path_i];
    if (decl_i >= gParams.n_hir_nodes)
        return false;

    uint decl_token = decl_name_token[decl_i];
    if (!valid_token(decl_token))
        return false;

    uint2 const_record = x86_const_value_record[decl_token];
    if (const_record.x != X86_CONST_VALUE_LITERAL)
        return false;

    value = const_record.y;
    return true;
}

bool path_literal_value(uint path_node, out uint value)
{
    if (path_literal_value_candidate(path_node, value))
        return true;

    uint resolved = resolve_expr(path_node);
    if (resolved != path_node && path_literal_value_candidate(resolved, value))
        return true;

    uint root = expr_result_root(path_node);
    return root != path_node && root != resolved && path_literal_value_candidate(root, value);
}

bool compile_time_scalar_immutable_atom_value(uint node, out uint value)
{
    value = 0u;
    if (literal_value(node, value))
        return true;
    if (source_head_const_literal_value(node, value))
        return true;
    if (path_literal_value(node, value))
        return true;
    return decl_const_literal_value(node, value);
}

bool compile_time_scalar_immutable_binary_value(uint node, out uint value)
{
    value = 0u;
    node = resolve_expr(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    uint left_node = expr_left(node);
    uint right_node = expr_right(node);
    if (expr_semantic_type_metadata_for_node(node) == TY_FLOAT ||
        expr_semantic_type_metadata_for_value_node(left_node) == TY_FLOAT ||
        expr_semantic_type_metadata_for_value_node(right_node) == TY_FLOAT ||
        expr_form(resolve_expr(left_node)) == HIR_EXPR_FLOAT ||
        expr_form(resolve_expr(right_node)) == HIR_EXPR_FLOAT)
        return false;
    if (form != HIR_EXPR_EQ &&
        form != HIR_EXPR_NE &&
        form != HIR_EXPR_ADD &&
        form != HIR_EXPR_SUB &&
        form != HIR_EXPR_MUL &&
        form != HIR_EXPR_MOD &&
        form != HIR_EXPR_DIV &&
        form != HIR_EXPR_AND &&
        form != HIR_EXPR_OR &&
        form != HIR_EXPR_BIT_OR &&
        form != HIR_EXPR_BIT_XOR &&
        form != HIR_EXPR_BIT_AND &&
        form != HIR_EXPR_SHL &&
        form != HIR_EXPR_SHR)
        return false;

    uint left = 0u;
    uint right = 0u;
    if (!compile_time_scalar_immutable_atom_value(left_node, left) ||
        !compile_time_scalar_immutable_atom_value(right_node, right))
        return false;

    if (form == HIR_EXPR_EQ)
        value = left == right ? 1u : 0u;
    else if (form == HIR_EXPR_NE)
        value = left != right ? 1u : 0u;
    else if (form == HIR_EXPR_ADD)
        value = left + right;
    else if (form == HIR_EXPR_SUB)
        value = left - right;
    else if (form == HIR_EXPR_MUL)
        value = left * right;
    else if (form == HIR_EXPR_MOD && right != 0u && left < I32_MIN && right < I32_MIN)
        value = left % right;
    else if (form == HIR_EXPR_DIV && right != 0u && left < I32_MIN && right < I32_MIN)
        value = left / right;
    else if (form == HIR_EXPR_AND)
        value = (left != 0u && right != 0u) ? 1u : 0u;
    else if (form == HIR_EXPR_OR)
        value = (left != 0u || right != 0u) ? 1u : 0u;
    else if (form == HIR_EXPR_BIT_OR)
        value = left | right;
    else if (form == HIR_EXPR_BIT_XOR)
        value = left ^ right;
    else if (form == HIR_EXPR_BIT_AND)
        value = left & right;
    else if (form == HIR_EXPR_SHL && right < 32u)
        value = left << right;
    else if (form == HIR_EXPR_SHR && right < 32u)
        value = left >> right;
    else
        return false;
    return true;
}

bool compile_time_scalar_immutable_value(uint node, out uint value)
{
    if (compile_time_scalar_immutable_atom_value(node, value))
        return true;
    return compile_time_scalar_immutable_binary_value(node, value);
}

bool compile_time_zero_value(uint node)
{
    uint value = 0u;
    return compile_time_scalar_immutable_value(node, value) && value == 0u;
}

bool compile_time_signed_div_overflow(uint left_node, uint right_node)
{
    uint left = 0u;
    uint right = 0u;
    return compile_time_scalar_immutable_value(left_node, left) &&
           compile_time_scalar_immutable_value(right_node, right) &&
           left == I32_MIN &&
           right == I32_NEG_ONE;
}

bool statically_safe_divisor(uint node, out uint value)
{
    value = 0u;
    if (compile_time_scalar_immutable_value(node, value))
        return value != 0u && value != I32_NEG_ONE;
    return false;
}

bool compile_time_index_out_of_bounds(uint index_expr, uint width)
{
    uint value = 0u;
    return compile_time_scalar_immutable_value(index_expr, value) && value >= width;
}

bool param_record_for_name(uint name_node, out uint4 record)
{
    record = uint4_fill(INVALID);
    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(name_node, decl_token))
        return false;

    record = param_reg_record(decl_token);
    return record.x != INVALID && record.z != INVALID;
}

uint name_failure_detail(uint node)
{
    uint resolved = resolve_expr(node);
    uint query = valid_node(resolved) && expr_form(resolved) == HIR_EXPR_NAME
                     ? resolved
                     : node;
    if (!valid_node(query) || expr_form(query) != HIR_EXPR_NAME)
        return X86_VINST_ERROR_NAME_NODE;
    uint name_token = expr_value_token(query);
    if (!valid_token(name_token))
        return X86_VINST_ERROR_NAME_TOKEN;
    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(query, decl_token))
        return X86_VINST_ERROR_NAME_DECL;
    return X86_VINST_ERROR_NAME_VALUE;
}

bool local_decl_vreg_for_name(uint name_node, out uint vreg)
{
    vreg = INVALID;
    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(name_node, decl_token))
        return false;

    uint decl_node = decl_layout_node(decl_token);
    return decl_layout_base(decl_token) != INVALID &&
           valid_node(decl_node) &&
           location_for_node_local(decl_node, 0u, vreg);
}

bool decl_token_for_name(uint name_node, out uint decl_token)
{
    return decl_token_for_name_expr(name_node, decl_token);
}

bool local_slot_for_decl(uint decl_token, uint owner_fn, out uint slot)
{
    slot = INVALID;
    if (!valid_token(decl_token) || owner_fn == INVALID)
        return false;

    uint base = decl_layout_base(decl_token);
    uint decl_node = decl_layout_node(decl_token);
    if (base != INVALID && valid_node(decl_node) && x86_node_func[decl_node] == owner_fn)
    {
        slot = base;
        return true;
    }
    return false;
}

bool emit_string_literal_to_local(uint node)
{
    uint init_node = resolve_expr(stmt_slot(node, 2u));
    if (!valid_node(init_node) ||
        hir_kind[init_node] != HIR_LITERAL_EXPR ||
        expr_form(init_node) != HIR_EXPR_STRING)
        return false;

    uint slot = INVALID;
    uint decl_token = stmt_slot(node, 1u);
    if (!valid_token(decl_token) ||
        decl_layout_width(decl_token) < 2u ||
        !local_slot_for_decl(decl_token, x86_node_func[node], slot))
    {
        write_status_error_detail(node, stmt_slot(node, 1u));
        return false;
    }

    uint ptr_row = INVALID;
    uint len_row = INVALID;
    if (!location_for_node_local(node, 0u, ptr_row) ||
        !location_for_node_local(node, 1u, len_row))
    {
        write_status_error_detail(node, X86_VINST_ERROR_LET_INIT_VALUE);
        return false;
    }
    write_inst(ptr_row, node, 0u, X86_VINST_STORE_LOCAL_RODATA_PTR, INVALID, uint4(slot, init_node, 0u, 0u));
    write_inst(len_row, node, 1u, X86_VINST_STORE_LOCAL_IMM, INVALID, uint4(slot + 1u, hir_expr_string_len[init_node], 0u, 0u));
    write_node_value(node, X86_NODE_VALUE_NONE, INVALID, 0u, 0u);
    return true;
}

bool local_slot_for_name(uint name_node, uint owner_fn, out uint slot)
{
    slot = INVALID;
    uint decl_token = INVALID;
    if (!decl_token_for_name(name_node, decl_token))
        return false;
    return local_slot_for_decl(decl_token, owner_fn, slot);
}

bool dynamic_param_index_operand(uint index_expr, uint owner_fn)
{
    uint value = 0u;
    if (compile_time_scalar_immutable_atom_value(index_expr, value))
        return false;

    uint name_node = resolve_expr(index_expr);
    uint decl_token = INVALID;
    if (!valid_node(name_node) ||
        expr_form(name_node) != HIR_EXPR_NAME ||
        !decl_token_for_name(name_node, decl_token))
        return false;

    uint4 param = param_reg_record(decl_token);
    return param.x == owner_fn && param.z != INVALID && param.w == 1u;
}

void publish_dynamic_index_error(uint index_expr)
{
    uint detail = valid_node(index_expr) ? resolve_expr(index_expr) : INVALID;
    if (!valid_node(detail))
        detail = index_expr;
    publish_stage_error_min_detail4(
        x86_virtual_inst_status,
        X86_ERR_DYNAMIC_INDEX,
        detail);
}

bool write_unsupported_dynamic_param_index_error(uint index_expr, uint owner_fn)
{
    if (!dynamic_param_index_operand(index_expr, owner_fn))
        return false;

    publish_dynamic_index_error(index_expr);
    return true;
}

bool aggregate_source_for_decl(uint decl_token, uint owner_fn, out uint source_kind, out uint payload, out uint width)
{
    source_kind = 0u;
    payload = INVALID;
    width = 0u;
    if (!valid_token(decl_token))
        return false;

    uint base = decl_layout_base(decl_token);
    uint decl_node = decl_layout_node(decl_token);
    uint kind = decl_layout_kind(decl_token);
    uint local_width = decl_layout_width(decl_token);
    if (base != INVALID && valid_node(decl_node) &&
        x86_node_func[decl_node] == owner_fn && kind != 0u && local_width > 1u)
    {
        source_kind = X86_AGG_SOURCE_LOCAL;
        payload = base;
        width = local_width;
        return true;
    }

    uint4 param = param_reg_record(decl_token);
    if (param.x == owner_fn && param.z != INVALID && param.w > 1u)
    {
        source_kind = X86_AGG_SOURCE_PARAM;
        payload = pack_u16_pair(param.z, 0u);
        width = param.w;
        return true;
    }
    return false;
}

uint aggregate_source_payload_offset(uint source_kind, uint payload, uint offset)
{
    if (source_kind == X86_AGG_SOURCE_PARAM)
        return pack_u16_pair(unpack_u16_pair_low(payload), unpack_u16_pair_high(payload) + offset);
    return payload + offset;
}

uint param_aggregate_payload_base(uint payload)
{
    return unpack_u16_pair_low(payload);
}

uint param_aggregate_payload_ordinal(uint payload)
{
    return unpack_u16_pair_high(payload);
}

bool aggregate_source_for_name(uint name_node, uint owner_fn, out uint source_kind, out uint payload, out uint width)
{
    source_kind = 0u;
    payload = INVALID;
    width = 0u;
    uint decl_token = INVALID;
    if (!decl_token_for_name(name_node, decl_token))
        return false;
    return aggregate_source_for_decl(decl_token, owner_fn, source_kind, payload, width);
}

bool semantic_struct_aggregate_width(uint semantic_ty, out uint width)
{
    width = 0u;
    if (semantic_ty < TY_STRUCT_BASE || semantic_ty >= TY_ENUM_BASE)
        return false;
    uint struct_token = semantic_ty - TY_STRUCT_BASE;
    if (!valid_token(struct_token))
        return false;
    width = x86_struct_type_record[struct_token];
    return width > 1u;
}

bool aggregate_source_for_member_expr(uint member_node, uint owner_fn, out uint source_kind, out uint payload, out uint width)
{
    source_kind = 0u;
    payload = INVALID;
    width = 0u;
    if (!valid_node(member_node) ||
        hir_kind[member_node] != HIR_MEMBER_EXPR ||
        struct_access_kind(member_node) != X86_STRUCT_ACCESS_MEMBER)
        return false;

    uint receiver_node = struct_access_payload0(member_node);
    uint ordinal = struct_access_payload1(member_node);
    uint receiver_width = 0u;
    if (ordinal == INVALID ||
        !member_source_for_expr(receiver_node, owner_fn, source_kind, payload, receiver_width) ||
        ordinal >= receiver_width)
        return false;

    uint member_token = struct_access_payload2(member_node);
    uint field_width = 0u;
    if (!valid_token(member_token))
    {
        field_width = receiver_width - ordinal;
    }
    else if (!semantic_struct_aggregate_width(visible_type[member_token], field_width))
    {
        field_width = 1u;
    }
    if (field_width <= 1u || ordinal + field_width > receiver_width)
        return false;

    payload = aggregate_source_payload_offset(source_kind, payload, ordinal);
    width = field_width;
    return true;
}

bool aggregate_source_for_expr(uint expr_node, uint owner_fn, out uint source_kind, out uint payload, out uint width)
{
    source_kind = 0u;
    payload = INVALID;
    width = 0u;
    if (aggregate_source_for_name(expr_node, owner_fn, source_kind, payload, width))
        return true;
    if (aggregate_source_for_member_expr(expr_node, owner_fn, source_kind, payload, width))
        return true;
    uint resolved = resolve_expr(expr_node);
    if (resolved != expr_node &&
        aggregate_source_for_member_expr(resolved, owner_fn, source_kind, payload, width))
        return true;
    uint root = expr_result_root(expr_node);
    return root != expr_node &&
           root != resolved &&
           aggregate_source_for_member_expr(root, owner_fn, source_kind, payload, width);
}

bool member_source_for_decl(uint decl_token, uint owner_fn, out uint source_kind, out uint payload, out uint width)
{
    source_kind = 0u;
    payload = INVALID;
    width = 0u;
    if (!valid_token(decl_token))
        return false;

    uint base = decl_layout_base(decl_token);
    uint decl_node = decl_layout_node(decl_token);
    uint kind = decl_layout_kind(decl_token);
    uint local_width = decl_layout_width(decl_token);
    if (base != INVALID && valid_node(decl_node) &&
        x86_node_func[decl_node] == owner_fn && kind != 0u && local_width > 0u)
    {
        source_kind = X86_AGG_SOURCE_LOCAL;
        payload = base;
        width = local_width;
        return true;
    }

    uint4 param = param_reg_record(decl_token);
    if (param.x == owner_fn &&
        param.z != INVALID &&
        param_reg_aggregate_kind(decl_token) != 0u &&
        param.w > 0u)
    {
        source_kind = X86_AGG_SOURCE_PARAM;
        payload = pack_u16_pair(param.z, 0u);
        width = param.w;
        return true;
    }
    return false;
}

bool member_source_for_expr(uint expr_node, uint owner_fn, out uint source_kind, out uint payload, out uint width)
{
    source_kind = 0u;
    payload = INVALID;
    width = 0u;
    uint current = expr_node;
    uint offset = 0u;
    uint limit = active_hir_node_count();
    for (uint i = 0u; i < limit; i++)
    {
        if (valid_node(current) &&
            hir_kind[current] == HIR_MEMBER_EXPR &&
            struct_access_kind(current) == X86_STRUCT_ACCESS_MEMBER)
        {
            uint member_offset = struct_access_payload1(current);
            uint receiver = struct_access_payload0(current);
            if (member_offset == INVALID || !valid_node(receiver))
                return false;
            offset += member_offset;
            current = receiver;
            continue;
        }

        uint resolved = resolve_expr(current);
        if (valid_node(resolved) && resolved != current)
        {
            current = resolved;
            continue;
        }

        uint decl_token = INVALID;
        if (decl_token_for_name(current, decl_token))
        {
            if (!member_source_for_decl(decl_token, owner_fn, source_kind, payload, width))
                return false;
            if (offset >= width)
                return false;
            payload = aggregate_source_payload_offset(source_kind, payload, offset);
            width -= offset;
            return true;
        }

        return false;
    }

    return false;
}

uint member_source_failure_detail(uint expr_node, uint owner_fn)
{
    uint name_node = resolve_expr(expr_node);
    if (!valid_node(name_node))
        return X86_VINST_ERROR_MEMBER_SOURCE_BAD_NODE;

    if (expr_form(name_node) != HIR_EXPR_NAME)
        return X86_VINST_ERROR_MEMBER_SOURCE_NOT_NAME;

    uint name_token = expr_value_token(name_node);
    if (!valid_token(name_token))
        return X86_VINST_ERROR_MEMBER_SOURCE_TOKEN;

    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(name_node, decl_token))
        return X86_VINST_ERROR_MEMBER_SOURCE_DECL;

    uint base = decl_layout_base(decl_token);
    if (base != INVALID)
    {
        uint decl_node = decl_layout_node(decl_token);
        if (!valid_node(decl_node) || x86_node_func[decl_node] != owner_fn)
            return X86_VINST_ERROR_MEMBER_SOURCE_LOCAL_OWNER;
        if (decl_layout_kind(decl_token) == 0u || decl_layout_width(decl_token) <= 1u)
            return X86_VINST_ERROR_MEMBER_SOURCE_LOCAL_WIDTH;
    }

    uint4 param = param_reg_record(decl_token);
    if (param.x == INVALID)
        return X86_VINST_ERROR_MEMBER_SOURCE_NO_PARAM;
    if (param.x != owner_fn)
        return X86_VINST_ERROR_MEMBER_SOURCE_PARAM_OWNER;
    if (param.z == INVALID)
        return X86_VINST_ERROR_MEMBER_SOURCE_PARAM_REG;
    if (param.w <= 1u)
        return X86_VINST_ERROR_MEMBER_SOURCE_PARAM_WIDTH;
    return X86_VINST_ERROR_MEMBER_SOURCE;
}

uint nth_match_arm_node(uint match_node, uint ordinal)
{
    if (!has_match_feature() || !valid_node(match_node))
        return INVALID;
    uint4 record = x86_match_record[match_node];
    if (ordinal == 0u)
        return record.y;
    if (ordinal == 1u)
        return record.w;
    return INVALID;
}

bool match_expr_is_return_value(uint match_node, out uint return_node)
{
    return_node = INVALID;
    if (!valid_node(match_node))
        return false;
    return_node = x86_match_return_node[match_node];
    if (!valid_node(return_node) || stmt_slot(return_node, 0u) != STMT_RECORD_KIND_RETURN)
        return false;
    uint return_expr = stmt_slot(return_node, 1u);
    return resolve_expr(return_expr) == match_node;
}

bool supported_return_match(uint match_node)
{
    if (!has_match_feature() || !valid_node(match_node))
        return false;
    uint4 record = x86_match_record[match_node];
    uint return_node = INVALID;
    return hir_kind[match_node] == HIR_MATCH_EXPR &&
           valid_node(record.x) &&
           valid_node(record.y) &&
           record.z == 2u &&
           match_expr_is_return_value(match_node, return_node);
}

uint return_stmt_match_node(uint return_node)
{
    if (!has_match_feature())
        return INVALID;
    if (!valid_node(return_node) || stmt_slot(return_node, 0u) != STMT_RECORD_KIND_RETURN)
        return INVALID;
    uint return_expr = stmt_slot(return_node, 1u);
    uint expr_node = resolve_expr(return_expr);
    return supported_return_match(expr_node) ? expr_node : INVALID;
}

bool return_stmt_has_supported_match(uint return_node)
{
    return valid_node(return_stmt_match_node(return_node));
}

bool pattern_variant_ordinal(uint arm_node, out uint ordinal)
{
    ordinal = INVALID;
    if (!has_match_feature() || !valid_node(arm_node))
        return false;

    uint packed_ordinal = x86_match_record[arm_node].z >> 16u;
    if (packed_ordinal == MATCH_ARM_VARIANT_UNRESOLVED)
    {
        ordinal = MATCH_ARM_VARIANT_UNRESOLVED;
        return false;
    }
    if (packed_ordinal == MATCH_ARM_VARIANT_NO_USE_TOKEN ||
        packed_ordinal == MATCH_ARM_VARIANT_NO_VARIANT)
    {
        ordinal = packed_ordinal;
        return false;
    }
    if (packed_ordinal != MATCH_ARM_VARIANT_UNKNOWN)
    {
        ordinal = packed_ordinal;
        return true;
    }
    ordinal = MATCH_ARM_VARIANT_UNRESOLVED;
    return false;
}

uint match_arm_payload_count(uint4 arm_record)
{
    return unpack_u16_pair_low(arm_record.z);
}

bool match_payload_source_for_name(uint name_node, out uint source_kind, out uint payload, out uint reason)
{
    source_kind = 0u;
    payload = INVALID;
    reason = 0u;
    if (!has_match_feature())
        return false;
    name_node = resolve_expr(name_node);
    if (!valid_node(name_node) || expr_form(name_node) != HIR_EXPR_NAME)
        return false;
    uint name_token = expr_value_token(name_node);
    if (!valid_token(name_token))
        return false;
    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(name_node, decl_token))
        return false;

    uint arm = x86_match_result_value_owner[name_node];
    if (!valid_node(arm))
        return false;
    uint4 arm_record = x86_match_record[arm];
    uint match_node = x86_match_arm_owner[arm];
    if (!supported_return_match(match_node))
        return false;
    uint4 match_record = x86_match_record[match_node];
    if (match_arm_payload_count(arm_record) != 1u)
    {
        reason = X86_VINST_ERROR_NAME_MATCH_PAYLOAD_COUNT;
        return false;
    }
    uint payload_decl = arm_record.y;
    if (!valid_token(payload_decl) || decl_token != payload_decl)
    {
        reason = X86_VINST_ERROR_NAME_MATCH_PAYLOAD_BINDING;
        return false;
    }
    uint width = 0u;
    if (!aggregate_source_for_expr(match_record.x, x86_node_func[name_node], source_kind, payload, width))
    {
        reason = X86_VINST_ERROR_NAME_MATCH_PAYLOAD_SOURCE;
        return false;
    }
    if (width != 2u)
    {
        reason = X86_VINST_ERROR_NAME_MATCH_PAYLOAD_WIDTH;
        return false;
    }
    return true;
}

bool aggregate_source_for_index(uint index_node, out uint source_kind, out uint payload, out uint width)
{
    source_kind = 0u;
    payload = INVALID;
    width = 0u;
    uint base_node = base_node_for_index(index_node);
    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(base_node, decl_token))
        return false;
    if (aggregate_source_for_decl(decl_token, x86_node_func[index_node], source_kind, payload, width))
        return true;

    uint4 param = param_reg_record(decl_token);
    if (param.x == x86_node_func[index_node] && param.z != INVALID && param.w == 0u)
    {
        source_kind = X86_AGG_SOURCE_PARAM;
        payload = pack_u16_pair(param.z, 0u);
        width = 0u;
        return true;
    }

    return false;
}

bool let_initializer_resolves_to(uint let_node, uint value_node)
{
    if (!valid_node(let_node) || !valid_node(value_node))
        return false;
    uint init_node = stmt_slot(let_node, 2u);
    if (init_node == value_node)
        return true;
    uint resolved_init = expr_result_root(init_node);
    uint resolved_value = expr_result_root(value_node);
    if (valid_node(resolved_init) && resolved_init == resolved_value)
        return true;

    uint forwarded_init = resolve_expr(init_node);
    uint forwarded_value = resolve_expr(value_node);
    return valid_node(forwarded_init) && forwarded_init == forwarded_value;
}

bool aggregate_call_destination(uint call_node, uint expected_width, out uint base_slot, out uint reason)
{
    base_slot = INVALID;
    reason = X86_VINST_ERROR_CALL_AGG_DEST;
    uint return_node = valid_node(call_node) ? x86_enclosing_return_node[call_node] : INVALID;
    if (valid_node(return_node) &&
        stmt_slot(return_node, 0u) == STMT_RECORD_KIND_RETURN &&
        resolve_expr(stmt_slot(return_node, 1u)) == resolve_expr(call_node) &&
        expected_width > 1u)
    {
        base_slot = X86_AGG_RETURN_DEST_RET_PTR;
        return true;
    }

    uint let_node = valid_node(call_node) ? x86_enclosing_let_node[call_node] : INVALID;
    if (!valid_node(let_node))
    {
        reason = X86_VINST_ERROR_CALL_AGG_DEST_NO_LET;
        return false;
    }
    if (!let_initializer_resolves_to(let_node, call_node))
    {
        reason = X86_VINST_ERROR_CALL_AGG_DEST_NOT_INIT;
        return false;
    }
    uint decl_token = stmt_slot(let_node, 1u);
    uint dest_width = local_width_for_decl(decl_token);
    if (expected_width <= 1u || dest_width < expected_width)
    {
        reason = X86_VINST_ERROR_CALL_AGG_DEST_WIDTH;
        return false;
    }
    if (!local_slot_for_decl(decl_token, x86_node_func[call_node], base_slot))
    {
        reason = X86_VINST_ERROR_CALL_AGG_DEST_SLOT;
        return false;
    }
    return true;
}

bool aggregate_call_return_expr_width(uint expr_node, uint width)
{
    uint call_node = call_node_for_expr(expr_node);
    if (!valid_node(call_node))
        return false;
    uint call_slot = call_record_slot(call_node);
    if (call_slot == INVALID)
        return false;
    uint2 abi = x86_call_abi_record[call_slot];
    return has_call_abi_record(abi) &&
           call_abi_return_width(abi) == width &&
           width > 1u;
}

uint scalar_type_for_name_value(uint node)
{
    uint decl_token = INVALID;
    if (!decl_token_for_name(node, decl_token))
        return TY_UNKNOWN;

    uint param_ty = param_reg_type(decl_token);
    if (param_ty != INVALID && param_ty != TY_UNKNOWN)
        return param_ty;

    uint layout_ty = decl_layout_type(decl_token);
    if (layout_ty != INVALID && layout_ty != TY_UNKNOWN)
        return layout_ty;

    uint visible_ty = visible_type[decl_token];
    return visible_ty != INVALID ? visible_ty : TY_UNKNOWN;
}

bool call_arg_operand(uint arg_node, uint owner_fn, out uint kind, out uint payload)
{
    kind = 0u;
    payload = INVALID;
    uint source_kind = 0u;
    uint width = 0u;
    if (aggregate_source_for_expr(arg_node, owner_fn, source_kind, payload, width))
    {
        kind = source_kind == X86_AGG_SOURCE_LOCAL ? X86_ARG_LOCAL_PTR : X86_ARG_PARAM_PTR;
        return true;
    }

    uint vreg = INVALID;
    if (!value_vreg_for_node(arg_node, vreg))
        return false;
    kind = X86_ARG_SCALAR;
    payload = vreg;
    return true;
}

uint unary_op_for_form(uint form)
{
    if (form == HIR_EXPR_NEG)
        return X86_OP_NEG_I32;
    if (form == HIR_EXPR_NOT)
        return X86_OP_NOT_BOOL;
    return 0u;
}

bool expr_value_is_float(uint node)
{
    uint resolved = resolve_expr(node);
    uint root = expr_result_root(node);
    uint member_node =
        struct_access_kind(node) == X86_STRUCT_ACCESS_MEMBER
            ? node
            : struct_access_kind(resolved) == X86_STRUCT_ACCESS_MEMBER
                  ? resolved
                  : root;
    uint member_token =
        struct_access_kind(member_node) == X86_STRUCT_ACCESS_MEMBER
            ? struct_access_payload2(member_node)
            : INVALID;
    uint member_ty = valid_token(member_token) ? visible_type[member_token] : TY_UNKNOWN;
    return expr_semantic_type_metadata_for_value_node(node) == TY_FLOAT ||
           member_ty == TY_FLOAT ||
           scalar_type_for_name_value(node) == TY_FLOAT ||
           expr_form(resolved) == HIR_EXPR_FLOAT ||
           expr_form(root) == HIR_EXPR_FLOAT;
}

uint unary_op_for_node(uint node, uint form)
{
    uint op = unary_op_for_form(form);
    uint left = expr_left(node);
    uint left_root = valid_node(left) ? hir_expr_result_root_node[left] : INVALID;
    uint left_root_resolved = valid_node(left_root) ? resolve_expr(left_root) : INVALID;
    if (op == X86_OP_NEG_I32 &&
        (expr_semantic_type_metadata_for_node(node) == TY_FLOAT ||
         (valid_node(left_root) && expr_form(left_root) == HIR_EXPR_FLOAT) ||
         (valid_node(left_root_resolved) && expr_form(left_root_resolved) == HIR_EXPR_FLOAT) ||
         expr_value_is_float(left)))
        return X86_OP_NEG_F32;
    return op;
}

uint binary_op_for_form(uint form)
{
    if (form == HIR_EXPR_ADD)
        return X86_OP_ADD_I32;
    if (form == HIR_EXPR_SUB)
        return X86_OP_SUB_I32;
    if (form == HIR_EXPR_MUL)
        return X86_OP_MUL_I32;
    if (form == HIR_EXPR_AND)
        return X86_OP_AND_BOOL;
    if (form == HIR_EXPR_OR)
        return X86_OP_OR_BOOL;
    if (form == HIR_EXPR_MOD)
        return X86_OP_MOD_I32;
    if (form == HIR_EXPR_DIV)
        return X86_OP_DIV_I32;
    if (form == HIR_EXPR_BIT_AND)
        return X86_OP_BIT_AND_I32;
    if (form == HIR_EXPR_BIT_OR)
        return X86_OP_BIT_OR_I32;
    if (form == HIR_EXPR_BIT_XOR)
        return X86_OP_BIT_XOR;
    if (form == HIR_EXPR_SHL)
        return X86_OP_SHL_I32;
    if (form == HIR_EXPR_SHR)
        return X86_OP_SHR_I32;
    return 0u;
}

uint expr_semantic_type_metadata_for_node(uint node)
{
    uint meta = valid_node(node) ? x86_node_inst_location_record[node].w : INVALID;
    if ((meta & X86_LOCATION_META_KIND_MASK) == X86_LOCATION_META_EXPR_SEMANTIC_TYPE)
        return meta & X86_LOCATION_META_PAYLOAD_MASK;

    uint record = valid_node(node) ? x86_expr_semantic_type[node] : INVALID;
    if ((record & EXPR_SEMANTIC_UINT_FLAG) != 0u)
        return TY_UINT;
    if ((record & EXPR_SEMANTIC_FLOAT_FLAG) != 0u)
        return TY_FLOAT;
    return TY_UNKNOWN;
}

uint expr_semantic_type_metadata_for_value_node(uint node)
{
    uint ty = expr_semantic_type_metadata_for_node(node);
    if (ty != TY_UNKNOWN)
        return ty;

    uint resolved = resolve_expr(node);
    if (resolved == node)
        return TY_UNKNOWN;

    return expr_semantic_type_metadata_for_node(resolved);
}

uint binary_op_for_node(uint node, uint form)
{
    uint op = binary_op_for_form(form);
    if (expr_semantic_type_metadata_for_node(node) == TY_FLOAT ||
        expr_value_is_float(expr_left(node)) ||
        expr_value_is_float(expr_right(node)))
    {
        if (op == X86_OP_ADD_I32)
            return X86_OP_ADD_F32;
        if (op == X86_OP_SUB_I32)
            return X86_OP_SUB_F32;
        if (op == X86_OP_MUL_I32)
            return X86_OP_MUL_F32;
        if (op == X86_OP_DIV_I32)
            return X86_OP_DIV_F32;
    }
    if (expr_semantic_type_metadata_for_node(node) != TY_UINT)
        return op;
    if (op == X86_OP_MOD_I32)
        return X86_OP_MOD_U32;
    if (op == X86_OP_DIV_I32)
        return X86_OP_DIV_U32;
    if (op == X86_OP_SHR_I32)
        return X86_OP_SHR_U32;
    return op;
}

uint binary_op_for_assignment(uint op)
{
    if (op == ASSIGN_OP_ADD)
        return X86_OP_ADD_I32;
    if (op == ASSIGN_OP_SUB)
        return X86_OP_SUB_I32;
    if (op == ASSIGN_OP_MUL)
        return X86_OP_MUL_I32;
    if (op == ASSIGN_OP_DIV)
        return X86_OP_DIV_I32;
    if (op == ASSIGN_OP_MOD)
        return X86_OP_MOD_I32;
    if (op == ASSIGN_OP_XOR)
        return X86_OP_BIT_XOR;
    if (op == ASSIGN_OP_SHL)
        return X86_OP_SHL_I32;
    if (op == ASSIGN_OP_SHR)
        return X86_OP_SHR_I32;
    if (op == ASSIGN_OP_BAND)
        return X86_OP_BIT_AND_I32;
    if (op == ASSIGN_OP_BOR)
        return X86_OP_BIT_OR_I32;
    return 0u;
}

uint scalar_type_for_assignment_target(uint target_node)
{
    uint target_ty = expr_semantic_type_metadata_for_value_node(target_node);
    if (target_ty == TY_UNKNOWN && valid_node(target_node) &&
        struct_access_kind(target_node) == X86_STRUCT_ACCESS_MEMBER)
    {
        uint member_token = struct_access_payload2(target_node);
        if (valid_token(member_token))
        {
            uint member_ty = visible_type[member_token];
            if (member_ty != INVALID && member_ty != TY_UNKNOWN)
                target_ty = member_ty;
        }
    }
    if (target_ty != TY_UNKNOWN)
        return target_ty;

    uint decl_token = INVALID;
    if (!decl_token_for_name(target_node, decl_token))
        return TY_UNKNOWN;
    return decl_layout_type(decl_token);
}

uint f32_binary_op_for_assignment(uint binary_op)
{
    if (binary_op == X86_OP_ADD_I32)
        return X86_OP_ADD_F32;
    if (binary_op == X86_OP_SUB_I32)
        return X86_OP_SUB_F32;
    if (binary_op == X86_OP_MUL_I32)
        return X86_OP_MUL_F32;
    if (binary_op == X86_OP_DIV_I32)
        return X86_OP_DIV_F32;
    return binary_op;
}

uint binary_op_for_assignment_target(uint target_node, uint rhs_node, uint op)
{
    uint binary_op = binary_op_for_assignment(op);
    uint target_ty = scalar_type_for_assignment_target(target_node);
    if (target_ty == TY_FLOAT || expr_value_is_float(rhs_node))
        return f32_binary_op_for_assignment(binary_op);

    if (target_ty == TY_UINT &&
        (binary_op == X86_OP_DIV_I32 ||
         binary_op == X86_OP_MOD_I32 ||
         binary_op == X86_OP_SHR_I32))
    {
        return binary_op == X86_OP_DIV_I32 ? X86_OP_DIV_U32
             : binary_op == X86_OP_MOD_I32 ? X86_OP_MOD_U32
             : X86_OP_SHR_U32;
    }

    return binary_op;
}

uint compare_op_for_form(uint form)
{
    if (form == HIR_EXPR_LT)
        return X86_CMP_LT;
    if (form == HIR_EXPR_GT)
        return X86_CMP_GT;
    if (form == HIR_EXPR_LE)
        return X86_CMP_LE;
    if (form == HIR_EXPR_GE)
        return X86_CMP_GE;
    if (form == HIR_EXPR_EQ)
        return X86_CMP_EQ;
    if (form == HIR_EXPR_NE)
        return X86_CMP_NE;
    return 0u;
}

uint compare_op_for_node(uint node, uint form)
{
    uint op = compare_op_for_form(form);
    if (expr_semantic_type_metadata_for_node(node) == TY_FLOAT ||
        expr_value_is_float(expr_left(node)) ||
        expr_value_is_float(expr_right(node)))
        return op == 0u ? 0u : (op | X86_CMP_FLOAT_FLAG);
    if (op == 0u || op == X86_CMP_EQ || op == X86_CMP_NE)
        return op;
    return expr_semantic_type_metadata_for_node(node) == TY_UINT
               ? (op | X86_CMP_UNSIGNED_FLAG)
               : op;
}

void write_status_error_detail(uint node, uint detail)
{
    publish_stage_error_first4(
        x86_virtual_inst_status,
        X86_ERR_NODE_VIRTUAL_INST,
        node,
        detail);
}

void write_status_error(uint node)
{
    write_status_error_detail(node, valid_node(node) ? hir_kind[node] : INVALID);
}

void write_param_aggregate_assignment_error(uint node)
{
    publish_stage_error_min_detail4(
        x86_virtual_inst_status,
        X86_ERR_PARAM_AGG_ASSIGN,
        node);
}

void write_param_aggregate_index_assignment_error(uint node)
{
    publish_stage_error_min_detail4(
        x86_virtual_inst_status,
        X86_ERR_PARAM_AGG_INDEX_ASSIGN,
        node);
}

void write_aggregate_return_call_error(uint node, uint detail)
{
    publish_stage_error_first4(
        x86_virtual_inst_status,
        X86_ERR_AGGREGATE_RETURN_CALL,
        node,
        detail);
}

bool is_member_expr_node(uint node)
{
    return valid_node(node) && hir_kind[node] == HIR_MEMBER_EXPR;
}

bool nested_aggregate_member_receiver(uint node, out uint receiver)
{
    receiver = INVALID;
    if (!valid_node(node) ||
        hir_kind[node] != HIR_MEMBER_EXPR ||
        struct_access_kind(node) != X86_STRUCT_ACCESS_MEMBER)
        return false;

    receiver = struct_access_payload0(node);
    uint resolved_receiver = valid_node(receiver) ? resolve_expr(receiver) : INVALID;
    return is_member_expr_node(receiver) || is_member_expr_node(resolved_receiver);
}

void write_nested_aggregate_member_error(uint node)
{
    uint receiver = INVALID;
    if (!nested_aggregate_member_receiver(node, receiver))
        receiver = node;
    publish_stage_error_min_detail4(
        x86_virtual_inst_status,
        X86_ERR_NESTED_AGGREGATE_MEMBER,
        receiver);
}

void write_loop_control_outside_loop_error(uint node)
{
    publish_stage_error_min_detail4(
        x86_virtual_inst_status,
        X86_ERR_LOOP_CONTROL_OUTSIDE_LOOP,
        node);
}

bool logical_form_short_circuits(uint form)
{
    return form == HIR_EXPR_AND || form == HIR_EXPR_OR;
}

uint call_node_for_expr(uint value_node)
{
    uint resolved = resolve_expr(value_node);
    if (valid_node(resolved) && hir_kind[resolved] == HIR_CALL_EXPR)
        return resolved;
    return valid_node(value_node) && hir_kind[value_node] == HIR_CALL_EXPR
               ? value_node
               : INVALID;
}

bool write_short_circuit_call_error(uint value_node)
{
    uint call_node = call_node_for_expr(value_node);
    if (!valid_node(call_node))
        return false;

    if (call_record_slot(call_node) == INVALID && intrinsic_call_tag(call_node) == 0u)
        return false;

    publish_stage_error_min_detail4(
        x86_virtual_inst_status,
        X86_ERR_SHORT_CIRCUIT_CALL,
        call_node);
    return true;
}

bool call_is_nested_in_short_circuit_rhs(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    return valid_node(x86_short_circuit_rhs_node[call_node]);
}

bool write_nested_short_circuit_call_error(uint call_node)
{
    if (!call_is_nested_in_short_circuit_rhs(call_node))
        return false;

    if (call_record_slot(call_node) == INVALID && intrinsic_call_tag(call_node) == 0u)
        return false;

    publish_stage_error_min_detail4(
        x86_virtual_inst_status,
        X86_ERR_SHORT_CIRCUIT_CALL,
        call_node);
    return true;
}

bool node_is_nested_in_short_circuit_rhs(uint node)
{
    if (!valid_node(node))
        return false;
    return valid_node(x86_short_circuit_rhs_node[node]);
}

bool write_short_circuit_trap_error(uint node, uint detail_node)
{
    if (!node_is_nested_in_short_circuit_rhs(node))
        return false;

    uint diagnostic_node = resolve_expr(detail_node);
    publish_stage_error_min_detail4(
        x86_virtual_inst_status,
        X86_ERR_SHORT_CIRCUIT_TRAP,
        valid_node(diagnostic_node) ? diagnostic_node : detail_node);
    return true;
}

bool write_unsupported_short_circuit_arithmetic_error(uint node, uint binary_op)
{
    bool signed_divisor_op = binary_op == X86_OP_DIV_I32 || binary_op == X86_OP_MOD_I32;
    bool unsigned_divisor_op = binary_op == X86_OP_DIV_U32 || binary_op == X86_OP_MOD_U32;
    bool divisor_op = signed_divisor_op || unsigned_divisor_op;
    bool shift_op = binary_op == X86_OP_SHL_I32 ||
                    binary_op == X86_OP_SHR_I32 ||
                    binary_op == X86_OP_SHR_U32;
    if (!divisor_op && !shift_op)
        return false;

    uint rhs = expr_right(node);
    uint value = 0u;
    bool safe = divisor_op
        ? (unsigned_divisor_op
               ? (compile_time_scalar_immutable_value(rhs, value) && value != 0u)
               : statically_safe_divisor(rhs, value))
        : (compile_time_scalar_immutable_value(rhs, value) && value < 32u);
    if (safe)
        return false;

    return write_short_circuit_trap_error(node, rhs);
}

bool compile_time_index_in_bounds(uint index_expr, uint width)
{
    uint value = 0u;
    return width != 0u && compile_time_scalar_immutable_value(index_expr, value) && value < width;
}

bool write_unsupported_short_circuit_index_error(uint node, uint index_expr, uint width)
{
    if (!node_is_nested_in_short_circuit_rhs(node))
        return false;

    if (compile_time_index_in_bounds(index_expr, width))
        return false;

    return write_short_circuit_trap_error(node, index_expr);
}

bool write_loop_call_value_error(uint value_node)
{
    uint call_node = call_node_for_expr(value_node);
    if (!valid_node(call_node) ||
        !valid_node(x86_enclosing_loop_node[call_node]))
        return false;

    if (call_record_slot(call_node) == INVALID && intrinsic_call_tag(call_node) == 0u)
        return false;

    publish_stage_error_min_detail4(
        x86_virtual_inst_status,
        X86_ERR_LOOP_CONTAINED_CALL,
        call_node);
    return true;
}

bool write_zero_divisor_error(uint value_node)
{
    if (!compile_time_zero_value(value_node))
        return false;

    uint diagnostic_node = resolve_expr(value_node);
    publish_stage_error_min_detail4(
        x86_virtual_inst_status,
        X86_ERR_ZERO_DIVISOR,
        valid_node(diagnostic_node) ? diagnostic_node : value_node);
    return true;
}

bool write_compile_time_zero_divisor_error(uint value_node)
{
    return write_zero_divisor_error(value_node);
}

bool write_compile_time_signed_div_overflow_error(uint node)
{
    if (!compile_time_signed_div_overflow(expr_left(node), expr_right(node)))
        return false;

    uint diagnostic_node = resolve_expr(node);
    publish_stage_error_min_detail4(
        x86_virtual_inst_status,
        X86_ERR_SIGNED_DIV_OVERFLOW,
        valid_node(diagnostic_node) ? diagnostic_node : node);
    return true;
}

void write_node_value(uint node, uint kind, uint value, uint aux0, uint aux1)
{
}

void write_inst(uint row, uint node, uint local_i, uint op, uint dst, uint4 args)
{
    if (row >= gParams.inst_capacity)
    {
        write_status_error_detail(node, row);
        return;
    }
    if (!virtual_row_can_be_written_by_node(node, local_i, row))
    {
        write_status_error_detail(node, X86_VINST_ERROR_ROW_OUTSIDE_SUBTREE);
        return;
    }
    x86_virtual_inst_record[row] = uint4(node, local_i, op, dst);
    x86_virtual_inst_args[row] = args;
}

bool emit_padding_range(uint node, uint2 range)
{
    // Padding rows are reserved for ancestor control-flow instructions.
    // The host clears the virtual instruction buffers before this pass, so
    // unclaimed padding remains X86_VINST_NONE without racing parent writers.
    return true;
}

bool emit_array_element_store(uint node, uint src, uint local_i)
{
    uint decl_token = INVALID;
    uint ordinal = INVALID;
    if (!array_element_store_for_value_node(node, decl_token, ordinal))
        return true;

    uint base_slot = INVALID;
    uint row = INVALID;
    if (!local_slot_for_decl(decl_token, x86_node_func[node], base_slot) ||
        !location_for_node_local(node, local_i, row))
        return false;

    write_inst(row, node, local_i, X86_VINST_STORE_LOCAL, INVALID, uint4(base_slot + ordinal, src, 0u, 0u));
    return true;
}

bool emit_struct_field_store(uint node, uint src, uint local_i)
{
    uint decl_token = INVALID;
    uint ordinal = INVALID;
    if (!struct_field_store_for_value_node(node, decl_token, ordinal))
        return true;

    uint base_slot = INVALID;
    uint row = INVALID;
    if (!local_slot_for_decl(decl_token, x86_node_func[node], base_slot) ||
        !location_for_node_local(node, local_i, row))
        return false;
    write_inst(row, node, local_i, X86_VINST_STORE_LOCAL, INVALID, uint4(base_slot + ordinal, src, 0u, 0u));
    return true;
}

bool struct_field_aggregate_copy_width(uint node, out uint width)
{
    width = 0u;
    uint decl_token = INVALID;
    uint ordinal = INVALID;
    if (!struct_field_store_for_value_node(node, decl_token, ordinal))
        return false;

    uint dest_width = 0u;
    if (!decl_storage_aggregate_width(decl_token, dest_width) ||
        ordinal >= dest_width)
        return false;

    uint source_node = resolve_expr(node);
    if (!valid_node(source_node))
        source_node = node;

    uint source_kind = 0u;
    uint source_payload = INVALID;
    uint source_width = 0u;
    if (!aggregate_source_for_expr(
            source_node,
            x86_node_func[node],
            source_kind,
            source_payload,
            source_width) ||
        source_width <= 1u)
        return false;

    width = min(source_width, dest_width - ordinal);
    return width > 1u;
}

uint aggregate_element_store_count(uint node)
{
    uint decl_token = INVALID;
    uint ordinal = INVALID;
    uint count = 0u;
    if (array_element_store_for_value_node(node, decl_token, ordinal))
        count += 1u;
    uint copy_width = 0u;
    if (struct_field_store_for_value_node(node, decl_token, ordinal) &&
        !struct_field_aggregate_copy_width(node, copy_width))
        count += 1u;
    return count;
}

bool emit_aggregate_element_stores(uint node, uint src, uint first_local_i)
{
    uint local_i = first_local_i;
    uint decl_token = INVALID;
    uint ordinal = INVALID;
    if (array_element_store_for_value_node(node, decl_token, ordinal))
    {
        if (!emit_array_element_store(node, src, local_i))
            return false;
        local_i += 1u;
    }
    if (struct_field_store_for_value_node(node, decl_token, ordinal))
    {
        if (!emit_struct_field_store(node, src, local_i))
            return false;
    }
    return true;
}

bool local_array_base_slot_for_index(uint index_node, out uint base_slot)
{
    base_slot = INVALID;
    uint base_node = base_node_for_index(index_node);
    uint decl_token = INVALID;
    if (!decl_token_for_name_expr(base_node, decl_token))
        return false;

    uint len = 0u;
    if (!decl_array_len(decl_token, len))
        return false;

    return local_slot_for_decl(decl_token, x86_node_func[index_node], base_slot);
}

uint member_access_node_for_expr(uint expr_node)
{
    if (!valid_node(expr_node))
        return INVALID;

    uint resolved = resolve_expr(expr_node);
    if (valid_node(resolved) && hir_kind[resolved] == HIR_MEMBER_EXPR)
        return resolved;
    if (hir_kind[expr_node] == HIR_MEMBER_EXPR)
        return expr_node;
    return INVALID;
}

bool local_store_slot_for_assignment_target(uint target_node, uint owner_fn, out uint slot, out uint value_node)
{
    slot = INVALID;
    value_node = target_node;
    if (local_slot_for_name(target_node, owner_fn, slot))
        return true;

    uint member_node = member_access_node_for_expr(target_node);
    if (!valid_node(member_node))
        return false;

    if (struct_access_kind(member_node) != X86_STRUCT_ACCESS_MEMBER ||
        !valid_node(struct_access_payload0(member_node)) ||
        struct_access_payload1(member_node) == INVALID)
        return false;

    uint receiver_node = struct_access_payload0(member_node);
    uint ordinal = struct_access_payload1(member_node);
    uint source_kind = 0u;
    uint payload = INVALID;
    uint width = 0u;
    if (!aggregate_source_for_expr(receiver_node, owner_fn, source_kind, payload, width))
        return false;
    if (source_kind != X86_AGG_SOURCE_LOCAL || ordinal >= width)
        return false;

    slot = payload + ordinal;
    value_node = member_node;
    return true;
}

bool assignment_target_param_aggregate_member(
    uint target_node,
    uint owner_fn,
    out uint member_node,
    out uint base_slot,
    out uint width,
    out uint ordinal)
{
    member_node = member_access_node_for_expr(target_node);
    base_slot = INVALID;
    width = 0u;
    ordinal = INVALID;
    if (!valid_node(member_node) ||
        struct_access_kind(member_node) != X86_STRUCT_ACCESS_MEMBER ||
        !valid_node(struct_access_payload0(member_node)) ||
        struct_access_payload1(member_node) == INVALID)
        return false;

    uint source_kind = 0u;
    uint payload = INVALID;
    if (!aggregate_source_for_expr(
            struct_access_payload0(member_node),
            owner_fn,
            source_kind,
            payload,
            width))
        return false;

    ordinal = struct_access_payload1(member_node);
    if (source_kind != X86_AGG_SOURCE_PARAM || ordinal >= width)
        return false;

    base_slot = payload;
    return true;
}

bool assignment_target_index_node(uint target_node, out uint index_node)
{
    index_node = INVALID;
    uint resolved = resolve_expr(target_node);
    if (is_index_expr_node(resolved))
    {
        index_node = resolved;
        return true;
    }
    if (is_index_expr_node(target_node))
    {
        index_node = target_node;
        return true;
    }
    return false;
}

void publish_index_assignment_error(uint index_node)
{
    publish_stage_error_min_detail4(
        x86_virtual_inst_status,
        X86_ERR_INDEX_ASSIGNMENT,
        valid_node(index_node) ? index_node : INVALID);
}

void publish_index_bounds_error(uint index_expr)
{
    uint detail = valid_node(index_expr) ? resolve_expr(index_expr) : INVALID;
    if (!valid_node(detail))
        detail = index_expr;
    publish_stage_error_min_detail4(
        x86_virtual_inst_status,
        X86_ERR_INDEX_BOUNDS,
        detail);
}

void publish_aggregate_temporary_index_error(uint index_node)
{
    uint base = is_index_expr_node(index_node) ? base_node_for_index(index_node) : INVALID;
    uint detail = valid_node(base) ? resolve_expr(base) : INVALID;
    if (!valid_node(detail))
        detail = valid_node(base) ? base : index_node;
    publish_stage_error_min_detail4(
        x86_virtual_inst_status,
        X86_ERR_AGGREGATE_TEMPORARY_INDEX,
        detail);
}

bool publish_unsized_index_error(uint index_node)
{
    uint index_expr = INVALID;
    if (!index_operand_expr_node(index_node, index_expr))
        index_expr = index_node;
    publish_dynamic_index_error(index_expr);
    return true;
}

bool node_is_index_source(uint node, out uint index_node)
{
    index_node = INVALID;
    if (!valid_node(node))
        return false;

    index_node = x86_index_source_owner[node];
    return valid_node(index_node) && is_index_expr_node(index_node);
}

bool write_index_source_value_error(uint value_node)
{
    uint index_node = INVALID;
    uint resolved = resolve_expr(value_node);
    if (!assignment_target_index_node(value_node, index_node) &&
        !node_is_index_source(resolved, index_node))
        return false;

    uint source_kind = 0u;
    uint payload = INVALID;
    uint width = 0u;
    if (!aggregate_source_for_index(index_node, source_kind, payload, width))
    {
        publish_aggregate_temporary_index_error(index_node);
        return true;
    }
    if (width == 0u)
        return publish_unsized_index_error(index_node);
    return false;
}

bool index_assignment_target(
    uint target_node,
    out uint index_node,
    out uint source_kind,
    out uint base_slot,
    out uint width,
    out uint index_vreg)
{
    index_node = INVALID;
    source_kind = 0u;
    base_slot = INVALID;
    width = 0u;
    index_vreg = INVALID;
    if (!assignment_target_index_node(target_node, index_node))
        return false;

    uint index_expr = INVALID;
    if (!index_operand_expr_node(index_node, index_expr))
    {
        publish_index_assignment_error(index_node);
        return false;
    }

    if (!aggregate_source_for_index(index_node, source_kind, base_slot, width))
    {
        if (!write_loop_call_value_error(index_expr))
            publish_aggregate_temporary_index_error(index_node);
        return false;
    }

    if (source_kind != X86_AGG_SOURCE_LOCAL && source_kind != X86_AGG_SOURCE_PARAM)
    {
        publish_index_assignment_error(index_node);
        return false;
    }

    if (width == 0u)
    {
        publish_unsized_index_error(index_node);
        return false;
    }

    if (compile_time_index_out_of_bounds(index_expr, width))
    {
        publish_index_bounds_error(index_expr);
        return false;
    }

    if (!value_vreg_for_node(index_expr, index_vreg))
    {
        if (!write_loop_call_value_error(index_expr))
            publish_index_assignment_error(index_node);
        return false;
    }
    return true;
}

uint call_abi_arg_count(uint2 abi)
{
    return abi.y & X86_CALL_ABI_ARG_COUNT_MASK;
}

uint call_abi_return_width(uint2 abi)
{
    return abi.y >> X86_CALL_ABI_ARG_COUNT_BITS;
}

bool has_call_abi_record(uint2 abi)
{
    bool host_call = abi.x >= X86_CALL_TARGET_HOST_STDERR_WRITE &&
                     abi.x <= X86_CALL_TARGET_HOST_TEXT_WRITE;
    if (abi.x == INVALID || abi.y == INVALID || (!host_call && !valid_node(abi.x)))
        return false;

    uint arg_count = call_abi_arg_count(abi);
    uint return_width = call_abi_return_width(abi);
    return arg_count <= X86_BACKEND_MAX_PACKED_CALL_ARGS &&
           return_width != 0u &&
           return_width <= X86_CALL_ABI_RETURN_WIDTH_MAX;
}

bool host_call_abi_record(uint2 abi)
{
    return has_call_abi_record(abi) &&
           abi.x >= X86_CALL_TARGET_HOST_STDERR_WRITE &&
           abi.x <= X86_CALL_TARGET_HOST_TEXT_WRITE;
}

uint call_abi_arg_count_for_call(uint call_node)
{
    uint call_slot = call_record_slot(call_node);
    if (call_slot == INVALID)
        return 0u;

    uint2 abi = x86_call_abi_record[call_slot];
    return has_call_abi_record(abi) ? call_abi_arg_count(abi) : 0u;
}

uint method_member_node_for_call(uint call_node)
{
    if (!valid_node(call_node))
        return INVALID;

    uint callee_node = hir_call_callee_node[call_node];
    if (valid_node(callee_node) && valid_node(hir_member_receiver_node[callee_node]))
        return callee_node;

    uint root = expr_result_root(callee_node);
    return valid_node(root) && valid_node(hir_member_receiver_node[root]) ? root : INVALID;
}

uint method_receiver_node_for_call(uint call_node)
{
    uint member_node = method_member_node_for_call(call_node);
    return valid_node(member_node) ? hir_member_receiver_node[member_node] : INVALID;
}

bool method_receiver_is_abi_arg(uint call_node)
{
    if (method_member_node_for_call(call_node) == INVALID)
        return false;

    uint explicit_count = hir_call_arg_count[call_node];
    return call_abi_arg_count_for_call(call_node) > explicit_count;
}

bool call_arg_node_for_call(uint call_node, uint ordinal, out uint arg_node)
{
    arg_node = INVALID;
    if (!valid_node(call_node))
        return false;

    uint explicit_count = hir_call_arg_count[call_node];
    bool receiver_arg = method_receiver_is_abi_arg(call_node);
    if (receiver_arg)
    {
        if (ordinal == 0u)
        {
            arg_node = method_receiver_node_for_call(call_node);
            return valid_node(arg_node);
        }
        ordinal -= 1u;
    }

    if (ordinal >= explicit_count)
        return false;

    uint start = call_arg_row_start[call_node];
    uint count = call_arg_row_count[call_node];
    if (start == INVALID || ordinal >= count)
        return false;

    uint row = start + ordinal;
    if (row < start || row >= gParams.n_hir_nodes)
        return false;

    arg_node = call_arg_row_node[row];
    return valid_node(arg_node);
}

bool enum_local_destination_for_value_node(uint node, out uint base_slot, out uint width)
{
    base_slot = INVALID;
    width = 0u;
    uint let_node = valid_node(node) ? x86_enclosing_let_node[node] : INVALID;
    if (!valid_node(let_node))
        return false;
    if (!let_initializer_resolves_to(let_node, node))
        return false;
    uint decl_token = stmt_slot(let_node, 1u);
    if (!decl_aggregate_width(decl_token, width) || width != 2u)
        return false;
    return local_slot_for_decl(decl_token, x86_node_func[node], base_slot);
}

bool emit_enum_value_to_local(uint node)
{
    uint2 record = x86_enum_value_record[node];
    if (!has_enum_value_record(node))
        return false;
    uint kind = enum_value_kind(record);

    uint base_slot = INVALID;
    uint width = 0u;
    if (!enum_local_destination_for_value_node(node, base_slot, width))
        return false;

    uint tag_row = INVALID;
    uint payload_row = INVALID;
    if (!location_for_node_local(node, 0u, tag_row) ||
        !location_for_node_local(node, 1u, payload_row))
        return false;

    write_inst(tag_row, node, 0u, X86_VINST_STORE_LOCAL_IMM, INVALID, uint4(base_slot, enum_value_ordinal(record), 0u, 0u));
    if (kind == X86_ENUM_VALUE_UNIT_CTOR)
    {
        write_inst(payload_row, node, 1u, X86_VINST_STORE_LOCAL_IMM, INVALID, uint4(base_slot + 1u, 0u, 0u, 0u));
        return true;
    }

    if (enum_value_payload_count(record) != 1u)
        return false;
    uint arg_node = INVALID;
    uint src = INVALID;
    if (!call_arg_node_for_call(node, 0u, arg_node) ||
        !value_vreg_for_node(arg_node, src))
        return false;
    write_inst(payload_row, node, 1u, X86_VINST_STORE_LOCAL, INVALID, uint4(base_slot + 1u, src, 0u, 0u));
    return true;
}

bool emit_member_field_value(uint node, uint row, uint dst)
{
    if (!valid_node(node) || hir_kind[node] != HIR_MEMBER_EXPR)
        return false;

    if (struct_access_kind(node) != X86_STRUCT_ACCESS_MEMBER)
    {
        write_status_error_detail(node, X86_VINST_ERROR_MEMBER_RECORD);
        return false;
    }

    uint receiver_node = struct_access_payload0(node);
    uint ordinal = struct_access_payload1(node);
    if (ordinal == INVALID)
    {
        write_status_error_detail(node, X86_VINST_ERROR_MEMBER_ORDINAL);
        return false;
    }

    uint source_kind = 0u;
    uint payload = INVALID;
    uint width = 0u;
    if (!member_source_for_expr(receiver_node, x86_node_func[node], source_kind, payload, width))
    {
        uint nested_receiver = INVALID;
        if (nested_aggregate_member_receiver(node, nested_receiver))
        {
            write_nested_aggregate_member_error(node);
            return false;
        }
        write_status_error_detail(
            node,
            member_source_failure_detail(receiver_node, x86_node_func[node]));
        return false;
    }
    if (ordinal >= width)
    {
        write_status_error_detail(node, X86_VINST_ERROR_MEMBER_WIDTH);
        return false;
    }

    if (source_kind == X86_AGG_SOURCE_LOCAL)
        write_inst(row, node, 0u, X86_VINST_LOAD_LOCAL, dst, uint4(payload + ordinal, 0u, 0u, 0u));
    else if (source_kind == X86_AGG_SOURCE_PARAM)
    {
        uint4 param_record = uint4_fill(INVALID);
        uint base = param_aggregate_payload_base(payload);
        uint base_ordinal = param_aggregate_payload_ordinal(payload);
        if (width == 1u && base_ordinal == 0u && ordinal == 0u)
        {
            if (!param_record_for_name(receiver_node, param_record))
                return false;
            write_inst(row, node, 0u, X86_VINST_PARAM, dst, param_record);
        }
        else
        {
            write_inst(row, node, 0u, X86_VINST_LOAD_PARAM_SLOT, dst, uint4(base, base_ordinal + ordinal, 0u, 0u));
        }
    }
    else
        return false;

    write_node_value(node, X86_NODE_VALUE_VREG, dst, node, payload);
    return emit_aggregate_element_stores(node, dst, 1u);
}

bool emit_aggregate_let_copy(uint node)
{
    uint stmt_kind = stmt_slot(node, 0u);
    if (!((hir_kind[node] == HIR_LET_STMT || hir_kind[node] == HIR_STMT) &&
          (stmt_kind == STMT_RECORD_KIND_LET ||
           stmt_kind == STMT_RECORD_KIND_CONST)))
        return false;

    uint dest_decl = stmt_slot(node, 1u);
    uint init_expr = stmt_slot(node, 2u);
    uint dest_slot = INVALID;
    uint dest_width = 0u;
    if (!local_slot_for_decl(dest_decl, x86_node_func[node], dest_slot) ||
        !decl_aggregate_width(dest_decl, dest_width) ||
        dest_width <= 1u)
        return false;

    uint source_kind = 0u;
    uint source_payload = INVALID;
    uint source_width = 0u;
    if (!aggregate_source_for_expr(init_expr, x86_node_func[node], source_kind, source_payload, source_width) ||
        source_width < dest_width)
        return false;
    if (dest_width > X86_AGG_COPY_MAX_WIDTH)
    {
        write_status_error_detail(node, X86_VINST_ERROR_AGG_COPY_WIDTH);
        return false;
    }

    write_node_value(node, X86_NODE_VALUE_NONE, INVALID, 0u, 0u);
    return true;
}

bool aggregate_let_initializer_stores_to_local(uint node)
{
    uint stmt_kind = stmt_slot(node, 0u);
    if (!((hir_kind[node] == HIR_LET_STMT || hir_kind[node] == HIR_STMT) &&
          (stmt_kind == STMT_RECORD_KIND_LET ||
           stmt_kind == STMT_RECORD_KIND_CONST)))
        return false;

    uint dest_width = 0u;
    if (!decl_aggregate_width(stmt_slot(node, 1u), dest_width) ||
        dest_width <= 1u)
        return false;

    uint init_expr = stmt_slot(node, 2u);
    uint init_width = 0u;
    if (array_literal_width(init_expr, init_width) && init_width == dest_width)
        return true;
    if (struct_literal_width(init_expr, init_width) && init_width == dest_width)
        return true;

    uint enum_node = INVALID;
    if (enum_value_node_for_expr(init_expr, enum_node, init_width) &&
        init_width == dest_width)
        return true;

    uint call_node = resolve_expr(init_expr);
    if (valid_node(call_node) && hir_kind[call_node] == HIR_CALL_EXPR)
    {
        uint call_slot = call_record_slot(call_node);
        uint2 abi = call_slot == INVALID
                        ? uint2(INVALID, INVALID)
                        : x86_call_abi_record[call_slot];
        return has_call_abi_record(abi) && call_abi_return_width(abi) >= dest_width;
    }

    return false;
}

bool struct_literal_child_has_scalar_value_instr(uint node)
{
    uint kind = valid_node(node) ? hir_kind[node] : 0u;
    uint form = expr_form(node);
    if (kind == HIR_LITERAL_EXPR)
        return true;
    if (form == HIR_EXPR_NAME)
        return scalar_name_expr_has_value_instr(node);
    return unary_op_for_form(form) != 0u ||
           binary_op_for_form(form) != 0u ||
           compare_op_for_form(form) != 0u;
}

bool emit_expr(uint node, uint2 range)
{
    uint row = INVALID;
    if (!location_for_node_local(node, 0u, row))
        return false;
    uint dst = row;
    uint form = expr_form(node);
    uint value = 0u;

    uint aggregate_field_copy_width = 0u;
    if (struct_field_aggregate_copy_width(node, aggregate_field_copy_width))
    {
        write_node_value(node, X86_NODE_VALUE_NONE, INVALID, 0u, 0u);
        return true;
    }

    if (hir_kind[node] == HIR_MEMBER_EXPR)
        return emit_member_field_value(node, row, dst);

    if (is_index_expr_node(node))
    {
        uint source_kind = 0u;
        uint payload = INVALID;
        uint width = 0u;
        uint index_expr = INVALID;
        uint index_vreg = INVALID;
        if (!index_operand_expr_node(node, index_expr))
        {
            write_status_error_detail(node, X86_VINST_ERROR_INDEX_OPERAND);
            return false;
        }
        if (!aggregate_source_for_index(node, source_kind, payload, width))
        {
            publish_aggregate_temporary_index_error(node);
            return false;
        }
        if (width == 0u)
        {
            publish_unsized_index_error(node);
            return false;
        }
        if (compile_time_index_out_of_bounds(index_expr, width))
        {
            publish_index_bounds_error(index_expr);
            return false;
        }
        if (write_unsupported_short_circuit_index_error(node, index_expr, width))
            return false;
        if (!value_vreg_for_node(index_expr, index_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_INDEX_VREG);
            return false;
        }
        if (source_kind == X86_AGG_SOURCE_LOCAL)
            write_inst(row, node, 0u, X86_VINST_LOAD_LOCAL_INDEX, dst, uint4(payload, index_vreg, width, 0u));
        else if (source_kind == X86_AGG_SOURCE_PARAM)
            write_inst(row, node, 0u, X86_VINST_LOAD_PARAM_INDEX, dst, uint4(payload, index_vreg, width, 0u));
        else
            return false;
        write_node_value(node, X86_NODE_VALUE_VREG, dst, node, payload);
        return emit_aggregate_element_stores(node, dst, 1u);
    }

    if (literal_scalar_value(node, value))
    {
        write_inst(row, node, 0u, X86_VINST_IMM_I32, dst, uint4(value, 0u, 0u, 0u));
        write_node_value(node, X86_NODE_VALUE_IMM_I32, value, dst, 0u);
        return emit_aggregate_element_stores(node, dst, 1u);
    }
    if (path_literal_value(node, value))
    {
        write_inst(row, node, 0u, X86_VINST_IMM_I32, dst, uint4(value, 0u, 0u, 0u));
        write_node_value(node, X86_NODE_VALUE_IMM_I32, value, dst, 0u);
        return emit_aggregate_element_stores(node, dst, 1u);
    }
    uint4 param_record = uint4_fill(INVALID);
    uint extra_store = aggregate_element_store_count(node);
    if (is_struct_literal_head_or_path_child(node) &&
        extra_store == 0u &&
        !struct_literal_child_has_scalar_value_instr(node))
        return true;

    if (form == HIR_EXPR_NAME && has_enum_value_record(node))
        return emit_enum_value_to_local(node);

    uint payload_source_kind = 0u;
    uint payload_source = INVALID;
    uint match_payload_reason = 0u;
    if (form == HIR_EXPR_NAME &&
        match_payload_source_for_name(node, payload_source_kind, payload_source, match_payload_reason))
    {
        if (payload_source_kind == X86_AGG_SOURCE_LOCAL)
            write_inst(row, node, 0u, X86_VINST_LOAD_LOCAL, dst, uint4(payload_source + 1u, 0u, 0u, 0u));
        else if (payload_source_kind == X86_AGG_SOURCE_PARAM)
        {
            uint payload_base = param_aggregate_payload_base(payload_source);
            uint payload_ordinal = param_aggregate_payload_ordinal(payload_source);
            write_inst(row, node, 0u, X86_VINST_LOAD_PARAM_SLOT, dst, uint4(payload_base, payload_ordinal + 1u, 0u, 0u));
        }
        else
            return false;
        write_node_value(node, X86_NODE_VALUE_VREG, dst, node, payload_source);
        return true;
    }

    uint local_slot = INVALID;
    if (form == HIR_EXPR_NAME && local_slot_for_name(node, x86_node_func[node], local_slot))
    {
        write_inst(row, node, 0u, X86_VINST_LOAD_LOCAL, dst, uint4(local_slot, 0u, 0u, 0u));
        write_node_value(node, X86_NODE_VALUE_VREG, dst, node, local_slot);
        return emit_aggregate_element_stores(node, dst, 1u);
    }

    if (form == HIR_EXPR_NAME && param_record_for_name(node, param_record))
    {
        write_inst(row, node, 0u, X86_VINST_PARAM, dst, param_record);
        write_node_value(node, X86_NODE_VALUE_PARAM, dst, param_record.x, param_record.z);
        return emit_aggregate_element_stores(node, dst, 1u);
    }

    if (form == HIR_EXPR_NAME && decl_literal_value(node, value))
    {
        write_inst(row, node, 0u, X86_VINST_IMM_I32, dst, uint4(value, 0u, 0u, 0u));
        write_node_value(node, X86_NODE_VALUE_IMM_I32, value, dst, 0u);
        return emit_aggregate_element_stores(node, dst, 1u);
    }

    uint unary_op = unary_op_for_node(node, form);
    if (unary_op != 0u)
    {
        uint src = INVALID;
        if (!value_vreg_for_node(expr_left(node), src))
            return false;
        write_inst(row, node, 0u, X86_VINST_UNARY, dst, uint4(unary_op, src, 0u, 0u));
        write_node_value(node, X86_NODE_VALUE_VREG, dst, node, 0u);
        return emit_aggregate_element_stores(node, dst, 1u);
    }

    uint binary_op = binary_op_for_node(node, form);
    uint compare_op = compare_op_for_node(node, form);
    if (binary_op != 0u || compare_op != 0u)
    {
        uint left = INVALID;
        uint right = INVALID;
        if (logical_form_short_circuits(form) &&
            write_short_circuit_call_error(expr_right(node)))
            return false;
        if (write_unsupported_short_circuit_arithmetic_error(node, binary_op))
            return false;
        if ((binary_op == X86_OP_DIV_I32 || binary_op == X86_OP_MOD_I32 ||
             binary_op == X86_OP_DIV_U32 || binary_op == X86_OP_MOD_U32) &&
            write_compile_time_zero_divisor_error(expr_right(node)))
            return false;
        if ((binary_op == X86_OP_DIV_I32 || binary_op == X86_OP_MOD_I32) &&
            write_compile_time_signed_div_overflow_error(node))
            return false;
        if (!value_vreg_for_node(expr_left(node), left))
        {
            if (write_index_source_value_error(expr_left(node)))
                return false;
            write_status_error_detail(node, X86_VINST_ERROR_BINARY_LEFT);
            return false;
        }
        if (!value_vreg_for_node(expr_right(node), right))
        {
            if (write_index_source_value_error(expr_right(node)))
                return false;
            write_status_error_detail(node, X86_VINST_ERROR_BINARY_RIGHT);
            return false;
        }

        uint op = binary_op != 0u ? binary_op : compare_op;
        uint inst_kind = binary_op != 0u ? X86_VINST_BINARY : X86_VINST_COMPARE;
        write_inst(row, node, 0u, inst_kind, dst, uint4(op, left, right, 0u));
        write_node_value(node, X86_NODE_VALUE_VREG, dst, node, 0u);
        return emit_aggregate_element_stores(node, dst, 1u);
    }

    if (form == HIR_EXPR_NAME)
        write_status_error_detail(
            node,
            match_payload_reason != 0u ? match_payload_reason : name_failure_detail(node));
    return false;
}

bool emit_param(uint node, uint2 range)
{
    if (!valid_node(node) || hir_kind[node] != HIR_PARAM)
        return false;

    uint load_row = INVALID;
    uint store_row = INVALID;
    uint decl_token = param_node_reg_link(node);
    uint local_slot = INVALID;
    if (param_node_reg_owner(node) != x86_node_func[node] ||
        param_node_reg_width(node) != 1u ||
        !valid_token(decl_token) ||
        !local_slot_for_decl(decl_token, x86_node_func[node], local_slot) ||
        !location_for_node_local(node, 0u, load_row) ||
        !location_for_node_local(node, 1u, store_row))
        return false;

    uint4 param_record = param_node_reg_record(node);
    write_inst(load_row, node, 0u, X86_VINST_PARAM, load_row, param_record);
    write_inst(store_row, node, 1u, X86_VINST_STORE_LOCAL, INVALID, uint4(local_slot, load_row, 0u, 0u));
    return true;
}

bool scalar_name_expr_has_value_instr(uint node)
{
    if (!valid_node(node) || expr_form(node) != HIR_EXPR_NAME)
        return false;

    uint local_slot = INVALID;
    if (local_slot_for_name(node, x86_node_func[node], local_slot))
        return true;

    uint4 param_record = uint4_fill(INVALID);
    if (param_record_for_name(node, param_record))
        return true;

    uint value = 0u;
    return decl_literal_value(node, value);
}

uint function_slot_for_node(uint fn_node)
{
    return valid_node(fn_node) ? x86_func_slot_by_node[fn_node] : INVALID;
}

bool compiled_function_node(uint node)
{
    return valid_node(node) &&
           hir_kind[node] == HIR_FN &&
           x86_node_func[node] == node &&
           function_slot_for_node(node) != INVALID;
}

bool emit_call(uint node, uint2 range)
{
    uint row = INVALID;
    if (!location_for_node_local(node, 0u, row))
        return false;
    uint dst = row;
    if (has_enum_value_record(node))
        return emit_enum_value_to_local(node);

    if (write_nested_short_circuit_call_error(node))
        return false;

    uint call_slot = call_record_slot(node);
    uint intrinsic_tag = intrinsic_call_tag(node);
    if (intrinsic_tag != 0u)
    {
        if (intrinsic_tag != X86_INTRINSIC_TEXT_WRITE)
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_INTRINSIC);
            return false;
        }
        uint arg_vreg = INVALID;
        uint arg0_node = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !value_vreg_for_node(arg0_node, arg_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_INTRINSIC_ARG);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_INTRINSIC, INVALID, uint4(intrinsic_tag, arg_vreg, arg0_node, 0u));
        return true;
    }

    uint2 abi = call_slot == INVALID
                    ? uint2(INVALID, INVALID)
                    : x86_call_abi_record[call_slot];
    if (!has_call_abi_record(abi))
    {
        uint index_node = INVALID;
        if (node_is_index_source(node, index_node))
        {
            publish_aggregate_temporary_index_error(index_node);
            return false;
        }
        write_status_error_detail(node, X86_VINST_ERROR_CALL_RECORD);
        return false;
    }

    if (host_call_abi_record(abi))
        return true;

    uint arg_count = call_abi_arg_count(abi);
    if (arg_count > X86_BACKEND_MAX_PACKED_CALL_ARGS)
    {
        write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG_COUNT);
        return false;
    }

    uint payload_row = INVALID;
    uint payload_row_hi = INVALID;
    if (!location_for_node_local(node, 1u, payload_row) ||
        !location_for_node_local(node, 2u, payload_row_hi))
    {
        write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG_PACK);
        return false;
    }
    write_mixed_arg_payloads(
        payload_row,
        payload_row_hi,
        row,
        node,
        0u,
        INVALID,
        INVALID,
        INVALID,
        INVALID,
        INVALID,
        INVALID);

    uint target_slot = function_slot_for_node(abi.x);
    if (target_slot == INVALID)
    {
        write_status_error_detail(node, X86_VINST_ERROR_CALL_TARGET);
        return false;
    }

    uint arg0_node = INVALID;
    uint arg1_node = INVALID;
    uint arg2_node = INVALID;
    uint arg3_node = INVALID;
    uint arg4_node = INVALID;
    uint arg5_node = INVALID;
    if (arg_count >= 1u && !valid_node(arg0_node) &&
        !call_arg_node_for_call(node, 0u, arg0_node))
    {
        write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG0_NODE);
        return false;
    }
    if (arg_count >= 2u && !valid_node(arg1_node) &&
        !call_arg_node_for_call(node, 1u, arg1_node))
    {
        write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG1_NODE);
        return false;
    }
    if (arg_count >= 3u && !call_arg_node_for_call(node, 2u, arg2_node))
    {
        write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG2_NODE);
        return false;
    }
    if (arg_count >= 4u && !call_arg_node_for_call(node, 3u, arg3_node))
    {
        write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG3_NODE);
        return false;
    }
    if (arg_count >= 5u && !call_arg_node_for_call(node, 4u, arg4_node))
    {
        write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG4_NODE);
        return false;
    }
    if (arg_count >= 6u && !call_arg_node_for_call(node, 5u, arg5_node))
    {
        write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG5_NODE);
        return false;
    }

    uint arg0_kind = 0u;
    uint arg1_kind = 0u;
    uint arg2_kind = 0u;
    uint arg3_kind = 0u;
    uint arg4_kind = 0u;
    uint arg5_kind = 0u;
    uint arg0_payload = INVALID;
    uint arg1_payload = INVALID;
    uint arg2_payload = INVALID;
    uint arg3_payload = INVALID;
    uint arg4_payload = INVALID;
    uint arg5_payload = INVALID;
    if (arg_count >= 1u && !call_arg_operand(arg0_node, x86_node_func[node], arg0_kind, arg0_payload))
    {
        write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG0_OPERAND);
        return false;
    }
    if (arg_count >= 2u && !call_arg_operand(arg1_node, x86_node_func[node], arg1_kind, arg1_payload))
    {
        write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG1_OPERAND);
        return false;
    }
    if (arg_count >= 3u && !call_arg_operand(arg2_node, x86_node_func[node], arg2_kind, arg2_payload))
    {
        write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG2_OPERAND);
        return false;
    }
    if (arg_count >= 4u && !call_arg_operand(arg3_node, x86_node_func[node], arg3_kind, arg3_payload))
    {
        write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG3_OPERAND);
        return false;
    }
    if (arg_count >= 5u && !call_arg_operand(arg4_node, x86_node_func[node], arg4_kind, arg4_payload))
    {
        write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG4_OPERAND);
        return false;
    }
    if (arg_count >= 6u && !call_arg_operand(arg5_node, x86_node_func[node], arg5_kind, arg5_payload))
    {
        write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG5_OPERAND);
        return false;
    }

    uint return_width = call_abi_return_width(abi);
    bool aggregate_return = return_width > 1u;
    uint dest_payload = row;
    uint mixed_dst = dst;
    uint agg_dest_reason = X86_VINST_ERROR_CALL_AGG_DEST;
    if (aggregate_return)
    {
        if (!aggregate_call_destination(node, return_width, dest_payload, agg_dest_reason))
        {
            uint index_node = INVALID;
            if (node_is_index_source(node, index_node))
            {
                publish_aggregate_temporary_index_error(index_node);
                return false;
            }
            write_aggregate_return_call_error(node, agg_dest_reason);
            return false;
        }
        // Aggregate calls still need a value-def row so regalloc computes the
        // live-register save mask for the call barrier.
        mixed_dst = row;
    }
    write_mixed_arg_payloads(
        payload_row,
        payload_row_hi,
        row,
        node,
        arg_count,
        arg_count >= 1u ? arg0_payload : INVALID,
        arg_count >= 2u ? arg1_payload : INVALID,
        arg_count >= 3u ? arg2_payload : INVALID,
        arg_count >= 4u ? arg3_payload : INVALID,
        arg_count >= 5u ? arg4_payload : INVALID,
        arg_count >= 6u ? arg5_payload : INVALID);
    uint info = pack_u8x4(arg_count, aggregate_return ? 1u : 0u, 0u, 0u) |
                pack_u2x4_at_offset(12u, arg0_kind, arg1_kind, arg2_kind, arg3_kind) |
                pack_u2x4_at_offset(20u, arg4_kind, arg5_kind, 0u, 0u);
    write_inst(
        row,
        node,
        0u,
        X86_VINST_CALL_MIXED,
        mixed_dst,
        uint4(target_slot, dest_payload, payload_row, info));
    if (!aggregate_return)
    {
        write_node_value(node, X86_NODE_VALUE_VREG, dst, node, abi.x);
        return emit_aggregate_element_stores(node, dst, 3u);
    }
    else
    {
        return true;
    }
}

bool emit_enum_value_to_ret_ptr(uint return_node, uint value_node, uint width)
{
    if (width != 2u || !has_enum_value_record(value_node))
        return false;

    uint2 record = x86_enum_value_record[value_node];
    uint kind = enum_value_kind(record);
    uint tag_row = INVALID;
    uint payload_row = INVALID;
    uint return_row = INVALID;
    if (!location_for_node_local(return_node, 0u, tag_row) ||
        !location_for_node_local(return_node, 1u, payload_row) ||
        !location_for_node_local(return_node, 2u, return_row))
        return false;

    write_inst(tag_row, return_node, 0u, X86_VINST_STORE_RET_PTR_IMM, INVALID, uint4(enum_value_ordinal(record), 0u, 0u, 0u));
    if (kind == X86_ENUM_VALUE_UNIT_CTOR)
    {
        write_inst(payload_row, return_node, 1u, X86_VINST_STORE_RET_PTR_IMM, INVALID, uint4(0u, 1u, 0u, 0u));
    }
    else
    {
        if (enum_value_payload_count(record) != 1u)
            return false;
        uint arg_node = INVALID;
        uint src = INVALID;
        if (!call_arg_node_for_call(value_node, 0u, arg_node) ||
            !value_vreg_for_node(arg_node, src))
            return false;
        write_inst(payload_row, return_node, 1u, X86_VINST_STORE_RET_PTR, INVALID, uint4(src, 1u, 0u, 0u));
    }

    write_inst(return_row, return_node, 2u, X86_VINST_RETURN_VOID, INVALID, uint4(0u, 0u, 0u, 0u));
    return true;
}

bool validate_struct_literal_to_ret_ptr(uint expr_node, uint width)
{
    if (width == 0u || width > 32u)
        return false;

    uint record_node = struct_literal_record_node_for_expr(expr_node);
    if (!valid_node(record_node))
        return false;

    if (struct_access_payload0(record_node) != width ||
        !valid_node(struct_access_payload1(record_node)))
        return false;

    return true;
}

bool emit_aggregate_return(uint node, uint width)
{
    uint expr_node = stmt_slot(node, 1u);
    uint enum_value_node = INVALID;
    uint enum_width = 0u;
    if (enum_value_node_for_expr(expr_node, enum_value_node, enum_width))
        return enum_width == width && emit_enum_value_to_ret_ptr(node, enum_value_node, width);

    uint struct_width = 0u;
    uint array_width = 0u;
    if (struct_literal_width(expr_node, struct_width))
    {
        if (struct_width != width)
        {
            write_status_error_detail(node, X86_VINST_ERROR_AGG_RET_STRUCT_WIDTH);
            return false;
        }
        if (!validate_struct_literal_to_ret_ptr(expr_node, width))
        {
            write_status_error_detail(node, X86_VINST_ERROR_AGG_RET_STRUCT_FIELD);
            return false;
        }
    }
    else if (array_literal_width(expr_node, array_width))
    {
        if (array_width != width)
        {
            write_status_error_detail(node, X86_VINST_ERROR_AGG_RET_ARRAY_WIDTH);
            return false;
        }
        if (!validate_array_literal_to_ret_ptr(expr_node, width))
        {
            write_status_error_detail(node, X86_VINST_ERROR_AGG_RET_ARRAY_FIELD);
            return false;
        }
    }
    else
    {
        uint source_kind = 0u;
        uint payload = INVALID;
        uint source_width = 0u;
        if (!aggregate_call_return_expr_width(expr_node, width) &&
            (!aggregate_source_for_expr(expr_node, x86_node_func[node], source_kind, payload, source_width) ||
             source_width != width))
        {
            write_status_error_detail(node, X86_VINST_ERROR_AGG_RET_SOURCE);
            return false;
        }
        if (width > X86_AGG_COPY_MAX_WIDTH)
        {
            write_status_error_detail(node, X86_VINST_ERROR_AGG_RET_COPY_WIDTH);
            return false;
        }
    }

    uint return_row = INVALID;
    if (!location_for_node_local(node, width, return_row))
    {
        write_status_error_detail(node, X86_VINST_ERROR_AGG_RET_RETURN_LOCATION);
        return false;
    }
    write_inst(return_row, node, width, X86_VINST_RETURN_VOID, INVALID, uint4(0u, 0u, 0u, 0u));
    return true;
}

bool emit_return_match(uint node)
{
    if (!supported_return_match(node))
        return false;

    uint4 match_record = x86_match_record[node];
    uint arm0 = nth_match_arm_node(node, 0u);
    uint arm1 = nth_match_arm_node(node, 1u);
    if (!valid_node(arm0) || !valid_node(arm1))
    {
        write_status_error_detail(node, X86_VINST_ERROR_MATCH_ARMS);
        return false;
    }

    uint tag0 = INVALID;
    if (!pattern_variant_ordinal(arm0, tag0))
    {
        uint pattern_error = X86_VINST_ERROR_MATCH_PATTERN;
        if (tag0 == MATCH_ARM_VARIANT_UNRESOLVED)
            pattern_error = X86_VINST_ERROR_MATCH_PATTERN_UNRESOLVED;
        else if (tag0 == MATCH_ARM_VARIANT_NO_USE_TOKEN)
            pattern_error = X86_VINST_ERROR_MATCH_PATTERN_NO_USE_TOKEN;
        else if (tag0 == MATCH_ARM_VARIANT_NO_VARIANT)
            pattern_error = X86_VINST_ERROR_MATCH_PATTERN_NO_VARIANT;
        write_status_error_detail(node, pattern_error);
        return false;
    }

    uint source_kind = 0u;
    uint source_payload = INVALID;
    uint source_width = 0u;
    if (!aggregate_source_for_expr(match_record.x, x86_node_func[node], source_kind, source_payload, source_width) ||
        source_width != 2u)
    {
        write_status_error_detail(node, X86_VINST_ERROR_MATCH_SOURCE);
        return false;
    }

    uint branch_row = INVALID;
    uint return0_row = INVALID;
    uint return1_row = INVALID;
    uint arm1_target = INVALID;
    uint result0 = x86_match_record[arm0].w;
    uint result1 = x86_match_record[arm1].w;
    uint result0_vreg = INVALID;
    uint result1_vreg = INVALID;
    if (!location_for_node_local(node, 0u, branch_row) ||
        !location_for_node_local(node, 1u, return0_row) ||
        !location_for_node_local(node, 2u, return1_row))
    {
        write_status_error_detail(node, X86_VINST_ERROR_MATCH_LOCATION);
        return false;
    }
    if (!first_instruction_row_in_subtree(result1, arm1_target))
    {
        write_status_error_detail(node, X86_VINST_ERROR_MATCH_TARGET);
        return false;
    }
    if (!value_vreg_for_node(result0, result0_vreg) ||
        !value_vreg_for_node(result1, result1_vreg))
    {
        write_status_error_detail(node, X86_VINST_ERROR_MATCH_RESULT);
        return false;
    }

    write_inst(
        branch_row,
        node,
        0u,
        X86_VINST_MATCH_TAG_BRANCH,
        INVALID,
        uint4(source_kind, source_payload, tag0, arm1_target));
    write_inst(return0_row, node, 1u, X86_VINST_RETURN, INVALID, uint4(result0_vreg, 0u, 0u, 0u));
    write_inst(return1_row, node, 2u, X86_VINST_RETURN, INVALID, uint4(result1_vreg, 0u, 0u, 0u));
    return true;
}

bool emit_stmt(uint node, uint2 range)
{
    uint row = INVALID;
    if (!location_for_node_local(node, 0u, row))
        return false;
    uint stmt_kind = stmt_slot(node, 0u);

    if ((hir_kind[node] == HIR_FOR_STMT || hir_kind[node] == HIR_STMT) &&
        stmt_kind == STMT_RECORD_KIND_FOR)
        return true;

    if (((hir_kind[node] == HIR_IF_STMT || hir_kind[node] == HIR_STMT) &&
         stmt_kind == STMT_RECORD_KIND_IF) ||
        ((hir_kind[node] == HIR_WHILE_STMT || hir_kind[node] == HIR_STMT) &&
         stmt_kind == STMT_RECORD_KIND_WHILE))
        return true;

    if (stmt_kind == STMT_RECORD_KIND_RETURN)
    {
        if (return_stmt_has_supported_match(node))
            return true;

        uint return_value = stmt_slot(node, 1u);
        if (!valid_node(return_value))
        {
            uint return_row = INVALID;
            if (!location_for_node_local(node, 1u, return_row))
            {
                write_status_error_detail(node, X86_VINST_ERROR_RETURN_LOCATION);
                return false;
            }
            write_inst(row, node, 0u, X86_VINST_IMM_I32, row, uint4(0u, 0u, 0u, 0u));
            write_node_value(node, X86_NODE_VALUE_IMM_I32, 0u, row, 0u);
            write_inst(return_row, node, 1u, X86_VINST_RETURN, INVALID, uint4(row, 0u, 0u, 0u));
            return true;
        }

        uint return_width = 0u;
        if (aggregate_return_width(node, return_width))
            return emit_aggregate_return(node, return_width);

        uint src = INVALID;
        if (!result_vreg_for_node(return_value, src))
        {
            if (write_index_source_value_error(return_value))
                return false;
            if (write_loop_call_value_error(return_value))
                return false;
            write_status_error_detail(node, resolve_expr(return_value));
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_RETURN, INVALID, uint4(src, 0u, 0u, 0u));
        return true;
    }

    if ((hir_kind[node] == HIR_LET_STMT || hir_kind[node] == HIR_STMT) &&
        (stmt_kind == STMT_RECORD_KIND_LET ||
         stmt_kind == STMT_RECORD_KIND_CONST))
    {
        if (emit_aggregate_let_copy(node))
            return true;
        if (emit_string_literal_to_local(node))
            return true;
        if (aggregate_let_initializer_stores_to_local(node))
        {
            write_node_value(node, X86_NODE_VALUE_NONE, INVALID, 0u, 0u);
            return true;
        }

        uint init_node = stmt_slot(node, 2u);
        uint src = INVALID;
        uint slot = INVALID;
        uint init_value = 0u;
        if (compile_time_scalar_immutable_value(init_node, init_value))
        {
            if (!local_slot_for_decl(stmt_slot(node, 1u), x86_node_func[node], slot))
            {
                write_status_error_detail(node, stmt_slot(node, 1u));
                return false;
            }
            write_inst(row, node, 0u, X86_VINST_STORE_LOCAL_IMM, INVALID, uint4(slot, init_value, stmt_kind, 0u));
            write_node_value(node, X86_NODE_VALUE_NONE, INVALID, 0u, 0u);
            return true;
        }
        if (!result_vreg_for_node(init_node, src))
        {
            if (write_index_source_value_error(init_node))
                return false;
            if (write_loop_call_value_error(init_node))
                return false;
            write_status_error_detail(node, X86_VINST_ERROR_LET_INIT_VALUE);
            return false;
        }
        if (!local_slot_for_decl(stmt_slot(node, 1u), x86_node_func[node], slot))
        {
            write_status_error_detail(node, stmt_slot(node, 1u));
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_STORE_LOCAL, INVALID, uint4(slot, src, stmt_kind, 0u));
        write_node_value(node, X86_NODE_VALUE_NONE, INVALID, 0u, 0u);
        return true;
    }

    if (hir_kind[node] == HIR_STMT && stmt_kind == STMT_RECORD_KIND_ASSIGN)
    {
        uint target_node = stmt_slot(node, 1u);
        uint rhs_node = stmt_slot(node, 2u);
        uint assign_op = stmt_slot(node, 3u);
        uint index_node = INVALID;
        if (assignment_target_index_node(target_node, index_node))
        {
            uint source_kind = 0u;
            uint base_slot = INVALID;
            uint width = 0u;
            uint index_vreg = INVALID;
            uint rhs = INVALID;
            if (!index_assignment_target(
                    target_node,
                    index_node,
                    source_kind,
                    base_slot,
                    width,
                    index_vreg))
                return false;
            if ((assign_op == ASSIGN_OP_DIV || assign_op == ASSIGN_OP_MOD) &&
                write_compile_time_zero_divisor_error(rhs_node))
                return false;
            if (!value_vreg_for_node(rhs_node, rhs))
            {
                if (write_index_source_value_error(rhs_node))
                    return false;
                if (write_loop_call_value_error(rhs_node))
                    return false;
                write_status_error_detail(node, X86_VINST_ERROR_ASSIGN_RHS);
                return false;
            }

            if (assign_op == ASSIGN_OP_SET)
            {
                uint store_op = source_kind == X86_AGG_SOURCE_PARAM
                                    ? X86_VINST_STORE_PARAM_INDEX
                                    : X86_VINST_STORE_LOCAL_INDEX;
                write_inst(row, node, 0u, store_op, INVALID, uint4(base_slot, index_vreg, rhs, width));
                write_node_value(node, X86_NODE_VALUE_NONE, INVALID, 0u, 0u);
                return true;
            }

            uint load_row = INVALID;
            uint binary_row = INVALID;
            uint store_row = INVALID;
            uint binary_op = binary_op_for_assignment_target(index_node, rhs_node, assign_op);
            if (binary_op == 0u ||
                !location_for_node_local(node, 0u, load_row) ||
                !location_for_node_local(node, 1u, binary_row) ||
                !location_for_node_local(node, 2u, store_row))
            {
                write_status_error_detail(node, X86_VINST_ERROR_ASSIGN_LOCATION);
                return false;
            }
            uint load_op = source_kind == X86_AGG_SOURCE_PARAM
                               ? X86_VINST_LOAD_PARAM_INDEX
                               : X86_VINST_LOAD_LOCAL_INDEX;
            uint store_op = source_kind == X86_AGG_SOURCE_PARAM
                                ? X86_VINST_STORE_PARAM_INDEX
                                : X86_VINST_STORE_LOCAL_INDEX;
            write_inst(load_row, node, 0u, load_op, load_row, uint4(base_slot, index_vreg, width, 0u));
            write_inst(binary_row, node, 1u, X86_VINST_BINARY, binary_row, uint4(binary_op, load_row, rhs, 0u));
            write_inst(store_row, node, 2u, store_op, INVALID, uint4(base_slot, index_vreg, binary_row, width));
            write_node_value(node, X86_NODE_VALUE_VREG, binary_row, node, base_slot);
            return true;
        }

        uint slot = INVALID;
        uint rhs = INVALID;
        uint target_value_node = INVALID;
        if (!local_store_slot_for_assignment_target(target_node, x86_node_func[node], slot, target_value_node))
        {
            uint member_node = INVALID;
            uint param_base = INVALID;
            uint param_width = 0u;
            uint param_ordinal = INVALID;
            if (assignment_target_param_aggregate_member(
                    target_node,
                    x86_node_func[node],
                    member_node,
                    param_base,
                    param_width,
                    param_ordinal))
            {
                if ((assign_op == ASSIGN_OP_DIV || assign_op == ASSIGN_OP_MOD) &&
                    write_compile_time_zero_divisor_error(rhs_node))
                    return false;
                if (!value_vreg_for_node(rhs_node, rhs))
                {
                    if (write_index_source_value_error(rhs_node))
                        return false;
                    if (write_loop_call_value_error(rhs_node))
                        return false;
                    write_status_error_detail(node, X86_VINST_ERROR_ASSIGN_RHS);
                    return false;
                }

                uint index_row = INVALID;
                if (assign_op == ASSIGN_OP_SET)
                {
                    uint store_row = INVALID;
                    if (!location_for_node_local(node, 0u, index_row) ||
                        !location_for_node_local(node, 1u, store_row))
                    {
                        write_status_error_detail(node, X86_VINST_ERROR_ASSIGN_LOCATION);
                        return false;
                    }
                    write_inst(
                        index_row,
                        node,
                        0u,
                        X86_VINST_IMM_I32,
                        index_row,
                        uint4(param_ordinal, 0u, 0u, 0u));
                    write_inst(
                        store_row,
                        node,
                        1u,
                        X86_VINST_STORE_PARAM_INDEX,
                        INVALID,
                        uint4(param_base, index_row, rhs, param_width));
                    write_node_value(node, X86_NODE_VALUE_NONE, INVALID, 0u, 0u);
                    return true;
                }

                uint load_row = INVALID;
                uint binary_row = INVALID;
                uint store_row = INVALID;
                uint binary_op = binary_op_for_assignment_target(member_node, rhs_node, assign_op);
                if (binary_op == 0u ||
                    !location_for_node_local(node, 0u, index_row) ||
                    !location_for_node_local(node, 1u, load_row) ||
                    !location_for_node_local(node, 2u, binary_row) ||
                    !location_for_node_local(node, 3u, store_row))
                {
                    write_status_error_detail(node, X86_VINST_ERROR_ASSIGN_LOCATION);
                    return false;
                }

                write_inst(
                    index_row,
                    node,
                    0u,
                    X86_VINST_IMM_I32,
                    index_row,
                    uint4(param_ordinal, 0u, 0u, 0u));
                write_inst(
                    load_row,
                    node,
                    1u,
                    X86_VINST_LOAD_PARAM_INDEX,
                    load_row,
                    uint4(param_base, index_row, param_width, 0u));
                write_inst(
                    binary_row,
                    node,
                    2u,
                    X86_VINST_BINARY,
                    binary_row,
                    uint4(binary_op, load_row, rhs, 0u));
                write_inst(
                    store_row,
                    node,
                    3u,
                    X86_VINST_STORE_PARAM_INDEX,
                    INVALID,
                    uint4(param_base, index_row, binary_row, param_width));
                write_node_value(node, X86_NODE_VALUE_VREG, binary_row, node, param_base);
                return true;
            }
            write_status_error_detail(node, X86_VINST_ERROR_ASSIGN_TARGET);
            return false;
        }
        if ((assign_op == ASSIGN_OP_DIV || assign_op == ASSIGN_OP_MOD) &&
            write_compile_time_zero_divisor_error(rhs_node))
            return false;
        if (!value_vreg_for_node(rhs_node, rhs))
        {
            if (write_index_source_value_error(rhs_node))
                return false;
            if (write_loop_call_value_error(rhs_node))
                return false;
            write_status_error_detail(node, X86_VINST_ERROR_ASSIGN_RHS);
            return false;
        }

        if (assign_op == ASSIGN_OP_SET)
        {
            write_inst(row, node, 0u, X86_VINST_STORE_LOCAL, INVALID, uint4(slot, rhs, assign_op, 0u));
            write_node_value(node, X86_NODE_VALUE_NONE, INVALID, 0u, 0u);
            return true;
        }

        uint lhs = INVALID;
        uint load_row = INVALID;
        uint binary_row = INVALID;
        uint store_row = INVALID;
        uint binary_op = binary_op_for_assignment_target(target_value_node, rhs_node, assign_op);
        if (binary_op == 0u ||
            !location_for_node_local(node, 0u, load_row) ||
            !location_for_node_local(node, 1u, binary_row) ||
            !location_for_node_local(node, 2u, store_row))
        {
            write_status_error_detail(node, X86_VINST_ERROR_ASSIGN_LOCATION);
            return false;
        }

        lhs = load_row;
        write_inst(load_row, node, 0u, X86_VINST_LOAD_LOCAL, lhs, uint4(slot, 0u, 0u, 0u));
        write_inst(binary_row, node, 1u, X86_VINST_BINARY, binary_row, uint4(binary_op, lhs, rhs, 0u));
        write_inst(store_row, node, 2u, X86_VINST_STORE_LOCAL, INVALID, uint4(slot, binary_row, assign_op, 0u));
        write_node_value(node, X86_NODE_VALUE_VREG, binary_row, node, slot);
        return true;
    }

    if (hir_kind[node] == HIR_BREAK_STMT || hir_kind[node] == HIR_CONTINUE_STMT)
    {
        uint loop_node = INVALID;
        uint target = INVALID;
        if (!enclosing_while_for_node(node, loop_node))
        {
            write_loop_control_outside_loop_error(node);
            return false;
        }
        if (hir_kind[node] == HIR_BREAK_STMT)
        {
            if (!row_after_subtree(loop_node, target))
                return false;
        }
        else
        {
            if (stmt_slot(loop_node, 0u) == STMT_RECORD_KIND_FOR)
            {
                uint body_node = stmt_slot(loop_node, 3u);
                if (!location_for_node_local(body_node, 0u, target))
                    return false;
            }
            else
            {
                uint cond_node = stmt_slot(loop_node, 1u);
                if (!first_instruction_row_in_subtree(cond_node, target))
                    return false;
            }
        }
        write_inst(row, node, 0u, X86_VINST_BRANCH, INVALID, uint4(INVALID, target, loop_node, 0u));
        return true;
    }

    return false;
}

bool emit_function_fallthrough_return(uint node)
{
    if (!compiled_function_node(node))
        return false;

    uint value_row = INVALID;
    uint return_row = INVALID;
    if (!location_for_node_local(node, 0u, value_row) ||
        !location_for_node_local(node, 1u, return_row))
    {
        write_status_error_detail(node, X86_VINST_ERROR_RETURN_LOCATION);
        return false;
    }

    write_inst(value_row, node, 0u, X86_VINST_IMM_I32, value_row, uint4(0u, 0u, 0u, 0u));
    write_node_value(node, X86_NODE_VALUE_IMM_I32, 0u, value_row, 0u);
    write_inst(return_row, node, 1u, X86_VINST_RETURN, INVALID, uint4(value_row, 0u, 0u, 0u));
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint order_row = linear_dispatch_id(tid);
    if (!upstream_ok() || order_row >= gen_worklist_count())
        return;

    uint node = gen_worklist_node(order_row);
    if (!valid_node(node))
    {
        publish_stage_error_min_detail4(
            x86_virtual_inst_status,
            X86_ERR_NODE_VIRTUAL_INST,
            order_row);
        return;
    }

    uint2 range = uint2(INVALID, 0u);
    bool has_range = range_for_node(node, range);
    if (!has_range && !has_location_for_node_local(node, 0u))
        return;

    if (has_range && range_count(range) == 0u)
    {
        if (!has_location_for_node_local(node, 0u))
        {
            write_node_value(node, X86_NODE_VALUE_NONE, INVALID, 0u, 0u);
            return;
        }
    }

    if (has_range && range_kind(range) == X86_NODE_INST_PADDING)
    {
        if (!emit_padding_range(node, range))
            write_status_error(node);
        return;
    }

    bool emitted = false;
    if (hir_kind[node] == HIR_FN)
        emitted = true;
    else if (has_match_feature() && hir_kind[node] == HIR_MATCH_EXPR)
        emitted = emit_return_match(node);
    else if (hir_kind[node] == HIR_PARAM)
        emitted = true;
    else if (hir_kind[node] == HIR_CALL_EXPR)
        emitted = emit_call(node, range);
    else if (hir_kind[node] == HIR_STMT ||
             hir_kind[node] == HIR_RETURN_STMT ||
             hir_kind[node] == HIR_LET_STMT ||
             hir_kind[node] == HIR_IF_STMT ||
             hir_kind[node] == HIR_WHILE_STMT ||
             hir_kind[node] == HIR_FOR_STMT ||
             hir_kind[node] == HIR_BREAK_STMT ||
             hir_kind[node] == HIR_CONTINUE_STMT ||
             stmt_slot(node, 0u) == STMT_RECORD_KIND_RETURN)
        emitted = emit_stmt(node, range);
    else if (hir_kind[node] == HIR_ASSIGN_EXPR ||
             hir_kind[node] == HIR_BINARY_EXPR ||
             hir_kind[node] == HIR_UNARY_EXPR ||
             hir_kind[node] == HIR_POSTFIX_EXPR ||
             is_index_expr_node(node) ||
             hir_kind[node] == HIR_MEMBER_EXPR ||
             hir_kind[node] == HIR_PATH_EXPR ||
             hir_kind[node] == HIR_EXPR ||
             hir_kind[node] == HIR_NAME_EXPR ||
             hir_kind[node] == HIR_LITERAL_EXPR)
        emitted = emit_expr(node, range);

    if (!emitted)
        write_status_error(node);
}

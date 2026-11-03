module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc0
public import Lanius.Faithful.Gen.SelfSrc4
public import Lanius.Faithful.Gen.SelfSrc6
public import Lanius.Faithful.Gen.SelfSrc7
public import Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
public import Lanius.Faithful.Gen.SelfSrcC_DivOp_size
public import Lanius.Faithful.Gen.SelfSrcC_Expr_agrees
public import Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
public import Lanius.Faithful.Gen.SelfSrcC_Inline_factOr
public import Lanius.Faithful.Gen.SelfSrcC_Inline_lowerSetScalar
public import Lanius.Faithful.Gen.SelfSrcC_Lists_empty
public import Lanius.Faithful.Gen.SelfSrcC_SrcType_same
public import Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
public import Lanius.Faithful.Gen.SelfSrcC_UintTy_isWide
public import Lanius.Faithful.Gen.SelfSrcC_Word_compute
public import Lanius.Faithful.Gen.SelfSrcC_Word_narrows
public import Lanius.Faithful.Gen.SelfSrcC_arithShiftRight
public import Lanius.Faithful.Gen.SelfSrcC_arities
public import Lanius.Faithful.Gen.SelfSrcC_assignFrom
public import Lanius.Faithful.Gen.SelfSrcC_binaryConstant
public import Lanius.Faithful.Gen.SelfSrcC_bindingBytes
public import Lanius.Faithful.Gen.SelfSrcC_conjunction
public import Lanius.Faithful.Gen.SelfSrcC_declareProgram
public import Lanius.Faithful.Gen.SelfSrcC_elementAddress
public import Lanius.Faithful.Gen.SelfSrcC_elementBase
public import Lanius.Faithful.Gen.SelfSrcC_equality
public import Lanius.Faithful.Gen.SelfSrcC_floatApply
public import Lanius.Faithful.Gen.SelfSrcC_guardAnd
public import Lanius.Faithful.Gen.SelfSrcC_hostRandomCode
public import Lanius.Faithful.Gen.SelfSrcC_iteThen
public import Lanius.Faithful.Gen.SelfSrcC_killShared
public import Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
public import Lanius.Faithful.Gen.SelfSrcC_longer
public import Lanius.Faithful.Gen.SelfSrcC_lowerCallSig
public import Lanius.Faithful.Gen.SelfSrcC_lowerLoadType
public import Lanius.Faithful.Gen.SelfSrcC_lowerLocal
public import Lanius.Faithful.Gen.SelfSrcC_lowerSetValues
public import Lanius.Faithful.Gen.SelfSrcC_lowerShift
public import Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
public import Lanius.Faithful.Gen.SelfSrcC_repeatType
public import Lanius.Faithful.Gen.SelfSrcC_shortCircuit
public import Lanius.Faithful.Gen.SelfSrcC_sintToUint
public import Lanius.Faithful.Gen.SelfSrcC_storeEvalWord
public import Lanius.Faithful.Gen.SelfSrcC_storeType
public import Lanius.Faithful.Gen.SelfSrcC_storeWordElement
public import Lanius.Faithful.Gen.SelfSrcC_widthOf
public import Lanius.Faithful.Gen.SelfSrcC_wordStride
public import Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc0
import all Lanius.Faithful.Gen.SelfSrc4
import all Lanius.Faithful.Gen.SelfSrc6
import all Lanius.Faithful.Gen.SelfSrc7
import all Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
import all Lanius.Faithful.Gen.SelfSrcC_DivOp_size
import all Lanius.Faithful.Gen.SelfSrcC_Expr_agrees
import all Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
import all Lanius.Faithful.Gen.SelfSrcC_Inline_factOr
import all Lanius.Faithful.Gen.SelfSrcC_Inline_lowerSetScalar
import all Lanius.Faithful.Gen.SelfSrcC_Lists_empty
import all Lanius.Faithful.Gen.SelfSrcC_SrcType_same
import all Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
import all Lanius.Faithful.Gen.SelfSrcC_UintTy_isWide
import all Lanius.Faithful.Gen.SelfSrcC_Word_compute
import all Lanius.Faithful.Gen.SelfSrcC_Word_narrows
import all Lanius.Faithful.Gen.SelfSrcC_arithShiftRight
import all Lanius.Faithful.Gen.SelfSrcC_arities
import all Lanius.Faithful.Gen.SelfSrcC_assignFrom
import all Lanius.Faithful.Gen.SelfSrcC_binaryConstant
import all Lanius.Faithful.Gen.SelfSrcC_bindingBytes
import all Lanius.Faithful.Gen.SelfSrcC_conjunction
import all Lanius.Faithful.Gen.SelfSrcC_declareProgram
import all Lanius.Faithful.Gen.SelfSrcC_elementAddress
import all Lanius.Faithful.Gen.SelfSrcC_elementBase
import all Lanius.Faithful.Gen.SelfSrcC_equality
import all Lanius.Faithful.Gen.SelfSrcC_floatApply
import all Lanius.Faithful.Gen.SelfSrcC_guardAnd
import all Lanius.Faithful.Gen.SelfSrcC_hostRandomCode
import all Lanius.Faithful.Gen.SelfSrcC_iteThen
import all Lanius.Faithful.Gen.SelfSrcC_killShared
import all Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
import all Lanius.Faithful.Gen.SelfSrcC_longer
import all Lanius.Faithful.Gen.SelfSrcC_lowerCallSig
import all Lanius.Faithful.Gen.SelfSrcC_lowerLoadType
import all Lanius.Faithful.Gen.SelfSrcC_lowerLocal
import all Lanius.Faithful.Gen.SelfSrcC_lowerSetValues
import all Lanius.Faithful.Gen.SelfSrcC_lowerShift
import all Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
import all Lanius.Faithful.Gen.SelfSrcC_repeatType
import all Lanius.Faithful.Gen.SelfSrcC_shortCircuit
import all Lanius.Faithful.Gen.SelfSrcC_sintToUint
import all Lanius.Faithful.Gen.SelfSrcC_storeEvalWord
import all Lanius.Faithful.Gen.SelfSrcC_storeType
import all Lanius.Faithful.Gen.SelfSrcC_storeWordElement
import all Lanius.Faithful.Gen.SelfSrcC_widthOf
import all Lanius.Faithful.Gen.SelfSrcC_wordStride
import all Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfTypes
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.Types

@[expose] public section

/-! Generated by formal/tools/faithful_pure.py. Do not edit. -/

namespace Lanius.Faithful.SelfPure

open Lanius.Mini
open Lanius.Faithful
open Lanius.Faithful.Self

/-- Functions 1000 to 1099, and their signature entries. -/
def dpart10 : List SrcFunc := [(src_low_bits), (src_optimize_both 332 1240 1241), (src_optimize_left 332 1242 1243 1244 1245 1246), (src_optimize_right 332 1242 1244 1245 1246), (src_Word_test 1247 1248), (src_fact_or 689), (src_unbox_of_mini_selfhost_List_mini_selfhost_Fact 1249), (src_assigned 459 1008 1250 1251 1252 1253), (src_kill_shared 1254 1255), (src_Stmt_kills 302 1009 1251 1256 1257 1258), (src_Expr_agrees 485 685 703 1259 1260 1261 1262 1263 1264), (src_negate_constant 1000), (src_binary_constant 1265 1266), (src_compare_constant 495 1004), (src_constant_is), (src_args_agree 486 1010 1015), (src_MemWidth_bytes), (src_Word_number), (src_DivOp_number), (src_Syscall_number), (src_get_of_mini_selfhost_Arity 56 1020 1267), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Instr), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Instr), (src_BinOp_size), (src_Word_prefix), (src_MemWidth_prefix), (src_DivOp_size 75 1024), (src_FOp_size 75 105 1024 1268), (src_core_mem_size_of_of_mini_selfhost_List_u8), (src_le64 742 743), (src_slot_load 478 742 743 744 1269), (src_slot_store 478 742 743 744 1269), (src_BinOp_bytes 478 1270 1271 1272), (src_slot_compare 478 742 743 1270 1271 1273), (src_relative), (src_copy_bytes 75 76 110 478 1030 1031 1035), (src_arg_base 75 745), (src_fsp_save 478 742 743 744 1269), (src_fsp_load 478 742 743 744 1269), (src_slot_range 56 75 138 398 1039), (src_epilogue 742 743), (src_bump_bytes 478 742 743 1029 1274), (src_load_at_bytes 742 743), (src_store_at_bytes 478 742 743 744 1269), (src_load_word_bytes 478 742 743 1275), (src_store_word_bytes 478 742 743 744 1269 1275), (src_DivOp_bytes 478 742 743 1270 1271 1276 1277 1278), (src_FOp_bytes 478 1270 1279), (src_sys_bytes 75 478 742 743 744 1269 1280 1281 1282), (src_frame_memory_bytes 478 742 743 1029), (src_literal_below), (src_UintTy_bits), (src_lower_field_at 1283), (src_offset_or_arith 332 334 385 1054), (src_arith 332 333 386 791 793 794 801 1284 1285 1286 1287), (src_lower_shift 1054 1288), (src_arith_shift_right 333 386 1055 1285), (src_order 332 333 386 387 791 793 794 801 1285 1289 1290 1291 1292), (src_equality 232 332 791 793 1289 1293), (src_conjunction 332 382), (src_disjunction 332 382), (src_cast_to_i32 1294 1295), (src_cast_to_uint 1294 1296 1297), (src_cast_to_isize 1296 1298), (src_cast_to_float 1299 1300 1301 1302), (src_cast_to_sint 312 382 385 791 1063 1085 1086), (src_copy_field_at 1303), (src_concat_of_mini_selfhost_Expr 306 486 1067), (src_unbox_of_mini_selfhost_List_mini_selfhost_SrcArm 1304), (src_lower_arm 185 307 311 332), (src_arm_guard 188), (src_lower_set_value), (src_load_type 178 180 185 1091 1092 1305 1306), (src_eval_pick 120 185 307 332 333 334 1307), (src_eval_field_type 190 1308), (src_element_address 375 1309), (src_store_element 204 1075), (src_store_byte_element 204 1075), (src_store_word_element 120 190 807 808), (src_array_args 75 138 178 351 534 1079 1310 1311), (src_array_call_code 75 120 185 307 312), (src_host_text_code 75 185 332 781), (src_host_newline_code 75 185 780), (src_FloatTy_sign_word), (src_FloatTy_sign_bit), (src_UintTy_is_wide), (src_norm 332 1312), (src_overflow_guard 75 332 1313), (src_unsigned_div), (src_word_stride 105 332), (src_store_one), (src_width_of 1314), (src_address_below 332), (src_get_of_mini_selfhost_Expr 56 486 1093), (src_store_types 75 105 120 178 197 807 1094), (src_store_cases 75 180 332 1094 1095 1315), (src_put_element 56 75 105 185 311 332 348 1096), (src_core_mem_size_of_of_mini_selfhost_List_u64), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcStructDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcEnumDecl)]

def dents10 : List SigEntry := [some ([(.uint .uint64)], (.uint .uint64)), some ([ty53, ty54, (.uint .uint64), (.uint .uint64), ty90, ty90], ty90), some ([ty53, ty54, (.uint .uint64), ty90, ty90], ty90), some ([ty53, ty54, ty90, ty90, (.uint .uint64)], ty90), some ([ty53, ty55, (.uint .uint64), (.uint .uint64)], .bool), some ([ty201, (.uint .usize), ty203], ty90), some ([ty202], ty203), some ([ty203, (.uint .usize), ty90], ty203), some ([ty203, (.uint .usize)], ty203), some ([ty94, (.uint .usize)], .bool), some ([ty90, ty90], .bool), some ([ty233], ty233), some ([ty53, ty54, ty233, ty233], ty233), some ([ty53, ty55, ty233, ty233], ty233), some ([ty233, (.uint .uint64)], .bool), some ([ty93, ty93], .bool), some ([ty56], (.uint .usize)), some ([ty53], (.uint .usize)), some ([ty57], (.uint .usize)), some ([ty61], (.uint .usize)), some ([ty161, (.uint .usize)], ty255), none, none, some ([ty54], (.uint .usize)), some ([ty53], (.uint .usize)), some ([ty56], (.uint .usize)), some ([ty57, ty53], (.uint .usize)), some ([ty60], (.uint .usize)), none, some ([(.uint .uint64)], ty35), some ([(.uint .usize)], ty35), some ([(.uint .usize)], ty35), some ([ty54, ty53, (.uint .usize)], ty35), some ([ty53, ty55, (.uint .usize)], ty35), some ([(.uint .usize), (.uint .usize)], .i32), some ([(.uint .usize), ty20, (.uint .usize)], ty35), some ([(.uint .usize)], (.uint .usize)), some ([(.uint .usize)], ty35), some ([(.uint .usize)], ty35), some ([(.uint .usize), (.uint .usize)], ty20), some ([], ty35), some ([(.uint .usize)], ty35), some ([], ty35), some ([(.uint .usize)], ty35), some ([ty56], ty35), some ([ty56, (.uint .usize)], ty35), some ([ty57, ty53, (.uint .usize)], ty35), some ([ty60, (.uint .usize)], ty35), some ([ty61, (.uint .usize)], ty35), some ([(.uint .usize)], ty35), some ([ty90, (.uint .uint64)], .bool), some ([ty4], (.uint .uint64)), some ([(.uint .usize), ty177], ty174), some ([ty54, ty173, ty173], ty174), some ([ty54, ty173, ty173], ty174), some ([ty54, ty173, ty173], ty174), some ([ty173, ty173], ty174), some ([ty55, ty173, ty173], ty174), some ([ty55, ty173, ty173], ty174), some ([ty173, ty173], ty174), some ([ty173, ty173], ty174), some ([ty173], ty174), some ([ty4, ty173], ty174), some ([ty173], ty174), some ([ty8, ty173], ty174), some ([ty4, ty173], ty174), some ([(.uint .usize), ty177, ty9], ty169), some ([ty93, ty93], ty93), some ([ty22], ty23), some ([(.uint .usize), (.uint .usize), (.uint .usize), ty90, ty169, ty23, ty145], ty145), some ([ty215, ty15], ty90), some ([(.uint .usize), ty172], ty145), some ([ty9, (.uint .usize), ty90, (.uint .usize), ty94], ty94), some ([(.uint .usize), ty9, (.uint .usize), (.uint .usize), ty175], ty176), some ([ty148, ty15, (.uint .usize), ty177], ty176), some ([ty146, ty172], ty172), some ([ty146, ty9, ty172, ty148, ty15], ty145), some ([ty146, ty9, ty172, ty148, ty15], ty145), some ([ty146, ty9, ty172, ty148, ty15], ty145), some ([ty148, ty212, ty71, (.uint .usize), (.uint .usize)], ty258), some ([(.uint .usize), (.uint .usize), ty100, ty257], ty176), some ([(.uint .usize)], ty94), some ([(.uint .usize)], ty94), some ([ty8], ty53), some ([ty8], (.uint .uint64)), some ([ty4], .bool), some ([ty4, ty90], ty90), some ([ty4, (.uint .usize)], ty90), some ([ty28], ty57), some ([(.uint .usize), (.uint .usize)], ty175), some ([ty56, ty90, ty172], ty145), some ([ty9], ty56), some ([ty90, (.uint .usize)], ty90), some ([ty93, (.uint .usize)], ty172), some ([ty71, ty93, (.uint .usize), ty90, (.uint .usize)], ty145), some ([ty90, ty93, (.uint .usize), ty90, (.uint .usize), (.uint .usize), ty75], ty145), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], ty94), none, none, none]

/-- `declareFuncs` of functions 1000 to 1099. -/
theorem dchunk10 : declsStep dpart10 decls 35 59 35 58 = true := by decide +kernel

theorem dfit10 : entriesFit dpart10 dents10 = true := by decide +kernel

end Lanius.Faithful.SelfPure

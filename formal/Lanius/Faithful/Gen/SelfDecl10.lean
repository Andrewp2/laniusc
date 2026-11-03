module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc4
public import Lanius.Faithful.Gen.SelfSrc6
public import Lanius.Faithful.Gen.SelfSrc7
public import Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
public import Lanius.Faithful.Gen.SelfSrcC_DivOp_size
public import Lanius.Faithful.Gen.SelfSrcC_Expr_agrees
public import Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
public import Lanius.Faithful.Gen.SelfSrcC_Inline_lowerSetScalar
public import Lanius.Faithful.Gen.SelfSrcC_Lists_empty
public import Lanius.Faithful.Gen.SelfSrcC_SrcType_size
public import Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
public import Lanius.Faithful.Gen.SelfSrcC_UintTy_isWide
public import Lanius.Faithful.Gen.SelfSrcC_Word_narrows
public import Lanius.Faithful.Gen.SelfSrcC_arithShiftRight
public import Lanius.Faithful.Gen.SelfSrcC_arities
public import Lanius.Faithful.Gen.SelfSrcC_assignFrom
public import Lanius.Faithful.Gen.SelfSrcC_binaryConstant
public import Lanius.Faithful.Gen.SelfSrcC_bindingBytes
public import Lanius.Faithful.Gen.SelfSrcC_conjunction
public import Lanius.Faithful.Gen.SelfSrcC_elementAddress
public import Lanius.Faithful.Gen.SelfSrcC_elementBase
public import Lanius.Faithful.Gen.SelfSrcC_equality
public import Lanius.Faithful.Gen.SelfSrcC_floatApply
public import Lanius.Faithful.Gen.SelfSrcC_guardAnd
public import Lanius.Faithful.Gen.SelfSrcC_iteThen
public import Lanius.Faithful.Gen.SelfSrcC_killShared
public import Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
public import Lanius.Faithful.Gen.SelfSrcC_longer
public import Lanius.Faithful.Gen.SelfSrcC_lowerCallSig
public import Lanius.Faithful.Gen.SelfSrcC_lowerLoadType
public import Lanius.Faithful.Gen.SelfSrcC_lowerLocal
public import Lanius.Faithful.Gen.SelfSrcC_lowerSetValues
public import Lanius.Faithful.Gen.SelfSrcC_lowerShift
public import Lanius.Faithful.Gen.SelfSrcC_repeatType
public import Lanius.Faithful.Gen.SelfSrcC_shortCircuit
public import Lanius.Faithful.Gen.SelfSrcC_sintToUint
public import Lanius.Faithful.Gen.SelfSrcC_storeEvalWord
public import Lanius.Faithful.Gen.SelfSrcC_storeType
public import Lanius.Faithful.Gen.SelfSrcC_storeWordElement
public import Lanius.Faithful.Gen.SelfSrcC_widthOf
public import Lanius.Faithful.Gen.SelfSrcC_wordStride
public import Lanius.Faithful.Gen.SelfSrcF_lxExponent
public import Lanius.Faithful.Gen.SelfSrcF_lxLeadingDot
public import Lanius.Faithful.Gen.SelfSrcF_lxSpaceEnd
public import Lanius.Faithful.Gen.SelfSrcF_lxSymbolStart
public import Lanius.Faithful.Gen.SelfSrcF_wideLeftStmt
public import Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc4
import all Lanius.Faithful.Gen.SelfSrc6
import all Lanius.Faithful.Gen.SelfSrc7
import all Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
import all Lanius.Faithful.Gen.SelfSrcC_DivOp_size
import all Lanius.Faithful.Gen.SelfSrcC_Expr_agrees
import all Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
import all Lanius.Faithful.Gen.SelfSrcC_Inline_lowerSetScalar
import all Lanius.Faithful.Gen.SelfSrcC_Lists_empty
import all Lanius.Faithful.Gen.SelfSrcC_SrcType_size
import all Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
import all Lanius.Faithful.Gen.SelfSrcC_UintTy_isWide
import all Lanius.Faithful.Gen.SelfSrcC_Word_narrows
import all Lanius.Faithful.Gen.SelfSrcC_arithShiftRight
import all Lanius.Faithful.Gen.SelfSrcC_arities
import all Lanius.Faithful.Gen.SelfSrcC_assignFrom
import all Lanius.Faithful.Gen.SelfSrcC_binaryConstant
import all Lanius.Faithful.Gen.SelfSrcC_bindingBytes
import all Lanius.Faithful.Gen.SelfSrcC_conjunction
import all Lanius.Faithful.Gen.SelfSrcC_elementAddress
import all Lanius.Faithful.Gen.SelfSrcC_elementBase
import all Lanius.Faithful.Gen.SelfSrcC_equality
import all Lanius.Faithful.Gen.SelfSrcC_floatApply
import all Lanius.Faithful.Gen.SelfSrcC_guardAnd
import all Lanius.Faithful.Gen.SelfSrcC_iteThen
import all Lanius.Faithful.Gen.SelfSrcC_killShared
import all Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
import all Lanius.Faithful.Gen.SelfSrcC_longer
import all Lanius.Faithful.Gen.SelfSrcC_lowerCallSig
import all Lanius.Faithful.Gen.SelfSrcC_lowerLoadType
import all Lanius.Faithful.Gen.SelfSrcC_lowerLocal
import all Lanius.Faithful.Gen.SelfSrcC_lowerSetValues
import all Lanius.Faithful.Gen.SelfSrcC_lowerShift
import all Lanius.Faithful.Gen.SelfSrcC_repeatType
import all Lanius.Faithful.Gen.SelfSrcC_shortCircuit
import all Lanius.Faithful.Gen.SelfSrcC_sintToUint
import all Lanius.Faithful.Gen.SelfSrcC_storeEvalWord
import all Lanius.Faithful.Gen.SelfSrcC_storeType
import all Lanius.Faithful.Gen.SelfSrcC_storeWordElement
import all Lanius.Faithful.Gen.SelfSrcC_widthOf
import all Lanius.Faithful.Gen.SelfSrcC_wordStride
import all Lanius.Faithful.Gen.SelfSrcF_lxExponent
import all Lanius.Faithful.Gen.SelfSrcF_lxLeadingDot
import all Lanius.Faithful.Gen.SelfSrcF_lxSpaceEnd
import all Lanius.Faithful.Gen.SelfSrcF_lxSymbolStart
import all Lanius.Faithful.Gen.SelfSrcF_wideLeftStmt
import all Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfTypes
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcType_size
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
def dpart10 : List SrcFunc := [(src_assigned 457 1001 1237 1238 1239 1240), (src_kill_shared 1241 1242), (src_Stmt_kills 302 1002 1238 1243 1244 1245), (src_Expr_agrees 483 682 700 1246 1247 1248 1249 1250 1251), (src_negate_constant 993), (src_binary_constant 1252 1253), (src_compare_constant 493 997), (src_constant_is), (src_args_agree 484 1003 1008), (src_MemWidth_bytes), (src_Word_number), (src_DivOp_number), (src_Syscall_number), (src_get_of_mini_selfhost_Arity 56 1013 1254), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Instr), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Instr), (src_BinOp_size), (src_Word_prefix), (src_MemWidth_prefix), (src_DivOp_size 75 1017), (src_FOp_size 75 106 1017 1255), (src_core_mem_size_of_of_mini_selfhost_List_u8), (src_le64 739 740), (src_slot_load 476 739 740 741 1256), (src_slot_store 476 739 740 741 1256), (src_BinOp_bytes 476 1257 1258 1259), (src_slot_compare 476 739 740 1257 1258 1260), (src_relative), (src_copy_bytes 75 76 84 476 1023 1024 1028), (src_arg_base 75 742), (src_fsp_save 476 739 740 741 1256), (src_fsp_load 476 739 740 741 1256), (src_slot_range 56 75 138 396 1032), (src_epilogue 739 740), (src_bump_bytes 476 739 740 1022 1261), (src_load_at_bytes 739 740), (src_store_at_bytes 476 739 740 741 1256), (src_load_word_bytes 476 739 740 1262), (src_store_word_bytes 476 739 740 741 1256 1262), (src_DivOp_bytes 476 739 740 1257 1258 1263 1264 1265), (src_FOp_bytes 476 1257 1266), (src_sys_bytes 75 476 739 740 741 1256 1267 1268 1269), (src_frame_memory_bytes 476 739 740 1022), (src_literal_below), (src_UintTy_bits), (src_lower_field_at 1270), (src_offset_or_arith 332 334 384 1047), (src_arith 332 333 385 787 789 790 797 1271 1272 1273 1274), (src_lower_shift 1047 1275), (src_arith_shift_right 333 385 1048 1272), (src_order 332 333 385 386 787 789 790 797 1272 1276 1277 1278 1279), (src_equality 232 332 787 789 1276 1280), (src_conjunction 332 381), (src_disjunction 332 381), (src_cast_to_i32 1281 1282), (src_cast_to_uint 1281 1283 1284), (src_cast_to_isize 1283 1285), (src_cast_to_float 1286 1287 1288 1289), (src_cast_to_sint 312 381 384 787 1056 1076 1077), (src_copy_field_at 1290), (src_concat_of_mini_selfhost_Expr 306 484 1060), (src_unbox_of_mini_selfhost_List_mini_selfhost_SrcArm 1291), (src_lower_arm 185 307 311 332), (src_arm_guard 188), (src_lower_set_value), (src_load_type 178 180 185 1082 1083 1292 1293), (src_eval_pick 120 185 307 332 333 334 1294), (src_eval_field_type 190 1295), (src_element_address 374 1296), (src_store_element 204 1068), (src_store_byte_element 204 1068), (src_store_word_element 120 190 801 802), (src_array_args 75 138 178 351 532 1072 1297 1298), (src_array_call_code 75 120 185 307 312), (src_FloatTy_sign_word), (src_FloatTy_sign_bit), (src_UintTy_is_wide), (src_norm 332 1299), (src_overflow_guard 75 332 1300), (src_unsigned_div), (src_word_stride 106 332), (src_store_one), (src_width_of 1301), (src_address_below 332), (src_get_of_mini_selfhost_Expr 56 484 1084), (src_store_types 75 106 120 178 197 801 1085), (src_store_cases 75 180 332 1085 1086 1302), (src_put_element 56 75 106 185 311 332 348 1087), (src_core_mem_size_of_of_mini_selfhost_List_u64), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcStructDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcEnumDecl), (src_lx_ident_start), (src_lx_ident_end 75 581 1303), (src_lx_digit), (src_lx_from_number), (src_lx_number 75 1304 1305 1306), (src_lx_space), (src_lx_space_end 75 581 1307), (src_lx_delimited), (src_lx_quoted 76 1308)]

def dents10 : List SigEntry := [some ([ty203, (.uint .usize), ty90], ty203), some ([ty203, (.uint .usize)], ty203), some ([ty94, (.uint .usize)], .bool), some ([ty90, ty90], .bool), some ([ty233], ty233), some ([ty51, ty52, ty233, ty233], ty233), some ([ty51, ty53, ty233, ty233], ty233), some ([ty233, (.uint .uint64)], .bool), some ([ty93, ty93], .bool), some ([ty54], (.uint .usize)), some ([ty51], (.uint .usize)), some ([ty55], (.uint .usize)), some ([ty59], (.uint .usize)), some ([ty161, (.uint .usize)], ty255), none, none, some ([ty52], (.uint .usize)), some ([ty51], (.uint .usize)), some ([ty54], (.uint .usize)), some ([ty55, ty51], (.uint .usize)), some ([ty58], (.uint .usize)), none, some ([(.uint .uint64)], ty67), some ([(.uint .usize)], ty67), some ([(.uint .usize)], ty67), some ([ty52, ty51, (.uint .usize)], ty67), some ([ty51, ty53, (.uint .usize)], ty67), some ([(.uint .usize), (.uint .usize)], .i32), some ([(.uint .usize), ty20, (.uint .usize)], ty67), some ([(.uint .usize)], (.uint .usize)), some ([(.uint .usize)], ty67), some ([(.uint .usize)], ty67), some ([(.uint .usize), (.uint .usize)], ty20), some ([], ty67), some ([(.uint .usize)], ty67), some ([], ty67), some ([(.uint .usize)], ty67), some ([ty54], ty67), some ([ty54, (.uint .usize)], ty67), some ([ty55, ty51, (.uint .usize)], ty67), some ([ty58, (.uint .usize)], ty67), some ([ty59, (.uint .usize)], ty67), some ([(.uint .usize)], ty67), some ([ty90, (.uint .uint64)], .bool), some ([ty4], (.uint .uint64)), some ([(.uint .usize), ty177], ty174), some ([ty52, ty173, ty173], ty174), some ([ty52, ty173, ty173], ty174), some ([ty52, ty173, ty173], ty174), some ([ty173, ty173], ty174), some ([ty53, ty173, ty173], ty174), some ([ty53, ty173, ty173], ty174), some ([ty173, ty173], ty174), some ([ty173, ty173], ty174), some ([ty173], ty174), some ([ty4, ty173], ty174), some ([ty173], ty174), some ([ty8, ty173], ty174), some ([ty4, ty173], ty174), some ([(.uint .usize), ty177, ty9], ty169), some ([ty93, ty93], ty93), some ([ty22], ty23), some ([(.uint .usize), (.uint .usize), (.uint .usize), ty90, ty169, ty23, ty145], ty145), some ([ty215, ty15], ty90), some ([(.uint .usize), ty172], ty145), some ([ty9, (.uint .usize), ty90, (.uint .usize), ty94], ty94), some ([(.uint .usize), ty9, (.uint .usize), (.uint .usize), ty175], ty176), some ([ty148, ty15, (.uint .usize), ty177], ty176), some ([ty146, ty172], ty172), some ([ty146, ty9, ty172, ty148, ty15], ty145), some ([ty146, ty9, ty172, ty148, ty15], ty145), some ([ty146, ty9, ty172, ty148, ty15], ty145), some ([ty148, ty212, ty71, (.uint .usize), (.uint .usize)], ty258), some ([(.uint .usize), (.uint .usize), ty100, ty257], ty176), some ([ty8], ty51), some ([ty8], (.uint .uint64)), some ([ty4], .bool), some ([ty4, ty90], ty90), some ([ty4, (.uint .usize)], ty90), some ([ty28], ty55), some ([(.uint .usize), (.uint .usize)], ty175), some ([ty54, ty90, ty172], ty145), some ([ty9], ty54), some ([ty90, (.uint .usize)], ty90), some ([ty93, (.uint .usize)], ty172), some ([ty71, ty93, (.uint .usize), ty90, (.uint .usize)], ty145), some ([ty90, ty93, (.uint .usize), ty90, (.uint .usize), (.uint .usize), ty75], ty145), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], ty94), none, none, none, some ([(.uint .usize)], .bool), some ([ty20, (.uint .usize)], (.uint .usize)), some ([(.uint .usize)], .bool), some ([(.uint .usize), ty279], ty223), some ([ty20, (.uint .usize)], ty279), some ([(.uint .usize)], .bool), some ([ty20, (.uint .usize)], (.uint .usize)), some ([(.uint .usize), (.uint .usize), ty280], ty223), some ([(.uint .usize), .bool, ty20, (.uint .usize)], ty280)]

/-- `declareFuncs` of functions 1000 to 1099. -/
theorem dchunk10 : declsStep dpart10 decls 35 59 35 56 = true := by decide +kernel

theorem dfit10 : entriesFit dpart10 dents10 = true := by decide +kernel

end Lanius.Faithful.SelfPure

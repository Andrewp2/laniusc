module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc1
public import Lanius.Faithful.Gen.SelfSrc3
public import Lanius.Faithful.Gen.SelfSrc4
public import Lanius.Faithful.Gen.SelfSrc6
public import Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
public import Lanius.Faithful.Gen.SelfSrcC_DivOp_size
public import Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
public import Lanius.Faithful.Gen.SelfSrcC_Inline_arithOf
public import Lanius.Faithful.Gen.SelfSrcC_Inline_lowerSetScalar
public import Lanius.Faithful.Gen.SelfSrcC_Lists_empty
public import Lanius.Faithful.Gen.SelfSrcC_SrcType_size
public import Lanius.Faithful.Gen.SelfSrcC_UintTy_half
public import Lanius.Faithful.Gen.SelfSrcC_Word_compute
public import Lanius.Faithful.Gen.SelfSrcC_Word_narrows
public import Lanius.Faithful.Gen.SelfSrcC_arithShiftRight
public import Lanius.Faithful.Gen.SelfSrcC_arithUint
public import Lanius.Faithful.Gen.SelfSrcC_arities
public import Lanius.Faithful.Gen.SelfSrcC_binaryConstant
public import Lanius.Faithful.Gen.SelfSrcC_bindingBytes
public import Lanius.Faithful.Gen.SelfSrcC_callAgrees
public import Lanius.Faithful.Gen.SelfSrcC_declareProgram
public import Lanius.Faithful.Gen.SelfSrcC_elementBase
public import Lanius.Faithful.Gen.SelfSrcC_extentAfter
public import Lanius.Faithful.Gen.SelfSrcC_floatApply
public import Lanius.Faithful.Gen.SelfSrcC_iteThen
public import Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
public import Lanius.Faithful.Gen.SelfSrcC_longer
public import Lanius.Faithful.Gen.SelfSrcC_lowerLoadType
public import Lanius.Faithful.Gen.SelfSrcC_lowerLocal
public import Lanius.Faithful.Gen.SelfSrcC_sintToUint
public import Lanius.Faithful.Gen.SelfSrcC_substAll
public import Lanius.Faithful.Gen.SelfSrcC_wordWidth
public import Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
public import Lanius.Faithful.Gen.SelfSrcF_Inline_lxAfterFractionAt
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pBitAnd
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pExpr
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pLeTail
public import Lanius.Faithful.Gen.SelfSrcF_consTys
public import Lanius.Faithful.Gen.SelfSrcF_genericOpen
public import Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
public import Lanius.Faithful.Gen.SelfSrcF_litIf
public import Lanius.Faithful.Gen.SelfSrcF_lxBlockEnd
public import Lanius.Faithful.Gen.SelfSrcF_lxCanonicalKind
public import Lanius.Faithful.Gen.SelfSrcF_lxDotAt
public import Lanius.Faithful.Gen.SelfSrcF_lxExponent
public import Lanius.Faithful.Gen.SelfSrcF_lxSymbolStart
public import Lanius.Faithful.Gen.SelfSrcF_paramGoals
public import Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc1
import all Lanius.Faithful.Gen.SelfSrc3
import all Lanius.Faithful.Gen.SelfSrc4
import all Lanius.Faithful.Gen.SelfSrc6
import all Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
import all Lanius.Faithful.Gen.SelfSrcC_DivOp_size
import all Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
import all Lanius.Faithful.Gen.SelfSrcC_Inline_arithOf
import all Lanius.Faithful.Gen.SelfSrcC_Inline_lowerSetScalar
import all Lanius.Faithful.Gen.SelfSrcC_Lists_empty
import all Lanius.Faithful.Gen.SelfSrcC_SrcType_size
import all Lanius.Faithful.Gen.SelfSrcC_UintTy_half
import all Lanius.Faithful.Gen.SelfSrcC_Word_compute
import all Lanius.Faithful.Gen.SelfSrcC_Word_narrows
import all Lanius.Faithful.Gen.SelfSrcC_arithShiftRight
import all Lanius.Faithful.Gen.SelfSrcC_arithUint
import all Lanius.Faithful.Gen.SelfSrcC_arities
import all Lanius.Faithful.Gen.SelfSrcC_binaryConstant
import all Lanius.Faithful.Gen.SelfSrcC_bindingBytes
import all Lanius.Faithful.Gen.SelfSrcC_callAgrees
import all Lanius.Faithful.Gen.SelfSrcC_declareProgram
import all Lanius.Faithful.Gen.SelfSrcC_elementBase
import all Lanius.Faithful.Gen.SelfSrcC_extentAfter
import all Lanius.Faithful.Gen.SelfSrcC_floatApply
import all Lanius.Faithful.Gen.SelfSrcC_iteThen
import all Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
import all Lanius.Faithful.Gen.SelfSrcC_longer
import all Lanius.Faithful.Gen.SelfSrcC_lowerLoadType
import all Lanius.Faithful.Gen.SelfSrcC_lowerLocal
import all Lanius.Faithful.Gen.SelfSrcC_sintToUint
import all Lanius.Faithful.Gen.SelfSrcC_substAll
import all Lanius.Faithful.Gen.SelfSrcC_wordWidth
import all Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_lxAfterFractionAt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pBitAnd
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pExpr
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pLeTail
import all Lanius.Faithful.Gen.SelfSrcF_consTys
import all Lanius.Faithful.Gen.SelfSrcF_genericOpen
import all Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
import all Lanius.Faithful.Gen.SelfSrcF_litIf
import all Lanius.Faithful.Gen.SelfSrcF_lxBlockEnd
import all Lanius.Faithful.Gen.SelfSrcF_lxCanonicalKind
import all Lanius.Faithful.Gen.SelfSrcF_lxDotAt
import all Lanius.Faithful.Gen.SelfSrcF_lxExponent
import all Lanius.Faithful.Gen.SelfSrcF_lxSymbolStart
import all Lanius.Faithful.Gen.SelfSrcF_paramGoals
import all Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfTypes
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.arithShiftRight
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

/-- Functions 1200 to 1299, and their signature entries. -/
def dpart12 : List SrcFunc := [(src_fn_bounds_ok 155 1393 1394 1395), (src_ref_checked 1396 1397), (src_func_params 1398), (src_self_ref_id 1399), (src_boxed_of_mini_selfhost_List_mini_selfhost_MParam 50 1180 1400), (src_field_tys 1154 1401 1402), (src_BinOp_folds), (src_Word_compute 977 1403), (src_BinOp_annihilates), (src_BinOp_commutes), (src_Word_same_operand 977), (src_BinOp_unit), (src_Word_keeps 1404), (src_CmpOp_test), (src_signed_key 977), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Fact), (src_Expr_is_atom), (src_Expr_mentions 474 1217), (src_cons_of_mini_selfhost_Fact 1405), (src_trim_facts 1406 1407), (src_kill_prefix 56 276 983 1220 1408 1409), (src_dying_extent 75 983 1221 1410 1411), (src_Stmt_ignores 298 1217 1222 1224), (src_Stmt_jumps 298 1223), (src_mentions_any 475 1217 1224), (src_Expr_is_constant 991), (src_neg_agrees 474 987), (src_binary_agrees 474 987 994 1412), (src_unit_agrees 987 1209 1212 1413), (src_compare_agrees 474 987 994 1414), (src_fp_agrees 474 987 1415), (src_fold_constant 1206 1207), (src_absorbed 1208), (src_unbox_of_mini_selfhost_List_mini_selfhost_Arity 724), (src_FloatTy_rex_size), (src_slot_offset 75 105), (src_slot_operands 467 726 727 1007), (src_Word_rex 110 727), (src_BinOp_opcode 726 727), (src_CmpOp_setcc 1416 1417), (src_pow2 56 1240), (src_MemWidth_rex 110 727), (src_DivOp_extend 467 726 727 1237), (src_DivOp_opcode 726 727), (src_DivOp_result 110 726 727), (src_FOp_opcode_bytes 467 726 727 1237 1418 1419 1420 1421 1422), (src_syscall_rsi_bytes 726 727), (src_syscall_linux_byte), (src_syscall_linux_high), (src_lower_scalar_slot 308), (src_float_arith 1423), (src_SrcType_is_sint_any), (src_arith_sint 1424), (src_arith_uint 1425), (src_SrcType_is_integer), (src_float_order 1426), (src_sign_key 328), (src_order_sint 1427), (src_order_uint 1428), (src_SrcType_word 1268), (src_wrap 328 735 1060), (src_sint_to_i32 1060 1260), (src_from_i32 328 1060 1260), (src_sint_to_uint 1060 1260 1262), (src_sint_to_wide 1060 1262), (src_int_to_float 328), (src_if_narrow 1060), (src_float_to_float 328), (src_UintTy_signed_word 1060), (src_copy_slots 120 231 344), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcArm), (src_load_types 75 105 120 178 1049 1271), (src_load_cases 75 180 184 328 1271 1272), (src_pick_element 56 75 105 184 307 328 344 1273), (src_eval_sized 120 757), (src_element_at 328 329 330), (src_array_arg 187 189 198 1429 1430), (src_arg_bytes 198 1431), (src_UintTy_spare), (src_UintTy_least_bits), (src_word_width 1432), (src_ite_then 184), (src_lx_ident_run 76 1433), (src_lx_prefixed_base 75 800 1434 1435), (src_lx_digit_run 76 569 1436), (src_lx_finish_decimal 800 1437), (src_lx_space_run 76 1438), (src_lx_quoted_at 75 1082), (src_lx_symbol_at 75 800 1439 1440), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_RawTok), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Token), (src_lx_as_text 367 387), (src_lx_keyword_at 904 1091), (src_unbox_of_mini_selfhost_List_mini_selfhost_SymRule 1087), (src_p_member_type_args_some), (src_generic_open 166 1441 1442), (src_p_member_type_args_none), (src_p_block_stmt), (src_opens_block 1443), (src_p_expr_stmt)]

def dents12 : List SigEntry := [some ([(.uint .usize), ty127, ty110, ty271], .bool), some ([ty229, ty238], ty229), some ([(.uint .usize), ty271, ty289, ty272, ty84, ty84], ty229), some ([ty271, ty85], ty238), some ([ty186], ty185), some ([(.uint .usize), ty127, (.uint .usize), ty153], ty248), some ([ty52], .bool), some ([ty51, ty52, (.uint .uint64), (.uint .uint64)], (.uint .uint64)), some ([ty52], .bool), some ([ty52], .bool), some ([ty51, (.uint .uint64), (.uint .uint64)], .bool), some ([ty52], (.uint .uint64)), some ([ty51, ty90], .bool), some ([ty53, (.uint .uint64), (.uint .uint64)], .bool), some ([(.uint .uint64)], (.uint .uint64)), none, some ([ty90], .bool), some ([ty90, (.uint .usize)], .bool), some ([ty201, ty203], ty203), some ([ty203], ty203), some ([ty203, (.uint .usize), (.uint .usize)], ty203), some ([ty203, (.uint .usize), (.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty94, (.uint .usize)], .bool), some ([ty94], .bool), some ([ty93, (.uint .usize)], .bool), some ([ty90, ty231], .bool), some ([ty90, ty90], .bool), some ([ty51, ty52, ty90, ty90, ty90], .bool), some ([ty51, ty52, ty90, ty90, ty90], .bool), some ([ty51, ty53, ty90, ty90, ty90], .bool), some ([ty58, ty90, ty90, ty90], .bool), some ([ty51, ty52, (.uint .uint64), (.uint .uint64)], ty231), some ([ty52, (.uint .uint64)], ty231), some ([ty160], ty161), some ([ty8], (.uint .usize)), some ([(.uint .usize)], .i32), some ([(.uint .usize)], ty67), some ([ty51], ty67), some ([ty52], ty67), some ([ty53, ty51], (.uint .uint8)), some ([(.uint .usize)], (.uint .uint64)), some ([ty54], ty67), some ([ty55, ty51], ty67), some ([ty55], ty67), some ([ty55], ty67), some ([ty58], ty67), some ([ty59], ty67), some ([ty59], (.uint .uint8)), some ([ty59], (.uint .uint8)), some ([(.uint .usize), ty9], ty174), some ([ty52, ty173, ty173, ty256], ty174), some ([ty9], .bool), some ([ty52, ty173, ty173, ty234], ty174), some ([ty52, ty173, ty173, ty234], ty174), some ([ty9], .bool), some ([ty53, ty173, ty173, ty256], ty174), some ([ty90], ty90), some ([ty53, ty173, ty173, ty234], ty174), some ([ty53, ty173, ty173, ty234], ty174), some ([ty9], ty51), some ([ty4, ty90], ty90), some ([ty4, ty90], ty90), some ([ty4, ty90], ty90), some ([ty4, ty4, ty90], ty90), some ([ty4, ty90], ty90), some ([ty8, ty51, ty90], ty174), some ([ty4, ty174], ty174), some ([ty8, ty8, ty90], ty174), some ([ty4], ty51), some ([(.uint .usize), ty9, ty9], ty169), none, some ([ty71, (.uint .usize), ty90, (.uint .usize), ty94], ty94), some ([(.uint .usize), ty90, (.uint .usize), (.uint .usize), ty75], ty94), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], ty94), some ([(.uint .usize), ty9, ty169], ty176), some ([(.uint .usize), ty9, ty90], ty172), some ([ty148, ty29, ty9, (.uint .usize), (.uint .usize), ty255], ty255), some ([ty148, ty29], (.uint .usize)), some ([ty4], (.uint .uint64)), some ([ty4], (.uint .uint64)), some ([ty9], ty275), some ([ty90, ty145, ty145], ty145), some ([ty20], (.uint .usize)), some ([ty20, (.uint .usize)], ty238), some ([ty20, (.uint .usize), (.uint .usize)], ty277), some ([ty20, (.uint .usize)], ty276), some ([ty20], (.uint .usize)), some ([(.uint .usize), .bool, (.uint .usize), ty20, (.uint .usize)], ty277), some ([ty220, ty20, (.uint .usize), (.uint .usize)], ty221), none, none, some ([], ty20), some ([ty20, ty218, ty220], ty238), some ([ty219], ty220), some ([], (.uint .usize)), some ([ty44], .bool), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty44], .bool), some ([], (.uint .usize))]

/-- `declareFuncs` of functions 1200 to 1299. -/
theorem dchunk12 : declsStep dpart12 decls 30 50 30 50 = true := by decide +kernel

theorem dfit12 : entriesFit dpart12 dents12 = true := by decide +kernel

end Lanius.Faithful.SelfPure

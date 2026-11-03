module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc1
public import Lanius.Faithful.Gen.SelfSrc4
public import Lanius.Faithful.Gen.SelfSrc5
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
public import Lanius.Faithful.Gen.SelfSrcF_consTys
public import Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
public import Lanius.Faithful.Gen.SelfSrcF_litIf
public import Lanius.Faithful.Gen.SelfSrcF_lxBlockEnd
public import Lanius.Faithful.Gen.SelfSrcF_lxDotAt
public import Lanius.Faithful.Gen.SelfSrcF_lxExponent
public import Lanius.Faithful.Gen.SelfSrcF_lxSymbolStart
public import Lanius.Faithful.Gen.SelfSrcF_paramGoals
public import Lanius.Faithful.Gen.SelfSrcF_projectionRet
public import Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc1
import all Lanius.Faithful.Gen.SelfSrc4
import all Lanius.Faithful.Gen.SelfSrc5
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
import all Lanius.Faithful.Gen.SelfSrcF_consTys
import all Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
import all Lanius.Faithful.Gen.SelfSrcF_litIf
import all Lanius.Faithful.Gen.SelfSrcF_lxBlockEnd
import all Lanius.Faithful.Gen.SelfSrcF_lxDotAt
import all Lanius.Faithful.Gen.SelfSrcF_lxExponent
import all Lanius.Faithful.Gen.SelfSrcF_lxSymbolStart
import all Lanius.Faithful.Gen.SelfSrcF_paramGoals
import all Lanius.Faithful.Gen.SelfSrcF_projectionRet
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

/-- Functions 1200 to 1299, and their signature entries. -/
def dpart12 : List SrcFunc := [(src_params_of 104 1390 1391), (src_empty_of_mini_selfhost_Local), (src_result_of 152 155 1392 1393 1394 1395 1396), (src_never_ret 152 155 1393 1394), (src_last_ty 646 1204), (src_boxed_of_mini_selfhost_MStmt 50 1189 1397), (src_boxed_of_mini_selfhost_List_mini_selfhost_MEff 50 1387 1398), (src_param_effs 954 1207 1399 1400), (src_ret_expected), (src_fn_bounds_ok 155 1401 1402 1403), (src_ref_checked 1404 1405), (src_func_params 1406), (src_self_ref_id 1407), (src_boxed_of_mini_selfhost_List_mini_selfhost_MParam 50 1188 1408), (src_field_tys 1161 1409 1410), (src_BinOp_folds), (src_Word_compute 983 1411), (src_BinOp_annihilates), (src_BinOp_commutes), (src_Word_same_operand 983), (src_BinOp_unit), (src_Word_keeps 1412), (src_CmpOp_test), (src_signed_key 983), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Fact), (src_Expr_is_atom), (src_Expr_mentions 478 1226), (src_cons_of_mini_selfhost_Fact 1413), (src_trim_facts 1414 1415), (src_kill_prefix 56 278 989 1229 1416 1417), (src_dying_extent 75 989 1230 1418 1419), (src_Stmt_ignores 301 1226 1231 1233), (src_Stmt_jumps 301 1232), (src_mentions_any 479 1226 1233), (src_Expr_is_constant 997), (src_neg_agrees 478 993), (src_binary_agrees 478 993 1000 1420), (src_unit_agrees 993 1218 1221 1421), (src_compare_agrees 478 993 1000 1422), (src_fp_agrees 478 993 1423), (src_fold_constant 1215 1216), (src_absorbed 1217), (src_unbox_of_mini_selfhost_List_mini_selfhost_Arity 729), (src_FloatTy_rex_size), (src_slot_offset 75 106), (src_slot_operands 471 731 732 1013), (src_Word_rex 84 732), (src_BinOp_opcode 731 732), (src_CmpOp_setcc 1424 1425), (src_pow2 56 1249), (src_MemWidth_rex 84 732), (src_DivOp_extend 471 731 732 1246), (src_DivOp_opcode 731 732), (src_DivOp_result 84 731 732), (src_FOp_opcode_bytes 471 731 732 1246 1426 1427 1428 1429 1430), (src_syscall_rsi_bytes 731 732), (src_syscall_linux_byte), (src_syscall_linux_high), (src_lower_scalar_slot 311), (src_float_arith 1431), (src_SrcType_is_sint_any), (src_arith_sint 1432), (src_arith_uint 1433), (src_SrcType_is_integer), (src_float_order 1434), (src_sign_key 331), (src_order_sint 1435), (src_order_uint 1436), (src_SrcType_word 1277), (src_wrap 331 740 1066), (src_sint_to_i32 1066 1269), (src_from_i32 331 1066 1269), (src_sint_to_uint 1066 1269 1271), (src_sint_to_wide 1066 1271), (src_int_to_float 331), (src_if_narrow 1066), (src_float_to_float 331), (src_UintTy_signed_word 1066), (src_copy_slots 120 232 347), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcArm), (src_load_types 75 106 120 178 1055 1280), (src_load_cases 75 180 185 331 1280 1281), (src_pick_element 56 75 106 185 310 331 347 1282), (src_eval_sized 120 762), (src_element_at 331 332 333), (src_array_arg 188 190 199 1437 1438), (src_arg_bytes 199 1439), (src_UintTy_spare), (src_UintTy_least_bits), (src_word_width 1440), (src_ite_then 185), (src_lx_ident_run 76 1441), (src_lx_prefixed_base 75 805 1442 1443), (src_lx_digit_run 76 573 1444), (src_lx_finish_decimal 805 1445), (src_lx_space_run 76 1446), (src_lx_quoted_at 75 1088), (src_lx_symbol_at 75 805 1447 1448), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_RawTok), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Token)]

def dents12 : List SigEntry := [some ([(.uint .usize), ty271, ty110, ty287, ty85], ty289), some ([], ty287), some ([(.uint .usize), ty271, ty84], ty272), some ([ty110], .bool), some ([ty153], ty247), some ([ty192], ty188), some ([ty282], ty189), some ([ty186], ty282), some ([ty272], ty247), some ([(.uint .usize), ty127, ty110, ty271], .bool), some ([ty229, ty238], ty229), some ([(.uint .usize), ty271, ty289, ty272, ty84, ty84], ty229), some ([ty271, ty85], ty238), some ([ty186], ty185), some ([(.uint .usize), ty127, (.uint .usize), ty153], ty248), some ([ty52], .bool), some ([ty51, ty52, (.uint .uint64), (.uint .uint64)], (.uint .uint64)), some ([ty52], .bool), some ([ty52], .bool), some ([ty51, (.uint .uint64), (.uint .uint64)], .bool), some ([ty52], (.uint .uint64)), some ([ty51, ty90], .bool), some ([ty53, (.uint .uint64), (.uint .uint64)], .bool), some ([(.uint .uint64)], (.uint .uint64)), none, some ([ty90], .bool), some ([ty90, (.uint .usize)], .bool), some ([ty201, ty203], ty203), some ([ty203], ty203), some ([ty203, (.uint .usize), (.uint .usize)], ty203), some ([ty203, (.uint .usize), (.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty94, (.uint .usize)], .bool), some ([ty94], .bool), some ([ty93, (.uint .usize)], .bool), some ([ty90, ty231], .bool), some ([ty90, ty90], .bool), some ([ty51, ty52, ty90, ty90, ty90], .bool), some ([ty51, ty52, ty90, ty90, ty90], .bool), some ([ty51, ty53, ty90, ty90, ty90], .bool), some ([ty58, ty90, ty90, ty90], .bool), some ([ty51, ty52, (.uint .uint64), (.uint .uint64)], ty231), some ([ty52, (.uint .uint64)], ty231), some ([ty160], ty161), some ([ty8], (.uint .usize)), some ([(.uint .usize)], .i32), some ([(.uint .usize)], ty67), some ([ty51], ty67), some ([ty52], ty67), some ([ty53, ty51], (.uint .uint8)), some ([(.uint .usize)], (.uint .uint64)), some ([ty54], ty67), some ([ty55, ty51], ty67), some ([ty55], ty67), some ([ty55], ty67), some ([ty58], ty67), some ([ty59], ty67), some ([ty59], (.uint .uint8)), some ([ty59], (.uint .uint8)), some ([(.uint .usize), ty9], ty174), some ([ty52, ty173, ty173, ty256], ty174), some ([ty9], .bool), some ([ty52, ty173, ty173, ty234], ty174), some ([ty52, ty173, ty173, ty234], ty174), some ([ty9], .bool), some ([ty53, ty173, ty173, ty256], ty174), some ([ty90], ty90), some ([ty53, ty173, ty173, ty234], ty174), some ([ty53, ty173, ty173, ty234], ty174), some ([ty9], ty51), some ([ty4, ty90], ty90), some ([ty4, ty90], ty90), some ([ty4, ty90], ty90), some ([ty4, ty4, ty90], ty90), some ([ty4, ty90], ty90), some ([ty8, ty51, ty90], ty174), some ([ty4, ty174], ty174), some ([ty8, ty8, ty90], ty174), some ([ty4], ty51), some ([(.uint .usize), ty9, ty9], ty169), none, some ([ty71, (.uint .usize), ty90, (.uint .usize), ty94], ty94), some ([(.uint .usize), ty90, (.uint .usize), (.uint .usize), ty75], ty94), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], ty94), some ([(.uint .usize), ty9, ty169], ty176), some ([(.uint .usize), ty9, ty90], ty172), some ([ty148, ty29, ty9, (.uint .usize), (.uint .usize), ty255], ty255), some ([ty148, ty29], (.uint .usize)), some ([ty4], (.uint .uint64)), some ([ty4], (.uint .uint64)), some ([ty9], ty275), some ([ty90, ty145, ty145], ty145), some ([ty20], (.uint .usize)), some ([ty20, (.uint .usize)], ty238), some ([ty20, (.uint .usize), (.uint .usize)], ty277), some ([ty20, (.uint .usize)], ty276), some ([ty20], (.uint .usize)), some ([(.uint .usize), .bool, (.uint .usize), ty20, (.uint .usize)], ty277), some ([ty220, ty20, (.uint .usize), (.uint .usize)], ty221), none, none]

/-- `declareFuncs` of functions 1200 to 1299. -/
theorem dchunk12 : declsStep dpart12 decls 31 51 31 51 = true := by decide +kernel

theorem dfit12 : entriesFit dpart12 dents12 = true := by decide +kernel

end Lanius.Faithful.SelfPure

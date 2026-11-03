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
public import Lanius.Faithful.Gen.SelfSrcC_SrcType_same
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
public import Lanius.Faithful.Gen.SelfSrcF_consTys
public import Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
public import Lanius.Faithful.Gen.SelfSrcF_litIf
public import Lanius.Faithful.Gen.SelfSrcF_lxBlockEnd
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
import all Lanius.Faithful.Gen.SelfSrcC_SrcType_same
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
import all Lanius.Faithful.Gen.SelfSrcF_consTys
import all Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
import all Lanius.Faithful.Gen.SelfSrcF_litIf
import all Lanius.Faithful.Gen.SelfSrcF_lxBlockEnd
import all Lanius.Faithful.Gen.SelfSrcF_lxExponent
import all Lanius.Faithful.Gen.SelfSrcF_lxSymbolStart
import all Lanius.Faithful.Gen.SelfSrcF_paramGoals
import all Lanius.Faithful.Gen.SelfSrcF_projectionRet
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

/-- Functions 1200 to 1299, and their signature entries. -/
def dpart12 : List SrcFunc := [(src_never_ret 152 155 1398 1399), (src_last_ty 656 1201), (src_boxed_of_mini_selfhost_MStmt 50 1186 1402), (src_boxed_of_mini_selfhost_List_mini_selfhost_MEff 50 1392 1403), (src_param_effs 964 1204 1404 1405), (src_ret_expected), (src_fn_bounds_ok 155 1406 1407 1408), (src_ref_checked 1409 1410), (src_func_params 1411), (src_self_ref_id 1412), (src_boxed_of_mini_selfhost_List_mini_selfhost_MParam 50 1185 1413), (src_field_tys 1158 1414 1415), (src_BinOp_folds), (src_Word_compute 993 1416), (src_BinOp_annihilates), (src_BinOp_commutes), (src_Word_same_operand 993), (src_BinOp_unit), (src_Word_keeps 1417), (src_CmpOp_test), (src_signed_key 993), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Fact), (src_Expr_is_atom), (src_Expr_mentions 484 1223), (src_cons_of_mini_selfhost_Fact 1418), (src_trim_facts 1419 1420), (src_kill_prefix 56 279 999 1226 1421 1422), (src_dying_extent 75 999 1227 1423 1424), (src_Stmt_ignores 301 1223 1228 1230), (src_Stmt_jumps 301 1229), (src_mentions_any 485 1223 1230), (src_Expr_is_constant 1007), (src_neg_agrees 484 1003), (src_binary_agrees 484 1003 1010 1425), (src_unit_agrees 1003 1215 1218 1426), (src_compare_agrees 484 1003 1010 1427), (src_fp_agrees 484 1003 1428), (src_fold_constant 1212 1213), (src_absorbed 1214), (src_unbox_of_mini_selfhost_List_mini_selfhost_Arity 739), (src_FloatTy_rex_size), (src_core_mem_size_of_of_mini_selfhost_List_u8), (src_le64 1022 1023), (src_slot_load 740 1022 1023 1024 1429), (src_slot_store 740 1022 1023 1024 1429), (src_BinOp_bytes 740 1430 1431 1432), (src_slot_compare 740 1022 1023 1430 1431 1433), (src_relative), (src_copy_bytes 75 76 110 740 1243 1244 1248), (src_arg_base 75 1025), (src_fsp_save 740 1022 1023 1024 1429), (src_fsp_load 740 1022 1023 1024 1429), (src_slot_range 56 75 138 397 1252), (src_epilogue 1022 1023), (src_bump_bytes 740 1022 1023 1242 1434), (src_load_at_bytes 1022 1023), (src_store_at_bytes 740 1022 1023 1024 1429), (src_load_word_bytes 740 1022 1023 1435), (src_store_word_bytes 740 1022 1023 1024 1429 1435), (src_DivOp_bytes 740 1022 1023 1430 1431 1436 1437 1438), (src_FOp_bytes 740 1430 1439), (src_sys_bytes 75 740 1022 1023 1024 1429 1440 1441 1442), (src_frame_memory_bytes 740 1022 1023 1242), (src_lower_scalar_slot 311), (src_float_arith 1443), (src_SrcType_is_sint_any), (src_arith_sint 1444), (src_arith_uint 1445), (src_SrcType_is_integer), (src_float_order 1446), (src_sign_key 331), (src_order_sint 1447), (src_order_uint 1448), (src_SrcType_word 1282), (src_wrap 331 746 1061), (src_sint_to_i32 1061 1274), (src_from_i32 331 1061 1274), (src_sint_to_uint 1061 1274 1276), (src_sint_to_wide 1061 1276), (src_int_to_float 331), (src_if_narrow 1061), (src_float_to_float 331), (src_UintTy_signed_word 1061), (src_copy_slots 120 232 347), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcArm), (src_load_types 75 105 120 178 1050 1285), (src_load_cases 75 180 185 331 1285 1286), (src_pick_element 56 75 105 185 310 331 347 1287), (src_eval_sized 120 768), (src_element_at 331 332 333), (src_array_arg 188 190 199 1449 1450), (src_arg_bytes 199 1451), (src_UintTy_spare), (src_UintTy_least_bits), (src_word_width 1452), (src_ite_then 185), (src_lx_ident_run 76 1453), (src_lx_prefixed_base 75 815 1454 1455), (src_lx_digit_run 76 583 1456), (src_lx_finish_decimal 815 1457)]

def dents12 : List SigEntry := [some ([ty110], .bool), some ([ty153], ty250), some ([ty193], ty189), some ([ty286], ty190), some ([ty187], ty286), some ([ty276], ty250), some ([(.uint .usize), ty127, ty110, ty275], .bool), some ([ty231, ty163], ty231), some ([(.uint .usize), ty275, ty293, ty276, ty84, ty84], ty231), some ([ty275, ty85], ty163), some ([ty187], ty186), some ([(.uint .usize), ty127, (.uint .usize), ty153], ty251), some ([ty54], .bool), some ([ty53, ty54, (.uint .uint64), (.uint .uint64)], (.uint .uint64)), some ([ty54], .bool), some ([ty54], .bool), some ([ty53, (.uint .uint64), (.uint .uint64)], .bool), some ([ty54], (.uint .uint64)), some ([ty53, ty90], .bool), some ([ty55, (.uint .uint64), (.uint .uint64)], .bool), some ([(.uint .uint64)], (.uint .uint64)), none, some ([ty90], .bool), some ([ty90, (.uint .usize)], .bool), some ([ty202, ty204], ty204), some ([ty204], ty204), some ([ty204, (.uint .usize), (.uint .usize)], ty204), some ([ty204, (.uint .usize), (.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty94, (.uint .usize)], .bool), some ([ty94], .bool), some ([ty93, (.uint .usize)], .bool), some ([ty90, ty233], .bool), some ([ty90, ty90], .bool), some ([ty53, ty54, ty90, ty90, ty90], .bool), some ([ty53, ty54, ty90, ty90, ty90], .bool), some ([ty53, ty55, ty90, ty90, ty90], .bool), some ([ty60, ty90, ty90, ty90], .bool), some ([ty53, ty54, (.uint .uint64), (.uint .uint64)], ty233), some ([ty54, (.uint .uint64)], ty233), some ([ty160], ty161), some ([ty8], (.uint .usize)), none, some ([(.uint .uint64)], ty35), some ([(.uint .usize)], ty35), some ([(.uint .usize)], ty35), some ([ty54, ty53, (.uint .usize)], ty35), some ([ty53, ty55, (.uint .usize)], ty35), some ([(.uint .usize), (.uint .usize)], .i32), some ([(.uint .usize), ty20, (.uint .usize)], ty35), some ([(.uint .usize)], (.uint .usize)), some ([(.uint .usize)], ty35), some ([(.uint .usize)], ty35), some ([(.uint .usize), (.uint .usize)], ty20), some ([], ty35), some ([(.uint .usize)], ty35), some ([], ty35), some ([(.uint .usize)], ty35), some ([ty56], ty35), some ([ty56, (.uint .usize)], ty35), some ([ty57, ty53, (.uint .usize)], ty35), some ([ty60, (.uint .usize)], ty35), some ([ty61, (.uint .usize)], ty35), some ([(.uint .usize)], ty35), some ([(.uint .usize), ty9], ty175), some ([ty54, ty174, ty174, ty259], ty175), some ([ty9], .bool), some ([ty54, ty174, ty174, ty237], ty175), some ([ty54, ty174, ty174, ty237], ty175), some ([ty9], .bool), some ([ty55, ty174, ty174, ty259], ty175), some ([ty90], ty90), some ([ty55, ty174, ty174, ty237], ty175), some ([ty55, ty174, ty174, ty237], ty175), some ([ty9], ty53), some ([ty4, ty90], ty90), some ([ty4, ty90], ty90), some ([ty4, ty90], ty90), some ([ty4, ty4, ty90], ty90), some ([ty4, ty90], ty90), some ([ty8, ty53, ty90], ty175), some ([ty4, ty175], ty175), some ([ty8, ty8, ty90], ty175), some ([ty4], ty53), some ([(.uint .usize), ty9, ty9], ty170), none, some ([ty71, (.uint .usize), ty90, (.uint .usize), ty94], ty94), some ([(.uint .usize), ty90, (.uint .usize), (.uint .usize), ty75], ty94), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], ty94), some ([(.uint .usize), ty9, ty170], ty177), some ([(.uint .usize), ty9, ty90], ty173), some ([ty148, ty29, ty9, (.uint .usize), (.uint .usize), ty258], ty258), some ([ty148, ty29], (.uint .usize)), some ([ty4], (.uint .uint64)), some ([ty4], (.uint .uint64)), some ([ty9], ty279), some ([ty90, ty145, ty145], ty145), some ([ty20], (.uint .usize)), some ([ty20, (.uint .usize)], ty163), some ([ty20, (.uint .usize), (.uint .usize)], ty281), some ([ty20, (.uint .usize)], ty280)]

/-- `declareFuncs` of functions 1200 to 1299. -/
theorem dchunk12 : declsStep dpart12 decls 31 51 31 51 = true := by decide +kernel

theorem dfit12 : entriesFit dpart12 dents12 = true := by decide +kernel

end Lanius.Faithful.SelfPure

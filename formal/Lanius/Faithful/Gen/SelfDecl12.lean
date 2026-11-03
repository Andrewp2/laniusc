module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc0
public import Lanius.Faithful.Gen.SelfSrc1
public import Lanius.Faithful.Gen.SelfSrc3
public import Lanius.Faithful.Gen.SelfSrc4
public import Lanius.Faithful.Gen.SelfSrc5
public import Lanius.Faithful.Gen.SelfSrc6
public import Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
public import Lanius.Faithful.Gen.SelfSrcC_DivOp_size
public import Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
public import Lanius.Faithful.Gen.SelfSrcC_Inline_arithOf
public import Lanius.Faithful.Gen.SelfSrcC_Inline_lowerSetScalar
public import Lanius.Faithful.Gen.SelfSrcC_Lists_empty
public import Lanius.Faithful.Gen.SelfSrcC_SrcType_same
public import Lanius.Faithful.Gen.SelfSrcC_UintTy_half
public import Lanius.Faithful.Gen.SelfSrcC_Word_compute
public import Lanius.Faithful.Gen.SelfSrcC_Word_narrows
public import Lanius.Faithful.Gen.SelfSrcC_arithShiftRight
public import Lanius.Faithful.Gen.SelfSrcC_arithUint
public import Lanius.Faithful.Gen.SelfSrcC_arities
public import Lanius.Faithful.Gen.SelfSrcC_binaryConstant
public import Lanius.Faithful.Gen.SelfSrcC_callAgrees
public import Lanius.Faithful.Gen.SelfSrcC_declareProgram
public import Lanius.Faithful.Gen.SelfSrcC_extentAfter
public import Lanius.Faithful.Gen.SelfSrcC_floatApply
public import Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
public import Lanius.Faithful.Gen.SelfSrcC_longer
public import Lanius.Faithful.Gen.SelfSrcC_lowerLocal
public import Lanius.Faithful.Gen.SelfSrcC_sintToUint
public import Lanius.Faithful.Gen.SelfSrcC_substAll
public import Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
public import Lanius.Faithful.Gen.SelfSrcF_collect
public import Lanius.Faithful.Gen.SelfSrcF_consTys
public import Lanius.Faithful.Gen.SelfSrcF_effNamedTys
public import Lanius.Faithful.Gen.SelfSrcF_externBody
public import Lanius.Faithful.Gen.SelfSrcF_findConst
public import Lanius.Faithful.Gen.SelfSrcF_funcsOnto
public import Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
public import Lanius.Faithful.Gen.SelfSrcF_joinInsts
public import Lanius.Faithful.Gen.SelfSrcF_litIf
public import Lanius.Faithful.Gen.SelfSrcF_paramGoals
public import Lanius.Faithful.Gen.SelfSrcF_projectionRet
public import Lanius.Faithful.Gen.SelfSrcF_readInst
public import Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc0
import all Lanius.Faithful.Gen.SelfSrc1
import all Lanius.Faithful.Gen.SelfSrc3
import all Lanius.Faithful.Gen.SelfSrc4
import all Lanius.Faithful.Gen.SelfSrc5
import all Lanius.Faithful.Gen.SelfSrc6
import all Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
import all Lanius.Faithful.Gen.SelfSrcC_DivOp_size
import all Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
import all Lanius.Faithful.Gen.SelfSrcC_Inline_arithOf
import all Lanius.Faithful.Gen.SelfSrcC_Inline_lowerSetScalar
import all Lanius.Faithful.Gen.SelfSrcC_Lists_empty
import all Lanius.Faithful.Gen.SelfSrcC_SrcType_same
import all Lanius.Faithful.Gen.SelfSrcC_UintTy_half
import all Lanius.Faithful.Gen.SelfSrcC_Word_compute
import all Lanius.Faithful.Gen.SelfSrcC_Word_narrows
import all Lanius.Faithful.Gen.SelfSrcC_arithShiftRight
import all Lanius.Faithful.Gen.SelfSrcC_arithUint
import all Lanius.Faithful.Gen.SelfSrcC_arities
import all Lanius.Faithful.Gen.SelfSrcC_binaryConstant
import all Lanius.Faithful.Gen.SelfSrcC_callAgrees
import all Lanius.Faithful.Gen.SelfSrcC_declareProgram
import all Lanius.Faithful.Gen.SelfSrcC_extentAfter
import all Lanius.Faithful.Gen.SelfSrcC_floatApply
import all Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
import all Lanius.Faithful.Gen.SelfSrcC_longer
import all Lanius.Faithful.Gen.SelfSrcC_lowerLocal
import all Lanius.Faithful.Gen.SelfSrcC_sintToUint
import all Lanius.Faithful.Gen.SelfSrcC_substAll
import all Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
import all Lanius.Faithful.Gen.SelfSrcF_collect
import all Lanius.Faithful.Gen.SelfSrcF_consTys
import all Lanius.Faithful.Gen.SelfSrcF_effNamedTys
import all Lanius.Faithful.Gen.SelfSrcF_externBody
import all Lanius.Faithful.Gen.SelfSrcF_findConst
import all Lanius.Faithful.Gen.SelfSrcF_funcsOnto
import all Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
import all Lanius.Faithful.Gen.SelfSrcF_joinInsts
import all Lanius.Faithful.Gen.SelfSrcF_litIf
import all Lanius.Faithful.Gen.SelfSrcF_paramGoals
import all Lanius.Faithful.Gen.SelfSrcF_projectionRet
import all Lanius.Faithful.Gen.SelfSrcF_readInst
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
def dpart12 : List SrcFunc := [(src_cons_of_mini_selfhost_LocalTy 1400), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_core_option_Option_usize), (src_weighed_more 957 1401), (src_weigh_round_at 957 959 960 961 1402), (src_boxed_of_mini_selfhost_List_core_option_Option_usize 50 1201 1403), (src_inst_member 662 1205 1404), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_Ty), (src_decl_insts 56 1234 1364 1405 1406), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MParam), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_MStmt), (src_core_mem_size_of_of_mini_selfhost_Ty), (src_effs_named_tys 443 663 973 1211 1212), (src_unbox_of_mini_selfhost_List_mini_selfhost_MEff 1407), (src_unbox_of_mini_selfhost_MEff 1408), (src_effs_calls 269 977 978 1212 1214), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_MFunc), (src_module_globals 932 935 936 1409), (src_field_start_Token_of_mini_selfhost_Token), (src_length_of_mini_selfhost_Ty 75 657 1218), (src_extern_body 1226 1227), (src_params_of 103 1410 1411), (src_empty_of_mini_selfhost_Local), (src_result_of 152 155 1412 1413 1414 1415 1416), (src_never_ret 152 155 1413 1414), (src_last_ty 657 1224), (src_boxed_of_mini_selfhost_MStmt 50 1209 1417), (src_boxed_of_mini_selfhost_List_mini_selfhost_MEff 50 1407 1418), (src_param_effs 970 1227 1419 1420), (src_ret_expected), (src_fn_bounds_ok 155 1421 1422 1423), (src_ref_checked 1424 1425), (src_func_params 1426), (src_self_ref_id 1427), (src_boxed_of_mini_selfhost_List_mini_selfhost_MParam 50 1208 1428), (src_field_tys 1181 1429 1430), (src_BinOp_folds), (src_Word_compute 999 1431), (src_BinOp_annihilates), (src_BinOp_commutes), (src_Word_same_operand 999), (src_BinOp_unit), (src_Word_keeps 1432), (src_CmpOp_test), (src_signed_key 999), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Fact), (src_Expr_is_atom), (src_Expr_mentions 485 1246), (src_cons_of_mini_selfhost_Fact 1433), (src_trim_facts 1434 1435), (src_kill_prefix 56 279 1005 1249 1436 1437), (src_dying_extent 75 1005 1250 1438 1439), (src_Stmt_ignores 302 1246 1251 1253), (src_Stmt_jumps 302 1252), (src_mentions_any 486 1246 1253), (src_Expr_is_constant 1013), (src_neg_agrees 485 1009), (src_binary_agrees 485 1009 1016 1440), (src_unit_agrees 1009 1238 1241 1441), (src_compare_agrees 485 1009 1016 1442), (src_fp_agrees 485 1009 1443), (src_fold_constant 1235 1236), (src_absorbed 1237), (src_unbox_of_mini_selfhost_List_mini_selfhost_Arity 740), (src_FloatTy_rex_size), (src_slot_offset 75 105), (src_slot_operands 478 742 743 1029), (src_Word_rex 110 743), (src_BinOp_opcode 742 743), (src_CmpOp_setcc 1444 1445), (src_pow2 56 1269), (src_MemWidth_rex 110 743), (src_DivOp_extend 478 742 743 1266), (src_DivOp_opcode 742 743), (src_DivOp_result 110 742 743), (src_FOp_opcode_bytes 478 742 743 1266 1446 1447 1448 1449 1450), (src_syscall_rsi_bytes 742 743), (src_syscall_linux_byte), (src_syscall_linux_high), (src_lower_scalar_slot 312), (src_float_arith 1451), (src_SrcType_is_sint_any), (src_arith_sint 1452), (src_arith_uint 1453), (src_SrcType_is_integer), (src_float_order 1454), (src_sign_key 332), (src_order_sint 1455), (src_order_uint 1456), (src_SrcType_word 1297), (src_wrap 332 751 1084), (src_sint_to_i32 1084 1289), (src_from_i32 332 1084 1289), (src_sint_to_uint 1084 1289 1291), (src_sint_to_wide 1084 1291), (src_int_to_float 332), (src_if_narrow 1084), (src_float_to_float 332), (src_UintTy_signed_word 1084), (src_copy_slots 120 232 348), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcArm)]

def dents12 : List SigEntry := [some ([ty268, ty270], ty270), none, some ([ty246, ty246], .bool), some ([(.uint .usize), ty127, ty156, ty246, ty154, ty156, ty246], ty246), some ([ty246], ty245), some ([ty156, ty154], .bool), none, some ([(.uint .usize), ty127, .bool, (.uint .usize), ty153], ty226), none, none, none, some ([ty286], ty153), some ([ty189], ty286), some ([ty190], ty191), some ([ty286], ty156), none, some ([ty127, ty27], ty27), some ([ty44], (.uint .usize)), some ([ty153], (.uint .usize)), some ([ty293, ty276, (.uint .usize)], ty231), some ([(.uint .usize), ty275, ty110, ty291, ty85], ty293), some ([], ty291), some ([(.uint .usize), ty275, ty84], ty276), some ([ty110], .bool), some ([ty153], ty250), some ([ty192], ty188), some ([ty286], ty189), some ([ty186], ty286), some ([ty276], ty250), some ([(.uint .usize), ty127, ty110, ty275], .bool), some ([ty231, ty241], ty231), some ([(.uint .usize), ty275, ty293, ty276, ty84, ty84], ty231), some ([ty275, ty85], ty241), some ([ty186], ty185), some ([(.uint .usize), ty127, (.uint .usize), ty153], ty251), some ([ty54], .bool), some ([ty53, ty54, (.uint .uint64), (.uint .uint64)], (.uint .uint64)), some ([ty54], .bool), some ([ty54], .bool), some ([ty53, (.uint .uint64), (.uint .uint64)], .bool), some ([ty54], (.uint .uint64)), some ([ty53, ty90], .bool), some ([ty55, (.uint .uint64), (.uint .uint64)], .bool), some ([(.uint .uint64)], (.uint .uint64)), none, some ([ty90], .bool), some ([ty90, (.uint .usize)], .bool), some ([ty201, ty203], ty203), some ([ty203], ty203), some ([ty203, (.uint .usize), (.uint .usize)], ty203), some ([ty203, (.uint .usize), (.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty94, (.uint .usize)], .bool), some ([ty94], .bool), some ([ty93, (.uint .usize)], .bool), some ([ty90, ty233], .bool), some ([ty90, ty90], .bool), some ([ty53, ty54, ty90, ty90, ty90], .bool), some ([ty53, ty54, ty90, ty90, ty90], .bool), some ([ty53, ty55, ty90, ty90, ty90], .bool), some ([ty60, ty90, ty90, ty90], .bool), some ([ty53, ty54, (.uint .uint64), (.uint .uint64)], ty233), some ([ty54, (.uint .uint64)], ty233), some ([ty160], ty161), some ([ty8], (.uint .usize)), some ([(.uint .usize)], .i32), some ([(.uint .usize)], ty35), some ([ty53], ty35), some ([ty54], ty35), some ([ty55, ty53], (.uint .uint8)), some ([(.uint .usize)], (.uint .uint64)), some ([ty56], ty35), some ([ty57, ty53], ty35), some ([ty57], ty35), some ([ty57], ty35), some ([ty60], ty35), some ([ty61], ty35), some ([ty61], (.uint .uint8)), some ([ty61], (.uint .uint8)), some ([(.uint .usize), ty9], ty174), some ([ty54, ty173, ty173, ty259], ty174), some ([ty9], .bool), some ([ty54, ty173, ty173, ty236], ty174), some ([ty54, ty173, ty173, ty236], ty174), some ([ty9], .bool), some ([ty55, ty173, ty173, ty259], ty174), some ([ty90], ty90), some ([ty55, ty173, ty173, ty236], ty174), some ([ty55, ty173, ty173, ty236], ty174), some ([ty9], ty53), some ([ty4, ty90], ty90), some ([ty4, ty90], ty90), some ([ty4, ty90], ty90), some ([ty4, ty4, ty90], ty90), some ([ty4, ty90], ty90), some ([ty8, ty53, ty90], ty174), some ([ty4, ty174], ty174), some ([ty8, ty8, ty90], ty174), some ([ty4], ty53), some ([(.uint .usize), ty9, ty9], ty169), none]

/-- `declareFuncs` of functions 1200 to 1299. -/
theorem dchunk12 : declsStep dpart12 decls 34 54 31 51 = true := by decide +kernel

theorem dfit12 : entriesFit dpart12 dents12 = true := by decide +kernel

end Lanius.Faithful.SelfPure

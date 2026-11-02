module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc1
public import Lanius.Faithful.Gen.SelfSrc2
public import Lanius.Faithful.Gen.SelfSrc3
public import Lanius.Faithful.Gen.SelfSrc4
public import Lanius.Faithful.Gen.SelfSrc6
public import Lanius.Faithful.Gen.SelfSrc7
public import Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
public import Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
public import Lanius.Faithful.Gen.SelfSrcC_FloatTy_rex
public import Lanius.Faithful.Gen.SelfSrcC_Word_narrows
public import Lanius.Faithful.Gen.SelfSrcC_arities
public import Lanius.Faithful.Gen.SelfSrcC_binaryConstant
public import Lanius.Faithful.Gen.SelfSrcC_declareProgram
public import Lanius.Faithful.Gen.SelfSrcC_extentAfter
public import Lanius.Faithful.Gen.SelfSrcC_killShared
public import Lanius.Faithful.Gen.SelfSrcC_longer
public import Lanius.Faithful.Gen.SelfSrcC_substAll
public import Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pRetVoid
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pTypeArgsNone
public import Lanius.Faithful.Gen.SelfSrcF_allocClosed
public import Lanius.Faithful.Gen.SelfSrcF_blockArmsOf
public import Lanius.Faithful.Gen.SelfSrcF_collect
public import Lanius.Faithful.Gen.SelfSrcF_compoundOf
public import Lanius.Faithful.Gen.SelfSrcF_consTys
public import Lanius.Faithful.Gen.SelfSrcF_eDivideClosed
public import Lanius.Faithful.Gen.SelfSrcF_eIndexClosed
public import Lanius.Faithful.Gen.SelfSrcF_eStructClosed
public import Lanius.Faithful.Gen.SelfSrcF_findConst
public import Lanius.Faithful.Gen.SelfSrcF_firstSrc
public import Lanius.Faithful.Gen.SelfSrcF_flExpFirst
public import Lanius.Faithful.Gen.SelfSrcF_flattenTys
public import Lanius.Faithful.Gen.SelfSrcF_funcsOnto
public import Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
public import Lanius.Faithful.Gen.SelfSrcF_joinInsts
public import Lanius.Faithful.Gen.SelfSrcF_lowerTy
public import Lanius.Faithful.Gen.SelfSrcF_negWideI32
public import Lanius.Faithful.Gen.SelfSrcF_paramGoals
public import Lanius.Faithful.Gen.SelfSrcF_selfRefOf
public import Lanius.Faithful.Gen.SelfSrcF_sintAt
public import Lanius.Faithful.Gen.SelfSrcF_typeDeclAt
public import Lanius.Faithful.Gen.SelfSrcF_weightAdd
public import Lanius.Faithful.Gen.SelfSrcF_wideOf
public import Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc1
import all Lanius.Faithful.Gen.SelfSrc2
import all Lanius.Faithful.Gen.SelfSrc3
import all Lanius.Faithful.Gen.SelfSrc4
import all Lanius.Faithful.Gen.SelfSrc6
import all Lanius.Faithful.Gen.SelfSrc7
import all Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
import all Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
import all Lanius.Faithful.Gen.SelfSrcC_FloatTy_rex
import all Lanius.Faithful.Gen.SelfSrcC_Word_narrows
import all Lanius.Faithful.Gen.SelfSrcC_arities
import all Lanius.Faithful.Gen.SelfSrcC_binaryConstant
import all Lanius.Faithful.Gen.SelfSrcC_declareProgram
import all Lanius.Faithful.Gen.SelfSrcC_extentAfter
import all Lanius.Faithful.Gen.SelfSrcC_killShared
import all Lanius.Faithful.Gen.SelfSrcC_longer
import all Lanius.Faithful.Gen.SelfSrcC_substAll
import all Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pRetVoid
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pTypeArgsNone
import all Lanius.Faithful.Gen.SelfSrcF_allocClosed
import all Lanius.Faithful.Gen.SelfSrcF_blockArmsOf
import all Lanius.Faithful.Gen.SelfSrcF_collect
import all Lanius.Faithful.Gen.SelfSrcF_compoundOf
import all Lanius.Faithful.Gen.SelfSrcF_consTys
import all Lanius.Faithful.Gen.SelfSrcF_eDivideClosed
import all Lanius.Faithful.Gen.SelfSrcF_eIndexClosed
import all Lanius.Faithful.Gen.SelfSrcF_eStructClosed
import all Lanius.Faithful.Gen.SelfSrcF_findConst
import all Lanius.Faithful.Gen.SelfSrcF_firstSrc
import all Lanius.Faithful.Gen.SelfSrcF_flExpFirst
import all Lanius.Faithful.Gen.SelfSrcF_flattenTys
import all Lanius.Faithful.Gen.SelfSrcF_funcsOnto
import all Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
import all Lanius.Faithful.Gen.SelfSrcF_joinInsts
import all Lanius.Faithful.Gen.SelfSrcF_lowerTy
import all Lanius.Faithful.Gen.SelfSrcF_negWideI32
import all Lanius.Faithful.Gen.SelfSrcF_paramGoals
import all Lanius.Faithful.Gen.SelfSrcF_selfRefOf
import all Lanius.Faithful.Gen.SelfSrcF_sintAt
import all Lanius.Faithful.Gen.SelfSrcF_typeDeclAt
import all Lanius.Faithful.Gen.SelfSrcF_weightAdd
import all Lanius.Faithful.Gen.SelfSrcF_wideOf
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

/-- Functions 1300 to 1399, and their signature entries. -/
def dpart13 : List SrcFunc := [(src_close_effs 1125 1167 1300 1425 1426), (src_e_apply_closed 1349), (src_e_neg_closed 1349), (src_e_not_closed 1349), (src_e_cast_closed 1349), (src_e_index_closed 1349), (src_e_struct_closed 1347), (src_e_variant_closed 1347), (src_e_match_closed 1347 1349), (src_e_divide_closed 1349), (src_e_array_slice_closed), (src_core_mem_size_of_of_mini_selfhost_List_core_option_Option_mini_selfhost_SrcType), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_core_option_Option_mini_selfhost_SrcType), (src_enum_src 1427), (src_lower_variants 56 528 1314 1317 1428 1429), (src_payload_tys 1138 1382 1430), (src_struct_src 376), (src_lower_tys 56 232 629 1317 1431 1432), (src_wide_left 303 1318 1433), (src_wide_left_exprs 311 1318 1319), (src_wide_left_arms 1031 1318 1320), (src_wide_left_eff 343 345 1318 1321 1434), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcFunc), (src_int_at 1435), (src_wide_value 303 1436), (src_neg_wide_at 1437 1438 1439), (src_neg_least 1440), (src_boxed_of_mini_selfhost_SrcExpr 50 470 1441), (src_operand_want 1442 1443 1444), (src_known_expr 303 1146 1151 1152 1329 1445 1446), (src_amount_want 1328 1443 1444), (src_wide_at 1447 1448 1449), (src_float_want 1450), (src_core_mem_size_of_of_mini_selfhost_SrcStmt), (src_empty_of_mini_selfhost_SrcExpr), (src_cons_of_mini_selfhost_SrcExpr 1451), (src_first_src 1152), (src_rest_src 178), (src_repeat_src 56 232 233 1338), (src_get_of_mini_selfhost_SrcFunc 56 59 1339), (src_src_param_tys 173 232 233 1340), (src_empty_of_mini_selfhost_SrcArm), (src_cons_of_mini_selfhost_SrcArm 1452), (src_bound_tys 76 1156 1336 1337 1343), (src_rest_payloads 180), (src_ty_local_at 1151), (src_unbox_of_mini_selfhost_List_mini_selfhost_LocalTy 1453), (src_boxed_of_mini_selfhost_List_mini_selfhost_SrcEff 50 515 1454), (src_lit_effs 343 1154 1336 1337 1348 1425 1455), (src_boxed_of_mini_selfhost_SrcEff 50 517 1456), (src_known_eff 213 345 1151 1153 1329 1350 1443 1445 1457), (src_lit_arm_effs 343 1148 1154 1343 1344 1351 1425 1455 1458 1459), (src_boxed_of_mini_selfhost_List_mini_selfhost_LocalTy 50 1453 1460), (src_weighed_more_at 921 922 1158), (src_weigh_again 1461), (src_core_mem_size_of_of_mini_selfhost_List_core_option_Option_usize), (src_same_inst 1462), (src_tys_insts 56 265 629 631 1357 1463), (src_flat_payloads 1464), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MEff), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_MEff), (src_type_names_in 258 269 1465), (src_empty_of_mini_selfhost_MParam), (src_param_of 56 152 1099 1175 1368 1466 1467 1468 1469 1470 1471 1472 1473), (src_p_ret_void), (src_p_ret_type), (src_p_type_never), (src_ret_of_ty), (src_ty_of 56 152 154 155 858 1368 1474 1475 1476 1477 1478 1479 1480 1481 1482 1483 1484), (src_core_mem_size_of_of_mini_selfhost_MStmt), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_MEff), (src_empty_of_mini_selfhost_MEff), (src_cons_of_mini_selfhost_MEff 1181), (src_goals_hold 56 1485), (src_item_goals 154 1486 1487 1488), (src_impl_where 152 155 594), (src_if_not_writes), (src_writes_local 936 1377), (src_func_ret 1489 1490 1491), (src_self_ref_of 56 152 591 1172 1469), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_MParam), (src_ty_list 56 103 422 1368 1381 1492), (src_decl_env 258), (src_BinOp_compute), (src_Expr_narrow 1493), (src_boxed_of_mini_selfhost_List_mini_selfhost_Fact 50 1199 1494), (src_longer 56 969 1386), (src_first_facts 56 275 969 1202 1387), (src_kill_tail 1495 1496), (src_kill_prefix_at 1202 1391), (src_extent_after), (src_fact_dies 1201), (src_BinOp_number), (src_Expr_unit_of 675 1194 1195), (src_CmpOp_number), (src_FOp_number 75 105 540 980 1497 1498), (src_CmpOp_setcc_signed), (src_CmpOp_setcc_unsigned), (src_float_operands 457 713 714 1499), (src_FloatTy_scalar_prefix)]

def dents13 : List SigEntry := [some ([(.uint .usize), ty226, ty280], ty289), some ([ty14, ty277, ty277], ty277), some ([ty277], ty277), some ([ty277], ty277), some ([ty9, ty277], ty277), some ([(.uint .usize), ty277], ty277), some ([ty177, ty289], ty277), some ([ty177, (.uint .usize), ty289], ty277), some ([ty277, ty177, ty177, ty27, ty289], ty277), some ([ty28, ty277, ty277], ty277), some ([ty177, (.uint .usize)], ty277), none, none, some ([ty238, ty216], ty177), some ([(.uint .usize), ty127, ty156, ty292], ty216), some ([(.uint .usize), ty127, (.uint .usize), ty153], ty292), some ([ty238, ty215], ty177), some ([(.uint .usize), ty127, ty156, ty248], ty215), some ([ty15], .bool), some ([ty18], .bool), some ([ty23], .bool), some ([ty29], .bool), none, some ([ty177, .i32, ty15], ty15), some ([ty15], ty230), some ([ty177, (.uint .uint64), ty15], ty15), some ([ty177, ty15, ty15], ty15), some ([ty15], ty13), some ([ty14, ty177, ty177, ty177], ty177), some ([ty264, ty15], ty177), some ([ty14, ty177, ty177, ty177], ty177), some ([ty177, (.uint .uint64), ty15], ty15), some ([ty177, ty9, ty15], ty279), none, some ([], ty18), some ([ty15, ty18], ty18), some ([ty215], ty177), some ([ty215], ty215), some ([ty9, (.uint .usize)], ty71), some ([ty33, (.uint .usize)], ty259), some ([ty12], ty71), some ([], ty23), some ([ty21, ty23], ty23), some ([ty20, ty215, ty264], ty264), some ([ty216], ty216), some ([ty262, ty264, (.uint .usize)], ty177), some ([ty263], ty264), some ([ty212], ty24), some ([ty33, ty264, ty215, ty212], ty212), some ([ty29], ty25), some ([ty33, ty264, ty29], ty177), some ([ty33, ty264, ty216, ty9, ty27, ty212], ty212), some ([ty264], ty263), some ([ty238, ty243, ty243], .bool), some ([(.uint .usize), ty127, ty156, ty243, ty154, ty238], ty238), none, some ([ty154, ty154], .bool), some ([(.uint .usize), ty127, ty248], ty223), some ([ty292], ty248), none, none, some ([ty109, ty27], ty27), some ([], ty186), some ([(.uint .usize), ty269, ty110, ty285, ty84, ty85], ty287), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty247], ty270), some ([(.uint .usize), ty269, ty84], ty247), none, none, some ([], ty280), some ([ty191, ty280], ty280), some ([(.uint .usize), ty127, ty298], .bool), some ([(.uint .usize), ty269, ty84, ty84], ty298), some ([ty84], ty84), some ([.bool, ty193], ty228), some ([ty192, (.uint .usize)], .bool), some ([(.uint .usize), ty269, ty286, ty270, ty84, ty84], ty228), some ([ty269, ty84], ty238), none, some ([(.uint .usize), ty269, ty85], ty248), some ([ty127, ty27, ty27, ty153], ty269), some ([ty52, (.uint .uint64), (.uint .uint64)], (.uint .uint64)), some ([ty90], .bool), some ([ty203], ty202), some ([ty203, (.uint .usize)], .bool), some ([ty203, (.uint .usize)], ty203), some ([ty203, (.uint .usize)], ty203), some ([ty201, (.uint .usize), ty203], ty203), some ([.bool, (.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty201, (.uint .usize)], .bool), some ([ty52], (.uint .usize)), some ([ty90, ty51, ty52], .bool), some ([ty53], (.uint .usize)), some ([ty58], (.uint .usize)), some ([ty53], (.uint .uint8)), some ([ty53], (.uint .uint8)), some ([ty8], ty67), some ([ty8], (.uint .uint8))]

/-- `declareFuncs` of functions 1300 to 1399. -/
theorem dchunk13 : declsStep dpart13 decls 28 45 24 41 = true := by decide +kernel

theorem dfit13 : entriesFit dpart13 dents13 = true := by decide +kernel

end Lanius.Faithful.SelfPure

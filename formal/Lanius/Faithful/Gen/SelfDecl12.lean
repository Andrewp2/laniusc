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
public import Lanius.Faithful.Gen.SelfSrcC_Inline_blockLeft
public import Lanius.Faithful.Gen.SelfSrcC_Word_compute
public import Lanius.Faithful.Gen.SelfSrcC_Word_narrows
public import Lanius.Faithful.Gen.SelfSrcC_arities
public import Lanius.Faithful.Gen.SelfSrcC_binaryConstant
public import Lanius.Faithful.Gen.SelfSrcC_callAgrees
public import Lanius.Faithful.Gen.SelfSrcC_declareProgram
public import Lanius.Faithful.Gen.SelfSrcC_extentAfter
public import Lanius.Faithful.Gen.SelfSrcC_floatApply
public import Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
public import Lanius.Faithful.Gen.SelfSrcC_longer
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
public import Lanius.Faithful.Gen.SelfSrcF_namesFieldBase
public import Lanius.Faithful.Gen.SelfSrcF_negWideI32
public import Lanius.Faithful.Gen.SelfSrcF_paramGoals
public import Lanius.Faithful.Gen.SelfSrcF_projectionRet
public import Lanius.Faithful.Gen.SelfSrcF_readInst
public import Lanius.Faithful.Gen.SelfSrcF_sintAt
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
import all Lanius.Faithful.Gen.SelfSrcC_Inline_blockLeft
import all Lanius.Faithful.Gen.SelfSrcC_Word_compute
import all Lanius.Faithful.Gen.SelfSrcC_Word_narrows
import all Lanius.Faithful.Gen.SelfSrcC_arities
import all Lanius.Faithful.Gen.SelfSrcC_binaryConstant
import all Lanius.Faithful.Gen.SelfSrcC_callAgrees
import all Lanius.Faithful.Gen.SelfSrcC_declareProgram
import all Lanius.Faithful.Gen.SelfSrcC_extentAfter
import all Lanius.Faithful.Gen.SelfSrcC_floatApply
import all Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
import all Lanius.Faithful.Gen.SelfSrcC_longer
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
import all Lanius.Faithful.Gen.SelfSrcF_namesFieldBase
import all Lanius.Faithful.Gen.SelfSrcF_negWideI32
import all Lanius.Faithful.Gen.SelfSrcF_paramGoals
import all Lanius.Faithful.Gen.SelfSrcF_projectionRet
import all Lanius.Faithful.Gen.SelfSrcF_readInst
import all Lanius.Faithful.Gen.SelfSrcF_sintAt
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
def dpart12 : List SrcFunc := [(src_src_fields 181 184 1209), (src_callee_params 1425 1426), (src_payload_at 386), (src_src_variants 183), (src_lit_src_arms 1066 1196 1202 1204 1427 1428 1429 1430), (src_ty_local 1431 1432), (src_ty_at 521), (src_src_element 184), (src_lit_eff 356 358 1196 1200 1201 1202 1203 1208 1211 1415 1417 1433 1434 1435 1436 1437), (src_repeat_src 56 239 240 1209), (src_empty_of_mini_selfhost_LocalTy), (src_cons_of_mini_selfhost_LocalTy 1438), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_core_option_Option_usize), (src_weighed_more 969 1439), (src_weigh_round_at 969 971 972 973 1440), (src_boxed_of_mini_selfhost_List_core_option_Option_usize 50 1212 1441), (src_inst_member 671 1216 1442), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_Ty), (src_decl_insts 56 1246 1388 1443 1444), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MParam), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_MStmt), (src_core_mem_size_of_of_mini_selfhost_Ty), (src_effs_named_tys 448 672 985 1222 1223), (src_unbox_of_mini_selfhost_List_mini_selfhost_MEff 1445), (src_unbox_of_mini_selfhost_MEff 1446), (src_effs_calls 272 989 990 1223 1225), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_MFunc), (src_module_globals 941 944 945 1447), (src_field_start_Token_of_mini_selfhost_Token), (src_length_of_mini_selfhost_Ty 75 666 1229), (src_extern_body 1237 1238), (src_params_of 103 1448 1449), (src_empty_of_mini_selfhost_Local), (src_result_of 153 156 1450 1451 1452 1453 1454), (src_never_ret 153 156 1451 1452), (src_last_ty 666 1235), (src_boxed_of_mini_selfhost_MStmt 50 1220 1455), (src_boxed_of_mini_selfhost_List_mini_selfhost_MEff 50 1445 1456), (src_param_effs 982 1238 1457 1458), (src_ret_expected), (src_fn_bounds_ok 156 1459 1460 1461), (src_refs_checked 148 156 607 1462 1463), (src_ref_checked 1464 1465), (src_func_params 1466), (src_self_ref_id 1467), (src_boxed_of_mini_selfhost_List_mini_selfhost_MParam 50 1219 1468), (src_field_tys 1185 1469 1470), (src_BinOp_folds), (src_Word_compute 1011 1471), (src_BinOp_annihilates), (src_BinOp_commutes), (src_Word_same_operand 1011), (src_BinOp_unit), (src_Word_keeps 1472), (src_CmpOp_test), (src_signed_key 1011), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Fact), (src_Expr_is_atom), (src_Expr_mentions 492 1258), (src_cons_of_mini_selfhost_Fact 1473), (src_trim_facts 1474 1475), (src_kill_prefix 56 282 1017 1261 1476 1477), (src_dying_extent 75 1017 1262 1478 1479), (src_Stmt_ignores 307 1258 1263 1265), (src_Stmt_jumps 307 1264), (src_mentions_any 493 1258 1265), (src_Expr_is_constant 1025), (src_neg_agrees 492 1021), (src_binary_agrees 492 1021 1028 1480), (src_unit_agrees 1021 1250 1253 1481), (src_compare_agrees 492 1021 1028 1482), (src_fp_agrees 492 1021 1483), (src_fold_constant 1247 1248), (src_absorbed 1249), (src_unbox_of_mini_selfhost_List_mini_selfhost_Arity 753), (src_FloatTy_rex_size), (src_core_mem_size_of_of_mini_selfhost_List_u8), (src_le64 1042 1043), (src_slot_load 754 1042 1043 1044 1484), (src_slot_store 754 1042 1043 1044 1484), (src_BinOp_bytes 754 1485 1486 1487), (src_slot_compare 754 1042 1043 1485 1486 1488), (src_relative), (src_copy_bytes 75 76 110 754 1278 1279 1283), (src_arg_base 75 1045), (src_fsp_save 754 1042 1043 1044 1484), (src_fsp_load 754 1042 1043 1044 1484), (src_slot_range 56 75 139 418 1287), (src_epilogue 1042 1043), (src_bump_bytes 754 1042 1043 1277 1489), (src_load_at_bytes 1042 1043), (src_store_at_bytes 754 1042 1043 1044 1484), (src_load_word_bytes 754 1042 1043 1490), (src_store_word_bytes 754 1042 1043 1044 1484 1490), (src_DivOp_bytes 754 1042 1043 1485 1486 1491 1492 1493), (src_FOp_bytes 754 1485 1494), (src_sys_bytes 75 754 1042 1043 1044 1484 1495 1496 1497), (src_frame_memory_bytes 754 1042 1043 1277), (src_lower_scalar_slot 317), (src_float_arith 1498)]

def dents12 : List SigEntry := [some ([ty179], ty217), some ([ty34, (.uint .usize)], ty217), some ([ty220, (.uint .usize)], ty217), some ([ty179], ty220), some ([ty271, ty220, ty9, ty23], ty23), some ([ty271, (.uint .usize)], ty179), some ([ty217, (.uint .usize)], ty179), some ([ty179], ty179), some ([ty34, ty271, ty179, ty29], ty29), some ([ty9, (.uint .usize)], ty72), some ([], ty271), some ([ty269, ty271], ty271), none, some ([ty247, ty247], .bool), some ([(.uint .usize), ty128, ty158, ty247, ty156, ty158, ty247], ty247), some ([ty247], ty246), some ([ty158, ty156], .bool), none, some ([(.uint .usize), ty128, .bool, (.uint .usize), ty155], ty227), none, none, none, some ([ty287], ty155), some ([ty191], ty287), some ([ty192], ty193), some ([ty287], ty158), none, some ([ty128, ty27], ty27), some ([ty45], (.uint .usize)), some ([ty155], (.uint .usize)), some ([ty294, ty277, (.uint .usize)], ty232), some ([(.uint .usize), ty276, ty111, ty292, ty86], ty294), some ([], ty292), some ([(.uint .usize), ty276, ty85], ty277), some ([ty111], .bool), some ([ty155], ty251), some ([ty194], ty190), some ([ty287], ty191), some ([ty188], ty287), some ([ty277], ty251), some ([(.uint .usize), ty128, ty111, ty276], .bool), some ([(.uint .usize), ty85, ty86, ty232], ty232), some ([ty232, ty146], ty232), some ([(.uint .usize), ty276, ty294, ty277, ty85, ty85], ty232), some ([ty276, ty86], ty146), some ([ty188], ty187), some ([(.uint .usize), ty128, (.uint .usize), ty155], ty252), some ([ty55], .bool), some ([ty54, ty55, (.uint .uint64), (.uint .uint64)], (.uint .uint64)), some ([ty55], .bool), some ([ty55], .bool), some ([ty54, (.uint .uint64), (.uint .uint64)], .bool), some ([ty55], (.uint .uint64)), some ([ty54, ty91], .bool), some ([ty56, (.uint .uint64), (.uint .uint64)], .bool), some ([(.uint .uint64)], (.uint .uint64)), none, some ([ty91], .bool), some ([ty91, (.uint .usize)], .bool), some ([ty203, ty205], ty205), some ([ty205], ty205), some ([ty205, (.uint .usize), (.uint .usize)], ty205), some ([ty205, (.uint .usize), (.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty95, (.uint .usize)], .bool), some ([ty95], .bool), some ([ty94, (.uint .usize)], .bool), some ([ty91, ty234], .bool), some ([ty91, ty91], .bool), some ([ty54, ty55, ty91, ty91, ty91], .bool), some ([ty54, ty55, ty91, ty91, ty91], .bool), some ([ty54, ty56, ty91, ty91, ty91], .bool), some ([ty61, ty91, ty91, ty91], .bool), some ([ty54, ty55, (.uint .uint64), (.uint .uint64)], ty234), some ([ty55, (.uint .uint64)], ty234), some ([ty162], ty163), some ([ty8], (.uint .usize)), none, some ([(.uint .uint64)], ty36), some ([(.uint .usize)], ty36), some ([(.uint .usize)], ty36), some ([ty55, ty54, (.uint .usize)], ty36), some ([ty54, ty56, (.uint .usize)], ty36), some ([(.uint .usize), (.uint .usize)], .i32), some ([(.uint .usize), ty20, (.uint .usize)], ty36), some ([(.uint .usize)], (.uint .usize)), some ([(.uint .usize)], ty36), some ([(.uint .usize)], ty36), some ([(.uint .usize), (.uint .usize)], ty20), some ([], ty36), some ([(.uint .usize)], ty36), some ([], ty36), some ([(.uint .usize)], ty36), some ([ty57], ty36), some ([ty57, (.uint .usize)], ty36), some ([ty58, ty54, (.uint .usize)], ty36), some ([ty61, (.uint .usize)], ty36), some ([ty62, (.uint .usize)], ty36), some ([(.uint .usize)], ty36), some ([(.uint .usize), ty9], ty176), some ([ty55, ty175, ty175, ty260], ty176)]

/-- `declareFuncs` of functions 1200 to 1299. -/
theorem dchunk12 : declsStep dpart12 decls 34 55 31 52 = true := by decide +kernel

theorem dfit12 : entriesFit dpart12 dents12 = true := by decide +kernel

end Lanius.Faithful.SelfPure

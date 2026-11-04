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
public import Lanius.Faithful.Gen.SelfSrcC_UintTy_half
public import Lanius.Faithful.Gen.SelfSrcC_Word_compute
public import Lanius.Faithful.Gen.SelfSrcC_Word_narrows
public import Lanius.Faithful.Gen.SelfSrcC_arithUint
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
import all Lanius.Faithful.Gen.SelfSrcC_UintTy_half
import all Lanius.Faithful.Gen.SelfSrcC_Word_compute
import all Lanius.Faithful.Gen.SelfSrcC_Word_narrows
import all Lanius.Faithful.Gen.SelfSrcC_arithUint
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
def dpart12 : List SrcFunc := [(src_src_variants 183), (src_lit_src_arms 1065 1193 1199 1201 1419 1420 1421 1422), (src_ty_local 1423 1424), (src_ty_at 521), (src_src_element 184), (src_lit_eff 356 358 1193 1197 1198 1199 1200 1205 1208 1407 1409 1425 1426 1427 1428 1429), (src_repeat_src 56 239 240 1206), (src_empty_of_mini_selfhost_LocalTy), (src_cons_of_mini_selfhost_LocalTy 1430), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_core_option_Option_usize), (src_weighed_more 968 1431), (src_weigh_round_at 968 970 971 972 1432), (src_boxed_of_mini_selfhost_List_core_option_Option_usize 50 1209 1433), (src_inst_member 670 1213 1434), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_Ty), (src_decl_insts 56 1242 1380 1435 1436), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MParam), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_MStmt), (src_core_mem_size_of_of_mini_selfhost_Ty), (src_effs_named_tys 448 671 984 1219 1220), (src_unbox_of_mini_selfhost_List_mini_selfhost_MEff 1437), (src_unbox_of_mini_selfhost_MEff 1438), (src_effs_calls 272 988 989 1220 1222), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_MFunc), (src_module_globals 940 943 944 1439), (src_field_start_Token_of_mini_selfhost_Token), (src_length_of_mini_selfhost_Ty 75 665 1226), (src_extern_body 1234 1235), (src_params_of 103 1440 1441), (src_empty_of_mini_selfhost_Local), (src_result_of 153 156 1442 1443 1444 1445 1446), (src_never_ret 153 156 1443 1444), (src_last_ty 665 1232), (src_boxed_of_mini_selfhost_MStmt 50 1217 1447), (src_boxed_of_mini_selfhost_List_mini_selfhost_MEff 50 1437 1448), (src_param_effs 981 1235 1449 1450), (src_ret_expected), (src_fn_bounds_ok 156 1451 1452 1453), (src_ref_checked 1454 1455), (src_func_params 1456), (src_self_ref_id 1457), (src_boxed_of_mini_selfhost_List_mini_selfhost_MParam 50 1216 1458), (src_field_tys 1182 1459 1460), (src_BinOp_folds), (src_Word_compute 1010 1461), (src_BinOp_annihilates), (src_BinOp_commutes), (src_Word_same_operand 1010), (src_BinOp_unit), (src_Word_keeps 1462), (src_CmpOp_test), (src_signed_key 1010), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Fact), (src_Expr_is_atom), (src_Expr_mentions 492 1254), (src_cons_of_mini_selfhost_Fact 1463), (src_trim_facts 1464 1465), (src_kill_prefix 56 282 1016 1257 1466 1467), (src_dying_extent 75 1016 1258 1468 1469), (src_Stmt_ignores 307 1254 1259 1261), (src_Stmt_jumps 307 1260), (src_mentions_any 493 1254 1261), (src_Expr_is_constant 1024), (src_neg_agrees 492 1020), (src_binary_agrees 492 1020 1027 1470), (src_unit_agrees 1020 1246 1249 1471), (src_compare_agrees 492 1020 1027 1472), (src_fp_agrees 492 1020 1473), (src_fold_constant 1243 1244), (src_absorbed 1245), (src_unbox_of_mini_selfhost_List_mini_selfhost_Arity 752), (src_FloatTy_rex_size), (src_core_mem_size_of_of_mini_selfhost_List_u8), (src_le64 1041 1042), (src_slot_load 753 1041 1042 1043 1474), (src_slot_store 753 1041 1042 1043 1474), (src_BinOp_bytes 753 1475 1476 1477), (src_slot_compare 753 1041 1042 1475 1476 1478), (src_relative), (src_copy_bytes 75 76 110 753 1274 1275 1279), (src_arg_base 75 1044), (src_fsp_save 753 1041 1042 1043 1474), (src_fsp_load 753 1041 1042 1043 1474), (src_slot_range 56 75 139 418 1283), (src_epilogue 1041 1042), (src_bump_bytes 753 1041 1042 1273 1479), (src_load_at_bytes 1041 1042), (src_store_at_bytes 753 1041 1042 1043 1474), (src_load_word_bytes 753 1041 1042 1480), (src_store_word_bytes 753 1041 1042 1043 1474 1480), (src_DivOp_bytes 753 1041 1042 1475 1476 1481 1482 1483), (src_FOp_bytes 753 1475 1484), (src_sys_bytes 75 753 1041 1042 1043 1474 1485 1486 1487), (src_frame_memory_bytes 753 1041 1042 1273), (src_lower_scalar_slot 317), (src_float_arith 1488), (src_SrcType_is_sint_any), (src_arith_sint 1489), (src_arith_uint 1490), (src_SrcType_is_integer)]

def dents12 : List SigEntry := [some ([ty178], ty219), some ([ty270, ty219, ty9, ty23], ty23), some ([ty270, (.uint .usize)], ty178), some ([ty216, (.uint .usize)], ty178), some ([ty178], ty178), some ([ty33, ty270, ty178, ty29], ty29), some ([ty9, (.uint .usize)], ty71), some ([], ty270), some ([ty268, ty270], ty270), none, some ([ty246, ty246], .bool), some ([(.uint .usize), ty127, ty157, ty246, ty155, ty157, ty246], ty246), some ([ty246], ty245), some ([ty157, ty155], .bool), none, some ([(.uint .usize), ty127, .bool, (.uint .usize), ty154], ty226), none, none, none, some ([ty286], ty154), some ([ty190], ty286), some ([ty191], ty192), some ([ty286], ty157), none, some ([ty127, ty27], ty27), some ([ty44], (.uint .usize)), some ([ty154], (.uint .usize)), some ([ty293, ty276, (.uint .usize)], ty231), some ([(.uint .usize), ty275, ty110, ty291, ty85], ty293), some ([], ty291), some ([(.uint .usize), ty275, ty84], ty276), some ([ty110], .bool), some ([ty154], ty250), some ([ty193], ty189), some ([ty286], ty190), some ([ty187], ty286), some ([ty276], ty250), some ([(.uint .usize), ty127, ty110, ty275], .bool), some ([ty231, ty145], ty231), some ([(.uint .usize), ty275, ty293, ty276, ty84, ty84], ty231), some ([ty275, ty85], ty145), some ([ty187], ty186), some ([(.uint .usize), ty127, (.uint .usize), ty154], ty251), some ([ty54], .bool), some ([ty53, ty54, (.uint .uint64), (.uint .uint64)], (.uint .uint64)), some ([ty54], .bool), some ([ty54], .bool), some ([ty53, (.uint .uint64), (.uint .uint64)], .bool), some ([ty54], (.uint .uint64)), some ([ty53, ty90], .bool), some ([ty55, (.uint .uint64), (.uint .uint64)], .bool), some ([(.uint .uint64)], (.uint .uint64)), none, some ([ty90], .bool), some ([ty90, (.uint .usize)], .bool), some ([ty202, ty204], ty204), some ([ty204], ty204), some ([ty204, (.uint .usize), (.uint .usize)], ty204), some ([ty204, (.uint .usize), (.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty94, (.uint .usize)], .bool), some ([ty94], .bool), some ([ty93, (.uint .usize)], .bool), some ([ty90, ty233], .bool), some ([ty90, ty90], .bool), some ([ty53, ty54, ty90, ty90, ty90], .bool), some ([ty53, ty54, ty90, ty90, ty90], .bool), some ([ty53, ty55, ty90, ty90, ty90], .bool), some ([ty60, ty90, ty90, ty90], .bool), some ([ty53, ty54, (.uint .uint64), (.uint .uint64)], ty233), some ([ty54, (.uint .uint64)], ty233), some ([ty161], ty162), some ([ty8], (.uint .usize)), none, some ([(.uint .uint64)], ty35), some ([(.uint .usize)], ty35), some ([(.uint .usize)], ty35), some ([ty54, ty53, (.uint .usize)], ty35), some ([ty53, ty55, (.uint .usize)], ty35), some ([(.uint .usize), (.uint .usize)], .i32), some ([(.uint .usize), ty20, (.uint .usize)], ty35), some ([(.uint .usize)], (.uint .usize)), some ([(.uint .usize)], ty35), some ([(.uint .usize)], ty35), some ([(.uint .usize), (.uint .usize)], ty20), some ([], ty35), some ([(.uint .usize)], ty35), some ([], ty35), some ([(.uint .usize)], ty35), some ([ty56], ty35), some ([ty56, (.uint .usize)], ty35), some ([ty57, ty53, (.uint .usize)], ty35), some ([ty60, (.uint .usize)], ty35), some ([ty61, (.uint .usize)], ty35), some ([(.uint .usize)], ty35), some ([(.uint .usize), ty9], ty175), some ([ty54, ty174, ty174, ty259], ty175), some ([ty9], .bool), some ([ty54, ty174, ty174, ty237], ty175), some ([ty54, ty174, ty174, ty237], ty175), some ([ty9], .bool)]

/-- `declareFuncs` of functions 1200 to 1299. -/
theorem dchunk12 : declsStep dpart12 decls 34 54 31 51 = true := by decide +kernel

theorem dfit12 : entriesFit dpart12 dents12 = true := by decide +kernel

end Lanius.Faithful.SelfPure

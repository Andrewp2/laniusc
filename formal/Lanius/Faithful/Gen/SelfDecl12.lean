module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc0
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
public import Lanius.Faithful.Gen.SelfSrcC_callAgrees
public import Lanius.Faithful.Gen.SelfSrcC_declareProgram
public import Lanius.Faithful.Gen.SelfSrcC_extentAfter
public import Lanius.Faithful.Gen.SelfSrcC_floatApply
public import Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
public import Lanius.Faithful.Gen.SelfSrcC_longer
public import Lanius.Faithful.Gen.SelfSrcC_lowerLocal
public import Lanius.Faithful.Gen.SelfSrcC_sintToUint
public import Lanius.Faithful.Gen.SelfSrcC_substAll
public import Lanius.Faithful.Gen.SelfSrcF_collect
public import Lanius.Faithful.Gen.SelfSrcF_consTys
public import Lanius.Faithful.Gen.SelfSrcF_effNamedTys
public import Lanius.Faithful.Gen.SelfSrcF_externBody
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
import all Lanius.Faithful.Gen.SelfSrcC_callAgrees
import all Lanius.Faithful.Gen.SelfSrcC_declareProgram
import all Lanius.Faithful.Gen.SelfSrcC_extentAfter
import all Lanius.Faithful.Gen.SelfSrcC_floatApply
import all Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
import all Lanius.Faithful.Gen.SelfSrcC_longer
import all Lanius.Faithful.Gen.SelfSrcC_lowerLocal
import all Lanius.Faithful.Gen.SelfSrcC_sintToUint
import all Lanius.Faithful.Gen.SelfSrcC_substAll
import all Lanius.Faithful.Gen.SelfSrcF_collect
import all Lanius.Faithful.Gen.SelfSrcF_consTys
import all Lanius.Faithful.Gen.SelfSrcF_effNamedTys
import all Lanius.Faithful.Gen.SelfSrcF_externBody
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
def dpart12 : List SrcFunc := [(src_core_mem_typed_slice_from_storage_of_mini_selfhost_Ty), (src_decl_insts 56 1228 1366 1409 1410), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MParam), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_MStmt), (src_core_mem_size_of_of_mini_selfhost_Ty), (src_effs_named_tys 442 664 976 1205 1206), (src_unbox_of_mini_selfhost_List_mini_selfhost_MEff 1411), (src_unbox_of_mini_selfhost_MEff 1412), (src_effs_calls 269 980 981 1206 1208), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_MFunc), (src_module_globals 934 937 938 1413), (src_field_start_Token_of_mini_selfhost_Token), (src_length_of_mini_selfhost_Ty 75 658 1212), (src_extern_body 1220 1221), (src_params_of 103 1414 1415), (src_empty_of_mini_selfhost_Local), (src_result_of 152 155 1416 1417 1418 1419 1420), (src_never_ret 152 155 1417 1418), (src_last_ty 658 1218), (src_boxed_of_mini_selfhost_MStmt 50 1203 1421), (src_boxed_of_mini_selfhost_List_mini_selfhost_MEff 50 1411 1422), (src_param_effs 973 1221 1423 1424), (src_ret_expected), (src_fn_bounds_ok 155 1425 1426 1427), (src_ref_checked 1428 1429), (src_func_params 1430), (src_self_ref_id 1431), (src_boxed_of_mini_selfhost_List_mini_selfhost_MParam 50 1202 1432), (src_field_tys 1173 1433 1434), (src_BinOp_folds), (src_Word_compute 1002 1435), (src_BinOp_annihilates), (src_BinOp_commutes), (src_Word_same_operand 1002), (src_BinOp_unit), (src_Word_keeps 1436), (src_CmpOp_test), (src_signed_key 1002), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Fact), (src_Expr_is_atom), (src_Expr_mentions 486 1240), (src_cons_of_mini_selfhost_Fact 1437), (src_trim_facts 1438 1439), (src_kill_prefix 56 279 1008 1243 1440 1441), (src_dying_extent 75 1008 1244 1442 1443), (src_Stmt_ignores 301 1240 1245 1247), (src_Stmt_jumps 301 1246), (src_mentions_any 487 1240 1247), (src_Expr_is_constant 1016), (src_neg_agrees 486 1012), (src_binary_agrees 486 1012 1019 1444), (src_unit_agrees 1012 1232 1235 1445), (src_compare_agrees 486 1012 1019 1446), (src_fp_agrees 486 1012 1447), (src_fold_constant 1229 1230), (src_absorbed 1231), (src_unbox_of_mini_selfhost_List_mini_selfhost_Arity 746), (src_FloatTy_rex_size), (src_core_mem_size_of_of_mini_selfhost_List_u8), (src_le64 1033 1034), (src_slot_load 747 1033 1034 1035 1448), (src_slot_store 747 1033 1034 1035 1448), (src_BinOp_bytes 747 1449 1450 1451), (src_slot_compare 747 1033 1034 1449 1450 1452), (src_relative), (src_copy_bytes 75 76 110 747 1260 1261 1265), (src_arg_base 75 1036), (src_fsp_save 747 1033 1034 1035 1448), (src_fsp_load 747 1033 1034 1035 1448), (src_slot_range 56 75 138 397 1269), (src_epilogue 1033 1034), (src_bump_bytes 747 1033 1034 1259 1453), (src_load_at_bytes 1033 1034), (src_store_at_bytes 747 1033 1034 1035 1448), (src_load_word_bytes 747 1033 1034 1454), (src_store_word_bytes 747 1033 1034 1035 1448 1454), (src_DivOp_bytes 747 1033 1034 1449 1450 1455 1456 1457), (src_FOp_bytes 747 1449 1458), (src_sys_bytes 75 747 1033 1034 1035 1448 1459 1460 1461), (src_frame_memory_bytes 747 1033 1034 1259), (src_lower_scalar_slot 311), (src_float_arith 1462), (src_SrcType_is_sint_any), (src_arith_sint 1463), (src_arith_uint 1464), (src_SrcType_is_integer), (src_float_order 1465), (src_sign_key 331), (src_order_sint 1466), (src_order_uint 1467), (src_SrcType_word 1299), (src_wrap 331 753 1074), (src_sint_to_i32 1074 1291), (src_from_i32 331 1074 1291), (src_sint_to_uint 1074 1291 1293), (src_sint_to_wide 1074 1293), (src_int_to_float 331), (src_if_narrow 1074), (src_float_to_float 331), (src_UintTy_signed_word 1074)]

def dents12 : List SigEntry := [none, some ([(.uint .usize), ty127, .bool, (.uint .usize), ty153], ty226), none, none, none, some ([ty286], ty153), some ([ty190], ty286), some ([ty191], ty192), some ([ty286], ty156), none, some ([ty127, ty27], ty27), some ([ty44], (.uint .usize)), some ([ty153], (.uint .usize)), some ([ty293, ty276, (.uint .usize)], ty231), some ([(.uint .usize), ty275, ty110, ty291, ty85], ty293), some ([], ty291), some ([(.uint .usize), ty275, ty84], ty276), some ([ty110], .bool), some ([ty153], ty250), some ([ty193], ty189), some ([ty286], ty190), some ([ty187], ty286), some ([ty276], ty250), some ([(.uint .usize), ty127, ty110, ty275], .bool), some ([ty231, ty163], ty231), some ([(.uint .usize), ty275, ty293, ty276, ty84, ty84], ty231), some ([ty275, ty85], ty163), some ([ty187], ty186), some ([(.uint .usize), ty127, (.uint .usize), ty153], ty251), some ([ty54], .bool), some ([ty53, ty54, (.uint .uint64), (.uint .uint64)], (.uint .uint64)), some ([ty54], .bool), some ([ty54], .bool), some ([ty53, (.uint .uint64), (.uint .uint64)], .bool), some ([ty54], (.uint .uint64)), some ([ty53, ty90], .bool), some ([ty55, (.uint .uint64), (.uint .uint64)], .bool), some ([(.uint .uint64)], (.uint .uint64)), none, some ([ty90], .bool), some ([ty90, (.uint .usize)], .bool), some ([ty202, ty204], ty204), some ([ty204], ty204), some ([ty204, (.uint .usize), (.uint .usize)], ty204), some ([ty204, (.uint .usize), (.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty94, (.uint .usize)], .bool), some ([ty94], .bool), some ([ty93, (.uint .usize)], .bool), some ([ty90, ty233], .bool), some ([ty90, ty90], .bool), some ([ty53, ty54, ty90, ty90, ty90], .bool), some ([ty53, ty54, ty90, ty90, ty90], .bool), some ([ty53, ty55, ty90, ty90, ty90], .bool), some ([ty60, ty90, ty90, ty90], .bool), some ([ty53, ty54, (.uint .uint64), (.uint .uint64)], ty233), some ([ty54, (.uint .uint64)], ty233), some ([ty160], ty161), some ([ty8], (.uint .usize)), none, some ([(.uint .uint64)], ty35), some ([(.uint .usize)], ty35), some ([(.uint .usize)], ty35), some ([ty54, ty53, (.uint .usize)], ty35), some ([ty53, ty55, (.uint .usize)], ty35), some ([(.uint .usize), (.uint .usize)], .i32), some ([(.uint .usize), ty20, (.uint .usize)], ty35), some ([(.uint .usize)], (.uint .usize)), some ([(.uint .usize)], ty35), some ([(.uint .usize)], ty35), some ([(.uint .usize), (.uint .usize)], ty20), some ([], ty35), some ([(.uint .usize)], ty35), some ([], ty35), some ([(.uint .usize)], ty35), some ([ty56], ty35), some ([ty56, (.uint .usize)], ty35), some ([ty57, ty53, (.uint .usize)], ty35), some ([ty60, (.uint .usize)], ty35), some ([ty61, (.uint .usize)], ty35), some ([(.uint .usize)], ty35), some ([(.uint .usize), ty9], ty175), some ([ty54, ty174, ty174, ty259], ty175), some ([ty9], .bool), some ([ty54, ty174, ty174, ty237], ty175), some ([ty54, ty174, ty174, ty237], ty175), some ([ty9], .bool), some ([ty55, ty174, ty174, ty259], ty175), some ([ty90], ty90), some ([ty55, ty174, ty174, ty237], ty175), some ([ty55, ty174, ty174, ty237], ty175), some ([ty9], ty53), some ([ty4, ty90], ty90), some ([ty4, ty90], ty90), some ([ty4, ty90], ty90), some ([ty4, ty4, ty90], ty90), some ([ty4, ty90], ty90), some ([ty8, ty53, ty90], ty175), some ([ty4, ty175], ty175), some ([ty8, ty8, ty90], ty175), some ([ty4], ty53)]

/-- `declareFuncs` of functions 1200 to 1299. -/
theorem dchunk12 : declsStep dpart12 decls 34 54 31 51 = true := by decide +kernel

theorem dfit12 : entriesFit dpart12 dents12 = true := by decide +kernel

end Lanius.Faithful.SelfPure

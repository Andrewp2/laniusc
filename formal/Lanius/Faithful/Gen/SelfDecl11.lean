module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc0
public import Lanius.Faithful.Gen.SelfSrc1
public import Lanius.Faithful.Gen.SelfSrc2
public import Lanius.Faithful.Gen.SelfSrc3
public import Lanius.Faithful.Gen.SelfSrc4
public import Lanius.Faithful.Gen.SelfSrc5
public import Lanius.Faithful.Gen.SelfSrc6
public import Lanius.Faithful.Gen.SelfSrc7
public import Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
public import Lanius.Faithful.Gen.SelfSrcC_Word_compute
public import Lanius.Faithful.Gen.SelfSrcC_Word_narrows
public import Lanius.Faithful.Gen.SelfSrcC_declareProgram
public import Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
public import Lanius.Faithful.Gen.SelfSrcF_Inline_positionAt
public import Lanius.Faithful.Gen.SelfSrcF_allWeighed
public import Lanius.Faithful.Gen.SelfSrcF_allocClosed
public import Lanius.Faithful.Gen.SelfSrcF_assertClosed
public import Lanius.Faithful.Gen.SelfSrcF_blockArmsOf
public import Lanius.Faithful.Gen.SelfSrcF_collect
public import Lanius.Faithful.Gen.SelfSrcF_consTys
public import Lanius.Faithful.Gen.SelfSrcF_eStructClosed
public import Lanius.Faithful.Gen.SelfSrcF_effNamedTys
public import Lanius.Faithful.Gen.SelfSrcF_externBody
public import Lanius.Faithful.Gen.SelfSrcF_findConst
public import Lanius.Faithful.Gen.SelfSrcF_funcsOnto
public import Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
public import Lanius.Faithful.Gen.SelfSrcF_joinInsts
public import Lanius.Faithful.Gen.SelfSrcF_letClosed
public import Lanius.Faithful.Gen.SelfSrcF_letStructClosed
public import Lanius.Faithful.Gen.SelfSrcF_lowerTy
public import Lanius.Faithful.Gen.SelfSrcF_negWideI32
public import Lanius.Faithful.Gen.SelfSrcF_paramGoals
public import Lanius.Faithful.Gen.SelfSrcF_projectionRet
public import Lanius.Faithful.Gen.SelfSrcF_readInst
public import Lanius.Faithful.Gen.SelfSrcF_setEvalClosed
public import Lanius.Faithful.Gen.SelfSrcF_sintAt
public import Lanius.Faithful.Gen.SelfSrcF_textSelf
public import Lanius.Faithful.Gen.SelfSrcF_wideLeftStmt
public import Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc0
import all Lanius.Faithful.Gen.SelfSrc1
import all Lanius.Faithful.Gen.SelfSrc2
import all Lanius.Faithful.Gen.SelfSrc3
import all Lanius.Faithful.Gen.SelfSrc4
import all Lanius.Faithful.Gen.SelfSrc5
import all Lanius.Faithful.Gen.SelfSrc6
import all Lanius.Faithful.Gen.SelfSrc7
import all Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
import all Lanius.Faithful.Gen.SelfSrcC_Word_compute
import all Lanius.Faithful.Gen.SelfSrcC_Word_narrows
import all Lanius.Faithful.Gen.SelfSrcC_declareProgram
import all Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_positionAt
import all Lanius.Faithful.Gen.SelfSrcF_allWeighed
import all Lanius.Faithful.Gen.SelfSrcF_allocClosed
import all Lanius.Faithful.Gen.SelfSrcF_assertClosed
import all Lanius.Faithful.Gen.SelfSrcF_blockArmsOf
import all Lanius.Faithful.Gen.SelfSrcF_collect
import all Lanius.Faithful.Gen.SelfSrcF_consTys
import all Lanius.Faithful.Gen.SelfSrcF_eStructClosed
import all Lanius.Faithful.Gen.SelfSrcF_effNamedTys
import all Lanius.Faithful.Gen.SelfSrcF_externBody
import all Lanius.Faithful.Gen.SelfSrcF_findConst
import all Lanius.Faithful.Gen.SelfSrcF_funcsOnto
import all Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
import all Lanius.Faithful.Gen.SelfSrcF_joinInsts
import all Lanius.Faithful.Gen.SelfSrcF_letClosed
import all Lanius.Faithful.Gen.SelfSrcF_letStructClosed
import all Lanius.Faithful.Gen.SelfSrcF_lowerTy
import all Lanius.Faithful.Gen.SelfSrcF_negWideI32
import all Lanius.Faithful.Gen.SelfSrcF_paramGoals
import all Lanius.Faithful.Gen.SelfSrcF_projectionRet
import all Lanius.Faithful.Gen.SelfSrcF_readInst
import all Lanius.Faithful.Gen.SelfSrcF_setEvalClosed
import all Lanius.Faithful.Gen.SelfSrcF_sintAt
import all Lanius.Faithful.Gen.SelfSrcF_textSelf
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

/-- Functions 1100 to 1199, and their signature entries. -/
def dpart11 : List SrcFunc := [(src_fn_name_at 895 898 1098), (src_type_only_at 895 899 1098), (src_alias_name_at 895 900 1098), (src_const_name_at 895 901 1098), (src_enum_named_ok 895 896 1292), (src_spelled1 76 1293), (src_cons_func_tail 918), (src_empty_of_mini_selfhost_SrcParam), (src_cons_src_param 1294), (src_close_ty 56 629 930 1109 1113 1295 1296 1297), (src_let_closed 1143), (src_let_struct_closed 1143), (src_let_call_closed 1143), (src_inst_index 634 1298), (src_let_enum_closed 1143), (src_let_match_closed 1143), (src_src_enum_id), (src_set_call_closed), (src_then_closed 1143), (src_if_closed 1143), (src_while_closed 1143), (src_alloc_closed 1143), (src_let_slice_closed 1143), (src_let_index_closed 1143), (src_let_eval_closed 1143), (src_close_eff 1109 1113 1125 1167 1168 1299 1300 1301 1302 1303 1304 1305 1306 1307 1308 1309 1310), (src_set_eval_closed), (src_if_eval_closed 1143), (src_while_eval_closed 1143), (src_return_eval_closed), (src_discard_closed), (src_set_index_eval_closed), (src_set_field_eval_closed), (src_assert_closed), (src_match_arm_closed 1143), (src_arm_ty_closed), (src_unreachable_closed), (src_boxed_of_mini_selfhost_List_core_option_Option_mini_selfhost_SrcType 50 1311 1312), (src_get_of_mini_selfhost_TypeDecl 56 269 1138), (src_lower_decl 56 1189 1313 1314 1315 1316 1317), (src_wide_left_stmt 81 1140 1318 1319 1320 1321), (src_boxed_of_mini_selfhost_List_mini_selfhost_SrcFunc 50 82 1322), (src_lit_expr 303 1142 1323 1324 1325 1326 1327 1328 1329 1330 1331 1332), (src_boxed_of_mini_selfhost_SrcStmt 50 112 1333), (src_with_local 1156), (src_lit_exprs 311 1142 1145 1334 1335 1336 1337), (src_src_fields 178 181 1338), (src_callee_params 1339 1340), (src_payload_at 366), (src_src_variants 180), (src_lit_src_arms 1031 1142 1148 1150 1341 1342 1343 1344), (src_ty_local 1345 1346), (src_ty_at 494), (src_src_element 181), (src_lit_eff 343 345 1142 1146 1147 1148 1149 1154 1328 1330 1347 1348 1349 1350 1351), (src_empty_of_mini_selfhost_LocalTy), (src_cons_of_mini_selfhost_LocalTy 1352), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_core_option_Option_usize), (src_weighed_more 922 1353), (src_weigh_round_at 922 924 925 926 1354), (src_boxed_of_mini_selfhost_List_core_option_Option_usize 50 1157 1355), (src_inst_member 634 1161 1356), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_Ty), (src_decl_insts 56 1189 1315 1357 1358), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MParam), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_MStmt), (src_effs_named_tys 422 635 937 1166 1167), (src_unbox_of_mini_selfhost_List_mini_selfhost_MEff 1359), (src_unbox_of_mini_selfhost_MEff 1360), (src_effs_calls 265 941 942 1167 1169), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_MFunc), (src_module_globals 897 900 901 1361), (src_field_start_Token_of_mini_selfhost_Token), (src_length_of_mini_selfhost_Ty 75 629 1173), (src_extern_body 1181 1182), (src_params_of 103 1362 1363), (src_empty_of_mini_selfhost_Local), (src_result_of 152 155 1364 1365 1366 1367 1368), (src_never_ret 152 155 1365 1366), (src_last_ty 629 1179), (src_boxed_of_mini_selfhost_MStmt 50 1165 1369), (src_boxed_of_mini_selfhost_List_mini_selfhost_MEff 50 1359 1370), (src_param_effs 935 1182 1371 1372), (src_ret_expected), (src_fn_bounds_ok 155 1373 1374 1375), (src_ref_checked 1376 1377), (src_func_params 1378), (src_self_ref_id 1379), (src_boxed_of_mini_selfhost_List_mini_selfhost_MParam 50 1164 1380), (src_field_tys 1138 1381 1382), (src_BinOp_folds), (src_Word_compute 963 1383), (src_BinOp_annihilates), (src_BinOp_commutes), (src_Word_same_operand 963), (src_BinOp_unit), (src_Word_keeps 1384), (src_CmpOp_test), (src_signed_key 963), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Fact)]

def dents11 : List SigEntry := [some ([ty110, ty112, ty27], ty27), some ([ty107, ty109, ty27], ty27), some ([ty119, ty121, ty27], ty27), some ([ty113, ty115, ty27], ty27), some ([ty107, ty27, ty27], .bool), some ([ty20, (.uint .usize)], .bool), some ([ty31, ty227], ty227), some ([], ty12), some ([(.uint .usize), ty177, ty260], ty260), some ([(.uint .usize), ty226, ty152], ty177), some ([(.uint .usize), ty177, ty15, ty261], ty261), some ([(.uint .usize), ty177, ty18, ty261], ty261), some ([(.uint .usize), ty177, ty238, ty18, ty261], ty261), some ([ty156, ty154, (.uint .usize)], ty238), some ([(.uint .usize), ty177, (.uint .usize), ty18, ty261], ty261), some ([(.uint .usize), ty177, (.uint .usize), ty238, ty23, ty261], ty261), some ([ty177], ty238), some ([(.uint .usize), ty238, ty18], ty261), some ([ty261, ty261], ty261), some ([ty15, ty261, ty261], ty261), some ([ty15, ty261], ty261), some ([(.uint .usize), ty15, (.uint .usize), ty261], ty261), some ([(.uint .usize), ty177, ty15, ty15, ty261], ty261), some ([(.uint .usize), ty177, (.uint .usize), ty15, ty261], ty261), some ([(.uint .usize), ty177, ty277, ty261], ty261), some ([(.uint .usize), ty226, ty191], ty277), some ([(.uint .usize), ty277], ty261), some ([ty277, ty261, ty261], ty261), some ([ty277, ty261], ty261), some ([ty277], ty261), some ([ty277], ty261), some ([(.uint .usize), ty277, ty277], ty261), some ([(.uint .usize), (.uint .usize), ty277], ty261), some ([ty277], ty261), some ([(.uint .usize), ty238, (.uint .usize), .bool, (.uint .usize), ty177, ty261, ty261], ty261), some ([.bool, ty177], ty177), some ([(.uint .usize), ty177], ty261), some ([ty225], ty224), some ([ty109, (.uint .usize)], ty240), some ([(.uint .usize), ty127, ty156, .bool, ty238, (.uint .usize), ty153], ty177), some ([ty30], .bool), some ([ty33], ty32), some ([ty264, ty177, ty15], ty15), some ([ty30], ty16), some ([(.uint .usize), ty9, ty264], ty264), some ([ty264, ty215, ty18], ty18), some ([ty177], ty215), some ([ty33, (.uint .usize)], ty215), some ([ty216, (.uint .usize)], ty215), some ([ty177], ty216), some ([ty264, ty216, ty9, ty23], ty23), some ([ty264, (.uint .usize)], ty177), some ([ty215, (.uint .usize)], ty177), some ([ty177], ty177), some ([ty33, ty264, ty177, ty29], ty29), some ([], ty264), some ([ty262, ty264], ty264), none, some ([ty243, ty243], .bool), some ([(.uint .usize), ty127, ty156, ty243, ty154, ty156, ty243], ty243), some ([ty243], ty242), some ([ty156, ty154], .bool), none, some ([(.uint .usize), ty127, .bool, (.uint .usize), ty153], ty223), none, none, some ([ty280], ty153), some ([ty189], ty280), some ([ty190], ty191), some ([ty280], ty156), none, some ([ty127, ty27], ty27), some ([ty42], (.uint .usize)), some ([ty153], (.uint .usize)), some ([ty287, ty270, (.uint .usize)], ty228), some ([(.uint .usize), ty269, ty110, ty285, ty85], ty287), some ([], ty285), some ([(.uint .usize), ty269, ty84], ty270), some ([ty110], .bool), some ([ty153], ty247), some ([ty192], ty188), some ([ty280], ty189), some ([ty186], ty280), some ([ty270], ty247), some ([(.uint .usize), ty127, ty110, ty269], .bool), some ([ty228, ty238], ty228), some ([(.uint .usize), ty269, ty287, ty270, ty84, ty84], ty228), some ([ty269, ty85], ty238), some ([ty186], ty185), some ([(.uint .usize), ty127, (.uint .usize), ty153], ty248), some ([ty52], .bool), some ([ty51, ty52, (.uint .uint64), (.uint .uint64)], (.uint .uint64)), some ([ty52], .bool), some ([ty52], .bool), some ([ty51, (.uint .uint64), (.uint .uint64)], .bool), some ([ty52], (.uint .uint64)), some ([ty51, ty90], .bool), some ([ty53, (.uint .uint64), (.uint .uint64)], .bool), some ([(.uint .uint64)], (.uint .uint64)), none]

/-- `declareFuncs` of functions 1100 to 1199. -/
theorem dchunk11 : declsStep dpart11 decls 31 52 28 47 = true := by decide +kernel

theorem dfit11 : entriesFit dpart11 dents11 = true := by decide +kernel

end Lanius.Faithful.SelfPure

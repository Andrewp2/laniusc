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
public import Lanius.Faithful.Gen.SelfSrcC_DivOp_size
public import Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
public import Lanius.Faithful.Gen.SelfSrcC_Inline_arithOf
public import Lanius.Faithful.Gen.SelfSrcC_Inline_lowerSetScalar
public import Lanius.Faithful.Gen.SelfSrcC_Lists_empty
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
public import Lanius.Faithful.Gen.SelfSrcF_blockArmsOf
public import Lanius.Faithful.Gen.SelfSrcF_collect
public import Lanius.Faithful.Gen.SelfSrcF_consTys
public import Lanius.Faithful.Gen.SelfSrcF_effNamedTys
public import Lanius.Faithful.Gen.SelfSrcF_externBody
public import Lanius.Faithful.Gen.SelfSrcF_findConst
public import Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
public import Lanius.Faithful.Gen.SelfSrcF_joinInsts
public import Lanius.Faithful.Gen.SelfSrcF_letStructClosed
public import Lanius.Faithful.Gen.SelfSrcF_lowerTy
public import Lanius.Faithful.Gen.SelfSrcF_negWideI32
public import Lanius.Faithful.Gen.SelfSrcF_paramGoals
public import Lanius.Faithful.Gen.SelfSrcF_projectionRet
public import Lanius.Faithful.Gen.SelfSrcF_readInst
public import Lanius.Faithful.Gen.SelfSrcF_sintAt
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
import all Lanius.Faithful.Gen.SelfSrcC_DivOp_size
import all Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
import all Lanius.Faithful.Gen.SelfSrcC_Inline_arithOf
import all Lanius.Faithful.Gen.SelfSrcC_Inline_lowerSetScalar
import all Lanius.Faithful.Gen.SelfSrcC_Lists_empty
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
import all Lanius.Faithful.Gen.SelfSrcF_blockArmsOf
import all Lanius.Faithful.Gen.SelfSrcF_collect
import all Lanius.Faithful.Gen.SelfSrcF_consTys
import all Lanius.Faithful.Gen.SelfSrcF_effNamedTys
import all Lanius.Faithful.Gen.SelfSrcF_externBody
import all Lanius.Faithful.Gen.SelfSrcF_findConst
import all Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
import all Lanius.Faithful.Gen.SelfSrcF_joinInsts
import all Lanius.Faithful.Gen.SelfSrcF_letStructClosed
import all Lanius.Faithful.Gen.SelfSrcF_lowerTy
import all Lanius.Faithful.Gen.SelfSrcF_negWideI32
import all Lanius.Faithful.Gen.SelfSrcF_paramGoals
import all Lanius.Faithful.Gen.SelfSrcF_projectionRet
import all Lanius.Faithful.Gen.SelfSrcF_readInst
import all Lanius.Faithful.Gen.SelfSrcF_sintAt
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
def dpart11 : List SrcFunc := [(src_match_arm_closed 1109), (src_arm_ty_closed), (src_unreachable_closed), (src_boxed_of_mini_selfhost_List_core_option_Option_mini_selfhost_SrcType 50 1273 1274), (src_get_of_mini_selfhost_TypeDecl 56 257 1104), (src_lower_decl 56 1151 1275 1276 1277 1278 1279), (src_wide_left_stmt 81 1106 1280 1281 1282 1283), (src_boxed_of_mini_selfhost_List_mini_selfhost_SrcFunc 50 82 1284), (src_lit_expr 287 1108 1285 1286 1287 1288 1289 1290 1291 1292 1293 1294), (src_boxed_of_mini_selfhost_SrcStmt 50 112 1295), (src_with_local 1122), (src_lit_exprs 295 1108 1111 1296 1297 1298 1299), (src_src_fields 166 169 1300), (src_callee_params 1301 1302), (src_payload_at 350), (src_src_variants 168), (src_lit_src_arms 997 1108 1114 1116 1303 1304 1305 1306), (src_ty_local 1307 1308), (src_ty_at 471), (src_src_element 169), (src_lit_eff 327 329 1108 1112 1113 1114 1115 1120 1290 1292 1309 1310 1311 1312 1313), (src_empty_of_mini_selfhost_LocalTy), (src_cons_of_mini_selfhost_LocalTy 1314), (src_inst_member 606 1123 1315), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_Ty), (src_decl_insts 56 1151 1277 1316 1317), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MParam), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_MStmt), (src_effs_named_tys 403 607 902 1128 1129), (src_unbox_of_mini_selfhost_List_mini_selfhost_MEff 1318), (src_unbox_of_mini_selfhost_MEff 1319), (src_effs_calls 253 906 907 1129 1131), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_MFunc), (src_module_globals 868 871 872 1320), (src_field_start_Token_of_mini_selfhost_Token), (src_length_of_mini_selfhost_Ty 75 601 1135), (src_extern_body 1143 1144), (src_params_of 103 1321 1322), (src_empty_of_mini_selfhost_Local), (src_result_of 144 147 1323 1324 1325 1326 1327), (src_never_ret 144 147 1324 1325), (src_last_ty 601 1141), (src_boxed_of_mini_selfhost_MStmt 50 1127 1328), (src_boxed_of_mini_selfhost_List_mini_selfhost_MEff 50 1318 1329), (src_param_effs 900 1144 1330 1331), (src_ret_expected), (src_fn_bounds_ok 147 1332 1333 1334), (src_ref_checked 1335 1336), (src_func_params 1337), (src_self_ref_id 1338), (src_boxed_of_mini_selfhost_List_mini_selfhost_MParam 50 1126 1339), (src_field_tys 1104 1340 1341), (src_BinOp_folds), (src_Word_compute 928 1342), (src_BinOp_annihilates), (src_BinOp_commutes), (src_Word_same_operand 928), (src_BinOp_unit), (src_Word_keeps 1343), (src_CmpOp_test), (src_signed_key 928), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Fact), (src_Expr_is_atom), (src_Expr_mentions 441 1163), (src_cons_of_mini_selfhost_Fact 1344), (src_trim_facts 1345 1346), (src_kill_prefix 56 263 934 1166 1347 1348), (src_dying_extent 75 934 1167 1349 1350), (src_Stmt_ignores 281 1163 1168 1170), (src_Stmt_jumps 281 1169), (src_mentions_any 442 1163 1170), (src_Expr_is_constant 942), (src_neg_agrees 441 938), (src_binary_agrees 441 938 945 1351), (src_unit_agrees 938 1155 1158 1352), (src_compare_agrees 441 938 945 1353), (src_fp_agrees 441 938 1354), (src_fold_constant 1152 1153), (src_absorbed 1154), (src_unbox_of_mini_selfhost_List_mini_selfhost_Arity 683), (src_FloatTy_rex_size), (src_slot_offset 75 105), (src_slot_operands 438 685 686 958), (src_Word_rex 110 686), (src_BinOp_opcode 685 686), (src_CmpOp_setcc 1355 1356), (src_pow2 56 1186), (src_MemWidth_rex 110 686), (src_DivOp_extend 438 685 686 1183), (src_DivOp_opcode 685 686), (src_DivOp_result 110 685 686), (src_FOp_opcode_bytes 438 685 686 1183 1357 1358 1359 1360 1361), (src_syscall_rsi_bytes 685 686), (src_syscall_linux_byte), (src_syscall_linux_high), (src_lower_scalar_slot 291), (src_float_arith 1362), (src_SrcType_is_sint_any), (src_arith_sint 1363), (src_arith_uint 1364)]

def dents11 : List SigEntry := [some ([(.uint .usize), ty238, (.uint .usize), .bool, (.uint .usize), ty177, ty259, ty259], ty259), some ([.bool, ty177], ty177), some ([(.uint .usize), ty177], ty259), some ([ty225], ty224), some ([ty109, (.uint .usize)], ty240), some ([(.uint .usize), ty127, ty157, .bool, ty238, (.uint .usize), ty154], ty177), some ([ty30], .bool), some ([ty33], ty32), some ([ty262, ty177, ty15], ty15), some ([ty30], ty16), some ([(.uint .usize), ty9, ty262], ty262), some ([ty262, ty215, ty18], ty18), some ([ty177], ty215), some ([ty33, (.uint .usize)], ty215), some ([ty216, (.uint .usize)], ty215), some ([ty177], ty216), some ([ty262, ty216, ty9, ty23], ty23), some ([ty262, (.uint .usize)], ty177), some ([ty215, (.uint .usize)], ty177), some ([ty177], ty177), some ([ty33, ty262, ty177, ty29], ty29), some ([], ty262), some ([ty260, ty262], ty262), some ([ty157, ty155], .bool), none, some ([(.uint .usize), ty127, .bool, (.uint .usize), ty154], ty223), none, none, some ([ty277], ty154), some ([ty189], ty277), some ([ty190], ty191), some ([ty277], ty157), none, some ([ty127, ty27], ty27), some ([ty42], (.uint .usize)), some ([ty154], (.uint .usize)), some ([ty284, ty267, (.uint .usize)], ty228), some ([(.uint .usize), ty266, ty110, ty282, ty85], ty284), some ([], ty282), some ([(.uint .usize), ty266, ty84], ty267), some ([ty110], .bool), some ([ty154], ty245), some ([ty192], ty188), some ([ty277], ty189), some ([ty186], ty277), some ([ty267], ty245), some ([(.uint .usize), ty127, ty110, ty266], .bool), some ([ty228, ty238], ty228), some ([(.uint .usize), ty266, ty284, ty267, ty84, ty84], ty228), some ([ty266, ty85], ty238), some ([ty186], ty185), some ([(.uint .usize), ty127, (.uint .usize), ty154], ty246), some ([ty52], .bool), some ([ty51, ty52, (.uint .uint64), (.uint .uint64)], (.uint .uint64)), some ([ty52], .bool), some ([ty52], .bool), some ([ty51, (.uint .uint64), (.uint .uint64)], .bool), some ([ty52], (.uint .uint64)), some ([ty51, ty90], .bool), some ([ty53, (.uint .uint64), (.uint .uint64)], .bool), some ([(.uint .uint64)], (.uint .uint64)), none, some ([ty90], .bool), some ([ty90, (.uint .usize)], .bool), some ([ty201, ty203], ty203), some ([ty203], ty203), some ([ty203, (.uint .usize), (.uint .usize)], ty203), some ([ty203, (.uint .usize), (.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty94, (.uint .usize)], .bool), some ([ty94], .bool), some ([ty93, (.uint .usize)], .bool), some ([ty90, ty230], .bool), some ([ty90, ty90], .bool), some ([ty51, ty52, ty90, ty90, ty90], .bool), some ([ty51, ty52, ty90, ty90, ty90], .bool), some ([ty51, ty53, ty90, ty90, ty90], .bool), some ([ty58, ty90, ty90, ty90], .bool), some ([ty51, ty52, (.uint .uint64), (.uint .uint64)], ty230), some ([ty52, (.uint .uint64)], ty230), some ([ty161], ty162), some ([ty8], (.uint .usize)), some ([(.uint .usize)], .i32), some ([(.uint .usize)], ty67), some ([ty51], ty67), some ([ty52], ty67), some ([ty53, ty51], (.uint .uint8)), some ([(.uint .usize)], (.uint .uint64)), some ([ty54], ty67), some ([ty55, ty51], ty67), some ([ty55], ty67), some ([ty55], ty67), some ([ty58], ty67), some ([ty59], ty67), some ([ty59], (.uint .uint8)), some ([ty59], (.uint .uint8)), some ([(.uint .usize), ty9], ty174), some ([ty52, ty173, ty173, ty252], ty174), some ([ty9], .bool), some ([ty52, ty173, ty173, ty233], ty174), some ([ty52, ty173, ty173, ty233], ty174)]

/-- `declareFuncs` of functions 1100 to 1199. -/
theorem dchunk11 : declsStep dpart11 decls 31 50 28 46 = true := by decide +kernel

theorem dfit11 : entriesFit dpart11 dents11 = true := by decide +kernel

end Lanius.Faithful.SelfPure

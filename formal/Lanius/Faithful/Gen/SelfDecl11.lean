module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc0
public import Lanius.Faithful.Gen.SelfSrc1
public import Lanius.Faithful.Gen.SelfSrc2
public import Lanius.Faithful.Gen.SelfSrc3
public import Lanius.Faithful.Gen.SelfSrc6
public import Lanius.Faithful.Gen.SelfSrc7
public import Lanius.Faithful.Gen.SelfSrcF_Inline_attachNode
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pBoundTypeArgsAfterCommaMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_positionAt
public import Lanius.Faithful.Gen.SelfSrcF_allWeighed
public import Lanius.Faithful.Gen.SelfSrcF_allocClosed
public import Lanius.Faithful.Gen.SelfSrcF_assertClosed
public import Lanius.Faithful.Gen.SelfSrcF_collect
public import Lanius.Faithful.Gen.SelfSrcF_depthLimit
public import Lanius.Faithful.Gen.SelfSrcF_eDerefClosed
public import Lanius.Faithful.Gen.SelfSrcF_eStructClosed
public import Lanius.Faithful.Gen.SelfSrcF_findConst
public import Lanius.Faithful.Gen.SelfSrcF_funcsBytes
public import Lanius.Faithful.Gen.SelfSrcF_genericOpen
public import Lanius.Faithful.Gen.SelfSrcF_letClosed
public import Lanius.Faithful.Gen.SelfSrcF_letStructClosed
public import Lanius.Faithful.Gen.SelfSrcF_limLeaf
public import Lanius.Faithful.Gen.SelfSrcF_lowerTy
public import Lanius.Faithful.Gen.SelfSrcF_lxCanonicalKind
public import Lanius.Faithful.Gen.SelfSrcF_lxDotAt
public import Lanius.Faithful.Gen.SelfSrcF_lxExponent
public import Lanius.Faithful.Gen.SelfSrcF_lxLeadingDot
public import Lanius.Faithful.Gen.SelfSrcF_lxSpaceEnd
public import Lanius.Faithful.Gen.SelfSrcF_lxSymbolStart
public import Lanius.Faithful.Gen.SelfSrcF_methodDecl
public import Lanius.Faithful.Gen.SelfSrcF_moduleOr
public import Lanius.Faithful.Gen.SelfSrcF_negWideI32
public import Lanius.Faithful.Gen.SelfSrcF_setEvalClosed
public import Lanius.Faithful.Gen.SelfSrcF_strBytes
public import Lanius.Faithful.Gen.SelfSrcF_textSelf
public import Lanius.Faithful.Gen.SelfSrcF_wideLeftStmt
public import Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc0
import all Lanius.Faithful.Gen.SelfSrc1
import all Lanius.Faithful.Gen.SelfSrc2
import all Lanius.Faithful.Gen.SelfSrc3
import all Lanius.Faithful.Gen.SelfSrc6
import all Lanius.Faithful.Gen.SelfSrc7
import all Lanius.Faithful.Gen.SelfSrcF_Inline_attachNode
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pBoundTypeArgsAfterCommaMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_positionAt
import all Lanius.Faithful.Gen.SelfSrcF_allWeighed
import all Lanius.Faithful.Gen.SelfSrcF_allocClosed
import all Lanius.Faithful.Gen.SelfSrcF_assertClosed
import all Lanius.Faithful.Gen.SelfSrcF_collect
import all Lanius.Faithful.Gen.SelfSrcF_depthLimit
import all Lanius.Faithful.Gen.SelfSrcF_eDerefClosed
import all Lanius.Faithful.Gen.SelfSrcF_eStructClosed
import all Lanius.Faithful.Gen.SelfSrcF_findConst
import all Lanius.Faithful.Gen.SelfSrcF_funcsBytes
import all Lanius.Faithful.Gen.SelfSrcF_genericOpen
import all Lanius.Faithful.Gen.SelfSrcF_letClosed
import all Lanius.Faithful.Gen.SelfSrcF_letStructClosed
import all Lanius.Faithful.Gen.SelfSrcF_limLeaf
import all Lanius.Faithful.Gen.SelfSrcF_lowerTy
import all Lanius.Faithful.Gen.SelfSrcF_lxCanonicalKind
import all Lanius.Faithful.Gen.SelfSrcF_lxDotAt
import all Lanius.Faithful.Gen.SelfSrcF_lxExponent
import all Lanius.Faithful.Gen.SelfSrcF_lxLeadingDot
import all Lanius.Faithful.Gen.SelfSrcF_lxSpaceEnd
import all Lanius.Faithful.Gen.SelfSrcF_lxSymbolStart
import all Lanius.Faithful.Gen.SelfSrcF_methodDecl
import all Lanius.Faithful.Gen.SelfSrcF_moduleOr
import all Lanius.Faithful.Gen.SelfSrcF_negWideI32
import all Lanius.Faithful.Gen.SelfSrcF_setEvalClosed
import all Lanius.Faithful.Gen.SelfSrcF_strBytes
import all Lanius.Faithful.Gen.SelfSrcF_textSelf
import all Lanius.Faithful.Gen.SelfSrcF_wideLeftStmt
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

/-- Functions 1100 to 1199, and their signature entries. -/
def dpart11 : List SrcFunc := [(src_lx_ident_end 75 593 1331), (src_lx_digit), (src_lx_from_number), (src_lx_number 75 1332 1333 1334), (src_lx_space), (src_lx_space_end 75 593 1335), (src_lx_delimited), (src_lx_quoted 76 1336), (src_lx_symbol_start), (src_lx_symbol 830 1337), (src_boxed_of_mini_selfhost_List_mini_selfhost_RawTok 50 836 1338), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SymRule), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SymRule), (src_boxed_of_mini_selfhost_List_mini_selfhost_Token 50 280 1339), (src_lx_token_text 934 1340), (src_lx_take 56 76 139 418 1115), (src_lx_keyword 1341 1342), (src_picks 645 1343 1344 1345 1346 1347 1348 1349 1350), (src_get_of_mini_selfhost_Rule 44 56 1118), (src_attach_node 75 149 1351), (src_concat_of_mini_selfhost_CTree 103 254 1120), (src_struct_decl_fields 265 940 1123), (src_fields_of 96 103 265 1122 1352), (src_empty_of_mini_selfhost_List_mini_selfhost_CTree), (src_cons_variant 1353), (src_variant_payload 96 153 155 156 1354), (src_param_spelling_at 153 627 628 649 925 1355), (src_method_decl 153 156 623 624 1356 1357 1358), (src_cons_of_mini_selfhost_ImplDecl 692), (src_p_type_param_bound_none), (src_text_write_byte 376 418), (src_text_write_stdout 376 418), (src_text_write_stderr 376 418), (src_text_read_stdin 376 418), (src_text_sleep_ms_i32 376 418), (src_text_monotonic_read 376 418), (src_text_system_read 376 418), (src_text_fill_secure_bytes 376 418), (src_text_write_text 376 418), (src_text_write_newline 376 418), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_List_usize), (src_cons_of_mini_selfhost_List_usize 937), (src_member 558 934 1142), (src_fn_name_at 939 942 1141), (src_type_only_at 939 943 1141), (src_alias_name_at 939 944 1141), (src_const_name_at 939 945 1141), (src_enum_named_ok 939 940 1359), (src_spelled1 76 1360), (src_cons_func_tail 965), (src_empty_of_mini_selfhost_SrcParam), (src_cons_src_param 1361), (src_close_ty 56 666 977 1152 1156 1362 1363 1364 1365), (src_let_closed 1197), (src_let_struct_closed 1197), (src_let_call_closed 1197), (src_inst_index 671 1366), (src_let_enum_closed 1197), (src_let_match_closed 1197), (src_src_enum_id), (src_set_call_closed), (src_then_closed 1197), (src_if_closed 1197), (src_while_closed 1197), (src_alloc_closed 1197), (src_let_slice_closed 1197), (src_let_index_closed 1197), (src_let_view_closed 1197), (src_let_str_closed 1197), (src_let_eval_closed 1197), (src_close_eff 1152 1156 1170 1223 1224 1367 1368 1369 1370 1371 1372 1373 1374 1375 1376 1377 1378 1379 1380 1381 1382 1383), (src_set_eval_closed), (src_if_eval_closed 1197), (src_while_eval_closed 1197), (src_return_eval_closed), (src_discard_closed), (src_set_index_eval_closed), (src_set_field_eval_closed), (src_assert_closed), (src_match_arm_closed 1197), (src_arm_ty_closed), (src_unreachable_closed), (src_set_place_closed), (src_set_place_op_closed), (src_boxed_of_mini_selfhost_List_core_option_Option_mini_selfhost_SrcType 50 1384 1385), (src_get_of_mini_selfhost_TypeDecl 56 276 1185), (src_lower_decl 56 1246 1386 1387 1388 1389 1390), (src_wide_left_stmt 81 1187 1391 1392 1393 1394), (src_lim_params 174 1188 1190), (src_lim_param_slots 174 1189 1395 1396), (src_lim_ty 968 1396), (src_lim_stmt 81 1191 1395 1396 1397 1398 1399 1400 1401 1402 1403 1404 1405 1406), (src_place_stmt 81 754 1192 1193 1197 1407 1408), (src_stmt_bytes 81 110 754 1193 1408), (src_funcs_bytes 59 110 754 1193 1194), (src_boxed_of_mini_selfhost_List_mini_selfhost_SrcFunc 50 82 1409), (src_lit_expr 313 1196 1410 1411 1412 1413 1414 1415 1416 1417 1418 1419), (src_boxed_of_mini_selfhost_SrcStmt 50 112 1420), (src_with_local 1211), (src_lit_exprs 321 1196 1199 1421 1422 1423 1424)]

def dents11 : List SigEntry := [some ([ty20, (.uint .usize)], (.uint .usize)), some ([(.uint .usize)], .bool), some ([(.uint .usize), ty281], ty224), some ([ty20, (.uint .usize)], ty281), some ([(.uint .usize)], .bool), some ([ty20, (.uint .usize)], (.uint .usize)), some ([(.uint .usize), (.uint .usize), ty282], ty224), some ([(.uint .usize), .bool, ty20, (.uint .usize)], ty282), some ([(.uint .usize)], .bool), some ([ty223, ty20, (.uint .usize)], ty224), some ([ty183], ty182), none, none, some ([ty47], ty46), some ([ty181, ty20], ty45), some ([ty20, (.uint .usize)], ty20), some ([ty20, ty223], ty146), some ([(.uint .usize), ty47], .bool), some ([ty44, (.uint .usize)], ty263), some ([ty44, (.uint .usize), (.uint .usize), (.uint .usize), ty42, ty20, ty20, ty41, (.uint .usize), ty139], ty141), some ([ty86, ty86], ty86), some ([ty27, ty20, ty27, ty283], ty244), some ([ty86], ty283), some ([], ty107), some ([ty20, ty87, ty265], ty265), some ([(.uint .usize), ty85], ty87), some ([ty85, ty86], ty151), some ([(.uint .usize), ty27, ty27, ty85, ty85, ty85], ty233), some ([ty123, ty125], ty125), some ([], (.uint .usize)), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), some ([], ty20), none, some ([ty20, ty27], ty27), some ([ty27, ty20], .bool), some ([ty111, ty113, ty27], ty27), some ([ty108, ty110, ty27], ty27), some ([ty120, ty122, ty27], ty27), some ([ty114, ty116, ty27], ty27), some ([ty108, ty27, ty27], .bool), some ([ty20, (.uint .usize)], .bool), some ([ty32, ty231], ty231), some ([], ty12), some ([(.uint .usize), ty179, ty267], ty267), some ([(.uint .usize), ty230, ty154], ty179), some ([(.uint .usize), ty179, ty15, ty268], ty268), some ([(.uint .usize), ty179, ty18, ty268], ty268), some ([(.uint .usize), ty179, ty146, ty18, ty268], ty268), some ([ty158, ty156, (.uint .usize)], ty146), some ([(.uint .usize), ty179, (.uint .usize), ty18, ty268], ty268), some ([(.uint .usize), ty179, (.uint .usize), ty146, ty23, ty268], ty268), some ([ty179], ty146), some ([(.uint .usize), ty146, ty18], ty268), some ([ty268, ty268], ty268), some ([ty15, ty268, ty268], ty268), some ([ty15, ty268], ty268), some ([(.uint .usize), ty15, (.uint .usize), ty268], ty268), some ([(.uint .usize), ty179, ty15, ty15, ty268], ty268), some ([(.uint .usize), ty179, (.uint .usize), ty15, ty268], ty268), some ([(.uint .usize), (.uint .usize), ty18, (.uint .usize), ty268], ty268), some ([(.uint .usize), ty20, ty268], ty268), some ([(.uint .usize), ty179, ty284, ty268], ty268), some ([(.uint .usize), ty230, ty193], ty284), some ([(.uint .usize), ty284], ty268), some ([ty284, ty268, ty268], ty268), some ([ty284, ty268], ty268), some ([ty284], ty268), some ([ty284], ty268), some ([(.uint .usize), ty284, ty284], ty268), some ([(.uint .usize), (.uint .usize), ty284], ty268), some ([ty284], ty268), some ([(.uint .usize), ty146, (.uint .usize), .bool, (.uint .usize), ty179, ty268, ty268], ty268), some ([.bool, ty179], ty179), some ([(.uint .usize), ty179], ty268), some ([ty284, ty284], ty268), some ([ty30, ty284, ty284], ty268), some ([ty229], ty228), some ([ty110, (.uint .usize)], ty244), some ([(.uint .usize), ty128, ty158, .bool, ty146, (.uint .usize), ty155], ty179), some ([ty31], .bool), some ([ty12], .bool), some ([ty12], ty146), some ([ty9], .bool), some ([ty31], ty146), some ([ty36, ty31], ty31), some ([ty31], ty36), some ([ty34], ty36), some ([ty34], ty33), some ([ty271, ty179, ty15], ty15), some ([ty31], ty16), some ([(.uint .usize), ty9, ty271], ty271), some ([ty271, ty217, ty18], ty18)]

/-- `declareFuncs` of functions 1100 to 1199. -/
theorem dchunk11 : declsStep dpart11 decls 35 59 34 55 = true := by decide +kernel

theorem dfit11 : entriesFit dpart11 dents11 = true := by decide +kernel

end Lanius.Faithful.SelfPure

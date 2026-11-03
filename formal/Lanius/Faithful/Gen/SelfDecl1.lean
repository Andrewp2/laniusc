module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc0
public import Lanius.Faithful.Gen.SelfSrc1
public import Lanius.Faithful.Gen.SelfSrc2
public import Lanius.Faithful.Gen.SelfSrc3
public import Lanius.Faithful.Gen.SelfSrc4
public import Lanius.Faithful.Gen.SelfSrc5
public import Lanius.Faithful.Gen.SelfSrc7
public import Lanius.Faithful.Gen.SelfSrcC_Inline_blockLeft
public import Lanius.Faithful.Gen.SelfSrcC_SrcExpr_guard
public import Lanius.Faithful.Gen.SelfSrcC_SrcType_same
public import Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
public import Lanius.Faithful.Gen.SelfSrcC_arities
public import Lanius.Faithful.Gen.SelfSrcC_arrayCallSig
public import Lanius.Faithful.Gen.SelfSrcC_compileOr
public import Lanius.Faithful.Gen.SelfSrcC_funcNeeds
public import Lanius.Faithful.Gen.SelfSrcC_larger
public import Lanius.Faithful.Gen.SelfSrcC_linkedSize
public import Lanius.Faithful.Gen.SelfSrcC_lowerBody
public import Lanius.Faithful.Gen.SelfSrcC_lowerCallSig
public import Lanius.Faithful.Gen.SelfSrcC_lowerSetCallArgs
public import Lanius.Faithful.Gen.SelfSrcC_lowerTagged
public import Lanius.Faithful.Gen.SelfSrcC_matchVariants
public import Lanius.Faithful.Gen.SelfSrcC_needsAfter
public import Lanius.Faithful.Gen.SelfSrcC_optimizeIte
public import Lanius.Faithful.Gen.SelfSrcC_repeatType
public import Lanius.Faithful.Gen.SelfSrcC_withBudget
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pExpr
public import Lanius.Faithful.Gen.SelfSrcF_Inline_positionAt
public import Lanius.Faithful.Gen.SelfSrcF_collect
public import Lanius.Faithful.Gen.SelfSrcF_hasKids
public import Lanius.Faithful.Gen.SelfSrcF_isEmptyUsize
public import Lanius.Faithful.Gen.SelfSrcF_lxCanonicalKind
public import Lanius.Faithful.Gen.SelfSrcF_moduleOr
public import Lanius.Faithful.Gen.SelfSrcF_noToken
public import Lanius.Faithful.Gen.SelfSrcF_readCountedBytes
public import Lanius.Faithful.Gen.SelfSrcF_rootInsts
public import Lanius.Faithful.Gen.SelfSrcF_shrFirst
public import Lanius.Faithful.Gen.SelfSrcF_wideLeftStmt
public import Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc0
import all Lanius.Faithful.Gen.SelfSrc1
import all Lanius.Faithful.Gen.SelfSrc2
import all Lanius.Faithful.Gen.SelfSrc3
import all Lanius.Faithful.Gen.SelfSrc4
import all Lanius.Faithful.Gen.SelfSrc5
import all Lanius.Faithful.Gen.SelfSrc7
import all Lanius.Faithful.Gen.SelfSrcC_Inline_blockLeft
import all Lanius.Faithful.Gen.SelfSrcC_SrcExpr_guard
import all Lanius.Faithful.Gen.SelfSrcC_SrcType_same
import all Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
import all Lanius.Faithful.Gen.SelfSrcC_arities
import all Lanius.Faithful.Gen.SelfSrcC_arrayCallSig
import all Lanius.Faithful.Gen.SelfSrcC_compileOr
import all Lanius.Faithful.Gen.SelfSrcC_funcNeeds
import all Lanius.Faithful.Gen.SelfSrcC_larger
import all Lanius.Faithful.Gen.SelfSrcC_linkedSize
import all Lanius.Faithful.Gen.SelfSrcC_lowerBody
import all Lanius.Faithful.Gen.SelfSrcC_lowerCallSig
import all Lanius.Faithful.Gen.SelfSrcC_lowerSetCallArgs
import all Lanius.Faithful.Gen.SelfSrcC_lowerTagged
import all Lanius.Faithful.Gen.SelfSrcC_matchVariants
import all Lanius.Faithful.Gen.SelfSrcC_needsAfter
import all Lanius.Faithful.Gen.SelfSrcC_optimizeIte
import all Lanius.Faithful.Gen.SelfSrcC_repeatType
import all Lanius.Faithful.Gen.SelfSrcC_withBudget
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pExpr
import all Lanius.Faithful.Gen.SelfSrcF_Inline_positionAt
import all Lanius.Faithful.Gen.SelfSrcF_collect
import all Lanius.Faithful.Gen.SelfSrcF_hasKids
import all Lanius.Faithful.Gen.SelfSrcF_isEmptyUsize
import all Lanius.Faithful.Gen.SelfSrcF_lxCanonicalKind
import all Lanius.Faithful.Gen.SelfSrcF_moduleOr
import all Lanius.Faithful.Gen.SelfSrcF_noToken
import all Lanius.Faithful.Gen.SelfSrcF_readCountedBytes
import all Lanius.Faithful.Gen.SelfSrcF_rootInsts
import all Lanius.Faithful.Gen.SelfSrcF_shrFirst
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

/-- Functions 100 to 199, and their signature entries. -/
def dpart1 : List SrcFunc := [(src_file_decls 152 153 154 155 156 157), (src_build_collected 158 159 160 161 162), (src_collect_files 100 103 163), (src_unbox_of_mini_selfhost_List_mini_selfhost_CTree 164), (src_single_of_mini_selfhost_List_mini_selfhost_List_usize 165), (src_times 50), (src_length_of_mini_selfhost_Token 75 106 166), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Sym), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Sym), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_usize), (src_empty_of_u8), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_u8), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_SrcStmt), (src_optimize_program 167), (src_validate 168), (src_compile_or 116), (src_compile_program 169 170 171), (src_cons_of_mini_selfhost_Func 172), (src_params_size 75 118 120 173), (src_frame_block 174 175 176 177 178), (src_SrcType_size 75 105 120 179 180 181 182 183), (src_params_valid 120 121 173 184), (src_SrcStmt_breaks_out 81 122), (src_lower_body 75 185 186), (src_SrcStmt_depth 75 81 120 124 185), (src_unit_tail 57 187 188), (src_with_frame 187), (src_SrcStmt_lower 75 81 120 127 189 190 191 192 193 194 195 196 197 198 199 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216 217 218 219 220 221 222 223 224 225 226 227 228 229 230 231 232 233 234 235 236), (src_with_budget 87 128 132 133), (src_param_scope 75 120 129 173 193), (src_empty_of_mini_selfhost_Binding), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Sig), (src_empty_of_mini_selfhost_Sig), (src_cons_of_mini_selfhost_Sig 237), (src_param_types 134 173 238 239), (src_get_or_of_usize 56 76 135), (src_rest_needs 76 138), (src_needs_after 56 137 240 241), (src_empty_of_usize), (src_length_of_mini_selfhost_SrcFunc 59 75 139), (src_declare_params 142 173 242), (src_declare_in 243), (src_SrcType_declare 142 180 182 183 244 245 246 247), (src_read_bytes 10 41 56 138 143 248), (src_read_file_end 249 250), (src_read_nums 10 41 56 138 145 251), (src_boxed_of_mini_selfhost_List_mini_selfhost_FileInput 50 151 252), (src_cons_of_mini_selfhost_CTree 253), (src_attach 56 96 254 255), (src_single_of_mini_selfhost_Sym 74), (src_whole 103 256 257), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_FileInput), (src_node_prod), (src_p_file), (src_list_items 56 258 259), (src_kid 259 260 261), (src_file_items 262 263), (src_module_path 103 264 265 266), (src_build_checked 267 268 269 270), (src_root_insts 271 272 273), (src_field_fns_Decls_of_mini_selfhost_Decls), (src_seed_insts 271 274 275), (src_field_types_Decls_of_mini_selfhost_Decls), (src_collect_file_next 102 276), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_CTree), (src_boxed_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_List_usize 50 277 278), (src_unbox_of_mini_selfhost_List_mini_selfhost_Token 279), (src_optimize_funcs 84 117 167 280 281 282), (src_funcs_agree 168 282 283), (src_compile_funcs 169 282 284 285 286), (src_arities 170 282 287 288), (src_link 56 289 290 291 292), (src_boxed_of_mini_selfhost_List_mini_selfhost_Func 50 293 294), (src_unbox_of_mini_selfhost_List_mini_selfhost_SrcParam 295), (src_SrcStmt_slice_uses 81 138 174 296 297), (src_params_room 173 298 299 300), (src_block_limit), (src_block_left 56 176), (src_block_room 81 178 299 300 301), (src_sizes 75 120 179 180), (src_unbox_of_mini_selfhost_List_mini_selfhost_SrcType 302), (src_max_size 179 181 182 185), (src_unbox_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_SrcType 303), (src_unbox_of_mini_selfhost_SrcType 304), (src_viewed_type), (src_max_of), (src_Stmt_extent 75 185 186 305 306 307), (src_boxed_of_mini_selfhost_Stmt 50 308 309), (src_single_of_mini_selfhost_Expr 310), (src_guarded 311), (src_SrcExpr_guard 190 312 313 314), (src_lower_let 315), (src_lower_value 206 316 317 318), (src_cons_of_mini_selfhost_Binding 319), (src_guard_all 190 194 210 320), (src_lower_literal 180 183 321 322), (src_lower_let_call 187), (src_lower_call 323 324), (src_lower_enum_value 182 325), (src_lower_then 187)]

def dents1 : List SigEntry := [some ([(.uint .usize), ty84], ty129), some ([(.uint .usize), ty128, ty142], ty37), some ([(.uint .usize), ty85, ty130], ty142), some ([ty83], ty85), some ([ty27], ty126), some ([(.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty46], (.uint .usize)), none, none, none, some ([], ty35), none, none, some ([ty99], ty99), some ([ty99, ty99], .bool), some ([ty69, ty99], ty69), some ([ty99], ty69), some ([ty95, ty97], ty97), some ([ty12], (.uint .usize)), some ([ty31], (.uint .usize)), some ([ty9], (.uint .usize)), some ([ty12], .bool), some ([ty30], .bool), some ([(.uint .usize), (.uint .usize), (.uint .usize), ty146], ty135), some ([ty30], (.uint .usize)), some ([ty9, ty146], ty146), some ([(.uint .usize), (.uint .usize), ty146], ty146), some ([ty30, ty102, ty79, ty9, ty149, (.uint .usize)], ty146), some ([ty102, (.uint .usize), (.uint .usize)], ty102), some ([ty12, (.uint .usize), ty149], ty149), some ([], ty149), none, some ([], ty102), some ([ty100, ty102], ty102), some ([ty12], ty71), some ([ty20, (.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty20], ty20), some ([ty33, ty20, (.uint .usize)], ty20), some ([], ty20), some ([ty33], (.uint .usize)), some ([ty12, ty79], ty80), some ([ty80, ty30], ty80), some ([ty9, ty79], ty80), some ([ty1, (.uint .usize)], ty104), some ([ty20, ty20, ty104], ty82), some ([ty1, (.uint .usize)], ty104), some ([ty49], ty48), some ([ty84, ty85], ty85), some ([ty43, (.uint .usize), ty40, (.uint .usize), ty138], ty140), some ([ty38], ty40), some ([ty139], ty137), none, some ([ty84], (.uint .usize)), some ([], (.uint .usize)), some ([(.uint .usize), ty84], ty86), some ([ty84, (.uint .usize)], ty84), some ([(.uint .usize), ty150, ty85], ty129), some ([(.uint .usize), ty85], ty150), some ([(.uint .usize), ty130, ty157, ty157], ty37), some ([ty112, (.uint .usize)], ty157), some ([ty127], ty112), some ([ty109, (.uint .usize)], ty157), some ([ty127], ty109), some ([(.uint .usize), ty130, ty129, ty85], ty142), none, some ([ty126], ty125), some ([ty45], ty46), some ([ty97], ty97), some ([ty97, ty97], .bool), some ([ty162, ty97], ty144), some ([ty97], ty162), some ([ty67, ty35], ty69), some ([ty97], ty96), some ([ty11], ty12), some ([ty30], ty20), some ([(.uint .usize), ty12, ty20], ty145), some ([], (.uint .usize)), some ([ty145], (.uint .usize)), some ([(.uint .usize), ty20, ty30], ty145), some ([ty71], (.uint .usize)), some ([ty5], ty71), some ([ty75], (.uint .usize)), some ([ty6], ty75), some ([ty7], ty9), some ([ty9], .bool), some ([(.uint .usize), (.uint .usize)], (.uint .usize)), some ([ty94], (.uint .usize)), some ([ty94], ty91), some ([ty90], ty93), some ([(.uint .usize), ty90, ty146], ty146), some ([ty15, ty149], ty90), some ([(.uint .usize), ty170, ty146], ty146), some ([ty149, ty15, ty9], ty170), some ([ty147, ty149], ty149), some ([ty149, ty18], ty90), some ([ty149, ty9, ty18], ty170), some ([(.uint .usize), (.uint .usize), (.uint .usize), ty170, ty146], ty146), some ([ty102, ty149, (.uint .usize), ty18, ty9], ty170), some ([ty149, ty9, (.uint .usize), ty18], ty170), some ([ty146, ty146], ty146)]

/-- `declareFuncs` of functions 100 to 199. -/
theorem dchunk1 : declsStep dpart1 decls 70 121 62 108 = true := by decide +kernel

theorem dfit1 : entriesFit dpart1 dents1 = true := by decide +kernel

end Lanius.Faithful.SelfPure

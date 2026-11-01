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
public import Lanius.Faithful.Gen.SelfSrcC_DivOp_size
public import Lanius.Faithful.Gen.SelfSrcC_Inline_arithOf
public import Lanius.Faithful.Gen.SelfSrcC_Inline_factOr
public import Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
public import Lanius.Faithful.Gen.SelfSrcC_UintTy_mask
public import Lanius.Faithful.Gen.SelfSrcC_arities
public import Lanius.Faithful.Gen.SelfSrcC_assignAgrees
public import Lanius.Faithful.Gen.SelfSrcC_binaryConstant
public import Lanius.Faithful.Gen.SelfSrcC_callAgrees
public import Lanius.Faithful.Gen.SelfSrcC_codeSize
public import Lanius.Faithful.Gen.SelfSrcC_compileArgs
public import Lanius.Faithful.Gen.SelfSrcC_conjunction
public import Lanius.Faithful.Gen.SelfSrcC_guardAnd
public import Lanius.Faithful.Gen.SelfSrcC_larger
public import Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
public import Lanius.Faithful.Gen.SelfSrcC_longer
public import Lanius.Faithful.Gen.SelfSrcC_lowerLocal
public import Lanius.Faithful.Gen.SelfSrcC_optimizeIte
public import Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
public import Lanius.Faithful.Gen.SelfSrcC_optimizeNeg
public import Lanius.Faithful.Gen.SelfSrcC_repeatType
public import Lanius.Faithful.Gen.SelfSrcC_sintToUint
public import Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
public import Lanius.Faithful.Gen.SelfSrcF_effNamedTys
public import Lanius.Faithful.Gen.SelfSrcF_findConst
public import Lanius.Faithful.Gen.SelfSrcF_funcsOnto
public import Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
public import Lanius.Faithful.Gen.SelfSrcF_joinInsts
public import Lanius.Faithful.Gen.SelfSrcF_projectionRet
public import Lanius.Faithful.Gen.SelfSrcF_readDeclInst
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
import all Lanius.Faithful.Gen.SelfSrcC_DivOp_size
import all Lanius.Faithful.Gen.SelfSrcC_Inline_arithOf
import all Lanius.Faithful.Gen.SelfSrcC_Inline_factOr
import all Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
import all Lanius.Faithful.Gen.SelfSrcC_UintTy_mask
import all Lanius.Faithful.Gen.SelfSrcC_arities
import all Lanius.Faithful.Gen.SelfSrcC_assignAgrees
import all Lanius.Faithful.Gen.SelfSrcC_binaryConstant
import all Lanius.Faithful.Gen.SelfSrcC_callAgrees
import all Lanius.Faithful.Gen.SelfSrcC_codeSize
import all Lanius.Faithful.Gen.SelfSrcC_compileArgs
import all Lanius.Faithful.Gen.SelfSrcC_conjunction
import all Lanius.Faithful.Gen.SelfSrcC_guardAnd
import all Lanius.Faithful.Gen.SelfSrcC_larger
import all Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
import all Lanius.Faithful.Gen.SelfSrcC_longer
import all Lanius.Faithful.Gen.SelfSrcC_lowerLocal
import all Lanius.Faithful.Gen.SelfSrcC_optimizeIte
import all Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
import all Lanius.Faithful.Gen.SelfSrcC_optimizeNeg
import all Lanius.Faithful.Gen.SelfSrcC_repeatType
import all Lanius.Faithful.Gen.SelfSrcC_sintToUint
import all Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
import all Lanius.Faithful.Gen.SelfSrcF_effNamedTys
import all Lanius.Faithful.Gen.SelfSrcF_findConst
import all Lanius.Faithful.Gen.SelfSrcF_funcsOnto
import all Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
import all Lanius.Faithful.Gen.SelfSrcF_joinInsts
import all Lanius.Faithful.Gen.SelfSrcF_projectionRet
import all Lanius.Faithful.Gen.SelfSrcF_readDeclInst
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

/-- Functions 600 to 699, and their signature entries. -/
def dpart6 : List SrcFunc := [(src_unbox_of_mini_selfhost_List_mini_selfhost_Ty 894), (src_type_table_next 394 611), (src_ty_insts 56 253 600 602 895 896 897), (src_cons_of_mini_selfhost_Ty 604), (src_boxed_of_mini_selfhost_List_mini_selfhost_Ty 50 894 898), (src_unbox_of_mini_selfhost_List_mini_selfhost_Inst 899), (src_concat_of_mini_selfhost_Ty 600 604 606), (src_param_tys 403 603 607 900), (src_ret_tys 403 893), (src_stmt_tys 403 603 606 609 893 901 902), (src_unbox_of_mini_selfhost_List_mini_selfhost_MFunc 903), (src_add_insts 605 611 904), (src_stmt_calls 253 402 612 901 905 906 907), (src_cons_of_mini_selfhost_MFunc 908), (src_get_of_mini_selfhost_FnDecl 56 255 614), (src_read_decl_inst 144 579 909 910 911 912 913), (src_projection_func 56 914 915), (src_projection_ret 56 915 916 917), (src_boxed_of_mini_selfhost_List_mini_selfhost_Inst 50 899 918), (src_boxed_of_mini_selfhost_List_mini_selfhost_TypeDecl 50 405 919), (src_boxed_of_mini_selfhost_List_mini_selfhost_FnDecl 50 404 920), (src_boxed_of_mini_selfhost_List_mini_selfhost_ConstDecl 50 921 922), (src_unbox_of_mini_selfhost_List_mini_selfhost_ConstDecl 922), (src_boxed_of_mini_selfhost_List_mini_selfhost_ImportDecl 50 923 924), (src_unbox_of_mini_selfhost_List_mini_selfhost_ImportDecl 924), (src_boxed_of_mini_selfhost_List_mini_selfhost_AliasDecl 50 878 925), (src_boxed_of_mini_selfhost_List_mini_selfhost_ImplDecl 50 926 927), (src_unbox_of_mini_selfhost_List_mini_selfhost_ImplDecl 927), (src_Expr_is_var), (src_optimize_neg 311 636 928), (src_optimize_binary 311 636 929 930 931), (src_optimize_compare 311 451 636 932), (src_fact_value 933 934), (src_Stmt_facts_after 263 281 633 935 936), (src_Stmt_dead_before 937), (src_optimize_seq 172 640), (src_Expr_literal), (src_pick_branch), (src_ite_or_skip 172 640), (src_loop_unless_zero 172), (src_Stmt_is_skip), (src_assign_agrees 938), (src_seq_agrees 281 425 633), (src_dead_agrees 425 935 937), (src_ite_agrees 281 425 938), (src_branch_agrees 425), (src_Expr_constant 441 646 939 940 941), (src_unknown), (src_Expr_is_zero 646 942), (src_loop_agrees 263 281 425 938), (src_call_agrees 943), (src_ret_agrees 943), (src_Stmt_is_brk), (src_Stmt_is_cont), (src_alloc_agrees 938), (src_load_byte_agrees 938), (src_store_byte_agrees 938), (src_load_word_agrees 938 944), (src_store_word_agrees 938 944), (src_divide_agrees 938 945 946), (src_sys_agrees 943 947), (src_frame_agrees), (src_Expr_temps 75 170 441 662), (src_args_temps 75 170 442 662 663), (src_Expr_within 441 664), (src_arity_is 948), (src_length_of_mini_selfhost_Expr 75 442 666), (src_all_within 442 664 667), (src_boxed_of_mini_selfhost_List_mini_selfhost_Instr 50 949 950), (src_empty_of_mini_selfhost_Instr), (src_unbox_of_mini_selfhost_List_mini_selfhost_Instr 950), (src_compile_expr 75 431 441 671 672), (src_single_of_mini_selfhost_Instr 668), (src_seq_code 75 431 432 433), (src_ite_code 75 431 432 433 672), (src_loop_code 75 431 432 433 672), (src_compile_args 75 431 442 669 671 672 676), (src_arg_slots 75 229 374 442 677), (src_Instr_size 52 75 105 951 952 953 954 955), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Code), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Code), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Arity), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Arity), (src_boxed_of_mini_selfhost_List_u8 50 111 956), (src_cons_of_u8 683), (src_single_of_u8 683), (src_le32 684 685), (src_frame_size 75 105), (src_stack_check 684 685), (src_Instr_encode 52 75 105 438 684 685 686 957 958 959 960 961 962 963 964 965 966 967 968 969 970 971 972 973 974 975 976 977 978), (src_amount_guard 311 979), (src_shift_width 980), (src_UintTy_mask), (src_lower_scalar_local 291), (src_lower_field_of 75 166 470 471 981), (src_SrcOp_lower 982 983 984 985 986 987 988 989), (src_cast_to 990 991 992 993 994), (src_FloatTy_mask), (src_copy_same 119 218 343), (src_copy_field_of 75 166 470 471 995)]

def dents6 : List SigEntry := [some ([ty152], ty154), some ([(.uint .usize), ty127, ty157, ty223, ty154], ty223), some ([(.uint .usize), ty127, ty153], ty223), some ([ty153, ty154], ty154), some ([ty154], ty152), some ([ty156], ty157), some ([ty154, ty154], ty154), some ([ty186], ty154), some ([ty187], ty154), some ([ty192], ty154), some ([ty194], ty195), some ([ty157, ty157], ty157), some ([ty192], ty157), some ([ty193, ty195], ty195), some ([ty112, (.uint .usize)], ty229), some ([(.uint .usize), ty127, ty110, ty155], ty228), some ([ty245, ty155, ty127], ty228), some ([(.uint .usize), ty127, ty155], ty245), some ([ty157], ty156), some ([ty109], ty108), some ([ty112], ty111), some ([ty115], ty114), some ([ty114], ty115), some ([ty118], ty117), some ([ty117], ty118), some ([ty121], ty120), some ([ty124], ty123), some ([ty123], ty124), some ([ty90, (.uint .usize)], .bool), some ([ty90], ty90), some ([ty51, ty52, ty90, ty90], ty90), some ([ty51, ty53, ty90, ty90], ty90), some ([ty203, (.uint .usize)], ty90), some ([ty94, ty203], ty203), some ([ty94, ty94], .bool), some ([ty94, ty94], ty94), some ([ty90], ty230), some ([(.uint .uint64), ty94, ty94], ty94), some ([ty90, ty94, ty94], ty94), some ([(.uint .uint64), ty90, ty94], ty94), some ([ty94], .bool), some ([(.uint .usize), ty90, ty94], .bool), some ([ty94, ty94, ty203, ty94], .bool), some ([ty94, ty94, ty203, ty94], .bool), some ([ty90, ty94, ty94, ty203, ty94], .bool), some ([ty230, ty94, ty94, ty203, ty94], .bool), some ([ty90], ty230), some ([ty230], .bool), some ([ty90], .bool), some ([ty90, ty94, ty94], .bool), some ([(.uint .usize), (.uint .usize), (.uint .usize), ty93, ty94], .bool), some ([ty93, ty94], .bool), some ([ty94], .bool), some ([ty94], .bool), some ([(.uint .usize), (.uint .usize), ty90, ty94], .bool), some ([(.uint .usize), ty90, ty94], .bool), some ([ty90, ty90, ty94], .bool), some ([ty54, (.uint .usize), ty90, ty94], .bool), some ([ty54, ty90, ty90, ty94], .bool), some ([ty51, ty55, (.uint .usize), ty90, ty90, ty94], .bool), some ([ty59, (.uint .usize), ty93, ty94], .bool), some ([(.uint .usize), (.uint .usize), ty94], .bool), some ([ty90], (.uint .usize)), some ([ty93, (.uint .usize)], (.uint .usize)), some ([ty90, (.uint .usize)], .bool), some ([ty162, (.uint .usize), (.uint .usize), (.uint .usize)], .bool), some ([ty93], (.uint .usize)), some ([(.uint .usize), ty93], .bool), some ([ty62], ty61), some ([], ty62), some ([ty61], ty62), some ([(.uint .usize), ty90, (.uint .usize)], ty62), some ([ty60], ty62), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), ty62, ty94], ty62), some ([(.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), ty62, ty94, ty94], ty62), some ([(.uint .usize), (.uint .usize), ty62, ty94], ty62), some ([(.uint .usize), ty93, (.uint .usize)], ty62), some ([(.uint .usize), ty93, (.uint .usize)], ty20), some ([ty60], (.uint .usize)), none, none, none, none, some ([ty67], ty66), some ([(.uint .uint8), ty67], ty67), some ([(.uint .uint8)], ty67), some ([.i32], ty67), some ([(.uint .usize)], (.uint .usize)), some ([], ty67), some ([ty60, ty204, (.uint .usize)], ty67), some ([(.uint .uint64), ty90], ty90), some ([ty9], (.uint .uint64)), some ([ty4], (.uint .uint64)), some ([ty145], ty174), some ([ty145, (.uint .usize)], ty174), some ([ty14, ty173, ty173], ty174), some ([ty9, ty173], ty174), some ([ty8], (.uint .uint64)), some ([ty145, ty9], ty169), some ([ty145, (.uint .usize), ty9], ty169)]

/-- `declareFuncs` of functions 600 to 699. -/
theorem dchunk6 : declsStep dpart6 decls 36 65 36 62 = true := by decide +kernel

theorem dfit6 : entriesFit dpart6 dents6 = true := by decide +kernel

end Lanius.Faithful.SelfPure

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
public import Lanius.Faithful.Gen.SelfSrcC_Inline_factOr
public import Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
public import Lanius.Faithful.Gen.SelfSrcC_UintTy_mask
public import Lanius.Faithful.Gen.SelfSrcC_arities
public import Lanius.Faithful.Gen.SelfSrcC_assignAgrees
public import Lanius.Faithful.Gen.SelfSrcC_binaryConstant
public import Lanius.Faithful.Gen.SelfSrcC_callAgrees
public import Lanius.Faithful.Gen.SelfSrcC_codeSize
public import Lanius.Faithful.Gen.SelfSrcC_compileArgs
public import Lanius.Faithful.Gen.SelfSrcC_guardAnd
public import Lanius.Faithful.Gen.SelfSrcC_larger
public import Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
public import Lanius.Faithful.Gen.SelfSrcC_longer
public import Lanius.Faithful.Gen.SelfSrcC_optimizeIte
public import Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
public import Lanius.Faithful.Gen.SelfSrcC_optimizeNeg
public import Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
public import Lanius.Faithful.Gen.SelfSrcF_allWeighed
public import Lanius.Faithful.Gen.SelfSrcF_effNamedTys
public import Lanius.Faithful.Gen.SelfSrcF_findConst
public import Lanius.Faithful.Gen.SelfSrcF_funcsOnto
public import Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
public import Lanius.Faithful.Gen.SelfSrcF_joinInsts
public import Lanius.Faithful.Gen.SelfSrcF_negWideI32
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
import all Lanius.Faithful.Gen.SelfSrcC_Inline_factOr
import all Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
import all Lanius.Faithful.Gen.SelfSrcC_UintTy_mask
import all Lanius.Faithful.Gen.SelfSrcC_arities
import all Lanius.Faithful.Gen.SelfSrcC_assignAgrees
import all Lanius.Faithful.Gen.SelfSrcC_binaryConstant
import all Lanius.Faithful.Gen.SelfSrcC_callAgrees
import all Lanius.Faithful.Gen.SelfSrcC_codeSize
import all Lanius.Faithful.Gen.SelfSrcC_compileArgs
import all Lanius.Faithful.Gen.SelfSrcC_guardAnd
import all Lanius.Faithful.Gen.SelfSrcC_larger
import all Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
import all Lanius.Faithful.Gen.SelfSrcC_longer
import all Lanius.Faithful.Gen.SelfSrcC_optimizeIte
import all Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
import all Lanius.Faithful.Gen.SelfSrcC_optimizeNeg
import all Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
import all Lanius.Faithful.Gen.SelfSrcF_allWeighed
import all Lanius.Faithful.Gen.SelfSrcF_effNamedTys
import all Lanius.Faithful.Gen.SelfSrcF_findConst
import all Lanius.Faithful.Gen.SelfSrcF_funcsOnto
import all Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
import all Lanius.Faithful.Gen.SelfSrcF_joinInsts
import all Lanius.Faithful.Gen.SelfSrcF_negWideI32
import all Lanius.Faithful.Gen.SelfSrcF_projectionRet
import all Lanius.Faithful.Gen.SelfSrcF_readDeclInst
import all Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfTypes
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.FloatTy_rex
import all Lanius.Mini.Compiler.P.Instr_pieces
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.UintTy_mask
import all Lanius.Mini.Compiler.P.applyGuard
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.arithUint
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.armBodyScope
import all Lanius.Mini.Compiler.P.armPayload
import all Lanius.Mini.Compiler.P.armScope
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.compileModules
import all Lanius.Mini.Compiler.P.conjunction
import all Lanius.Mini.Compiler.P.consArgs
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.elementAddress
import all Lanius.Mini.Compiler.P.elementBase
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.evalDivide
import all Lanius.Mini.Compiler.P.evalDivideSint
import all Lanius.Mini.Compiler.P.evalNot
import all Lanius.Mini.Compiler.P.evalSame
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.hostRandomCode
import all Lanius.Mini.Compiler.P.imageLimit
import all Lanius.Mini.Compiler.P.importOk
import all Lanius.Mini.Compiler.P.importsOk
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.iteThen
import all Lanius.Mini.Compiler.P.leftTrue
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.lowerAddress
import all Lanius.Mini.Compiler.P.lowerApply
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.lowerCallSig
import all Lanius.Mini.Compiler.P.lowerLoadType
import all Lanius.Mini.Compiler.P.lowerLocal
import all Lanius.Mini.Compiler.P.lowerReturn
import all Lanius.Mini.Compiler.P.lowerSetCallArgs
import all Lanius.Mini.Compiler.P.lowerSetValues
import all Lanius.Mini.Compiler.P.lowerShift
import all Lanius.Mini.Compiler.P.lowerSlice
import all Lanius.Mini.Compiler.P.lowerTagged
import all Lanius.Mini.Compiler.P.matchDst
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.moduleExports
import all Lanius.Mini.Compiler.P.moduleFirsts
import all Lanius.Mini.Compiler.P.modulesOk
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.sigs
import all Lanius.Mini.Compiler.P.sintToUint
import all Lanius.Mini.Compiler.P.storeArray
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.storeWordElement
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.wordStride
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.Types

@[expose] public section

/-! Generated by formal/tools/faithful_pure.py. Do not edit. -/

namespace Lanius.Faithful.SelfPure

open Lanius.Mini
open Lanius.Faithful
open Lanius.Faithful.Self

/-- `declareFuncs` of functions 600 to 699. -/
theorem dchunk6 : declsStep [(src_lit_funcs 59 600 885 895 896 897), (src_table_weighed), (src_all_weighed 602 898 899), (src_weigh_rounds 56 900 901), (src_length_of_mini_selfhost_Inst 75 604 612), (src_unweighed 605 612 902 903), (src_type_table_more_at 394 395 904 905), (src_unbox_of_mini_selfhost_List_mini_selfhost_Ty 906), (src_type_table_next 395 618), (src_ty_insts 56 253 607 609 907 908 909), (src_cons_of_mini_selfhost_Ty 611), (src_boxed_of_mini_selfhost_List_mini_selfhost_Ty 50 906 910), (src_unbox_of_mini_selfhost_List_mini_selfhost_Inst 911), (src_concat_of_mini_selfhost_Ty 607 611 613), (src_param_tys 404 610 614 912), (src_ret_tys 404 905), (src_stmt_tys 404 610 613 616 905 913 914), (src_unbox_of_mini_selfhost_List_mini_selfhost_MFunc 915), (src_add_insts 612 618 916), (src_stmt_calls 253 403 619 913 917 918 919), (src_cons_of_mini_selfhost_MFunc 920), (src_get_of_mini_selfhost_FnDecl 56 255 621), (src_read_decl_inst 144 581 921 922 923 924 925), (src_projection_func 56 926 927), (src_projection_ret 56 927 928 929), (src_boxed_of_mini_selfhost_List_mini_selfhost_Inst 50 911 930), (src_boxed_of_mini_selfhost_List_mini_selfhost_TypeDecl 50 406 931), (src_boxed_of_mini_selfhost_List_mini_selfhost_FnDecl 50 405 932), (src_boxed_of_mini_selfhost_List_mini_selfhost_ConstDecl 50 933 934), (src_unbox_of_mini_selfhost_List_mini_selfhost_ConstDecl 934), (src_boxed_of_mini_selfhost_List_mini_selfhost_ImportDecl 50 935 936), (src_unbox_of_mini_selfhost_List_mini_selfhost_ImportDecl 936), (src_boxed_of_mini_selfhost_List_mini_selfhost_AliasDecl 50 884 937), (src_boxed_of_mini_selfhost_List_mini_selfhost_ImplDecl 50 938 939), (src_unbox_of_mini_selfhost_List_mini_selfhost_ImplDecl 939), (src_Expr_is_var), (src_optimize_neg 311 643 940), (src_optimize_binary 311 643 941 942 943), (src_optimize_compare 311 452 643 944), (src_fact_value 945 946), (src_Stmt_facts_after 263 281 640 947 948), (src_Stmt_dead_before 949), (src_optimize_seq 172 647), (src_Expr_literal), (src_pick_branch), (src_ite_or_skip 172 647), (src_loop_unless_zero 172), (src_Stmt_is_skip), (src_assign_agrees 950), (src_seq_agrees 281 426 640), (src_dead_agrees 426 947 949), (src_ite_agrees 281 426 950), (src_branch_agrees 426), (src_Expr_constant 442 653 951 952 953), (src_unknown), (src_Expr_is_zero 653 954), (src_loop_agrees 263 281 426 950), (src_call_agrees 955), (src_ret_agrees 955), (src_Stmt_is_brk), (src_Stmt_is_cont), (src_alloc_agrees 950), (src_load_byte_agrees 950), (src_store_byte_agrees 950), (src_load_word_agrees 950 956), (src_store_word_agrees 950 956), (src_divide_agrees 950 957 958), (src_sys_agrees 955 959), (src_frame_agrees), (src_Expr_temps 75 170 442 669), (src_args_temps 75 170 443 669 670), (src_Expr_within 442 671), (src_arity_is 960), (src_length_of_mini_selfhost_Expr 75 443 673), (src_all_within 443 671 674), (src_boxed_of_mini_selfhost_List_mini_selfhost_Instr 50 961 962), (src_empty_of_mini_selfhost_Instr), (src_unbox_of_mini_selfhost_List_mini_selfhost_Instr 962), (src_compile_expr 75 432 442 678 679), (src_single_of_mini_selfhost_Instr 675), (src_seq_code 75 432 433 434), (src_ite_code 75 432 433 434 679), (src_loop_code 75 432 433 434 679), (src_compile_args 75 432 443 676 678 679 683), (src_arg_slots 75 229 374 443 684), (src_Instr_size 52 75 105 963 964 965 966 967), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Code), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Code), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Arity), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Arity), (src_boxed_of_mini_selfhost_List_u8 50 111 968), (src_cons_of_u8 690), (src_single_of_u8 690), (src_le32 691 692), (src_frame_size 75 105), (src_stack_check 691 692), (src_Instr_encode 52 75 105 439 691 692 693 969 970 971 972 973 974 975 976 977 978 979 980 981 982 983 984 985 986 987 988 989 990), (src_amount_guard 311 991), (src_shift_width 992), (src_UintTy_mask)]
    decls 37 67 36 63 = true := by decide +kernel

end Lanius.Faithful.SelfPure

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
public import Lanius.Faithful.Gen.SelfSrcC_conjunction
public import Lanius.Faithful.Gen.SelfSrcC_guardAnd
public import Lanius.Faithful.Gen.SelfSrcC_larger
public import Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
public import Lanius.Faithful.Gen.SelfSrcC_longer
public import Lanius.Faithful.Gen.SelfSrcC_lowerLocal
public import Lanius.Faithful.Gen.SelfSrcC_optimizeIte
public import Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
public import Lanius.Faithful.Gen.SelfSrcC_optimizeNeg
public import Lanius.Faithful.Gen.SelfSrcC_sintToUint
public import Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
public import Lanius.Faithful.Gen.SelfSrcF_effNamedTys
public import Lanius.Faithful.Gen.SelfSrcF_findConst
public import Lanius.Faithful.Gen.SelfSrcF_funcsOnto
public import Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
public import Lanius.Faithful.Gen.SelfSrcF_joinInsts
public import Lanius.Faithful.Gen.SelfSrcF_negWideI32
public import Lanius.Faithful.Gen.SelfSrcF_projectionRet
public import Lanius.Faithful.Gen.SelfSrcF_readDeclInst
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
import all Lanius.Faithful.Gen.SelfSrcC_conjunction
import all Lanius.Faithful.Gen.SelfSrcC_guardAnd
import all Lanius.Faithful.Gen.SelfSrcC_larger
import all Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
import all Lanius.Faithful.Gen.SelfSrcC_longer
import all Lanius.Faithful.Gen.SelfSrcC_lowerLocal
import all Lanius.Faithful.Gen.SelfSrcC_optimizeIte
import all Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
import all Lanius.Faithful.Gen.SelfSrcC_optimizeNeg
import all Lanius.Faithful.Gen.SelfSrcC_sintToUint
import all Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
import all Lanius.Faithful.Gen.SelfSrcF_effNamedTys
import all Lanius.Faithful.Gen.SelfSrcF_findConst
import all Lanius.Faithful.Gen.SelfSrcF_funcsOnto
import all Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
import all Lanius.Faithful.Gen.SelfSrcF_joinInsts
import all Lanius.Faithful.Gen.SelfSrcF_negWideI32
import all Lanius.Faithful.Gen.SelfSrcF_projectionRet
import all Lanius.Faithful.Gen.SelfSrcF_readDeclInst
import all Lanius.Faithful.Gen.SelfSrcF_wideLeftStmt
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
theorem dchunk6 : declsStep [(src_untyped_rejected 890), (src_lit_funcs 59 601 881 891 892 893), (src_type_table_more_at 396 397 894 895), (src_unbox_of_mini_selfhost_List_mini_selfhost_Ty 896), (src_type_table_next 397 614), (src_ty_insts 56 256 603 605 897 898 899), (src_cons_of_mini_selfhost_Ty 607), (src_boxed_of_mini_selfhost_List_mini_selfhost_Ty 50 896 900), (src_unbox_of_mini_selfhost_List_mini_selfhost_Inst 901), (src_concat_of_mini_selfhost_Ty 603 607 609), (src_param_tys 406 606 610 902), (src_ret_tys 406 895), (src_stmt_tys 406 606 609 612 895 903 904), (src_unbox_of_mini_selfhost_List_mini_selfhost_MFunc 905), (src_add_insts 608 614 906), (src_stmt_calls 256 405 615 903 907 908 909), (src_cons_of_mini_selfhost_MFunc 910), (src_get_of_mini_selfhost_FnDecl 56 258 617), (src_read_decl_inst 148 582 911 912 913 914 915), (src_projection_func 56 916 917), (src_projection_ret 56 917 918 919), (src_boxed_of_mini_selfhost_List_mini_selfhost_Inst 50 901 920), (src_boxed_of_mini_selfhost_List_mini_selfhost_TypeDecl 50 408 921), (src_boxed_of_mini_selfhost_List_mini_selfhost_FnDecl 50 407 922), (src_boxed_of_mini_selfhost_List_mini_selfhost_ConstDecl 50 923 924), (src_unbox_of_mini_selfhost_List_mini_selfhost_ConstDecl 924), (src_boxed_of_mini_selfhost_List_mini_selfhost_ImportDecl 50 925 926), (src_unbox_of_mini_selfhost_List_mini_selfhost_ImportDecl 926), (src_boxed_of_mini_selfhost_List_mini_selfhost_AliasDecl 50 880 927), (src_boxed_of_mini_selfhost_List_mini_selfhost_ImplDecl 50 928 929), (src_unbox_of_mini_selfhost_List_mini_selfhost_ImplDecl 929), (src_Expr_is_var), (src_optimize_neg 314 639 930), (src_optimize_binary 314 639 931 932 933), (src_optimize_compare 314 454 639 934), (src_fact_value 935 936), (src_Stmt_facts_after 266 284 636 937 938), (src_Stmt_dead_before 939), (src_optimize_seq 176 643), (src_Expr_literal), (src_pick_branch), (src_ite_or_skip 176 643), (src_loop_unless_zero 176), (src_Stmt_is_skip), (src_assign_agrees 940), (src_seq_agrees 284 428 636), (src_dead_agrees 428 937 939), (src_ite_agrees 284 428 940), (src_branch_agrees 428), (src_Expr_constant 444 649 941 942 943), (src_unknown), (src_Expr_is_zero 649 944), (src_loop_agrees 266 284 428 940), (src_call_agrees 945), (src_ret_agrees 945), (src_Stmt_is_brk), (src_Stmt_is_cont), (src_alloc_agrees 940), (src_load_byte_agrees 940), (src_store_byte_agrees 940), (src_load_word_agrees 940 946), (src_store_word_agrees 940 946), (src_divide_agrees 940 947 948), (src_sys_agrees 945 949), (src_frame_agrees), (src_Expr_temps 75 174 444 665), (src_args_temps 75 174 445 665 666), (src_Expr_within 444 667), (src_arity_is 950), (src_length_of_mini_selfhost_Expr 75 445 669), (src_all_within 445 667 670), (src_boxed_of_mini_selfhost_List_mini_selfhost_Instr 50 951 952), (src_empty_of_mini_selfhost_Instr), (src_unbox_of_mini_selfhost_List_mini_selfhost_Instr 952), (src_compile_expr 75 434 444 674 675), (src_single_of_mini_selfhost_Instr 671), (src_seq_code 75 434 435 436), (src_ite_code 75 434 435 436 675), (src_loop_code 75 434 435 436 675), (src_compile_args 75 434 445 672 674 675 679), (src_arg_slots 75 232 377 445 680), (src_Instr_size 52 75 106 953 954 955 956 957), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Code), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Code), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Arity), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Arity), (src_boxed_of_mini_selfhost_List_u8 50 112 958), (src_cons_of_u8 686), (src_single_of_u8 686), (src_le32 687 688), (src_frame_size 75 106), (src_stack_check 687 688), (src_Instr_encode 52 75 106 441 687 688 689 959 960 961 962 963 964 965 966 967 968 969 970 971 972 973 974 975 976 977 978 979 980), (src_amount_guard 314 981), (src_shift_width 982), (src_UintTy_mask), (src_lower_scalar_local 294), (src_lower_field_of 75 170 472 473 983), (src_SrcOp_lower 984 985 986 987 988 989 990 991), (src_cast_to 992 993 994 995 996)]
    decls 36 65 36 62 = true := by decide +kernel

end Lanius.Faithful.SelfPure

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
public import Lanius.Faithful.Gen.SelfSrcC_Inline_lowerSetScalar
public import Lanius.Faithful.Gen.SelfSrcC_UintTy_half
public import Lanius.Faithful.Gen.SelfSrcC_compileOr
public import Lanius.Faithful.Gen.SelfSrcC_compileSource
public import Lanius.Faithful.Gen.SelfSrcC_declareFuncs
public import Lanius.Faithful.Gen.SelfSrcC_declareProgram
public import Lanius.Faithful.Gen.SelfSrcC_lowerBody
public import Lanius.Faithful.Gen.SelfSrcC_packRound
public import Lanius.Faithful.Gen.SelfSrcC_sigs
public import Lanius.Faithful.Gen.SelfSrcC_storeArray
public import Lanius.Faithful.Gen.SelfSrcF_frontEndRead
public import Lanius.Faithful.Gen.SelfSrcF_frontEndWords
public import Lanius.Faithful.Gen.SelfSrcF_grammarPart13
public import Lanius.Faithful.Gen.SelfSrcF_grammarPart8
public import Lanius.Faithful.Gen.SelfSrcF_isEmptyUsize
public import Lanius.Faithful.Gen.SelfSrcF_lxCanonicalKind
public import Lanius.Faithful.Gen.SelfSrcF_readCountedBytes
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
import all Lanius.Faithful.Gen.SelfSrcC_Inline_lowerSetScalar
import all Lanius.Faithful.Gen.SelfSrcC_UintTy_half
import all Lanius.Faithful.Gen.SelfSrcC_compileOr
import all Lanius.Faithful.Gen.SelfSrcC_compileSource
import all Lanius.Faithful.Gen.SelfSrcC_declareFuncs
import all Lanius.Faithful.Gen.SelfSrcC_declareProgram
import all Lanius.Faithful.Gen.SelfSrcC_lowerBody
import all Lanius.Faithful.Gen.SelfSrcC_packRound
import all Lanius.Faithful.Gen.SelfSrcC_sigs
import all Lanius.Faithful.Gen.SelfSrcC_storeArray
import all Lanius.Faithful.Gen.SelfSrcF_frontEndRead
import all Lanius.Faithful.Gen.SelfSrcF_frontEndWords
import all Lanius.Faithful.Gen.SelfSrcF_grammarPart13
import all Lanius.Faithful.Gen.SelfSrcF_grammarPart8
import all Lanius.Faithful.Gen.SelfSrcF_isEmptyUsize
import all Lanius.Faithful.Gen.SelfSrcF_lxCanonicalKind
import all Lanius.Faithful.Gen.SelfSrcF_readCountedBytes
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

/-- `declareFuncs` of functions 0 to 99. -/
theorem dchunk0 : declsStep [(src_app_main_w 1 2 5 6 7 8), (src_app_main_oracle_read 1 9), (src_app_main_oracle_put 3), (src_app_main_oracle_write 4 10), (src_app_main_oracle_write_one 3), (src_empty_of_i32), (src_compile_words 11 12), (src_front_end_words 13 14), (src_grammar 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32), (src_cons_of_i32 33), (src_unbox_of_mini_selfhost_List_i32 34), (src_binary_words 35 36), (src_compile_source 37 38 39), (src_read_counted_files 10 40 41), (src_front_end_read 42), (src_concat_of_mini_selfhost_Rule 15 43 44), (src_grammar_part_0 45 46 47 48), (src_grammar_part_1 45 46 47 48), (src_grammar_part_2 45 46 47 48), (src_grammar_part_3 45 46 47 48), (src_grammar_part_4 45 46 47 48), (src_grammar_part_5 45 46 47 48), (src_grammar_part_6 45 46 47 48), (src_grammar_part_7 45 46 47 48), (src_grammar_part_8 45 46 47 48), (src_grammar_part_9 45 46 47 48), (src_grammar_part_10 45 46 47 48), (src_grammar_part_11 45 46 47 48), (src_grammar_part_12 45 46 47 48), (src_grammar_part_13 45 46 47 48), (src_grammar_part_14 45 46 47 48), (src_grammar_part_15 45 46 47 48), (src_grammar_part_16 45 46 47 48), (src_boxed_of_mini_selfhost_List_i32 34 49 50), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_i32), (src_image_words 9 51 52 53), (src_pack_rounds 36 54 55 56), (src_funcs_return 37 57 58 59), (src_compile_declared 60 61 62), (src_declare_program 63 64 65), (src_read_files 40 56 66 67 68), (src_word_num), (src_front_end_files 69 70 71), (src_boxed_of_mini_selfhost_List_mini_selfhost_Rule 50 72 73), (src_unbox_of_mini_selfhost_List_mini_selfhost_Rule 73), (src_cons_of_mini_selfhost_Rule 43), (src_cons_of_mini_selfhost_Sym 74), (src_empty_of_mini_selfhost_Sym), (src_empty_of_mini_selfhost_Rule), (src_core_mem_size_of_of_mini_selfhost_List_i32), (src_core_panic_panic), (src_concat_of_i32 10 33 51), (src_length_of_usize 52 75 76), (src_usize_words 5 9 53 76), (src_pack_round 5 54 56 77 78 79 80), (src_round_join 51 75), (src_minus 50), (src_SrcType_is_unit), (src_SrcStmt_returns 58 81), (src_unbox_of_mini_selfhost_List_mini_selfhost_SrcFunc 82), (src_compile_lowered 83), (src_lower_funcs 59 61 84 85 86), (src_sigs 59 62 87 88 89), (src_declare_funcs 59 90 91), (src_empty_of_mini_selfhost_SrcStructDecl), (src_empty_of_mini_selfhost_SrcEnumDecl), (src_empty_of_mini_selfhost_FileInput), (src_read_file 92 93 94), (src_files_after 95), (src_validate_files 69 96 97 98 99), (src_build_files 100 101 102 103 104), (src_files_fuel 52 71 75 99 105 106), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Rule), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Rule), (src_boxed_of_mini_selfhost_List_mini_selfhost_Sym 50 107 108), (src_plus 50), (src_unbox_of_mini_selfhost_List_usize 109), (src_round_end 5 110), (src_unbox_of_mini_selfhost_List_u8 111), (src_round_cons 9 75), (src_pack_word), (src_unbox_of_mini_selfhost_SrcStmt 112), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcFunc), (src_compile_optimized 113 114 115 116), (src_empty_of_mini_selfhost_Func), (src_lower_func_cons 117), (src_lower_func 118 119 120 121 122 123 124 125 126 127), (src_empty_of_mini_selfhost_Sig), (src_cons_of_mini_selfhost_Sig 128), (src_param_types 89 129 130 131), (src_declare_funcs_after 63), (src_declare_func 132 133 134), (src_read_counted_bytes 10 41 135), (src_read_file_parents 94 136), (src_read_counted_nums 10 41 137), (src_cons_of_mini_selfhost_FileInput 138), (src_empty_of_mini_selfhost_CTree), (src_cons_root 139), (src_validate_tree 52 75 105 106 140 141 142), (src_unbox_of_mini_selfhost_List_mini_selfhost_FileInput 143)]
    decls 131 177 64 112 = true := by decide +kernel

end Lanius.Faithful.SelfPure

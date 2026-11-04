module

public import Lanius.Faithful.SelfPre.Values
public import Lanius.Faithful.SelfPre.NB
public import Lanius.Faithful.SelfPre.TS
public import Lanius.Faithful.SelfPre.CompileTypes
public import Lanius.Faithful.SelfPre.CompileEvalTypes
public import Lanius.Faithful.SelfPre.CompileNeeds
public import Lanius.Faithful.SelfPre.CompileSlots
public import Lanius.Faithful.SelfPre.EvalSlots
public import Lanius.Mini.Room
import all Lanius.Mini.Compiler.P.BinOp_folds
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.Expr_agrees
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.FloatTy_rex
import all Lanius.Mini.Compiler.P.Instr_pieces
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.Stmt_kills
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.UintTy_mask
import all Lanius.Mini.Compiler.P.Word_compute
import all Lanius.Mini.Compiler.P.Word_narrows
import all Lanius.Mini.Compiler.P.applyGuard
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.arithUint
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.armBodyScope
import all Lanius.Mini.Compiler.P.armPayload
import all Lanius.Mini.Compiler.P.armScope
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.assignAgrees
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.binaryConstant
import all Lanius.Mini.Compiler.P.bindingBytes
import all Lanius.Mini.Compiler.P.callAgrees
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.compileModules
import all Lanius.Mini.Compiler.P.compileOr
import all Lanius.Mini.Compiler.P.compileSource
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
import all Lanius.Mini.Compiler.P.evalHost
import all Lanius.Mini.Compiler.P.evalNot
import all Lanius.Mini.Compiler.P.evalSame
import all Lanius.Mini.Compiler.P.evalSlotLimit
import all Lanius.Mini.Compiler.P.extentAfter
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.funcNeeds
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.hostRandomCode
import all Lanius.Mini.Compiler.P.importOk
import all Lanius.Mini.Compiler.P.importsOk
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.iteThen
import all Lanius.Mini.Compiler.P.killShared
import all Lanius.Mini.Compiler.P.leftTrue
import all Lanius.Mini.Compiler.P.linkedSize
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.longer
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
import all Lanius.Mini.Compiler.P.needCapped
import all Lanius.Mini.Compiler.P.needLimit
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.optimizeIte
import all Lanius.Mini.Compiler.P.optimizeLeft
import all Lanius.Mini.Compiler.P.optimizeNeg
import all Lanius.Mini.Compiler.P.packRound
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.roomFits
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.sintToUint
import all Lanius.Mini.Compiler.P.storeArray
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.storeWordElement
import all Lanius.Mini.Compiler.P.strStores
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.substAll
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.withBudget
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.wordStride
import all Lanius.Mini.Compiler.P.wordWidth

@[expose] public section

/-! # Byte lists of the compile side (F14)

The compiler's encoders build long literal byte lists (`bumpBytes` has 42
literal bytes and two `le64`s). `post_auto` bounds each cons cell's height
by its own `omega` call over every cost atom so far, about a minute for one
such function; these lemmas let the hand proofs in `tools/pre_certs.py`
(`POST_HAND`, compile section) count lengths instead: a byte list is as high
as it is long, a list primitive's cost does not depend on its arguments and
is at least 1, and an `le32`/`le64` costs at least its 4/8 bytes. -/

namespace Lanius.Faithful.SelfPre

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget

theorem pc_hb_u8 : ∀ l : List UInt8, hb l = l.length
  | [] => rfl
  | a :: l => by simp only [hb_cons, hb_uint8, List.length_cons, pc_hb_u8 l]; omega

/-- A list primitive's cost, which does not depend on its arguments (a constant
of its own, so that `simp` does not take the rewrite for a permutation). -/
def pcCons (n : Nat) : Nat := Cost_cons_of_u8 n 0 []
def pcSingle (n : Nat) : Nat := Cost_single_of_u8 n 0
def pcLe64 (n : Nat) : Nat := Cost_le64 n 0
def pcLe32 (n : Nat) : Nat := Cost_le32 n 0

theorem pc_cons_u8 (n : Nat) (a : UInt8) (l : List UInt8) : Cost_cons_of_u8 n a l = pcCons n := by
  cases n <;> rfl

theorem pc_single_u8 (n : Nat) (a : UInt8) : Cost_single_of_u8 n a = pcSingle n := by
  cases n <;> rfl

theorem pc_cons_u8_pos (n : Nat) : 1 ≤ pcCons n := by
  cases n <;> simp only [pcCons, Cost_cons_of_u8] <;> omega

theorem pc_single_u8_pos (n : Nat) : 1 ≤ pcSingle n := by
  cases n <;> simp only [pcSingle, Cost_single_of_u8] <;> omega

theorem pc_len_le64 (v : BitVec 64) : (le64 v).length = 8 := by rfl
theorem pc_len_le32 (v : BitVec 32) : (le32 v).length = 4 := by rfl

theorem pc_le64 (n : Nat) (v : BitVec 64) : Cost_le64 n v = pcLe64 n := by
  rcases n with _ | n
  · rfl
  · simp only [pcLe64, Cost_le64, pc_cons_u8, pc_single_u8]

theorem pc_le32 (n : Nat) (v : BitVec 32) : Cost_le32 n v = pcLe32 n := by
  rcases n with _ | n
  · rfl
  · simp only [pcLe32, Cost_le32, pc_cons_u8, pc_single_u8]

theorem pc_le64_ge (n : Nat) (h : pcLe64 n < 18446744073709551616) : 8 ≤ pcLe64 n := by
  rcases n with _ | n
  · exact absurd h (Nat.lt_irrefl _)
  · simp only [pcLe64, Cost_le64, pc_cons_u8, pc_single_u8] at h ⊢
    have := pc_cons_u8_pos n
    have := pc_single_u8_pos n
    omega

theorem pc_le32_ge (n : Nat) (h : pcLe32 n < 18446744073709551616) : 4 ≤ pcLe32 n := by
  rcases n with _ | n
  · exact absurd h (Nat.lt_irrefl _)
  · simp only [pcLe32, Cost_le32, pc_cons_u8, pc_single_u8] at h ⊢
    have := pc_cons_u8_pos n
    have := pc_single_u8_pos n
    omega

/-! The encoder's small numbers (for `valueFacts`, as `val_<T>_<f>`). -/

theorem val_FloatTy_number (x : FloatTy) : FloatTy.number x ≤ 1 := by cases x <;> decide
theorem val_FArith_number (x : FArith) : FArith.number x ≤ 3 := by cases x <;> decide
theorem val_FCmp_number (x : FCmp) : FCmp.number x ≤ 2 := by cases x <;> decide
theorem val_Word_number (x : Word) : Word.number x ≤ 1 := by cases x <;> decide
theorem val_Word_prefix (x : Word) : Word.prefix x ≤ 1 := by cases x <;> decide
theorem val_MemWidth_prefix (x : MemWidth) : MemWidth.prefix x ≤ 1 := by cases x <;> decide
theorem val_FloatTy_rexSize (x : FloatTy) : FloatTy.rexSize x ≤ 1 := by cases x <;> decide
theorem val_BinOp_size (x : BinOp) : BinOp.size x ≤ 13 := by cases x <;> decide
theorem val_DivOp_size (x : DivOp) (w : Word) : DivOp.size x w ≤ 5 := by cases x <;> cases w <;> decide
theorem val_FOp_size (x : FOp) : FOp.size x ≤ 22 := by
  cases x <;> simp only [FOp.size] <;>
    first | omega | (rename_i a b; cases a <;> cases b <;> decide) | (rename_i a _; cases a <;> decide)
theorem val_FOp_number (x : FOp) : FOp.number x ≤ 19 := by
  cases x <;> simp only [FOp.number] <;>
    first | omega | (rename_i a b; cases a <;> cases b <;> decide)

/-! Code sizes: a statement's code is at most 64 bytes per unit of its weight
(`Room.lean`), which `compileFunc`'s room check bounds by the image limit, so
the pc offsets the compile adds up stay small (the compile side's
`COMPILE_OVERRIDES` in `tools/pre_certs.py`). -/

theorem val_compileStmt (base pos brk cont : Nat) (s : Stmt) :
    codeSize (compileStmt base pos brk cont s) ≤ 64 * s.weight := codeSize_le base s pos brk cont
theorem val_compileExpr (base : Nat) (e : Expr) (depth : Nat) :
    codeSize (compileExpr base e depth) ≤ 40 * e.weight := codeSize_le_expr base e depth
theorem val_compileArgs (base : Nat) (args : List Expr) (k : Nat) :
    codeSize (compileArgs base args k) + 14 * args.length ≤ 64 * argsWeight args :=
  codeSize_le_args base args k
theorem val_zeroLocals (first count : Nat) : codeSize (zeroLocals first count) = 7 * count := by
  induction count generalizing first with
  | zero => simp [zeroLocals, codeSize]
  | succ c ih => rw [zeroLocals]; simp [codeSize, Instr.size, ih]; omega

/-! Temporaries: `compileFunc` adds a function's locals and its body's
temporaries before its room check, so the Mini compile's pre lemmas carry the
most temporaries of the functions they compile (`funcsTemps`, below `K`; where
it comes from: `Lanius.Open.LowerFuncsTemps`, `Lanius.Open.OptimizeKeepsNumbers`). -/

/-- The most temporaries any of the functions' bodies uses. -/
def funcsTemps : List Func → Nat
  | [] => 0
  | f :: fs => max (Stmt.temps f.body) (funcsTemps fs)

/-- `funcsTemps` of a lowering's result (`0` when it failed). -/
def optTemps : Option (List Func) → Nat
  | none => 0
  | some fs => funcsTemps fs

theorem paramsMax_le (fs : List SrcFunc) (k : Nat) (h : ∀ f ∈ fs, paramsSize f.params ≤ k) :
    paramsMax fs ≤ k := by
  induction fs with
  | nil => simp [paramsMax]
  | cons f fs ih =>
    simp only [paramsMax, Nat.max_le]
    exact ⟨h f (List.mem_cons_self ..), ih (fun g hg => h g (List.mem_cons_of_mem _ hg))⟩


/-- A string's ASCII test, as a bound (`pre_auto` simplifies an `if`'s condition
by `hb_simp`): `lower_str` lowers only ASCII strings, so `str_words`' bytes are
below 128 (its `COMPILE_OVERRIDES` invariant, `nb chars ≤ 255`). -/
@[hb_simp] theorem strAscii_eq_true (l : List Nat) : (strAscii l = true) = (nb l < 128) := by
  induction l with
  | nil => simp only [strAscii, nb_nil]; decide
  | cons c r ih =>
    simp only [strAscii, Bool.and_eq_true, decide_eq_true_eq, ih, nb_cons]
    show (c < 128 ∧ nb r < 128) = (max c (nb r) < 128)
    apply propext; omega

@[hb_simp] theorem strAscii_eq_false (l : List Nat) : (strAscii l = false) = (128 ≤ nb l) := by
  have h := strAscii_eq_true l
  apply propext
  cases hs : strAscii l
  · rw [hs] at h
    have : ¬ nb l < 128 := by rw [← h]; simp
    simp only [true_iff]; omega
  · rw [hs] at h
    have : nb l < 128 := by rw [← h]
    simp only [Bool.true_eq_false, false_iff]; omega


/-- A body's temporaries are at most its weight, which `compileFunc`'s room check
bounds (`roomFits_stmtRoom`): `compile_func`'s `locals + temps`. -/
theorem val_Stmt_temps (s : Stmt) : Stmt.temps s ≤ Stmt.weight s := Stmt.temps_le_weight s

/-- A round packs the bytes it does not leave (as `PreBinaryWordsV3`'s proof). -/
theorem packRound_count_rest : ∀ (k : Nat) (xs : List UInt8),
    (packRound xs k).count + (packRound xs k).rest.length = xs.length
  | 0, xs => by rw [packRound.eq_def]; simp
  | k + 1, [] => by rw [packRound.eq_def]; simp [roundEnd]
  | k + 1, [a] => by rw [packRound.eq_def]; simp [roundCons, roundEnd]
  | k + 1, [a, b] => by rw [packRound.eq_def]; simp [roundCons, roundEnd]
  | k + 1, [a, b, c] => by rw [packRound.eq_def]; simp [roundCons, roundEnd]
  | k + 1, a :: b :: c :: d :: rd => by
    have ih := packRound_count_rest k rd
    rw [packRound.eq_def]
    simp only [Nat.add_one_ne_zero, if_false, roundCons, Nat.add_sub_cancel, List.length_cons]
    omega

theorem packRounds_count_rest : ∀ (fuel : Nat) (xs : List UInt8),
    (packRounds xs fuel).count + (packRounds xs fuel).rest.length = xs.length
  | 0, xs => by rw [packRounds.eq_def]; simp only [if_true]; exact packRound_count_rest _ xs
  | fuel + 1, xs => by
    have hr := packRound_count_rest 4096 xs
    rw [packRounds.eq_def]
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel]
    split
    · exact hr
    · rename_i x more heq
      have ih := packRounds_count_rest fuel (packRound xs 4096).rest
      simp only [roundJoin]
      omega

/-- A round's byte count and what it leaves are at most its bytes (`round_cons`, `round_join`). -/
theorem val_packRound (xs : List UInt8) (k : Nat) :
    (packRound xs k).count ≤ hb xs ∧ hb (packRound xs k).rest ≤ hb xs := by
  have := packRound_count_rest k xs
  simp only [pc_hb_u8]; omega

theorem val_packRounds (xs : List UInt8) (fuel : Nat) : (packRounds xs fuel).count ≤ hb xs := by
  have := packRounds_count_rest fuel xs
  simp only [pc_hb_u8]; omega

/-- The entries `layout` lays out are at most where the codes end (`link_onto`'s entries). -/
theorem val_layout : ∀ (start : Nat) (codes : List Code), nb (layout start codes) ≤ start + codesSize codes
  | _, [] => by simp only [layout, nb_nil]; omega
  | start, c :: rest => by
    have := val_layout (start + Code.size c) rest
    simp only [layout, nb_cons, nb_nat, codesSize] at *
    omega

/-- The largest number in the codes' instructions (`encode_onto`'s `nb` premise). -/
def codesNb : List Code → Nat
  | [] => 0
  | c :: rest => max (nb c.instrs) (codesNb rest)

/-- A program's numbers are its functions' (`compile_program`'s `nb`, for `vals_compileFuncs`). -/
theorem nb_Program_eq (p : Program) : nb p = nb p.funcs := rfl

end Lanius.Faithful.SelfPre

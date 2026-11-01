import Lanius.Mini.SourceCorrect
import Lanius.Std.SetSpec
import Lanius.Std.VecPrograms

/-! # S7: a `Vec` client through the verified compiler

`last_or_zero(v)` calls `std::vec::len` and `std::vec::get_or`. In any source
program that `compileSource` accepts and whose Core image is a `std::vec`
instance at `i32`, Core runs `last_or_zero(v)` on a vector `v` representing
`xs` in a heap built by earlier Core code (a `Vec` some other function
pushed into, say) to `xs.getLast?.getD 0`, by the vector specs. Then
`compileSource_correct_from` gives that the compiled function returns slots
representing that value and leaves a heap representing Core's. -/

namespace Lanius.Std

section core
open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {ids : VecIds}

/-- `fn last_or_zero(v: Vec<i32>) -> i32 { let n: i32 = std::vec::len(v);
return std::vec::get_or(v, n - 1, 0); }` -/
def lastOrZeroSrc (ids : VecIds) : Mini.SrcFunc where
  params := [⟨0, .struct ids.vec [.ptr, .i32, .i32]⟩]
  ret := .i32
  body := .letCall 1 .i32 ids.len [.local 0]
    (.returnEval (.eCall ids.getOr [.ePure (.local 0), .ePure (.apply .minus (.local 1) (.int 1)),
      .ePure (.int 0)]))

theorem lastOr_eq (xs : List Value) (z : Value) :
    (if 0 ≤ (xs.length : Int) - 1 then (xs[((xs.length : Int) - 1).toNat]?).getD z else z) = xs.getLast?.getD z := by
  cases xs with
  | nil => rfl
  | cons a rest =>
      rw [if_pos (by simp), List.getLast?_eq_getElem?]
      congr 2
      simp

/-- Core's run of `last_or_zero(v)`. -/
theorem lastOrZero_core (inst : VecInstance P i32Ty ids) {f : FunctionId}
    (found : P.function? f = some ((lastOrZeroSrc ids).toCore f)) {caller : State}
    (formed : caller.CellsWellFormed) {v : Value} {xs : List Value}
    (rep : VecRep P i32Ty 4 ids.vec caller.heap v xs) :
    ∃ after, RunsExpr P caller (.call f ([v].map Expr.value)) (xs.getLast?.getD (.signed .i32 0)) after ∧
      PureFrame caller after := by
  have small : xs.length < 2 ^ 31 := by
    obtain ⟨p, cap, rfl, lenLe, capBound, _⟩ := id rep
    omega
  refine PureRun.call found rfl rfl formed ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  let E := E0.bindLocal 0 v
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f0.bindLocal _ _
  have l0 : E.local? 0 = some v := local_bound f0 0 _
  obtain ⟨S', lenRun, frame⟩ := len_spec inst fE rep
  refine PureRun.letRun (callArgs (RunsExprs.one (RunsExpr.local' l0)) lenRun) frame ?_
  have fS := frame.afterFormed
  let B := S'.bindLocal 1 (.signed .i32 xs.length)
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have b1 : B.local? 1 = some (.signed .i32 xs.length) := local_bound fS 1 _
  have b0 : B.local? 0 = some v := local_kept fS _ (by decide) (frame.localFound l0)
  have one : (1 : BitVec 32).toInt = 1 := rfl
  have zero : (0 : BitVec 32).toInt = 0 := rfl
  have sub : RunsExpr P B (.binary .subtract (.local 1) (.value (.signed .i32 (1 : BitVec 32).toInt)))
      (.signed .i32 ((xs.length : Int) - 1)) B :=
    RunsExpr.binary (RunsExpr.local' b1) (RunsExpr.value' _) (by decide)
      (by rw [inst.target, one]; exact eval_i32_sub (by omega) (by omega))
  obtain ⟨S2, getRun, frame2⟩ := getOr_spec inst ElemKind.i32 fB (by rw [show B.heap = caller.heap from frame.heap]; exact rep)
    ((xs.length : Int) - 1) (.signed .i32 (0 : BitVec 32).toInt)
  rw [lastOr_eq, zero] at getRun
  exact PureRun.retCall (RunsExprs.three (RunsExpr.local' b0) sub (RunsExpr.value' _)) ⟨S2, getRun, frame2⟩

end core

section compiled
open Lanius.Mini Lanius.X86.Machine
open Lanius.Core (Value)

/-- What `compileSource_correct_from` promises of the compiled function `f`:
entered by a near call with `bits` in its parameter slots, a stack window
holding `depth` frames and a heap `heap`, it returns `results` and leaves
the heap `after`. -/
def MachineReturns (binary : Binary) (depth f : Nat) (bits : List (BitVec 64)) (heap : Heap)
    (results : List (BitVec 64)) (after : Heap) : Prop :=
  ∀ (s : State) (imageBase : BitVec 64) (window : Nat),
    binary.stackNeed depth ≤ window → window ≤ 2 ^ 62 →
    CodeAt s.memory imageBase binary.image →
    (∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index)) →
    (∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index)) →
    s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0) →
    (∀ k (bound : k < bits.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k]) →
    HeapAt window s heap → StackAt binary.guard window s →
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after

/-- A call that Core runs without touching the heap, by a Std spec, through
the verified compiler: the compiled call returns slots representing the same
value and a heap representing the same Core heap. -/
theorem compiled_of_pure {sp : SrcProgram} {binary : Binary} (compiled : compileSource sp = some binary)
    {f : Nat} {func : SrcFunc} (found : sp.funcs[f]? = some func) {args : List Value}
    {bits : List (BitVec 64)} (typed : FieldsHold (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {st : Semantics.State} {heap : Heap}
    (fresh : st.Fresh) (hc : HeapCorr st.heap st.world heap) (fits : st.heap.nextAddress ≤ heap.limit) {w : Value}
    (core : ∃ after, Semantics.RunsExpr sp.toCore st (.call f (args.map Core.Expr.value)) w after ∧
      Semantics.PureFrame st after) :
    ∃ depth results after, func.ret.HoldsAt w (Func.entry results) 0 ∧ results.length = func.ret.size ∧
      HeapCorr st.heap st.world after ∧ MachineReturns binary depth f bits heap results after := by
  obtain ⟨final, ⟨threshold, stable, _⟩, frame⟩ := core
  have heapEq : final.heap = st.heap := frame.heap
  have result := compileSource_correct_from compiled found typed bitsLen fresh hc (stable threshold (Nat.le_refl _))
    (by rw [heapEq]; exact fits)
  rw [heapEq, frame.world] at result
  exact result

/-- The heap invariants the verified compiler keeps give `HeapBlocksDisjoint`. -/
theorem HeapCorr.blocksDisjoint {h : Memory.Heap} {hp : Heap} (hc : HeapCorr h world hp) : Memory.HeapBlocksDisjoint h := by
  intro l lm r rm ne
  unfold Memory.BlockIntervalsDisjoint
  rcases Nat.lt_trichotomy l.base r.base with lt | eq | gt
  · exact Or.inl (hc.apart l lm r rm lt)
  · exact absurd (hc.unique l lm r rm eq) ne
  · exact Or.inr (hc.apart r rm l lm gt)

/-- The compiled `last_or_zero(v)`, entered with `v`'s slots and a heap
representing a Core heap in which `v` represents `xs`, returns slots
representing `xs.getLast?.getD 0`; its final heap represents the same Core
heap (the call only reads). -/
theorem vec_client_correct {sp : SrcProgram} {binary : Binary} (compiled : compileSource sp = some binary)
    {ids : VecIds} (inst : VecInstance sp.toCore i32Ty ids) {f : Nat}
    (found : sp.funcs[f]? = some (lastOrZeroSrc ids)) {v : Value} {bits : List (BitVec 64)}
    (typed : FieldsHold (paramTypes (lastOrZeroSrc ids).params) [v] (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize (lastOrZeroSrc ids).params)
    {st : Semantics.State} {heap : Heap} (fresh : st.Fresh) (hc : HeapCorr st.heap st.world heap)
    {xs : List Value} (rep : VecRep sp.toCore i32Ty 4 ids.vec st.heap v xs)
    (fits : st.heap.nextAddress ≤ heap.limit) :
    ∃ depth results after, SrcType.i32.HoldsAt (xs.getLast?.getD (.signed .i32 0)) (Func.entry results) 0 ∧
      results.length = SrcType.i32.size ∧ HeapCorr st.heap st.world after ∧
      MachineReturns binary depth f bits heap results after := by
  have coreFound : sp.toCore.function? f = some ((lastOrZeroSrc ids).toCore f) := by
    rw [SrcProgram.function?_toCore, found]
  exact compiled_of_pure compiled found typed bitsLen fresh hc fits (lastOrZero_core inst coreFound fresh.1 rep)

end compiled

/-! ## A concrete client program

`std::vec` at `i32` (the functions of `vecI32Program`, ids as in
`transcriptionIds`) written as source functions, and `last_or_zero` as
function 12. Its Core image is a vector instance by `rfl`. -/

section program
open Lanius.Mini

def vecSrcTy : SrcType := .struct 0 [.ptr, .i32, .i32]
def optionSrcTy : SrcType := .enum 1 [[.i32], []]

/-- `index < 0 || index >= value.length` -/
def badIndexSrc (i : Nat) : SrcExpr :=
  .apply .logicalOr (.apply .less (.local i) (.int 0)) (.apply .greaterEq (.local i) (.field 0 1))

def vecClientSrc : SrcProgram where
  funcs := [
    { params := [], ret := vecSrcTy,
      body := .let 0 .ptr .null (.returnEval (.eStruct vecSrcTy [.ePure (.local 0), .ePure (.int 0), .ePure (.int 0)])) },
    { params := [⟨0, vecSrcTy⟩], ret := .i32, body := .return (.field 0 1) },
    { params := [⟨0, vecSrcTy⟩], ret := .i32, body := .return (.field 0 2) },
    { params := [⟨0, vecSrcTy⟩], ret := .bool, body := .return (.apply .equal (.field 0 1) (.int 0)) },
    { params := [⟨0, vecSrcTy⟩, ⟨1, .i32⟩], ret := optionSrcTy,
      body := .then (.if (badIndexSrc 1) (.returnEval (.eVariant optionSrcTy 1 [])) .nop)
        (.letCall 2 (.slice .i32) 5 [.local 0]
          (.returnEval (.eVariant optionSrcTy 0 [.eIndex 2 (.ePure (.local 1))]))) },
    { params := [⟨0, vecSrcTy⟩], ret := .slice .i32,
      body := .returnEval (.eCall 6 [.ePure (.field 0 0), .ePure (.field 0 2)]) },
    { params := [⟨0, .ptr⟩, ⟨1, .i32⟩], ret := .slice .i32,
      body := .then (.assert (.ePure (.apply .greaterEq (.local 1) (.int 0))))
        (.let 2 .ptr .null
        (.letSlice 3 .i32 (.local 2) (.int 0)
        (.letEval 4 .isize (.eStride 3)
        (.then
          (.if (.apply .logicalOr (.apply .greaterEq (.local 4) (.cast .isize (.int 0)))
              (.apply .equal (.local 1) (.int 0)))
            (.letSlice 5 .i32 (.local 0) (.local 1) (.return (.local 5))) .nop)
        (.let 6 (.uint .usize)
          (.apply .minus
            (.apply .times (.cast (.uint .usize) (.apply .minus (.cast .isize (.int 0)) (.local 4)))
              (.cast (.uint .usize) (.local 1)))
            (.unsigned .usize 8))
        (.letSlice 7 .i32 (.apply .plus (.local 0) (.local 6)) (.local 1) (.return (.local 7)))))))) },
    { params := [⟨0, vecSrcTy⟩, ⟨1, .i32⟩, ⟨2, .i32⟩], ret := .i32,
      body := .then (.if (badIndexSrc 1) (.return (.local 2)) .nop)
        (.letCall 3 (.slice .i32) 5 [.local 0] (.returnEval (.eIndex 3 (.ePure (.local 1))))) },
    { params := [⟨0, vecSrcTy⟩, ⟨1, .i32⟩, ⟨2, .i32⟩], ret := vecSrcTy,
      body := .then (.if (badIndexSrc 1) (.return (.local 0)) .nop)
        (.letCall 3 (.slice .i32) 5 [.local 0] (.then (.setIndex 3 (.local 1) (.local 2)) (.return (.local 0)))) },
    { params := [⟨0, vecSrcTy⟩], ret := vecSrcTy,
      body := .then (.if (.apply .equal (.field 0 1) (.int 0)) (.return (.local 0)) .nop)
        (.returnEval (.eStruct vecSrcTy [.ePure (.field 0 0), .ePure (.apply .minus (.field 0 1) (.int 1)),
          .ePure (.field 0 2)])) },
    { params := [⟨0, vecSrcTy⟩, ⟨1, .i32⟩], ret := vecSrcTy,
      body := .then (.if (badIndexSrc 1) (.return (.local 0)) .nop)
        (.returnEval (.eStruct vecSrcTy [.ePure (.field 0 0), .ePure (.local 1), .ePure (.field 0 2)])) },
    { params := [⟨0, vecSrcTy⟩], ret := vecSrcTy,
      body := .returnEval (.eStruct vecSrcTy [.ePure (.field 0 0), .ePure (.int 0), .ePure (.field 0 2)]) },
    lastOrZeroSrc transcriptionIds]

theorem vecClientSrc_instance : VecInstance vecClientSrc.toCore i32Ty transcriptionIds :=
  ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

end program

section concrete
open Lanius.Mini Lanius.X86.Machine
open Lanius.Core (Value)

/-- `vec_client_correct` for `vecClientSrc`, whose `last_or_zero` is
function 12. (`compileSource vecClientSrc` is `some _`: `#eval` shows it;
the kernel does not reduce the compiler, so it stays a hypothesis.) -/
theorem vecClientSrc_correct {binary : Binary} (compiled : compileSource vecClientSrc = some binary)
    {v : Value} {bits : List (BitVec 64)}
    (typed : FieldsHold (paramTypes (lastOrZeroSrc transcriptionIds).params) [v] (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize (lastOrZeroSrc transcriptionIds).params)
    {st : Semantics.State} {heap : Heap} (fresh : st.Fresh) (hc : HeapCorr st.heap st.world heap)
    {xs : List Value} (rep : VecRep vecClientSrc.toCore i32Ty 4 0 st.heap v xs)
    (fits : st.heap.nextAddress ≤ heap.limit) :
    ∃ depth results after, SrcType.i32.HoldsAt (xs.getLast?.getD (.signed .i32 0)) (Func.entry results) 0 ∧
      results.length = SrcType.i32.size ∧ HeapCorr st.heap st.world after ∧
      MachineReturns binary depth 12 bits heap results after :=
  vec_client_correct compiled vecClientSrc_instance (f := 12) rfl typed bitsLen fresh hc rep fits

end concrete

#print axioms lastOrZero_core
#print axioms vecClientSrc_instance
#print axioms compiled_of_pure
#print axioms HeapCorr.blocksDisjoint
#print axioms vec_client_correct
#print axioms vecClientSrc_correct

end Lanius.Std

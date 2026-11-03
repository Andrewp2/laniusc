module

public import Lanius.Mini.Validate
public import Lanius.Mini.LowerEval
public import Lanius.Mini.Compiler.P.compileSource
import all Lanius.Mini.Compiler.P.BinOp_folds
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.Expr_agrees
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.FloatTy_rex
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
import all Lanius.Mini.Compiler.P.assignAgrees
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.binaryConstant
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
import all Lanius.Mini.Compiler.P.evalNot
import all Lanius.Mini.Compiler.P.evalSame
import all Lanius.Mini.Compiler.P.extentAfter
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.hostRandomCode
import all Lanius.Mini.Compiler.P.evalHost
import all Lanius.Mini.Compiler.P.imageLimit
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.iteThen
import all Lanius.Mini.Compiler.P.killShared
import all Lanius.Mini.Compiler.P.leftTrue
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
import all Lanius.Mini.Compiler.P.optimizeIte
import all Lanius.Mini.Compiler.P.optimizeLeft
import all Lanius.Mini.Compiler.P.optimizeNeg
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.withBudget
import all Lanius.Mini.Compiler.P.funcNeeds
import all Lanius.Mini.Compiler.P.sintToUint
import all Lanius.Mini.Compiler.P.storeArray
import all Lanius.Mini.Compiler.P.strStores
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.needRound
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.storeWordElement
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.substAll
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.wordStride
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.Types
public import Lanius.Mini.Compiler.P.storeArray
public import Lanius.Mini.Compiler.P.strStores
public import Lanius.Mini.Compiler.P.arrayCallSig
public import Lanius.Mini.Compiler.P.bindingBytes
public import Lanius.Mini.Compiler.P.funcNeeds
public import Lanius.Mini.Compiler.P.needRound
public import Lanius.Mini.Compiler.P.needsAfter
public import Lanius.Mini.Compiler.P.withBudget

@[expose] public section
/-! The verified compiler's top-level theorem for the Core subset: if Core
evaluates a call of a source function to a value, the machine code that
`compileSource` produces returns slots representing that value, provided the
stack has room for the call's nesting depth. `compileSource` runs the
unverified optimizer, and the theorem covers its output through the proved
validator (`compileOptimized_correct`). -/

namespace Lanius.Mini

variable {sx : Statics}

open Lanius.X86.Machine
open Lanius.Core (Value)

theorem evalExprs_values {P : Core.Program} {st : Semantics.State} :
    ∀ {vs : List Value} {fuel : Nat} {values : List Value} {st' : Semantics.State},
      Semantics.evalExprs fuel P st (vs.map Core.Expr.value) = .done values st' →
      values = vs ∧ st' = st := by
  intro vs
  induction vs with
  | nil =>
    intro fuel values st' run
    cases fuel with
    | zero => simp [Semantics.evalExprs] at run
    | succ fuel =>
      simp only [List.map_nil, Semantics.evalExprs, Semantics.Outcome.done.injEq] at run
      exact ⟨run.1.symm, run.2.symm⟩
  | cons v rest ih =>
    intro fuel values st' run
    cases fuel with
    | zero => simp [Semantics.evalExprs] at run
    | succ fuel =>
      cases fuel with
      | zero => simp [Semantics.evalExprs, Semantics.evalExpr] at run
      | succ fuel =>
        simp only [List.map_cons, Semantics.evalExprs, Semantics.evalExpr] at run
        split at run
        · rename_i rvs fin restRun
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨rfl, rfl⟩ := run
          obtain ⟨rfl, rfl⟩ := ih restRun
          exact ⟨rfl, rfl⟩
        all_goals simp at run

/-- Core's starting state for a process given the streams of `io`: an empty
heap, no cells, and a world holding standard input, the clocks' readings and
the secure bytes the process is given, and nothing else. -/
def startState (io : Lanius.X86.Machine.Io) : Semantics.State :=
  { world :=
      { standardInput := io.input
        monotonicReadings := io.monotonic
        systemReadings := io.realtime
        secureByteStream := io.entropy } }

theorem startState_fresh (io : Lanius.X86.Machine.Io) : (startState io).Fresh :=
  ⟨fun _ mem => by simp [startState] at mem, Views.ViewsHold.nil rfl⟩

/-- Core's starting state for the mini heap's input, and a mini heap whose
cursor is 1, whose bytes from 1 up are zero, and whose trace is empty. -/
theorem HeapCorr.empty {heap : Heap} (start : heap.cursor = 1) (zero : ∀ a, 1 ≤ a → heap.bytes a = 0)
    (small : heap.limit < 2 ^ 62) (silent : heap.io.trace = []) :
    HeapCorr (startState heap.io).heap (startState heap.io).world heap :=
  { cursor := start, pos := Nat.le_refl _, unbounded := rfl, small
    sized := fun _ mem => by cases mem
    below := fun _ mem => by cases mem
    apart := fun _ mem => by cases mem
    unique := fun _ mem => by cases mem
    bytes := fun _ mem => by cases mem
    zero := fun a ge _ => zero a ge
    out := by rw [silent]; rfl
    err := by rw [silent]; rfl
    closed := rfl
    input := rfl
    streams := ⟨rfl, rfl, rfl⟩ }

/-- `compileSource_correct` from any Core state whose cells are fresh and
whose heap the mini heap represents (`HeapCorr`), not just the empty one:
Core runs `f(args)` from `st` to `v` and `final`; the compiled `f` returns
`results` representing `v`, and its heap `after` represents Core's final heap.
A client that built values in the heap (a `Vec`, say) composes through this. -/
theorem compileSource_correct_from {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold sx [] (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {fuel : Nat} {v : Value}
    {st final : Semantics.State} {heap : Heap} (fresh : st.Fresh) (hc : HeapCorr st.heap st.world heap)
    (runs : Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)) = .done v final)
    (fits : final.heap.nextAddress ≤ heap.limit) (frameRoom : 0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62)
    (statics : heap.StaticsAt sx) (ofSp : sx.bytes = sp.decls.statics) :
    ∃ depth results after, func.ret.HoldsAt sx [] v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
      HeapCorr final.heap final.world after ∧
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
        ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after := by
  obtain ⟨_, _, funcs, lowered, compiledProgram⟩ := compileSource_some compiled
  haveI : StaticsOf sp sx := ⟨ofSp⟩
  cases fuel with
  | zero => simp [Semantics.evalExpr] at runs
  | succ k =>
    obtain ⟨func', values, afterArgs, completed, c, argsRun, found', _, bodyRun, result, rfl⟩ :=
      call_inv (List.getElem?_eq_some_iff.mp found).1 runs
    rw [found] at found'
    cases found'
    obtain ⟨rfl, rfl⟩ := evalExprs_values argsRun
    obtain ⟨_, _, depth, results, after, _, returns, holds, len, hc', -⟩ :=
      body_sound (mp := { funcs := funcs, statics := sp.decls.statics }) (hp := heap) lowered (stmt_sound lowered k) found
        fresh hc (FrameCorr.start _ frameRoom statics) (Nat.le_refl _) (fun _ mem => by simp at mem) typed bitsLen bodyRun result fits
    exact ⟨depth, results, after, holds, len, hc',
      fun s imageBase window enough bounded loaded apart imageHeap entry params heapAt stack =>
        compileOptimized_correct compiledProgram returns s imageBase window enough bounded loaded apart
          imageHeap entry params heapAt stack⟩

/-- Core runs `f(args)` from the empty state whose standard input is the
mini heap's (`startState`) to `v`, ending with its heap's
next free address at `final.heap.nextAddress`, and `bits` lay the arguments
out by parameter type (a struct one slot per field). Then the compiled `f`,
entered by a near call with `bits` in its parameter slots and a `heap` whose
cursor is 1, whose bytes from 1 up are zero, and whose limit Core's final
next address does not pass, returns `results` representing `v` in the same
slots, laid out the same way, with the heap's cursor at Core's final next
address. When the mini heap's trace starts empty, the bytes the compiled code
writes to the standard output and error (the machine's trace is `after`'s,
`Returned.io`) are those Core's world gained. -/
theorem compileSource_correct {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold sx [] (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {fuel : Nat} {v : Value}
    {final : Semantics.State} {heap : Heap} (start : heap.cursor = 1)
    (zero : ∀ a, 1 ≤ a → heap.bytes a = 0) (small : heap.limit < 2 ^ 62) (silent : heap.io.trace = [])
    (runs : Semantics.evalExpr fuel sp.toCore (startState heap.io) (.call f (args.map Core.Expr.value)) =
      .done v final)
    (fits : final.heap.nextAddress ≤ heap.limit) (frameRoom : 0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62)
    (statics : heap.StaticsAt sx) (ofSp : sx.bytes = sp.decls.statics) :
    ∃ depth results after, func.ret.HoldsAt sx [] v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
      after.cursor = final.heap.nextAddress ∧ final.world.standardOutput = outputOf 1 after.io.trace ∧
      final.world.standardError = outputOf 2 after.io.trace ∧
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
        ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after := by
  obtain ⟨depth, results, after, holds, len, hc, run⟩ := compileSource_correct_from compiled found typed bitsLen
    (st := startState heap.io) (startState_fresh _) (HeapCorr.empty start zero small silent) runs fits frameRoom statics ofSp
  exact ⟨depth, results, after, holds, len, hc.cursor, hc.out, hc.err, run⟩

end Lanius.Mini

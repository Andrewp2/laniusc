module

public import Lanius.Mini.SourceStops
public import Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.BinOp_folds
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.Expr_agrees
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.FloatTy_rex
import all Lanius.Mini.Compiler.P.Instr_pieces
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcType_size
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
import all Lanius.Mini.Compiler.P.imageLimit
import all Lanius.Mini.Compiler.P.importOk
import all Lanius.Mini.Compiler.P.importsOk
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
import all Lanius.Mini.Compiler.P.moduleExports
import all Lanius.Mini.Compiler.P.moduleFirsts
import all Lanius.Mini.Compiler.P.modulesOk
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
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.bindingBytes
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
public import Lanius.Mini.Compiler.P.compileSource
public import Lanius.Mini.Compiler.P.storeArray
public import Lanius.Mini.Compiler.P.arrayCallSig
public import Lanius.Mini.Compiler.P.bindingBytes
public import Lanius.Mini.Compiler.P.funcNeeds
public import Lanius.Mini.Compiler.P.needRound
public import Lanius.Mini.Compiler.P.needsAfter
public import Lanius.Mini.Compiler.P.withBudget

@[expose] public section
/-! # Every outcome of a compiled call, from any Core state

`compileSource_outcome_from` puts `compileSource_correct_from` and
`compileSource_stops_from` together for any stack window: the compiled `f`,
entered from an x86 state that represents a Core state `st`, either faults
(every run of it that stops, stops at a fault), or returns deterministically
what a completed Core call `f(args)` returns, with its heap representing
Core's final heap, or Core's call reaches an undefined trap. -/

namespace Lanius.Mini

open Lanius.X86.Machine
open Lanius.Core (Value)

/-- `compileSource_correct_from` for any stack window: the compiled `f`
returns, or the window is below what the run needs and it faults. -/
theorem compileSource_contract_from {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold [] (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {fuel : Nat} {v : Value}
    {st final : Semantics.State} {heap : Heap} (fresh : st.Fresh) (hc : HeapCorr st.heap st.world heap)
    (runs : Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)) = .done v final)
    (fits : final.heap.nextAddress ≤ heap.limit) (frameRoom : 0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62) :
    ∃ depth results after, func.ret.HoldsAt [] v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
      HeapCorr final.heap final.world after ∧
      ∀ imageBase window, Contract binary imageBase (binary.stackNeed depth) window f bits heap results after := by
  obtain ⟨_, _, funcs, lowered, compiledProgram⟩ := compileSource_some compiled
  cases fuel with
  | zero => simp [Semantics.evalExpr] at runs
  | succ k =>
    obtain ⟨func', values, afterArgs, completed, c, argsRun, found', _, bodyRun, result, rfl⟩ :=
      call_inv (List.getElem?_eq_some_iff.mp found).1 runs
    rw [found] at found'
    cases found'
    obtain ⟨rfl, rfl⟩ := evalExprs_values argsRun
    obtain ⟨_, _, depth, results, after, _, returns, holds, len, hc', -⟩ :=
      body_sound (mp := { funcs := funcs }) (hp := heap) lowered (stmt_sound lowered k) found
        fresh hc (FrameCorr.start _ frameRoom) (Nat.le_refl _) (fun _ mem => by simp at mem) typed bitsLen bodyRun result fits
    refine ⟨depth, results, after, holds, len, hc', fun imageBase window => ?_⟩
    rcases compileOptimized_some compiledProgram with original | ⟨q, accepted, optimized⟩
    · exact compiled_contract original imageBase depth f bits heap results after returns window
    · exact compiled_contract optimized imageBase depth f bits heap results after (returns.validated accepted) window

/-- Every outcome of the compiled `f` entered from an x86 state that
represents the Core state `st` (premises as in `compileSource_stops_from`):
it faults, or Core's call completes within the heap's limit and the compiled
code returns its results with a heap that represents Core's final heap, or
Core's call reaches an undefined trap within the heap's limit. -/
theorem compileSource_outcome_from {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold [] (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {st : Semantics.State} {heap : Heap}
    (fresh : st.Fresh) (hc : HeapCorr st.heap st.world heap) (within : st.heap.nextAddress ≤ heap.limit) (frameRoom : 0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62)
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < bits.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k])
    (heapAt : HeapAt window s heap) (stack : StackAt binary.guard window s) :
    Faults s ∨
    (∃ fuel v final, Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)) = .done v final ∧
      final.heap.nextAddress ≤ heap.limit ∧
      ∃ results after, func.ret.HoldsAt [] v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
        HeapCorr final.heap final.world after ∧ ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after) ∨
    ∃ fuel r st', Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)) = .trapped r st' ∧
      undefinedTrap r = true ∧ st'.heap.nextAddress ≤ heap.limit := by
  by_cases fails : ∀ fuel, Failing heap.limit (Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)))
  · exact .inl (compileSource_stops_from compiled found typed bitsLen fresh hc within frameRoom fails s imageBase window bounded
      loaded apart imageHeap entry params heapAt stack)
  · obtain ⟨fuel, notFailing⟩ := Classical.not_forall.mp fails
    rcases not_failing notFailing with ⟨v, final, done, fits⟩ | ⟨r, st', trapped, undefined, bound⟩
    · obtain ⟨depth, results, after, holds, len, hc', contract⟩ :=
        compileSource_contract_from compiled found typed bitsLen fresh hc done fits frameRoom
      rcases contract imageBase window s bounded loaded apart imageHeap entry params heapAt stack with
        ⟨n, s', run, det, ret⟩ | ⟨-, faults⟩
      · exact .inr (.inl ⟨fuel, v, final, done, fits, results, after, holds, len, hc', n, s', run, det, ret⟩)
      · exact .inl faults
    · exact .inr (.inr ⟨fuel, r, st', trapped, undefined, bound⟩)

/-- `compileSource_outcome_from` with the reason for a fault kept (review
finding 5): the compiled `f` faults only when Core's call fails at every fuel
(it diverges, stops at a checked trap, or completes with the heap past the
mini heap's limit), or when Core's call completes within the limit and the
stack window is below what the compiled run needs. Otherwise it returns
Core's results, or Core's call reaches an undefined trap. -/
theorem compileSource_outcome_reason {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold [] (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {st : Semantics.State} {heap : Heap}
    (fresh : st.Fresh) (hc : HeapCorr st.heap st.world heap) (within : st.heap.nextAddress ≤ heap.limit) (frameRoom : 0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62)
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < bits.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k])
    (heapAt : HeapAt window s heap) (stack : StackAt binary.guard window s) :
    ((∀ fuel, Failing heap.limit (Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)))) ∧
      Faults s) ∨
    (∃ fuel v final depth, Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)) = .done v final ∧
      final.heap.nextAddress ≤ heap.limit ∧ window < binary.stackNeed depth ∧ Faults s) ∨
    (∃ fuel v final, Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)) = .done v final ∧
      final.heap.nextAddress ≤ heap.limit ∧
      ∃ results after, func.ret.HoldsAt [] v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
        HeapCorr final.heap final.world after ∧ ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after) ∨
    ∃ fuel r st', Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)) = .trapped r st' ∧
      undefinedTrap r = true ∧ st'.heap.nextAddress ≤ heap.limit := by
  by_cases fails : ∀ fuel, Failing heap.limit (Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value)))
  · exact .inl ⟨fails, compileSource_stops_from compiled found typed bitsLen fresh hc within frameRoom fails s imageBase window
      bounded loaded apart imageHeap entry params heapAt stack⟩
  · obtain ⟨fuel, notFailing⟩ := Classical.not_forall.mp fails
    rcases not_failing notFailing with ⟨v, final, done, fits⟩ | ⟨r, st', trapped, undefined, bound⟩
    · obtain ⟨depth, results, after, holds, len, hc', contract⟩ :=
        compileSource_contract_from compiled found typed bitsLen fresh hc done fits frameRoom
      rcases contract imageBase window s bounded loaded apart imageHeap entry params heapAt stack with
        ⟨n, s', run, det, ret⟩ | ⟨short, faults⟩
      · exact .inr (.inr (.inl ⟨fuel, v, final, done, fits, results, after, holds, len, hc', n, s', run, det, ret⟩))
      · exact .inr (.inl ⟨fuel, v, final, depth, done, fits, short, faults⟩)
    · exact .inr (.inr (.inr ⟨fuel, r, st', trapped, undefined, bound⟩))

end Lanius.Mini

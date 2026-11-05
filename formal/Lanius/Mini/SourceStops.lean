module

public import Lanius.Mini.EvalStops
public import Lanius.Mini.StopsValidate
public import Lanius.Mini.SourceCorrect
public import Lanius.Mini.Compiler.P.SrcExpr_guard
public import Lanius.Mini.Compiler.P.boundsGuard
public import Lanius.Mini.Compiler.P.checkThen
public import Lanius.Mini.Compiler.P.expectType
public import Lanius.Mini.Compiler.P.guardAll
public import Lanius.Mini.Compiler.P.guarded
public import Lanius.Mini.Compiler.P.lowerAppend
public import Lanius.Mini.Compiler.P.lowerAs
public import Lanius.Mini.Compiler.P.slotVars
public import Lanius.Mini.Compiler.P.thenCheck
public import Lanius.Mini.Compiler.P.trap
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.FCmp_predicate
import all Lanius.Mini.Compiler.P.FOp_bytes
import all Lanius.Mini.Compiler.P.FOp_opcodeBytes
import all Lanius.Mini.Compiler.P.bumpBytes
import all Lanius.Mini.Compiler.P.floatOperands
import all Lanius.Mini.Compiler.P.floatResult
import all Lanius.Mini.Compiler.P.frameMemoryBytes
import all Lanius.Mini.Compiler.P.pow2
import all Lanius.Mini.Compiler.P.BinOp_size
import all Lanius.Mini.Compiler.P.Lists_concat
import all Lanius.Mini.Compiler.P.Lists_cons
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.Lists_get
import all Lanius.Mini.Compiler.P.Lists_getOr
import all Lanius.Mini.Compiler.P.Lists_length
import all Lanius.Mini.Compiler.P.Lists_single
import all Lanius.Mini.Compiler.P.MemWidth_bytes
import all Lanius.Mini.Compiler.P.MemWidth_prefix
import all Lanius.Mini.Compiler.P.MemWidth_rex
import all Lanius.Mini.Compiler.P.Word_prefix
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.boundsGuard
import all Lanius.Mini.Compiler.P.checkThen
import all Lanius.Mini.Compiler.P.expectType
import all Lanius.Mini.Compiler.P.guardAll
import all Lanius.Mini.Compiler.P.guarded
import all Lanius.Mini.Compiler.P.lowerAppend
import all Lanius.Mini.Compiler.P.lowerAs
import all Lanius.Mini.Compiler.P.slotVars
import all Lanius.Mini.Compiler.P.thenCheck
import all Lanius.Mini.Compiler.P.trap
import all Lanius.Mini.Compiler.P.BinOp_bytes
import all Lanius.Mini.Compiler.P.BinOp_opcode
import all Lanius.Mini.Compiler.P.CmpOp_setcc
import all Lanius.Mini.Compiler.P.CmpOp_setccSigned
import all Lanius.Mini.Compiler.P.CmpOp_setccUnsigned
import all Lanius.Mini.Compiler.P.DivOp_bytes
import all Lanius.Mini.Compiler.P.DivOp_extend
import all Lanius.Mini.Compiler.P.DivOp_opcode
import all Lanius.Mini.Compiler.P.DivOp_result
import all Lanius.Mini.Compiler.P.Word_rex
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.compileFuncs
import all Lanius.Mini.Compiler.P.fspLoad
import all Lanius.Mini.Compiler.P.fspSave
import all Lanius.Mini.Compiler.P.le32
import all Lanius.Mini.Compiler.P.le64
import all Lanius.Mini.Compiler.P.slotCompare
import all Lanius.Mini.Compiler.P.slotLoad
import all Lanius.Mini.Compiler.P.slotOffset
import all Lanius.Mini.Compiler.P.slotOperands
import all Lanius.Mini.Compiler.P.slotStore
import all Lanius.Mini.Compiler.P.compileSource
import all Lanius.Mini.Compiler.P.packWord
import all Lanius.Mini.Compiler.P.roundCons
import all Lanius.Mini.Compiler.P.roundEnd
import all Lanius.Mini.Compiler.P.usizeWords
import all Lanius.Mini.Compiler.P.Code_image
import all Lanius.Mini.Compiler.P.Code_size
import all Lanius.Mini.Compiler.P.Instr_encode
import all Lanius.Mini.Compiler.P.argBase
import all Lanius.Mini.Compiler.P.copyBytes
import all Lanius.Mini.Compiler.P.encodeFrom
import all Lanius.Mini.Compiler.P.encodeOnto
import all Lanius.Mini.Compiler.P.epilogue
import all Lanius.Mini.Compiler.P.frameSize
import all Lanius.Mini.Compiler.P.layout
import all Lanius.Mini.Compiler.P.linkFrom
import all Lanius.Mini.Compiler.P.linkOnto
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.loadWordBytes
import all Lanius.Mini.Compiler.P.prologue
import all Lanius.Mini.Compiler.P.relative
import all Lanius.Mini.Compiler.P.slotRange
import all Lanius.Mini.Compiler.P.stackCheck
import all Lanius.Mini.Compiler.P.storeAtBytes
import all Lanius.Mini.Compiler.P.storeWordBytes
import all Lanius.Mini.Compiler.P.sysBytes
import all Lanius.Mini.Compiler.P.syscallLinuxByte
import all Lanius.Mini.Compiler.P.syscallLinuxHigh
import all Lanius.Mini.Compiler.P.syscallRsiBytes
import all Lanius.Mini.Compiler.P.SrcEff_isSlice
import all Lanius.Mini.Compiler.P.SrcEff_passesSlices
import all Lanius.Mini.Compiler.P.SrcEff_sliceCall
import all Lanius.Mini.Compiler.P.SrcStmt_breaksOut
import all Lanius.Mini.Compiler.P.SrcStmt_depth
import all Lanius.Mini.Compiler.P.SrcStmt_lower
import all Lanius.Mini.Compiler.P.arrayCall
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.effsSlice
import all Lanius.Mini.Compiler.P.paramScope
import all Lanius.Mini.Compiler.P.paramTypes
import all Lanius.Mini.Compiler.P.paramsSize
import all Lanius.Mini.Compiler.P.paramsValid
import all Lanius.Mini.Compiler.P.stmtEval
import all Lanius.Mini.Compiler.P.needCapped
import all Lanius.Mini.Compiler.P.needRound
import all Lanius.Mini.Compiler.P.needRoundAt
import all Lanius.Mini.Compiler.P.restNeeds
import all Lanius.Mini.Compiler.P.sameNeeds
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.putElement
import all Lanius.Mini.Compiler.P.storeArrayElement
import all Lanius.Mini.Compiler.P.storeEval
import all Lanius.Mini.Compiler.P.storeEvalByte
import all Lanius.Mini.Compiler.P.storeEvalElement
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.storePick
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.withinLayout
import all Lanius.Mini.Compiler.P.lowerSetIndexOf
import all Lanius.Mini.Compiler.P.storeAny
import all Lanius.Mini.Compiler.P.storeWordElement
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.factDies
import all Lanius.Mini.Compiler.P.kill
import all Lanius.Mini.Compiler.P.killTail
import all Lanius.Mini.Compiler.P.mentionsAny
import all Lanius.Mini.Compiler.P.noneDies
import all Lanius.Mini.Compiler.P.substAll
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.SrcEff_eval
import all Lanius.Mini.Compiler.P.evalLen
import all Lanius.Mini.Compiler.P.evalLenOf
import all Lanius.Mini.Compiler.P.evalStr
import all Lanius.Mini.Compiler.P.evalStride
import all Lanius.Mini.Compiler.P.evalStrideOf
import all Lanius.Mini.Compiler.P.evalWordStride
import all Lanius.Mini.Compiler.P.staticByteIs
import all Lanius.Mini.Compiler.P.storeEvalThen
import all Lanius.Mini.Compiler.P.strPlaced
import all Lanius.Mini.Compiler.P.wordStride
import all Lanius.Mini.Compiler.P.declaredSame
import all Lanius.Mini.Compiler.P.declaredVariants
import all Lanius.Mini.Compiler.P.wordType
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.Types
public import Lanius.Mini.Compiler.P.compileSource
public import Lanius.Mini.Compiler.P.packWord
public import Lanius.Mini.Compiler.P.roundCons
public import Lanius.Mini.Compiler.P.roundEnd
public import Lanius.Mini.Compiler.P.usizeWords
public import Lanius.Mini.Compiler.P.lowerReturnUnit
public import Lanius.Mini.Compiler.P.lowerSetFieldEval
public import Lanius.Mini.Compiler.P.lowerUnreachable
public import Lanius.Mini.Compiler.P.lowerView
public import Lanius.Mini.Compiler.P.setFieldEvalAt
public import Lanius.Mini.Compiler.P.setFieldEvalOf
public import Lanius.Mini.Compiler.P.storeArray
public import Lanius.Mini.Compiler.P.strAscii
public import Lanius.Mini.Compiler.P.strWords
public import Lanius.Mini.Compiler.P.viewStores
public import Lanius.Mini.Compiler.P.blockAt
public import Lanius.Mini.Compiler.P.blockLoad
public import Lanius.Mini.Compiler.P.blockStore
public import Lanius.Mini.Compiler.P.elementLoads
public import Lanius.Mini.Compiler.P.elementStores
public import Lanius.Mini.Compiler.P.idAbsent
public import Lanius.Mini.Compiler.P.lowerAssert
public import Lanius.Mini.Compiler.P.lowerSetIndexAny
public import Lanius.Mini.Compiler.P.lowerSetIndexEval
public import Lanius.Mini.Compiler.P.lowerStr
public import Lanius.Mini.Compiler.P.packedWidth
public import Lanius.Mini.Compiler.P.strStores
public import Lanius.Mini.Compiler.P.SrcEff_isSlice
public import Lanius.Mini.Compiler.P.SrcEff_passesSlices
public import Lanius.Mini.Compiler.P.SrcEff_sliceCall
public import Lanius.Mini.Compiler.P.SrcStmt_breaksOut
public import Lanius.Mini.Compiler.P.SrcStmt_depth
public import Lanius.Mini.Compiler.P.SrcStmt_lower
public import Lanius.Mini.Compiler.P.arrayCall
public import Lanius.Mini.Compiler.P.arrayCallSig
public import Lanius.Mini.Compiler.P.effsSlice
public import Lanius.Mini.Compiler.P.paramScope
public import Lanius.Mini.Compiler.P.paramTypes
public import Lanius.Mini.Compiler.P.paramsSize
public import Lanius.Mini.Compiler.P.paramsValid
public import Lanius.Mini.Compiler.P.stmtEval
public import Lanius.Mini.Compiler.P.argBytes
public import Lanius.Mini.Compiler.P.arrayArg
public import Lanius.Mini.Compiler.P.arrayArgBefore
public import Lanius.Mini.Compiler.P.arrayArgChecked
public import Lanius.Mini.Compiler.P.arrayArgLocal
public import Lanius.Mini.Compiler.P.arrayArgPure
public import Lanius.Mini.Compiler.P.arrayArgSlice
public import Lanius.Mini.Compiler.P.arrayArgs
public import Lanius.Mini.Compiler.P.arrayCallCode
public import Lanius.Mini.Compiler.P.bindingBytes
public import Lanius.Mini.Compiler.P.blockLimit
public import Lanius.Mini.Compiler.P.Expr_extent
public import Lanius.Mini.Compiler.P.Stmt_extent
public import Lanius.Mini.Compiler.P.argsExtent
public import Lanius.Mini.Compiler.P.funcNeeds
public import Lanius.Mini.Compiler.P.sigs
public import Lanius.Mini.Compiler.P.sigsWith
public import Lanius.Mini.Compiler.P.needCapped
public import Lanius.Mini.Compiler.P.needRound
public import Lanius.Mini.Compiler.P.needRoundAt
public import Lanius.Mini.Compiler.P.restNeeds
public import Lanius.Mini.Compiler.P.sameNeeds
public import Lanius.Mini.Compiler.P.needsAfter
public import Lanius.Mini.Compiler.P.SrcEff_sliceUses
public import Lanius.Mini.Compiler.P.SrcStmt_calleeNeed
public import Lanius.Mini.Compiler.P.SrcStmt_sliceUses
public import Lanius.Mini.Compiler.P.arrayBytesOf
public import Lanius.Mini.Compiler.P.blockRoom
public import Lanius.Mini.Compiler.P.declBytes
public import Lanius.Mini.Compiler.P.frameBlock
public import Lanius.Mini.Compiler.P.paramsRoom
public import Lanius.Mini.Compiler.P.withBudget

@[expose] public section
/-! The verified compiler's top-level theorem for runs that do not complete:
if Core's call of a source function fails at every fuel (it runs out of fuel,
stops at a trap the compiled code checks, or completes with the heap past the
mini heap's limit, but never reaches an undefined trap), the machine code that
`compileSource` produces faults: every run of it from the entry ends at a
checked fault, or does not end. Together with `compileSource_correct` this
covers every call whose Core run reaches no undefined trap. -/

namespace Lanius.Mini

variable {sx : Statics}

open Lanius.X86.Machine
open Lanius.Core (Value)

theorem evalExprs_values_done {P : Core.Program} {st : Semantics.State} :
    ∀ (vs : List Value) (extra : Nat),
      Semantics.evalExprs (vs.length + extra + 1) P st (vs.map Core.Expr.value) = .done vs st
  | [], _ => by simp [Semantics.evalExprs]
  | v :: rest, extra => by
    have ih := evalExprs_values_done (P := P) (st := st) rest extra
    rw [show (v :: rest).length + extra + 1 = (rest.length + extra + 1) + 1 by simp only [List.length_cons]; omega]
    simp only [List.map_cons, Semantics.evalExprs, Semantics.evalExpr, ih]

/-- `compileSource_stops` from any Core state whose cells are fresh and whose
heap the mini heap represents, within its limit. -/
theorem compileSource_stops_from {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold sx [] (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {st : Semantics.State} {heap : Heap}
    (fresh : st.Fresh) (hc : HeapCorr st.heap st.world heap) (within : st.heap.nextAddress ≤ heap.limit) (frameRoom : 0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62)
    (statics : heap.StaticsAt sx) (ofSp : sx.bytes = sp.decls.statics)
    (fails : ∀ fuel, Failing heap.limit (Semantics.evalExpr fuel sp.toCore st (.call f (args.map Core.Expr.value))))
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < bits.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k])
    (heapAt : HeapAt window s heap) (stack : StackAt binary.guard window s) : Faults s := by
  obtain ⟨returns, _, funcs, lowered, compiledProgram⟩ := compileSource_some compiled
  haveI : StaticsOf sp sx := ⟨ofSp⟩
  have stops : ∀ n, ∃ depth, Program.Stops { funcs := funcs, statics := sp.decls.statics } depth f bits heap n := fun n => by
    obtain ⟨d, g, gFound, arity, body⟩ := callee_stops (mp := { funcs := funcs, statics := sp.decls.statics }) lowered returns
      (stmtStops_all lowered returns n) (evalExprs_values_done args 0) found fresh hc (LentHomes.start _ frameRoom statics) (Nat.le_refl _) within typed bitsLen fails
    exact ⟨d, g, gFound, arity, body⟩
  exact compileOptimized_stops compiledProgram stops s imageBase window bounded loaded apart imageHeap entry params
    heapAt stack

/-- Core's call `f(args)` from the empty state fails at every fuel, and `bits`
lay the arguments out by parameter type. Then the compiled `f`, entered by a
near call with `bits` in its parameter slots and a `heap` whose cursor is 1,
whose bytes from 1 up are zero, and whose limit is at least 1, faults: it
ends only at a checked fault, or runs forever. -/
theorem compileSource_stops {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold sx [] (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {heap : Heap} (start : heap.cursor = 1)
    (zero : ∀ a, 1 ≤ a → heap.bytes a = 0) (small : heap.limit < 2 ^ 62) (silent : heap.io.trace = [])
    (room : 1 ≤ heap.limit) (frameRoom : 0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62)
    (statics : heap.StaticsAt sx) (ofSp : sx.bytes = sp.decls.statics)
    (fails : ∀ fuel, Failing heap.limit (Semantics.evalExpr fuel sp.toCore (startState heap.io) (.call f (args.map Core.Expr.value))))
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < bits.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k])
    (heapAt : HeapAt window s heap) (stack : StackAt binary.guard window s) : Faults s := by
  have hc := HeapCorr.empty start zero small silent
  exact compileSource_stops_from compiled found typed bitsLen (st := startState heap.io) (startState_fresh _) hc
    (by rw [← hc.cursor, start]; exact room) frameRoom statics ofSp fails s imageBase window bounded loaded apart imageHeap entry params
    heapAt stack

/-- A Core result that is not `Failing`: a completion within the limit or an
undefined trap within it. -/
theorem not_failing {α : Type} {limit : Nat} {out : Semantics.Outcome α} (h : ¬Failing limit out) :
    (∃ v st, out = .done v st ∧ st.heap.nextAddress ≤ limit) ∨
    ∃ r st, out = .trapped r st ∧ undefinedTrap r = true ∧ st.heap.nextAddress ≤ limit := by
  cases out with
  | done v st => exact .inl ⟨v, st, rfl, Nat.le_of_not_lt h⟩
  | trapped r st =>
    refine .inr ⟨r, st, rfl, ?_, ?_⟩
    · cases u : undefinedTrap r with
      | true => rfl
      | false => exact absurd (.inl u) h
    · exact Nat.le_of_not_lt fun lt => h (.inr lt)
  | exited _ _ => exact absurd trivial h
  | outOfFuel => exact absurd trivial h

/-- The verified compiler's behaviour theorem. A run of the compiled `f` from
its entry (premises as in `compileSource_correct`, with any window) that ends
at a state with no step that is not a fault (the caller's exit, say) comes
from a Core call that completes, with the heap within its limit, or that
reaches an undefined trap. The completion is `compileSource_correct`'s, which
gives the results the compiled code returns. -/
theorem compileSource_behaviour {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold sx [] (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {heap : Heap} (start : heap.cursor = 1)
    (zero : ∀ a, 1 ≤ a → heap.bytes a = 0) (small : heap.limit < 2 ^ 62) (silent : heap.io.trace = [])
    (room : 1 ≤ heap.limit) (frameRoom : 0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62)
    (statics : heap.StaticsAt sx) (ofSp : sx.bytes = sp.decls.statics)
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < bits.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k])
    (heapAt : HeapAt window s heap) (stack : StackAt binary.guard window s)
    {m : Nat} {u : State} (run : Steps m s u) (stuck : ∀ v, ¬Lanius.X86.Machine.Step u v) (clean : ¬Lanius.X86.Machine.Fault u) :
    (∃ fuel v final, Semantics.evalExpr fuel sp.toCore (startState heap.io) (.call f (args.map Core.Expr.value)) = .done v final ∧
      final.heap.nextAddress ≤ heap.limit) ∨
    ∃ fuel r st, Semantics.evalExpr fuel sp.toCore (startState heap.io) (.call f (args.map Core.Expr.value)) = .trapped r st ∧
      undefinedTrap r = true ∧ st.heap.nextAddress ≤ heap.limit := by
  by_cases fails : ∀ fuel, Failing heap.limit
      (Semantics.evalExpr fuel sp.toCore (startState heap.io) (.call f (args.map Core.Expr.value)))
  · exact (clean (compileSource_stops compiled found typed bitsLen start zero small silent room frameRoom statics ofSp fails s imageBase window
      bounded loaded apart imageHeap entry params heapAt stack m s u (DataEq.refl s) run stuck)).elim
  · obtain ⟨fuel, notFailing⟩ := Classical.not_forall.mp fails
    rcases not_failing notFailing with ⟨v, final, done, fits⟩ | ⟨r, st, trapped, undefined, within⟩
    · exact .inl ⟨fuel, v, final, done, fits⟩
    · exact .inr ⟨fuel, r, st, trapped, undefined, within⟩

end Lanius.Mini

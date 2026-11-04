module

public import Lanius.Mini.SourceCorrect

@[expose] public section

open Lanius.Mini Lanius.X86.Machine
open Lanius.Core (Value)

/-- **F5's top statement** (SEMANTIC_DECISIONS "Stage 2's root" and "Stage
1's order", S4). `compileSource` is correct for programs with references:
a binary it makes, entered at a source function with arguments its
parameters' slots hold, returns the slots of the value Core's call returns,
with the same output, as `compileSource_correct` says. The entry function
takes no references, so no place is held at entry (`places = []`). While
`compileSource` rejects every reference form (stage 1) this is
`compileSource_correct`; when stage 1's S6 gives it the reference cases, the
proof goes through the F5 leaves, and if `compileSource_correct` takes a
temporary `noRefs` hypothesis then, this statement (without it) is what is
left to prove. -/
def Lanius.Open.SourceRefsCorrect : Prop :=
  ∀ {sx : Statics} {sp : SrcProgram} {binary : Binary},
    compileSource sp = some binary → ∀ {f : Nat} {func : SrcFunc},
    sp.funcs[f]? = some func → ∀ {args : List Value} {bits : List (BitVec 64)},
    FieldsHold sx [] (paramTypes func.params) args (Func.entry bits) 0 →
    bits.length = paramsSize func.params → ∀ {fuel : Nat} {v : Value}
    {final : Lanius.Semantics.State} {heap : Heap}, heap.cursor = 1 →
    (∀ a, 1 ≤ a → heap.bytes a = 0) → heap.limit < 2 ^ 62 → heap.io.trace = [] →
    Lanius.Semantics.evalExpr fuel sp.toCore (startState heap.io) (.call f (args.map Lanius.Core.Expr.value)) =
      .done v final →
    final.heap.nextAddress ≤ heap.limit →
    (0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62) →
    heap.StaticsAt sx → sx.bytes = sp.decls.statics →
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
        ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after

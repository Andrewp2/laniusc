import Lanius.Semantics.ExpressionProof
import Lanius.Semantics.StmtList

namespace Lanius.Semantics

open Lanius.Core

private def lookupFirst : Constant := { id := 7, type := .scalar (.signed .i32), value := .signed .i32 12 }
private def lookupSecond : Constant := { lookupFirst with value := .signed .i32 13 }
private def lookupFunction : Function := { id := 7, parameters := [], returnType := .unit, body := some .skip }
private def lookupProgram : Program :=
  { constants := [lookupFirst, lookupSecond], functions := [lookupFunction] }

example : lookupProgram.constant? 7 = some lookupFirst := by core_lookup
example : lookupProgram.constant? 8 = none := by core_lookup
example : lookupProgram.function? 7 = some lookupFunction := by core_lookup
example : lookupProgram.function? 8 = none := by core_lookup

-- The linked representation remains one list with first-match semantics.
-- Empty chunks and duplicates must not alter either a hit or a miss.
private def chunkedProgram : Program := {
  constants := Lanius.Data.List.flatten [[], [lookupFirst], [], [lookupSecond]]
  functions := Lanius.Data.List.flatten [[], [lookupFunction], []]
  structures := Lanius.Data.List.flatten [[{ id := 12, fields := [] }], []]
  enumerations := Lanius.Data.List.flatten [[], [{ id := 19, variants := [[], [.unit]] }]] }

example : chunkedProgram.constant? 7 = some lookupFirst := by core_lookup
example : chunkedProgram.constant? 8 = none := by core_lookup
example : chunkedProgram.function? 7 = some lookupFunction := by core_lookup
example : chunkedProgram.function? 8 = none := by core_lookup
example : chunkedProgram.structure? 12 = some { id := 12, fields := [] } := by core_lookup
example : chunkedProgram.enumeration? 19 = some { id := 19, variants := [[], [.unit]] } := by core_lookup

example : True := by
  fail_if_success
    have wrong : chunkedProgram.constant? 7 = some lookupSecond := by core_lookup
  fail_if_success
    have wrong : chunkedProgram.structure? 12 = some { id := 12, fields := [.unit] } := by core_lookup
  trivial

-- A thousand-entry negative lookup must not require a thousand-deep reduction.
private def wideProgram : Program := {
  functions := Lanius.Data.List.flatten (List.replicate 16 (List.replicate 64 lookupFunction)) }

theorem wideMiss : wideProgram.function? 8 = none := by core_lookup

#print axioms wideMiss

-- These aliases are declared after the program. Shared lookup facts must not
-- capture a later caller's names into the program's realization context.
private def lateLookupId : Nat := 7
private def lateLookupResult : Constant := lookupFirst

example : lookupProgram.constant? lateLookupId = some lateLookupResult := by core_lookup
example : chunkedProgram.constant? lateLookupId = some lateLookupResult := by core_lookup

example (state : State) :
    StableExpr 1 lookupProgram state (.constant 7) (.signed .i32 12) state := by core_expr

example (state : State) : True := by
  fail_if_success
    have wrong : StableExpr 1 lookupProgram state (.constant 7) (.signed .i32 13) state := by core_expr
  trivial

-- Finding an entry is not enough: lookup must preserve first-match semantics.
example : True := by
  fail_if_success
    have wrong : lookupProgram.constant? 7 = some lookupSecond := by core_lookup
  fail_if_success
    have absent : lookupProgram.function? 8 = some lookupFunction := by core_lookup
  trivial

example (program : Program) (state : State) (declaration : Constant)
    (found : program.constant? declaration.id = some declaration) :
    StableExpr 1 program state (.constant declaration.id) declaration.value state := by core_expr

-- A later mismatch must roll back the fuel inferred from an unrelated fact.
example (program : Program) (state : State)
    (wanted : StableExpr 2 program state (.value .unit) .unit state)
    (unrelated : StableExpr 3 program state (.value (.boolean true)) (.boolean true) state) :
    StableExpr 4 program state (.value .unit) .unit state := by
  apply StableExpr.weaken
  · core_contract
  · decide

-- Even with matching computation/result, a state mismatch must roll back
-- the already inferred fuel before trying the next fact.
example (program : Program) (state other : State)
    (_wanted : StableExpr 2 program state (.value .unit) .unit state)
    (_unrelated : StableExpr 3 program other (.value .unit) .unit other) :
    StableExpr 4 program state (.value .unit) .unit state := by
  apply StableExpr.weaken
  · core_contract
  · decide

example (program : Program) (state other : State)
    (_unrelated : RunsExpr program other (.value .unit) .unit other) : True := by
  fail_if_success
    have wrong : RunsExpr program state (.value .unit) .unit state := by core_contract
  trivial

-- Syntax is matched first, but a later state mismatch still rolls back
-- every inferred expression, result and output state.
example (program : Program) (state other after : State) (expression : Expr) (value : Value)
    (_wanted : RunsExpr program state expression value after)
    (_unrelated : RunsExpr program other (.value .unit) .unit other) :
    ∃ expression value after, RunsExpr program state expression value after := by
  apply Exists.intro
  apply Exists.intro
  apply Exists.intro
  core_contract

example (program : Program) (state other after : State) (statement : Stmt) (completion : Completion)
    (_wanted : RunsStmt program state statement completion after)
    (_unrelated : RunsStmt program other .skip .next other) :
    ∃ statement completion after, RunsStmt program state statement completion after := by
  apply Exists.intro
  apply Exists.intro
  apply Exists.intro
  core_contract

example (state : State) (wanted : state.local? 10 = some (.boolean true))
    (unrelated : state.local? 20 = some (.boolean true)) : state.local? 10 = some (.boolean true) := by
  core_contract

-- An unknown key may still be inferred; filtering must not forbid this case.
example (state : State) (wanted : state.local? 10 = some (.boolean true)) :
    ∃ id, state.local? id = some (.boolean true) := by
  apply Exists.intro
  core_contract

example (state other : State) (wanted : state.local? 10 = some (.boolean true))
    (unrelated : other.local? 10 = some (.boolean true)) : state.local? 10 = some (.boolean true) := by
  core_contract

-- Local scopes do not change a native read. The matcher must reuse the
-- supplied fact rather than run the native-layout reader again.
example (program : Program) (state : State) (element : Ty) (address length index : Nat) (value : Value)
    (loaded : readRawSliceIndex program state element address length index = .ok value) :
    readRawSliceIndex program (state.bindLocal 10 .unit |>.bindLocal 20 value)
      element address length index = .ok value := by core_contract

example (program otherProgram : Program) (state other : State) (element otherElement : Ty)
    (address length index : Nat) (value : Value)
    (_loaded : readRawSliceIndex program state element address length index = .ok value) : True := by
  fail_if_success
    have wrongHeap : readRawSliceIndex program other element address length index = .ok value := by core_contract
  fail_if_success
    have wrongProgram : readRawSliceIndex otherProgram state element address length index = .ok value := by core_contract
  fail_if_success
    have wrongElement : readRawSliceIndex program state otherElement address length index = .ok value := by core_contract
  fail_if_success
    have wrongIndex : readRawSliceIndex program state element address length (index + 1) = .ok value := by core_contract
  trivial

-- A failed candidate must not retain a guessed read index or output value.
example (program : Program) (state other : State) (element : Ty) (address length : Nat)
    (wanted : readRawSliceIndex program state element address length 0 = .ok .unit)
    (unrelated : readRawSliceIndex program other element address length 1 = .ok (.boolean true)) :
    ∃ index value, readRawSliceIndex program state element address length index = .ok value := by
  apply Exists.intro
  apply Exists.intro
  core_contract

-- The indexed path retains uniqueness and the complete value obligation.
example (state : State) (formed : state.CellsWellFormed) :
    (state.bindLocals [(10, .unit), (20, .boolean true), (30, .signed .i32 7)]).local? 20 =
      some (.boolean true) := by core_bound_local

example (state : State) (formed : state.CellsWellFormed) (value : Value) :
    (state.bindLocals [(10, .unit), (20, value)]).local? 20 = some value := by core_bound_local

example (state : State) (formed : state.CellsWellFormed) : True := by
  fail_if_success
    have wrong : (state.bindLocals [(10, .unit), (20, .boolean true)]).local? 20 =
        some (.boolean false) := by core_bound_local
  fail_if_success
    have shadowed : (state.bindLocals [(10, .unit), (10, .boolean true)]).local? 10 =
        some .unit := by core_bound_local
  trivial

-- Framed contracts must match both states and the frame, not only their
-- computation and result.
example (program : Program) (state other : State)
    (_wanted : ∃ after, RunsExpr program state (.value .unit) .unit after ∧ PureFrame state after)
    (_wrong : ∃ after, RunsExpr program other (.value .unit) .unit after ∧ PureFrame other after) :
    ∃ after, RunsExpr program state (.value .unit) .unit after ∧ PureFrame state after := by
  core_contract

example (program : Program) (state other : State)
    (_wrong : ∃ after, RunsExpr program other (.value (.boolean true)) (.boolean true) after ∧ PureFrame other after) :
    True := by
  fail_if_success
    have invalid : ∃ after, RunsExpr program state (.value .unit) .unit after ∧ PureFrame state after := by
      core_contract
  trivial

example {program : Program} {state : State} {localId : VarId} {value : Bool}
    (found : state.local? localId = some (.boolean value)) :
    StableExpr 2 program state (.unary .logicalNot (.local localId)) (.boolean (!value)) state := by
  core_expr

-- Pure calls can introduce fresh cells. Local lookup transports through the
-- frame, without rebuilding the caller's bindings in each client proof.
example {before after : State} {localId : VarId} {value : Int}
    (frame : PureFrame before after) (found : before.local? localId = some (.signed .i32 value)) :
    after.local? localId = some (.signed .i32 value) := by core_local

example {before after : State} {localId : VarId}
    (frame : PureFrame before after) (found : before.local? localId = some (.boolean false)) : True := by
  fail_if_success
    have wrong : after.local? localId = some (.boolean true) := by core_local
  trivial

-- Writer/control contracts are local functions, rather than global transport
-- rules. Compose them without copying every retained lookup at each step.
example (before middle after : State) (id : VarId) (value : Value) (firstCell secondCell : CellId)
    (found : before.local? id = some value)
    (firstSeparate : before.cellId? id ≠ some firstCell)
    (secondSeparate : middle.cellId? id ≠ some secondCell)
    (first : ∀ key value, before.local? key = some value → before.cellId? key ≠ some firstCell →
      middle.local? key = some value)
    (second : ∀ key value, middle.local? key = some value → middle.cellId? key ≠ some secondCell →
      after.local? key = some value) : after.local? id = some value := by core_local

example (before after unrelated : State) (id : VarId) (cell : CellId)
    (found : before.local? id = some (.boolean true))
    (separate : before.cellId? id ≠ some cell)
    (kept : ∀ key value, before.local? key = some value → before.cellId? key ≠ some cell →
      after.local? key = some value) : True := by
  fail_if_success
    have wrongValue : after.local? id = some (.boolean false) := by core_local
  fail_if_success
    have wrongState : unrelated.local? id = some (.boolean true) := by core_local
  trivial

example (before after : State) (id : VarId) (cell : CellId)
    (found : before.local? id = some (.boolean true))
    (same : before.cellId? id = some cell)
    (kept : ∀ key value, before.local? key = some value → before.cellId? key ≠ some cell →
      after.local? key = some value) : True := by
  fail_if_success
    have overwritten : after.local? id = some (.boolean true) := by core_local
  trivial

-- Closed exclusions for several fresh bindings remain kernel-checked facts.
-- Automation must not preserve a shadowed name or change a retained value.
example (before after : State) (found : before.local? 10 = some (.boolean true))
    (kept : ∀ key value, key ≠ 20 ∧ key ≠ 30 → before.local? key = some value →
      after.local? key = some value) : after.local? 10 = some (.boolean true) := by core_local

example (before after : State) (found : before.local? 20 = some (.boolean true))
    (kept : ∀ key value, key ≠ 20 ∧ key ≠ 30 → before.local? key = some value →
      after.local? key = some value) : True := by
  fail_if_success
    have shadowed : after.local? 20 = some (.boolean true) := by core_local
  fail_if_success
    have wrong : after.local? 10 = some (.boolean false) := by core_local
  trivial

example (state : State) (tail : List (VarId × CellId)) (first second : CellId)
    (scope : state.locals = [(10, first), (20, second)] ++ tail) (ordered : first < second) :
    state.cellId? 20 ≠ some first := by core_cell_separate

example (state other : State) (tail : List (VarId × CellId)) (cell : CellId)
    (scope : other.locals = [(10, cell)] ++ tail) : True := by
  fail_if_success
    have wrongState : state.cellId? 10 = some cell := by core_cell_scope
  trivial

example (state : State) (tail : List (VarId × CellId)) (first middle last : CellId)
    (scope : state.locals = [(10, first)] ++ tail) (left : first < middle) (right : middle < last) :
    state.cellId? 10 ≠ some last := by
  have trans := Nat.lt_trans left right
  clear left right
  core_cell_separate

example {program : Program} {state : State} {localId : VarId} {value : Int}
    (found : state.local? localId = some (.signed .i32 value)) :
    StableExpr 3 program state
      (.binary .logicalOr (.binary .less (.local localId) (.value (.signed .i32 0)))
        (.binary .greater (.local localId) (.value (.signed .i32 255))))
      (.boolean (decide (value < 0) || decide (value > 255))) state := by
  core_expr

example {program : Program} {state : State} {position : Nat}
    (formed : state.CellsWellFormed) (bound : position < 2 ^ 31)
    (found : state.local? 10 = some (.signed .i32 position)) :
    StableExpr 3 program (state.bindLocal 20 .unit |>.bindLocal 30 .unit)
      (.binary .multiply (.binary .remainder (.local 10) (.value (.signed .i32 4)))
        (.value (.signed .i32 8))) (.signed .i32 ((position % 4) * 8 : Nat))
      (state.bindLocal 20 .unit |>.bindLocal 30 .unit) := by
  core_expr

example {program : Program} {state : State} {value : Int}
    (found : state.local? 10 = some (.signed .i32 value))
    (bad : value < 0 ∨ value > 255) :
    StableExpr 3 program state
      (.binary .logicalOr (.binary .less (.local 10) (.value (.signed .i32 (Int.ofNat 0))))
        (.binary .greater (.local 10) (.value (.signed .i32 255)))) (.boolean true) state := by
  core_guard

example {program : Program} {state : State} {value : Int}
    (found : state.local? 10 = some (.signed .i32 value)) (valid : 0 ≤ value ∧ value ≤ 255) :
    StableExpr 3 program state
      (.binary .logicalOr (.binary .less (.local 10) (.value (.signed .i32 (Int.ofNat 0))))
        (.binary .greater (.local 10) (.value (.signed .i32 255)))) (.boolean false) state := by
  core_guard

-- Wrong results, insufficient fuel, and trapping arithmetic must not produce
-- contracts. These check proof-search failure, not the runtime evaluator.
example (_program : Program) (_state : State) : True := by
  fail_if_success
    have wrong : StableExpr 1 _program _state (.value (.signed .i32 1)) (.signed .i32 2) _state := by
      core_expr
  fail_if_success
    have noFuel : StableExpr 0 _program _state (.value .unit) .unit _state := by
      core_expr
  fail_if_success
    have trapped : StableExpr 2 _program _state
        (.binary .divide (.value (.signed .i32 1)) (.value (.signed .i32 0)))
        (.signed .i32 0) _state := by core_expr
  fail_if_success
    have overflow : StableExpr 2 _program _state
        (.binary .add (.value (.signed .i32 2147483647)) (.value (.signed .i32 1)))
        (.signed .i32 2147483648) _state := by core_expr
  fail_if_success
    have negativeAsZero : StableExpr 2 lookupProgram _state
        (.binary .subtract (.value (.signed .i32 0)) (.value (.signed .i32 1)))
        (.signed .i32 0) _state := by core_expr
  fail_if_success
    have wrongGuard : StableExpr 2 _program _state
        (.binary .less (.value (.signed .i32 1)) (.value (.signed .i32 0)))
        (.boolean true) _state := by core_guard
  fail_if_success
    have noGuardFuel : StableExpr 0 _program _state (.value (.boolean true))
        (.boolean true) _state := by core_guard
  trivial

example (program : Program) (state : State) (left right : Nat)
    (ordered : right ≤ left) (bound : left < 2 ^ 31) :
    StableExpr 2 program state
      (.binary .subtract (.value (.signed .i32 left)) (.value (.signed .i32 right)))
      (.signed .i32 (left - right : Nat)) state := by core_expr

-- Short-circuiting needs no contract for the unreachable, trapping operand.
example (program : Program) (state : State) :
    StableExpr 2 program state
      (.binary .logicalOr (.value (.boolean true))
        (.binary .divide (.value (.signed .i32 1)) (.value (.signed .i32 0))))
      (.boolean true) state := StableExpr.logicalOrTrue StableExpr.value

example (program : Program) (state : State) (value : Nat)
    (found : state.local? 10 = some (.signed .i32 value))
    (bound : value < unsignedModulus program.target .usize) :
    StableExpr 3 program state (.cast (.unsigned .usize) (.local 10))
      (.unsigned .usize value) state := by
  core_expr

example (program : Program) (state : State) : True := by
  fail_if_success
    have wrong : StableExpr 2 program state (.cast .rawPtr (.value (.signed .i32 0))) (.pointer 0) state := by
      core_expr
  fail_if_success
    have wrong : StableExpr 1 program state (.cast (.unsigned .u8) (.value (.signed .i32 1)))
        (.unsigned .u8 1) state := by core_expr
  trivial

example (program : Program) (state : State) :
    StableExpr 2 program state (.i32SliceFromRawParts (.value (.pointer 0)) (.value (.signed .i32 0)))
      (.rawSlice (.scalar (.signed .i32)) 0 0) state := by core_expr

private def pairSliceProgram : Program := {
  structures := [{ id := 3, fields := [.scalar (.signed .i32), .scalar (.signed .i32)] }]
}

-- Empty nominal descriptors also need no backing heap, but do need a valid
-- positive-width nominal layout. Scalar and missing layouts are not nominal.
example (state : State) :
    StableExpr 2 pairSliceProgram state
      (.typedSliceFromRawParts (.structure 3) (.value (.pointer 0)) (.value (.signed .i32 0)))
      (.rawSlice (.structure 3) 0 0) state := by
  have layout : NativeLayout.valueWords? pairSliceProgram (.structure 3) = some 2 := by decide
  core_expr

example (state : State) : True := by
  fail_if_success
    have nonempty : StableExpr 2 pairSliceProgram state
        (.typedSliceFromRawParts (.structure 3) (.value (.pointer 0)) (.value (.signed .i32 1)))
        (.rawSlice (.structure 3) 0 1) state := by core_expr
  fail_if_success
    have scalar : StableExpr 2 pairSliceProgram state
        (.typedSliceFromRawParts (.scalar (.signed .i32)) (.value (.pointer 0)) (.value (.signed .i32 0)))
        (.rawSlice (.scalar (.signed .i32)) 0 0) state := by core_expr
  fail_if_success
    have missing : StableExpr 2 pairSliceProgram state
        (.typedSliceFromRawParts (.structure 4) (.value (.pointer 0)) (.value (.signed .i32 0)))
        (.rawSlice (.structure 4) 0 0) state := by core_expr
  trivial

example (program : Program) (state : State) : True := by
  fail_if_success
    have wrong : StableExpr 2 program state
        (.i32SliceFromRawParts (.value (.pointer 0)) (.value (.signed .i32 1)))
        (.rawSlice (.scalar (.signed .i32)) 0 1) state := by core_expr
  trivial

private abbrev stateAlias (state : State) : State := state
private abbrev boundState (state : State) : State :=
  state.bindLocals (List.range 32 |>.map fun id => (id + 20, .unit))

-- A later fixed-state fact must be rejected before reducing its cell list;
-- the matching earlier fact and its reducible spelling still remain usable.
theorem fixedStateContractSearch (program : Program) (state : State) (expression : Expr) (value : Value)
    (wanted : RunsExpr program (boundState state) expression value (boundState state))
    (unrelated : RunsExpr program state expression value state) :
    RunsExpr program (boundState (stateAlias state)) expression value (boundState state) := by core_contract

theorem lookupThroughLetAlias (state : State) (found : state.local? 17 = some (.boolean true)) :
    (stateAlias state).local? 17 = some (.boolean true) := by
  let alias := state
  change alias.local? 17 = some (.boolean true)
  core_contract

theorem rejectsUntransportedState (state : State) (found : state.local? 17 = some (.boolean true)) : True := by
  fail_if_success
    have withoutFrame : (boundState state).local? 17 = some (.boolean true) := by core_contract
  trivial

private def nominalAlias : Ty := .structure 3
private def boundValueAlias : Value := .rawSlice nominalAlias 64 0
theorem boundValueAliases (state : State)
    (found : (state.bindLocal 10 (.rawSlice (.structure 3) 64 0)).local? 10 =
      some (.rawSlice (.structure 3) 64 0)) :
    (state.bindLocal 10 boundValueAlias).local? 10 = some (.rawSlice (.structure 3) 64 0) := by core_contract

-- An opaque call result uses its supplied frame before speculative binding
-- or inventory search. Irrelevant deep-bound facts must not expand cells.
theorem opaquePureFrame (before after other : State) (frame : PureFrame before after)
    (found : before.local? 17 = some (.boolean true))
    (irrelevantFormed : (boundState other).CellsWellFormed)
    (irrelevantFound : (boundState other).local? 17 = some (.boolean true)) :
    after.CellsWellFormed ∧ after.local? 17 = some (.boolean true) := by
  constructor
  · core_formed
  · core_local

theorem opaqueFreshFrame (before after other : State) (formed : before.CellsWellFormed)
    (frame : FreshCellFrame before after) (irrelevant : (boundState other).CellsWellFormed) :
    after.CellsWellFormed := by core_formed

theorem boundFormedAliases (state : State) (formed : state.CellsWellFormed) :
    (boundState (stateAlias state)).CellsWellFormed := by core_formed

#print axioms fixedStateContractSearch
#print axioms lookupThroughLetAlias
#print axioms rejectsUntransportedState
#print axioms boundValueAliases
#print axioms opaquePureFrame
#print axioms opaqueFreshFrame
#print axioms boundFormedAliases

-- Repeated closed lookups may reuse only the proved query/result pair.
-- Late aliases must not capture a new realization context or weaken checking.
theorem reusedClosedLookup : chunkedProgram.constant? lateLookupId = some lateLookupResult := by
  core_lookup

theorem inferredLookupResult : ∃ declaration, chunkedProgram.constant? lateLookupId = some declaration := by
  apply Exists.intro
  core_lookup

private def otherLookupProgram : Program := { constants := [lookupSecond] }
theorem distinguishesLookupPrograms : otherLookupProgram.constant? 7 = some lookupSecond := by
  core_lookup

theorem rejectsCachedWrongResult : True := by
  fail_if_success
    have wrong : chunkedProgram.constant? lateLookupId = some lookupSecond := by core_lookup
  trivial

theorem rejectsCachedMissAsHit : True := by
  fail_if_success
    have wrong : wideProgram.function? 8 = some lookupFunction := by core_lookup
  trivial

#print axioms reusedClosedLookup
#print axioms inferredLookupResult
#print axioms distinguishesLookupPrograms
#print axioms rejectsCachedWrongResult
#print axioms rejectsCachedMissAsHit

end Lanius.Semantics

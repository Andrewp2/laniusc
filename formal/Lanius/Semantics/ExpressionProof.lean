import Lanius.Semantics.Stable
import Lanius.Semantics.CallRun
import Lanius.Semantics.Bindings
import Lanius.Semantics.NaturalArithmetic
import Lanius.Semantics.ProofFacts
import Lanius.Semantics.WellFormedAutomation
import Lanius.Data.List

namespace Lanius.Semantics

/-- Compose pure expression rules, using local lookup hypotheses and checked
    constant definitions. Arithmetic side conditions remain ordinary proof
    obligations; this never runs the evaluator or trusts native computation. -/
syntax "core_expr" : tactic
syntax "core_expr_step" : tactic
syntax "core_formed" : tactic
syntax "core_scalar" : tactic
syntax "core_guard" : tactic
syntax "core_guard_step" : tactic
syntax "core_guard_logic" : tactic

open Lean Meta Elab Tactic in
/-- Reflexivity only for identical expressions. Trying definitional reduction
    on a false symbolic guard can expand a large integer before failing. -/
elab "core_guard_refl" : tactic => withMainContext do
  let goal ← getMainGoal
  let some (_, left, right) := (← instantiateMVars (← goal.getType)).eq? |
    throwError "expected guard equality"
  unless left.consumeMData == right.consumeMData do throwError "guard is not syntactically reflexive"
  goal.assign (← mkEqRefl left)
  replaceMainGoal []

/-- Heap-only reads survive fresh local cells and any proved pure call. -/
private theorem rawSlice_heapEq (program : Lanius.Core.Program) (before after : State)
    (element : Lanius.Core.Ty) (address length index : Nat) (same : after.heap = before.heap) :
    readRawSliceIndex program after element address length index =
      readRawSliceIndex program before element address length index := by
  simp only [readRawSliceIndex, same]

open Lean Meta in
/-- Follow only supplied heap equalities and pure frames, never call bodies.
    The supplied-fact count bounds the search. -/
private def framedHeapEquality (left right : Expr) (frames : List Expr) (fuel : Nat) : MetaM (Option Expr) := do
  let saved ← saveState
  if ← isDefEq left right then return some (← mkEqRefl left)
  saved.restore
  let fuel + 1 := fuel | return none
  for equality in frames do
    let saved ← saveState
    let some (_, after, before) := (← inferType equality).eq? | continue
    if ← isDefEq left after then
      if let some tail ← framedHeapEquality before right frames fuel then
        return some (← mkEqTrans equality tail)
    saved.restore
  return none

open Lean Meta in
/-- Reject different fixed states without executing their binding inventories.
    Aliases and ordinary unknown-argument inference retain the enclosing policy. -/
private def contractArgument (left right : Expr) : MetaM Bool := do
  let left := (← instantiateMVars left).consumeMData
  let right := (← instantiateMVars right).consumeMData
  if left == right then return true
  if left.hasExprMVar || right.hasExprMVar then return ← isDefEq left right
  unless (← whnf (← inferType left)).isConstOf ``State do return ← isDefEq left right
  let parent := (← read).canUnfold?
  withCanUnfoldPred (fun config info => do
    if info.name == ``State.bindLocal || info.name == ``State.bindLocals ||
        info.name == ``State.bindCell then return false
    match parent with
    | some predicate => predicate config info
    | none => canUnfoldDefault config info) (isDefEq left right)

open Lean Meta Elab Tactic in
/-- Match contract arguments without unfolding the execution relation itself.
    A failed match must not start interpreting either program. -/
elab_rules : tactic
  | `(tactic| core_contract) => withMainContext do
    let goal ← getMainGoal
    let target := (← instantiateMVars (← goal.getType)).consumeMData
    let frames ← (← getLCtx).foldlM (init := []) fun frames declaration => do
      let type := (← instantiateMVars declaration.type).consumeMData
      let proof := mkFVar declaration.fvarId
      if type.isAppOfArity ``PureFrame 2 then
        return (← mkAppM ``PureFrame.heap #[proof]) :: frames
      return if type.eq?.any (fun (type, _, _) => type.isConstOf ``Lanius.Memory.Heap)
        then proof :: frames else frames
    if let some (type, left, right) := target.eq? then
      if type.isConstOf ``Lanius.Memory.Heap then
        let saved ← saveState
        if let some proof ← framedHeapEquality left right frames frames.length then
          goal.assign proof
          replaceMainGoal []
          return
        saved.restore
    let found ← (← getLCtx).findDeclRevM? fun declaration => do
      let mut declarationType := (← instantiateMVars declaration.type).consumeMData
      if declaration.isImplementationDetail then return none
      if target.getAppFn != declarationType.getAppFn ||
          target.getAppNumArgs != declarationType.getAppNumArgs then
        -- Contract records may have local abbreviations. Expose only their
        -- head, never normalize an execution relation to search for a match.
        let some name := target.getAppFn.constName? | return none
        unless isStructure (← getEnv) name do return none
        let some alias := declarationType.getAppFn.constName? | return none
        unless (← getReducibilityStatus alias) == .reducible do return none
        declarationType := (← whnf declarationType).consumeMData
        if target.getAppFn != declarationType.getAppFn ||
            target.getAppNumArgs != declarationType.getAppNumArgs then return none
      let saved ← saveState
      -- Reject a different lookup key before normalizing either state's
      -- cells/locals. The full comparison below still checks both states.
      if let some (_, left, _) := target.eq? then
        if let some (_, other, _) := declarationType.eq? then
          if left.getAppFn == other.getAppFn && left.getAppNumArgs == 2 &&
              (left.isAppOf ``State.local? || left.isAppOf ``State.cellId? || left.isAppOf ``State.cell?) then
            unless ← isDefEq left.getAppArgs[1]! other.getAppArgs[1]! do
              saved.restore
              return none
            -- Compare states before their lookup results: unifying two whole
            -- queries can otherwise execute both cell searches accidentally.
            unless ← contractArgument left.getAppArgs[0]! other.getAppArgs[0]! do
              saved.restore
              return none
          if left.isAppOfArity ``readRawSliceIndex 6 && other.isAppOfArity ``readRawSliceIndex 6 then
            -- Native reads depend on the heap, not local bindings. Match the
            -- read's identity before reduction, then compare the two heaps.
            for index in [0, 2, 3, 4, 5] do
              unless ← isDefEq left.getAppArgs[index]! other.getAppArgs[index]! do
                saved.restore
                return none
            let heap ← mkAppM ``State.heap #[left.getAppArgs[1]!]
            let otherHeap ← mkAppM ``State.heap #[other.getAppArgs[1]!]
            unless ← isDefEq heap otherHeap do
              if let some same ← framedHeapEquality heap otherHeap frames frames.length then
                unless ← isDefEq target.getAppArgs[2]! declarationType.getAppArgs[2]! do
                  saved.restore
                  return none
                let readEquality ← mkAppM ``rawSlice_heapEq #[left.getAppArgs[0]!,
                  other.getAppArgs[1]!, left.getAppArgs[1]!, left.getAppArgs[2]!,
                  left.getAppArgs[3]!, left.getAppArgs[4]!, left.getAppArgs[5]!, same]
                return some (← mkEqTrans readEquality (mkFVar declaration.fvarId))
              else
                saved.restore
                return none
      -- Execution contracts fix their syntax before comparing states. A
      -- different statement/expression must not expand an unrelated chain
      -- of local bindings while the search is only rejecting a candidate.
      let order := if target.isAppOfArity ``RunsExpr 5 || target.isAppOfArity ``RunsStmt 5 ||
          target.isAppOfArity ``RunsExprs 5 then #[0, 2, 1, 3, 4]
        else List.range target.getAppNumArgs |>.toArray
      if ← order.allM (fun index => contractArgument target.getAppArgs[index]! declarationType.getAppArgs[index]!) then
        return some (mkFVar declaration.fvarId)
      saved.restore
      return none
    let some found := found | throwError "no matching execution contract"
    goal.assign found
    replaceMainGoal []

/-- Reuse the linked table's existing chunks without interpreting one deeply
    nested lookup over their flattened payload. First-match semantics stay exact. -/
private theorem lookupByChunks {α : Type} (predicate : α → Bool) (chunks : List (List α))
    (result : Option α) (found : Lanius.Data.List.findChunks predicate chunks = result) :
    (Lanius.Data.List.flatten chunks).find? predicate = result := by
  rw [← Lanius.Data.List.findChunks_eq]
  exact found

-- Preserve the original query head in the generated proof's type. Otherwise
-- converting a generic list-lookup conclusion can normalize the whole query.
private theorem functionByChunks (program : Lanius.Core.Program) (id : Lanius.FunctionId)
    (chunks : List (List Lanius.Core.Function)) (result : Option Lanius.Core.Function)
    (entries : program.functions = Lanius.Data.List.flatten chunks)
    (found : Lanius.Data.List.findChunks (fun entry => entry.id == id) chunks = result) :
    program.function? id = result := by
  simpa only [Lanius.Core.Program.function?, entries] using lookupByChunks _ chunks result found

private theorem constantByChunks (program : Lanius.Core.Program) (id : Lanius.ConstantId)
    (chunks : List (List Lanius.Core.Constant)) (result : Option Lanius.Core.Constant)
    (entries : program.constants = Lanius.Data.List.flatten chunks)
    (found : Lanius.Data.List.findChunks (fun entry => entry.id == id) chunks = result) :
    program.constant? id = result := by
  simpa only [Lanius.Core.Program.constant?, entries] using lookupByChunks _ chunks result found

private theorem structureByChunks (program : Lanius.Core.Program) (id : Lanius.TypeId)
    (chunks : List (List Lanius.Core.StructDecl)) (result : Option Lanius.Core.StructDecl)
    (entries : program.structures = Lanius.Data.List.flatten chunks)
    (found : Lanius.Data.List.findChunks (fun entry => entry.id == id) chunks = result) :
    program.structure? id = result := by
  simpa only [Lanius.Core.Program.structure?, entries] using lookupByChunks _ chunks result found

private theorem enumerationByChunks (program : Lanius.Core.Program) (id : Lanius.TypeId)
    (chunks : List (List Lanius.Core.EnumDecl)) (result : Option Lanius.Core.EnumDecl)
    (entries : program.enumerations = Lanius.Data.List.flatten chunks)
    (found : Lanius.Data.List.findChunks (fun entry => entry.id == id) chunks = result) :
    program.enumeration? id = result := by
  simpa only [Lanius.Core.Program.enumeration?, entries] using lookupByChunks _ chunks result found

open Lean Meta in
/-- Only closed program/table/key inputs enter the realization context. The
    caller's requested result is checked afterwards, never captured here. -/
private def proveLookup (program id query : Expr) (table key rule : Name) : MetaM (Expr × Expr) := do
  let mut entries ← mkAppM table #[program]
  let tableEntries := entries
  let mut candidate := query
  repeat
    let entry ← whnf entries
    if entry.isAppOfArity ``List.nil 1 then
      candidate := mkApp (mkConst ``Option.none [0]) entry.getAppArgs[0]!
      break
    let #[_, head, tail] := entry.getAppArgs | throwError "expected declaration list"
    unless entry.isAppOf ``List.cons do throwError "expected declaration list"
    if ← isDefEq id (← mkAppM key #[head]) then
      candidate ← mkAppM ``Option.some #[head]
      break
    entries := tail
  let proof ← if let some flattened ← whnfUntil tableEntries ``Lanius.Data.List.flatten then do
      mkAppM rule #[program, id, flattened.getAppArgs[1]!, candidate,
        ← mkEqRefl flattened, ← mkEqRefl candidate]
    else mkEqRefl candidate
  return (← mkEq query candidate, proof)

open Lean Meta in
/-- Realize before scanning: an existing kernel-checked fact is replayed without
    repeating its proof construction. Private naming remains caller-module local. -/
private def rememberLookup (program id query : Expr) (table key rule : Name) : MetaM Name := do
  if let .const programName [] := program then
    if let .lit (.natVal symbol) := id then
      let env ← getEnv
      if env.areRealizationsEnabledForConst programName then
        let name := mkPrivateName env ((programName.appendAfter "_coreLookup").str
          s!"{query.getAppFn.constName!.getString!}_{symbol}")
        realizeConst programName name do
          let (type, proof) ← proveLookup program id query table key rule
          addDecl (.thmDecl { name, levelParams := [], type, value := proof })
        return name
  let (type, proof) ← proveLookup program id query table key rule
  withOptions (Elab.async.set · false) do mkAuxLemma [] type proof

open Lean Meta Elab Tactic in
/-- Closed symbol lookup without the elaborator's recursive table reduction.
    The scan proposes a result; the kernel checks the original lookup equality,
    sharing checked facts across branches. No native execution or additional axioms. -/
elab "core_lookup" : tactic => withMainContext do
  let goal ← getMainGoal
  let type ← instantiateMVars (← goal.getType)
  let some (_, query, result) := type.eq? | throwError "expected lookup equality"
  let (table, key, rule) ← match query.getAppFn.constName? with
    | some ``Lanius.Core.Program.constant? => pure (``Lanius.Core.Program.constants, ``Lanius.Core.Constant.id, ``constantByChunks)
    | some ``Lanius.Core.Program.function? => pure (``Lanius.Core.Program.functions, ``Lanius.Core.Function.id, ``functionByChunks)
    | some ``Lanius.Core.Program.structure? => pure (``Lanius.Core.Program.structures, ``Lanius.Core.StructDecl.id, ``structureByChunks)
    | some ``Lanius.Core.Program.enumeration? => pure (``Lanius.Core.Program.enumerations, ``Lanius.Core.EnumDecl.id, ``enumerationByChunks)
    | _ => throwError "expected constant, function, structure or enum lookup"
  let #[program, id] := query.getAppArgs | throwError "expected program and symbol ID"
  if query.hasFVar || query.hasMVar then throwError "closed lookup required"
  -- A later source alias for the ID is not part of the realization context.
  -- Store the normalized key, not the caller's spelling of that key.
  let id ← whnf id
  let query := mkApp2 query.getAppFn program id
  let name ← rememberLookup program id query table key rule
  let some (_, _, candidate) := (← getConstInfo name).type.eq? | throwError "expected lookup fact"
  unless ← isDefEq result candidate do throwError "lookup result differs"
  let type ← instantiateMVars type
  if type.hasFVar || type.hasMVar then throwError "closed lookup equality required"
  goal.assign (mkConst name)
  replaceMainGoal []

open Lean Meta Elab Tactic in
/-- Apply binding rules with the actual entry state and binding fixed before
    unification. Local lookup search must not infer them by executing cells. -/
elab "core_bound_local" : tactic => withMainContext do
  let some (_, query, _) := (← instantiateMVars (← (← getMainGoal).getType)).eq? |
    throwError "expected local lookup"
  unless query.isAppOfArity ``State.local? 2 do throwError "expected local lookup"
  let mut state := query.getAppArgs[0]!
  repeat
    state := (← instantiateMVars state).consumeMData
    if let .fvar id := state then
      if let some value := (← id.getDecl).value? then
        state := value
        continue
    break
  if state.isAppOfArity ``State.bindLocal 3 then
    let base ← Term.exprToSyntax state.getAppArgs[0]!
    let id ← Term.exprToSyntax state.getAppArgs[1]!
    let value ← Term.exprToSyntax state.getAppArgs[2]!
    if ← isDefEq query.getAppArgs[1]! state.getAppArgs[1]! then
      evalTactic (← `(tactic| apply State.bindLocal_local? $base (id := $id) (value := $value)))
      evalTactic (← `(tactic| core_formed))
    else
      evalTactic (← `(tactic|
        apply State.bindLocal_local?_of_ne $base (newId := $id) (newValue := $value)))
      evalTactic (← `(tactic| core_formed))
      evalTactic (← `(tactic| decide))
      evalTactic (← `(tactic| core_local))
    return
  unless state.isAppOfArity ``State.bindLocals 2 do throwError "expected parameter bindings"
  let bindings := state.getAppArgs[1]!
  let mut tail := bindings
  let mut index := 0
  repeat
    let entry ← whnf tail
    unless entry.isAppOfArity ``List.cons 3 do throwError "parameter not bound"
    let binding := entry.getAppArgs[1]!
    let saved ← saveState
    if ← isDefEq query.getAppArgs[1]! (← mkAppM ``Prod.fst #[binding]) then
      let base ← Term.exprToSyntax state.getAppArgs[0]!
      let list ← Term.exprToSyntax bindings
      let selected ← Term.exprToSyntax binding
      let position ← Term.exprToSyntax (mkNatLit index)
      evalTactic (← `(tactic|
        apply State.bindLocals_local?_get? $base $list
          (index := $position) (binding := $selected)))
      evalTactic (← `(tactic| core_formed))
      evalTactic (← `(tactic| first | core_contract |
        (simp only [List.map_cons, List.map_nil, Prod.fst]; decide)))
      evalTactic (← `(tactic| rfl))
      return
    saved.restore
    index := index + 1
    tail := entry.getAppArgs[2]!

open Lean Meta Elab Tactic in
/-- Apply a local preservation contract only after matching its destination
    state, key, and value. The old lookup and cell separation remain checked
    premises; searching never evaluates a writer or invents a frame. -/
elab "core_local_kept" : tactic => withMainContext do
  let goal ← getMainGoal
  let target ← instantiateMVars (← goal.getType)
  let some (_, query, value) := target.eq? | throwError "expected local lookup"
  unless query.isAppOfArity ``State.local? 2 do throwError "expected local lookup"
  for declaration in (← getLCtx) do
    if declaration.isImplementationDetail || !declaration.type.isForall then continue
    let saved ← saveState
    try
      let (parameters, _, conclusion) ← forallMetaTelescope declaration.type
      unless parameters.size == 4 do throwError "not a cell preservation contract"
      let some (_, other, result) := conclusion.eq? | throwError "not a lookup contract"
      unless other.isAppOfArity ``State.local? 2 do throwError "not a lookup contract"
      -- Fix the state before the key/result, avoiding cell-search reduction
      -- while considering contracts from earlier or unrelated writes.
      unless ← isDefEq query.getAppArgs[0]! other.getAppArgs[0]! do throwError "different destination"
      unless ← isDefEq query.getAppArgs[1]! other.getAppArgs[1]! do throwError "different key"
      unless ← isDefEq value result do throwError "different value"
      let key ← instantiateMVars parameters[0]!
      let stored ← instantiateMVars parameters[1]!
      unless !key.hasMVar && !stored.hasMVar do throwError "lookup not fixed"
      setGoals ((← goal.apply (mkApp2 (mkFVar declaration.fvarId) key stored)) ++ (← getGoals).tail)
      return
    catch _ => saved.restore
  throwError "no local preservation contract for this state"

open Lean Meta Elab Tactic in
/-- Reduce a cell query using the proved lexical scope of that exact state,
    not its stored values. Ordering/separation remains an ordinary goal. -/
elab "core_cell_scope" : tactic => withMainContext do
  let type ← instantiateMVars (← (← getMainGoal).getType)
  let some query := type.find? (·.isAppOfArity ``State.cellId? 2) |
    throwError "expected a cell query"
  let state := query.getAppArgs[0]!
  for declaration in (← getLCtx) do
    let some (_, left, _) := declaration.type.eq? | continue
    unless left.isAppOfArity ``State.locals 1 do continue
    let saved ← saveState
    unless ← isDefEq state left.getAppArgs[0]! do
      saved.restore
      continue
    let fact ← Term.exprToSyntax (mkFVar declaration.fvarId)
    evalTactic (← `(tactic| simp [State.cellId?, $fact:term]))
    return
  throwError "no proved scope for this state"

open Lean Meta Elab Tactic in
elab "core_cell_separate" : tactic => do
  evalTactic (← `(tactic| core_cell_scope))
  if (← getGoals).isEmpty then return
  withMainContext do
    let mut facts : Array (TSyntax ``Parser.Tactic.SolveByElim.arg) := #[]
    for declaration in (← getLCtx) do
      -- Do not feed execution contracts or arbitrary preservation functions
      -- into arithmetic proof search.
      let type := (← instantiateMVars declaration.type).consumeMData
      if type.isAppOf ``LT.lt || type.isAppOf ``LE.le ||
          type.isAppOf ``Nat.lt || type.isAppOf ``Nat.le then
        let fact ← Term.exprToSyntax (mkFVar declaration.fvarId)
        facts := facts.push (← `(Parser.Tactic.SolveByElim.arg| $fact:term))
    -- Use an existing order before attempting to construct another chain.
    facts := facts ++ #[← `(Parser.Tactic.SolveByElim.arg| Nat.ne_of_lt),
      ← `(Parser.Tactic.SolveByElim.arg| Nat.ne_of_gt),
      ← `(Parser.Tactic.SolveByElim.arg| Nat.lt_trans)]
    evalTactic (← `(tactic| solve_by_elim only [$facts,*]))

open Lean Meta Elab Tactic in
elab "core_nat_arithmetic" : tactic => do
  let goal ← getMainGoal
  let some (_, lhs, _) := (← instantiateMVars (← goal.getType)).eq? |
    throwError "expected a scalar evaluation equality"
  unless lhs.isAppOf ``evalBinaryValue do throwError "expected scalar evaluation"
  let #[target, operation, left, right] := lhs.getAppArgs |
    throwError "expected binary operands"
  let theoremName ← match operation with
    | .const ``Lanius.Core.BinaryOp.divide _ => pure ``eval_i32_divNat
    | .const ``Lanius.Core.BinaryOp.remainder _ => pure ``eval_i32_modNat
    | .const ``Lanius.Core.BinaryOp.add _ => pure ``eval_i32_addNat
    | .const ``Lanius.Core.BinaryOp.subtract _ => pure ``eval_i32_subNat
    | .const ``Lanius.Core.BinaryOp.multiply _ => pure ``eval_i32_mulNat
    | _ => throwError "not nonnegative arithmetic"
  let #[_, left] := (← whnf left).getAppArgs | throwError "expected signed operands"
  let #[_, right] := (← whnf right).getAppArgs | throwError "expected signed operands"
  let left ← mkAppM ``Int.toNat #[left]
  let right ← mkAppM ``Int.toNat #[right]
  let remaining := (← getGoals).tail
  setGoals (← goal.apply (mkApp3 (mkConst theoremName) target left right))
  evalTactic (← `(tactic| all_goals
    (first | (simp only [Int.toNat_natCast, Int.toNat] <;> omega) | omega)))
  unless (← getGoals).isEmpty do throwError "arithmetic side conditions remain"
  setGoals remaining

open Lean Meta Elab Tactic in
elab "core_expr_node" : tactic => withMainContext do
  let target ← instantiateMVars (← (← getMainGoal).getType)
  unless target.isAppOfArity ``StableExpr 6 do throwError "expected expression contract"
  let expression ← whnf target.getAppArgs[3]!
  let rule ← match expression.getAppFn.constName? with
    | some ``Lanius.Core.Expr.value => `(tactic| exact StableExpr.value)
    | some ``Lanius.Core.Expr.local => `(tactic| (apply StableExpr.local; core_local))
    | some ``Lanius.Core.Expr.enumValue => `(tactic| exact StableExpr.enumEmpty)
    | some ``Lanius.Core.Expr.field =>
        `(tactic| (apply StableExpr.field <;> first | core_expr_step | rfl))
    | some ``Lanius.Core.Expr.index =>
        `(tactic| (apply StableExpr.rawSliceRead <;> first | core_expr_step | core_contract))
    | some ``Lanius.Core.Expr.i32SliceFromRawParts =>
        `(tactic| (apply StableExpr.emptyRawI32Slice <;> core_expr_step))
    | some ``Lanius.Core.Expr.typedSliceFromRawParts =>
        `(tactic| (apply StableExpr.emptyRawNominalSlice <;>
          first | core_contract | core_expr_step | rfl | omega))
    | some ``Lanius.Core.Expr.constant =>
        `(tactic| (apply StableExpr.constantResult <;> first | core_contract | core_lookup | rfl))
    | some ``Lanius.Core.Expr.unary =>
        `(tactic| apply StableExpr.unary <;> first | core_expr_step | core_scalar)
    | some ``Lanius.Core.Expr.cast =>
        `(tactic| apply StableExpr.cast <;> first | core_expr_step | core_scalar)
    | some ``Lanius.Core.Expr.binary =>
        if expression.getAppArgs[0]!.isConstOf ``Lanius.Core.BinaryOp.logicalAnd then
          `(tactic| first
            | (apply StableExpr.logicalAndFalse; core_expr_step)
            | (apply StableExpr.logicalAndTrue <;> core_expr_step)
            | (apply StableExpr.logicalAnd <;> core_expr_step))
        else if expression.getAppArgs[0]!.isConstOf ``Lanius.Core.BinaryOp.logicalOr then
          `(tactic| apply StableExpr.logicalOr <;> core_expr_step)
        else
          `(tactic| apply StableExpr.binary <;> first
            | core_expr_step | (solve | simp) | core_scalar)
    | _ => throwError "expression requires a supplied contract"
  evalTactic rule

open Lean Meta Elab Tactic in
elab_rules : tactic
  | `(tactic| core_scalar) => withMainContext do
    let type ← instantiateMVars (← (← getMainGoal).getType)
    let saved ← saveState
    try
      evalTactic (← `(tactic| core_contract))
      return
    catch _ => saved.restore
    if let some (_, left, _) := type.eq? then
      if !left.hasFVar && !left.hasMVar &&
          (left.isAppOf ``evalBinaryValue || left.isAppOf ``evalUnaryValue || left.isAppOf ``evalScalarCast) then
        -- Normalize only closed scalar arithmetic, not program execution.
        -- The resulting equality is still checked by the kernel.
        let value ← reduce left
        let proof ← mkEqRefl value
        unless ← isDefEq type (← inferType proof) do
          throwError "closed scalar result does not match the contract"
        (← getMainGoal).assign proof
        replaceMainGoal []
        return
    let comparison ← match type.eq? with
      | some (_, left, result) => do
          let result ← whnf result
          let mut needsNormalization := false
          if result.isAppOfArity ``Except.ok 3 then
            let value ← whnf result.getAppArgs[2]!
            if value.isAppOfArity ``Lanius.Core.Value.boolean 1 then
              let expected ← whnf value.getAppArgs[0]!
              if expected.isMVar && left.isAppOf ``evalBinaryValue then
                -- Choose an unknown result from the scalar operation's outer
                -- constructor, without simplifying or deciding its predicate.
                -- Simplification here can prematurely choose true or false.
                let proposed ← whnf left
                unless proposed.isAppOfArity ``Except.ok 3 do throwError "scalar operation does not return a value"
                let proposedValue ← whnf proposed.getAppArgs[2]!
                unless proposedValue.isAppOfArity ``Lanius.Core.Value.boolean 1 do
                  throwError "scalar operation does not return a Boolean"
                expected.mvarId!.assign proposedValue.getAppArgs[0]!
                let proof ← mkEqRefl proposed
                unless ← isDefEq type (← inferType proof) do throwError "scalar equality does not match"
                (← getMainGoal).assign proof
                replaceMainGoal []
                return
              needsNormalization := expected.isConstOf ``Bool.true || expected.isConstOf ``Bool.false
          pure (needsNormalization && left.isAppOf ``evalBinaryValue &&
            [``Lanius.Core.BinaryOp.less, ``Lanius.Core.BinaryOp.lessEqual,
              ``Lanius.Core.BinaryOp.greater, ``Lanius.Core.BinaryOp.greaterEqual,
              ``Lanius.Core.BinaryOp.equal, ``Lanius.Core.BinaryOp.notEqual].any
                (left.getAppArgs[1]!.isConstOf ·))
      | none => pure false
    if comparison then
      -- Fixed Boolean comparisons need normalization before unification.
      -- Otherwise a failed reflexivity attempt can expand large numerals.
      evalTactic (← `(tactic| first
        | assumption
        | (simp [evalBinaryValue, evalSignedBinary, scalarEqual] <;> omega)))
    else
      evalTactic (← `(tactic| first
        | assumption
        | (apply eval_unsigned_castNat; first | core_contract |
            (simp only [unsignedModulus, Lanius.Core.UnsignedIntTy.bits, Lanius.Core.PointerWidth.bits] <;> omega))
        | core_nat_arithmetic
        | rfl
        | (simp [evalBinaryValue, evalSignedBinary, scalarEqual] <;> omega)))

open Lean Meta Elab Tactic in
/-- Recurse through a visible binding with its arguments fixed. Speculative
    application can infer the invariant while leaving an unrelated ID goal. -/
elab "core_bound_formed" : tactic => withMainContext do
  let goal ← getMainGoal
  let target ← instantiateMVars (← goal.getType)
  unless target.isAppOfArity ``State.CellsWellFormed 1 do throwError "expected a cell-frontier invariant"
  let mut state := target.getAppArgs[0]!
  repeat
    state := (← instantiateMVars state).consumeMData
    if let .fvar id := state then
      if let some value := (← id.getDecl).value? then
        state := value
        continue
    break
  state ← withTransparency .reducible (whnf state)
  for (operation, rule, arity) in [(``State.bindLocal, ``State.CellsWellFormed.bindLocal, 3),
      (``State.bindLocals, ``State.CellsWellFormed.bindLocals, 2)] do
    if state.isAppOfArity operation arity then
      let base := state.getAppArgs[0]!
      let formed ← mkFreshExprSyntheticOpaqueMVar (← mkAppM ``State.CellsWellFormed #[base])
      let proof ← mkAppOptM rule (#[some base, some formed] ++
        (state.getAppArgs.extract 1 arity).map some)
      goal.assign proof
      replaceMainGoal [formed.mvarId!]
      evalTactic (← `(tactic| core_formed))
      return
  throwError "expected a visible local binding"

macro_rules
  | `(tactic| core_formed) => `(tactic|
      first
      | core_contract
      | core_bound_formed
      | (apply PureFrame.afterFormed; core_contract)
      | (focus (apply FreshCellFrame.after_cellsWellFormed; rotate_left; core_contract; core_formed))
      | assumption
      | core_execution_formed
      | (apply State.CellsWellFormed.bindLocal; core_formed)
      | (apply State.CellsWellFormed.bindLocals; core_formed))
  | `(tactic| core_local) => `(tactic|
      first
      | core_contract
      | core_bound_local
      | (apply PureFrame.localFound; core_contract; core_local)
      | apply State.bindLocal_local?; core_formed
      | apply State.bindLocal_local?_of_ne <;>
          first | core_formed | decide | (simp only [Prod.fst] <;> decide) | core_local
      | (core_local_kept <;> first | core_contract | decide | core_cell_separate | core_local)
      | core_local_rule)
  | `(tactic| core_expr_step) => `(tactic|
      first | core_contract | core_expr_node)
  | `(tactic| core_expr) => `(tactic|
      apply StableExpr.weaken <;> first | core_expr_step | decide)
  | `(tactic| core_guard_logic) => `(tactic| first
        | core_contract
        | core_guard_refl
        | (simp only [decide_eq_true_eq, decide_eq_false_iff_not, Int.ofNat_eq_natCast] <;>
            first | core_contract | omega)
        | (apply Bool.eq_false_iff.mpr; (try simp only [ne_eq]); core_contract)
        | ((try (apply Bool.eq_false_iff.mpr));
            (try simp only [Bool.or_eq_true, Bool.or_eq_false_iff, Bool.and_eq_true, Bool.and_eq_false_iff,
              Bool.not_eq_true', Bool.not_eq_false',
              Bool.false_or, Bool.true_or, Bool.false_and, Bool.true_and,
              Bool.false_eq_true, Bool.true_eq_false, false_or, true_or, false_and, true_and,
              decide_eq_true_eq, decide_eq_false_iff_not,
              beq_iff_eq, beq_eq_false_iff_ne, ne_eq, Int.ofNat_eq_natCast, or_assoc]) <;>
            first | core_contract | omega | grind))
  | `(tactic| core_guard_step) => `(tactic|
      apply StableExpr.booleanResult <;> first | core_expr_step | core_guard_logic)
  | `(tactic| core_guard) => `(tactic|
      apply StableExpr.weaken <;> first | core_guard_step | decide)

end Lanius.Semantics

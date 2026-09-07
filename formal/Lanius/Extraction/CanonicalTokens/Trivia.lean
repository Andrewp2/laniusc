import Lanius.Extraction.CanonicalTokens.Dispatch.Rule

namespace Lanius.Extraction.CanonicalTokens.Trivia

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

def result (kind : Int) : Bool := kind == 3 || kind == 10 || kind == 11

def equal (constant : ConstantId) : Expr := .binary .equal (.local 0) (.constant constant)

def body (whitespace lineComment blockComment : ConstantId) : Stmt :=
  .sequence (.returnValue (some (.binary .logicalOr
    (.binary .logicalOr (equal whitespace) (equal lineComment)) (equal blockComment)))) .skip

def sourceFunction (id : FunctionId) (whitespace lineComment blockComment : ConstantId) : Function := {
  id
  parameters := [(0, .scalar (.signed .i32))]
  returnType := .scalar .bool
  body := some (body whitespace lineComment blockComment)
}

def ConstantAt (program : Program) (id : ConstantId) (value : Int) : Prop :=
  program.constant? id = some { id, type := .scalar (.signed .i32), value := .signed .i32 value }

structure Checked (program : Program) (functionId : FunctionId) where
  whitespace : ConstantId
  lineComment : ConstantId
  blockComment : ConstantId
  whitespaceFound : ConstantAt program whitespace 3
  lineFound : ConstantAt program lineComment 10
  blockFound : ConstantAt program blockComment 11
  found : program.function? functionId = some (sourceFunction functionId whitespace lineComment blockComment)

private def checkConstant? (program : Program) (id : ConstantId) (value : Int) : Option (PLift (ConstantAt program id value)) := do
  match found : program.constant? id with
  | none => none
  | some constant =>
      let same ← Equality.constant? constant { id, type := .scalar (.signed .i32), value := .signed .i32 value }
      pure ⟨found.trans (congrArg some same.equal)⟩

def check? (program : Program) (functionId : FunctionId) : Option (Checked program functionId) := do
  match found : program.function? functionId with
  | none => none
  | some function =>
      let some (.sequence (.returnValue (some (.binary .logicalOr
          (.binary .logicalOr (.binary .equal _ (.constant whitespace))
            (.binary .equal _ (.constant lineComment))) (.binary .equal _ (.constant blockComment))))) _) := function.body | none
      let same ← Equality.function? function (sourceFunction functionId whitespace lineComment blockComment)
      let whitespaceFound ← checkConstant? program whitespace 3
      let lineFound ← checkConstant? program lineComment 10
      let blockFound ← checkConstant? program blockComment 11
      pure ⟨whitespace, lineComment, blockComment, whitespaceFound.down, lineFound.down, blockFound.down,
        found.trans (congrArg some same.equal)⟩

private theorem evaluates_equal (program : Program) (before : State) (kind : Int) {id : ConstantId} {value : Int}
    (localValue : before.local? 0 = some (.signed .i32 kind)) (constant : ConstantAt program id value) :
    Evaluates program before (equal id) (.boolean (kind == value)) before := by
  have localResult : Evaluates program before (.local 0) (.signed .i32 kind) before :=
    ⟨1, evalLocal_of_local 0 program before _ _ localValue⟩
  have constantResult : Evaluates program before (.constant id) (.signed .i32 value) before := by
    unfold ConstantAt at constant
    refine ⟨1, ?_⟩
    rw [evalExpr.eq_def]
    simp only [constant]
  exact evaluatesEagerBinary (by decide) (by decide) localResult constantResult (by rfl)

theorem Checked.evaluates_call (checked : Checked program functionId)
    (before : State) (kind : Int) (expression : Expr) (wellFormed : StateWellFormed before)
    (argument : Evaluates program before expression (.signed .i32 kind) before) :
    ∃ after, Evaluates program before (.call functionId [expression]) (.boolean (result kind)) after ∧
      CellEffect CellSet.empty before after := by
  let bindings : List (VarId × Value) := [(0, .signed .i32 kind)]
  let entered := enterCall before bindings
  have localValue : entered.local? 0 = some (.signed .i32 kind) :=
    enterCall_local_of_binding before [] [] 0 (.signed .i32 kind) wellFormed (by simp)
  have compared := evaluatesPureLogicalOr
    (evaluatesPureLogicalOr
      (evaluates_equal program entered kind localValue checked.whitespaceFound)
      (evaluates_equal program entered kind localValue checked.lineFound))
    (evaluates_equal program entered kind localValue checked.blockFound)
  have executed : Executes program entered (body checked.whitespace checked.lineComment checked.blockComment)
      (.returned (some (.boolean (result kind)))) entered :=
    executesSequenceReturned (executesReturnValue compared)
  have parameters : bindParameters
      (sourceFunction functionId checked.whitespace checked.lineComment checked.blockComment).parameters
      [.signed .i32 kind] = some bindings := rfl
  have called := evaluatesCallReturned (ArgumentsEvaluateTo.singleton argument) checked.found parameters rfl executed
  have effect := enterCall_effect before bindings
  refine ⟨restoreLocals before entered, called, ?_⟩
  exact CellEffect.ofModifiesOnly effect.restoreLocals
    (effect.restoreLocals_wellFormed wellFormed (enterCall_preserves_wellFormed wellFormed))

end Lanius.Extraction.CanonicalTokens.Trivia

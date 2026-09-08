import Lanius.Extraction.Frontend.Result

namespace Lanius.Extraction.Frontend

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}

/-- Source order and public BAD_INPUT detail codes. Depth is not one of the
eight length guards; materialization handles its own depth resource limit. -/
def inputLengths : List (VarId × Int) :=
  [(1, 1), (3, 2), (5, 3), (7, 4), (9, 5), (11, 6), (13, 7), (15, 8)]

def negativeLength (id : VarId) : Expr :=
  .binary .lessEqual (.local id) (.unary .negate (.value (.signed .i32 1)))

def invalidInput (result : FunctionId) (badInput : ConstantId) (detail : Int) : Stmt :=
  .sequence (.returnValue (some (.call result [.constant badInput, .value (.signed .i32 detail),
    .value (.signed .i32 0), .value (.signed .i32 0), .value (.signed .i32 0),
    .value (.signed .i32 0), .value (.signed .i32 0)]))) .skip

def inputGuards (result : FunctionId) (badInput : ConstantId) : List (VarId × Int) → Stmt → Stmt
  | [], rest => rest
  | (id, detail) :: entries, rest =>
    .sequence (.ifThenElse (negativeLength id) (invalidInput result badInput detail) .skip)
      (inputGuards result badInput entries rest)

structure CheckedInput (constructor : CheckedResult program) where
  badInput : ConstantId
  badValue : ParserTreeSource.constantValue program.core badInput 1

def CheckedInput.body (checked : CheckedInput constructor) (rest : Stmt) : Stmt :=
  inputGuards constructor.source.function.id checked.badInput inputLengths rest

/-- Authenticate the entire guard sequence, including order, exact error
fields, and adjacency to the already-checked lexer-to-return body. -/
def checkInput? (constructor : CheckedResult program) (body rest : Stmt) :
    Option (Σ checked : CheckedInput constructor, Core.Equality.Evidence body (checked.body rest)) := do
  let .sequence (.ifThenElse _ (.sequence (.returnValue (some (.call _ (.constant badInput :: _)))) .skip) _) _ := body
    | none
  let bad ← ParserTreeSource.checkConstantValue? program.core badInput 1
  let checked : CheckedInput constructor := ⟨badInput, bad.equal⟩
  let equal ← Core.Equality.statement? body (checked.body rest)
  pure ⟨checked, equal⟩

/-- The first negative length, requiring only the locals that the source reads
before returning. In particular, later lengths and all buffers may be absent. -/
inductive FirstNegative (lookup : VarId → Option Value) : List (VarId × Int) → Int → Prop
  | here {id : VarId} {length detail : Int} {rest : List (VarId × Int)}
      (read : lookup id = some (.signed .i32 length)) (negative : length < 0) :
      FirstNegative lookup ((id, detail) :: rest) detail
  | later {id : VarId} {length detail other : Int} {rest : List (VarId × Int)}
      (read : lookup id = some (.signed .i32 length)) (nonnegative : 0 ≤ length)
      (next : FirstNegative lookup rest detail) : FirstNegative lookup ((id, other) :: rest) detail

theorem FirstNegative.transfer (failed : FirstNegative lookup entries detail)
    (same : ∀ entry ∈ entries, other entry.1 = lookup entry.1) : FirstNegative other entries detail := by
  induction failed with
  | @here id length detail entries read negative => exact .here ((same (id, detail) (by simp)).trans read) negative
  | @later id length detail ignored entries read nonnegative _ ih =>
      exact .later ((same (id, ignored) (by simp)).trans read) nonnegative
        (ih (fun entry member => same entry (by simp [member])))

theorem negativeLength_evaluates (program : Program) {id : VarId}
    (read : before.local? id = some (.signed .i32 length)) :
    Evaluates program before (negativeLength id) (.boolean (decide (length < 0))) before := by
  have negativeOne : Evaluates program before (.unary .negate (.value (.signed .i32 1))) (.signed .i32 (-1)) before := by
    apply evaluatesUnary (show Evaluates program before (.value (.signed .i32 1)) (.signed .i32 1) before from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
  have same : decide (length ≤ -1) = decide (length < 0) := by
    simp only [show length ≤ -1 ↔ length < 0 from by omega]
  exact evaluatesEagerBinary (by decide) (by decide)
    ⟨1, evalLocal_of_local 0 _ _ _ _ read⟩ negativeOne (by simp [evalBinaryValue, evalSignedBinary, same])

/-- Passing all length guards leaves the state unchanged before the real body. -/
theorem inputGuards.pass (program : Program) (result : FunctionId) (badInput : ConstantId)
    (entries : List (VarId × Int))
    (nonnegative : ∀ entry ∈ entries, ∃ length, before.local? entry.1 = some (.signed .i32 length) ∧ 0 ≤ length)
    (tailRun : Executes program before rest completion after) :
    Executes program before (inputGuards result badInput entries rest) completion after := by
  induction entries with
  | nil => exact tailRun
  | cons entry entries ih =>
      obtain ⟨length, read, valid⟩ := nonnegative entry (by simp)
      have guardRun := negativeLength_evaluates program read
      have positive : ¬ length < 0 := by omega
      simp only [positive, decide_false] at guardRun
      exact executesSequence (executesIfFalse guardRun (executesSkip _ _))
        (ih (fun item member => nonnegative item (by simp [member])))

theorem CheckedInput.reject {constructor : CheckedResult program} (checked : CheckedInput constructor)
    (wellFormed : StateWellFormed before) (failed : FirstNegative before.local? entries detail) :
    ∃ after, (∀ rest, Executes program.core before
      (inputGuards constructor.source.function.id checked.badInput entries rest)
      (.returned (some (syntaxResult constructor.typeId 1 detail 0 0 0 0 0))) after) ∧
      CellEffect CellSet.empty before after := by
  induction failed with
  | @here id length detail entries read negative =>
      have guardRun := negativeLength_evaluates program.core read
      simp only [negative, decide_true] at guardRun
      have arguments : ArgumentsEvaluateTo program.core before
          [.constant checked.badInput, .value (.signed .i32 detail), .value (.signed .i32 0),
            .value (.signed .i32 0), .value (.signed .i32 0), .value (.signed .i32 0), .value (.signed .i32 0)]
          [.signed .i32 1, .signed .i32 detail, .signed .i32 0, .signed .i32 0,
            .signed .i32 0, .signed .i32 0, .signed .i32 0] before :=
        .cons (evaluatesConstant checked.badValue) (.cons ⟨1, rfl⟩ (.cons ⟨1, rfl⟩
          (.cons ⟨1, rfl⟩ (.cons ⟨1, rfl⟩ (.cons ⟨1, rfl⟩ (.singleton ⟨1, rfl⟩))))))
      obtain ⟨after, returned, effect⟩ := constructor.call wellFormed arguments
      exact ⟨after, fun _ => executesSequenceReturned
        (executesIfTrue guardRun (executesSequenceReturned (executesReturnValue returned))), effect⟩
  | @later id length detail other entries read nonnegative _ ih =>
      have guardRun := negativeLength_evaluates program.core read
      have positive : ¬ length < 0 := by omega
      simp only [positive, decide_false] at guardRun
      obtain ⟨after, returned, effect⟩ := ih
      exact ⟨after, fun rest => executesSequence (executesIfFalse guardRun (executesSkip _ _))
        (returned rest), effect⟩

end Lanius.Extraction.Frontend

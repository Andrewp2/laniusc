import Lanius.Compiler.FrontendArtifact
import Lanius.Compiler.LexerStream
import Lanius.Semantics.Call

namespace Lanius.Compiler

open Lanius Lanius.Core Lanius.Semantics
open Lanius.Compiler.Lexer

/-! The Core `LexResult` is the three-field view of the stream result.  The
    fuel-exhausted case is retained here so this encoding can also be used by
    bounded drivers; `lexRaw` itself proves that case impossible. -/

def rawLexResultValue : RawLexResult → Value
  | .success tokens =>
      .structure 4 [.signed .i32 0, .signed .i32 (Int.ofNat tokens.length),
        .signed .i32 0]
  | .failure tokens errorOffset =>
      .structure 4 [.signed .i32 1, .signed .i32 (Int.ofNat tokens.length),
        .signed .i32 (Int.ofNat errorOffset)]
  | .fuelExhausted tokens sourceOffset =>
      .structure 4 [.signed .i32 2, .signed .i32 (Int.ofNat tokens.length),
        .signed .i32 (Int.ofNat sourceOffset)]

def lexRawValue (source : List Byte) : Value :=
  rawLexResultValue (lexRaw source)

/-! Generic entry-point composition.  All evaluator detail for the body is
    supplied as one stable contract, so callers can prove a loop oracle (and
    output-buffer writes) once and reuse this boundary for any model type. -/

theorem thresholdModelEntryCall
    {α : Type} (program : Program) (caller : State) (function : Function)
    (arguments : List Expr) (body : Stmt) (values : List Value)
    (bindings : List (VarId × Value)) (afterArguments callee completed : State)
    (model : α) (encode : α → Value)
    (functionFound : program.function? function.id = some function)
    (bodyFound : function.body = some body)
    {argumentsFuel bodyFuel : Nat}
    (argumentsContract : ThresholdPureList argumentsFuel program caller
      arguments values afterArguments)
    (parametersBind : bindParameters function.parameters values = some bindings)
    (calleeShape : callee = ({ afterArguments with locals := [] }).bindLocals bindings)
    (bodyContract : StableStmt bodyFuel program callee body
      (.returned (some (encode model))) completed)
    (completedFrame : CallerFrame caller completed) :
    ThresholdPure (max argumentsFuel bodyFuel + 1) program caller
      (.call function.id arguments) (encode model) (restoreLocals caller completed) := by
  exact thresholdInternalCallUnderCaller program caller function arguments body values
    bindings afterArguments callee completed (encode model) functionFound bodyFound
    argumentsContract parametersBind calleeShape bodyContract completedFrame

/-! Thin artifact-specific wrapper.  The caller's `bodyContract` is the only
    remaining proof obligation for the actual loop, scanner dispatch, and
    bounded output writes. -/

theorem lexInto_refines_lexRaw_of_body
    (caller : State) (source : List Byte) (arguments : List Expr)
    (body : Stmt) (values : List Value) (bindings : List (VarId × Value))
    (afterArguments callee completed : State) (result : RawLexResult)
    {argumentsFuel bodyFuel : Nat}
    (argumentsContract : ThresholdPureList argumentsFuel FrontendArtifact.frontendProgram
      caller arguments values afterArguments)
    (bodyFound : FrontendArtifact.lexInto.body = some body)
    (parametersBind : bindParameters FrontendArtifact.lexInto.parameters values =
      some bindings)
    (calleeShape : callee = ({ afterArguments with locals := [] }).bindLocals bindings)
    (bodyContract : StableStmt bodyFuel FrontendArtifact.frontendProgram callee body
      (.returned (some (rawLexResultValue result))) completed)
    (completedFrame : CallerFrame caller completed)
    (resultEq : result = lexRaw source) :
    PurelyEvaluates FrontendArtifact.frontendProgram caller
      (.call FrontendArtifact.lexInto.id arguments) (lexRawValue source) := by
  have contract := thresholdModelEntryCall FrontendArtifact.frontendProgram caller
    FrontendArtifact.lexInto arguments body values bindings afterArguments callee completed
    result rawLexResultValue FrontendArtifact.lexInto_found bodyFound argumentsContract
    parametersBind calleeShape bodyContract completedFrame
  simpa [lexRawValue, resultEq] using contract.erase

theorem lexInto_id_current : FrontendArtifact.lexInto.id = 53 := by
  rfl

end Lanius.Compiler

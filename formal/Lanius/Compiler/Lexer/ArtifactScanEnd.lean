import Lanius.Compiler.Lexer.Artifact

namespace Lanius.Compiler.Lexer.Artifact

open Lanius Lanius.Core

private def i32Type : Ty := .scalar (.signed .i32)
private def scanEndType : Ty := .structure 0

private def returned (expression : Expr) : Stmt :=
  .sequence (.returnValue (some expression)) .skip

def scanSucceededFunction : Function := {
  id := 8
  parameters := [(0, scanEndType)]
  returnType := .scalar .bool
  body := some (returned (.field (.local 0) 0))
}

def scanEndOffsetFunction : Function := {
  id := 9
  parameters := [(0, scanEndType)]
  returnType := i32Type
  body := some (returned (.field (.local 0) 1))
}

def scanErrorOffsetFunction : Function := {
  id := 10
  parameters := [(0, scanEndType)]
  returnType := i32Type
  body := some (returned (.field (.local 0) 2))
}

def successfulScanFunction : Function := {
  id := 11
  parameters := [(0, i32Type)]
  returnType := scanEndType
  body := some (returned (.structValue 0
    [.value (.boolean true), .local 0, .value (.signed .i32 0)]))
}

def failedScanFunction : Function := {
  id := 12
  parameters := [(0, i32Type)]
  returnType := scanEndType
  body := some (returned (.structValue 0
    [.value (.boolean false), .value (.signed .i32 0), .local 0]))
}

theorem scanSucceededFunction_found :
    lexerProgram.function? scanSucceededFunction.id = some scanSucceededFunction := by
  rfl

theorem scanEndOffsetFunction_found :
    lexerProgram.function? scanEndOffsetFunction.id = some scanEndOffsetFunction := by
  rfl

theorem scanErrorOffsetFunction_found :
    lexerProgram.function? scanErrorOffsetFunction.id = some scanErrorOffsetFunction := by
  rfl

theorem successfulScanFunction_found :
    lexerProgram.function? successfulScanFunction.id = some successfulScanFunction := by
  rfl

theorem failedScanFunction_found :
    lexerProgram.function? failedScanFunction.id = some failedScanFunction := by
  rfl

end Lanius.Compiler.Lexer.Artifact

import Lanius.X86.Source.Buffer
import Lanius.X86.Register

namespace Lanius.X86.Source

open Lanius.Core Lanius.Extraction Lanius.X86.Register

def validationName : Validation → Surface.Name
  | .register => "valid"
  | .width => "width_valid"

def validationExpression : Validation → Expr
  | .register => .binary .logicalAnd
      (.binary .greaterEqual (read 0) (number 0)) (.binary .less (read 0) (number 16))
  | .width => .binary .logicalOr
      (.binary .equal (read 0) (number 32)) (.binary .equal (read 0) (number 64))

abbrev CheckedValidation (program : CoreSynthesis.Program.CheckedProgram artifacts) (kind : Validation) :=
  Extraction.Source.CheckedInternal program ["x86", "register"] (validationName kind)
    [(0, i32)] (.scalar .bool) (returned (validationExpression kind))

def checkValidation? (program : CoreSynthesis.Program.CheckedProgram artifacts) (kind : Validation) :
    Option (CheckedValidation program kind) :=
  Extraction.Source.checkInternal? program ["x86", "register"] (validationName kind)
    [(0, i32)] (.scalar .bool) (returned (validationExpression kind))

def rexInitial : Expr :=
  .binary .add
    (.binary .add (number 64) (.binary .multiply (.binary .divide (read 1) (number 8)) (number 4)))
    (.binary .divide (read 2) (number 8))

def rexWidth : Stmt :=
  .ifThenElse (.binary .equal (read 0) (number 64))
    (.sequence (.expression (.assign .add (.local 4) (number 8))) .skip) .skip

def rexOmitted : Expr :=
  .binary .logicalAnd (.binary .equal (read 4) (number 64)) (.unary .logicalNot (read 3))

def rexReturn : Stmt :=
  .sequence (.ifThenElse rexOmitted (returned (number 0)) .skip) (returned (read 4))

def rexBody : Stmt := .letLocal 4 i32 rexInitial (.sequence rexWidth rexReturn)

abbrev CheckedRex (program : CoreSynthesis.Program.CheckedProgram artifacts) :=
  Extraction.Source.CheckedInternal program ["x86", "register"] "rex"
    [(0, i32), (1, i32), (2, i32), (3, .scalar .bool)] i32 rexBody

def checkRex? (program : CoreSynthesis.Program.CheckedProgram artifacts) : Option (CheckedRex program) :=
  Extraction.Source.checkInternal? program ["x86", "register"] "rex"
    [(0, i32), (1, i32), (2, i32), (3, .scalar .bool)] i32 rexBody

end Lanius.X86.Source

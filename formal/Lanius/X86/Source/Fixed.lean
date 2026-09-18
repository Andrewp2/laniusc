import Lanius.X86.Source.Patch

namespace Lanius.X86.Source

open Lanius.Core Lanius.Extraction

def fixedIndex (offset : Nat) : Expr :=
  if offset = 0 then read 2 else .binary .add (read 2) (number offset)

def fixedStore (offset byte : Nat) : Expr :=
  .assign .set (.index (.local 0) (fixedIndex offset)) (number byte)

/-- A source-shape family for straight-line constant-byte instruction
emission. It authenticates the stores themselves, not an assumed byte result. -/
def fixedStatements (count offset : Nat) : List Nat → Stmt
  | [] => returned (.binary .add (read 2) (number count))
  | byte :: bytes => .sequence (.expression (fixedStore offset byte))
      (fixedStatements count (offset + 1) bytes)

def fixedGuard (fits : FunctionId) (count : Nat) : Expr :=
  .unary .logicalNot (.call fits [read 1, read 2, number count])

def fixedBody (fits : FunctionId) (bytes : List Nat) : Stmt :=
  .sequence (.ifThenElse (fixedGuard fits bytes.length) (returned negativeOne) .skip)
    (fixedStatements bytes.length 0 bytes)

abbrev CheckedFixed (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (fits : CheckedFits program) (modulePath : Names.ModulePath) (name : Surface.Name) (bytes : List Nat) :=
  Extraction.Source.CheckedInternal program modulePath name
    [(0, .slice i32), (1, i32), (2, i32)] i32 (fixedBody fits.source.function.id bytes)

def checkFixed? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (fits : CheckedFits program) (modulePath : Names.ModulePath) (name : Surface.Name) (bytes : List Nat) :
    Option (CheckedFixed program fits modulePath name bytes) :=
  Extraction.Source.checkInternal? program modulePath name
    [(0, .slice i32), (1, i32), (2, i32)] i32 (fixedBody fits.source.function.id bytes)

end Lanius.X86.Source

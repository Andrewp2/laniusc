import Lanius.X86.Source.Patch

namespace Lanius.X86.Source

open Lanius.Core Lanius.Extraction

def relativeConditional : Expr := .binary .equal (read 3) (number 15)

def relativeSize : Stmt :=
  .ifThenElse relativeConditional
    (.sequence (.expression (.assign .set (.local 6) (number 6))) .skip) .skip

def relativeGuard (fits : FunctionId) : Expr :=
  .binary .logicalOr (.binary .less (read 5) (number 0))
    (.unary .logicalNot (.call fits [read 1, read 2, read 6]))

def relativeOpcode : Expr := .assign .set (.index (.local 0) (read 2)) (read 3)

def relativeCondition : Stmt :=
  .ifThenElse relativeConditional
    (.sequence (.expression (.assign .set
      (.index (.local 0) (.binary .add (read 2) (number 1)))
      (.binary .add (number 128) (read 4)))) .skip) .skip

def relativeWrite (word : FunctionId) : Stmt :=
  .sequence (.expression relativeOpcode)
    (.sequence relativeCondition (returned (.call word
      [read 0, .binary .subtract (read 7) (number 4), .binary .subtract (read 5) (read 7)])))

def relativeAfterSize (fits word : FunctionId) : Stmt :=
  .sequence (.ifThenElse (relativeGuard fits) (returned negativeOne) .skip)
    (.letLocal 7 i32 (.binary .add (read 2) (read 6)) (relativeWrite word))

def relativeBody (fits word : FunctionId) : Stmt :=
  .letLocal 6 i32 (number 5) (.sequence relativeSize (relativeAfterSize fits word))

abbrev CheckedRelative (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (fits : CheckedFits program) (word : CheckedWord program) :=
  Extraction.Source.CheckedInternal program ["x86", "control"] "relative"
    [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32), (5, i32)] i32
    (relativeBody fits.source.function.id word.source.function.id)

def checkRelative? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (fits : CheckedFits program) (word : CheckedWord program) : Option (CheckedRelative program fits word) :=
  Extraction.Source.checkInternal? program ["x86", "control"] "relative"
    [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32), (5, i32)] i32
    (relativeBody fits.source.function.id word.source.function.id)

def directBody (relative : FunctionId) (opcode : Nat) : Stmt :=
  returned (.call relative [read 0, read 1, read 2, number opcode, number 0, read 3])

abbrev CheckedDirect (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {fits : CheckedFits program} {word : CheckedWord program}
    (relative : CheckedRelative program fits word) (name : Surface.Name) (opcode : Nat) :=
  Extraction.Source.CheckedInternal program ["x86", "control"] name
    [(0, .slice i32), (1, i32), (2, i32), (3, i32)] i32 (directBody relative.source.function.id opcode)

def checkDirect? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {fits : CheckedFits program} {word : CheckedWord program}
    (relative : CheckedRelative program fits word) (name : Surface.Name) (opcode : Nat) :
    Option (CheckedDirect program relative name opcode) :=
  Extraction.Source.checkInternal? program ["x86", "control"] name
    [(0, .slice i32), (1, i32), (2, i32), (3, i32)] i32 (directBody relative.source.function.id opcode)

def branchGuard : Expr :=
  .binary .logicalOr (.binary .less (read 3) (number 0)) (.binary .greater (read 3) (number 15))

def branchBody (relative : FunctionId) : Stmt :=
  .sequence (.ifThenElse branchGuard (returned negativeOne) .skip)
    (returned (.call relative [read 0, read 1, read 2, number 15, read 3, read 4]))

abbrev CheckedBranch (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {fits : CheckedFits program} {word : CheckedWord program}
    (relative : CheckedRelative program fits word) :=
  Extraction.Source.CheckedInternal program ["x86", "control"] "branch"
    [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32)] i32 (branchBody relative.source.function.id)

def checkBranch? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {fits : CheckedFits program} {word : CheckedWord program}
    (relative : CheckedRelative program fits word) : Option (CheckedBranch program relative) :=
  Extraction.Source.checkInternal? program ["x86", "control"] "branch"
    [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32)] i32 (branchBody relative.source.function.id)

end Lanius.X86.Source

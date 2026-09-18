import Lanius.X86.Source.Buffer

namespace Lanius.X86.Source

open Lanius.Core Lanius.Extraction

def negativeOne : Expr := .unary .negate (number 1)

def patchGuard (fits : FunctionId) : Expr :=
  .binary .logicalOr
    (.binary .logicalOr
      (.unary .logicalNot (.call fits [read 1, read 2, number 4]))
      (.binary .less (read 3) (number 0)))
    (.binary .greater (read 3) (read 1))

def patchBody (fits word : FunctionId) : Stmt :=
  .sequence (.ifThenElse (patchGuard fits) (returned negativeOne) .skip)
    (returned (.call word [read 0, read 2,
      .binary .subtract (read 3) (.binary .add (read 2) (number 4))]))

abbrev CheckedPatch (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (fits : CheckedFits program) (word : CheckedWord program) :=
  Extraction.Source.CheckedInternal program ["x86", "control"] "patch_relative"
    [(0, .slice i32), (1, i32), (2, i32), (3, i32)] i32
    (patchBody fits.source.function.id word.source.function.id)

def checkPatch? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (fits : CheckedFits program) (word : CheckedWord program) : Option (CheckedPatch program fits word) :=
  Extraction.Source.checkInternal? program ["x86", "control"] "patch_relative"
    [(0, .slice i32), (1, i32), (2, i32), (3, i32)] i32
    (patchBody fits.source.function.id word.source.function.id)

end Lanius.X86.Source

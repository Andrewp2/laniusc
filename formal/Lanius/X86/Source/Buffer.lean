import Lanius.Extraction.Source.Internal

namespace Lanius.X86.Source

open Lanius.Core Lanius.Extraction

abbrev i32 : Ty := .scalar (.signed .i32)
abbrev number (value : Nat) : Expr := .value (.signed .i32 value)
abbrev read (id : VarId) : Expr := .local id
def returned (value : Expr) : Stmt := .sequence (.returnValue (some value)) .skip

def fitsGuard : Expr :=
  .binary .logicalOr
    (.binary .logicalOr
      (.binary .logicalOr (.binary .less (read 0) (number 0))
        (.binary .less (read 1) (number 0)))
      (.binary .less (read 2) (number 0)))
    (.binary .greater (read 1) (read 0))

def fitsBody : Stmt :=
  .sequence (.ifThenElse fitsGuard (returned (.value (.boolean false))) .skip)
    (returned (.binary .lessEqual (read 2) (.binary .subtract (read 0) (read 1))))

abbrev CheckedFits (program : CoreSynthesis.Program.CheckedProgram artifacts) :=
  Extraction.Source.CheckedInternal program ["x86", "buffer"] "fits"
    [(0, i32), (1, i32), (2, i32)] (.scalar .bool) fitsBody

def checkFits? (program : CoreSynthesis.Program.CheckedProgram artifacts) : Option (CheckedFits program) :=
  Extraction.Source.checkInternal? program ["x86", "buffer"] "fits"
    [(0, i32), (1, i32), (2, i32)] (.scalar .bool) fitsBody

def wordIndex (lane : Nat) : Expr :=
  if lane = 0 then read 1 else .binary .add (read 1) (number lane)

def wordByte (lane : Nat) : Expr :=
  .binary .bitAnd
    (if lane = 0 then read 2 else .binary .shiftRight (read 2) (number (lane * 8)))
    (number 255)

def wordStore (lane : Nat) : Expr :=
  .assign .set (.index (.local 0) (wordIndex lane)) (wordByte lane)

def wordStatements (lane : Nat) : Nat → Stmt
  | 0 => returned (.binary .add (read 1) (number 4))
  | count + 1 => .sequence (.expression (wordStore lane)) (wordStatements (lane + 1) count)

def wordBody : Stmt := wordStatements 0 4

abbrev CheckedWord (program : CoreSynthesis.Program.CheckedProgram artifacts) :=
  Extraction.Source.CheckedInternal program ["x86", "buffer"] "store_word"
    [(0, .slice i32), (1, i32), (2, i32)] i32 wordBody

def checkWord? (program : CoreSynthesis.Program.CheckedProgram artifacts) : Option (CheckedWord program) :=
  Extraction.Source.checkInternal? program ["x86", "buffer"] "store_word"
    [(0, .slice i32), (1, i32), (2, i32)] i32 wordBody

end Lanius.X86.Source

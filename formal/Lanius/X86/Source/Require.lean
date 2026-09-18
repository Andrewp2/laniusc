import Lanius.X86.Source.Relative
import Lanius.X86.Source.Fixed

namespace Lanius.X86.Source.Require

open Lanius.Core Lanius.Extraction

def parameters : List (VarId × Ty) := [(0, .slice i32), (1, i32), (2, i32), (3, i32)]
def branchArguments : List Expr := [read 0, read 1, read 2, read 3, .binary .add (read 2) (number 8)]
def body (branch trap : FunctionId) : Stmt :=
  .letLocal 4 i32 (.call branch branchArguments) (returned (.call trap [read 0, read 1, read 4]))

abbrev Checked (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {fits : CheckedFits program} {word : CheckedWord program}
    {relative : CheckedRelative program fits word} (branch : CheckedBranch program relative)
    (trap : CheckedFixed program fits ["x86", "control"] "trap" [15, 11]) :=
  Extraction.Source.CheckedInternal program ["backend", "index"] "require" parameters i32
    (body branch.source.function.id trap.source.function.id)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    {fits : CheckedFits program} {word : CheckedWord program}
    {relative : CheckedRelative program fits word} (branch : CheckedBranch program relative)
    (trap : CheckedFixed program fits ["x86", "control"] "trap" [15, 11]) : Option (Checked program branch trap) :=
  Extraction.Source.checkInternal? program ["backend", "index"] "require" parameters i32
    (body branch.source.function.id trap.source.function.id)

end Lanius.X86.Source.Require

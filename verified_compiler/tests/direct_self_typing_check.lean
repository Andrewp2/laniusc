import Lanius.Typing.Check
import SelfCore

def main (_args : List String) : IO UInt32 := do
  let start ← IO.monoMsNow
  match Lanius.Typing.Check.checkProgramWellTyped extractedProgram with
  | none =>
      IO.eprintln "directly emitted self Core failed independent typing"
      return 1
  | some _ =>
      let elapsed := (← IO.monoMsNow) - start
      IO.println s!"directly emitted self Core is well typed ({elapsed} ms)"
      return 0

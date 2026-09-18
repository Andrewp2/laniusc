import Lanius.Extraction.Entry.Domain
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Domain

private def input (paths : List String) (files : List (String × List UInt8)) : Lanius.World.State := {
  arguments := "extractor" :: paths
  files := files.map fun (path, bytes) => ⟨Lanius.World.utf8Bytes path, bytes⟩ }

/-- Loading is independent of syntax validity. Exercise its actual external
limits, duplicate selection, UTF-8 byte lengths, and fresh-handle boundary. -/
def check : IO Unit := do
  let ordinary := input ["a"] [("a", [0])]
  let exactPath := String.ofList (List.replicate 512 'é')
  let longPath := exactPath ++ "a"
  let cases : List (String × Lanius.World.State × Bool) := [
    ("empty argv", {}, false),
    ("no sources", input [] [], false),
    ("empty path", input [""] [("", [])], false),
    ("missing file", input ["a"] [], false),
    ("empty source", input ["a"] [("a", [])], true),
    ("syntax unchecked", ordinary, true),
    ("repeated path", input ["a", "a"] [("a", [0])], true),
    ("missing second file", input ["a", "b"] [("a", [])], false),
    ("UTF-8 path limit", input [exactPath] [(exactPath, [])], true),
    ("UTF-8 path overflow", input [longPath] [(longPath, [])], false),
    ("file limit", input ["a"] [("a", List.replicate 65536 0)], true),
    ("file overflow", input ["a"] [("a", List.replicate 65537 0)], false),
    ("last representable handle", { ordinary with nextFileHandle := 2147483647 }, true),
    ("unrepresentable handle", { ordinary with nextFileHandle := 2147483648 }, false),
    ("second handle overflow", { input ["a", "a"] [("a", [])] with nextFileHandle := 2147483647 }, false),
    ("old handle preserved", { ordinary with fileHandles := [⟨2, [65], 7, true, false⟩] }, true),
    ("handle collision", { ordinary with fileHandles := [⟨3, [65], 7, true, false⟩] }, false)]
  for (name, world, expected) in cases do
    unless (Entry.checkLoadingDomain? world).isSome == expected do
      throw (IO.userError s!"loading-domain boundary differs: {name}")
  IO.println s!"{cases.length} loading-domain cases passed, including UTF-8 and handle boundaries"

#eval check

run_elab do
  for assumption in ← Lean.collectAxioms ``Entry.checkLoadingDomain? do
    unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
      throwError "Loading-domain checker adds unexpected axiom {assumption}"
  Lean.logInfo "Loading-domain evidence uses only standard Lean axioms; no execution or accepted-output premise."

end Lanius.Extraction.Tests.Domain

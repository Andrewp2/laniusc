import Lean

/-- Boundary smoke tests of the untrusted x86 bootstrap. Binary fixtures are
generated test data, not compiler source or extraction/proof generation. -/
def main (arguments : List String) : IO UInt32 := do
  let [executable, directory, validPrefix] := arguments
    | throw (IO.userError "expected x86 extractor, fixture directory, and valid prefix source")
  IO.FS.createDirAll directory
  for size in [65535, 65536, 65537, 131073] do
    let file := System.FilePath.mk directory / s!"{size}.bin"
    IO.FS.writeBinFile file (ByteArray.mk (Array.replicate size 255))
    for earlier in [#[], #[validPrefix], Array.replicate 3 validPrefix] do
      let run ← IO.Process.output { cmd := executable, args := earlier ++ #[file.toString, "must-not-run"] }
      let expected : UInt32 := if size ≤ 65536 then 28 else 6
      unless run.exitCode == expected && run.stdout.isEmpty do
        throw (IO.userError s!"native boundary mismatch: bytes={size}, prefix={earlier.size}, code={run.exitCode}, expected={expected}, stdout={run.stdout.length}")
      if size > 65536 && run.stderr != s!"{earlier.size + 1}\n2\n" then
        throw (IO.userError s!"native overflow diagnostic mismatch: {run.stderr}")
      IO.println s!"x86 boundary: bytes={size}, prefix={earlier.size}, code={run.exitCode}, stdout=0"
  pure 0

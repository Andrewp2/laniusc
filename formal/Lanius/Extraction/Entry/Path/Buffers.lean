import Lanius.Extraction.Entry.Path.Initialize

namespace Lanius.Extraction.Entry.Path
open Lanius.Core Lanius.Semantics

/-- Storage needed before inspecting any requested file. It does not assume
that the path is valid, that a file exists, or that a handle can be opened. -/
structure Buffers (read : Read.Stage) (unpack : Input.Unpack.Stage) (before : State) where
  packed : I32ArrayView
  output : I32ArrayView
  packedMember : packed ∈ before.i32ArrayViews
  outputMember : output ∈ before.i32ArrayViews
  pointerRead : before.local? read.pointer = some (.pointer packed.address)
  packedRead : before.local? unpack.locals.packed = some
    (.slice (.scalar (.signed .i32)) packed.root [] 0 packed.length)
  outputRead : before.local? unpack.locals.output = some
    (.slice (.scalar (.signed .i32)) output.root [] 0 output.length)
  packedLength : packed.length = 256
  outputLength : output.length = 1024
  distinct : packed.root ≠ output.root

end Lanius.Extraction.Entry.Path

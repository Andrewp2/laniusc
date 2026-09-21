import Lanius.X86.ImageCheck

namespace Lanius.X86.ImageCheckTests

open Lanius Lanius.X86
open Lanius.X86.ProgramCheck
open Lanius.X86.ImageCheck

private def literalBytes : List UInt8 :=
  LiteralReturn.bytes (.i32 (BitVec.ofNat 32 42))

private def expectedByte (length index : Nat) : UInt8 :=
  match (fields lanius length).find? (fun field => field.1 == index) with
  | some (_, value) => value
  | none => 0

private def elf : List UInt8 :=
  let length := 512 + literalBytes.length
  (List.range 512).map (expectedByte length) ++ literalBytes

private def image : Image :=
  { functions :=
      [{ address := lanius.base + BitVec.ofNat 64 lanius.codeOffset
         bytes := literalBytes }] }

#eval (checkHeader lanius elf).isSome -- true
#eval (check lanius elf image).isSome -- true

private def badMagic : List UInt8 := 0 :: elf.drop 1
#eval (check lanius badMagic image).isSome -- false

private def badSlice : Image :=
  { functions :=
      [{ address := lanius.base + BitVec.ofNat 64 lanius.codeOffset
         bytes := [195] }] }
#eval (check lanius elf badSlice).isSome -- false

private def badEntrypointLayout : Layout := { lanius with entryOffset := 257 }
#eval (check badEntrypointLayout elf image).isSome -- false

end Lanius.X86.ImageCheckTests

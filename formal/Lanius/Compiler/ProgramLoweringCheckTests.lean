import Lanius.Compiler.ProgramLoweringCheck

namespace Lanius.Compiler.ProgramLoweringCheckTests

open Lanius
open Lanius.Compiler.ProgramLoweringCheck

def address : Declarations.ItemAddress := { file := 0, index := 2 }
structure AddressRow where
  address : Declarations.ItemAddress

example : coveredBy [address] [{ address := address }] AddressRow.address = true := by
  decide

example : coveredBy [address] ([] : List AddressRow) AddressRow.address = false := by
  decide

example : supportedItem (.module { segments := [.mk "demo" []] }) = true := by
  decide

example : supportedItem (.typeAlias "Alias" false [] [] (.path [.mk "i32" []])) = true := by
  decide

example : supportedItem
    (.typeAlias "Generic" false [.type { name := "T", bounds := [] }] []
      (.path [.mk "T" []])) = false := by
  decide

end Lanius.Compiler.ProgramLoweringCheckTests

import Lanius.Extraction.CertificateEmitterPackingExecution

namespace Lanius.Extraction.CertificateEmitterPackingExecutionTests

open Lanius Lanius.Core Lanius.Extraction Lanius.Semantics
open Lanius.Extraction.OutputPacking
open Lanius.Extraction.CertificateEmitterPackingExecution
open Lanius.Extraction.CertificateEmitterFrame

example : pack ([] : List UInt8) = [] := by rfl

example (program : Program) (body : Stmt) (root : CellId) (caller : State)
    (bound : root < caller.nextCell)
    (trace : PackTrace program body root [] caller [] [] caller [] []) :
    ([] : List Value).take ((([] : List UInt8).length + 3) / 4) = pack [] ∧
      ([] : List (SourcePackStep program body root)).length = (([] : List UInt8).length + 3) / 4 ∧
      (([] : List (SourcePackStep program body root)) = [] ∧ caller = caller ∨
        WriteFrame caller caller root (.array [])) := by
  exact pack_in_place_complete (bytes := ([] : List UInt8)) trace bound

example (a b c : UInt8) :
    (pack [a, b, c]).length = ([a, b, c].length + 3) / 4 := by
  simp [pack]

example (a b c : UInt8) :
    pack ([a, b, c] ++ []) = pack [a, b, c] ++ pack [] := by
  exact pack_append_four_or_final _ _ (Or.inr rfl)

end Lanius.Extraction.CertificateEmitterPackingExecutionTests

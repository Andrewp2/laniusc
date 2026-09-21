import Lanius.X86.CertificateImageCheck

namespace Lanius.X86.CertificateImageCheckTests

open Lanius.Extraction
open Lanius.X86.CertificateImageCheck

private def nonOverlapping : List FunctionSpan :=
  [{ start := 4, length := 6 }, { start := 10, length := 3 }]

private def overlapping : List FunctionSpan :=
  [{ start := 4, length := 6 }, { start := 9, length := 3 }]

private def outOfRange : List FunctionSpan :=
  [{ start := 4, length := 7 }]

private def reversed : List FunctionSpan :=
  [{ start := 10, length := 3 }, { start := 4, length := 6 }]

example : spansOK 16 0 nonOverlapping = true := by decide
example : spansOK 16 0 overlapping = false := by decide
example : spansOK 10 0 outOfRange = false := by decide
example : spansOK 16 0 reversed = false := by decide

end Lanius.X86.CertificateImageCheckTests

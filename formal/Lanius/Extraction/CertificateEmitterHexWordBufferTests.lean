import Lanius.Extraction.CertificateEmitterHexWord

namespace Lanius.Extraction.CertificateEmitterHexWordBufferTests

open Lanius Lanius.Core Lanius.Extraction Lanius.Semantics
open Lanius.Extraction.CertificateEmitterHexWord
open Lanius.Extraction.CertificateEmitterOutputBuffer

example :
    (hexWordElements (List.replicate 8 (.signed .i32 0)) 0 0)[7]? =
      some (.signed .i32 48) := by
  have h := (hexWordElements_canonical (List.replicate 8 (.signed .i32 0)) 0 0
    (by simp)).2 7 (by decide)
  simpa [hexWordByte, CertificateRoundTrip.wordNat, hexByteLowValue,
    CertificateRoundTrip.hexDigit] using h

end Lanius.Extraction.CertificateEmitterHexWordBufferTests

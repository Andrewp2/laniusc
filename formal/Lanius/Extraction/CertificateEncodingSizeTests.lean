import Lanius.Extraction.CertificateEncodingSize

namespace Lanius.Extraction.CertificateEncodingSizeTests

open Lanius.Extraction
open Lanius.Extraction.CertificateEncodingSize
open Lanius.Extraction.CertificateRoundTrip

#check encodeCertificate_utf8_size

def emptyCertificate : Certificate :=
  { compact := "", transport := [], elf := [], functions := [] }

example (certificate : Certificate) :
    (encodeCertificate certificate).toUTF8.size =
      40 + certificate.compact.toUTF8.size +
        8 * certificate.transport.length +
        2 * certificate.elf.length +
        16 * certificate.functions.length := by
  exact encodeCertificate_utf8_size certificate

example : (encodeCertificate emptyCertificate).toUTF8.size = 40 := by
  simpa [emptyCertificate] using encodeCertificate_utf8_size emptyCertificate

end Lanius.Extraction.CertificateEncodingSizeTests

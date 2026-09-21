import Lanius.Extraction.CertificateRoundTrip

namespace Lanius.Extraction.CertificateEncodingSize

open Lanius.Extraction
open Lanius.Extraction.CertificateRoundTrip

private theorem join_map_utf8_size {α : Type} (values : List α)
    (render : α → String) (width : Nat)
    (render_size : ∀ value, (render value).toUTF8.size = width) :
    (join (values.map render)).toUTF8.size = width * values.length := by
  induction values with
  | nil => simp [join]
  | cons value values ih =>
      have hvalue : (render value).toByteArray.size = width := by
        simpa [String.toUTF8] using render_size value
      have htail : (join (values.map render)).toByteArray.size =
          width * values.length := by
        simpa [String.toUTF8] using ih
      simp only [List.map, join, String.toUTF8, String.toByteArray_append,
        ByteArray.size_append]
      rw [hvalue, htail]
      simp [Nat.mul_succ, Nat.add_comm]

private theorem hexWord_size (value : Int) :
    (hexWord value).toUTF8.size = 8 := by
  exact hexNat_size 8 (wordNat value)

private theorem hexFunction_size (span : FunctionSpan) :
    (hexFunction span).toUTF8.size = 16 := by
  simp only [hexFunction, String.toUTF8, String.toByteArray_append,
    ByteArray.size_append]
  have hstart : (hexNat 8 span.start).toByteArray.size = 8 := by
    simpa [String.toUTF8] using hexNat_size 8 span.start
  have hlength : (hexNat 8 span.length).toByteArray.size = 8 := by
    simpa [String.toUTF8] using hexNat_size 8 span.length
  rw [hstart, hlength]

theorem encodeCertificate_utf8_size (certificate : Certificate) :
    (encodeCertificate certificate).toUTF8.size =
      40 + certificate.compact.toUTF8.size +
        8 * certificate.transport.length +
        2 * certificate.elf.length +
        16 * certificate.functions.length := by
  have htransport := join_map_utf8_size certificate.transport hexWord 8 hexWord_size
  have hfunctions := join_map_utf8_size certificate.functions hexFunction 16
    hexFunction_size
  have htransportLength : (hexNat 8 certificate.transport.length).toUTF8.size = 8 :=
    hexNat_size 8 certificate.transport.length
  have helfLength : (hexNat 8 certificate.elf.length).toUTF8.size = 8 :=
    hexNat_size 8 certificate.elf.length
  have hfunctionsLength : (hexNat 8 certificate.functions.length).toUTF8.size = 8 :=
    hexNat_size 8 certificate.functions.length
  simp only [encodeCertificate, String.toUTF8, String.toByteArray_append,
    ByteArray.size_append]
  have htransport' : (join (certificate.transport.map hexWord)).toByteArray.size =
      8 * certificate.transport.length := by
    simpa [String.toUTF8] using htransport
  have helf' : (join (certificate.elf.map hexByte)).toByteArray.size =
      2 * certificate.elf.length := by
    simpa [String.toUTF8] using (join_hex_size certificate.elf)
  have hfunctions' : (join (certificate.functions.map hexFunction)).toByteArray.size =
      16 * certificate.functions.length := by
    simpa [String.toUTF8] using hfunctions
  have hcompactLength' : (hexNat 8 certificate.compact.toByteArray.size).toByteArray.size = 8 := by
    exact hexNat_size 8 certificate.compact.toByteArray.size
  have htransportLength' : (hexNat 8 certificate.transport.length).toByteArray.size = 8 := by
    simpa [String.toUTF8] using htransportLength
  have helfLength' : (hexNat 8 certificate.elf.length).toByteArray.size = 8 := by
    simpa [String.toUTF8] using helfLength
  have hfunctionsLength' : (hexNat 8 certificate.functions.length).toByteArray.size = 8 := by
    simpa [String.toUTF8] using hfunctionsLength
  have hversion : (hexNat 8 3).toByteArray.size = 8 := by
    simpa [String.toUTF8] using (hexNat_size 8 3)
  rw [hversion, hcompactLength', htransportLength', htransport',
    helfLength', helf', hfunctionsLength', hfunctions']
  omega

end Lanius.Extraction.CertificateEncodingSize

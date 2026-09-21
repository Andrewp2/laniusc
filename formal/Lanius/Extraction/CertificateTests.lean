import Lanius.Extraction.Certificate

namespace Lanius.Extraction.CertificateTests

open Lanius.Extraction

private def compactFixture : String :=
  "0000000100000001" ++
  "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

private def transportFixture : String :=
  "00000012" ++
  "0000000200000040000000070000000000000000000000010000000b0000000100000040000000070000000100000000000000050000000a0000000100000000000000010000002a"

private def certificateFixture : String :=
  "00000003" ++ "00000068" ++ compactFixture ++ transportFixture ++
  "00000000" ++ "00000000"

-- The envelope parser keeps the compact payload byte-exact and decodes signed
-- transport words independently of the frontend/backend acceptance stages.
#eval (decodeCertificate? certificateFixture).isSome
#eval (decodeCertificate? certificateFixture).map (·.compact) == some compactFixture
#eval (decodeCertificate? certificateFixture).map (·.transport)

end Lanius.Extraction.CertificateTests

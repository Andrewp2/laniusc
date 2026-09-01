import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerClaimsSpellingCache

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

def verifiedFrontendLexerSpellingClaimsChunk0 :=
  verifiedFrontendLexerClaimsQuoted.spellings.take 12
def verifiedFrontendLexerSpellingClaimsChunk1 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 12).take 12
def verifiedFrontendLexerSpellingClaimsChunk2 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 24).take 12
def verifiedFrontendLexerSpellingClaimsChunk3 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 36).take 12
def verifiedFrontendLexerSpellingClaimsChunk4 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 48).take 12
def verifiedFrontendLexerSpellingClaimsChunk5 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 60).take 12
def verifiedFrontendLexerSpellingClaimsChunk6 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 72).take 12
def verifiedFrontendLexerSpellingClaimsChunk7 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 84).take 12
def verifiedFrontendLexerSpellingClaimsChunk8 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 96).take 12
def verifiedFrontendLexerSpellingClaimsChunk9 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 108).take 12
def verifiedFrontendLexerSpellingClaimsChunk10 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 120).take 12
def verifiedFrontendLexerSpellingClaimsChunk11 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 132).take 12
def verifiedFrontendLexerSpellingClaimsChunk12 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 144).take 12
def verifiedFrontendLexerSpellingClaimsChunk13 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 156).take 12
def verifiedFrontendLexerSpellingClaimsChunk14 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 168).take 12
def verifiedFrontendLexerSpellingClaimsChunk15 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 180).take 12
def verifiedFrontendLexerSpellingClaimsChunk16 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 192).take 12
def verifiedFrontendLexerSpellingClaimsChunk17 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 204).take 12
def verifiedFrontendLexerSpellingClaimsChunk18 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 216).take 12
def verifiedFrontendLexerSpellingClaimsChunk19 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 228).take 12
def verifiedFrontendLexerSpellingClaimsChunk20 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 240).take 12
def verifiedFrontendLexerSpellingClaimsChunk21 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 252).take 12
def verifiedFrontendLexerSpellingClaimsChunk22 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 264).take 12
def verifiedFrontendLexerSpellingClaimsChunk23 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 276).take 12
def verifiedFrontendLexerSpellingClaimsChunk24 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 288).take 12
def verifiedFrontendLexerSpellingClaimsChunk25 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 300).take 12
def verifiedFrontendLexerSpellingClaimsChunk26 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 312).take 12
def verifiedFrontendLexerSpellingClaimsChunk27 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 324).take 12
def verifiedFrontendLexerSpellingClaimsChunk28 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 336).take 12
def verifiedFrontendLexerSpellingClaimsChunk29 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 348).take 12
def verifiedFrontendLexerSpellingClaimsChunk30 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 360).take 12
def verifiedFrontendLexerSpellingClaimsChunk31 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 372).take 12
def verifiedFrontendLexerSpellingClaimsChunk32 :=
  (verifiedFrontendLexerClaimsQuoted.spellings.drop 384).take 12
def verifiedFrontendLexerSpellingClaimsChunk33 :=
  verifiedFrontendLexerClaimsQuoted.spellings.drop 396

theorem verifiedFrontendLexer_spelling_claims_chunks_kernel :
    verifiedFrontendLexerClaimsQuoted.spellings =
      verifiedFrontendLexerSpellingClaimsChunk0 ++
      verifiedFrontendLexerSpellingClaimsChunk1 ++
      verifiedFrontendLexerSpellingClaimsChunk2 ++
      verifiedFrontendLexerSpellingClaimsChunk3 ++
      verifiedFrontendLexerSpellingClaimsChunk4 ++
      verifiedFrontendLexerSpellingClaimsChunk5 ++
      verifiedFrontendLexerSpellingClaimsChunk6 ++
      verifiedFrontendLexerSpellingClaimsChunk7 ++
      verifiedFrontendLexerSpellingClaimsChunk8 ++
      verifiedFrontendLexerSpellingClaimsChunk9 ++
      verifiedFrontendLexerSpellingClaimsChunk10 ++
      verifiedFrontendLexerSpellingClaimsChunk11 ++
      verifiedFrontendLexerSpellingClaimsChunk12 ++
      verifiedFrontendLexerSpellingClaimsChunk13 ++
      verifiedFrontendLexerSpellingClaimsChunk14 ++
      verifiedFrontendLexerSpellingClaimsChunk15 ++
      verifiedFrontendLexerSpellingClaimsChunk16 ++
      verifiedFrontendLexerSpellingClaimsChunk17 ++
      verifiedFrontendLexerSpellingClaimsChunk18 ++
      verifiedFrontendLexerSpellingClaimsChunk19 ++
      verifiedFrontendLexerSpellingClaimsChunk20 ++
      verifiedFrontendLexerSpellingClaimsChunk21 ++
      verifiedFrontendLexerSpellingClaimsChunk22 ++
      verifiedFrontendLexerSpellingClaimsChunk23 ++
      verifiedFrontendLexerSpellingClaimsChunk24 ++
      verifiedFrontendLexerSpellingClaimsChunk25 ++
      verifiedFrontendLexerSpellingClaimsChunk26 ++
      verifiedFrontendLexerSpellingClaimsChunk27 ++
      verifiedFrontendLexerSpellingClaimsChunk28 ++
      verifiedFrontendLexerSpellingClaimsChunk29 ++
      verifiedFrontendLexerSpellingClaimsChunk30 ++
      verifiedFrontendLexerSpellingClaimsChunk31 ++
      verifiedFrontendLexerSpellingClaimsChunk32 ++
      verifiedFrontendLexerSpellingClaimsChunk33 := by
  cbv

end Lanius.Extraction

import Lanius.Open.Cert.CertShallowSound.Red1
import Lanius.Open.Cert.CertCheckFacts.Proof
import Lanius.Open.Cert.CertMatchSound.Proof

theorem Lanius.Open.CertShallowSound.proof : Lanius.Open.CertShallowSound :=
  Lanius.Open.CertShallowSound.red1 Lanius.Open.CertCheckFacts.proof Lanius.Open.CertMatchSound.proof

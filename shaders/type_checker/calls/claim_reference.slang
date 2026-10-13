// A generic binding carries a checked reference. Scalar/native cache markers
// and the rejection marker (tag 4, slot 32) are not argument types.
public bool checked_claim_reference(uint tag, uint payload)
{
    return tag >= 1u && tag <= 3u && payload != 0xffffffffu &&
        (tag != 1u || payload != 0u);
}

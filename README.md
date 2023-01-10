# Vespass

## A New Kind Of Password Manager

I am unhappy with [the](https://twitter.com/dystopiabreaker/status/1606106769364684800?s=20) [state](https://www.reddit.com/r/privacy/comments/7l75d5/comment/husrjl5/?utm_source=share&utm_medium=web2x&context=3) [of](https://twitter.com/dystopiabreaker/status/1606449079420342272?s=20) commercial password managers. Vespass is an uncompromising password manager with stronger security guarantees and lower friction than anything else on the market. It works with iPhone, iPads and Macs that have a secure enclave (and in future, hardware authentication devices like Yubikey/Ledger).

Features:

- No master passwords
- Security of secrets at [rest](https://en.wikipedia.org/wiki/Data_at_rest) = breaking _two_ device's hardware secure enclave
- Security of secrets in [transit](https://en.wikipedia.org/wiki/Data_in_transit) = **max**(breaking iCloud end-to-end encryption, breaking _one_ device's secure enclave)
- Minimal dependencies and minimal crypto
- Fully open source
- Two-factor authentication by design (even if the provider doesn't support it)
- (In future) Support bluetooth or NFC instead of iCloud for secrets in transit
- (In future) Minimal [TOFU](https://keybase.io/blog/chat-apps-softer-than-tofu)


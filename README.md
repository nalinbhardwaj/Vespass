# Vespass

## A New Kind of Password Manager

I am unhappy with [the](https://twitter.com/matthew_d_green/status/1606037649625530368?s=20) [state](https://www.reddit.com/r/privacy/comments/7l75d5/comment/husrjl5/?utm_source=share&utm_medium=web2x&context=3) [of](https://twitter.com/dystopiabreaker/status/1606449079420342272?s=20) [commercial](https://dustri.org/b/the-quest-for-a-family-friendly-password-manager.html) [password](https://twitter.com/benjitaylor/status/1465813017560432643?s=20) [managers](https://rot256.dev/post/pass/) (every single word here is a problem). Vespass is an uncompromising password manager with stronger security guarantees and lower friction than anything else on the market. It works with iPhones, iPads and Macs that have a secure enclave (and in future, hardware authentication devices like Yubikey/Ledger and possibly some subset of Android/Linux devices).

Features:

- No master passwords
- Minimal dependencies and minimal crypto
- Fully open source
- Secure and recoverable in event of device loss
- Under 5000 lines of code to simplify auditing (Current: `1192`)[^1]
- (In future) Support Bluetooth or NFC instead of iCloud for secrets in transit
- (In future) Minimal [TOFU](https://keybase.io/blog/chat-apps-softer-than-tofu)

[^1]: Bitwarden, for comparison, has at least 500,000. I wonder what the distribution of bugs per line of code looks like. :)

Depending on your friction vs. security tradeoff appetite, you can choose either the low friction mode (with lower security) or high security mode (with higher friction). In both cases, your password is likely more secure than most other password managers in the market. More precisely, we measure security as:

High security mode:
- Security of secrets at [rest](https://en.wikipedia.org/wiki/Data_at_rest) = breaking _two_ device's hardware secure enclave
- Security of secrets in [transit](https://en.wikipedia.org/wiki/Data_in_transit) = breaking iCloud end-to-end encryption _and_ breaking one device's secure enclave
- Two-factor authentication by design (even if the provider doesn't support it)

Low friction mode:
- Security of secrets (in all cases) = breaking iCloud end-to-end encryption _and_ breaking one device's secure enclave

## How does it work?

Vespass works with a clever combination of [secret sharing](https://en.wikipedia.org/wiki/Secret_sharing) and encryption to [hardware secure enclave keys](https://support.apple.com/en-in/guide/security/sec59b0b31ff/web). With some secret sharing magic, we can force a secret (password) to be split into pieces. Each piece is then encrypted to a cryptographic key attached to the secure enclave, and stored by your devices separately[^2]. Then, when you are ready to sign in, your devices need to decrypt their individual pieces (requiring biometrics for decryption) and then collaborate with each other to re-derive the plaintext secret. After one-time use, Vespass deletes the plaintext versions from memory, so future use is just as secure.

[^2]: In low-friction mode, one of the secret shares is stored by iCloud servers (doubly encrypted under E2EE and secure enclave key cryptography)

## How secure are "Secure Enclaves"?

Most devices these days have [hardware secure enclaves](https://support.apple.com/en-in/guide/security/sec59b0b31ff/web) for handling secrets. These secure enclaves are the key to securing most of everything on your devices (such as with Apple's Touch ID/Face ID). Any attacks on the secure enclave are essentially a compromise of anything else on the device (and in practice, most attacks [assume at least a firmware level access](https://appleinsider.com/articles/20/08/03/security-enclave-vulnerability-seems-scary-but-wont-affect-most-iphone-users)). If the secure enclave can be broken, so can any secret in any other software/hardware (on the OS, RAM, etc.) on the device. Thus, building a password manager that inherits the security of the secure enclave is likely the lowest-security assumption method to build a password manager.

## How does secret-sharing work?

A secret is broken into $N$ parts (where $N$ = number of devices you use) and at least two of the pieces are required to reassemble the original secret. This means that to recreate, you essentially need to run a process much like Two-factor authentication: two of your devices need to authorise the reassembly of the secret. Additionally, this means that even if you lose one of your devices, it's useless by itself (even if someone is able to break into its secure enclave with physical access).

In low friction mode, one of the secret shares is stored in the cloud (under iCloud end-to-end encryption AND secure enclave encryption) and retrieved only when necessary, so you only require one device at hand to authenticate, and in case of device loss, you can simply retract that device's iCloud access to make it useless by itself.

### How does the secret-sharing math work?

General secret sharing is a bit more complex, but we only require a simple version for our specific use case: 2-of-$N$ secret sharing. Imagine a simple line: $f(x) = m \cdot x + c$. Let's say $f(0)$ is the value of the secret. Then, instead of storing the value of $f(0)$ directly, each device stores a different evaluation of $f$ instead: your laptop has $f(1)$, your phone has $f(2)$, etc. Now, to recover the secret, you need to recompute $f(0)$, which requires rediscovering the line $f(x)$. As you may recall from [high-school algebra](https://www3.nd.edu/~apilking/Precalculus/Lectures/Lecture%209%20lines.pdf), a line is only uniquely determined by **two** points on it, so it takes at least one other evaluation to discover $f(0)$.

## How ready is Vespass?

It's not.

If a [Vespa](https://web.archive.org/web/20010313020959/http://home.rol3.com/~u0341403/iss15/vespa.htm) is a "motorcycle of a rational complexity of organs and elements combined with a frame with mudguards and a casing covering the whole mechanical part", Vespass is just the organs and elements right now.

Help me build the remainder of this motorcycle. [Reach out.](https://twitter.com/nibnalin)

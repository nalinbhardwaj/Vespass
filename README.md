# Vespass

## A New Kind of Password Manager

<img alt="Vespass" src="https://user-images.githubusercontent.com/6984346/224432008-c25e2135-5108-4ff2-a9f7-66b04a2fb276.png">

I am unhappy with [the](https://twitter.com/matthew_d_green/status/1606037649625530368?s=20) [state](https://www.reddit.com/r/privacy/comments/7l75d5/comment/husrjl5/?utm_source=share&utm_medium=web2x&context=3) [of](https://twitter.com/dystopiabreaker/status/1606449079420342272?s=20) [commercial](https://dustri.org/b/the-quest-for-a-family-friendly-password-manager.html) [password](https://twitter.com/benjitaylor/status/1465813017560432643?s=20) [managers](https://rot256.dev/post/pass/) (every single word here links to a problem). Vespass is an uncompromising password manager with stronger security guarantees and lower friction than anything else on the market.

Features:

- No master passwords
- Minimal cryptography and minimal package dependencies (just one)
- Fully open source (GPL-3)
- Secure and recoverable in event of device loss
- Under 5000 lines of code (Current: `1198`)[^1]
- (In future) Support Bluetooth/NFC for communication
- (In future) Minimal [TOFU](https://keybase.io/blog/chat-apps-softer-than-tofu)

[^1]: This minimizes surface area for bugs and simplifies auditing. Bitwarden, for comparison, has at least 500,000. I wonder what the distribution of bugs per line of code looks like. :)

Vespass ships two modes: a low friction mode (with lower security) and a high security mode (with higher friction). **In either case, your passwords are likely more secure than most other password managers in the market.** More precisely, we measure cryptographic security as:

High security mode:
- Security of secrets at [rest](https://en.wikipedia.org/wiki/Data_at_rest) = breaking _two_ device's hardware secure enclave
- Security of secrets in [transit](https://en.wikipedia.org/wiki/Data_in_transit) = breaking iCloud end-to-end encryption _and_ breaking one device's secure enclave

Low friction mode:
- Security of secrets (both at rest and in transit) = breaking iCloud end-to-end encryption _and_ breaking one device's secure enclave

Notice that the high security mode is much like enabling two-factor authentication, so even if a website does not support 2FA out of the box, your password to it is stored with as much security as it could add.

Vespass uses secret sharing and end-to-end encryption to hardware-secure keys to enable these properties. It ships a macOS and iOS app that works on all Apple devices that have a secure enclave (and in future, hardware authentication devices like Yubikeys, some subset of Android/Linux/Windows devices and paper keys).

## How does it work?

Vespass uses a combination of [secret sharing](https://en.wikipedia.org/wiki/Secret_sharing) and encryption to [hardware secure enclave keys](https://support.apple.com/en-in/guide/security/sec59b0b31ff/web). With some secret sharing magic, we can force a secret (password) to be split into pieces. Each piece is then encrypted to a cryptographic key attached to the secure enclave and stored by your devices separately[^2]. When you are ready to reassemble the secret and sign in, your devices need to decrypt their individual pieces (requiring biometrics for decryption) and then collaborate with each other to re-derive the plaintext secret. After one-time use, Vespass deletes the plaintext versions from memory, so future use remains just as secure.

[^2]: In low-friction mode, one of the secret shares is stored by iCloud servers (doubly encrypted under E2EE and secure enclave key cryptography)

## How secure are "Secure Enclaves" in the real world?

Most devices these days have [hardware secure enclaves](https://support.apple.com/en-in/guide/security/sec59b0b31ff/web) for handling secrets. These secure enclaves are the key to securing most of everything on your devices (such as with Apple's Touch ID/Face ID). Any attacks on the secure enclave are essentially a compromise of anything else on the device (and in practice, most attacks [assume at least firmware access](https://appleinsider.com/articles/20/08/03/security-enclave-vulnerability-seems-scary-but-wont-affect-most-iphone-users)). If the secure enclave can be broken, so can any secret in any other software/hardware (on the OS, RAM, etc.) on the device. Thus, building a password manager that inherits the security of the secure enclave likely makes the most secure security assumptions possible.

## How does secret-sharing work?

A secret is broken into $N$ parts (where $N$ = number of devices you use) and at least two of the pieces are required to reassemble the original secret. This means that to recreate, you essentially need to run a process much like Two-factor authentication: two of your devices need to authorise the reassembly of the secret. Additionally, this means that even if you lose one of your devices, it is useless by itself (even if someone is able to break into its secure enclave with physical access).

In low friction mode, one of the secret shares is stored in the cloud (under iCloud end-to-end encryption AND secure enclave encryption) and retrieved only when necessary, so you only require one device at hand to authenticate, and in case of device loss, you can simply retract that device's iCloud access to make it useless by itself.

### How does the secret-sharing math work?

General secret sharing is a bit more complex, but we only require a simple version for our specific use case: 2-of- $N$ secret sharing. Imagine a simple line: $f(x) = m \cdot x + c$. Let's say $f(0)$ is the value of the secret. Then, instead of storing the value of $f(0)$ directly, each device stores a different evaluation of $f$ instead: your laptop has $f(1)$, your phone has $f(2)$, etc. Now, to recover the secret, you need to recompute $f(0)$, which requires rediscovering the line $f(x)$. As you may recall from [high-school algebra](https://www3.nd.edu/~apilking/Precalculus/Lectures/Lecture%209%20lines.pdf), a line is only uniquely determined by **two** points on it, so it takes at least one other evaluation to discover $f(0)$.

## How ready is Vespass?

It's not.

If a [Vespa](https://web.archive.org/web/20010313020959/http://home.rol3.com/~u0341403/iss15/vespa.htm) is a "motorcycle of a rational complexity of organs and elements combined with a frame with mudguards and a casing covering the whole mechanical part", Vespass is just the organs and elements right now.

Here's a WIP demo of the organs using the iOS and macOS app:


Another way to put it is that Vespass is currently closer to an [eprint](https://eprint-sanity.com) protocol specification (code is the best spec) than it is to a usable product.

Help me build the remainder of this motorcycle. [Reach out.](https://twitter.com/nibnalin)

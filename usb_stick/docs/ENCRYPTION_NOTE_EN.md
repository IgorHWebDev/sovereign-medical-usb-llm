# Encryption Note (English)

How to protect this stick — and why the usual software options were rejected.

## Recommendation: hardware-keypad encrypted USB drive

Deploy this package on a **hardware-encrypted drive with a physical PIN keypad**,
for example:

- **Kingston IronKey Vault Privacy 80ES** (FIPS 197, XTS-AES 256, touchscreen PIN)
- **Apricorn Aegis Secure Key / Aegis Padlock** series (FIPS 140-2/140-3 validated,
  onboard keypad)

Why this class of device fits hospital constraints:

- Encryption/decryption happens **inside the drive's own controller**. The host PC
  sees a normal USB mass-storage device only *after* the correct PIN is entered on
  the drive itself.
- **No software, no driver, no admin rights** are needed on the host PC — this is
  the only encryption approach compatible with our "no installation, no admin"
  deployment rule.
- OS-independent: the same drive unlocks identically on Windows and macOS.
- Brute-force lockout / crypto-erase after repeated wrong PINs protects data if
  the stick is lost.

## Rejected alternatives (and why)

| Option | Verdict | Reason |
| --- | --- | --- |
| **VeraCrypt** (software container/volume) | **Rejected** | Mounting a VeraCrypt volume requires the VeraCrypt kernel driver. Installing or loading that driver **requires administrator rights** on the host PC — even "portable mode" needs admin to load the driver. Hospital PCs give us neither. |
| **BitLocker To Go** | **Rejected** | Windows-only. There is **no macOS support** for reading or unlocking BitLocker To Go media, and this package must run on both Windows and macOS hosts. Also depends on host-side Windows edition/policy. |
| Plain (unencrypted) USB stick | **Rejected** for any stick that ever carries patient-derived text | No protection at all if lost. Acceptable only for demo sticks containing zero clinical data. |

## Filesystem: why exFAT

The data partition of the (hardware-encrypted) drive should be formatted **exFAT**:

- Readable **and writable** on both Windows 10/11 and macOS with no extra drivers.
- Supports files **larger than 4 GB** (the GGUF model files are ~1.9 GB each today,
  and future models may exceed FAT32's 4 GB limit).
- Avoids NTFS, which macOS mounts read-only, breaking audit-log writes.

## Custody register (mandatory)

Every stick must be tracked on a **drive custody register**: who holds it, when it
was signed out and back in, and for what purpose. Loss or suspected loss must be
reported the same day. Use the bundled template:
[CUSTODY_REGISTER_TEMPLATE.md](CUSTODY_REGISTER_TEMPLATE.md).

The stick also keeps a tamper-evident, hash-chained usage log in its `audit/`
folder; the custody register covers the *physical* chain of custody that the
digital log cannot.

Japanese version: [ENCRYPTION_NOTE_JA.md](ENCRYPTION_NOTE_JA.md)

# Local self-signed certificate and a code-signing pin on XPC

`make cert` creates a trusted self-signed code-signing identity in the user's keychain; `make app` and `make sign` sign with it. The root daemon accepts XPC callers only when they are signed with that certificate, so no other local process can read history or send Quit or Force Quit through it. A Developer ID would allow distribution but needs a paid account; this is a personal tool. Rebuilding with another certificate breaks the connection to an installed daemon until `make install` runs again. Spec §7.

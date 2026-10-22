# Local self-signed certificate and a code-signing pin on XPC

`make cert` creates a trusted self-signed code-signing identity in the user's keychain; `make app` and `make sign` sign with it. The root daemon accepts XPC callers only when they are signed with that certificate, so no other local process can read history or send Quit or Force Quit through it. A Developer ID would allow distribution but needs a paid account; this is a personal tool. Rebuilding with another certificate breaks the connection to an installed daemon until `make install` runs again. Spec §7.

`codesign` has standing access to the key so builds and installs run unattended (D52, replacing D49). Accepted risk: any process of the user can sign as the app and pass the pin; the pin keeps out other users and unsigned code.

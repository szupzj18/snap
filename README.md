# Snapkit

An open-source screenshot tool for macOS, in the spirit of CleanShot X.

> Status: early development (MVP in progress).

## Requirements

- macOS 14 Sonoma or later
- Xcode 15 or later (Swift 5.9+) to build

## Building

```sh
make app      # builds build/Snapkit.app
make run      # builds, then (re)launches the app
make test     # runs unit tests
CONFIG=release make app
```

Snapkit is a plain Swift package; `open Package.swift` works for editing and running tests in Xcode.
Launch the app through `make run` rather than Xcode's Run button: only the bundled `.app`
gets its own Screen Recording permission.

### Code signing

macOS remembers the Screen Recording permission per code signature. With the default ad-hoc
signature you have to grant it again after every rebuild. To avoid that, sign with a stable
identity by creating a `local.mk` (gitignored):

```make
SIGN_IDENTITY = Apple Development: Your Name (TEAMID)
```

`security find-identity -v -p codesigning` lists the identities you have.

## License

MIT, see [LICENSE](LICENSE).

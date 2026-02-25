# FerrisPad Signing Tool

A tool for signing FerrisPad plugins and release binaries with ed25519 signatures.

## Building

```bash
cargo build --release
```

## Usage

### Generate a new keypair (first time only)

```bash
./target/release/plugin-signer keygen
```

This creates:
- `~/.config/ferrispad/signing/plugin_signing_key.bin` - Private key (keep secure!)
- `~/.config/ferrispad/signing/plugin_signing_key.pub.bin` - Public key

### Sign a plugin

```bash
cd /path/to/ferrispad-plugins
./tools/signer/target/release/plugin-signer sign python-lint
```

This outputs:
- Checksums for `init.lua` and `plugin.toml`
- Base64-encoded signature
- JSON fragment to paste into `plugins.json`

### Show the public key

```bash
./target/release/plugin-signer show-key
```

Outputs the public key in Rust array format for embedding in FerrisPad's `plugin_verify.rs`.

### Verify a plugin (testing)

```bash
./target/release/plugin-signer verify python-lint "BASE64_SIGNATURE"
```

## How it works

1. Computes SHA-256 checksums of `init.lua` and `plugin.toml`
2. Builds a message: `{path}:{version}:{init_checksum}:{toml_checksum}`
3. Signs the message with ed25519
4. The signature is verified by FerrisPad during plugin installation

---

## Release Binary Signing

### Sign a release binary

```bash
./target/release/plugin-signer sign-release ./FerrisPad 0.9.1 linux-amd64
```

Platform identifiers:
- `linux-amd64` - Linux x86_64
- `macos-universal` - macOS Universal (Intel + Apple Silicon)
- `windows-x64.exe` - Windows x64

This:
1. Computes SHA-256 of the binary
2. Signs the message: `{version}:{platform}:{sha256}`
3. Writes signature to `{binary}.sig`

### Verify a release binary

```bash
./target/release/plugin-signer verify-release ./FerrisPad 0.9.1 linux-amd64 "BASE64_SIGNATURE"
```

### Release workflow

When creating a new release:

1. Build binaries for all platforms
2. Sign each binary:
   ```bash
   plugin-signer sign-release FerrisPad-linux-amd64 0.9.1 linux-amd64
   plugin-signer sign-release FerrisPad-macos-universal 0.9.1 macos-universal
   plugin-signer sign-release FerrisPad-windows-x64.exe 0.9.1 windows-x64.exe
   ```
3. Upload both the binaries AND the `.sig` files to the GitHub release
4. FerrisPad's updater will automatically download and verify the signature

---

## Security

- The private key is stored with 600 permissions (owner read/write only)
- Keep the private key secure and backed up
- The public key is embedded in FerrisPad at compile time
- Plugin signatures are verified before installation
- Release binary signatures are verified before update installation

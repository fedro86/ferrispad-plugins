# FerrisPad Plugin Signer

A tool for signing FerrisPad plugins with ed25519 signatures.

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

## Security

- The private key is stored with 600 permissions (owner read/write only)
- Keep the private key secure and backed up
- The public key is embedded in FerrisPad at compile time
- Plugin signatures are verified before installation

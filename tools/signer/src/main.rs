//! FerrisPad Signing Tool
//!
//! Usage:
//!   plugin-signer keygen                    - Generate new keypair
//!   plugin-signer sign <plugin_dir>         - Sign a plugin
//!   plugin-signer verify <plugin_dir>       - Verify a plugin (for testing)
//!   plugin-signer sign-release <binary> <version> <platform> - Sign a release binary

use base64::Engine;
use clap::{Parser, Subcommand};
use ed25519_dalek::{SigningKey, Signer, VerifyingKey, Verifier, Signature};
use sha2::{Sha256, Digest};
use std::fs;
use std::path::{Path, PathBuf};

const KEY_DIR: &str = ".config/ferrispad/signing";
const PRIVATE_KEY_FILE: &str = "plugin_signing_key.bin";
const PUBLIC_KEY_FILE: &str = "plugin_signing_key.pub.bin";

#[derive(Parser)]
#[command(name = "plugin-signer")]
#[command(about = "FerrisPad plugin signing tool", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Generate a new ed25519 keypair
    Keygen,
    /// Sign a plugin directory
    Sign {
        /// Path to plugin directory
        plugin_dir: PathBuf,
    },
    /// Verify a plugin's signature (for testing)
    Verify {
        /// Path to plugin directory
        plugin_dir: PathBuf,
        /// Base64-encoded signature
        signature: String,
    },
    /// Show the public key in Rust array format
    ShowKey,
    /// Sign a release binary (for FerrisPad updates)
    SignRelease {
        /// Path to the binary file
        binary: PathBuf,
        /// Version string (e.g., "0.9.1")
        version: String,
        /// Platform identifier (e.g., "linux-amd64", "macos-universal", "windows-x64.exe")
        platform: String,
    },
    /// Verify a release binary signature
    VerifyRelease {
        /// Path to the binary file
        binary: PathBuf,
        /// Version string
        version: String,
        /// Platform identifier
        platform: String,
        /// Base64-encoded signature
        signature: String,
    },
}

fn get_key_dir() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME not set");
    PathBuf::from(home).join(KEY_DIR)
}

fn compute_checksum(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    let result = hasher.finalize();
    format!("sha256:{}", hex::encode(result))
}

fn keygen() -> Result<(), Box<dyn std::error::Error>> {
    let key_dir = get_key_dir();
    fs::create_dir_all(&key_dir)?;

    let private_key_path = key_dir.join(PRIVATE_KEY_FILE);
    let public_key_path = key_dir.join(PUBLIC_KEY_FILE);

    if private_key_path.exists() {
        eprintln!("Warning: Key already exists at {:?}", private_key_path);
        eprintln!("Delete it manually if you want to generate a new one.");
        return Ok(());
    }

    // Generate keypair
    let mut csprng = rand::rngs::OsRng;
    let signing_key = SigningKey::generate(&mut csprng);
    let verifying_key = signing_key.verifying_key();

    // Save keys
    fs::write(&private_key_path, signing_key.to_bytes())?;
    fs::write(&public_key_path, verifying_key.to_bytes())?;

    // Set permissions on private key
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&private_key_path, fs::Permissions::from_mode(0o600))?;
    }

    println!("Generated new keypair:");
    println!("  Private key: {:?}", private_key_path);
    println!("  Public key:  {:?}", public_key_path);
    println!();
    println!("Public key bytes (for plugin_verify.rs):");
    print_key_as_rust_array(&verifying_key.to_bytes());

    Ok(())
}

fn print_key_as_rust_array(bytes: &[u8; 32]) {
    println!("const PLUGIN_PUBLIC_KEY: [u8; 32] = [");
    for (i, chunk) in bytes.chunks(8).enumerate() {
        print!("    ");
        for b in chunk {
            print!("0x{:02x}, ", b);
        }
        if i < 3 {
            println!();
        }
    }
    println!("\n];");
}

fn load_signing_key() -> Result<SigningKey, Box<dyn std::error::Error>> {
    let key_path = get_key_dir().join(PRIVATE_KEY_FILE);
    let bytes = fs::read(&key_path)
        .map_err(|_| format!("Could not read private key from {:?}. Run 'plugin-signer keygen' first.", key_path))?;

    let key_bytes: [u8; 32] = bytes.try_into()
        .map_err(|_| "Invalid key file size")?;

    Ok(SigningKey::from_bytes(&key_bytes))
}

fn load_verifying_key() -> Result<VerifyingKey, Box<dyn std::error::Error>> {
    let key_path = get_key_dir().join(PUBLIC_KEY_FILE);
    let bytes = fs::read(&key_path)
        .map_err(|_| format!("Could not read public key from {:?}", key_path))?;

    let key_bytes: [u8; 32] = bytes.try_into()
        .map_err(|_| "Invalid key file size")?;

    Ok(VerifyingKey::from_bytes(&key_bytes)?)
}

fn sign_plugin(plugin_dir: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let init_lua = plugin_dir.join("init.lua");
    let plugin_toml = plugin_dir.join("plugin.toml");

    if !init_lua.exists() {
        return Err(format!("init.lua not found in {:?}", plugin_dir).into());
    }
    if !plugin_toml.exists() {
        return Err(format!("plugin.toml not found in {:?}", plugin_dir).into());
    }

    // Read files
    let init_content = fs::read(&init_lua)?;
    let toml_content = fs::read_to_string(&plugin_toml)?;

    // Extract version from plugin.toml
    let version = toml_content.lines()
        .find(|line| line.starts_with("version = "))
        .and_then(|line| line.strip_prefix("version = "))
        .map(|v| v.trim_matches('"'))
        .ok_or("Could not find version in plugin.toml")?;

    // Compute checksums
    let init_checksum = compute_checksum(&init_content);
    let toml_checksum = compute_checksum(toml_content.as_bytes());

    // Build plugin path (directory name with trailing slash)
    let plugin_name = plugin_dir.file_name()
        .ok_or("Invalid plugin directory")?
        .to_string_lossy();
    let plugin_path = format!("{}/", plugin_name);

    // Build message to sign (same format as FerrisPad verification)
    let message = format!("{}:{}:{}:{}", plugin_path, version, init_checksum, toml_checksum);

    // Sign
    let signing_key = load_signing_key()?;
    let signature = signing_key.sign(message.as_bytes());
    let signature_b64 = base64::engine::general_purpose::STANDARD.encode(signature.to_bytes());

    println!("Plugin: {}", plugin_name);
    println!("Version: {}", version);
    println!();
    println!("Checksums:");
    println!("  init.lua:    {}", init_checksum);
    println!("  plugin.toml: {}", toml_checksum);
    println!();
    println!("Message signed: {}", message);
    println!("Signature: {}", signature_b64);
    println!();
    println!("JSON fragment for plugins.json:");
    println!("----------------------------------------");
    println!(r#"    "checksums": {{"#);
    println!(r#"      "init.lua": "{}","#, init_checksum);
    println!(r#"      "plugin.toml": "{}""#, toml_checksum);
    println!(r#"    }},"#);
    println!(r#"    "signature": "{}""#, signature_b64);
    println!("----------------------------------------");

    Ok(())
}

fn verify_plugin(plugin_dir: &Path, signature_b64: &str) -> Result<(), Box<dyn std::error::Error>> {
    let init_lua = plugin_dir.join("init.lua");
    let plugin_toml = plugin_dir.join("plugin.toml");

    let init_content = fs::read(&init_lua)?;
    let toml_content = fs::read_to_string(&plugin_toml)?;

    let version = toml_content.lines()
        .find(|line| line.starts_with("version = "))
        .and_then(|line| line.strip_prefix("version = "))
        .map(|v| v.trim_matches('"'))
        .ok_or("Could not find version in plugin.toml")?;

    let init_checksum = compute_checksum(&init_content);
    let toml_checksum = compute_checksum(toml_content.as_bytes());

    let plugin_name = plugin_dir.file_name()
        .ok_or("Invalid plugin directory")?
        .to_string_lossy();
    let plugin_path = format!("{}/", plugin_name);

    let message = format!("{}:{}:{}:{}", plugin_path, version, init_checksum, toml_checksum);

    let verifying_key = load_verifying_key()?;
    let signature_bytes = base64::engine::general_purpose::STANDARD.decode(signature_b64)?;
    let signature = Signature::from_slice(&signature_bytes)?;

    match verifying_key.verify(message.as_bytes(), &signature) {
        Ok(()) => {
            println!("Verification: PASSED");
            println!("Plugin {} v{} is authentic.", plugin_name, version);
        }
        Err(e) => {
            println!("Verification: FAILED");
            println!("Error: {}", e);
        }
    }

    Ok(())
}

fn show_key() -> Result<(), Box<dyn std::error::Error>> {
    let verifying_key = load_verifying_key()?;
    println!("Public key for plugin_verify.rs:");
    println!();
    print_key_as_rust_array(&verifying_key.to_bytes());
    Ok(())
}

/// Compute SHA-256 checksum without the "sha256:" prefix (for release binaries)
fn compute_checksum_hex(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    let result = hasher.finalize();
    hex::encode(result)
}

/// Sign a release binary
///
/// The signature is over: "{version}:{platform}:{sha256_hex}"
/// This format matches what FerrisPad's updater expects.
fn sign_release(binary_path: &Path, version: &str, platform: &str) -> Result<(), Box<dyn std::error::Error>> {
    if !binary_path.exists() {
        return Err(format!("Binary not found: {:?}", binary_path).into());
    }

    // Read binary
    let binary_data = fs::read(binary_path)?;
    let checksum = compute_checksum_hex(&binary_data);

    // Build message to sign (same format as FerrisPad updater)
    let message = format!("{}:{}:{}", version, platform, checksum);

    // Sign
    let signing_key = load_signing_key()?;
    let signature = signing_key.sign(message.as_bytes());
    let signature_b64 = base64::engine::general_purpose::STANDARD.encode(signature.to_bytes());

    println!("Binary: {:?}", binary_path);
    println!("Size: {} bytes", binary_data.len());
    println!("Version: {}", version);
    println!("Platform: {}", platform);
    println!();
    println!("SHA-256: {}", checksum);
    println!();
    println!("Message signed: {}", message);
    println!("Signature: {}", signature_b64);
    println!();

    // Write .sig file next to the binary
    let sig_path = binary_path.with_extension(
        binary_path
            .extension()
            .map(|e| format!("{}.sig", e.to_string_lossy()))
            .unwrap_or_else(|| "sig".to_string())
    );
    fs::write(&sig_path, &signature_b64)?;
    println!("Signature written to: {:?}", sig_path);

    Ok(())
}

/// Verify a release binary signature
fn verify_release(
    binary_path: &Path,
    version: &str,
    platform: &str,
    signature_b64: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let binary_data = fs::read(binary_path)?;
    let checksum = compute_checksum_hex(&binary_data);

    let message = format!("{}:{}:{}", version, platform, checksum);

    let verifying_key = load_verifying_key()?;
    let signature_bytes = base64::engine::general_purpose::STANDARD.decode(signature_b64)?;
    let signature = Signature::from_slice(&signature_bytes)?;

    match verifying_key.verify(message.as_bytes(), &signature) {
        Ok(()) => {
            println!("Verification: PASSED");
            println!("Binary {} v{} ({}) is authentic.",
                binary_path.file_name().unwrap().to_string_lossy(),
                version,
                platform
            );
        }
        Err(e) => {
            println!("Verification: FAILED");
            println!("Error: {}", e);
        }
    }

    Ok(())
}

fn main() {
    let cli = Cli::parse();

    let result = match cli.command {
        Commands::Keygen => keygen(),
        Commands::Sign { plugin_dir } => sign_plugin(&plugin_dir),
        Commands::Verify { plugin_dir, signature } => verify_plugin(&plugin_dir, &signature),
        Commands::ShowKey => show_key(),
        Commands::SignRelease { binary, version, platform } => {
            sign_release(&binary, &version, &platform)
        }
        Commands::VerifyRelease { binary, version, platform, signature } => {
            verify_release(&binary, &version, &platform, &signature)
        }
    };

    if let Err(e) = result {
        eprintln!("Error: {}", e);
        std::process::exit(1);
    }
}

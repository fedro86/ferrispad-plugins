//! FerrisPad Signing Tool
//!
//! Usage:
//!   plugin-signer keygen                    - Generate new keypair
//!   plugin-signer sign <plugin_dir>         - Sign a plugin
//!   plugin-signer verify <plugin_dir>       - Verify a plugin (for testing)
//!   plugin-signer update <plugin_dir>       - Sign + update plugins.json
//!   plugin-signer update-all                - Sign all plugins + update plugins.json
//!   plugin-signer sign-release <binary> <version> <platform> - Sign a release binary

use base64::Engine;
use clap::{Parser, Subcommand};
use ed25519_dalek::{SigningKey, Signer, VerifyingKey, Verifier, Signature};
use sha2::{Sha256, Digest};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

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
    /// Sign a plugin and update plugins.json
    Update {
        /// Path to plugin directory
        plugin_dir: PathBuf,
        /// Path to plugins.json registry
        #[arg(long, default_value = "plugins.json")]
        registry: PathBuf,
    },
    /// Sign all plugins and update plugins.json
    UpdateAll {
        /// Path to plugins.json registry
        #[arg(long, default_value = "plugins.json")]
        registry: PathBuf,
    },
}

fn get_key_dir() -> PathBuf {
    if let Ok(path) = std::env::var("SIGNING_KEY_PATH") {
        return PathBuf::from(path);
    }
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

/// Extract a string value from a TOML file's content by key.
/// Expects lines like: `key = "value"`
fn extract_toml_string(content: &str, key: &str) -> Option<String> {
    let prefix = format!("{} = ", key);
    content.lines()
        .find(|line| line.starts_with(&prefix))
        .and_then(|line| line.strip_prefix(&prefix))
        .map(|v| v.trim_matches('"').to_string())
}

/// Result of computing a plugin signature.
struct PluginSignResult {
    plugin_name: String,
    version: String,
    #[allow(dead_code)] // kept for future use; registry descriptions are hand-crafted
    description: String,
    init_checksum: String,
    toml_checksum: String,
    signature_b64: String,
}

/// Core signing logic: compute checksums and sign a plugin directory.
fn compute_plugin_signature(plugin_dir: &Path) -> Result<PluginSignResult, Box<dyn std::error::Error>> {
    let init_lua = plugin_dir.join("init.lua");
    let plugin_toml = plugin_dir.join("plugin.toml");

    if !init_lua.exists() {
        return Err(format!("init.lua not found in {:?}", plugin_dir).into());
    }
    if !plugin_toml.exists() {
        return Err(format!("plugin.toml not found in {:?}", plugin_dir).into());
    }

    let init_content = fs::read(&init_lua)?;
    let toml_content = fs::read_to_string(&plugin_toml)?;

    let version = extract_toml_string(&toml_content, "version")
        .ok_or("Could not find version in plugin.toml")?;
    let description = extract_toml_string(&toml_content, "description")
        .unwrap_or_default();

    let init_checksum = compute_checksum(&init_content);
    let toml_checksum = compute_checksum(toml_content.as_bytes());

    let plugin_name = plugin_dir.file_name()
        .ok_or("Invalid plugin directory")?
        .to_string_lossy()
        .to_string();
    let plugin_path = format!("{}/", plugin_name);

    let message = format!("{}:{}:{}:{}", plugin_path, version, init_checksum, toml_checksum);

    let signing_key = load_signing_key()?;
    let signature = signing_key.sign(message.as_bytes());
    let signature_b64 = base64::engine::general_purpose::STANDARD.encode(signature.to_bytes());

    Ok(PluginSignResult {
        plugin_name,
        version,
        description,
        init_checksum,
        toml_checksum,
        signature_b64,
    })
}

fn sign_plugin(plugin_dir: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let result = compute_plugin_signature(plugin_dir)?;

    println!("Plugin: {}", result.plugin_name);
    println!("Version: {}", result.version);
    println!();
    println!("Checksums:");
    println!("  init.lua:    {}", result.init_checksum);
    println!("  plugin.toml: {}", result.toml_checksum);
    println!();
    println!("Message signed: {}/:{}:{}:{}", result.plugin_name, result.version, result.init_checksum, result.toml_checksum);
    println!("Signature: {}", result.signature_b64);
    println!();
    println!("JSON fragment for plugins.json:");
    println!("----------------------------------------");
    println!(r#"    "checksums": {{"#);
    println!(r#"      "init.lua": "{}","#, result.init_checksum);
    println!(r#"      "plugin.toml": "{}""#, result.toml_checksum);
    println!(r#"    }},"#);
    println!(r#"    "signature": "{}""#, result.signature_b64);
    println!("----------------------------------------");

    Ok(())
}

fn verify_plugin(plugin_dir: &Path, signature_b64: &str) -> Result<(), Box<dyn std::error::Error>> {
    let init_lua = plugin_dir.join("init.lua");
    let plugin_toml = plugin_dir.join("plugin.toml");

    let init_content = fs::read(&init_lua)?;
    let toml_content = fs::read_to_string(&plugin_toml)?;

    let version = extract_toml_string(&toml_content, "version")
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

/// Get today's date as YYYY-MM-DD without chrono.
/// Uses a civil date conversion from Unix timestamp.
fn today_iso() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();

    // Civil date from days since epoch (algorithm from Howard Hinnant)
    let days = (secs / 86400) as i64;
    let z = days + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = (z - era * 146097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = (yoe as i64) + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };

    format!("{:04}-{:02}-{:02}", y, m, d)
}

/// Sign a single plugin and update its entry in plugins.json.
fn update_plugin(
    plugin_dir: &Path,
    registry: &mut serde_json::Value,
) -> Result<(), Box<dyn std::error::Error>> {
    let result = compute_plugin_signature(plugin_dir)?;

    let plugins = registry
        .get_mut("plugins")
        .and_then(|v| v.as_array_mut())
        .ok_or("plugins.json missing 'plugins' array")?;

    let entry = plugins.iter_mut()
        .find(|p| p.get("name").and_then(|n| n.as_str()) == Some(&result.plugin_name))
        .ok_or_else(|| format!(
            "Plugin '{}' not found in plugins.json. Add a scaffold entry first (author, license, tags, etc.).",
            result.plugin_name
        ))?;

    // Update version, checksums, signature
    entry["version"] = serde_json::json!(result.version);
    entry["checksums"] = serde_json::json!({
        "init.lua": result.init_checksum,
        "plugin.toml": result.toml_checksum,
    });
    entry["signature"] = serde_json::json!(result.signature_b64);

    println!("  {} v{} — signed", result.plugin_name, result.version);

    Ok(())
}

/// Update a single plugin and write plugins.json.
fn update_command(plugin_dir: &Path, registry_path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let content = fs::read_to_string(registry_path)
        .map_err(|_| format!("Could not read {:?}", registry_path))?;
    let mut registry: serde_json::Value = serde_json::from_str(&content)
        .map_err(|e| format!("Invalid JSON in {:?}: {}", registry_path, e))?;

    update_plugin(plugin_dir, &mut registry)?;

    // Update top-level date
    registry["updated"] = serde_json::json!(today_iso());

    let output = serde_json::to_string_pretty(&registry)? + "\n";
    fs::write(registry_path, output)?;

    println!("Updated {:?}", registry_path);
    Ok(())
}

/// Discover all plugin subdirectories and update plugins.json once.
fn update_all_command(registry_path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let content = fs::read_to_string(registry_path)
        .map_err(|_| format!("Could not read {:?}", registry_path))?;
    let mut registry: serde_json::Value = serde_json::from_str(&content)
        .map_err(|e| format!("Invalid JSON in {:?}: {}", registry_path, e))?;

    // Find all subdirectories containing plugin.toml
    let base = match registry_path.parent() {
        Some(p) if p.as_os_str().is_empty() => Path::new("."),
        Some(p) => p,
        None => Path::new("."),
    };
    let mut found = 0;

    let mut entries: Vec<_> = fs::read_dir(base)?
        .filter_map(|e| e.ok())
        .filter(|e| e.path().join("plugin.toml").exists())
        .collect();
    entries.sort_by_key(|e| e.file_name());

    for entry in entries {
        let plugin_dir = entry.path();
        match update_plugin(&plugin_dir, &mut registry) {
            Ok(()) => found += 1,
            Err(e) => eprintln!("  Warning: skipping {:?}: {}", plugin_dir, e),
        }
    }

    if found == 0 {
        return Err("No plugin directories found".into());
    }

    // Update top-level date
    registry["updated"] = serde_json::json!(today_iso());

    let output = serde_json::to_string_pretty(&registry)? + "\n";
    fs::write(registry_path, output)?;

    println!("Updated {:?} ({} plugins)", registry_path, found);
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
        Commands::Update { plugin_dir, registry } => {
            update_command(&plugin_dir, &registry)
        }
        Commands::UpdateAll { registry } => {
            update_all_command(&registry)
        }
    };

    if let Err(e) = result {
        eprintln!("Error: {}", e);
        std::process::exit(1);
    }
}

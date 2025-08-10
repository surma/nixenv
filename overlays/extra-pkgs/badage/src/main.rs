use age::secrecy::Secret;
use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use std::io::{self, Read, Write};

#[derive(Parser, Debug)]
#[command(name = "badage")]
#[command(about = "Simple age encryption/decryption tool with passphrase as CLI flag")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Parser, Debug)]
struct Args {
    #[arg(short, long, help = "Passphrase for encryption")]
    passphrase: String,

    #[arg(short, long, help = "Input file path or '-' for stdin")]
    input: String,

    #[arg(short, long, help = "Output file path or '-' for stdout")]
    output: String,

    #[arg(short, long, help = "Use ASCII armor for encryption output")]
    armor: bool,
}

#[derive(Subcommand, Debug)]
enum Commands {
    #[command(about = "Encrypt a file or stream")]
    Encrypt(Args),
    #[command(about = "Decrypt a file or stream")]
    Decrypt(Args),
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Encrypt(Args {
            passphrase,
            input,
            output,
            armor,
        }) => {
            encrypt(passphrase, input, output, armor)?;
        }
        Commands::Decrypt(Args {
            passphrase,
            input,
            output,
            armor: _,
        }) => {
            decrypt(passphrase, input, output)?;
        }
    }

    Ok(())
}

fn encrypt(passphrase: String, input: String, output: String, armor: bool) -> Result<()> {
    let input_data = if input == "-" {
        let mut buffer = Vec::new();
        io::stdin()
            .read_to_end(&mut buffer)
            .context("Failed to read from stdin")?;
        buffer
    } else {
        std::fs::read(&input).with_context(|| format!("Failed to read input file: {}", input))?
    };

    let passphrase = Secret::new(passphrase);
    let encryptor = age::Encryptor::with_user_passphrase(passphrase);

    if armor {
        let mut armored = vec![];
        let armor_writer =
            age::armor::ArmoredWriter::wrap_output(&mut armored, age::armor::Format::AsciiArmor)
                .context("Failed to create armored writer")?;
        let mut writer = encryptor
            .wrap_output(armor_writer)
            .context("Failed to create encrypted writer")?;
        writer
            .write_all(&input_data)
            .context("Failed to write encrypted data")?;
        let armor_writer = writer.finish().context("Failed to finish encryption")?;
        armor_writer
            .finish()
            .context("Failed to finish armor writer")?;

        if output == "-" {
            io::stdout()
                .write_all(&armored)
                .context("Failed to write to stdout")?;
        } else {
            std::fs::write(&output, &armored)
                .with_context(|| format!("Failed to write encrypted file: {}", output))?
        }
    } else {
        let mut encrypted = vec![];
        let mut writer = encryptor
            .wrap_output(&mut encrypted)
            .context("Failed to create encrypted writer")?;
        writer
            .write_all(&input_data)
            .context("Failed to write encrypted data")?;
        writer.finish().context("Failed to finish encryption")?;

        if output == "-" {
            io::stdout()
                .write_all(&encrypted)
                .context("Failed to write to stdout")?;
        } else {
            std::fs::write(&output, &encrypted)
                .with_context(|| format!("Failed to write encrypted file: {}", output))?
        }
    }

    Ok(())
}

fn decrypt(passphrase: String, input: String, output: String) -> Result<()> {
    let input_data = if input == "-" {
        let mut buffer = Vec::new();
        io::stdin()
            .read_to_end(&mut buffer)
            .context("Failed to read from stdin")?;
        buffer
    } else {
        std::fs::read(&input).with_context(|| format!("Failed to read input file: {}", input))?
    };

    let passphrase = Secret::new(passphrase);

    let mut output_data = Vec::new();

    // Check if input is armored and handle accordingly
    if input_data.starts_with(b"-----BEGIN AGE ENCRYPTED FILE-----") {
        // Handle armored input
        let armor_reader = age::armor::ArmoredReader::new(&input_data[..]);
        let decryptor = match age::Decryptor::new(armor_reader)
            .context("Failed to parse armored encrypted data")?
        {
            age::Decryptor::Passphrase(d) => d,
            _ => bail!("Invalid encrypted data: expected passphrase-encrypted file"),
        };
        let mut reader = decryptor
            .decrypt(&passphrase, None)
            .context("Failed to decrypt data - incorrect passphrase?")?;
        reader
            .read_to_end(&mut output_data)
            .context("Failed to read decrypted data")?;
    } else {
        // Handle binary input
        let decryptor =
            match age::Decryptor::new(&input_data[..]).context("Failed to parse encrypted data")? {
                age::Decryptor::Passphrase(d) => d,
                _ => bail!("Invalid encrypted data: expected passphrase-encrypted file"),
            };
        let mut reader = decryptor
            .decrypt(&passphrase, None)
            .context("Failed to decrypt data - incorrect passphrase?")?;
        reader
            .read_to_end(&mut output_data)
            .context("Failed to read decrypted data")?;
    }

    if output == "-" {
        io::stdout()
            .write_all(&output_data)
            .context("Failed to write to stdout")?;
    } else {
        std::fs::write(&output, &output_data)
            .with_context(|| format!("Failed to write decrypted file: {}", output))?
    }

    Ok(())
}

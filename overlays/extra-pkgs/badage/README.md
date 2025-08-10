# badage

A simple command-line encryption/decryption tool that allows you to encrypt and decrypt files with [age](https://github.com/FiloSottile/age) by providing the passphrase via a commandline flag.

**This is bad. Don’t use it unles you know why you are doing it.**

## Usage

Encrypt a file:

```bash
badage encrypt --passphrase "your-passphrase" --input plaintext.txt --output encrypted.age
```

Encrypt with ASCII armor output:

```bash
badage encrypt --passphrase "your-passphrase" --input plaintext.txt --output encrypted.age --armor
```

Decrypt a file:

```bash
badage decrypt --passphrase "your-passphrase" --input encrypted.age --output decrypted.txt
```

Stream encryption/decryption from stdin to stdout:

```bash
echo "secret data" | badage encrypt --passphrase "your-passphrase" --input - --output - --armor
```

## Compatibility

`badage` should be fully compatible with files encrypted using the standard `age` tool.

## License

Apache 2.0

package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"strings"
	"sync"
)

const encPrefix = "enc:"

var (
	keyOnce sync.Once
	aesKey  []byte // nil = encryption disabled
)

// loadKey reads and validates ENCRYPTION_KEY from the environment.
// Returns nil if the variable is absent or invalid (no-op mode).
func loadKey() []byte {
	raw := strings.TrimSpace(os.Getenv("ENCRYPTION_KEY"))
	if raw == "" {
		return nil
	}
	// Accept 64-character hex string (= 32 bytes).
	if len(raw) == 64 {
		b, err := hex.DecodeString(raw)
		if err == nil && len(b) == 32 {
			return b
		}
	}
	// Accept raw 32-byte key.
	if len(raw) == 32 {
		return []byte(raw)
	}
	fmt.Fprintf(os.Stderr, "WARN: ENCRYPTION_KEY is set but has invalid length (%d chars); credential encryption disabled\n", len(raw))
	return nil
}

func key() []byte {
	keyOnce.Do(func() { aesKey = loadKey() })
	return aesKey
}

// Encrypt encrypts plaintext with AES-256-GCM and returns "enc:<base64(nonce+ciphertext)>".
// If ENCRYPTION_KEY is not configured it returns the plaintext unchanged.
func Encrypt(plaintext string) (string, error) {
	k := key()
	if k == nil || plaintext == "" {
		return plaintext, nil
	}
	// Don't double-encrypt.
	if strings.HasPrefix(plaintext, encPrefix) {
		return plaintext, nil
	}

	block, err := aes.NewCipher(k)
	if err != nil {
		return "", fmt.Errorf("crypto: new cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("crypto: new GCM: %w", err)
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", fmt.Errorf("crypto: nonce: %w", err)
	}
	ct := gcm.Seal(nonce, nonce, []byte(plaintext), nil)
	return encPrefix + base64.StdEncoding.EncodeToString(ct), nil
}

// Decrypt decrypts a value produced by Encrypt. Values without the "enc:" prefix
// are returned as-is for migration compatibility with existing plaintext rows.
func Decrypt(s string) (string, error) {
	if !strings.HasPrefix(s, encPrefix) {
		return s, nil // plaintext passthrough
	}
	k := key()
	if k == nil {
		// Key not set — return the raw ciphertext; callers will see garbled data rather
		// than silently continuing, which surfaces the misconfiguration.
		return s, fmt.Errorf("crypto: ENCRYPTION_KEY not set but value is encrypted")
	}
	data, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(s, encPrefix))
	if err != nil {
		return "", fmt.Errorf("crypto: base64 decode: %w", err)
	}
	block, err := aes.NewCipher(k)
	if err != nil {
		return "", fmt.Errorf("crypto: new cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("crypto: new GCM: %w", err)
	}
	ns := gcm.NonceSize()
	if len(data) < ns {
		return "", fmt.Errorf("crypto: ciphertext too short")
	}
	pt, err := gcm.Open(nil, data[:ns], data[ns:], nil)
	if err != nil {
		return "", fmt.Errorf("crypto: decrypt: %w", err)
	}
	return string(pt), nil
}

// IsEncrypted reports whether s was encrypted by Encrypt.
func IsEncrypted(s string) bool {
	return strings.HasPrefix(s, encPrefix)
}

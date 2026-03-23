#!/usr/bin/env python3
"""Generate secp256k1 ECC key pair for mars xlog encryption.

Output:
  - Private key (hex): used by the decode script to decrypt logs.
  - Public key (hex):  passed to xlog_config_t.pub_key (or appender_open).

Dependencies: pip install ecdsa
"""

from binascii import hexlify
from ecdsa import SigningKey, SECP256k1

sk = SigningKey.generate(curve=SECP256k1)
vk = sk.get_verifying_key()

privkey_hex = hexlify(sk.to_string()).decode('ascii')
# Uncompressed public key = pubkey_x (32 bytes) + pubkey_y (32 bytes)
pubkey_hex = hexlify(vk.to_string()).decode('ascii')

print("save private key")
print(privkey_hex)

print("\nappender_open's parameter:")
print(pubkey_hex)

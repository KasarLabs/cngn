# cNGN Token 💰

A Cairo smart contract implementation of the cNGN token, a compliant ERC20 token.

## Key Features

- **Controlled Minting**: Pre-authorized minters with automatic authorization revocation after minting
- **Redemption Flow**: External whitelisted senders can transfer to internal users with auto-burn
- **Meta-Transaction Support**: Gasless transactions via Forwarder contract with SNIP-12 signing
- **Blacklist Management**: Prevent blacklisted addresses from interacting; owner can destroy their funds
- **Whitelist System**: Dual whitelist for external senders and internal users
- **Pausable Operations**: Emergency pause mechanism for all token operations
- **Trusted Forwarder**: Secure meta-transaction forwarding with nonce enforcement and replay protection

## Key Components

- **cngn.cairo**: Main token contract (V1) with ERC20, minting, burning, and redemption
- **cngn2.cairo**: Enhanced token contract (V2) with improved events and zero-address validation
- **forwarder.cairo**: Meta-transaction forwarder with SNIP-12 hashing and ISRC6 signature verification
- **Operations.cairo**: Admin contract (V1) managing minters, forwarders, blacklists, and whitelists
- **Operations2.cairo**: Admin contract (V2) with Pausable functionality for all admin functions
- **interface/IOperations.cairo**: Interface for administrative functions

Run `scarb build`

## Security Features

- Owner-controlled access for all administrative functions
- Blacklist protection preventing blacklisted addresses from any token interaction
- Sequential nonce enforcement and replay protection for meta-transactions
- ISRC6 signature verification for meta-transactions
- Emergency pause mechanism for all operations
- Zero-address validation in V2 contracts
- Automatic authorization revocation after minting

## Testing

Comprehensive test suite with 84 tests covering:
- Token deployment, ERC20 functions, and initialization
- Controlled minting, burning, and redemption flows
- Blacklist and whitelist management
- Admin operations and access control
- Pause/unpause functionality
- Meta-transaction forwarder verification
- Bridge authorization

Run `snforge test`

## Deployment

Deploy contracts to Starknet Sepolia (testnet) or Mainnet using TypeScript scripts.

### Setup

```bash
# Install dependencies
npm install

# Copy env.example to .env and configure
cp env.example .env
```

Configure your `.env` file:
```
STARKNET_PRIVATE_KEY=your_private_key
STARKNET_ACCOUNT_ADDRESS=0x_your_account_address
STARKNET_NETWORK=sepolia
```

### Deploy

```bash
# Deploy to Sepolia testnet
npm run deploy:sepolia

# Deploy to Mainnet
npm run deploy:mainnet
```

Deployment addresses are saved to the `deployments/` folder.


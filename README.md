# WrappedHive - HIVE Bridge for Ethereum

A bridge contract for wrapping HIVE/HBD tokens on Ethereum and compatible EVM chains.

## Features

- ERC20 compliant token with gasless approvals (EIP-2612)
- Multisig-controlled governance for security
- Prevents double minting and replay attacks
- Emergency pause functionality
- Optimized for gas efficiency

## Architecture

Hive Blockchain ↔ Bridge Nodes ↔ WrappedHive Contract

## Contract Details

- **Decimals**: 3 (matching HIVE precision)
- **Standards**: ERC20, ERC20Permit
- **Security**: Multisig, Pausable, Custom errors

## Getting Started

### Prerequisites

- Node.js 18+ and npm
- Git

### Installation

```bash
# Clone the repository
git clone https://github.com/mahdiyari/hive-bridge-eth.git
cd hive-bridge-eth

# Install dependencies
npm install

# Build contracts
npx hardhat build
```

### Running Tests

```bash
# Run all tests
npm test

# Run comprehensive test suite
npm run test:comprehensive
```

## Deployment

### Quick Start - Testnet

```bash
# Configure testnet private key
npx hardhat keystore set SEPOLIA_PRIVATE_KEY

# Deploy to Sepolia
npm run deploy:sepolia
```

## Usage

### For Users

#### Wrapping HIVE → Wrapped HIVE

1. Send HIVE/HBD to the bridge address on Hive blockchain with memo containing your Ethereum address e.g. `ETH:0x1234...`
2. Bridge nodes detect the transaction and create signatures
3. Call `wrap()` with the signatures to mint tokens on Ethereum

#### Unwrapping Wrapped HIVE → HIVE

1. Call `unwrap(amount, hiveUsername)` on the contract
2. Bridge nodes detect the Unwrap event
3. HIVE tokens sent to your Hive account after 12 confirmations

### For Developers

```javascript
// Import the contract ABI
import WrappedHiveABI from './artifacts/contracts/WrappedHive.sol/WrappedHive.json'

// Create contract instance
const contract = new ethers.Contract(
  contractAddress,
  WrappedHiveABI.abi,
  signer
)

// Check balance
const balance = await contract.balanceOf(userAddress)

// Unwrap tokens
await contract.unwrap(ethers.parseUnits('10', 3), 'hive-username')

// Get all signers
const signers = await contract.getAllSigners()
```

## API Reference

### Core Functions

#### `wrap(uint256 amount, string trx_id, uint32 op_in_trx, bytes[] signatures)`

Mints new tokens by wrapping HIVE from Hive blockchain.

- **amount**: Token amount (3 decimals, e.g., 1.000 HIVE = 1000)
- **trx_id**: Hive transaction ID
- **op_in_trx**: Operation index in the transaction
- **signatures**: Array of signatures from bridge signers

#### `unwrap(uint256 amount, string username)`

Burns tokens to unwrap back to Hive blockchain.

- **amount**: Token amount to burn (3 decimals)
- **username**: Hive username to receive tokens (3-16 characters)

### Governance Functions

#### `addSigner(address addr, string username, bytes[] signatures)`

Adds a new authorized signer (requires multisig approval).

#### `removeSigner(address addr, bytes[] signatures)`

Removes an authorized signer (requires multisig approval).

#### `updateMultisigThreshold(uint8 newThreshold, bytes[] signatures)`

Updates the number of required signatures (requires multisig approval).

#### `pause(bytes[] signatures)` / `unpause(bytes[] signatures)`

Emergency pause/unpause functions (requires multisig approval).

## License

GPL-3.0 - see LICENSE file.

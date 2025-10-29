import type { HardhatUserConfig } from 'hardhat/config'

import hardhatToolboxViemPlugin from '@nomicfoundation/hardhat-toolbox-viem'
import { configVariable } from 'hardhat/config'

const config: HardhatUserConfig = {
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    profiles: {
      default: {
        version: '0.8.30',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          viaIR: false,
        },
      },
      production: {
        version: '0.8.30',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000000, // Optimize for function execution cost
          },
          viaIR: true, // Use intermediate representation for better optimization
        },
      },
    },
  },
  networks: {
    // Local development networks
    hardhatMainnet: {
      type: 'edr-simulated',
      chainType: 'l1',
    },
    hardhatOp: {
      type: 'edr-simulated',
      chainType: 'op',
    },

    // Testnets
    sepolia: {
      type: 'http',
      chainType: 'l1',
      url: configVariable('SEPOLIA_RPC_URL'),
      accounts: [configVariable('SEPOLIA_PRIVATE_KEY')],
    },
    holesky: {
      type: 'http',
      chainType: 'l1',
      url: configVariable('HOLESKY_RPC_URL'),
      accounts: [configVariable('HOLESKY_PRIVATE_KEY')],
    },

    // Production mainnet - Ethereum
    mainnet: {
      type: 'http',
      chainType: 'l1',
      url: configVariable('MAINNET_RPC_URL'),
      accounts: [configVariable('MAINNET_PRIVATE_KEY')],
    },

    // Layer 2 Networks
    optimism: {
      type: 'http',
      chainType: 'op',
      url: configVariable('OPTIMISM_RPC_URL'),
      accounts: [configVariable('OPTIMISM_PRIVATE_KEY')],
    },
    arbitrum: {
      type: 'http',
      chainType: 'op',
      url: configVariable('ARBITRUM_RPC_URL'),
      accounts: [configVariable('ARBITRUM_PRIVATE_KEY')],
    },
    base: {
      type: 'http',
      chainType: 'op',
      url: configVariable('BASE_RPC_URL'),
      accounts: [configVariable('BASE_PRIVATE_KEY')],
    },
    polygon: {
      type: 'http',
      chainType: 'op',
      url: configVariable('POLYGON_RPC_URL'),
      accounts: [configVariable('POLYGON_PRIVATE_KEY')],
    },
  },
}

export default config

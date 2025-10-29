import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

/**
 * Deployment module for WrappedHive contract
 *
 * Usage:
 * npx hardhat ignition deploy ignition/modules/WrappedHive.ts --network <network>
 *
 * For mainnet/production deployment, ensure you have:
 * 1. Set the PRIVATE_KEY environment variable
 * 2. Set the appropriate RPC_URL
 * 3. Review and confirm the initial signer address and username
 */

const WrappedHiveModule = buildModule('WrappedHiveModule', (m) => {
  // Parameters for deployment - these can be overridden during deployment
  const tokenName = m.getParameter('tokenName', 'Wrapped HIVE')
  const tokenSymbol = m.getParameter('tokenSymbol', 'WHIVE')

  // IMPORTANT: Change these values for production deployment
  // The initial signer should be a secure multisig wallet or trusted party
  const initialSigner = m.getParameter(
    'initialSigner',
    '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266' // Default Hardhat account #0
  )
  const initialUsername = m.getParameter('initialUsername', 'hive-bridge')

  // Deploy the WrappedHive contract
  const wrappedHive = m.contract('WrappedHive', [
    tokenName,
    tokenSymbol,
    initialSigner,
    initialUsername,
  ])

  return { wrappedHive }
})

export default WrappedHiveModule

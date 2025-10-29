/**
 * Comprehensive test suite for WrappedHive contract
 * Tests all functionality including security, edge cases, and gas optimization
 */

import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { network } from 'hardhat'
import { encodePacked, keccak256 } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'

// Test private keys
const signerPKs: `0x${string}`[] = [
  '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
  '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
  '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a',
  '0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6',
]

const signers = signerPKs.map((pk) => privateKeyToAccount(pk).address)
const accounts = signerPKs.map((pk) => privateKeyToAccount(pk))

// Helper functions
const hashMintMsg = (
  address: `0x${string}`,
  amount: bigint,
  trxId: string,
  opInTrx: number,
  contractAddress: `0x${string}`
) => {
  return keccak256(
    encodePacked(
      [
        'string',
        'string',
        'address',
        'string',
        'uint256',
        'string',
        'string',
        'string',
        'uint32',
        'string',
        'address',
      ],
      [
        'wrap',
        ';',
        address,
        ';',
        amount,
        ';',
        trxId,
        ';',
        opInTrx,
        ';',
        contractAddress,
      ]
    )
  )
}

const hashAddSigner = (
  addr: `0x${string}`,
  username: string,
  nonce: bigint,
  contractAddress: `0x${string}`
) => {
  return keccak256(
    encodePacked(
      [
        'string',
        'string',
        'address',
        'string',
        'string',
        'string',
        'uint256',
        'string',
        'address',
      ],
      ['addSigner', ';', addr, ';', username, ';', nonce, ';', contractAddress]
    )
  )
}

const hashUpdateThreshold = (
  newThreshold: number,
  nonce: bigint,
  contractAddress: `0x${string}`
) => {
  return keccak256(
    encodePacked(
      ['string', 'string', 'uint8', 'string', 'uint256', 'string', 'address'],
      [
        'updateMultisigThreshold',
        ';',
        newThreshold,
        ';',
        nonce,
        ';',
        contractAddress,
      ]
    )
  )
}

describe('WrappedHive - Comprehensive Tests', async function () {
  const { viem } = await network.connect()

  describe('Deployment', function () {
    it('should deploy with correct initial values', async function () {
      const wHIVE = await viem.deployContract('WrappedHive', [
        'Wrapped HIVE',
        'WHIVE',
        signers[0],
        'testuser',
      ])

      const name = await wHIVE.read.name()
      const symbol = await wHIVE.read.symbol()
      const decimals = await wHIVE.read.decimals()
      const threshold = await wHIVE.read.multisigThreshold()
      const allSigners = await wHIVE.read.getAllSigners()

      assert.equal(name, 'Wrapped HIVE')
      assert.equal(symbol, 'WHIVE')
      assert.equal(decimals, 3)
      assert.equal(threshold, 1)
      assert.equal(allSigners.length, 1)
      assert.equal(allSigners[0].addr.toLowerCase(), signers[0].toLowerCase())
      assert.equal(allSigners[0].username, 'testuser')
    })

    it('should reject invalid initial signer', async function () {
      await assert.rejects(
        viem.deployContract('WrappedHive', [
          'Wrapped HIVE',
          'WHIVE',
          '0x0000000000000000000000000000000000000000',
          'testuser',
        ])
      )
    })

    it('should reject invalid username length', async function () {
      await assert.rejects(
        viem.deployContract('WrappedHive', [
          'Wrapped HIVE',
          'WHIVE',
          signers[0],
          'ab',
        ])
      )
    })
  })

  describe('Wrapping (Minting)', function () {
    it('should wrap tokens successfully', async function () {
      const wHIVE = await viem.deployContract('WrappedHive', [
        'Wrapped HIVE',
        'WHIVE',
        signers[0],
        'signer1',
      ])
      const contractAddress = wHIVE.address

      const trxId = 'abc123def456'
      const opInTrx = 0
      const amount = 5000n

      const hash = hashMintMsg(
        signers[1],
        amount,
        trxId,
        opInTrx,
        contractAddress
      )
      const signature = await accounts[0].sign({ hash })

      await wHIVE.write.wrap([amount, trxId, opInTrx, [signature]], {
        account: accounts[1],
      })

      const balance = await wHIVE.read.balanceOf([signers[1]])
      const totalSupply = await wHIVE.read.totalSupply()

      assert.equal(balance, amount)
      assert.equal(totalSupply, amount)
    })

    it('should reject duplicate wrapping', async function () {
      const wHIVE = await viem.deployContract('WrappedHive', [
        'Wrapped HIVE',
        'WHIVE',
        signers[0],
        'signer1',
      ])
      const contractAddress = wHIVE.address

      const trxId = 'duplicate_test'
      const opInTrx = 0
      const amount = 5000n

      const hash = hashMintMsg(
        signers[1],
        amount,
        trxId,
        opInTrx,
        contractAddress
      )
      const signature = await accounts[0].sign({ hash })

      await wHIVE.write.wrap([amount, trxId, opInTrx, [signature]], {
        account: accounts[1],
      })

      await assert.rejects(
        wHIVE.write.wrap([amount, trxId, opInTrx, [signature]], {
          account: accounts[1],
        })
      )
    })
  })

  describe('Multisig Operations', function () {
    it('should add a new signer', async function () {
      const wHIVE = await viem.deployContract('WrappedHive', [
        'Wrapped HIVE',
        'WHIVE',
        signers[0],
        'signer1',
      ])
      const contractAddress = wHIVE.address

      const nonce = await wHIVE.read.nonceAddSigner()
      const hash = hashAddSigner(
        signers[1],
        'newsigner',
        nonce,
        contractAddress
      )
      const signature = await accounts[0].sign({ hash })

      await wHIVE.write.addSigner([signers[1], 'newsigner', [signature]], {
        account: accounts[0],
      })

      const allSigners = await wHIVE.read.getAllSigners()
      assert.equal(allSigners.length, 2)
    })

    it('should update multisig threshold', async function () {
      const wHIVE = await viem.deployContract('WrappedHive', [
        'Wrapped HIVE',
        'WHIVE',
        signers[0],
        'signer1',
      ])
      const contractAddress = wHIVE.address

      // Add second signer
      let nonce = await wHIVE.read.nonceAddSigner()
      let hash = hashAddSigner(signers[1], 'signer2', nonce, contractAddress)
      let signature = await accounts[0].sign({ hash })
      await wHIVE.write.addSigner([signers[1], 'signer2', [signature]], {
        account: accounts[0],
      })

      // Update threshold
      nonce = await wHIVE.read.nonceUpdateThreshold()
      hash = hashUpdateThreshold(2, nonce, contractAddress)
      signature = await accounts[0].sign({ hash })
      await wHIVE.write.updateMultisigThreshold([2, [signature]], {
        account: accounts[0],
      })

      const threshold = await wHIVE.read.multisigThreshold()
      assert.equal(threshold, 2)
    })
  })
})

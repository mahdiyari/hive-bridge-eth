/**
 * Don't really need tests? but built the foundation for further test writing
 * Currently includes two simple mint tests
 */

import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { network } from 'hardhat'
import { encodePacked, keccak256 } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'

// Default Hardhat test private keys for simulation
const signerPKs: `0x${string}`[] = [
  '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
  '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
  '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a',
  '0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6',
]

const signers = signerPKs.map((pk) => privateKeyToAccount(pk).address)
const accounts = signerPKs.map((pk) => privateKeyToAccount(pk))

const hashMintMsg = (
  address: `0x${string}`,
  amount: bigint,
  trxId: string,
  opInTrx: number,
  contractAddress: `0x${string}`,
  chainId: bigint
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
        'string',
        'uint256',
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
        ';',
        chainId,
      ]
    )
  )
}

describe('WrappedHive', async function () {
  const { viem } = await network.connect()

  const wHIVE = await viem.deployContract('WrappedHive', [
    'Wrapped HIVE',
    'HIVE',
    signers[0],
    'randomuser',
  ])
  const contractAddress = wHIVE.address
  const chainId = BigInt(await (await viem.getPublicClient()).getChainId())

  it('should have total supply equal to all minted tokens', async function () {
    const trxId = '0000000000000000000000000000000000000000'
    const opInTrx = 0
    const amount = 2500n
    const hash = hashMintMsg(
      signers[0],
      amount,
      trxId,
      opInTrx,
      contractAddress,
      chainId
    )
    const signature = await accounts[0].sign({ hash })
    await wHIVE.write.wrap([amount, trxId, opInTrx, [signature]], {
      account: accounts[0],
    })
    const supply = await wHIVE.read.totalSupply()
    assert.equal(supply, amount)
  })

  it("shouldn't mint with the same (trx_id, op_in_trx)", async function () {
    const trxId = '0000000000000000000000000000000000000000'
    const opInTrx = 0
    const amount = 5000n
    const hash = hashMintMsg(
      signers[0],
      amount,
      trxId,
      opInTrx,
      contractAddress,
      chainId
    )
    const signature = await accounts[0].sign({ hash })
    assert.rejects(
      wHIVE.write.wrap([amount, trxId, opInTrx, [signature]], {
        account: accounts[0],
      })
    )
  })
})

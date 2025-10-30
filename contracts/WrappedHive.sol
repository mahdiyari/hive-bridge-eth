// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/// @title WrappedHive - A bridge token for HIVE blockchain
/// @notice This contract implements a wrapped version of HIVE token with multisig governance
/// @dev Implements ERC20, ERC20Permit for gasless approvals, and Pausable for emergency stops
/// @dev No reentrancy protection needed - contract has no external calls or value transfers
contract WrappedHive is ERC20, ERC20Permit, Pausable {
    /// @notice Tracks whether tokens have been minted for a specific Hive transaction
    /// @dev Prevents double-minting by tracking (trx_id, op_in_trx) combinations
    mapping(string trx_id => mapping(uint32 op_in_trx => bool))
        public hasMinted;

    /// @notice Array of authorized signers
    address[] public signers;

    /// @notice Maps signer addresses to their Hive usernames
    mapping(address ethAddress => string hiveUsername) public signerNames;

    /// @notice Struct for returning signer information
    /// @param username The Hive username of the signer
    /// @param addr The Ethereum address of the signer
    struct signerInfo {
        string username;
        address addr;
    }

    /// @notice Minimum number of signatures required for multisig operations
    uint8 public multisigThreshold;

    /// @notice Nonces to prevent replay attacks for different operations
    uint256 public nonceAddSigner;
    uint256 public nonceRemoveSigner;
    uint256 public nonceUpdateThreshold;
    uint256 public noncePause;
    uint256 public nonceUnpause;

    /// @notice Emitted when tokens are unwrapped (burned) to send back to Hive
    /// @param messenger The address initiating the unwrap
    /// @param amount The amount of tokens being unwrapped (3 decimals)
    /// @param username The Hive username that will receive the native tokens
    event Unwrap(address indexed messenger, uint256 amount, string username);

    /// @notice Emitted when tokens are wrapped (minted) from Hive
    /// @param recipient The address receiving the wrapped tokens
    /// @param amount The amount of tokens being wrapped (3 decimals)
    /// @param trxId The Hive transaction ID
    /// @param opInTrx The operation index within the transaction
    event Wrap(
        address indexed recipient,
        uint256 amount,
        string trxId,
        uint32 opInTrx
    );

    /// @notice Emitted when a new signer is added
    /// @param signer The address of the new signer
    /// @param username The Hive username of the new signer
    event SignerAdded(address indexed signer, string username);

    /// @notice Emitted when a signer is removed
    /// @param signer The address of the removed signer
    /// @param username The Hive username of the removed signer
    event SignerRemoved(address indexed signer, string username);

    /// @notice Emitted when the multisig threshold is updated
    /// @param oldThreshold The previous threshold value
    /// @param newThreshold The new threshold value
    event MultisigThresholdUpdated(uint8 oldThreshold, uint8 newThreshold);

    /// @dev Cached contract address for gas optimization
    address private immutable contractAddress;

    /// @notice Thrown when signature verification fails
    error InvalidSignatures();

    /// @notice Thrown when not enough signatures provided to satisfy threshold
    error NotEnoughSignatures();

    /// @notice Thrown when too many signatures are provided
    error TooManySignatures();

    /// @notice Thrown when trying to add a duplicate signer
    error SignerAlreadyExists();

    /// @notice Thrown when trying to remove a non-existent signer
    error SignerDoesNotExist();

    /// @notice Thrown when threshold would be invalid
    error InvalidThreshold();

    /// @notice Thrown when username is invalid
    error InvalidUsername();

    /// @notice Thrown when trying to mint tokens that have already been minted
    error AlreadyMinted();

    /// @notice Thrown when value is zero
    error MustBeNonZero();

    /// @notice Thrown when signature length is invalid
    error InvalidSignatureLength();

    /// @notice Initializes the WrappedHive contract
    /// @param name The name of the token (e.g., "Wrapped HIVE")
    /// @param symbol The symbol of the token (e.g., "WHIVE")
    /// @param initialSigner The address of the initial signer
    /// @param initialUsername The Hive username of the initial signer
    constructor(
        string memory name,
        string memory symbol,
        address initialSigner,
        string memory initialUsername
    ) ERC20(name, symbol) ERC20Permit(name) {
        contractAddress = address(this);
        multisigThreshold = 1;
        nonceAddSigner = 0;
        nonceRemoveSigner = 0;
        nonceUpdateThreshold = 0;
        noncePause = 0;
        nonceUnpause = 0;

        signers.push(initialSigner);
        signerNames[initialSigner] = initialUsername;
        emit SignerAdded(initialSigner, initialUsername);
    }

    /// @notice Updates the multisig threshold
    /// @dev Requires valid signatures from current signers
    /// @param newThreshold New threshold value (must be > 0 and <= signers.length)
    /// @param signatures Array of signatures from signers
    /// Message format: "updateMultisigThreshold;{newThreshold};{nonceUpdateThreshold};{contract}"
    function updateMultisigThreshold(
        uint8 newThreshold,
        bytes[] memory signatures
    ) external whenNotPaused {
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "updateMultisigThreshold",
                ";",
                newThreshold,
                ";",
                nonceUpdateThreshold,
                ";",
                contractAddress
            )
        );
        _validateSignatures(msgHash, signatures);

        if (newThreshold == 0 || newThreshold > signers.length) {
            revert InvalidThreshold();
        }
        if (newThreshold == multisigThreshold) {
            revert InvalidThreshold();
        }

        emit MultisigThresholdUpdated(multisigThreshold, newThreshold);
        multisigThreshold = newThreshold;
        nonceUpdateThreshold++;
    }

    /// @notice Adds a new signer to the multisig
    /// @dev Requires valid signatures from current signers
    /// @param addr Ethereum address of the new signer
    /// @param username Hive username of the new signer (3-16 characters)
    /// @param signatures Array of signatures from current signers
    /// Message format: "addSigner;{addr};{username};{nonceAddSigner};{contract}"
    function addSigner(
        address addr,
        string memory username,
        bytes[] memory signatures
    ) external whenNotPaused {
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "addSigner",
                ";",
                addr,
                ";",
                username,
                ";",
                nonceAddSigner,
                ";",
                contractAddress
            )
        );
        _validateSignatures(msgHash, signatures);

        if (addr == address(0)) {
            revert InvalidUsername();
        }
        if (bytes(signerNames[addr]).length != 0) {
            revert SignerAlreadyExists();
        }
        uint256 len = bytes(username).length;
        if (len < 3 || len > 16) {
            revert InvalidUsername();
        }

        signers.push(addr);
        signerNames[addr] = username;
        nonceAddSigner++;
        emit SignerAdded(addr, username);
    }

    /// @notice Removes a signer from the multisig
    /// @dev Requires valid signatures and ensures threshold remains valid
    /// @param addr Ethereum address of the signer to remove
    /// @param signatures Array of signatures from current signers
    /// Message format: "removeSigner;{addr};{nonceRemoveSigner};{contract}"
    function removeSigner(
        address addr,
        bytes[] memory signatures
    ) external whenNotPaused {
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "removeSigner",
                ";",
                addr,
                ";",
                nonceRemoveSigner,
                ";",
                contractAddress
            )
        );
        _validateSignatures(msgHash, signatures);
        if (bytes(signerNames[addr]).length == 0) {
            revert SignerDoesNotExist();
        }
        uint256 signerCount = signers.length;
        if (multisigThreshold > signerCount - 1) {
            revert InvalidThreshold();
        }
        emit SignerRemoved(addr, signerNames[addr]);
        delete signerNames[addr];
        for (uint256 i = 0; i < signerCount; i++) {
            if (signers[i] == addr) {
                // replace with last
                signers[i] = signers[signerCount - 1];
                // remove last
                signers.pop();
                break;
            }
        }
        nonceRemoveSigner++;
    }

    /// @notice Pauses all token transfers and critical operations
    /// @dev Requires valid signatures from current signers
    /// @param signatures Array of signatures from current signers
    /// Message format: "pause;{noncePause};{contract}"
    function pause(bytes[] memory signatures) external whenNotPaused {
        bytes32 msgHash = keccak256(
            abi.encodePacked("pause", ";", noncePause, ";", contractAddress)
        );
        _validateSignatures(msgHash, signatures);
        noncePause++;
        _pause();
    }

    /// @notice Unpauses all token transfers and critical operations
    /// @dev Requires valid signatures from current signers
    /// @param signatures Array of signatures from current signers
    /// Message format: "unpause;{nonceUnpause};{contract}"
    function unpause(bytes[] memory signatures) external whenPaused {
        bytes32 msgHash = keccak256(
            abi.encodePacked("unpause", ";", nonceUnpause, ";", contractAddress)
        );
        _validateSignatures(msgHash, signatures);
        nonceUnpause++;
        _unpause();
    }

    /// @notice Mints new tokens by wrapping HIVE from the Hive blockchain
    /// @dev Prevents replay attacks and double-minting
    /// @param amount Token amount (3 decimals, e.g., 1.000 HIVE = 1000)
    /// @param trx_id Transaction ID from the Hive blockchain
    /// @param op_in_trx Operation index within the Hive transaction
    /// @param signatures Array of signatures from current signers
    /// Message format: "wrap;{address};{amount};{trx_id};{op_in_trx};{contract}"
    function wrap(
        uint256 amount,
        string memory trx_id,
        uint32 op_in_trx,
        bytes[] memory signatures
    ) external whenNotPaused {
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "wrap",
                ";",
                _msgSender(),
                ";",
                amount,
                ";",
                trx_id,
                ";",
                op_in_trx,
                ";",
                contractAddress
            )
        );
        _validateSignatures(msgHash, signatures);

        if (hasMinted[trx_id][op_in_trx]) {
            revert AlreadyMinted();
        }
        if (amount == 0) {
            revert MustBeNonZero();
        }

        hasMinted[trx_id][op_in_trx] = true;
        _mint(_msgSender(), amount);
        emit Wrap(_msgSender(), amount, trx_id, op_in_trx);
    }

    /// @notice Burns tokens to unwrap them back to the Hive blockchain
    /// @dev Emits Unwrap event that bridge nodes will process
    /// @param amount Token amount to burn (3 decimals, e.g., 1.000 HIVE = 1000)
    /// @param username Hive username that will receive the native tokens (3-16 characters)
    function unwrap(
        uint256 amount,
        string memory username
    ) external whenNotPaused {
        uint256 len = bytes(username).length;
        if (len < 3 || len > 16) {
            revert InvalidUsername();
        }
        if (amount == 0) {
            revert MustBeNonZero();
        }
        _burn(_msgSender(), amount);
        emit Unwrap(_msgSender(), amount, username);
    }

    /// @notice Returns the number of decimals used by the token
    /// @dev HIVE/HBD uses 3 decimals
    /// @return The number of decimals (3)
    function decimals() public view virtual override returns (uint8) {
        return 3;
    }

    /// @notice Returns all current signers with their Hive usernames
    /// @return Array of signerInfo structs containing addresses and usernames
    function getAllSigners() public view returns (signerInfo[] memory) {
        uint256 singerCount = signers.length;
        signerInfo[] memory signerInfos = new signerInfo[](singerCount);
        for (uint256 i = 0; i < singerCount; i++) {
            address signer = signers[i];
            string memory username = signerNames[signer];
            signerInfos[i] = signerInfo({addr: signer, username: username});
        }
        return signerInfos;
    }

    /// @dev Validates that enough valid signatures are provided
    /// @param messageHash The hash of the message that was signed
    /// @param signatures Array of signatures to validate
    /// @return true if validation succeeds (reverts otherwise)
    function _validateSignatures(
        bytes32 messageHash,
        bytes[] memory signatures
    ) internal view returns (bool) {
        uint256 signatureCount = signatures.length;
        uint8 threshold = multisigThreshold;
        uint256 signerCount = signers.length;

        if (signatureCount < threshold) {
            revert NotEnoughSignatures();
        }
        if (signatureCount > signerCount) {
            revert TooManySignatures();
        }

        uint256 validSignatures;
        address[] memory seen = new address[](signerCount);
        uint256 seenCount = 0;

        for (uint256 i = 0; i < signatureCount; i++) {
            address recovered = _recoverSigner(messageHash, signatures[i]);

            if (
                bytes(signerNames[recovered]).length > 0 &&
                !_alreadySeen(seen, seenCount, recovered)
            ) {
                seen[seenCount] = recovered;
                seenCount++;
                validSignatures++;

                if (validSignatures >= threshold) {
                    return true;
                }
            }
        }

        revert InvalidSignatures();
    }

    /// @dev Recovers the signer address from a signature
    /// @param messageHash The hash of the message that was signed
    /// @param signature The signature bytes (must be 65 bytes)
    /// @return The recovered signer address
    function _recoverSigner(
        bytes32 messageHash,
        bytes memory signature
    ) internal pure returns (address) {
        if (signature.length != 65) {
            revert InvalidSignatureLength();
        }

        uint8 v;
        bytes32 r;
        bytes32 s;

        assembly {
            // first 32 bytes, after the length prefix.
            r := mload(add(signature, 32))
            // second 32 bytes.
            s := mload(add(signature, 64))
            // final byte (first byte of the next 32 bytes).
            v := byte(0, mload(add(signature, 96)))
        }

        return ecrecover(messageHash, v, r, s);
    }

    /// @dev Checks if an address has already been counted in signature validation
    /// @param seen Array of addresses that have been seen
    /// @param seenCount Number of addresses in the seen array
    /// @param addr Address to check
    /// @return true if the address has been seen, false otherwise
    function _alreadySeen(
        address[] memory seen,
        uint256 seenCount,
        address addr
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < seenCount; i++) {
            if (seen[i] == addr) {
                return true;
            }
        }
        return false;
    }
}

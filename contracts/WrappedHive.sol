// SPDX-License-Identifier: GNU-GPL3.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract WrappedHive is ERC20, ERC20Permit {
    // Only mint once per hive (trx_id, op_in_trx)
    mapping(string trx_id => mapping(uint32 op_in_trx => bool))
        public hasMinted;

    // Storing signers for multisig
    address[] public signers;
    mapping(address ethAddress => string hiveUsername) public signerNames;
    // Using this struct to return signers data
    struct signerInfo {
        string username;
        address addr;
    }

    // Require this number of signatures
    uint8 public multisigThreshold;

    // Using nonces to prevent replay attacks
    uint256 public nonceAddSigner;
    uint256 public nonceRemoveSigner;
    uint256 public nonceUpdateThreshold;

    // We need this event to log the username for unwrapping
    event Unwrap(address messenger, uint256 amount, string username);

    // Events for important actions
    event SignerAdded(address indexed signer, string username);
    event SignerRemoved(address indexed signer, string username);
    event MultisigThresholdUpdated(uint8 oldThreshold, uint8 newThreshold);

    constructor(
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) ERC20Permit(name) {
        multisigThreshold = 1;
        nonceAddSigner = 0;
        nonceRemoveSigner = 0;
        nonceUpdateThreshold = 0;

        // Use hive account bridge2 as initial signer
        address initAddress = address(
            0xdaFee37b351Db49C3F3D1C01e75fbbbAbA65e68c
        );
        signers.push(initAddress);
        signerNames[initAddress] = "bridge2";
    }

    /// Update the value of multisigThreshold
    /// @param newThreshold positive value lower than the total number of signers
    /// @param signatures signed message: "updateMultisigThreshold";newThreshold;nonceUpdateThreshold;contract
    function updateMultisigThreshold(
        uint8 newThreshold,
        bytes[] memory signatures
    ) public {
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "updateMultisigThreshold",
                ";",
                newThreshold,
                ";",
                nonceUpdateThreshold,
                ";",
                address(this)
            )
        );
        _validateSignatures(msgHash, signatures);
        require(
            newThreshold <= signers.length,
            "multisigThreshold must be less than or equal to signers.length"
        );
        require(newThreshold > 0, "multisigThreshold must be positive");
        emit MultisigThresholdUpdated(multisigThreshold, newThreshold);
        multisigThreshold = newThreshold;
        nonceUpdateThreshold++;
    }

    /// Add new signer
    /// @param addr Ethereum address of the signer derived from their public active key
    /// @param username Hive username of the signer
    /// @param signatures signed message: "addSigner";addr;username;nonceAddSigner;contract
    function addSigner(
        address addr,
        string memory username,
        bytes[] memory signatures
    ) public {
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
                address(this)
            )
        );
        _validateSignatures(msgHash, signatures);
        require(!_isSigner(addr), "Already a signer.");
        signers.push(addr);
        signerNames[addr] = username;
        nonceAddSigner++;
        emit SignerAdded(addr, username);
    }

    /// Remove a signer
    /// @param addr Ethereum address of the signer
    /// @param signatures signed message: "removeSigner";addr;nonceRemoveSigner;contract
    function removeSigner(address addr, bytes[] memory signatures) public {
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "removeSigner",
                ";",
                addr,
                ";",
                nonceRemoveSigner,
                ";",
                address(this)
            )
        );
        _validateSignatures(msgHash, signatures);
        require(_isSigner(addr), "Address is not a signer.");
        require(
            signers.length - 1 >= multisigThreshold,
            "multisigThreshold can't be higher than signers.length"
        );
        emit SignerRemoved(addr, signerNames[addr]);
        delete signerNames[addr];
        for (uint256 i = 0; i < signers.length; i++) {
            if (signers[i] == addr) {
                // replace with last
                signers[i] = signers[signers.length - 1];
                // remove last
                signers.pop();
                break;
            }
        }
        nonceRemoveSigner++;
    }

    /// Mint new tokens
    /// @param amount token amount without decimals "1.000 HIVE" => 1000
    /// @param trx_id trx_id from the Hive transaction
    /// @param op_in_trx op_in_trx from the Hive transaction
    /// @param signatures signed message: "wrap";address;amount;trx_id;op_in_trx;contract
    function wrap(
        uint256 amount,
        string memory trx_id,
        uint32 op_in_trx,
        bytes[] memory signatures
    ) public {
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
                address(this)
            )
        );
        _validateSignatures(msgHash, signatures);
        require(
            !hasMinted[trx_id][op_in_trx],
            "Already minted with this (trx_id, op_in_trx)"
        );
        hasMinted[trx_id][op_in_trx] = true;
        _mint(_msgSender(), amount);
    }

    /// Burn the tokens and emit an Unwrap event that will be picked up by the bridge nodes
    /// @param amount token amount without decimals "1.000 HIVE" => 1000
    /// @param username Hive username that will receive the native tokens
    function unwrap(uint256 amount, string memory username) public {
        uint256 len = bytes(username).length;
        require(len >= 3 && len <= 16, "Username must be 3-16 characters long");
        _burn(_msgSender(), amount);
        emit Unwrap(_msgSender(), amount, username);
    }

    // HIVE/HBD decimals is 3
    function decimals() public view virtual override returns (uint8) {
        return 3;
    }

    /// Returns all the signers with their Hive username
    function getAllSigners() public view returns (signerInfo[] memory) {
        signerInfo[] memory signerInfos = new signerInfo[](signers.length);
        for (uint256 i = 0; i < signers.length; i++) {
            address signer = signers[i];
            string memory username = signerNames[signer];
            signerInfos[i] = signerInfo({addr: signer, username: username});
        }
        return signerInfos;
    }

    // Validate multisig signatures based on a threshold
    function _validateSignatures(
        bytes32 messageHash,
        bytes[] memory signatures
    ) internal view returns (bool) {
        require(
            signatures.length >= multisigThreshold,
            "Not enought signatures to satisfy multisigThreshold."
        );
        uint256 validSignatures;
        address[] memory seen = new address[](signers.length);
        uint256 seenCount = 0;
        for (uint256 i = 0; i < signatures.length; i++) {
            address recovered = _recoverSigner(messageHash, signatures[i]);
            if (
                _isSigner(recovered) &&
                !_alreadySeen(seen, seenCount, recovered)
            ) {
                seen[seenCount] = recovered;
                seenCount++;
                validSignatures++;
                if (validSignatures >= multisigThreshold) {
                    return true;
                }
            }
        }
        revert("Invalid signatures");
    }

    // Is the address a registered signer?
    function _isSigner(address addr) internal view returns (bool) {
        return bytes(signerNames[addr]).length > 0;
    }

    // Find out if we have already seen a signer
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

    // Split a signature to v,r,s
    function _splitSignature(
        bytes memory sig
    ) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(sig.length == 65);
        assembly {
            // first 32 bytes, after the length prefix.
            r := mload(add(sig, 32))
            // second 32 bytes.
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes).
            v := byte(0, mload(add(sig, 96)))
        }
        return (v, r, s);
    }

    // recover address from msg and signature
    function _recoverSigner(
        bytes32 message,
        bytes memory sig
    ) internal pure returns (address) {
        (uint8 v, bytes32 r, bytes32 s) = _splitSignature(sig);
        return ecrecover(message, v, r, s);
    }
}

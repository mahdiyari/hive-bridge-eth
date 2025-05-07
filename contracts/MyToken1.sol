// SPDX-License-Identifier: GNU-GPL3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

// import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract WrappedHive is ERC20, ERC20Permit {
    // Only mint once per blockNum per given address
    // {address: {blockNum: boolean}}
    mapping(address => mapping(uint32 => bool)) public hasMinted;
    address[] public signers;
    mapping(address => string) public signerNames;
    struct signerInfo {
        string username;
        address addr;
    }
    // Don't use multisig until we set this to true - Used for testing
    bool public multisig = false;
    // This depends on how many signers we end up having
    // I feel 60% would be fine - might be worth having a function to change it later
    uint8 public constant multisigThreshold = 60;

    uint256 public nonceAddSigner = 0;
    uint256 public nonceRemoveSigner = 0;

    // We need this event to log the username for unwrapping
    event Unwrap(address messenger, uint64 amount, string username);

    constructor()
        ERC20("Wrapped HBD (hive.io)", "wHBD")
        ERC20Permit("Wrapped HBD (hive.io)")
    {
        address smarttrailAddress = address(
            0xaDED1170927F2f3a7DC6868Ecc19488e0d9472D3
        );
        signers.push(smarttrailAddress);
        signerNames[smarttrailAddress] = "smarttrail";
    }

    // For testing - later enable multisig for more testing
    function startMultisig(bytes memory signature) public {
        bytes32 msgHash = keccak256(
            abi.encodePacked("startMultisig", ";", address(this))
        );
        if (_recoverSigner(msgHash, signature) == signers[0]) {
            multisig = true;
        }
    }
 
    // Add a new signer
    function addSigner(
        address addr,
        string memory username,
        bytes[] memory signatures
    ) public {
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                addr,
                ";",
                username,
                ";",
                nonceAddSigner,
                ";",
                address(this)
            )
        );
        if (multisig) {
            if (_validateSignatures(msgHash, signatures)) {
                if (_isSigner(addr)) {
                    return;
                }
                signers.push(addr);
                signerNames[addr] = username;
                nonceAddSigner++;
            }
        } else {
            // we can remove this after testing
            for (uint256 i = 0; i < signatures.length; i++) {
                address signer = _recoverSigner(msgHash, signatures[i]);
                if (signers[0] == signer) {
                    if (_isSigner(addr)) {
                        return;
                    }
                    signers.push(addr);
                    signerNames[addr] = username;
                    nonceAddSigner++;
                }
            }
        }
    }

    function removeSigner(address addr, bytes[] memory signatures) public {
        bytes32 msgHash = keccak256(
            abi.encodePacked(addr, ";", nonceRemoveSigner, ";", address(this))
        );
        if (multisig) {
            if (_validateSignatures(msgHash, signatures)) {
                if (!_isSigner(addr)) {
                    return;
                }
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
        } else {
            // we can remove this after testing
            for (uint256 i = 0; i < signatures.length; i++) {
                address signer = _recoverSigner(msgHash, signatures[i]);
                if (signers[0] == signer) {
                    if (!_isSigner(addr)) {
                        return;
                    }
                    delete signerNames[addr];
                    for (uint256 k = 0; k < signers.length; k++) {
                        if (signers[k] == addr) {
                            // replace with last
                            signers[k] = signers[signers.length - 1];
                            // remove last
                            signers.pop();
                            break;
                        }
                    }
                    nonceRemoveSigner++;
                }
            }
        }
    }

    /// Provide the hive amount (no decimals), blocknum, and signatures
    function wrap(
        uint64 amount,
        uint32 blockNum,
        bytes[] memory signatures
    ) public {
        if (canWrap(amount, blockNum, signatures)) {
            hasMinted[_msgSender()][blockNum] = true;
            return _mint(_msgSender(), amount);
        }
    }

    function canWrap(uint64 amount, uint32 blockNum, bytes[] memory signatures) public view returns (bool) {
        require(
            !hasMinted[_msgSender()][blockNum],
            "Already minted with this blockNum"
        );
        // hash (minter;amount;blocknum;contract)
        if (hasMinted[_msgSender()][blockNum]) {
            return false;
        }
        bytes32 msgHash = _hash(_msgSender(), amount, blockNum);
        if (multisig) {
            if (_validateSignatures(msgHash, signatures)) {
                return true;
            }
        } else {
            // we can remove this part after testing
            // validates only the first added signer
            for (uint256 i = 0; i < signatures.length; i++) {
                address signer = _recoverSigner(msgHash, signatures[i]);
                if (signers[0] == signer) {
                    return true;
                }
            }
        }
        return false;
    }

    // Burn the tokens and emit an Unwrap event that will be picked up by the bridge nodes
    function unwrap(uint64 amount, string memory username) public {
        uint256 len = bytes(username).length;
        require(len >= 3 && len <= 16, "Username must be 3-16 characters long");
        _burn(_msgSender(), amount);
        emit Unwrap(_msgSender(), amount, username);
    }

    /// HIVE decimals is 3
    function decimals() public view virtual override returns (uint8) {
        return 3;
    }

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
        uint256 signerCount = signers.length;
        // (20 * 60 + 99 / 100) = 12
        uint256 threshold = (signerCount * multisigThreshold + 99) / 100;
        uint256 validSignatures;
        address[] memory seen = new address[](signerCount);
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
                if (validSignatures >= threshold) {
                    return true;
                }
            }
        }
        return false;
    }

    // Is the address a registered signer?
    function _isSigner(address addr) internal view returns (bool) {
        return bytes(signerNames[addr]).length > 0;
        // for (uint256 i = 0; i < signers.length; i++) {
        //     if (signers[i] == addr) {
        //         return true;
        //     }
        // }
        // return false;
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

    /// Split a signature to v,r,s
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

    function _hash(
        address minter,
        uint64 amount,
        uint32 blockNum
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    minter,
                    ";",
                    amount,
                    ";",
                    blockNum,
                    ";",
                    address(this)
                )
            );
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.11;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';

/// @notice Token already minted.
error DuplicateMint();

/// @notice Source address does not own the NFT.
error InvalidOwner();

/// @notice Receiving contract does not implement the ERC721 wallet interface.
error InvalidReceiver();

/// @notice Destination address is the zero address, which is invalid.
error InvalidRecipient();

/// @notice NFT does not exist.
error NonExistentNFT();

/// @notice NFT collection has hit maximum supply capacity.
error SupplyMaxCapacity();

/// @notice Sender is not NFT owner, approved address, or owner operator.
error UnauthorizedSender();

/// @title Bit Louie ERC721 base contract
/// @notice ERC-721 contract with metadata extension and capped supply.
/// @dev The contract also contains components needed for EIP-712 signing.
abstract contract ERC721 is IERC721, IERC721Metadata {

    /// @notice Count of NFTs in circulation.
    uint256 public totalSupply;

    /// @notice Maximum supply allowed for the NFT collection.
    uint256 public immutable maxSupply;

    /// @notice Name of the NFT collection.
    string public name;

    /// @notice Abbreviated name of the NFT collection.
    string public symbol;

    /// @notice Gets the number of NFTs owned by a particular address.
    /// @dev To save gas, zero address queries do not throw (returns 0 instead).
    /// @return The number of NFTs owned by an address.
    mapping(address => uint256) public balanceOf

    /// @notice Retrieves the assigned owner of an NFT.
    /// @dev Non-existent NFTs have the zero address assigned as their owner.
    /// @return Address owning the NFT (if it exists), zero address otherwise.
    mapping(uint256 => address) public ownerOf;

    /// @notice Gets the approved address of an NFT.
    /// @dev To save gas, queries for non-existent NFTs do not throw.
    /// @return NFT's approved address, or the zero address if there is none.
    mapping(uint256 => address) public getApproved;

    /// @notice Checks if an address is an authorized operator for an owner.
    /// @return True if the address is an authorized operator, false otherwise.
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /// @notice EIP-712 structures used for hashing & signing.
    uint256 internal immutable _CHAIN_ID;
    bytes32 internal immutable _DOMAIN_SEPARATOR;
    mapping(address => uint256) public nonces;

    /// @notice EIP-165 identifiers for all supported interfaces.
    bytes4 private constant _ERC165_INTERFACE_ID = 0x01ffc9a7;
    bytes4 private constant _ERC721_INTERFACE_ID = 0x80ac58cd;
    bytes4 private constant _ERC721_METADATA_INTERFACE_ID = 0x5b5e139f;

    /// @dev Parameters may only be set once.
    /// @param _name      Name of the NFT collection.
    /// @param _symbol    Abbreviated name of the NFT collection.
    /// @param _maxSupply Max supply allowed for the NFT collection.
    constructor(string memory _name, string memory _symbol, uint256 _maxSupply) {
        name = _name;
        symbol = _symbol;

        _CHAIN_ID = block.chainid;
        _DOMAIN_SEPARATOR = _buildDomainSeparator();
    }

    /// @notice Transfers ownership of NFT `id` from `from` to `to`, without
    ///  safety checks on whether `to` is capable of receiving NFTs.
    /// @dev This implementation does not explicitly check if the NFT exists,
    ///  since any non-existent NFTs would not have an associated owner anyway.
    ///  Approval event omitted as Transfer events indicate approval clearance.
    /// @param from The current owner of the NFT
    /// @param to The new owner of the NFT
    /// @param id The NFT transferred
    function transferFrom(address from, address to, uint256 id) public virtual {
        address owner = ownerOf[id];
        if (from != owner) {
            revert InvalidOwner();
        }
        
        if (msg.sender != from && msg.sender != getApproved[id] && !isApprovedForAll) {
            revert UnauthorizedSender();
        }

        if (to == address(0)) {
            revert InvalidRecipient();
        }

        delete getApproved[id];

        unchecked {
            balanceOf[from]--;
            balanceOf[to]++;
        }

        ownerOf[id] = to;
        emit Transfer(from, to, id);
    }

    /// @notice Transfers ownership of NFT `id` from `from` to `to`, with
    ///  safety checks ensuring `to` is capable of receiving NFTs.
    /// @param from The current owner of the NFT
    /// @param to The new owner of the NFT
    /// @param id The NFT transferred
    /// @param data Additional data to be sent to `to`
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes memory data
    ) public virtual {
        transferFrom(from, to, id);

        if (to.code.length != 0 && IERC721Receiver(to).onERC721Received(msg.sender, from, data) != IERC721Receiver.onERC721Received.selector) {
            revert InvalidReceiver();
        }
    }

    /// @notice Transfers ownership of NFT `id` from `from` to `to`, with
    ///  safety checks ensuring `to` is capable of receiving NFTs.
    /// @dev This function is equivalent to the previous, with data set to "".
    /// @param from The current owner of the NFT
    /// @param to The new owner of the NFT
    /// @param id The NFT transferred
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual {
        transferFrom(from, to, id);

        if (to.code.length != 0 && IERC721Receiver(to).onERC721Received(msg.sender, from, "") != IERC721Receiver.onERC721Received.selector) {
            revert InvalidReceiver();
        }
    }


    /// @notice Sets the approved address of NFT `id` to `approved`.
    /// @dev The zero address indicates an NFT has no approved address.
    /// @param approved The new approved address for the NFT
    /// @param id The NFT to approve
    function approve(address approved, uint256 id) public virtual {
        address owner = ownerOf[tokenId];

        if (msg.sender != owner && !isApprovedForAll[owner][msg.sender]) {
            revert UnauthorizedSender();
        }

        getApproved[id] = approved;

        emit Approval(owner, spender, id);
    }

    /// @notice Sets the operator for `msg.sender` to `operator`.
    /// @param operator The operator that will manage the sender's NFTs
    /// @param approved Whether the operator is allowed to operate sender's NFTs
    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @notice Checks if interface of identifier `interfaceId` is supported.
    /// @param interfaceId Interface's ERC-165 identifier 
    /// @return `true` if `interfaceId` is supported, `false` otherwise.
    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return
            interfaceId == _ERC165_INTERFACE_ID ||
            interfaceId == _ERC721_INTERFACE_ID ||
            interfaceId == _ERC721_METADATA_INTERFACE_ID;
    }

    /// @notice Mints NFT `id` to address `to`.
    /// @dev Saves gas assuming maxSupply < type(uint256).max for unchecked ops.
    ///  Transfer events indicate approval clearance (Approval not emitted).
    /// @param to Address receiving the minted NFT
    /// @param id NFT being minted
    function _mint(address to, uint256 id) internal virtual {
        if (to == address(0)) {
            revert InvalidRecipient();
        }
        if (ownerOf[id] != address(0)) {
            revert DuplicateMint();
        }
        unchecked {
            totalSupply++;
            balanceOf[to]++;
        }
        if (totalSupply > maxSupply) {
            revert SupplyMaxCapacity();
        }
        ownerOf[id] = to;
        emit Transfer(address(0), to, id);
    }

    /// @notice Burns NFT `id`, making it permanently non-existent.
    /// @dev Transfer events indicate approval clearance (Approval not emitted).
    /// @param id NFT being burned
    function _burn(uint256 id) internal virtual {
        address owner = ownerOf[id];

        if (owner == address(0)) {
            revert NonExistentNFT();
        }

        unchecked {
            totalSupply--;
            balanceOf[owner]--;
        }

        delete ownerOf[id];
        emit Transfer(owner, adderss(0), id);
    }

    /// @notice Generates a domain separator for making signatures unique.
    /// @dev See https://eips.ethereum.org/EIPS/eip-712 for details.
    /// @return A 256-bit domain separator.
	function _buildDomainSeparator() internal view returns (bytes32) {
		return keccak256(
			abi.encode(
				keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
				block.chainid,
				address(this)
			)
		);
	}

    /// @notice Returns the domain separator tied to the contract.
    /// @dev Recreated if chain id changes, otherwise a cached value is used.
    /// @return 256-bit domain separator tied to this contract.
    function _domainSeparator() internal view virtual returns (bytes32) {
        if (block.chainid == _CHAIN_ID) {
            return _DOMAIN_SEPARATOR;
        } else {
            return _buildDomainSeparator();
        }
    }

    /// @notice Returns an EIP-712 encoding of structured data `structHash`.
    /// @param structHash The structured data to be encoded and signed.
    /// @return A bytestring suitable for signing in accordance to EIP-712.
    function _hashTypedData(bytes32 structHash) internal view virtual returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
    }


}

// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

import "src/test/mocks/MockERC721.sol";
import "src/test/mocks/MockERC721Receiver.sol";

import "src/test/utils/Test.sol";

/// @title ERC721 Test Suites
contract ERC721Test is Test {

    bytes4 constant RECEIVER_MAGIC_VALUE = 0x150b7a02;

    uint256 constant NFT = 0;
    uint256 constant NONEXISTENT_NFT = 99;

    address constant FROM = address(1337);
    address constant TO = address(69);
    address constant OPERATOR = address(420);

    MockERC721 token;

    /// @notice ERC-721 emitted events.
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /// @notice Event emitted to test ERC721 Receiver behavior.
    event ERC721Received(address operator, address from, uint256 tokenId, bytes data);

    /// @notice Used for subtests that modify state.
    modifier reset {
        _;
        setUp();
    }

    /// @dev All tests revolve around premise of `NFT` originating from `FROM`.
    function setUp() public {
        token = new MockERC721("Mock Token", "MT", 10);
        token.mint(FROM, NFT);
        vm.startPrank(FROM);
    }

    function testConstructor() public {
        assertEq(token.maxSupply(), 10);
        assertEq(token.name(), "Mock Token");
        assertEq(token.symbol(), "MT");
    }

    function testBalanceOf() public {
        assertEq(token.balanceOf(FROM), 1);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);

        token.mint(FROM, NFT + 1);
        assertEq(token.balanceOf(FROM), 2);

        token.burn(NFT);
        assertEq(token.balanceOf(FROM), 1);
    }

    function testOwnerOf() public {
        token.transferFrom(FROM, TO, NFT);
        assertEq(token.ownerOf(NFT), TO);

        token.burn(NFT);
        assertEq(token.ownerOf(NFT), address(0));
    }

    function testGetApproved() public {
        assertEq(token.getApproved(NONEXISTENT_NFT), address(0));
        assertEq(token.getApproved(NFT), address(0)); // Unapproved NFT

        token.approve(OPERATOR, NFT); 
        assertEq(token.getApproved(NFT), OPERATOR); // Approved NFT

        token.approve(address(0), NFT);
        assertEq(token.getApproved(NFT), address(0)); // NFT approval cleared
    } 

    function testApprove() public {
        // Approval succeeds when owner approves.
        vm.expectEmit(true, true, true, true);
        emit Approval(FROM, OPERATOR, NFT);
        token.approve(OPERATOR, NFT);
        assertEq(token.getApproved(NFT), OPERATOR);

        // Approvals fail when invoked by the unauthorized address.
        vm.prank(OPERATOR);
        expectRevert("UnauthorizedSender()");
        token.approve(OPERATOR, NFT);

        // Approvals succeed when executed by the authorized operator.
        token.setApprovalForAll(OPERATOR, true);
        vm.prank(OPERATOR);
        vm.expectEmit(true, true, true, true);
        emit Approval(FROM, OPERATOR, NFT);
        token.approve(OPERATOR, NFT);
        assertEq(token.getApproved(NFT), OPERATOR);
    }

    function testIsApprovedForAll() public {
        assertTrue(!token.isApprovedForAll(FROM, OPERATOR));

        vm.startPrank(FROM);
        token.setApprovalForAll(OPERATOR, true);
        assertTrue(token.isApprovedForAll(FROM, OPERATOR));

        token.setApprovalForAll(OPERATOR, false);
        assertTrue(!token.isApprovedForAll(FROM, OPERATOR));
    }

    function testSetApprovalForAll() public {
        vm.expectEmit(true, true, true, true);
        emit ApprovalForAll(FROM, OPERATOR, true);
        token.setApprovalForAll(OPERATOR, true);
        assertTrue(token.isApprovedForAll(FROM,OPERATOR));

        vm.expectEmit(true, true, true, true);
        emit ApprovalForAll(FROM, OPERATOR, false);
        token.setApprovalForAll(OPERATOR, false);
        assertTrue(!token.isApprovedForAll(FROM,OPERATOR));
    }

    function testSupportsInterface() public {
        assertTrue(token.supportsInterface(0x01ffc9a7)); // ERC165
        assertTrue(token.supportsInterface(0x80ac58cd)); // ERC721
        assertTrue(token.supportsInterface(0x5b5e139f)); // ERC721Metadata
    }

    function testSafeTransferFromBehavior() public {
        _testSafeTransferBehavior(token.safeTransferFromWithoutData, "");
        _testSafeTransferBehavior(token.safeTransferFromWithData, token.DATA());
    }

    function testTransferFromBehavior() public {
        _testTransferBehavior(token.transferFrom, TO);
        _testTransferBehavior(token.safeTransferFromWithoutData, TO);
    }

    function _testSafeTransferBehavior(
        function(address, address, uint256) external fn,
        bytes memory data
    ) internal {
        // Transferring to a contract
        _testSafeTransferFailure(fn);
        _testSafeTransferSuccess(fn, data);
    }

  	function _testSafeTransferFailure(function(address, address, uint256) external fn) internal {
        // Should throw when receiver magic value is invalid.
        MockERC721Receiver invalidReceiver = new MockERC721Receiver(0xDEADBEEF, false);
        expectRevert("InvalidReceiver()");
        fn(FROM, address(invalidReceiver), NFT);

        // Should throw when receiver function throws.
        invalidReceiver = new MockERC721Receiver(RECEIVER_MAGIC_VALUE, true);
        expectRevert("Throwing()");
        fn(FROM, address(invalidReceiver), NFT);

        // Should throw when receiver function is not implemented.
        vm.expectRevert("");
        fn(FROM, address(this), NFT);
    }

    function _testSafeTransferSuccess(
        function(address, address, uint256) external fn,
        bytes memory data
    ) internal reset {
        MockERC721Receiver validReceiver = new MockERC721Receiver(RECEIVER_MAGIC_VALUE, false);
        vm.expectEmit(true, true, true, true);
        emit ERC721Received(FROM, FROM, NFT, data);
        fn(FROM, address(validReceiver), NFT);

        assertEq(token.ownerOf(NFT), address(validReceiver));
    }

    function _testTransferBehavior(function(address, address, uint256) external fn, address to) internal {
        // Test transfer failure conditions.
        _testTransferFailure(fn, to); 
        
        // Test normal transfers invoked via owner.
        _testTransferSuccess(token.transferFrom, FROM, to);

        // Test transfers through an approved address.
        token.approve(OPERATOR, NFT);
        _testTransferSuccess(token.transferFrom, OPERATOR, to);

        // Test transfers through an authorized operator.
        token.setApprovalForAll(OPERATOR, true);
        _testTransferSuccess(token.transferFrom, OPERATOR, to);
    }

    function _testTransferFailure(function(address, address, uint256) external fn, address to) internal {
        expectRevert("ZeroAddressReceiver()");

        fn(FROM, address(0), NFT);

        expectRevert("InvalidOwner()");
        fn(to, to, NFT);

        vm.prank(TO);
        expectRevert("UnauthorizedSender()");
        fn(FROM, to, NFT);
    }

    /// @dev Test successful transfer of `NFT` from `FROM` to `to`,
    ///  with `sender` as the transfer originator.
    function _testTransferSuccess(
        function(address, address, uint256) external fn,
        address sender,
        address to
    ) 
        internal reset
    {
        vm.expectEmit(true, true, true, true);
        emit Transfer(FROM, to, NFT);
        vm.prank(sender);
        token.transferFrom(FROM, to, NFT);

        if (to != FROM) {
            assertEq(0, token.balanceOf(FROM));
            assertEq(1, token.balanceOf(to));
        } else {
            assertEq(2, token.balanceOf(FROM));
        }

        assertEq(token.getApproved(NFT), address(0)); // Clear approvals
        assertEq(token.ownerOf(NFT), to);
    }

}

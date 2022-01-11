// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

import "src/ERC721.sol";

contract MockERC721 is ERC721 {

    bytes public constant DATA = "Bit Louie";

    constructor(string memory _name, string memory _symbol, uint256 _maxSupply)
        ERC721(_name, _symbol, _maxSupply) {}

    function tokenURI(uint256 id) public pure virtual override returns (string memory) {}

    function mint(address to, uint256 id) public virtual {
        _mint(to, id);
    }

    function burn(uint256 id) public virtual {
        _burn(id);
    }

    function safeTransferFromWithoutData(
        address from,
        address to,
        uint256 id
    ) external {
        safeTransferFrom(from, to, id);
    }

    function safeTransferFromWithData(
        address from,
        address to,
        uint256 id
    ) external {
        safeTransferFrom(from, to, id, DATA);
    }
}

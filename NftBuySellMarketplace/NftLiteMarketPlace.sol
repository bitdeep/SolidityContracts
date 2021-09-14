// SPDX-License-Identifier: MIT
/**
Copyright 2021 <vlad, twitter.com/VladFinance, t.me/VladFinanceOfficial>
Copyright 2021 <bitdeep, twitter.com/bitdeep_oficial, t.me/bitdeep>

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
OR OTHER DEALINGS IN THE SOFTWARE.

// 2020 - PancakeSwap Team - https://pancakeswap.com
// 2021 - bitdeep, twitter.com/bitdeep_oficial, t.me/bitdeep
// 2021, Vlad Team, t.me/VladFinanceOfficial, https://vlad.finance/

**/

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./INFTLite.sol";
import "./IBEP20.sol";
import "./SafeBEP20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./AddrArrayLib.sol";
import "./Uint256ArrayLib.sol";
import "./Uint8ArrayLib.sol";
import "./StringArrayLib.sol";

pragma experimental ABIEncoderV2;
pragma solidity ^0.6.12;

contract NftLiteMarketPlace is Ownable, ReentrancyGuard {
    using SafeMath for uint8;
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    using AddrArrayLib for AddrArrayLib.Addresses;
    using Uint256ArrayLib for Uint256ArrayLib.Values;
    using Uint8ArrayLib for Uint8ArrayLib.Values;
    using StringArrayLib for StringArrayLib.Values;

    struct NftInfo {
        uint256 floorPrice;
        uint256 fee;
        INFTLite nft;
        IBEP20 token;
    }

    struct NftSell {
        uint256 orderId;
        uint256 tokenId;
        address user;
        uint256 price;
    }

    address[] public nftIndex;
    mapping(address => NftInfo) public nftInfo;
    mapping(address => Uint256ArrayLib.Values) private ordersByNft;
    mapping(address => Uint256ArrayLib.Values) private tokenIdToSell;
    mapping(uint256 => NftSell) private sellsByOrderId;
    uint256 orderIndex;
    address feeAddress;
    uint256 platformFee;
    constructor() public {
        feeAddress = msg.sender;
        platformFee = 1000; // 10%
    }
    function adminSetFeeAddress(address _feeAddress) external onlyOwner {
        feeAddress = _feeAddress;
    }
    function adminSetPlatformFee(address _platformFee) external onlyOwner {
        platformFee = _platformFee;
    }

    function sell(address _nft, uint256 _tokenId, uint256 _price) public {
        NftInfo storage NFT = nftInfo[_nft];
        INFTLite nft = NFT.nft;
        require(msg.sender == nft.ownerOf(_tokenId), "not owner");
        require(_price >= NFT.floorPrice, "price too low");
        ordersByNft[_nft].pushValue(orderIndex);
        tokenIdToSell[_nft].pushValue(_tokenId);
        NftSell sell = sellsByOrderId[orderIndex];
        sell.orderId = orderIndex;
        sell.tokenId = _tokenId;
        sell.user = msg.sender;
        sell.price = _price;
        orderIndex = orderIndex.add(1);
        // require(nft.isApprovedForAll(msg.sender, address(this)),"not approved to sell");
    }
    function buy(address _nft, uint256 _tokenId, uint256 _orderId) public{
        NftInfo storage NFT = nftInfo[_nft];
        INFTLite nft = NFT.nft;
        IBEP20 token = NFT.token;
        NftSell sell = sellsByOrderId[_orderId];
        uint256 fee = sell.price.mul(platformFee).div(10000);
        uint256 amount = price.sub(fee);
        token.safeTransferFrom(address(msg.sender), feeAddress, fee);
        token.safeTransferFrom(address(msg.sender), sell.user, amount);
        nft.safeTransferFrom(sell.user, address(msg.sender), _tokenId);
    }
    function isApproved( address user, address nft ) public view returns(bool){
        INFTLite nft = NFT.nft;
        return nft.isApprovedForAll(user, nft);
    }
    function add(address _nft, address _token,
        uint256 _floorPrice, uint256 _fee,
        string memory _authorName, string memory _authorTwitter)
    external
    mintingManagers
    {
        NftInfo storage NFT = nftInfo[_nft];
        nftIndex.push(_nft);
        NFT.nft = INFTLite(_nft);
        NFT.token = IBEP20(_token);
        NFT.floorPrice = _floorPrice;
        NFT.fee = _fee;
        NFT.authorName = _authorName;
        NFT.authorTwitter = _authorTwitter;
    }

    function set(address _nft, address _token,
        uint256 _floorPrice, uint256 _fee,
        string memory _authorName, string memory _authorTwitter)
    external
    mintingManagers
    {
        NftInfo storage NFT = nftInfo[_nft];
        NFT.token = IBEP20(_token);
        NFT.floorPrice = _floorPrice;
        NFT.fee = _fee;
        NFT.authorName = _authorName;
        NFT.authorTwitter = _authorTwitter;
    }

    modifier mintingManagers(){
        require(mintingManager[_msgSender()] == true, "not manager");
        _;
    }
    function _transfer(address nft, address to, uint256 tokenId) internal {
        NftInfo storage NFT = nftInfo[nft];
        NFT.nft.safeTransferFrom(msg.sender, to, tokenId);
    }
}

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
import "./INFT.sol";
import "./IBEP20.sol";
import "./SafeBEP20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./AddrArrayLib.sol";
import "./Uint256ArrayLib.sol";
import "./Uint8ArrayLib.sol";
import "./StringArrayLib.sol";

pragma experimental ABIEncoderV2;
pragma solidity ^0.6.12;

contract NftMarketplace is Ownable, ReentrancyGuard {
    using SafeMath for uint8;
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    using AddrArrayLib for AddrArrayLib.Addresses;
    using Uint256ArrayLib for Uint256ArrayLib.Values;
    using Uint8ArrayLib for Uint8ArrayLib.Values;
    using StringArrayLib for StringArrayLib.Values;

    INFT public nft;    // default platform nft
    IBEP20 public token;// default platform payment token

    // global stats
    uint256 totalMint; // total of all mints
    uint256 totalBurn; // total of all burns
    uint256 totalTokensCollected; //amount of tokens received
    uint256 totalTokensRefunded; //amount of tokens refunded to users on burn
    uint256 totalPaidToAuthors; //amount of tokens sent to nft authors

    uint8[] public minted; // array of nft minted, unique, added on first mint only.
    mapping(uint8 => AddrArrayLib.Addresses) private ownersOf; // wallets by nftId

    // can manage price and limits
    mapping(address => bool) public mintingManager;

    // fee & payment management
    struct PlatformFees {
        uint256 authorFee; // 30%
        uint256 govFee; // 15%
        uint256 devFee;  //  5%

        uint256 marketAuthorFee; // 30%
        uint256 marketGovFee; // 15%
        uint256 marketDevFee;  //  5%
    }

    PlatformFees platformFees;

    // artist management
    struct PlatformAddresses {
        address govFeeAddr;
        address devFeeAddr;
    }

    PlatformAddresses platformAddresses;

    struct NftInfo {
        uint8 nftId;
        address author; // nft artist/owner, who get paid
        uint256 authorFee; // fee to pay to author of this nft
        bool allowMng; // allow owner to manage this nft
        uint256 authorId; // unique id for this author
        string authorName; // author name (string)
        string authorTwitter; // author twitter account ie (@test)
        string rarity;
        string uri;
        uint256 startBlock; // only allow mint after this block
        uint256 endBlock;   // only allow mint before this block
        uint256 status;     // use to: 0=inactive, 1=active, 2=auction
    }

    struct NftInfoState {
        uint8 nftId;
        uint256 price;      // default price
        uint256 maxMint;    // max amount of nft to be minted
        uint256 multiplier; // factor, to enable price curve
        uint256 rarityId;   // unique id for this rarity
        uint256 minted;     // amount minted
        uint256 lastMint;   // timestamp of last minted
        uint256 burned;     // amount burned
        uint256 lastBurn;   // timestamp of last burn
        address lastOwner;  // last one that minted this nft
        INFT nft;          // mint/burn this nft
        IBEP20 token;      // buy/sell using this token (AfterLife, WBNB, BUSD)
    }

    // global index of each trade
    uint256 tradeIdPool;

    // array of all nft added
    uint256[] public nftIndex;
    // basic nft info to display
    mapping(uint8 => NftInfo) public nftInfo;
    // state info, like minting, minted, burned
    mapping(uint8 => NftInfoState) public nftInfoState;
    // list of all nft minting by nft id
    mapping(uint8 => uint256[]) private listOfTradesByNftId;

    // primary trade info
    struct NftTradeInfo {
        uint8 nftId; // store the market place id (comes from admin)
        uint256 tokenId; // store token id (comes from token)
        uint256 tradeId; // store trade id (sequence generated here)
        address owner;
        uint256 price;
        uint256 artistFee;
        uint256 governanceFee;
        uint256 devFee;
        uint256 reserve;
        uint256 mintedIn;
        uint256 burnedIn;
    }

    mapping(uint256 => NftTradeInfo) private nftTrade; // store all trades by tradeId
    mapping(uint8 => mapping(address => Uint256ArrayLib.Values)) private nftTradeByUser; // store all trades by user
    mapping(uint8 => mapping(address => Uint256ArrayLib.Values)) private nftBurnsByUser; // store all trades by user
    mapping(address => Uint8ArrayLib.Values) private nftIdByUser; // store all nftId by user

    struct NftSecondaryMarket {
        uint8 nftId;
        bool allowSell;   // allow owner to sell this nft
        uint256 sellMinPrice; // min price allowed to sell

        // global secondary market stats
        uint256 totalArtistFee; // total fee paid to this artist
        uint256 totalGovernanceFee; // total fee collected to governance
        uint256 totalDevFee; // total fee collected to dev fund
        uint256 qtdSells; // qtd of sells made
        uint256 totalCollected; // amount of token collected
        uint256 lastSellPrice; // last seel price
        uint256 lastSellIn; // last sell date
    }

    mapping(uint8 => NftSecondaryMarket) public nftSecondaryMarket;
    mapping(uint8 => Uint256ArrayLib.Values) private listOfOpenSells; // list of open sells

    // secondary trade info
    struct NftSecondaryTradeInfo {
        uint256 sellPrice; // price user want to sell
        uint256 sellDate; // when order added
        uint256 soldDate; // price sold
    }

    mapping(uint256 => NftSecondaryTradeInfo) public nftSecondaryTradeInfo;

    event NewNftAuctionMarket(uint8 indexed nftId, uint256 minBid, uint256 blockStart);
    event NewNftBid(uint8 indexed nftId, uint256 bid, address indexed user);
    event AuctionWin(uint8 indexed nftId, uint256 bid, address indexed user);
    event AuctionEnd(uint8 indexed nftId, address indexed user);

    struct NftAuctionMarket {
        uint8 nftId;
        bool allowAuction;
        uint256 minBid;
        uint256 blockStart;
        uint256 blockEnd;
        uint256 priceStep; // % min price increment on each bid, ex: 10=0.1%, 100=1%
        uint256 entryFee; // a fee to join the auction (one time only)
        uint256 bidFee; // $ fee to be paid on each bid (to prevent spam), ex: 10=0.1%, 100=1%
        uint256 lastBid;
        uint256 bidFeeCollected;
        uint16 state; // 0 inactive, 1 open, 2 completed
        uint256 auctionLimit;
        uint256 auctionCount;
    }

    mapping(uint8 => NftAuctionMarket) public nftAuctionMarket;
    mapping(uint8 => Uint256ArrayLib.Values) private auctionBid;

    // filters
    mapping(string => uint8[]) private listOfNftByRarity;
    mapping(string => uint8[]) private listOfNftByAuthor;

    mapping(string => uint256) private authorIdByName;
    mapping(string => uint256) private rarityIdByName;
    StringArrayLib.Values private listOfAuthors;
    StringArrayLib.Values private listOfRarity;

    // events
    event NftAdded(uint8 indexed nftId, address indexed author, uint256 startBlock, uint256 endBlock);
    event NftChanged(uint8 indexed nftId, address indexed author, uint256 startBlock, uint256 endBlock);
    event NftStateAdded(uint8 indexed nftId, uint256 price, uint256 multiplier);

    event NftMint(address indexed to, uint256 indexed tokenId, uint8 indexed nftId, uint256 amount, uint256 price);
    event NftBurn(address indexed from, uint256 indexed tokenId);
    event NftTransfer(address indexed from, address indexed to, uint256 indexed tradeId);

    constructor(address _nft, address _token) public {

        nft = INFT(_nft);
        token = IBEP20(_token);
        mintingManager[msg.sender] = true;

        // all fee wallets defaults to deployer, must be changed later.
        platformAddresses.govFeeAddr = msg.sender;
        platformAddresses.devFeeAddr = msg.sender;

        platformFees.authorFee = 3000;
        // 30%
        platformFees.govFee = 1500;
        // 15%
        platformFees.devFee = 500;
        //  5%

        platformFees.marketAuthorFee = 3000;
        // 30%
        platformFees.marketGovFee = 1500;
        // 15%
        platformFees.marketDevFee = 500;
        //  5%

    }

    function getOwnersOf(uint8 _nftId) public view returns (address[] memory){
        return ownersOf[_nftId].getAllAddresses();
    }

    function getTotalOfOwners(uint8 _nftId) public view returns (uint256){
        return ownersOf[_nftId].getAllAddresses().length;
    }

    function getMinted(address _user) external view returns
    (uint8[] memory, uint256[] memory, uint256[] memory){
        uint256 total = minted.length;
        uint256[] memory mintedAmounts = new uint256[](total);
        uint256[] memory myMints = new uint256[](total);

        for (uint256 index = 0; index < total; ++index) {
            uint8 nftId = minted[index];
            NftInfoState storage NftState = nftInfoState[nftId];
            mintedAmounts[index] = NftState.minted;
            myMints[index] = getMintsOf(_user, nftId);
        }
        return (minted, mintedAmounts, myMints);
    }

    // get total mints of a nft filtered by user
    function getMintsOf(address user, uint8 _nftId) public view returns (uint256) {
        address[] memory _ownersOf = getOwnersOf(_nftId);
        uint256 total = _ownersOf.length;
        uint256 mints = 0;
        for (uint256 index = 0; index < total; ++index) {
            if (_ownersOf[index] == user) {
                mints = mints.add(1);
            }
        }
        return mints;
    }

    function getPrice(uint8 _nftId, uint256 _minted) public view returns (uint256){
        NftInfoState storage NFT = nftInfoState[_nftId];
        uint256 price = NFT.price;
        if (_minted == 0) {
            return price;
        }
        if (NFT.multiplier > 0) {
            // price curve by m-dot :)
            for (uint256 i = 0; i < _minted; ++i) {
                price = price.mul(NFT.multiplier).div(1000000);
            }
        }
        return price;
    }


    function mint(uint8 _nftId) external nonReentrant {
        NftInfo storage NFT = nftInfo[_nftId];
        NftInfoState storage NftState = nftInfoState[_nftId];
        require(NftState.nftId > 0, "NFT not available");
        require(NFT.status > 0, "nft disabled");
        require(NFT.startBlock == 0 || block.number > NFT.startBlock, "Too early");
        require(NFT.endBlock == 0 || block.number < NFT.endBlock, "Too late");
        _mint(_nftId);
    }

    function _mint(uint8 _nftId) internal {
        NftInfo storage NFT = nftInfo[_nftId];
        NftInfoState storage NftState = nftInfoState[_nftId];

        if (NftState.minted == 0) {
            minted.push(_nftId);
            NftState.nft.setNftName(_nftId, NFT.rarity);
        }

        NftState.lastOwner = msg.sender;
        NftState.lastMint = block.timestamp;
        NftState.price = getPrice(_nftId, 1);
        NftState.minted = NftState.minted.add(1);

        require(NftState.maxMint == 0 || NftState.minted <= NftState.maxMint, "Max minting reached");

        ownersOf[_nftId].pushAddress(msg.sender, true);

        // we increment before, then we can check if index is != 0
        tradeIdPool = tradeIdPool.add(1);
        // we finished here, increment trade index by i

        uint256[] storage tradesByNftId = listOfTradesByNftId[_nftId];
        tradesByNftId.push(tradeIdPool);

        NftTradeInfo storage TRADE = nftTrade[tradeIdPool];
        // tradeId eg 0
        TRADE.tradeId = tradeIdPool;
        TRADE.nftId = _nftId;
        TRADE.owner = msg.sender;
        TRADE.tokenId = NftState.nft.mint(address(msg.sender), NFT.uri, _nftId);

        TRADE.mintedIn = block.timestamp;
        TRADE.price = NftState.price;
        if (NFT.authorFee == 0) {
            TRADE.artistFee = TRADE.price.mul(platformFees.authorFee).div(10000);
        } else {
            TRADE.artistFee = TRADE.price.mul(NFT.authorFee).div(10000);
        }
        TRADE.governanceFee = TRADE.price.mul(platformFees.govFee).div(10000);
        TRADE.devFee = TRADE.price.mul(platformFees.devFee).div(10000);
        TRADE.reserve = TRADE.price.sub(TRADE.artistFee).sub(TRADE.governanceFee).sub(TRADE.devFee);

        NftState.token.safeTransferFrom(address(msg.sender), NFT.author, TRADE.artistFee);
        NftState.token.safeTransferFrom(address(msg.sender), platformAddresses.govFeeAddr, TRADE.governanceFee);
        NftState.token.safeTransferFrom(address(msg.sender), platformAddresses.devFeeAddr, TRADE.devFee);
        NftState.token.safeTransferFrom(address(msg.sender), address(this), TRADE.reserve);

        totalMint = totalMint.add(1);
        totalTokensCollected = totalTokensCollected.add(NftState.price);
        totalPaidToAuthors = totalPaidToAuthors.add(TRADE.artistFee);


        // add this id of user minted nfts (only once)
        nftIdByUser[msg.sender].pushValue(_nftId);

        // store trades for this user
        nftTradeByUser[_nftId][msg.sender].pushValue(TRADE.tradeId);

        emit NftMint(msg.sender, TRADE.tokenId, _nftId, NftState.minted, NftState.price);


    }


    function burnByNftId(uint8 _nftId) external nonReentrant {
        uint256 tradeId = getTradeIdByNftId(msg.sender, _nftId);
        _burn(tradeId);
    }

    function burn(uint256 tradeId) public nonReentrant {
        _burn(tradeId);
    }

    function _burn(uint256 tradeId) internal {

        NftTradeInfo storage TRADE = nftTrade[tradeId];
        NftInfoState storage NftState = nftInfoState[TRADE.nftId];
        NftInfo storage NFT = nftInfo[TRADE.nftId];

        require(TRADE.owner == msg.sender, "not nft owner");
        require(TRADE.burnedIn == 0, "already burned");
        // avoid double burn exploit
        require(NftState.minted > 0, "no burn available");
        require(NFT.status > 0, "disabled");

        require(NftState.nft.ownerOf(TRADE.tokenId) == address(msg.sender), "not owner");
        NftState.nft.burn(TRADE.tokenId);
        nftTradeByUser[TRADE.nftId][msg.sender].removeValue(tradeId);
        nftBurnsByUser[TRADE.nftId][msg.sender].pushValue(tradeId);
        TRADE.burnedIn = block.timestamp;
        if (nftTradeByUser[TRADE.nftId][msg.sender].size() == 0) {
            ownersOf[TRADE.nftId].removeAddress(msg.sender);
            nftIdByUser[msg.sender].removeValue(TRADE.nftId);
        }
        NftState.burned = NftState.burned.add(1);
        NftState.lastBurn = block.timestamp;
        NftState.minted = NftState.minted.sub(1);

        if (TRADE.reserve > 0) {
            NftState.token.safeTransfer(address(msg.sender), TRADE.reserve);
            totalTokensRefunded = totalTokensRefunded.add(TRADE.reserve);
        }
        totalBurn = totalBurn.add(1);

        listOfOpenSells[TRADE.nftId].removeValue(tradeId);
        // added only once

        emit NftBurn(msg.sender, tradeId);
    }

    function itod(uint256 x) private pure returns (string memory) {
        if (x > 0) {
            string memory str;
            while (x > 0) {
                str = string(abi.encodePacked(uint8(x % 10 + 48), str));
                x /= 10;
            }
            return str;
        }
        return "0";
    }


    // manage the minting interval to avoid front-run exploiters
    function add(uint8 _nftId, address _author,
        uint256 _startBlock, uint256 _endBlock, bool _allowMng,
        string memory _rarity, string memory _uri, uint256 _authorFee,
        string memory _authorName, string memory _authorTwitter, uint256 _status)
    external
    mintingManagers
    {

        NftInfo storage NFT = nftInfo[_nftId];
        NftInfoState storage NftState = nftInfoState[_nftId];

        require(_nftId != 0, "invalid nftId");
        require(NFT.nftId == 0, "already exists");

        nftIndex.push(_nftId);

        NFT.nftId = _nftId;
        NFT.author = _author;
        NFT.authorFee = _authorFee;
        NFT.allowMng = _allowMng;
        NFT.authorName = _authorName;
        NFT.authorTwitter = _authorTwitter;
        NFT.rarity = _rarity;
        NFT.uri = string(abi.encodePacked(_uri, "/", itod(_nftId), ".json"));
        NFT.startBlock = _startBlock;
        NFT.endBlock = _endBlock;
        NFT.status = _status;

        NftState.nftId = _nftId;
        NftState.nft = nft;
        // default platform nft
        NftState.token = token;
        // default platform payment token

        // avoid fee mint/burn exploit
        require(platformFees.authorFee.add(platformFees.govFee).add(platformFees.devFee).add(_authorFee) < 10000, "TOO HIGH");

        uint8[] storage nftByRarity = listOfNftByRarity[_rarity];
        uint8[] storage nftByAuthors = listOfNftByAuthor[_authorName];

        if (listOfRarity.pushValue(_rarity)) {
            // generate rarityID by array index.
            rarityIdByName[_rarity] = listOfRarity.size();
        }

        if (listOfAuthors.pushValue(_authorName)) {
            // generate authorID by array index.
            authorIdByName[_authorName] = listOfAuthors.size();
        }

        NFT.authorId = authorIdByName[_authorName];
        NftState.rarityId = rarityIdByName[_rarity];

        nftByRarity.push(_nftId);
        nftByAuthors.push(_nftId);

        emit NftAdded(_nftId, _author, _startBlock, _endBlock);
    }

    function set(uint8 _nftId, address _author,
        uint256 _startBlock, uint256 _endBlock, bool _allowMng,
        string memory _rarity, string memory _uri, uint256 _authorFee,
        string memory _authorName, string memory _authorTwitter)
    external
    mintingManagers
    {

        NftInfo storage NFT = nftInfo[_nftId];

        require(NFT.nftId != 0, "NFT does not exists");

        // add new author/rarity if changed
        listOfAuthors.pushValue(_authorName);
        listOfRarity.pushValue(_rarity);

        NFT.author = _author;
        NFT.authorFee = _authorFee;
        NFT.allowMng = _allowMng;
        NFT.authorName = _authorName;
        NFT.authorTwitter = _authorTwitter;
        NFT.rarity = _rarity;
        NFT.uri = string(abi.encodePacked(_uri, "/", itod(_nftId), ".json"));
        NFT.startBlock = _startBlock;
        NFT.endBlock = _endBlock;

        // avoid fee mint/burn exploit
        require(platformFees.authorFee.add(platformFees.govFee).add(platformFees.devFee).add(_authorFee) < 10000, "TOO HIGH");

        emit NftChanged(_nftId, _author, _startBlock, _endBlock);
    }

    // manage the minting interval to avoid front-run exploiters
    function setState(uint8 _nftId, uint256 _price,
        uint256 _maxMint, uint256 _multiplier)
    external
    mintingManagers
    {
        NftInfoState storage NftState = nftInfoState[_nftId];
        require(NftState.nftId != 0, "does not exists");
        NftState.price = _price;
        NftState.maxMint = _maxMint;
        NftState.multiplier = _multiplier;
        emit NftStateAdded(_nftId, _price, _multiplier);
    }

    function adminSetNftTokenMarket(uint8 nftId, INFT _nft, IBEP20 _token) external mintingManagers {
        NftInfoState storage INFO = nftInfoState[nftId];
        INFO.nft = _nft;
        INFO.token = _token;
    }

    // change governance address
    function adminSetgovFeeAddr(address _newAddr) external onlyOwner {
        platformAddresses.govFeeAddr = _newAddr;
    }
    // change treasure/dev address
    function adminSetdevFeeAddr(address _newAddr) external onlyOwner {
        platformAddresses.devFeeAddr = _newAddr;
    }

    // manage nft emission
    function adminSetMintingManager(address _manager, bool _status) external onlyOwner {
        mintingManager[_manager] = _status;
    }

    function adminSetPlatformFee(uint256 govFee, uint256 devFee, uint256 authorFee) external onlyOwner {
        platformFees.authorFee = govFee;
        platformFees.govFee = devFee;
        platformFees.devFee = authorFee;
        require(authorFee.add(govFee).add(devFee).add(platformFees.authorFee) < 10000, "TOO HIGH");
    }

    function adminSetMarketFee(uint256 govFee, uint256 devFee, uint256 authorFee) external onlyOwner {
        platformFees.marketAuthorFee = govFee;
        platformFees.marketGovFee = devFee;
        platformFees.marketDevFee = authorFee;
        require(authorFee.add(govFee).add(devFee).add(platformFees.authorFee) < 10000, "TOO HIGH");
    }

    modifier mintingManagers(){
        require(mintingManager[_msgSender()] == true, "not manager");
        _;
    }

    function getNftIdByAuthor(string memory author)
    public view returns (uint8[] memory)
    {
        return listOfNftByAuthor[author];
    }

    function getNftIdByRarity(string memory author)
    public view returns (uint8[] memory)
    {
        return listOfNftByRarity[author];
    }

    function getNftByAuthor(string memory author) public view returns
    (NftInfo[] memory nftInfoByAuthor, NftInfoState[] memory nftInfoStateByAuthor)
    {
        uint8[] memory list = getNftIdByAuthor(author);
        uint256 authorId = authorIdByName[author];

        NftInfo[] memory info = new NftInfo[](list.length);
        NftInfoState[] memory state = new NftInfoState[](list.length);

        uint256 i = 0;
        for (uint8 index = 0; index < list.length; ++index) {
            uint8 nftId = list[index];
            if (nftInfo[nftId].authorId != authorId) {
                continue;
            }
            info[i] = nftInfo[nftId];
            state[i] = nftInfoState[nftId];
            i = i.add(1);
        }
        return (info, state);
    }


    function getNftByRarity(string memory rarity) public view returns
    (NftInfo[] memory nftInfoByRarity, NftInfoState[] memory nftInfoStateByRarity)
    {
        uint8[] memory list = getNftIdByRarity(rarity);
        uint256 rarityId = rarityIdByName[rarity];

        NftInfo[] memory info = new NftInfo[](list.length);
        NftInfoState[] memory state = new NftInfoState[](list.length);

        uint256 i = 0;
        for (uint8 index = 0; index < list.length; ++index) {
            uint8 nftId = list[index];
            if (nftInfoState[nftId].rarityId != rarityId) {
                continue;
            }
            info[i] = nftInfo[nftId];
            state[i] = nftInfoState[nftId];
            i = i.add(1);
        }
        return (info, state);
    }

    function transferByNftId(uint8 nftId, address to) external nonReentrant {
        // call "setApprovalForAll(address(this), true)" before transfer
        uint256 tradeId = getTradeIdByNftId(msg.sender, nftId);
        _transfer(tradeId, to);
    }
    // use to transfer your nft to someone (to gif for example)
    function transfer(uint256 tradeId, address to) external nonReentrant {
        // call "setApprovalForAll(address(this), true)" before transfer
        _transfer(tradeId, to);
    }

    function _transfer(uint256 tradeId, address to) internal {
        NftTradeInfo storage TRADE = nftTrade[tradeId];
        NftInfoState storage NftState = nftInfoState[TRADE.nftId];
        // NftSecondaryTradeInfo storage SECONDARY_TRADE = nftSecondaryTradeInfo[tradeId];
        require(TRADE.tradeId > 0, "transfer: nft not found");
        require(TRADE.owner == address(msg.sender), "transfer: not nft owner");
        require(TRADE.burnedIn == 0, "transfer: burned");
        // security check: if user transfer his nft via other contract, this should fail.
        require(NftState.nft.ownerOf(TRADE.tokenId) == address(msg.sender), "not owner");
        NftState.nft.safeTransferFrom(msg.sender, to, TRADE.tokenId);
        TRADE.owner = to;
        // update trade owner to new owner
        NftState.lastOwner = to;
        // new owner

        ownersOf[TRADE.nftId].removeAddress(msg.sender);
        // remove old owner
        ownersOf[TRADE.nftId].pushAddress(to, true);
        // add new owner

        nftTradeByUser[TRADE.nftId][msg.sender].removeValue(tradeId);
        // remove old owner
        nftTradeByUser[TRADE.nftId][to].pushValue(tradeId);
        // add new owner

        // remove from sell list
        listOfOpenSells[TRADE.nftId].removeValue(tradeId);
        // added only once

        emit NftTransfer(msg.sender, to, tradeId);
    }
    /**
        // nft secondary market sub-system:
        function setNftSellable(uint8 _nftId, bool _allowSell,
            uint256 _sellMinPrice)
        external
        mintingManagers
        {
            NftSecondaryMarket storage NFT = nftSecondaryMarket[_nftId];
            require(nftInfoState[_nftId].nftId > 0, "does not exists");
            require(_sellMinPrice > 0, "invalid sell min price");
            NFT.allowSell = _allowSell;
            NFT.sellMinPrice = _sellMinPrice;
        }

        function sell(uint256 tradeId, uint256 _price)
        external nonReentrant
        {
            require(tradeId > 0, "no minted");

            NftTradeInfo storage TRADE = nftTrade[tradeId];
            uint8 _nftId = TRADE.nftId;
            NftSecondaryMarket storage MARKET = nftSecondaryMarket[_nftId];
            NftSecondaryTradeInfo storage secondaryTrade = nftSecondaryTradeInfo[tradeId];
            require(MARKET.allowSell && secondaryTrade.sellPrice == 0, "not sellable");

            require(TRADE.owner == msg.sender, "not owner");
            require(_price >= MARKET.sellMinPrice, "price < min price");
            listOfOpenSells[_nftId].pushValue(tradeId);
            // added only once


            secondaryTrade.sellPrice = _price;
            secondaryTrade.sellDate = block.timestamp;

        }

        // list all trade id from a specific nft open to sell
        function getListOpenTradesByNftId(uint8 _nftId)
        public view returns (uint256[] memory sells)
        {
            return listOfOpenSells[_nftId].getAllValues();
        }

        // list all trades structs from a specific nft open to sell
        function getOpenTradesByNftId(uint8 _nftId)
        public view returns (NftTradeInfo[] memory TRADES)
        {
            uint256 size = listOfOpenSells[_nftId].size();
            NftTradeInfo[] memory listOfTrades = new NftTradeInfo[](size);
            for (uint256 i = 0; i < size; i++) {
                uint256 tradeId = listOfOpenSells[_nftId].getValueAtIndex(i);
                listOfTrades[i] = nftTrade[tradeId];
            }
            return listOfTrades;
        }

        function buy(uint8 tradeId)
        external nonReentrant
        {
            require(tradeId > 0, "buy: NFT not minted");
            NftTradeInfo storage TRADE = nftTrade[tradeId];
            NftSecondaryMarket storage MARKET = nftSecondaryMarket[TRADE.nftId];
            NftInfoState storage NftState = nftInfoState[TRADE.nftId];
            // NftInfo storage NFT = nftInfo[TRADE.nftId];

            NftSecondaryTradeInfo storage secondaryTrade = nftSecondaryTradeInfo[tradeId];
            require(MARKET.allowSell == true, "buy: NFT not sellable");
            require(TRADE.owner != msg.sender, "buy: no wash trading");
            require(TRADE.burnedIn == 0, "buy: burned");
            require(secondaryTrade.sellPrice > 0, "buy: not for sell");

            buyDoPayment(tradeId);
            // transfer from old owner to hew owner

            require(NftState.nft.ownerOf(TRADE.tokenId) == TRADE.owner, "by: not owner anymore");
            NftState.nft.safeTransferFrom(TRADE.owner, msg.sender, TRADE.tokenId);


            ownersOf[TRADE.nftId].removeAddress(TRADE.owner);
            // remove old owner
            ownersOf[TRADE.nftId].pushAddress(msg.sender, true);
            // add new owner

            nftTradeByUser[TRADE.nftId][TRADE.owner].removeValue(tradeId);
            // remove old owner
            nftTradeByUser[TRADE.nftId][msg.sender].pushValue(tradeId);
            // add new owner

            emit NftTransfer(TRADE.owner, msg.sender, tradeId);

            MARKET.qtdSells = MARKET.qtdSells.add(1);
            MARKET.lastSellPrice = secondaryTrade.sellPrice;
            MARKET.lastSellIn = block.timestamp;

            TRADE.owner = msg.sender;
            // update trade owner to new owner
            NftState.lastOwner = msg.sender;
            // new owner

        }


        function buyDoPayment(uint8 tradeId) internal {
            NftTradeInfo storage TRADE = nftTrade[tradeId];
            NftInfo storage NFT = nftInfo[TRADE.nftId];
            NftInfoState storage STATE = nftInfoState[TRADE.nftId];
            NftSecondaryMarket storage secondaryMarketInfo = nftSecondaryMarket[tradeId];
            NftSecondaryTradeInfo storage secondaryTrade = nftSecondaryTradeInfo[tradeId];


            // transfer tokens from new owner to old owner
            uint256 _authorFee = NFT.authorFee;
            if (_authorFee == 0) {
                _authorFee = platformFees.authorFee;
                // default author fee
            }

            uint256 _artistFee = secondaryTrade.sellPrice.mul(_authorFee).div(10000);
            uint256 _governanceFee = secondaryTrade.sellPrice.mul(platformFees.govFee).div(10000);
            uint256 _devFee = secondaryTrade.sellPrice.mul(platformFees.devFee).div(10000);
            uint256 _totalSold = secondaryTrade.sellPrice.sub(_artistFee).sub(_governanceFee).sub(_devFee);

            // do platform transfers
            STATE.token.safeTransferFrom(address(msg.sender), NFT.author, _artistFee);
            STATE.token.safeTransferFrom(address(msg.sender), platformAddresses.govFeeAddr, _governanceFee);
            STATE.token.safeTransferFrom(address(msg.sender), platformAddresses.devFeeAddr, _devFee);

            // after fees, pay old owner:
            STATE.token.safeTransferFrom(address(msg.sender), TRADE.owner, _totalSold);

            // accumulate fees paid
            secondaryMarketInfo.totalArtistFee = secondaryMarketInfo.totalArtistFee.add(_artistFee);
            secondaryMarketInfo.totalGovernanceFee = secondaryMarketInfo.totalGovernanceFee.add(_governanceFee);
            secondaryMarketInfo.totalDevFee = secondaryMarketInfo.totalDevFee.add(_devFee);
            secondaryMarketInfo.totalCollected = secondaryMarketInfo.totalCollected.add(_totalSold);

            secondaryTrade.sellPrice = 0;
            // reset selling property
            secondaryTrade.soldDate = block.timestamp;
            //when sold

            // remove this trade from the list of open trades
            listOfOpenSells[TRADE.nftId].removeValue(tradeId);
            // added only once

        }
    */


    //auxiliary market views

    // list all unique nft id that this user has minted
    function getNftIdByUser(address user)
    public view returns (uint8[] memory)
    {
        return nftIdByUser[user].getAllValues();
    }

    // return all trade id numbers by nft id and user wallet
    function getTradesByNftIdAndUser(address user, uint8 nftId)
    public view returns (uint256[] memory)
    {
        return nftTradeByUser[nftId][user].getAllValues();
    }

    function getBurnsByNftIdAndUser(address user, uint8 nftId)
    public view returns (uint256[] memory)
    {
        return nftBurnsByUser[nftId][user].getAllValues();
    }

    // return a nft mint/burn (aka trade) by trade id number.
    function getTradeByTradeId(uint256 tradeId)
    public view returns (NftTradeInfo memory)
    {
        return nftTrade[tradeId];
    }

    function getTradeIdByNftId(address user, uint8 nftId)
    public view returns (uint256)
    {
        uint256 size = nftTradeByUser[nftId][user].size();
        require(size > 0, "no nft minted");
        return nftTradeByUser[nftId][user].getValueAtIndex(0);
    }


    function getAllAuthors()
    public view returns (string[] memory)
    {
        return listOfAuthors.getAllValues();
    }

    function getAllRarity()
    public view returns (string[] memory)
    {
        return listOfRarity.getAllValues();
    }


    // nft secondary market sub-system:
    function setNftAuction(uint8 _nftId, bool _allowAuction, uint256 _minBid,
        uint256 _blockStart, uint256 _blockEnd, uint256 _priceStep, uint256 _entryFee, uint16 _auctionLimit)
    external
    mintingManagers
    {
        NftAuctionMarket storage AUCTION = nftAuctionMarket[_nftId];
        require(nftInfoState[_nftId].nftId > 0, "nft not configured");
        require(_minBid > 0, "invalid sell min price");
        require(_blockEnd > _blockStart, "invalid start/end block");
        // require(_blockStart >= block.number, "invalid start block");
        require(_auctionLimit >= AUCTION.auctionCount, "invalid limit");

        // to prevent spam in the bid array list that can slowdown the app
        // min step is 0.01%
        require(_priceStep >= 1, "price step should be >= 1");

        require(AUCTION.state != 1, "invalid state");
        nftAuctionMarket[_nftId].nftId = _nftId;
        AUCTION.allowAuction = _allowAuction;
        AUCTION.minBid = _minBid;
        AUCTION.blockStart = _blockStart;
        AUCTION.blockEnd = _blockEnd;
        AUCTION.priceStep = _priceStep;
        AUCTION.entryFee = _entryFee;
        AUCTION.state = 1;
        // open auction
        AUCTION.auctionLimit = _auctionLimit;
        if( AUCTION.auctionCount == 0 ){
            AUCTION.auctionCount = 1;
        }
        emit NewNftAuctionMarket(_nftId, _minBid, _blockStart);
    }

    function bid(uint8 _nftId, uint256 _bid) external nonReentrant {

        NftAuctionMarket storage AUCTION = nftAuctionMarket[_nftId];
        NftInfoState storage NftState = nftInfoState[_nftId];
        require(AUCTION.nftId > 0, "nft does not exists");
        require(block.number >= AUCTION.blockStart, "auction not started");
        require(AUCTION.auctionLimit > 0 && AUCTION.auctionCount <= AUCTION.auctionLimit, "max limit reached");
        require(AUCTION.state == 1, "invalid state");

        // initial bid should be >= min bid
        uint256 lastBid = AUCTION.lastBid > 0 ? AUCTION.lastBid : AUCTION.minBid;
        require(_bid > lastBid, "invalid bid");

        (uint256 nextPrice, bool offeredIsValid, uint256 increment) = auctionNextPrice(_nftId, _bid);
        require(offeredIsValid, "bid too low");

        // # bid fee to prevent spam
        // check first if we have a bid fee, deduct it here:
        if (AUCTION.bidFee > 0) {
            uint256 fee = _bid.mul(AUCTION.bidFee).div(10000);
            // extract bid fee, ex: 10=0.1%, 100=1%
            _bid = _bid.sub(fee);
            // set the final bid price less fee:
            uint256 artistFee = fee.mul(platformFees.authorFee).div(10000);
            // extract author fee
            NftState.token.safeTransferFrom(address(msg.sender), nftInfo[_nftId].author, artistFee);
            // pay author
            // pay platform - less author
            NftState.token.safeTransferFrom(address(msg.sender), platformAddresses.govFeeAddr, fee.sub(artistFee));
        }

        AUCTION.lastBid = _bid;
        auctionBid[_nftId].pushValue(_bid);
        // save this bid into the bid list
        emit NewNftBid(_nftId, _bid, msg.sender);
        if (block.number >= AUCTION.blockEnd) {
            if (AUCTION.auctionLimit == 0 ||
                AUCTION.auctionLimit > 0 && AUCTION.auctionCount == AUCTION.auctionLimit) {
                AUCTION.state = 2;
                emit AuctionEnd(_nftId, msg.sender);
            }
            _mint(_nftId);
            emit AuctionWin(_nftId, _bid, msg.sender);
            AUCTION.auctionCount = AUCTION.auctionCount.add(1);
        }
    }

    // see the list of bids
    function bidsByNftId( uint8 _nftId )
    public view returns(uint256[] memory){
        return auctionBid[_nftId].getAllValues();
    }

    // use to know the next best offer before you submit a bid
    // and tx fail
    function auctionNextPrice(uint8 _nftId, uint256 _bid) public view
    returns(uint256 nextPrice, bool offeredIsValid, uint256 increment)
    {
        NftAuctionMarket storage AUCTION = nftAuctionMarket[_nftId];
        if( AUCTION.priceStep == 0 ){
            return (_bid, true, 0);
        }
        uint256 lastBid = AUCTION.lastBid > 0 ? AUCTION.lastBid : AUCTION.minBid;
        increment = lastBid.mul(AUCTION.priceStep).div(10000);
        nextPrice = lastBid.add(increment);
        offeredIsValid = _bid >= nextPrice;
        return (nextPrice, offeredIsValid, increment);
    }

    function getBlock()
    public view returns(uint256){
        return block.number;
    }

}

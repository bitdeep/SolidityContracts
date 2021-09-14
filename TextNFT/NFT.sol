// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./StringArrayLib.sol";
import "./strings.sol";

contract OneAndOnly is ERC721, Pausable, Ownable {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    using StringArrayLib for StringArrayLib.Values;
    using StringsUtils for string;
    string private _baseURIPrefix;
    uint private constant maxTokensPerTransaction = 100;
    uint256 private tokenPrice = 0.05 ether; //0.05 ETH
    uint256 private featurePrice = 0.01 ether; //0.01 ETH
    mapping(string => address) public registry;
    mapping(string => uint256) public idByWords;
    mapping(uint256 => string) public wordById;
    mapping(address => StringArrayLib.Values) private wordsByOwner;
    Counters.Counter private _tokenIdCounter;

    mapping(string => string) public validProps;
    StringArrayLib.Values private listOfProps;
    mapping(string => mapping(string => string)) public features;

    constructor() ERC721("OneAndOnly", "ONE") public {
        _tokenIdCounter.increment();
    }

    function setBaseURI(string memory baseURIPrefix) public onlyOwner {
        _baseURIPrefix = baseURIPrefix;
    }

    function adminTokenPrice(uint256 _price) public onlyOwner {
        tokenPrice = _price;
    }

    function adminFeaturePrice(uint256 _price) public onlyOwner {
        featurePrice = _price;
    }

    function getBaseURIPrefix() internal view returns (string memory) {
        return _baseURIPrefix;
    }

    function adminPause() public onlyOwner {
        _pause();
    }

    function adminUnpause() public onlyOwner {
        _unpause();
    }

    function adminWithdraw() public onlyOwner {
        uint balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    function isThisWordAvailable(string memory word) public view returns (bool) {
        return registry[word] == address(0x0);
    }

    function getAllRegisteredWordsByOwner(address user)
    public view returns (string[] memory)
    {
        return wordsByOwner[user].getAllValues();
    }

    function tokenURI(uint256 tokenId)
    public
    view
    override(ERC721)
    returns (string memory)
    {
        return string(abi.encodePacked(_baseURIPrefix, "/", wordById[tokenId]));
    }

    event OnBuy(address indexed user, string word, uint256 id);

    function buyOneWord(string memory _word) whenNotPaused public payable {
        _buy(_word);
    }

    function buyMultipleWords(string memory _wordsByComa) whenNotPaused public payable {
        string[] memory split = _wordsByComa.split(",");
        require(tokenPrice.mul(split.length) <= msg.value, "Ether value sent is too low");
        uint256 count = split.length;
        for (uint256 i = 0; i < count; i++) {
            _buy(split[i]);
        }
    }

    function _buy(string memory _word) internal {
        require(StringsUtils.length(_word) > 0, "no word");
        require(StringsUtils.indexOf(_word, "<") == - 1 && StringsUtils.indexOf(_word, " ") == - 1 , "invalid char");
        require(tokenPrice <= msg.value, "Ether value sent is too low");
        string memory word = _word.upper();
        require(registry[word] == address(0x0), "word already registered");
        registry[word] = msg.sender;
        wordsByOwner[msg.sender].pushValue(word);
        uint256 id = _tokenIdCounter.current();
        idByWords[word] = id;
        wordById[id] = word;
        _safeMint(msg.sender, _tokenIdCounter.current());
        _tokenIdCounter.increment();
        emit OnBuy(msg.sender, word, id);
    }

    event OnBurn(address indexed user, string word, uint256 id);

    function burn(string memory _word) whenNotPaused public payable {
        require(tokenPrice <= msg.value, "Ether value sent is too low");
        string memory word = _word.upper();
        require(registry[word] == msg.sender, "not owner");
        uint256 id = idByWords[word];
        idByWords[word] = 0;
        wordById[id] = "";
        require(id > 0, "invalid token id");
        registry[word] = address(0x0);
        wordsByOwner[msg.sender].removeValue(word);
        _burn(id);
        emit OnBuy(msg.sender, word, id);
    }

    function adminSetValidProps(string memory name, string memory value) public onlyOwner {
        validProps[name] = value;
        listOfProps.pushValue(name);
    }

    function getListOfPropsNames() public view returns (string[] memory){
        return listOfProps.getAllValues();
    }

    event OnFeatureSet(address indexed user, string word, string name, string value);

    function setFeature(string memory _word, string memory _name, string memory _value) whenNotPaused public payable {
        require(featurePrice <= msg.value, "Ether value sent is too low");
        string memory word = _word.upper();
        string memory name = _name.upper();
        string memory value = _value.upper();
        require(validProps[name].length() > 0, "invalide prop");
        uint256 id = idByWords[word];
        require(id > 0, "invalid token id");
        require(registry[word] == msg.sender, "access denied");
        features[word][name] = value;
        emit OnFeatureSet(msg.sender, word, name, value);
    }
    function getFeatureOf(string memory word) public view returns(string[] memory names, string[] memory values){
        names = getListOfPropsNames();
        for (uint256 i = 0; i < names.length; i++) {
            values[i] = features[word][ names[i] ] ;
        }
        return (names, values);
    }

}

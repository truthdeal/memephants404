//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC404} from "./ERC404.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
// image ipfs://bafybeidxx62c5a2fnnyymmm2wnvtgwk2rhpai3gmfdscilixvmjhtwqcry
contract Memephants is ERC404 {
    string public baseTokenURI = "ipfs://bafybeidxx62c5a2fnnyymmm2wnvtgwk2rhpai3gmfdscilixvmjhtwqcry/";

    error InvalidId();
    error IdNotAssigned();
    error PoolIsEmpty();
    error InvalidSetWhitelistCondition();

    mapping (address => uint256[]) internal previousOwned ; 
    mapping(uint256 => bool) private idAssigned;
    uint256 public erc721totalSupply;
    uint256[] internal tokenIdPool;
    uint256 public maxMintedId;

    constructor(address _owner) ERC404("Memephants 404", "MEMP", 18, 100, _owner) {
        balanceOf[_owner] = totalSupply;
        erc721totalSupply = 100;
        setWhitelist(_owner, true);
    }

    function setTokenURI(string memory _tokenURI) public onlyOwner {
        baseTokenURI = _tokenURI;
    }

    function setNameSymbol(string memory _name, string memory _symbol) public onlyOwner {
        _setNameSymbol(_name, _symbol);
    }

    function tokenURI(uint256 _id) public view override returns (string memory) {
        uint256 _totalSupply = totalSupply / 1e18;
        uint256 id = _id % _totalSupply ;
        return string.concat(baseTokenURI, Strings.toString(id), ".json");
    }

    function approve(
        address spender,
        uint256 amountOrId
    ) public override returns (bool) {
        if (amountOrId <= maxMintedId && amountOrId > 0) {
            address owner = _ownerOf[amountOrId];

            if (msg.sender != owner && !isApprovedForAll[owner][msg.sender]) {
                revert Unauthorized();
            }

            getApproved[amountOrId] = spender;

            emit Approval(owner, spender, amountOrId);
        } else {
            allowance[msg.sender][spender] = amountOrId;

            emit Approval(msg.sender, spender, amountOrId);
        }

        return true;
    }

    function transferFrom(address from, address to, uint256 amountOrId) public override {
        if (amountOrId <= erc721totalSupply) {
            if (from != _ownerOf[amountOrId]) {
                revert InvalidSender();
            }

            if (to == address(0)) {
                revert InvalidRecipient();
            }

            if (
                msg.sender != from &&
                !isApprovedForAll[from][msg.sender] &&
                msg.sender != getApproved[amountOrId]
            ) {
                revert Unauthorized();
            }

            balanceOf[from] -= _getUnit();

            unchecked {
                balanceOf[to] += _getUnit();
            }

            _ownerOf[amountOrId] = to;
            delete getApproved[amountOrId];

            // update _owned for sender
            uint256 updatedId = _owned[from][_owned[from].length - 1];
            _owned[from][_ownedIndex[amountOrId]] = updatedId;
            // pop
            _owned[from].pop();
            // update index for the moved id
            _ownedIndex[updatedId] = _ownedIndex[amountOrId];
            // push token to to owned
            _owned[to].push(amountOrId);
            // update index for to owned
            _ownedIndex[amountOrId] = _owned[to].length - 1;

            emit Transfer(from, to, amountOrId);
            emit ERC20Transfer(from, to, _getUnit());
        } else {
            uint256 allowed = allowance[from][msg.sender];

            if (allowed != type(uint256).max)
                allowance[from][msg.sender] = allowed - amountOrId;

            _transfer(from, to, amountOrId);
        }
    }

    function _mint(address to) internal override {
        if (to == address(0)) {
            revert InvalidRecipient();
        }
        uint256[] memory _previousOwned =  previousOwned[to] ;
        uint256 prevArrLength = _previousOwned.length;
        
        uint256 id;
        
        if (prevArrLength > 0 ) {
            uint256 index;

            for (uint256 i = 1; i < prevArrLength + 1 ; i++) 
            {
                index = prevArrLength - i;

                uint256 tokenId = _previousOwned[index] ;

                if (!idAssigned[tokenId]) {
                    id = tokenId;
                    idAssigned[id] = true;
                    removeIndex(index , to);
                    removeFromPool(id);
                    break ;
                } 
            }
            if (id == 0) {
                id = findNewId();
            }

        } else {
            id = findNewId();
        }

        _ownerOf[id] = to;
        _owned[to].push(id);
        _ownedIndex[id] = _owned[to].length - 1;

        emit Transfer(address(0), to, id);
    }

    function _burn(address from) internal override {
        if (from == address(0)) {
            revert InvalidSender();
        }
        uint256 id = _owned[from][_owned[from].length - 1];
        _returnIdToPool(id);
        previousOwned[from].push(id);

        _owned[from].pop();
        delete _ownedIndex[id];
        delete _ownerOf[id];
        delete getApproved[id];

        emit Transfer(from, address(0), id);
    }

    function _randomIdFromPool() private returns (uint256) {
        if (tokenIdPool.length == 0) {
            revert PoolIsEmpty();
        }
        uint256 randomIndex = uint256(
            keccak256(abi.encodePacked(block.timestamp, msg.sender,tokenIdPool.length))
        ) % tokenIdPool.length;
        uint256 id = tokenIdPool[randomIndex];
        tokenIdPool[randomIndex] = tokenIdPool[tokenIdPool.length - 1];
        tokenIdPool.pop();
        idAssigned[id] = true;
        return id;
    }
    
    function _returnIdToPool(uint256 id) private {
        if (!idAssigned[id]) {
            revert IdNotAssigned();
        }
        tokenIdPool.push(id);
        idAssigned[id] = false;
    }

    function removeFromPool (uint256 _tokenId) internal {
        uint256[] memory _tokenIdPool = tokenIdPool ;
        for (uint256 i ; i < _tokenIdPool.length ; i++) 
        {
            if (_tokenIdPool[i] == _tokenId) {
                tokenIdPool[i] = tokenIdPool[tokenIdPool.length - 1];
                tokenIdPool.pop();
                break ;
            }
        }
    }

    function removeIndex(uint index, address user) internal  {
        previousOwned[user][index] = previousOwned[user][previousOwned[user].length -1];
        previousOwned[user].pop();
    }
    
    function findNewId () internal returns (uint256 id){
        if (maxMintedId < erc721totalSupply) {
                maxMintedId++;
                idAssigned[maxMintedId] = true;
                return maxMintedId;
            } else if (tokenIdPool.length > 0) {
                return _randomIdFromPool();
            } else {
                revert PoolIsEmpty();
            }
    }

    function getTokenIdPool() public view returns (uint256[] memory) {
        return tokenIdPool;
    }

    function getPreviousOwneds(address _user) public view returns (uint256[] memory) {
        return previousOwned[_user];
    }

    
}

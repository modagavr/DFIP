// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./TCS.sol";
import "./DEFI_Insurance.sol";

contract TravelCrowdsurance is TokenCrowdsurance {
    DEFI_Insurance public DFIP; // DFIP smart contract address
    uint256 public joinAmountDFIP; // Join amount in DFIP
    bool public ETHOnly; // Join only for DFIP tokens
    uint8 public maxHold; // Maximum number of toikens for one address
    uint256 public dfipETHRate; // DFIP/ETH rate
    uint8 public paybackRatio; // Payback ratio

    mapping(uint256 => uint256) public payback; // payback mapping

    function join() public override payable returns (uint256 crowdsuranceId) {
        uint256 amount = msg.value;
        address member = msg.sender;

        if (!ETHOnly && amount == uint256(0)) {
            require(address(DFIP) != address(0));
            uint256 dfipAmt = DFIP.allowance(member, address(this));
            uint256 dfipDecimals = uint256(DFIP.decimals());
            uint256 dfipAmtInETH = dfipAmt * dfipETHRate / (10**dfipDecimals);
            require(dfipAmtInETH >= uint256(0.01 ether) && amount <= (parameters.maxClaimAmount / 10));
            require(DFIP.transferFrom(member, owner, dfipAmt));
            amount = dfipAmtInETH;
        } else {
            require(amount >= uint256(0.01 ether) && amount <= (parameters.maxClaimAmount / 10));
        }        
        crowdsuranceId = _createNFT(amount, "Crowdsurance", uint256(0), member);

        extensions[crowdsuranceId] = Crowdsurance({
            timestamp: block.timestamp,
            activated: uint256(0),
            duration: parameters.coverageDuration,
            amount: amount,
            paid: uint256(0),
            score: parameters.averageScore,
            claimNumber: uint8(0),
            status: uint8(Status.Init)
        });
        assert(_insertPool(crowdsuranceId, 2));
        assert(_distributeValue(crowdsuranceId));
    }

    function _tokensOfOwner(address _owner)
        internal
        view
        returns (uint256[] memory ownerTokens)
    {
        require(_owner != address(0));
        uint256 tokenCount = ownershipTokenCount[_owner];

        if (tokenCount == 0) {
            return new uint256[](0); // Return an empty array
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 totalCases = totalSupply(); // totalSupply is cases.lenght -1, 0 index is reserved
            uint256 resultIndex = 0;

            for (uint256 id = 1; id <= totalCases; id++) {
                if (tokenIndexToOwner[id] == _owner) {
                    result[resultIndex++] = id;
                }
            }
            return result;
        }
    }

    function requestsInfos()
        public
        view
        returns (Request[] memory, Crowdsurance[] memory, uint256[] memory)
    {
        uint256 reqCount = 0;
        for (uint256 id = 1; id <= nfts.length; id++) {
            if (requests[id].timestamp != 0) {
                reqCount++;
            }
        }
        if (reqCount == 0) return (new Request[](0),new Crowdsurance[](0), new uint256[](0));
        Request[] memory reqs = new Request[](reqCount);
        Crowdsurance[] memory exts = new Crowdsurance[](reqCount);
        uint256[] memory ids = new uint256[](reqCount);
        uint256 resultIndex = 0;
        for (uint256 id = 1; id <= nfts.length; id++) {
            if (requests[id].timestamp != 0) {
                reqs[resultIndex] = requests[id];
                exts[resultIndex] = extensions[id];
                ids[resultIndex] = id;
                resultIndex++;
            }
        }
        return (reqs, exts, ids);
    }

    function tokensOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        return _tokensOfOwner(_owner);
    }

    function statusCount(address _member, uint8 _status)
        public
        view
        returns (uint256 count)
    {
        uint256[] memory tokenIds = _tokensOfOwner(_member);
        count = uint256(0);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (extensions[tokenIds[i]].status == _status) {
                count++;
            }
        }
    }

    function activate(uint256 _id) public override {
        address member = msg.sender;
        require(statusCount(member, uint8(Status.Active)) < maxHold);
        super.activate(_id);
    }

    function transferCommission() public ownerOnly {
        uint256 commission = nfts[0].value;
        require(commission != uint256(0));
        nfts[0].value = 0;
        msg.sender.transfer(commission);
    }

    function testBuyDFIP() public payable {
        require(msg.value >= 0.01 ether);
        uint256 ethToDFIP = msg.value / dfipETHRate * (10**DFIP.decimals());
        DFIP.transferFrom(owner, msg.sender, ethToDFIP);
    }

    constructor(
        DEFI_Insurance _dfip,
        uint256 _amount,
        bool _only,
        uint8 _max
    ) TokenCrowdsurance("Travel Crowdsurance NFT", "TCS") {
        DFIP = _dfip;
        parameters.joinAmount = 0.001 ether;
        parameters.maxClaimAmount = 4 ether;
        if (_amount == uint256(0)) {
            joinAmountDFIP = 100000000;
        } else {
            joinAmountDFIP = _amount;
        }
        if (_max == uint8(0)) {
            maxHold = 5;
        } else {
            maxHold = _max;
        }
        ETHOnly = _only;
        dfipETHRate = 0.001 ether;
        paybackRatio = 80;
    }
}
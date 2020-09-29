// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

contract TokenCrowdsurance {
    struct Parameters {
        uint256 joinAmount; // default join amount
        uint256 coverageDuration; // coverage duration
        uint256 maxClaimAmount; // max claim amount
        uint8 maxClaimNumber; // max claim number for the contract
        uint8 paymentRatio; // claim to payment patio
        uint256 maxPaymentAmount; // max payment amount for the contract
        uint8 minJuriesNumber; // min juries number to count voting
        uint256 votingDuration; // juries voting duration
        uint8 juriesNumber; // number of juries
        uint256 maxApplications; // maximum number of unprocessed applications
        uint256 averageScore; // avarega score
    }
    struct Crowdsurance {
        uint256 timestamp; // join time stamp
        uint256 activated; // coverage activation time stamp
        uint256 duration; // risk coverage duration
        uint256 amount; // join amount
        uint256 paid; // paid amount
        uint256 score; // score
        uint8 claimNumber; // number of claims
        uint8 status; // crowdsurance status
    }
    struct Request {
        uint256 amount; // claim amount
        uint256 timestamp; // claim time stamp
        uint256 duration; // voting duration
        uint8 positive; // number of positive votes
        uint8 negative; // number of negative votes
        uint8 number; // juries number
        address payable[5] members; // jury members
    }
    struct NFT {
        uint256 value; // NFT value
        string metadata; // ... metadata: IPFS path
        uint256 kind; // ... type
        uint256 level; // ... activities level
        uint256 state; // ... state
    }
    struct Pool {
        uint8 level; // Pool level: 0,1,2,3
        uint256 maxNumber; // Maximum number of pools on this lavel
        uint256 maxMember; // Maximum number of members for the pool
        uint256 number; // Pool number for this level
        uint256 last; // NFT ID for last availible pool (with member capacity)
        uint256 share; // Pool share from token investment
    }
    enum Status {Init, Active, Claim, Approved, Rejected, Closed}
    enum VotingState {Progress, Voted, Timeout}
    mapping(address => uint256) public addressToApplication;
    mapping(address => uint256) ownershipTokenCount;
    mapping(uint256 => address) public tokenIndexToOwner;
    mapping(uint256 => address) public tokenIndexToApproved;
    mapping(uint256 => uint256) public tokenIndexToPoolToken;
    mapping(uint256 => Crowdsurance) public extensions;
    mapping(uint256 => Request) public requests;
    mapping(address => uint256) public voters;
    NFT[] nfts;
    Pool[] pools;

    address public owner;
    string public name;
    string public symbol;
    Parameters public parameters;
    uint256 public maxLevel;

    modifier ownerOnly {
        assert(msg.sender == owner);
        _;
    }

    function addToken(uint256 _nodeId, uint256 _parentId) public {
        require(_nodeId != uint256(0) && _nodeId < nfts.length);
        require(_parentId != uint256(0) && _parentId < nfts.length);
        require(nfts[_parentId].level < (maxLevel - 1));

        tokenIndexToPoolToken[_nodeId] = _parentId;
        nfts[_nodeId].level = nfts[_parentId].level + 1;
    }

    function totalSupply() public view returns (uint256) {
        uint256 result = nfts.length;
        if (result > 0) {
            result = result - 1;
        }
        return result;
    }

    function votingStatus(uint256 _id)
        public
        view
        returns (
            VotingState state,
            uint8 positive,
            uint8 negative,
            uint256 payment,
            uint256 balance
        )
    {
        require(_id != uint256(0));
        require(extensions[_id].status == uint256(Status.Claim));

        Request storage _request = requests[_id];

        positive = _request.positive;
        negative = _request.negative;
        state = VotingState.Progress;
        payment = _request.amount;
        balance = address(this).balance;
        bool timeout = (_request.timestamp + _request.duration) < block.timestamp;
        bool voted = (_request.positive + _request.negative) ==
            parameters.juriesNumber;

        if (timeout) {
            state = VotingState.Timeout;
        } else if (voted) {
            state = VotingState.Voted;
        }
    }

    function _getPoolSize(uint256 _nodeId)
        internal
        view
        returns (uint256 size)
    {
        require(_nodeId != uint256(0) && _nodeId < nfts.length);

        uint256 total = totalSupply();

        size = 0;

        for (uint256 id = 1; id <= total; id++) {
            if (tokenIndexToPoolToken[id] == _nodeId) {
                size++;
            }
        }
    }

    function _transfer(
        address _from,
        address _to,
        uint256 _tokenId
    ) internal {
        assert(nfts[_tokenId].state != uint256(1024));

        ownershipTokenCount[_to]++;
        tokenIndexToOwner[_tokenId] = _to;

        if (_from != address(0)) {
            ownershipTokenCount[_from]--;
            delete tokenIndexToApproved[_tokenId];
        }
    }

    function _createNFT(
        uint256 _value,
        string memory _metadata,
        uint256 _kind,
        address _owner
    ) internal returns (uint256) {
        NFT memory _nft = NFT({
            value: _value,
            metadata: _metadata,
            kind: _kind,
            level: uint256(0),
            state: uint256(0)
        });
        nfts.push(_nft);
        uint256 newId = nfts.length - 1;
        if (newId == uint32(0)) {
            nfts.push(_nft);
            newId = nfts.length - 1;
        }
        _transfer(address(0), _owner, newId);
        return newId;
    }

    function _distributeValue(uint256 _id) internal returns (bool) {
        require(_id != uint256(0) && _id < nfts.length);
        require(nfts[_id].level == maxLevel - 1);

        uint256 subPoolId = tokenIndexToPoolToken[_id];
        require(subPoolId != uint256(0));
        uint256 poolId = tokenIndexToPoolToken[subPoolId];
        require(poolId != uint256(0));
        uint256 superPoolId = tokenIndexToPoolToken[poolId];
        require(superPoolId != uint256(0));

        uint256 subPoolValue = (nfts[_id].value * pools[2].share) / 100;
        require(subPoolValue != uint256(0));
        uint256 poolValue = (nfts[_id].value * pools[1].share) / 100;
        require(poolValue != uint256(0));
        uint256 superPoolValue = (nfts[_id].value * pools[0].share) / 100;
        require(superPoolValue != uint256(0));

        uint256 commission = nfts[_id].value -
            subPoolValue -
            poolValue -
            superPoolValue;
        require(commission != uint256(0));
        nfts[subPoolId].value = nfts[subPoolId].value + subPoolValue;
        nfts[poolId].value = nfts[poolId].value + poolValue;
        nfts[superPoolId].value = nfts[superPoolId].value + superPoolValue;
        nfts[0].value = nfts[0].value + commission;
        return true;
    }

    function _insertPool(uint256 _id, uint8 _level) internal returns (bool) {
        uint256 parentId = pools[_level].last;
        uint256 size = _getPoolSize(parentId);
        uint256 max = pools[_level].maxMember - 1;
        if (size < max) {
            addToken(_id, parentId);
            return true;
        }
        if (pools[_level].number == pools[_level].maxNumber) {
            return false;
        }
        uint256 newPool = _createNFT(
            uint256(0),
            nfts[parentId].metadata,
            nfts[parentId].kind,
            owner
        );
        if (newPool == uint256(0)) {
            return false;
        }
        if (_insertPool(newPool, _level - 1) == false) {
            return false;
        }
        addToken(_id, newPool);
        pools[_level].last = newPool;
        pools[_level].number++;
        return true;
    }

    function _checkPayment(uint256 _id, uint256 _value)
        internal
        view
        returns (bool possible)
    {
        possible = false;
        uint256 subPoolId = tokenIndexToPoolToken[_id];
        require(subPoolId != uint256(0));
        uint256 poolId = tokenIndexToPoolToken[subPoolId];
        require(poolId != uint256(0));
        uint256 superPoolId = tokenIndexToPoolToken[poolId];
        require(superPoolId != uint256(0));
        if (
            _value <=
            nfts[superPoolId].value + nfts[poolId].value + nfts[subPoolId].value
        ) {
            possible = true;
        }
    }

    function _payValue(uint256 _id, uint256 _value)
        internal
        returns (uint256[4] memory distribution)
    {
        require(_id != uint256(0) && _id < nfts.length);
        require(_value != uint256(0));
        distribution[0] = uint256(0);
        distribution[1] = uint256(0);
        distribution[2] = uint256(0);
        distribution[3] = uint256(0);
        uint256 subPoolId = tokenIndexToPoolToken[_id];
        require(subPoolId != uint256(0));
        uint256 poolId = tokenIndexToPoolToken[subPoolId];
        require(poolId != uint256(0));
        uint256 superPoolId = tokenIndexToPoolToken[poolId];
        require(superPoolId != uint256(0));
        if (_value <= nfts[subPoolId].value) {
            distribution[2] = _value;
            nfts[subPoolId].value = nfts[subPoolId].value - distribution[2];
        } else if (_value <= nfts[poolId].value + nfts[subPoolId].value) {
            distribution[2] = nfts[subPoolId].value;
            distribution[1] = _value - nfts[subPoolId].value;
            nfts[subPoolId].value = nfts[subPoolId].value - distribution[2];
            nfts[poolId].value = nfts[poolId].value - distribution[1];
        } else if (
            _value <=
            nfts[superPoolId].value + nfts[poolId].value + nfts[subPoolId].value
        ) {
            distribution[2] = nfts[subPoolId].value;
            distribution[1] = nfts[poolId].value;
            distribution[0] =
                _value -
                nfts[subPoolId].value -
                nfts[poolId].value;
            nfts[subPoolId].value = nfts[subPoolId].value - distribution[2];
            nfts[poolId].value = nfts[poolId].value - distribution[1];
            nfts[superPoolId].value = nfts[superPoolId].value - distribution[0];
        } else {}
    }

    function join() public virtual payable returns (uint256 crowdsuranceId) {
        uint256 amount = msg.value;
        address member = msg.sender;
        require(amount != uint256(0) && amount <= 0.4 ether);

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

    function activate(uint256 _id) public virtual {
        require(_id != uint256(0));
        require(tokenIndexToOwner[_id] == msg.sender);
        require(extensions[_id].amount != uint256(0));
        require(extensions[_id].status != uint8(Status.Active));

        nfts[_id].state = uint256(1024);
        extensions[_id].status = uint8(Status.Active);
        extensions[_id].activated = block.timestamp;
    }

    function claim(uint256 _id) public returns (bool) {
        require(_id != uint256(0));
        require(tokenIndexToOwner[_id] == msg.sender);
        require(extensions[_id].status == uint256(Status.Active));
        require(extensions[_id].claimNumber < parameters.maxClaimNumber);
        uint256 coverageEnd = extensions[_id].activated +
            extensions[_id].duration;
        require(coverageEnd >= block.timestamp);
        requests[_id] = Request({
            amount: extensions[_id].amount * 10,
            timestamp: block.timestamp,
            duration: parameters.votingDuration,
            positive: uint8(0),
            negative: uint8(0),
            number: uint8(0),
            members: [
                address(0),
                address(0),
                address(0),
                address(0),
                address(0)
            ]
        });
        extensions[_id].claimNumber++;
        extensions[_id].status = uint8(Status.Claim);
        return true;
    }

    function addVoter(address payable _jury, uint256 _id) public ownerOnly {
        require(_jury != address(0));
        require(_id != uint256(0));
        require(extensions[_id].status == uint256(Status.Claim));
        Request storage _request = requests[_id];
        require(_request.amount != uint256(0));
        uint256 votingEnd = _request.timestamp + _request.duration;
        require(votingEnd >= block.timestamp);
        uint8 _number = _request.number;
        require(_number < parameters.juriesNumber);

        _request.members[_number] = _jury;
        _request.number++;
        voters[_jury] = _id;
    }

    function vote(uint256 _id, bool _positive) public {
        require(_id != uint256(0));
        require(_id == voters[msg.sender]);
        require(extensions[_id].status == uint8(Status.Claim));
        Request storage _request = requests[_id];
        uint256 votingEnd = _request.timestamp + _request.duration;
        require(votingEnd >= block.timestamp);

        if (_positive) {
            _request.positive++;
        } else {
            _request.negative++;
        }
        delete voters[msg.sender];
    }

    function castPositive(uint256 _id) public {
        vote(_id, true);
    }

    function castNegative(uint256 _id) public {
        vote(_id, false);
    }

    function payment(uint256 _id) public {
        require(_id != uint256(0));
        require(tokenIndexToOwner[_id] == msg.sender);
        require(extensions[_id].status == uint256(Status.Claim));
        Request storage _request = requests[_id];
        bool timeout = (_request.timestamp + _request.duration) <
            block.timestamp;
        bool voted = (_request.positive + _request.negative) ==
            parameters.juriesNumber;
        require(timeout || voted);
        uint256 _payment = _request.amount;
        uint256[4] memory distribution;
        if (
            (_request.positive > _request.negative) &&
            _checkPayment(_id, _payment)
        ) {
            msg.sender.transfer(_payment);
            extensions[_id].status = uint8(Status.Approved);
            extensions[_id].paid = extensions[_id].paid + _payment;
            _payValue(_id, _payment);
        } else if (
            (_request.positive > 0) && _checkPayment(_id, extensions[_id].amount)
        ) {
            msg.sender.transfer(extensions[_id].amount);
            extensions[_id].status = uint8(Status.Closed);
            extensions[_id].paid =
                extensions[_id].paid +
                extensions[_id].amount;
            _payValue(_id, extensions[_id].amount);
        } else {
            extensions[_id].status = uint8(Status.Rejected);
        }
        for (uint256 i; i < _request.number; i++) {
            if (voters[_request.members[i]] == _id) delete voters[_request.members[i]];
        }
        delete requests[_id];
        delete distribution;
    }

    constructor(string memory _name, string memory _symbol) {  
        owner = msg.sender;
        name = _name;
        symbol = _symbol;

        maxLevel = 4;

        uint superPoolId = _createNFT(10 ether, "SuperPool", uint256(1), owner);
        uint poolId = _createNFT(uint256(0), "Pool", uint256(1), owner);
        uint subPoolId = _createNFT(uint256(0), "SubPool", uint256(2), owner);

        addToken(poolId, superPoolId);
        addToken(subPoolId, poolId);

        Pool memory superPool = Pool({
            level: uint8(0),
            maxNumber: uint256(1),
            maxMember: uint256(10),
            number: uint256(1),
            last: uint256(superPoolId),
            share: uint256(10)
        });
        pools.push(superPool);
        Pool memory pool = Pool({
            level: uint8(1),
            maxNumber: uint256(10),
            maxMember: uint256(100),
            number: uint256(1),
            last: uint256(poolId),
            share: uint256(20)
        });
        pools.push(pool);
        Pool memory subPool = Pool({
            level: uint8(2),
            maxNumber: uint256(1000),
            maxMember: uint256(100),
            number: uint256(1),
            last: uint256(subPoolId),
            share: uint256(50)
        });
        pools.push(subPool);
        nfts[0].value = uint256(0);  

        parameters.joinAmount = 0.1 ether; // default join amount
        parameters.coverageDuration = 180 days; // coverage duration in sec
        parameters.maxClaimAmount = 10 ether; // max claim amount
        parameters.maxClaimNumber = 1; // max claim number for the contract
        parameters.paymentRatio = 80; // claim to payment patio
        parameters.maxPaymentAmount = 10 ether; // max payment amount for the contract
        parameters.minJuriesNumber = 3; // min juries number to count voting
        parameters.votingDuration = 2 days; // juries voting duration in sec
        parameters.juriesNumber = 5; // juries number -- not more than 5
        parameters.maxApplications = 10; // max number of unprocessed applications
        parameters.averageScore = 100; // average score value
    }
}

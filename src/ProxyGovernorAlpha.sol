pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./AddrArrayLib.sol";
contract ProxyGovernorAlpha {
     using SafeMath for uint256;
     using AddrArrayLib for AddrArrayLib.Addresses;
    /// @notice The name of this contract
    string public constant name = "Tollfree Governor Alpha";
    /// @notice The address of the Tollfree Voters Registry
    voterRegistryInterface public voterRegistry;
     /// @notice The address of the Toll  token
    tollInterface public toll;
    /// @notice The total number of proposals
    uint public proposalCount;

    struct Proposal {
        uint id;
        address proposer;
        uint eta;
        address proxy;
        uint startBlock;
        uint endBlock;
        uint forVotes;
        uint againstVotes;
        uint revokeVotes;
        bool canceled;
        bool executed;
        bool queued;
        mapping (address => Receipt) receipts;
    }

    /// @notice Ballot receipt record for a voter
    struct Receipt {
        /// @notice Whether or not a vote has been cast
        bool hasVoted;
        /// @notice Whether or not a vote has been cast
        bool hasRevoked;
        /// @notice Whether or not the voter supports the proposal
        bool support;
       /// @notice The number of votes the voter had, which were cast
        uint96 votes;
         /// @notice The number of votes the voter had, which are revoked
        uint96 revokedVotes;
    }

    /// @notice Possible states that a proposal may be in
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed,
        Revoked,
        Removed
    }
    
    /// @notice The official record of all proposals ever proposed
    mapping (uint => Proposal) public proposals;
    /// @notice The latest proposal for each proposer
    mapping (address => uint) public latestProposalIds;
    mapping (address => uint) public totalMintOf;
    mapping (uint => bool) public removed;
    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    /// @notice The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,bool support)");
    /// @notice An event emitted when a new proposal is created
    event ProposalCreated(uint id, address proposer, address proxy, uint startBlock, uint endBlock, string description);
    /// @notice An event emitted when a vote has been cast on a proposal
    event VoteCast(address voter, uint proposalId, bool support, uint votes);
    /// @notice An event emitted when a proposal has been canceled
    event ProposalCanceled(uint id);
    /// @notice An event emitted when a proposal has been queued in the Timelock
    event ProposalQueued(uint id, uint eta);
    /// @notice An event emitted when a proposal has been executed in the Timelock
    event ProposalExecuted(uint id);
    
    /// @notice The latest proposal for each proposer
    AddrArrayLib.Addresses internal minters;
    constructor( address voterRegistry_, address toll_, address tranferProxy, address univ2Proxy) public {
        voterRegistry = voterRegistryInterface(voterRegistry_);
        toll = tollInterface(toll_);
        addMinter(tranferProxy);
        addMinter(univ2Proxy);
    }
    
   
    
    /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
    function quorumVotes() public view returns (uint) {
        return onePercent(toll.totalSupply());
    } // 4% of Toll

    /// @notice The number of votes required in order for a voter to become a proposer
    function proposalThreshold() public pure returns (uint) { 
        return 10000 ether;
    } // 1% of Toll

 
    /// @notice The delay before voting on a proposal may take place, once proposed
    function votingDelay() public pure returns (uint) { return 5760; } // ~ 1 day in 15s block

    /// @notice The duration of voting on a proposal, in blocks
    function votingPeriod() public pure returns (uint) { return 40_320; } // ~7 days in blocks (assuming 15s blocks)

    function propose(address proxy, string memory description) public returns (uint) {
        require(voterRegistry.getPriorVotes(msg.sender, sub256(block.number, 1)) > proposalThreshold(), "GovernorAlpha::propose: proposer votes below proposal threshold");
        uint latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
          ProposalState proposersLatestProposalState = state(latestProposalId);
          require(proposersLatestProposalState != ProposalState.Active, "GovernorAlpha::propose: one live proposal per proposer, found an already active proposal");
          require(proposersLatestProposalState != ProposalState.Pending, "GovernorAlpha::propose: one live proposal per proposer, found an already pending proposal");
        }
        uint startBlock = add256(block.number, votingDelay());
        uint endBlock = add256(startBlock, votingPeriod());
        proposalCount++;
        Proposal memory newProposal = Proposal({
            id: proposalCount,
            proposer: msg.sender,
            proxy: proxy,
            eta: 0,
            startBlock: startBlock,
            endBlock: endBlock,
            forVotes: 0,
            againstVotes: 0,
            canceled: false,
            executed: false,
            queued:false,
            revokeVotes: 0
        });
        proposals[newProposal.id] = newProposal;
        latestProposalIds[newProposal.proposer] = newProposal.id;
        emit ProposalCreated(newProposal.id, msg.sender, proxy, startBlock, endBlock, description);
        return newProposal.id;
    }

    function queue(uint proposalId) public {
        require(state(proposalId) == ProposalState.Succeeded, "GovernorAlpha::queue: proposal can only be queued if it is succeeded");
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.queued, "GovernorAlpha::_queueOrRevert: proposal action already queued at eta");
        uint eta = add256(block.timestamp, 2 days);
        proposal.eta = eta;
        proposal.queued = true;
        emit ProposalQueued(proposalId, eta);
    }

    function execute(uint proposalId) public {
        require(state(proposalId) == ProposalState.Queued, "GovernorAlpha::execute: proposal can only be executed if it is queued");
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        addMinter(proposal.proxy);
        emit ProposalExecuted(proposalId);
    }
    
 
    function cancel(uint proposalId) public {
        ProposalState state = state(proposalId);
        require(state != ProposalState.Executed, "GovernorAlpha::cancel: cannot cancel executed proposal");
        Proposal storage proposal = proposals[proposalId];
        require(voterRegistry.getPriorVotes(proposal.proposer, sub256(block.number, 1)) < proposalThreshold(), "GovernorAlpha::cancel: proposer above threshold");
        proposal.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    function getReceipt(uint proposalId, address voter) public view returns (Receipt memory) {
        return proposals[proposalId].receipts[voter];
    }

    function state(uint proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId && proposalId > 0, "GovernorAlpha::state: invalid proposal id");
        Proposal storage proposal = proposals[proposalId];
        if (removed[proposalId]) {
            return ProposalState.Removed;
        }else if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < quorumVotes()) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            if (proposal.revokeVotes >=  proposal.forVotes){
                return ProposalState.Revoked;
            }
            return ProposalState.Executed;
        } else if (block.timestamp >= add256(proposal.eta, 14 days)) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

    function castVote(uint proposalId, bool support) public {
        return _castVote(msg.sender, proposalId, support);
    }


    function castVoteBySig(uint proposalId, bool support, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "GovernorAlpha::castVoteBySig: invalid signature");
        return _castVote(signatory, proposalId, support);
    }

    function _castVote(address voter, uint proposalId, bool support) internal {
        require(state(proposalId) == ProposalState.Active, "GovernorAlpha::_castVote: voting is closed");
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[voter];
        require(receipt.hasVoted == false, "GovernorAlpha::_castVote: voter already voted");
        uint96 votes = voterRegistry.getPriorVotes(voter, proposal.startBlock);
        if (support) {
            proposal.forVotes = add256(proposal.forVotes, votes);
        } else {
            proposal.againstVotes = add256(proposal.againstVotes, votes);
        }
        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;
        emit VoteCast(voter, proposalId, support, votes);
    }
    
    
    function revokeVote(uint proposalId) public {
        return _revokeVote(msg.sender, proposalId);
    }

    function revokeVoteBySig(uint proposalId, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "GovernorAlpha::castVoteBySig: invalid signature");
        return _revokeVote(signatory, proposalId);
    }

    function _revokeVote(address voter, uint proposalId) internal {
        require(state(proposalId) != ProposalState.Active, "GovernorAlpha::_castVote: voting is Active");
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[voter];
        require(receipt.hasRevoked == false, "GovernorAlpha::_revokeVote: voter already revoked");
        uint96 votes = voterRegistry.getPriorVotes(voter, proposal.startBlock);
        add256(proposal.revokeVotes, votes);
        receipt.hasRevoked = true;
        receipt.revokedVotes = votes;
    }
    
    function remove(uint proposalId) public {
        require(state(proposalId) == ProposalState.Revoked, "GovernorAlpha::revoke: proposal can only be removed if it is revoked");
        Proposal storage proposal = proposals[proposalId];
        removed[proposalId] = true;
        removeMinter(proposal.proxy);
        emit ProposalExecuted(proposalId);
    }

    function add256(uint256 a, uint256 b) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, "addition overflow");
        return c;
    }

    function sub256(uint256 a, uint256 b) internal pure returns (uint) {
        require(b <= a, "subtraction underflow");
        return a - b;
    }

    function getChainId() internal pure returns (uint) {
        uint chainId;
        assembly { chainId := chainid() }
        return chainId;
    }
     //https://ethereum.stackexchange.com/questions/71928/percentage-calculation
    function onePercent(uint256 _tokens) private pure returns (uint256) {
        uint256 roundValue = ceil(_tokens, 100);
        uint256 onePercentofTokens = roundValue.mul(100).div(100 * 10**uint256(2));
        return onePercentofTokens;
    }

    function ceil(uint256 a, uint256 m) internal pure returns (uint256) {
        uint256 c = a.add(m);
        uint256 d = c.sub(1);
        uint256 e = d.div(m);
        return e.mul(m);
    }
    
   function mintersCount()public view returns(uint count){
        return minters.size();
    }
    
   function addMinter(address minter) internal{
        minters.pushAddress(minter);
   }

  function removeMinter(address minter) internal {
        minters.removeAddress(minter);
  }

  function mint(address to, uint256 amount) public {
        require(minters.exists(msg.sender), 'GovernorAlpha::mint: sender is not a minter');
        require(voterRegistry.isEligible(to), 'GovernorAlpha::mint: Low Balance');
        totalMintOf[msg.sender] = totalMintOf[msg.sender].add(amount);
        toll.mint(to, amount);
  }
  
  function getProxies() public view returns(address[] memory allMinters){
      allMinters = minters.getAllAddresses();
  }
  
  function isProxy(address minter) public view returns(bool){
      return minters.exists(minter);
  }
  
    
}




interface voterRegistryInterface {
    function getPriorVotes(address account, uint blockNumber) external view returns (uint96);
    function isEligible(address transactor) external view returns(bool);
}

interface tollInterface {
    function totalSupply() external view returns (uint256);
    function mint(address to, uint256 amount) external;
}


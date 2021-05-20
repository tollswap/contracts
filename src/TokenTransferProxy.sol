// SPDX-License-Identifier: MIT
pragma solidity ^0.5.0;
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
interface IGovernorAlpha {
    function mint(address to, uint256 amount) external;
}

interface IVotersRegistry{
    function  isEligible(address transactor) external view returns(bool);
}

contract TOLLTransferProxy {
    using SafeMath for uint256;
    uint256 MINIMUMFEE = 918; //+ 21000 ; //tx fee is not refunded
    uint256 MINTFEE = 14585;
    uint256 APPOVAL_FEES = 46000; // could be more or less
    mapping(address => uint256) public approvals;
    IGovernorAlpha private TOLL;
    IVotersRegistry private votersRegistry;
    address public GOVERNOR;
    address public VOTERREGISTER;
     event refund (
        address indexed token,
        address indexed sender,
        uint256  refund
    );
    
    constructor( address _votersRegistry) public {
        votersRegistry = IVotersRegistry(_votersRegistry);
        VOTERREGISTER = _votersRegistry;
        GOVERNOR = msg.sender;
    }
    
    function setGovernor(address _GovernorAlpha)public{
        require(msg.sender == GOVERNOR, "Only Governor can Transfer Governance");
        TOLL = IGovernorAlpha(_GovernorAlpha);
        GOVERNOR = _GovernorAlpha;
    }
    

    function transferTokens(
        address to,
        uint256 tokens,
        address token
    ) external {
        uint256 fees = gasleft().add(MINIMUMFEE);
        uint256 approvalFees = getApprovalFees(token, msg.sender);
        require(votersRegistry.isEligible(msg.sender), "Low TOLL Balance.");
        require(
            IERC20(token).transferFrom(msg.sender, to, tokens),
            "Transfer failed failed."
        );
        setApproval(token, msg.sender);
        emit refund(token, msg.sender, tx.gasprice.mul((fees.add(MINTFEE.add(approvalFees))).sub(gasleft())));
        TOLL.mint(
            msg.sender,
            tx.gasprice.mul((fees.add(MINTFEE.add(approvalFees))).sub(gasleft()))
        );
    }

    function getApprovalFees(address token, address user)
        internal
        view
        returns (uint256)
    {
        if (IERC20(token).allowance(user, address(this)) > approvals[user])
            return APPOVAL_FEES;
        return 0;
    }

    function setApproval(address token, address user) internal returns (uint256) {
        approvals[user] = IERC20(token).allowance(user, address(this));
    }
}

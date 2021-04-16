// SPDX-License-Identifier: MIT
pragma solidity ^0.5.0;
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";

contract TOLLTransferProxy {
    using SafeMath for uint256;
    address public TOLL_ADDRESS = 0x420c6C82f5b8184beE86D457fC3D6a9Db6355e34;
    uint256 MINIMUMFEE = 918; //+ 21000 ; //tx fee is not refunded
    uint256 MINTFEE = 14585;
    uint256 APPOVAL_FEES = 46000; // could be more or less
    mapping(address => uint256) public approvals;
    ERC20Mintable private TOLL;
    constructor() public {
        TOLL = ERC20Mintable(TOLL_ADDRESS);
    }

    function transferTokens(
        address to,
        uint256 tokens,
        address token
    ) external {
        uint256 fees = gasleft().add(MINIMUMFEE);
        uint256 approvalFees = getApprovalFees(token, msg.sender);
        require(fees <= 1 ether, " Max refund is 1 Ether");
        require(TOLL.balanceOf(msg.sender) >= 1 ether, "Low TOLL Balance.");
        require(
            IERC20(token).transferFrom(msg.sender, to, tokens),
            "Transfer failed failed."
        );
        setApproval(token, msg.sender);
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

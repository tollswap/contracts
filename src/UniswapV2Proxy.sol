// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../libs/SafeMath.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";


interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function mint(address to, uint256 amount) external;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IGovernorAlpha {
    function mint(address to, uint256 amount) external;
}

interface IVotersRegistry{
    function  isEligible(address transactor) external view returns(bool);
}

contract UniswapV2Proxy {
    using SafeMath for uint256;
    address public UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public Governor;
    IUniswapV2Router02 private uniswapRouter;
    IUniswapV2Factory private uniswapFactory;
    IVotersRegistry public VotersRegistry;
    uint256 MINFEE = 918; //+ 21000 ; //tx fee is not refunded
    uint256 MINTFEE = 14585;
    uint256 APPOVAL_FEES = 46000; // could be more or less
    mapping(address => uint256) public approvals;
    IGovernorAlpha private TOLL;
    uint256 public gasstart = 0;
    uint256 public gassend = 0;
    constructor(address _VotersRegistry) public {
        uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
        VotersRegistry = IVotersRegistry(_VotersRegistry);
        Governor = msg.sender;
        uniswapFactory = IUniswapV2Factory(uniswapRouter.factory());
    }
    
    function setGovernor(address _GovernorAlpha)public{
        require(msg.sender == Governor, "Only Governor can Transfer Governance");
        TOLL = IGovernorAlpha(_GovernorAlpha);
        Governor = _GovernorAlpha;
    }


    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        gasstart = gasleft();
        uint256 fees = gasleft().add(MINFEE);
        uint256 approvalFees = getApprovalFees(path[0], msg.sender);
        require(VotersRegistry.isEligible(msg.sender), "Not Eligible for A Refund");
        require(
            IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn),
            "transferFrom failed."
        );
        require(
            IERC20(path[0]).approve(address(uniswapRouter), amountIn),
            "approval failed."
        );
        amounts = uniswapRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
        setApproval(path[0], msg.sender);
        TOLL.mint(
            msg.sender,
            tx.gasprice.mul((fees.add(MINTFEE.add(approvalFees))).sub(gasleft()))
        );
        gassend = gasleft();
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        gasstart = gasleft();
        uint256 fees = gasleft().add(MINFEE);
        uint256 approvalFees = getApprovalFees(path[0], msg.sender);
        require(VotersRegistry.isEligible(msg.sender), "Not Eligible for A Refund");
        uint256[] memory output = uniswapRouter.getAmountsIn(amountOut, path);
        require(
            IERC20(path[0]).transferFrom(msg.sender, address(this), output[0]),
            "transferFrom failed."
        );
        require(
            IERC20(path[0]).approve(address(uniswapRouter), output[0]),
            "approval failed."
        );
        amounts = uniswapRouter.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            to,
            deadline
        );
        setApproval(path[0], msg.sender);
        TOLL.mint( 
            msg.sender,
            tx.gasprice.mul((fees.add(MINTFEE.add(approvalFees))).sub(gasleft()))
        );
        gassend = gasleft();
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        gasstart = gasleft();
        uint256 fees = gasleft().add(MINFEE);
        require(VotersRegistry.isEligible(msg.sender), "Not Eligible for A Refund");
        amounts = uniswapRouter.swapExactETHForTokens{value:msg.value}(
            amountOutMin,
            path,
            to,
            deadline
        );
        TOLL.mint(
            msg.sender,
            tx.gasprice.mul((fees.add(MINTFEE)).sub(gasleft()))
        );
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        gasstart = gasleft();
        uint256 fees = gasleft().add(MINFEE);
        uint256 approvalFees = getApprovalFees(path[0], msg.sender);
        require(VotersRegistry.isEligible(msg.sender), "Not Eligible for A Refund");
        uint256[] memory outputs = uniswapRouter.getAmountsIn(amountOut, path);
        require(
            IERC20(path[0]).transferFrom(msg.sender, address(this), outputs[0]),
            "transferFrom failed."
        );
        require(
            IERC20(path[0]).approve(address(uniswapRouter), outputs[0]),
            "approval failed."
        );
        amounts = uniswapRouter.swapTokensForExactETH(
            amountOut,
            amountInMax,
            path,
            to,
            deadline
        );
        setApproval(path[0], msg.sender);
        TOLL.mint(
            msg.sender,
            tx.gasprice.mul((fees.add(MINTFEE.add(approvalFees))).sub(gasleft()))
        );
        gassend = gasleft();
    }
    
 
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        uint256 fees = gasleft().add(MINFEE);
        uint256 approvalFees = getApprovalFees(path[0], msg.sender);
        require(VotersRegistry.isEligible(msg.sender), "Not Eligible for A Refund");
        require(
            IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn),
            "transferFrom failed."
        );
        require(
            IERC20(path[0]).approve(address(uniswapRouter), amountIn),
            "approval failed."
        );
        amounts = uniswapRouter.swapExactTokensForETH(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
        setApproval(path[0], msg.sender);
        TOLL.mint(
            msg.sender,
            tx.gasprice.mul((fees.add(MINTFEE.add(approvalFees))).sub(gasleft()))
        );
        gassend = gasleft();
    }
    
    

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        gasstart = gasleft();
        uint256 fees = gasleft().add(MINFEE);
        require(VotersRegistry.isEligible(msg.sender), "Not Eligible for A Refund");
        amounts = uniswapRouter.swapETHForExactTokens{value:msg.value}(
            amountOut,
            path,
            to,
            deadline
        );
        if (msg.value > amounts[0])
            TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
        TOLL.mint(
            msg.sender,
            tx.gasprice.mul((fees.add(MINTFEE)).sub(gasleft()))
        );
        gassend = gasleft();
    }



    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external{
        gasstart = gasleft();
        uint256 fees = gasleft().add(MINFEE);
        uint256 approvalFees = getApprovalFees(path[0], msg.sender);
        require(VotersRegistry.isEligible(msg.sender), "Not Eligible for A Refund");
        require(
            IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn),
            "transferFrom failed."
        );
        require(
            IERC20(path[0]).approve(address(uniswapRouter), amountIn),
            "approval failed."
        );
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
        setApproval(path[0], msg.sender);
        TOLL.mint(
            msg.sender,
            tx.gasprice.mul((fees.add(MINTFEE.add(approvalFees))).sub(gasleft()))
        );
        gassend = gasleft();
    }



    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        payable
    {
        gasstart = gasleft();
        uint256 fees = gasleft().add(MINFEE);
        require(VotersRegistry.isEligible(msg.sender), "Not Eligible for A Refund");
        uniswapRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value:msg.value}(
            amountOutMin,
            path,
            to,
            deadline
        );
        TOLL.mint(
            msg.sender,
            tx.gasprice.mul((fees.add(MINTFEE)).sub(gasleft()))
        );
    }


    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
    {
        gasstart = gasleft();
        uint256 fees = gasleft().add(MINFEE);
        uint256 approvalFees = getApprovalFees(path[0], msg.sender);
        require(VotersRegistry.isEligible(msg.sender), "Not Eligible for A Refund");
        require(
            IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn),
            "transferFrom failed."
        );
        require(
            IERC20(path[0]).approve(address(uniswapRouter), amountIn),
            "approval failed."
        );
        uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
        setApproval(path[0], msg.sender);
        TOLL.mint(
            msg.sender,
            tx.gasprice.mul((fees.add(MINTFEE.add(approvalFees))).sub(gasleft()))
        );
        gassend = gasleft();
    }


    
    function getApprovalFees(address token, address user) internal view returns (uint256) {
        if (IERC20(token).allowance(user, address(this)) > approvals[user])
            return APPOVAL_FEES;
        return 0;
    }

    function setApproval(address token, address user) internal returns (uint256) {
        approvals[user] = IERC20(token).allowance(user, address(this));
    }
    
    receive() external payable {}
}

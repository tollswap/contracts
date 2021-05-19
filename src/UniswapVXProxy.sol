// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../libs/SafeMath.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
interface IVotersRegistry{
    function  isEligible(address transactor) external view returns(bool);
}

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

contract UniswapVXProxy {
    using SafeMath for uint256;
    //0xf0c742ec7c801a6afc99f9d41c92c06ebef2cf91
    address public TOLL_ADDRESS;
    address public UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    IUniswapV2Router02 private uniswapRouter;
    IUniswapV2Factory private uniswapFactory;
    IVotersRegistry public VotersRegistry;
    uint256 MINFEE = 918; //+ 21000 ; //tx fee is not refunded
    uint256 MINTFEE = 14585;
    uint256 APPOVAL_FEES = 46000; // could be more or less
    mapping(address => uint256) public approvals;
    IERC20 private TOLL;
    address[] TOLL_ETH_PATH;
    uint256 public gasstart = 0;
    uint256 public gassend = 0;

    constructor(address _TOLL , address _VotersRegistry) public {
        TOLL_ADDRESS = _TOLL;
        uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
        VotersRegistry = IVotersRegistry(_VotersRegistry);
        TOLL = IERC20(_TOLL);
        TOLL_ETH_PATH.push(address(TOLL));
        TOLL_ETH_PATH.push(uniswapRouter.WETH());
        uniswapFactory = IUniswapV2Factory(uniswapRouter.factory());
    }


   
    function swapExactETHForTokens(
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external payable returns (uint256[] memory amounts) {
        amounts = uniswapRouter.swapExactETHForTokens{value:msg.value}(
            amountOutMin,
            path,
            to,
            deadline
        );
    }
    
    function getApprovalFees(address token, address user) internal view returns (uint256) {
        if (IERC20(token).allowance(user, address(this)) > approvals[user])
            return APPOVAL_FEES;
        return 0;
    }

    function setApproval(address token, address user) internal returns (uint256) {
        approvals[user] = IERC20(token).allowance(user, address(this));
    }
    
    event Received(address, uint);
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}

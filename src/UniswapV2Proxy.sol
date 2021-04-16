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

contract UniswapV2Proxy {
    using SafeMath for uint256;
    //0xf0c742ec7c801a6afc99f9d41c92c06ebef2cf91
    address public TOLL_ADDRESS = 0x420c6C82f5b8184beE86D457fC3D6a9Db6355e34;
    address public UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    IUniswapV2Router02 private uniswapRouter;
    IUniswapV2Factory private uniswapFactory;
    uint256 MINFEE = 918; //+ 21000 ; //tx fee is not refunded
    uint256 MINTFEE = 14585;
    uint256 APPOVAL_FEES = 46000; // could be more or less
    mapping(address => uint256) public approvals;
    IERC20 private TOLL;
    address[] TOLL_ETH_PATH;
    uint256 public gasstart = 0;
    uint256 public gassend = 0;

    constructor() public {
        uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
        TOLL = IERC20(TOLL_ADDRESS);
        TOLL_ETH_PATH.push(address(TOLL));
        TOLL_ETH_PATH.push(uniswapRouter.WETH());
        uniswapFactory = IUniswapV2Factory(uniswapRouter.factory());
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
        require(fees <= 1 ether, " Max refund is 1 Ether");
        require(TOLL.balanceOf(msg.sender) >= MINIMUM_TOLL(), "Low FITH Balance.");
        require(path[0] != TOLL_ADDRESS, "Exit Transactions Prohibited");
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
        require(TOLL.balanceOf(msg.sender) >= MINIMUM_TOLL(), "Low FITH Balance.");
        require(path[0] != TOLL_ADDRESS, "Exit Transactions Prohibited");
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
        uint256 approvalFees = getApprovalFees(path[0], msg.sender);
        require(fees <= 1 ether, " Max refund is 1 Ether");
        require(TOLL.balanceOf(msg.sender) >= MINIMUM_TOLL(), "Low FITH Balance.");
        require(path[0] != TOLL_ADDRESS, "Exit Transactions Prohibited");
        amounts = uniswapRouter.swapExactETHForTokens{value:msg.value}(
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
        require(fees <= 1 ether, " Max refund is 1 Ether");
        require(TOLL.balanceOf(msg.sender) >= MINIMUM_TOLL(), "Low FITH Balance.");
        require(path[0] != TOLL_ADDRESS, "Exit Transactions Prohibited");
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

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        gasstart = gasleft();
        uint256 fees = gasleft().add(MINFEE);
        uint256 approvalFees = getApprovalFees(path[0], msg.sender);
        require(fees <= 1 ether, " Max refund is 1 Ether");
        require(TOLL.balanceOf(msg.sender) >= MINIMUM_TOLL(), "Low FITH Balance.");
        require(path[0] != TOLL_ADDRESS, "Exit Transactions Prohibited");
        amounts = uniswapRouter.swapETHForExactTokens{value:msg.value}(
            amountOut,
            path,
            to,
            deadline
        );
        uint256[] memory output = uniswapRouter.getAmountsIn(amountOut, path);
        if (msg.value > output[0])
            TransferHelper.safeTransferETH(msg.sender, msg.value - output[0]);
        setApproval(path[0], msg.sender);
        TOLL.mint(
            msg.sender,
            tx.gasprice.mul((fees.add(MINTFEE.add(approvalFees))).sub(gasleft()))
        );
        gassend = gasleft();
    }

    function MINIMUM_TOLL() public view returns (uint256) {
        uint256 min = TOLL.totalSupply() / 10000000;
        return min > 1 ether ? 1 ether : min;
    }

    function getApprovalFees(address token, address user) internal view returns (uint256) {
        if (IERC20(token).allowance(user, address(this)) > approvals[user])
            return APPOVAL_FEES;
        return 0;
    }

    function setApproval(address token, address user) internal returns (uint256) {
        approvals[user] = IERC20(token).allowance(user, address(this));
    }
}

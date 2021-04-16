// SPDX-License-Identifier: MIT
pragma solidity ^0.5.0;

import "@openzeppelin/contracts/crowdsale/validation/CappedCrowdsale.sol";
import "@openzeppelin/contracts/crowdsale/distribution/FinalizableCrowdsale.sol";
import "@openzeppelin/contracts/crowdsale/emission/MintedCrowdsale.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/lifecycle/Pausable.sol";
import "./IUniswapV2Router01.sol";

/**
 * @title TollCrowdSale
 * @dev This is an example of a fully fledged crowdsale.
 * The way to add new features to a base crowdsale is by multiple inheritance.
 * In this example we are providing following extensions:
 * CappedCrowdsale - sets a max boundary for raised funds
 * RefundableCrowdsale - set a min goal to be reached and returns funds if it's not met
 * MintedCrowdsale - assumes the token can be minted by the crowdsale, which does so
 * when receiving purchases.
 *
 * After adding multiple features it's good practice to run integration tests
 * to ensure that subcontracts works together as intended.
 */
contract TollCrowdSale is MintedCrowdsale, FinalizableCrowdsale {
    using SafeMath for uint256;
    uint256 public totalPresale;
    uint256 public totalClaims;
    uint256 public timelock;
    uint256 public totalTeamFundsWithdrawn;
    address payable public devTeam = 0x7f0374480b9Ca09144F6cBd16774FDf1da1ae528;
    address payable public adminTeam = 0xACe0C45A761BB92150092b88Abf1A7c9Fc2b118D;
    address public marketingTeam = 0x31749B1213C4191ff24951Ac3866007611695142;
    address public salesTeam = 0x5e93F2C38050794CDE01DE459b2947632F271e1c;
    ERC20Mintable internal TOLL;
    IUniswapV2Router01 internal uniswapRouter;
    address internal _uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public oracle = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public exchangeAddress;
    mapping(uint256 => bool) public usedNonces;
    mapping(address => uint256) public claims;
    mapping(address => uint256) public teamFunds;
    // Flag to know if liquidity has been locked
    bool public liquidityLocked = false;
    bool public teamWithdrawn = false;

    constructor(
        uint256 openingTime,
        uint256 closingTime,
        address payable wallet,
        ERC20Mintable _token
    )
        public
        Crowdsale(1, wallet, _token) // rate is 1 => 1;
        TimedCrowdsale(openingTime, closingTime)
    {
        TOLL = _token;
        uniswapRouter = IUniswapV2Router01(_uniswapRouter);
    }

    /**
     * @dev  finalization task, called when finalize() is called.
     */
    function _finalization() internal {
        // How many ETH is in this contract
        uint256 amountEthForUniswap = onePercent(address(this).balance).mul(80);
        // Exact amount of $TOLL are needed by Uniswap
        TOLL.mint(address(this), amountEthForUniswap);
        // Send 60% of the presale  balance and all tokens in the contract to Uniswap LP
        TOLL.approve(address(uniswapRouter), amountEthForUniswap);
        uniswapRouter.addLiquidityETH.value(amountEthForUniswap)(
            address(TOLL),
            amountEthForUniswap,
            amountEthForUniswap,
            amountEthForUniswap,
            address(0), // burn address
            // solium-disable-next-line security/no-block-members */
            block.timestamp
        );
        liquidityLocked = true;
        exchangeAddress = pairFor(
            uniswapRouter.factory(),
            uniswapRouter.WETH(),
            address(TOLL)
        );
        // Unpause TOLL forever.
        Pausable(address(token())).unpause();
        // solium-disable-next-line security/no-block-members */
        timelock = block.timestamp; // start timelock
    }

    /**
     * @dev  claim unpaid toll fees.
     */

    function claim(
        uint256 amount,
        uint256 nonce,
        bytes memory sig,
        address claimer
    ) public {
        // solium-disable-next-line security/no-block-members */
        require(block.timestamp < closingTime().add(20 days), "Fees Reclaim Ended");
        require(!usedNonces[nonce], "Used Nonce");
        require(claims[claimer] == 0, "Already Claimed");
        require(TOLL.balanceOf(claimer) >= amount, "Invalid Toll Balance at Claim Time");
        bytes32 message = addPrefix(keccak256(abi.encodePacked(claimer, amount, nonce, address(this))));
        address signedBy = whoSigned(message, sig);
        require(signedBy == oracle, "Invalid signature");
        usedNonces[nonce] = true;
        claims[claimer] = amount;
        totalClaims = totalClaims.add(amount);
        TOLL.mint(claimer, amount);
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

    /**
     * @dev Overrides Crowdsale fund forwarding, sending funds to escrow.
     */
    function _forwardFunds() internal {
        totalPresale = totalPresale.add(msg.value);
    }

    // Some fancy Signature Legwork
    function decodeSignature(bytes memory sig)
        internal
        pure
        returns (
            uint8,
            bytes32,
            bytes32
        )
    {
        require(sig.length == 65, "Invalid SIgnature");
        bytes32 r;
        bytes32 s;
        uint8 v;
        // solium-disable-next-line security/no-inline-assembly */
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        return (v, r, s);
    }

    function releaseTeamShare() public {
        // solium-disable-next-line security/no-block-members */
        require(block.timestamp > timelock.add(30 days), "Time Lock is Active");
        require(liquidityLocked, "No Liquidity");
        require(totalTeamFundsWithdrawn < 105000, "Team Funds Exhausted");
        // solium-disable-next-line security/no-block-members */
        timelock = block.timestamp;
        uint256 EthLiquidity = ERC20(uniswapRouter.WETH()).balanceOf(exchangeAddress);
        uint256 onePercentEthLiquidity = onePercent(EthLiquidity);
        uint256 max = onePercentEthLiquidity.mul(5); // 5% max
        uint256 adminAndDevTeamMintAmount = max > 1000 ether ? 1000 ether : max; //
        if (teamFunds[devTeam] <= 500000 ether) {
            teamFunds[devTeam] = adminAndDevTeamMintAmount.add(teamFunds[devTeam]);
            TOLL.mint(devTeam, adminAndDevTeamMintAmount);
        }
        if (teamFunds[adminTeam] <= 500000 ether) {
            teamFunds[adminTeam] = adminAndDevTeamMintAmount.add(teamFunds[adminTeam]);
            TOLL.mint(adminTeam, adminAndDevTeamMintAmount);
        }
    }

    function teamWithdraw() public {
        require(totalTeamFundsWithdrawn < 105000, "Team Funds Exhausted");
        require(liquidityLocked, "Create Uniswap Pair Before Withdraw");
        require(!teamWithdrawn, "Team Withdraw is completed");
        teamWithdrawn = true;
        totalTeamFundsWithdrawn = totalTeamFundsWithdrawn.add(5000);
        TOLL.mint(adminTeam, 1000 ether);
        TOLL.mint(devTeam, 2000 ether);
        TOLL.mint(salesTeam, 1000 ether);
        TOLL.mint(marketingTeam, 1000 ether);
        uint256 TeamEther = address(this).balance;
        devTeam.transfer(TeamEther.div(2));
        adminTeam.transfer(TeamEther.div(2));
    }
    function whoSigned(bytes32 message, bytes memory sig)
        internal
        pure
        returns (address)
    {
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = decodeSignature(sig);
        return ecrecover(message, v, r, s);
    }

    function addPrefix(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address token0, address token1)
    {
        require(tokenA != tokenB, "");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(
        address factory,
        address tokenA,
        address tokenB
    ) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex"ff",
                        factory,
                        keccak256(abi.encodePacked(token0, token1)),
                        hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f" // init code hash
                    )
                )
            )
        );
    }
}

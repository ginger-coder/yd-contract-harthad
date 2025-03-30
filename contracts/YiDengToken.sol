// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract YiDengToken is ERC20, Ownable {
    uint256 public constant MAX_SUPPLY = 1250000 * 10 ** 18;
    uint256 public tokensPerEth = 1000 * 10 ** 18;
    uint256 public constant RESERVE_RATIO = 10;

    uint256 public teamAllocation = (MAX_SUPPLY * 20) / 100;
    uint256 public marketingAllocation = (MAX_SUPPLY * 10) / 100;
    uint256 public communityAllocation = (MAX_SUPPLY * 10) / 100;

    bool public initialDistributionDone;
    uint256 public reservedEth;

    // 事件定义部分，带有详细注释
    /**
     * @dev 当用户使用 ETH 购买 YD 代币时触发
     * @param buyer 购买者的地址，使用 indexed 修饰符便于按地址过滤事件
     * @param ethAmount 用户支付的 ETH 数量（单位：wei）
     * @param tokenAmount 用户获得的 YD 代币数量（单位：10^18 wei）
     */
    event TokensPurchased(
        address indexed buyer,
        uint256 ethAmount,
        uint256 tokenAmount
    );

    /**
     * @dev 当用户出售 YD 代币换回 ETH 时触发
     * @param seller 出售者的地址，使用 indexed 修饰符便于按地址过滤事件
     * @param tokenAmount 用户出售的 YD 代币数量（单位：10^18 wei）
     * @param ethAmount 用户获得的 ETH 数量（单位：wei）
     */
    event TokensSold(
        address indexed seller,
        uint256 tokenAmount,
        uint256 ethAmount
    );

    /**
     * @dev 当初始代币分配完成时触发
     * @param teamWallet 接收团队分配代币的钱包地址
     * @param marketingWallet 接收市场营销分配代币的钱包地址
     * @param communityWallet 接收社区分配代币的钱包地址
     */
    event InitialDistributionCompleted(
        address teamWallet,
        address marketingWallet,
        address communityWallet
    );

    /**
     * @dev 当所有者更新 ETH-YD 汇率时触发
     * @param newRate 新的汇率值（单位：YD per ETH，不含 10^18 因子，实际存储时会调整）
     */
    event TokensPerEthUpdated(uint256 newRate);

    constructor() ERC20("YiDeng Token", "YD") {}

    function distributeInitialTokens(
        address teamWallet,
        address marketingWallet,
        address communityWallet
    ) external onlyOwner {
        require(!initialDistributionDone, "Initial distribution already done");
        require(
            teamWallet != address(0) &&
                marketingWallet != address(0) &&
                communityWallet != address(0),
            "Invalid address"
        );

        _mint(teamWallet, teamAllocation);
        _mint(marketingWallet, marketingAllocation);
        _mint(communityWallet, communityAllocation);

        initialDistributionDone = true;
        emit InitialDistributionCompleted(
            teamWallet,
            marketingWallet,
            communityWallet
        );
    }

    function buyWithETH() external payable {
        require(msg.value > 0, "Must send ETH");
        uint256 tokenAmount = (msg.value * tokensPerEth) / 10 ** 18;
        require(
            totalSupply() + tokenAmount <= MAX_SUPPLY,
            "Would exceed max supply"
        );

        uint256 reserveAmount = (msg.value * RESERVE_RATIO) / 100;
        reservedEth += reserveAmount;

        _mint(msg.sender, tokenAmount);
        emit TokensPurchased(msg.sender, msg.value, tokenAmount);
    }

    function sellTokens(uint256 tokenAmount) external {
        require(tokenAmount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= tokenAmount, "Insufficient balance");

        uint256 ethAmount = (tokenAmount * 10 ** 18) / tokensPerEth;
        require(
            address(this).balance >= ethAmount,
            "Insufficient ETH in contract"
        );
        require(reservedEth >= ethAmount, "Insufficient reserved ETH");

        reservedEth -= ethAmount;

        _burn(msg.sender, tokenAmount);
        (bool success, ) = payable(msg.sender).call{value: ethAmount}("");
        require(success, "ETH transfer failed");

        emit TokensSold(msg.sender, tokenAmount, ethAmount);
    }

    function setTokensPerEth(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Rate must be greater than 0");
        tokensPerEth = newRate * 10 ** 18;
        emit TokensPerEthUpdated(newRate);
    }

    function remainingMintableSupply() public view returns (uint256) {
        return MAX_SUPPLY - totalSupply();
    }

    function withdrawETH(uint256 amount) external onlyOwner {
        uint256 availableEth = address(this).balance - reservedEth;
        require(amount <= availableEth, "Insufficient available ETH");
        require(amount > 0, "Amount must be greater than 0");

        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    function availableEthBalance() public view returns (uint256) {
        return address(this).balance - reservedEth;
    }

    receive() external payable {}

    fallback() external payable {}
}

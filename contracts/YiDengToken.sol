// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// 导入 OpenZeppelin 的 ERC20 和 Ownable 合约，提供标准代币功能和所有者权限控制
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// YiDengToken 合约继承自 ERC20（标准代币）和 Ownable（限制访问权限给所有者）
contract YiDengToken is ERC20, Ownable {
    // 最大代币供应量：125万 YD 代币，带 18 位小数 (1,250,000 * 10^18)
    uint256 public constant MAX_SUPPLY = 1250000 * 10 ** 18;
    
    // 初始汇率：1 ETH 可兑换 1000 YD 代币（已调整为 18 位小数）
    uint256 public tokensPerEth = 1000 * 10 ** 18;
    
    // 储备比例：10% 的 ETH 收入将被储备，不允许立即提取
    uint256 public constant RESERVE_RATIO = 10;

    // 代币分配：团队、市场营销和社区的分配量（按 MAX_SUPPLY 的百分比计算）
    uint256 public teamAllocation = (MAX_SUPPLY * 20) / 100;      // 20% 分配给团队
    uint256 public marketingAllocation = (MAX_SUPPLY * 10) / 100; // 10% 分配给市场营销
    uint256 public communityAllocation = (MAX_SUPPLY * 10) / 100; // 10% 分配给社区

    // 标志变量，确保初始代币分配只执行一次
    bool public initialDistributionDone;
    
    // 跟踪储备的 ETH 数量（不可供所有者立即提取的部分）
    uint256 public reservedEth;

    /**
     * @dev 当用户使用 ETH 购买 YD 代币时触发的事件
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
     * @dev 当用户出售 YD 代币换回 ETH 时触发的事件
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
     * @dev 当初始代币分配完成时触发的事件
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
     * @dev 当所有者更新 ETH-YD 汇率时触发的事件
     * @param newRate 新的汇率值（单位：YD per ETH，不含 10^18 因子，实际存储时会调整）
     */
    event TokensPerEthUpdated(uint256 newRate);

    // 构造函数：初始化 ERC20 代币，名称为 "YiDeng Token"，符号为 "YD"
    constructor() ERC20("YiDeng Token", "YD") {}

    /**
     * @dev 分配初始代币给团队、市场营销和社区钱包
     * @param teamWallet 接收团队分配的地址 (占 MAX_SUPPLY 的 20%)
     * @param marketingWallet 接收市场营销分配的地址 (占 MAX_SUPPLY 的 10%)
     * @param communityWallet 接收社区分配的地址 (占 MAX_SUPPLY 的 10%)
     * 仅限合约所有者调用，且只能调用一次（由 initialDistributionDone 控制）
     */
    function distributeInitialTokens(
        address teamWallet,
        address marketingWallet,
        address communityWallet
    ) external onlyOwner {
        // 确保初始分配只执行一次
        require(!initialDistributionDone, "Initial distribution already done");
        
        // 验证输入地址不为空（零地址无效）
        require(
            teamWallet != address(0) &&
                marketingWallet != address(0) &&
                communityWallet != address(0),
            "Invalid address"
        );

        // 铸造并分配代币给指定钱包
        _mint(teamWallet, teamAllocation);
        _mint(marketingWallet, marketingAllocation);
        _mint(communityWallet, communityAllocation);

        // 标记初始分配已完成
        initialDistributionDone = true;
        
        // 触发初始分配完成事件
        emit InitialDistributionCompleted(
            teamWallet,
            marketingWallet,
            communityWallet
        );
    }

    /**
     * @dev 使用 ETH 购买 YD 代币
     * 用户通过发送 ETH 调用此函数，获得相应数量的 YD 代币
     */
    function buyWithETH() external payable {
        // 确保用户发送了 ETH
        require(msg.value > 0, "Must send ETH");
        
        // 计算用户应获得的 YD 代币数量（ETH 数量 * 汇率 / 10^18）
        uint256 tokenAmount = (msg.value * tokensPerEth) / 10 ** 18;
        
        // 确保铸造后的总供应量不超过最大供应量
        require(
            totalSupply() + tokenAmount <= MAX_SUPPLY,
            "Would exceed max supply"
        );

        // 计算储备的 ETH 数量（支付的 ETH * 储备比例 / 100）
        uint256 reserveAmount = (msg.value * RESERVE_RATIO) / 100;
        reservedEth += reserveAmount;

        // 铸造代币给购买者
        _mint(msg.sender, tokenAmount);
        
        // 触发代币购买事件
        emit TokensPurchased(msg.sender, msg.value, tokenAmount);
    }

    /**
     * @dev 出售 YD 代币换回 ETH
     * @param tokenAmount 用户希望出售的 YD 代币数量
     * 用户将代币烧毁并从合约中提取对应的 ETH
     */
    function sellTokens(uint256 tokenAmount) external {
        // 确保出售数量大于 0
        require(tokenAmount > 0, "Amount must be greater than 0");
        
        // 确保用户有足够的代币余额
        require(balanceOf(msg.sender) >= tokenAmount, "Insufficient balance");

        // 计算用户应获得的 ETH 数量（代币数量 * 10^18 / 汇率）
        uint256 ethAmount = (tokenAmount * 10 ** 18) / tokensPerEth;
        
        // 确保合约中有足够的 ETH 可供支付
        require(
            address(this).balance >= ethAmount,
            "Insufficient ETH in contract"
        );
        
        // 确保储备的 ETH 足够支付
        require(reservedEth >= ethAmount, "Insufficient reserved ETH");

        // 从储备中减去支付的 ETH
        reservedEth -= ethAmount;

        // 烧毁用户的代币
        _burn(msg.sender, tokenAmount);
        
        // 将 ETH 转账给用户
        (bool success, ) = payable(msg.sender).call{value: ethAmount}("");
        require(success, "ETH transfer failed");

        // 触发代币出售事件
        emit TokensSold(msg.sender, tokenAmount, ethAmount);
    }

    /**
     * @dev 设置新的 ETH-YD 汇率
     * @param newRate 新的汇率值（单位：YD per ETH，不含 10^18 因子）
     * 仅限合约所有者调用
     */
    function setTokensPerEth(uint256 newRate) external onlyOwner {
        // 确保新汇率大于 0
        require(newRate > 0, "Rate must be greater than 0");
        
        // 更新汇率（调整为 18 位小数）
        tokensPerEth = newRate * 10 ** 18;
        
        // 触发汇率更新事件
        emit TokensPerEthUpdated(newRate);
    }

    /**
     * @dev 查看剩余可铸造的代币供应量
     * @return 最大供应量减去当前总供应量的差值
     */
    function remainingMintableSupply() public view returns (uint256) {
        return MAX_SUPPLY - totalSupply();
    }

    /**
     * @dev 提取合约中的 ETH（仅限所有者）
     * @param amount 要提取的 ETH 数量（单位：wei）
     * 只能提取非储备部分的 ETH
     */
    function withdrawETH(uint256 amount) external onlyOwner {
        // 计算可提取的 ETH（总余额减去储备部分）
        uint256 availableEth = address(this).balance - reservedEth;
        
        // 确保提取金额不超过可提取余额
        require(amount <= availableEth, "Insufficient available ETH");
        
        // 确保提取金额大于 0
        require(amount > 0, "Amount must be greater than 0");

        // 将 ETH 转账给所有者
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    /**
     * @dev 查看当前可提取的 ETH 余额
     * @return 合约总 ETH 余额减去储备部分的差值
     */
    function availableEthBalance() public view returns (uint256) {
        return address(this).balance - reservedEth;
    }

    // 接收函数：允许合约直接接收 ETH
    receive() external payable {}

    // 回退函数：处理未定义函数调用时接收 ETH
    fallback() external payable {}
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// 导入所需的 OpenZeppelin 合约
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title CourseCertificate
 * @notice 易登课程证书NFT合约，用于发放和管理课程完成证书
 */
contract CourseCertificate is ERC721, AccessControl {
    using Counters for Counters.Counter;
    using Strings for uint256;

    // NFT ID计数器
    Counters.Counter private _tokenIds;

    // 定义铸造者角色，只有拥有该角色才能铸造证书
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    // 定义销毁者角色，只有拥有该角色才能销毁证书
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // 证书数据结构
    struct CertificateData {
        string web2CourseId; // Web2平台的课程ID
        address student; // 学生地址
        uint256 timestamp; // 发放时间
        string metadataURI; // 元数据URI
    }

    // tokenId => 证书数据
    mapping(uint256 => CertificateData) public certificates;

    // 记录学生获得的证书：courseId => 学生地址 => tokenId数组
    mapping(string => mapping(address => uint256[])) public studentCertificates;

    // 事件定义，带有详细注释
    /**
     * @dev 当新的课程证书被铸造时触发
     * @param tokenId 新铸造的证书ID，使用 indexed 修饰符便于按ID过滤事件
     * @param web2CourseId Web2平台的课程ID，用于标识课程
     * @param student 接收证书的学生地址，使用 indexed 修饰符便于按地址过滤事件
     */
    event CertificateMinted(
        uint256 indexed tokenId,
        string web2CourseId,
        address indexed student
    );

    /**
     * @dev 当证书被销毁时触发
     * @param tokenId 被销毁的证书ID，使用 indexed 修饰符便于按ID过滤事件
     * @param web2CourseId 证书关联的课程ID
     * @param student 原持有证书的学生地址，使用 indexed 修饰符便于按地址过滤事件
     */
    event CertificateBurned(
        uint256 indexed tokenId,
        string web2CourseId,
        address indexed student
    );

    /**
     * @notice 构造函数，初始化NFT名称和符号，并设置初始角色
     */
    constructor() ERC721("YiDeng Course Certificate", "YDCC") {
        // 授予合约部署者管理员、铸造者和销毁者权限
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(BURNER_ROLE, msg.sender);
    }

    /**
     * @notice 铸造新的课程证书，确保每个学生每课程只获得一个证书
     * @param student 学生地址
     * @param web2CourseId 课程ID
     * @param metadataURI 元数据URI
     * @return uint256 新铸造的证书ID
     */
    function mintCertificate(
        address student,
        string memory web2CourseId,
        string memory metadataURI
    ) external onlyRole(MINTER_ROLE) returns (uint256) {
        require(student != address(0), "Invalid student address");
        require(
            !hasCertificate(student, web2CourseId),
            "Student already has this certificate"
        );

        // 生成新的tokenId
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        // 铸造NFT
        _safeMint(student, newTokenId);

        // 存储证书数据
        certificates[newTokenId] = CertificateData({
            web2CourseId: web2CourseId,
            student: student,
            timestamp: block.timestamp,
            metadataURI: metadataURI
        });

        // 记录学生的证书
        studentCertificates[web2CourseId][student].push(newTokenId);

        emit CertificateMinted(newTokenId, web2CourseId, student);
        return newTokenId;
    }

    /**
     * @notice 销毁指定证书，只有拥有 BURNER_ROLE 的地址可以调用
     * @param tokenId 要销毁的证书ID
     */
    function burnCertificate(uint256 tokenId) external onlyRole(BURNER_ROLE) {
        require(_exists(tokenId), "Certificate does not exist");

        // 获取证书数据
        CertificateData memory cert = certificates[tokenId];
        address student = cert.student;
        string memory web2CourseId = cert.web2CourseId;

        // 销毁NFT
        _burn(tokenId);

        // 从证书映射中删除数据
        delete certificates[tokenId];

        // 从学生证书记录中移除
        uint256[] storage certs = studentCertificates[web2CourseId][student];
        for (uint256 i = 0; i < certs.length; i++) {
            if (certs[i] == tokenId) {
                // 将目标元素移到数组末尾并删除
                certs[i] = certs[certs.length - 1];
                certs.pop();
                break;
            }
        }

        emit CertificateBurned(tokenId, web2CourseId, student);
    }

    /**
     * @notice 获取证书元数据URI
     * @param tokenId 证书ID
     * @return string 证书的元数据URI
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(_exists(tokenId), "Certificate does not exist");
        return certificates[tokenId].metadataURI;
    }

    /**
     * @notice 检查学生是否拥有某课程的证书
     * @param student 学生地址
     * @param web2CourseId 课程ID
     * @return bool 是否拥有证书
     */
    function hasCertificate(
        address student,
        string memory web2CourseId
    ) public view returns (bool) {
        return studentCertificates[web2CourseId][student].length > 0;
    }

    /**
     * @notice 获取学生某课程的所有证书ID
     * @param student 学生地址
     * @param web2CourseId 课程ID
     * @return uint256[] 证书ID数组
     */
    function getStudentCertificates(
        address student,
        string memory web2CourseId
    ) public view returns (uint256[] memory) {
        return studentCertificates[web2CourseId][student];
    }

    /**
     * @notice 实现 supportsInterface，检查合约支持的接口
     * @param interfaceId 接口ID
     * @return bool 是否支持该接口
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./YiDengToken.sol";
import "./CourseCertificate.sol";

/**
 * @title CourseMarket
 * @notice 一灯教育课程市场合约，用于课程创建、购买和证书发放
 */
contract CourseMarket is Ownable {
    // 合约实例
    YiDengToken public immutable yiDengToken;
    CourseCertificate public immutable certificate;

    // 课程结构体
    struct Course {
        string web2CourseId; // Web2平台的课程ID
        string name; // 课程名称
        uint256 price; // 课程价格(YD代币，单位：10^18 wei)
        bool isActive; // 课程是否可购买
        address creator; // 课程创建者地址
    }

    // 合约状态变量
    mapping(uint256 => Course) public courses; // courseId => Course
    mapping(string => uint256) public web2ToCourseId; // web2CourseId => courseId
    mapping(address => mapping(uint256 => bool)) public userCourses; // 用户购买记录
    uint256 public courseCount; // 课程总数

    /**
     * @dev 当用户成功购买课程时触发
     * @param buyer 购买者的地址，使用 indexed 修饰符便于按地址过滤事件
     * @param courseId 课程的内部ID，使用 indexed 修饰符便于按ID过滤事件
     * @param web2CourseId Web2平台的课程ID，用于外部系统关联
     */
    event CoursePurchased(
        address indexed buyer,
        uint256 indexed courseId,
        string web2CourseId
    );

    /**
     * @dev 当学生完成课程并获得证书时触发
     * @param student 学生地址，使用 indexed 修饰符便于按地址过滤事件
     * @param courseId 课程的内部ID，使用 indexed 修饰符便于按ID过滤事件
     * @param certificateId 发放的证书NFT的tokenId
     */
    event CourseCompleted(
        address indexed student,
        uint256 indexed courseId,
        uint256 certificateId
    );

    /**
     * @dev 当新课程被添加到市场时触发
     * @param courseId 新课程的内部ID，使用 indexed 修饰符便于按ID过滤事件
     * @param web2CourseId Web2平台的课程ID，用于外部系统关联
     * @param name 课程名称
     */
    event CourseAdded(
        uint256 indexed courseId,
        string web2CourseId,
        string name
    );

    /**
     * @dev 当课程状态（是否可购买）被更新时触发
     * @param courseId 课程的内部ID，使用 indexed 修饰符便于按ID过滤事件
     * @param isActive 课程的新状态（true为可购买，false为不可购买）
     */
    event CourseStatusUpdated(uint256 indexed courseId, bool isActive);

    /**
     * @notice 构造函数，初始化代币和证书合约地址
     * @param _tokenAddress YiDeng代币合约地址
     * @param _certificateAddress 证书NFT合约地址
     */
    constructor(address _tokenAddress, address _certificateAddress) Ownable() {
        require(_tokenAddress != address(0), "Invalid token address");
        require(
            _certificateAddress != address(0),
            "Invalid certificate address"
        );
        yiDengToken = YiDengToken(payable(_tokenAddress));
        certificate = CourseCertificate(_certificateAddress);
    }

    /**
     * @notice 添加新课程，仅限所有者调用
     * @param web2CourseId Web2平台的课程ID
     * @param name 课程名称
     * @param price 课程价格(YD代币，单位：10^18 wei)
     */
    function addCourse(
        string memory web2CourseId,
        string memory name,
        uint256 price
    ) external onlyOwner {
        require(
            bytes(web2CourseId).length > 0,
            "Web2 course ID cannot be empty"
        );
        require(bytes(name).length > 0, "Course name cannot be empty");
        require(web2ToCourseId[web2CourseId] == 0, "Course already exists");
        require(price > 0, "Price must be greater than 0");

        courseCount++;
        courses[courseCount] = Course({
            web2CourseId: web2CourseId,
            name: name,
            price: price,
            isActive: true,
            creator: msg.sender
        });
        web2ToCourseId[web2CourseId] = courseCount;

        emit CourseAdded(courseCount, web2CourseId, name);
    }

    /**
     * @notice 更新课程状态（是否可购买），仅限所有者调用
     * @param courseId 课程内部ID
     * @param isActive 新状态
     */
    function updateCourseStatus(
        uint256 courseId,
        bool isActive
    ) external onlyOwner {
        require(courseId > 0 && courseId <= courseCount, "Invalid course ID");
        Course storage course = courses[courseId];
        require(course.isActive != isActive, "Status already set");
        course.isActive = isActive;
        emit CourseStatusUpdated(courseId, isActive);
    }

    /**
     * @notice 购买课程，用户需提前授权足够的YD代币
     * @param web2CourseId Web2平台的课程ID
     */
    function purchaseCourse(string memory web2CourseId) external {
        uint256 courseId = web2ToCourseId[web2CourseId];
        require(courseId > 0, "Course does not exist");

        Course memory course = courses[courseId];
        require(course.isActive, "Course not active");
        require(!userCourses[msg.sender][courseId], "Already purchased");

        // 检查并转移代币
        require(
            yiDengToken.transferFrom(msg.sender, course.creator, course.price),
            "Transfer failed - ensure allowance is set"
        );

        userCourses[msg.sender][courseId] = true;
        emit CoursePurchased(msg.sender, courseId, web2CourseId);
    }

    /**
     * @notice 验证课程完成并发放证书，仅限所有者调用
     * @param student 学生地址
     * @param web2CourseId Web2平台的课程ID
     */
    function verifyCourseCompletion(
        address student,
        string memory web2CourseId
    ) public onlyOwner {
        require(student != address(0), "Invalid student address");
        uint256 courseId = web2ToCourseId[web2CourseId];
        require(courseId > 0, "Course does not exist");
        require(userCourses[student][courseId], "Course not purchased");
        require(
            !certificate.hasCertificate(student, web2CourseId),
            "Certificate already issued"
        );
        
        // 生成证书元数据URI
        string memory metadataURI = generateCertificateURI(
            student,
            web2CourseId
        );
        // 铸造证书NFT
        uint256 tokenId = certificate.mintCertificate(
            student,
            web2CourseId,
            metadataURI
        );

        emit CourseCompleted(student, courseId, tokenId);
    }

    /**
     * @notice 批量验证课程完成，仅限所有者调用
     * @param students 学生地址数组
     * @param web2CourseId Web2平台的课程ID
     */
    function batchVerifyCourseCompletion(
        address[] memory students,
        string memory web2CourseId
    ) external onlyOwner {
        require(students.length > 0, "Empty student list");
        uint256 courseId = web2ToCourseId[web2CourseId];
        require(courseId > 0, "Course does not exist");

        for (uint256 i = 0; i < students.length; i++) {
            if (
                students[i] != address(0) &&
                userCourses[students[i]][courseId] &&
                !certificate.hasCertificate(students[i], web2CourseId)
            ) {
                verifyCourseCompletion(students[i], web2CourseId);
            }
        }
    }

    /**
     * @notice 检查用户是否已购买课程
     * @param user 用户地址
     * @param web2CourseId Web2平台的课程ID
     * @return bool 是否已购买
     */
    function hasCourse(
        address user,
        string memory web2CourseId
    ) external view returns (bool) {
        uint256 courseId = web2ToCourseId[web2CourseId];
        require(courseId > 0, "Course does not exist");
        return userCourses[user][courseId];
    }

    /**
     * @notice 获取课程详情
     * @param courseId 课程内部ID
     * @return Course 课程结构体
     */
    function getCourse(uint256 courseId) external view returns (Course memory) {
        require(courseId > 0 && courseId <= courseCount, "Invalid course ID");
        return courses[courseId];
    }

    /**
     * @notice 生成证书元数据URI
     * @param student 学生地址
     * @param web2CourseId Web2平台的课程ID
     * @return string 元数据URI
     */
    function generateCertificateURI(
        address student,
        string memory web2CourseId
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "https://api.yideng.com/certificate/",
                    web2CourseId,
                    "/",
                    Strings.toHexString(student)
                )
            );
    }
}

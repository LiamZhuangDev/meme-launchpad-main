// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {LearningMEMEFactory} from "./LearningMEMEFactory.sol";
import {LearningMEMEToken} from "./LearningMEMEToken.sol";

contract LearningMEMECore is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 public constant REQUEST_EXPIRY = 1 hours;

    enum TokenStatus {
        NOT_CREATED,
        TRADING
    }

    struct CreateTokenParams {
        string name;
        string symbol;
        uint256 totalSupply;
        uint256 launchTime;
        address creator;
        uint256 timestamp;
        bytes32 requestId;
        uint256 nonce;
    }

    struct TokenInfo {
        address creator;
        uint256 createdAt;
        uint256 launchTime;
        TokenStatus status;
    }

    bool public initialized;

    LearningMEMEFactory public factory;
    address public helper;
    address public vesting;
    address public platformFeeReceiver;
    address public marginReceiver;
    address public graduateFeeReceiver;
    uint256 public chainId;

    uint256 public creationFee;
    uint256 public preBuyFeeRate;
    uint256 public tradingFeeRate;
    uint256 public graduationPlatformFeeRate;
    uint256 public graduationCreatorFeeRate;
    uint256 public minLockTime;

    mapping(bytes32 => bool) public usedRequestIds;
    mapping(address => TokenInfo) public tokenInfo;

    error AlreadyInitialized();
    error ZeroAddress();
    error InvalidSigner();
    error RequestExpired();
    error RequestAlreadyProcessed();
    error InsufficientFee();
    error InvalidTokenParameters();
    error NativeTransferFailed();

    event Initialized(address indexed admin, address indexed signer, address indexed factory);
    event HelperChanged(address indexed oldHelper, address indexed newHelper);
    event VestingChanged(address indexed oldVesting, address indexed newVesting);
    event TokenCreated(
        address indexed token,
        address indexed creator,
        string name,
        string symbol,
        uint256 totalSupply,
        bytes32 requestId
    );

    function initialize(
        address factory_,
        address helper_,
        address signer_,
        address platformFeeReceiver_,
        address marginReceiver_,
        address graduateFeeReceiver_,
        address admin_
    ) external {
        if (initialized) revert AlreadyInitialized();
        if (
            factory_ == address(0) || helper_ == address(0) || signer_ == address(0)
                || platformFeeReceiver_ == address(0) || marginReceiver_ == address(0)
                || graduateFeeReceiver_ == address(0) || admin_ == address(0)
        ) {
            revert ZeroAddress();
        }

        initialized = true;
        factory = LearningMEMEFactory(factory_);
        helper = helper_;
        platformFeeReceiver = platformFeeReceiver_;
        marginReceiver = marginReceiver_;
        graduateFeeReceiver = graduateFeeReceiver_;
        chainId = block.chainid;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ADMIN_ROLE, admin_);
        _grantRole(SIGNER_ROLE, signer_);
        _grantRole(DEPLOYER_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);

        creationFee = 0.05 ether;
        preBuyFeeRate = 300;
        tradingFeeRate = 100;
        graduationPlatformFeeRate = 550;
        graduationCreatorFeeRate = 250;
        minLockTime = 1 days;

        emit Initialized(admin_, signer_, factory_);
    }

    function deployTokenForLearning(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        uint256 timestamp,
        uint256 nonce
    ) external onlyRole(ADMIN_ROLE) returns (address) {
        return factory.deployToken(name, symbol, totalSupply, timestamp, nonce);
    }

    function createToken(bytes calldata data, bytes calldata signature)
        external
        payable
        nonReentrant
        returns (address tokenAddress)
    {
        if (msg.value < creatio nFee) revert InsufficientFee();

        CreateTokenParams memory params = abi.decode(data, (CreateTokenParams));
        bytes32 messageHash = keccak256(abi.encodePacked(data, chainId, address(this)));
        address recoveredSigner = messageHash.recover(signature);

        if (!hasRole(SIGNER_ROLE, recoveredSigner)) revert InvalidSigner();
        if (block.timestamp > params.timestamp + REQUEST_EXPIRY) revert RequestExpired();
        if (usedRequestIds[params.requestId]) revert RequestAlreadyProcessed();
        if (
            bytes(params.name).length == 0 || bytes(params.symbol).length == 0 || params.totalSupply == 0
                || params.creator == address(0) || params.requestId == bytes32(0)
        ) {
            revert InvalidTokenParameters();
        }

        // Consume the signed request before making external calls.
        usedRequestIds[params.requestId] = true;

        tokenAddress =
            factory.deployToken(params.name, params.symbol, params.totalSupply, params.timestamp, params.nonce);

        LearningMEMEToken(tokenAddress).setTransferMode(LearningMEMEToken.TransferMode.CONTROLLED);
        tokenInfo[tokenAddress] = TokenInfo({
            creator: params.creator,
            createdAt: block.timestamp,
            launchTime: params.launchTime,
            status: TokenStatus.TRADING
        });

        _sendNative(platformFeeReceiver, creationFee);

        uint256 refund = msg.value - creationFee;
        if (refund > 0) _sendNative(msg.sender, refund);

        emit TokenCreated(
            tokenAddress, params.creator, params.name, params.symbol, params.totalSupply, params.requestId
        );
    }

    function setHelper(address helper_) external onlyRole(ADMIN_ROLE) {
        if (helper_ == address(0)) revert ZeroAddress();
        address oldHelper = helper;
        helper = helper_;
        emit HelperChanged(oldHelper, helper_);
    }

    function setVesting(address vesting_) external onlyRole(ADMIN_ROLE) {
        if (vesting_ == address(0)) revert ZeroAddress();
        address oldVesting = vesting;
        vesting = vesting_;
        emit VestingChanged(oldVesting, vesting_);
    }

    function _sendNative(address receiver, uint256 amount) private {
        (bool success,) = payable(receiver).call{value: amount}("");
        if (!success) revert NativeTransferFailed();
    }
}

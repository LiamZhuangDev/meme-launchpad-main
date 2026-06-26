// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {LearningMEMEFactory} from "./LearningMEMEFactory.sol";

contract LearningMEMECore is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

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

    error AlreadyInitialized();
    error ZeroAddress();

    event Initialized(address indexed admin, address indexed signer, address indexed factory);
    event HelperChanged(address indexed oldHelper, address indexed newHelper);
    event VestingChanged(address indexed oldVesting, address indexed newVesting);

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
}

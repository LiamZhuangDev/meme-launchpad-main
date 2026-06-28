// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LearningMEMECore} from "../src/LearningMEMECore.sol";
import {LearningMEMEFactory} from "../src/LearningMEMEFactory.sol";
import {LearningMEMEToken} from "../src/LearningMEMEToken.sol";

contract Step03SignedTokenCreationTest is Test {
    uint256 private constant SIGNER_PRIVATE_KEY = 0xA11CE;

    LearningMEMEFactory private factory;
    LearningMEMECore private core;

    address private admin = makeAddr("admin");
    address private signer;
    address private platform = makeAddr("platform");
    address private creator = makeAddr("creator");
    address private caller = makeAddr("caller");

    function setUp() public {
        vm.warp(1_717_171_717);
        signer = vm.addr(SIGNER_PRIVATE_KEY);
        factory = new LearningMEMEFactory(admin);
        core = new LearningMEMECore();
        core.initialize(
            address(factory), makeAddr("helper"), signer, platform, makeAddr("margin"), makeAddr("graduate"), admin
        );

        vm.prank(admin);
        factory.setCore(address(core));

        vm.deal(caller, 10 ether);
    }

    function testValidSignedRequestDeploysAndRegistersToken() public {
        LearningMEMECore.CreateTokenParams memory params = _validParams();
        bytes memory data = abi.encode(params);
        bytes memory signature = _sign(data, SIGNER_PRIVATE_KEY, address(core));
        uint256 platformBalanceBefore = platform.balance;

        vm.prank(caller);
        address tokenAddress = core.createToken{value: core.creationFee()}(data, signature);

        LearningMEMEToken token = LearningMEMEToken(tokenAddress);
        assertEq(token.name(), params.name);
        assertEq(token.symbol(), params.symbol);
        assertEq(token.balanceOf(address(core)), params.totalSupply);
        assertEq(uint8(token.transferMode()), uint8(LearningMEMEToken.TransferMode.CONTROLLED));
        assertTrue(core.usedRequestIds(params.requestId));
        assertEq(platform.balance, platformBalanceBefore + core.creationFee());

        (
            address storedCreator,
            uint256 createdAt,
            uint256 launchTime,
            LearningMEMECore.TokenStatus status,
            address liquidityPool
        ) = core.tokenInfo(tokenAddress);
        assertEq(storedCreator, creator);
        assertEq(createdAt, block.timestamp);
        assertEq(launchTime, params.launchTime);
        assertEq(uint8(status), uint8(LearningMEMECore.TokenStatus.TRADING));
        assertEq(liquidityPool, address(0));
    }

    function testRefundsPaymentAboveCreationFee() public {
        LearningMEMECore.CreateTokenParams memory params = _validParams();
        bytes memory data = abi.encode(params);
        bytes memory signature = _sign(data, SIGNER_PRIVATE_KEY, address(core));
        uint256 callerBalanceBefore = caller.balance;

        vm.prank(caller);
        core.createToken{value: 1 ether}(data, signature);

        assertEq(caller.balance, callerBalanceBefore - core.creationFee());
        assertEq(address(core).balance, 0);
    }

    function testRejectsInsufficientCreationFee() public {
        LearningMEMECore.CreateTokenParams memory params = _validParams();
        bytes memory data = abi.encode(params);
        bytes memory signature = _sign(data, SIGNER_PRIVATE_KEY, address(core));
        uint256 insufficientFee = core.creationFee() - 1;

        vm.prank(caller);
        vm.expectRevert(LearningMEMECore.InsufficientFee.selector);
        core.createToken{value: insufficientFee}(data, signature);
    }

    function testRejectsSignerWithoutSignerRole() public {
        LearningMEMECore.CreateTokenParams memory params = _validParams();
        bytes memory data = abi.encode(params);
        bytes memory signature = _sign(data, 0xB0B, address(core));
        uint256 fee = core.creationFee();

        vm.prank(caller);
        vm.expectRevert(LearningMEMECore.InvalidSigner.selector);
        core.createToken{value: fee}(data, signature);
    }

    function testRejectsExpiredRequest() public {
        LearningMEMECore.CreateTokenParams memory params = _validParams();
        params.timestamp = block.timestamp - core.REQUEST_EXPIRY() - 1;
        bytes memory data = abi.encode(params);
        bytes memory signature = _sign(data, SIGNER_PRIVATE_KEY, address(core));
        uint256 fee = core.creationFee();

        vm.prank(caller);
        vm.expectRevert(LearningMEMECore.RequestExpired.selector);
        core.createToken{value: fee}(data, signature);
    }

    function testRejectsReplayedRequestId() public {
        LearningMEMECore.CreateTokenParams memory params = _validParams();
        bytes memory data = abi.encode(params);
        bytes memory signature = _sign(data, SIGNER_PRIVATE_KEY, address(core));
        uint256 fee = core.creationFee();

        vm.prank(caller);
        core.createToken{value: fee}(data, signature);

        vm.prank(caller);
        vm.expectRevert(LearningMEMECore.RequestAlreadyProcessed.selector);
        core.createToken{value: fee}(data, signature);
    }

    function testSignatureIsBoundToCoreAddress() public {
        LearningMEMECore.CreateTokenParams memory params = _validParams();
        bytes memory data = abi.encode(params);
        address differentCore = makeAddr("differentCore");
        bytes memory signature = _sign(data, SIGNER_PRIVATE_KEY, differentCore);
        uint256 fee = core.creationFee();

        vm.prank(caller);
        vm.expectRevert(LearningMEMECore.InvalidSigner.selector);
        core.createToken{value: fee}(data, signature);
    }

    function _validParams() private view returns (LearningMEMECore.CreateTokenParams memory) {
        return LearningMEMECore.CreateTokenParams({
            name: "Signed Meme",
            symbol: "SIGN",
            totalSupply: 1_000_000 ether,
            saleAmount: 800_000 ether,
            virtualBNBReserve: 10 ether,
            virtualTokenReserve: 1_000_000 ether,
            launchTime: block.timestamp + 1 hours,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("step-03-request"),
            nonce: 3,
            initialBuyPercentage: 0,
            vestingAllocations: new LearningMEMECore.VestingAllocation[](0)
        });
    }

    function _sign(bytes memory data, uint256 privateKey, address coreAddress) private view returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked(data, core.chainId(), coreAddress));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}

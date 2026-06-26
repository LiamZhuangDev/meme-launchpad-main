// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LearningMEMEFactory} from "../src/LearningMEMEFactory.sol";
import {LearningMEMEToken} from "../src/LearningMEMEToken.sol";

contract Step01FactoryAndTokenTest is Test {
    LearningMEMEFactory private factory;

    address private admin = address(this);
    address private pair = makeAddr("pair");
    address private user = makeAddr("user");

    function setUp() public {
        factory = new LearningMEMEFactory(admin);
        factory.setCore(address(this));
    }

    function testFactoryDeploysTokenAtPredictedAddress() public {
        uint256 totalSupply = 1_000_000 ether;
        uint256 timestamp = 1_717_171_717;
        uint256 nonce = 42;

        address predicted =
            factory.predictTokenAddress("Learning Meme", "LMEME", totalSupply, address(this), timestamp, nonce);

        address deployed = factory.deployToken("Learning Meme", "LMEME", totalSupply, timestamp, nonce);

        assertEq(deployed, predicted);
        assertEq(LearningMEMEToken(deployed).balanceOf(address(this)), totalSupply);
        assertEq(uint8(LearningMEMEToken(deployed).transferMode()), uint8(LearningMEMEToken.TransferMode.RESTRICTED));
    }

    function testOnlyCoreCanChangeTokenControls() public {
        LearningMEMEToken token = _deployToken();

        vm.prank(user);
        vm.expectRevert(LearningMEMEToken.OnlyCore.selector);
        token.setTransferMode(LearningMEMEToken.TransferMode.NORMAL);

        token.setTransferMode(LearningMEMEToken.TransferMode.NORMAL);
        assertEq(uint8(token.transferMode()), uint8(LearningMEMEToken.TransferMode.NORMAL));
    }

    function testTransferModesProtectLaunchLifecycle() public {
        LearningMEMEToken token = _deployToken();

        vm.expectRevert(LearningMEMEToken.TransferRestricted.selector);
        token.transfer(user, 1 ether);

        token.setTransferMode(LearningMEMEToken.TransferMode.CONTROLLED);
        token.transfer(user, 1 ether);
        assertEq(token.balanceOf(user), 1 ether);

        token.setPair(pair);
        vm.expectRevert(LearningMEMEToken.TransferNotAllowedToPair.selector);
        token.transfer(pair, 1 ether);

        token.setTransferMode(LearningMEMEToken.TransferMode.NORMAL);
        token.transfer(pair, 1 ether);
        assertEq(token.balanceOf(pair), 1 ether);
    }

    function testOnlyFactoryDeployerRoleCanDeploy() public {
        vm.prank(user);
        vm.expectRevert();
        factory.deployToken("Bad", "BAD", 1 ether, block.timestamp, 1);
    }

    function _deployToken() private returns (LearningMEMEToken) {
        address deployed = factory.deployToken("Learning Meme", "LMEME", 1_000_000 ether, block.timestamp, 1);
        return LearningMEMEToken(deployed);
    }
}

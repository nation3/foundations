// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";
import {IVotingEscrow, Point} from "../governance/IVotingEscrow.sol";

import {VotingStrategy} from "../governance/VotingStrategy.sol";

contract IntegrationTest is DSTestPlus {
    Vm public vm = Vm(HEVM_ADDRESS);

    string public MAINNET_RPC_URL = "https://mainnet.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161";
    uint256 public forkId;

    address address1 = 0x636d65212C815b93B8E5b069f7082169cec851b7;
    address address2 = 0xD7E7638a352192Eb5e472ABe4b8D2edFfEDBc4E7;

    VotingStrategy strategy;
    IVotingEscrow veToken = IVotingEscrow(0xF7deF1D2FBDA6B74beE7452fdf7894Da9201065d);

    function setUp() public {
        forkId = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(forkId);
        strategy = new VotingStrategy();
    }

    function testCheckpoint() public {
        console2.log("Supply Point Epoch: %s", strategy.getSupplyPointEpoch());

        strategy._checkpoint(address2);

        uint256 supplyPoint = strategy.totalSupply();

        console2.log("Total voting power: %s", supplyPoint);

        assertEq(supplyPoint, veToken.balanceOf(address2));

        console2.log("Supply Point Epoch: %s", strategy.getSupplyPointEpoch());

        strategy._checkpoint(address1);

        console2.log("Supply Point Epoch: %s", strategy.getSupplyPointEpoch());

        supplyPoint = strategy.totalSupply();

        console2.log("Total voting power: %s", supplyPoint);

        uint256 sumBalance = veToken.balanceOf(address2) + veToken.balanceOf(address1);

        console2.log("Sum of balances %s", sumBalance);

        assertEq(supplyPoint, sumBalance);
    }

    function testCheckpoint2() public {
        console2.log("Supply Point Epoch: %s", strategy.getSupplyPointEpoch());

        strategy._checkpoint(address1);

        uint256 supplyPoint = strategy.totalSupply();

        console2.log("Total voting power: %s", supplyPoint);

        console2.log("Supply Point Epoch: %s", strategy.getSupplyPointEpoch());

        vm.prank(address1, address1);

        veToken.increase_unlock_time(1709679600);

        strategy._checkpoint(address1);

        supplyPoint = strategy.totalSupply();

        console2.log("Total voting power: %s", supplyPoint);

        assertEq(supplyPoint, veToken.balanceOf(address1));

        console2.log("Supply Point Epoch: %s", strategy.getSupplyPointEpoch());
    }

    function testCheckpoint3() public {
        console2.log("Supply Point Epoch: %s", strategy.getSupplyPointEpoch());

        strategy._checkpoint(address2);
        strategy._checkpoint(address1);

        console2.log("Balance before: %s", veToken.balanceOf(address1));

        vm.prank(address1, address1);
        veToken.increase_unlock_time(1709679600);

        console2.log("Balance after: %s", veToken.balanceOf(address1));

        strategy._checkpoint(address1);

        uint256 supplyPoint = strategy.totalSupply();

        uint256 sumBalance = veToken.balanceOf(address2) + veToken.balanceOf(address1);

        console2.log("Sum of balances %s", sumBalance);

        assertEq(supplyPoint, sumBalance);
    }

    function testBalanceOf() public {
        strategy._checkpoint(address1);

        assertEq(strategy.balanceOf(address1), veToken.balanceOf(address1));
    }

    function testBalanceOfAt() public {
        strategy._checkpoint(address1);

        // Checkpoint was made now. There is no voting power 100 block ago.
        assertEq(strategy.balanceOfAt(address1, block.number - 100), 0);
    }

    function testBalanceOfAt2() public {
        strategy._checkpoint(address1);
        vm.roll(block.number + 100);

        assertEq(strategy.balanceOfAt(address1, block.number), veToken.balanceOfAt(address1, block.number));
    }

    function testTotalSupply() public {
        strategy._checkpoint(address1);
        vm.roll(block.number + 100);

        console2.log("Total supply at %s: %s", block.number, strategy.totalSupplyAt(block.number));
        console2.log("Balance of at %s: %s", block.number, strategy.balanceOfAt(address1, block.number));

        assertEq(strategy.balanceOfAt(address1, block.number), strategy.totalSupplyAt(block.number));
    }

    function testTotalSupply2() public {
        strategy._checkpoint(address1);
        strategy._checkpoint(address2);

        vm.roll(block.number + 100);

        console2.log("Total supply at %s: %s", block.number, strategy.totalSupplyAt(block.number));
        console2.log("Balance of addr1 at %s: %s", block.number, strategy.balanceOfAt(address1, block.number));
        console2.log("Balance of addr2 at %s: %s", block.number, strategy.balanceOfAt(address2, block.number));

        uint256 votingPowerSum = strategy.balanceOfAt(address1, block.number) +
            strategy.balanceOfAt(address2, block.number);
        assertEq(votingPowerSum, strategy.totalSupplyAt(block.number));
    }
}

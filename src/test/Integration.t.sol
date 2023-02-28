// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {Vm} from "forge-std/Vm.sol";
import {IVotingEscrow} from "../governance/IVotingEscrow.sol";

contract IntegrationTest is DSTestPlus {
    Vm public vm = Vm(HEVM_ADDRESS);

    string public MAINNET_RPC_URL = "https://mainnet.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161";
    uint256 public forkId;
    
    function setUp() public {
        forkId = vm.createFork(MAINNET_RPC_URL);
    }

    function test() public {
        vm.selectFork(forkId);
        
        IVotingEscrow veToken = IVotingEscrow(0xF7deF1D2FBDA6B74beE7452fdf7894Da9201065d);

        assertEq(veToken.totalSupply(1677616845), 2150156121074342113005);
    }
}
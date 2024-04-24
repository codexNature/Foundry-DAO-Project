// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {GovToken} from "../src/GovToken.sol";
import {Box} from "../src/Box.sol";
import {TimeLock} from "../src/TimeLock.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";


contract MyGovernorTest is Test {
    MyGovernor governor;
    Box box;
    TimeLock timelock;
    GovToken token;

    address public USER = makeAddr("user");
    address public VOTER = makeAddr("voter");
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    address[] proposers;
    address[] executors;

    uint256[] values;
    bytes[] functionCalls;
    address[] targets;

    uint256 public constant MIN_DELAY = 3600; // 1 hour after a vote passes
    uint256 public constant VOTING_DELAY = 1; // how many blocks till the ghost 
    uint256 public constant VOTING_PERIOD = 50400;

    function setUp() public {
        token = new GovToken();
        token.mint(USER, INITIAL_SUPPLY);
        token.delegate(USER);

        vm.startPrank(USER);
        token.delegate(USER);

        timelock = new TimeLock(MIN_DELAY, proposers, executors);
        governor = new MyGovernor(token, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, USER);
        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timelock));
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 889;
        string memory description = "store 1 in Box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);

        values.push(0);
        functionCalls.push(encodedFunctionCall);
        targets.push(address(box));

        //1. propose to the DAO
        uint256 proposalId = governor.propose(targets, values, functionCalls, description);

        //View the state
        console.log("Proposal State: ", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 7200);
        vm.roll(block.number + VOTING_DELAY + 7200);

        console.log("Proposal State: ", uint256(governor.state(proposalId)));

        // 2. Vote on the proposal
        string memory reason = "cus blue fros is cool";
        uint8 voteWay = 1;
        
        vm.prank(USER);
        governor.castVoteWithReason(proposalId, voteWay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD);
        vm.roll(block.number + VOTING_PERIOD);

        //3. Queue the transaction
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, functionCalls, descriptionHash);

        vm.roll(block.number + MIN_DELAY + 1);
        vm.warp(block.number + MIN_DELAY + 1);

        // 4. Execute
        governor.execute(targets, values, functionCalls, descriptionHash);
        console.log("Box Value: ", box.readNumber());
        assert(box.readNumber() == valueToStore);

        // console.log("Box value: ", box.getNumber());
        // assert(box.getNumber() == valueToStore);
    }
}

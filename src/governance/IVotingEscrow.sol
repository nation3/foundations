// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

struct Point {
    uint128 bias;
    uint128 slope;
    uint256 ts;
    uint256 blk;
}

interface IVotingEscrow {
    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    function user_point_history(address, uint256) external view returns (Point memory);

    function user_point_epoch(address) external view returns (uint256);

    function increase_unlock_time(uint256) external;

    function point_history(uint256) external view returns (Point memory);

    function locked(address) external view returns (LockedBalance memory);

    function balanceOf(address) external view returns (uint256);

    function totalSupply(uint256) external view returns (uint256);

    function balanceOfAt(address, uint256) external view returns (uint256);

    function totalSupplyAt(uint256) external view returns (uint256);
}

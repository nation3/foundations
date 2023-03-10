// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {PassportIssuer} from "../passport/PassportIssuer.sol";
import {IVotingEscrow, Point} from "./IVotingEscrow.sol";

contract VotingStrategy {
    error DelegateIsNotPassportHolder();
    error AlreadyDelegatedToThisAddress();

    PassportIssuer public passportIssuer;
    IVotingEscrow public veToken;

    mapping(address => mapping(uint256 => Point)) internal _userPointHistory;
    mapping(address => uint256) internal _userPointEpoch; // last epoch for a given user
    mapping(address => uint256) internal _userVeTokenEpoch; // VeToken epoch

    mapping(uint256 => Point) internal _supplyPointHistory;
    uint256 internal _supplyPointEpoch; // last epoch of total supply

    mapping(address => address) internal _representativeOf;
    // mapping(address => address[]) internal _proxyOf;
    mapping(address => mapping(uint256 => Point)) internal _representativePointHistory;
    mapping(address => uint256) internal _representativePointEpoch;

    constructor() {
        passportIssuer = PassportIssuer(0x279c0b6bfCBBA977eaF4ad1B2FFe3C208aa068aC);
        veToken = IVotingEscrow(0xF7deF1D2FBDA6B74beE7452fdf7894Da9201065d);
    }

    function getSupplyPointEpoch() external view returns (uint256) {
        return _supplyPointEpoch;
    }

    function registerVotingPower(address holder, address representative) external {
        if (passportIssuer.passportStatus(representative) != 1) revert DelegateIsNotPassportHolder();

        _checkpoint(holder, representative);
    }

    function _checkpoint(address holder, address representative) public {
        // USER CHECKPOINT //
        uint256 veUserEpoch = veToken.user_point_epoch(holder);
        //uint256 userEpoch = _userPointEpoch[holder];

        uint256 registeredVeEpoch = _userVeTokenEpoch[holder];

        Point memory previousUserPoint;
        Point memory userPoint;

        if (registeredVeEpoch == veUserEpoch) {
            // no need to query veToken as balance remains the same
            userPoint = _userPointHistory[holder][_userPointEpoch[holder]];
        } else if (veUserEpoch > registeredVeEpoch) {
            // TODO: maybe this can be removed? registeredEpoch can't be > veUserEpoch
            userPoint = veToken.user_point_history(holder, veUserEpoch);
        }

        userPoint.bias -= userPoint.slope * uint128(block.timestamp - userPoint.ts);

        userPoint.ts = block.timestamp;
        userPoint.blk = block.number;

        _userPointHistory[holder][++_userPointEpoch[holder]] = userPoint;

        _userVeTokenEpoch[holder] = veUserEpoch;

        // Epoch 1 is the first lock. Epoch 0 (no lock) is always Point(0,0,0,0)
        // If epoch > 1, then user has locked before and we need to calculate the
        // delta between the last lock and new lock.
        if (veUserEpoch > 1) {
            previousUserPoint = veToken.user_point_history(holder, veUserEpoch - 1);

            if (block.timestamp > previousUserPoint.ts) {
                previousUserPoint.bias -= previousUserPoint.slope * uint128(block.timestamp - previousUserPoint.ts);
            }
        }

        // REPRESENTATIVE CHECKPOINT //
        uint256 representativeEpoch = _representativePointEpoch[representative];

        Point memory representativePoint = Point({bias: 0, slope: 0, ts: block.timestamp, blk: block.number});

        if (representativeEpoch > 0) {
            representativePoint = _representativePointHistory[representative][representativeEpoch];
        }

        representativePoint.bias -= representativePoint.slope * uint128(block.timestamp - representativePoint.ts);

        address oldRepresentative = _representativeOf[holder];

        if (oldRepresentative == representative) {
            representativePoint.bias += (userPoint.bias - previousUserPoint.bias);
            representativePoint.slope += (userPoint.slope - previousUserPoint.slope);
        } else if (oldRepresentative == address(0)) {
            representativePoint.bias += userPoint.bias;
            representativePoint.slope += userPoint.slope;
        } else {
            // New non-null representative

            representativePoint.bias += userPoint.bias;
            representativePoint.slope += userPoint.slope;

            uint256 oldRepresentativeEpoch = _representativePointEpoch[oldRepresentative];

            Point memory oldRepresentativePoint = Point({bias: 0, slope: 0, ts: block.timestamp, blk: block.number});

            if (oldRepresentativeEpoch > 0) {
                oldRepresentativePoint = _representativePointHistory[oldRepresentative][oldRepresentativeEpoch];
            }

            oldRepresentativePoint.bias -=
                oldRepresentativePoint.slope *
                uint128(block.timestamp - oldRepresentativePoint.ts);

            oldRepresentativePoint.bias -= userPoint.bias;
            oldRepresentativePoint.slope -= userPoint.slope;

            oldRepresentativePoint.ts = block.timestamp;
            oldRepresentativePoint.blk = block.number;

            _representativePointHistory[oldRepresentative][
                ++_representativePointEpoch[oldRepresentative]
            ] = oldRepresentativePoint;

            _representativeOf[holder] = representative;
        }

        representativePoint.ts = block.timestamp;
        representativePoint.blk = block.number;

        _representativePointHistory[representative][++_representativePointEpoch[representative]] = representativePoint;

        // SUPPLY CHECKPOINT //
        Point memory supplyPoint = Point({bias: 0, slope: 0, ts: block.timestamp, blk: block.number});

        if (_supplyPointEpoch > 0) {
            supplyPoint = _supplyPointHistory[_supplyPointEpoch];
        }

        supplyPoint.bias -= supplyPoint.slope * uint128(block.timestamp - supplyPoint.ts);

        // Delta decay for this user needs to be added to the supply point
        supplyPoint.bias += (userPoint.bias - previousUserPoint.bias);
        supplyPoint.slope += (userPoint.slope - previousUserPoint.slope);

        supplyPoint.ts = block.timestamp;
        supplyPoint.blk = block.number;

        _supplyPointHistory[++_supplyPointEpoch] = supplyPoint;
    }

    function balanceOf(address _address) external view returns (uint256) {
        uint256 representativeEpoch = _representativePointEpoch[_address];

        if (representativeEpoch == 0) return 0;

        Point memory representativePoint = _representativePointHistory[_address][representativeEpoch];

        return
            representativePoint.bias - (representativePoint.slope * uint128(block.timestamp - representativePoint.ts));
    }

    function totalSupply() external view returns (uint256) {
        Point memory lastSupplyPoint = _supplyPointHistory[_supplyPointEpoch];

        return lastSupplyPoint.bias - (lastSupplyPoint.slope * uint128(block.timestamp - lastSupplyPoint.ts));
    }

    function balanceOfAt(address _address, uint256 _block) external view returns (uint256) {
        assert(_block <= block.number);

        uint256 _min = 0;
        uint256 _max = _representativePointEpoch[_address];

        for (uint256 i = 0; i < 128; i++) {
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (_representativePointHistory[_address][_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }

        Point memory representativePoint = _representativePointHistory[_address][_min];
        uint256 maxEpoch = _supplyPointEpoch;

        uint256 _epoch = _findBlockEpoch(_block, maxEpoch);
        Point memory point0 = _supplyPointHistory[_epoch];

        uint256 deltaBlock = 0;
        uint256 deltaTs = 0;
        if (_epoch < maxEpoch) {
            Point memory point1 = _supplyPointHistory[_epoch + 1];
            deltaBlock = point1.blk - point0.blk;
            deltaTs = point1.ts - point0.ts;
        } else {
            deltaBlock = block.number - point0.blk;
            deltaTs = block.timestamp - point0.ts;
        }
        uint256 blockTime = point0.ts;
        if (deltaBlock != 0) {
            blockTime += (deltaTs * (_block - point0.blk)) / deltaBlock;
        }

        return representativePoint.bias - representativePoint.slope * uint128(blockTime - representativePoint.ts);
    }

    function totalSupplyAt(uint256 _block) public view returns (uint256) {
        assert(_block <= block.number);
        uint256 epoch = _supplyPointEpoch;
        uint256 targetEpoch = _findBlockEpoch(_block, epoch);

        Point memory point = _supplyPointHistory[targetEpoch];
        uint256 deltaTs = 0;

        if (targetEpoch < epoch) {
            Point memory pointNext = _supplyPointHistory[targetEpoch + 1];
            if (point.blk != pointNext.blk) {
                deltaTs = ((_block - point.blk) * (pointNext.ts - point.ts)) / (pointNext.blk - point.blk);
            }
        } else {
            if (point.blk != block.number) {
                deltaTs = ((_block - point.blk) * (block.timestamp - point.ts)) / (block.number - point.blk);
            }
        }

        return point.bias - point.slope * uint128(deltaTs);
    }

    function _findBlockEpoch(uint256 _block, uint256 maxEpoch) internal view returns (uint256) {
        uint256 _min = 0;
        uint256 _max = maxEpoch;
        for (uint256 i = 0; i < 128; i++) {
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (_supplyPointHistory[_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }

        return _min;
    }
}

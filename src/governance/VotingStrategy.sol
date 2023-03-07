// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {PassportIssuer} from "../passport/PassportIssuer.sol";
import {IVotingEscrow, Point} from "./IVotingEscrow.sol";
// Remove this import
import {console2} from "forge-std/console2.sol";

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

    // This is still a WIP. It's messy af

    //
    function registerVotingPower(address representative) external {
        if (passportIssuer.passportStatus(representative) != 1) revert DelegateIsNotPassportHolder();

        /*
        address oldRepresentative = _representativeOf[msg.sender];

        _userCheckpoint(msg.sender); */
        /* address oldProxy = _delegateOf[msg.sender];

        if (oldProxy != address(0)) {
            if (oldProxy == delegateTo) revert AlreadyDelegatedToThisAddress();

            // Remove delegate from old proxy
            for (uint256 i = 0; i < _proxyOf[delegateTo].length; ++i) {
                if (_proxyOf[delegateTo][i] == msg.sender) {
                    _proxyOf[delegateTo][i] = _proxyOf[delegateTo][_proxyOf[delegateTo].length - 1];
                    _proxyOf[delegateTo].pop();
                    break;
                }
            }
        } */
        // Add delegate to new proxy
        /* _delegateOf[msg.sender] = delegateTo;
        _proxyOf[delegateTo].push(msg.sender); */
    }

    function _checkpoint(address _address, address representative) external {
        // USER CHECKPOINT //
        uint256 lastVeUserEpoch = veToken.user_point_epoch(_address);
        uint256 lastUserEpoch = _userPointEpoch[_address];

        uint256 lastRegisteredVeEpoch = _userVeTokenEpoch[_address];

        Point memory previousUserPoint;
        Point memory userPoint;

        if (lastRegisteredVeEpoch == lastVeUserEpoch) {
            // no need to query veToken
            userPoint = _userPointHistory[_address][lastUserEpoch];
        } else if (lastVeUserEpoch > lastRegisteredVeEpoch) {
            userPoint = veToken.user_point_history(_address, lastVeUserEpoch);
        }

        userPoint.bias -= userPoint.slope * uint128(block.timestamp - userPoint.ts);
        userPoint.ts = block.timestamp;
        userPoint.blk = block.number;

        _userPointHistory[_address][lastUserEpoch + 1] = userPoint;

        // TODO: Check else if above ^ for correctness

        _userVeTokenEpoch[_address] = lastVeUserEpoch;
        _userPointEpoch[_address] += 1;

        // Epoch 1 is the first time a user votes.
        // Epoch 0 is always Point(0,0,0,0)
        if (lastVeUserEpoch > 1) {
            previousUserPoint = veToken.user_point_history(_address, lastVeUserEpoch - 1);

            if (block.timestamp > previousUserPoint.ts) {
                previousUserPoint.bias -= previousUserPoint.slope * uint128(block.timestamp - previousUserPoint.ts);
            }
        }
        // REPRESENTATIVE CHECKPOINT //

        address oldRepresentative = _representativeOf[_address];

        Point memory currentRepresentativePoint = Point({bias: 0, slope: 0, ts: block.timestamp, blk: block.number});

        uint256 lastRepresentativeEpoch = _representativePointEpoch[representative];

        if (lastRepresentativeEpoch > 0) {
            currentRepresentativePoint = _representativePointHistory[lastRepresentativeEpoch];
        }

        currentRepresentativePoint.bias -=
            currentRepresentativePoint.slope *
            uint128(block.timestamp - currentRepresentativePoint.ts);

        if (oldRepresentative == representative) {
            // We need to add the delta slope for this user
            // to the contract's slope
            currentRepresentativePoint.bias += (userPoint.bias - previousUserPoint.bias);
            currentRepresentativePoint.slope += (userPoint.slope - previousUserPoint.slope);
        } else if (oldRepresentative == address(0)) {
            currentRepresentativePoint.bias += userPoint.bias;
            currentRepresentativePoint.slope += userPoint.slope;
        } else {
            // new non-null representative
            currentRepresentativePoint.bias += userPoint.bias;
            currentRepresentativePoint.slope += userPoint.slope;

            Point memory oldRepresentativePoint = Point({bias: 0, slope: 0, ts: block.timestamp, blk: block.number});

            uint256 oldRepresentativeEpoch = _representativePointEpoch[oldRepresentative];

            if (oldRepresentativeEpoch > 0) {
                oldRepresentativePoint = _representativePointHistory[oldRepresentativeEpoch];
            }

            oldRepresentativePoint.bias -=
                oldRepresentativePoint.slope *
                uint128(block.timestamp - oldRepresentativePoint.ts);

            oldRepresentativePoint.bias -= userPoint.bias;
            oldRepresentativePoint.slope -= userPoint.slope;

            oldRepresentativePoint.ts = block.timestamp;
            oldRepresentativePoint.blk = block.number;

            _representativeOf[_address] = representative;
        }

        lastRepresentativePoint.ts = block.timestamp;
        lastRepresentativePoint.blk = block.number;

        _representativePointHistory[++lastRepresentativeEpoch] = lastRepresentativePoint;

        // SUPPLY CHECKPOINT //
        Point memory lastPoint = Point({bias: 0, slope: 0, ts: block.timestamp, blk: block.number});

        if (_supplyPointEpoch > 0) {
            lastPoint = _supplyPointHistory[_supplyPointEpoch];
        }

        lastPoint.bias -= lastPoint.slope * uint128(block.timestamp - lastPoint.ts);

        // We need to add the delta slope for this user
        // to the contract's slope
        lastPoint.bias += (userPoint.bias - previousUserPoint.bias);
        lastPoint.slope += (userPoint.slope - previousUserPoint.slope);

        lastPoint.ts = block.timestamp;
        lastPoint.blk = block.number;

        _supplyPointHistory[++_supplyPointEpoch] = lastPoint;
    }

    function balanceOf(address _address) external view returns (uint256) {
        uint256 lastUserEpoch = _userPointEpoch[_address];

        if (lastUserEpoch == 0) return 0;

        Point memory userPoint = _userPointHistory[_address][lastUserEpoch];

        return userPoint.bias - (userPoint.slope * uint128(block.timestamp - userPoint.ts));
    }

    function totalSupply() external view returns (uint256) {
        Point memory lastSupplyPoint = _supplyPointHistory[_supplyPointEpoch];

        return lastSupplyPoint.bias - (lastSupplyPoint.slope * uint128(block.timestamp - lastSupplyPoint.ts));
    }

    function balanceOfAt(address _address, uint256 _block) external view returns (uint256) {
        assert(_block <= block.number);

        uint256 _min = 0;
        uint256 _max = _userPointEpoch[_address];
        for (uint256 i = 0; i < 128; i++) {
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (_userPointHistory[_address][_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }

        Point memory userPoint = _userPointHistory[_address][_min];
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

        return userPoint.bias - userPoint.slope * uint128(blockTime - userPoint.ts);
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

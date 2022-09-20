// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}
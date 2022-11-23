// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

library AddressArray {
    function concat(address[] memory self, address[] memory array) internal pure returns (address[] memory) {
        address[] memory newArray = new address[](self.length+array.length);
        for (uint i = 0; i<self.length; i++) {
            newArray[i] = self[i];
        }
        for (uint i = 0; i<array.length; i++) {
            newArray[i+self.length] = array[i];
        }
        return newArray;
    }

    function append(address[] memory self, address element) internal pure returns (address[] memory) {
        address[] memory newArray = new address[](self.length+1);
        for (uint i = 0; i<self.length; i++) {
            newArray[i] = self[i];
        }
        newArray[self.length] = element;
        return newArray;
    }

    function findAll(address[] memory self, address toFind) internal pure returns (uint[] memory) {
        uint[] memory indices;
        uint numMatching;
        for (uint i = 0; i<self.length; i++) {
            if (self[i]==toFind) {
                numMatching+=1;
            }
        }
        if (numMatching==0) {
            return indices;
        }
        indices = new uint[](numMatching);
        uint numPushed = 0;
        for (uint i = 0; i<self.length; i++) {
            if (self[i]==toFind) {
                indices[numPushed] = i;
                numPushed+=1;
                if (numPushed==numMatching) {
                    return indices;
                }
            }
        }
        return indices;
    }

    function findFirst(address[] memory self, address toFind) internal pure returns (uint) {
        for (uint i = 0; i<self.length; i++) {
            if (self[i]==toFind) {
                return i;
            }
        }
        return self.length;
    }

    function exists(address[] memory self, address toFind) internal pure returns (bool) {
        for (uint i = 0; i<self.length; i++) {
            if (self[i]==toFind) {
                return true;
            }
        }
        return false;
    }
}
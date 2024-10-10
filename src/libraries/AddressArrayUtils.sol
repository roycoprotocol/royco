// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Address Array Utilities Library
/// @notice Provides utility functions for working with arrays of addresses
/// @dev Includes functionality to check for duplicates and sort address arrays
library AddressArrayUtils {

    /// @notice Checks if an array of addresses contains any duplicates
    /// @param addressArray The array of addresses to check for duplicates
    /// @return bool True if duplicates are found, false otherwise
    function hasDuplicates(address[] memory addressArray) internal pure returns (bool) {
        if (addressArray.length <= 1) {
            return false;
        }
        
        // Sort the array
        quickSort(addressArray, 0, int(addressArray.length - 1));
        
        // Check for adjacent duplicates
        for (uint i = 1; i < addressArray.length; i++) {
            if (addressArray[i] == addressArray[i-1]) {
                return true;
            }
        }
        
        return false;
    }

    /// @notice Sorts an array of addresses using the quicksort algorithm
    /// @param arr The array to be sorted
    /// @param left The starting index of the array portion to be sorted
    /// @param right The ending index of the array portion to be sorted
    function quickSort(address[] memory arr, int left, int right) private pure {
        int i = left;
        int j = right;
        if (i == j) return;
        address pivot = arr[uint(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint(i)] < pivot) i++;
            while (pivot < arr[uint(j)]) j--;
            if (i <= j) {
                // Swap elements
                (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                i++;
                j--;
            }
        }
        if (left < j)
            quickSort(arr, left, j);
        if (i < right)
            quickSort(arr, i, right);
    }

    /// @notice Sorts an array of addresses in ascending order
    /// @param addressArray The array of addresses to be sorted
    function sort(address[] memory addressArray) internal pure {
        quickSort(addressArray, 0, int(addressArray.length - 1));
    }
}

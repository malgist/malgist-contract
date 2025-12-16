// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LeaderboardLib
 * @notice Library for efficient on-chain leaderboard sorting and ranking
 * @dev Uses a simple insertion sort optimized for small datasets (top-N strategies)
 */
library LeaderboardLib {
    /**
     * @notice Leaderboard entry for ranking
     */
    struct LeaderboardEntry {
        address user;
        uint256 value;
    }

    /**
     * @notice Sort array of entries by value in descending order
     * @dev Uses insertion sort - O(n²) but efficient for small n (typically < 100)
     * @param entries Array of leaderboard entries to sort
     * @param maxLength Maximum length to consider
     * @return Sorted entries in descending order by value
     */
    function sortDescending(LeaderboardEntry[] memory entries, uint256 maxLength)
        internal
        pure
        returns (LeaderboardEntry[] memory)
    {
        uint256 length = entries.length < maxLength ? entries.length : maxLength;

        // Insertion sort
        for (uint256 i = 1; i < length; i++) {
            LeaderboardEntry memory key = entries[i];
            int256 j = int256(i) - 1;

            while (j >= 0 && entries[uint256(j)].value < key.value) {
                entries[uint256(j) + 1] = entries[uint256(j)];
                j--;
            }
            entries[uint256(j) + 1] = key;
        }

        return entries;
    }

    /**
     * @notice Get top-N entries from unsorted array without modifying original
     * @param entries Array of entries to rank
     * @param topN Number of top entries to return
     * @return topEntries Top N entries sorted descending by value
     */
    function getTopN(LeaderboardEntry[] memory entries, uint256 topN)
        internal
        pure
        returns (LeaderboardEntry[] memory topEntries)
    {
        uint256 length = entries.length < topN ? entries.length : topN;
        topEntries = new LeaderboardEntry[](length);

        // Copy entries to new array
        for (uint256 i = 0; i < length; i++) {
            topEntries[i] = entries[i];
        }

        // Sort the copy
        topEntries = sortDescending(topEntries, length);

        return topEntries;
    }

    /**
     * @notice Calculate ranking percentile for a given value
     * @param value The value to rank
     * @param entries Array of all values
     * @return percentile Percentile ranking (0-10000 basis points)
     */
    function getPercentile(uint256 value, uint256[] memory entries) internal pure returns (uint256 percentile) {
        if (entries.length == 0) return 10000;

        uint256 countAbove = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i] > value) {
                countAbove++;
            }
        }

        // Percentile = (entries above / total entries) * 10000
        percentile = ((entries.length - countAbove) * 10000) / entries.length;
    }
}

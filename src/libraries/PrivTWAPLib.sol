// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64, euint32, ebool, InEuint64, InEuint32} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/// @title PrivTWAPLib
/// @notice Library for privacy-preserving Time-Weighted Average Price calculations
/// @dev Uses Fhenix FHE to maintain encrypted price observations
library PrivTWAPLib {
    using FHE for euint64;
    using FHE for euint32;

    /// @notice Encrypted price observation structure
    struct PrivateObservation {
        euint64 priceCumulative;    // Encrypted cumulative price
        euint32 timestamp;           // Encrypted timestamp
        bool initialized;            // Whether this observation is initialized
    }

    /// @notice Oracle storage for encrypted TWAP data
    struct PrivateOracle {
        PrivateObservation current;
        PrivateObservation previous;
        euint64 lastUpdateTime;
    }

    /// @notice Initialize the private oracle with encrypted initial price
    /// @param oracle The oracle storage to initialize
    /// @param initialPrice Encrypted initial price
    /// @param initialTimestamp Encrypted initial timestamp
    function initialize(
        PrivateOracle storage oracle,
        InEuint64 calldata initialPrice,
        InEuint32 calldata initialTimestamp
    ) internal {
        oracle.current.priceCumulative = FHE.asEuint64(initialPrice);
        oracle.current.timestamp = FHE.asEuint32(initialTimestamp);
        oracle.current.initialized = true;
        
        // Initialize previous with same values
        oracle.previous.priceCumulative = FHE.asEuint64(initialPrice);
        oracle.previous.timestamp = FHE.asEuint32(initialTimestamp);
        oracle.previous.initialized = true;
        
        oracle.lastUpdateTime = FHE.asEuint64(FHE.asEuint32(initialTimestamp));
    }

    /// @notice Update the oracle with a new encrypted price observation
    /// @param oracle The oracle storage to update
    /// @param newPrice New encrypted price to add
    /// @param currentTimestamp Current encrypted timestamp
    function update(
        PrivateOracle storage oracle,
        euint64 newPrice,
        euint32 currentTimestamp
    ) internal {
        require(oracle.current.initialized, "Oracle not initialized");

        // Move current to previous
        oracle.previous = oracle.current;

        // Calculate time delta (encrypted)
        euint32 timeDelta = FHE.sub(
            currentTimestamp,
            oracle.current.timestamp
        );

        // Calculate price * timeDelta (encrypted multiplication)
        euint64 priceTimeProduct = FHE.mul(
            newPrice,
            FHE.asEuint64(timeDelta)
        );

        // Add to cumulative price (encrypted addition)
        oracle.current.priceCumulative = FHE.add(
            oracle.current.priceCumulative,
            priceTimeProduct
        );

        oracle.current.timestamp = currentTimestamp;
        oracle.lastUpdateTime = FHE.asEuint64(currentTimestamp);
    }

    /// @notice Compute encrypted TWAP between two observations
    /// @param oracle The oracle to read from
    /// @return Encrypted TWAP value
    function getEncryptedTWAP(
        PrivateOracle storage oracle
    ) internal view returns (euint64) {
        require(oracle.current.initialized && oracle.previous.initialized, "Oracle not ready");

        // Calculate time delta between observations
        euint32 timeDelta = FHE.sub(
            oracle.current.timestamp,
            oracle.previous.timestamp
        );

        // Calculate price delta
        euint64 priceDelta = FHE.sub(
            oracle.current.priceCumulative,
            oracle.previous.priceCumulative
        );

        // TWAP = priceDelta / timeDelta (encrypted division)
        // Note: For production, you'd want a fixed-point math library
        // This is simplified for demonstration
        euint64 twap = FHE.div(priceDelta, FHE.asEuint64(timeDelta));

        return twap;
    }

    /// @notice Check if oracle has enough data for TWAP calculation
    /// @param oracle The oracle to check
    /// @return True if oracle is ready
    function isReady(PrivateOracle storage oracle) internal view returns (bool) {
        return oracle.current.initialized && oracle.previous.initialized;
    }

    /// @notice Compare encrypted TWAP against an encrypted threshold
    /// @param oracle The oracle containing TWAP data
    /// @param threshold Encrypted threshold value
    /// @return Encrypted boolean result of comparison
    function exceedsThreshold(
        PrivateOracle storage oracle,
        euint64 threshold
    ) internal view returns (ebool) {
        if (!isReady(oracle)) {
            return FHE.asEbool(false);
        }

        euint64 twap = getEncryptedTWAP(oracle);
        
        // Use FHE comparison - returns encrypted boolean
        // For action triggers, we'd need to decrypt this or use it in encrypted control flow
        return FHE.gt(twap, threshold);
    }

    /// @notice Calculate percentage deviation between current price and TWAP
    /// @param currentPrice Current encrypted price
    /// @param twap Encrypted TWAP value
    /// @return Encrypted deviation percentage
    function calculateDeviation(
        euint64 currentPrice,
        euint64 twap
    ) internal pure returns (euint64) {
        // deviation = |currentPrice - twap| / twap * 100
        // This is simplified; production would need proper fixed-point math
        
        euint64 diff;
        // Handle both positive and negative deviations
        ebool isGreater = FHE.gt(currentPrice, twap);
        diff = FHE.select(
            isGreater,
            FHE.sub(currentPrice, twap),
            FHE.sub(twap, currentPrice)
        );

        // Scale by 100 for percentage
        euint64 scaled = FHE.mul(diff, FHE.asEuint64(100));
        
        // Divide by TWAP
        return FHE.div(scaled, twap);
    }
}

// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.9;

import "../interfaces/IPriceGate.sol";

/// @title A factory pattern for a price gate whose price increases exponentially on purchase and decays linearly thereafter
/// @author metapriest, adrian.wachel, marek.babiarz, radoslaw.gorecki
/// @notice This contract has no management key, anyone can add a gate
/// @dev Note passing thru the gate forwards all gas, so beneficiary can be a contract, possibly malicious
contract SpeedBumpPriceGate is IPriceGate {

    // this represents a single gate
    struct Gate {
        uint priceIncreaseFactor;
        uint priceIncreaseDenominator;
        uint lastPrice;
        uint decayFactor;
        uint priceFloor;
        uint lastPurchaseBlock;
        address beneficiary;
    }

    // array-like mapping of gate structs
    mapping (uint => Gate) public gates;
    // count the gates as they come in!
    uint public numGates;

    /// @notice Add a price gate to the list of available price gates
    /// @dev Anyone can call this, but it must be connected to MerkleIdentity via priceGateIndex to be used
    /// @dev The price increase factor is split into numerator and denominator to enable fractions (wow! I love fractions!)
    /// @param priceFloor the starting price and the lowest price that can be reached via decay
    /// @param priceDecay the per-block rate at which the price reduces until it hits the price floor
    /// @param priceIncrease the numerator of the factor by which the price multiplies when a purchase occurs
    /// @param priceIncreaseDenominator the denominator of the price increase factor
    /// @param beneficiary who receives the proceeds from a purchase
    function addGate(uint priceFloor, uint priceDecay, uint priceIncrease, uint priceIncreaseDenominator, address beneficiary) external {
        // prefix operator increments then evaluates
        Gate storage gate = gates[++numGates];
        gate.priceFloor = priceFloor;
        gate.decayFactor = priceDecay;
        gate.priceIncreaseFactor = priceIncrease;
        gate.priceIncreaseDenominator = priceIncreaseDenominator;
        gate.beneficiary = beneficiary;
    }

    /// @notice Get the cost of passing thru this gate
    /// @param index which gate are we talking about?
    /// @return _ethCost the amount of ether required to pass thru this gate
    function getCost(uint index) override public view returns (uint _ethCost) {
        Gate memory gate = gates[index];
        // compute the linear decay
        uint decay = gate.decayFactor * (block.number - gate.lastPurchaseBlock);
        // gate.lastPrice - decay < gate.priceFloor (left side could underflow)
        if (gate.lastPrice < decay + gate.priceFloor) {
            return gate.priceFloor;
        } else {
            return gate.lastPrice - decay;
        }
    }

    /// @notice Pass thru this gate, should be called by MerkleIndex
    /// @dev This can be called by anyone, devs can call it to test it on mainnet
    /// @param index which gate are we passing thru?
    function passThruGate(uint index, address) override external payable {
        uint price = getCost(index);
        require(msg.value >= price, 'Please send more ETH');

        // bump up the price
        Gate storage gate = gates[index];
        // multiply by the price increase factor
        gate.lastPrice = (price * gate.priceIncreaseFactor) / gate.priceIncreaseDenominator;
        // move up the reference
        gate.lastPurchaseBlock = block.number;

        // pass thru the ether
        if (msg.value > 0) {
            // use .call so we can send to contracts, for example gnosis safe, re-entrance is not a threat here
            (bool sent, bytes memory data) = gate.beneficiary.call{value: msg.value}("");
            require(sent, 'ETH transfer failed');
        }
    }
}

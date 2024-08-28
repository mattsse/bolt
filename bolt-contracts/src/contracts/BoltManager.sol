// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {IBaseDelegator} from "@symbiotic/interfaces/delegator/IBaseDelegator.sol";
import {Subnetwork} from "@symbiotic/contracts/libraries/Subnetwork.sol";
import {IVault} from "@symbiotic/interfaces/vault/IVault.sol";
import {MapWithTimeData} from "../lib/MapWithTimeData.sol";
import {IBoltValidators} from "../interfaces/IBoltValidators.sol";

contract BoltManager {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using MapWithTimeData for EnumerableMap.AddressToUintMap;
    using Subnetwork for address;

    /// @notice Validators registry, where validators are registered via their
    /// BLS pubkey and are assigned a sequence number.
    IBoltValidators public validators;

    /// @notice Set of Symbiotic operator addresses that have opted in to Bolt Protocol.
    EnumerableMap.AddressToUintMap private symbioticOperators;

    /// @notice Set of Symbiotic protocol vaults that have opted in to Bolt Protocol.
    EnumerableMap.AddressToUintMap private symbioticVaults;

    /// @notice Address of the Bolt network in Symbiotic Protocol.
    address public immutable BOLT_SYMBIOTIC_NETWORK;

    uint48 public constant EPOCH_DURATION = 1 days;
    uint48 public constant SLASHING_WINDOW = 7 days;

    uint48 public immutable START_TIMESTAMP;

    error InvalidQuery();
    error AlreadyRegistered();

    constructor(address _validators) {
        validators = IBoltValidators(_validators);
        START_TIMESTAMP = Time.timestamp();
    }

    /// @notice Get the start timestamp of an epoch.
    function getEpochStartTs(uint48 epoch) public view returns (uint48 timestamp) {
        return START_TIMESTAMP + epoch * EPOCH_DURATION;
    }

    /// @notice Get the epoch at a given timestamp.
    function getEpochAtTs(uint48 timestamp) public view returns (uint48 epoch) {
        return (timestamp - START_TIMESTAMP) / EPOCH_DURATION;
    }

    /// @notice Get the current epoch.
    function getCurrentEpoch() public view returns (uint48 epoch) {
        return getEpochAtTs(Time.timestamp());
    }

    /// @notice Allow an operator to signal opt-in to Bolt Protocol.
    function registerSymbioticOperator(address operator) public {
        if (symbioticOperators.contains(operator)) {
            revert AlreadyRegistered();
        }

        // TODO: check if the operator exists in the canonical symbiotic registry
        // and if it's opted in the Symbiotic Bolt network.
        // refer to SimpleMiddleware.sol L124

        symbioticOperators.add(operator);
        symbioticOperators.enable(operator);
    }

    /// @notice Allow a vault to signal opt-in to Bolt Protocol.
    function registerSymbioticVault(address vault) public {
        if (symbioticVaults.contains(vault)) {
            revert AlreadyRegistered();
        }

        // TODO: check if the vault exists in the canonical symbiotic registry
        // and if it's opted in the Symbiotic Bolt network.
        // refer to SimpleMiddleware.sol L175

        symbioticVaults.add(vault);
        symbioticVaults.enable(vault);
    }

    /// @notice Check if an operator is currently enabled to work in Bolt Protocol.
    function isSymbioticOperatorEnabled(address operator) public view returns (bool) {
        (uint48 enabledTime, uint48 disabledTime) = symbioticOperators.getTimes(operator);
        return enabledTime != 0 && disabledTime == 0;
    }

    /// @notice Check if an operator address is authorized to work for a validator,
    /// given the validator's pubkey hash. This function performs a lookup in the
    /// validators registry to check if they explicitly authorized the operator.
    function isSymbioticOperatorAuthorizedForValidator(
        address operator,
        bytes32 pubkeyHash
    ) public view returns (bool) {
        if (operator == address(0) || pubkeyHash == bytes32(0)) {
            revert InvalidQuery();
        }

        return validators.getValidatorByPubkeyHash(pubkeyHash).authorizedOperator == operator;
    }

    /// @notice Get the stake of an operator in Symbiotic protocol at a given timestamp.
    function getSymbioticOperatorStakeAt(address operator, uint48 timestamp) public view returns (uint256) {
        if (timestamp > Time.timestamp() || timestamp < START_TIMESTAMP) {
            revert InvalidQuery();
        }

        uint48 epochStartTs = getEpochStartTs(getEpochAtTs(timestamp));

        for (uint256 i = 0; i < symbioticVaults.length(); ++i) {
            (address vault, uint48 enabledTime, uint48 disabledTime) = symbioticVaults.atWithTimes(i);

            if (!_wasActiveAt(enabledTime, disabledTime, epochStartTs)) {
                continue;
            }

            return IBaseDelegator(IVault(vault).delegator()).stakeAt(
                // The stake for each subnetwork is stored in the vault's delegator contract.
                // stakeAt returns the stake of "operator" at "timestamp" for "network" (or subnetwork)
                // bytes(0) is hints, which we don't use.
                BOLT_SYMBIOTIC_NETWORK.subnetwork(0),
                operator,
                timestamp,
                new bytes(0)
            );
        }

        return 0;
    }

    /// @notice Check if a map entry was active at a given timestamp.
    function _wasActiveAt(uint48 enabledTime, uint48 disabledTime, uint48 timestamp) private pure returns (bool) {
        return enabledTime != 0 && enabledTime <= timestamp && (disabledTime == 0 || disabledTime >= timestamp);
    }
}

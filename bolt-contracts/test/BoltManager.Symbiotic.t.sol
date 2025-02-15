// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";

import {INetworkRegistry} from "@symbiotic/interfaces/INetworkRegistry.sol";
import {IOperatorRegistry} from "@symbiotic/interfaces/IOperatorRegistry.sol";
import {IVaultFactory} from "@symbiotic/interfaces/IVaultFactory.sol";
import {IVault} from "@symbiotic/interfaces/vault/IVault.sol";
import {IOptInService} from "@symbiotic/interfaces/service/IOptInService.sol";
import {IVaultConfigurator} from "@symbiotic/interfaces/IVaultConfigurator.sol";
import {IBaseDelegator} from "@symbiotic/interfaces/delegator/IBaseDelegator.sol";
import {IBaseSlasher} from "@symbiotic/interfaces/slasher/IBaseSlasher.sol";
import {IMetadataService} from "@symbiotic/interfaces/service/IMetadataService.sol";
import {INetworkRestakeDelegator} from "@symbiotic/interfaces/delegator/INetworkRestakeDelegator.sol";
import {INetworkMiddlewareService} from "@symbiotic/interfaces/service/INetworkMiddlewareService.sol";
import {ISlasherFactory} from "@symbiotic/interfaces/ISlasherFactory.sol";
import {IVetoSlasher} from "@symbiotic/interfaces/slasher/IVetoSlasher.sol";
import {IDelegatorFactory} from "@symbiotic/interfaces/IDelegatorFactory.sol";
import {IMigratablesFactory} from "@symbiotic/interfaces/common/IMigratablesFactory.sol";
import {Subnetwork} from "@symbiotic/contracts/libraries/Subnetwork.sol";

import {IBoltValidatorsV2} from "../src/interfaces/IBoltValidatorsV2.sol";
import {IBoltMiddlewareV1} from "../src/interfaces/IBoltMiddlewareV1.sol";
import {IBoltManagerV3} from "../src/interfaces/IBoltManagerV3.sol";

import {BoltParametersV1} from "../src/contracts/BoltParametersV1.sol";
import {BoltValidatorsV2} from "../src/contracts/BoltValidatorsV2.sol";
import {BoltManagerV3} from "../src/contracts/BoltManagerV3.sol";
import {BoltSymbioticMiddlewareV1} from "../src/contracts/BoltSymbioticMiddlewareV1.sol";
import {EnumerableMapV3} from "../src/lib/EnumerableMapV3.sol";
import {BLS12381} from "../src/lib/bls/BLS12381.sol";
import {BoltConfig} from "../src/lib/BoltConfig.sol";
import {ValidatorsLib} from "../src/lib/ValidatorsLib.sol";
import {Utils} from "./Utils.sol";

import {SymbioticSetupFixture} from "./fixtures/SymbioticSetup.f.sol";
import {Token} from "../test/mocks/Token.sol";

contract BoltManagerSymbioticTest is Test {
    using BLS12381 for BLS12381.G1Point;
    using Subnetwork for address;

    uint48 public constant EPOCH_DURATION = 1 days;
    uint48 public constant SLASHING_WINDOW = 7 days;

    uint32 public constant PRECONF_MAX_GAS_LIMIT = 5_000_000;

    BoltValidatorsV2 public validators;
    BoltManagerV3 public manager;
    BoltSymbioticMiddlewareV1 public middleware;

    IVaultFactory public vaultFactory;
    IDelegatorFactory public delegatorFactory;
    ISlasherFactory public slasherFactory;
    INetworkRegistry public networkRegistry;
    IOperatorRegistry public operatorRegistry;
    IMetadataService public operatorMetadataService;
    IMetadataService public networkMetadataService;
    INetworkMiddlewareService public networkMiddlewareService;
    IOptInService public operatorVaultOptInService;
    IOptInService public operatorNetworkOptInService;
    IVetoSlasher public vetoSlasher;
    IVault public vault;
    INetworkRestakeDelegator public networkRestakeDelegator;
    IVaultConfigurator public vaultConfigurator;
    Token public collateral;

    address deployer = makeAddr("deployer");
    address admin = makeAddr("admin");
    address provider = makeAddr("provider");
    address operator = makeAddr("operator");
    address validator = makeAddr("validator");
    address networkAdmin = makeAddr("networkAdmin");
    address vaultAdmin = makeAddr("vaultAdmin");
    address user = makeAddr("user");

    uint96 subnetworkId = 0;
    bytes32 subnetwork = networkAdmin.subnetwork(subnetworkId);

    function setUp() public {
        // fast forward a few days to avoid timestamp underflows
        vm.warp(block.timestamp + SLASHING_WINDOW * 3);

        // --- Deploy Symbiotic contracts ---
        (
            vaultFactory,
            delegatorFactory,
            slasherFactory,
            networkRegistry,
            operatorRegistry,
            operatorMetadataService,
            networkMetadataService,
            networkMiddlewareService,
            operatorVaultOptInService,
            operatorNetworkOptInService,
            vaultConfigurator,
            collateral
        ) = new SymbioticSetupFixture().setUp(deployer, admin);

        // --- Create vault ---

        address[] memory adminRoleHolders = new address[](1);
        adminRoleHolders[0] = vaultAdmin;

        IVaultConfigurator.InitParams memory vaultConfiguratorInitParams = IVaultConfigurator.InitParams({
            version: IMigratablesFactory(vaultConfigurator.VAULT_FACTORY()).lastVersion(),
            owner: vaultAdmin,
            vaultParams: abi.encode(
                IVault.InitParams({
                    collateral: address(collateral),
                    burner: address(0xdead),
                    epochDuration: EPOCH_DURATION,
                    depositWhitelist: false,
                    isDepositLimit: false,
                    depositLimit: 0,
                    defaultAdminRoleHolder: vaultAdmin,
                    depositWhitelistSetRoleHolder: vaultAdmin,
                    depositorWhitelistRoleHolder: vaultAdmin,
                    isDepositLimitSetRoleHolder: vaultAdmin,
                    depositLimitSetRoleHolder: vaultAdmin
                })
            ),
            delegatorIndex: 0, // Use NetworkRestakeDelegator
            delegatorParams: abi.encode(
                INetworkRestakeDelegator.InitParams({
                    baseParams: IBaseDelegator.BaseParams({
                        defaultAdminRoleHolder: vaultAdmin,
                        hook: address(0), // we don't need a hook
                        hookSetRoleHolder: vaultAdmin
                    }),
                    networkLimitSetRoleHolders: adminRoleHolders,
                    operatorNetworkSharesSetRoleHolders: adminRoleHolders
                })
            ),
            withSlasher: true,
            slasherIndex: 1, // Use VetoSlasher
            slasherParams: abi.encode(
                IVetoSlasher.InitParams({
                    baseParams: IBaseSlasher.BaseParams({
                        isBurnerHook: false // ?
                    }),
                    // veto duration must be smaller than epoch duration
                    vetoDuration: uint48(12 hours),
                    resolverSetEpochsDelay: 3
                })
            )
        });

        (address vault_, address networkRestakeDelegator_, address vetoSlasher_) =
            vaultConfigurator.create(vaultConfiguratorInitParams);
        vault = IVault(vault_);
        networkRestakeDelegator = INetworkRestakeDelegator(networkRestakeDelegator_);
        vetoSlasher = IVetoSlasher(vetoSlasher_);

        assertEq(address(networkRestakeDelegator), address(vault.delegator()));
        assertEq(address(vetoSlasher), address(vault.slasher()));
        assertEq(address(vault.collateral()), address(collateral));
        assertEq(vault.epochDuration(), EPOCH_DURATION);

        // --- Deploy Bolt contracts ---

        BoltConfig.Parameters memory config = new Utils().readParameters();

        BoltParametersV1 parameters = new BoltParametersV1();
        parameters.initialize(
            admin,
            config.epochDuration,
            config.slashingWindow,
            config.maxChallengeDuration,
            config.allowUnsafeRegistration,
            config.challengeBond,
            config.blockhashEvmLookback,
            config.justificationDelay,
            config.eth2GenesisTimestamp,
            config.slotTime,
            config.minimumOperatorStake
        );

        validators = new BoltValidatorsV2();
        validators.initialize(admin, address(parameters));
        manager = new BoltManagerV3();
        manager.initialize(admin, address(parameters), address(validators));

        middleware = new BoltSymbioticMiddlewareV1();

        middleware.initialize(
            admin,
            address(parameters),
            address(manager),
            networkAdmin,
            address(operatorRegistry),
            address(operatorNetworkOptInService),
            address(vaultFactory)
        );

        // --- Whitelist collateral in BoltSymbioticMiddleware ---
        vm.startPrank(admin);
        middleware.registerVault(address(vault));
        manager.addRestakingProtocol(address(middleware));
        vm.stopPrank();
    }

    /// @notice Internal helper to register Symbiotic contracts and opt-in operators and vaults.
    /// Should be called inside other tests that need a common setup beyond the default setUp().
    function _symbioticOptInRoutine() internal {
        // --- Register Network and Middleware in Symbiotic ---

        vm.prank(networkAdmin);
        networkRegistry.registerNetwork();

        vm.prank(networkAdmin);
        networkMiddlewareService.setMiddleware(address(middleware));

        // --- Register Validator in BoltValidators ---

        // pubkeys aren't checked, any point will be fine
        BLS12381.G1Point memory pubkey = BLS12381.generatorG1();
        bytes20 pubkeyHash = validators.hashPubkey(pubkey);

        vm.prank(validator);
        validators.registerValidatorUnsafe(pubkeyHash, PRECONF_MAX_GAS_LIMIT, operator);
        assert(validators.getValidatorByPubkey(pubkey).pubkeyHash != bytes20(0));
        assertEq(validators.getValidatorByPubkey(pubkey).authorizedOperator, operator);

        // --- Register Operator in Symbiotic, opt-in network and vault ---

        vm.prank(operator);
        operatorRegistry.registerOperator();
        assertEq(operatorRegistry.isEntity(operator), true);

        vm.prank(operator);
        operatorNetworkOptInService.optIn(networkAdmin);
        assertEq(operatorNetworkOptInService.isOptedIn(operator, networkAdmin), true);

        vm.prank(operator);
        operatorVaultOptInService.optIn(address(vault));
        assertEq(operatorVaultOptInService.isOptedIn(operator, address(vault)), true);

        // --- Register Vault and Operator in BoltManager (middleware) ---
        assertEq(middleware.isVaultEnabled(address(vault)), true);

        vm.prank(operator);
        middleware.registerOperator("https://bolt-rpc.io");
        assertEq(manager.isOperatorEnabled(operator), true);

        // --- Set the stake limit for the Vault ---

        vm.prank(networkAdmin);
        networkRestakeDelegator.setMaxNetworkLimit(subnetworkId, 10 ether);

        vm.prank(vaultAdmin);
        networkRestakeDelegator.setNetworkLimit(subnetwork, 2 ether);

        // --- Add stake to the Vault ---
        deal(address(collateral), provider, 1 ether);

        vm.prank(provider);
        collateral.approve(address(vault), 1 ether);

        // deposit collateral from "provider" on behalf of "operator"
        vm.prank(provider);
        (uint256 depositedAmount, uint256 mintedShares) = vault.deposit(operator, 1 ether);

        assertEq(depositedAmount, 1 ether);
        assertEq(mintedShares, 1 ether);
        assertEq(vault.slashableBalanceOf(operator), 1 ether);
        assertEq(collateral.balanceOf(address(vault)), 1 ether);
    }

    /// @notice Compute the hash of a BLS public key
    function _pubkeyHash(
        BLS12381.G1Point memory pubkey
    ) internal pure returns (bytes32) {
        uint256[2] memory compressedPubKey = pubkey.compress();
        return keccak256(abi.encodePacked(compressedPubKey));
    }

    function testReadOperatorStake() public {
        _symbioticOptInRoutine();

        // --- Read the operator stake ---

        // initial state
        uint256 shares = networkRestakeDelegator.totalOperatorNetworkShares(subnetwork);
        uint256 stakeFromDelegator = networkRestakeDelegator.stake(subnetwork, operator);
        uint256 stakeFromMiddleware = middleware.getOperatorStake(operator, address(collateral));
        assertEq(shares, 0);
        assertEq(stakeFromMiddleware, stakeFromDelegator);
        assertEq(stakeFromMiddleware, 0);

        vm.warp(block.timestamp + EPOCH_DURATION + 1);
        assertEq(vault.currentEpoch(), 1);

        // after an epoch has passed
        assertEq(vault.totalStake(), 1 ether);
        assertEq(vault.activeStake(), 1 ether);
        assertEq(vault.activeBalanceOf(operator), 1 ether);
        assertEq(vault.activeSharesAt(uint48(0), ""), 0);
        assertEq(vault.activeSharesAt(uint48(block.timestamp), ""), 1 ether);

        // there still aren't any shares minted on the delegator
        assertEq(networkRestakeDelegator.totalOperatorNetworkShares(subnetwork), 0);
        assertEq(networkRestakeDelegator.operatorNetworkShares(subnetwork, operator), 0);

        // we need to mint shares from the vault admin to activate stake
        // for the operator in the subnetwork.
        vm.prank(vaultAdmin);
        networkRestakeDelegator.setOperatorNetworkShares(subnetwork, operator, 100);
        assertEq(networkRestakeDelegator.totalOperatorNetworkShares(subnetwork), 100);
        assertEq(networkRestakeDelegator.operatorNetworkShares(subnetwork, operator), 100);

        vm.warp(block.timestamp + EPOCH_DURATION + 1);
        assertEq(vault.currentEpoch(), 2);

        // it takes 2 epochs to activate the stake
        stakeFromDelegator = networkRestakeDelegator.stake(subnetwork, operator);
        stakeFromMiddleware = middleware.getOperatorStake(operator, address(collateral));
        assertEq(stakeFromDelegator, stakeFromMiddleware);
        assertEq(stakeFromMiddleware, 1 ether);
    }

    function testGetProposerStatus() public {
        _symbioticOptInRoutine();

        // we need to mint shares from the vault admin to activate stake
        // for the operator in the subnetwork.
        vm.prank(vaultAdmin);
        networkRestakeDelegator.setOperatorNetworkShares(subnetwork, operator, 100);
        assertEq(networkRestakeDelegator.totalOperatorNetworkShares(subnetwork), 100);
        assertEq(networkRestakeDelegator.operatorNetworkShares(subnetwork, operator), 100);

        BLS12381.G1Point memory pubkey = BLS12381.generatorG1();
        bytes20 pubkeyHash = validators.hashPubkey(pubkey);

        vm.warp(block.timestamp + EPOCH_DURATION * 2 + 1);
        assertEq(vault.currentEpoch(), 2);

        IBoltManagerV3.ProposerStatus memory status = manager.getProposerStatus(pubkeyHash);
        assertEq(status.pubkeyHash, pubkeyHash);
        assertEq(status.operator, operator);
        assertEq(status.active, true);
        assertEq(status.collaterals.length, 1);
        assertEq(status.amounts.length, 1);
        assertEq(status.collaterals[0], address(collateral));
        assertEq(status.amounts[0], 1 ether);
    }

    function testProposersLookaheadStatus() public {
        _symbioticOptInRoutine();

        bytes20[] memory pubkeyHashes = new bytes20[](10);

        // register 10 proposers with random pubkeys
        for (uint256 i = 0; i < 10; i++) {
            BLS12381.G1Point memory pubkey = BLS12381.generatorG1();
            pubkey.x[0] = pubkey.x[0] + i + 2;
            pubkey.y[0] = pubkey.y[0] + i + 2;

            pubkeyHashes[i] = validators.hashPubkey(pubkey);
            validators.registerValidatorUnsafe(pubkeyHashes[i], PRECONF_MAX_GAS_LIMIT, operator);
        }

        vm.warp(block.timestamp + EPOCH_DURATION * 2 + 1);
        assertEq(vault.currentEpoch(), 2);

        IBoltManagerV3.ProposerStatus[] memory statuses = manager.getProposerStatuses(pubkeyHashes);
        assertEq(statuses.length, 10);
    }

    function testGetNonExistentProposerStatus() public {
        _symbioticOptInRoutine();

        bytes20 pubkeyHash = bytes20("0x1");

        vm.expectRevert(abi.encodeWithSelector(ValidatorsLib.ValidatorDoesNotExist.selector, pubkeyHash));
        manager.getProposerStatus(pubkeyHash);
    }

    function testUpdateOperatorRpc() public {
        _symbioticOptInRoutine();

        // --- Get current operator data ---
        EnumerableMapV3.Operator memory operatorData = manager.getOperatorData(operator);
        assertEq(operatorData.rpc, "https://bolt-rpc.io");

        // --- Update Operator RPC ---
        vm.prank(operator);
        manager.updateOperatorRPC("https://new-rpc.io");

        // --- Check new operator data ---
        operatorData = manager.getOperatorData(operator);
        assertEq(operatorData.rpc, "https://new-rpc.io");

        // --- Check that the operator is still enabled ---
        assertEq(manager.isOperatorEnabled(operator), true);
    }

    function testCalculateSubnetwork() public {
        address network_ = 0xb017002D8024d8c8870A5CECeFCc63887650D2a4;
        uint96 identifier_ = 0;

        bytes32 subnetwork_ = network_.subnetwork(identifier_);
        assertEq(subnetwork_, 0xb017002D8024d8c8870A5CECeFCc63887650D2a4000000000000000000000000);
    }
}

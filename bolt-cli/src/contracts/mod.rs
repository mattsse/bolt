use std::collections::HashMap;

use alloy::primitives::{address, Address};
use clap::ValueEnum;
use lazy_static::lazy_static;
use serde::{Deserialize, Serialize};

use crate::cli::Chain;

pub mod bolt;
pub mod eigenlayer;
pub mod erc20;
pub mod symbiotic;

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct Contracts {
    pub bolt: Bolt,
    pub symbiotic: Symbiotic,
    pub eigen_layer: EigenLayer,
    pub collateral: [(String, Address); 6],
}

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct Bolt {
    pub validators: Address,
    pub parameters: Address,
    pub manager: Address,
    pub eigenlayer_middleware: Address,
    pub symbiotic_middleware: Address,
}

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct Symbiotic {
    pub network: Address,
    pub operator_registry: Address,
    pub network_opt_in_service: Address,
    pub vault_factory: Address,
    pub vault_configurator: Address,
    pub network_registry: Address,
    pub network_middleware_service: Address,
    pub middleware: Address,
    pub supported_vaults: [Address; 6],
}

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct EigenLayer {
    pub avs_directory: Address,
    pub delegation_manager: Address,
    pub strategy_manager: Address,
    pub middleware: Address,
    pub supported_strategies: EigenLayerStrategies,
}

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct EigenLayerStrategies {
    st_eth: Address,
    r_eth: Address,
    w_eth: Address,
    cb_eth: Address,
    m_eth: Address,
}

#[derive(Copy, Clone, Serialize, Deserialize, Debug, ValueEnum)]
#[allow(clippy::enum_variant_names)]
#[serde(rename_all = "kebab-case")]
pub enum EigenLayerStrategy {
    StEth,
    REth,
    WEth,
    CbEth,
    MEth,
}

impl std::fmt::Display for EigenLayerStrategy {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let output = match self {
            Self::StEth => "stETH",
            Self::REth => "rETH",
            Self::WEth => "wETH",
            Self::CbEth => "cbETH",
            Self::MEth => "mETH",
        };
        write!(f, "{}", output)
    }
}

pub fn strategy_to_address(
    strategy: EigenLayerStrategy,
    addresses: EigenLayerStrategies,
) -> Address {
    match strategy {
        EigenLayerStrategy::StEth => addresses.st_eth,
        EigenLayerStrategy::REth => addresses.r_eth,
        EigenLayerStrategy::WEth => addresses.w_eth,
        EigenLayerStrategy::CbEth => addresses.cb_eth,
        EigenLayerStrategy::MEth => addresses.m_eth,
    }
}

pub fn deployments() -> HashMap<Chain, Contracts> {
    let mut deployments = HashMap::new();
    deployments.insert(Chain::Holesky, HOLESKY_DEPLOYMENTS.clone());

    deployments
}

pub fn deployments_for_chain(chain: Chain) -> Contracts {
    deployments()
        .get(&chain)
        .cloned()
        .unwrap_or_else(|| panic!("no deployments for chain: {:?}", chain))
}

lazy_static! {
    pub static ref HOLESKY_DEPLOYMENTS: Contracts = Contracts {
        bolt: Bolt {
            validators: address!("47D2DC1DE1eFEFA5e6944402f2eda3981D36a9c8"),
            parameters: address!("20d1cf3A5BD5928dB3118b2CfEF54FDF9fda5c12"),
            manager: address!("440202829b493F9FF43E730EB5e8379EEa3678CF"),
            eigenlayer_middleware: address!("a632a3e652110Bb2901D5cE390685E6a9838Ca04"),
            symbiotic_middleware: address!("04f40d9CaE475E5BaA462acE53E5c58A0DD8D8e8"),
        },
        symbiotic: Symbiotic {
            network: address!("b017002D8024d8c8870A5CECeFCc63887650D2a4"),
            operator_registry: address!("6F75a4ffF97326A00e52662d82EA4FdE86a2C548"),
            network_opt_in_service: address!("58973d16FFA900D11fC22e5e2B6840d9f7e13401"),
            vault_factory: address!("407A039D94948484D356eFB765b3c74382A050B4"),
            vault_configurator: address!("D2191FE92987171691d552C219b8caEf186eb9cA"),
            network_registry: address!("7d03b7343BF8d5cEC7C0C27ecE084a20113D15C9"),
            network_middleware_service: address!("62a1ddfD86b4c1636759d9286D3A0EC722D086e3"),
            middleware: address!("04f40d9CaE475E5BaA462acE53E5c58A0DD8D8e8"),
            supported_vaults: [
                address!("c79c533a77691641d52ebD5e87E51dCbCaeb0D78"),
                address!("e5708788c90e971f73D928b7c5A8FD09137010e0"),
                address!("11c5b9A9cd8269580aDDbeE38857eE451c1CFacd"),
                address!("C56Ba584929c6f381744fA2d7a028fA927817f2b"),
                address!("cDdeFfcD2bA579B8801af1d603812fF64c301462"),
                address!("91e84e12Bb65576C0a6614c5E6EbbB2eA595E10f"),
            ],
        },
        eigen_layer: EigenLayer {
            avs_directory: address!("055733000064333CaDDbC92763c58BF0192fFeBf"),
            delegation_manager: address!("A44151489861Fe9e3055d95adC98FbD462B948e7"),
            strategy_manager: address!("dfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6"),
            middleware: address!("a632a3e652110Bb2901D5cE390685E6a9838Ca04"),
            supported_strategies: EigenLayerStrategies {
                st_eth: address!("7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3"),
                r_eth: address!("3A8fBdf9e77DFc25d09741f51d3E181b25d0c4E0"),
                w_eth: address!("80528D6e9A2BAbFc766965E0E26d5aB08D9CFaF9"),
                cb_eth: address!("70EB4D3c164a6B4A5f908D4FBb5a9cAfFb66bAB6"),
                m_eth: address!("accc5A86732BE85b5012e8614AF237801636F8e5"),
            },
        },
        collateral: [
            ("wst_eth".to_string(), address!("8d09a4502Cc8Cf1547aD300E066060D043f6982D")),
            ("r_eth".to_string(), address!("7322c24752f79c05FFD1E2a6FCB97020C1C264F1")),
            ("st_eth".to_string(), address!("3F1c547b21f65e10480dE3ad8E19fAAC46C95034")),
            ("w_eth".to_string(), address!("94373a4919B3240D86eA41593D5eBa789FEF3848")),
            ("cb_eth".to_string(), address!("8720095Fa5739Ab051799211B146a2EEE4Dd8B37")),
            ("m_eth".to_string(), address!("e3C063B1BEe9de02eb28352b55D49D85514C67FF")),
        ],
    };
}

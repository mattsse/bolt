use std::num::NonZero;

use clap::Parser;

/// Default max commitments to accept per block.
pub const DEFAULT_MAX_COMMITMENTS: usize = 128;

/// Default max committed gas per block.
pub const DEFAULT_MAX_COMMITTED_GAS: u64 = 10_000_000;

/// Default min profit to accept for a commitment.
pub const DEFAULT_MIN_PROFIT: u64 = 2_000_000_000; // 2 Gwei

/// Default max account states size.
pub const DEFAULT_MAX_ACCOUNT_STATES_SIZE: u64 = 1_024;

/// Limits for the sidecar.
#[cfg_attr(test, derive(PartialEq))]
#[derive(Debug, Parser, Clone, Copy, serde::Serialize, serde::Deserialize)]
pub struct LimitsOpts {
    /// Max committed gas per slot
    #[clap(
        long,
        env = "BOLT_SIDECAR_MAX_COMMITTED_GAS",
        default_value_t = LimitsOpts::default().max_committed_gas_per_slot
    )]
    pub max_committed_gas_per_slot: NonZero<u64>,
    /// Min profit per gas to accept a commitment
    #[clap(
        long,
        env = "BOLT_SIDECAR_MIN_PROFIT",
        default_value_t = LimitsOpts::default().min_inclusion_profit
    )]
    pub min_inclusion_profit: u64,
    /// The maximum size in MiB of the [crate::state::ExecutionState] ScoreCache that holds account
    /// states. Each [crate::primitives::AccountState] is 48 bytes, its score is [usize] bytes, and
    /// its key is 20 bytes, so the default value of 1024 KiB = 1 MiB can hold around 15k account
    /// states.
    #[clap(
        long,
        env = "BOLT_SIDECAR_MAX_ACCOUNT_STATES_SIZE",
        default_value_t = LimitsOpts::default().max_account_states_size,
    )]
    pub max_account_states_size: NonZero<usize>,
}

impl Default for LimitsOpts {
    fn default() -> Self {
        Self {
            max_committed_gas_per_slot: NonZero::new(DEFAULT_MAX_COMMITTED_GAS)
                .expect("Valid non-zero"),
            min_inclusion_profit: DEFAULT_MIN_PROFIT,
            max_account_states_size: NonZero::new(1_024).expect("Valid non-zero"),
        }
    }
}

use std::{
    collections::HashMap,
    fs::{self, File},
    io::Read,
};

use crate::cli::TlsCredentials;
use eyre::{Context, Result};
use reqwest::{Certificate, Identity, Url};
use serde::Deserialize;

/// Web3Signer remote server.
///
///  Functionality:
/// - List consensus accounts in the keystore.
/// - Sign roots over the consensus type.
///
/// Reference: https://docs.web3signer.consensys.io/reference
#[derive(Clone)]
pub struct Web3Signer {
    base_url: Url,
    client: reqwest::Client,
}

impl Web3Signer {
    pub async fn connect(addr: String, credentials: TlsCredentials) -> Result<Self> {
        // Establish connection with TLS config.
        let base_url = addr.parse()?;
        let (cert, identity) = compose_credentials(credentials)?;
        let client = reqwest::Client::builder()
            // TODO: handle this properly
            .danger_accept_invalid_certs(true)
            .add_root_certificate(cert)
            .identity(identity)
            .build()?;

        Ok(Self { base_url, client })
    }

    /// List the consensus accounts of the keystore.
    ///
    /// Only the consensus keys are returned.
    /// This is due to signing only being over the consensus type.
    ///
    /// Reference: https://commit-boost.github.io/commit-boost-client/api/
    pub async fn list_accounts(&mut self) -> Result<Vec<String>> {
        #[derive(Deserialize)]
        struct Keys {
            /// The consensus keys stored in the Web3Signer.
            pub consensus: String,
            /// The two below proxy fields are here for deserialisation purposes.
            /// They are not used as signing is only over the consensus type.
            #[allow(unused)]
            proxy_bls: Vec<String>,
            #[allow(unused)]
            proxy_ecdsa: Vec<String>,
        }

        /// Outer container for response.
        #[derive(Deserialize)]
        struct CommitBoostKeys {
            keys: Vec<Keys>,
        }

        let resp = self
            .client
            .get(self.base_url.join("/signer/v1/get_pubkeys")?)
            .send()
            .await?
            .json::<CommitBoostKeys>()
            .await?;

        let consensus_keys: Vec<String> =
            resp.keys.into_iter().map(|key_set| key_set.consensus).collect();

        Ok(consensus_keys)
    }

    /// Request a signature from the remote signer.
    ///
    /// This will sign an arbituary root over the consensus type.
    ///
    /// Reference: https://commit-boost.github.io/commit-boost-client/api/
    pub async fn request_signature(&mut self, pub_key: &str, object_root: &str) -> Result<String> {
        let mut map = HashMap::new();
        map.insert("type", "consensus");
        map.insert("pubkey", pub_key);
        map.insert("object_root", object_root);
        let resp = self
            .client
            .post(self.base_url.join("/signer/v1/request_signature")?)
            .json(&map)
            .send()
            .await?
            .json::<String>()
            .await?;

        Ok(resp.to_string())
    }
}

pub fn compose_credentials(credentials: TlsCredentials) -> Result<(Certificate, Identity)> {
    // Create certificate.
    let mut buff = Vec::new();
    File::open(credentials.client_cert_path.clone())
        .wrap_err("Failed to read client cert")?
        .read_to_end(&mut buff)
        .wrap_err("Failed to read client cert into buffer")?;
    let cert = Certificate::from_pem(&buff)?;

    // Create identity.
    let cert_read =
        fs::read(credentials.client_cert_path).wrap_err("Failed to read client cert")?;
    let key_read = fs::read(credentials.client_key_path).wrap_err("Failed to read client key")?;
    let identity = Identity::from_pkcs8_pem(&cert_read, &key_read)?;
    Ok((cert, identity))
}

#[cfg(test)]
pub mod test_util {
    use std::{
        process::{Child, Command},
        time::Duration,
    };

    use crate::cli::TlsCredentials;
    use eyre::{bail, Ok};

    pub async fn start_web3signer_test_server() -> eyre::Result<(String, Child, TlsCredentials)> {
        // Key store test data.
        let test_data_dir =
            env!("CARGO_MANIFEST_DIR").to_string() + "/test_data/web3signer/keystore";

        // TLS test data.
        let tls_dir = env!("CARGO_MANIFEST_DIR").to_string() + "/test_data/web3signer/tls/";
        let tls_keystore = tls_dir.clone() + "key.p12";
        let tls_password = tls_dir + "password.txt";

        // Check if web3signer is installed (in $PATH).
        if Command::new("web3signer").spawn().is_err() {
            bail!("Web3Signer is not installed in $PATH");
        }

        // Start the web3signer server.
        let web3signer_proc = Command::new("web3signer")
            .arg("--key-store-path")
            .arg(test_data_dir.clone())
            .arg("--tls-keystore-file")
            .arg(tls_keystore)
            .arg("--tls-allow-any-client")
            .arg("true")
            .arg("--tls-keystore-password-file")
            .arg(tls_password)
            .arg("eth2")
            .arg("--network")
            .arg("mainnet")
            .arg("--slashing-protection-enabled")
            .arg("false")
            .arg("--commit-boost-api-enabled")
            .arg("true")
            .arg("--proxy-keystores-path")
            .arg(test_data_dir.clone())
            .arg("--proxy-keystores-password-file")
            .arg(test_data_dir + "/password.txt")
            .spawn()?;

        // Allow the server to start up.
        tokio::time::sleep(Duration::from_secs(5)).await;

        // TLS client test data.
        let client_tls_dir = env!("CARGO_MANIFEST_DIR").to_string() + "/test_data/dirk_single";

        // TLS credentials.
        let credentials = TlsCredentials {
            client_cert_path: client_tls_dir.clone() + "/client1.crt",
            client_key_path: client_tls_dir + "/client1.key",
            ca_cert_path: None,
        };

        // Connect to the Web3Signer client.
        let url = "https://127.0.0.1:9000".to_string();

        Ok((url, web3signer_proc, credentials))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Test for connecting to the Web3Signer and listing accounts.
    ///
    /// ```shell
    /// cargo test --package bolt --bin bolt -- common::web3signer::tests
    /// --exact --show-output --ignored
    /// ```
    #[tokio::test]
    #[ignore = "Requires Web3Signer to be installed on the system"]
    async fn test_web3signer_connection_e2e() -> eyre::Result<()> {
        let (url, mut web3signer_proc, creds) = test_util::start_web3signer_test_server().await?;
        let mut web3signer = Web3Signer::connect(url, creds).await?;

        let accounts = web3signer.list_accounts().await?;
        println!("Web3Signer Accounts: {:?}", accounts);

        web3signer_proc.kill()?;

        Ok(())
    }
}

use std::sync::Arc;

use axum::{
    body::Body,
    extract::State,
    http::{HeaderMap, Request},
    response::Html,
    Json,
};
use axum_extra::extract::WithRejection;
use serde_json::json;
use tracing::{debug, error, info, instrument};

use crate::{
    api::commitments::{
        server::headers::auth_from_headers,
        spec::{
            CommitmentError, CommitmentsApi, MetadataResponse, GET_METADATA_METHOD,
            GET_VERSION_METHOD, REQUEST_INCLUSION_METHOD,
        },
    },
    common::BOLT_SIDECAR_VERSION,
    primitives::{
        jsonrpc::{JsonRpcRequest, JsonRpcResponse, JsonRpcSuccessResponse},
        signature::SignatureError,
        InclusionRequest,
    },
};

use super::CommitmentsApiInner;

/// Handler function for the root JSON-RPC path.
#[instrument(skip_all, name = "POST /rpc", fields(method = %payload.method))]
pub async fn rpc_entrypoint(
    headers: HeaderMap,
    State(api): State<Arc<CommitmentsApiInner>>,
    WithRejection(Json(payload), _): WithRejection<Json<JsonRpcRequest>, CommitmentError>,
) -> Result<Json<JsonRpcResponse>, CommitmentError> {
    debug!("Received new request");

    match payload.method.as_str() {
        GET_VERSION_METHOD => Ok(Json(
            JsonRpcSuccessResponse {
                id: payload.id,
                result: json!(BOLT_SIDECAR_VERSION.to_string()),
                ..Default::default()
            }
            .into(),
        )),

        GET_METADATA_METHOD => {
            let metadata = MetadataResponse {
                limits: api.limits(),
                version: BOLT_SIDECAR_VERSION.to_string(),
            };

            let response = JsonRpcSuccessResponse {
                id: payload.id,
                result: json!(metadata),
                ..Default::default()
            }
            .into();
            Ok(Json(response))
        }

        REQUEST_INCLUSION_METHOD => {
            // Validate the authentication header and extract the signer and signature
            let (signer, signature) = auth_from_headers(&headers).inspect_err(|e| {
                error!("Failed to extract signature from headers: {:?}", e);
            })?;

            let Some(request_json) = payload.params.first().cloned() else {
                return Err(CommitmentError::InvalidParams("missing param".to_string()));
            };

            // Parse the inclusion request from the parameters
            let mut inclusion_request = serde_json::from_value::<InclusionRequest>(request_json)
                .map_err(CommitmentError::InvalidJson)
                .inspect_err(|err| error!(?err, "Failed to parse inclusion request"))?;

            debug!(?inclusion_request, "New inclusion request");

            // Set the signature here for later processing
            inclusion_request.set_signature(signature.into());

            let digest = inclusion_request.digest();
            let recovered_signer = signature.recover_address_from_prehash(&digest)?;

            if recovered_signer != signer {
                error!(
                    %recovered_signer,
                    %signer,
                    "Recovered signer does not match the provided signer"
                );

                return Err(CommitmentError::InvalidSignature(SignatureError));
            }

            // Set the request signer
            inclusion_request.set_signer(recovered_signer);

            info!(signer = ?recovered_signer, %digest, "New valid inclusion request received");
            let inclusion_commitment = api.request_inclusion(inclusion_request).await?;

            // Create the JSON-RPC response
            let response = JsonRpcSuccessResponse {
                id: payload.id,
                result: json!(inclusion_commitment),
                ..Default::default()
            }
            .into();

            Ok(Json(response))
        }
        other => {
            error!("Unknown method: {}", other);
            Err(CommitmentError::UnknownMethod)
        }
    }
}

/// Not found fallback handler for all non-matched routes.
///
/// This handler returns a simple 404 page.
#[instrument(skip_all, name = "not_found")]
pub async fn not_found(req: Request<Body>) -> Html<&'static str> {
    error!(uri = ?req.uri(), "Route not found");
    Html("404 - Not Found")
}

/// Status handler
#[instrument(skip_all, name = "GET /status")]
pub async fn status() -> Html<&'static str> {
    Html("OK")
}

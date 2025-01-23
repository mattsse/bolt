# Guide on creating new releases

## 0. Pre-release checks

There is not a single end2end test procedure, but each release should at least
go through a manual test of the core components, including the happy-case and
error-case scenarios. This includes the Kurtosis devnet environment and any
live testnet deployment that is available at time of release.

For testnets, if the launch setup has changed since the previous version,
the `guides/` directory should be updated to reflect the new setup.
Pay special attention to the `README` and `docker-compose` files.

## 1. Update the version tag in the necessary packages

For instance, for the Bolt sidecar this is in `bolt-sidecar/Cargo.toml`.
Similar changes should be made in the other packages getting updated.

Next, update the version of the Docker images used in any `docker-compose` files.
These currently only live inside the `guides/` dir.

## 2. Create a release on Github

Create a new release on Github with the new tag and a description of the changes.

We use the built-in Github changelog feature to generate the changelog.

## 3. Build new Docker images

You can build new Docker images with the `just build-and-push-all-images <tag>` recipe.

Example: `just build-and-push-all-images v0.2.0-alpha` will build and push the Docker images
for all Bolt components with the tag `v0.2.0-alpha` for both `arm64` and `amd64`
architectures. This can take a long time.

Since we use cross compilation, we recommend running this from an x86_64 linux box.

## 4. Build the `bolt` CLI binaries and upload them to the release assets

You can build the `bolt` CLI binaries with the `just create-bolt-cli-tarballs` recipe.

This will output tarballs in `bolt-cli/dist/` that you can ultimately upload to the
Github release assets.

These will then be automatically consumed by `boltup` consumers when selecting the
tag they want to use for their Bolt cli installation.

e.g. `boltup --tag v0.1.0` will pick one of the tarballs in the `cli-v0.1.0` release.

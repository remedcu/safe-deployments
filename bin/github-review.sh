#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

usage() {
    cat <<EOF
This script verifies the deployed contracts on a chain ID for a given PR.

USAGE
    bash ./bin/github-review.sh <PR> <CHAIN_ID> <RPC_URL> <VERSION>

ARGUMENTS
    PR          The GitHub PR number
    CHAIN_ID    The chain ID to verify
    RPC_URL     The RPC URL to use for the chain ID
    VERSION     The version of the contracts to verify

EXAMPLES
    bash ./bin/github-review.sh 123 1 https://rpc.ankr.com/eth 1.3.0
    bash ./bin/github-review.sh 123 1 https://rpc.ankr.com/eth 1.4.1
EOF
}

if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: Dirty Git index, please commit all changes before continuing" 1>&2
    exit 1
fi
if ! command -v gh &> /dev/null; then
    echo "ERROR: Please install the 'gh' GitHub CLI" 1>&2
    exit 1
fi
if ! command -v cast &> /dev/null; then
    echo "ERROR: Please install the 'cast' tool included in the Foundry toolset" 1>&2
    exit 1
fi

if [[ "$#" -ne 1 ]]; then
    usage
    exit 1
fi
if ! [[ $1 =~ ^[0-9]+$ ]]; then
    echo "ERROR: $1 is not a valid GitHub PR number" 1>&2
    usage
    exit 1
fi
pr=$1
prChainID="$(gh pr view $pr | sed -nE 's/.*Chain_ID: ([0-9]+).*/\1/p')"
if ! [[ $prChainID =~ ^[0-9]+$ ]]; then
    echo "ERROR: $prChainID is not a valid Chain ID number" 1>&2
    usage
    exit 1
fi
chainlistURL="https://chainlist.org/chain/$prChainID"
if [[ "$(curl -s "$chainlistURL")" == 'nope' ]]; then
    echo "ERROR: Chainlist URL $chainlistURL doesn't exist" 1>&2
    usage
    exit 1
fi
rpc="$(gh pr view $pr | sed -nE 's/.*RPC_URL: (https?:\/\/[^ ]+).*/\1/p')"
chainid="$(cast chain-id --rpc-url $rpc)"
if [[ $chainid != $prChainID ]]; then
    echo "ERROR: RPC $rpc doesn't match chain ID $prChainID" 1>&2
    usage
    exit 1
fi
version="$(gh pr view $pr | sed -nE 's/.*Contract_Version: (1\.[3-4]\.[0-1]).*/\1/p')"
versionFiles=(src/assets/v$version/*.json)
if [[ ${#versionFiles[@]} -eq 0 ]]; then
    echo "ERROR: Version $version doesn't exist" 1>&2
    usage
    exit 1
fi

# Fetching PR and checking if other files are changed or not.
echo "Checking changes to other files"
if [[ -n "$(gh pr diff $pr --name-only | grep -v -e 'src/assets/v'$version'/.*\.json')" ]]; then
    echo "ERROR: PR contains changes in files other than src/assets/v$version/*.json" 1>&2
    echo "Changed files:"
    echo "$(gh pr diff $pr --name-only | grep -v -e 'src/assets/v'$version'/.*\.json')"
    exit 1
fi

echo "Verifying Deployment Asset"
gh pr diff $pr --patch | git apply --include 'src/assets/**'

# Getting default addresses, address on the chain and checking code hash.
defaultAddresses=$(jq -r '.addresses' "$versionFiles")
deploymentTypes=($(jq -r --arg c "$chainid" '.networkAddresses[$c][]' "$versionFiles"))
for file in "${versionFiles[@]}"; do
    for deploymentType in "${deploymentTypes[@]}"; do
        defaultAddress=$(jq -r --arg t "$deploymentType" '.addresses[$t]' "$file")
        defaultCodeHash=$(jq -r --arg t "$deploymentType" '.codeHash[$t]' "$file")
        networkCodeHash=$(cast keccak $(cast code $defaultAddress --rpc-url $rpc))
        if [[ $defaultCodeHash != $networkCodeHash ]]; then
            echo "ERROR: "$file"("$defaultAddress") code hash is not the same as the one created for the chain id" 1>&2
            exit 1
        fi
    done
done

echo "Network addresses & Code hashes are correct"

git restore --ignore-unmerged -- src/assets

# NOTE/TODO
# - We should still manually verify there is no extra chain added in the PR.
# - We can approve PR using Github CLI. Should only be added after all manual tasks can be automated.
# - Supporting zkSync and alternative deployment addresses for 1.3.0 contracts.
# - We should ensure there are not more than a single chain ID being added in a PR.

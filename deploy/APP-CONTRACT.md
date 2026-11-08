# App and CI contract

This file is the interface for a separate infrastructure change. It is not a setup runbook. One-time Entra, Container Apps, Front Door, and GitHub Environment steps stay in HQ. The access standard merged as HQ PR 668 and the deployment draft HQ PR 669 were not readable from the environment that prepared this template, so this repository does not invent a second click-through.

The template does not create client sites, migrate data, open ingress, or create identities and secrets.

## What the app enforces

| Mode | How a browser reaches it | What the process requires before it serves HTML or assets |
| --- | --- | --- |
| local | Developer machine. Compose sets this explicitly. | Anonymous demo access. Platform identity headers are ignored. Refused when Azure Container Apps or App Service marker variables are present, and when the Vapor environment is production and `APP_RUNTIME_MODE` is unset. |
| staging | Normal browser to the Container App through Easy Auth and Microsoft Entra. | Public host match, a verified Entra ID token from `X-MS-TOKEN-AAD-ID-TOKEN`, and agreement with any `X-MS-CLIENT-PRINCIPAL*` headers. Front Door settings must be unset. |
| production | Azure Front Door in front of the origin. | Staging's token checks, plus `X-Azure-FDID` equal to `FRONTDOOR_ID`, plus the Front Door origin secret header, plus the public host rule below. |

`/health` `GET` and `HEAD` return `ok` with no authentication, no host check, and no origin check. No other path is anonymous. `POST /health`, `/health/`, and `/healthz` are not exceptions.

Staging responses send `X-Robots-Tag: noindex, nofollow`. HTML and static assets also send `Cache-Control: private, no-store`. Production does not add those headers.

Host comparison lowercases the name and accepts one trailing DNS dot (`example.com.`). A second dot, an explicit port, a suffix such as `example.com.evil.net.`, or a comma-separated forwarded list is rejected with `421`. When `X-Forwarded-Host` is present it must be `PUBLIC_HOST`, and `Host` must be `PUBLIC_HOST` or `ORIGIN_HOST`.

The default authorizer allows any principal that passed those checks. It does not read roles or site-specific claims. A site assigns `app.accessAuthorizer` in `configure.swift`. `AccessPrincipal.stringClaims` contains single-valued strings from the verified ID token for that extension; the default ignores them.

## App inputs

Set these on the existing container app. Do not commit secrets. Empty values are treated as unset.

| Variable | Staging | Production | Local |
| --- | --- | --- | --- |
| `APP_RUNTIME_MODE` | `staging` | `production` | unset, or `local` |
| `PUBLIC_HOST` | browser hostname | public DNS hostname | unset |
| `ORIGIN_HOST` | optional | optional Container Apps hostname when `Host` differs from the public host | unset |
| `ENTRA_TENANT_ID` | directory GUID | directory GUID | unset |
| `ENTRA_CLIENT_ID` | application GUID | application GUID | unset |
| `ENTRA_AUDIENCE` | optional; defaults to the client id. Exact `aud` match. | same | unset |
| `ENTRA_ISSUER` | optional. Unset accepts only `https://login.microsoftonline.com/{tenant}/v2.0` and `https://sts.windows.net/{tenant}/`. A national-cloud or CIAM issuer must be the exact `iss` value and must contain the tenant id. | same | unset |
| `ENTRA_JWKS_URL` | optional for commercial issuers. Required for any other accepted issuer. https Microsoft JWKS URL containing the tenant id. | same | unset |
| `FRONTDOOR_ID` | unset | Front Door profile GUID | unset |
| `ORIGIN_AUTH_HEADER` | unset | optional, default `X-App-Origin-Auth` | unset |
| `ORIGIN_AUTH_SECRET` | unset | secret of at least 32 characters, injected by Front Door and not equal to the Front Door id | unset |

`ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID`, and `FRONTDOOR_ID` reject the nil GUID.

Easy Auth must use Microsoft Entra, require authentication except for `/health`, and enable the token store so the ID token header is forwarded. The app does not trust `X-MS-CLIENT-PRINCIPAL*` without a verified token, and it rejects the request when those headers disagree with the token. Container Apps strips client-supplied copies of the platform headers only for requests that pass the auth sidecar. Keeping the container reachable only through that sidecar is an infrastructure constraint; this repository does not open ingress.

Production also needs Front Door to overwrite `X-Azure-FDID` and `ORIGIN_AUTH_HEADER` on the way to the origin. `X-Azure-FDID` by itself is spoofable if the origin port is public. Managed-identity origin authentication that replaces `Authorization` is not implemented here, because that header collision belongs to infrastructure and would fight the user token.

## App outputs

| Output | Meaning |
| --- | --- |
| Process exit on boot | Configuration is invalid. No port is served. |
| `200` `ok` on `GET` and `HEAD /health` | Liveness only. Not an auth signal. |
| `401` `unauthorized` | Missing or rejected Easy Auth token, origin secret, or Front Door id. |
| `403` `forbidden` | The site authorizer rejected an otherwise valid principal. |
| `421` `misdirected` | Host failed validation. |
| `AccessPrincipal` on the request | `subject` (`oid`, otherwise `sub`), `tenantID`, `audience`, optional `name`, optional `identityProvider` (`aad` only when the platform header said so). |

Log lines name the failure class (`host`, `origin`, `token`, `authorizer`) and do not include tokens or secrets.

## CI inputs

GitHub Actions variables. No client secrets. `AZURE_DEPLOY_ENABLED` must be the string `true` or main will test and build a local image, then stop without pushing.

| Variable | Used by |
| --- | --- |
| `AZURE_DEPLOY_ENABLED` | main publish and production dispatch |
| `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | OIDC login |
| `AZURE_CLIENT_ID_PUBLISH` | main, push to the registry only |
| `AZURE_CLIENT_ID_STAGING` | main, update the staging app only |
| `AZURE_CLIENT_ID_PRODUCTION` | production dispatch only |
| `ACR_NAME` | registry login and manifest check |
| `IMAGE_REPOSITORY` | `registry.azurecr.io/app` with no tag and no digest |
| `STAGING_RESOURCE_GROUP`, `STAGING_CONTAINER_APP`, `STAGING_BASE_URL` | staging update and auth gate |
| `PRODUCTION_RESOURCE_GROUP`, `PRODUCTION_CONTAINER_APP`, `PRODUCTION_BASE_URL` | production update and auth gate |
| workflow dispatch `image_digest` | `sha256:` plus 64 hex characters. Production does not build. |

`STAGING_BASE_URL` and `PRODUCTION_BASE_URL` are `https` origins with no path, userinfo, or port. The gate requests `/health` and `/`.

Federated credentials are created outside this repository. Suggested subjects, not applied by these files:

| Client | Subject | Azure scope |
| --- | --- | --- |
| publish | `repo:<org>/<repo>:ref:refs/heads/main` | `AcrPush` on that registry |
| staging | `repo:<org>/<repo>:environment:staging` | update that one container app |
| production | `repo:<org>/<repo>:environment:production` | update that one container app |

Do not federate `pull_request`. Pull request workflows in this repo do not request `id-token`.

The GitHub Environments `staging` and `production` need required reviewers configured in GitHub. The workflow `environment:` key only selects the name. It does not create reviewers, and a missing protection rule will not show up as a YAML error.

## CI outputs

| Event | Result |
| --- | --- |
| pull request | `swift test` and `docker build`. No registry login, push, or deploy. |
| push to main, inputs incomplete | tests run, a local image builds, the job summary says nothing was published. |
| push to main, inputs invalid while deploy is enabled | the publish job fails. |
| push to main, inputs valid | one push, job output `digest`, then `az containerapp update` of the existing staging app to `repository@digest`. |
| production dispatch | no compile and no image build. The same digest is checked in the registry and applied to the existing production app. |

After the image update, the deploy script polls revision readiness and requires `GET` and `HEAD /health` to be `200` and `/` to be `301`, `302`, `303`, `307`, `308`, `401`, or `403`. A healthy `200` on `/` fails the deploy. Failure requests `az containerapp ingress traffic set` back to the previous ready revision. That rollback needs multiple revision mode on the existing app. The script does not turn that mode on.

Main deploys use a concurrency group and a stale-commit check immediately before the update. Two commits that pass the check before either writes still depend on the queue (`cancel-in-progress: false`).

## What is intentionally absent

- No Bicep or Terraform, and no `az containerapp create`, identity creation, secret creation, or ingress enablement.
- No shared workflow reference to a central repository. Callers in this repo use a relative path. Copy the files into another project, or pin a commit only after this workflow is on the default branch.
- No claim rules from any one client site.
- The Azure CLI path has not been executed against a subscription. `Tests/scripts/deploy-contract.test.sh` covers the scripts' decisions and the workflow boundaries.

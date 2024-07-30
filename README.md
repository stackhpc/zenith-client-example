# zenith-client-example

This repository contains manifests and configuration for setting up a Zenith server on a
Kubernetes cluster and an example Zenith client that forwards traffic to an echo server.

The server and client should be deployed on different Kubernetes clusters in order to properly
demonstrate the briding of NAT and/or firewalls. The cluster that the client is deployed on
does not need egress from the internet, however it must be able to pull the required images
and to reach the SSHD server that is part of the Zenith server.

## Installing the server

### NGINX ingress controller

First, install [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) on the target
cluster, as Zenith relies on it. Zenith uses snippet annotations, which are disabled by
default:

```sh
helm upgrade ingress-nginx ingress-nginx \
  --install \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.allowSnippetAnnotations=true \
  --wait
```

### TLS using Let's Encrypt

To provide TLS using [Let's Encrypt](https://letsencrypt.org/), we use
[cert-manager](https://cert-manager.io/):

```sh
helm upgrade cert-manager cert-manager \
  --install \
  --repo https://charts.jetstack.io \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --wait
```

```sh
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-privkey
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
```

> Note that this only works when the IP for the ingress controller is public-facing.

### Zenith server

Get the external IP of the service for the ingress controller:

```sh
INGRESS_IP="$(
  kubectl get svc ingress-nginx-controller \
    --namespace ingress-nginx \
    --output jsonpath='{.status.loadBalancer.ingress[0].ip}'
)"
```

Next, we will need a wildcard DNS record that points to this IP (Zenith expects to
be given control of a whole subdomain). For testing, an [sslip.io](https://sslip.io/)
domain (or similar) is sufficient:

```sh
ZENITH_DOMAIN="zenith.$(tr . - <<< "$INGRESS_IP").sslip.io"
```

Generate a random signing key for the registrar:

```sh
ZENITH_SIGNING_KEY="$(openssl rand -hex 32)"
```

Then install the Zenith server:

```sh
helm upgrade zenith-server zenith-server \
  --install \
  --repo https://stackhpc.github.io/zenith \
  --namespace zenith \
  --create-namespace \
  --set common.ingress.baseDomain=$ZENITH_DOMAIN \
  --set common.ingress.annotations."nginx\.ingress\.kubernetes\.io/proxy-buffer-size"=16k \
  --set common.ingress.tls.annotations."cert-manager\.io/cluster-issuer"=letsencrypt \
  --set registrar.config.subdomainTokenSigningKey=$ZENITH_SIGNING_KEY \
  --wait
```

## Launching the client

While still connected to the cluster on which the server is deployed, reserve a subdomain
to use with the client and store the information in a file. The endpoint for reserving a
subdomain is internal to the Zenith cluster, so we use `kubectl port-forward` to access it:

```sh
kubectl -n zenith port-forward svc/zenith-server-registrar 8080:80 >/dev/null &
until nc -z localhost 8080; do sleep 1; done
curl -X POST http://localhost:8080/admin/reserve | jq > subdomain.json
kill $(jobs -p)
```

Extract information about the endpoints to use and put it into a file:

```sh
cat <<EOF > zenith-server.env
export ZENITH_REGISTRAR_HOST="$(
  kubectl get ingress zenith-server-registrar \
     --namespace zenith \
     --output jsonpath='{.spec.rules[0].host}'
)"
export ZENITH_SSHD_IP="$(
  kubectl get svc zenith-server-sshd \
     --namespace zenith \
     --output jsonpath='{.status.loadBalancer.ingress[0].ip}'
)"
EOF
```

Generate an SSH keypair (no passphrase) for use with the client:

```sh
ssh-keygen -t rsa -b 4096 -f test-key
```

Now, switch to the cluster on which the client should be deployed, and launch it using
the following command:

```sh
source zenith-server.env
helm upgrade zenith-client ./client/ \
  --install \
  --set zenithClient.config.registrarUrl="https://$ZENITH_REGISTRAR_HOST" \
  --set zenithClient.config.serverAddress="$ZENITH_SSHD_IP" \
  --set zenithClient.sshKey.public="$(cat test-key.pub)" \
  --set zenithClient.sshKey.private="$(cat test-key)" \
  --set zenithClient.config.token="$(jq -r '.token' subdomain.json)" \
  --wait
```

Once the Zenith client app has launched, you can then visit the service by getting the
FQDN from the subdomain file written earlier:

```sh
open "https://$(jq -r '.fqdn' subdomain.json)"
```

### Enabling OIDC

Zenith natively supports using OIDC to authenticate services. To do this for an individual
service, you must first create a client in your OIDC identity provider using
`https://<service fqdn>/_oidc/callback` as the callback URL. This will result in a client ID and
secret which are passed to Zenith along with the URL of the identity provider - Zenith
will use the
[discovery endpoint](https://swagger.io/docs/specification/authentication/openid-connect-discovery/)
to discover how to connect with the provider:

```sh
source zenith-server.env
helm upgrade zenith-client ./client/ \
  --install \
  --set zenithClient.config.registrarUrl="https://$ZENITH_REGISTRAR_HOST" \
  --set zenithClient.config.serverAddress="$ZENITH_SSHD_IP" \
  --set zenithClient.sshKey.public="$(cat test-key.pub)" \
  --set zenithClient.sshKey.private="$(cat test-key)" \
  --set zenithClient.config.token="$(jq -r '.token' subdomain.json)" \
  --set zenithClient.config.authOidcIssuer="https://my-idp.com" \
  --set zenithClient.config.authOidcClientId="<client-id>" \
  --set zenithClient.config.authOidcClientSecret="<client-secret>" \
  --wait
```

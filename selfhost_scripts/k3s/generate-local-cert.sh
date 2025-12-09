#!/bin/bash
set -e
# TODO use env variables
DOMAIN1="mysky.local.app"
DOMAIN2="mysky.local.social"
BASE_DIR=$(git rev-parse --show-toplevel)
CERT_DIR=$BASE_DIR/foodios-chart/certs

mkdir -p "$CERT_DIR"

echo "Generating self-signed certificate for multiple domains..."
echo "  - *.$DOMAIN1 and $DOMAIN1"
echo "  - *.$DOMAIN2 and $DOMAIN2"

# Create OpenSSL config for SAN (Subject Alternative Names)
cat > "$CERT_DIR/openssl.cnf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=Local
L=Local
O=Foodios Local Development
CN=*.mysky.local

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN1
DNS.2 = *.$DOMAIN1
DNS.3 = $DOMAIN2
DNS.4 = *.$DOMAIN2
EOF

# Generate private key
openssl genrsa -out "$CERT_DIR/tls.key" 2048

# Generate certificate signing request
openssl req -new -key "$CERT_DIR/tls.key" -out "$CERT_DIR/tls.csr" -config "$CERT_DIR/openssl.cnf"

# Generate self-signed certificate (valid for 365 days)
openssl x509 -req -days 365 -in "$CERT_DIR/tls.csr" -signkey "$CERT_DIR/tls.key" -out "$CERT_DIR/tls.crt" -extensions v3_req -extfile "$CERT_DIR/openssl.cnf"

echo ""
echo "✓ Certificate generated successfully!"
echo "  Certificate: $CERT_DIR/tls.crt"
echo "  Private Key: $CERT_DIR/tls.key"
echo ""
echo "Next steps:"
echo "1. Create Kubernetes secret: kubectl create secret tls local-tls --cert=$CERT_DIR/tls.crt --key=$CERT_DIR/tls.key -n foodios"
echo "2. Trust the certificate on macOS: sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $CERT_DIR/tls.crt"
echo ""
# kubectl delete secret local-tls -n foodios
# kubectl create secret tls local-tls --cert=foodios-chart/certs/tls.crt --key=foodios-chart/certs/tls.key -n foodios
# kubectl rollout restart deployment -n foodios

# refer toplevel makefile for undefined variables and targets.

# target to generate self-signed CA certificate in easy.

#  run caddy 
#  HINT: make getCAcerts

getCAcert: ${wDir}/certs/root.crt ${wDir}/certs/intermediate.crt ${wDir}/certs/ca-bundle-curl.crt ${wDir}/certs/ca-bundle-openssl.crt

${wDir}/certs/root.crt ${wDir}/certs/root.key ${wDir}/certs/intermediate.crt ${wDir}/certs/intermediate.key:
	mkdir -p ${wDir}/certs
	@echo "start caddy as self-signed CA certificate generator."
	docker run -it --rm -d --name caddy -v ${wDir}/config/caddy/Caddyfile4cert:/etc/caddy/Caddyfile caddy:2
	@echo "wait a little for caddy get ready..."
	@sleep 1
	@echo "get self-signed CA certificates from caddy container"
	docker cp caddy:/data/caddy/pki/authorities/local/root.crt ${wDir}/certs/
	docker cp caddy:/data/caddy/pki/authorities/local/root.key ${wDir}/certs/
	docker cp caddy:/data/caddy/pki/authorities/local/intermediate.crt ${wDir}/certs/
	docker cp caddy:/data/caddy/pki/authorities/local/intermediate.key ${wDir}/certs/
	docker rm -f caddy

# CA bundle for curl (intermediate first, then root)
${wDir}/certs/ca-bundle-curl.crt: ${wDir}/certs/intermediate.crt ${wDir}/certs/root.crt
	@echo "generating CA bundle for curl..."
	cat ${wDir}/certs/intermediate.crt ${wDir}/certs/root.crt > ${wDir}/certs/ca-bundle-curl.crt

# CA bundle for OpenSSL (root first, then intermediate)
${wDir}/certs/ca-bundle-openssl.crt: ${wDir}/certs/root.crt ${wDir}/certs/intermediate.crt
	@echo "generating CA bundle for OpenSSL..."
	cat ${wDir}/certs/root.crt ${wDir}/certs/intermediate.crt > ${wDir}/certs/ca-bundle-openssl.crt

# Update certificates from running caddy container
updateCAcert:
	@echo "updating CA certificates from running caddy container..."
	@if ! docker ps --format '{{.Names}}' | grep -E 'caddy$$|.*-caddy-[0-9]+$$' >/dev/null; then \
		echo "Error: No running caddy container found"; \
		echo "Available containers:"; \
		docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'; \
		exit 1; \
	fi
	@CADDY_CONTAINER=$$(docker ps --format '{{.Names}}' | grep -E 'caddy$$|.*-caddy-[0-9]+$$' | head -1); \
	echo "Using caddy container: $$CADDY_CONTAINER"; \
	mkdir -p ${wDir}/certs; \
	docker cp $$CADDY_CONTAINER:/data/caddy/pki/authorities/local/root.crt ${wDir}/certs/; \
	docker cp $$CADDY_CONTAINER:/data/caddy/pki/authorities/local/root.key ${wDir}/certs/; \
	docker cp $$CADDY_CONTAINER:/data/caddy/pki/authorities/local/intermediate.crt ${wDir}/certs/; \
	docker cp $$CADDY_CONTAINER:/data/caddy/pki/authorities/local/intermediate.key ${wDir}/certs/; \
	$(MAKE) CAbundles

# CA bundles built from existing certificates
CAbundles: ${wDir}/certs/ca-bundle-curl.crt ${wDir}/certs/ca-bundle-openssl.crt

ifeq ($(shell uname),Darwin)
# On MacOS, check if certificate is already in system keychain and if not install
installCAcert:
	@echo "install self-signed CA certificate into system keychain..."
	@if ! security find-certificate -c "Caddy Local Authority" /System/Library/Keychains/SystemRootCertificates.keychain > /dev/null 2>&1 && \
	   ! security find-certificate -c "Caddy Local Authority" /Library/Keychains/System.keychain > /dev/null 2>&1; then \
		echo "Adding certificate to system keychain (will ask for user password to sudo on commandline and then in GUI)..."; \
		sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ${wDir}/certs/root.crt; \
	else \
		echo "Certificate already exists in system keychain"; \
	fi
else
installCAcert:
	@echo "install self-signed CA certificate into this machine..."
	sudo cp -p ${wDir}/certs/root.crt /usr/local/share/ca-certificates/testCA-caddy.crt
	sudo update-ca-certificates
endif

ifeq ($(shell uname),Darwin)
${wDir}/certs/ca-certificates.crt:
	@echo "Extracting system CA certificates from macOS keychains for Docker containers..."
	@mkdir -p ${wDir}/certs
	@# Export all certificates from system root certificates keychain
	@security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain > $@
	@# Export all certificates from system keychain and append
	@security find-certificate -a -p /Library/Keychains/System.keychain >> $@ 2>/dev/null || true
	@echo "Exported $$(grep -c 'BEGIN CERTIFICATE' $@) certificates from macOS system keychains"
else
${wDir}/certs/ca-certificates.crt:
	@echo "Extracting system CA certificates for Docker containers..."
	cp -p /etc/ssl/certs/ca-certificates.crt $@
endif

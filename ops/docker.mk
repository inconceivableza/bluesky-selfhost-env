
_up_templ: _load_vars
	${_envs} docker-compose -f ${f} up -d ${services}

# _env := passfile + below listup vars. cf. sed '1i' command inserts given chars to stdin.
_load_vars:
	$(eval _envs=@$(shell cat ${passfile} | sed '1i\
DOMAIN=${DOMAIN} \
asof=${asof} \
dDir=${dDir} \
LOG_LEVEL_DEFAULT=${LOG_LEVEL_DEFAULT} \
EMAIL4CERTS=${EMAIL4CERTS} \
PDS_EMAIL_SMTP_URL=${PDS_EMAIL_SMTP_URL} \
FEEDGEN_PUBLISHER_DID=${FEEDGEN_PUBLISHER_DID} \
FEEDGEN_PUBLISHER_HANDLE=${FEEDGEN_PUBLISHER_HANDLE}' \
	| cat))
	@echo ${_envs} | sed 's/ /\n/g' | awk -F= '{print $$1,"=",$$2}' | sed 's/ //g'

_old_load_vars:
	$(eval _envs=$${_TEMPLATE_VARS})
	@echo ${_envs} | sed 's/ /\n/g' | awk -F= '{print $$1,"=",$$2}' | sed 's/ //g'

build:
	DOMAIN=${DOMAIN} asof=${asof} docker-compose -f ${f} build ${services}

#docker-start::      setupdir config/caddy/Caddyfile certs/ca-certificates.crt ${passfile} _applySdep _docker_up
docker-start::      setupdir config/caddy/Caddyfile certs/ca-certificates.crt ${passfile} _applySdep _up_templ
docker-start::      docker-watchlog
docker-start-bsky:: _applySbsky _up_templ
docker-start-bsky:: docker-watchlog
docker-start-bsky-feedgen:: _applySfeed _up_templ
docker-start-bsky-feedgen:: docker-watchlog
docker-stop:
	docker-compose -f ${f} down -v ${services}
	docker system  prune -f
	docker volume  prune -f
	docker network prune -f
	sudo rm -rf ${dDir}
#	rm -rf ${passfile}

docker-watchlog:
	-docker-compose -f ${f} logs -f || true

_old_docker_up:
	DOMAIN=${DOMAIN} asof=${asof} EMAIL4CERTS=${EMAIL4CERTS} LOG_LEVEL_DEFAULT=${LOG_LEVEL_DEFAULT} \
	    dDir=${dDir} \
	    PDS_EMAIL_SMTP_URL=${PDS_EMAIL_SMTP_URL} \
	    FEEDGEN_PUBLISHER_DID=${FEEDGEN_PUBLISHER_DID} \
	    FEEDGEN_PUBLISHER_HANDLE=${FEEDGEN_PUBLISHER_HANDLE} \
	    FEEDGEN_PUBLISHER_PASSWORD=${FEEDGEN_PUBLISHER_PASSWORD} \
	    ADMIN_PASSWORD=${ADMIN_PASSWORD} \
	    BGS_ADMIN_KEY=${BGS_ADMIN_KEY} \
	    IMG_URI_KEY=${IMG_URI_KEY} \
	    IMG_URI_SALT=${IMG_URI_SALT} \
	    MODERATOR_PASSWORD=${MODERATOR_PASSWORD} \
	    OZONE_ADMIN_PASSWORD=${OZONE_ADMIN_PASSWORD} \
	    OZONE_MODERATOR_PASSWORD=${OZONE_MODERATOR_PASSWORD} \
	    OZONE_SIGNING_KEY_HEX=${OZONE_SIGNING_KEY_HEX} \
	    OZONE_TRIAGE_PASSWORD=${OZONE_TRIAGE_PASSWORD} \
	    PDS_ADMIN_PASSWORD=${PDS_ADMIN_PASSWORD} \
	    PDS_JWT_SECRET=${PDS_JWT_SECRET} \
	    PDS_PLC_ROTATION_KEY_K256_PRIVATE_KEY_HEX=${PDS_PLC_ROTATION_KEY_K256_PRIVATE_KEY_HEX} \
	    PDS_REPO_SIGNING_KEY_K256_PRIVATE_KEY_HEX=${PDS_REPO_SIGNING_KEY_K256_PRIVATE_KEY_HEX} \
	    SERVICE_SIGNING_KEY=${SERVICE_SIGNING_KEY} \
	    TRIAGE_PASSWORD=${TRIAGE_PASSWORD} \
	    POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
	    BSKY_SERVICE_SIGNING_KEY=${BSKY_SERVICE_SIGNING_KEY} \
	    PASS=${PASS} \
        docker-compose -f ${f} up -d ${services}

docker-check-status:
	docker ps -a
	docker volume ls

docker-rm-all:
	-docker ps -a -q | xargs docker rm -f
	-docker volume ls | tail -n +2 | awk '{print $$2}' | xargs docker volume rm -f
	-docker system prune -f

# target to configure variable
_applySdep:
	$(eval services=${Sdep})
_applySbsky:
	$(eval services=${Sbsky})
_applySfeed:
	$(eval services=${Sfeed})

#
# _TEMPLATE_VARS: make lists of env vars to feed docker-compose and containers >>>>>
#
define _TEMPLATE_VARS
DOMAIN=${DOMAIN} \
asof=${asof} \
dDir=${dDir} \
LOG_LEVEL_DEFAULT=${LOG_LEVEL_DEFAULT} \
EMAIL4CERTS=${EMAIL4CERTS} \
PDS_EMAIL_SMTP_URL=${PDS_EMAIL_SMTP_URL} \
FEEDGEN_PUBLISHER_DID=${FEEDGEN_PUBLISHER_DID} \
FEEDGEN_PUBLISHER_HANDLE=${FEEDGEN_PUBLISHER_HANDLE} \
ADMIN_PASSWORD=${ADMIN_PASSWORD} \
BGS_ADMIN_KEY=${BGS_ADMIN_KEY} \
IMG_URI_KEY=${IMG_URI_KEY} \
IMG_URI_SALT=${IMG_URI_SALT} \
MODERATOR_PASSWORD=${MODERATOR_PASSWORD} \
OZONE_ADMIN_PASSWORD=${OZONE_ADMIN_PASSWORD} \
OZONE_MODERATOR_PASSWORD=${OZONE_MODERATOR_PASSWORD} \
OZONE_SIGNING_KEY_HEX=${OZONE_SIGNING_KEY_HEX} \
OZONE_TRIAGE_PASSWORD=${OZONE_TRIAGE_PASSWORD} \
PDS_ADMIN_PASSWORD=${PDS_ADMIN_PASSWORD} \
PDS_JWT_SECRET=${PDS_JWT_SECRET} \
PDS_PLC_ROTATION_KEY_K256_PRIVATE_KEY_HEX=${PDS_PLC_ROTATION_KEY_K256_PRIVATE_KEY_HEX} \
PDS_REPO_SIGNING_KEY_K256_PRIVATE_KEY_HEX=${PDS_REPO_SIGNING_KEY_K256_PRIVATE_KEY_HEX} \
POSTGRES_USER=${POSTGRES_USER} \
POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
SERVICE_SIGNING_KEY=${SERVICE_SIGNING_KEY} \
TRIAGE_PASSWORD=${TRIAGE_PASSWORD} \
FEEDGEN_PUBLISHER_PASSWORD=${FEEDGEN_PUBLISHER_PASSWORD} \
BSKY_SERVICE_SIGNING_KEY=${BSKY_SERVICE_SIGNING_KEY} \
BSKY_ADMIN_PASSWORDS=${BSKY_ADMIN_PASSWORDS} \
PASS=${PASS}
endef
export _TEMPLATE_VARS
#
# _TEMPLATE_VARS: make lists of env vars to feed docker-compose and containers <<<<<
#

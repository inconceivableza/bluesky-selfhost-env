
dockerCompose ?= docker compose
dockerPullPolicy ?= missing
auto_watchlog ?= true
COMPOSE_PROFILES ?= $(shell echo ${_nrepo} | sed 's/ /,/g')

_dockerUp: envs
	${dockerCompose} -f ${f} up --pull ${dockerPullPolicy} -d ${services}

docker-pull:
	DOMAIN= asof=${asof} branded_asof=${branded_asof} ${dockerCompose} -f ${f} pull --policy ${dockerPullPolicy}
docker-pull-unbranded:
	DOMAIN= asof=${asof} branded_asof=${branded_asof} ${dockerCompose} -f ${f} pull --policy ${dockerPullPolicy} ${unbranded_services}
build:
	COMPOSE_PROFILES=${COMPOSE_PROFILES} asof=${asof} branded_asof=${branded_asof} ${dockerCompose} -f ${f} build ${build_args} ${services}

docker-start::      setupdir ${wDir}/config/caddy/Caddyfile ${passfile}
ifeq ($(EMAIL4CERTS),internal)
docker-start::      ${wDir}/certs/root.crt ${wDir}/certs/ca-certificates.crt
endif
docker-start::      _applySdep _dockerUp
ifeq ($(auto_watchlog),true)
docker-start::      docker-watchlog
endif

docker-start-bsky:: _applySbsky _dockerUp
ifeq ($(auto_watchlog),true)
docker-start-bsky:: docker-watchlog
endif

docker-start-bsky-feedgen:: _applySfeed _dockerUp
ifeq ($(auto_watchlog),true)
docker-start-bsky-feedgen:: docker-watchlog
endif

docker-start-bsky-ozone:: _applySozone _dockerUp
ifeq ($(auto_watchlog),true)
docker-start-bsky-ozone:: docker-watchlog
endif

docker-start-bsky-jetstream:: _applySjetstream _dockerUp
ifeq ($(auto_watchlog),true)
docker-start-bsky-jetstream:: docker-watchlog
endif

docker-start-backup:: _applySbackup _dockerUp
ifeq ($(auto_watchlog),true)
docker-start-backup:: docker-watchlog
endif

# execute publishFeed on feed-generator
publishFeed:
	DOMAIN=${DOMAIN} asof=${asof} branded_asof=${branded_asof} docker_network=${docker_network} ${dockerCompose} -f ${f} exec feed-generator /app/scripts/publishFeed.exp ${FEEDGEN_PUBLISHER_HANDLE} "${FEEDGEN_PUBLISHER_PASSWORD}" https://${pdsFQDN} whats-alf

# execute reload on caddy container
reloadCaddy:
	DOMAIN=${DOMAIN} asof=${asof} branded_asof=${branded_asof} docker_network=${docker_network} ${dockerCompose} -f ${f} exec caddy caddy reload -c /etc/caddy/Caddyfile

docker-stop:
	${dockerCompose} -f ${f} down ${services}
docker-stop-with-clean:
	${dockerCompose} -f ${f} down -v ${services}
	docker volume  prune -f
	docker system  prune -f
	docker network rm -f ${docker_network}
	@echo You may want to remove the data directory:
	@echo rm -rf ${dDir}

docker-watchlog:
	-${dockerCompose} -f ${f} logs -f || true

docker-check-status:
	docker ps -a
	docker volume ls

docker-rm-all:
	-docker ps -a -q | xargs docker rm -f
	-docker volume ls | tail -n +2 | awk '{print $$2}' | xargs docker volume rm -f
	-docker system prune -f

docker-exec: envs
docker-exec:
	docker ${cmd}

docker-compose-exec: envs
docker-compose-exec:
	${dockerCompose} --env-file=${params_file} ${cmd}


_gen_compose_for_binary:
	cat docker-compose-builder.yaml | yq -yY 'del(.services[].build)' > docker-compose.yaml

# target to configure variable
_applySdep:
	$(eval services=${Sdep})
_applySbsky:
	$(eval services=${Sbsky})
_applySfeed:
	$(eval services=${Sfeed})
_applySozone:
	$(eval services=${Sozone})
_applySjetstream:
	$(eval services=${Sjetstream})
_applySbackup:
	$(eval services=${Sbackup})

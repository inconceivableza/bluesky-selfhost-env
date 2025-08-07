##########################################################################################
# starts: definitions, need to care in especial.

# Include the .env file, which can be a symlink pointing to an env - see params-file-util.sh
ifeq (,$(wildcard ./.env))
    $(error .env file not found. Please create one based on bluesky-params.env.example and symlink to .env)
endif

# Validate .env file has all required variables
ENV_CHECK_RESULT := $(shell ./selfhost_scripts/check-env.py -s 2>/dev/null; echo $$?)
ifneq ($(ENV_CHECK_RESULT),0)
    $(error .env file is missing required variables. Run './selfhost_scripts/check-env.py' to see what is missing and correct it)
endif

include .env

# this is used for identifying restic backups; try to get as specifica a FQDN name as possible
HOST_HOSTNAME ?= $(shell { hostname -A 2>/dev/null | sed 's/ /\n/g' | sed 's/.internal//g' ; hostname ; } | head -n 1)

##########################################################################################
# other definitions

#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# paths for folders and files

# top level folder
wDir ?=${PWD}

# data folder to persist container's into filesystem
dDir ?=${wDir}/data

# account folder (for feed-generator and others, created with bluesky API during ops).
aDir ?=${dDir}/accounts

# top level repos folder
rDir ?=${wDir}/repos

# file path to store generated passwords with openssl, during ops.
passfile ?=${wDir}/config/secrets-passwords.env

# List of all secret env files that can be generated
SECRET_ENV_FILES := config/backup-secrets.env config/bgs-secrets.env config/bsky-secrets.env config/db-secrets.env config/opensearch-secrets.env config/ozone-secrets.env config/palomar-secrets.env config/pds-secrets.env config/plc-secrets.env

# derived secrets files that limit the scope of secrets

# lots of the other files incorporate the contents of db-secrets.env
config/db-secrets.env: ${passfile}
	@grep -h '^POSTGRES_PASSWORD=' $^ > $@ || echo postgres password not found >&2
	@echo "POSTGRES_USER=${POSTGRES_USER}" >> $@ # this will persist the POSTGRES_USER from the current .env; that and the password are then used in subsequent variables

config/backup-secrets.env: ${passfile} config/db-secrets.env
	@cat config/db-secrets.env > $@
	@grep -h '^\(RESTIC_PASSWORD\|RESTIC_REMOTE_PASSWORD[123]=\|RESTIC_AWS_SECRET_ACCESS_KEY\)' $^ >> $@
	@grep -h '^RESTIC_\(AWS_ACCESS_KEY_ID\|AWS_SECRET_ACCESS_KEY\)=' $^ | sed 's/^RESTIC_//' >> $@

config/bgs-secrets.env: ${passfile} config/db-secrets.env
	@grep -h '^BGS_ADMIN_KEY=' $^ > $@
	@cat config/db-secrets.env >> $@
	@echo 'CARSTORE_DATABASE_URL=postgres://$${POSTGRES_USER}:$${POSTGRES_PASSWORD}@database/carstore' >> $@
	@echo 'DATABASE_URL=postgres://$${POSTGRES_USER}:$${POSTGRES_PASSWORD}@database/bgs' >> $@

config/bsky-secrets.env: ${passfile} config/db-secrets.env
	@grep -h '^\(BSKY_ADMIN_PASSWORDS\|BSKY_SERVICE_SIGNING_KEY\|BSKY_STATSIG_KEY\)=' $^ > $@
	@cat config/db-secrets.env >> $@
	@echo 'BSKY_DB_POSTGRES_URL=postgres://$${POSTGRES_USER}:$${POSTGRES_PASSWORD}@database/bsky' >> $@

config/opensearch-secrets.env: ${passfile}
	@grep -h '^OPENSEARCH_INITIAL_ADMIN_PASSWORD=' $^ > $@

config/ozone-secrets.env: ${passfile} config/db-secrets.env
	@grep -h '^\(OZONE_ADMIN_PASSWORD\|OZONE_SIGNING_KEY_HEX\)=' $^ > $@
	@cat config/db-secrets.env >> $@
	@echo 'OZONE_DB_POSTGRES_URL=postgres://$${POSTGRES_USER}:$${POSTGRES_PASSWORD}@database/ozone' >> $@

config/palomar-secrets.env: config/opensearch-secrets.env
	@cat $^ > $@
	@grep -h '^OPENSEARCH_INITIAL_ADMIN_PASSWORD=' $^ | sed 's/OPENSEARCH_INITIAL_ADMIN_PASSWORD/ES_PASSWORD/' >> $@
	@cat config/db-secrets.env >> $@
	@echo 'DATABASE_URL=postgres://$${POSTGRES_USER}:$${POSTGRES_PASSWORD}@database/palomar' >> $@

config/pds-secrets.env: ${passfile}
	@grep -h '^\(PDS_ADMIN_PASSWORD\|PDS_JWT_SECRET\|PDS_PLC_ROTATION_KEY_K256_PRIVATE_KEY_HEX\)=' $^ > $@

config/plc-secrets.env: config/db-secrets.env
	@cat $^ > $@
	@echo 'DATABASE_URL=postgres://$${POSTGRES_USER}:$${POSTGRES_PASSWORD}@database/plc' >> $@
	@echo 'DB_CREDS_JSON={"username":"$${POSTGRES_USER}","password":"$${POSTGRES_PASSWORD}","host":"database","port":"5432","database":"plc"}' >> $@
	@echo 'DB_MIGRATE_CREDS_JSON={"username":"$${POSTGRES_USER}","password":"$${POSTGRES_PASSWORD}","host":"database","port":"5432","database":"plc"}' >> $@

clean-secret-envs:
	rm -f $(SECRET_ENV_FILES)

secret-envs: $(SECRET_ENV_FILES)

# docker-compose file
f ?=${wDir}/docker-compose.yaml
#f ?=${wDir}/docker-compose-builder.yaml

# folders of repos
#_nrepo  ?=atproto indigo social-app feed-generator did-method-plc pds ozone jetstream
_nrepo   ?=atproto indigo social-app feed-generator did-method-plc ozone jetstream
repoDirs ?=$(addprefix ${rDir}/, ${_nrepo})
_nofork  ?=feed-generator ozone jetstream

#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# other parameters

# prefix of github (https://github.com/ | git@github.com:)
gh  ?=$(addsuffix /, https://github.com)
gh_git ?=$(addsuffix :, git@github.com)

# origin repo prefix to clone source, points code owner(org). DO NOT CHANGE THESE, FOR USUAL CASES. these are features for experts.
origin_repo_bsky_prefix ?=${gh}bluesky-social/
origin_repo_did_prefix  ?=${gh}did-method-plc/

# services to start in N-step ops, with single docker-compose file.
# by these parameters, you can tune which components to start
#  - no need to edit this file. just set environment as below before execute ops.
#  - following three lines allow you try-out integration/fediverse with official PLC and public CA(lets encrypt).
#    export plcFQDN=plc.directory
#    export EMAIL4CERTS=YOUR-VALID-EMAIL-ADDRESS
#    export Sdep='caddy caddy-sidecar database redis opensearch test-wss test-ws test-indigo pgadmin'
#    # no plc in Sdep, comparing below line.
#
Sdep  ?=caddy caddy-sidecar database redis opensearch plc test-wss test-ws test-indigo pgadmin backup ipcc otel-collector jaeger prometheus
Sbsky ?=pds bgs bsky social-app palomar
Sfeed ?=feed-generator
#Sozone ?=ozone ozone-daemon
Sozone ?=ozone-standalone
Sjetstream ?=jetstream
Sbackup ?=backup

# load passfile content as Makefile variables if exists
ifeq ($(shell test -e ${passfile} && echo -n exists),exists)
   include ${passfile}
endif

##########################################################################################
##########################################################################################
# starts:  targets for  operations


# get all sources from github
cloneAll:   ${repoDirs} remoteForks

ifeq (${fork_repo_name},)
_frn := fork
else
_frn := ${fork_repo_name}
endif

ifneq ($(fork_repo_prefix),)
_prepr ?=$(filter-out ${_nofork},${_nrepo})
remoteForks: $(addprefix ${rDir}/,$(addsuffix /.git/refs/remotes/${fork_repo_name},${_prepr}))
else
remoteForks:
	$(warning define fork_repo_prefix in .env (and optionally fork_repo_name) for remoteForks to be fetched)
endif

${rDir}/atproto:
	git clone ${origin_repo_bsky_prefix}atproto.git $@

ifneq ($(fork_repo_prefix),)
${rDir}/atproto/.git/refs/remotes/$(_frn)/:
	-(cd ${rDir}//atproto/; git remote add ${_frn} ${fork_repo_prefix}atproto.git; git remote update ${_frn})
endif


${rDir}/indigo:
	git clone ${origin_repo_bsky_prefix}indigo.git $@

ifneq ($(fork_repo_prefix),)
${rDir}/indigo/.git/refs/remotes/brightsun/:
	-(cd ${rDir}/indigo; git remote add ${_frn} ${fork_repo_prefix}indigo.git; git remote update ${_frn})
endif


${rDir}/social-app:
	git clone ${origin_repo_bsky_prefix}social-app.git $@

ifneq ($(fork_repo_prefix),)
${rDir}/social-app/.git/refs/remotes/${_frn}/:
	-(cd ${rDir}/social-app; git remote add ${_frn} ${fork_repo_prefix}social-app.git; git remote update ${_frn})
endif


${rDir}/feed-generator:
	git clone ${origin_repo_bsky_prefix}feed-generator.git $@

ifneq ($(fork_repo_prefix),)
${rDir}/feed-generator/.git/refs/remotes/${_frn}/:
	-(cd ${rDir}/feed-generator; git remote add ${_frn} ${fork_repo_prefix}feed-generator.git; git remote update ${_frn})
endif


${rDir}/pds:
	git clone ${origin_repo_bsky_prefix}pds.git $@

ifneq ($(fork_repo_prefix),)
${rDir}/pds/.git/refs/remotes/${_frn}/:
	-(cd ${rDir/pds}; git remote add ${_frn} ${fork_repo_prefix}pds.git; git remote update ${_frn})
endif


${rDir}/ozone:
	git clone ${origin_repo_bsky_prefix}ozone.git $@

ifneq ($(fork_repo_prefix),)
${rDir}/ozone/.git/refs/remotes/${_frn}/:
	-(cd ${rDir}/ozone; git remote add ${_frn} ${fork_repo_prefix}ozone.git; git remote update ${_frn})
endif


${rDir}/did-method-plc:
	git clone ${origin_repo_did_prefix}did-method-plc.git $@

ifneq ($(fork_repo_prefix),)
${rDir}/did-method-plc/.git/refs/remotes/${_frn}/:
	-(cd ${rDir}/did-method-plc; git remote add ${_frn} ${fork_repo_prefix}did-method-plc.git; git remote update ${_frn})
endif


${rDir}/jetstream:
	git clone ${origin_repo_bsky_prefix}jetstream.git $@

ifneq ($(fork_repo_prefix),)
${rDir}/jetstream/.git/refs/remotes/${_frn}/:
	-(cd ${rDir}/jetstream; git remote add ${_frn} ${fork_repo_prefix}jetstream.git; git remote update ${_frn})
endif


# delete all repos.
delRepoDirAll:
	rm -rf ${rDir}/[a-z]*

# generate secrets for test env
genSecrets: ${passfile}
${passfile}: ./config/gen-secrets.sh
	wDir=${wDir} ./config/gen-secrets.sh
	cat $@
	@echo "secrets generated and stored in $@"

genSecrets: secret-envs

setupdir:
	mkdir -p ${aDir}

################################
# include other ops.
################################
include ops/git.mk
include ops/certs.mk
include ops/docker.mk
include ops/patch.mk
include ops/api-bsky.mk

# execute the command under folders (one or multiple).
# HINT: make exec under=./repos/* cmd='git status                        | cat'  => show        git status for all repos.
# HINT: make exec under=./repos/* cmd='git branch --show-current         | cat'  => show        current branch for all repos
# HINT: make exec under=./repos/* cmd='git log --decorate=full | head -3 | cat ' => show        last commit log for all repos
# HINT: make exec under=./repos/* cmd='git remote update ${fork_repo_name:-fork}            | cat'  => update      remote named ${fork_repo_name:-fork} for all repos
# HINT: make exec under=./repos/* cmd='git checkout work                 | cat'  => checkout to work branch for all repos.
# HINT: make exec under=./repos/* cmd='git push ${fork_repo_name:-fork} --tags              | cat'  => push        tags to remote named ${fork_repo_name:-fork}
exec: ${under}
	for d in ${under}; do \
		r=`basename $${d})`; \
		echo "############ exec cmd @ $${d} $${r} ########################################" ;\
		(cd $${d};   ${cmd} ); \
	done;

# to show ops configurations
# HINT: make echo
echo:
	@echo ""
	@echo "########## >>>>>>>>>>>>>>"
	@echo "DOMAIN:        ${DOMAIN}"
	@echo "asof:          ${asof}"
	@echo "branded_asof:  ${branded_asof}"
	@echo ""
	@echo "bgsFQDN       ${bgsFQDN}"
	@echo "bskyFQDN      ${bskyFQDN}"
	@echo "feedgenFQDN   ${feedgenFQDN}"
	@echo "jetstreamFQDN ${jetstreamFQDN}"
	@echo "ozoneFQDN     ${ozoneFQDN}"
	@echo "palomarFQDN   ${palomarFQDN}"
	@echo "pdsFQDN       ${pdsFQDN}"
	@echo "plcFQDN       ${plcFQDN}"
	@echo "publicApiFQDN ${publicApiFQDN}"
	@echo "socialappFQDN ${socialappFQDN}"
	@echo ""
	@echo "EMAIL4CERTS: ${EMAIL4CERTS}"
	@echo "PDS_EMAIL_SMTP_URL: ${PDS_EMAIL_SMTP_URL}"
	@echo "FEEDGEN_EMAIL: ${FEEDGEN_EMAIL}"
	@echo "FEEDGEN_PUBLISHER_HANDLE: ${FEEDGEN_PUBLISHER_HANDLE}"
	@echo "FEEDGEN_PUBLISHER_PASSWORD: ${FEEDGEN_PUBLISHER_PASSWORD}"
	@echo "OZONE_ADMIN_EMAIL: ${OZONE_ADMIN_EMAIL}"
	@echo "OZONE_ADMIN_HANDLE: ${OZONE_ADMIN_HANDLE}"
	@echo "OZONE_ADMIN_PASSWORD: ${OZONE_ADMIN_PASSWORD}"
	@echo ""
	@echo "wDir:     ${wDir}"
	@echo "passfile: ${passfile}"
	@echo "dDir:     ${dDir}"
	@echo "aDir:     ${aDir}"
	@echo "rDir:     ${rDir}"
	@echo "_nrepo:   ${_nrepo}"
	@echo "repoDirs: ${repoDirs}"
	@echo "f:        ${f}"
	@echo "gh:       ${gh}"
	@echo "fork_repo_name: ${fork_repo_name}"
	@echo "fork_repo_prefix: ${fork_repo_prefix}"
	@echo ""
	@echo "LOG_LEVEL_DEFAULT=${LOG_LEVEL_DEFAULT}"
	@echo "########## <<<<<<<<<<<<<<"

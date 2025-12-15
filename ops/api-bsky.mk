
# output file path of API response.
resp ?=/dev/null

# component urls for default:
pdsURL   ?=https://${pdsFQDN}
bgsURL   ?=https://${bgsFQDN}
relayURL ?=https://${relayFQDN}
ozoneURL ?=https://${ozoneFQDN}

#HINT: make api_setPerDayLimit
api_setPerDayLimit:
	$(eval _key=$(shell cat ${passfile} | grep RELAY_ADMIN_KEY | awk -F= '{ print $$2}'))
	$(eval _token=$(shell echo -n "admin:${_key}" | base64 -w0))
	curl -k -X POST -L "${relayURL}/admin/subs/setPerDayLimit?limit=10000" -H "Authorization: Basic ${_token}"
	curl -k -X GET  -L "${relayURL}/admin/subs/perDayLimit" -H "Authorization: Basic ${_token}"

#HINT: make api_CreateAccount email=...  password=...  handle=...
api_CreateAccount:: _mkmsg_createAccount  _sendMsg
api_CreateAccount:: _echo_reqAccount _findDid

#HINT: make api_CheckAccount handle=... password=...
api_CheckAccount:: _mkmsg_createSession _sendMsg
api_CheckAccount:: _echo_reqAccount _findDid

#HINT: make api_DeleteAccount did=...
api_DeleteAccount:
	$(eval pass=$(shell cat ${passfile} | grep PDS_ADMIN_PASSWORD | awk -F= '{ print $$2}'))
	$(eval url=${pdsURL}/xrpc/com.atproto.admin.deleteAccount)
	curl -k -X POST -u "admin:${pass}" ${url} -H 'content-type: application/json' -d '{ "did": "${did}" }'
	-echo '' | grep -s -l ${did} ${aDir}/*.secrets | xargs rm -f

#HINT: make api_CreateAccount_feedgen
api_CreateAccount_feedgen: getFeedgenUserinfo api_CreateAccount

#HINT: make api_CheckAccount_feedgen
api_CheckAccount_feedgen: getFeedgenUserinfo api_CheckAccount

#HINT: make api_CreateAccount_ozone
api_CreateAccount_ozone: getOzoneUserinfo api_CreateAccount

#HINT: make api_CheckAccount_ozone
api_CheckAccount_ozone: getOzoneUserinfo api_CheckAccount

#HINT: api_ozone_member_add role=...  did=...
api_ozone_member_add:
	$(eval pass=$(shell cat ${passfile} | grep OZONE_ADMIN_PASSWORD | awk -F= '{ print $$2}'))
	curl -k -L -X POST -u "admin:${pass}" ${ozoneURL}/xrpc/tools.ozone.team.addMember -H "content-type: application/json" -d '{"role": "${role}", "did": "${did}" }'
	curl -k -L -X GET  -u "admin:${pass}" ${ozoneURL}/xrpc/tools.ozone.team.listMembers | jq

#HINT: make api_ozone_reqPlcSign handle=... password=...
api_ozone_reqPlcSign: getOzoneUserinfo
	./selfhost_scripts/apiImpl/reqPlcOpeSign.ts --pdsURL ${pdsURL} --handle ${handle} --password ${password}
	@echo "########## check email for ${handle}, token sent #########"

#HINT: make api_ozone_updateDidDoc   plcSignToken=...  ozoneURL=...  handle=... password=...
api_ozone_updateDidDoc: getOzoneUserinfo
	$(eval signkey=$(shell cat ${passfile} | grep OZONE_SIGNING_KEY_HEX | awk -F= '{ print $$2}'))
	./selfhost_scripts/apiImpl/updateDidDoc-labeler.ts --plcSignToken ${plcSignToken} --signingKeyHex ${signkey} --pdsURL ${pdsURL} --handle ${handle} --password ${password} --labelerURL=${ozoneURL}

_sendMsg:
	@curl -k -L -X ${method} ${url} ${header} ${msg} | tee -a ${resp}


ifeq (${PDS_INVITE_REQUIRED}, true)
_mkmsg_createAccount::
	@echo PDS invite required: requesting invite code from server
	$(eval invite_code=$(shell curl --fail --silent --show-error --request POST --user "admin:${PDS_ADMIN_PASSWORD}" --header "Content-Type: application/json" --data '{"useCount": 1}' https://${pdsFQDN}/xrpc/com.atproto.server.createInviteCode | jq --raw-output '.code'))
endif

_mkmsg_createAccount::
	$(eval url=${pdsURL}/xrpc/com.atproto.server.createAccount)
	$(eval method=POST)
	$(eval header=-H 'Content-Type: application/json'  -H 'Accept: application/json')
	$(eval msg=-d '{ "email": "${email}" ,"handle": "${handle}", "password": "${password}", "inviteCode": "${invite_code}" }')

_mkmsg_createSession::
	$(eval url=${pdsURL}/xrpc/com.atproto.server.createSession)
	$(eval method=POST)
	$(eval header=-H 'Content-Type: application/json'  -H 'Accept: application/json')
	$(eval msg=-d '{ "identifier": "${handle}", "password": "${password}" }')

_mkmsg_checkAccount::
	$(eval url=${pdsURL}/xrpc/com.atproto.server.checkAccountStatus)
	$(eval method=POST)
	$(eval header=-H 'Content-Type: application/json'  -H 'Accept: application/json')
	$(eval msg=--user "${handle}:${password}")

getFeedgenUserinfo:
	$(eval handle=${FEEDGEN_PUBLISHER_HANDLE})
	$(eval email=${FEEDGEN_EMAIL})
	$(eval password=$(shell cat ${passfile} | grep FEEDGEN_PUBLISHER_PASSWORD | awk -F= '{ print $$2}'))
	$(eval resp=${aDir}/${handle}.secrets)

getOzoneUserinfo:
	$(eval handle=${OZONE_ADMIN_HANDLE})
	$(eval email=${OZONE_ADMIN_EMAIL})
	$(eval password=$(shell cat ${passfile} | grep OZONE_ADMIN_PASSWORD | awk -F= '{ print $$2}'))
	$(eval resp=${aDir}/${handle}.secrets)

_echo_reqAccount:
	@echo ""
	@echo "handle:     ${handle}"
	@echo "email:      ${email}"
	@echo "password:   ${password}"
	@echo "resp(path): ${resp}"

_echo_apiops:
	@echo "url:    ${url}"
	@echo "method: ${method}"
	@echo "header: ${header}"
	@echo "msg:    ${msg}"

_findDid:
	@echo -n "### DID: "
	-@cat ${resp} | jq ".did // empty" | sed 's/"//g'
ifneq ($(exportDidFile), )
	-@cat ${resp} | jq ".did // empty" | sed 's/"//g' > "${exportDidFile}"
	-@echo DID saved to ${exportDidFile}
endif


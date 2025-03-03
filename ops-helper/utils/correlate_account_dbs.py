#!/usr/bin/env python

"""This is a script to check the correlations between atproto/bluesky/brightsun user accounts, dids, profiles, handles etc
It relies on all the data being in a directory in JSON format, as extracted by the account data script in brightsun's
bluesky-selfhost-env under ops-helper/backup-scripts/accounts-health-check.sh"""

import json
import os
import glob
import re
import base64
import pprint
try:
    import deepdiff
except Exception as e:
    print(f"Could not import deepdiff: {e}")
    deepdiff = None

uniesc_re = re.compile(rb'[\\]u([0-9a-f][0-9a-f][0-9a-f][0-9a-f])')
str_quote_re = re.compile(rb'"event":"(.*[^\\])"')

def fixup_binary_json(a):
    aa, pos = [], 0
    for m in uniesc_re.finditer(a):
        aa.append(a[pos:m.start()])
        aa.append(chr(int(m.group(1), 16)).encode('UTF-8'))
        pos = m.end()
    aa.append(a[pos:])
    aaa = b''.join(aa)
    b, pos = [], 0
    for m in str_quote_re.finditer(aaa):
       in_between = aaa[pos:m.start()]
       if max(set(in_between)) > 126:
           print("Error trying to patch things up")
           continue
       b.append(in_between)
       b.append(b'"event":"' + base64.b64encode(m.group(1)) + b'"')
       pos = m.end()
    b.append(aaa[pos:])
    return b''.join(b)

def read_all_data():
    data = {}
    for filename in glob.glob('*.json'):
        basename = os.path.basename(filename.replace('.json', ''))
        if basename == 'pds-sequencer-repo_seq':
            with open(filename, 'rb') as f:
                adjusted_bstr = fixup_binary_json(f.read())
            try:
                d = json.loads(adjusted_bstr)
                for dd in d:
                    if isinstance(dd, dict) and 'event' in dd:
                        dd['event'] = base64.b64decode(dd['event'])
            except Exception as e:
                print(f"Error persisted despite binary repatch. Check file {filename}: {e}")
                continue
        else:
            with open(filename, 'rb') as f:
                try:
                    d = json.load(f)
                except Exception as e:
                    print(f"Error parsing {filename}: {e}")
        data[basename] = d
    return data

data_files = {}

all_dids = []

dids_with_mismatches = {}

current_did_info = {}
current_did_commit = {}
did_to_handles = {}
did_to_profiles = {}
handle_to_did = {}

bgs_user_dids = {}
bgs_actor_info_dids = {}

# PLC processing

def process_plc_data():
    all_dids.extend([r['did'] for r in data_files['plc-dids']])
    current_did_info.update({did: {} for did in all_dids})
    for did_op in data_files['plc-operations']:
        did = did_op['did']
        op_record = did_op['operation']
        op_type = op_record.pop('type')
        if op_type == 'plc_operation':
            existing_record = current_did_info[did]
            if existing_record:
                if deepdiff:
                    e2 = existing_record.copy()
                    e2.pop('prev'); e2.pop('sig')
                    o2 = op_record.copy()
                    o2.pop('prev'); o2.pop('sig')
                    record_diff = deepdiff.DeepDiff(e2, o2)
                    if list(record_diff.get('values_changed')) == ["root['alsoKnownAs'][0]"]:
                        print(f"Handle change for {did}: {existing_record.get('alsoKnownAs')[0]} -> {op_record.get('alsoKnownAs')[0]}")
                    else:
                        print(f"Differences received for {did} (excluding sig and prev):")
                        pprint.pprint(record_diff['values_changed'])
            else:
                handles = op_record.get('alsoKnownAs', None)
                if handles and len(handles) == 1:
                    print(f"Initial load for {did} with handle {handles[0]}")
                else:
                    print(f"Initial load for {did} with handles {handles}")
            current_did_info[did].update(op_record)
            current_did_commit[did] = did_op['cid']
            did_to_handles[did] = op_record.get('alsoKnownAs', None)
        else:
            print(f"Unknown op_type {op_type}")

    for did, handles in did_to_handles.items():
        for handle in handles:
            base_handle = handle.replace('at://', '', 1)
            handle_to_did.setdefault(handle, {})['plc'] = did

# BSKY processing

def process_bsky_data():
    for actor in data_files['bsky-actor']:
        did, handle = actor.get('did'), actor.get('handle')
        plc_handle = did_to_handles.get(did)
        if plc_handle != [f'at://{handle}']:
            print(f"Mismatch for did {did}: plc handle is {plc_handle} but bsky actor has handle {handle}")
            print(f"PLC info after last operation:\n{pprint.pformat(current_did_info[did])}\nbsky-actor info:\n{pprint.pformat(actor)}")
            dids_with_mismatches.setdefault(did, []).append('plc-bsky-actor-handle')
        # do something with takedownRef, upstreamStatus, indexedAt?
        handle_to_did.setdefault(handle, {})['bsky'] = did
    
    # bsky-actor_state seems to just have some last-seen-notifications state
    
    
    # commitCid from actor_sync never matches the plc did cid - it's from the actor's event repository
    # for actor_sync in data_files['bsky-actor_sync']:
    #     did, commit_cid = actor_sync.get('did'), actor_sync.get('commitCid')
    #     plc_cid = current_did_commit.get(did, None)
    #     if plc_cid != commit_cid:
    #         print(f"Commit mismatch for did {did}: plc commit is {plc_cid} but bsky actor_sync has commit {commit_cid}")
    #         print(f"PLC info after last operation:\n{pprint.pformat(current_did_info[did])}\nbsky-actor_sync info:\n{pprint.pformat(actor_sync)}")
    #         dids_with_mismatches.setdefault(did, []).append('plc-bsky-actor_sync-commit')
    
    bsky_dids_cached = {}
    
    for did_cache in data_files['bsky-did_cache']:
        did, handle = did_cache.get('did'), did_cache.get('handle')
        plc_handle = did_to_handles.get(did)
        if plc_handle != [f'at://{handle}']:
            print(f"Mismatch for did {did}: plc handle is {plc_handle} but bsky did_cache has handle {handle}")
            print(f"PLC info after last operation:\n{pprint.pformat(current_did_info[did])}\nbsky-did_cache info:\n{pprint.pformat(did_cache)}")
            dids_with_mismatches.setdefault(did, []).append('plc-bsky-did_cache-handle')
        bsky_dids_cached[did] = did_cache
    
    for did in current_did_info:
        if did not in bsky_dids_cached:
            print(f"plc did {did} was not cached in bsky did_cache")
            dids_with_mismatches.setdefault(did, []).append('missing-bsky-did_cache')
    
    for profile in data_files['bsky-profile']:
        did, uri, display_name = profile.get('creator'), profile.get('uri'), profile.get('displayName')
        if did not in current_did_info:
            print(f"bsky profile for did {did} but not registered in plc")
            dids_with_mismatches.setdefault(did, []).append('bsky-profile-without-plc-did')
        if uri != f'at://{did}/app.bsky.actor.profile/self':
            print(f"bsky profile uri {uri} doesn't match did {did}")
            dids_with_mismatches.setdefault(did, []).append('bsky-profile-uri-mismatch')
        if not display_name:
            print(f"did {did} doesn't have a display name")
            dids_with_mismatches.setdefault(did, []).append('bsky-profile-display-name-missing')
        did_to_profiles.setdefault(did, []).append((uri, display_name))
    
    for did in current_did_info:
        if did not in did_to_profiles:
            print(f"plc did {did} does not have a profile in bsky")
            dids_with_mismatches.setdefault(did, []).append('missing-bsky-profile')

# PDS processing

def process_pds_data():
    pds_account_dids = {pds_account.get('did'): pds_account for pds_account in data_files['pds-account-account']}
    
    for did in current_did_info:
        if did not in pds_account_dids:
            print(f"plc did {did} does not have an account on pds")
            dids_with_mismatches.setdefault(did, []).append('missing-pds-account')
    
    for did in pds_account_dids:
        if did not in current_did_info:
            print(f"pds has account under did {did} but not seen on plc")
            dids_with_mismatches.setdefault(did, []).append('spurious-pds-account-did')
    
    pds_actor_dids = {pds_actor.get('did'): pds_actor for pds_actor in data_files['pds-account-actor']}
    
    for did in current_did_info:
        if did not in pds_actor_dids:
            print(f"plc did {did} does not have an actor on pds")
            dids_with_mismatches.setdefault(did, []).append('missing-pds-actor')
    
    for did in pds_actor_dids:
        if did not in current_did_info:
            print(f"pds has actor under did {did} but not seen on plc")
            dids_with_mismatches.setdefault(did, []).append('spurious-pds-actor-did')
    
    pds_did_cache_docs = {cache_doc['did']: json.loads(cache_doc['doc']) for cache_doc in data_files['pds-did_cache-did_doc']}
    
    for did in current_did_info:
        if did not in pds_did_cache_docs:
            print(f"plc did {did} does not have a cached did doc on pds")
            dids_with_mismatches.setdefault(did, []).append('missing-pds-cache-doc')
    
    for did in pds_did_cache_docs:
        if did not in current_did_info:
            print(f"pds has cached did doc under did {did} but not seen on plc")
            dids_with_mismatches.setdefault(did, []).append('spurious-pds-did-cache-doc')
        elif 'missing-pds-actor' in dids_with_mismatches.get(did, []):
            print(f"did {did} was missing an actor, but this is what's in its cache:\n{pprint.pformat(pds_did_cache_docs[did])}")

# ignore pds-sequencer-repo_seq - this is about repositories, not accounts

# BGS (relay) processing

# ignore bgs-repo_event_records - contains non-account info

def process_bgs_data():
    bgs_user_dids.update({bgs_user.get('did'): bgs_user for bgs_user in data_files['bgs-users']})
    
    for did in current_did_info:
        if did not in bgs_user_dids:
            print(f"plc did {did} does not have an user on bgs")
            dids_with_mismatches.setdefault(did, []).append('missing-bgs-user')
    
    for did, bgs_user in bgs_user_dids.items():
        handle = bgs_user.get('handle')
        if did not in current_did_info:
            print(f"bgs has user under did {did} (handle {handle}) but not seen on plc")
            dids_with_mismatches.setdefault(did, []).append('spurious-bgs-user-did')
        handle_to_did.setdefault(handle, {})['bgs-users'] = did
    
    bgs_actor_info_dids.update({bgs_actor_info.get('did'): bgs_actor_info for bgs_actor_info in data_files['bgs-actor_infos']})
    
    for did in current_did_info:
        if did not in bgs_actor_info_dids:
            print(f"plc did {did} does not have an actor_info on bgs")
            dids_with_mismatches.setdefault(did, []).append('missing-bgs-actor_info')
    
    for did, bgs_actor_info in bgs_actor_info_dids.items():
        handle, display_name, valid_handle = bgs_actor_info.get('handle'), bgs_actor_info.get('display_name'), bgs_actor_info.get('valid_handle')
        if did not in current_did_info:
            print(f"bgs has actor_info under did {did} (handle {handle}) but not seen on plc")
            dids_with_mismatches.setdefault(did, []).append('spurious-bgs-actor_info-did')
        if not valid_handle:
            print(f"bgs reports invalid handle for did {did}, handle {handle}")
            dids_with_mismatches.setdefault(did, []).append('bgs-actor_info-invalid-handle')
        plc_handle = did_to_handles.get(did, [])
        if plc_handle != [f'at://{handle}']:
            print(f"bgs handle for did {did} is {handle}, but plc has {plc_handle}")
            dids_with_mismatches.setdefault(did, []).append('bgs-plc-handle-mismatch')
        bsky_display_name = did_to_profiles.get(did, [(None, '')])[0][1]
        if bsky_display_name != display_name:
            print(f"bgs display name for did {did} is {display_name}, but bsky has {bsky_display_name}")
            dids_with_mismatches.setdefault(did, []).append('bgs-bsky-display-name-mismatch')
        handle_to_did.setdefault(handle, {})['bgs-actor_infos'] = did

# Patch scripts

def update_bsky_handle_from_plc(did):
    plc_handle = did_to_handles.get(did)[0].replace('at://', '')
    return ["UPDATE actor SET handle=:handle where did=:did", {'handle': plc_handle, 'did': did}]

def update_bgs_display_name_from_bsky(did):
    bsky_display_name = did_to_profiles.get(did, [(None, '')])[0][1]
    return ["UPDATE actor_infos SET display_name=:display_name where did=:did", {'display_name': bsky_display_name, 'did': did}]

def update_bgs_handle_from_plc(did):
    plc_handle = did_to_handles.get(did)[0].replace('at://', '')
    return ["UPDATE actor_infos SET handle=:handle where did=:did", {'handle': plc_handle, 'did': did}]

known_handlers = {
    'plc-bsky-actor-handle': ('bsky', update_bsky_handle_from_plc),
    'bgs-plc-handle-mismatch': ('bgs', update_bgs_handle_from_plc),
    'bgs-bsky-display-name-mismatch': ('bgs', update_bgs_display_name_from_bsky),
    'bsky-profile-display-name-missing': None,  # this isn't necessarily an error
}

def create_patch_scripts():
    db_scripts = {}
    for did, mismatches in dids_with_mismatches.items():
        can_handle = [mismatch in known_handlers for mismatch in mismatches]
        if False not in can_handle:
            for mismatch in mismatches:
                handler = known_handlers.get(mismatch)
                if handler is None:
                    continue
                target_db, handler_fn = handler
                script = handler_fn(did)
                db_scripts.setdefault(target_db, []).append(script)
    return db_scripts

if __name__ == '__main__':
    data_files.update(read_all_data())
    process_plc_data()
    process_bsky_data()
    process_pds_data()
    process_bgs_data()
    patch_scripts = create_patch_scripts()
    pprint.pprint(patch_scripts)


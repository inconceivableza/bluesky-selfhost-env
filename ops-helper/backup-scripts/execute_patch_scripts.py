#!/usr/bin/env python

"""This executes a set of SQL patch scripts in a json file against the specified databases

It is intended for fixing up failures to the account health checks
Specifically:
  * account-health-checks.sh exports a set of JSON data
  * ../utils/correlate_account_dbs.py analyzes those files and determines mismatches, and produces patch scripts for certain scenarios
  * this script then executes those patch scripts
"""

import json
import psycopg
import logging

def execute_scripts(db, scripts, dry_run=False):
    with psycopg.Connection.connect(f'dbname={db}') as conn:
        if db == 'bsky':
            conn.execute(f'SET search_path={db}')
        results = []
        for script, data in scripts:
            try:
                logging.info("Executing %s with %r", script, data)
                if not args.dry_run:
                    cur = conn.execute(script, data)
                results.append(True)
            except Exception as e:
                logging.error("Error executing SQL: %s", e)
                results.append(e)
                cur.rollback()
        return results

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('-n', '--dry-run', action='store_true', default=False, help="Don't execute the scripts, just show them")
    parser.add_argument('patch_scripts', type=open, help="JSON file with patch scripts")
    args = parser.parse_args()
    logging.getLogger().setLevel(logging.INFO)
    patch_scripts = json.load(args.patch_scripts)
    for db, scripts in patch_scripts.items():
        logging.info("Executing %d scripts on %s", len(scripts), db)
        results = execute_scripts(db, scripts, dry_run=args.dry_run)
        if set(results) != {True}:
            logging.warning("Not all scripts succeeded: check and adjust and re-run?")



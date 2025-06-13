#!/bin/bash
. config/secrets-passwords.env
curl  -L https://bgs.foodios.vabl.dev/admin/subs/perDayLimit -H "Authorization: Bearer ${BGS_ADMIN_KEY}"
curl  -L -X POST https://bgs.foodios.vabl.dev/admin/subs/setPerDayLimit?limit=500 -H "Authorization: Bearer ${BGS_ADMIN_KEY}"

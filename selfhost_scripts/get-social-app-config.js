#!/usr/bin/env node
var app_config_script = require('../repos/social-app/app.config.js')
var app_config = app_config_script()
console.log(JSON.stringify(app_config, false, 2))

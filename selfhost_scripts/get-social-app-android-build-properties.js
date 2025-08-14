#!/usr/bin/env node
var app_config_script = require('../repos/social-app/app.config.js')
var app_config = app_config_script()
var plugins_config = (app_config.expo || {}).plugins || []
var build_configs = plugins_config.filter(item => (Array.isArray(item) && (item.length > 0) && (item[0] == 'expo-build-properties')))
if (build_configs.length == 1 && build_configs[0].length == 2) {
  var build_config = build_configs[0][1]
  console.log(JSON.stringify(build_config.android, false, 2))
} else if (build_configs.length == 0) {
  console.error("Could not find expo-build-properties plugin in app.config.js under expo.plugins")
  process.exit(1)
} else {
  console.error("Found multiple or irregular expo-build-properties plugins in app.config.js under expo.plugins")
  process.exit(1)
}

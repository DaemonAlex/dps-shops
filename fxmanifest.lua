fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dps-shops'
description 'DPS shops: clerks who greet and react, then owned shops'
author 'DPS'
version '0.1.0'

shared_scripts { '@ox_lib/init.lua', 'config.lua', 'shared/shops.lua' }
client_scripts { '@qbx_core/modules/playerdata.lua', 'client/clerk.lua', 'client/threat.lua' }
server_scripts { 'server/main.lua' }

dependencies { 'ox_lib', 'qbx_core', 'wasabi_mdt' }

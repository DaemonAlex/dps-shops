-- tests/run.lua
package.path = './?.lua;./shared/?.lua;./tests/?.lua;' .. package.path
local passed, failed = 0, 0
function check(name, ok, detail)
    if ok then passed = passed + 1 else failed = failed + 1; print(('  FAIL %s%s'):format(name, detail and (' -> ' .. tostring(detail)) or '')) end
end
function eq(name, got, want) check(name, got == want, ('got %s want %s'):format(tostring(got), tostring(want))) end
vector3 = function(x, y, z) return { x = x, y = y, z = z } end
dofile('config.lua')
dofile('shared/shops.lua')
for _, f in ipairs({ 'tests/test_persona.lua', 'tests/test_reaction.lua', 'tests/test_claims.lua' }) do
    local fh = io.open(f, 'r')
    if fh then fh:close(); print('== ' .. f); local ok, err = pcall(dofile, f); if not ok then failed = failed + 1; print('  ERROR ' .. tostring(err)) end end
end
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)

SOURCE='src/TormentedShoulderCamera/Scripts'
for _,name in ipairs({'main','camera','config','input','collision'}) do
    assert(loadfile(SOURCE..'/'..name..'.lua'))
end
print('PASS: syntax')
dofile('tests/test_collision.lua')
dofile('tests/test_input.lua')

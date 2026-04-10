find_program(LUA_EXECUTABLE NAMES lua lua5.4 REQUIRED)

set(RMCS_NAVIGATION_LUA_TESTS
    clock
    fsm
    runable
    scheduler
)

foreach(test_name IN LISTS RMCS_NAVIGATION_LUA_TESTS)
    set(LUA ${LUA_EXECUTABLE})
    add_test(
        NAME rmcs-navigation.lua.${test_name}
        COMMAND ${LUA} ${CMAKE_CURRENT_SOURCE_DIR}/test/lua/${test_name}.lua
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    )
endforeach()

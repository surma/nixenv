cmake_minimum_required(VERSION 3.21)
project(fcitx5-unicodehex VERSION 1.0.0 LANGUAGES CXX)

find_package(Fcitx5Core REQUIRED)

add_executable(test-unicodehex test_unicodehex.cpp)

add_fcitx5_addon(unicodehex fcitx5-unicodehex.cpp)
target_link_libraries(unicodehex PRIVATE Fcitx5::Core)

set_target_properties(unicodehex test-unicodehex PROPERTIES
    CXX_STANDARD 20
    CXX_STANDARD_REQUIRED ON)

install(TARGETS unicodehex DESTINATION "${FCITX_INSTALL_ADDONDIR}")
install(FILES unicodehex.conf.in DESTINATION "${FCITX_INSTALL_PKGDATADIR}/addon"
        RENAME unicodehex.conf)

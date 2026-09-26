cmake_minimum_required(VERSION 3.16)

project(AvroTextConverter VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Qt 6 preferred, Qt 5 fallback.
find_package(QT NAMES Qt6 Qt5 REQUIRED COMPONENTS Widgets Concurrent)
find_package(Qt${QT_VERSION_MAJOR} REQUIRED COMPONENTS Widgets Concurrent)

set(CONVERTER_CORE
    src/core/ansi_registry.cpp
    src/core/avroenco_reader.cpp
    src/core/sweep_table.cpp
    src/core/unicode_to_bijoy.cpp
    src/core/bijoy_to_unicode.cpp
)

add_executable(AvroTextConverter
    src/main.cpp
    src/ui/mainwindow.cpp
    src/ui/settingsdialog.cpp
    src/ui/fontpicker.cpp
    src/ui/memoedit.cpp
    src/ui/downwardcombo.cpp
    ${CONVERTER_CORE}
)

target_include_directories(AvroTextConverter PRIVATE
    src
    src/core
)

target_link_libraries(AvroTextConverter PRIVATE
    Qt${QT_VERSION_MAJOR}::Widgets
    Qt${QT_VERSION_MAJOR}::Concurrent
)

# Maximum optimization for Release builds ONLY - Debug stays debuggable
# (no /GL, no LTO, no aggressive inlining).  Generator expressions gate the
# flags per-configuration so multi-config generators (Visual Studio) and
# single-config generators (Ninja/Makefiles with CMAKE_BUILD_TYPE=Release)
# both get the fast Release binary.
if(MSVC)
    target_compile_options(AvroTextConverter PRIVATE
        $<$<CONFIG:Release>:/Ox /GL>)
    set_target_properties(AvroTextConverter PROPERTIES
        INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE
        LINK_FLAGS_RELEASE "/LTCG")
elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    # Plain -flto (NOT the INTERPROCEDURAL_OPTIMIZATION property, which emits
    # -flto=auto -fno-fat-lto-objects): that combination is broken on MinGW
    # GCC 13.1.0 - lto-wrapper's jobserver handshake fails at link time with
    # "cannot find ...ltrans0.ltrans.o".  Plain -flto performs the same
    # whole-program LTO without the jobserver path.
    target_compile_options(AvroTextConverter PRIVATE
        $<$<CONFIG:Release>:-O3 -flto>)
    target_link_options(AvroTextConverter PRIVATE
        $<$<CONFIG:Release>:-flto>)
endif()

# Ship the bundled Bengali fonts next to the executable (see
# MainWindow::loadBundledFonts).  The ANSI mappings are deliberately *not*
# bundled: they are read from the installed Avro Keyboard
# (C:\ProgramData\Avro Keyboard\AnsiMapping), where they ship as encrypted
# .AvroEnco containers, so the converter never carries a stale copy.
set(AVRO_SHARED_ASSETS "${CMAKE_CURRENT_SOURCE_DIR}/../assets" CACHE PATH
    "Directory holding the shared fonts/ assets to bundle")
set(AVRO_SHARE_DIR "$<TARGET_FILE_DIR:AvroTextConverter>/assets")
# Only re-copy when the shared assets are actually present: copy_directory
# hard-fails the build when the source is missing, and the assets live outside
# this checkout (next to the Avro Keyboard install), so a machine without them
# must still produce a working binary.  Point -DAVRO_SHARED_ASSETS=<dir> at
# the real directory to bundle fonts.
if(EXISTS "${AVRO_SHARED_ASSETS}/fonts")
    add_custom_command(TARGET AvroTextConverter POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "${AVRO_SHARE_DIR}"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
                "${AVRO_SHARED_ASSETS}/fonts"
                "${AVRO_SHARE_DIR}/fonts"
    )
else()
    message(STATUS "Shared assets not found at ${AVRO_SHARED_ASSETS} - "
                   "not bundling fonts next to the executable")
endif()

# ---------------------------------------------------------------------------
# Application icon.  Explorer, the taskbar and Alt-Tab take the icon of a
# .exe from the *first* Win32 RT_GROUP_ICON resource compiled into it, not
# from any runtime QIcon - that is why a binary without a resource shows the
# generic "application" glyph.  We embed the .ico here as well.  Override the
# choice with -DAVRO_APP_ICON=<path>.ico; otherwise the first candidate that
# exists on disk wins.
# ---------------------------------------------------------------------------
set(AVRO_APP_ICON "" CACHE FILEPATH
    "Optional .ico compiled into the executable as its Windows shell icon")
if(NOT AVRO_APP_ICON)
    foreach(candidate
            "${CMAKE_CURRENT_SOURCE_DIR}/assets/icon/Converter.ico"
            "${AVRO_SHARED_ASSETS}/icon/Converter.ico"
            "${CMAKE_CURRENT_SOURCE_DIR}/dist/assets/icon/Converter.ico")
        if(EXISTS "${candidate}")
            set(AVRO_APP_ICON "${candidate}")
            break()
        endif()
    endforeach()
endif()

# Windows: GUI subsystem so no console window opens, plus dwmapi for the
# native window shadow (DwmExtendFrameIntoClientArea) in mainwindow.cpp.
if(WIN32)
    set_target_properties(AvroTextConverter PROPERTIES
        WIN32_EXECUTABLE TRUE
    )
    # bcrypt: SHA-512 / HMAC / AES for the encrypted mapping containers.
    # z:     the deflate stream inside those containers (see avroenco_reader).
    target_link_libraries(AvroTextConverter PRIVATE dwmapi comctl32 bcrypt z)

    # Compile the .ico into the executable (app_icon.rc.in -> build/app_icon.rc).
    enable_language(RC)
    if(AVRO_APP_ICON)
        file(TO_CMAKE_PATH "${AVRO_APP_ICON}" AVRO_APP_ICON_RC_PATH)
        configure_file("${CMAKE_CURRENT_SOURCE_DIR}/src/app_icon.rc.in"
                       "${CMAKE_CURRENT_BINARY_DIR}/app_icon.rc" @ONLY)
        target_sources(AvroTextConverter PRIVATE
                       "${CMAKE_CURRENT_BINARY_DIR}/app_icon.rc")
        # The runtime icons (title bar, taskbar, Alt-Tab, tray) are read from
        # assets/icon/Converter.ico next to the executable, so a build without
        # a same-shaped dist/ folder still has to ship that file.
        add_custom_command(TARGET AvroTextConverter POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory
                    "${AVRO_SHARE_DIR}/icon"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${AVRO_APP_ICON}"
                    "${AVRO_SHARE_DIR}/icon/Converter.ico")
        message(STATUS "Application icon: ${AVRO_APP_ICON}")
    else()
        message(WARNING
            "No application icon found - the .exe would show the default "
            "Windows glyph. Pass -DAVRO_APP_ICON=<file>.ico to embed one.")
    endif()
endif()

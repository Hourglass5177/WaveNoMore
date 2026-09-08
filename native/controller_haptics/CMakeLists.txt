cmake_minimum_required(VERSION 3.25)
project(wnm_controller_haptics LANGUAGES C CXX)

if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
	message(FATAL_ERROR "Controller haptics v1 targets Windows x86_64 only.")
endif()
get_filename_component(WNM_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(WNM_DEPS "${WNM_ROOT}/.godot/haptics_deps" CACHE PATH "Pinned, project-local dependencies")
set(GODOTCPP_BUILD_PROFILE "${CMAKE_CURRENT_SOURCE_DIR}/build_profile.json" CACHE FILEPATH "" FORCE)
set(GODOTCPP_ENABLE_TESTING OFF CACHE BOOL "" FORCE)
set(GODOTCPP_TARGET template_release CACHE STRING "" FORCE)
add_subdirectory("${WNM_DEPS}/godot-cpp" godot-cpp EXCLUDE_FROM_ALL)

# Private static SDL: never load/replace the engine's SDL DLL or share its event queue.
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_TESTS OFF CACHE BOOL "" FORCE)
set(SDL_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SDL_INSTALL OFF CACHE BOOL "" FORCE)
set(SDL_AUDIO OFF CACHE BOOL "" FORCE)
# SDL's Windows build gates DirectInput headers behind its DirectX/video option.
# Compile this support for haptic effects; our runtime never initializes SDL video.
set(SDL_VIDEO ON CACHE BOOL "" FORCE)
set(SDL_DIRECTX ON CACHE BOOL "" FORCE)
set(SDL_RENDER OFF CACHE BOOL "" FORCE)
set(SDL_GPU OFF CACHE BOOL "" FORCE)
set(SDL_CAMERA OFF CACHE BOOL "" FORCE)
set(SDL_JOYSTICK ON CACHE BOOL "" FORCE)
set(SDL_HAPTIC ON CACHE BOOL "" FORCE)
add_subdirectory("${WNM_DEPS}/SDL" SDL EXCLUDE_FROM_ALL)

add_library(wnm_controller_haptics SHARED src/controller_haptics_backend.cpp src/register_types.cpp)
target_compile_features(wnm_controller_haptics PRIVATE cxx_std_17)
target_compile_definitions(wnm_controller_haptics PRIVATE SDL_MAIN_HANDLED)
target_link_libraries(wnm_controller_haptics PRIVATE godot-cpp SDL3::SDL3-static)
if(MINGW)
	target_compile_options(wnm_controller_haptics PRIVATE -Wall -Wextra -Wno-unused-parameter)
	target_link_options(wnm_controller_haptics PRIVATE -static-libstdc++ -static-libgcc)
endif()
set_target_properties(wnm_controller_haptics PROPERTIES
	PREFIX ""
	CXX_VISIBILITY_PRESET hidden
	VISIBILITY_INLINES_HIDDEN YES
	RUNTIME_OUTPUT_DIRECTORY "${WNM_ROOT}/bin/controller_haptics/windows"
)
# Distributed together with the native binary, including license notices.
configure_file("${WNM_DEPS}/SDL/LICENSE.txt" "${WNM_ROOT}/bin/controller_haptics/licenses/SDL.txt" COPYONLY)
configure_file("${WNM_DEPS}/godot-cpp/LICENSE.md" "${WNM_ROOT}/bin/controller_haptics/licenses/godot-cpp.txt" COPYONLY)
if(MINGW AND CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
	get_filename_component(WNM_COMPILER_BIN "${CMAKE_CXX_COMPILER}" DIRECTORY)
	get_filename_component(WNM_TOOLCHAIN_ROOT "${WNM_COMPILER_BIN}/.." ABSOLUTE)
	configure_file("${WNM_TOOLCHAIN_ROOT}/LICENSE.TXT" "${WNM_ROOT}/bin/controller_haptics/licenses/LLVM.txt" COPYONLY)
	configure_file("${WNM_TOOLCHAIN_ROOT}/x86_64-w64-mingw32/share/mingw32/COPYING.MinGW-w64-runtime.txt"
		"${WNM_ROOT}/bin/controller_haptics/licenses/MinGW-w64-runtime.txt" COPYONLY)
endif()

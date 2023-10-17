include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(temp_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(temp_setup_options)
  option(temp_ENABLE_HARDENING "Enable hardening" ON)
  option(temp_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    temp_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    temp_ENABLE_HARDENING
    OFF)

  temp_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR temp_PACKAGING_MAINTAINER_MODE)
    option(temp_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(temp_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(temp_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(temp_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(temp_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(temp_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(temp_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(temp_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(temp_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(temp_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(temp_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(temp_ENABLE_PCH "Enable precompiled headers" OFF)
    option(temp_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(temp_ENABLE_IPO "Enable IPO/LTO" ON)
    option(temp_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(temp_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(temp_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(temp_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(temp_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(temp_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(temp_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(temp_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(temp_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(temp_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(temp_ENABLE_PCH "Enable precompiled headers" OFF)
    option(temp_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      temp_ENABLE_IPO
      temp_WARNINGS_AS_ERRORS
      temp_ENABLE_USER_LINKER
      temp_ENABLE_SANITIZER_ADDRESS
      temp_ENABLE_SANITIZER_LEAK
      temp_ENABLE_SANITIZER_UNDEFINED
      temp_ENABLE_SANITIZER_THREAD
      temp_ENABLE_SANITIZER_MEMORY
      temp_ENABLE_UNITY_BUILD
      temp_ENABLE_CLANG_TIDY
      temp_ENABLE_CPPCHECK
      temp_ENABLE_COVERAGE
      temp_ENABLE_PCH
      temp_ENABLE_CACHE)
  endif()

  temp_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (temp_ENABLE_SANITIZER_ADDRESS OR temp_ENABLE_SANITIZER_THREAD OR temp_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(temp_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(temp_global_options)
  if(temp_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    temp_enable_ipo()
  endif()

  temp_supports_sanitizers()

  if(temp_ENABLE_HARDENING AND temp_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR temp_ENABLE_SANITIZER_UNDEFINED
       OR temp_ENABLE_SANITIZER_ADDRESS
       OR temp_ENABLE_SANITIZER_THREAD
       OR temp_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${temp_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${temp_ENABLE_SANITIZER_UNDEFINED}")
    temp_enable_hardening(temp_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(temp_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(temp_warnings INTERFACE)
  add_library(temp_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  temp_set_project_warnings(
    temp_warnings
    ${temp_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(temp_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(temp_options)
  endif()

  include(cmake/Sanitizers.cmake)
  temp_enable_sanitizers(
    temp_options
    ${temp_ENABLE_SANITIZER_ADDRESS}
    ${temp_ENABLE_SANITIZER_LEAK}
    ${temp_ENABLE_SANITIZER_UNDEFINED}
    ${temp_ENABLE_SANITIZER_THREAD}
    ${temp_ENABLE_SANITIZER_MEMORY})

  set_target_properties(temp_options PROPERTIES UNITY_BUILD ${temp_ENABLE_UNITY_BUILD})

  if(temp_ENABLE_PCH)
    target_precompile_headers(
      temp_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(temp_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    temp_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(temp_ENABLE_CLANG_TIDY)
    temp_enable_clang_tidy(temp_options ${temp_WARNINGS_AS_ERRORS})
  endif()

  if(temp_ENABLE_CPPCHECK)
    temp_enable_cppcheck(${temp_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(temp_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    temp_enable_coverage(temp_options)
  endif()

  if(temp_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(temp_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(temp_ENABLE_HARDENING AND NOT temp_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR temp_ENABLE_SANITIZER_UNDEFINED
       OR temp_ENABLE_SANITIZER_ADDRESS
       OR temp_ENABLE_SANITIZER_THREAD
       OR temp_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    temp_enable_hardening(temp_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()

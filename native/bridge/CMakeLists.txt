cmake_minimum_required(VERSION 3.18)
project(wallet_engine_core LANGUAGES C CXX)

set(WALLET_ENGINE_WALLET_CORE_VERSION "4.8.4" CACHE STRING
    "Pinned Trust Wallet Core version")
set(WALLET_ENGINE_WALLET_CORE_COMMIT
    "d40d24a63d92619167903369308bf0e2f7eb3a59" CACHE STRING
    "Pinned Trust Wallet Core commit")
set(WALLET_CORE_ROOT "" CACHE PATH "Path to the verified wallet-core source")

if(NOT TARGET TrustWalletCore)
  if(NOT WALLET_CORE_ROOT)
    message(FATAL_ERROR "Set WALLET_CORE_ROOT to the verified source checkout")
  endif()
  add_subdirectory("${WALLET_CORE_ROOT}" wallet-core EXCLUDE_FROM_ALL)
endif()

add_library(wallet_engine_core SHARED
  src/wallet_engine_wallet_core.cpp
)

target_compile_features(wallet_engine_core PRIVATE cxx_std_17)
target_compile_options(wallet_engine_core PRIVATE
  -fvisibility=hidden
  -Wall
  -Wextra
  -Werror
)
target_compile_definitions(wallet_engine_core PRIVATE
  WALLET_ENGINE_WALLET_CORE_VERSION="${WALLET_ENGINE_WALLET_CORE_VERSION}"
  WALLET_ENGINE_WALLET_CORE_COMMIT="${WALLET_ENGINE_WALLET_CORE_COMMIT}"
)
target_include_directories(wallet_engine_core PUBLIC include)
target_link_libraries(wallet_engine_core PRIVATE TrustWalletCore)

set_target_properties(wallet_engine_core PROPERTIES
  OUTPUT_NAME "wallet_engine_core"
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN YES
)

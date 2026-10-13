get_filename_component(
  WALLET_ENGINE_ROOT
  "${CMAKE_CURRENT_LIST_DIR}/../../.."
  ABSOLUTE
)

function(wallet_engine_configure_android_bridge)
  if(NOT TARGET TrustWalletCore)
    message(FATAL_ERROR "Wallet Core target was not created")
  endif()

  # Wallet Core's Android build hides its native C surface. Compiling the
  # owned bridge into the same DSO preserves that boundary while allowing the
  # bridge to call upstream internals. Only WALLET_ENGINE_EXPORT functions
  # remain externally visible. The linker export map is authoritative because
  # Wallet Core also marks its JNI and legacy C symbols with default visibility.
  target_sources(
    TrustWalletCore
    PRIVATE
    "${WALLET_ENGINE_ROOT}/native/bridge/src/wallet_engine_wallet_core.cpp"
  )
  target_include_directories(
    TrustWalletCore
    PRIVATE
    "${WALLET_ENGINE_ROOT}/native/bridge/include"
  )
  target_link_options(
    TrustWalletCore
    PRIVATE
    "-Wl,--version-script=${WALLET_ENGINE_ROOT}/native/bridge/android/wallet_engine.exports.map"
  )
  target_compile_definitions(
    TrustWalletCore
    PRIVATE
    WALLET_ENGINE_WALLET_CORE_VERSION="4.8.4"
    WALLET_ENGINE_WALLET_CORE_COMMIT="d40d24a63d92619167903369308bf0e2f7eb3a59"
  )
  set_target_properties(
    TrustWalletCore
    PROPERTIES
    OUTPUT_NAME wallet_engine_core
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
  )
endfunction()

# CMAKE_PROJECT_INCLUDE runs immediately after Wallet Core's project() call,
# before its library target exists. Defer the bridge wiring until the root
# CMake directory has created the target.
cmake_language(DEFER CALL wallet_engine_configure_android_bridge)

#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${1:-/tmp/yuki-llama.cpp}"
OUTPUT_DIR="${2:-$(pwd)/Vendor/Llama}"
BUILD_DIR="${SOURCE_DIR}/build-yuki-ios-metal"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8)"

cmake -B "${BUILD_DIR}" -G Xcode \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphoneos \
  -DBUILD_SHARED_LIBS=OFF \
  -DLLAMA_BUILD_APP=OFF \
  -DLLAMA_BUILD_COMMON=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TOOLS=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_SERVER=OFF \
  -DLLAMA_OPENSSL=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_BLAS_DEFAULT=ON \
  -DGGML_NATIVE=OFF \
  -DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16 \
  -DGGML_OPENMP=OFF \
  -S "${SOURCE_DIR}"

cmake --build "${BUILD_DIR}" --config Release -j "${JOBS}" -- -quiet

FRAMEWORK="${BUILD_DIR}/framework/llama.framework"
mkdir -p "${FRAMEWORK}/Headers" "${FRAMEWORK}/Modules" "${BUILD_DIR}/temp"
cp "${SOURCE_DIR}/include/llama.h" "${FRAMEWORK}/Headers/"
for header in ggml.h ggml-opt.h ggml-alloc.h ggml-backend.h ggml-metal.h ggml-cpu.h ggml-blas.h gguf.h; do
  cp "${SOURCE_DIR}/ggml/include/${header}" "${FRAMEWORK}/Headers/"
done

cat > "${FRAMEWORK}/Modules/module.modulemap" <<'EOF'
framework module llama {
    umbrella "Headers"
    link "c++"
    link framework "Accelerate"
    link framework "Metal"
    link framework "Foundation"
    export *
}
EOF

cat > "${FRAMEWORK}/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>llama</string>
<key>CFBundleIdentifier</key><string>org.ggml.llama</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>llama</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>DTPlatformName</key><string>iphoneos</string>
</dict></plist>
EOF

LIBS=(
  "${BUILD_DIR}/src/Release-iphoneos/libllama.a"
  "${BUILD_DIR}/ggml/src/Release-iphoneos/libggml.a"
  "${BUILD_DIR}/ggml/src/Release-iphoneos/libggml-base.a"
  "${BUILD_DIR}/ggml/src/Release-iphoneos/libggml-cpu.a"
  "${BUILD_DIR}/ggml/src/ggml-metal/Release-iphoneos/libggml-metal.a"
  "${BUILD_DIR}/ggml/src/ggml-blas/Release-iphoneos/libggml-blas.a"
)
xcrun libtool -static -o "${BUILD_DIR}/temp/combined.a" "${LIBS[@]}"
xcrun -sdk iphoneos clang++ -dynamiclib \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -arch arm64 -mios-version-min=17.0 \
  -Wl,-force_load,"${BUILD_DIR}/temp/combined.a" \
  -framework Foundation -framework Metal -framework Accelerate \
  -install_name @rpath/llama.framework/llama \
  -o "${FRAMEWORK}/llama"
xcrun vtool -set-build-version ios 17.0 17.0 -replace -output "${FRAMEWORK}/llama" "${FRAMEWORK}/llama"
xcrun strip -S "${FRAMEWORK}/llama"

mkdir -p "${OUTPUT_DIR}"
ditto "${FRAMEWORK}" "${OUTPUT_DIR}/llama.framework"
echo "Built ${OUTPUT_DIR}/llama.framework"

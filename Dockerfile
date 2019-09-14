FROM ubuntu:18.04 AS builder

RUN apt-get update
RUN apt-get install -y build-essential cmake libncurses-dev ninja-build nodejs python

ENV SRC_ROOT /tmp/src
ENV REPOS_ROOT /tmp/repos
ENV BUILD_ROOT /tmp/build
ENV INSTALL_ROOT /opt
ENV DIST_ROOT /srv

COPY repos/llvm-project/llvm ${REPOS_ROOT}/llvm
COPY repos/llvm-project/clang ${REPOS_ROOT}/llvm/tools/clang
COPY repos/llvm-project/lld ${REPOS_ROOT}/llvm/tools/lld
COPY repos/llvm-project/compiler-rt ${REPOS_ROOT}/llvm/projects/compiler-rt
COPY repos/llvm-project/libcxx ${REPOS_ROOT}/llvm/projects/libcxx
COPY repos/llvm-project/libcxxabi ${REPOS_ROOT}/llvm/projects/libcxxabi
WORKDIR ${BUILD_ROOT}/llvm-Release/
RUN cmake -G "Ninja" -DCMAKE_INSTALL_PREFIX=${INSTALL_ROOT}/llvm-Release/ -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD="X86;WebAssembly" ${REPOS_ROOT}/llvm
RUN ninja
RUN ninja install install-cxx install-cxxabi install-compiler-rt
ENV PATH ${INSTALL_ROOT}/llvm-Release/bin:${PATH}
ENV LD_LIBRARY_PATH ${INSTALL_ROOT}/llvm-Release/lib

COPY repos/binaryen ${REPOS_ROOT}/binaryen
WORKDIR ${BUILD_ROOT}/binaryen-RelWithDebInfo/
RUN cmake -G "Ninja" -DCMAKE_INSTALL_PREFIX=${INSTALL_ROOT}/binaryen-RelWithDebInfo/ -DCMAKE_BUILD_TYPE=RelWithDebInfo ${REPOS_ROOT}/binaryen
RUN ninja
RUN ninja install
ENV PATH ${INSTALL_ROOT}/binaryen-RelWithDebInfo/bin:${PATH}

COPY repos/emscripten ${REPOS_ROOT}/emscripten
ENV PATH ${REPOS_ROOT}/emscripten:${PATH}

WORKDIR ${BUILD_ROOT}/optimizer-RelWithDebInfo/
RUN cmake -G "Ninja" -DCMAKE_BUILD_TYPE=RelWithDebInfo ${REPOS_ROOT}/emscripten/tools/optimizer
RUN ninja

RUN em++
RUN (echo && echo "BINARYEN_ROOT='${INSTALL_ROOT}/binaryen-RelWithDebInfo/'") >> ${HOME}/.emscripten

COPY src ${SRC_ROOT}

WORKDIR ${BUILD_ROOT}/dummy
RUN em++ ${SRC_ROOT}/say-hello.cpp -o say-hello.html

WORKDIR ${BUILD_ROOT}/tools
RUN CXX=${INSTALL_ROOT}/llvm-Release/bin/clang++ cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Debug ${SRC_ROOT}
RUN ninja cib-link cib-ar combine-data

RUN sed 's/-Wl,-allow-shlib-undefined//g' -i ${REPOS_ROOT}/llvm/CMakeLists.txt

WORKDIR ${BUILD_ROOT}/llvm-browser-Release/
RUN emcmake cmake -G "Ninja" \
-DCMAKE_CXX_FLAGS="" \
-DLIBCXXABI_LIBCXX_INCLUDES=${INSTALL_ROOT}/llvm-Release/include/c++/v1 \
-DLIBCXX_ENABLE_SHARED=OFF \
-DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
-DLIBCXXABI_ENABLE_SHARED=OFF \
-DLLVM_ENABLE_DUMP=OFF \
-DLLVM_ENABLE_ASSERTIONS=OFF \
-DLLVM_ENABLE_EXPENSIVE_CHECKS=OFF \
-DLLVM_ENABLE_BACKTRACES=OFF \
-DCMAKE_INSTALL_PREFIX=${INSTALL_ROOT}/llvm-browser-Release/ \
-DCMAKE_BUILD_TYPE=Release \
-DLLVM_TARGETS_TO_BUILD=WebAssembly \
-DLLVM_BUILD_TOOLS=OFF \
-DLLVM_ENABLE_THREADS=OFF \
-DLLVM_BUILD_LLVM_DYLIB=OFF \
-DLLVM_INCLUDE_TESTS=OFF \
-DLLVM_TABLEGEN=${INSTALL_ROOT}/llvm-Release/bin/llvm-tblgen \
-DCLANG_TABLEGEN=${BUILD_ROOT}/llvm-Release/bin/clang-tblgen \
-DHAVE_POSIX_SPAWN=0 \
${REPOS_ROOT}/llvm
RUN ninja LLVMAnalysis LLVMAsmParser LLVMAsmPrinter LLVMBinaryFormat LLVMBitReader LLVMBitWriter LLVMCodeGen LLVMCore LLVMCoroutines LLVMCoverage LLVMDebugInfoCodeView LLVMGlobalISel LLVMInstCombine LLVMInstrumentation LLVMipo LLVMIRReader LLVMLinker LLVMLTO LLVMMC LLVMMCDisassembler LLVMMCParser LLVMObjCARCOpts LLVMObject LLVMOption LLVMPasses LLVMProfileData LLVMScalarOpts LLVMSelectionDAG LLVMSupport LLVMTarget LLVMTransformUtils LLVMVectorize LLVMAggressiveInstCombine LLVMBitstreamReader LLVMDebugInfoDWARF LLVMDemangle LLVMRemarks
RUN ninja LLVMWebAssemblyCodeGen LLVMWebAssemblyDesc LLVMWebAssemblyInfo LLVMWebAssemblyAsmParser
RUN ninja clangAnalysis clangAST clangBasic clangCodeGen clangDriver clangEdit clangFormat clangFrontend clangLex clangParse clangRewrite clangSema clangSerialization clangToolingCore clangASTMatchers

ADD https://registry.npmjs.org/monaco-editor/-/monaco-editor-0.10.1.tgz /tmp/
WORKDIR /tmp/monaco-editor-0.10.1
RUN tar -xf ../monaco-editor-0.10.1.tgz
WORKDIR ${DIST_ROOT}/monaco-editor
RUN cp -au /tmp/monaco-editor-0.10.1/package/LICENSE .
RUN cp -au /tmp/monaco-editor-0.10.1/package/README.md .
RUN cp -au /tmp/monaco-editor-0.10.1/package/ThirdPartyNotices.txt .
RUN cp -auv /tmp/monaco-editor-0.10.1/package/min .

ADD http://code.jquery.com/jquery-1.11.1.min.js ${DIST_ROOT}/

WORKDIR ${DIST_ROOT}/golden-layout
COPY repos/golden-layout/LICENSE .
COPY repos/golden-layout/src/css/goldenlayout-base.css .
COPY repos/golden-layout/src/css/goldenlayout-light-theme.css .
COPY repos/golden-layout/dist/goldenlayout.min.js .

WORKDIR ${DIST_ROOT}/zip.js
COPY repos/zip.js/WebContent/inflate.js .
COPY repos/zip.js/WebContent/zip.js .

RUN apt-get install -y closure-compiler

WORKDIR ${REPOS_ROOT}/binaryen
RUN sed 's/ASYNC_COMPILATION=0/ASYNC_COMPILATION=1/g' -i build-js.sh
RUN bash ./build-js.sh
RUN cp -au out/binaryen.js ${DIST_ROOT}/binaryen.js
RUN cp -au LICENSE ${DIST_ROOT}/binaryen-LICENSE

WORKDIR ${SRC_ROOT}
RUN cp -au clang.html process.js process-manager.js process-clang-format.js wasm-tools.js process-clang.js process-runtime.js ${DIST_ROOT}

WORKDIR ${BUILD_ROOT}/rtl/
RUN cmake -G "Ninja" -DLLVM_INSTALL=${BUILD_ROOT}/llvm-Release/ -DCMAKE_C_COMPILER=${BUILD_ROOT}/llvm-Release/bin/clang -DCMAKE_CXX_COMPILER=${BUILD_ROOT}/llvm-Release/bin/clang++ ${SRC_ROOT}/rtl
RUN ninja



WORKDIR ${BUILD_ROOT}/clang-browser-Release/
RUN emcmake cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Release -DLLVM_BUILD=${BUILD_ROOT}/llvm-browser-Release/ -DEMSCRIPTEN=on ${SRC_ROOT}

RUN mkdir -p ${BUILD_ROOT}/clang-browser-Release/usr/lib/libcxxabi ${BUILD_ROOT}/clang-browser-Release/usr/lib/libc/musl/arch/emscripten
RUN cp -auv ${REPOS_ROOT}/emscripten/system/include ${BUILD_ROOT}/clang-browser-Release/usr
RUN cp -auv ${REPOS_ROOT}/emscripten/system/lib/libcxxabi/include ${BUILD_ROOT}/clang-browser-Release/usr/lib/libcxxabi
RUN cp -auv ${REPOS_ROOT}/emscripten/system/lib/libc/musl/arch/emscripten ${BUILD_ROOT}/clang-browser-Release/usr/lib/libc/musl/arch

WORKDIR ${BUILD_ROOT}/clang-browser-Release/
RUN ninja clang

WORKDIR ${BUILD_ROOT}/clang-browser-Release/
RUN wasm-opt -Os clang.wasm -o clang-opt.wasm
RUN cp -au ${BUILD_ROOT}/clang-browser-Release/clang.js ${BUILD_ROOT}/clang-browser-Release/clang.data ${DIST_ROOT}
RUN cp -au ${BUILD_ROOT}/clang-browser-Release/clang-opt.wasm ${DIST_ROOT}/clang.wasm

WORKDIR ${BUILD_ROOT}/runtime-browser-Debug/
RUN emcmake cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Debug -DLLVM_BUILD=${BUILD_ROOT}/llvm-browser-Release/ -DEMSCRIPTEN=on ${SRC_ROOT}
RUN EMCC_FORCE_STDLIBS=1 ninja runtime

RUN cp ${BUILD_ROOT}/rtl/rtl ${BUILD_ROOT}/runtime-browser-Debug/runtime.wasm
RUN cp -au ${BUILD_ROOT}/runtime-browser-Debug/runtime.js ${BUILD_ROOT}/runtime-browser-Debug/runtime.wasm ${DIST_ROOT}

FROM nginx
COPY --from=builder /srv /usr/share/nginx/html
RUN chmod -R a+r /usr/share/nginx/html

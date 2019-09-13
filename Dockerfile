FROM ubuntu:18.04 AS builder

RUN apt-get update
RUN apt-get install -y build-essential cmake ninja-build python libncurses-dev unzip

ENV SRC_ROOT /tmp/src
ENV REPOS_ROOT /tmp/repos
ENV BUILD_ROOT /tmp/build
ENV INSTALL_ROOT /opt
ENV DIST_ROOT /srv

COPY src ${SRC_ROOT}
COPY repos ${REPOS_ROOT}

RUN ln -sv ${REPOS_ROOT}/llvm-tools/* ${REPOS_ROOT}/llvm/tools/
RUN ln -sv ${REPOS_ROOT}/llvm-projects/* ${REPOS_ROOT}/llvm/projects/

WORKDIR ${BUILD_ROOT}/llvm-Release/
RUN cmake -G "Ninja" -DCMAKE_INSTALL_PREFIX=${INSTALL_ROOT}/llvm-Release/ -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD=X86 -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=WebAssembly ${REPOS_ROOT}/llvm
RUN ninja
RUN ninja install install-cxx install-cxxabi install-compiler-rt

WORKDIR ${BUILD_ROOT}/binaryen-RelWithDebInfo/
RUN cmake -G "Ninja" -DCMAKE_INSTALL_PREFIX=${INSTALL_ROOT}/binaryen-RelWithDebInfo/ -DCMAKE_BUILD_TYPE=RelWithDebInfo ${REPOS_ROOT}/binaryen
RUN ninja
RUN ninja install

WORKDIR ${BUILD_ROOT}/optimizer-RelWithDebInfo/
RUN cmake -G "Ninja" -DCMAKE_BUILD_TYPE=RelWithDebInfo ${REPOS_ROOT}/emscripten/tools/optimizer
RUN ninja

RUN apt-get install -y nodejs

ENV PATH ${INSTALL_ROOT}/llvm-Release/bin:${PATH}
ENV PATH ${INSTALL_ROOT}/binaryen-RelWithDebInfo/bin:${PATH}
ENV PATH ${REPOS_ROOT}/emscripten:${PATH}

RUN em++
RUN (echo && echo "BINARYEN_ROOT='${INSTALL_ROOT}/binaryen-RelWithDebInfo/'") >> ${HOME}/.emscripten

WORKDIR ${BUILD_ROOT}/dummy
RUN em++ ${SRC_ROOT}/say-hello.cpp -o say-hello.html

WORKDIR ${BUILD_ROOT}/tools
RUN CXX=${INSTALL_ROOT}/llvm-Release/bin/clang++ cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Debug ${SRC_ROOT}
RUN ninja cib-link cib-ar combine-data

WORKDIR ${BUILD_ROOT}/llvm-browser-Release/
RUN emcmake cmake -G "Ninja" -DCMAKE_CXX_FLAGS="" -DLIBCXXABI_LIBCXX_INCLUDES=${INSTALL_ROOT}/llvm-Release/include/c++/v1 -DLLVM_ENABLE_DUMP=OFF -DLLVM_ENABLE_ASSERTIONS=OFF -DLLVM_ENABLE_EXPENSIVE_CHECKS=OFF -DLLVM_ENABLE_BACKTRACES=OFF -DCMAKE_INSTALL_PREFIX=${INSTALL_ROOT}/llvm-browser-Release/ -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD= -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=WebAssembly -DLLVM_BUILD_TOOLS=OFF -DLLVM_ENABLE_THREADS=OFF -DLLVM_BUILD_LLVM_DYLIB=OFF -DLLVM_INCLUDE_TESTS=OFF -DLLVM_TABLEGEN=${INSTALL_ROOT}/llvm-Release/bin/llvm-tblgen -DCLANG_TABLEGEN=${BUILD_ROOT}/llvm-Release/bin/clang-tblgen ${REPOS_ROOT}/llvm
RUN ninja clangAnalysis clangAST clangBasic clangCodeGen clangDriver clangEdit clangFormat clangFrontend clangLex clangParse clangRewrite clangSema clangSerialization clangToolingCore LLVMAnalysis LLVMAsmParser LLVMAsmPrinter LLVMBinaryFormat LLVMBitReader LLVMBitWriter LLVMCodeGen LLVMCore LLVMCoroutines LLVMCoverage LLVMDebugInfoCodeView LLVMGlobalISel LLVMInstCombine LLVMInstrumentation LLVMipo LLVMIRReader LLVMLinker LLVMLTO LLVMMC LLVMMCDisassembler LLVMMCParser LLVMObjCARCOpts LLVMObject LLVMOption LLVMPasses LLVMProfileData LLVMScalarOpts LLVMSelectionDAG LLVMSupport LLVMTarget LLVMTransformUtils LLVMVectorize LLVMWebAssemblyAsmPrinter LLVMWebAssemblyCodeGen LLVMWebAssemblyDesc LLVMWebAssemblyInfo

RUN apt-get install -y wget

RUN wget https://registry.npmjs.org/monaco-editor/-/monaco-editor-0.10.1.tgz -O /tmp/monaco-editor-0.10.1.tgz
WORKDIR /tmp/monaco-editor-0.10.1
RUN tar -xf ../monaco-editor-0.10.1.tgz
WORKDIR ${DIST_ROOT}/monaco-editor
RUN cp -au /tmp/monaco-editor-0.10.1/package/LICENSE .
RUN cp -au /tmp/monaco-editor-0.10.1/package/README.md .
RUN cp -au /tmp/monaco-editor-0.10.1/package/ThirdPartyNotices.txt .
RUN cp -auv /tmp/monaco-editor-0.10.1/package/min .

RUN wget http://code.jquery.com/jquery-1.11.1.min.js -O ${DIST_ROOT}/jquery-1.11.1.min.js

WORKDIR ${DIST_ROOT}/golden-layout
RUN cp -au ${REPOS_ROOT}/golden-layout/LICENSE .
RUN cp -au ${REPOS_ROOT}/golden-layout/src/css/goldenlayout-base.css .
RUN cp -au ${REPOS_ROOT}/golden-layout/src/css/goldenlayout-light-theme.css .
RUN cp -au ${REPOS_ROOT}/golden-layout/dist/goldenlayout.min.js .

WORKDIR ${DIST_ROOT}/zip.js
RUN cp -au ${REPOS_ROOT}/zip.js/WebContent/inflate.js .
RUN cp -au ${REPOS_ROOT}/zip.js/WebContent/zip.js .

RUN cp -au ${REPOS_ROOT}/binaryen/bin/binaryen.js ${DIST_ROOT}/binaryen.js
RUN cp -au ${REPOS_ROOT}/binaryen/bin/binaryen.wasm ${DIST_ROOT}/binaryen.wasm
RUN cp -au ${REPOS_ROOT}/binaryen/LICENSE ${DIST_ROOT}/binaryen-LICENSE

WORKDIR ${SRC_ROOT}
RUN cp -au clang.html process.js process-manager.js process-clang-format.js wasm-tools.js process-clang.js process-runtime.js ${DIST_ROOT}

ENV LD_LIBRARY_PATH ${INSTALL_ROOT}/llvm-Release/lib

WORKDIR ${BUILD_ROOT}/rtl/
RUN cmake -G "Ninja" -DLLVM_INSTALL=${BUILD_ROOT}/llvm-Release/ -DCMAKE_C_COMPILER=${BUILD_ROOT}/llvm-Release/bin/clang -DCMAKE_CXX_COMPILER=${BUILD_ROOT}/llvm-Release/bin/clang++ ${SRC_ROOT}/rtl
RUN ninja

WORKDIR ${BUILD_ROOT}/clang-format-browser-Release/
RUN emcmake cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Release -DLLVM_BUILD=${BUILD_ROOT}/llvm-browser-Release/ -DEMSCRIPTEN=on ${SRC_ROOT}
RUN ninja clang-format

WORKDIR ${DIST_ROOT}
RUN cp -au ${BUILD_ROOT}/clang-format-browser-Release/clang-format.js ${BUILD_ROOT}/clang-format-browser-Release/clang-format.wasm .

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

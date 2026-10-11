#!/usr/bin/env python3
"""Build pinned iOS curl/OpenSSL with peer verification via native Apple SecTrust.

Build tools may come from the host. Target libraries come only from these source
archives and the selected Xcode iOS SDK, never Homebrew macOS libraries.
"""
import argparse, json, shutil, subprocess, time
from pathlib import Path
from common import ROOT, config, env, output, sha, write_json

SOURCES = {
    'curl': {'version':'8.22.0','archive':'curl-8.22.0.tar.xz',
             'sha256':'f7ef3ae8a22e521f289803fe93543eb64c329b58aa73a9e224dfd915a2a5f4f7'},
    'openssl': {'version':'3.5.9','archive':'openssl-3.5.9.tar.gz',
                'sha256':'603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a'},
}

def command(argv, *, cwd=None, logfile, extra_env=None):
    environ=env()
    if extra_env:environ.update(extra_env)
    logfile=Path(logfile);logfile.parent.mkdir(parents=True,exist_ok=True)
    print('TLS_BUILD '+str(logfile.relative_to(ROOT)),flush=True)
    with logfile.open('w') as log:
        log.write('ARGV '+json.dumps(list(map(str,argv)))+'\n');log.flush()
        result=subprocess.run(list(map(str,argv)),cwd=cwd,env=environ,stdout=log,stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f'Command failed {result.returncode}: {argv}\n{logfile.read_text()[-12000:]}')

def query(argv):
    return subprocess.check_output(argv,env=env(),text=True).strip()

def build(platform, jobs=6):
    assert platform in ('ios','iossim')
    cfg=config();minimum=cfg.get('minimum_ios','18.0')
    simulator=platform=='iossim';sdkname='iphonesimulator' if simulator else 'iphoneos'
    target='arm64-apple-ios'+minimum+('-simulator' if simulator else '')
    sdk=query(['xcrun','--sdk',sdkname,'--show-sdk-path'])
    clang=query(['xcrun','--sdk',sdkname,'--find','clang'])
    logs=ROOT/'evidence'/'tls'/platform
    base=output(platform)/'tls';base.mkdir(parents=True,exist_ok=True)
    vendor=ROOT/'vendor'
    for component,details in SOURCES.items():
        archive=vendor/details['archive']
        if sha(archive)!=details['sha256']:raise RuntimeError(f'Pinned source hash mismatch: {archive}')
    for source,dest in [('curl-8.22.0/COPYING','curl-COPYING.txt'),('openssl-3.5.9/LICENSE.txt','openssl-LICENSE.txt')]:
        shutil.copy2(vendor/source,ROOT/dest)

    ssl_source=vendor/'openssl-3.5.9'
    ssl_build=base/'openssl-build';ssl_build.mkdir(exist_ok=True)
    ssl_prefix=base/'openssl';ssl_prefix.mkdir(exist_ok=True)
    flags=f'-target {target} -isysroot {sdk} -fPIC -O2'
    ssl_env={'CFLAGS':flags,'LDFLAGS':f'-target {target} -isysroot {sdk}', 'CC':clang}
    stamp=ssl_prefix/'source-build.json'
    expected={'sources':SOURCES['openssl'],'target':target,'sdk':sdk,'flags':flags}
    if not stamp.exists() or json.loads(stamp.read_text())!=expected:
        command(['perl',ssl_source/'Configure','iossimulator-arm64-xcrun' if simulator else 'ios64-xcrun',
                 'no-shared','no-tests','no-module','no-asm','no-apps','no-docs',
                 '--prefix='+str(ssl_prefix),'--openssldir='+str(ssl_prefix/'ssl')],
                cwd=ssl_build,logfile=logs/'openssl-configure.log',extra_env=ssl_env)
        command(['make',f'-j{jobs}','build_libs'],cwd=ssl_build,logfile=logs/'openssl-build.log',extra_env=ssl_env)
        command(['make','install_dev'],cwd=ssl_build,logfile=logs/'openssl-install.log',extra_env=ssl_env)
        write_json(stamp,expected)

    curl_source=base/'curl-source'
    if not curl_source.exists():shutil.copytree(vendor/'curl-8.22.0',curl_source)
    # Upstream's SecTrust CMake path adds macOS CoreServices, which is unavailable
    # in iOS. Its implementation uses Security/CoreFoundation only. Change only
    # this platform check in the build copy, preserving vendor source and TLS code.
    cmake_file=curl_source/'CMakeLists.txt'
    original=(vendor/'curl-8.22.0'/'CMakeLists.txt').read_text()
    old='''  find_library(CORESERVICES_FRAMEWORK NAMES "CoreServices")
  mark_as_advanced(CORESERVICES_FRAMEWORK)
  if(NOT CORESERVICES_FRAMEWORK)
    message(FATAL_ERROR "CoreServices framework not found")
  endif()
  list(APPEND CURL_LIBS "-framework CoreServices")'''
    new='''  if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    find_library(CORESERVICES_FRAMEWORK NAMES "CoreServices")
    mark_as_advanced(CORESERVICES_FRAMEWORK)
    if(NOT CORESERVICES_FRAMEWORK)
      message(FATAL_ERROR "CoreServices framework not found")
    endif()
    list(APPEND CURL_LIBS "-framework CoreServices")
  endif()'''
    if original.count(old)!=1:raise RuntimeError('Pinned curl CoreServices CMake block changed')
    cmake_file.write_text(original.replace(old,new))
    curl_build=base/'curl-build'
    ssl_lib=ssl_prefix/'lib'
    if not (ssl_lib/'libssl.a').exists():ssl_lib=ssl_prefix/'lib64'
    arguments=['cmake','-S',curl_source,'-B',curl_build,'-G','Unix Makefiles',
        '-DCMAKE_SYSTEM_NAME=iOS','-DCMAKE_OSX_SYSROOT='+sdk,
        '-DCMAKE_OSX_ARCHITECTURES=arm64','-DCMAKE_OSX_DEPLOYMENT_TARGET='+minimum,
        '-DCMAKE_C_COMPILER='+clang,'-DCMAKE_C_FLAGS='+flags,
        '-DCMAKE_BUILD_TYPE=Release','-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY',
        '-DCMAKE_INSTALL_NAME_DIR=@rpath','-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY',
        '-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY','-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY',
        '-DBUILD_SHARED_LIBS=ON','-DBUILD_STATIC_LIBS=OFF','-DBUILD_CURL_EXE=OFF',
        '-DBUILD_TESTING=OFF','-DBUILD_LIBCURL_DOCS=OFF','-DBUILD_MISC_DOCS=OFF',
        '-DENABLE_CURL_MANUAL=OFF','-DCURL_DISABLE_INSTALL=ON','-DCURL_USE_PKGCONFIG=OFF',
        '-DLIBCURL_OUTPUT_NAME=libCPCurl','-DCURL_LIBCURL_SOVERSION=OFF',
        '-DCURL_USE_OPENSSL=ON','-DOPENSSL_USE_STATIC_LIBS=TRUE','-DOPENSSL_ROOT_DIR='+str(ssl_prefix),
        '-DOPENSSL_INCLUDE_DIR='+str(ssl_prefix/'include'),'-DOPENSSL_SSL_LIBRARY='+str(ssl_lib/'libssl.a'),
        '-DOPENSSL_CRYPTO_LIBRARY='+str(ssl_lib/'libcrypto.a'),'-DUSE_APPLE_SECTRUST=ON',
        '-DCURL_CA_BUNDLE=none','-DCURL_CA_PATH=none','-DCURL_CA_FALLBACK=OFF',
        '-DCURL_USE_LIBPSL=OFF','-DCURL_USE_LIBSSH=OFF','-DCURL_USE_LIBSSH2=OFF',
        '-DCURL_BROTLI=OFF','-DCURL_ZSTD=OFF','-DCURL_ZLIB=ON','-DUSE_LIBIDN2=OFF',
        '-DUSE_APPLE_IDN=OFF','-DCURL_USE_GSSAPI=OFF',
        '-DZLIB_INCLUDE_DIR='+str(Path(sdk)/'usr/include'),'-DZLIB_LIBRARY='+str(Path(sdk)/'usr/lib/libz.tbd')]
    for protocol in ('DICT','FILE','FTP','GOPHER','IMAP','LDAP','LDAPS','MQTT','POP3','RTSP','SMTP','TELNET','TFTP'):
        arguments.append('-DCURL_DISABLE_'+protocol+'=ON')
    command(arguments,logfile=logs/'curl-configure.log')
    command(['cmake','--build',curl_build,'--parallel',str(jobs)],logfile=logs/'curl-build.log')
    built=curl_build/'lib/libCPCurl.dylib'
    if not built.exists():raise RuntimeError('libCPCurl output missing')
    destination=output(platform)/'compat/libCPCurl.dylib';destination.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(built,destination)
    command(['install_name_tool','-id','@rpath/libCPCurl.dylib',destination],logfile=logs/'install-name.log')
    command(['codesign','--force','--sign','-',destination],logfile=logs/'codesign.log')
    dependencies=query(['xcrun','otool','-L',str(destination)])
    if '/opt/homebrew/' in dependencies or '/usr/local/' in dependencies or 'libssl' in dependencies or 'libcrypto' in dependencies:
        raise RuntimeError('Unexpected host/OpenSSL shared dependency: '+dependencies)
    (logs/'dependencies.txt').write_text(dependencies+'\n')
    cache=(curl_build/'CMakeCache.txt').read_text()
    if 'USE_APPLE_SECTRUST:BOOL=ON' not in cache or 'CURL_USE_OPENSSL:BOOL=ON' not in cache:
        raise RuntimeError('TLS trust configuration did not activate')
    report={'platform':platform,'target':target,'sdk':sdk,'sources':SOURCES,
            'output':str(destination.relative_to(ROOT)),'sha256':sha(destination),'dependencies':dependencies,
            'verificationPolicy':{'peerVerificationDefault':True,'hostnameVerificationDefault':True,
                                  'appleSystemTrust':True,'sourceTLSChecksModified':False},
            'curlCMakeOnlyPatch':'CoreServices is linked for macOS Darwin only; iOS uses Security/CoreFoundation',
            'runtimeTLSVerified':False}
    write_json(logs/'build-report.json',report)
    print('TLS_BUILD_COMPLETE '+platform+' '+str(destination),flush=True)
    return report

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--platform',choices=['ios','iossim','all'],default='all');parser.add_argument('--jobs',type=int,default=6)
    args=parser.parse_args()
    for platform in (['iossim','ios'] if args.platform=='all' else [args.platform]):build(platform,args.jobs)

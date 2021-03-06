import "dart:async";
import "dart:io";
import "package:build_tools/build_shell.dart";
import "package:build_tools/build_tools.dart";
import "package:ccompilers/ccompilers.dart";
import "package:file_utils/file_utils.dart";
import "package:patsubst/patsubst.dart";

Future main(List<String> args) async {
  const String PROJECT_NAME = "sample_extension";
  const String LIBNAME_LINUX = "lib$PROJECT_NAME.so";
  const String LIBNAME_MACOS = "lib$PROJECT_NAME.dylib";
  const String LIBNAME_WINDOWS = "$PROJECT_NAME.dll";

  // Determine operating system
  var os = Platform.operatingSystem;

  // Setup Dart SDK bitness for native extension
  var bits = DartSDK.getVmBits();

  // Compiler options
  var compilerDefine = {};
  var compilerInclude = ['$DART_SDK/include'];

  // Linker options
  var linkerLibpath = [];

  // OS dependent parameters
  var libname = "";
  var objExtension = "";
  switch (os) {
    case "linux":
      libname = LIBNAME_LINUX;
      objExtension = ".o";
      break;
    case "macos":
      libname = LIBNAME_MACOS;
      objExtension = ".o";
      break;
    case "windows":
      libname = LIBNAME_WINDOWS;
      objExtension = ".obj";
      compilerDefine["DART_SHARED_LIB"] = null;
      linkerLibpath.add('$DART_SDK/bin');
      break;
    default:
      print("Unsupported operating system: $os");
      exit(-1);
  }

  // Set working directory
  FileUtils.chdir("lib/src");

  // C++ files
  var cppFiles = FileUtils.glob("*.cc");
  if (os != "windows") {
    cppFiles = FileUtils.exclude(cppFiles, "${PROJECT_NAME}_dllmain_win.cc");
  }

  // Object files
  var objFiles = patsubst("%.cc", "%${objExtension}").replaceAll(cppFiles);

  // Makefile
  // Target: default
  target("default", ["build"], null, description: "Build and clean.");

  // Target: build
  target("build", ["clean_all", "compile_link", "clean"], (Target t, Map args) {
    print("The ${t.name} successful.");
  }, description: "Build '$PROJECT_NAME'.");

  // Target: compile_link
  target("compile_link", [libname], (Target t, Map args) {
  }, description: "Compile and link '$PROJECT_NAME'.");

  // Target: clean
  target("clean", [], (Target t, Map args) {
    FileUtils.rm(["*.exp", "*.lib", "*.o", "*.obj"], force: true);
  }, description: "Deletes all intermediate files.", reusable: true);

  // Target: clean_all
  target("clean_all", ["clean"], (Target t, Map args) {
    FileUtils.rm([libname], force: true);
  }, description: "Deletes all intermediate and output files.", reusable: true);

  // Compile on Posix
  rule("%.o", ["%.cc"], (Target t, Map args) {
    var compiler = new GnuCppCompiler(bits: bits);
    var args = ['-fPIC', '-Wall'];
    return compiler.compile(t.sources, arguments: args, define: compilerDefine, include: compilerInclude, output: t.name).exitCode;
  });

  // Compile on Windows
  rule("%.obj", ["%.cc"], (Target t, Map args) {
    var compiler = new MsCppCompiler(bits: bits);
    return compiler.compile(t.sources, define: compilerDefine, include: compilerInclude, output: t.name).exitCode;
  });

  // Link on Linux
  file(LIBNAME_LINUX, objFiles, (Target t, Map args) {
    var linker = new GnuLinker(bits: bits);
    var args = ['-shared'];
    return linker.link(t.sources, arguments: args, libpaths: linkerLibpath, output: t.name).exitCode;
  });

  // Link on Macos
  file(LIBNAME_MACOS, objFiles, (Target t, Map args) {
    var linker = new GnuLinker(bits: bits);
    var args = ['-dynamiclib', '-undefined', 'dynamic_lookup'];
    return linker.link(t.sources, arguments: args, libpaths: linkerLibpath, output: t.name).exitCode;
  });

  // Link on Windows
  file(LIBNAME_WINDOWS, objFiles, (Target t, Map args) {
    var linker = new MsLinker(bits: bits);
    var args = ['/DLL', 'dart.lib'];
    return linker.link(t.sources, arguments: args, libpaths: linkerLibpath, output: t.name).exitCode;
  });

  exit(await new BuildShell().run(args));
}

# Copyright 2017 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Helpers for configuring the TypeScript compiler.
"""
_DEBUG = False

def create_tsconfig(ctx, files, srcs, tsconfig_path,
                    devmode_manifest=None, tsickle_externs=None, type_blacklisted_declarations=[],
                    out_dir=None, disable_strict_deps=False, allowed_deps=set(),
                    extra_root_dirs=[]):
  """Creates an object representing the TypeScript configuration
      to run the compiler under Bazel.

      Args:
        ctx: the skylark execution context
        files: Labels of all TypeScript compiler inputs
        srcs: Immediate sources being compiled, as opposed to transitive deps.
        tsconfig_path: where the resulting config will be written; paths will be relative
            to this folder
        devmode_manifest: path to the manifest file to write for --target=es5
        tsickle_externs: path to write tsickle-generated externs.js.
        type_blacklisted_declarations: types declared in these files will never be
            mentioned in generated .d.ts.
        out_dir: directory for generated output. Default is ctx.bin_dir
        disable_strict_deps: whether to disable the strict deps check
        allowed_deps: the set of files that code in srcs may depend on (strict deps)
        extra_root_dirs: Extra root dirs to be passed to tsc_wrapped.
  """
  outdir_path = out_dir if out_dir != None else ctx.configuration.bin_dir.path
  workspace_path = "/".join([".."] * len(tsconfig_path.split("/")))

  perf_trace_path = "/".join([ctx.configuration.bin_dir.path, ctx.label.package,
                              ctx.label.name + ".trace"])
  # TODO(alexeagle): a better way to ask for the perf trace than editing here?
  perf_trace_path = ""  # Comment out => receive perf trace!

  # Options for running the TypeScript compiler under Bazel.
  # See javascript/typescript/compiler/tsc_wrapped.ts:BazelOptions.
  # Unlike compiler_options, the paths here are relative to the rootDir,
  # not the location of the tsconfig.json file.
  bazel_options = {
      "target": ctx.label,
      "tsickle": tsickle_externs != None,
      "tsickleGenerateExterns": getattr(ctx.attr, "generate_externs", True),
      "tsickleExternsPath": tsickle_externs.path if tsickle_externs else "",
      "untyped": not getattr(ctx.attr, "tsickle_typed", False),
      "typeBlackListPaths": [f.path for f in type_blacklisted_declarations],

      # Substitute commonjs with googmodule.
      "googmodule": ctx.attr.runtime == "browser",
      "es5Mode": devmode_manifest != None,
      "manifest": devmode_manifest.path if devmode_manifest else "",
      # Explicitly tell the compiler which sources we're interested in (emitting
      # and type checking).
      "compilationTargetSrc": [s.path for s in srcs],
      "disableStrictDeps": disable_strict_deps,
      "allowedStrictDeps": [f.path for f in allowed_deps],
      "perfTracePath": perf_trace_path,
      "enableConformance": getattr(ctx.attr, "enable_conformance", False),
  }

  # Keep these options in sync with those in playground/playground.ts.
  compiler_options = {
      # De-sugar to this language level
      "target": "es5" if devmode_manifest or ctx.attr.runtime == "nodejs" else "es6",
      "downlevelIteration": devmode_manifest != None or ctx.attr.runtime == "nodejs",

      # Do not type-check the lib.*.d.ts.
      # We think this shouldn't be necessary but haven't figured out why yet
      # and builds are faster with the setting on.
      # http://b/30709121
      "skipDefaultLibCheck": True,

      # Always produce commonjs modules (might get translated to goog.module).
      "module": "commonjs",
      "moduleResolution": "node",

      "outDir": "/".join([workspace_path, outdir_path]),

      # We must set a rootDir to avoid TypeScript emit paths varying
      # due computeCommonSourceDirectory behavior.
      # TypeScript requires the rootDir be a parent of all sources in
      # files[], so it must be set to the workspace_path.
      "rootDir": workspace_path,

      # Path handling for resolving modules, see specification at
      # https://github.com/Microsoft/TypeScript/issues/5039
      # Paths where we attempt to load relative references.
      # Longest match wins
      #
      # tsc_wrapped also uses this property to strip leading paths
      # to produce a flattened output tree, see
      # https://github.com/Microsoft/TypeScript/issues/8245
      "rootDirs": ["/".join([workspace_path, e]) for e in extra_root_dirs] + [
          workspace_path,
          "/".join([workspace_path, ctx.configuration.genfiles_dir.path]),
          "/".join([workspace_path, ctx.configuration.bin_dir.path]),
      ],

      "traceResolution": _DEBUG,
      "diagnostics": _DEBUG,

      # Inline const enums.
      "preserveConstEnums": False,

      # permit `@Decorator` syntax and allow runtime reflection on their types.
      "experimentalDecorators": True,
      "emitDecoratorMetadata": True,

      # Interpret JSX as React calls (until someone asks for something different)
      "jsx": "react",
      "jsxFactory": "React.createElement",

      "noEmitOnError": False,
      "declaration": True,
      "stripInternal": True,

      # Embed source maps and sources in .js outputs
      "inlineSourceMap": True,
      "inlineSources": True,

      # Don't emit decorate/metadata helper code, we provide our own helpers.js.
      "noEmitHelpers": ctx.attr.runtime == "browser",
  }

  return {
    "compilerOptions": compiler_options,
    "bazelOptions": bazel_options,
    "files": [workspace_path + "/" + f.path for f in files],
    "compileOnSave": False
  }
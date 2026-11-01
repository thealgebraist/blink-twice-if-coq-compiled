#!/usr/bin/env python3
"""
configure.py - Configuration generator & system prerequisite checker for Blink Formalization.
Checks for Rocq/Coq, Ninja, Clang (C99/C++23), Python 3, Node, and Chromium,
then analyzes Coq dependencies via coqdep and generates an optimized build.ninja.
"""

import sys
import os
import shutil
import subprocess
import glob
from pathlib import Path

# Terminal colors
BOLD = "\033[1m"
GREEN = "\033[32m"
RED = "\033[31m"
YELLOW = "\033[33m"
CYAN = "\033[36m"
RESET = "\033[0m"

def print_header(title):
    print(f"\n{BOLD}{CYAN}=== {title} ==={RESET}")

def run_cmd(cmd):
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        return res.returncode == 0, res.stdout.strip(), res.stderr.strip()
    except Exception as e:
        return False, "", str(e)

class DependencyChecker:
    def __init__(self):
        self.all_required_met = True
        self.results = {}

    def check_tool(self, name, binary_names, version_flag="--version", min_version=None, required=True):
        found_bin = None
        for b in binary_names:
            p = shutil.which(b)
            if p:
                found_bin = p
                break
            # Check standard Mac paths
            for prefix in ["/opt/homebrew/bin", "/usr/local/bin", "/Library/Developer/CommandLineTools/usr/bin"]:
                cand = os.path.join(prefix, b)
                if os.path.exists(cand) and os.access(cand, os.X_OK):
                    found_bin = cand
                    break
            if found_bin:
                break

        if found_bin:
            ok, stdout, stderr = run_cmd([found_bin, version_flag])
            v_line = stdout.splitlines()[0] if stdout else (stderr.splitlines()[0] if stderr else "detected")
            print(f"  {GREEN}[OK]{RESET} {BOLD}{name:<16}{RESET} : {v_line} ({found_bin})")
            self.results[name] = {"found": True, "path": found_bin, "version": v_line}
            return True, found_bin
        else:
            tag = f"{RED}[MISSING]{RESET}" if required else f"{YELLOW}[OPTIONAL]{RESET}"
            print(f"  {tag} {BOLD}{name:<16}{RESET} : NOT FOUND in PATH")
            if required:
                self.all_required_met = False
            self.results[name] = {"found": False, "path": None, "version": None}
            return False, None

    def check_python_module(self, mod_name, import_name=None, required=False):
        imp = import_name or mod_name
        venv_py = Path(".venv/bin/python3")
        py_bin = str(venv_py) if venv_py.exists() else sys.executable
        ok, stdout, stderr = run_cmd([py_bin, "-c", f"import {imp}; print(getattr({imp}, '__version__', 'available'))"])
        if ok:
            print(f"  {GREEN}[OK]{RESET} Python:{BOLD}{mod_name:<11}{RESET} : version {stdout}")
            return True
        else:
            tag = f"{RED}[MISSING]{RESET}" if required else f"{YELLOW}[OPTIONAL]{RESET}"
            print(f"  {tag} Python:{BOLD}{mod_name:<11}{RESET} : not installed in {py_bin}")
            if required:
                self.all_required_met = False
            return False

    def check_browser(self):
        candidates = [
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            shutil.which("chromium"),
            shutil.which("google-chrome")
        ]
        found = None
        for c in candidates:
            if c and os.path.exists(c) and os.access(c, os.X_OK):
                found = c
                break
        if found:
            ok, out, _ = run_cmd([found, "--version"])
            v_line = out.strip() if ok and out else "Chromium App detected"
            print(f"  {GREEN}[OK]{RESET} {BOLD}{'Chromium/Chrome':<16}{RESET} : {v_line} ({found})")
            self.results["browser"] = {"found": True, "path": found, "version": v_line}
            return True, found
        else:
            print(f"  {YELLOW}[OPTIONAL]{RESET} {BOLD}{'Chromium/Chrome':<16}{RESET} : Headless browser binary not found")
            self.results["browser"] = {"found": False, "path": None, "version": None}
            return False, None


def compute_coq_dependencies(coqdep_bin, v_files):
    """Run coqdep to discover exact inter-theory .vo dependencies."""
    deps = {f"{os.path.splitext(vf)[0]}.vo": [] for vf in v_files}
    if not v_files:
        return deps
    
    cmd = [coqdep_bin, "-Q", ".", ""] + v_files
    ok, stdout, stderr = run_cmd(cmd)
    if not ok:
        print(f"{YELLOW}Warning: coqdep failed, defaulting to flat dependencies: {stderr}{RESET}")
        return deps

    for line in stdout.splitlines():
        if ":" in line:
            targets_part, deps_part = line.split(":", 1)
            targets = targets_part.split()
            vo_targets = [t for t in targets if t.endswith(".vo")]
            if not vo_targets:
                continue
            vo_file = os.path.basename(vo_targets[0])
            dep_vos = []
            for d in deps_part.split():
                d_base = os.path.basename(d)
                if d_base.endswith(".vo") and d_base != vo_file:
                    dep_vos.append(d_base)
            if vo_file in deps:
                deps[vo_file] = sorted(list(set(dep_vos)))
    return deps


def generate_ninja(checker):
    print_header("Generating build.ninja")

    coqc_bin = checker.results.get("Rocq/Coq", {}).get("path", "coqc")
    coqdep_bin = shutil.which("coqdep") or os.path.join(os.path.dirname(coqc_bin), "coqdep")
    clang_bin = checker.results.get("Clang (C99)", {}).get("path", "clang")
    clangxx_bin = checker.results.get("Clang++ (C++23)", {}).get("path", "clang++")
    
    venv_py = Path(".venv/bin/python3")
    py_bin = str(venv_py) if venv_py.exists() else sys.executable

    # Scan for all Coq theory files
    v_files = sorted(glob.glob("*.v"))
    print(f"Discovered {len(v_files)} formal Coq theories (*.v)")
    
    print(f"Calculating dependency graph using {coqdep_bin}...")
    deps_map = compute_coq_dependencies(coqdep_bin, v_files)
    print(f"Computed dependency DAG across {len(deps_map)} compilation units.")

    ninja_lines = []
    ninja_lines.append("# Generated automatically by configure.py. DO NOT EDIT DIRECTLY.")
    ninja_lines.append("ninja_required_version = 1.10\n")

    ninja_lines.append("# Core Tool Variables")
    ninja_lines.append(f"COQC = {coqc_bin}")
    ninja_lines.append(f"CC = {clang_bin}")
    ninja_lines.append(f"CXX = {clangxx_bin}")
    ninja_lines.append(f"PYTHON = {py_bin}")
    ninja_lines.append("COQFLAGS = -Q . \"\"")
    ninja_lines.append("CFLAGS = -O3 -Wall -Wextra -pedantic")
    ninja_lines.append("CXXFLAGS = -O3 -std=c++23 -Wall -Wextra\n")

    ninja_lines.append("# Rule: Rocq/Coq formal proof verification")
    ninja_lines.append("rule coqc")
    ninja_lines.append("  command = $COQC $COQFLAGS $in")
    ninja_lines.append("  description = COQC $in\n")

    ninja_lines.append("# Rule: Zero-admit integrity verifier across all formal theories")
    ninja_lines.append("rule verify_admits")
    ninja_lines.append("  command = if grep -rn -E \"\\b(admit|Admitted)\\b\" *.v; then echo \"\\033[31m[ERROR] Found admits in Coq theories!\\033[0m\"; exit 1; else echo \"\\033[32m[PASS] All formal theories verified with strictly 0 admits.\\033[0m\"; touch $out; fi")
    ninja_lines.append("  description = VERIFY_ZERO_ADMITS\n")

    ninja_lines.append("# Rule: C99 Object Compilation")
    ninja_lines.append("rule c_compile")
    ninja_lines.append("  command = $CC $CFLAGS -c $in -o $out")
    ninja_lines.append("  description = CC $in -> $out\n")

    ninja_lines.append("# Rule: C99 Executable Linking")
    ninja_lines.append("rule c_link")
    ninja_lines.append("  command = $CC $CFLAGS $in -o $out")
    ninja_lines.append("  description = LINK $out\n")

    ninja_lines.append("# Rule: C++23 Compilation")
    ninja_lines.append("rule cpp_compile")
    ninja_lines.append("  command = $CXX $CXXFLAGS -c $in -o $out")
    ninja_lines.append("  description = CXX $in -> $out\n")

    ninja_lines.append("# Rule: LLVM IR Generation")
    ninja_lines.append("rule llvm_ir")
    ninja_lines.append("  command = $CC -S -emit-llvm -O3 $in -o $out")
    ninja_lines.append("  description = LLVM_IR $out\n")

    ninja_lines.append("# Rule: Native Assembly Generation")
    ninja_lines.append("rule asm_gen")
    ninja_lines.append("  command = $CC -S -O3 $in -o $out")
    ninja_lines.append("  description = ASM $out\n")

    ninja_lines.append("# Rule: Shared Dynamic Library")
    ninja_lines.append("rule shared_lib")
    ninja_lines.append("  command = $CC -shared -fPIC -O3 $in -o $out")
    ninja_lines.append("  description = DYLIB $out\n")

    ninja_lines.append("# Rule: Formal Runner Execution")
    ninja_lines.append("rule run_runner")
    ninja_lines.append("  command = ./$in > $out && cat $out")
    ninja_lines.append("  description = RUN_FORMAL_ENGINE\n")

    ninja_lines.append("# Rule: Reconfigure build system if configure.py changes")
    ninja_lines.append("rule reconfigure")
    ninja_lines.append("  command = $PYTHON configure.py")
    ninja_lines.append("  generator = 1\n")

    ninja_lines.append("build build.ninja: reconfigure configure.py\n")

    # Build targets for Coq theories with explicit DAG dependencies
    vo_targets = []
    for v_file in v_files:
        base = os.path.splitext(v_file)[0]
        vo = f"{base}.vo"
        vo_targets.append(vo)
        dep_vos = deps_map.get(vo, [])
        if dep_vos:
            # Use implicit dependency `|` so Ninja orders compilation correctly
            ninja_lines.append(f"build {vo}: coqc {v_file} | {' '.join(dep_vos)}")
        else:
            ninja_lines.append(f"build {vo}: coqc {v_file}")

    ninja_lines.append(f"\nbuild coq_all: phony {' '.join(vo_targets)}")
    ninja_lines.append("build .admits_verified: verify_admits coq_all\n")

    # Drop-in engine targets
    ninja_lines.append("build blink_formal_engine.o: c_compile blink_formal_engine.c | blink_formal_engine.h blink_dual_mode_z.h")
    ninja_lines.append("build blink_formal_runner.o: c_compile blink_formal_runner.c | blink_formal_engine.h blink_dual_mode_z.h")
    ninja_lines.append("build blink_formal_runner: c_link blink_formal_engine.o blink_formal_runner.o")
    ninja_lines.append("build blink_html_css_formal.o: c_compile blink_html_css_formal.c | blink_html_css_formal.h blink_dual_mode_z.h")
    ninja_lines.append("build blink_layout_paint_formal.o: c_compile blink_layout_paint_formal.c | blink_layout_paint_formal.h blink_html_css_formal.h blink_skia_font_engine.h blink_dual_mode_z.h")
    ninja_lines.append("build test_blink_html_css_formal.o: c_compile test_blink_html_css_formal.c | blink_html_css_formal.h blink_dual_mode_z.h")
    ninja_lines.append("build test_blink_html_css_formal: c_link blink_html_css_formal.o test_blink_html_css_formal.o")
    ninja_lines.append("build blink_formal_engine_cpp.o: cpp_compile blink_formal_engine.cpp")
    ninja_lines.append("build libblink_formal.dylib: shared_lib blink_formal_engine.c")
    ninja_lines.append("build blink_formal_engine.ll: llvm_ir blink_formal_engine.c")
    ninja_lines.append("build blink_formal_engine.s: asm_gen blink_formal_engine.c")

    ninja_lines.append("\n# Rule & target for Pillars 2, 3 & 4 and Pillars 1 & 5 verification suites")
    ninja_lines.append("rule build_pillars_test")
    ninja_lines.append("  command = $CC -O3 -std=c99 -Wall -Wextra -pedantic $in -framework CoreText -framework CoreGraphics -framework CoreFoundation $$(pkg-config --cflags --libs freetype2) -lm -o $out")
    ninja_lines.append("  description = BUILD_PILLARS_TEST $out\n")
    ninja_lines.append("build test_blink_pillars_2_3_4: build_pillars_test test_blink_pillars_2_3_4.c blink_html_css_formal.c blink_layout_paint_formal.c blink_skia_font_engine.c | blink_html_css_formal.h blink_layout_paint_formal.h blink_skia_font_engine.h blink_dual_mode_z.h")
    ninja_lines.append("build test_blink_pillars_1_5: build_pillars_test test_blink_pillars_1_5.c blink_html_css_formal.c blink_layout_paint_formal.c blink_skia_font_engine.c | blink_html_css_formal.h blink_layout_paint_formal.h blink_skia_font_engine.h blink_dual_mode_z.h")

    ninja_lines.append("\n# Rule & target for standalone URL to PNG tool powered by Coq formal models")
    ninja_lines.append("rule build_url2png")
    ninja_lines.append("  command = $CC -O3 -std=c99 blink_url2png.c blink_html_css_formal.c blink_layout_paint_formal.c blink_skia_font_engine.c blink_image_codec.c blink_vertical_flow.c -framework CoreText -framework CoreGraphics -framework CoreFoundation $$(pkg-config --cflags --libs freetype2) -lcurl -lz -lm -o $out")
    ninja_lines.append("  description = BUILD_URL2PNG $out\n")
    ninja_lines.append("build blink_url2png: build_url2png blink_url2png.c blink_html_css_formal.c blink_layout_paint_formal.c blink_skia_font_engine.c blink_image_codec.c blink_vertical_flow.c | blink_html_css_formal.h blink_layout_paint_formal.h blink_skia_font_engine.h blink_image_codec.h blink_vertical_flow.h blink_dual_mode_z.h")

    ninja_lines.append("\nbuild engine_all: phony blink_formal_runner test_blink_html_css_formal test_blink_pillars_2_3_4 test_blink_pillars_1_5 blink_url2png blink_formal_engine_cpp.o libblink_formal.dylib blink_formal_engine.ll blink_formal_engine.s")

    # Execution targets
    ninja_lines.append("build .engine_tested: run_runner blink_formal_runner")
    ninja_lines.append("build .html_css_tested: run_runner test_blink_html_css_formal")
    ninja_lines.append("build .pillars_2_3_4_tested: run_runner test_blink_pillars_2_3_4")
    ninja_lines.append("build .pillars_1_5_tested: run_runner test_blink_pillars_1_5")
    ninja_lines.append("build test: phony .admits_verified .engine_tested .html_css_tested .pillars_2_3_4_tested .pillars_1_5_tested")
    ninja_lines.append("build all: phony coq_all .admits_verified engine_all .engine_tested .html_css_tested .pillars_2_3_4_tested .pillars_1_5_tested")
    ninja_lines.append("default all\n")

    with open("build.ninja", "w") as f:
        f.write("\n".join(ninja_lines) + "\n")

    print(f"{GREEN}✓ Successfully generated build.ninja with {len(vo_targets)} Coq theory targets and C/C++ engine targets.{RESET}")


def main():
    print_header("Blink Formalization System Dependency & Prerequisite Check")

    checker = DependencyChecker()

    print(f"\n{BOLD}1. Prover & Proof Assistant:{RESET}")
    checker.check_tool("Rocq/Coq", ["coqc", "rocq"], version_flag="--version", required=True)

    print(f"\n{BOLD}2. Build Engine:{RESET}")
    checker.check_tool("Ninja", ["ninja"], version_flag="--version", required=True)

    print(f"\n{BOLD}3. C99 & C++23 Compilers & Toolchains:{RESET}")
    checker.check_tool("Clang (C99)", ["clang", "gcc"], version_flag="--version", required=True)
    checker.check_tool("Clang++ (C++23)", ["clang++", "g++"], version_flag="--version", required=True)
    checker.check_tool("LLVM Disassembler", ["llvm-dis"], version_flag="--version", required=False)
    checker.check_tool("LLVM Optimizer", ["opt"], version_flag="--version", required=False)

    print(f"\n{BOLD}4. Python Runtime & Verified LLM Agent Packages:{RESET}")
    checker.check_tool("Python 3", ["python3"], version_flag="--version", required=True)
    checker.check_python_module("google.genai", import_name="google.genai", required=True)
    checker.check_python_module("PIL (Pillow)", import_name="PIL", required=False)
    checker.check_python_module("requests", import_name="requests", required=False)

    print(f"\n{BOLD}5. Web Ecosystem & Browser Engines:{RESET}")
    checker.check_tool("Node.js", ["node"], version_flag="--version", required=True)
    checker.check_browser()

    print(f"\n{BOLD}6. Version Control:{RESET}")
    checker.check_tool("Git", ["git"], version_flag="--version", required=True)
    checker.check_tool("GitHub CLI", ["gh"], version_flag="--version", required=False)

    print_header("Configuration Summary")
    if checker.all_required_met:
        print(f"{GREEN}{BOLD}All required packages, compilers, and tools are verified and ready!{RESET}")
        generate_ninja(checker)
        print(f"\nYou can now build the entire formalization pipeline using:")
        print(f"  {BOLD}ninja{RESET}               # Compile all Coq theories and drop-in engine")
        print(f"  {BOLD}ninja coq_all{RESET}       # Compile all 235+ formal Coq theories")
        print(f"  {BOLD}ninja test{RESET}          # Verify zero admits and run drop-in engine test")
        print(f"  {BOLD}ninja engine_all{RESET}    # Build C99, C++23, LLVM IR, assembly, and dylib")
        return 0
    else:
        print(f"{RED}{BOLD}Missing critical prerequisites! Please install the required tools above.{RESET}")
        return 1

if __name__ == "__main__":
    sys.exit(main())

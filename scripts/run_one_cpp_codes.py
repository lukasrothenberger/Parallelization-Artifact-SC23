#!/usr/bin/python3 -u

import os
from pathlib import Path
import sys
import shutil
from discopop_library.Compatibility.PerfoGraph.convert_dependencies import run as convert_dependency_file
from discopop_library.Compatibility.PerfoGraph.convert_dependencies import PerfoGraphCompatibilityArguments

cpp_path = ['codes/cpp/sssp-cpp/', 'codes/cpp/bfs-cpp/', 'codes/cpp/cc-cpp/', 'codes/cpp/mis-cpp/', 'codes/cpp/pr-cpp/', 'codes/cpp/tc-cpp/']
source = '0'
algorithms = ['sssp', 'bfs', 'cc', 'mis', 'pr', 'tc']
inputs_folder = 'inputs/'
out_dir = 'throughputs/'
cpp_out = 'throughputs/cpp/'
graph_names = ['internet.egr']
total_num_cpp = 176
counter = 0

if __name__ == "__main__":
    # read command line
    args_val = sys.argv
    if (len(args_val) < 2):
        sys.exit('USAGE: verify thread_count(optional)\n')
    verify = args_val[1]
    thread_count = args_val[2]

    # create output directory
    if os.path.exists(out_dir):
        os.system('rm -rf %s' % (out_dir))
    os.mkdir(out_dir)
    os.mkdir(cpp_out)          

    # create discopop output directory
    discopop_out_dir = 'discopop_output/'
    if os.path.exists(discopop_out_dir):
        os.system("rm -rf %s" % (discopop_out_dir))
    os.mkdir(discopop_out_dir)

    for graph in graph_names:
        counter = 0
        input_path = inputs_folder + graph

        # run cpp programs
        for i in range(len(cpp_path)):
            code_path = cpp_path[i] 
            walk_code = os.walk(code_path)

            out_name = cpp_out + algorithms[i] + '_' + graph + '_cpp.out'
            
            if os.path.isfile(out_name):
                os.remove(out_name)

            for root, dircs, code_files in walk_code:
                for code_file in code_files:
                    if code_file.endswith('.cpp'):
                        counter += 1
                        sys.stdout.flush()
                        print("running %s\n%d out of %d programs, %d out of %d inputs" % (code_file, counter, total_num_cpp, graph_names.index(graph) + 1, len(graph_names)))
                        sys.stdout.flush()
                        with open(out_name, 'a') as f:
                            file_path = os.path.join(code_path, code_file)
                            sys.stdout.flush()
                            f.write('\ncompile : %s\n' % code_file)
                            sys.stdout.flush()
                            print("CWD: " , os.getcwd())
                            print("file_path: ", file_path)
                            print("__file__: ", __file__)
                            include_dir = os.path.join(Path(__file__).parent.parent.absolute(), "include")
                            print("include dir: ", include_dir)

                            DISCOPOP = True
                            if not DISCOPOP:
                                os.system('g++ %s -O3 -pthread -I%s -o minibenchmark' % (file_path, include_dir))
                            else:
                                project_root_dir = Path(__file__).parent.parent.absolute()
                                print("EXECUTING: " + 'DP_PROJECT_ROOT_DIR=%s discopop_cxx %s -pthread -I%s -o minibenchmark' % (project_root_dir, file_path, include_dir))
                                os.system('DP_PROJECT_ROOT_DIR=%s discopop_cxx %s -S -emit-llvm -pthread -I%s -o minibenchmark.ll' % (project_root_dir, file_path, include_dir))
                                os.system("rm -rf .discopop")
                                os.system('DP_PROJECT_ROOT_DIR=%s discopop_cxx %s -pthread -I%s -o minibenchmark' % (project_root_dir, file_path, include_dir))
                            
                            print("thread_count: ", thread_count)
                            thread_count = 1
                            print("--> Set to 1 for compatibility with DiscoPoP")


                            # execute the instrumented program
                            if 'sssp' in code_path or 'bfs' in code_path:
                                print('Executing: ./minibenchmark %s %s %s %s >> %s' % (input_path, source, verify, thread_count, out_name))
                                os.system('./minibenchmark %s %s %s %s >> %s' % (input_path, source, verify, thread_count, out_name))
                            elif 'pr' in code_path:
                                os.system('./minibenchmark %s %s >> %s' % (input_path, thread_count, out_name))
                            else:
                                os.system('./minibenchmark %s %s %s >> %s' % (input_path, verify, thread_count, out_name))
                            sys.stdout.flush()

                            # DiscoPoP output organization
                            #  - create folder for the current code
                            output_folder = os.path.join(discopop_out_dir, code_file)
                            os.mkdir(output_folder)
                            #  - move the relevant files to the created folder
                            shutil.move(os.path.join(".discopop", "profiler", "static_dependencies.txt"), output_folder)
                            shutil.move(os.path.join(".discopop", "profiler", "dynamic_dependencies.txt"), output_folder)
                            shutil.move(os.path.join(".discopop", "FileMapping.txt"), output_folder)
                            shutil.move("minibenchmark.ll", output_folder)
                            #  - prepare the identified static and dynamic dependencies for use in PerfoGraph
                            convert_dependency_file(
                                    PerfoGraphCompatibilityArguments(llvm_ir_file=os.path.join(output_folder, "minibenchmark.ll"),
                                                                    dynamic_deps_file=os.path.join(output_folder, "dynamic_dependencies.txt"),
                                                                    output_file=os.path.join(output_folder, "converted_dynamic_dependencies.txt"),
                                                                    force_output=False,
                                                                    log_level="INFO",
                                                                    write_log=False))
                            convert_dependency_file(
                                    PerfoGraphCompatibilityArguments(llvm_ir_file=os.path.join(output_folder, "minibenchmark.ll"),
                                                                    dynamic_deps_file=os.path.join(output_folder, "static_dependencies.txt"),
                                                                    output_file=os.path.join(output_folder, "converted_static_dependencies.txt"),
                                                                    force_output=False,
                                                                    log_level="INFO",
                                                                    write_log=False))
                            # DiscoPoP environment reset
                            #  - delete the created .discopop directory
                            shutil.rmtree(".discopop")
                            sys.exit(0)

                            # cleanup
                            if os.path.isfile('minibenchmark'):
                                os.system('rm minibenchmark')
                            else:
                                sys.exit('Error: compile failed')
                    else:
                        sys.exit('No C++ threads codes in the directory.')

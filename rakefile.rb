require('fileutils')

here_dir = File.dirname(__FILE__)

task :default do
    sh 'rake -T'
end

desc 'Run'
task :run, %i[extra mode] do |task, args|
    mode = args[:mode]&.to_sym || :release
    sh("xmake f -m #{mode}")
    sh("xmake build -v ampp")

    exe = {release: "#{here_dir}/build/linux/x86_64/release/ampp", debug: "#{here_dir}/build/linux/x86_64/release/ampp"}[mode]
    sh("#{exe} #{args[:extra]}")
end

desc 'Run all UTs'
task :ut, %i[filter] do |task, args|
    sh "zig build test"

    mode = :release
    # mode = :debug
    # sh("xmake f -c") # This was needed once to make xmake detect the local toolchains
    sh("xmake f -m #{mode}")
    sh("xmake build -v amplib_ut")
    sh("xmake run amplib_ut")
end

desc("Clean")
task :clean do
    sh("xmake clean")
end

desc("Generate .clangd file")
task :clangd do
    File.open('.clangd', 'w') do |fo|
        fo.puts("CompileFlags:")
        # &shortcut: How can I get the include path for catch2 from xmake?
        include_dirs = %w[src ext/rubr/src /home/geertf/.xmake/packages/c/catch2/v3.8.0/39d7db50b8e54e09ac555b3ca94b3a17/include].map{|dir|"-I#{dir[0] == '/' ? dir : File.join(here_dir, dir)}"}
        fo.puts("    Add: [-std=c++23, #{include_dirs*', '}]")
    end
end

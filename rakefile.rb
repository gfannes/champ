require('fileutils')

here_dir = File.dirname(__FILE__)

task :default do
    sh 'rake -T'
end

desc 'Run'
task :run do
    sh("xmake build -v ampp")

    ix = (ARGV.index('--') || -1) +1
    args = ARGV[ix...]
    sh("xmake run ampp #{args*' '}")
end

desc("Clean")
task :clean do
    sh("xmake clean")
end

desc("Generate .clangd file")
task :clangd do
    File.open('.clangd', 'w') do |fo|
        fo.puts("CompileFlags:")
        include_dirs = %w[src ext/rubr/src].map{|dir|"-I#{File.join(here_dir, dir)}"}
        fo.puts("    Add: [-std=c++20, #{include_dirs*', '}]")
    end
end

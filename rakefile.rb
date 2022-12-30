task :default do
    sh 'rake -T'
end

task :prepare do
    gubg = ENV['gubg']
    raise("Env var 'gubg' not set") unless gubg

    sh "ln -s #{gubg} gubg" unless File.exist?('gubg')

    require_relative('gubg/gubg.build/load.rb')
    require('gubg/build/Cooker')
    require('fileutils')
end

desc 'Build the targets'
task :build => :prepare do
    sh "cargo build"

    cooker = Gubg::Build::Cooker.new()
    cooker.option("c++.std", 20)
    cooker.generate(:ninja, 'champetter/cli').ninja()

    options = %w[--pkg-begin gubg/tui gubg/gubg.io/src/gubg/tui.zig --pkg-end -lc]
    sh "zig build-exe #{options*' '} src/cli/main.zig"
end

desc 'Clean the build'
task :clean => :prepare do
    FileUtils.rm_rf('.cook')
    FileUtils.rm_f(%w[build.ninja champetter.cli champetter.ut .ninja_log])
    FileUtils.rm(FileList.new("*.resp"))
end

desc 'Install the CLI application'
task :install => :build do
    sh 'sudo cp champetter.cli /usr/local/bin/champ'
end

desc 'Run the unit tests'
task :ut => :prepare do
    cooker = Gubg::Build::Cooker.new()
    cooker.generate(:ninja, 'champetter/ut').ninja()
    sh './champetter.ut'
end

desc 'Run the e2e tests'
task :e2e => :build do
end

desc 'Run the app'
task :run => :build do
    sh "./target/debug/champ"
end

desc 'Generate clangd file'
task :clangd => :prepare do
    include_paths = []
    include_paths += %w[src]
    include_paths += %w[std io].map{|name|"gubg/gubg.#{name}/src"}
    include_paths.map!{|ip|File.realdirpath(ip)}
    File.open('.clangd', 'w') do |fo|
        fo.puts('CompileFlags:')
        fo.puts("    Add: [-std=c++20, #{include_paths.map{|ip|"-I#{ip}"}*', '}]")
    end
    cooker = Gubg::Build::Cooker.new()
    cooker.option("c++.std", 20)
    cooker.generate(:ninja).ninja_compdb()
end

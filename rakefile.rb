require('fileutils')
require('pathname')


my = Class.new() do
    attr :test_dir
    def initialize()
        @test_dir = Pathname.new(__FILE__).parent()/'test'
        @test_dir.mkpath()
    end

    def product(*terms)
        if terms.size() == 1
            terms[0].map{|e|[e]}
        else
            p = product(*terms[0..terms.size-2])
            pp = []
            terms[terms.size-1].each do |e|
                p.each do |ary|
                    pp << ary+[e]
                end
            end
            pp
        end
    end
end.new()

task :default do
    sh 'rake -T'
end

DEFAULT_LANGUAGE = :rust
language = ->(task_args){task_args[:language] || DEFAULT_LANGUAGE}

exe_name = nil

{
    prepare: {desc: 'Prepare for building', default: ->(_){}},
    build: {desc: 'Build the CLI application'},
    run: {desc: 'Run the CLI application',
        default: ->(task_args) do
            task_name = "#{language.(task_args)}:build"
            Rake::Task[task_name].invoke()
            sh "./#{exe_name}"
        end
    },
    install: {desc: 'Install the CLI application',
        default: ->(task_args) do
            task_name = "#{language.(task_args)}:build"
            Rake::Task[task_name].invoke()
            sh "sudo cp #{exe_name} /usr/local/bin/champ"
        end
    },
    clean: {desc: 'Clean the build'},
    test: {desc: 'Run the tests'},
}.each do |name, info|
    desc(info[:desc])
    task(name, :language) do |t, args|
        task_name = "#{language.(args)}:#{name}"
        if Rake::Task.task_defined?(task_name)
            Rake::Task[task_name].invoke()
        elsif info[:default]
            info[:default].(args)
        else raise("No task found for #{task_name}")
        end
    end
end

namespace :rust do
    task :build => :prepare do
        mode = :release
        # mode = :debug
        sh "cargo build --#{mode}"
        exe_name = "target/#{mode}/champ"
    end

    task :install do
        sh 'cargo install --path .'
    end

    task :clean => :prepare do
        FileUtils.rm_rf('target')
    end

    task :test => %i[prepare install] do
        sh 'cargo test -- --nocapture --test-threads 1'
        sh 'ch -h'
        sh 'ch list -h'
        sh 'ch list'
    end
end

namespace :cpp do
    task :prepare do
        gubg = ENV['gubg']
        raise("Env var 'gubg' not set") unless gubg

        sh "ln -s #{gubg} gubg" unless File.exist?('gubg')

        require_relative('gubg/gubg.build/load.rb')
        require('gubg/build/Cooker')
    end

    task :build => :prepare do
        cooker = Gubg::Build::Cooker.new()
        cooker.option("c++.std", 20)
        cooker.generate(:ninja, 'champetter/cli').ninja()
        exe_name = 'champetter.cli'
    end

    task :clean => :prepare do
        FileUtils.rm_rf('.cook')
        FileUtils.rm_f(%w[build.ninja champetter.cli champetter.ut .ninja_log])
        FileUtils.rm(FileList.new("*.resp"))
    end

    task :ut => :prepare do
        cooker = Gubg::Build::Cooker.new()
        cooker.generate(:ninja, 'champetter/ut').ninja()
        sh './champetter.ut'
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
end

namespace :zig do
    task :build => :prepare do
        options = %w[--pkg-begin gubg/tui gubg/gubg.io/src/gubg/tui.zig --pkg-end -lc]
        sh "zig build-exe #{options*' '} src/cli/main.zig"
        exe_name = 'main'
    end

    task :clean => :prepare do
    end

    task :ut => :prepare do
    end
end

namespace :test do
    desc "Create test tree in '#{my.test_dir}'"
    task :create_tree do
        paths = []
        levels = %w[a b c d e]
        # levels = %w[a b]
        levels.size().times do |ix0|
            terms = []
            (ix0+1).times do |i|
                terms << (0...8).map{|j|"#{levels[i]}#{j}"}
            end
            paths += my.product(*terms)
        end
        paths.map! do |path|
            path = path*'/'
            path = my.test_dir/path
            path.sub_ext('.ext')
            # Pathname.new(path*'/').sub_ext('.ext')
        end
        paths.each do |path|
            path.parent().mkpath()
            path.open('w') do |fo|
                fo.puts("#{path}")
            end
        end
    end
end
